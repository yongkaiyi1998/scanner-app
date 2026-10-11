import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider/path_provider.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';

class SystemPhotoImporter implements PhotoImporter {
  SystemPhotoImporter({
    ImagePicker? picker,
    Future<Directory> Function()? temporaryDirectory,
    Future<LostDataResponse> Function()? retrieveLostData,
  }) : _picker = picker ?? ImagePicker(),
       _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory {
    final platform = ImagePickerPlatform.instance;
    if (platform is ImagePickerAndroid) platform.useAndroidPhotoPicker = true;
    _retrieveLostData =
        retrieveLostData ??
        () async => Platform.isAndroid
            ? await _picker.retrieveLostData()
            : LostDataResponse.empty();
  }

  static const maxBytes = 40 * 1024 * 1024;
  static const maxPixels = 64000000;
  static const previewEdge = 1024;
  final ImagePicker _picker;
  final Future<Directory> Function() _temporaryDirectory;
  final Map<String, Directory> _owned = {};
  static final Set<String> _activeSessions = {};
  final Map<String, RandomAccessFile> _leases = {};
  String? _basePath;
  static const _markerName = '.capture-owner';

  File _marker(Directory session) =>
      File('${session.path}${Platform.pathSeparator}$_markerName');
  String _ownership(Directory session) =>
      'scanner-capture-v1:${session.uri.pathSegments.where((s) => s.isNotEmpty).last}';

  Future<String> _readOwnership(Directory session) async {
    final lease = _leases[session.path];
    if (lease == null) return _marker(session).readAsString();
    await lease.setPosition(0);
    return utf8.decode(await lease.read(257));
  }

  Future<void> _checkRoot(Directory root) async {
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await root.resolveSymbolicLinks() != root.path ||
        await root.parent.resolveSymbolicLinks() != _basePath) {
      throw const FileSystemException('Unsafe capture storage');
    }
  }

  Future<void> _deleteSession(Directory root, Directory session) async {
    await _checkRoot(root);
    final type = await FileSystemEntity.type(session.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory ||
        session.parent.path != root.path ||
        await session.resolveSymbolicLinks() != session.path) {
      throw const FileSystemException('Unsafe capture session');
    }
    final marker = _marker(session);
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
            FileSystemEntityType.file ||
        await marker.length() > 256 ||
        await _readOwnership(session) != _ownership(session)) {
      throw const FileSystemException('Unowned capture session');
    }
    // Never recursively remove unexpected files, subdirectories, or links.
    final entries = await session.list(followLinks: false).toList();
    for (final entry in entries) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (entry is! File || (name != 'source.image' && name != _markerName)) {
        throw const FileSystemException('Unexpected capture contents');
      }
    }
    await _leases.remove(session.path)?.close();
    for (final entry in entries) {
      if (entry.path != marker.path) await entry.delete();
    }
    await marker.delete();
    await session.delete();
    _activeSessions.remove(session.path);
  }

  late final Future<LostDataResponse> Function() _retrieveLostData;
  Future<Directory>? _workingDirectory;
  Future<DocumentPage?>? _recovery;

  Future<Directory> _prepare() => _workingDirectory ??= _prepareDirectory();
  Future<Directory> _prepareDirectory() async {
    try {
      final base = await _temporaryDirectory();
      _basePath = await base.resolveSymbolicLinks();
      final root = Directory(
        '$_basePath${Platform.pathSeparator}capture_working',
      );
      if (await FileSystemEntity.type(root.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        await root.create();
      }
      await _checkRoot(root);
      await for (final entity in root.list(followLinks: false)) {
        if (entity is Directory && !_activeSessions.contains(entity.path)) {
          final marker = _marker(entity);
          if (await FileSystemEntity.type(marker.path, followLinks: false) !=
                  FileSystemEntityType.file ||
              await marker.length() > 256 ||
              await marker.readAsString() != _ownership(entity)) {
            continue;
          }
          final lease = await marker.open(mode: FileMode.append);
          try {
            await lease.lock(FileLock.exclusive);
          } on FileSystemException {
            await lease.close();
            continue; // Another process still owns this session.
          }
          _leases[entity.path] = lease;
          try {
            await _deleteSession(root, entity);
          } finally {
            await _leases.remove(entity.path)?.close();
          }
        }
      }
      return root;
    } on Exception {
      _workingDirectory = null;
      throw const PhotoImportException(ImportFailure.storage);
    }
  }

  @override
  Future<DocumentPage?> recoverLostPhoto() => _recovery ??= _recover();
  Future<DocumentPage?> _recover() async {
    await _prepare();
    try {
      final response = await _retrieveLostData();
      if (response.exception != null) throw response.exception!;
      final files = response.files;
      if (files == null || files.isEmpty) return null;
      return await _copyAndValidate(files.first);
    } on PlatformException catch (error) {
      throw _platformFailure(error);
    } on PhotoImportException {
      rethrow;
    } on Exception {
      throw const PhotoImportException(ImportFailure.unavailable);
    }
  }

  @override
  Future<DocumentPage?> importPhoto() async {
    await _prepare();
    try {
      final selection = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      return selection == null ? null : await _copyAndValidate(selection);
    } on PlatformException catch (error) {
      throw _platformFailure(error);
    } on MissingPluginException {
      throw const PhotoImportException(ImportFailure.unavailable);
    } on PhotoImportException {
      rethrow;
    } on Exception {
      throw const PhotoImportException(ImportFailure.unreadable);
    }
  }

  PhotoImportException _platformFailure(PlatformException error) =>
      PhotoImportException(
        error.code.contains('denied') || error.code.contains('permission')
            ? ImportFailure.permission
            : ImportFailure.unavailable,
      );

  Future<DocumentPage> _copyAndValidate(
    XFile selection, {
    PageSource source = PageSource.gallery,
    int sortOrder = 0,
  }) async {
    final int length;
    try {
      length = await selection.length();
    } on Exception {
      throw const PhotoImportException(ImportFailure.unreadable);
    }
    if (length == 0) {
      throw const PhotoImportException(ImportFailure.invalidImage);
    }
    if (length > maxBytes) {
      throw const PhotoImportException(ImportFailure.tooLarge);
    }
    final root = await _prepare();
    final Directory session;
    try {
      await _checkRoot(root);
      session = await root.createTemp('import_');
    } on Exception {
      throw const PhotoImportException(ImportFailure.storage);
    }
    final file = File('${session.path}${Platform.pathSeparator}source.image');
    try {
      _activeSessions.add(session.path);
      try {
        await _marker(session).writeAsString(_ownership(session), flush: true);
        final lease = await _marker(session).open(mode: FileMode.append);
        _leases[session.path] = lease;
        await lease.lock(FileLock.exclusive);
      } on FileSystemException {
        throw const PhotoImportException(ImportFailure.storage);
      }
      final RandomAccessFile output;
      try {
        output = await file.open(mode: FileMode.write);
      } on Exception {
        throw const PhotoImportException(ImportFailure.storage);
      }
      var copied = 0;
      try {
        await for (final chunk in selection.openRead()) {
          copied += chunk.length;
          if (copied > maxBytes) {
            throw const PhotoImportException(ImportFailure.tooLarge);
          }
          try {
            await output.writeFrom(chunk);
          } on Exception {
            throw const PhotoImportException(ImportFailure.storage);
          }
        }
      } on PhotoImportException {
        rethrow;
      } on Exception {
        throw const PhotoImportException(ImportFailure.unreadable);
      } finally {
        try {
          await output.close();
        } on FileSystemException {
          throw const PhotoImportException(ImportFailure.storage);
        }
      }
      if (copied == 0 || copied != length) {
        throw const PhotoImportException(ImportFailure.unreadable);
      }
      final photo = await _validate(file, session, copied, source, sortOrder);
      _owned[photo.id] = session;
      return photo;
    } catch (_) {
      try {
        await _deleteSession(root, session);
      } on FileSystemException {
        // A later startup retries cleanup of this owned session directory.
        await _leases.remove(session.path)?.close();
        _activeSessions.remove(session.path);
      }
      rethrow;
    }
  }

  @override
  Future<DocumentPage> copyPhoto(
    XFile input, {
    PageSource source = PageSource.gallery,
    int sortOrder = 0,
  }) => _copyAndValidate(input, source: source, sortOrder: sortOrder);

  Future<DocumentPage> _validate(
    File file,
    Directory session,
    int byteLength,
    PageSource source,
    int sortOrder,
  ) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width * descriptor.height > maxPixels) {
        throw const PhotoImportException(ImportFailure.tooLarge);
      }
      final scale = math.min(
        1.0,
        previewEdge / math.max(descriptor.width, descriptor.height),
      );
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
      image = (await codec.getNextFrame()).image;
      final sessionId = session.uri.pathSegments
          .where((s) => s.isNotEmpty)
          .last;
      return DocumentPage(
        id: sessionId,
        path: file.path,
        width: descriptor.width,
        height: descriptor.height,
        byteLength: byteLength,
        source: source,
        sortOrder: sortOrder,
        ownership: PageFileOwnership(sessionId: sessionId),
      );
    } on PhotoImportException {
      rethrow;
    } catch (_) {
      throw const PhotoImportException(ImportFailure.invalidImage);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  @override
  Future<void> discard(DocumentPage photo) async {
    final session = _owned[photo.id];
    if (session == null ||
        photo.ownership?.sessionId != photo.id ||
        photo.ownership?.lifetime != PageFileLifetime.previewTemporary ||
        photo.sourcePath != photo.workingPath ||
        photo.workingPath !=
            '${session.path}${Platform.pathSeparator}source.image') {
      return;
    }
    try {
      await _deleteSession(await _prepare(), session);
      await _leases.remove(session.path)?.close();
      _activeSessions.remove(session.path);
      _owned.remove(photo.id);
    } on FileSystemException {
      throw const PhotoImportException(ImportFailure.storage);
    }
  }
}

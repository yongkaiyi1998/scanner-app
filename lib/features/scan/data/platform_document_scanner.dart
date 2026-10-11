import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/scan/document_scanner.dart';

class PlatformDocumentScanner implements DocumentScanner {
  PlatformDocumentScanner({
    required this.importer,
    MethodChannel? channel,
    bool? isAndroid,
  }) : channel = channel ?? const MethodChannel('scanner_app/document_scanner'),
       isAndroid = isAndroid ?? Platform.isAndroid;
  final PhotoImporter importer;
  final MethodChannel channel;
  final bool isAndroid;
  final List<ImportedPhoto> _pendingCleanup = [];

  Future<void> _cleanup() async {
    while (_pendingCleanup.isNotEmpty) {
      await importer.discard(_pendingCleanup.first);
      _pendingCleanup.removeAt(0);
    }
  }

  @override
  Future<List<ImportedPhoto>?> scan() async {
    if (!isAndroid) throw const ScanException(ScanFailure.unsupported);
    await _cleanup();
    List<String> tokens = [];
    final copied = <ImportedPhoto>[];
    try {
      final raw = await channel.invokeMethod<Object?>('scan');
      if (raw == null) return null;
      if (raw is! List ||
          raw.isEmpty ||
          raw.any(
            (item) =>
                item is! String || !RegExp(r'^[0-9a-f-]{36}$').hasMatch(item),
          )) {
        throw const ScanException(ScanFailure.invalidResult);
      }
      tokens = raw.cast<String>();
      if (tokens.toSet().length != tokens.length) {
        throw const ScanException(ScanFailure.invalidResult);
      }
      for (final token in tokens) {
        copied.add(await importer.copyPhoto(_ScannerInput(channel, token)));
      }
      return List.unmodifiable(copied);
    } on PlatformException catch (error) {
      throw ScanException(switch (error.code) {
        'unsupported' => ScanFailure.unsupported,
        'unavailable' => ScanFailure.unavailable,
        'initialization' => ScanFailure.initialization,
        'invalid_result' => ScanFailure.invalidResult,
        'interrupted' => ScanFailure.interrupted,
        _ => ScanFailure.unexpected,
      });
    } on MissingPluginException {
      throw const ScanException(ScanFailure.unavailable);
    } on PhotoImportException {
      rethrow;
    } on ScanException {
      rethrow;
    } catch (_) {
      throw const ScanException(ScanFailure.unexpected);
    } finally {
      // Until the complete batch is ready, keep rollback ownership retryable.
      if (copied.length != tokens.length) {
        _pendingCleanup.addAll(copied);
        try {
          await _cleanup();
        } on PhotoImportException {
          /* Retry before the next scan. */
        }
      }
      try {
        await channel.invokeMethod<void>('releasePages');
      } on Exception {
        /* Native resources also close when the activity is destroyed. */
      }
    }
  }
}

class _ScannerInput extends XFile {
  _ScannerInput(this.channel, this.token) : super('scanner-input');
  final MethodChannel channel;
  final String token;
  @override
  Future<int> length() async {
    final length = await channel.invokeMethod<int>('pageLength', token);
    if (length == null || length <= 0) {
      throw const PhotoImportException(ImportFailure.unreadable);
    }
    return length;
  }

  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    if (start != null || end != null) {
      throw const PhotoImportException(ImportFailure.unreadable);
    }
    while (true) {
      final bytes = await channel.invokeMethod<Uint8List>('readPage', token);
      if (bytes == null) {
        throw const PhotoImportException(ImportFailure.unreadable);
      }
      if (bytes.isEmpty) break;
      yield bytes;
    }
  }
}

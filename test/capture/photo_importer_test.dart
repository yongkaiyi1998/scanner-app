import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scanner_app/features/capture/data/system_photo_importer.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';

class FakePicker extends ImagePicker {
  XFile? selection;
  Exception? failure;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, ImageSource.gallery);
    expect(requestFullMetadata, isFalse);
    if (failure != null) throw failure!;
    return selection;
  }
}

class GrowingSelection extends XFile {
  GrowingSelection() : super('unused');
  @override
  Future<int> length() async => 1;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    yield Uint8List(SystemPhotoImporter.maxBytes + 1);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late FakePicker picker;
  late SystemPhotoImporter importer;
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  Matcher failsWith(ImportFailure failure) => throwsA(
    isA<PhotoImportException>().having(
      (error) => error.failure,
      'failure',
      failure,
    ),
  );

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('capture_test_');
    picker = FakePicker();
    importer = SystemPhotoImporter(
      picker: picker,
      temporaryDirectory: () async => sandbox,
    );
  });
  tearDown(() async => sandbox.delete(recursive: true));

  test(
    'copies decodable content with generated names and preserves the original',
    () async {
      final source = File('${sandbox.path}/external.png');
      await source.writeAsBytes(png);
      picker.selection = XFile(source.path, name: '../../outside.png');
      final photo = (await importer.importPhoto())!;
      expect(
        photo.path,
        startsWith('${sandbox.path}${Platform.pathSeparator}capture_working'),
      );
      expect(photo.path, endsWith('source.image'));
      expect(photo.width, 1);
      expect(photo.id, startsWith('import_'));
      expect(photo.source, PageSource.gallery);
      expect(photo.sortOrder, 0);
      expect(photo.sourcePath, photo.workingPath);
      expect(photo.byteLength, png.length);
      expect(photo.ownership!.sessionId, photo.id);
      expect(photo.ownership!.lifetime, PageFileLifetime.previewTemporary);
      expect(await File(photo.path).readAsBytes(), png);
      await source.delete();
      expect(await File(photo.path).readAsBytes(), png);
      await importer.discard(photo);
      expect(await File(photo.path).exists(), isFalse);
    },
  );

  test('cancel returns no photo or working session', () async {
    expect(await importer.importPhoto(), isNull);
    expect(
      await Directory('${sandbox.path}/capture_working').list().toList(),
      isEmpty,
    );
  });

  test(
    'storage initialization can be retried after a transient failure',
    () async {
      var attempts = 0;
      final retrying = SystemPhotoImporter(
        picker: picker,
        temporaryDirectory: () async {
          if (attempts++ == 0) {
            throw const FileSystemException('temporarily unavailable');
          }
          return sandbox;
        },
      );
      await expectLater(
        retrying.importPhoto(),
        failsWith(ImportFailure.storage),
      );
      expect(await retrying.importPhoto(), isNull);
      expect(attempts, 2);
    },
  );

  test('discard tolerates an already removed private cache session', () async {
    if (Platform.isWindows) {
      markTestSkipped('Windows prevents deleting an open session lease');
      return;
    }
    final source = File('${sandbox.path}/external.png');
    await source.writeAsBytes(png);
    picker.selection = XFile(source.path);
    final photo = (await importer.importPhoto())!;
    await File(photo.path).parent.delete(recursive: true);
    await importer.discard(photo);
    expect(await source.exists(), isTrue);
  });

  test(
    'lost-data errors are mapped safely and allow a new selection',
    () async {
      final recovering = SystemPhotoImporter(
        picker: picker,
        temporaryDirectory: () async => sandbox,
        retrieveLostData: () async => LostDataResponse(
          exception: PlatformException(
            code: 'photo_access_denied',
            message: 'private details',
          ),
        ),
      );
      await expectLater(
        recovering.recoverLostPhoto(),
        failsWith(ImportFailure.permission),
      );
      expect(await recovering.importPhoto(), isNull);
    },
  );

  test(
    'rejects a text file disguised as PNG and cleans partial working files',
    () async {
      final source = File('${sandbox.path}/invalid.png');
      await source.writeAsString('not an image');
      picker.selection = XFile(source.path);
      await expectLater(
        importer.importPhoto(),
        failsWith(ImportFailure.invalidImage),
      );
      expect(
        await Directory('${sandbox.path}/capture_working').list().toList(),
        isEmpty,
      );
      expect(await source.exists(), isTrue);
    },
  );

  test('missing or revoked input becomes a readable error', () async {
    picker.selection = XFile('${sandbox.path}/missing.png');
    await expectLater(
      importer.importPhoto(),
      failsWith(ImportFailure.unreadable),
    );
  });

  test('rejects empty input', () async {
    final source = File('${sandbox.path}/empty.png');
    await source.create();
    picker.selection = XFile(source.path);
    await expectLater(
      importer.importPhoto(),
      failsWith(ImportFailure.invalidImage),
    );
  });

  test(
    'checks actual streamed size even if declared length is false',
    () async {
      picker.selection = GrowingSelection();
      await expectLater(
        importer.importPhoto(),
        failsWith(ImportFailure.tooLarge),
      );
      expect(
        await Directory('${sandbox.path}/capture_working').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'maps picker denial and unavailability without exposing details',
    () async {
      picker.failure = PlatformException(
        code: 'photo_access_denied',
        message: 'private source details',
      );
      await expectLater(
        importer.importPhoto(),
        failsWith(ImportFailure.permission),
      );
      picker.failure = MissingPluginException();
      await expectLater(
        importer.importPhoto(),
        failsWith(ImportFailure.unavailable),
      );
    },
  );

  test('storage failure is recoverable and leaves source untouched', () async {
    final source = File('${sandbox.path}/external.png');
    await source.writeAsBytes(png);
    picker.selection = XFile(source.path);
    final broken = SystemPhotoImporter(
      picker: picker,
      temporaryDirectory: () async =>
          throw const FileSystemException('unavailable'),
    );
    await expectLater(broken.importPhoto(), failsWith(ImportFailure.storage));
    expect(await source.readAsBytes(), png);
  });

  test(
    'recovered picker result is copied and recovery is read only once',
    () async {
      final source = File('${sandbox.path}/recovered.png');
      await source.writeAsBytes(png);
      var recoveryCalls = 0;
      final recovery = SystemPhotoImporter(
        picker: picker,
        temporaryDirectory: () async => sandbox,
        retrieveLostData: () async {
          recoveryCalls++;
          return LostDataResponse(
            files: [XFile(source.path)],
            type: RetrieveType.image,
          );
        },
      );
      final photo = (await recovery.recoverLostPhoto())!;
      expect(await File(photo.path).readAsBytes(), png);
      expect(await recovery.recoverLostPhoto(), same(photo));
      expect(recoveryCalls, 1);
      await recovery.discard(photo);
    },
  );

  test(
    'startup removes abandoned sessions but preserves unrelated files',
    () async {
      final root = Directory('${sandbox.path}/capture_working');
      final abandoned = await Directory(
        '${root.path}/import_old',
      ).create(recursive: true);
      final unrelated = File('${root.path}/keep.txt');
      await unrelated.writeAsString('keep');
      await File(
        '${abandoned.path}/.capture-owner',
      ).writeAsString('scanner-capture-v1:import_old');
      await importer.recoverLostPhoto();
      expect(await abandoned.exists(), isFalse);
      expect(await unrelated.exists(), isTrue);
      final external = File('${sandbox.path}/do_not_delete.png');
      await external.writeAsBytes(png);
      await importer.discard(
        DocumentPage(
          id: external.path,
          path: external.path,
          width: 1,
          height: 1,
        ),
      );
      expect(await external.exists(), isTrue);
    },
  );
  test(
    'unmarked import directories and active sessions survive startup',
    () async {
      final source = File('${sandbox.path}/external.png');
      await source.writeAsBytes(png);
      picker.selection = XFile(source.path);
      final photo = (await importer.importPhoto())!;
      final unrelated = await Directory(
        '${sandbox.path}/capture_working/import_unrelated',
      ).create();
      final second = SystemPhotoImporter(
        picker: FakePicker(),
        temporaryDirectory: () async => sandbox,
      );
      await second.importPhoto();
      expect(await File(photo.path).exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
      await importer.discard(photo);
      expect(await source.exists(), isTrue);
    },
  );

  test('unexpected session contents block deletion and allow retry', () async {
    final source = File('${sandbox.path}/external.png');
    await source.writeAsBytes(png);
    picker.selection = XFile(source.path);
    final photo = (await importer.importPhoto())!;
    final unrelated = File('${File(photo.path).parent.path}/keep.txt');
    await unrelated.writeAsString('keep');
    await expectLater(
      importer.discard(photo),
      failsWith(ImportFailure.storage),
    );
    expect(await unrelated.exists(), isTrue);
    expect(await source.exists(), isTrue);
    await unrelated.delete();
    await importer.discard(photo);
    expect(await File(photo.path).exists(), isFalse);
  });

  test('linked working root is refused before cleanup', () async {
    final outside = await Directory('${sandbox.path}/outside').create();
    final sentinel = File('${outside.path}/keep.txt');
    await sentinel.writeAsString('keep');
    final link = Link('${sandbox.path}/capture_working');
    try {
      await link.create(outside.path);
    } on FileSystemException {
      markTestSkipped('Creating symlinks is not permitted on this host');
      return;
    }
    await expectLater(importer.importPhoto(), failsWith(ImportFailure.storage));
    expect(await sentinel.exists(), isTrue);
    await link.delete();
  });

  test('invalid ownership markers never authorize startup deletion', () async {
    final session = await Directory(
      '${sandbox.path}/capture_working/import_other',
    ).create(recursive: true);
    final sentinel = File('${session.path}/source.image');
    await sentinel.writeAsBytes(png);
    await File(
      '${session.path}/.capture-owner',
    ).writeAsString('scanner-capture-v1:import_different');
    await importer.importPhoto();
    expect(await sentinel.readAsBytes(), png);
  });

  test('a non-directory working root is refused without deleting it', () async {
    final root = File('${sandbox.path}/capture_working');
    await root.writeAsString('keep');
    await expectLater(importer.importPhoto(), failsWith(ImportFailure.storage));
    expect(await root.readAsString(), 'keep');
  });

  test('linked child sessions are not followed during startup', () async {
    final outside = await Directory('${sandbox.path}/outside').create();
    final sentinel = File('${outside.path}/source.image');
    await sentinel.writeAsBytes(png);
    await File(
      '${outside.path}/.capture-owner',
    ).writeAsString('scanner-capture-v1:import_link');
    final root = await Directory('${sandbox.path}/capture_working').create();
    final link = Link('${root.path}/import_link');
    try {
      await link.create(outside.path);
    } on FileSystemException {
      markTestSkipped('Creating symlinks is not permitted on this host');
      return;
    }
    await importer.importPhoto();
    expect(await sentinel.readAsBytes(), png);
    await link.delete();
  });

  test(
    'root substituted after import blocks discard and remains retryable',
    () async {
      if (Platform.isWindows) {
        markTestSkipped('Windows prevents renaming an open session lease');
        return;
      }
      final source = File('${sandbox.path}/external.png');
      await source.writeAsBytes(png);
      picker.selection = XFile(source.path);
      final photo = (await importer.importPhoto())!;
      final root = Directory('${sandbox.path}/capture_working');
      final moved = await root.rename('${sandbox.path}/moved');
      final link = Link(root.path);
      try {
        await link.create(moved.path);
      } on FileSystemException {
        await moved.rename(root.path);
        await importer.discard(photo);
        markTestSkipped('Creating symlinks is not permitted on this host');
        return;
      }
      await expectLater(
        importer.discard(photo),
        failsWith(ImportFailure.storage),
      );
      expect(await source.exists(), isTrue);
      await link.delete();
      await moved.rename(root.path);
      await importer.discard(photo);
    },
  );
}

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import '../capture/fake_photo_importer.dart';
import 'package:scanner_app/features/capture/data/system_photo_importer.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/scan/data/platform_document_scanner.dart';
import 'package:scanner_app/features/scan/document_scanner.dart';

class RollbackImporter extends FakePhotoImporter {
  int copies = 0;
  @override
  Future<DocumentPage> copyPhoto(
    XFile input, {
    PageSource source = PageSource.gallery,
    int sortOrder = 0,
  }) async {
    if (++copies == 2) {
      throw const PhotoImportException(ImportFailure.invalidImage);
    }
    return super.copyPhoto(input, source: source, sortOrder: sortOrder);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('scanner_app/test_scanner');
  const first = '11111111-1111-1111-1111-111111111111';
  const second = '22222222-2222-2222-2222-222222222222';
  late Directory sandbox;
  late SystemPhotoImporter importer;
  late PlatformDocumentScanner scanner;
  late Uint8List image;
  Object? result;
  String? failure;
  String? unreadable;
  String? invalid;
  int releases = 0;
  final reads = <String>{};
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final frame = await picture.toImage(1, 1);
    image = (await frame.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    frame.dispose();
    picture.dispose();
  });
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('scan_test_');
    importer = SystemPhotoImporter(temporaryDirectory: () async => sandbox);
    scanner = PlatformDocumentScanner(
      importer: importer,
      channel: channel,
      isAndroid: true,
    );
    result = [first];
    failure = null;
    unreadable = null;
    invalid = null;
    releases = 0;
    reads.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'scan':
              if (failure != null) {
                throw PlatformException(
                  code: failure!,
                  message: 'private details',
                );
              }
              return result;
            case 'pageLength':
              if (call.arguments == unreadable) {
                throw PlatformException(code: 'invalid_result');
              }
              return call.arguments == invalid ? 3 : image.length;
            case 'readPage':
              if (!reads.add(call.arguments as String)) return Uint8List(0);
              return call.arguments == invalid
                  ? Uint8List.fromList([1, 2, 3])
                  : image;
            case 'releasePages':
              releases++;
              return null;
            default:
              throw MissingPluginException();
          }
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await sandbox.delete(recursive: true);
  });
  Matcher scanError(ScanFailure failure) => throwsA(
    isA<ScanException>().having((e) => e.failure, 'failure', failure),
  );

  test('native result is streamed into validated owned storage', () async {
    final pages = (await scanner.scan())!;
    expect(pages.length, 1);
    expect(pages.single.width, 1);
    expect(pages.single.source, PageSource.nativeScanner);
    expect(pages.single.sortOrder, 0);
    expect(pages.single.byteLength, image.length);
    expect(pages.single.sourcePath, pages.single.workingPath);
    expect(pages.single.ownership!.sessionId, pages.single.id);
    expect(await File(pages.single.path).readAsBytes(), image);
    expect(releases, 1);
    await importer.discard(pages.single);
  });
  test('cancellation returns idle without a working copy', () async {
    result = null;
    expect(await scanner.scan(), isNull);
    expect(await sandbox.list().toList(), isEmpty);
    expect(releases, 1);
  });
  test('unsupported platforms do not call native code', () async {
    final unsupported = PlatformDocumentScanner(
      importer: importer,
      channel: channel,
      isAndroid: false,
    );
    await expectLater(unsupported.scan(), scanError(ScanFailure.unsupported));
    expect(releases, 0);
  });
  for (final entry in {
    'unsupported': ScanFailure.unsupported,
    'unavailable': ScanFailure.unavailable,
    'initialization': ScanFailure.initialization,
    'interrupted': ScanFailure.interrupted,
    'invalid_result': ScanFailure.invalidResult,
    'other': ScanFailure.unexpected,
  }.entries) {
    test('maps ${entry.key} to a safe recoverable error', () async {
      failure = entry.key;
      await expectLater(scanner.scan(), scanError(entry.value));
      failure = null;
      result = null;
      expect(await scanner.scan(), isNull);
    });
  }
  test('rejects empty, malformed and duplicate page results', () async {
    for (final bad in [
      [],
      ['../../outside'],
      [first, first],
      {
        'pages': [first],
      },
    ]) {
      result = bad;
      await expectLater(scanner.scan(), scanError(ScanFailure.invalidResult));
    }
  });
  test('inaccessible page is rejected without a working session', () async {
    unreadable = first;
    await expectLater(scanner.scan(), throwsA(isA<PhotoImportException>()));
    expect(await sandbox.list().toList(), isEmpty);
    expect(releases, 1);
  });
  test(
    'copies all returned pages in order to distinct owned sessions',
    () async {
      result = [first, second];
      final pages = (await scanner.scan())!;
      expect(pages.length, 2);
      expect(reads.toList(), [first, second]);
      expect(pages.first.path, isNot(pages.last.path));
      expect(pages.first.id, isNot(pages.last.id));
      expect(pages.map((page) => page.sortOrder), [0, 1]);
      expect(
        pages.map((page) => page.source),
        everyElement(PageSource.nativeScanner),
      );
      for (final page in pages) {
        await importer.discard(page);
      }
    },
  );
  test('invalid later page rolls back the complete batch', () async {
    result = [first, second];
    invalid = second;
    await expectLater(
      scanner.scan(),
      throwsA(
        isA<PhotoImportException>().having(
          (e) => e.failure,
          'failure',
          ImportFailure.invalidImage,
        ),
      ),
    );
    expect(
      await Directory('${sandbox.path}/capture_working').list().toList(),
      isEmpty,
    );
    expect(releases, 1);
  });

  test('failed batch cannot remove a previously valid gallery page', () async {
    final previous = await importer.copyPhoto(XFile.fromData(image));
    result = [first, second];
    invalid = second;
    await expectLater(scanner.scan(), throwsA(isA<PhotoImportException>()));
    expect(await File(previous.path).readAsBytes(), image);
    final remaining = await Directory(
      '${sandbox.path}/capture_working',
    ).list().toList();
    expect(remaining.length, 1);
    expect(
      await remaining.single.resolveSymbolicLinks(),
      File(previous.path).parent.path,
    );
    await importer.discard(previous);
  });

  test(
    'failed batch rollback retains ownership and blocks new scans until retried',
    () async {
      final retryingImporter = RollbackImporter()
        ..cleanupFailure = const PhotoImportException(ImportFailure.storage);
      final retrying = PlatformDocumentScanner(
        importer: retryingImporter,
        channel: channel,
        isAndroid: true,
      );
      result = [first, second];
      await expectLater(retrying.scan(), throwsA(isA<PhotoImportException>()));
      expect(releases, 1);
      await expectLater(retrying.scan(), throwsA(isA<PhotoImportException>()));
      expect(releases, 1);
      retryingImporter.cleanupFailure = null;
      result = null;
      expect(await retrying.scan(), isNull);
      expect(retryingImporter.discarded, 1);
      expect(releases, 2);
    },
  );
}

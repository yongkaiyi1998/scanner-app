import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/data/system_photo_importer.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/editor/page_edit_session.dart';
import 'package:scanner_app/features/editor/source_validator.dart';
import '../scan/fake_document_scanner.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late SystemPhotoImporter importer;
  late ProviderContainer container;
  late List<DocumentPage> pages;
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawColor(const ui.Color(0xffcc4422), ui.BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 16);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('editor_integration_');
    importer = SystemPhotoImporter(
      temporaryDirectory: () async => sandbox,
      retrieveLostData: () async => LostDataResponse.empty(),
    );
    pages = [
      await importer.copyPhoto(XFile.fromData(png)),
      await importer.copyPhoto(
        XFile.fromData(png),
        source: PageSource.nativeScanner,
        sortOrder: 1,
      ),
    ];
    final scanner = FakeDocumentScanner()..pages = pages;
    container = ProviderContainer(
      overrides: [
        photoImporterProvider.overrideWithValue(importer),
        documentScannerProvider.overrideWithValue(scanner),
      ],
    );
    await container.read(captureControllerProvider.future);
    await container.read(captureControllerProvider.notifier).scanDocument();
  });
  tearDown(() async {
    container.dispose();
    for (final page in pages) {
      await importer.discard(page);
    }
    await sandbox.delete(recursive: true);
  });

  test(
    'Apply edits only selected page; paths, IDs and ownership cannot be replaced',
    () async {
      final original = pages.last;
      final malicious = DocumentPage(
        id: original.id,
        path: '../../other',
        sourcePath: 'external',
        width: 999,
        height: 999,
        rotationQuarterTurns: 1,
        crop: PageCrop(left: .25, top: 0, right: .75, bottom: 1),
      );
      final controller = container.read(captureControllerProvider.notifier);
      expect(controller.applyPageEdit(original, malicious), isTrue);
      final updated = container.read(captureControllerProvider).value!;
      expect(updated.isScan, isTrue);
      expect(updated.pages.first, same(pages.first));
      expect(updated.pages.last.id, original.id);
      expect(updated.pages.last.sourcePath, original.sourcePath);
      expect(updated.pages.last.workingPath, original.workingPath);
      expect(updated.pages.last.ownership, same(original.ownership));
      expect(updated.pages.last.width, original.width);
      expect(updated.pages.last.sortOrder, 1);
      expect(updated.pages.last.rotationQuarterTurns, 1);
      expect(updated.pages.last.crop, malicious.crop);
      expect(await File(original.sourcePath).readAsBytes(), png);
    },
  );

  test('stale or mismatched Apply cannot overwrite valid session pages', () {
    final controller = container.read(captureControllerProvider.notifier);
    expect(controller.applyPageEdit(pages.first, pages.last), isFalse);
    expect(
      controller.applyPageEdit(
        pages.first,
        pages.first.copyWith(rotationQuarterTurns: 1),
      ),
      isTrue,
    );
    expect(
      controller.applyPageEdit(
        pages.first,
        pages.first.copyWith(rotationQuarterTurns: 2),
      ),
      isFalse,
    );
    expect(
      container
          .read(captureControllerProvider)
          .value!
          .pages
          .first
          .rotationQuarterTurns,
      1,
    );
  });

  test('Cancel leaves all session pages and source bytes unchanged', () async {
    final initial = container.read(captureControllerProvider).value!;
    final draft = PageEditSession(pages.first)
      ..rotate()
      ..crop(PageCrop(left: .25, top: 0, right: .75, bottom: 1));
    expect(draft.page.rotationQuarterTurns, 1);
    expect(container.read(captureControllerProvider).value, same(initial));
    for (final page in pages) {
      expect(await File(page.sourcePath).readAsBytes(), png);
    }
  });

  test(
    'edits create no intermediate files; edited preview cleanup remains owned',
    () async {
      final controller = container.read(captureControllerProvider.notifier);
      final draft = PageEditSession(pages.last)
        ..rotate()
        ..crop(PageCrop(left: .25, top: .25, right: .75, bottom: .75));
      controller.applyPageEdit(pages.last, draft.page);
      for (final page in pages) {
        final files = await File(page.sourcePath).parent.list().toList();
        expect(
          files.length,
          2,
        ); // Unchanged source and existing ownership marker.
        expect(await File(page.sourcePath).readAsBytes(), png);
      }
      await controller.discard();
      expect(container.read(captureControllerProvider).value, isNull);
      expect(
        await Directory('${sandbox.path}/capture_working').list().toList(),
        isEmpty,
      );
    },
  );

  test(
    'bounded source validation accepts original metadata without changing bytes',
    () async {
      await validateEditorSource(pages.first);
      expect(await File(pages.first.sourcePath).readAsBytes(), png);
    },
  );

  test(
    'missing, corrupt and mismatched sources fail safely without losing other pages',
    () async {
      final initial = container.read(captureControllerProvider).value;
      final source = File(pages.first.sourcePath);
      await source.delete();
      await expectLater(
        validateEditorSource(pages.first),
        throwsA(isA<EditorException>()),
      );
      await source.writeAsBytes([1, 2, 3]);
      await expectLater(
        validateEditorSource(pages.first),
        throwsA(isA<EditorException>()),
      );
      await source.writeAsBytes(png);
      final wrong = DocumentPage(
        id: 'wrong',
        path: source.path,
        width: 1,
        height: 1,
      );
      await expectLater(
        validateEditorSource(wrong),
        throwsA(isA<EditorException>()),
      );
      expect(container.read(captureControllerProvider).value, same(initial));
      expect(await File(pages.last.sourcePath).readAsBytes(), png);
    },
  );
}

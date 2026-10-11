import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/app/app.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'capture/fake_photo_importer.dart';
import 'scan/fake_document_scanner.dart';

void main() {
  late FakePhotoImporter importer;
  setUp(() => importer = FakePhotoImporter());
  Future<void> mount(
    WidgetTester tester, {
    FakeDocumentScanner? scanner,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photoImporterProvider.overrideWithValue(importer),
          if (scanner != null)
            documentScannerProvider.overrideWithValue(scanner),
        ],
        child: const ScannerApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Home placeholder', (WidgetTester tester) async {
    await mount(tester);

    expect(find.text('Document Scanner'), findsOneWidget);
    expect(find.text('Your documents will appear here'), findsOneWidget);
  });

  testWidgets('opens the History placeholder', (WidgetTester tester) async {
    await mount(tester);

    await tester.tap(find.text('View recent documents'));
    await tester.pumpAndSettle();

    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('Saved documents will appear here.'), findsOneWidget);
  });

  testWidgets(
    'Scan entry point reports unsupported desktop without launching import',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Scan Document'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'Document scanning is not supported on this device',
        ),
        findsOneWidget,
      );
      expect(importer.calls, 0);
    },
  );

  testWidgets('cancelled import keeps Home usable', (tester) async {
    await mount(tester);
    await tester.tap(find.text('Import from Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Imported image preview'), findsNothing);
    expect(find.text('Import from Gallery'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid import shows a safe message and allows retry', (
    tester,
  ) async {
    importer.failure = const PhotoImportException(ImportFailure.invalidImage);
    await mount(tester);
    await tester.tap(find.text('Import from Gallery'));
    await tester.pumpAndSettle();
    expect(find.text(importer.failure!.message), findsOneWidget);
    importer.failure = null;
    await tester.tap(find.text('Import from Gallery'));
    await tester.pumpAndSettle();
    expect(importer.calls, 2);
    expect(find.textContaining('This file is not'), findsNothing);
  });

  testWidgets('successful import reaches bounded preview and can close', (
    tester,
  ) async {
    importer.nextPhoto = const DocumentPage(
      id: 'missing-test-preview.image',
      path: 'missing-test-preview.image',
      width: 6000,
      height: 4000,
    );
    await mount(tester);
    await tester.tap(find.text('Import from Gallery'));
    await tester.pumpAndSettle();
    expect(find.text('Imported image preview'), findsOneWidget);
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, 1024);
    expect(resized.height, 683);
    await tester.ensureVisible(find.text('Close preview'));
    await tester.tap(find.text('Close preview'));
    await tester.pumpAndSettle();
    expect(importer.discarded, 1);
    expect(find.text('Imported image preview'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview applies additional rotation separately from decoder EXIF',
    (tester) async {
      importer.nextPhoto = const DocumentPage(
        id: 'rotation-test',
        path: 'missing-rotation-preview.image',
        width: 32,
        height: 16,
        rotationQuarterTurns: 1,
      );
      await mount(tester);
      await tester.tap(find.text('Import from Gallery'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns,
        1,
      );
      final image = tester.widget<Image>(find.byType(Image));
      final fallback =
          image.errorBuilder!(
                tester.element(find.byType(Image)),
                const FileSystemException('Unreadable test image'),
                StackTrace.empty,
              )
              as Text;
      expect(fallback.data, contains('preview is no longer readable'));
      await tester.ensureVisible(find.text('Close preview'));
      await tester.tap(find.text('Close preview'));
      await tester.pumpAndSettle();
      expect(importer.discarded, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('scanned pages reuse preview navigation and all close together', (
    tester,
  ) async {
    final scanner = FakeDocumentScanner()
      ..pages = [
        const DocumentPage(
          id: 'missing-scan-one',
          path: 'missing-scan-one',
          width: 1000,
          height: 1500,
        ),
        const DocumentPage(
          id: 'missing-scan-two',
          path: 'missing-scan-two',
          width: 1000,
          height: 1500,
        ),
      ];
    await mount(tester, scanner: scanner);
    await tester.tap(find.text('Scan Document'));
    await tester.pumpAndSettle();
    expect(find.text('Scanned document preview'), findsOneWidget);
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Next page'));
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 2 of 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous page'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1 of 2'), findsOneWidget);
    await tester.ensureVisible(find.text('Close preview'));
    await tester.tap(find.text('Close preview'));
    await tester.pumpAndSettle();
    expect(importer.discarded, 2);
    expect(find.text('Scan Document'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('scanner cancellation restores Home actions', (tester) async {
    await mount(tester, scanner: FakeDocumentScanner());
    await tester.tap(find.text('Scan Document'));
    await tester.pumpAndSettle();
    expect(find.text('Scan Document'), findsOneWidget);
    expect(find.text('Import from Gallery'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

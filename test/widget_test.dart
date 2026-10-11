import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/app/app.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'capture/fake_photo_importer.dart';

void main() {
  late FakePhotoImporter importer;
  setUp(() => importer = FakePhotoImporter());
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [photoImporterProvider.overrideWithValue(importer)],
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
    'Scan entry point explains availability without launching capture',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text('Scan Document'));
      await tester.pump();
      expect(
        find.textContaining('Document scanning is not available yet'),
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
    importer.nextPhoto = const ImportedPhoto(
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
}

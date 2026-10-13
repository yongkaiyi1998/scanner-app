import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/features/documents/domain/document_page.dart';
import 'package:scanner_app/features/editor/presentation/crop_screen.dart';
import 'package:scanner_app/features/editor/presentation/document_page_image.dart';
import 'package:scanner_app/features/editor/presentation/editor_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late File file;
  late DocumentPage page;
  late Uint8List png;
  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, 16, 16),
      ui.Paint()..color = const ui.Color(0xffff0000),
    );
    canvas.drawRect(
      const ui.Rect.fromLTWH(16, 0, 16, 16),
      ui.Paint()..color = const ui.Color(0xff0000ff),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 16);
    png = (await image.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();
    image.dispose();
    picture.dispose();
  });
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('editor_widget_');
    file = File('${sandbox.path}/source.png');
    await file.writeAsBytes(png);
    page = DocumentPage(id: 'selected', path: file.path, width: 32, height: 16);
  });
  tearDown(() async => sandbox.delete(recursive: true));

  Future<void> cacheSource(WidgetTester tester) async {
    await tester.runAsync(
      () => precacheImage(
        ResizeImage(FileImage(file), width: 32, height: 16),
        tester.element(find.byType(Scaffold).first),
      ).timeout(const Duration(seconds: 5)),
    );
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> dragCrop(
    WidgetTester tester,
    String corner,
    Offset delta,
  ) async {
    await tester.drag(find.byKey(ValueKey('crop-$corner')), delta);
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    required DocumentPage input,
    required void Function(DocumentPage?) onResult,
    Future<void> Function(DocumentPage)? validate,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final result = await Navigator.push<DocumentPage>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditorScreen(
                      page: input,
                      pageNumber: 2,
                      pageCount: 3,
                      validateSource: validate ?? (_) async {},
                    ),
                  ),
                );
                onResult(result);
              },
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await cacheSource(tester);
    await tap(tester, 'Open editor');
  }

  testWidgets('Rotate, Undo, Reset and Apply return only the committed draft', (
    tester,
  ) async {
    DocumentPage? result;
    await open(tester, input: page, onResult: (value) => result = value);
    expect(find.text('Edit page 2 of 3'), findsOneWidget);
    await tap(tester, 'Rotate 90°');
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 1);
    await tap(tester, 'Undo');
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 0);
    await tap(tester, 'Rotate 90°');
    await tap(tester, 'Reset');
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 0);
    await tap(tester, 'Rotate 90°');
    await tap(tester, 'Apply');
    expect(result!.rotationQuarterTurns, 1);
    expect(result!.sourcePath, page.sourcePath);
    expect(page.rotationQuarterTurns, 0);
    // Real file I/O must complete outside the widget test's fake-async zone.
    final sourceBytes = await tester.runAsync(
      () => file.readAsBytes().timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
          'Source-byte verification timed out while reading the editor fixture.',
          const Duration(seconds: 5),
        ),
      ),
    );
    expect(sourceBytes, png);
  }, timeout: const Timeout(Duration(seconds: 20)));
  testWidgets('Cancel and system Back discard uncommitted metadata', (
    tester,
  ) async {
    DocumentPage? result;
    var returns = 0;
    for (final cancel in [true, false]) {
      await open(
        tester,
        input: page,
        onResult: (value) {
          result = value;
          returns++;
        },
      );
      await tap(tester, 'Rotate 90°');
      if (cancel) {
        await tap(tester, 'Cancel');
      } else {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }
      expect(result, isNull);
      expect(find.text('Open editor'), findsOneWidget);
      expect(page.rotationQuarterTurns, 0);
    }
    expect(returns, 2);
  });

  testWidgets('crop controls confirm; re-crop shows the original full source', (
    tester,
  ) async {
    DocumentPage? result;
    await open(tester, input: page, onResult: (value) => result = value);
    await tap(tester, 'Rotate 90°');
    await tap(tester, 'Crop');
    final imageBounds = tester.getRect(
      find.byKey(const ValueKey('crop-image-bounds')),
    );
    await dragCrop(tester, 'top-left', Offset(imageBounds.width * .25, 0));
    await dragCrop(tester, 'bottom-right', Offset(-imageBounds.width * .25, 0));
    await tap(tester, 'Confirm crop');
    expect(find.text('Re-crop'), findsOneWidget);
    await tap(tester, 'Re-crop');
    final sourceView = tester.widget<DocumentPageImage>(
      find.byType(DocumentPageImage).last,
    );
    expect(sourceView.page.crop, PageCrop.full);
    expect(sourceView.page.sourcePath, page.sourcePath);
    final reopenedBounds = tester.getRect(
      find.byKey(const ValueKey('crop-image-bounds')),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('crop-top-left'))).dx,
      closeTo(reopenedBounds.left + reopenedBounds.width * .25, .01),
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('crop-bottom-right'))).dx,
      closeTo(reopenedBounds.left + reopenedBounds.width * .75, .01),
    );
    await dragCrop(tester, 'top-left', Offset(-reopenedBounds.width * .25, 0));
    await dragCrop(
      tester,
      'bottom-right',
      Offset(reopenedBounds.width * .25, 0),
    );
    await tap(tester, 'Confirm crop');
    await tap(tester, 'Apply');
    expect(result!.crop, PageCrop.full);
    expect(result!.rotationQuarterTurns, 1);
  });

  testWidgets('Cancel crop does not add an edit operation', (tester) async {
    DocumentPage? result;
    await open(tester, input: page, onResult: (value) => result = value);
    await tap(tester, 'Crop');
    final imageBounds = tester.getRect(
      find.byKey(const ValueKey('crop-image-bounds')),
    );
    await dragCrop(tester, 'top-left', Offset(imageBounds.width * .25, 0));
    await tap(tester, 'Cancel crop');
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Undo'))
          .onPressed,
      isNull,
    );
    await tap(tester, 'Apply');
    expect(result!.crop, PageCrop.full);
  });

  testWidgets('unreadable source disables Apply and permits retry or cancel', (
    tester,
  ) async {
    var fail = true;
    await open(
      tester,
      input: page,
      onResult: (_) {},
      validate: (_) async {
        if (fail) throw StateError('Private details');
      },
    );
    expect(
      find.textContaining('source image is no longer readable'),
      findsOneWidget,
    );
    expect(find.textContaining('Private details'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Apply'))
          .onPressed,
      isNull,
    );
    fail = false;
    await tap(tester, 'Retry source');
    expect(
      find.textContaining('source image is no longer readable'),
      findsNothing,
    );
    await tap(tester, 'Cancel');
  });

  testWidgets(
    'source failure at Apply keeps the draft and does not publish it',
    (tester) async {
      var checks = 0;
      var returned = false;
      await open(
        tester,
        input: page,
        onResult: (_) => returned = true,
        validate: (_) async {
          if (++checks > 1) throw StateError('Missing');
        },
      );
      await tap(tester, 'Rotate 90°');
      await tap(tester, 'Apply');
      expect(returned, isFalse);
      expect(
        find.textContaining('source image is no longer readable'),
        findsOneWidget,
      );
      await tap(tester, 'Cancel');
    },
  );

  testWidgets('cropped preview renders source pixels, not the unedited image', (
    tester,
  ) async {
    final key = GlobalKey();
    final fixtureProvider = ResizeImage(FileImage(file), width: 32, height: 16);
    try {
      // Start file loading in real async before any image-bearing widget exists.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      final bootstrapContext = tester.element(find.byType(Scaffold));
      final preloaded = await tester.runAsync<bool>(() async {
        Object? preloadError;
        await precacheImage(
          fixtureProvider,
          bootstrapContext,
          onError: (error, stack) => preloadError = error,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException(
              'Fixture preload timed out before widget mounting.',
              const Duration(seconds: 5),
            );
          },
        );
        if (preloadError != null) {
          throw StateError(
            'Fixture image could not be decoded before widget mounting.',
          );
        }
        return true;
      });
      expect(
        preloaded,
        isTrue,
        reason: 'Pixel capture requires a fully decoded fixture.',
      );
      await tester.pump(); // Release the precache listener before mounting.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: DocumentPageImage(
                    page: page.copyWith(
                      crop: PageCrop(left: .5, top: 0, right: 1, bottom: 1),
                      rotationQuarterTurns: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 5),
      );
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      expect(boundary.debugNeedsPaint, isFalse);
      // Settle frames first; only native pixel capture runs outside fake async.
      await tester.runAsync(() async {
        var captureExpired = false;
        final image = await boundary
            .toImage()
            .then((captured) {
              if (captureExpired) captured.dispose();
              return captured;
            })
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                captureExpired = true;
                throw TimeoutException(
                  'Frames settled, but boundary.toImage timed out.',
                  const Duration(seconds: 5),
                );
              },
            );
        try {
          final bytes = await image.toByteData().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
              'Image captured, but image.toByteData timed out.',
              const Duration(seconds: 5),
            ),
          );
          expect(bytes, isNotNull);
          final pixels = bytes!.buffer.asUint8List();
          final center = (60 * image.width + 60) * 4;
          expect(pixels[center], lessThan(30));
          expect(pixels[center + 2], greaterThan(200));
        } finally {
          image.dispose();
        }
      });
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final released = await tester.runAsync<bool>(() async {
        await fixtureProvider.evict().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException(
            'Fixture image eviction timed out.',
            const Duration(seconds: 5),
          ),
        );
        return true;
      });
      expect(
        released,
        isTrue,
        reason: 'Fixture users must be released before teardown.',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets(
    'crop overlay fits portrait and landscape viewports without overflow',
    (tester) async {
      final fixtureProvider = ResizeImage(
        FileImage(file),
        width: 32,
        height: 16,
      );
      try {
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        );
        final bootstrapContext = tester.element(find.byType(Scaffold));
        final preloaded = await tester.runAsync<bool>(() async {
          Object? preloadError;
          await precacheImage(
            fixtureProvider,
            bootstrapContext,
            onError: (error, stack) => preloadError = error,
          ).timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              throw TimeoutException(
                'Viewport fixture preload timed out before mounting.',
                const Duration(seconds: 5),
              );
            },
          );
          if (preloadError != null) {
            throw StateError(
              'Viewport fixture could not be decoded before mounting.',
            );
          }
          return true;
        });
        expect(
          preloaded,
          isTrue,
          reason: 'Viewport assertions require a fully decoded fixture.',
        );
        await tester.pump();
        for (final size in [const Size(360, 640), const Size(640, 360)]) {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          await tester.pumpWidget(MaterialApp(home: CropScreen(page: page)));
          await tester.pumpAndSettle(
            const Duration(milliseconds: 100),
            EnginePhase.sendSemanticsUpdate,
            const Duration(seconds: 5),
          );
          expect(tester.takeException(), isNull);
          for (final corner in [
            'top-left',
            'top-right',
            'bottom-left',
            'bottom-right',
          ]) {
            expect(find.byKey(ValueKey('crop-$corner')), findsOneWidget);
          }
        }
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        final released = await tester.runAsync<bool>(() async {
          await fixtureProvider.evict().timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException(
              'Viewport fixture eviction timed out.',
              const Duration(seconds: 5),
            ),
          );
          return true;
        });
        expect(
          released,
          isTrue,
          reason: 'Viewport fixture users must be released before teardown.',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

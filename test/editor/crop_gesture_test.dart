import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/features/documents/domain/document_page.dart';
import 'package:scanner_app/features/editor/page_edit_session.dart';
import 'package:scanner_app/features/editor/presentation/crop_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late File file;
  late DocumentPage page;
  late Uint8List png;
  PageCrop? confirmed;

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
    sandbox = await Directory.systemTemp.createTemp('crop_gesture_');
    file = File('${sandbox.path}/source.png');
    await file.writeAsBytes(png);
    page = DocumentPage(
      id: 'touch-page',
      path: file.path,
      width: 32,
      height: 16,
    );
    confirmed = null;
  });
  tearDown(() async => sandbox.delete(recursive: true));

  Finder handle(String corner) => find.byKey(ValueKey('crop-$corner'));
  Rect selection(WidgetTester tester) => Rect.fromPoints(
    tester.getCenter(handle('top-left')),
    tester.getCenter(handle('bottom-right')),
  );

  Future<void> withCrop(
    WidgetTester tester, {
    int rotation = 0,
    Size viewport = const Size(360, 640),
    PageCrop initial = PageCrop.full,
    required Future<void> Function(Rect imageBounds) body,
  }) async {
    final provider = ResizeImage(FileImage(file), width: 32, height: 16);
    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  confirmed = await Navigator.push<PageCrop>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CropScreen(
                        page: page.copyWith(
                          rotationQuarterTurns: rotation,
                          crop: initial,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open crop'),
              ),
            ),
          ),
        ),
      );
      final context = tester.element(find.byType(Scaffold));
      final ready = await tester.runAsync<bool>(() async {
        Object? error;
        await precacheImage(
          provider,
          context,
          onError: (exception, stack) => error = exception,
        ).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            throw TimeoutException(
              'Gesture fixture preload timed out before mounting.',
            );
          },
        );
        if (error != null) {
          throw StateError('Gesture fixture could not be decoded.');
        }
        return true;
      });
      expect(
        ready,
        isTrue,
        reason: 'Drag tests require a decoded source image.',
      );
      await tester.pump();
      await tester.tap(find.text('Open crop'));
      await tester.pumpAndSettle();
      await body(
        tester.getRect(find.byKey(const ValueKey('crop-image-bounds'))),
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      final released = await tester.runAsync<bool>(() async {
        await provider.evict().timeout(const Duration(seconds: 5));
        return true;
      });
      expect(released, isTrue);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    }
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Confirm crop'));
    await tester.tap(find.text('Confirm crop'));
    await tester.pumpAndSettle();
    expect(confirmed, isNotNull);
  }

  final corners = {
    'top-left': const Offset(1, 1),
    'top-right': const Offset(-1, 1),
    'bottom-left': const Offset(1, -1),
    'bottom-right': const Offset(-1, -1),
  };
  for (final entry in corners.entries) {
    testWidgets('drag ${entry.key} updates both adjacent rectangular edges', (
      tester,
    ) async {
      await withCrop(
        tester,
        body: (image) async {
          final before = tester.widget<Image>(find.byType(Image));
          expect(tester.getSize(handle(entry.key)), const Size(48, 48));
          await tester.drag(
            handle(entry.key),
            Offset(
              entry.value.dx * image.width * .2,
              entry.value.dy * image.height * .2,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.widget<Image>(find.byType(Image)),
            same(before),
            reason: 'Dragging must not rebuild or decode the source image.',
          );
          await confirm(tester);
          expect(confirmed!.left, closeTo(entry.value.dx > 0 ? .2 : 0, .001));
          expect(confirmed!.right, closeTo(entry.value.dx < 0 ? .8 : 1, .001));
          expect(confirmed!.top, closeTo(entry.value.dy > 0 ? .2 : 0, .001));
          expect(confirmed!.bottom, closeTo(entry.value.dy < 0 ? .8 : 1, .001));
          final bytes = await tester.runAsync(
            () => file.readAsBytes().timeout(const Duration(seconds: 5)),
          );
          expect(bytes, png);
          expect(page.crop, PageCrop.full);
        },
      );
    }, timeout: const Timeout(Duration(seconds: 20)));

    testWidgets(
      '${entry.key} clamps outside image and cannot cross the opposite corner',
      (tester) async {
        await withCrop(
          tester,
          body: (image) async {
            await tester.drag(
              handle(entry.key),
              Offset(-entry.value.dx * 1000, -entry.value.dy * 1000),
            );
            await tester.pumpAndSettle();
            expect(selection(tester).left, closeTo(image.left, .01));
            expect(selection(tester).top, closeTo(image.top, .01));
            expect(selection(tester).right, closeTo(image.right, .01));
            expect(selection(tester).bottom, closeTo(image.bottom, .01));
            await tester.drag(
              handle(entry.key),
              Offset(entry.value.dx * 1000, entry.value.dy * 1000),
            );
            await tester.pumpAndSettle();
            final rect = selection(tester);
            expect(rect.width, closeTo(48, .01));
            expect(rect.height, closeTo(48, .01));
            expect(rect.left, greaterThanOrEqualTo(image.left - .01));
            expect(rect.top, greaterThanOrEqualTo(image.top - .01));
            expect(rect.right, lessThanOrEqualTo(image.right + .01));
            expect(rect.bottom, lessThanOrEqualTo(image.bottom + .01));
            await confirm(tester);
            expect(confirmed!.width, greaterThan(0));
            expect(confirmed!.height, greaterThan(0));
          },
        );
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );
  }

  for (final viewport in [const Size(360, 640), const Size(640, 360)]) {
    for (var turns = 0; turns < 4; turns++) {
      testWidgets(
        'fitted bounds and source mapping: $viewport rotation $turns',
        (tester) async {
          await withCrop(
            tester,
            viewport: viewport,
            rotation: turns,
            body: (image) async {
              final expectedAspect = turns.isOdd ? .5 : 2.0;
              expect(image.width / image.height, closeTo(expectedAspect, .001));
              final canvas = tester.getRect(
                find
                    .ancestor(
                      of: find.byKey(const ValueKey('crop-image-bounds')),
                      matching: find.byType(Stack),
                    )
                    .first,
              );
              expect(image.left - canvas.left, greaterThanOrEqualTo(23.99));
              expect(image.top - canvas.top, greaterThanOrEqualTo(23.99));
              for (final corner in corners.keys) {
                expect(
                  tester.getRect(handle(corner)).left,
                  greaterThanOrEqualTo(canvas.left - .01),
                );
                expect(
                  tester.getRect(handle(corner)).right,
                  lessThanOrEqualTo(canvas.right + .01),
                );
              }
              await tester.drag(
                handle('top-left'),
                Offset(image.width * .2, image.height * .2),
              );
              await tester.pumpAndSettle();
              await confirm(tester);
              expect(confirmed!.left, closeTo(.2, .001));
              expect(confirmed!.top, closeTo(.2, .001));
              final edit = PageEditSession(
                page.copyWith(rotationQuarterTurns: turns),
              )..crop(confirmed!);
              final expected = PageCrop(
                left: .2,
                top: .2,
                right: 1,
                bottom: 1,
              ).rotated(-turns);
              expect(edit.page.crop.left, closeTo(expected.left, .001));
              expect(edit.page.crop.top, closeTo(expected.top, .001));
              expect(edit.page.crop.right, closeTo(expected.right, .001));
              expect(edit.page.crop.bottom, closeTo(expected.bottom, .001));
            },
          );
        },
        timeout: const Timeout(Duration(seconds: 20)),
      );
    }
  }

  testWidgets('drag updates interactively without jumping to finger offset', (
    tester,
  ) async {
    await withCrop(
      tester,
      body: (image) async {
        final start = tester.getCenter(handle('top-left'));
        final gesture = await tester.startGesture(start + const Offset(8, 8));
        await gesture.moveBy(const Offset(25, 30));
        await tester.pump();
        expect(
          tester.getCenter(handle('top-left')).dx,
          closeTo(start.dx + 25, .01),
        );
        expect(
          tester.getCenter(handle('top-left')).dy,
          closeTo(start.dy + 30, .01),
        );
        await gesture.moveBy(const Offset(10, 10));
        await tester.pump();
        expect(
          tester.getCenter(handle('top-left')).dx,
          closeTo(start.dx + 35, .01),
        );
        await gesture.up();
        await tester.pumpAndSettle();
      },
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets('touching letterbox space does not change the selection', (
    tester,
  ) async {
    await withCrop(
      tester,
      rotation: 1,
      body: (image) async {
        final before = selection(tester);
        await tester.dragFrom(
          Offset(image.left - 50, image.center.dy),
          const Offset(25, 0),
        );
        await tester.pumpAndSettle();
        expect(selection(tester), before);
        await confirm(tester);
        expect(confirmed, PageCrop.full);
      },
    );
  }, timeout: const Timeout(Duration(seconds: 20)));

  testWidgets(
    'tiny previously accepted crop remains unchanged until dragged, then stays valid',
    (tester) async {
      final tiny = PageCrop(left: .995, top: .995, right: 1, bottom: 1);
      await withCrop(
        tester,
        initial: tiny,
        body: (image) async {
          expect(
            selection(tester).width,
            closeTo(image.width * tiny.width, .01),
          );
          await tester.drag(handle('bottom-right'), const Offset(-100, -100));
          await tester.pumpAndSettle();
          final rect = selection(tester);
          expect(rect.width, greaterThanOrEqualTo(47.99));
          expect(rect.height, greaterThanOrEqualTo(47.99));
          await confirm(tester);
          expect(confirmed!.left, greaterThanOrEqualTo(0));
          expect(confirmed!.top, greaterThanOrEqualTo(0));
          expect(confirmed!.right, lessThanOrEqualTo(1));
          expect(confirmed!.bottom, lessThanOrEqualTo(1));
        },
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

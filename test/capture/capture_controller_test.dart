import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';

import 'fake_photo_importer.dart';

void main() {
  const photo = ImportedPhoto(
    path: 'owned/source.image',
    width: 100,
    height: 200,
  );
  late FakePhotoImporter importer;
  late ProviderContainer container;

  setUp(() {
    importer = FakePhotoImporter();
    container = ProviderContainer(
      overrides: [photoImporterProvider.overrideWithValue(importer)],
    );
  });
  tearDown(() => container.dispose());

  test('restores a recovered selection on startup', () async {
    importer.recoveredPhoto = photo;
    expect(await container.read(captureControllerProvider.future), same(photo));
    expect(importer.recoveries, 1);
  });

  test('serializes import taps and cancellation returns idle', () async {
    await container.read(captureControllerProvider.future);
    importer.pending = Completer<ImportedPhoto?>();
    final controller = container.read(captureControllerProvider.notifier);
    final operation = controller.importPhoto();
    await controller.importPhoto();
    await Future<void>.delayed(Duration.zero);
    expect(importer.calls, 1);
    expect(container.read(captureControllerProvider).isLoading, isTrue);
    importer.pending!.complete(null);
    await operation;
    expect(container.read(captureControllerProvider).value, isNull);
    expect(container.read(captureControllerProvider).hasError, isFalse);
  });

  test('error can be retried, then preview is discarded', () async {
    await container.read(captureControllerProvider.future);
    final controller = container.read(captureControllerProvider.notifier);
    importer.failure = const PhotoImportException(ImportFailure.unreadable);
    await controller.importPhoto();
    expect(container.read(captureControllerProvider).hasError, isTrue);
    importer.failure = null;
    importer.nextPhoto = photo;
    await controller.importPhoto();
    expect(container.read(captureControllerProvider).value, same(photo));
    await controller.importPhoto();
    expect(importer.calls, 2);
    await controller.discard();
    expect(importer.discarded, 1);
    expect(container.read(captureControllerProvider).value, isNull);
  });

  test('failed cleanup is retried before another image is imported', () async {
    await container.read(captureControllerProvider.future);
    final controller = container.read(captureControllerProvider.notifier);
    importer.nextPhoto = photo;
    await controller.importPhoto();
    importer.cleanupFailure = const PhotoImportException(ImportFailure.storage);
    await controller.discard();
    expect(container.read(captureControllerProvider).hasError, isTrue);
    await controller.importPhoto();
    expect(importer.calls, 1);
    importer.cleanupFailure = null;
    importer.nextPhoto = null;
    await controller.importPhoto();
    expect(importer.discarded, 1);
    expect(importer.calls, 2);
  });
}

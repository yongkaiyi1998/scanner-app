import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/scan/document_scanner.dart';
import '../capture/fake_photo_importer.dart';
import 'fake_document_scanner.dart';

void main() {
  const first = DocumentPage(
    id: 'owned-first',
    path: 'owned-first',
    width: 1,
    height: 1,
  );
  const second = DocumentPage(
    id: 'owned-second',
    path: 'owned-second',
    width: 1,
    height: 1,
  );
  late FakeDocumentScanner scanner;
  late FakePhotoImporter importer;
  late ProviderContainer container;
  setUp(() {
    scanner = FakeDocumentScanner();
    importer = FakePhotoImporter();
    container = ProviderContainer(
      overrides: [
        photoImporterProvider.overrideWithValue(importer),
        documentScannerProvider.overrideWithValue(scanner),
      ],
    );
  });
  tearDown(() => container.dispose());
  test(
    'all scanned pages share the capture preview and close lifecycle',
    () async {
      await container.read(captureControllerProvider.future);
      scanner.pages = [first, second];
      final controller = container.read(captureControllerProvider.notifier);
      await controller.scanDocument();
      final preview = container.read(captureControllerProvider).value!;
      expect(preview.isScan, isTrue);
      expect(preview.pages, [first, second]);
      await controller.scanDocument();
      expect(scanner.calls, 1);
      await controller.discard();
      expect(importer.discarded, 2);
      expect(container.read(captureControllerProvider).value, isNull);
    },
  );
  test('cancellation and scanner failure leave capture retryable', () async {
    await container.read(captureControllerProvider.future);
    final controller = container.read(captureControllerProvider.notifier);
    await controller.scanDocument();
    expect(container.read(captureControllerProvider).value, isNull);
    scanner.failure = const ScanException(ScanFailure.initialization);
    await controller.scanDocument();
    expect(container.read(captureControllerProvider).isLoading, isFalse);
    expect(container.read(captureControllerProvider).hasError, isTrue);
    scanner.failure = null;
    scanner.pages = [first];
    await controller.scanDocument();
    expect(container.read(captureControllerProvider).value?.pages, [first]);
  });
  test('failed page cleanup is retried before another scan starts', () async {
    await container.read(captureControllerProvider.future);
    final controller = container.read(captureControllerProvider.notifier);
    scanner.pages = [first, second];
    await controller.scanDocument();
    importer.cleanupFailure = const PhotoImportException(ImportFailure.storage);
    await controller.discard();
    await controller.scanDocument();
    expect(scanner.calls, 1);
    importer.cleanupFailure = null;
    scanner.pages = null;
    await controller.scanDocument();
    expect(importer.discarded, 2);
    expect(scanner.calls, 2);
  });
}

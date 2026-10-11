import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scanner_app/features/capture/data/system_photo_importer.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/scan/document_scanner.dart';
import 'package:scanner_app/features/scan/data/platform_document_scanner.dart';

final photoImporterProvider = Provider<PhotoImporter>(
  (ref) => SystemPhotoImporter(),
);
final captureControllerProvider =
    AsyncNotifierProvider<CaptureController, CapturePreview?>(
      CaptureController.new,
    );
final documentScannerProvider = Provider<DocumentScanner>(
  (ref) => PlatformDocumentScanner(importer: ref.read(photoImporterProvider)),
);

class CapturePreview {
  CapturePreview(List<ImportedPhoto> pages, {this.isScan = false})
    : pages = List.unmodifiable(pages);
  final List<ImportedPhoto> pages;
  final bool isScan;
}

class CaptureController extends AsyncNotifier<CapturePreview?> {
  final List<ImportedPhoto> _pendingCleanup = [];
  @override
  Future<CapturePreview?> build() async {
    final photo = await ref.read(photoImporterProvider).recoverLostPhoto();
    return photo == null ? null : CapturePreview([photo]);
  }

  Future<void> _cleanup() async {
    while (_pendingCleanup.isNotEmpty) {
      await ref.read(photoImporterProvider).discard(_pendingCleanup.first);
      _pendingCleanup.removeAt(0);
    }
  }

  Future<void> importPhoto() => _capture(scan: false);
  Future<void> scanDocument() => _capture(scan: true);

  Future<void> _capture({required bool scan}) async {
    if (state.isLoading || (state.value != null && !state.hasError)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await _cleanup();
      if (scan) {
        final pages = await ref.read(documentScannerProvider).scan();
        if (pages == null) return null;
        if (pages.isEmpty) throw const ScanException(ScanFailure.invalidResult);
        return CapturePreview(pages, isScan: true);
      }
      final photo = await ref.read(photoImporterProvider).importPhoto();
      return photo == null ? null : CapturePreview([photo]);
    });
  }

  Future<void> discard() async {
    if (state.isLoading) return;
    final preview = state.value;
    if (preview != null) {
      _pendingCleanup.addAll(
        preview.pages.where((photo) => !_pendingCleanup.contains(photo)),
      );
    }
    if (_pendingCleanup.isEmpty) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    try {
      await _cleanup();
      state = const AsyncData(null);
    } catch (error, stack) {
      // Keep ownership available for another cleanup attempt.
      state = AsyncError(error, stack);
    }
  }
}

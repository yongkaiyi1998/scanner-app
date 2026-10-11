import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scanner_app/features/capture/data/system_photo_importer.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';

final photoImporterProvider = Provider<PhotoImporter>(
  (ref) => SystemPhotoImporter(),
);
final captureControllerProvider =
    AsyncNotifierProvider<CaptureController, ImportedPhoto?>(
      CaptureController.new,
    );

class CaptureController extends AsyncNotifier<ImportedPhoto?> {
  ImportedPhoto? _pendingCleanup;
  @override
  Future<ImportedPhoto?> build() =>
      ref.read(photoImporterProvider).recoverLostPhoto();

  Future<void> importPhoto() async {
    if (state.isLoading || (state.value != null && !state.hasError)) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      if (_pendingCleanup != null) {
        await ref.read(photoImporterProvider).discard(_pendingCleanup!);
        _pendingCleanup = null;
      }
      return ref.read(photoImporterProvider).importPhoto();
    });
  }

  Future<void> discard() async {
    if (state.isLoading) return;
    final photo = state.value ?? _pendingCleanup;
    if (photo == null) {
      state = const AsyncData(null);
      return;
    }
    state = const AsyncLoading();
    try {
      await ref.read(photoImporterProvider).discard(photo);
      _pendingCleanup = null;
      state = const AsyncData(null);
    } catch (error, stack) {
      // Keep ownership available for another cleanup attempt.
      _pendingCleanup = photo;
      state = AsyncError(error, stack);
    }
  }
}

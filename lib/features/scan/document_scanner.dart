import 'package:scanner_app/features/capture/photo_importer.dart';

enum ScanFailure {
  unsupported,
  unavailable,
  initialization,
  invalidResult,
  interrupted,
  unexpected,
}

class ScanException implements Exception {
  const ScanException(this.failure);
  final ScanFailure failure;
  String get message => switch (failure) {
    ScanFailure.unsupported =>
      'Document scanning is not supported on this device. You can import from Gallery.',
    ScanFailure.unavailable =>
      'Document scanning needs available Google Play services. You can import from Gallery.',
    ScanFailure.initialization =>
      'The scanner could not initialize. Check your connection for the first-use component download and try again.',
    ScanFailure.invalidResult =>
      'The scanned image could not be read safely. Please scan again.',
    ScanFailure.interrupted => 'Scanning was interrupted. Please try again.',
    ScanFailure.unexpected => 'Document scanning failed. Please try again.',
  };
  @override
  String toString() => message;
}

abstract interface class DocumentScanner {
  Future<List<DocumentPage>?> scan();
}

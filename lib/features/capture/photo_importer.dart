enum ImportFailure {
  unreadable,
  invalidImage,
  tooLarge,
  storage,
  unavailable,
  permission,
}

class PhotoImportException implements Exception {
  const PhotoImportException(this.failure);
  final ImportFailure failure;
  String get message => switch (failure) {
    ImportFailure.unreadable =>
      'This image could not be read. Please choose another image.',
    ImportFailure.invalidImage =>
      'This file is not a supported, readable image. Please choose another image.',
    ImportFailure.tooLarge =>
      'This image is too large to preview safely. Choose an image under 40 MB and 64 megapixels.',
    ImportFailure.storage =>
      'Working storage is unavailable. Free some space and try again.',
    ImportFailure.unavailable =>
      'The photo picker is unavailable. Please try again.',
    ImportFailure.permission =>
      'Access to the selected image was denied. Please select it again.',
  };
  @override
  String toString() => message;
}

class ImportedPhoto {
  const ImportedPhoto({
    required this.path,
    required this.width,
    required this.height,
  });
  final String path;
  final int width;
  final int height;
}

abstract interface class PhotoImporter {
  Future<ImportedPhoto?> recoverLostPhoto();
  Future<ImportedPhoto?> importPhoto();
  Future<void> discard(ImportedPhoto photo);
}

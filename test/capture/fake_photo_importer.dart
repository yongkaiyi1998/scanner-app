import 'dart:async';
import 'package:image_picker/image_picker.dart';

import 'package:scanner_app/features/capture/photo_importer.dart';

class FakePhotoImporter implements PhotoImporter {
  final List<String> copied = [];
  @override
  Future<ImportedPhoto> copyPhoto(XFile input) async {
    copied.add(input.path);
    if (failure != null) throw failure!;
    return nextPhoto ??
        ImportedPhoto(path: input.path, width: 100, height: 200);
  }

  ImportedPhoto? nextPhoto;
  ImportedPhoto? recoveredPhoto;
  PhotoImportException? failure;
  PhotoImportException? cleanupFailure;
  Completer<ImportedPhoto?>? pending;
  int calls = 0;
  int recoveries = 0;
  int discarded = 0;

  @override
  Future<ImportedPhoto?> recoverLostPhoto() async {
    recoveries++;
    return recoveredPhoto;
  }

  @override
  Future<ImportedPhoto?> importPhoto() async {
    calls++;
    if (failure != null) throw failure!;
    return pending == null ? nextPhoto : await pending!.future;
  }

  @override
  Future<void> discard(ImportedPhoto photo) async {
    if (cleanupFailure != null) throw cleanupFailure!;
    discarded++;
  }
}

import 'dart:async';
import 'package:image_picker/image_picker.dart';

import 'package:scanner_app/features/capture/photo_importer.dart';

class FakePhotoImporter implements PhotoImporter {
  final List<String> copied = [];
  @override
  Future<DocumentPage> copyPhoto(
    XFile input, {
    PageSource source = PageSource.gallery,
    int sortOrder = 0,
  }) async {
    copied.add(input.path);
    if (failure != null) throw failure!;
    return nextPhoto ??
        DocumentPage(
          id: input.path,
          path: input.path,
          width: 100,
          height: 200,
          source: source,
          sortOrder: sortOrder,
        );
  }

  DocumentPage? nextPhoto;
  DocumentPage? recoveredPhoto;
  PhotoImportException? failure;
  PhotoImportException? cleanupFailure;
  Completer<DocumentPage?>? pending;
  int calls = 0;
  int recoveries = 0;
  int discarded = 0;

  @override
  Future<DocumentPage?> recoverLostPhoto() async {
    recoveries++;
    return recoveredPhoto;
  }

  @override
  Future<DocumentPage?> importPhoto() async {
    calls++;
    if (failure != null) throw failure!;
    return pending == null ? nextPhoto : await pending!.future;
  }

  @override
  Future<void> discard(DocumentPage photo) async {
    if (cleanupFailure != null) throw cleanupFailure!;
    discarded++;
  }
}

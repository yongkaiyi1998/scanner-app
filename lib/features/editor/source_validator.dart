import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:scanner_app/features/documents/domain/document_page.dart';

enum EditorFailure { unreadableSource }

class EditorException implements Exception {
  const EditorException(this.failure);
  final EditorFailure failure;
  String get message =>
      'This source image is no longer readable. '
      'Retry or cancel editing; the other pages will be kept.';
  @override
  String toString() => message;
}

Future<void> validateEditorSource(DocumentPage page) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    final file = File(page.sourcePath);
    final length = await file.length();
    if (length <= 0 || length > 40 * 1024 * 1024) {
      throw const EditorException(EditorFailure.unreadableSource);
    }
    buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width != page.width ||
        descriptor.height != page.height ||
        descriptor.width * descriptor.height > 64000000) {
      throw const EditorException(EditorFailure.unreadableSource);
    }
    final scale = math.min(1.0, 1024 / math.max(page.width, page.height));
    codec = await descriptor.instantiateCodec(
      targetWidth: math.max(1, (page.width * scale).round()),
      targetHeight: math.max(1, (page.height * scale).round()),
    );
    image = (await codec.getNextFrame()).image;
  } catch (_) {
    throw const EditorException(EditorFailure.unreadableSource);
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

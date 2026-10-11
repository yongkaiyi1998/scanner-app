import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scanner_app/features/capture/data/system_photo_importer.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';

// Synthetic 32x16 JPEG: red left half, blue right half, no user image data.
Uint8List orientedJpeg(int orientation) {
  final jpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAQACADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDi6KKK+ZP3E5Ciiiv6XP57P//Z',
  );
  return Uint8List.fromList([
    ...jpeg.take(2),
    0xff, 0xe1, 0, 34,
    69, 120, 105, 102, 0, 0, // Exif header.
    73, 73, 42, 0, 8, 0, 0, 0, // Little-endian TIFF.
    1, 0, 18, 1, 3, 0, 1, 0, 0, 0, orientation, 0, 0, 0,
    0, 0, 0, 0,
    ...jpeg.skip(2),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  late SystemPhotoImporter importer;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('page_model_test_');
    importer = SystemPhotoImporter(temporaryDirectory: () async => sandbox);
  });
  tearDown(() async => sandbox.delete(recursive: true));

  for (final source in PageSource.values) {
    for (var orientation = 1; orientation <= 8; orientation++) {
      test(
        '${source.name}: EXIF $orientation is decoded exactly once',
        () async {
          final bytes = orientedJpeg(orientation);
          final page = await importer.copyPhoto(
            XFile.fromData(bytes),
            source: source,
            sortOrder: 2,
          );
          expect(page.id, startsWith('import_'));
          expect(page.source, source);
          expect(page.sortOrder, 2);
          expect(page.sourcePath, page.workingPath);
          expect(page.byteLength, bytes.length);
          expect(page.ownership!.sessionId, page.id);
          expect(page.ownership!.lifetime, PageFileLifetime.previewTemporary);
          expect(page.orientation, PageOrientation.decoderManagedExif);
          expect(page.rotationQuarterTurns, 0);
          expect(page.width, orientation >= 5 ? 16 : 32);
          expect(page.height, orientation >= 5 ? 32 : 16);
          expect(await File(page.path).readAsBytes(), bytes);

          final buffer = await ui.ImmutableBuffer.fromFilePath(page.path);
          final descriptor = await ui.ImageDescriptor.encoded(buffer);
          final codec = await descriptor.instantiateCodec();
          final image = (await codec.getNextFrame()).image;
          try {
            expect(image.width, page.width);
            expect(image.height, page.height);
            final pixels = (await image.toByteData())!.buffer.asUint8List();
            final offset =
                ((image.height ~/ 4) * image.width + image.width ~/ 4) * 4;
            final redFirst = [1, 4, 5, 6].contains(orientation);
            expect(
              redFirst ? pixels[offset] : pixels[offset + 2],
              greaterThan(200),
            );
            expect(
              redFirst ? pixels[offset + 2] : pixels[offset],
              lessThan(30),
            );
          } finally {
            image.dispose();
            codec.dispose();
            descriptor.dispose();
            buffer.dispose();
          }
          final changed = page.copyWith(sortOrder: 0, rotationQuarterTurns: -1);
          expect(changed.id, page.id);
          expect(changed.sourcePath, page.sourcePath);
          expect(changed.workingPath, page.workingPath);
          expect(changed.ownership, same(page.ownership));
          expect(changed.sortOrder, 0);
          expect(changed.rotationQuarterTurns, 3);
          expect(page.rotationQuarterTurns, 0);
          await importer.discard(changed);
          expect(await File(page.path).exists(), isFalse);
        },
      );
    }
  }

  test(
    'IDs are distinct for identical input; forged ownership cannot delete',
    () async {
      final bytes = orientedJpeg(1);
      final first = await importer.copyPhoto(XFile.fromData(bytes));
      final second = await importer.copyPhoto(XFile.fromData(bytes));
      expect(first.id, isNot(second.id));
      final external = File('${sandbox.path}/original.jpg');
      await external.writeAsBytes(bytes);
      final forged = DocumentPage(
        id: first.id,
        path: external.path,
        width: 32,
        height: 16,
        ownership: first.ownership,
      );
      await importer.discard(forged);
      expect(await external.exists(), isTrue);
      expect(await File(first.path).exists(), isTrue);
      final retained = DocumentPage(
        id: first.id,
        path: first.path,
        width: 32,
        height: 16,
        ownership: PageFileOwnership(
          sessionId: first.id,
          lifetime: PageFileLifetime.retainedForEditing,
        ),
      );
      await importer.discard(retained);
      expect(await File(first.path).exists(), isTrue);
      await importer.discard(first);
      await importer.discard(second);
      expect(await external.exists(), isTrue);
    },
  );
}

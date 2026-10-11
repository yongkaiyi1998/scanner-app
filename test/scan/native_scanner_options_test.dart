import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String options;
  setUpAll(() {
    // Source-contract checks complement the build; native UI still needs device QA.
    final source = File(
      'android/app/src/main/kotlin/com/example/scanner_app/DocumentScannerChannel.kt',
    ).readAsStringSync();
    final builders = RegExp(
      r'val options = GmsDocumentScannerOptions\.Builder\(\)([\s\S]*?)\.build\(\)',
    ).allMatches(source).toList();
    expect(builders, hasLength(1));
    options = builders.single.group(1)!;
  });

  test('native scanner permits multiple pages with a bounded limit of ten', () {
    final limits = RegExp(r'\.setPageLimit\((\d+)\)').allMatches(options);
    expect(limits, hasLength(1));
    expect(int.parse(limits.single.group(1)!), 10);
  });

  test('multi-page scanner keeps base mode without filters', () {
    expect(
      options,
      contains('.setScannerMode(GmsDocumentScannerOptions.SCANNER_MODE_BASE)'),
    );
    expect(options, isNot(contains('SCANNER_MODE_FULL')));
    expect(options, isNot(contains('SCANNER_MODE_BASE_WITH_FILTER')));
  });

  test('native output stays JPEG-only and gallery setting is unchanged', () {
    expect(
      options,
      contains(
        '.setResultFormats(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)',
      ),
    );
    expect(options, isNot(contains('RESULT_FORMAT_PDF')));
    expect(options, contains('.setGalleryImportAllowed(false)'));
  });
}

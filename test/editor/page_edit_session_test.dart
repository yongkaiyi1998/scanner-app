import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/features/documents/domain/document_page.dart';
import 'package:scanner_app/features/editor/page_edit_session.dart';

void main() {
  const source = DocumentPage(
    id: 'page',
    path: 'owned/source.image',
    width: 6000,
    height: 4000,
  );
  final bounds = PageCrop(left: .25, top: .125, right: .75, bottom: .875);
  test('90, 180, 270 and 360 degrees remain separate from EXIF', () {
    final session = PageEditSession(source);
    for (final rotation in [1, 2, 3, 0]) {
      session.rotate();
      expect(session.page.rotationQuarterTurns, rotation);
      expect(session.page.orientation, PageOrientation.decoderManagedExif);
      expect(session.page.sourcePath, source.sourcePath);
    }
    session.rotate();
    session.reset();
    expect(session.page.rotationQuarterTurns, 0);
    expect(session.page.crop, PageCrop.full);
  });
  for (final size in [
    const Size(300, 200),
    const Size(200, 300),
    const Size(1600, 400),
    const Size(6000, 4000),
  ]) {
    test('normalized crop maps directly to $size', () {
      expect(
        bounds.toRect(size),
        Rect.fromLTRB(
          size.width * .25,
          size.height * .125,
          size.width * .75,
          size.height * .875,
        ),
      );
    });
  }
  for (var turns = 0; turns < 4; turns++) {
    test('crop mapping is reversible at $turns quarter turns', () {
      final session = PageEditSession(
        source.copyWith(rotationQuarterTurns: turns),
      );
      session.crop(bounds.rotated(turns));
      expect(session.page.crop, bounds);
      expect(session.displayedCrop, bounds.rotated(turns));
    });
  }
  test('crop after rotation agrees with rotation after source crop', () {
    final first = PageEditSession(source)
      ..rotate()
      ..crop(bounds.rotated(1));
    final second = PageEditSession(source)
      ..crop(bounds)
      ..rotate();
    expect(first.page.crop, second.page.crop);
    expect(first.displayedCrop, second.displayedCrop);
    expect(first.page.rotationQuarterTurns, second.page.rotationQuarterTurns);
  });
  test(
    're-crop replaces original-source bounds, never crops the previous crop',
    () {
      final session = PageEditSession(source)..crop(bounds);
      final wider = PageCrop(left: .125, top: 0, right: .875, bottom: 1);
      session.crop(wider);
      expect(session.page.crop, wider);
      expect(session.page.sourcePath, source.sourcePath);
      expect(session.page.width, 6000);
      expect(session.page.height, 4000);
    },
  );
  test('successive undo and reset restore metadata without mutating input', () {
    final session = PageEditSession(source)
      ..crop(bounds)
      ..rotate()
      ..reset();
    session.undo();
    expect(session.page.crop, bounds);
    expect(session.page.rotationQuarterTurns, 1);
    session.undo();
    expect(session.page.rotationQuarterTurns, 0);
    session.undo();
    expect(session.page, same(source));
    expect(session.canUndo, isFalse);
    expect(source.crop, PageCrop.full);
    expect(source.rotationQuarterTurns, 0);
  });
  test(
    'reopening applied metadata and Reset restore the original source view',
    () {
      final firstVisit = PageEditSession(source)
        ..rotate()
        ..crop(bounds);
      final secondVisit = PageEditSession(firstVisit.page);
      expect(secondVisit.page.crop, firstVisit.page.crop);
      expect(secondVisit.page.rotationQuarterTurns, 1);
      secondVisit.reset();
      expect(secondVisit.page.crop, PageCrop.full);
      expect(secondVisit.page.rotationQuarterTurns, 0);
    },
  );
  test(
    'invalid, empty, non-finite and outside-source crop bounds are rejected',
    () {
      for (final left in [double.nan, double.infinity, -.1, 1.0]) {
        expect(
          () => PageCrop(left: left, top: 0, right: 1, bottom: 1),
          throwsArgumentError,
        );
      }
      expect(
        () => PageCrop(left: 0, top: 0, right: 1.1, bottom: 1),
        throwsArgumentError,
      );
      expect(
        () => PageCrop(left: 0, top: .5, right: 1, bottom: .5),
        throwsArgumentError,
      );
    },
  );
  test('undo history is bounded to 50 metadata-only operations', () {
    final session = PageEditSession(source);
    for (var i = 0; i < 80; i++) {
      session.rotate();
    }
    for (var i = 0; i < 50; i++) {
      expect(session.canUndo, isTrue);
      session.undo();
    }
    expect(session.canUndo, isFalse);
  });
}

import 'dart:ui';

/// Normalized bounds in the EXIF-oriented, unedited source image.
class PageCrop {
  const PageCrop._(this.left, this.top, this.right, this.bottom);

  factory PageCrop({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) {
    if (![left, top, right, bottom].every((value) => value.isFinite) ||
        left < 0 ||
        top < 0 ||
        right > 1 ||
        bottom > 1 ||
        left >= right ||
        top >= bottom) {
      throw ArgumentError('Crop bounds must be within the source image.');
    }
    return PageCrop._(left, top, right, bottom);
  }

  static const full = PageCrop._(0, 0, 1, 1);
  final double left;
  final double top;
  final double right;
  final double bottom;
  double get width => right - left;
  double get height => bottom - top;

  Rect toRect(Size size) => Rect.fromLTRB(
    left * size.width,
    top * size.height,
    right * size.width,
    bottom * size.height,
  );

  PageCrop rotated(int quarterTurns) {
    var result = this;
    for (var i = 0; i < (quarterTurns % 4 + 4) % 4; i++) {
      result = PageCrop._(
        1 - result.bottom,
        result.left,
        1 - result.top,
        result.right,
      );
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      other is PageCrop &&
      left == other.left &&
      top == other.top &&
      right == other.right &&
      bottom == other.bottom;
  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scanner_app/features/documents/domain/document_page.dart';
import 'document_page_image.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.page});
  final DocumentPage page;
  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _Corner {
  topLeft('top-left', 'Top left'),
  topRight('top-right', 'Top right'),
  bottomLeft('bottom-left', 'Bottom left'),
  bottomRight('bottom-right', 'Bottom right');

  const _Corner(this.keyName, this.label);
  final String keyName;
  final String label;
  bool get isLeft => this == topLeft || this == bottomLeft;
  bool get isTop => this == topLeft || this == topRight;
}

class _CropScreenState extends State<CropScreen> {
  static const _touchSize = 48.0;
  final _canvasKey = GlobalKey();
  late PageCrop _crop;
  late final Widget _sourceImage;
  bool _readable = true;
  _Corner? _activeCorner;
  Offset _grabOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _crop = widget.page.crop.rotated(widget.page.rotationQuarterTurns);
    // Keep the cached bounded image widget unchanged during overlay dragging.
    _sourceImage = DocumentPageImage(
      page: widget.page.copyWith(crop: PageCrop.full),
      onUnreadable: () {
        if (mounted) setState(() => _readable = false);
      },
    );
  }

  Offset _cornerPosition(_Corner corner, Rect imageRect) => Offset(
    imageRect.left +
        (corner.isLeft ? _crop.left : _crop.right) * imageRect.width,
    imageRect.top +
        (corner.isTop ? _crop.top : _crop.bottom) * imageRect.height,
  );

  void _startDrag(_Corner corner, Offset position, Rect imageRect) {
    if (_activeCorner != null) return;
    final canvas = _canvasKey.currentContext!.findRenderObject()! as RenderBox;
    _activeCorner = corner;
    // Preserve the finger's offset within the generous hit target (no jump).
    _grabOffset =
        position - canvas.localToGlobal(_cornerPosition(corner, imageRect));
  }

  void _drag(
    _Corner corner,
    DragUpdateDetails details,
    Rect imageRect,
    Size source,
  ) {
    if (_activeCorner != corner) return;
    final canvas = _canvasKey.currentContext!.findRenderObject()! as RenderBox;
    final point = canvas.globalToLocal(details.globalPosition - _grabOffset);
    final x = (point.dx - imageRect.left) / imageRect.width;
    final y = (point.dy - imageRect.top) / imageRect.height;
    final minWidth = math.min(
      1.0,
      math.max(1 / source.width, _touchSize / imageRect.width),
    );
    final minHeight = math.min(
      1.0,
      math.max(1 / source.height, _touchSize / imageRect.height),
    );
    var left = _crop.left;
    var right = _crop.right;
    var top = _crop.top;
    var bottom = _crop.bottom;
    if (corner.isLeft) {
      right = math.max(right, minWidth);
      left = x.clamp(0.0, right - minWidth);
    } else {
      left = math.min(left, 1 - minWidth);
      right = x.clamp(left + minWidth, 1.0);
    }
    if (corner.isTop) {
      bottom = math.max(bottom, minHeight);
      top = y.clamp(0.0, bottom - minHeight);
    } else {
      top = math.min(top, 1 - minHeight);
      bottom = y.clamp(top + minHeight, 1.0);
    }
    setState(
      () =>
          _crop = PageCrop(left: left, top: top, right: right, bottom: bottom),
    );
  }

  void _endDrag(_Corner corner) {
    if (_activeCorner == corner) _activeCorner = null;
  }

  @override
  Widget build(BuildContext context) {
    final page = widget.page;
    final odd = page.rotationQuarterTurns.isOdd;
    final source = Size(
      (odd ? page.height : page.width).toDouble(),
      (odd ? page.width : page.height).toDouble(),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Adjust crop')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text(
              'Drag the four corner handles. The outlined area will be kept.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(
                    constraints.maxWidth,
                    constraints.maxHeight,
                  );
                  // Leave a handle-radius gutter so full-image corners remain hittable.
                  final fitted = applyBoxFit(
                    BoxFit.contain,
                    source,
                    Size(
                      math.max(1.0, viewport.width - _touchSize),
                      math.max(1.0, viewport.height - _touchSize),
                    ),
                  );
                  final imageRect = Alignment.center.inscribe(
                    fitted.destination,
                    Offset.zero & viewport,
                  );
                  return Stack(
                    key: _canvasKey,
                    fit: StackFit.expand,
                    children: [
                      Positioned.fromRect(
                        rect: imageRect,
                        child: SizedBox.expand(
                          key: const ValueKey('crop-image-bounds'),
                          child: _sourceImage,
                        ),
                      ),
                      IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOutline(_crop, imageRect),
                        ),
                      ),
                      if (_readable)
                        for (final corner in _Corner.values)
                          Positioned(
                            left:
                                _cornerPosition(corner, imageRect).dx -
                                _touchSize / 2,
                            top:
                                _cornerPosition(corner, imageRect).dy -
                                _touchSize / 2,
                            width: _touchSize,
                            height: _touchSize,
                            child: Semantics(
                              label: '${corner.label} crop corner',
                              button: true,
                              child: Listener(
                                key: ValueKey('crop-${corner.keyName}'),
                                behavior: HitTestBehavior.opaque,
                                onPointerDown: (event) => _startDrag(
                                  corner,
                                  event.position,
                                  imageRect,
                                ),
                                onPointerUp: (_) => _endDrag(corner),
                                onPointerCancel: (_) => _endDrag(corner),
                                // Draggable claims corner movement before parent scrolling.
                                child: Draggable<_Corner>(
                                  maxSimultaneousDrags: 1,
                                  feedback: const SizedBox.shrink(),
                                  dragAnchorStrategy: pointerDragAnchorStrategy,
                                  onDragUpdate: (details) =>
                                      _drag(corner, details, imageRect, source),
                                  onDragEnd: (_) => _endDrag(corner),
                                  child: Center(
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 3,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.open_with,
                                        size: 14,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel crop'),
                ),
                FilledButton(
                  onPressed: !_readable
                      ? null
                      : () => Navigator.pop(context, _crop),
                  child: const Text('Confirm crop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CropOutline extends CustomPainter {
  const _CropOutline(this.crop, this.imageRect);
  final PageCrop crop;
  final Rect imageRect;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = crop.toRect(imageRect.size).shift(imageRect.topLeft);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRect(rect);
    canvas.drawPath(outside, Paint()..color = const Color(0x88000000));
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CropOutline oldDelegate) =>
      crop != oldDelegate.crop || imageRect != oldDelegate.imageRect;
}

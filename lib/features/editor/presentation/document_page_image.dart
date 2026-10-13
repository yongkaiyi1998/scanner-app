import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:scanner_app/features/documents/domain/document_page.dart';

/// Bounded cached decode; clipping and rotation never change the source bytes.
class DocumentPageImage extends StatefulWidget {
  const DocumentPageImage({super.key, required this.page, this.onUnreadable});
  final DocumentPage page;
  final VoidCallback? onUnreadable;
  @override
  State<DocumentPageImage> createState() => _DocumentPageImageState();
}

class _DocumentPageImageState extends State<DocumentPageImage> {
  bool _failed = false;
  bool _reportPending = false;
  @override
  void didUpdateWidget(DocumentPageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.sourcePath != widget.page.sourcePath) _failed = false;
  }

  Widget _error(BuildContext context, Object error, StackTrace? stack) {
    if (!_failed && !_reportPending) {
      _reportPending = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportPending = false;
        if (!mounted) return;
        setState(() => _failed = true);
        widget.onUnreadable?.call();
      });
    }
    return const Text(
      'The preview is no longer readable. Please import the image again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return _error(context, StateError('Unreadable preview'), null);
    final page = widget.page;
    final scale = math.min(1.0, 1024 / math.max(page.width, page.height));
    final width = page.width * scale;
    final height = page.height * scale;
    final image = Image.file(
      File(page.sourcePath),
      fit: page.crop == PageCrop.full ? BoxFit.contain : BoxFit.fill,
      cacheWidth: math.max(1, width.round()),
      cacheHeight: math.max(1, height.round()),
      semanticLabel: 'Imported document image',
      errorBuilder: _error,
    );
    if (page.crop == PageCrop.full) {
      return RotatedBox(quarterTurns: page.rotationQuarterTurns, child: image);
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: RotatedBox(
        quarterTurns: page.rotationQuarterTurns,
        child: SizedBox(
          width: width * page.crop.width,
          height: height * page.crop.height,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -width * page.crop.left,
                top: -height * page.crop.top,
                width: width,
                height: height,
                child: image,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:scanner_app/features/documents/domain/document_page.dart';

/// Route-local draft. Only Apply returns this page to the capture controller.
class PageEditSession {
  PageEditSession(DocumentPage page) : _page = page;
  DocumentPage _page;
  final List<DocumentPage> _undo = [];
  DocumentPage get page => _page;
  bool get canUndo => _undo.isNotEmpty;
  PageCrop get displayedCrop => _page.crop.rotated(_page.rotationQuarterTurns);

  void _change(DocumentPage next) {
    if (next.crop == _page.crop &&
        next.rotationQuarterTurns == _page.rotationQuarterTurns) {
      return;
    }
    _undo.add(_page);
    if (_undo.length > 50) _undo.removeAt(0);
    _page = next;
  }

  void rotate() => _change(
    _page.copyWith(rotationQuarterTurns: _page.rotationQuarterTurns + 1),
  );
  void crop(PageCrop displayedBounds) => _change(
    _page.copyWith(crop: displayedBounds.rotated(-_page.rotationQuarterTurns)),
  );
  void reset() =>
      _change(_page.copyWith(crop: PageCrop.full, rotationQuarterTurns: 0));
  void undo() {
    if (canUndo) _page = _undo.removeLast();
  }
}

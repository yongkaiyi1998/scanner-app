import 'package:flutter/material.dart';
import 'package:scanner_app/features/documents/domain/document_page.dart';
import '../page_edit_session.dart';
import '../source_validator.dart';
import 'crop_screen.dart';
import 'document_page_image.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.page,
    required this.pageNumber,
    required this.pageCount,
    this.validateSource = validateEditorSource,
  });
  final DocumentPage page;
  final int pageNumber;
  final int pageCount;
  final Future<void> Function(DocumentPage) validateSource;
  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final PageEditSession _draft;
  bool _checking = true;
  bool _applying = false;
  String? _error;
  int _imageAttempt = 0;
  @override
  void initState() {
    super.initState();
    _draft = PageEditSession(widget.page);
    _checkSource();
  }

  Future<void> _checkSource({bool apply = false}) async {
    setState(() {
      _checking = true;
      _applying = apply;
      _error = null;
    });
    try {
      await widget.validateSource(_draft.page);
      if (!mounted) return;
      if (apply) {
        // Enable route popping only after the source has been revalidated.
        setState(() {
          _checking = false;
          _applying = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, _draft.page);
        });
      } else {
        setState(() {
          _checking = false;
          _imageAttempt++;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _checking = false;
          _applying = false;
          _error = const EditorException(
            EditorFailure.unreadableSource,
          ).message;
        });
      }
    }
  }

  Future<void> _crop() async {
    final bounds = await Navigator.push<PageCrop>(
      context,
      MaterialPageRoute(builder: (_) => CropScreen(page: _draft.page)),
    );
    if (!mounted || bounds == null) return;
    setState(() => _draft.crop(bounds));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !_checking && _error == null;
    return PopScope<DocumentPage>(
      canPop: !_applying,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Edit page ${widget.pageNumber} of ${widget.pageCount}'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_checking)
                const SizedBox(
                  height: 280,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                SizedBox(height: 280, child: Center(child: Text(_error!)))
              else
                SizedBox(
                  height: 280,
                  child: DocumentPageImage(
                    key: ValueKey(_imageAttempt),
                    page: _draft.page,
                    onUnreadable: () {
                      if (mounted) {
                        setState(() {
                          _error = const EditorException(
                            EditorFailure.unreadableSource,
                          ).message;
                        });
                      }
                    },
                  ),
                ),
              if (_error != null)
                TextButton(
                  onPressed: _checking ? null : _checkSource,
                  child: const Text('Retry source'),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: enabled ? () => setState(_draft.rotate) : null,
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('Rotate 90°'),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled ? _crop : null,
                    icon: const Icon(Icons.crop),
                    label: Text(
                      _draft.page.crop == PageCrop.full ? 'Crop' : 'Re-crop',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled && _draft.canUndo
                        ? () => setState(_draft.undo)
                        : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('Undo'),
                  ),
                  OutlinedButton.icon(
                    onPressed: enabled ? () => setState(_draft.reset) : null,
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Apply keeps edits for this session. Cancel or Back discards '
                'this draft. Undo covers up to 50 edits in this editor visit.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  TextButton(
                    onPressed: _applying ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: enabled ? () => _checkSource(apply: true) : null,
                    child: const Text('Apply'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

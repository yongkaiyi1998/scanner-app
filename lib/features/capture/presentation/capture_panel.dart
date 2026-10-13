import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/scan/document_scanner.dart';
import 'package:scanner_app/features/editor/presentation/editor_screen.dart';
import 'package:scanner_app/features/editor/presentation/document_page_image.dart';

class CapturePanel extends ConsumerStatefulWidget {
  const CapturePanel({super.key});

  @override
  ConsumerState<CapturePanel> createState() => _CapturePanelState();
}

class _CapturePanelState extends ConsumerState<CapturePanel> {
  int _pageIndex = 0;
  CapturePreview? _previousPreview;

  Future<void> _edit(DocumentPage page, int pageCount) async {
    final edited = await Navigator.push<DocumentPage>(
      context,
      MaterialPageRoute(
        builder: (_) => EditorScreen(
          page: page,
          pageNumber: _pageIndex + 1,
          pageCount: pageCount,
        ),
      ),
    );
    if (!mounted || edited == null) return;
    final applied = ref
        .read(captureControllerProvider.notifier)
        .applyPageEdit(page, edited);
    if (applied) {
      setState(
        () => _previousPreview = ref.read(captureControllerProvider).value,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The preview changed. Please reopen the page editor.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);
    final preview = state.value;
    if (!identical(preview, _previousPreview)) {
      _pageIndex = 0;
      _previousPreview = preview;
    }
    final photo = preview?.pages[_pageIndex];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photo != null) ...[
          Text(
            preview!.isScan
                ? 'Scanned document preview'
                : 'Imported image preview',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SizedBox(height: 280, child: DocumentPageImage(page: photo)),
          const Text('This preview has not been saved.'),
          if (preview.pages.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: state.isLoading || _pageIndex == 0
                      ? null
                      : () => setState(() => _pageIndex--),
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page ${_pageIndex + 1} of ${preview.pages.length}'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed:
                      state.isLoading || _pageIndex == preview.pages.length - 1
                      ? null
                      : () => setState(() => _pageIndex++),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          OutlinedButton.icon(
            onPressed: state.isLoading
                ? null
                : () => _edit(photo, preview.pages.length),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit selected page'),
          ),
          TextButton(
            onPressed: state.isLoading ? null : controller.discard,
            child: const Text('Close preview'),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: state.isLoading ? null : controller.scanDocument,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan Document'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: state.isLoading ? null : controller.importPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Import from Gallery'),
          ),
        ],
        if (state.isLoading) ...[
          const SizedBox(height: 12),
          const CircularProgressIndicator(),
          const Text('Preparing image…'),
        ],
        if (state.hasError) ...[
          const SizedBox(height: 12),
          Text(
            state.error is PhotoImportException
                ? (state.error as PhotoImportException).message
                : state.error is ScanException
                ? (state.error as ScanException).message
                : 'The image could not be prepared. Please try again.',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

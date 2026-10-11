import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scanner_app/features/capture/capture_controller.dart';
import 'package:scanner_app/features/capture/photo_importer.dart';

class CapturePanel extends ConsumerWidget {
  const CapturePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(captureControllerProvider);
    final controller = ref.read(captureControllerProvider.notifier);
    final photo = state.value;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (photo != null) ...[
          Text(
            'Imported image preview',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: Image.file(
              File(photo.path),
              fit: BoxFit.contain,
              cacheWidth: math.max(
                1,
                (photo.width *
                        math.min(
                          1.0,
                          1024 / math.max(photo.width, photo.height),
                        ))
                    .round(),
              ),
              cacheHeight: math.max(
                1,
                (photo.height *
                        math.min(
                          1.0,
                          1024 / math.max(photo.width, photo.height),
                        ))
                    .round(),
              ),
              semanticLabel: 'Imported document image',
              errorBuilder: (context, error, stack) => const Text(
                'The preview is no longer readable. Please import the image again.',
              ),
            ),
          ),
          const Text('This preview has not been saved.'),
          TextButton(
            onPressed: state.isLoading ? null : controller.discard,
            child: const Text('Close preview'),
          ),
        ] else ...[
          FilledButton.icon(
            onPressed: state.isLoading
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Document scanning is not available yet. You can import an image from your gallery.',
                      ),
                    ),
                  ),
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
                : 'The image could not be imported. Please try again.',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';

class EditorPlaceholderPage extends StatelessWidget {
  const EditorPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PlaceholderScaffold(
      title: 'Editor',
      message: 'Document editing will be available here.',
    );
  }
}

class _PlaceholderScaffold extends StatelessWidget {
  const _PlaceholderScaffold({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(message)),
    );
  }
}

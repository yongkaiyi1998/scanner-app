import 'package:flutter/material.dart';

class HistoryPlaceholderPage extends StatelessWidget {
  const HistoryPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recent documents')),
      body: const Center(
        child: Text('Saved documents will appear here.'),
      ),
    );
  }
}

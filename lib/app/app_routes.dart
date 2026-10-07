import 'package:flutter/material.dart';
import 'package:scanner_app/features/documents/presentation/home_page.dart';
import 'package:scanner_app/features/editor/presentation/editor_placeholder_page.dart';
import 'package:scanner_app/features/history/presentation/history_placeholder_page.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const editor = '/editor';
  static const history = '/history';

  static Route<void> generate(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      home => const HomePage(),
      editor => const EditorPlaceholderPage(),
      history => const HistoryPlaceholderPage(),
      _ => const HomePage(),
    };

    return MaterialPageRoute<void>(
      builder: (context) => page,
      settings: settings,
    );
  }
}

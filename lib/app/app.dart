import 'package:flutter/material.dart';
import 'package:scanner_app/app/app_routes.dart';
import 'package:scanner_app/app/app_theme.dart';

class ScannerApp extends StatelessWidget {
  const ScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Scanner',
      theme: AppTheme.light,
      initialRoute: AppRoutes.home,
      onGenerateRoute: AppRoutes.generate,
    );
  }
}

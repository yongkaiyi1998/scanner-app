import 'package:scanner_app/features/capture/photo_importer.dart';
import 'package:scanner_app/features/scan/document_scanner.dart';

class FakeDocumentScanner implements DocumentScanner {
  List<ImportedPhoto>? pages;
  ScanException? failure;
  int calls = 0;
  @override
  Future<List<ImportedPhoto>?> scan() async {
    calls++;
    if (failure != null) throw failure!;
    return pages;
  }
}

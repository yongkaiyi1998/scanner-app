import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_app/app/app.dart';

void main() {
  testWidgets('shows the Home placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ScannerApp());

    expect(find.text('Document Scanner'), findsOneWidget);
    expect(find.text('Your documents will appear here'), findsOneWidget);
  });

  testWidgets('opens the History placeholder', (WidgetTester tester) async {
    await tester.pumpWidget(const ScannerApp());

    await tester.tap(find.text('View recent documents'));
    await tester.pumpAndSettle();

    expect(find.text('Recent documents'), findsOneWidget);
    expect(find.text('Saved documents will appear here.'), findsOneWidget);
  });
}

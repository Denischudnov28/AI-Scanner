import 'package:ai_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI Scanner opens with its app title', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    expect(find.text('AI Scanner'), findsOneWidget);
  });
}

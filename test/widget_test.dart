import 'package:ai_scanner/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI Scanner opens with its app title', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    expect(find.text('AI Scanner'), findsOneWidget);
  });

  testWidgets('Settings can be opened from the home screen', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pumpAndSettle();
    expect(find.text('Настройки и безопасность'), findsOneWidget);
    expect(find.text('Локальная обработка'), findsOneWidget);
  });
}

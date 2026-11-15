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

  testWidgets('A named document can be created', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await tester.tap(find.byTooltip('Создать документ'));
    await tester.pumpAndSettle();
    expect(find.text('Новый документ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Договор аренды');
    await tester.tap(find.text('Создать'));
    await tester.pumpAndSettle();
    expect(find.text('Новый документ'), findsNothing);
  });
}

import 'package:ai_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AI Scanner opens with its app title', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    expect(find.text('AI Scanner'), findsOneWidget);
  });

  testWidgets('Settings can be opened from the home screen', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Настройки и безопасность'), findsOneWidget);
    expect(find.text('Локальная обработка'), findsOneWidget);
  });


  testWidgets('Document library can be opened', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await tester.tap(find.byTooltip('Создать документ'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField).last, 'Договор аренды');
    await tester.tap(find.text('Создать'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Мои документы'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Мои документы'), findsOneWidget);
    expect(find.text('Договор аренды'), findsOneWidget);
    expect(find.text('0 страниц'), findsOneWidget);
  });

  testWidgets('A named document can be created', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await tester.tap(find.byTooltip('Создать документ'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Новый документ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Договор аренды');
    await tester.tap(find.text('Создать'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Новый документ'), findsNothing);
  });
}

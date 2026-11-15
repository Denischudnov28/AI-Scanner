import 'package:ai_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> createDocument(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Создать документ'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byType(TextField).last, name);
  await tester.tap(find.text('Создать'));
  await tester.pump(const Duration(milliseconds: 300));
}

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

  testWidgets('Document library shows a newly created document', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await createDocument(tester, 'Договор аренды');

    await tester.tap(find.byTooltip('Мои документы'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Мои документы'), findsOneWidget);
    expect(find.text('Договор аренды'), findsOneWidget);
    expect(find.text('0 страниц'), findsOneWidget);
  });

  testWidgets('A named document can be created', (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await createDocument(tester, 'Договор аренды');
    expect(find.text('Новый документ'), findsNothing);
  });

  testWidgets('A document can be renamed from the document library',
      (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await createDocument(tester, 'Старое название');
    await tester.tap(find.byTooltip('Мои документы'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Действия с документом'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Переименовать'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField).last, 'Новое название');
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Новое название'), findsOneWidget);
    expect(find.text('Старое название'), findsNothing);
  });

  testWidgets('Deleting a document requires confirmation and removes it',
      (tester) async {
    await tester.pumpWidget(const AiScannerApp());
    await createDocument(tester, 'Документ для удаления');
    await tester.tap(find.byTooltip('Мои документы'));
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byTooltip('Действия с документом'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Удалить документ'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Удалить документ?'), findsOneWidget);
    await tester.tap(find.text('Удалить').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Документ для удаления'), findsNothing);
    expect(find.text('Документов пока нет'), findsOneWidget);
  });
}

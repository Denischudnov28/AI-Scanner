import 'package:ai_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(const AiScannerApp());
}

Future<void> createDocument(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('Создать документ'));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.enterText(find.byType(TextField).last, name);
  await tester.tap(find.text('Создать'));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('AI Scanner opens with its app title', (tester) async {
    await pumpApp(tester);
    expect(find.text('AI Scanner'), findsOneWidget);
  });

  testWidgets('Settings can be opened from the home screen', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Настройки'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Настройки и безопасность'), findsOneWidget);
    expect(find.text('Локальная обработка'), findsOneWidget);
  });

  testWidgets('Document library shows a newly created document', (tester) async {
    await pumpApp(tester);
    await createDocument(tester, 'Договор аренды');

    await tester.tap(find.byTooltip('Мои документы'));
    // Start the route transition, then advance time until the sheet is fully visible.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Мои документы'), findsOneWidget);
    expect(find.text('Договор аренды'), findsOneWidget);
    expect(find.text('0 страниц'), findsOneWidget);
  });

  testWidgets('A named document can be created', (tester) async {
    await pumpApp(tester);
    await createDocument(tester, 'Договор аренды');
    expect(find.text('Новый документ'), findsNothing);
  });

  testWidgets('A document can be renamed from the document library',
      (tester) async {
    await pumpApp(tester);
    await createDocument(tester, 'Старое название');
    await tester.tap(find.byTooltip('Мои документы'));
    // Start the route transition, then advance time until the sheet is fully visible.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final renameButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Переименовать документ',
    );
    await tester.ensureVisible(renameButton);
    await tester.pump();
    await tester.tap(renameButton);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).last, 'Новое название');
    await tester.tap(find.text('Сохранить'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Новое название'), findsOneWidget);
    expect(find.text('Старое название'), findsNothing);
  });

  testWidgets('Deleting a document requires confirmation and removes it',
      (tester) async {
    await pumpApp(tester);
    await createDocument(tester, 'Документ для удаления');
    await tester.tap(find.byTooltip('Мои документы'));
    // Start the route transition, then advance time until the sheet is fully visible.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final deleteButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Удалить документ',
    );
    await tester.ensureVisible(deleteButton);
    await tester.pump();
    await tester.tap(deleteButton);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Удалить документ?'), findsOneWidget);
    await tester.tap(find.text('Удалить').last);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Документ для удаления'), findsNothing);
    expect(find.text('Документов пока нет'), findsOneWidget);
  });
}

import 'package:ai_scanner/converter_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('converter shows supported local conversion actions',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ConverterScreen()),
    );

    expect(find.text('Конвертер'), findsOneWidget);
    expect(find.text('Изображения → PDF'), findsOneWidget);
    expect(find.text('PDF → JPG'), findsOneWidget);
    expect(find.textContaining('прямо на устройстве'), findsOneWidget);
  });
}

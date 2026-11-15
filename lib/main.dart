import 'dart:io';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

void main() => runApp(const AiScannerApp());

class AiScannerApp extends StatelessWidget {
  const AiScannerApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI Scanner', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457D6)), useMaterial3: true),
    home: const ScannerHome(),
  );
}

class ScannerHome extends StatefulWidget {
  const ScannerHome({super.key});
  @override
  State<ScannerHome> createState() => _ScannerHomeState();
}

class _ScannerHomeState extends State<ScannerHome> {
  final _picker = ImagePicker();
  final List<File> _pages = [];
  bool _busy = false;

  Future<void> _addPage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 92);
      if (image == null || !mounted) return;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/scans');
      await folder.create(recursive: true);
      final target = File('${folder.path}/page_${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(image.path).copy(target.path);
      if (mounted) setState(() => _pages.add(target));
    } catch (e) { _message('Не удалось добавить страницу: $e'); }
  }

  Future<void> _exportPdf() async {
    if (_pages.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final doc = pw.Document();
      for (final file in _pages) {
        final bytes = await file.readAsBytes();
        final image = pw.MemoryImage(bytes);
        doc.addPage(pw.Page(build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain))));
      }
      final dir = await getTemporaryDirectory();
      final out = File('${dir.path}/AI_Scanner_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await out.writeAsBytes(await doc.save());
      await Share.shareXFiles([XFile(out.path)], text: 'Документ из AI Scanner');
    } catch (e) { _message('Не удалось создать PDF: $e'); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  void _message(String value) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value))); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Scanner'), centerTitle: true),
    body: _pages.isEmpty
      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.document_scanner_outlined, size: 72), SizedBox(height: 12), Text('Отсканируйте или добавьте документ'), SizedBox(height: 6), Text('Страницы хранятся локально на устройстве')]))
      : GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12), itemCount: _pages.length, itemBuilder: (context, i) => Stack(fit: StackFit.expand, children: [ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_pages[i], fit: BoxFit.cover)), Positioned(left: 6, top: 6, child: CircleAvatar(radius: 14, child: Text('${i + 1}'))), Positioned(right: 4, top: 4, child: IconButton.filledTonal(onPressed: () => setState(() => _pages.removeAt(i)), icon: const Icon(Icons.close, size: 18))) ])),
    bottomNavigationBar: SafeArea(child: Padding(padding: const EdgeInsets.all(12), child: Column(mainAxisSize: MainAxisSize.min, children: [Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () => _addPage(ImageSource.camera), icon: const Icon(Icons.camera_alt), label: const Text('Камера'))), const SizedBox(width: 10), Expanded(child: OutlinedButton.icon(onPressed: () => _addPage(ImageSource.gallery), icon: const Icon(Icons.photo_library), label: const Text('Галерея')))]), const SizedBox(height: 8), SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy || _pages.isEmpty ? null : _exportPdf, icon: const Icon(Icons.picture_as_pdf), label: Text(_busy ? 'Создание PDF…' : 'Экспорт в PDF (${_pages.length})')))]))),
  );
}

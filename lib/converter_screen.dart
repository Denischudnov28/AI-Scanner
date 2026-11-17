import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as px;
import 'package:share_plus/share_plus.dart';

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  static const int _maxImageCount = 30;
  static const int _maxSingleImageBytes = 20 * 1024 * 1024;
  static const int _maxTotalImageBytes = 80 * 1024 * 1024;
  static const int _maxPdfBytes = 100 * 1024 * 1024;

  bool _busy = false;
  String? _status;

  Future<void> _run(Future<void> Function() operation, String label) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = label;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось выполнить конвертацию: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
        });
      }
    }
  }

  void _showLimitError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<int> _fileLength(PlatformFile file) async {
    final length = file.lengthSync() ?? await file.length();
    if (length == null) {
      throw Exception('Не удалось определить размер файла ${file.name}.');
    }
    return length;
  }

  void _showPickerError(Object error) {
    _showLimitError('Не удалось открыть файл: $error');
  }

  Future<Directory> _temporaryDirectory() async {
    final directory = await getTemporaryDirectory();
    final output = Directory('${directory.path}/ai_scanner_converter');
    await output.create(recursive: true);
    return output;
  }

  Future<void> _shareOutput(List<File> files, String message) async {
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        files: files.map((file) => XFile(file.path)).toList(),
        text: message,
      ),
    );
  }

  Future<void> _imagesToPdf() async {
    late final List<PlatformFile> selection;
    try {
      selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
    } catch (error) {
      _showPickerError(error);
      return;
    }
    if (selection.isEmpty) return;
    if (selection.length > _maxImageCount) {
      _showLimitError('Можно выбрать не более $_maxImageCount изображений за раз.');
      return;
    }

    final imageSizes = <int>[];
    var totalImageBytes = 0;
    try {
      for (final file in selection) {
        final size = await _fileLength(file);
        if (size > _maxSingleImageBytes) {
          _showLimitError('Файл ${file.name} превышает 20 МБ.');
          return;
        }
        totalImageBytes += size;
        if (totalImageBytes > _maxTotalImageBytes) {
          _showLimitError('Общий размер изображений не должен превышать 80 МБ.');
          return;
        }
        imageSizes.add(size);
      }
    } catch (error) {
      _showPickerError(error);
      return;
    }

    await _run(() async {
      final document = pw.Document();
      var pageCount = 0;
      for (var index = 0; index < selection.length; index++) {
        final selectedFile = selection[index];
        final bytes = await selectedFile.readAsBytes();
        if (bytes.length != imageSizes[index]) {
          throw Exception('Файл ${selectedFile.name} изменился во время чтения.');
        }
        if (bytes.isEmpty) {
          throw Exception('Не удалось прочитать файл ${selectedFile.name}.');
        }
        final image = pw.MemoryImage(bytes);
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (_) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
        pageCount++;
      }
      if (pageCount == 0) {
        throw Exception('Не выбраны изображения для конвертации.');
      }
      final outputDirectory = await _temporaryDirectory();
      final output = File(
        '${outputDirectory.path}/images_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      try {
        await output.writeAsBytes(await document.save(), flush: true);
        await _shareOutput([output], 'PDF создан локально в AI Scanner');
      } finally {
        try {
          if (await output.exists()) await output.delete();
        } catch (_) {
          // Best-effort cleanup must not hide the original conversion error.
        }
      }
    }, 'Создание PDF…');
  }

  Future<void> _pdfToImages() async {
    late final PlatformFile? selected;
    try {
      selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
    } catch (error) {
      _showPickerError(error);
      return;
    }
    if (selected == null) return;
    final selectedPdf = selected;

    late final int selectedSize;
    try {
      selectedSize = await _fileLength(selectedPdf);
    } catch (error) {
      _showPickerError(error);
      return;
    }
    if (selectedSize > _maxPdfBytes) {
      _showLimitError('Размер PDF не должен превышать 100 МБ.');
      return;
    }

    await _run(() async {
      final bytes = await selectedPdf.readAsBytes();
      if (bytes.length != selectedSize) {
        throw Exception('PDF-файл изменился во время чтения.');
      }
      if (bytes.isEmpty) {
        throw Exception('Не удалось прочитать PDF-файл.');
      }
      final document = await px.PdfDocument.openData(bytes);
      final outputFiles = <File>[];
      try {
        if (document.pagesCount > 100) {
          throw Exception('Для одной операции поддерживается до 100 страниц.');
        }
        final outputDirectory = await _temporaryDirectory();
        final rawBaseName = selectedPdf.name.replaceFirst(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        );
        final baseName = rawBaseName
            .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
            .replaceAll(RegExp(r'[. ]+$'), '')
            .trim();
        final safeBaseName = baseName.isEmpty ? 'document' : baseName;
        final operationId = DateTime.now().microsecondsSinceEpoch;
        for (var pageNumber = 1; pageNumber <= document.pagesCount; pageNumber++) {
          final page = await document.getPage(pageNumber);
          try {
            final longestSide = math.max(page.width, page.height);
            final scale = math.min(2.0, 2400.0 / longestSide);
            final rendered = await page.render(
              width: math.max(1.0, page.width * scale),
              height: math.max(1.0, page.height * scale),
              format: px.PdfPageImageFormat.jpeg,
              backgroundColor: '#FFFFFF',
            );
            if (rendered == null || rendered.bytes.isEmpty) {
              throw Exception('Не удалось обработать страницу $pageNumber.');
            }
            final output = File(
              '${outputDirectory.path}/${safeBaseName}_${operationId}_page_$pageNumber.jpg',
            );
            await output.writeAsBytes(rendered.bytes, flush: true);
            outputFiles.add(output);
          } finally {
            await page.close();
          }
        }
        await _shareOutput(outputFiles, 'Страницы PDF преобразованы в JPG');
      } finally {
        try {
          await document.close();
        } finally {
          for (final file in outputFiles) {
            try {
              if (await file.exists()) await file.delete();
            } catch (_) {
              // Best-effort cleanup must not hide the original conversion error.
            }
          }
        }
      }
    }, 'Преобразование PDF в изображения…');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FA),
      appBar: AppBar(
        title: const Text('Конвертер'),
        backgroundColor: const Color(0xFFF3F5FA),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1B356B), Color(0xFF102653)],
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 34),
                SizedBox(height: 12),
                Text(
                  'Конвертируйте документы',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Файлы обрабатываются прямо на устройстве.',
                  style: TextStyle(color: Color(0xFFD7E1F5), fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ConverterAction(
            icon: Icons.picture_as_pdf_outlined,
            title: 'Изображения → PDF',
            subtitle: 'Объединить JPG и PNG в один PDF-файл',
            onTap: _busy ? null : _imagesToPdf,
          ),
          const SizedBox(height: 12),
          _ConverterAction(
            icon: Icons.image_outlined,
            title: 'PDF → JPG',
            subtitle: 'Преобразовать страницы PDF в изображения',
            onTap: _busy ? null : _pdfToImages,
          ),
          const SizedBox(height: 18),
          if (_busy)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Text(_status ?? 'Обработка…')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Результат откроется в меню «Поделиться». Там можно сохранить файл в приложение «Файлы» или отправить его.',
            style: TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ConverterAction extends StatelessWidget {
  const _ConverterAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        leading: CircleAvatar(
          radius: 25,
          backgroundColor: const Color(0xFFE8EEFC),
          child: Icon(icon, color: const Color(0xFF2457D6)),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

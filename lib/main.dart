import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_ocr/flutter_native_ocr.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'local_vault.dart';

void main() => runApp(const AiScannerApp());

class AiScannerApp extends StatelessWidget {
  const AiScannerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AI Scanner',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2457D6)),
          useMaterial3: true,
        ),
        home: const ScannerHome(),
      );
}

class ScannerHome extends StatefulWidget {
  const ScannerHome({super.key});

  @override
  State<ScannerHome> createState() => _ScannerHomeState();
}

class _ScannerHomeState extends State<ScannerHome> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  final _ocr = FlutterNativeOcr();
  final _vault = LocalVault();
  final _auth = LocalAuthentication();
  final List<File> _pages = [];
  bool _vaultReady = false;
  String? _vaultError;
  bool _busy = false;
  String? _busyLabel;
  bool _reauthenticateOnResume = false;
  File? _exportedPdf;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeVault();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _vaultReady) {
      _reauthenticateOnResume = true;
      setState(() => _vaultReady = false);
    } else if (state == AppLifecycleState.resumed && _reauthenticateOnResume) {
      _reauthenticateOnResume = false;
      _unlockVault();
    }
  }

  Future<void> _initializeVault() async {
    try {
      await _vault.initialize();
      await _unlockVault();
    } catch (_) {
      if (mounted) {
        setState(() => _vaultError = 'Не удалось открыть защищённое хранилище.');
      }
    }
  }

  Future<void> _unlockVault() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Подтвердите личность для доступа к документам',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      setState(() {
        _vaultReady = authenticated;
        _vaultError = authenticated ? null : 'Доступ не подтверждён.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _vaultReady = false;
          _vaultError = 'Не удалось выполнить биометрическую проверку. Проверьте настройки Face ID или код-пароль устройства.';
        });
      }
    }
  }

  Future<Uint8List> _readPage(File file) async {
    return _vault.decrypt(await file.readAsBytes());
  }

  Future<void> _addPage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 92);
      if (image == null || !mounted) return;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/scans');
      await folder.create(recursive: true);
      final target = File(
        '${folder.path}/page_${DateTime.now().microsecondsSinceEpoch}.aiscan',
      );
      final clearBytes = await File(image.path).readAsBytes();
      await target.writeAsBytes(await _vault.encrypt(clearBytes), flush: true);
      if (mounted) setState(() => _pages.add(target));
    } catch (e) {
      _message('Не удалось добавить страницу: $e');
    }
  }

  Future<void> _removePage(int index) async {
    if (_busy || index < 0 || index >= _pages.length) return;
    final file = _pages[index];
    try {
      if (await file.exists()) await file.delete();
      if (mounted) setState(() => _pages.removeAt(index));
    } catch (e) {
      _message('Не удалось удалить файл страницы: $e');
    }
  }

  Future<void> _recognizePage(File file) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Распознавание текста…';
    });
    try {
      final tempDir = await getTemporaryDirectory();
      final clearFile = File(
        '${tempDir.path}/ai_scanner_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
      );
      final clearBytes = await _readPage(file);
      await clearFile.writeAsBytes(clearBytes, flush: true);
      String text;
      try {
        text = await _ocr.recognizeText(clearFile.path);
      } finally {
        if (await clearFile.exists()) await clearFile.delete();
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Распознанный текст'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                text.trim().isEmpty ? 'Текст на странице не найден.' : text,
              ),
            ),
          ),
          actions: [
            if (text.trim().isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: text));
                  Navigator.pop(dialogContext);
                  _message('Текст скопирован');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Копировать'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (e) {
      _message('Не удалось распознать текст: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  Future<void> _exportPdf() async {
    if (_pages.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _busyLabel = 'Создание PDF…';
    });
    try {
      final doc = pw.Document();
      for (final file in _pages) {
        final bytes = await _readPage(file);
        final image = pw.MemoryImage(bytes);
        doc.addPage(
          pw.Page(
            build: (_) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
      }
      final dir = await getTemporaryDirectory();
      final out = File(
        '${dir.path}/AI_Scanner_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await out.writeAsBytes(await doc.save());
      _exportedPdf = out;
      await Share.shareXFiles(
        [XFile(out.path)],
        text: 'Документ из AI Scanner',
      );
    } catch (e) {
      _message('Не удалось создать PDF: $e');
    } finally {
      final exported = _exportedPdf;
      _exportedPdf = null;
      if (exported != null && await exported.exists()) {
        await exported.delete();
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
    }
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value)),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('AI Scanner'),
          centerTitle: true,
        ),
        body: !_vaultReady
            ? Center(
                child: _vaultError == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _vaultError ?? 'Защищённое хранилище заблокировано.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _unlockVault,
                              icon: const Icon(Icons.lock_open),
                              label: const Text('Повторить разблокировку'),
                            ),
                          ],
                        ),
                      ),
              )
            : _pages.isEmpty
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.document_scanner_outlined, size: 72),
                    SizedBox(height: 12),
                    Text('Отсканируйте или добавьте документ'),
                    SizedBox(height: 6),
                    Text('Обработка выполняется на устройстве'),
                  ],
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: _pages.length,
                itemBuilder: (context, i) => Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: FutureBuilder<Uint8List>(
                        future: _readPage(_pages[i]),
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return const Center(
                              child: Icon(Icons.broken_image_outlined),
                            );
                          }
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          return Image.memory(
                            snapshot.data!,
                            fit: BoxFit.cover,
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: CircleAvatar(
                        radius: 14,
                        child: Text('${i + 1}'),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: IconButton.filledTonal(
                        tooltip: 'Удалить страницу',
                        onPressed: _busy
                            ? null
                            : () => _removePage(i),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                    Positioned(
                      left: 4,
                      right: 4,
                      bottom: 4,
                      child: FilledButton.tonalIcon(
                        onPressed:
                            _busy ? null : () => _recognizePage(_pages[i]),
                        icon: const Icon(Icons.text_snippet_outlined),
                        label: const Text('Распознать текст'),
                      ),
                    ),
                  ],
                ),
              ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || !_vaultReady
                            ? null
                            : () => _addPage(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Камера'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || !_vaultReady
                            ? null
                            : () => _addPage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library),
                        label: const Text('Галерея'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _busy || !_vaultReady || _pages.isEmpty ? null : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: Text(
                      _busy
                          ? (_busyLabel ?? 'Подождите…')
                          : 'Экспорт в PDF (${_pages.length})',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_ocr/flutter_native_ocr.dart';
import 'package:document_scan/document_scan.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'local_vault.dart';
import 'vault_file_store.dart';

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
  final _fileStore = VaultFileStore();
  final List<File> _pages = [];
  bool _vaultReady = false;
  String? _vaultError;
  bool _busy = false;
  String? _busyLabel;
  bool _reauthenticateOnResume = false;
  bool _appObscured = false;

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
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (mounted) setState(() => _appObscured = true);
      if (state == AppLifecycleState.paused && _vaultReady) {
        _reauthenticateOnResume = true;
        _vault.lock();
        setState(() {
          _vaultReady = false;
          _pages.clear();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_reauthenticateOnResume) {
        _reauthenticateOnResume = false;
        _unlockVault();
      } else if (mounted) {
        setState(() => _appObscured = false);
      }
    }
  }

  Future<void> _initializeVault() async {
    try {
      await _cleanupTemporaryFiles();
      await _unlockVault();
    } catch (_) {
      if (mounted) {
        setState(() => _vaultError = 'Не удалось открыть защищённое хранилище.');
      }
    }
  }

  Future<void> _unlockVault() async {
    try {
      // Reading the AES key from secure storage itself invokes Face ID /
      // Touch ID / device-credential authentication at the OS level.
      await _vault.initialize();
      if (!mounted) return;
      final appDir = await getApplicationDocumentsDirectory();
      final folder = Directory('${appDir.path}/scans');
      // Ignore incomplete writes and remove abandoned staging files after a
      // crash; only fully renamed .aiscan files are visible to the app.
      await _fileStore.cleanupPendingFiles(folder);
      final savedPages = await _fileStore.listPages(folder);
      if (!mounted) return;
      setState(() {
        _vaultReady = true;
        _appObscured = false;
        _vaultError = null;
        _pages
          ..clear()
          ..addAll(savedPages);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _vaultReady = false;
          _appObscured = false;
          _vaultError =
              'Не удалось разблокировать хранилище. Подтвердите Face ID, биометрию или код устройства и повторите попытку.';
        });
      }
    }
  }

  Future<void> _cleanupTemporaryFiles() async {
    try {
      final directory = await getTemporaryDirectory();
      if (!await directory.exists()) return;
      await for (final entity in directory.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isEmpty
              ? ''
              : entity.uri.pathSegments.last;
          if (name.startsWith('ai_scanner_ocr_') ||
              name.startsWith('AI_Scanner_')) {
            try {
              await entity.delete();
            } on FileSystemException {
              // A temporary file may already have been removed by the OS.
            }
          }
        }
      }
    } on FileSystemException {
      // Startup cleanup is best-effort and must not block vault access.
    }
  }

  Future<Uint8List> _readPage(File file) async {
    return _vault.decrypt(await file.readAsBytes());
  }

  Future<void> _addPage(ImageSource source) async {
    if (_busy || !_vaultReady) return;
    XFile? pickedImage;
    setState(() {
      _busy = true;
      _busyLabel = 'Добавление страницы…';
    });
    try {
      pickedImage = await _picker.pickImage(source: source, imageQuality: 92);
      if (pickedImage == null || !mounted) return;
      final originalBytes = await File(pickedImage.path).readAsBytes();
      // Detect the page edges and correct perspective locally. If detection
      // cannot find a page, keep the original photo rather than losing it.
      Uint8List clearBytes = originalBytes;
      try {
        final scanned = await DocumentScanner().scan(
          ScanInput.file(pickedImage.path),
        );
        if (scanned != null && scanned.bytes.isNotEmpty) {
          clearBytes = scanned.bytes;
        }
      } catch (_) {
        _message('Не удалось автоматически выровнять документ. Сохранено исходное фото.');
      }
      final encryptedBytes = await _vault.encrypt(clearBytes);
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/scans');
      await folder.create(recursive: true);
      final target = await _fileStore.saveEncryptedPage(
        folder,
        encryptedBytes,
      );
      if (mounted) setState(() => _pages.add(target));
    } catch (e) {
      _message('Не удалось добавить страницу: $e');
    } finally {
      // image_picker creates a temporary plaintext copy. Remove it as soon as
      // the encrypted vault copy has been written (or the import has failed).
      if (pickedImage != null) {
        try {
          final temporaryImage = File(pickedImage.path);
          if (await temporaryImage.exists()) await temporaryImage.delete();
        } on FileSystemException {
          // The OS may already have cleaned the picker cache.
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = null;
        });
      }
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
      String text;
      try {
        // Keep the decrypted OCR copy inside the cleanup scope, including
        // failures while writing the temporary file or starting the OCR engine.
        await clearFile.writeAsBytes(clearBytes, flush: true);
        if (Platform.isAndroid) {
          text = await const MethodChannel('ai_scanner/russian_ocr')
                  .invokeMethod<String>(
                    'recognizeRussian',
                    <String, String>{'imagePath': clearFile.path},
                  ) ??
              '';
        } else {
          // Apple Vision remains the native, on-device OCR engine on iOS.
          text = await _ocr.recognizeText(clearFile.path);
        }
      } finally {
        try {
          if (await clearFile.exists()) await clearFile.delete();
        } on FileSystemException {
          // Best-effort cleanup; stale files are retried on next launch.
        }
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
    File? exported;
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
      exported = File(
        '${dir.path}/AI_Scanner_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
      await exported.writeAsBytes(await doc.save(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(exported.path)],
          text: 'Документ из AI Scanner',
        ),
      );
    } catch (e) {
      _message('Не удалось создать PDF: $e');
    } finally {
      // Keep the temporary export in scope from creation onward so even a
      // partially written PDF is cleaned up if writing or sharing fails.
      if (exported != null) {
        try {
          if (await exported.exists()) await exported.delete();
        } on FileSystemException {
          // Best-effort cleanup; stale exports are retried on next launch.
        }
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
        backgroundColor: const Color(0xFFF3F5FA),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF3F5FA),
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 82,
          title: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF192F61),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.document_scanner_outlined,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'AI Scanner',
                      style: TextStyle(
                        color: Color(0xFF101828),
                        fontWeight: FontWeight.w700,
                        fontSize: 20,
                      ),
                    ),
                    Text(
                      'Умный сканер документов',
                      style: TextStyle(
                        color: Color(0xFF667085),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (_vaultReady)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDF5E7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_user, color: Color(0xFF168447), size: 16),
                      SizedBox(width: 5),
                      Text(
                        'Защищено',
                        style: TextStyle(
                          color: Color(0xFF168447),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: _appObscured
            ? const ColoredBox(
                color: Color(0xFF101828),
                child: Center(
                  child: Icon(Icons.lock_outline, color: Colors.white, size: 56),
                ),
              )
            : !_vaultReady
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
                : CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1B356B), Color(0xFF102653)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Align(
                                  alignment: Alignment.topRight,
                                  child: Icon(
                                    Icons.lock_outline,
                                    color: Color(0xFFDCE7FF),
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Все документы в одном месте',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 27,
                                    height: 1.16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'Сканируйте, сохраняйте и управляйте документами. Ваши файлы остаются на устройстве.',
                                  style: TextStyle(
                                    color: Color(0xFFD7E1F5),
                                    fontSize: 15,
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _statTile(
                                        '${_pages.length}',
                                        'Страниц',
                                      ),
                                    ),
                                    const SizedBox(width: 9),
                                    const Expanded(
                                      child: _statTile('100%', 'Локально'),
                                    ),
                                    const SizedBox(width: 9),
                                    const Expanded(
                                      child: _statTile('AES-256', 'Шифрование'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (_pages.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 25,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(23),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.note_add_outlined,
                                    color: Color(0xFF315AA5),
                                    size: 42,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Пока нет документов',
                                    style: TextStyle(
                                      color: Color(0xFF101828),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 19,
                                    ),
                                  ),
                                  SizedBox(height: 7),
                                  Text(
                                    'Отсканируйте или добавьте первый документ',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF667085),
                                      fontSize: 14,
                                    ),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'Обработка выполняется на устройстве',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Color(0xFF8490A5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (_pages.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                          sliver: SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount:
                                  MediaQuery.sizeOf(context).width > 650 ? 3 : 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => Stack(
                                fit: StackFit.expand,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: FutureBuilder<Uint8List>(
                                      future: _readPage(_pages[i]),
                                      builder: (context, snapshot) {
                                        if (snapshot.hasError) {
                                          return const ColoredBox(
                                            color: Colors.white,
                                            child: Center(
                                              child: Icon(Icons.broken_image_outlined),
                                            ),
                                          );
                                        }
                                        if (!snapshot.hasData) {
                                          return const ColoredBox(
                                            color: Colors.white,
                                            child: Center(
                                              child: CircularProgressIndicator(),
                                            ),
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
                                    left: 7,
                                    top: 7,
                                    child: CircleAvatar(
                                      radius: 14,
                                      backgroundColor: Colors.white,
                                      child: Text(
                                        '${i + 1}',
                                        style: const TextStyle(
                                          color: Color(0xFF1B356B),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: IconButton.filledTonal(
                                      tooltip: 'Удалить страницу',
                                      onPressed: _busy ? null : () => _removePage(i),
                                      icon: const Icon(Icons.close, size: 18),
                                    ),
                                  ),
                                  Positioned(
                                    left: 4,
                                    right: 4,
                                    bottom: 4,
                                    child: FilledButton.tonalIcon(
                                      onPressed: _busy
                                          ? null
                                          : () => _recognizePage(_pages[i]),
                                      icon: const Icon(
                                        Icons.text_snippet_outlined,
                                        size: 18,
                                      ),
                                      label: const Text(
                                        'Распознать текст',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              childCount: _pages.length,
                            ),
                          ),
                        ),
                    ],
                  ),
        bottomNavigationBar: SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF3F5FA),
              border: Border(
                top: BorderSide(color: Color(0xFFE2E7F0)),
              ),
            ),
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
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: const Text('Камера'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: const Color(0xFF244B91),
                          side: const BorderSide(color: Color(0xFFC9D5EA)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || !_vaultReady
                            ? null
                            : () => _addPage(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Галерея'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: const Color(0xFF244B91),
                          side: const BorderSide(color: Color(0xFFC9D5EA)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy || !_vaultReady || _pages.isEmpty
                        ? null
                        : _exportPdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(
                      _busy
                          ? (_busyLabel ?? 'Подождите…')
                          : 'Экспорт в PDF',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF244B91),
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  static Widget _statTile(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0x2FFFFFFF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                ),
              ),
            ),
            const SizedBox(height: 5),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD7E1F5),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
}

import 'dart:io';
import 'dart:typed_data';

/// Persists encrypted pages using a same-directory staging file and rename.
///
/// The final .aiscan name is published only after all encrypted bytes have
/// been flushed, so an interrupted write is never mistaken for a complete page.
class VaultFileStore {
  Future<File> saveEncryptedPage(
    Directory folder,
    Uint8List encryptedBytes,
  ) async {
    await folder.create(recursive: true);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    var suffix = 0;
    late File target;
    late File pending;
    do {
      final extra = suffix == 0 ? '' : '_$suffix';
      target = File('${folder.path}/page_$timestamp$extra.aiscan');
      pending = File('${target.path}.pending');
      suffix++;
    } while (await target.exists() || await pending.exists());

    try {
      await pending.writeAsBytes(encryptedBytes, flush: true);
      return await pending.rename(target.path);
    } finally {
      // If writing or renaming fails, leave no staging plaintext or ciphertext
      // behind. A process kill may bypass finally; startup cleanup handles it.
      if (await pending.exists()) {
        await pending.delete();
      }
    }
  }

  Future<List<File>> listPages(Directory folder) async {
    if (!await folder.exists()) return <File>[];
    final pages = await folder
        .list()
        .where((entity) => entity is File && entity.path.endsWith('.aiscan'))
        .cast<File>()
        .toList();
    pages.sort((a, b) => a.path.compareTo(b.path));
    return pages;
  }

  Future<void> cleanupPendingFiles(Directory folder) async {
    if (!await folder.exists()) return;
    await for (final entity in folder.list()) {
      if (entity is File && entity.path.endsWith('.aiscan.pending')) {
        await entity.delete();
      }
    }
  }
}

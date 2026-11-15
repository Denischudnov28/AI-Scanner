import 'dart:io';
import 'dart:typed_data';

import 'package:ai_scanner/vault_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late VaultFileStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai_scanner_vault_test_');
    store = VaultFileStore();
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('publishes a page only as a complete encrypted file', () async {
    final encrypted = Uint8List.fromList([9, 8, 7, 6, 5]);

    final saved = await store.saveEncryptedPage(directory, encrypted);

    expect(saved.path, endsWith('.aiscan'));
    expect(await saved.readAsBytes(), encrypted);
    expect(
      (await store.listPages(directory)).map((file) => file.path),
      [saved.path],
    );
    expect(
      directory.listSync().where((entry) => entry.path.endsWith('.pending')),
      isEmpty,
    );
  });

  test('does not list incomplete staging files as pages', () async {
    final complete = File('${directory.path}/page_1.aiscan');
    final pending = File('${directory.path}/page_2.aiscan.pending');
    await complete.writeAsBytes([1, 2, 3]);
    await pending.writeAsBytes([4, 5, 6]);

    expect(
      (await store.listPages(directory)).map((file) => file.path),
      [complete.path],
    );
  });

  test('removes abandoned staging files but preserves completed pages', () async {
    final complete = File('${directory.path}/page_1.aiscan');
    final pending = File('${directory.path}/page_2.aiscan.pending');
    final unrelated = File('${directory.path}/notes.txt');
    await complete.writeAsBytes([1]);
    await pending.writeAsBytes([2]);
    await unrelated.writeAsString('keep');

    await store.cleanupPendingFiles(directory);

    expect(await complete.exists(), isTrue);
    expect(await pending.exists(), isFalse);
    expect(await unrelated.exists(), isTrue);
  });

  test('returns an empty page list when the vault folder is absent', () async {
    expect(await store.listPages(directory), isEmpty);
  });
}

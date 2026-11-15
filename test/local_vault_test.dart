import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_scanner/local_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalVault', () {
    test('requires initialization before encryption', () async {
      final vault = LocalVault(keyStore: _MemoryKeyStore());

      await expectLater(
        vault.encrypt(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    });

    test('encrypts and decrypts document bytes', () async {
      final store = _MemoryKeyStore();
      final vault = LocalVault(keyStore: store);
      final clear = Uint8List.fromList(List<int>.generate(256, (i) => i));

      await vault.initialize();
      final encrypted = await vault.encrypt(clear);

      expect(encrypted, isNot(equals(clear)));
      expect(await vault.decrypt(encrypted), equals(clear));
      expect(store.values, contains('ai_scanner_vault_key_v1'));
      expect(base64Decode(store.values['ai_scanner_vault_key_v1']!).length, 32);
    });

    test('uses a fresh nonce for each encryption', () async {
      final vault = LocalVault(keyStore: _MemoryKeyStore());
      await vault.initialize();
      final clear = Uint8List.fromList([10, 20, 30, 40]);

      final first = await vault.encrypt(clear);
      final second = await vault.encrypt(clear);

      expect(first, isNot(equals(second)));
      expect(await vault.decrypt(first), equals(clear));
      expect(await vault.decrypt(second), equals(clear));
    });

    test('rejects modified ciphertext', () async {
      final vault = LocalVault(keyStore: _MemoryKeyStore());
      await vault.initialize();
      final encrypted = await vault.encrypt(Uint8List.fromList([1, 2, 3, 4]));
      encrypted[12] ^= 0x01;

      await expectLater(
        vault.decrypt(encrypted),
        throwsA(anything),
      );
    });

    test('rejects truncated encrypted files', () async {
      final vault = LocalVault(keyStore: _MemoryKeyStore());
      await vault.initialize();

      await expectLater(
        vault.decrypt(Uint8List.fromList(List<int>.filled(27, 0))),
        throwsA(isA<FormatException>()),
      );
    });

    test('does not silently replace an invalid saved key', () async {
      final store = _MemoryKeyStore()
        ..values['ai_scanner_vault_key_v1'] = base64Encode([1, 2, 3]);
      final vault = LocalVault(keyStore: store);

      await expectLater(
        vault.initialize(),
        throwsA(isA<FormatException>()),
      );
      expect(base64Decode(store.values['ai_scanner_vault_key_v1']!), [1, 2, 3]);
    });
  });
}

class _MemoryKeyStore implements VaultKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

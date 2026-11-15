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

    test('creates a protected key and encrypts/decrypts document bytes',
        () async {
      final store = _MemoryKeyStore();
      final vault = LocalVault(keyStore: store);
      final clear = Uint8List.fromList(List<int>.generate(256, (i) => i));

      await vault.initialize();
      final encrypted = await vault.encrypt(clear);

      expect(encrypted, isNot(equals(clear)));
      expect(await vault.decrypt(encrypted), equals(clear));
      expect(store.protectedValues, contains('ai_scanner_vault_key_v2'));
      expect(
        base64Decode(store.protectedValues['ai_scanner_vault_key_v2']!).length,
        32,
      );
      expect(store.legacyValues, isEmpty);
    });

    test('migrates the exact legacy key before deleting the old copy',
        () async {
      final originalKey = List<int>.generate(32, (i) => i + 1);
      final store = _MemoryKeyStore()
        ..legacyValues['ai_scanner_vault_key_v1'] =
            base64Encode(originalKey);
      final vault = LocalVault(keyStore: store);
      final clear = Uint8List.fromList([8, 6, 7, 5, 3, 0, 9]);

      await vault.initialize();
      final encrypted = await vault.encrypt(clear);

      expect(
        base64Decode(store.protectedValues['ai_scanner_vault_key_v2']!),
        originalKey,
      );
      expect(store.legacyValues, isEmpty);
      expect(await vault.decrypt(encrypted), equals(clear));
    });

    test('keeps the legacy key if protected-key verification fails', () async {
      final originalKey = List<int>.generate(32, (i) => 255 - i);
      final store = _MemoryKeyStore()
        ..legacyValues['ai_scanner_vault_key_v1'] =
            base64Encode(originalKey)
        ..failOnVerificationRead = true;
      final vault = LocalVault(keyStore: store);

      await expectLater(vault.initialize(), throwsA(isA<StateError>()));
      expect(store.legacyValues, contains('ai_scanner_vault_key_v1'));
      await expectLater(
        vault.encrypt(Uint8List.fromList([1])),
        throwsA(isA<StateError>()),
      );
    });

    test('does not fall back to legacy key when protected read fails',
        () async {
      final store = _MemoryKeyStore()
        ..legacyValues['ai_scanner_vault_key_v1'] =
            base64Encode(List<int>.filled(32, 7))
        ..failProtectedRead = true;
      final vault = LocalVault(keyStore: store);

      await expectLater(vault.initialize(), throwsA(isA<StateError>()));
      expect(store.legacyValues, contains('ai_scanner_vault_key_v1'));
      expect(store.protectedValues, isEmpty);
    });

    test('requires authentication again after locking', () async {
      final store = _MemoryKeyStore();
      final vault = LocalVault(keyStore: store);
      await vault.initialize();
      final encrypted = await vault.encrypt(Uint8List.fromList([1, 2, 3]));

      vault.lock();
      await expectLater(
        vault.decrypt(encrypted),
        throwsA(isA<StateError>()),
      );

      await vault.initialize();
      expect(await vault.decrypt(encrypted), [1, 2, 3]);
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
        ..legacyValues['ai_scanner_vault_key_v1'] = base64Encode([1, 2, 3]);
      final vault = LocalVault(keyStore: store);

      await expectLater(
        vault.initialize(),
        throwsA(isA<FormatException>()),
      );
      expect(
        base64Decode(store.legacyValues['ai_scanner_vault_key_v1']!),
        [1, 2, 3],
      );
      expect(store.protectedValues, isEmpty);
    });
  });
}

class _MemoryKeyStore implements VaultKeyStore {
  final Map<String, String> protectedValues = {};
  final Map<String, String> legacyValues = {};
  int protectedReadCount = 0;
  bool failProtectedRead = false;
  bool failOnVerificationRead = false;

  @override
  Future<String?> readProtected(String key) async {
    protectedReadCount++;
    if (failProtectedRead ||
        (failOnVerificationRead && protectedReadCount >= 2)) {
      throw StateError('Protected storage authentication failed');
    }
    return protectedValues[key];
  }

  @override
  Future<void> writeProtected(String key, String value) async {
    protectedValues[key] = value;
  }

  @override
  Future<void> deleteProtected(String key) async {
    protectedValues.remove(key);
  }

  @override
  Future<String?> readLegacy(String key) async => legacyValues[key];

  @override
  Future<void> deleteLegacy(String key) async {
    legacyValues.remove(key);
  }
}

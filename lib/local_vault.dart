import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Minimal storage contract so the vault can be tested without platform APIs.
abstract interface class VaultKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Encrypts document bytes with AES-256-GCM. The random key is stored in the
/// platform keychain/keystore, never alongside the encrypted document files.
class LocalVault {
  LocalVault({VaultKeyStore? keyStore})
      : _keyStore = keyStore ?? _PlatformVaultKeyStore();

  final VaultKeyStore _keyStore;
  static const _keyName = 'ai_scanner_vault_key_v1';
  static const _keyLength = 32;
  static const _nonceLength = 12;
  static const _macLength = 16;
  final _algorithm = AesGcm.with256bits();
  SecretKey? _key;

  Future<void> initialize() async {
    final saved = await _keyStore.read(_keyName);
    if (saved != null) {
      final bytes = base64Decode(saved);
      if (bytes.length != _keyLength) {
        throw const FormatException('Недействительный ключ защищённого хранилища');
      }
      _key = SecretKey(bytes);
      return;
    }

    final random = Random.secure();
    final bytes = List<int>.generate(
      _keyLength,
      (_) => random.nextInt(256),
    );
    await _keyStore.write(_keyName, base64Encode(bytes));
    _key = SecretKey(bytes);
  }

  Future<Uint8List> encrypt(Uint8List clearBytes) async {
    final key = _key;
    if (key == null) {
      throw StateError('Локальное хранилище не инициализировано');
    }
    final nonce = _algorithm.newNonce();
    final box = await _algorithm.encrypt(
      clearBytes,
      secretKey: key,
      nonce: nonce,
    );
    return Uint8List.fromList([
      ...nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  Future<Uint8List> decrypt(Uint8List encryptedBytes) async {
    final key = _key;
    if (key == null) {
      throw StateError('Локальное хранилище не инициализировано');
    }
    if (encryptedBytes.length < _nonceLength + _macLength) {
      throw const FormatException('Повреждённый файл документа');
    }

    final nonce = encryptedBytes.sublist(0, _nonceLength);
    final mac = encryptedBytes.sublist(encryptedBytes.length - _macLength);
    final cipherText =
        encryptedBytes.sublist(_nonceLength, encryptedBytes.length - _macLength);
    final clear = await _algorithm.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    return Uint8List.fromList(clear);
  }
}

class _PlatformVaultKeyStore implements VaultKeyStore {
  _PlatformVaultKeyStore()
      : _storage = const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          aOptions: AndroidOptions(
            // Never silently reset a vault key after a Keystore error: that
            // would make existing encrypted documents permanently unreadable.
            resetOnError: false,
            // Stage the legacy EncryptedSharedPreferences -> v10 cipher
            // migration with a recoverable backup before biometric storage
            // is enabled in the next upgrade step.
            encryptedSharedPreferences: true,
            migrateOnAlgorithmChange: true,
            migrateWithBackup: true,
          ),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

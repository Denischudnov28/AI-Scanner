import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage contract separates the old, unprotected key from the new
/// authentication-gated key. Tests can exercise migration without platform APIs.
abstract interface class VaultKeyStore {
  Future<String?> readProtected(String key);
  Future<void> writeProtected(String key, String value);
  Future<void> deleteProtected(String key);
  Future<String?> readLegacy(String key);
  Future<void> deleteLegacy(String key);
}

/// Encrypts document bytes with AES-256-GCM. The data-encryption key is kept
/// in platform storage that requires device authentication before it can be read.
class LocalVault {
  LocalVault({VaultKeyStore? keyStore})
      : _keyStore = keyStore ?? _PlatformVaultKeyStore();

  final VaultKeyStore _keyStore;
  static const _legacyKeyName = 'ai_scanner_vault_key_v1';
  static const _protectedKeyName = 'ai_scanner_vault_key_v2';
  static const _keyLength = 32;
  static const _nonceLength = 12;
  static const _macLength = 16;
  final _algorithm = AesGcm.with256bits();
  SecretKey? _key;

  /// Loads the protected key, or migrates the existing key without changing it.
  ///
  /// The protected value is read back and compared before the legacy copy is
  /// deleted. If authentication is cancelled or migration fails, the vault
  /// stays locked and the legacy key is retained for a safe retry.
  Future<void> initialize() async {
    if (_key != null) return;

    final protected = await _keyStore.readProtected(_protectedKeyName);
    if (protected != null) {
      final bytes = _decodeKey(protected);
      // Do not leave an old, non-authenticated copy behind after migration.
      await _keyStore.deleteLegacy(_legacyKeyName);
      _key = SecretKey(bytes);
      return;
    }

    final legacy = await _keyStore.readLegacy(_legacyKeyName);
    final bytes = legacy == null ? _newKey() : _decodeKey(legacy);

    await _keyStore.writeProtected(_protectedKeyName, base64Encode(bytes));

    // Verify that the protected entry can be read before deleting the old key.
    final verified = await _keyStore.readProtected(_protectedKeyName);
    if (verified == null) {
      throw StateError('Защищённый ключ не удалось проверить');
    }
    final verifiedBytes = _decodeKey(verified);
    if (!_constantTimeEquals(bytes, verifiedBytes)) {
      throw StateError('Проверка переноса ключа не пройдена');
    }

    await _keyStore.deleteLegacy(_legacyKeyName);
    _key = SecretKey(verifiedBytes);
  }

  /// Drops the data-encryption key reference when the app is locked.
  /// Dart does not guarantee zeroization of previously allocated memory.
  void lock() {
    _key = null;
  }

  List<int> _newKey() {
    final random = Random.secure();
    return List<int>.generate(_keyLength, (_) => random.nextInt(256));
  }

  List<int> _decodeKey(String value) {
    final bytes = base64Decode(value);
    if (bytes.length != _keyLength) {
      throw const FormatException(
        'Недействительный ключ защищённого хранилища',
      );
    }
    return bytes;
  }

  bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
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
      : _legacyStorage = const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          aOptions: AndroidOptions(
            // v11 reads the v10 cipher format; v10 migration must have run
            // before this upgrade. Keep errors fatal to avoid silent key loss.
            resetOnError: false,
            migrateOnAlgorithmChange: true,
            migrateWithBackup: true,
          ),
        ),
        _protectedStorage = const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.unlocked,
            accessControlFlags: [AccessControlFlag.userPresence],
            useSecureEnclave: true,
          ),
          aOptions: AndroidOptions.biometric(
            resetOnError: false,
            enforceBiometrics: true,
            requireBiometricsPerOperation: true,
            biometricType: AndroidBiometricType.biometricOrDeviceCredential,
            migrateOnAlgorithmChange: true,
            migrateWithBackup: true,
            storageNamespace: 'ai_scanner_vault_biometric_v2',
            biometricPromptTitle: 'Разблокировать AI Scanner',
            biometricPromptSubtitle:
                'Подтвердите личность для доступа к документам',
          ),
        );

  final FlutterSecureStorage _legacyStorage;
  final FlutterSecureStorage _protectedStorage;

  @override
  Future<String?> readProtected(String key) =>
      _protectedStorage.read(key: key);

  @override
  Future<void> writeProtected(String key, String value) =>
      _protectedStorage.write(key: key, value: value);

  @override
  Future<void> deleteProtected(String key) =>
      _protectedStorage.delete(key: key);

  @override
  Future<String?> readLegacy(String key) => _legacyStorage.read(key: key);

  @override
  Future<void> deleteLegacy(String key) => _legacyStorage.delete(key: key);
}

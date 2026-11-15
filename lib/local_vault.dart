import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Encrypts document bytes with AES-256-GCM. The random key is stored in the
/// platform keychain/keystore, never alongside the encrypted document files.
class LocalVault {
  LocalVault()
      : _storage = const FlutterSecureStorage(
          iOptions: IOSOptions(
            accessibility: KeychainAccessibility.first_unlock_this_device,
          ),
          aOptions: AndroidOptions(
            encryptedSharedPreferences: true,
          ),
        );

  final FlutterSecureStorage _storage;
  static const _keyName = 'ai_scanner_vault_key_v1';
  final _algorithm = AesGcm.with256bits();
  SecretKey? _key;

  Future<void> initialize() async {
    final saved = await _storage.read(key: _keyName);
    if (saved != null) {
      _key = SecretKey(base64Decode(saved));
      return;
    }
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    await _storage.write(key: _keyName, value: base64Encode(bytes));
    _key = SecretKey(bytes);
  }

  Future<Uint8List> encrypt(Uint8List clearBytes) async {
    final key = _key;
    if (key == null) throw StateError('Локальное хранилище не инициализировано');
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
    if (key == null) throw StateError('Локальное хранилище не инициализировано');
    if (encryptedBytes.length < 28) {
      throw const FormatException('Повреждённый файл документа');
    }
    final nonce = encryptedBytes.sublist(0, 12);
    final mac = encryptedBytes.sublist(encryptedBytes.length - 16);
    final cipherText = encryptedBytes.sublist(12, encryptedBytes.length - 16);
    final clear = await _algorithm.decrypt(
      SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: key,
    );
    return Uint8List.fromList(clear);
  }
}

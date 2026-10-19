import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Crittografia della sessione Secret Service
/// "dh-ietf1024-sha256_aes128-cbc-pkcs7", la stessa usata da libsecret:
/// Diffie-Hellman sul gruppo 2 di RFC 2409, chiave AES-128 derivata con
/// HKDF-SHA256, cifratura AES-CBC con padding PKCS#7.
///
/// Serve perché sul bus di sessione altri processi dello stesso utente
/// possono osservare i messaggi: con la sessione "plain" la password
/// viaggerebbe in chiaro.
class DhSession {
  DhSession._(this._private, this.publicKey);

  factory DhSession.generate([Random? random]) {
    final rnd = random ?? Random.secure();
    final bytes = Uint8List.fromList(List.generate(_primeBytes, (_) => rnd.nextInt(256)));
    // Esponente privato in [2, p-2].
    final private = _toBigInt(bytes) % (prime - BigInt.from(3)) + BigInt.two;
    final public = BigInt.two.modPow(private, prime);
    return DhSession._(private, toFixedBytes(public));
  }

  static const algorithm = 'dh-ietf1024-sha256_aes128-cbc-pkcs7';
  static const _primeBytes = 128;

  /// RFC 2409, sezione 6.2 (Second Oakley Group, 1024 bit).
  static final prime = BigInt.parse(
      'FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1'
      '29024E088A67CC74020BBEA63B139B22514A08798E3404DD'
      'EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245'
      'E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED'
      'EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE65381'
      'FFFFFFFFFFFFFFFF',
      radix: 16);

  final BigInt _private;

  /// Chiave pubblica da inviare con OpenSession (128 byte, big-endian).
  final Uint8List publicKey;

  Uint8List? _aesKey;

  /// Completa lo scambio con la chiave pubblica del servizio.
  void complete(List<int> serverPublic) {
    final y = _toBigInt(Uint8List.fromList(serverPublic));
    // Rifiuta valori degeneri che renderebbero il segreto prevedibile.
    if (y <= BigInt.one || y >= prime - BigInt.one) {
      throw const FormatException('Chiave pubblica del servizio non valida');
    }
    // Il segreto condiviso va rappresentato SEMPRE su 128 byte: se il valore
    // inizia con byte nulli, libsecret li mantiene. Toglierli darebbe una
    // chiave diversa circa una volta su 256.
    final shared = toFixedBytes(y.modPow(_private, prime));
    _aesKey = hkdfSha256(shared, 16);
  }

  bool get isReady => _aesKey != null;

  ({Uint8List iv, Uint8List ciphertext}) encrypt(List<int> plaintext, [Random? random]) {
    final rnd = random ?? Random.secure();
    final iv = Uint8List.fromList(List.generate(16, (_) => rnd.nextInt(256)));
    return (iv: iv, ciphertext: _cipher(true, iv).process(Uint8List.fromList(plaintext)));
  }

  Uint8List decrypt(List<int> iv, List<int> ciphertext) {
    if (iv.length != 16 || ciphertext.isEmpty || ciphertext.length % 16 != 0) {
      throw const FormatException('Segreto cifrato malformato');
    }
    try {
      return _cipher(false, Uint8List.fromList(iv)).process(Uint8List.fromList(ciphertext));
    } on ArgumentError {
      throw const FormatException('Padding non valido: chiave di sessione errata?');
    }
  }

  PaddedBlockCipher _cipher(bool forEncryption, Uint8List iv) {
    final key = _aesKey;
    if (key == null) throw StateError('Sessione non completata');
    return PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(forEncryption,
          PaddedBlockCipherParameters(ParametersWithIV(KeyParameter(key), iv), null));
  }

  /// HKDF-SHA256 (RFC 5869) con salt e info vuoti, come libsecret.
  static Uint8List hkdfSha256(List<int> ikm, int length) {
    final prk = Hmac(sha256, List.filled(32, 0)).convert(ikm).bytes;
    final out = <int>[];
    var block = <int>[];
    for (var i = 1; out.length < length; i++) {
      block = Hmac(sha256, prk).convert([...block, i]).bytes;
      out.addAll(block);
    }
    return Uint8List.fromList(out.sublist(0, length));
  }

  static BigInt _toBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  static Uint8List toFixedBytes(BigInt value) {
    final out = Uint8List(_primeBytes);
    var v = value;
    for (var i = _primeBytes - 1; i >= 0; i--) {
      out[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return out;
  }
}

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Decodifica di testo in qualunque charset dichiarato da un'email.
///
/// UTF-8, ASCII e Latin-1 in puro Dart; tutto il resto (windows-125x,
/// ISO-8859-*, KOI8, Shift_JIS, ISO-2022-JP, EUC-*, GB18030, Big5, UTF-16...)
/// tramite iconv di glibc, che su Linux copre ogni charset usato nella posta.
///
/// Non lancia mai: un'email con charset sbagliato o sconosciuto deve comunque
/// essere leggibile. Ordine di ripiego: charset dichiarato → UTF-8 rigoroso →
/// windows-1252 (il caso reale più comune di "dichiarato male").
abstract final class Charsets {
  /// Alias usati nelle email reali che iconv non conosce o interpreta male.
  static const _aliases = {
    'utf8': 'UTF-8',
    'unicode-1-1-utf-8': 'UTF-8',
    'latin1': 'ISO-8859-1',
    'latin-1': 'ISO-8859-1',
    'us-ascii': 'ASCII',
    'ascii': 'ASCII',
    'ansi_x3.4-1968': 'ASCII',
    // Le email dichiarano ISO-8859-1 ma usano quasi sempre caratteri
    // windows-1252 (virgolette tipografiche, €): WHATWG fa lo stesso.
    'iso-8859-1': 'WINDOWS-1252',
    'iso8859-1': 'WINDOWS-1252',
    'x-user-defined': 'WINDOWS-1252',
    'cp1252': 'WINDOWS-1252',
    'gb2312': 'GB18030',
    'gbk': 'GB18030',
    'x-gbk': 'GB18030',
    'ks_c_5601-1987': 'CP949',
    'euc-kr': 'CP949',
    'shift_jis': 'CP932',
    'shift-jis': 'CP932',
    'sjis': 'CP932',
    'x-sjis': 'CP932',
    'ms_kanji': 'CP932',
    'windows-31j': 'CP932',
    'iso-2022-jp': 'ISO-2022-JP-2',
    'utf-7': 'UTF-7',
    // La tabella BIG5 di glibc è ridotta (niente cirillico né kana) e scarta
    // in silenzio i caratteri che non conosce: BIG5-HKSCS è il superinsieme
    // usato anche dai browser (WHATWG).
    'big5': 'BIG5-HKSCS',
    'x-x-big5': 'BIG5-HKSCS',
    'cn-big5': 'BIG5-HKSCS',
    'unicode': 'UTF-16',
    'ucs-2': 'UTF-16',
  };

  static final _validName = RegExp(r'^[A-Za-z0-9._:+-]{1,40}$');

  /// Nome normalizzato che si darà a iconv, o null se non plausibile.
  static String? canonical(String? name) {
    if (name == null) return null;
    var n = name.trim().toLowerCase();
    if (n.startsWith('"') && n.endsWith('"') && n.length > 1) n = n.substring(1, n.length - 1);
    if (n.isEmpty || !_validName.hasMatch(n)) return null;
    return _aliases[n] ?? n.toUpperCase();
  }

  static String decode(List<int> input, String? charset) {
    if (input.isEmpty) return '';
    // Difesa: valori fuori da 0..255 non sono byte; si riportano nell'intervallo
    // invece di far cadere i decodificatori.
    final bytes = input.every((b) => b >= 0 && b <= 255) ? input : [for (final b in input) b & 0xff];
    final name = canonical(charset);
    if (name != null) {
      final r = _decodeStrict(bytes, name);
      if (r != null) return r;
    }
    return decodeUnknown(bytes);
  }

  /// Testo senza charset dichiarato (intestazioni a 8 bit, charset rotto).
  static String decodeUnknown(List<int> input) {
    final bytes = input.every((b) => b >= 0 && b <= 255) ? input : [for (final b in input) b & 0xff];
    if (bytes.every((b) => b < 0x80)) return ascii.decode(bytes);
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return _decodeStrict(bytes, 'WINDOWS-1252') ?? latin1.decode(bytes);
    }
  }

  /// Null se il charset è sconosciuto o i byte non sono validi per esso.
  static String? _decodeStrict(List<int> bytes, String name) {
    switch (name) {
      case 'UTF-8':
        try {
          return utf8.decode(bytes);
        } on FormatException {
          return null;
        }
      case 'ASCII':
        if (bytes.every((b) => b < 0x80)) return ascii.decode(bytes);
        return null;
    }
    return _Iconv.instance?.convert(bytes, name);
  }

  /// Il charset è supportato (per i test e la diagnostica).
  static bool supports(String charset) {
    final n = canonical(charset);
    if (n == null) return false;
    if (n == 'UTF-8' || n == 'ASCII') return true;
    // Nessun singolo campione è valido ovunque: "A" è incompleto in UTF-16,
    // il byte nullo non è ammesso in UTF-7.
    final iconv = _Iconv.instance;
    return iconv != null &&
        (iconv.convert(const [0x41], n) != null || iconv.convert(const [0x00, 0x41], n) != null);
  }
}

typedef _IconvOpenC = Pointer<Void> Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _IconvC = Size Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>,
    Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _IconvDart = int Function(Pointer<Void>, Pointer<Pointer<Uint8>>, Pointer<Size>,
    Pointer<Pointer<Uint8>>, Pointer<Size>);
typedef _IconvCloseC = Int32 Function(Pointer<Void>);
typedef _IconvCloseDart = int Function(Pointer<Void>);

/// Binding minimo a iconv(3) di glibc. Converte sempre verso UTF-8.
class _Iconv {
  _Iconv._(DynamicLibrary lib)
      : _open = lib.lookupFunction<_IconvOpenC, _IconvOpenC>('iconv_open'),
        _iconv = lib.lookupFunction<_IconvC, _IconvDart>('iconv'),
        _close = lib.lookupFunction<_IconvCloseC, _IconvCloseDart>('iconv_close');

  static final _Iconv? instance = _load();

  static _Iconv? _load() {
    try {
      return _Iconv._(DynamicLibrary.process());
    } catch (_) {
      try {
        return _Iconv._(DynamicLibrary.open('libc.so.6'));
      } catch (_) {
        return null;
      }
    }
  }

  final _IconvOpenC _open;
  final _IconvDart _iconv;
  final _IconvCloseDart _close;

  /// Limite di sicurezza: nessun corpo di testo decodificato oltre 64 MiB.
  static const _maxInput = 64 * 1024 * 1024;

  String? convert(List<int> input, String from) {
    if (input.length > _maxInput) return null;
    final fromName = from.toNativeUtf8();
    final toName = 'UTF-8'.toNativeUtf8();
    final cd = _open(toName, fromName);
    calloc.free(fromName);
    calloc.free(toName);
    if (cd.address == -1 || cd.address == 0xFFFFFFFFFFFFFFFF) return null;

    // Caso peggiore: ogni byte diventa 4 byte UTF-8; +16 per gli stati finali.
    final outCap = input.length * 4 + 16;
    final inBuf = calloc<Uint8>(input.length);
    final outBuf = calloc<Uint8>(outCap);
    final inPtr = calloc<Pointer<Uint8>>();
    final outPtr = calloc<Pointer<Uint8>>();
    final inLeft = calloc<Size>();
    final outLeft = calloc<Size>();
    try {
      inBuf.asTypedList(input.length).setAll(0, input);
      inPtr.value = inBuf;
      outPtr.value = outBuf;
      inLeft.value = input.length;
      outLeft.value = outCap;
      final r = _iconv(cd, inPtr, inLeft, outPtr, outLeft);
      // (size_t)-1 = byte non validi o sequenza incompleta: decodifica fallita.
      if (r == -1 || inLeft.value != 0) return null;
      // Svuota eventuali stati di shift (ISO-2022-JP).
      final r2 = _iconv(cd, nullptr, nullptr, outPtr, outLeft);
      if (r2 == -1) return null;
      final produced = outCap - outLeft.value;
      return utf8.decode(Uint8List.fromList(outBuf.asTypedList(produced)), allowMalformed: true);
    } finally {
      _close(cd);
      calloc.free(inBuf);
      calloc.free(outBuf);
      calloc.free(inPtr);
      calloc.free(outPtr);
      calloc.free(inLeft);
      calloc.free(outLeft);
    }
  }
}

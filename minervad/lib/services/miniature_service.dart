import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'casa/md5.dart';

/// Le miniature di video e PDF per il gestore file.
///
/// ── Perché esiste ────────────────────────────────────────────────────────
///
/// Il gestore file disegnava in miniatura solo le immagini, che Qt sa
/// leggere da sé. Video e PDF erano un'icona grigia tutti uguali — nella
/// cartella Video, una parete di quadrati identici (6 ottobre 2026), mentre
/// `ffmpegthumbnailer` e `pdftoppm` erano già installati.
///
/// ── Prima quelle che ci sono già ─────────────────────────────────────────
///
/// Dolphin, Nautilus e gli altri le tengono in `~/.cache/thumbnails`, col
/// nome dato dalla specifica freedesktop: l'MD5 dell'indirizzo del file. Se
/// ce n'è una e la sua data (`Thumb::MTime`, dentro il PNG) è quella del
/// file, si usa quella e non si rifà niente.
///
/// Quelle che facciamo noi vanno in `~/.cache/minerva/miniature` e NON nella
/// cartella comune: la specifica vuole dentro il PNG dei campi che i nostri
/// programmi non scrivono, e una miniatura comune scritta male gli altri la
/// scartano o, peggio, la credono buona per un file cambiato.
///
/// ── Al più due alla volta ────────────────────────────────────────────────
///
/// Aprire una cartella con trecento video chiederebbe trecento `ffmpeg`
/// insieme. Si mettono in fila e se ne fanno due per volta; un file che non
/// riesce si ricorda, e non si riprova a ogni rilettura.
class MiniatureService {
  MiniatureService({String? casa}) : _casa = casa ?? Platform.environment['HOME'] ?? '';

  final String _casa;

  static const _contemporanee = 2;
  static const _lato = 256;
  static const _limite = Duration(seconds: 20);

  final _inCorso = <String, Completer<String>>{};
  final _fila = <_Lavoro>[];
  final _fallite = <String>{};
  int _attive = 0;

  String get _nostra => '$_casa/.cache/minerva/miniature';

  /// Il PNG della miniatura di `percorso`, o «» se non c'è modo di farla.
  Future<String> miniatura(String percorso) async {
    if (!percorso.startsWith('/')) return '';
    final f = File(percorso);
    FileStat st;
    try {
      st = await f.stat();
    } catch (_) {
      return '';
    }
    if (st.type != FileSystemEntityType.file) return '';
    final tipo = _tipo(percorso);
    if (tipo == null) return '';

    final uri = Uri.file(percorso).toString();
    final nome = '${Md5.esa(utf8.encode(uri))}.png';
    final mtime = st.modified.millisecondsSinceEpoch ~/ 1000;

    // Le comuni, se sono di questo file così com'è adesso.
    for (final cartella in ['x-large', 'large', 'normal']) {
      final c = File('$_casa/.cache/thumbnails/$cartella/$nome');
      if (await _valida(c, mtime)) return c.path;
    }
    // Le nostre: valgono se sono più nuove del file.
    final nostra = File('$_nostra/$nome');
    try {
      final ns = await nostra.stat();
      if (ns.type == FileSystemEntityType.file && !ns.modified.isBefore(st.modified)) {
        return nostra.path;
      }
    } catch (_) {}

    final chiave = '$percorso@$mtime';
    if (_fallite.contains(chiave)) return '';
    final gia = _inCorso[chiave];
    if (gia != null) return gia.future;

    final c = Completer<String>();
    _inCorso[chiave] = c;
    _fila.add(_Lavoro(percorso, tipo, nostra.path, chiave, c));
    _avanti();
    return c.future;
  }

  void _avanti() {
    while (_attive < _contemporanee && _fila.isNotEmpty) {
      final l = _fila.removeAt(0);
      _attive++;
      unawaited(_fai(l).whenComplete(() {
        _attive--;
        _inCorso.remove(l.chiave);
        _avanti();
      }));
    }
  }

  Future<void> _fai(_Lavoro l) async {
    try {
      await Directory(_nostra).create(recursive: true);
      final provvisorio = '${l.destinazione}.$pid.tmp';
      ProcessResult r;
      if (l.tipo == 'video') {
        r = await Process.run('ffmpegthumbnailer',
                ['-i', l.percorso, '-o', provvisorio, '-s', '$_lato', '-c', 'png', '-t', '10%'])
            .timeout(_limite);
      } else {
        // pdftoppm aggiunge «.png» da sé al nome che riceve.
        final base = provvisorio.substring(0, provvisorio.length - 4);
        r = await Process.run('pdftoppm',
                ['-png', '-singlefile', '-f', '1', '-l', '1', '-scale-to', '$_lato', l.percorso, base])
            .timeout(_limite);
        if (r.exitCode == 0) await File('$base.png').rename(provvisorio);
      }
      if (r.exitCode == 0 && await File(provvisorio).exists()) {
        await File(provvisorio).rename(l.destinazione);
        l.fatto.complete(l.destinazione);
        return;
      }
      try {
        await File(provvisorio).delete();
      } catch (_) {}
    } catch (_) {
      // Programma mancante, file rovinato, tempo scaduto: niente miniatura.
    }
    _fallite.add(l.chiave);
    l.fatto.complete('');
  }

  static String? _tipo(String percorso) {
    final punto = percorso.lastIndexOf('.');
    if (punto < 0) return null;
    final est = percorso.substring(punto + 1).toLowerCase();
    const video = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'm4v', 'wmv', 'flv', 'mpg', 'mpeg', 'ts', 'ogv', '3gp'};
    if (video.contains(est)) return 'video';
    if (est == 'pdf') return 'pdf';
    return null;
  }

  /// Una miniatura comune vale se il PNG dice la stessa data del file.
  static Future<bool> _valida(File f, int mtime) async {
    Uint8List b;
    try {
      final r = await f.open();
      try {
        b = await r.read(8192);
      } finally {
        await r.close();
      }
    } catch (_) {
      return false;
    }
    // I campi di testo stanno nei primi pezzi del PNG: si scorrono quelli.
    var i = 8;
    while (i + 8 <= b.length) {
      final lung = (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      final tipo = String.fromCharCodes(b.sublist(i + 4, i + 8));
      if (tipo == 'IDAT' || tipo == 'IEND') break;
      if (tipo == 'tEXt' && i + 8 + lung <= b.length) {
        final testo = latin1.decode(b.sublist(i + 8, i + 8 + lung));
        final zero = testo.indexOf('\u0000');
        if (zero > 0 && testo.substring(0, zero) == 'Thumb::MTime') {
          return int.tryParse(testo.substring(zero + 1)) == mtime;
        }
      }
      i += 12 + lung;
    }
    return false;
  }
}

class _Lavoro {
  _Lavoro(this.percorso, this.tipo, this.destinazione, this.chiave, this.fatto);
  final String percorso;
  final String tipo;
  final String destinazione;
  final String chiave;
  final Completer<String> fatto;
}

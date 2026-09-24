import 'dart:io';
import 'dart:typed_data';

import 'exif.dart';
import 'media.dart';
import '../../core/minerva_paths.dart';

/// Le miniature: piccole, riusate, e quasi sempre gratis.
///
/// ── Le tre strade, in ordine di costo ──────────────────────────────────────
///
/// 1. **Quella che c'è già dentro il file.** Ogni fotografia di telefono si
///    porta in pancia un JPEG da 6-8 KB, in fondo all'EXIF. Costa 42 KB letti
///    e zero decodifiche. Misurato su questa libreria: **454 fotografie su
///    466** ce l'hanno. È la strada che copre quasi tutto.
/// 2. **`magick`**, per HEIC, AVIF, TIFF, i grezzi delle macchine
///    fotografiche, e per le fotografie che la miniatura interna non ce
///    l'hanno o ce l'hanno troppo piccola.
/// 3. **`ffmpegthumbnailer`**, per i video.
///
/// Quello che Qt sa già disegnare da solo — PNG, GIF, WEBP, JPEG piccoli — non
/// passa di qui affatto: lo fa la shell, con `sourceSize`, senza svegliare
/// nessuno. Il demone serve per ciò che Qt non sa aprire, e per non pagare due
/// volte ciò che è già pronto.
///
/// ── Perché una cache su disco ──────────────────────────────────────────────
///
/// Perché la seconda apertura della galleria deve costare zero. Lo schema è
/// quello già collaudato dalle onde sonore in `audio_service.dart`: chiave
/// fatta di percorso, dimensione e data, cartella iniettabile per le prove, e
/// una potatura quando si esagera.
class Miniature {
  /// Dove si tengono. Iniettabile: una prova non deve scrivere nella cache
  /// vera, e soprattutto non deve poterla cancellare.
  final String cartellaCache;

  /// Il seme per le prove: `magick` e `ffmpegthumbnailer` non devono girare
  /// davvero quando si prova la logica.
  final Future<ProcessResult> Function(String, List<String>) esegui;

  /// Oltre questo, si pota. Cinquecento megabyte sono circa centomila
  /// miniature: più di quante fotografie abbia chiunque in questa casa.
  final int tettoByte;

  Miniature({
    String? cartellaCache,
    Future<ProcessResult> Function(String, List<String>)? esegui,
    this.tettoByte = 500 * 1024 * 1024,
  })  : cartellaCache = cartellaCache ?? _cartellaVera(),
        esegui = esegui ?? Process.run;

  static String _cartellaVera() {
    return '${MinervaPaths.cache()}/miniature';
  }

  /// I lati che si possono chiedere.
  ///
  /// A scatti, e non un numero qualunque, per lo stesso motivo per cui la
  /// griglia di Anteprima quantizza `sourceSize` a 64 pixel: un lato legato
  /// esattamente alla cella rigenererebbe l'intera libreria a ogni scatto di
  /// rotellina.
  static const List<int> lati = [128, 256, 512, 1024];

  static int latoVicino(int chiesto) {
    for (final l in lati) {
      if (l >= chiesto) return l;
    }
    return lati.last;
  }

  /// La miniatura di un file. Restituisce **un percorso**, non dei byte: la
  /// shell la disegna da lì, e il bus non si porta dietro megabyte in base64.
  Future<Map<String, dynamic>> per(String percorso, {int lato = 256}) async {
    if (!percorso.startsWith('/')) {
      return _no('Mi serve il percorso completo, non «$percorso».');
    }
    final nome = percorso.split('/').last;
    // `magick` legge «foto.jpg[0]» come «il primo fotogramma di foto.jpg», e
    // «@elenco.txt» come «una lista di file». Un nome può contenerli davvero, e
    // allora il programma aprirebbe un file diverso da quello chiesto. Non è un
    // buco di sicurezza — è peggio: è una risposta sbagliata che sembra giusta.
    if (nome.contains('[') || nome.contains(']') || nome.startsWith('@')) {
      return _no('Non so fare la miniatura di un file che si chiama «$nome».');
    }

    final f = File(percorso);
    final FileStat s;
    try {
      s = f.statSync();
    } catch (_) {
      return _no('Non riesco a leggere «$nome».');
    }
    if (s.type != FileSystemEntityType.file) {
      return _no('«$nome» non è un file.');
    }

    final l = latoVicino(lato);
    final dove = _dove(percorso, s, l);

    final gia = File(dove);
    if (gia.existsSync() && gia.lengthSync() > 0) {
      return {'ok': true, 'percorso': dove, 'da': 'cache', 'lato': l};
    }
    Directory(dove.substring(0, dove.lastIndexOf('/')))
        .createSync(recursive: true);

    if (eVideo(percorso)) {
      return _daVideo(percorso, dove, l);
    }
    return _daFoto(percorso, dove, l);
  }

  // ── Le fotografie ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _daFoto(
      String percorso, String dove, int lato) async {
    final e = DatiExif.leggi(percorso);

    // Strada 1: quella che c'è già.
    //
    // Si usa solo se è abbastanza grande — su questo telefono il lato lungo è
    // 288 pixel: buona per una cella da 256, sgranata per una da 512. E solo se
    // la fotografia non va girata: girarla vorrebbe dire decodificarla, cioè
    // rinunciare all'unico vantaggio che ha.
    if (e.haMiniatura && lato <= 256 && (e.orientamento <= 1)) {
      final b = DatiExif.miniatura(percorso, e);
      if (b != null && _sembraJpeg(b)) {
        File(dove).writeAsBytesSync(b);
        return {'ok': true, 'percorso': dove, 'da': 'exif', 'lato': lato};
      }
    }

    // Strada 2: `magick`.
    final r = await _prova('magick', [
      percorso,
      '-auto-orient', // la rotazione dell'EXIF applicata davvero, non promessa
      '-thumbnail', '${lato}x$lato>', // «>» = non ingrandire mai
      '-quality', '82',
      '-strip', // via l'EXIF dalla miniatura: pesa e non serve più
      dove,
    ]);
    if (r) return {'ok': true, 'percorso': dove, 'da': 'magick', 'lato': lato};

    return _no('Non so aprire «${percorso.split('/').last}».');
  }

  // ── I video ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _daVideo(
      String percorso, String dove, int lato) async {
    // `-s` è il lato lungo, `-q` la qualità, `-t 10%` il fotogramma: non il
    // primo, che in mezzo video è nero.
    final r = await _prova('ffmpegthumbnailer',
        ['-i', percorso, '-o', dove, '-s', '$lato', '-q', '8', '-t', '10%']);
    if (r) {
      return {'ok': true, 'percorso': dove, 'da': 'video', 'lato': lato};
    }
    return _no('Non so guardare dentro «${percorso.split('/').last}».');
  }

  Future<bool> _prova(String comando, List<String> argomenti) async {
    try {
      final r = await esegui(comando, argomenti);
      if (r.exitCode != 0) return false;
      // Un codice di uscita zero non basta: `magick` sa uscire bene e non
      // scrivere niente. Quello che conta è se il file c'è.
      final f = File(_uscita(argomenti));
      return f.existsSync() && f.lengthSync() > 0;
    } catch (_) {
      return false;
    }
  }

  /// Dove finisce il risultato: l'ultimo argomento per `magick`, quello dopo
  /// `-o` per `ffmpegthumbnailer`.
  static String _uscita(List<String> argomenti) {
    final i = argomenti.indexOf('-o');
    if (i >= 0 && i + 1 < argomenti.length) return argomenti[i + 1];
    return argomenti.last;
  }

  static bool _sembraJpeg(Uint8List b) =>
      b.length > 4 && b[0] == 0xFF && b[1] == 0xD8;

  // ── La cache ───────────────────────────────────────────────────────────

  /// Il nome del file di cache.
  ///
  /// Nella chiave entrano percorso, dimensione e data: se la fotografia cambia
  /// — o se al suo posto ne arriva un'altra con lo stesso nome — la chiave
  /// cambia e la miniatura vecchia smette semplicemente di essere trovata.
  String _dove(String percorso, FileStat s, int lato) {
    final chiave = _impronta(
        '$percorso|${s.size}|${s.modified.millisecondsSinceEpoch}|$lato');
    // Due caratteri di sottocartella: centomila file in una cartella sola
    // rallentano ogni `readdir`, compresi i nostri.
    return '$cartellaCache/${chiave.substring(0, 2)}/$chiave.jpg';
  }

  /// FNV-1a a 64 bit, come già `custodia/registro.dart`. Non è una firma
  /// crittografica e non deve esserlo: deve solo cambiare quando cambia
  /// l'ingresso.
  static String _impronta(String s) {
    var h = 0xcbf29ce484222325;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  /// Quanto occupa la cache, in byte.
  int quantoOccupa() {
    var totale = 0;
    final d = Directory(cartellaCache);
    if (!d.existsSync()) return 0;
    for (final v in d.listSync(recursive: true, followLinks: false)) {
      if (v is File) {
        try {
          totale += v.lengthSync();
        } catch (_) {}
      }
    }
    return totale;
  }

  /// Butta le più vecchie finché non si rientra sotto il tetto.
  ///
  /// Si guarda l'ultimo **accesso**, non l'ultima scrittura: una miniatura
  /// scritta un anno fa ma guardata ieri è quella che serve di più.
  int pota() {
    final d = Directory(cartellaCache);
    if (!d.existsSync()) return 0;
    final file = <FileSystemEntity>[];
    var totale = 0;
    for (final v in d.listSync(recursive: true, followLinks: false)) {
      if (v is! File) continue;
      try {
        totale += v.lengthSync();
        file.add(v);
      } catch (_) {}
    }
    if (totale <= tettoByte) return 0;

    file.sort((a, b) {
      try {
        return a.statSync().accessed.compareTo(b.statSync().accessed);
      } catch (_) {
        return 0;
      }
    });

    var buttati = 0;
    for (final v in file) {
      if (totale <= tettoByte) break;
      try {
        final quanto = (v as File).lengthSync();
        v.deleteSync();
        totale -= quanto;
        buttati++;
      } catch (_) {}
    }
    return buttati;
  }

  /// Butta tutto. Le scelte dell'utente NON stanno qui — stanno nella
  /// configurazione — quindi svuotare la cache non perde niente di suo.
  void svuota() {
    final d = Directory(cartellaCache);
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  static Map<String, dynamic> _no(String perche) =>
      {'ok': false, 'error': perche};
}

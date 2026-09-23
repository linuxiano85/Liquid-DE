import 'dart:io';

import 'riordino.dart';

/// Che cosa è successo davvero a ogni file.
class Fatto {
  final String da;
  final String a;
  final String errore;

  const Fatto({required this.da, required this.a, this.errore = ''});

  bool get riuscito => errore.isEmpty;

  Map<String, dynamic> toJson() =>
      {'da': da, 'a': a, if (errore.isNotEmpty) 'errore': errore};
}

/// Esegue un piano di riordino: **copia**, oppure **sposta**.
///
/// ── Perché due modi, e perché quello che serve è il secondo ──────────────
///
/// `sposta` è quello che uno vuole per davvero: `rename(2)` sullo stesso
/// filesystem è istantaneo e non lascia doppioni.
///
/// `copia` esiste **per potersi fidare del primo**. Si riordina una copia in
/// una cartella temporanea, si confronta che nessun file sia sparito e che i
/// conteggi tornino, e si guarda che gli originali siano intatti — senza aver
/// toccato una sola fotografia vera. Su btrfs non costa nemmeno spazio:
/// `cp --reflink` fa due nomi per gli stessi dati.
///
/// È l'idea di Giacomo del 26 agosto 2026, ed è la ragione per cui questa
/// parte è provabile invece che sperabile.
///
/// ── E perché «sposta» non parte senza un punto di ritorno ────────────────
///
/// Perché è la regola della casa: nessuna operazione che può perdere lavoro
/// parte senza un punto di ritorno. Qui è scritta come un **rifiuto**, non
/// come una raccomandazione — `puntoDiRitorno` è obbligatorio in modalità
/// `sposta`, e se torna falso non si muove niente.
///
/// In modalità `copia` non serve e non si chiede: gli originali non si
/// toccano, e chiedere un punto di ritorno per una cosa che non perde niente
/// insegnerebbe a dire di sì senza guardare.
class RiordinoMotore {
  /// `copia` o `sposta`.
  final String modo;

  /// Deve tornare `true` perché uno spostamento cominci. Chiamato **una
  /// volta sola**, prima di toccare qualunque cosa.
  final Future<bool> Function()? puntoDiRitorno;

  const RiordinoMotore({this.modo = 'copia', this.puntoDiRitorno});

  bool get sposta => modo == 'sposta';

  /// Esegue. `avanza` viene chiamata ogni tanto: `(fatti, totale)`.
  Future<Map<String, dynamic>> esegui(
    List<Passo> piano, {
    void Function(int fatti, int totale)? avanza,
  }) async {
    if (modo != 'copia' && modo != 'sposta') {
      return _no('Non so cosa voglia dire «$modo»: o «copia» o «sposta».');
    }

    final daFare = piano.where((p) => p.siFa).toList();
    if (daFare.isEmpty) {
      return _no('Non c\'è niente da fare: tutte le fotografie del piano sono '
          'state rifiutate. Guarda i motivi prima di riprovare.');
    }

    // ── Il rifiuto che conta ─────────────────────────────────────────────
    if (sposta) {
      if (puntoDiRitorno == null) {
        return _no('Non sposto niente senza un punto di ritorno. È la regola '
            'della casa, e vale soprattutto qui: uno spostamento sbagliato si '
            'scopre domani, quando non si sa più dov\'erano.');
      }
      final fatto = await puntoDiRitorno!();
      if (!fatto) {
        return _no('Il punto di ritorno non è riuscito: non sposto niente.');
      }
    }

    // ── E il rifiuto che nessuno si aspetta ──────────────────────────────
    //
    // Due file dello stesso piano che finiscono nello stesso posto sono una
    // fotografia persa. `Riordino.piano()` già li separa col «-2», ma questo
    // motore può ricevere un piano scritto da qualcun altro — o modificato a
    // mano nell'anteprima — e a quel punto sarebbe l'ultimo a poterlo vedere.
    final destinazioni = <String>{};
    for (final p in daFare) {
      if (!destinazioni.add(p.a)) {
        return _no('Due fotografie finirebbero nello stesso posto '
            '(«${p.a}»). Non faccio niente: così se ne perderebbe una.');
      }
    }

    final fatti = <Fatto>[];
    var quanti = 0;
    for (final p in daFare) {
      fatti.add(await _uno(p));
      quanti++;
      if (avanza != null && quanti % 10 == 0) avanza(quanti, daFare.length);
    }

    final falliti = fatti.where((f) => !f.riuscito).toList();
    return {
      'ok': falliti.isEmpty,
      'modo': modo,
      'fatti': fatti.length - falliti.length,
      'falliti': falliti.length,
      'dettagli': [for (final f in falliti) f.toJson()],
    };
  }

  Future<Fatto> _uno(Passo p) async {
    try {
      final origine = File(p.da);
      if (!await origine.exists()) {
        return Fatto(da: p.da, a: p.a, errore: 'non c\'è più');
      }
      // La cartella di destinazione, se manca. `recursive` perché la
      // struttura è `2026/03 marzo/07` e nasce tutta insieme.
      await Directory(_cartellaDi(p.a)).create(recursive: true);

      // ── Non si sovrascrive MAI ───────────────────────────────────────
      //
      // Il piano evita le collisioni fra i suoi passi, ma non sa che cosa c'è
      // già nella cartella di destinazione da ieri. Trovare qualcosa lì non è
      // un caso da risolvere in silenzio: si dice e si salta.
      if (await File(p.a).exists()) {
        return Fatto(
            da: p.da, a: p.a, errore: 'lì c\'è già un file: non lo sovrascrivo');
      }

      if (sposta) {
        try {
          await origine.rename(p.a);
        } on FileSystemException {
          // `rename` non attraversa i filesystem: fra il disco e una
          // chiavetta bisogna copiare e poi togliere. E si toglie SOLO se la
          // copia è riuscita — o si perde il file in mezzo.
          await _copia(p.da, p.a);
          await origine.delete();
        }
      } else {
        await _copia(p.da, p.a);
      }
      return Fatto(da: p.da, a: p.a);
    } catch (e) {
      return Fatto(da: p.da, a: p.a, errore: '$e');
    }
  }

  /// Copia, chiedendo il reflink quando c'è.
  ///
  /// `cp --reflink=auto` su btrfs non copia i dati: fa due nomi per gli stessi
  /// blocchi, quindi è istantaneo e non occupa spazio. Su un filesystem che
  /// non lo sa fare, `auto` copia normalmente invece di fallire — che è
  /// esattamente il comportamento voluto: la prova deve poter girare ovunque.
  static Future<void> _copia(String da, String a) async {
    final r = await Process.run('cp', ['--reflink=auto', '-p', '--', da, a]);
    if (r.exitCode == 0) return;
    // Niente `cp`: si copia in Dart. Più lento e senza reflink, ma funziona.
    await File(da).copy(a);
  }

  static String _cartellaDi(String percorso) {
    final i = percorso.lastIndexOf('/');
    return i <= 0 ? '/' : percorso.substring(0, i);
  }

  static Map<String, dynamic> _no(String perche) =>
      {'ok': false, 'error': perche};
}

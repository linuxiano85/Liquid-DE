import 'dart:io';
import '../core/minerva_paths.dart';

/// Lo sfondo già sfocato, calcolato una volta sola.
///
/// ── Perché un'immagine e non un effetto ─────────────────────────────────
///
/// Il «vetro» dietro la barra e la dock è la cosa che in Hyprland costava di
/// più: `blur { size = 4, passes = 2 }` sono due passaggi a schermo pieno
/// dietro ogni superficie appoggiata, **a ogni fotogramma, per sempre**,
/// batteria compresa, su una Intel Iris Plus G1 integrata.
///
/// E nella shell di Minerva non si potrebbe nemmeno fare: gira con
/// `QT_QUICK_BACKEND=software` — vale 38 MB — e col processore un
/// `layer.effect` non esiste. Verificato il 31 agosto 2026 anche la strada
/// nuova di Qt 6.8, `ShapePath.fillItem`: col renderer software la forma esce
/// **vuota**, mentre la stessa forma con un colore pieno si disegna
/// perfettamente. Misurato con una cattura, non supposto.
///
/// Un'immagine invece si disegna eccome. Si calcola quando cambia lo sfondo e
/// si tiene in cache: **costo a fotogramma zero**.
///
/// ── Cosa si perde, detto subito ─────────────────────────────────────────
///
/// Il vero vetro mostra le finestre che ci passano sotto; questo mostra lo
/// sfondo. La differenza è più piccola di quanto sembri: la barra ha una zona
/// riservata di layer-shell, quindi le finestre normali **non ci passano
/// sotto** — sotto c'è lo sfondo, sempre. Si perde solo dietro le finestre a
/// schermo intero, dove la barra si nasconde comunque.
class Vetro {
  /// Dove si tengono le copie sfocate. Iniettabile: una prova non deve
  /// scrivere nella cache vera, e soprattutto non deve poterla cancellare.
  final String cartellaCache;

  /// Il seme per le prove: `magick` non deve girare davvero quando si prova
  /// la logica.
  final Future<ProcessResult> Function(String, List<String>) esegui;

  Vetro({
    String? cartellaCache,
    Future<ProcessResult> Function(String, List<String>)? esegui,
  })  : cartellaCache = cartellaCache ?? _cartellaVera(),
        esegui = esegui ?? Process.run;

  static String _cartellaVera() {
    return '${MinervaPaths.cache()}/vetro';
  }

  /// ── Quanto si sfoca, e perché così ──────────────────────────────────
  ///
  /// Prima si RIMPICCIOLISCE a 320 pixel di larghezza, poi si sfoca poco.
  /// Sfocare a piena risoluzione con un raggio grande costa secondi; ridurre
  /// prima fa quasi tutto il lavoro da solo — la riduzione È una media — e la
  /// sfocatura dopo toglie la scalettatura che resterebbe.
  ///
  /// L'immagine finita pesa qualche decina di kilobyte e viene ringrandita da
  /// Qt quando la disegna. Nessuno guarda il vetro cercando il dettaglio: se
  /// lo si vedesse nitido non sarebbe vetro.
  static const int larghezzaRidotta = 320;
  static const String raggio = '0x8';

  /// Quante copie si tengono. Oltre, se ne vanno le più vecchie.
  ///
  /// La chiave della cache comprende la data di modifica, quindi ogni sfondo
  /// nuovo — e ogni ritocco di uno vecchio — aggiunge un file e non ne toglie
  /// nessuno. Con la rotazione degli sfondi accesa la cartella cresce a ogni
  /// fotografia che entra nella cartella degli sfondi.
  ///
  /// Sono decine di kilobyte l'uno, quindi non è un'emergenza — ma «non si
  /// pota mai» è una frase che invecchia male, e la potatura costa una
  /// lettura di cartella ogni volta che se ne calcola una nuova, cioè quasi
  /// mai.
  ///
  /// Quaranta è largo: gli sfondi di questa macchina sono meno.
  static const int quanteSeNeTengono = 40;

  /// La chiave della cache: percorso, dimensione e data di modifica.
  ///
  /// La data serve: cambiare l'immagine lasciandole lo stesso nome è quello
  /// che fa uno che ritocca lo sfondo, e senza la data si continuerebbe a
  /// mostrare la sfocatura di ieri per sempre.
  static String chiaveDi(String percorso, int byte, int modificatoMs) {
    var h = 0xcbf29ce484222325;
    for (final c in '$percorso|$byte|$modificatoMs'.codeUnits) {
      h ^= c;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(16, '0');
  }

  String percorsoDi(String chiave) => '$cartellaCache/$chiave.png';

  /// La copia sfocata di uno sfondo. Restituisce **un percorso**, non dei
  /// byte: la shell la disegna da lì, e il canale non si porta dietro
  /// megabyte in base64.
  Future<Map<String, dynamic>> per(String? sfondo) async {
    final p = (sfondo ?? '').trim();
    if (p.isEmpty || !p.startsWith('/')) {
      return _no('mi serve il percorso completo di uno sfondo');
    }
    final f = File(p);
    if (!await f.exists()) {
      return _no('«$p» non c\'è');
    }
    final st = await f.stat();
    final chiave = chiaveDi(p, st.size, st.modified.millisecondsSinceEpoch);
    final dove = percorsoDi(chiave);

    final gia = File(dove);
    if (await gia.exists() && await gia.length() > 0) {
      return {'ok': true, 'percorso': dove, 'da': 'cache'};
    }

    await Directory(cartellaCache).create(recursive: true);

    // `[0]` perché un'immagine può avere più fotogrammi — una GIF, un TIFF a
    // pagine — e senza, `magick` scriverebbe un file per ognuno e il nostro
    // non esisterebbe. È la stessa insidia già pagata dalle miniature.
    final r = await esegui('magick', [
      '$p[0]',
      '-resize', '${larghezzaRidotta}x',
      '-blur', raggio,
      '-strip',
      dove,
    ]);
    // Un codice di uscita zero non basta: `magick` sa uscire bene senza aver
    // scritto niente. Si guarda il file.
    if (r.exitCode != 0 || !await gia.exists() || await gia.length() == 0) {
      // Il file mezzo scritto non si lascia in giro: alla prossima richiesta
      // sembrerebbe una cache buona.
      if (await gia.exists()) await gia.delete();
      return _no('non sono riuscito a sfocare «$p»: '
          '${(r.stderr ?? '').toString().trim()}');
    }
    await _pota();
    return {'ok': true, 'percorso': dove, 'da': 'magick'};
  }

  // ── Qui c'era `perSchermo()`: provata e scartata ─────────────────────
  //
  // Preparava una copia dello sfondo già della misura dello schermo, perché la
  // shell non dovesse aprire un JPEG da otto milioni di pixel. Su una sonda
  // isolata valeva diciannove megabyte per riquadro; nella shell vera,
  // misurata due volte, non ha reso niente — 131 MB con la copia contro 127
  // con l'originale.
  //
  // Tolta il 2 settembre 2026, lo stesso giorno in cui è stata scritta. Il
  // racconto e i numeri stanno in `minerva-shell/menu/WallpaperLayer.qml`, che
  // è dove andrà a leggere chi ci riproverà.

  /// Butta le copie più vecchie oltre il tetto.
  ///
  /// Si ordina per data di ULTIMA MODIFICA e non per data d'uso: `mtime` è
  /// l'unica delle due che esiste davvero senza doverla tenere noi, e per una
  /// cache che si riempie una voce per sfondo le due coincidono quasi sempre.
  ///
  /// Non lancia mai: una potatura che fallisce non deve impedire di
  /// consegnare la sfocatura che il chiamante ha appena aspettato.
  Future<void> _pota() async {
    try {
      final d = Directory(cartellaCache);
      if (!await d.exists()) return;
      final file = <File>[];
      await for (final v in d.list(followLinks: false)) {
        // `.png` è la copia sfocata, l'unico prodotto di questa cache. I
        // `.jpg` restano nell'elenco perché il 2 settembre 2026 ci sono
        // finiti dentro — una copia dello sfondo alla misura dello schermo,
        // provata e scartata lo stesso giorno — e su questa macchina ce n'è
        // rimasto uno. Senza questa riga resterebbe lì per sempre: la
        // potatura guarderebbe accanto e non lo vedrebbe.
        if (v is File &&
            (v.path.endsWith('.png') || v.path.endsWith('.jpg'))) {
          file.add(v);
        }
      }
      if (file.length <= quanteSeNeTengono) return;

      final conData = <MapEntry<File, DateTime>>[];
      for (final f in file) {
        conData.add(MapEntry(f, (await f.stat()).modified));
      }
      conData.sort((a, b) => b.value.compareTo(a.value));
      for (final v in conData.skip(quanteSeNeTengono)) {
        try {
          await v.key.delete();
        } on FileSystemException {
          // Qualcuno l'ha già tolto, o non è nostro: si tira avanti.
        }
      }
    } on FileSystemException {
      // La cartella non si legge. Peggio per la potatura, non per la
      // sfocatura.
    }
  }

  static Map<String, dynamic> _no(String perche) =>
      {'ok': false, 'error': perche};
}

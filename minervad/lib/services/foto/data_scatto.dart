import 'dart:io';

import 'exif.dart';

/// Quanto crediamo alla data che abbiamo trovato.
///
/// L'ordine conta: `Fiducia.values.indexOf` è la graduatoria, e più in alto
/// vuol dire più affidabile.
enum Fiducia {
  /// Scritta dalla macchina al momento dello scatto.
  certa,

  /// Scritta nel nome del file da chi l'ha creato — telefono, sistema, app.
  probabile,

  /// Dedotta dal nome della cartella.
  incerta,

  /// La data di modifica del file. Dice quando è stato copiato, non quando è
  /// stato scattato.
  ultimaSpiaggia,

  /// Non lo sappiamo.
  nessuna,
}

/// Una data, la sua provenienza, e il dubbio.
///
/// ── Perché non restituisce solo una data ───────────────────────────────────
///
/// Perché una data senza la sua provenienza non si può né controllare né
/// correggere. Le 826 foto di questa casa hanno tutte lo stesso `mtime` —
/// 8 luglio 2026, il momento della copia dal telefono — e un programma che
/// restituisse quel valore come «la data» sarebbe sicuro di sé e sbagliato su
/// ogni singolo file.
///
/// Chi rinomina o sposta guarda [fiducia] e [daControllare] prima di toccare
/// qualcosa. È l'unica difesa che abbiamo: il nome di un file è per certe foto
/// l'unica prova della data che esista, e riscriverlo su una supposizione non
/// si annulla.
class DataScatto {
  final DateTime? quando;
  final Fiducia fiducia;

  /// `exif`, `video`, `nome`, `cartella`, `mtime`, oppure vuota.
  final String fonte;

  /// Due fonti attendibili dicono cose diverse. La data c'è lo stesso — si usa
  /// la migliore — ma **non si rinomina e non si sposta** finché qualcuno non
  /// ha guardato.
  final bool daControllare;

  /// Tutto quello che ogni fonte ha detto, per poterlo mostrare a chi decide.
  final Map<String, DateTime> proposte;

  const DataScatto({
    this.quando,
    this.fiducia = Fiducia.nessuna,
    this.fonte = '',
    this.daControllare = false,
    this.proposte = const {},
  });

  static const DataScatto ignota = DataScatto();

  bool get sicura => fiducia == Fiducia.certa && !daControllare;

  /// Si può riordinare o rinominare su questa data?
  ///
  /// No se è contesa, e no se l'unica cosa che sappiamo è quando il file è
  /// stato copiato.
  bool get sipuoAgire =>
      quando != null &&
      !daControllare &&
      fiducia != Fiducia.ultimaSpiaggia &&
      fiducia != Fiducia.nessuna;

  Map<String, dynamic> toJson() => {
        if (quando != null) 'quando': quando!.toIso8601String(),
        'fiducia': fiducia.name,
        'fonte': fonte,
        if (daControllare) 'daControllare': true,
        if (proposte.length > 1)
          'proposte': proposte
              .map((k, v) => MapEntry(k, v.toIso8601String())),
      };
}

/// Trova la data di scatto di una fotografia o di un video.
///
/// ── Le tre regole ──────────────────────────────────────────────────────────
///
/// 1. **Le fonti si incrociano, non si prende la prima.** Se l'EXIF e il nome
///    del file discordano di più di un giorno, la data entra lo stesso ma
///    marcata «da controllare».
/// 2. **Un `mtime` condiviso da molti file non è una data.** Si guarda tutto il
///    lotto: se venti o più file cadono nello stesso minuto, quella fonte viene
///    dichiarata inutilizzabile per tutti loro. Senza questa regola il
///    programma crederebbe di sapere.
/// 3. **Il fuso si dichiara.** L'EXIF senza `OffsetTime` è l'ora dell'orologio
///    della macchina; `ffprobe` risponde in UTC. Si porta tutto all'ora locale,
///    e si conserva da dove viene.
class Datatore {
  /// Il seme per le prove: `ffprobe` non deve girare davvero in una prova.
  final Future<ProcessResult> Function(String, List<String>) esegui;

  Datatore({Future<ProcessResult> Function(String, List<String>)? esegui})
      : esegui = esegui ?? Process.run;

  /// Quanti file devono cadere nella stessa finestra perché `mtime` smetta di
  /// essere una data. Venti è basso di proposito: una macchina fotografica non
  /// scrive venti file in un minuto, una copia sì.
  static const int copieNellaFinestra = 20;

  /// Quanto è larga la finestra, in secondi.
  ///
  /// Un minuto, e la prima versione sbagliava proprio qui: contava per
  /// **secondo esatto**. Ma una copia dal telefono non arriva in un secondo —
  /// questa si è spalmata su 24 minuti, 102 secondi distinti, al massimo 47
  /// file nello stesso. Contando per secondo la regola scattava solo a tratti,
  /// e 74 fotografie di Snapchat sono passate sotto: sono finite tutte
  /// nell'8 luglio, il giorno della copia, con l'aria di esserci state
  /// scattate. Con la finestra da un minuto, quei sei minuti coprono 801 file
  /// su 826 e la fonte viene dichiarata inutilizzabile, che è la verità.
  static const int finestraSecondi = 60;

  /// Decide per un lotto intero, perché la regola 2 si può applicare solo
  /// guardando tutti insieme.
  ///
  /// [candidati] è `{percorso: {exif, video, mtime}}` già raccolto da chi legge
  /// i file: qui non si tocca il disco, così questa parte si prova senza avere
  /// una fotografia.
  static Map<String, DataScatto> perLotto(Map<String, Candidato> candidati) {
    final sospetti = secondiDiCopia([
      for (final c in candidati.values)
        if (c.mtime != null) c.mtime!.millisecondsSinceEpoch ~/ 1000,
    ]);

    return {
      for (final e in candidati.entries)
        e.key: decidi(
          percorso: e.key,
          exif: e.value.exif,
          video: e.value.video,
          mtime: e.value.mtime,
          mtimeUsabile: e.value.mtime == null ||
              !sospetti.contains(e.value.mtime!.millisecondsSinceEpoch ~/ 1000),
        ),
    };
  }

  /// I secondi che sanno di copia: quelli attorno a cui, in una finestra di un
  /// minuto, si affollano troppi file.
  ///
  /// Finestra scorrevole e non «bucato per minuto», perché venti file a cavallo
  /// di un minuto si dividerebbero in dieci e dieci e passerebbero.
  ///
  /// È pubblico perché l'indice lo chiama **dopo il cammino e prima di leggere
  /// un solo EXIF**: a quel punto conosce già tutti gli `mtime`, e così ogni
  /// file può ricevere subito la sua risposta definitiva invece di una
  /// provvisoria da correggere alla fine.
  static Set<int> secondiDiCopia(List<int> secondi) {
    if (secondi.length < copieNellaFinestra) return const {};
    final ordinati = List<int>.from(secondi)..sort();
    final sospetti = <int>{};
    var da = 0;
    for (var a = 0; a < ordinati.length; a++) {
      while (ordinati[a] - ordinati[da] > finestraSecondi) {
        da++;
      }
      if (a - da + 1 >= copieNellaFinestra) {
        for (var k = da; k <= a; k++) {
          sospetti.add(ordinati[k]);
        }
      }
    }
    return sospetti;
  }

  /// La decisione per un file solo. Pura: nessuna lettura, nessun processo.
  static DataScatto decidi({
    required String percorso,
    DateTime? exif,
    DateTime? video,
    DateTime? mtime,
    bool mtimeUsabile = true,
  }) {
    final nome = percorso.split('/').last;
    final dalNome = daNome(nome);
    final dallaCartella = daCartella(percorso);

    final proposte = <String, DateTime>{
      'exif': ?exif,
      'video': ?video,
      'nome': ?dalNome,
      'cartella': ?dallaCartella,
      'mtime': ?mtime,
    };

    // ── Regola 1: le fonti attendibili si incrociano ─────────────────────
    //
    // Si confronta solo ciò che pretende di sapere l'ora dello scatto. La
    // cartella e l'mtime non entrano nel confronto: non discordano, sanno
    // meno.
    final certa = exif ?? video;
    var contesa = false;
    if (certa != null && dalNome != null) {
      contesa = certa.difference(dalNome).abs() > const Duration(hours: 24);
    }

    if (certa != null) {
      return DataScatto(
        quando: certa,
        fiducia: Fiducia.certa,
        fonte: exif != null ? 'exif' : 'video',
        daControllare: contesa,
        proposte: proposte,
      );
    }
    if (dalNome != null) {
      return DataScatto(
        quando: dalNome,
        fiducia: Fiducia.probabile,
        fonte: 'nome',
        proposte: proposte,
      );
    }
    if (dallaCartella != null) {
      return DataScatto(
        quando: dallaCartella,
        fiducia: Fiducia.incerta,
        fonte: 'cartella',
        proposte: proposte,
      );
    }
    // ── Regola 2 ─────────────────────────────────────────────────────────
    if (mtime != null && mtimeUsabile) {
      return DataScatto(
        quando: mtime,
        fiducia: Fiducia.ultimaSpiaggia,
        fonte: 'mtime',
        proposte: proposte,
      );
    }
    return DataScatto(proposte: proposte);
  }

  // ── Gli schemi dei nomi ────────────────────────────────────────────────
  //
  // Non sono inventati: sono stati contati sulla libreria vera, il 26 agosto
  // 2026. A destra quanti file di Giacomo cadono in ognuno.

  /// `IMG_20260317_112727.jpg`, `VID_20260222_211501.mp4` — 471 file.
  /// Vale anche per PXL (Pixel), MVIMG, PANO, BURST.
  static final RegExp _telefono =
      RegExp(r'(?:IMG|VID|MVIMG|PXL|PANO|BURST|SVID)[_-](\d{8})[_-](\d{6})');

  /// `Screenshot_2026-05-13-12-41-08-468_com.whatsapp.jpg` — 130 file.
  static final RegExp _schermataAndroid =
      RegExp(r'(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})');

  /// `IMG-20260317-WA0001.jpg` — WhatsApp. Nessuna ora: mezzogiorno, che è il
  /// punto meno sbagliato di un giorno di cui si sa solo il giorno.
  static final RegExp _whatsapp = RegExp(r'IMG-(\d{8})-WA\d+');

  /// `1778685238462.mp4` — millisecondi dal 1970. Verificato: coincide con
  /// quello che dice `ffprobe` sullo stesso file.
  static final RegExp _millisecondi = RegExp(r'^(\d{13})(?:\D|$)');

  /// `Schermata 2026-08-16 alle 21.03.45.png` — le nostre, dal pannello di
  /// Stamp. Anche `2026-08-16 alle 21.03.45`.
  static final RegExp _nostra =
      RegExp(r'(\d{4})-(\d{2})-(\d{2})\s+(?:alle|at)\s+(\d{2})\.(\d{2})\.(\d{2})');

  /// L'ultima rete: `20260513_171320`, `2026-05-13 17.13.20`,
  /// `2026_05_13-17_13_20`. Data e ora attaccate, con un separatore qualsiasi.
  static final RegExp _generico = RegExp(
      r'(\d{4})[-_.]?(\d{2})[-_.]?(\d{2})[-_.T ]{1,3}(\d{2})[-_.:]?(\d{2})[-_.:]?(\d{2})');

  /// Solo il giorno: `20260513`, `2026-05-13`.
  static final RegExp _soloGiorno = RegExp(r'(?:^|\D)(\d{4})[-_.]?(\d{2})[-_.]?(\d{2})(?:\D|$)');

  /// La data scritta nel nome del file, se c'è.
  static DateTime? daNome(String nome) {
    final senzaCoda = nome.contains('.')
        ? nome.substring(0, nome.lastIndexOf('.'))
        : nome;

    var m = _telefono.firstMatch(senzaCoda);
    if (m != null) {
      return _componi(m.group(1)!, m.group(2)!);
    }

    m = _nostra.firstMatch(senzaCoda);
    if (m != null) return _daPezzi(m, 1);

    m = _schermataAndroid.firstMatch(senzaCoda);
    if (m != null) return _daPezzi(m, 1);

    m = _whatsapp.firstMatch(senzaCoda);
    if (m != null) return _componi(m.group(1)!, '120000');

    m = _millisecondi.firstMatch(senzaCoda);
    if (m != null) {
      final ms = int.tryParse(m.group(1)!);
      if (ms != null) {
        return _seCredibile(DateTime.fromMillisecondsSinceEpoch(ms));
      }
    }

    m = _generico.firstMatch(senzaCoda);
    if (m != null) {
      final d = _daPezzi(m, 1);
      if (d != null) return d;
    }

    m = _soloGiorno.firstMatch(senzaCoda);
    if (m != null) {
      return _componi('${m.group(1)}${m.group(2)}${m.group(3)}', '120000');
    }

    return null;
  }

  /// `2019-08 Vacanze in Puglia/`, `2019/`, `Foto 2019-08-13/`.
  ///
  /// Vale il primo antenato che somiglia a una data, partendo dal più vicino:
  /// una cartella `2019` dentro `Foto 2018` non deve prendere il 2018.
  static DateTime? daCartella(String percorso) {
    final pezzi = percorso.split('/');
    if (pezzi.length < 2) return null;
    for (var i = pezzi.length - 2; i >= 0; i--) {
      final c = pezzi[i];
      if (c.isEmpty) continue;
      var m = RegExp(r'(?:^|\D)(\d{4})[-_.](\d{2})[-_.](\d{2})(?:\D|$)')
          .firstMatch(c);
      if (m != null) {
        final d = _giorno(int.parse(m.group(1)!), int.parse(m.group(2)!),
            int.parse(m.group(3)!), 12, 0, 0);
        if (d != null) return d;
      }
      m = RegExp(r'(?:^|\D)(\d{4})[-_.](\d{2})(?:\D|$)').firstMatch(c);
      if (m != null) {
        final d = _giorno(
            int.parse(m.group(1)!), int.parse(m.group(2)!), 1, 12, 0, 0);
        if (d != null) return d;
      }
      m = RegExp(r'^(\d{4})$').firstMatch(c.trim());
      if (m != null) {
        final d = _giorno(int.parse(m.group(1)!), 1, 1, 12, 0, 0);
        if (d != null) return d;
      }
    }
    return null;
  }

  /// Data, misure e durata di un video, in una chiamata sola.
  ///
  /// `ffprobe` costa circa 85 ms: è il pezzo più caro di tutta la scansione, e
  /// chiamarlo due volte — una per la data e una per le misure — raddoppierebbe
  /// il tempo della prima apertura.
  Future<Map<String, dynamic>> dettagliVideo(String percorso) async {
    try {
      final r = await esegui('ffprobe', [
        '-v', 'quiet',
        '-select_streams', 'v:0',
        '-show_entries', 'format_tags=creation_time:format=duration:stream=width,height',
        '-of', 'default=noprint_wrappers=1',
        '--', percorso,
      ]);
      if (r.exitCode != 0) return const {};
      final campi = <String, String>{};
      for (final riga in '${r.stdout}'.split('\n')) {
        final i = riga.indexOf('=');
        if (i > 0) campi[riga.substring(0, i).trim()] = riga.substring(i + 1).trim();
      }
      final grezza = campi['TAG:creation_time'] ?? campi['creation_time'] ?? '';
      final quando = grezza.isEmpty ? null : DateTime.tryParse(grezza);
      return {
        'quando': quando == null ? null : _seCredibile(quando.toLocal()),
        'larghezza': int.tryParse(campi['width'] ?? '') ?? 0,
        'altezza': int.tryParse(campi['height'] ?? '') ?? 0,
        'durataMs':
            ((double.tryParse(campi['duration'] ?? '') ?? 0) * 1000).round(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// La data del contenitore di un video.
  ///
  /// `ffprobe` risponde in UTC — verificato: `VID_20260222_211501.mp4` dice
  /// `2026-02-22T20:15:06Z`, che sono le 21:15 qui. Convertirla è obbligatorio,
  /// e dimenticarsene sposta ogni video di un'ora o due, cioè a volte di un
  /// giorno.
  Future<DateTime?> daVideo(String percorso) async {
    try {
      final r = await esegui('ffprobe', [
        '-v', 'quiet',
        '-show_entries', 'format_tags=creation_time',
        '-of', 'default=noprint_wrappers=1:nokey=1',
        '--', percorso,
      ]);
      if (r.exitCode != 0) return null;
      final t = '${r.stdout}'.trim();
      if (t.isEmpty) return null;
      final d = DateTime.tryParse(t);
      if (d == null) return null;
      // Alcuni contenitori scrivono l'anno zero quando il campo è vuoto.
      return _seCredibile(d.toLocal());
    } catch (_) {
      return null;
    }
  }

  /// È una schermata, non un ricordo?
  ///
  /// 162 file di questa casa sono schermate di telefono. Senza saperlo
  /// distinguere, la linea del tempo non è fatta di ricordi ma di conversazioni
  /// di WhatsApp fotografate.
  static bool eSchermata(String nome, {bool haExif = false}) {
    final n = nome.toLowerCase();
    if (n.startsWith('screenshot') ||
        n.startsWith('schermata') ||
        n.startsWith('screen shot') ||
        n.startsWith('scrn')) {
      return true;
    }
    // Una macchina fotografica scrive sempre l'EXIF. Chi non ce l'ha e sta in
    // una cartella che si chiama Screenshots, non è una fotografia.
    return !haExif && n.contains('screenshot');
  }

  // ── Il montaggio delle date, con i controlli ───────────────────────────

  static DateTime? _componi(String aaaammgg, String hhmmss) {
    if (aaaammgg.length != 8 || hhmmss.length < 6) return null;
    return _giorno(
      int.parse(aaaammgg.substring(0, 4)),
      int.parse(aaaammgg.substring(4, 6)),
      int.parse(aaaammgg.substring(6, 8)),
      int.parse(hhmmss.substring(0, 2)),
      int.parse(hhmmss.substring(2, 4)),
      int.parse(hhmmss.substring(4, 6)),
    );
  }

  static DateTime? _daPezzi(RegExpMatch m, int primo) => _giorno(
        int.parse(m.group(primo)!),
        int.parse(m.group(primo + 1)!),
        int.parse(m.group(primo + 2)!),
        int.parse(m.group(primo + 3)!),
        int.parse(m.group(primo + 4)!),
        int.parse(m.group(primo + 5)!),
      );

  /// Costruisce una data solo se esiste davvero e se è credibile.
  ///
  /// `DateTime(2026, 2, 31)` in Dart non è un errore: diventa il 3 marzo. Un
  /// nome di file sbagliato passerebbe per una data valida e finirebbe nel mese
  /// dopo, in silenzio.
  static DateTime? _giorno(int a, int me, int g, int o, int mi, int s) {
    if (me < 1 || me > 12 || g < 1 || g > 31) return null;
    if (o > 23 || mi > 59 || s > 59) return null;
    final d = DateTime(a, me, g, o, mi, s);
    if (d.month != me || d.day != g) return null;
    return _seCredibile(d);
  }

  /// Una fotografia non è stata scattata nel 1837 né la settimana prossima.
  ///
  /// Serve soprattutto ai millisecondi: tredici cifre qualunque danno sempre
  /// *una* data, e senza questo controllo un numero di serie diventerebbe una
  /// data di scatto.
  static DateTime? _seCredibile(DateTime d) {
    if (d.year < 1990) return null;
    if (d.isAfter(DateTime.now().add(const Duration(days: 2)))) return null;
    return d;
  }
}

/// Quello che si è riusciti a leggere da un file, prima di decidere.
class Candidato {
  final DateTime? exif;
  final DateTime? video;
  final DateTime? mtime;
  const Candidato({this.exif, this.video, this.mtime});

  /// Comodità: da un file già letto.
  factory Candidato.da(DatiExif e, DateTime? mtime, {DateTime? video}) =>
      Candidato(exif: e.scattata, video: video, mtime: mtime);
}

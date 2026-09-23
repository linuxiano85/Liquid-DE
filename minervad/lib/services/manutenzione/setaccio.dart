import 'dart:io';

import '../foto/doppioni.dart';
import '../foto/indice.dart';

/// Passa al setaccio la cartella di casa e trova i file che ci sono due volte.
///
/// ── Perché in Manutenzione e non nella Galleria ────────────────────────────
///
/// Giacomo, 9 settembre 2026: «la nostra fa pulizia? ma solo pulizia ma anche
/// riordino della cartella utente che è sempre una pulizia, file doppi, file
/// sparsi [...] ne parlammo per la galleria ma io la farei qui».
///
/// Ha ragione, e il motivo si vede nei numeri di questa macchina: dei 6,94 GB
/// di doppioni, la parte grossa sono video del telefono copiati tre volte —
/// ma dentro ci sono anche ISO, archivi e librerie compilate. Una funzione
/// che guarda solo le fotografie ne troverebbe metà, e chi la usa non
/// saprebbe nemmeno che l'altra metà esiste.
///
/// ── Cosa NON guarda, e perché è la decisione più importante ────────────────
///
/// Il codice. `~/Documenti/Progetti` da solo è 292 GB e 2,5 milioni di file, e
/// dentro un progetto i doppioni sono **normali**: `node_modules` ripete le
/// stesse librerie in ogni progetto, una compilazione ripete i suoi prodotti
/// in `build/`, e `.git` tiene apposta più copie della stessa cosa. Mostrarli
/// vorrebbe dire annegare le tre copie del telefono in decine di migliaia di
/// righe che non si devono toccare — e prima o poi qualcuno le toccherebbe.
///
/// Le cartelle nascoste restano fuori per la stessa ragione: `.cache`,
/// `.local`, `.var` sono roba dei programmi, e quella la guarda l'inventario.
class Setaccio {
  Setaccio({
    String? casa,
    this.soglia = 100 * 1024,
    this.escluse = const [],
    this.racconta,
  }) : casa = casa ?? (Platform.environment['HOME'] ?? '/root');

  final String casa;

  /// Sotto questa dimensione un doppione non si mostra. Cento kilobyte: due
  /// copie di un'icona non sono un problema di nessuno, e sarebbero migliaia
  /// di righe davanti alle poche che contano.
  final int soglia;

  /// ── Le cartelle che non si guardano, scelte da chi usa il computer ───
  ///
  /// Giacomo, 9 settembre 2026: «mettiamo esclusione di alcuni percorsi, ho
  /// ad esempio i sorgenti di android nella cartella android/sdk, il mio
  /// progetto di droidian».
  ///
  /// Quelle di serie qui sotto sono una regola generale — si salta ciò che è
  /// *generato o scaricato*, non ciò che è tuo — ma nessun elenco scritto da
  /// noi può conoscere le cartelle di chi usa il computer. Queste sono sue,
  /// arrivano dalle impostazioni, e valgono in più.
  ///
  /// Percorsi assoluti: una cartella si esclude perché è QUELLA, non perché
  /// si chiama così. `Documenti/foto` e `Scaricati/foto` sono due cose
  /// diverse, e un elenco di nomi le prenderebbe tutte e due.
  final List<String> escluse;

  final void Function(String fase, String testo, int fatte, int quante)?
      racconta;

  /// I nomi che non si attraversano mai.
  ///
  /// `Progetti` è il caso di questa macchina e sta scritto qui, ma la regola
  /// che vale è quella sotto: si salta ciò che è **generato**, non ciò che è
  /// di Giacomo.
  static const Set<String> _daNonGuardare = {
    'Progetti',
    'node_modules',
    'build',
    'target',
    '.git',
    'vendor',
    '__pycache__',
    'venv',
    '.venv',
    'snap',
    // ── E le cassette degli attrezzi, che sono roba SCARICATA ──────────
    //
    // `~/Android` sono 3,1 GB e 45.403 file, `~/flutter` 1,6 GB e 17.427:
    // dentro una SDK i doppioni sono normali quanto dentro `node_modules` —
    // le stesse librerie in più versioni della piattaforma — e non si toccano
    // mai. Misurate sulla macchina di Giacomo il 9 settembre 2026, mentre il
    // setaccio ci passava dentro.
    'Android',
    'flutter',
    'go',
    '.rustup',
    '.pub-cache',
    'AndroidStudioProjects',
  };

  bool _saltare(String nome) =>
      nome.startsWith('.') || _daNonGuardare.contains(nome);

  /// Vero se questo percorso è dentro una delle cartelle escluse da chi usa
  /// il computer.
  bool _escluso(String percorso) {
    for (final e in escluse) {
      if (e.isEmpty) continue;
      final pulita = e.endsWith('/') ? e.substring(0, e.length - 1) : e;
      if (percorso == pulita || percorso.startsWith('$pulita/')) return true;
    }
    return false;
  }

  /// Tutti i file che vale la pena confrontare.
  Future<List<Voce>> _elenco() async {
    final fuori = <Voce>[];
    final daFare = <String>[casa];
    var cartelle = 0;

    while (daFare.isNotEmpty) {
      final qui = daFare.removeLast();
      cartelle++;
      if (racconta != null && cartelle % 200 == 0) {
        racconta!('doppioni', 'Guardo ${fuori.length} file in $cartelle cartelle',
            0, 0);
      }
      try {
        await for (final v in Directory(qui).list(followLinks: false)) {
          final nome = v.path.split('/').last;
          if (_saltare(nome) || _escluso(v.path)) continue;
          if (v is Directory) {
            daFare.add(v.path);
            continue;
          }
          if (v is! File) continue; // i collegamenti non si contano
          try {
            final s = await v.stat();
            if (s.size < soglia) continue;
            fuori.add(Voce(
              percorso: v.path,
              dimensione: s.size,
              mtime: s.modified,
              tipo: 'file',
            ));
          } catch (_) {
            // Un file sparito mentre guardavamo non ferma il giro.
          }
        }
      } catch (_) {
        // Una cartella che non si legge non ferma il giro: si perde lei, non
        // tutto il resto.
      }
    }
    return fuori;
  }

  /// I gruppi di doppioni, dal più sprecone.
  Future<Map<String, dynamic>> doppioni() async {
    racconta?.call('doppioni', 'Percorro la tua cartella di casa', 0, 3);
    final voci = await _elenco();
    racconta?.call(
        'doppioni', '${voci.length} file da confrontare', 1, 3);

    final gruppi = await Doppioni.suElenco(voci).esatti(
      avanza: (fatti, totale) => racconta?.call(
          'doppioni', 'Confronto $fatti file su $totale', 2, 3),
    );

    final sprecato = gruppi.fold<int>(0, (s, g) => s + g.byteInPiu);
    racconta?.call(
        'doppioni',
        gruppi.isEmpty
            ? 'Nessun doppione: è tutta roba diversa'
            : '${gruppi.length} gruppi, ${_inParole(sprecato)} in più',
        3,
        3);

    final fuori = [for (final g in gruppi) _conProposta(g)];
    return {
      'ok': true,
      'gruppi': fuori,
      'cartelle': _riferimentiPossibili(fuori),
      'sprecato': sprecato,
      'guardati': voci.length,
    };
  }

  /// ── Le cartelle che si possono prendere come RIFERIMENTO ─────────────
  ///
  /// Giacomo, 9 settembre 2026: «metti caso che metto un nuovo backup nel PC
  /// e quelli che già avevo sono sparpagliati: seleziono la cartella come
  /// riferimento e tutto il resto viene considerato doppione».
  ///
  /// È il capovolgimento che rende usabile tutta la pagina. La domanda non è
  /// più «quali di questi settecento file butto?» — a cui nessuno risponde
  /// davvero, e chi risponde lo fa senza guardare — ma **«qual è la cartella
  /// buona?»**, che è una domanda sola e con una risposta che uno sa.
  ///
  /// Qui si prepara la scelta: per ogni cartella in cui vive almeno una copia
  /// si dice **quanto libererebbe** se fosse lei il riferimento, cioè la
  /// somma di tutte le copie che stanno FUORI. Senza quel numero la scelta
  /// sarebbe alla cieca: due cartelle plausibili possono valere tre giga e
  /// trecento mega.
  ///
  /// Si guardano i primi tre livelli sotto casa — `Scaricati`,
  /// `Scaricati/DCIM`, `Scaricati/DCIM/Camera` — perché il riferimento vero
  /// di solito non è né la cartella di casa né la singola cartella foglia.
  List<Map<String, dynamic>> _riferimentiPossibili(
      List<Map<String, dynamic>> gruppi) {
    final quanto = <String, int>{};
    final quanti = <String, int>{};

    for (final g in gruppi) {
      final percorsi = (g['percorsi'] as List).cast<String>();
      final unitario =
          (g['byteInPiu'] as int) ~/ (percorsi.length - 1).clamp(1, 1 << 30);

      // Le cartelle candidate di QUESTO gruppo, senza doppioni fra loro.
      final candidate = <String>{};
      for (final p in percorsi) {
        candidate.addAll(_antenati(p));
      }
      for (final c in candidate) {
        final dentro = percorsi.where((p) => p.startsWith('$c/')).length;
        if (dentro == 0) continue;
        // Quello che si libererebbe: tutte le copie che stanno fuori.
        quanto[c] = (quanto[c] ?? 0) + unitario * (percorsi.length - dentro);
        quanti[c] = (quanti[c] ?? 0) + 1;
      }
    }

    final fuori = quanto.entries
        .where((e) => e.value > 0)
        .map((e) => {
              'percorso': e.key,
              'liberabili': e.value,
              'gruppi': quanti[e.key] ?? 0,
            })
        .toList()
      ..sort((a, b) =>
          (b['liberabili'] as int).compareTo(a['liberabili'] as int));

    // Dieci bastano: un elenco di cartelle lungo quanto quello dei doppioni
    // non è una scorciatoia, è lo stesso problema scritto due volte.
    return fuori.take(10).toList();
  }

  /// Le cartelle che contengono un file, fino a tre livelli sotto casa.
  List<String> _antenati(String percorso) {
    if (!percorso.startsWith('$casa/')) return const [];
    final pezzi = percorso.substring(casa.length + 1).split('/');
    final fuori = <String>[];
    for (var i = 1; i < pezzi.length && i <= 3; i++) {
      fuori.add('$casa/${pezzi.take(i).join('/')}');
    }
    return fuori;
  }

  /// Un gruppo con dentro la proposta, e i percorsi **riordinati**.
  ///
  /// Riordinati e non solo etichettati: il primo dell'elenco è quello che si
  /// tiene, sempre. La prima versione lasciava l'ordine del motore e ci
  /// aggiungeva accanto un campo `tieni` diverso — e chi leggeva «il primo si
  /// tiene, gli altri via» si ritrovava lo stesso file scritto in tutte e due
  /// le colonne. Due modi di dire la stessa cosa sono due modi di dirla
  /// diversa.
  Map<String, dynamic> _conProposta(Gruppo g) {
    final tieni = _scegliTieni(g.percorsi);
    return {
      ...g.toJson(),
      'percorsi': [tieni, ...g.percorsi.where((p) => p != tieni)],
      'tieni': tieni,
      'perche': _perche(tieni),
    };
  }

  /// Le cartelle di **passaggio**: quello che ci sta dentro non ci sta perché
  /// qualcuno ce l'ha messo, ci sta perché ci è caduto.
  static const Set<String> _diPassaggio = {
    'Scaricati', 'Downloads', 'Scrivania', 'Desktop', 'tmp',
  };

  /// ── Le copie arrivate da WhatsApp valgono meno ───────────────────────
  ///
  /// Giacomo: «i file whatsapp duplicati devono avere meno priorità a pari
  /// file».
  ///
  /// Ha ragione, e la ragione non è il peso — qui i file sono identici byte
  /// per byte, non c'è una copia «peggiore» — è il **nome**.
  /// `IMG-20250730-WA0013.jpg` dice il giorno in cui la foto è ARRIVATA sul
  /// telefono, non quello in cui è stata scattata; `IMG_20260426_102932.jpg`
  /// dice lo scatto. A parità di byte si tiene quello che porta con sé
  /// l'informazione migliore, perché il giorno che si riordina per data è
  /// l'unica cosa su cui contare.
  ///
  /// Tre forme, tutte viste su questa macchina: la cartella
  /// `Social_Media/WhatsApp Images`, il nome `IMG-…-WA0013.jpg`, e le
  /// schermate `Screenshot_…_com.whatsapp.jpg`.
  static final RegExp _nomeWhatsApp =
      RegExp(r'-WA\d{4}', caseSensitive: false);

  bool _daWhatsApp(String percorso) {
    final basso = percorso.toLowerCase();
    return basso.contains('/whatsapp') ||
        basso.contains('com.whatsapp') ||
        _nomeWhatsApp.hasMatch(percorso);
  }

  bool _inTransito(String percorso) {
    if (!percorso.startsWith('$casa/')) return false;
    return _diPassaggio.contains(percorso.substring(casa.length + 1).split('/').first);
  }

  /// Quale copia si propone di tenere.
  ///
  /// ── Perché non basta «il percorso più corto» ─────────────────────────
  ///
  /// Perché sul disco vero la prima proposta è venuta fuori così:
  ///
  ///     tieni: ~/Scaricati/DCIM/Camera/VID_20260420_181258.mp4
  ///     via:   ~/documento rinominato/DCIM/Camera/VID_…
  ///     via:   ~/Documenti/22101316UG_rubypro_…/DCIM/Camera/VID_…
  ///
  /// Cioè: butta le due copie messe da qualche parte e tieni quella nella
  /// cartella degli scarichi — che è il posto da cui la roba dovrebbe
  /// USCIRE. Il percorso più corto è la regola giusta fra due fotografie in
  /// due album e quella sbagliata su una cartella di casa vera.
  ///
  /// Adesso, in ordine:
  ///
  ///  1. **fuori dalle cartelle di passaggio** — Scaricati, Scrivania, tmp:
  ///     lì dentro le cose non ci stanno, ci passano;
  ///  2. **meno profondo** — chi l'ha messo a mano di solito non l'ha messo
  ///     sotto cinque cartelle;
  ///  3. **in ordine alfabetico**, perché la stessa cartella deve dare la
  ///     stessa risposta domani.
  ///
  /// E resta una **proposta**: nella finestra si può scegliere un'altra
  /// copia. Un programma che decide da solo quale dei tuoi file sopravvive è
  /// un programma che non si riapre.
  String _scegliTieni(List<String> percorsi) {
    final ordinati = [...percorsi]..sort((a, b) {
        // Prima di tutto: una copia arrivata da WhatsApp è l'ultima da
        // tenere, perché il suo nome è il giorno in cui è arrivata e non
        // quello dello scatto.
        final w = (_daWhatsApp(a) ? 1 : 0).compareTo(_daWhatsApp(b) ? 1 : 0);
        if (w != 0) return w;
        final t = (_inTransito(a) ? 1 : 0).compareTo(_inTransito(b) ? 1 : 0);
        if (t != 0) return t;
        final p = '/'.allMatches(a).length.compareTo('/'.allMatches(b).length);
        if (p != 0) return p;
        return a.compareTo(b);
      });
    return ordinati.first;
  }

  /// Perché proprio quello si tiene, detto a chi guarda.
  String _perche(String tenuto) {
    final dentro = tenuto.startsWith('$casa/')
        ? tenuto.substring(casa.length + 1).split('/').first
        : tenuto;
    if (_inTransito(tenuto)) {
      return 'Sono tutte in cartelle di passaggio: questa è la meno '
          'profonda.';
    }
    return 'È in «$dentro» e non in una cartella di passaggio.';
  }

  /// ── Byte per byte, e solo su quello che stai per buttare ─────────────
  ///
  /// Giacomo, 9 settembre 2026: «in che modo confronta per sapere esattamente
  /// se sono uguali?».
  ///
  /// La scansione confronta a tre livelli — dimensione, le due estremità, poi
  /// un'impronta FNV-1a a 64 bit del file intero — ed è **quasi** certezza: su
  /// cinquemila file la probabilità che due diversi finiscano con la stessa
  /// impronta E la stessa lunghezza è dell'ordine di uno su diecimila
  /// miliardi. Per **mostrare** un elenco è più che abbastanza.
  ///
  /// Per **cancellare** no. «Quasi certo» moltiplicato per un file di
  /// Giacomo fa una risposta sbagliata, e quel file non torna. Quindi prima
  /// di mettere qualcosa nel cestino si leggono i due file e si confrontano
  /// **i byte**, con la copia che resta.
  ///
  /// Costa una lettura in più, e solo di quello che si è scelto: qualche
  /// secondo per qualche giga. È il prezzo per passare da «quasi certo» a
  /// «certo», ed è il momento giusto per pagarlo.
  ///
  /// E prende anche il caso più probabile di tutti, che con le impronte non
  /// si vedrebbe: **il file è cambiato dopo la scansione**. Un elenco di
  /// mezz'ora fa non sa che nel frattempo ci hai scritto dentro.
  /// Pubblica perché è il cuore della garanzia, e una garanzia che non si può
  /// provare da sola non è una garanzia.
  Future<bool> identici(String a, String b) async {
    try {
      final fa = File(a), fb = File(b);
      if (await fa.length() != await fb.length()) return false;
      final ra = await fa.open();
      final rb = await fb.open();
      try {
        const pezzo = 1 << 20;
        while (true) {
          final ba = await ra.read(pezzo);
          final bb = await rb.read(pezzo);
          if (ba.length != bb.length) return false;
          if (ba.isEmpty) return true;
          for (var i = 0; i < ba.length; i++) {
            if (ba[i] != bb[i]) return false;
          }
        }
      } finally {
        await ra.close();
        await rb.close();
      }
    } catch (_) {
      // Non si è potuto leggere: allora non si può dire che sono uguali, e
      // quindi non si tocca. Il dubbio vale come un no.
      return false;
    }
  }

  /// ── Togliere, senza mai restare senza ────────────────────────────────
  ///
  /// Arrivano i percorsi da buttare. Prima di toccarne uno si **rifà il
  /// giro**: si ricalcolano i gruppi adesso, e per ogni gruppo si controlla
  /// che almeno una copia resti in piedi.
  ///
  /// È la prova che un programma di doppioni deve avere e che quasi nessuno
  /// scrive. Il caso non è teorico: basta aprire due volte la finestra, o
  /// spuntare in una e nel frattempo aver già tolto nell'altra, e un elenco
  /// vecchio chiede di buttare l'ultima copia rimasta. La differenza fra
  /// «hai liberato sette giga» e «hai perso i video di tuo figlio» è questo
  /// controllo.
  ///
  /// Un percorso che non appartiene più a nessun gruppo si rifiuta: se non ha
  /// un gemello, non è un doppione — è un file.
  Future<Map<String, dynamic>> daButtare(List<String> percorsi) async {
    if (percorsi.isEmpty) {
      return {'ok': false, 'errore': 'Non hai scelto niente.'};
    }
    final chiesti = percorsi.toSet();
    final ora = await doppioni();

    final via = <String>[];
    final rifiutati = <Map<String, String>>[];
    final visti = <String>{};

    for (final g in (ora['gruppi'] as List).cast<Map<String, dynamic>>()) {
      final dentro = (g['percorsi'] as List).cast<String>();
      final butta = dentro.where(chiesti.contains).toList();
      if (butta.isEmpty) continue;
      visti.addAll(butta);
      final salvata = g['tieni'] as String;
      final tutte = butta.length >= dentro.length;
      for (final p in butta) {
        if (tutte && p == salvata) {
          // Le vuole tutte: una si salva, ed è quella proposta.
          rifiutati.add({
            'percorso': p,
            'perche': 'Era l\'ultima copia rimasta: questa resta.',
          });
          continue;
        }
        // Il confronto vero, byte per byte, con la copia che resta. Non con
        // una qualunque: con **quella** che sopravvive, che è l'unica di cui
        // interessi sapere che è davvero la stessa cosa.
        final controparte = tutte || p != salvata ? salvata : dentro.first;
        if (!await identici(p, controparte)) {
          rifiutati.add({
            'percorso': p,
            'perche': 'Confrontandoli byte per byte non sono più identici: '
                'uno dei due è cambiato dopo la scansione.',
          });
          continue;
        }
        via.add(p);
      }
    }

    for (final p in chiesti.difference(visti)) {
      rifiutati.add({
        'percorso': p,
        'perche': 'Adesso non ha più un gemello: non è un doppione, è un file.',
      });
    }

    return {'ok': true, 'via': via, 'rifiutati': rifiutati};
  }

  static String _inParole(int byte) {
    if (byte < 1000) return '$byte B';
    if (byte < 1000000) return '${(byte / 1000).round()} KB';
    if (byte < 1000000000) return '${(byte / 1000000).round()} MB';
    return '${(byte / 1000000000).toStringAsFixed(2).replaceAll('.', ',')} GB';
  }
}

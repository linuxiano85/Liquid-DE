import 'dart:io';

/// ArchiveService — Comprimere ed estrarre, che è metà di quello per cui si
/// apre un gestore file.
///
/// KDE lo dà da sempre: in Dolphin la voce «Comprimi» e «Estrai qui» arrivano
/// da Ark. Minerva riconosceva l'estensione `.zip` — le disegnava perfino
/// l'icona giusta — e poi non sapeva farci niente. Un archivio scaricato
/// restava una cosa da aprire con un terminale.
///
/// ── PERCHÉ `bsdtar` E NON `tar`, `unzip`, `7z` ─────────────────────────────
///
/// Perché è **uno** strumento per tutti i formati. `bsdtar` è libarchive, e
/// libarchive legge zip, 7z, rar, iso, cab e tutti i `tar.*` con la stessa
/// riga di comando; e su Arch c'è sempre, perché `pacman` stesso ci sta sopra:
/// non è una dipendenza da aggiungere, è una dipendenza che non si può
/// togliere. L'alternativa era un ramo `if` per ogni formato, ognuno con la
/// propria sintassi e i propri codici di uscita.
///
/// ── LA COSA CHE NON SI VEDE: uscire dalla cartella ─────────────────────────
///
/// Un archivio può contenere un file che si chiama `../../.bashrc`. Chi lo
/// estrae senza pensarci si ritrova un file scritto FUORI dalla cartella di
/// destinazione — in casa propria, o in `~/.config`. Si chiama «zip slip» ed è
/// il modo classico in cui un allegato diventa un programma che parte da solo.
///
/// Verificato sul campo, con un archivio costruito apposta: `bsdtar` rifiuta
/// («Path contains '..'») e torna con errore. Anche GNU `tar` rifiuta. Non è
/// quindi una ragione per preferire l'uno all'altro — ma è una garanzia che va
/// SAPUTA, perché se un domani qualcuno sostituisse questi comandi con una
/// libreria che spacchetta a mano, quel controllo sparirebbe in silenzio. C'è
/// una prova apposta che lo dimostra.
///
/// ── DOVE FINISCE LA ROBA ───────────────────────────────────────────────────
///
/// Accanto all'archivio, mai «da qualche parte». E dentro una cartella nuova
/// **solo se serve**: se l'archivio è fatto bene e ha una sola cartella in
/// cima, aggiungerne un'altra darebbe `foo/foo/…`; se invece è una «bomba»,
/// cioè trenta file sciolti in cima, senza la cartella nuova li rovescerebbe
/// tutti dove uno stava lavorando. Si guarda l'elenco prima di estrarre.
class ArchiveService {
  /// Si può cambiare per le prove: il nome del programma da eseguire.
  const ArchiveService({this.comando = 'bsdtar'});

  final String comando;

  /// I formati che sappiamo creare, nell'ordine in cui ha senso proporli.
  ///
  /// `zip` per primo perché è l'unico che si apre con un doppio clic anche su
  /// Windows e su un telefono: chi comprime lo fa quasi sempre per mandare
  /// qualcosa a qualcuno. Gli altri due sono per sé stessi — `tar.zst`
  /// comprime bene ed è velocissimo, `tar.gz` lo legge qualunque cosa.
  static const List<Map<String, String>> formati = [
    {'id': 'zip', 'estensione': '.zip', 'nome': 'ZIP'},
    {'id': 'tarzst', 'estensione': '.tar.zst', 'nome': 'TAR + Zstandard'},
    {'id': 'targz', 'estensione': '.tar.gz', 'nome': 'TAR + gzip'},
  ];

  /// Le estensioni che sappiamo APRIRE. Più larghe di quelle che sappiamo
  /// creare: libarchive legge anche `.rar` e `.7z`, che non crea.
  ///
  /// L'ordine conta: le doppie prima delle semplici, o `.tar.gz` verrebbe
  /// riconosciuto come `.gz` e il nome della cartella estratta resterebbe
  /// «archivio.tar».
  static const List<String> estensioni = [
    '.tar.gz', '.tar.bz2', '.tar.xz', '.tar.zst', '.tar.lz4', '.tar.lzma',
    '.tgz', '.tbz2', '.txz', '.tzst',
    '.zip', '.7z', '.rar', '.tar', '.iso', '.cab', '.jar', '.xpi',
    '.gz', '.bz2', '.xz', '.zst',
  ];

  /// Vero se il nome finisce con qualcosa che sappiamo aprire.
  static bool eArchivio(String percorso) => estensioneDi(percorso) != null;

  /// Quale delle estensioni note corrisponde, o `null`.
  static String? estensioneDi(String percorso) {
    final basso = percorso.toLowerCase();
    for (final e in estensioni) {
      if (basso.endsWith(e)) return e;
    }
    return null;
  }

  /// Il nome senza l'estensione dell'archivio: `foto.tar.gz` → `foto`.
  static String nomeSenzaEstensione(String nomeFile) {
    final e = estensioneDi(nomeFile);
    if (e == null) return nomeFile;
    return nomeFile.substring(0, nomeFile.length - e.length);
  }

  // ── Comprimere ───────────────────────────────────────────────────────────

  /// Mette `percorsi` in un archivio, accanto a loro.
  ///
  /// Tutti gli elementi devono stare nella stessa cartella: è sempre vero
  /// quando la selezione arriva da una finestra del gestore file, e permette
  /// di scrivere nell'archivio i nomi SEMPLICI invece dei percorsi completi.
  /// Un archivio che dentro contiene `home/giacomo/Documenti/…` è un archivio
  /// che, aperto da qualcun altro, crea tre cartelle inutili.
  Future<Map<String, dynamic>> comprimi(
    List<String> percorsi, {
    String formato = 'zip',
    String? nome,
  }) async {
    if (percorsi.isEmpty) {
      return {'ok': false, 'error': 'Niente da comprimere.'};
    }

    final estensione = formati.firstWhere(
      (f) => f['id'] == formato,
      orElse: () => formati.first,
    )['estensione']!;

    final cartella = _cartellaDi(percorsi.first);
    for (final p in percorsi) {
      if (_cartellaDi(p) != cartella) {
        return {
          'ok': false,
          'error': 'Gli elementi da comprimere non sono nella stessa cartella.'
        };
      }
    }

    // Il nome di partenza: se c'è un solo elemento prende il suo nome, se ce
    // ne sono tanti quello della cartella che li contiene. È la scelta che
    // fa Ark, e funziona perché è quasi sempre giusta senza chiedere niente.
    //
    // A un file l'estensione si toglie: `lettera.txt` dà `lettera.zip` e non
    // `lettera.txt.zip`. A una cartella no — `foto.vecchie` è un nome, non
    // un'estensione, e mangiarne un pezzo fa perdere l'unica cosa che
    // distingueva quell'archivio da un altro.
    final base = nome ?? await _nomeDiPartenza(percorsi, cartella);
    if (base.isEmpty || base == '.' || base == '..' || base.contains('/') || base.contains('\u0000')) {
      return {'ok': false, 'error': 'Nome archivio non valido.'};
    }

    final destinazione = await _liberoPer('$cartella/$base', estensione);

    // `-a` sceglie il formato dall'estensione del file di destinazione: è per
    // questo che `.zip` produce uno zip e `.tar.zst` un tar compresso, senza
    // che qui dentro ci sia un `if` per formato.
    final args = <String>[
      '-a', '-c', '-f', destinazione,
      '-C', cartella,
      '--',
      ...percorsi.map(_nomeDi),
    ];

    final esito = await _esegui(args);
    if (!esito['ok']) return esito;
    if (!await File(destinazione).exists()) {
      return {'ok': false, 'error': 'Il comando non ha creato l’archivio.'};
    }
    return {'ok': true, 'error': '', 'percorso': destinazione};
  }

  // ── Estrarre ─────────────────────────────────────────────────────────────

  /// Tira fuori il contenuto di `archivio`, accanto all'archivio stesso.
  ///
  /// Torna anche `cartella`: dove è finita la roba. Serve al gestore file per
  /// portarci dentro chi ha estratto, invece di lasciarlo a indovinare.
  Future<Map<String, dynamic>> estrai(String archivio, {String? dove}) async {
    if (!await File(archivio).exists()) {
      return {'ok': false, 'error': 'L\'archivio non esiste più.'};
    }

    final cartella = dove ?? _cartellaDi(archivio);

    final cime = await _cimeDi(archivio);
    if (cime == null) {
      return {
        'ok': false,
        'error': 'Non riesco a leggere l\'archivio: forse è danneggiato, '
            'o è un formato che non conosco.'
      };
    }

    // Una sola cosa in cima: l'archivio si porta già la sua cartella e non
    // serve avvolgerlo in un'altra. Zero o più d'una: si crea la cartella,
    // altrimenti il contenuto si rovescia dove uno sta lavorando.
    String destinazione;
    if (cime.length == 1) {
      destinazione = cartella;
      // Se quel nome è già occupato si estrae comunque in una cartella
      // nuova: sovrascrivere il lavoro di qualcuno non si fa mai in silenzio.
      final gia = '$cartella/${cime.first}';
      if (await FileSystemEntity.type(gia) != FileSystemEntityType.notFound) {
        destinazione = await _liberoPer(
            '$cartella/${nomeSenzaEstensione(_nomeDi(archivio))}', '');
        await Directory(destinazione).create(recursive: true);
      }
    } else {
      destinazione = await _liberoPer(
          '$cartella/${nomeSenzaEstensione(_nomeDi(archivio))}', '');
      await Directory(destinazione).create(recursive: true);
    }

    final esito = await _esegui(['-x', '-f', archivio, '-C', destinazione]);
    if (!esito['ok']) return esito;

    return {
      'ok': true,
      'error': '',
      'cartella': destinazione,
      // Quando si è estratto senza creare una cartella, quel che si è
      // aggiunto è il singolo elemento in cima: il gestore file lo seleziona.
      'nuovo': cime.length == 1 && destinazione == cartella
          ? '$cartella/${cime.first}'
          : destinazione,
    };
  }

  Future<String> _nomeDiPartenza(List<String> percorsi, String cartella) async {
    if (percorsi.length != 1) {
      return _nomeDi(cartella.isEmpty ? 'archivio' : cartella);
    }
    final nome = _nomeDi(percorsi.first);
    if (await FileSystemEntity.isDirectory(percorsi.first)) return nome;
    final punto = nome.lastIndexOf('.');
    // `punto > 0` e non `>= 0`: un file che si chiama `.bashrc` non ha
    // estensione, ha un nome che comincia per punto — e comprimerlo darebbe
    // un archivio senza nome, cioè `.zip`.
    return punto > 0 ? nome.substring(0, punto) : nome;
  }

  /// I nomi di primo livello dentro l'archivio, senza estrarlo.
  ///
  /// `null` se l'archivio non si legge — che è una risposta diversa da «è
  /// vuoto», e il chiamante deve poterle distinguere.
  Future<List<String>?> _cimeDi(String archivio) async {
    final r = await _esegui(['-t', '-f', archivio]);
    if (!r['ok']) return null;

    final cime = <String>{};
    for (final riga in (r['uscita'] as String).split('\n')) {
      final pulita = riga.trim();
      if (pulita.isEmpty) continue;
      // `bsdtar -t` scrive `cartella/file`: la cima è quel che viene prima
      // della prima barra. Un `./` iniziale, che alcuni archivi hanno, non è
      // una cima e va tolto o risulterebbero tutti dentro «.».
      var nome = pulita.startsWith('./') ? pulita.substring(2) : pulita;
      final barra = nome.indexOf('/');
      if (barra >= 0) nome = nome.substring(0, barra);
      if (nome.isNotEmpty && nome != '.') cime.add(nome);
    }
    return cime.toList();
  }

  // ── Il comando ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _esegui(List<String> args) async {
    try {
      final r = await Process.run(comando, args);
      if (r.exitCode != 0) {
        // `bsdtar` scrive l'errore utile su stderr e lo fa precedere dal
        // proprio nome: «bsdtar: …». Toglierlo lascia la frase che serve.
        var messaggio = '${r.stderr}'.trim();
        messaggio = messaggio
            .split('\n')
            .map((r) => r.replaceFirst(RegExp(r'^bsdtar: '), ''))
            .where((r) => r.isNotEmpty)
            .join('\n');
        return {
          'ok': false,
          'error': messaggio.isEmpty ? 'Operazione fallita.' : messaggio,
          'uscita': '',
        };
      }
      return {'ok': true, 'error': '', 'uscita': '${r.stdout}'};
    } on ProcessException catch (e) {
      // Il caso «lo strumento non c'è». Su Arch non capita, ma un messaggio
      // che lo dice vale molto di più di «Operazione fallita».
      return {
        'ok': false,
        'error': 'Manca il programma «$comando» (${e.message}).',
        'uscita': '',
      };
    }
  }

  // ── Utilità ──────────────────────────────────────────────────────────────

  static String _cartellaDi(String percorso) {
    final i = percorso.lastIndexOf('/');
    if (i <= 0) return i == 0 ? '/' : '';
    return percorso.substring(0, i);
  }

  static String _nomeDi(String percorso) {
    final pulito =
        percorso.endsWith('/') && percorso.length > 1
            ? percorso.substring(0, percorso.length - 1)
            : percorso;
    final i = pulito.lastIndexOf('/');
    return i < 0 ? pulito : pulito.substring(i + 1);
  }

  /// `base + estensione`, o `base 2 + estensione`, o `base 3`… Il primo che
  /// non esiste. Non si sovrascrive mai niente senza chiedere, e qui non c'è
  /// nessuno a cui chiedere.
  Future<String> _liberoPer(String base, String estensione) async {
    var tentativo = '$base$estensione';
    var n = 2;
    while (await FileSystemEntity.type(tentativo) !=
        FileSystemEntityType.notFound) {
      tentativo = '$base $n$estensione';
      n++;
    }
    return tentativo;
  }
}

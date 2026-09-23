import 'dart:io';

/// CartellaMotore — mandare un progetto al sicuro su una cartella o un disco.
///
/// ── A cosa serve, visto che c'è già GitHub ─────────────────────────────────
///
/// A tutto quello che GitHub non prende. `Ruby`, nella cartella dei progetti di
/// Giacomo, sono **286 GB** di immagini ROM Android: GitHub rifiuta ogni file
/// oltre 100 MB e si aspetta archivi sotto il giga. Non è un limite da
/// aggirare — è lo strumento sbagliato per quel contenuto.
///
/// E serve anche a chi ha GitHub: un disco che tieni in un cassetto è l'unica
/// copia che sopravvive a un account chiuso, a una password persa e a internet
/// che non c'è.
///
/// ── Come si tiene la cartella di destinazione ──────────────────────────────
///
/// **Uno specchio, più dei giri datati fatti di collegamenti.**
///
///     <destinazione>/<chiave del progetto>/
///         adesso/                      ← lo specchio: com'è ORA
///         2026-08-24_1725/             ← un giro: com'era allora
///         2026-08-23_0910/
///
/// I giri datati non sono copie: si fanno con `cp -al`, che crea un albero di
/// **collegamenti fisici** allo specchio. Ogni file non cambiato è lo stesso
/// dato sul disco, con due nomi. Dieci giri di un progetto da 1 GB in cui
/// cambia un file da 2 MB occupano 1 GB e 18 MB, non 10 GB.
///
/// `cp -al` e non `rsync --link-dest` perché qui la sorgente da collegare è lo
/// specchio, che sta **già sul disco di destinazione**: non c'è niente da
/// trasferire, solo nomi da creare. E funziona su ext4 e su un disco esterno,
/// dove il reflink di btrfs non c'è — i collegamenti fisici li sa fare
/// qualunque filesystem tranne FAT ed exFAT. Su quelli il giro fallisce, e
/// allora si aggiorna solo lo specchio invece di non fare niente.
///
/// ── La proprietà che rende `--delete` sicuro ───────────────────────────────
///
/// `rsync --delete` cancella dalla destinazione quello che nella sorgente non
/// c'è più. Puntato sulla cartella sbagliata, svuota quella cartella.
///
/// Qui non può succedere, e **non perché stiamo attenti**: perché non si scrive
/// mai nella cartella che l'utente ha scelto, si scrive sempre dentro una
/// sottocartella nostra che porta la chiave del progetto. Il `--delete` non può
/// arrivare oltre quella. Se uno indica per sbaglio la propria home, si ritrova
/// una cartella in più, non una home vuota.
class CartellaMotore {
  CartellaMotore({this.esegui = Process.run});

  final Future<ProcessResult> Function(String, List<String>) esegui;

  /// Il nome dello specchio dentro la cartella del progetto. Una parola e non
  /// una data, perché è **sempre l'ultima versione**: chi apre il disco per
  /// riprendersi un file cerca quella, non un elenco di date.
  static const String specchio = 'adesso';

  // ── I rifiuti, prima di qualsiasi cosa ─────────────────────────────────

  /// `null` se la destinazione va bene, la frase da mostrare se non va.
  ///
  /// Ogni riga qui sotto è una cartella che qualcuno ha già svuotato per
  /// sbaglio, in qualche progetto, da qualche parte.
  static String? percheNo(String progetto, String destinazione) {
    if (!destinazione.startsWith('/')) {
      return 'Serve il percorso completo della cartella dove mandarlo.';
    }
    final d = _pulisci(destinazione);
    final p = _pulisci(progetto);

    if (d == p) {
      return 'La destinazione è il progetto stesso.';
    }
    // Dentro il progetto: ogni copia finirebbe dentro la copia precedente, e
    // il giro dopo copierebbe anche quella. Cresce finché il disco non finisce.
    if (d.startsWith('$p/')) {
      return 'Questa cartella sta dentro il progetto: la copia finirebbe '
          'dentro sé stessa, e continuerebbe a crescere.';
    }
    // Il progetto dentro la destinazione: `--delete` lavorerebbe su un albero
    // che contiene la sorgente.
    if (p.startsWith('$d/')) {
      return 'Il progetto sta dentro questa cartella: scegline una fuori.';
    }

    final casa = Platform.environment['HOME'] ?? '';
    const sistema = {
      '/', '/etc', '/usr', '/var', '/boot', '/opt', '/srv', '/home',
      '/root', '/proc', '/sys', '/dev', '/run', '/bin', '/lib', '/sbin',
    };
    if (sistema.contains(d)) return 'Non mando niente dentro «$d».';
    if (casa.isNotEmpty && d == casa) {
      return 'Scegli una cartella dentro la tua home, non la home stessa.';
    }
    return null;
  }

  static String _pulisci(String s) {
    var x = s.trim();
    while (x.length > 1 && x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  // ── Mandare ────────────────────────────────────────────────────────────

  /// Aggiorna lo specchio, e — se `dataGiro` è dato — lascia anche un giro
  /// datato fatto di collegamenti allo specchio.
  ///
  /// L'ordine conta: **prima il giro datato, poi lo specchio.** Così il giro
  /// fotografa lo stato *precedente*, che è ancora tutto lì, e non uno specchio
  /// aggiornato a metà da un `rsync` che si è interrotto.
  Future<EsitoInvio> manda(
    String progetto,
    String destinazione, {
    required String chiave,
    String? dataGiro,
    List<String> escludi = const [],
  }) async {
    final no = percheNo(progetto, destinazione);
    if (no != null) return EsitoInvio.no(no);

    if (!await Directory(progetto).exists()) {
      return EsitoInvio.no('Il progetto non c\'è più.');
    }
    final dove = Directory(destinazione);
    if (!await dove.exists()) {
      return EsitoInvio.no(
        'La cartella «$destinazione» non c\'è. Se è un disco esterno, '
        'controlla che sia attaccato.',
      );
    }

    final casa = '${_pulisci(destinazione)}/$chiave';
    final adesso = '$casa/$specchio';
    try {
      await Directory(adesso).create(recursive: true);
    } catch (e) {
      return EsitoInvio.no('Non riesco a scrivere lì dentro: $e');
    }

    // Il giro datato PRIMA: fotografa lo specchio com'è adesso, con dei
    // collegamenti. Costa quanto i nomi dei file, non quanto i file.
    String? giro;
    if (dataGiro != null && await _haQualcosa(adesso)) {
      giro = '$casa/$dataGiro';
      final r = await esegui('cp', ['-al', '--', adesso, giro]);
      if (r.exitCode != 0) {
        // Non è un motivo per non aggiornare lo specchio: la copia più
        // importante è l'ultima. Si dice, e si va avanti.
        giro = null;
      }
    }

    final args = <String>[
      '-a',
      '--delete',
      // ── Il confronto al nanosecondo, e perché non è pignoleria ────────
      //
      // Senza questo, rsync confronta gli orari al **secondo intero**. Un file
      // modificato nello stesso secondo dell'ultima copia e che resta della
      // stessa lunghezza — cambiare `false` in `true`, correggere una parola —
      // viene **saltato in silenzio**, e la copia resta indietro senza che
      // nessuno lo sappia mai.
      //
      // Riprodotto il 24 agosto 2026: `primo` → `nuova`, cinque byte l'uno,
      // stesso secondo. La copia conteneva ancora `primo` dopo il secondo
      // invio, e rsync usciva con successo.
      //
      // Per un programma di backup è il difetto peggiore che esista: non
      // perde i dati, dice che li ha salvati quando non è vero.
      //
      // `-1` costa **niente**: gli orari al nanosecondo ci sono già, li
      // conserva `-a`. Misurato su 200 file immutati: zero ritrasferimenti.
      // L'alternativa, `--checksum`, rileggerebbe ogni byte di 286 GB.
      '--modify-window=-1',
      // I file che spariscono a metà copia sono normali in una cartella viva
      // (roba compilata, file temporanei) e non sono un guasto.
      '--ignore-missing-args',
      for (final e in escludi) ...['--exclude', e],
      '--',
      // La barra finale sulla sorgente vuol dire «il CONTENUTO di», non «la
      // cartella». Senza, si crea un livello in più a ogni invio.
      '${_pulisci(progetto)}/',
      '$adesso/',
    ];
    final r = await esegui('rsync', args);
    if (r.exitCode != 0) {
      return EsitoInvio.no(erroreLeggibile('${r.stderr}'));
    }

    return EsitoInvio.si(dove: adesso, giro: giro);
  }

  Future<bool> _haQualcosa(String cartella) async {
    try {
      return await Directory(cartella).list().isEmpty == false;
    } catch (_) {
      return false;
    }
  }

  /// I giri datati già presenti, dal più recente.
  Future<List<String>> giri(String destinazione, String chiave) async {
    final d = Directory('${_pulisci(destinazione)}/$chiave');
    if (!await d.exists()) return const [];
    final fuori = <String>[];
    await for (final e in d.list(followLinks: false)) {
      final n = e.path.split('/').last;
      if (e is Directory &&
          RegExp(r'^\d{4}-\d{2}-\d{2}_\d{4}').hasMatch(n)) {
        fuori.add(n);
      }
    }
    fuori.sort((a, b) => b.compareTo(a));
    return fuori;
  }

  // ── Gli errori, in italiano ────────────────────────────────────────────

  static String erroreLeggibile(String grezzo) {
    final g = grezzo.toLowerCase();
    if (g.contains('no space left')) {
      return 'Il disco di destinazione è pieno.';
    }
    if (g.contains('read-only file system')) {
      return 'Il disco di destinazione è in sola lettura.';
    }
    if (g.contains('permission denied')) {
      return 'Non ho il permesso di scrivere in quella cartella.';
    }
    if (g.contains('no such file or directory')) {
      return 'La cartella di destinazione è sparita: se è un disco esterno, '
          'forse si è staccato.';
    }
    if (g.contains('input/output error')) {
      return 'Il disco di destinazione dà errore di lettura: potrebbe essere '
          'che si stia rompendo.';
    }
    final righe = grezzo
        .trim()
        .split('\n')
        .where((r) => r.trim().isNotEmpty && !r.startsWith('rsync error:'))
        .toList();
    return righe.isEmpty ? 'L\'invio non è riuscito.' : righe.first;
  }
}

class EsitoInvio {
  const EsitoInvio.si({required this.dove, this.giro})
      : riuscito = true,
        errore = null;
  const EsitoInvio.no(this.errore)
      : riuscito = false,
        dove = null,
        giro = null;

  final bool riuscito;
  final String? errore;

  /// Dove è finito lo specchio: si mostra, perché chi manda una copia su un
  /// disco vuole sapere dove andarla a cercare senza chiedere.
  final String? dove;

  /// Il giro datato lasciato accanto, se è riuscito.
  final String? giro;

  Map<String, dynamic> toJson() => {
        'ok': riuscito,
        if (errore != null) 'errore': errore,
        if (dove != null) 'dove': dove,
        if (giro != null) 'giro': giro,
      };
}

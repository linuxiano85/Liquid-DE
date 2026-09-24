import 'dart:convert';
import 'dart:io';

/// RadiceService — Le operazioni che il gestore file fa da amministratore.
///
/// ── Dove sta il confine ────────────────────────────────────────────────────
///
/// Questo servizio **non ha nessun privilegio**. Gira dentro il demone, che
/// gira come te. Tutto quello che fa è chiamare `pkexec` su un aiutante
/// installato in `/usr/local/bin/liquid-de-radice`, e chi decide se quella
/// chiamata è lecita è **polkit**, che chiede la password di un amministratore.
///
/// Vale la pena dirlo perché la tentazione opposta è forte: sarebbe più comodo
/// se il demone potesse fare queste cose da solo. Sarebbe anche la fine della
/// sicurezza di tutto il resto — il demone ascolta su un socket, e per quanto
/// quel socket sia chiuso da una parola d'ordine, un demone che può scrivere in
/// `/etc` è un demone che vale la pena attaccare.
///
/// ── Perché un elenco chiuso di operazioni ──────────────────────────────────
///
/// Perché così l'insieme di quello che si può fare da root è scritto in un
/// posto solo, e si legge in venti righe. Con un `comando` generico
/// bisognerebbe fidarsi di ogni chiamante di adesso e di domani.
///
/// L'aiutante ricontrolla tutto da capo: si può lanciare a mano, e un controllo
/// che vive solo qui non è un controllo. Vedi `scripts/minerva-radice`.
class RadiceService {
  const RadiceService();

  /// Dove sta l'aiutante. Fisso, perché la regola di polkit lo nomina
  /// carattere per carattere — e perché è di root: root non deve eseguire un
  /// file che l'utente può riscrivere.
  static const String percorso = '/usr/local/bin/liquid-de-radice';

  /// Le operazioni che si possono chiedere. Chiuso di proposito.
  static const Set<String> operazioni = {
    // Non fa niente: chiede solo a polkit di identificarti, così la modalità
    // amministratore si accende DOPO la password e non prima. Vedi il commento
    // nel verbo `permesso` di `scripts/minerva-radice`.
    'permesso',
    'elenca',
    'leggi',
    'scrivi',
    'elimina',
    'crea-cartella',
    'rinomina',
    'copia',
    'sposta',
    'permessi',
    // ── E le due della trasmissione a schermo ─────────────────────────
    //
    // Aprono e chiudono UNA porta — la 8010 — verso la sola rete privata a cui
    // questo computer è attaccato. Non prendono argomenti, di proposito: un
    // aiutante che gira da root e accetta «apri la porta N verso la rete M»
    // sarebbe la stessa riga con dentro un buco. Vedi `scripts/minerva-radice`.
    'trasmetti-apri',
    'trasmetti-chiudi',
    // ── E le quattro della manutenzione ────────────────────────────────
    //
    // Tolgono roba che sta fuori dalla tua cartella: la cache dei pacchetti
    // (via `paccache`, non con un `rm`), le lingue che non usi (cancellate
    // **e** disattivate in `pacman.conf`, o al primo aggiornamento tornano
    // tutte), il registro di sistema (potato con `journalctl`, non azzerato)
    // e i pacchetti rimasti soli.
    //
    // Ognuno ricontrolla da capo: `togli-orfani` richiede a pacman chi sono
    // gli orfani ADESSO e toglie solo l'intersezione, così un elenco con
    // dentro «linux» non disinstalla il kernel.
    'pulisci-cache-pacchetti',
    'pulisci-lingue',
    'pulisci-registro',
    'togli-orfani',
  };

  /// `126` quando la finestrella della password viene annullata, `127` quando
  /// non si è riusciti ad aprirla. Sono di `pkexec`, non nostri, e vanno
  /// distinti da un fallimento vero: «annullato» non è un guasto.
  static const int annullato = 126;
  static const int nonAutorizzato = 127;

  Future<bool> disponibile() async {
    try {
      final f = File(percorso);
      if (!await f.exists()) return false;
      return (await f.stat()).mode & 0x49 != 0; // 0o111
    } catch (_) {
      return false;
    }
  }

  /// Chiede all'aiutante di fare una cosa.
  ///
  /// `dentro` è quello che finisce sullo standard input — serve solo a
  /// `scrivi`, e ci va il contenuto del file. Passarlo da lì e non fra gli
  /// argomenti non è pignoleria: la riga di comando di un processo la legge
  /// chiunque in `/proc`, e il contenuto di un file di configurazione può
  /// contenere una chiave.
  Future<Map<String, dynamic>> chiedi(
    String operazione,
    List<String> argomenti, {
    String? dentro,
  }) async {
    if (!operazioni.contains(operazione)) {
      return _no('Operazione «$operazione» sconosciuta.');
    }
    if (!await disponibile()) {
      return _no('La modalità amministratore non è installata su questo '
          'computer. Serve «$percorso»: lo mette scripts/install-minerva.sh.');
    }

    // Ogni argomento resta un ARGOMENTO. Niente `sh -c`, niente riga da
    // comporre: un nome di file con una virgoletta dentro è un nome di file,
    // non l'inizio di un secondo comando.
    for (final a in argomenti) {
      // Un byte zero in un percorso non è un percorso: è un tentativo di far
      // finire una stringa prima di dove finisce davvero. Nessun nome di file
      // su Linux ne contiene uno.
      //
      // Gli spazi invece si lasciano passare, e va detto perché la tentazione
      // di filtrarli è forte: questo progetto vive in «…/Minerva Shell», e un
      // controllo che rifiuta gli spazi vieta metà dei percorsi veri. Non
      // servono: `Process.start` prende un ELENCO di argomenti, non una riga
      // da far interpretare a una shell.
      if (a.contains('\u0000')) return _no('Percorso non valido.');
    }

    try {
      final p = await Process.start(
        'pkexec',
        [percorso, operazione, ...argomenti],
        // `stdout`/`stderr` raccolti, e `stdin` aperto: `scrivi` ci scrive
        // dentro il contenuto del file.
        mode: ProcessStartMode.normal,
      );

      if (dentro != null) {
        p.stdin.add(utf8.encode(dentro));
      }
      await p.stdin.close();

      final uscita = <int>[];
      final errori = StringBuffer();
      final a = p.stdout.listen(uscita.addAll).asFuture<void>();
      final b = p.stderr
          .transform(utf8.decoder)
          .listen(errori.write)
          .asFuture<void>();
      final codice = await p.exitCode;
      await a;
      await b;

      if (codice == annullato) {
        return {'ok': false, 'annullato': true, 'error': 'Annullato.'};
      }
      if (codice == nonAutorizzato) {
        return _no('Non sono riuscito a chiedere la password di '
            'amministratore.');
      }
      if (codice != 0) {
        final m = errori.toString().trim();
        // ── L'aiutante installato può essere più VECCHIO di noi ──────────
        //
        // `operazioni` qui sopra è l'elenco che conosce il demone, e il demone
        // si aggiorna da solo. L'aiutante no: sta in `/usr/local/bin` e ce lo
        // mette `install-minerva.sh` con un `sudo`. Fra un `git pull` e quel
        // `sudo` c'è una finestra in cui il demone chiede un verbo che
        // l'aiutante non conosce.
        //
        // Senza questa riga il messaggio è «azione «permesso» sconosciuta» —
        // vero, inutile, e per chi legge sembra un difetto del gestore file.
        // Un errore che non nomina la propria cura costringe a una caccia che
        // dura più dell'errore.
        if (m.contains('sconosciuta')) {
          return _no('L\'aiutante di amministratore installato è più vecchio '
              'di Minerva e non conosce «$operazione». Si rimette a posto con: '
              'scripts/install-minerva.sh');
        }
        return _no(m.isEmpty ? 'Operazione fallita.' : _senzaPrefisso(m));
      }

      return {'ok': true, 'uscita': uscita};
    } on ProcessException catch (e) {
      return _no('Manca «pkexec» (${e.message}).');
    } catch (e) {
      return _no('Non è andata: $e');
    }
  }

  /// Il contenuto di una cartella, letto da root.
  ///
  /// Le voci arrivano separate da un byte zero, non da un a capo: su Linux un
  /// nome di file può contenere un a capo, e con le righe chi crea il file
  /// deciderebbe cosa vede chi guarda la cartella. Vedi `minerva-radice`.
  Future<Map<String, dynamic>> elenca(String cartella) async {
    final r = await chiedi('elenca', [cartella]);
    if (r['ok'] != true) return r;

    final voci = <Map<String, dynamic>>[];
    final testo =
        utf8.decode(r['uscita'] as List<int>, allowMalformed: true);
    // `\u0000` per esteso, non un byte zero vero dentro le virgolette: uno
    // letterale non si vede leggendo, rende il file binario per `grep` e
    // sparisce al primo copia-incolla.
    for (final grezza in testo.split('\u0000')) {
      if (grezza.isEmpty) continue;
      // Sei campi e poi il nome: il nome è l'unico che può contenere una
      // tabulazione, quindi si taglia sei volte e il resto è tutto suo.
      final campi = grezza.split('\t');
      if (campi.length < 7) continue;
      final nome = campi.sublist(6).join('\t');
      voci.add({
        'name': nome,
        'path': cartella.endsWith('/') ? '$cartella$nome' : '$cartella/$nome',
        'isDir': campi[0] == 'd',
        'isLink': campi[0] == 'l',
        'size': int.tryParse(campi[1]) ?? 0,
        'mtime': (double.tryParse(campi[2]) ?? 0).round(),
        'mode': campi[3],
        'owner': campi[4],
        'group': campi[5],
      });
    }
    voci.sort((a, b) {
      final da = a['isDir'] == true, db = b['isDir'] == true;
      if (da != db) return da ? -1 : 1;
      return (a['name'] as String)
          .toLowerCase()
          .compareTo((b['name'] as String).toLowerCase());
    });
    return {'ok': true, 'path': cartella, 'entries': voci};
  }

  /// Il testo di un file, letto da root.
  Future<Map<String, dynamic>> leggi(String file) async {
    final r = await chiedi('leggi', [file]);
    if (r['ok'] != true) return r;
    return {
      'ok': true,
      'path': file,
      'text': utf8.decode(r['uscita'] as List<int>, allowMalformed: true),
    };
  }

  /// Riscrive un file da root, conservandone proprietario e permessi.
  Future<Map<String, dynamic>> scrivi(String file, String testo) async {
    final r = await chiedi('scrivi', [file], dentro: testo);
    if (r['ok'] != true) return r;
    return {'ok': true, 'path': file};
  }

  Map<String, dynamic> _no(String motivo) =>
      {'ok': false, 'error': motivo, 'annullato': false};

  /// L'aiutante fa precedere i propri errori dal proprio nome. Toglierlo
  /// lascia la frase che serve a chi legge, che non deve sapere che esiste un
  /// programma chiamato `minerva-radice`.
  String _senzaPrefisso(String m) =>
      m.split('\n').map((r) => r.replaceFirst('minerva-radice: ', '')).join('\n');
}

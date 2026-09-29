import 'dart:convert';
import 'dart:io';

import 'segreti.dart';

/// GitHubMotore — mandare un progetto su GitHub, e tenere il gettone dove va.
///
/// ── Dove sta il gettone, e perché non altrove ──────────────────────────────
///
/// Nel **portachiavi di sistema**, tramite `secret-tool`. Non in
/// `~/.config/rclone/rclone.conf`, non in `.git/config`, non in una variabile
/// d'ambiente scritta in un file di avvio.
///
/// Le tre strade sbagliate sono tutte comode e tutte diffuse:
///
///   · **nell'URL del remote** (`https://gettone@github.com/...`) — git lo
///     scrive in `.git/config`, che è dentro il progetto, che è dentro ogni
///     copia di backup e dentro ogni punto di ritorno. Un gettone che si
///     propaga da solo in venti posti.
///   · **in un file di configurazione** — sopravvive alla sessione, e chi
///     legge la tua home lo legge.
///   · **sulla riga di comando** — `/proc/<pid>/cmdline` la legge chiunque
///     giri come te, e per un istante il gettone è lì.
///
/// Il portachiavi si sblocca con la password che scrivi all'accesso e muore
/// con la sessione. È lo stesso che tiene le password di Chrome, e che questo
/// progetto ha già dovuto riparare una volta.
///
/// ── Perché le chiamate a GitHub non passano da `curl` ──────────────────────
///
/// Perché `curl -H "Authorization: Bearer …"` mette il gettone negli argomenti
/// del processo. Con `HttpClient` di Dart resta dentro il nostro processo e
/// non lo vede nessuno.
class GitHubMotore {
  GitHubMotore({
    this.esegui = Process.run,
    this.chiedi = _chiediVero,
    this.chiediAlSito = _chiediAlSitoVero,
    Future<int> Function(String, List<String>, String)? conSegreto,
  }) : _conSegreto = conSegreto ?? _conSegretoVero;

  final Future<ProcessResult> Function(
    String,
    List<String>, {
    Map<String, String>? environment,
    bool includeParentEnvironment,
  }) esegui;

  /// Come si parla con GitHub. Sostituibile solo per le prove — così si
  /// possono provare tutte le risposte, comprese quelle che in una prova vera
  /// non si riescono a provocare (un gettone scaduto, un archivio già esistente).
  final Future<RispostaRete> Function(String metodo, String percorso,
      String gettone, Map<String, dynamic>? corpo) chiedi;

  /// Il device flow non parla con `api.github.com` ma con `github.com`, e
  /// senza gettone — perché il gettone è proprio quello che sta chiedendo.
  /// Sostituibile per le stesse ragioni di `chiedi`.
  final Future<RispostaRete> Function(String percorso, Map<String, String> campi)
      chiediAlSito;

  /// Eseguire un comando dandogli un segreto **sullo standard input**.
  ///
  /// Sta qui, sostituibile, e non piantato dentro `salvaGettone`, per una
  /// ragione che è costata due prove rosse il 26 agosto 2026: finché era una
  /// `Process.start` dentro il metodo, ogni prova sul gettone **scriveva
  /// davvero nel portachiavi di Giacomo** — passando accanto al finto che la
  /// prova aveva messo — e restava appesa trenta secondi ad aspettare un
  /// portachiavi che non rispondeva.
  ///
  /// E la riga che controlla che un gettone non valido venga tolto non
  /// guardava niente, perché quel comando non passava dalla lista che la
  /// prova osservava. Una prova che non può fallire non è una prova.
  ///
  /// È lo stesso rimedio, e per lo stesso difetto, di
  /// `AccountService._conSegreto`.
  final Future<int> Function(String, List<String>, String) _conSegreto;

  static Future<int> _conSegretoVero(
      String comando, List<String> args, String segreto) async {
    final p = await Process.start(comando, args);
    p.stdin.write(segreto);
    await p.stdin.close();
    return p.exitCode;
  }

  static const String _servizio = 'minerva-custodia';
  static const String _chiave = 'github';

  // ── Il gettone ─────────────────────────────────────────────────────────

  /// C'è qualcuno che fa il portachiavi su questo computer?
  ///
  /// ── Perché serve un controllo a parte ──────────────────────────────────
  ///
  /// Perché senza, «non c'è nessun portachiavi» e «il portachiavi ha detto di
  /// no» danno lo stesso messaggio — e sono due situazioni diverse con due
  /// cure diverse. Il primo si ripara installando qualcosa, il secondo
  /// sbloccando il portafogli.
  ///
  /// L'8 settembre 2026 su questa macchina non c'era NESSUNO che dichiarasse
  /// `org.freedesktop.secrets`: il servizio di KDE si registra col nome suo e
  /// prende quello standard solo a programma avviato. La Custodia rispondeva
  /// «il portachiavi non ha accettato il gettone», cioè dava la colpa a
  /// qualcuno che non esisteva, e ci sono volute due ore per capirlo.
  ///
  /// Si guarda il BUS e non si prova a scrivere: provare vorrebbe dire un
  /// `secret-tool` che resta appeso finché non scade.
  Future<bool> cePortachiavi() async {
    try {
      final r = await esegui(
          'busctl', ['--user', '--no-pager', 'status', 'org.freedesktop.secrets']);
      return r.exitCode == 0;
    } catch (_) {
      // Senza `busctl` non si può dire di no con certezza, e dire di no per
      // ignoranza fermerebbe un computer dove il portachiavi magari c'è.
      return true;
    }
  }

  /// Mette il gettone nel portachiavi. Passa da **stdin**, mai dagli
  /// argomenti.
  Future<Esito> salvaGettone(String gettone) async {
    final g = gettone.trim();
    if (g.isEmpty) return Esito.no('Il gettone è vuoto.');
    // I gettoni di GitHub cominciano tutti per `ghp_`, `gho_`, `ghu_`,
    // `ghs_`, `ghr_` o `github_pat_`. Rifiutare qui evita di scoprire fra
    // dieci minuti che si era incollato l'indirizzo invece della chiave.
    if (!RegExp(r'^(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})$')
        .hasMatch(g)) {
      return Esito.no(
        'Questo non sembra un gettone di GitHub: cominciano per «ghp_» o per '
        '«github_pat_». Controlla di aver copiato la chiave e non altro.',
      );
    }
    if (!await cePortachiavi()) {
      return Esito.no(
        'Su questo computer non c\'è nessun portachiavi acceso, e senza non '
        'ho dove mettere il permesso al sicuro. Ne basta uno qualsiasi — '
        '`ksecretd` di KDE o `gnome-keyring` — e la sessione di Minerva lo '
        'avvia da sola al prossimo accesso.',
      );
    }
    try {
      final codice = await _conSegreto(
        'secret-tool',
        ['store', '--label=Minerva · GitHub', 'servizio', _servizio,
         'chiave', _chiave],
        g,
      );
      if (codice != 0) {
        return Esito.no('Il portachiavi c\'è ma non ha accettato il gettone: '
            'di solito vuol dire che il portafogli è ancora da sbloccare.');
      }
      return Esito.si('Gettone messo al sicuro nel portachiavi.');
    } catch (e) {
      return Esito.no('Non trovo il portachiavi di sistema: $e');
    }
  }

  Future<String?> leggiGettone() async {
    try {
      final r = await esegui(
        'secret-tool',
        ['lookup', 'servizio', _servizio, 'chiave', _chiave],
      );
      if (r.exitCode != 0) return null;
      final g = '${r.stdout}'.trim();
      return g.isEmpty ? null : g;
    } catch (_) {
      return null;
    }
  }

  Future<Esito> dimenticaGettone() async {
    try {
      final r = await esegui(
        'secret-tool',
        ['clear', 'servizio', _servizio, 'chiave', _chiave],
      );
      return r.exitCode == 0
          ? Esito.si('Gettone tolto dal portachiavi.')
          : Esito.no('Non sono riuscito a toglierlo.');
    } catch (e) {
      return Esito.no('$e');
    }
  }

  // ── Entrare senza incollare niente: il «device flow» ───────────────────
  //
  // Giacomo, 8 settembre 2026: «invece di aprire il browser e incollare… lo
  // fa Antigravity, VS Code e tanti altri. Perché non noi? Siamo di serie B?».
  //
  // Aveva ragione, e il gesto che criticava è finito male dieci minuti dopo:
  // il gettone appena creato è stato incollato dentro una conversazione, cioè
  // in un posto dove non doveva stare. Un gesto che si può sbagliare così è un
  // gesto da togliere, non da spiegare meglio.
  //
  // ── Perché il device flow e non il ritorno su 127.0.0.1 ────────────────
  //
  // Per Google usiamo il ritorno sul computer (`account/google.dart`), e va
  // bene: Google ammette le applicazioni installate senza segreto vero. GitHub
  // no — il suo giro web pretende il segreto dell'applicazione per scambiare
  // il codice, e un segreto dentro un programma che si installa non è un
  // segreto: chiunque lo estrae dal binario.
  //
  // VS Code e Antigravity ci riescono perché hanno un SERVER loro dove quel
  // segreto sta al sicuro, e il browser ci rimbalza sopra. Noi un server non
  // ce l'abbiamo. Il device flow è la risposta di GitHub esattamente a questo
  // caso: nessun segreto, nessun indirizzo di ritorno, nessun gettone da
  // copiare. È quello che usa `gh` da riga di comando.
  //
  // ── I due passi ────────────────────────────────────────────────────────
  //
  //  1. `iniziaAccesso` chiede a GitHub un codice per l'utente (otto
  //     caratteri, tipo `ABCD-1234`) e un codice per noi;
  //  2. la finestra mostra il primo e apre la pagina; l'utente conferma là;
  //  3. `attendiAccesso` chiede a GitHub, ogni pochi secondi, se ha
  //     confermato. Quando sì, torna il gettone — che va nel portachiavi come
  //     tutti gli altri.

  /// L'identificativo dell'applicazione «Minerva» su GitHub.
  ///
  /// Non è un segreto: nel device flow non ce n'è nessuno, ed è il punto. Si
  /// registra UNA volta su github.com/settings/developers (una OAuth App con
  /// «Enable Device Flow» acceso) e da lì in poi vale per chiunque usi
  /// Minerva, non per un utente solo.
  ///
  /// Registrata da Giacomo l'8 settembre 2026, con «Enable Device Flow»
  /// acceso e «Expire user access tokens» SPENTO — quest'ultimo perché un
  /// permesso che scade va rinnovato con un `refresh_token`, e quel rinnovo
  /// qui non c'è ancora: con la scadenza accesa la Custodia smetterebbe di
  /// mandare dopo qualche ora senza dire perché, che è la famiglia di difetti
  /// che questo progetto passa le giornate a togliere.
  ///
  /// Il giorno che si aggiunge il rinnovo, la scadenza si può riaccendere.
  ///
  /// Si può scavalcare con `MINERVA_GITHUB_CLIENT_ID` per provare senza
  /// toccare il codice.
  static const String _clientIdNostro = 'Ov23liGug1cmif8QD9sS';

  static String get clientId {
    final dallAmbiente = Platform.environment['MINERVA_GITHUB_CLIENT_ID'];
    if (dallAmbiente != null && dallAmbiente.trim().isNotEmpty) {
      return dallAmbiente.trim();
    }
    return _clientIdNostro;
  }

  /// Il solo permesso che si chiede: i repository. Lo stesso di prima, perché
  /// il mestiere non cambia — cambia solo come si ottiene.
  static const String _ambito = 'repo';

  /// Primo passo: GitHub dà un codice da mostrare e uno da tenere.
  Future<Esito> iniziaAccesso() async {
    if (clientId.isEmpty) {
      return Esito.no(
        'Minerva non è ancora registrata su GitHub come applicazione. Si fa '
        'una volta sola, su github.com/settings/developers: una «OAuth App» '
        'con «Enable Device Flow» acceso. Poi il suo Client ID va in '
        '`_clientIdNostro`.',
      );
    }
    final r = await chiediAlSito('/login/device/code', {
      'client_id': clientId,
      'scope': _ambito,
    });
    final c = r.corpo;
    if (r.codice != 200 || c == null || c['device_code'] == null) {
      return Esito.no(_perche(r, 'GitHub non ha dato un codice di accesso.'));
    }
    return Esito.si('Codice pronto.', dati: {
      // Quello che si mostra a chi guarda.
      'codice': '${c['user_code'] ?? ''}',
      'dove': '${c['verification_uri'] ?? 'https://github.com/login/device'}',
      // Quello che serve a noi, e che non si mostra a nessuno.
      'nostro': '${c['device_code'] ?? ''}',
      'ogni': c['interval'] is int ? c['interval'] : 5,
      'scadeFra': c['expires_in'] is int ? c['expires_in'] : 900,
    });
  }

  /// Secondo passo: si aspetta che l'utente confermi sul sito.
  ///
  /// `attendi` è iniettabile perché una prova non può stare ferma cinque
  /// secondi per giro: senza, provare il caso «prima aspetta, poi riesce»
  /// costerebbe dieci secondi veri a ogni esecuzione.
  Future<Esito> attendiAccesso(
    String nostro, {
    int ogni = 5,
    int scadeFra = 900,
    Future<void> Function(Duration)? attendi,
  }) async {
    if (nostro.isEmpty) return Esito.no('Manca il codice di questo accesso.');
    final dormi = attendi ?? (d) => Future<void>.delayed(d);
    var passo = ogni < 1 ? 1 : ogni;
    final fine = DateTime.now().add(Duration(seconds: scadeFra));

    while (DateTime.now().isBefore(fine)) {
      await dormi(Duration(seconds: passo));
      final r = await chiediAlSito('/login/oauth/access_token', {
        'client_id': clientId,
        'device_code': nostro,
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
      final c = r.corpo;
      if (c == null) {
        return Esito.no(_perche(r, 'GitHub non ha risposto.'));
      }
      final gettone = '${c['access_token'] ?? ''}';
      if (gettone.isNotEmpty) {
        // Il gettone del device flow comincia per `gho_`, e passa dallo stesso
        // portachiavi di prima: da qui in avanti non cambia niente.
        final messo = await salvaGettone(gettone);
        if (!messo.riuscito) return messo;
        return chiSei();
      }
      switch ('${c['error'] ?? ''}') {
        case 'authorization_pending':
          continue; // sta ancora guardando la pagina
        case 'slow_down':
          // GitHub chiede di rallentare, e lo si fa: insistere fa scadere
          // l'accesso invece di accelerarlo.
          passo += 5;
          continue;
        case 'expired_token':
          return Esito.no('Il codice è scaduto. Se ne fa un altro: '
              'non è un guasto, sono passati troppi minuti.');
        case 'access_denied':
          return Esito.no('L\'accesso è stato negato sulla pagina di GitHub.');
        default:
          return Esito.no(_perche(r, 'GitHub ha risposto in un modo che non '
              'conosco: ${c['error'] ?? r.codice}'));
      }
    }
    return Esito.no('Il codice è scaduto prima della conferma.');
  }

  static String _perche(RispostaRete r, String ripiego) {
    final d = r.corpo?['error_description'];
    if (d is String && d.isNotEmpty) return d;
    if (r.codice == 0) return 'Non riesco a raggiungere GitHub.';
    return ripiego;
  }

  static Future<RispostaRete> _chiediAlSitoVero(
      String percorso, Map<String, String> campi) async {
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await cliente.postUrl(Uri.parse('https://github.com$percorso'));
      // `Accept: application/json` e non il modulo: senza, GitHub risponde in
      // `application/x-www-form-urlencoded` e il `jsonDecode` qui sotto non
      // capisce niente — un difetto che si presenta come «GitHub non risponde».
      req.headers.set('Accept', 'application/json');
      req.headers.set('User-Agent', 'Minerva-Custodia');
      req.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(campi.entries
          .map((e) => '${Uri.encodeQueryComponent(e.key)}='
              '${Uri.encodeQueryComponent(e.value)}')
          .join('&'));
      final res = await req.close();
      final testo = await res.transform(utf8.decoder).join();
      Map<String, dynamic>? letto;
      try {
        final d = jsonDecode(testo);
        if (d is Map<String, dynamic>) letto = d;
      } catch (_) {}
      return RispostaRete(res.statusCode, letto);
    } catch (_) {
      return const RispostaRete(0, null);
    } finally {
      cliente.close(force: true);
    }
  }

  // ── Chi sei ────────────────────────────────────────────────────────────

  /// Chiede a GitHub chi è il proprietario del gettone.
  ///
  /// Si fa **prima** di qualsiasi altra cosa: un gettone sbagliato scoperto al
  /// momento dell'invio dà un errore di git che parla di autenticazione HTTP e
  /// non dice a nessuno che bisogna rifare la chiave.
  Future<Esito> chiSei() async {
    final g = await leggiGettone();
    if (g == null) return Esito.no('Non ho ancora un gettone di GitHub.');
    final r = await chiedi('GET', '/user', g, null);
    if (r.codice == 200) {
      final nome = '${r.corpo?['login'] ?? ''}';
      return Esito.si(nome, dati: r.corpo);
    }
    return Esito.no(erroreRete(r));
  }

  /// Nome e indirizzo con cui firmare i salvataggi, presi dall'account.
  ///
  /// L'indirizzo è quello «noreply» che GitHub dà a ogni account
  /// (`id+login@users.noreply.github.com`): lega i salvataggi al profilo
  /// senza mettere l'email vera in una storia che magari un giorno sarà
  /// pubblica. È anche quello che GitHub stesso usa quando si modifica un
  /// file dal sito con l'email nascosta.
  Future<Esito> identita() async {
    final r = await chiSei();
    if (!r.riuscito) return r;
    final c = r.dati ?? const <String, dynamic>{};
    final login = '${c['login'] ?? ''}'.trim();
    final id = c['id'];
    if (login.isEmpty || id == null) {
      return Esito.no('GitHub non mi ha detto chi sei.');
    }
    final nome = '${c['name'] ?? ''}'.trim();
    return Esito.si(login, dati: {
      'nome': nome.isNotEmpty ? nome : login,
      'email': '$id+$login@users.noreply.github.com',
      'login': login,
    });
  }

  /// Un archivio che c'è già, se è di chi è collegato.
  Future<Esito> archivioEsistente(String nome) async {
    final g = await leggiGettone();
    if (g == null) return Esito.no('Non ho ancora un gettone di GitHub.');
    final io = await chiSei();
    if (!io.riuscito) return io;
    final login = io.messaggio ?? '';
    final r = await chiedi('GET', '/repos/$login/$nome', g, null);
    if (r.codice == 200) {
      return Esito.si('${r.corpo?['clone_url'] ?? ''}', dati: r.corpo);
    }
    return Esito.no(erroreRete(r));
  }

  // ── L'archivio ─────────────────────────────────────────────────────────

  /// Crea l'archivio su GitHub. `già esiste` non è un guasto: si riusa.
  Future<Esito> creaArchivio(String nome, {bool privato = true}) async {
    final g = await leggiGettone();
    if (g == null) return Esito.no('Non ho ancora un gettone di GitHub.');
    if (!RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(nome)) {
      return Esito.no(
        'GitHub accetta solo lettere, numeri, punti, trattini e trattini '
        'bassi nel nome di un archivio: «$nome» non va.',
      );
    }
    final r = await chiedi('POST', '/user/repos', g, {
      'name': nome,
      'private': privato,
      // Niente README, licenza o .gitignore creati da loro: creerebbero un
      // primo salvataggio che il nostro non conosce, e il primo invio
      // fallirebbe con «rejected, fetch first» — che è il messaggio che fa
      // rinunciare la gente.
      'auto_init': false,
    });
    if (r.codice == 201) {
      return Esito.si('${r.corpo?['clone_url'] ?? ''}', dati: r.corpo);
    }
    if (r.codice == 422) {
      return Esito.no(
        'Su GitHub c\'è già un archivio che si chiama «$nome». Scegli un '
        'altro nome, oppure collega quello che c\'è già.',
      );
    }
    return Esito.no(erroreRete(r));
  }

  // ── Collegare e mandare ────────────────────────────────────────────────

  /// Dice a git dove sta l'archivio. **Senza gettone nell'indirizzo**: quello
  /// finirebbe in `.git/config`, e da lì in ogni copia del progetto.
  Future<Esito> collega(String cartella, String url) async {
    if (!RegExp(r'^https://github\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+(\.git)?$')
        .hasMatch(url)) {
      return Esito.no(
        'Questo non è un indirizzo di GitHub: deve essere fatto come '
        '«https://github.com/tuonome/progetto.git».',
      );
    }
    if (url.contains('@')) {
      return Esito.no('Non metto nessuna chiave dentro l\'indirizzo.');
    }
    final c = await esegui('git', ['-C', cartella, 'remote', 'get-url', 'origin']);
    final r = c.exitCode == 0
        ? await esegui('git', ['-C', cartella, 'remote', 'set-url', 'origin', url])
        : await esegui('git', ['-C', cartella, 'remote', 'add', 'origin', url]);
    if (r.exitCode != 0) return Esito.no('${r.stderr}'.trim());
    return Esito.si('Collegato a $url');
  }

  /// Manda i salvataggi su GitHub.
  ///
  /// ── Il gettone arriva a git senza toccare né il disco né la riga di
  /// comando ──
  ///
  /// `credential.helper` è uno script di shell che git esegue quando gli serve
  /// una password, e qui stampa il contenuto di una variabile d'ambiente che
  /// esiste **solo dentro quel processo**. Non passa da `.git/config`, non
  /// passa dagli argomenti, e muore quando git esce.
  Future<Esito> manda(String cartella, {String ramo = 'principale'}) async {
    final g = await leggiGettone();
    if (g == null) return Esito.no('Non ho ancora un gettone di GitHub.');

    final rem = await esegui('git', ['-C', cartella, 'remote', 'get-url', 'origin']);
    if (rem.exitCode != 0) {
      return Esito.no('Questo progetto non è ancora collegato a GitHub.');
    }

    // ── Il controllo dei segreti, di nuovo e per l'ultima volta ──────────
    //
    // Già fatto al salvataggio, e rifatto qui apposta: un progetto può avere
    // salvataggi più vecchi del controllo, e mandarli fuori è l'ultimo momento
    // in cui si può ancora non farlo.
    final tracciati = await esegui(
        'git', ['-C', cartella, 'ls-files', '-z']);
    if (tracciati.exitCode == 0) {
      final elenco = [
        for (final f in '${tracciati.stdout}'.split('\u0000'))
          if (f.isNotEmpty) f,
      ];
      final trovati = await const Segreti().guarda(cartella, elenco);
      if (trovati.isNotEmpty) {
        final primo = trovati.first;
        return Esito.no(
          'Non mando fuori niente: «${primo.percorso}» ${primo.perche}'
          '${trovati.length > 1 ? " (e altri ${trovati.length - 1})" : ""}. '
          'Su internet non si torna indietro.',
          dati: {'segreti': [for (final t in trovati) t.toJson()]},
        );
      }
    }

    // Quanti salvataggi stanno per partire: si conta PRIMA, contro quello
    // che si sa del ramo remoto. Serve a dire «mandati tre salvataggi» o
    // «GitHub era già aggiornato» invece di un «Mandato» uguale per tutti —
    // che è come si è arrivati a credere di aver mandato quello che non era
    // ancora stato salvato.
    var daMandare = -1;
    final conta = await esegui('git',
        ['-C', cartella, 'rev-list', '--count', 'origin/$ramo..$ramo']);
    if (conta.exitCode == 0) {
      daMandare = int.tryParse('${conta.stdout}'.trim()) ?? -1;
    }
    final ultimo = await esegui('git',
        ['-C', cartella, 'log', '-1', '--format=%s', ramo]);
    final cosa = ultimo.exitCode == 0 ? '${ultimo.stdout}'.trim() : '';

    final r = await esegui(
      'git',
      [
        // ── Solo il nostro gettone ─────────────────────────────────────
        //
        // I gestori di credenziali si sommano: quelli di sistema e di
        // `~/.gitconfig` (qui `libsecret`) venivano interpellati PRIMA del
        // nostro. Una credenziale vecchia nel portachiavi faceva fallire
        // l'invio, e noi — credendo morto il gettone — lo cancellavamo:
        // «mi chiede di nuovo l'accesso» (PC di prova, 29 settembre 2026).
        // Un valore vuoto azzera l'elenco, e resta solo quello qui sotto.
        '-c',
        'credential.helper=',
        '-c',
        'credential.helper=!f() { echo username=x; '
            'echo "password=\$MINERVA_GETTONE_GITHUB"; }; f',
        '-C', cartella,
        'push', '--set-upstream', 'origin', ramo,
      ],
      environment: {'MINERVA_GETTONE_GITHUB': g, 'GIT_TERMINAL_PROMPT': '0'},
      includeParentEnvironment: true,
    );
    if (r.exitCode != 0) {
      // ── Un gettone morto non resta nel portachiavi ──────────────────
      //
      // Un gettone scade, o viene revocato dal sito, e da quel momento non
      // varrà più niente: tenerlo vuol dire che il pannello continua a dire
      // «Sei linuxiano85» mentre ogni invio fallisce, e chi guarda dà la
      // colpa alla rete o al programma. Toglierlo fa ricomparire da sé la
      // casella «incolla qui la chiave», che è la cosa da fare.
      //
      // Si toglie SOLO quando GitHub dice che non ci riconosce: un disco
      // pieno o una rete che cade non c'entrano niente col gettone, e
      // buttarlo via a ogni intoppo sarebbe peggio del difetto.
      final frase = errorePush('${r.stderr}');
      if (frase.contains('non mi ha riconosciuto')) {
        await dimenticaGettone();
      }
      return Esito.no(frase);
    }
    if ('${r.stderr}'.contains('Everything up-to-date') || daMandare == 0) {
      return Esito.si('GitHub era già aggiornato: non c\'era niente di nuovo '
          'da mandare.${cosa.isNotEmpty ? " L'ultimo salvataggio lassù è «$cosa»." : ""}',
          dati: {'mandati': 0});
    }
    final quanti = daMandare > 0
        ? (daMandare == 1 ? 'un salvataggio' : '$daMandare salvataggi')
        : 'i salvataggi';
    return Esito.si('Mandat${daMandare == 1 ? "o" : "i"} su GitHub $quanti'
        '${cosa.isNotEmpty ? ", l'ultimo è «$cosa»" : ""}.',
        dati: {'mandati': daMandare});
  }

  // ── Gli errori, in italiano ────────────────────────────────────────────

  static String erroreRete(RispostaRete r) {
    switch (r.codice) {
      case 401:
        return 'GitHub non riconosce il gettone: forse è scaduto, o è stato '
            'revocato. Fanne uno nuovo.';
      case 403:
        return 'GitHub ha rifiutato: o il gettone non ha i permessi giusti '
            '(serve «repo»), oppure hai fatto troppe richieste di fila.';
      case 404:
        return 'GitHub dice che non c\'è. Se l\'archivio è privato, il '
            'gettone deve avere il permesso «repo».';
      case 0:
        return 'Non riesco a raggiungere GitHub: controlla la connessione.';
      default:
        final m = r.corpo?['message'];
        return m is String && m.isNotEmpty
            ? 'GitHub ha risposto: $m'
            : 'GitHub ha risposto con un errore ${r.codice}.';
    }
  }

  static String errorePush(String grezzo) {
    final g = grezzo.toLowerCase();
    if (g.contains('authentication failed') || g.contains('invalid username')) {
      return 'GitHub non mi ha riconosciuto: il gettone è sbagliato o scaduto.';
    }
    if (g.contains('permission') && g.contains('denied')) {
      return 'Il gettone non ha il permesso di scrivere in quell\'archivio '
          '(serve «repo»).';
    }
    if (g.contains('repository not found')) {
      return 'Quell\'archivio non esiste su GitHub, o il gettone non lo vede.';
    }
    if (g.contains('fetch first') || g.contains('non-fast-forward')) {
      return 'Su GitHub c\'è del lavoro che qui non c\'è. Prendi prima le '
          'novità, poi rimanda.';
    }
    if (g.contains('exceeds github\'s file size limit') ||
        g.contains('large files detected')) {
      return 'C\'è un file troppo grosso per GitHub (il limite è 100 MB). '
          'Toglilo dai salvataggi prima di rimandare.';
    }
    if (g.contains('could not resolve host') || g.contains('network')) {
      return 'Non riesco a raggiungere GitHub: controlla la connessione.';
    }
    final righe = grezzo
        .trim()
        .split('\n')
        .where((r) => r.trim().isNotEmpty && !r.startsWith('remote:'))
        .toList();
    return righe.isEmpty ? 'L\'invio non è riuscito.' : righe.first;
  }

  // ── La rete vera ───────────────────────────────────────────────────────

  static Future<RispostaRete> _chiediVero(
    String metodo,
    String percorso,
    String gettone,
    Map<String, dynamic>? corpo,
  ) async {
    final cliente = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await cliente.openUrl(
        metodo,
        Uri.parse('https://api.github.com$percorso'),
      );
      req.headers.set('Authorization', 'Bearer $gettone');
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'Minerva-Custodia');
      req.headers.set('X-GitHub-Api-Version', '2022-11-28');
      if (corpo != null) {
        final testo = jsonEncode(corpo);
        req.headers.contentType = ContentType.json;
        req.write(testo);
      }
      final res = await req.close();
      final testo = await res.transform(utf8.decoder).join();
      Map<String, dynamic>? letto;
      try {
        final d = jsonDecode(testo);
        if (d is Map<String, dynamic>) letto = d;
      } catch (_) {}
      return RispostaRete(res.statusCode, letto);
    } catch (_) {
      return const RispostaRete(0, null);
    } finally {
      cliente.close(force: true);
    }
  }
}

class RispostaRete {
  const RispostaRete(this.codice, this.corpo);
  final int codice;
  final Map<String, dynamic>? corpo;
}

class Esito {
  const Esito.si(this.messaggio, {this.dati})
      : riuscito = true,
        errore = null;
  const Esito.no(this.errore, {this.dati})
      : riuscito = false,
        messaggio = null;

  final bool riuscito;
  final String? messaggio;
  final String? errore;
  final Map<String, dynamic>? dati;

  Map<String, dynamic> toJson() => {
        'ok': riuscito,
        if (messaggio != null) 'messaggio': messaggio,
        if (errore != null) 'errore': errore,
        if (dati != null && dati!['segreti'] != null)
          'segreti': dati!['segreti'],
      };
}

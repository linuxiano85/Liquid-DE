import 'dart:io';

import 'package:minervad/services/custodia/github_motore.dart';
import 'package:test/test.dart';

/// Prove sull'invio a GitHub.
///
/// ── Cosa si prova qui, e cosa no ───────────────────────────────────────────
///
/// **Non** si parla con GitHub davvero: servirebbe un account, una rete e un
/// gettone vero, e una prova che ha bisogno di internet è una prova che un
/// giorno fallisce per motivi suoi e smette di essere creduta. Le risposte di
/// GitHub si fingono, e si finge **soprattutto quelle che non si riesce a
/// provocare apposta**: un gettone scaduto, un permesso mancante, un archivio
/// che esiste già.
///
/// Quello che invece si prova per davvero, e che è la parte che conta:
/// **che il gettone non finisca mai dove non deve.** Non nell'indirizzo del
/// remote (da lì si propaga in ogni copia del progetto), non in `.git/config`,
/// non negli argomenti di un processo.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-github-');
    await Process.run('git', ['-C', temp.path, 'init', '-q', '-b', 'principale']);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  /// Un motore che non tocca né la rete né il portachiavi.
  GitHubMotore finto({
    String? gettone,
    bool portachiavi = true,
    RispostaRete Function(String, String, Map<String, dynamic>?)? rete,
    RispostaRete Function(String, Map<String, String>)? sito,
    List<List<String>>? registra,
  }) {
    return GitHubMotore(
      esegui: (cmd, args, {environment, includeParentEnvironment = true}) async {
        registra?.add([cmd, ...args]);
        if (cmd == 'secret-tool' && args.isNotEmpty && args.first == 'lookup') {
          return gettone == null
              ? ProcessResult(0, 1, '', '')
              : ProcessResult(0, 0, gettone, '');
        }
        // ── Nessun `secret-tool` esce da qui ──────────────────────────
        //
        // Non basta fingere `lookup`: `clear` cadeva nel `Process.run` qui
        // sotto e arrivava al portachiavi VERO, sul servizio
        // `minerva-custodia`. Finché quel gettone non esisteva non si
        // vedeva niente; il giorno che Giacomo lo crea, lanciare le prove
        // glielo cancella — e non se ne accorge nessuno, perché la prova
        // resta verde.
        if (cmd == 'secret-tool') return ProcessResult(0, 0, '', '');
        // `busctl status org.freedesktop.secrets`: c'è un portachiavi?
        if (cmd == 'busctl') {
          return ProcessResult(0, portachiavi ? 0 : 1, '', '');
        }
        return Process.run(cmd, args,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment);
      },
      chiedi: (metodo, percorso, g, corpo) async =>
          rete != null ? rete(metodo, percorso, corpo) : const RispostaRete(0, null),
      chiediAlSito: (percorso, campi) async =>
          sito != null ? sito(percorso, campi) : const RispostaRete(0, null),
      // ── Anche il portachiavi si finge ──────────────────────────────────
      //
      // Senza questa riga `salvaGettone` chiamava `secret-tool store` per
      // davvero: la prova scriveva un gettone finto **nel portachiavi di
      // Giacomo**, restava appesa trenta secondi, e la verifica che un
      // gettone non valido venga tolto non guardava niente — perché quel
      // comando non passava dalla lista qui sopra.
      conSegreto: (cmd, args, segreto) async {
        registra?.add([cmd, ...args]);
        return 0;
      },
    );
  }

  // ── Il gettone ─────────────────────────────────────────────────────────

  group('il gettone', () {
    test('un incollaggio sbagliato si riconosce subito', () async {
      final m = finto();
      for (final sbagliato in [
        'https://github.com/tizio/roba',
        'la mia password',
        'ghp_corto',
        '',
        '   ',
      ]) {
        final e = await m.salvaGettone(sbagliato);
        expect(e.riuscito, isFalse, reason: 'ha accettato «$sbagliato»');
      }
    });

    test('senza gettone, ogni cosa lo dice invece di provarci', () async {
      final m = finto(gettone: null);
      for (final e in [
        await m.chiSei(),
        await m.creaArchivio('roba'),
        await m.manda(temp.path),
      ]) {
        expect(e.riuscito, isFalse);
        expect(e.errore, contains('gettone'));
      }
    });
  });

  // ── Il gettone NON finisce nell'indirizzo ──────────────────────────────

  group('dove il gettone non deve arrivare', () {
    test('un indirizzo con dentro una chiave si rifiuta', () async {
      final m = finto(gettone: 'ghp_${'A' * 36}');
      final e = await m.collega(
          temp.path, 'https://gh' 'p_${'A' * 36}@github.com/tizio/roba.git');
      expect(e.riuscito, isFalse);
    });

    test('dopo aver collegato, .git/config non contiene nessuna chiave',
        () async {
      final m = finto(gettone: 'ghp_${'A' * 36}');
      final e = await m.collega(temp.path, 'https://github.com/tizio/roba.git');
      expect(e.riuscito, isTrue, reason: e.errore);

      final conf = await File('${temp.path}/.git/config').readAsString();
      expect(conf, contains('github.com/tizio/roba.git'));
      expect(conf, isNot(contains('gh' 'p_')));
      expect(conf.toLowerCase(), isNot(contains('token')));
      expect(conf, isNot(contains('@github.com')));
    });

    test('e nemmeno negli argomenti di git', () async {
      // `/proc/<pid>/cmdline` la legge chiunque giri come te.
      final righe = <List<String>>[];
      final m = finto(gettone: 'ghp_${'S' * 36}', registra: righe);
      await m.collega(temp.path, 'https://github.com/tizio/roba.git');
      await m.manda(temp.path);

      for (final riga in righe) {
        expect(riga.join(' '), isNot(contains('S' * 36)),
            reason: 'il gettone è finito in: ${riga.join(' ')}');
      }
    });

    test('il gettone arriva a git da una variabile, non dal disco', () async {
      final righe = <List<String>>[];
      final m = finto(gettone: 'ghp_${'A' * 36}', registra: righe);
      await m.collega(temp.path, 'https://github.com/tizio/roba.git');
      await m.manda(temp.path);

      final push = righe.firstWhere((r) => r.contains('push'),
          orElse: () => const []);
      expect(push, isNotEmpty, reason: 'il push non è mai partito');
      expect(push.join(' '), contains('credential.helper'));
      expect(push.join(' '), contains(r'$MINERVA_GETTONE_GITHUB'));
    });
  });

  // ── Collegare ──────────────────────────────────────────────────────────

  group('collegare', () {
    test('solo indirizzi di GitHub', () async {
      final m = finto(gettone: 'ghp_${'A' * 36}');
      for (final brutto in [
        'git@github.com:tizio/roba.git',
        'https://gitlab.com/tizio/roba.git',
        'https://github.com/tizio',
        'roba',
        'https://github.com/tizio/roba.git; rm -rf /',
      ]) {
        expect((await m.collega(temp.path, brutto)).riuscito, isFalse,
            reason: 'ha accettato «$brutto»');
      }
      expect(
          (await m.collega(temp.path, 'https://github.com/tizio/roba.git'))
              .riuscito,
          isTrue);
    });

    test('ricollegare cambia l\'indirizzo, non ne aggiunge un secondo',
        () async {
      final m = finto(gettone: 'ghp_${'A' * 36}');
      await m.collega(temp.path, 'https://github.com/tizio/uno.git');
      await m.collega(temp.path, 'https://github.com/tizio/due.git');
      final r = await Process.run('git', ['-C', temp.path, 'remote']);
      expect('${r.stdout}'.trim(), 'origin');
      final u = await Process.run(
          'git', ['-C', temp.path, 'remote', 'get-url', 'origin']);
      expect('${u.stdout}'.trim(), 'https://github.com/tizio/due.git');
    });

    test('non si manda niente se non è collegato', () async {
      final m = finto(gettone: 'ghp_${'A' * 36}');
      final e = await m.manda(temp.path);
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('non è ancora collegato'));
    });
  });

  // ── L'archivio ─────────────────────────────────────────────────────────

  group('creare l\'archivio', () {
    test('un nome che GitHub non accetta si ferma qui', () async {
      final m = finto(gettone: 'ghp_${'A' * 36}');
      for (final n in ['con spazio', 'con/barra', '', 'a' * 200]) {
        expect((await m.creaArchivio(n)).riuscito, isFalse,
            reason: 'ha accettato «$n»');
      }
    });

    test('nasce vuoto, apposta', () async {
      // Con `auto_init` GitHub crea un README e quindi un salvataggio che il
      // nostro non conosce: il primo invio fallirebbe con «fetch first», che è
      // il messaggio che fa rinunciare la gente.
      Map<String, dynamic>? mandato;
      final m = finto(
        gettone: 'ghp_${'A' * 36}',
        rete: (metodo, percorso, corpo) {
          mandato = corpo;
          return const RispostaRete(201, {
            'clone_url': 'https://github.com/tizio/roba.git',
          });
        },
      );
      final e = await m.creaArchivio('roba', privato: true);
      expect(e.riuscito, isTrue, reason: e.errore);
      expect(mandato?['auto_init'], isFalse);
      expect(mandato?['private'], isTrue);
      expect(e.messaggio, 'https://github.com/tizio/roba.git');
    });

    test('pubblico se lo si chiede', () async {
      Map<String, dynamic>? mandato;
      final m = finto(
        gettone: 'ghp_${'A' * 36}',
        rete: (metodo, percorso, corpo) {
          mandato = corpo;
          return const RispostaRete(201, {'clone_url': 'x'});
        },
      );
      await m.creaArchivio('roba', privato: false);
      expect(mandato?['private'], isFalse);
    });

    test('un archivio che esiste già non è un guasto, ed è detto in italiano',
        () async {
      final m = finto(
        gettone: 'ghp_${'A' * 36}',
        rete: (metodo, percorso, corpo) => const RispostaRete(422, {
          'message': 'Repository creation failed.',
        }),
      );
      final e = await m.creaArchivio('roba');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('c\'è già'));
      expect(e.errore, contains('collega quello che c\'è già'));
    });
  });

  // ── Gli errori, che è dove si vince o si perde ─────────────────────────

  group('gli errori si leggono senza sapere cos\'è HTTP', () {
    test('un gettone scaduto dice di rifarlo', () {
      final e = GitHubMotore.erroreRete(const RispostaRete(401, null));
      expect(e, contains('scaduto'));
      expect(e, contains('Fanne uno nuovo'));
    });

    test('un permesso mancante nomina il permesso', () {
      expect(GitHubMotore.erroreRete(const RispostaRete(403, null)),
          contains('repo'));
      expect(GitHubMotore.erroreRete(const RispostaRete(404, null)),
          contains('repo'));
    });

    test('la rete che manca si distingue da GitHub che rifiuta', () {
      expect(GitHubMotore.erroreRete(const RispostaRete(0, null)),
          contains('connessione'));
    });

    test('un errore che non conosciamo riporta quello che ha detto GitHub', () {
      expect(
          GitHubMotore.erroreRete(
              const RispostaRete(500, {'message': 'qualcosa di strano'})),
          contains('qualcosa di strano'));
    });

    test('il push rifiutato spiega cosa fare', () {
      expect(GitHubMotore.errorePush('! [rejected] fetch first'),
          contains('Prendi prima le novità'));
      expect(GitHubMotore.errorePush('fatal: Authentication failed for …'),
          contains('non mi ha riconosciuto'));
      expect(GitHubMotore.errorePush('remote: Repository not found.'),
          contains('non esiste su GitHub'));
      expect(
          GitHubMotore.errorePush(
              'remote: error: File big.img exceeds GitHub\'s file size limit'),
          contains('100 MB'));
    });

    test('quello che non riconosce lo riporta, e salta le righe di «remote:»',
        () {
      // Le righe `remote:` sono quello che GitHub stampa a video, spesso in
      // inglese e spesso con dentro un URL di documentazione: non sono la
      // frase da mostrare.
      expect(
          GitHubMotore.errorePush('remote: vai su https://docs…\n'
              'fatal: qualcosa di mai visto'),
          'fatal: qualcosa di mai visto');
    });
  });

  // ── Un gettone morto non resta nel portachiavi ─────────────────────────

  group('quando GitHub smette di riconoscerci', () {
    test('il gettone rifiutato viene tolto dal portachiavi', () async {
      // Un gettone scade o viene revocato dal sito. Se resta lì, il pannello
      // continua a dire «Sei tizio» mentre ogni invio fallisce, e la colpa
      // sembra della rete. Toglierlo fa ricomparire la casella per incollarne
      // uno nuovo, che è la sola cosa da fare.
      final righe = <List<String>>[];
      final m = GitHubMotore(
        esegui: (cmd, args, {environment, includeParentEnvironment = true}) async {
          righe.add([cmd, ...args]);
          if (cmd == 'secret-tool' && args.first == 'lookup') {
            return ProcessResult(0, 0, 'gh' 'p_${'A' * 36}', '');
          }
          if (cmd == 'secret-tool' && args.first == 'clear') {
            return ProcessResult(0, 0, '', '');
          }
          if (cmd == 'git' && args.contains('push')) {
            return ProcessResult(
                0, 128, '', 'fatal: Authentication failed for \'https://…\'');
          }
          // ── Nessun `secret-tool` esce da qui ──────────────────────────
          //
          // Non basta fingere `lookup`: `clear` cadeva nel `Process.run` qui
          // sotto e arrivava al portachiavi VERO, sul servizio
          // `minerva-custodia`. Finché quel gettone non esisteva non si
          // vedeva niente; il giorno che Giacomo lo crea, lanciare le prove
          // glielo cancella — e non se ne accorge nessuno, perché la prova
          // resta verde.
          if (cmd == 'secret-tool') return ProcessResult(0, 0, '', '');
          return Process.run(cmd, args);
        },
        chiedi: (a, b, c, d) async => const RispostaRete(0, null),
      );
      await m.collega(temp.path, 'https://github.com/tizio/roba.git');
      final e = await m.manda(temp.path);
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('non mi ha riconosciuto'));
      expect(righe.any((r) => r.contains('secret-tool') && r.contains('clear')),
          isTrue,
          reason: 'il gettone morto è rimasto nel portachiavi');
    });

    test('ma un intoppo qualsiasi NON butta via il gettone', () async {
      // Un disco pieno, una rete che cade: non c'entrano niente col gettone,
      // e buttarlo via a ogni intoppo sarebbe peggio del difetto.
      final righe = <List<String>>[];
      final m = GitHubMotore(
        esegui: (cmd, args, {environment, includeParentEnvironment = true}) async {
          righe.add([cmd, ...args]);
          if (cmd == 'secret-tool' && args.first == 'lookup') {
            return ProcessResult(0, 0, 'gh' 'p_${'A' * 36}', '');
          }
          if (cmd == 'git' && args.contains('push')) {
            return ProcessResult(0, 128, '',
                'fatal: unable to access …: Could not resolve host: github.com');
          }
          // ── Nessun `secret-tool` esce da qui ──────────────────────────
          //
          // Non basta fingere `lookup`: `clear` cadeva nel `Process.run` qui
          // sotto e arrivava al portachiavi VERO, sul servizio
          // `minerva-custodia`. Finché quel gettone non esisteva non si
          // vedeva niente; il giorno che Giacomo lo crea, lanciare le prove
          // glielo cancella — e non se ne accorge nessuno, perché la prova
          // resta verde.
          if (cmd == 'secret-tool') return ProcessResult(0, 0, '', '');
          return Process.run(cmd, args);
        },
        chiedi: (a, b, c, d) async => const RispostaRete(0, null),
      );
      await m.collega(temp.path, 'https://github.com/tizio/roba.git');
      expect((await m.manda(temp.path)).riuscito, isFalse);
      expect(righe.any((r) => r.contains('clear')), isFalse,
          reason: 'ha buttato via il gettone per un problema di rete');
    });
  });

  // ── Il controllo dei segreti, di nuovo ─────────────────────────────────

  test('non manda fuori un progetto con dentro una chiave', () async {
    // Già controllato al salvataggio, e ricontrollato qui apposta: un progetto
    // può avere salvataggi più vecchi del controllo, e l'invio è l'ultimo
    // momento in cui si può ancora non farlo. Su internet non si torna
    // indietro.
    final capo = '-----BEGIN ';
    await File('${temp.path}/chiave.txt')
        .writeAsString('${capo}RSA PRIVATE KEY-----\nMIIE\n');
    await Process.run('git', ['-C', temp.path, 'add', '-A']);
    await Process.run('git', [
      '-C', temp.path,
      '-c', 'user.name=P', '-c', 'user.email=p@p',
      'commit', '-qm', 'ops',
    ]);

    final m = finto(gettone: 'ghp_${'A' * 36}');
    await m.collega(temp.path, 'https://github.com/tizio/roba.git');
    final e = await m.manda(temp.path);
    expect(e.riuscito, isFalse);
    expect(e.errore, contains('Non mando fuori niente'));
    expect(e.errore, contains('Su internet non si torna indietro'));
  });

  // ── Entrare senza incollare niente ─────────────────────────────────────
  //
  // Il device flow ha cinque risposte possibili e quattro non si riescono a
  // provocare dal vivo: si può aspettare un utente che non conferma, ma non si
  // può far scadere un codice a comando, né farsi dire «rallenta» da GitHub.
  // Sono proprio quelle che, sbagliate, lasciano la finestra ferma per sempre.
  //
  // `attendi` è iniettabile per questo: senza, ogni prova costerebbe cinque
  // secondi veri per giro, e una prova che costa dieci secondi si finisce col
  // non lanciarla.
  group('il device flow', () {
    test('senza applicazione registrata lo dice, e dice come si ripara',
        () async {
      // Il caso di oggi: il Client ID non c'è ancora. Deve uscirne una frase
      // che nomina la cura, non un errore di rete.
      final m = finto();
      final e = await m.iniziaAccesso();
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('github.com/settings/developers'));
      expect(e.errore, contains('Device Flow'));
    }, skip: GitHubMotore.clientId.isNotEmpty
        ? 'Minerva è già registrata: questo caso non esiste più'
        : null);

    test('il primo passo dà il codice da mostrare e quello da tenere',
        () async {
      if (GitHubMotore.clientId.isEmpty) return; // senza id non si parte
      final m = finto(sito: (percorso, campi) {
        expect(percorso, '/login/device/code');
        expect(campi['scope'], 'repo');
        return const RispostaRete(200, {
          'device_code': 'IL-NOSTRO',
          'user_code': 'ABCD-1234',
          'verification_uri': 'https://github.com/login/device',
          'interval': 5,
          'expires_in': 900,
        });
      });
      final e = await m.iniziaAccesso();
      expect(e.riuscito, isTrue);
      expect(e.dati!['codice'], 'ABCD-1234');
      expect(e.dati!['nostro'], 'IL-NOSTRO');
    });

    test('finché non confermi, si aspetta senza lamentarsi', () async {
      var giri = 0;
      final m = finto(
        gettone: 'gho_unoduetrequattrocinquesei12',
        sito: (percorso, campi) {
          giri++;
          if (giri < 3) return const RispostaRete(200, {'error': 'authorization_pending'});
          return const RispostaRete(200, {'access_token': 'gho_unoduetrequattrocinquesei12'});
        },
        rete: (metodo, percorso, corpo) =>
            const RispostaRete(200, {'login': 'linuxiano85'}),
      );
      final e = await m.attendiAccesso('IL-NOSTRO',
          ogni: 1, attendi: (_) async {});
      expect(giri, 3, reason: 'non ha aspettato la conferma');
      expect(e.riuscito, isTrue);
      expect(e.messaggio, 'linuxiano85');
    });

    test('«rallenta» si ascolta invece di insistere', () async {
      // Insistere fa scadere l'accesso invece di accelerarlo: GitHub lo dice,
      // e chi non lo ascolta si vede il codice morire in faccia.
      final attese = <int>[];
      var giri = 0;
      final m = finto(
        gettone: 'gho_unoduetrequattrocinquesei12',
        sito: (percorso, campi) {
          giri++;
          if (giri == 1) return const RispostaRete(200, {'error': 'slow_down'});
          return const RispostaRete(200, {'access_token': 'gho_unoduetrequattrocinquesei12'});
        },
        rete: (metodo, percorso, corpo) =>
            const RispostaRete(200, {'login': 'linuxiano85'}),
      );
      final e = await m.attendiAccesso('IL-NOSTRO',
          ogni: 5, attendi: (d) async => attese.add(d.inSeconds));
      expect(e.riuscito, isTrue);
      expect(attese, [5, 10],
          reason: 'dopo «slow_down» il passo deve allungarsi, non restare uguale');
    });

    test('un codice scaduto dice che se ne fa un altro', () async {
      final m = finto(sito: (percorso, campi) =>
          const RispostaRete(200, {'error': 'expired_token'}));
      final e = await m.attendiAccesso('IL-NOSTRO', ogni: 1, attendi: (_) async {});
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('scaduto'));
      expect(e.errore, contains('non è un guasto'));
    });

    test('un rifiuto sulla pagina non diventa un errore di rete', () async {
      final m = finto(sito: (percorso, campi) =>
          const RispostaRete(200, {'error': 'access_denied'}));
      final e = await m.attendiAccesso('IL-NOSTRO', ogni: 1, attendi: (_) async {});
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('negato'));
    });

    test('e il gettone finisce nel portachiavi, mai negli argomenti', () async {
      // La stessa regola di sempre, e qui va ricontrollata: il device flow è
      // una strada NUOVA per arrivare a un gettone, e una strada nuova può
      // saltare la porta giusta.
      final visti = <List<String>>[];
      final m = finto(
        gettone: 'gho_unoduetrequattrocinquesei12',
        registra: visti,
        sito: (percorso, campi) =>
            const RispostaRete(200, {'access_token': 'gho_unoduetrequattrocinquesei12'}),
        rete: (metodo, percorso, corpo) =>
            const RispostaRete(200, {'login': 'linuxiano85'}),
      );
      await m.attendiAccesso('IL-NOSTRO', ogni: 1, attendi: (_) async {});
      final store = visti.where((c) => c.contains('store')).toList();
      expect(store, isNotEmpty, reason: 'il gettone non è stato messo via');
      for (final c in visti) {
        expect(c.join(' '), isNot(contains('gho_')),
            reason: 'il gettone è finito negli argomenti di un processo: '
                '/proc/<pid>/cmdline lo legge chiunque giri come te');
      }
    });
  });

  // ── «Non c'è» e «ha detto di no» sono due cose diverse ──────────────────
  //
  // L'8 settembre 2026 su questa macchina non c'era NESSUNO che dichiarasse
  // `org.freedesktop.secrets`, e la Custodia rispondeva «il portachiavi non ha
  // accettato il gettone»: dava la colpa a qualcuno che non esisteva. Due ore
  // per capirlo.
  //
  // Le due situazioni hanno due cure opposte — installare qualcosa, o
  // sbloccare il portafogli — e un messaggio che le confonde manda a cercare
  // dalla parte sbagliata.
  group('il portachiavi che non c\'è', () {
    test('senza nessun portachiavi si dice quello, e come si ripara', () async {
      final m = finto(portachiavi: false);
      final e = await m.salvaGettone('gho_unoduetrequattrocinquesei12');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('nessun portachiavi'));
      expect(e.errore, contains('gnome-keyring'),
          reason: 'il messaggio deve nominare la cura, non solo il guasto');
    });

    test('e non si prova nemmeno a scrivere', () async {
      // Provare vorrebbe dire un `secret-tool` che resta appeso finché non
      // scade, con la finestra ferma a guardarlo.
      final visti = <List<String>>[];
      final m = finto(portachiavi: false, registra: visti);
      await m.salvaGettone('gho_unoduetrequattrocinquesei12');
      expect(visti.where((c) => c.first == 'secret-tool'), isEmpty);
    });

    test('col portachiavi acceso, un rifiuto parla di sblocco', () async {
      // Il caso opposto: il servizio c'è e dice di no. Quasi sempre è il
      // portafogli ancora chiuso, e dirlo risparmia la caccia.
      final m = GitHubMotore(
        esegui: (cmd, args, {environment, includeParentEnvironment = true}) async =>
            ProcessResult(0, cmd == 'busctl' ? 0 : 1, '', ''),
        conSegreto: (cmd, args, segreto) async => 1,
      );
      final e = await m.salvaGettone('gho_unoduetrequattrocinquesei12');
      expect(e.riuscito, isFalse);
      expect(e.errore, contains('sbloccare'));
    });
  });
}

import 'dart:io';

import 'package:minervad/services/custodia/git_motore.dart';
import 'package:minervad/services/custodia/github_motore.dart';
import 'package:minervad/services/custodia/punti_motore.dart';
import 'package:minervad/services/custodia/registro.dart';
import 'package:minervad/services/custodia_service.dart';
import 'package:test/test.dart';

/// Prove sul pezzo che unisce la Custodia a GitHub.
///
/// `github_motore_test.dart` prova il motore da solo — che il gettone non
/// finisca dove non deve, che gli errori si leggano. Qui si prova la cucitura,
/// che è dove stanno gli errori di questo strato: **cosa si rifiuta di fare, e
/// cosa si dice quando lo si rifiuta.**
///
/// Con GitHub non si parla: le sue risposte si fingono. Una prova che ha
/// bisogno di internet è una prova che un giorno fallisce per motivi suoi e
/// smette di essere creduta.
void main() {
  late Directory temp;
  late String progetto;

  /// Il servizio, con un GitHub finto sotto.
  Future<CustodiaService> costruisci({
    String? gettone,
    RispostaRete Function(String, String, Map<String, dynamic>?)? rete,
    List<List<String>>? registra,
  }) async {
    final s = CustodiaService(
      registro: Registro(percorso: '${temp.path}/progetti.json'),
      punti: PuntiMotore(radice: '${temp.path}/punti'),
      git: GitMotore(),
      github: GitHubMotore(
        esegui: (cmd, args, {environment, includeParentEnvironment = true}) async {
          registra?.add([cmd, ...args]);
          if (cmd == 'secret-tool' && args.isNotEmpty && args.first == 'lookup') {
            return gettone == null
                ? ProcessResult(0, 1, '', '')
                : ProcessResult(0, 0, gettone, '');
          }
          // Il push non parte davvero: non c'è nessun GitHub dall'altra parte,
          // e quello che qui interessa è che ci si sia arrivati.
          if (cmd == 'git' && args.contains('push')) {
            return ProcessResult(0, 0, '', '');
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
          return Process.run(cmd, args,
              environment: environment,
              includeParentEnvironment: includeParentEnvironment);
        },
        chiedi: (metodo, percorso, g, corpo) async =>
            rete != null ? rete(metodo, percorso, corpo) : const RispostaRete(0, null),
        // ── Anche il portachiavi si finge ────────────────────────────────
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
      ),
    );
    await s.init();
    return s;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-cust-gh-');
    progetto = '${temp.path}/Il Mio Progetto';
    await Directory(progetto).create(recursive: true);
    await File('$progetto/uno.txt').writeAsString('roba');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> conStoria(CustodiaService c) async {
    await c.iniziaStoria(progetto);
    await Process.run('git', ['-C', progetto, 'config', 'user.name', 'Prova']);
    await Process.run(
        'git', ['-C', progetto, 'config', 'user.email', 'p@prova.it']);
  }

  // Spezzato apposta: scritto per intero farebbe scattare il nostro stesso
  // controllo dei segreti su questo file, e avrebbe ragione lui.
  final chiave = 'gh' 'p_${'A' * 36}';
  const url = 'https://github.com/tizio/roba.git';

  // ── Chi non ha una storia non va su GitHub ─────────────────────────────

  test('una cartella senza storia non si collega, e sa perché', () async {
    final c = await costruisci(gettone: chiave);
    await c.aggiungi(progetto, motore: 'copia');
    final e = await c.aggiungiDestinazione(progetto, 'github', 'roba', url);
    expect(e['ok'], isFalse);
    expect('${e['errore']}', contains('storia'));
    // E non deve aver lasciato mezzo collegamento in giro.
    final r = await Process.run('git', ['-C', progetto, 'remote']);
    expect('${r.stdout}'.trim(), isEmpty);
  });

  test('un indirizzo sbagliato si scopre mentre lo si sceglie, non dopo',
      () async {
    final c = await costruisci(gettone: chiave);
    await c.aggiungi(progetto);
    await conStoria(c);
    final e = await c.aggiungiDestinazione(
        progetto, 'github', 'roba', 'https://gitlab.com/tizio/roba.git');
    expect(e['ok'], isFalse);
    // …e la destinazione non è finita nell'elenco.
    expect(c.registro.cerca(progetto)!.destinazioni, isEmpty);
  });

  test('collegare mette a posto il remote', () async {
    final c = await costruisci(gettone: chiave);
    await c.aggiungi(progetto);
    await conStoria(c);
    final e = await c.aggiungiDestinazione(progetto, 'github', 'roba', url);
    expect(e['ok'], isTrue, reason: '${e['errore']}');
    final r =
        await Process.run('git', ['-C', progetto, 'remote', 'get-url', 'origin']);
    expect('${r.stdout}'.trim(), url);
  });

  // ── Mandare ────────────────────────────────────────────────────────────

  test('non si manda un progetto che non ha ancora nessun salvataggio',
      () async {
    final c = await costruisci(gettone: chiave);
    await c.aggiungi(progetto);
    await conStoria(c);
    await c.aggiungiDestinazione(progetto, 'github', 'roba', url);
    final e = await c.manda(progetto, url);
    expect(e['ok'], isFalse);
    expect('${e['errore']}', contains('primo salvataggio'));
  });

  test('mandato, dice che le modifiche non salvate sono rimaste qui', () async {
    final c = await costruisci(gettone: chiave);
    await c.aggiungi(progetto);
    await conStoria(c);
    await c.salva(progetto, 'il primo');
    await c.aggiungiDestinazione(progetto, 'github', 'roba', url);

    // Del lavoro non salvato, che è il caso normale e non l'eccezione.
    await File('$progetto/due.txt').writeAsString('non ancora salvato');

    final e = await c.manda(progetto, url);
    expect(e['ok'], isTrue, reason: '${e['errore']}');
    expect('${e['nota']}', contains('non salvate'));
    // E lo dice NEL MESSAGGIO, che è l'unica cosa che la finestra mostra:
    // la nota in un campo a parte c'era dal primo giorno, e non l'ha mai
    // letta nessuno. Visto il 18 settembre 2026: «Mandato su GitHub.» con
    // le date vecchie lassù.
    expect('${e['messaggio']}', contains('non ancora salvat'));
    expect('${e['messaggio']}', contains('Salva'));
    // E l'invio è stato annotato: è quello che il riquadro mostra.
    expect(c.registro.cerca(progetto)!.ultimoInvio, isNotNull);
  });

  test('«Manda» mentre il salvataggio è in corso aspetta il salvataggio', () async {
    // La corsa vera del 18 settembre 2026: invio alle 21:28:49, salvataggio
    // finito alle 21:29:12. Il push era partito col salvataggio di PRIMA.
    // Qui il push finto registra quale HEAD trova quando parte.
    final teste = <String>[];
    final c = await costruisci(
      gettone: chiave,
      registra: null,
    );
    await c.aggiungi(progetto);
    await conStoria(c);
    await c.salva(progetto, 'il primo');
    await c.aggiungiDestinazione(progetto, 'github', 'roba', url);

    // Un GitHub finto che, al push, legge la testa del ramo in quel momento.
    final ghSpia = GitHubMotore(
      esegui: (cmd, args, {environment, includeParentEnvironment = true}) async {
        if (cmd == 'secret-tool' && args.first == 'lookup') {
          return ProcessResult(0, 0, chiave, '');
        }
        if (cmd == 'secret-tool') return ProcessResult(0, 0, '', '');
        if (cmd == 'git' && args.contains('push')) {
          final h = await Process.run('git', ['-C', progetto, 'log', '-1', '--format=%s']);
          teste.add('${h.stdout}'.trim());
          return ProcessResult(0, 0, '', '');
        }
        return Process.run(cmd, args, environment: environment,
            includeParentEnvironment: includeParentEnvironment);
      },
      chiedi: (m, p, g, corpo) async => const RispostaRete(0, null),
      conSegreto: (cmd, args, segreto) async => 0,
    );
    // E un git LENTO a salvare: nel progetto vero `git add -A` su una
    // cartella grossa ci mette dei secondi, ed è in quei secondi che il
    // dito arriva su «Manda adesso». Qui il commit aspetta mezzo secondo.
    final gitLento = GitMotore(esegui: (args, {dentro}) async {
      if (args.contains('commit')) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      return Process.run('git', args,
          environment: const {'LC_ALL': 'C', 'GIT_TERMINAL_PROMPT': '0'});
    });
    final c2 = CustodiaService(
      registro: c.registro, punti: c.punti, git: gitLento, github: ghSpia);
    await c2.init();

    await File('$progetto/due.txt').writeAsString('la seconda');
    // Salva e manda, uno dietro l'altro SENZA aspettare: com'è premere due
    // pulsanti di fila.
    final salva = c2.salva(progetto, 'il secondo');
    final manda = c2.manda(progetto, url);
    await Future.wait([salva, manda]);
    expect(teste, ['il secondo'],
        reason: 'il push è partito prima che il salvataggio fosse finito');
  });

  test('se GitHub era già aggiornato lo dice, invece di «Mandato»', () async {
    final c = await costruisci(
      gettone: chiave,
      registra: null,
    );
    await c.aggiungi(progetto);
    await conStoria(c);
    await c.salva(progetto, 'il primo');
    await c.aggiungiDestinazione(progetto, 'github', 'roba', url);
    final gh = GitHubMotore(
      esegui: (cmd, args, {environment, includeParentEnvironment = true}) async {
        if (cmd == 'secret-tool' && args.first == 'lookup') {
          return ProcessResult(0, 0, chiave, '');
        }
        if (cmd == 'secret-tool') return ProcessResult(0, 0, '', '');
        if (cmd == 'git' && args.contains('push')) {
          return ProcessResult(0, 0, '', 'Everything up-to-date\n');
        }
        return Process.run(cmd, args, environment: environment,
            includeParentEnvironment: includeParentEnvironment);
      },
      chiedi: (m, p, g, corpo) async => const RispostaRete(0, null),
      conSegreto: (cmd, args, segreto) async => 0,
    );
    final c2 = CustodiaService(
        registro: c.registro, punti: c.punti, git: c.git, github: gh);
    await c2.init();
    final e = await c2.manda(progetto, url);
    expect(e['ok'], isTrue);
    expect('${e['messaggio']}', contains('già aggiornato'));
    expect('${e['messaggio']}', isNot(startsWith('Mandat')));
    expect(e['mandati'], 0);
  });

  test('un progetto con dentro una chiave non esce, nemmeno se è salvato',
      () async {
    final c = await costruisci(gettone: chiave);
    await c.aggiungi(progetto);
    await conStoria(c);
    final capo = '-----BEGIN ';
    await File('$progetto/chiave.txt')
        .writeAsString('${capo}RSA PRIVATE KEY-----\nMIIE\n');
    await c.salva(progetto, 'ops', forza: true);
    await c.aggiungiDestinazione(progetto, 'github', 'roba', url);

    final e = await c.manda(progetto, url);
    expect(e['ok'], isFalse);
    expect('${e['errore']}', contains('Non mando fuori niente'));
  });

  // ── Il gettone ─────────────────────────────────────────────────────────

  group('il gettone', () {
    test('se non vale niente non resta nel portachiavi', () async {
      final righe = <List<String>>[];
      final c = await costruisci(
        gettone: chiave,
        rete: (m, p, b) => const RispostaRete(401, null),
        registra: righe,
      );
      final e = await c.gettoneGitHub(chiave);
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('scaduto'));
      expect(righe.any((r) => r.contains('secret-tool') && r.contains('clear')),
          isTrue,
          reason: 'un gettone che non vale niente è rimasto nel portachiavi');
    });

    test('quando vale, la risposta dice chi sei e non contiene la chiave',
        () async {
      final c = await costruisci(
        gettone: chiave,
        rete: (m, p, b) => const RispostaRete(200, {'login': 'linuxiano85'}),
      );
      final e = await c.gettoneGitHub(chiave);
      expect(e['ok'], isTrue);
      expect(e['chi'], 'linuxiano85');
      expect('$e', isNot(contains('AAAA')));
    });

    test('«chi sei» non è un errore quando non c\'è nessun gettone', () async {
      final c = await costruisci(gettone: null);
      final e = await c.chiSeiGitHub();
      // `ok` vero e `collegato` falso: non c'è niente di rotto, semplicemente
      // non è ancora stato fatto. Un rosso qui direbbe una bugia.
      expect(e['ok'], isTrue);
      expect(e['collegato'], isFalse);
    });
  });

  // ── Creare l'archivio ──────────────────────────────────────────────────

  test('creare l\'archivio lo collega anche, in un gesto solo', () async {
    final c = await costruisci(
      gettone: chiave,
      rete: (m, p, b) => const RispostaRete(201, {'clone_url': url}),
    );
    await c.aggiungi(progetto);
    await conStoria(c);

    final e = await c.creaArchivioGitHub(progetto, 'roba');
    expect(e['ok'], isTrue, reason: '${e['errore']}');
    expect(e['dove'], url);
    expect(c.registro.cerca(progetto)!.destinazioni.first.dove, url);
    final r =
        await Process.run('git', ['-C', progetto, 'remote', 'get-url', 'origin']);
    expect('${r.stdout}'.trim(), url);
  });

  test('se GitHub rifiuta, non resta una destinazione che non esiste',
      () async {
    final c = await costruisci(
      gettone: chiave,
      rete: (m, p, b) =>
          const RispostaRete(422, {'message': 'Repository creation failed.'}),
    );
    await c.aggiungi(progetto);
    await conStoria(c);

    final e = await c.creaArchivioGitHub(progetto, 'roba');
    expect(e['ok'], isFalse);
    expect(c.registro.cerca(progetto)!.destinazioni, isEmpty);
  });
}

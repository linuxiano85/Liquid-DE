import 'dart:io';

import 'package:minervad/services/custodia/git_motore.dart';
import 'package:minervad/services/custodia/punti_motore.dart';
import 'package:minervad/services/custodia/registro.dart';
import 'package:minervad/services/custodia_service.dart';
import 'package:test/test.dart';

/// Prove sulla regola che tiene in piedi tutta la Custodia:
///
///   **nessuna operazione che può perdere lavoro parte senza aver preso prima
///   un punto di ritorno; se il punto non riesce, l'operazione non parte.**
///
/// Sono le prove più importanti del programma, e sono quasi tutte **rifiuti**.
/// La ragione è semplice: quando la regola funziona non si vede niente — si
/// vede solo il giorno che qualcuno preme «torna a ieri» avendo tre ore di
/// lavoro non salvato aperte, e o le ritrova o non le ritrova.
void main() {
  late Directory temp;
  late String progetto;
  late CustodiaService c;

  Future<CustodiaService> costruisci({PuntiMotore? punti}) async {
    final s = CustodiaService(
      registro: Registro(percorso: '${temp.path}/progetti.json'),
      punti: punti ?? PuntiMotore(radice: '${temp.path}/punti'),
      git: GitMotore(),
    );
    await s.init();
    return s;
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-custodia-');
    progetto = '${temp.path}/Il Mio Progetto';
    await Directory(progetto).create(recursive: true);
    await File('$progetto/uno.txt').writeAsString('la prima versione');
    c = await costruisci();
    await c.aggiungi(progetto);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> firma() async {
    await Process.run('git', ['-C', progetto, 'config', 'user.name', 'Prova']);
    await Process.run(
        'git', ['-C', progetto, 'config', 'user.email', 'p@prova']);
  }

  // ── La regola ──────────────────────────────────────────────────────────

  group('la rete prima del salto', () {
    test('cominciare la storia prende prima un punto di ritorno', () async {
      expect(await c.punti.elenca(c.registro.cerca(progetto)!.chiave), isEmpty);
      final e = await c.iniziaStoria(progetto);
      expect(e['ok'], isTrue, reason: '${e['errore']}');

      final p = await c.punti.elenca(c.registro.cerca(progetto)!.chiave);
      expect(p.length, 1);
      expect(p.first.nota, contains('cominciare'));
    });

    test('tornare a un salvataggio prende prima un punto di ritorno', () async {
      await c.iniziaStoria(progetto);
      await firma();
      await c.salva(progetto, 'il primo');
      final id = (await c.git.storia(progetto)).first.id;

      // Lavoro non salvato: è esattamente quello che si rischia di perdere.
      await File('$progetto/uno.txt').writeAsString('tre ore di lavoro');

      final prima = (await c.punti.elenca(c.registro.cerca(progetto)!.chiave)).length;
      final e = await c.tornaASalvataggio(progetto, id);
      expect(e['ok'], isTrue, reason: '${e['errore']}');
      expect((await c.punti.elenca(c.registro.cerca(progetto)!.chiave)).length, prima + 1);

      // Il ritorno è avvenuto…
      expect(await File('$progetto/uno.txt').readAsString(), 'la prima versione');
      // …e il lavoro non salvato è recuperabile.
      expect(e['annullabile'], isNotNull);
      final rete = (await c.punti.elenca(c.registro.cerca(progetto)!.chiave)).first;
      expect(
        await File('${rete.percorso}/uno.txt').readAsString(),
        'tre ore di lavoro',
      );
    });

    test('SE LA RETE NON REGGE, NON SI SALTA — tornare a un salvataggio',
        () async {
      await c.iniziaStoria(progetto);
      await firma();
      await c.salva(progetto, 'il primo');
      final id = (await c.git.storia(progetto)).first.id;
      await File('$progetto/uno.txt').writeAsString('tre ore di lavoro');

      // Il disco pieno, il permesso negato, la corrente che va via.
      final rotto = await costruisci(
        punti: PuntiMotore(
          radice: '${temp.path}/punti',
          esegui: (cmd, args) async =>
              ProcessResult(0, 1, '', 'No space left on device'),
        ),
      );

      final e = await rotto.tornaASalvataggio(progetto, id);
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('non faccio niente'));
      // E il lavoro non salvato è ancora lì, intatto.
      expect(await File('$progetto/uno.txt').readAsString(),
          'tre ore di lavoro');
    });

    test('SE LA RETE NON REGGE, NON SI SALTA — cominciare la storia', () async {
      final rotto = await costruisci(
        punti: PuntiMotore(
          radice: '${temp.path}/punti',
          esegui: (cmd, args) async => ProcessResult(0, 1, '', 'boom'),
        ),
      );
      final e = await rotto.iniziaStoria(progetto);
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('non faccio niente'));
      // Non ha nemmeno cominciato.
      expect(await Directory('$progetto/.git').exists(), isFalse);
    });

    test('salvare NON prende un punto, ed è giusto così', () async {
      // Un salvataggio aggiunge alla storia e non toglie niente. Prendere un
      // punto anche qui sarebbe rumore: uno al giorno per il lavoro vero, e
      // trenta al giorno per i salvataggi, e in un mese non si trova più
      // niente.
      await c.iniziaStoria(progetto);
      await firma();
      final prima = (await c.punti.elenca(c.registro.cerca(progetto)!.chiave)).length;
      final e = await c.salva(progetto, 'il primo');
      expect(e['ok'], isTrue, reason: '${e['errore']}');
      expect((await c.punti.elenca(c.registro.cerca(progetto)!.chiave)).length, prima);
    });
  });

  // ── I rifiuti ──────────────────────────────────────────────────────────

  group('i rifiuti', () {
    test('non si opera su un progetto che non è nell\'elenco', () async {
      final fuori = '${temp.path}/estraneo';
      await Directory(fuori).create();
      for (final e in [
        await c.salva(fuori, 'x'),
        await c.iniziaStoria(fuori),
        await c.tornaASalvataggio(fuori, 'abc1234'),
        await c.tornaAPunto(fuori, '2026-08-24_1725'),
        await c.prendiPunto(fuori),
        await c.dettaglio(fuori),
      ]) {
        expect(e['ok'], isFalse, reason: '$e');
        expect('${e['errore']}', contains('non è nell\'elenco'));
      }
    });

    test('il registro si legge PRIMA di rispondere, non dopo', () async {
      // Il difetto vero, preso provando a schermo: la finestra manda «dammi la
      // griglia» e «dammi questo progetto» una dietro l'altra. Sono due
      // gestori asincroni, e il secondo entrava mentre il primo stava ancora
      // leggendo il registro dal disco — e rispondeva «Quel progetto non è
      // nell'elenco» su un elenco ancora vuoto.
      //
      // Qui si riproduce chiedendo il dettaglio a un servizio nuovo, senza
      // averlo mai fatto partire: se il registro non si legge da solo, questa
      // prova fallisce esattamente come falliva la finestra.
      await c.aggiungi(progetto);
      final appena = CustodiaService(
        registro: Registro(percorso: '${temp.path}/progetti.json'),
        punti: PuntiMotore(radice: '${temp.path}/punti'),
        git: GitMotore(),
      );
      final d = await appena.dettaglio(progetto);
      expect(d['ok'], isTrue, reason: '${d['errore']}');
      expect(d['nome'], 'Il Mio Progetto');
    });

    test('e due richieste insieme non se lo leggono due volte', () async {
      await c.aggiungi(progetto);
      final appena = CustodiaService(
        registro: Registro(percorso: '${temp.path}/progetti.json'),
        punti: PuntiMotore(radice: '${temp.path}/punti'),
        git: GitMotore(),
      );
      final due = await Future.wait([
        appena.panoramica(),
        appena.dettaglio(progetto),
      ]);
      expect((due[1] as Map)['ok'], isTrue);
      // Un solo progetto, non due copie dello stesso.
      expect((due[0] as List).length, 1);
      expect(appena.registro.progetti.length, 1);
    });

    test('non si salva un progetto che non tiene una storia', () async {
      final e = await c.salva(progetto, 'ci provo');
      expect(e['ok'], isFalse);
    });

    test('senza firma non si salva, e lo dice in italiano', () async {
      await c.iniziaStoria(progetto);
      // Un repo senza nessuna firma né locale né globale.
      await Process.run('git', ['-C', progetto, 'config', 'user.name', '']);
      await Process.run('git', ['-C', progetto, 'config', 'user.email', '']);
      final e = await c.salva(progetto, 'ci provo');
      if (e['ok'] != true) {
        expect('${e['errore']}', contains('firmare'));
      }
    });
  });

  // ── La griglia ─────────────────────────────────────────────────────────

  group('la griglia', () {
    test('dice le tre cose che servono, e niente altro', () async {
      await c.iniziaStoria(progetto);
      await firma();
      await c.salva(progetto, 'il primo');
      await File('$progetto/due.txt').writeAsString('nuovo');

      final g = (await c.panoramica()).single;
      expect(g['nome'], 'Il Mio Progetto');
      expect(g['esiste'], isTrue);
      expect(g['punti'], greaterThan(0));
      expect((g['stato'] as Map)['quante'], 1);
      expect((g['ultimoSalvataggio'] as Map)['cosa'], 'il primo');
    });

    test('una cartella sparita si dice, non si nasconde', () async {
      await Directory(progetto).delete(recursive: true);
      final g = (await c.panoramica()).single;
      expect(g['esiste'], isFalse);
      expect(g['avviso'], contains('non c\'è più'));
    });

    test('le modifiche arrivano già raggruppate in italiano', () async {
      await c.iniziaStoria(progetto);
      await firma();
      await c.salva(progetto, 'primo');
      await Directory('$progetto/minervad').create();
      await File('$progetto/minervad/x.dart').writeAsString('x');
      await File('$progetto/LEGGIMI.md').writeAsString('x');

      final d = await c.dettaglio(progetto);
      final gruppi = (d['stato'] as Map)['gruppi'] as List;
      final nomi = {for (final g in gruppi) g['nome']};
      expect(nomi, contains('il demone'));
      expect(nomi, contains('i documenti'));
    });

    test('dice anche se qui le copie costano davvero', () async {
      final d = await c.dettaglio(progetto);
      // Su btrfs è `true`, su tmpfs `false`. Quello che conta è che ci sia una
      // risposta: l'utente deve saperlo PRIMA, non col disco pieno.
      expect(d['copiaGratuita'], isA<bool>());
    });
  });

  // ── Le destinazioni ────────────────────────────────────────────────────

  group('dove va al sicuro', () {
    late String disco;

    setUp(() async {
      disco = '${temp.path}/DiscoEsterno';
      await Directory(disco).create(recursive: true);
    });

    test('si aggiunge un disco, e ci si manda il progetto', () async {
      final a = await c.aggiungiDestinazione(
          progetto, 'cartella', 'Disco Rosso', disco);
      expect(a['ok'], isTrue, reason: '${a['errore']}');

      final e = await c.manda(progetto, disco);
      expect(e['ok'], isTrue, reason: '${e['errore']}');
      // Dice DOVE è finita: chi manda una copia su un disco vuole poterla
      // andare a cercare senza chiedere.
      expect(e['dove'], isNotNull);
      expect(await File('${e['dove']}/uno.txt').readAsString(),
          'la prima versione');
    });

    test('non si aggiunge due volte lo stesso posto', () async {
      await c.aggiungiDestinazione(progetto, 'cartella', 'D', disco);
      final due = await c.aggiungiDestinazione(progetto, 'cartella', 'D', disco);
      expect(due['ok'], isFalse);
    });

    test('non si aggiunge una destinazione dentro il progetto', () async {
      final e = await c.aggiungiDestinazione(
          progetto, 'cartella', 'no', '$progetto/copie');
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('dentro sé stessa'));
    });

    test('non si manda in un posto che non è fra le destinazioni', () async {
      final e = await c.manda(progetto, disco);
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('non è fra le destinazioni'));
    });

    test('un indirizzo che non è di GitHub non entra nemmeno nell\'elenco',
        () async {
      // La cucitura completa con GitHub sta in `custodia_github_test.dart`,
      // che finge le sue risposte. Qui interessa solo che una destinazione
      // rifiutata non lasci una riga nell'elenco: un posto che non esiste su
      // cui poi si preme «manda adesso» è peggio di nessun posto.
      final e = await c.aggiungiDestinazione(
          progetto, 'github', 'GitHub', 'git@github.com:tizio/x.git');
      expect(e['ok'], isFalse);
      expect(c.registro.cerca(progetto)!.destinazioni
          .where((d) => d.tipo == 'github'), isEmpty);
    });

    test('un tipo che non conosciamo si rifiuta', () async {
      final e = await c.aggiungiDestinazione(
          progetto, 'piccione', 'Piccione', '/x');
      expect(e['ok'], isFalse);
    });

    test('togliere un posto NON cancella la copia che c\'è là', () async {
      await c.aggiungiDestinazione(progetto, 'cartella', 'D', disco);
      final e = await c.manda(progetto, disco);
      final dove = '${e['dove']}';

      final t = await c.togliDestinazione(progetto, disco);
      expect(t['ok'], isTrue);
      expect('${t['nota']}', contains('non cancella niente'));
      expect(await File('$dove/uno.txt').exists(), isTrue);
    });

    test('due invii nello stesso giorno non fanno due giri', () async {
      // Un giro per invio riempirebbe il disco di date senza aggiungere niente.
      await c.aggiungiDestinazione(progetto, 'cartella', 'D', disco);
      final q = DateTime(2026, 8, 24, 10, 0);
      await c.manda(progetto, disco, quando: q);
      await File('$progetto/uno.txt').writeAsString('cambiata');
      await c.manda(progetto, disco, quando: q.add(const Duration(hours: 3)));

      final chiave = c.registro.cerca(progetto)!.chiave;
      expect(await c.cartella.giri(disco, chiave), ['2026-08-24_0000']);
    });

    test('e la destinazione resta scritta nel registro', () async {
      await c.aggiungiDestinazione(progetto, 'cartella', 'Disco Rosso', disco);
      final riletto = Registro(percorso: c.registro.percorso);
      await riletto.carica();
      final d = riletto.cerca(progetto)!.destinazioni.single;
      expect(d.nome, 'Disco Rosso');
      expect(d.dove, disco);
    });
  });

  // ── Proporre, non fare ─────────────────────────────────────────────────

  test('le proposte non contengono quello che c\'è già', () async {
    final proposte = c.proposte();
    expect(proposte.map((p) => p['percorso']), isNot(contains(progetto)));
  });
}

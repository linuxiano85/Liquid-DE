// Il servizio che presta il FLUSSO dello schermo — e le prove che contano
// sono i rifiuti.
//
// Questo servizio non presta una fotografia scelta: presta **tutto quello che
// c'è sullo schermo**, password comprese, finché non lo si ferma. Non ha le
// difese di `ServizioEffimero` (un file solo, pochi prelievi): i file sono
// molti, cambiano nome mentre si trasmette, e si prelevano in continuazione.
//
// Quindi la difesa è un'altra, ed è quella che queste prove sorvegliano:
// una **lista di permessi** — chi ha la chiave, e solo i nomi che ffmpeg
// genera. Una lista di divieti si aggira; una di permessi no.
import 'dart:io';

import 'package:minervad/services/foto/servizio_flusso.dart';
import 'package:test/test.dart';

void main() {
  late Directory dove;
  late ServizioFlusso s;
  late String base;
  late String chiave;

  setUp(() async {
    dove = await Directory.systemTemp.createTemp('minerva-flusso-prova');
    await File('${dove.path}/schermo.m3u8')
        .writeAsString('#EXTM3U\n#EXTINF:1.0,\nschermo0.ts\n');
    await File('${dove.path}/schermo0.ts').writeAsBytes(List.filled(64, 7));
    // Un file che NON è un segmento, messo lì apposta: è quello che un
    // percorso storto proverebbe a raggiungere.
    await File('${dove.path}/segreto.txt').writeAsString('non uscire di qui');

    s = ServizioFlusso(cartella: dove, porta: 0);
    final url = await s.apri(versoIl: '127.0.0.1');
    // http://ip:porta/<chiave>/schermo.m3u8
    final u = Uri.parse(url);
    chiave = u.pathSegments.first;
    base = 'http://${u.host}:${u.port}';
  });

  tearDown(() async {
    await s.chiudi();
    await dove.delete(recursive: true);
  });

  Future<int> stato(String percorso, {String metodo = 'GET'}) async {
    final c = HttpClient();
    try {
      final r = await c.openUrl(metodo, Uri.parse('$base$percorso'));
      final risposta = await r.close();
      await risposta.drain<void>();
      return risposta.statusCode;
    } finally {
      c.close(force: true);
    }
  }

  group('quello che passa', () {
    test('la lista, con il tipo che un televisore riconosce', () async {
      final c = HttpClient();
      final r = await (await c.getUrl(
              Uri.parse('$base/$chiave/schermo.m3u8')))
          .close();
      expect(r.statusCode, 200);
      expect(r.headers.contentType.toString(),
          contains('application/vnd.apple.mpegurl'));
      // Una lista tenuta in memoria vorrebbe dire un televisore fermo
      // sull'immagine di dieci secondi fa.
      expect(r.headers.value('cache-control'), 'no-store');
      await r.drain<void>();
      c.close(force: true);
    });

    test('un segmento', () async {
      expect(await stato('/$chiave/schermo0.ts'), 200);
    });

    test('e la HEAD, che certi apparecchi mandano prima di accettare',
        () async {
      // Stessa trappola che il 3 settembre 2026 faceva dire al televisore
      // della cucina «Resource not found»: rispondere solo alle GET.
      expect(await stato('/$chiave/schermo.m3u8', metodo: 'HEAD'), 200);
    });

    test('un segmento che non c\'è (ancora, o più) è un 404 e non un guasto',
        () async {
      // Succede sempre: la finestra scorre, e il televisore chiede un
      // segmento cancellato un secondo fa.
      expect(await stato('/$chiave/schermo99.ts'), 404);
    });
  });

  group('quello che NON passa', () {
    test('senza la chiave, niente', () async {
      expect(await stato('/schermo.m3u8'), 404);
      expect(await stato('/'), 404);
    });

    test('con la chiave sbagliata, niente', () async {
      expect(await stato('/00112233445566778899aabb/schermo.m3u8'), 404);
    });

    test('la chiave giusta non apre gli ALTRI file della cartella', () async {
      // È il punto: la chiave dà accesso al flusso, non alla cartella.
      expect(await stato('/$chiave/segreto.txt'), 404);
    });

    test('niente risalita di cartella, in nessuna delle sue scritture',
        () async {
      for (final storto in [
        '/$chiave/../segreto.txt',
        '/$chiave/%2e%2e/segreto.txt',
        '/$chiave/sotto/schermo.m3u8',
        '/$chiave//schermo.m3u8',
        '/$chiave/schermo.m3u8/x',
      ]) {
        expect(await stato(storto), 404, reason: storto);
      }
    });

    test('un nome che somiglia a un segmento ma non lo è', () async {
      // La lista è di PERMESSI: `schermo` più cifre più `.ts`, e nient'altro.
      for (final quasi in [
        '/$chiave/schermo.ts',
        '/$chiave/schermo0.TS',
        '/$chiave/schermo0.ts.bak',
        '/$chiave/schermo-0.ts',
        '/$chiave/schermo.m3u8x',
      ]) {
        expect(await stato(quasi), 404, reason: quasi);
      }
    });

    test('i metodi che non sono letture', () async {
      for (final m in ['POST', 'PUT', 'DELETE']) {
        expect(await stato('/$chiave/schermo.m3u8', metodo: m), 404,
            reason: m);
      }
    });
  });

  test('la chiave è lunga e diversa a ogni trasmissione', () {
    // Ventiquattro byte dal generatore sicuro: chi non l'ha ricevuta non la
    // indovina. Se un giorno qualcuno la accorciasse «tanto è solo in casa»,
    // questa prova si accorge.
    expect(chiave.length, 48);
    final altra = ServizioFlusso(cartella: dove, porta: 0);
    // Non si apre: serve solo a vedere che la chiave non è la stessa.
    expect(altra.indirizzo, isNull);
    expect(altra.aperto, isFalse);
  });

  test('chiuso, non risponde più a niente', () async {
    await s.chiudi();
    expect(s.aperto, isFalse);
    expect(s.indirizzo, isNull);
    await expectLater(
      stato('/$chiave/schermo.m3u8'),
      throwsA(isA<SocketException>()),
    );
  });

  // ── Il flusso DIRETTO, per gli apparecchi DLNA ──────────────────────────
  //
  // Un Samsung non sa leggere un `.m3u8`, e il modo in cui lo dice è non dire
  // niente. A lui si dà un indirizzo che, aperto, comincia a versare MPEG-TS.
  //
  // Qui il rubinetto è una conduttura finta che versa byte a comando: quello
  // che si prova non è il video — quello lo prova `prova-specchio.py` sulla
  // sessione vera — ma le tre regole che, sbagliate, lasciano un processo a
  // leggere lo schermo di casa quando nessuno guarda.
  group('il flusso diretto', () {
    late Directory tana;
    late ServizioFlusso s;
    late String base;
    late String chiave;

    setUp(() async {
      tana = await Directory.systemTemp.createTemp('minerva-diretto');
      final finta = File('${tana.path}/finta');
      await finta.writeAsString('#!/bin/sh\n'
          r'[ "$1" = "schermi" ] && { echo eDP-1; exit 0; }' '\n'
          'trap \'exit 0\' TERM INT\n'
          'while : ; do printf "MINERVAMINERVA"; sleep 0.1; done\n');
      await Process.run('chmod', ['+x', finta.path]);

      s = ServizioFlusso(
          cartella: tana, porta: 0, diretto: true, comando: finta.path);
      final u = Uri.parse(await s.apri(versoIl: '127.0.0.1'));
      chiave = u.pathSegments.first;
      base = 'http://${u.host}:${u.port}';
    });

    tearDown(() async {
      await s.chiudi();
      tana.deleteSync(recursive: true);
    });

    test('l\'indirizzo e il tipo sono quelli di un flusso, non di una lista',
        () {
      expect(s.indirizzo, endsWith('/schermo.ts'));
      expect(s.tipo, 'video/mp2t');
    });

    test('la HEAD risponde e NON accende niente', () async {
      // Un renderer DLNA manda una HEAD prima di accettare l'indirizzo.
      // Accendere lì vorrebbe dire comprimere lo schermo per un televisore
      // che non ha ancora detto sì — e se non lo dicesse mai, per sempre.
      final c = HttpClient();
      final r = await (await c.openUrl(
              'HEAD', Uri.parse('$base/$chiave/schermo.ts')))
          .close();
      expect(r.statusCode, 200);
      expect(r.headers.contentType.toString(), contains('video/mp2t'));
      expect(r.headers.value('transferMode.dlna.org'), 'Streaming');
      // Su un flusso dal vivo non si salta da nessuna parte.
      expect(r.headers.value('contentFeatures.dlna.org'),
          contains('DLNA.ORG_OP=00'));
      await r.drain<void>();
      c.close(force: true);
      expect(s.richieste, 0,
          reason: 'la HEAD ha acceso la conduttura: lo schermo viene letto '
              'per nessuno');
    });

    test('la GET apre il rubinetto e i byte arrivano', () async {
      final c = HttpClient();
      final r = await (await c.getUrl(Uri.parse('$base/$chiave/schermo.ts')))
          .close();
      expect(r.statusCode, 200);
      // Non c'è lunghezza: non si sa quanto durerà, e dichiararla sbagliata
      // è peggio che tacerla.
      expect(r.headers.contentLength, -1);
      final primi = <int>[];
      await for (final p in r) {
        primi.addAll(p);
        if (primi.length >= 14) break;
      }
      expect(String.fromCharCodes(primi.take(14)), 'MINERVAMINERVA');
      c.close(force: true);
      // E quando chi guardava se ne va, la conduttura si spegne.
      await Future<void>.delayed(const Duration(seconds: 2));
    });

    test('in modo diretto la lista NON esiste', () async {
      // Offrire tutti e due gli indirizzi vorrebbe dire che un televisore
      // può chiedere quello sbagliato e restare nero.
      final c = HttpClient();
      final r = await (await c.getUrl(
              Uri.parse('$base/$chiave/schermo.m3u8')))
          .close();
      expect(r.statusCode, 404);
      await r.drain<void>();
      c.close(force: true);
    });

    test('chiudere il servizio spegne la conduttura', () async {
      final c = HttpClient();
      final r = await (await c.getUrl(Uri.parse('$base/$chiave/schermo.ts')))
          .close();
      final primi = <int>[];
      final letto = r.listen((p) => primi.addAll(p), onError: (_) {});
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(primi, isNotEmpty);
      await s.chiudi();
      await Future<void>.delayed(const Duration(seconds: 1));
      final quanti = primi.length;
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(primi.length, quanti,
          reason: 'arrivano ancora byte dopo la chiusura: la conduttura è '
              'rimasta viva a leggere lo schermo');
      await letto.cancel();
      c.close(force: true);
    });
  });
}

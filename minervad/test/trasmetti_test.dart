// Mandare un file a un televisore.
//
// ── La regola che viene prima di tutte ─────────────────────────────────────
//
// Giacomo, 2 settembre 2026: «se devi fare prove sulla funzione trasmetti
// falle verso cucina perché i bimbi dormono».
//
// Gli altri apparecchi che la scoperta trova stanno in stanze dove dorme
// qualcuno, e accenderne uno per una prova vuol dire svegliare dei bambini di
// notte. Quindi il nome sta **dentro la prova**, e se «Cucina» non c'è la
// prova **si salta**. Nessun ripiego sul primo trovato: un ripiego automatico
// è esattamente il modo in cui questa regola verrebbe violata senza che
// nessuno se ne accorga. Stessa famiglia di «non si sospende dentro una
// prova».
//
// ── E quasi tutto si prova SENZA toccare la rete ───────────────────────────
//
// Il giro vero vuole un televisore acceso. Tutto il resto — i rifiuti, l'
// ordine in cui si aprono le cose, e soprattutto che si RICHIUDA tutto quando
// qualcosa va storto — si prova con un televisore che non esiste. Sono i
// rifiuti che contano: un servizio HTTP con dentro una fotografia di casa,
// rimasto aperto perché un errore ha saltato la riga che lo spegneva, è il
// difetto peggiore che questo codice possa avere.
import 'dart:io';

import 'package:minervad/services/schermi_esterni.dart';
import 'package:minervad/services/trasmetti_service.dart';
import 'package:test/test.dart';

/// Il solo televisore verso cui è lecito trasmettere in una prova.
const nomeAmmesso = 'Cucina';

void main() {
  late Directory tana;
  late File foto;

  setUp(() {
    tana = Directory.systemTemp.createTempSync('minerva-cast-');
    foto = File('${tana.path}/prova.jpg')
      ..writeAsBytesSync(List<int>.filled(64, 0));
  });
  tearDown(() => tana.deleteSync(recursive: true));

  SchermoEsterno finto({
    String nome = 'Finto',
    String indirizzo = '192.0.2.1', // TEST-NET-1: non esiste per definizione
    String modo = 'cast',
  }) =>
      SchermoEsterno(
        nome: nome,
        indirizzo: indirizzo,
        porta: 8009,
        modo: modo,
        modello: '',
        id: 'finto-$nome',
      );

  group('i rifiuti, che sono la parte che conta', () {
    test('un file che non c\'è non apre niente', () async {
      final t = TrasmettiService();
      final r = await t.manda(
          file: File('${tana.path}/non-esiste.jpg'), verso: finto());
      expect(r['ok'], isFalse);
      expect('${r['error']}', contains('non c\'è'));
      expect(t.inCorso, isFalse);
    });

    test('un apparecchio che parla una lingua che non sappiamo riceve un no '
        'che spiega, non un guasto', () async {
      final t = TrasmettiService();
      final r = await t.manda(file: foto, verso: finto(modo: 'miracast'));
      expect(r['ok'], isFalse);
      expect('${r['error']}', contains('miracast'));
      // La differenza fra «non so» e «è rotto» è tutta qui: chi legge deve
      // capire che non c'è niente da riparare.
      expect('${r['error']}', contains('non c\'è ancora'));
      expect(t.inCorso, isFalse);
    });

    test('un televisore irraggiungibile non lascia niente aperto', () async {
      // ── È LA prova di questo file ──────────────────────────────────────
      //
      // L'indirizzo è in TEST-NET-1 (192.0.2.0/24), che per definizione non
      // risponde: il collegamento fallisce a metà, dopo che il servizio HTTP
      // è già stato aperto. Se `manda()` non disfacesse tutto nel `catch`,
      // resterebbe su un servizio che pubblica una fotografia sulla rete di
      // casa — e nessuno se ne accorgerebbe, perché la funzione ha già
      // risposto «non è andata».
      final t = TrasmettiService();
      final r = await t.manda(file: foto, verso: finto());
      expect(r['ok'], isFalse);
      expect(t.inCorso, isFalse);
      expect(t.versoChi, isEmpty);
      expect(t.fileCorrente, isEmpty);

      // E la porta non deve essere rimasta in ascolto.
      await _portaLibera('il servizio effimero è rimasto aperto dopo un errore');
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('l\'errore di rete diventa una frase che dice cosa fare', () async {
      final t = TrasmettiService();
      final r = await t.manda(file: foto, verso: finto(nome: 'Salotto'));
      // Non «SocketException: Connection refused»: quello non dice a nessuno
      // che il televisore si è spento.
      expect('${r['error']}', contains('Salotto'));
      expect('${r['error']}', isNot(contains('SocketException')));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('fermare quando non sta trasmettendo non fa danni', () async {
      final t = TrasmettiService();
      await t.ferma();
      await t.ferma();
      expect(t.inCorso, isFalse);
      expect(t.stato['inCorso'], isFalse);
    });
  });

  // ── Trasmettere lo SCHERMO ────────────────────────────────────────────
  //
  // Qui la posta è più alta che con una fotografia: quello che va in onda è
  // **tutto quello che c'è sullo schermo**, password comprese, e la
  // conduttura scrive i fotogrammi su disco (in RAM) finché gira. Le prove
  // che contano non sono «parte»: sono «quando NON parte, non resta niente».
  //
  // Serve una conduttura finta perché una macchina senza schermo non ne ha
  // una vera, ed è il motivo per cui `comandoSpecchio` si può sostituire.
  group('lo schermo, e cosa resta quando va storto', () {
    /// Scrive uno script che si comporta come `minerva-specchio`.
    /// `riesce` falso = muore subito, come quando manca ffmpeg.
    Future<String> conduttaFinta({required bool riesce}) async {
      final f = File('${tana.path}/finta-conduttura');
      await f.writeAsString(riesce
          ? '#!/bin/sh\n'
              'D="\$2"\n'
              'mkdir -p "\$D"\n'
              'printf "#EXTM3U\\n#EXTINF:1.0,\\nschermo0.ts\\n'
              '#EXTINF:1.0,\\nschermo1.ts\\n" > "\$D/schermo.m3u8"\n'
              ': > "\$D/schermo0.ts"\n'
              ': > "\$D/schermo1.ts"\n'
              'trap \'rm -rf "\$D"; exit 0\' TERM INT\n'
              'while : ; do sleep 1; done\n'
          : '#!/bin/sh\n'
              'echo "manca ffmpeg, e senza non si comprime video" >&2\n'
              'exit 1\n');
      await Process.run('chmod', ['+x', f.path]);
      return f.path;
    }

    test('se la conduttura non parte, si dice PERCHÉ', () async {
      final t = TrasmettiService(
          comandoSpecchio: await conduttaFinta(riesce: false));
      final r = await t.specchia(verso: finto());
      expect(r['ok'], isFalse);
      // Non «non è andata» e basta: la lamentela della conduttura è l'unica
      // cosa che dice a chi guarda che cosa manca.
      expect('${r['error']}', contains('ffmpeg'));
      expect(t.inCorso, isFalse);
      expect(t.specchio, isFalse);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('un televisore irraggiungibile non lascia la conduttura viva',
        () async {
      // ── È LA prova di questo gruppo ─────────────────────────────────
      //
      // La conduttura parte davvero (scrive la lista, resta viva), poi il
      // televisore in TEST-NET-1 non risponde. Se `specchia()` non disfacesse
      // tutto nel `catch`, resterebbe in piedi un processo che legge lo
      // schermo per sempre — con la spia nel pannello che dice «spento».
      final t = TrasmettiService(
          comandoSpecchio: await conduttaFinta(riesce: true));
      final r = await t.specchia(verso: finto());
      expect(r['ok'], isFalse);
      expect(t.inCorso, isFalse);
      expect(t.specchio, isFalse);
      expect(t.stato['specchio'], isFalse);

      // La cartella dei segmenti — cioè i fotogrammi dello schermo — non
      // deve essere rimasta.
      final corsa = Platform.environment['XDG_RUNTIME_DIR'] ?? '/tmp';
      final dove = Directory('$corsa/minerva-specchio');
      expect(dove.existsSync(), isFalse,
          reason: 'sono rimasti dei fotogrammi dello schermo in ${dove.path}');

      // E la porta non deve essere rimasta in ascolto.
      await _portaLibera('il servizio del flusso è rimasto aperto dopo un '
          'errore');
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('un apparecchio che non parla né Chromecast né DLNA riceve un no',
        () async {
      final t = TrasmettiService(
          comandoSpecchio: await conduttaFinta(riesce: true));
      final r = await t.specchia(verso: finto(modo: 'airplay'));
      expect(r['ok'], isFalse);
      // E la conduttura non deve nemmeno essere partita: si controlla prima.
      expect(t.inCorso, isFalse);
    });
  });

  group('il permesso del firewall', () {
    test('si apre PRIMA e si richiude anche quando fallisce', () async {
      // L'ordine non è pignoleria: aprendolo dopo, il televisore avrebbe già
      // provato a scaricare e sarebbe stato respinto — e quel no non torna
      // indietro a nessuno. Resta uno schermo nero senza errori.
      final fatti = <String>[];
      final t = TrasmettiService(
        permesso: (op, args) async {
          fatti.add(op);
          return {'ok': true};
        },
      );
      await t.manda(file: foto, verso: finto());
      // «apri» per PRIMO, e non preceduto da un «chiudi» inutile: `manda()`
      // comincia con un `ferma()` (una trasmissione per volta), e prima del
      // 3 settembre 2026 quel `ferma()` chiudeva il firewall anche quando non
      // era mai stato aperto — cioè una finestra della password in più a ogni
      // trasmissione, per non fare niente.
      expect(fatti.first, 'trasmetti-apri',
          reason: 'prima di «apri» è stato chiamato $fatti');
      expect(fatti, contains('trasmetti-chiudi'));
      expect(fatti.where((f) => f == 'trasmetti-apri').length, 1);
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('il giro vero, e solo verso «$nomeAmmesso»', () {
    test('manda una fotografia e la ferma', () async {
      final t = TrasmettiService();
      final trovati = await t.cerca();
      SchermoEsterno? cucina;
      for (final s in trovati) {
        if (s.nome == nomeAmmesso && (s.modo == 'cast' || s.modo == 'dlna')) {
          cucina = s;
        }
      }
      if (cucina == null) {
        // NON si ripiega sul primo trovato: gli altri televisori di questa
        // casa stanno in camere dove dorme qualcuno.
        final quali = [for (final s in trovati) '${s.nome} (${s.modo})'];
        markTestSkipped('«$nomeAmmesso» non è in rete. Trovati: $quali');
        return;
      }

      // ── E qui ci si ferma, di proposito ────────────────────────────────
      //
      // Mandare per davvero vuole la porta 8010 aperta nel firewall, e quella
      // la apre `minerva-radice trasmetti-apri` — cioè `pkexec`, cioè una
      // finestra della password sullo schermo di chi lancia le prove. Una
      // suite che fa comparire una richiesta di password è una suite che non
      // si lancia più.
      //
      // Il giro completo è stato fatto **a mano il 3 settembre 2026** verso
      // «Cucina» (Samsung UE55BU8070UXZT, DLNA/AVTransport) e la fotografia è
      // comparsa sullo schermo. Quello che si può provare senza password è
      // provato: i rifiuti qui sopra, e il pezzo che quel giorno era rotto
      // davvero — la HEAD — sta in `servizio_effimero_test.dart`.
      expect(cucina.modo, anyOf('dlna', 'cast'),
          reason: 'Minerva non saprebbe parlargli');
      expect(cucina.id, isNotEmpty,
          reason: 'senza un ID stabile, «manda a Cucina» domani manda altrove');
      markTestSkipped('trovato «$nomeAmmesso» (${cucina.modo}); il giro '
          'completo vuole la password del firewall e si fa a mano');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

/// La porta 8010 non deve essere rimasta in ascolto dopo un errore.
///
/// ── Perché non è un `expect` secco ────────────────────────────────────────
///
/// Perché questa prova gira sulla macchina di chi la lancia, e su quella
/// macchina Minerva **sta girando davvero**. Se in quel momento c'è una
/// trasmissione vera in corso — una foto sul televisore della cucina — la
/// porta è occupata dal demone vivo, e la prova diventava rossa dicendo «il
/// servizio è rimasto aperto dopo un errore»: una frase falsa che manda a
/// cercare un difetto che non c'è. Successo due volte il 4 settembre 2026.
///
/// Quello che questa prova può dire è: **il servizio che ho appena fatto
/// fallire non è rimasto aperto**. Se la porta è di qualcun altro, lo dice e
/// si salta — che è la verità, invece di un rosso che mente.
Future<void> _portaLibera(String perche) async {
  final s = await ServerSocket.bind(InternetAddress.anyIPv4, 8010,
          shared: false)
      .then<ServerSocket?>((x) => x)
      .catchError((_) => null);
  if (s != null) {
    await s.close();
    return;
  }
  final chi = await Process.run('sh', [
    '-c',
    "ss -tlnp 2>/dev/null | grep ':8010 ' | head -1",
  ]).then((r) => (r.stdout as String).trim()).catchError((_) => '');
  if (chi.contains('minervad')) {
    markTestSkipped('la porta 8010 è del demone vivo — c\'è una trasmissione '
        'vera in corso su questa macchina. Non si può distinguere da un '
        'servizio rimasto aperto: si salta invece di dire una cosa falsa.');
    return;
  }
  fail('la porta 8010 è ancora occupata: $perche (in ascolto: '
      '${chi.isEmpty ? "sconosciuto" : chi})');
}

import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/ipc/websocket_server.dart';

// Il demone non muore perché una finestra se n'è andata.
//
// ── Il guasto vero, del 31 agosto 2026 ───────────────────────────────────
//
// Giacomo: «attualmente sia qui che nella sessione wlroot non ho la dock e
// nemmeno le voci nel menu delle applicazioni. son quasi inutilizzabili.»
//
// La catena era questa, e comincia proprio qui:
//
//   1. una finestra si chiude mentre il demone le sta scrivendo addosso —
//      capita a ogni finestra chiusa, e il flusso `windows_state` arriva fino
//      a sedici volte al secondo, quindi capita spesso;
//   2. `send()` finisce in EPIPE, e l'errore NON arriva al `try/catch` che gli
//      sta intorno: Dart lo consegna alla ZONA (nella traccia si vede
//      `_RootZone.runUnaryGuarded` fra `_IOSinkImpl.write` e l'errore);
//   3. nessuno lo raccoglie → «Unhandled exception» → il demone esce con 255;
//   4. il guardiano lo rimette in piedi, ma la shell non lo ritrova più;
//   5. senza demone `Core.Apps.all` resta vuoto, e la dock ha scritto
//      `visible: dock.items.length > 0`: sparisce. Il menù pure.
//
// Era successo nelle sessioni 2, 5, 7 e 9: sotto Hyprland **e** sotto
// minerva-wayland. Ecco perché mancava «sia qui che nella sessione wlroot».
//
// ── Perché questa prova è fatta così ─────────────────────────────────────
//
// Il `WebSocketServer` intero vuole undici servizi, e montarli tutti per
// provare una scrittura sarebbe una prova che nessuno riesce a leggere.
// `WebSocketClientConnection` invece vuole un socket e basta — ed è la classe
// dov'è il difetto e dove sta la riparazione.
//
// **E questa prova non ha bisogno di `expect` per fallire.** Se il difetto
// c'è, l'errore non raccolto uccide l'isolato: `dart test` lo segna rosso da
// sé. Le asserzioni sotto servono a dire cosa DEVE succedere invece.
void main() {
  group('una finestra che se ne va non porta giù il demone', () {
    late Directory tmp;
    late String percorso;
    late ServerSocket server;
    late Stream<Socket> arrivi;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('minerva-canale-');
      percorso = '${tmp.path}/prova.sock';
      server = await ServerSocket.bind(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);
      // `broadcast` e non `server.first`: `first` cancella la sottoscrizione, e
      // cancellare la sottoscrizione di un `ServerSocket` lo CHIUDE — col file
      // del socket che sparisce da sotto. Il secondo client trovava «No such
      // file or directory» e sembrava un difetto del prodotto: era mio.
      arrivi = server.asBroadcastStream();
    });

    tearDown(() async {
      await server.close();
      tmp.deleteSync(recursive: true);
    });

    test('scrivere a chi ha chiuso di colpo non uccide il processo', () async {
      final accettato = arrivi.first;
      final client = await Socket.connect(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);
      final connessione = WebSocketClientConnection(await accettato)
        ..autenticato = true;

      // `destroy` e non `close`: è la finestra uccisa con `kill -9`, o
      // sparita col compositore. È il caso vero, ed è il caso peggiore —
      // `close` almeno saluta.
      client.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Una raffica, perché il primo `write` entra ancora nel buffer del
      // kernel e non fallisce: EPIPE arriva quando il buffer è pieno. È
      // esattamente quello che fa `windows_state` mentre una finestra si
      // muove.
      final grosso = {'roba': List<String>.generate(200, (i) => 'x' * 200)};
      for (var i = 0; i < 400; i++) {
        connessione.send({'event': 'windows_state', 'payload': grosso});
      }

      // L'errore arriva dopo, in modo asincrono: è il punto di tutta la
      // faccenda. Senza questa attesa la prova finirebbe prima del guasto e
      // sarebbe verde col difetto dentro.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Arrivare vivi fin qui È l'asserzione principale.
      expect(true, isTrue,
          reason: 'se il processo è ancora qui, la zona non è stata avvelenata');

      // E la connessione deve essersi accorta di essere morta, invece di
      // continuare a scrivere in un tubo rotto per il resto della sessione.
      expect(connessione.vivo, isFalse,
          reason: 'una connessione che non riceve più va marcata, non contata');
    });

    test('e il demone continua ad accettarne di nuove', () async {
      final accettato = arrivi.first;
      final primo = await Socket.connect(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);
      final connessione = WebSocketClientConnection(await accettato)
        ..autenticato = true;

      primo.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final grosso = {'roba': List<String>.generate(200, (i) => 'x' * 200)};
      for (var i = 0; i < 400; i++) {
        connessione.send({'event': 'windows_state', 'payload': grosso});
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // La parte che conta per chi guarda lo schermo: dopo il guasto, la
      // shell che si riavvia deve poter rientrare.
      final secondo = await Socket.connect(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);
      expect(secondo.remoteAddress.address, isNotNull);
      secondo.destroy();
    });
  });

  // ── E la shell deve DIRE quando si stacca ──────────────────────────────
  //
  // Il demone che riparte è la metà della storia; l'altra metà è la shell che
  // se ne accorge, si riaggancia, e lo scrive.
  //
  // Il 5 settembre 2026, sul registro della sessione viva: «Connesso al
  // demone» **nove volte**, «Connessione persa» **zero**. La shell si era
  // riagganciata nove volte senza mai dire di essersi staccata. La colpa era
  // la condizione: l'annuncio stava dentro `if (!reconnectTimer.running)`, e
  // quando il demone riparte quel timer sta già girando quasi sempre — lo
  // avvia `_rinnova()`, o la sveglia della scadenza.
  //
  // Non è rumore che manca: è l'unica riga che dice QUANDO è successo, ed è
  // esattamente l'evento che il 2 settembre ha lasciato dock e menù vuoti in
  // tutte e due le sessioni.
  group('il distacco finisce nel registro', () {
    late String ipc;

    setUpAll(() {
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4 && f == null; i++) {
        final c = File('${dir.path}/minerva-shell/core/Ipc.qml');
        if (c.existsSync()) f = c;
        dir = dir.parent;
      }
      if (f == null) fail('non trovo minerva-shell/core/Ipc.qml');
      ipc = f
          .readAsLinesSync()
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('l\'annuncio non dipende dal timer che sta girando', () {
      final i = ipc.indexOf('Connessione persa');
      expect(i, greaterThan(0), reason: 'la riga deve esistere');
      // Si guarda il pezzo di codice PRIMA dell'annuncio: se lì dentro si
      // apre `if (!reconnectTimer.running)`, l'annuncio è di nuovo appeso al
      // timer e torna a non uscire mai.
      final prima = ipc.substring((i - 700).clamp(0, i), i);
      final apre = prima.lastIndexOf('if (!reconnectTimer.running)');
      final chiude = prima.lastIndexOf('reconnectTimer.start();');
      expect(apre < chiude || apre == -1, isTrue,
          reason: 'l\'annuncio del distacco è finito dentro '
              '`if (!reconnectTimer.running)`: quando il demone riparte quel '
              'timer sta già girando, e il distacco torna invisibile');
    });

    test('e si dice una volta per distacco, non una per tentativo', () {
      expect(ipc, contains('_perditaDetta'),
          reason: 'senza la guardia, ogni tentativo di riconnessione '
              'scriverebbe la sua riga: la ripetizione si toglie, '
              'l\'informazione mai');
      final i = ipc.indexOf('Connesso al demone');
      expect(ipc.substring((i - 400).clamp(0, i), i),
          contains('_perditaDetta = false'),
          reason: 'il prossimo distacco è un altro distacco: l\'annuncio va '
              'riarmato quando il saluto viene accettato');
    });
  });
}

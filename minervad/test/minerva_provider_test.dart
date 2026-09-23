import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/providers/compositor_provider.dart';
import 'package:minervad/providers/minerva/minerva_provider.dart';

/// Un finto minerva-wayland: un socket Unix che parla il protocollo a righe.
///
/// Serve perché il pezzo che vale la pena provare — «cosa fa il demone quando
/// il compositore dice X» — non ha bisogno di uno schermo, e una prova che ha
/// bisogno di uno schermo non gira mai.
class FintoCompositore {
  late final ServerSocket _server;
  late final String percorso;
  final List<String> ricevuti = [];
  final List<Socket> _collegati = [];

  /// Cosa rispondere, per comando.
  Map<String, String> risposte = {};

  Future<void> apri(String dove) async {
    percorso = dove;
    final f = File(percorso);
    if (f.existsSync()) f.deleteSync();
    _server = await ServerSocket.bind(
        InternetAddress(percorso, type: InternetAddressType.unix), 0);
    _server.listen((s) {
      _collegati.add(s);
      s
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((riga) {
        ricevuti.add(riga);
        if (riga == 'ascolta') {
          s.add(utf8.encode('ok ascolto\n'));
          return;
        }
        final r = risposte[riga];
        s.add(utf8.encode('${r ?? 'no verbo sconosciuto'}\n'));
      }, onError: (_) {});
    });
  }

  void annuncia(String riga) {
    for (final s in _collegati) {
      s.add(utf8.encode('$riga\n'));
    }
  }

  Future<void> chiudi() async {
    for (final s in _collegati) {
      s.destroy();
    }
    await _server.close();
    final f = File(percorso);
    if (f.existsSync()) f.deleteSync();
  }
}

void main() {
  group('daRiga — dalla riga del canale all\'evento', () {
    test('una finestra che si apre', () {
      final e = MinervaProvider.daRiga(
          'evento aperta {"id":"0x55f1c0","pid":4211,"titolo":"Konsole"}');
      expect(e, isNotNull);
      expect(e!.type, CompositorEventType.windowOpened);
      expect(e.payload['id'], '0x55f1c0');
      expect(e.payload['pid'], 4211);
    });

    test('una che si chiude', () {
      final e = MinervaProvider.daRiga('evento chiusa {"id":"0x1"}');
      expect(e!.type, CompositorEventType.windowClosed);
    });

    test('il fuoco', () {
      final e = MinervaProvider.daRiga('evento fuoco {"id":"0x1"}');
      expect(e!.type, CompositorEventType.windowFocused);
    });

    test('il titolo', () {
      final e = MinervaProvider.daRiga('evento titolo {"id":"0x1"}');
      expect(e!.type, CompositorEventType.windowTitleChanged);
    });

    test('lo spostamento', () {
      final e = MinervaProvider.daRiga('evento mossa {"id":"0x1"}');
      expect(e!.type, CompositorEventType.windowMoved);
    });

    test('lo stato (ingrandita, ridotta, schermo intero)', () {
      final e = MinervaProvider.daRiga(
          'evento stato {"id":"0x1","ridotta":true}');
      expect(e!.type, CompositorEventType.fullscreenChanged);
      expect(e.payload['ridotta'], true);
    });

    test('gli schermi', () {
      final e = MinervaProvider.daRiga('evento schermi {}');
      expect(e!.type, CompositorEventType.monitorChanged);
    });

    // ── Il difetto che questo formato esiste per non rifare ──────────────
    //
    // Con Hyprland il carico è separato da virgole, e un titolo di finestra le
    // virgole ce le ha quasi sempre: `activewindow >> CLASSE,TITOLO` letto
    // come due campi si spezza al primo titolo che contiene una virgola. Qui
    // il titolo è dentro una stringa JSON e non spezza niente.
    test('un titolo con virgole e virgolette non spezza niente', () {
      final e = MinervaProvider.daRiga(
          r'evento titolo {"id":"0x1","titolo":"a, b, \"c\" — d"}');
      expect(e, isNotNull);
      expect(e!.payload['titolo'], 'a, b, "c" — d');
    });

    test('una riga che non è un evento si butta', () {
      expect(MinervaProvider.daRiga('ok [{"id":"0x1"}]'), isNull);
      expect(MinervaProvider.daRiga('no nessuna finestra'), isNull);
      expect(MinervaProvider.daRiga(''), isNull);
      expect(MinervaProvider.daRiga('evento'), isNull);
      expect(MinervaProvider.daRiga('evento aperta'), isNull);
    });

    test('un evento che non conosciamo si butta, senza rumore', () {
      expect(MinervaProvider.daRiga('evento pippo {}'), isNull);
    });

    test('un carico che non è JSON si butta invece di far cadere il demone',
        () {
      expect(MinervaProvider.daRiga('evento aperta non-json'), isNull);
    });
  });

  group('caricoOk — separare la risposta buona dalla cattiva', () {
    test('ok con carico', () {
      expect(MinervaProvider.caricoOk('ok [1,2]'), '[1,2]');
    });
    test('ok nudo', () {
      expect(MinervaProvider.caricoOk('ok'), '');
    });
    test('un «no» non diventa un elenco vuoto per sbaglio', () {
      expect(MinervaProvider.caricoOk('no nessuna finestra'), '');
    });
  });

  // ── Il difetto costato una scrivania senza finestre ────────────────────
  //
  // Un socket Unix è un file, e resta sul disco quando il programma muore
  // male. Il 24 agosto 2026, finita una prova annidata, il demone della
  // sessione VERA ha visto quel file, ha concluso «gira minerva-wayland», e ha
  // chiesto le finestre a un compositore morto. Hyprland aveva un terminale
  // aperto; la shell diceva `finestre=0`; nessun errore da nessuna parte.
  group('inAscolto — il file c\'è, ma risponde qualcuno?', () {
    // Due righe vere di `/proc/net/unix`, copiate come sono. Il percorso è
    // l'ultimo campo, e le righe senza percorso (i socket anonimi) sono la
    // maggioranza del file.
    const proc = '''Num       RefCount Protocol Flags    Type St Inode Path
0000000000000000: 00000002 00000000 00010000 0001 01 12345 /run/user/1000/minerva-wayland-minerva-0.sock
0000000000000000: 00000003 00000000 00000000 0001 03 12346 /run/user/1000/bus
0000000000000000: 00000002 00000000 00010000 0001 01 12347
''';

    test('un socket con qualcuno in ascolto', () {
      expect(
          MinervaProvider.inAscolto(
              '/run/user/1000/minerva-wayland-minerva-0.sock',
              proc: proc),
          isTrue);
    });

    test('un file avanzato da un compositore morto NON conta', () {
      expect(
          MinervaProvider.inAscolto(
              '/run/user/1000/minerva-wayland-minerva-1.sock',
              proc: proc),
          isFalse);
    });

    // Il confronto è sull'ULTIMO CAMPO INTERO e non un `contains`: cercando
    // per contenuto, un percorso che è il prefisso di un altro risulterebbe
    // vivo. È lo stesso genere di svista per cui `pgrep` trova sé stesso.
    test('e non basta essere un pezzo di un percorso vivo', () {
      expect(
          MinervaProvider.inAscolto('/run/user/1000/minerva-wayland-minerva-0',
              proc: proc),
          isFalse);
      expect(MinervaProvider.inAscolto('minerva-0.sock', proc: proc), isFalse);
    });

    test('un percorso vuoto non è mai vivo', () {
      expect(MinervaProvider.inAscolto('', proc: proc), isFalse);
    });

    test('le righe senza percorso non fanno cadere la lettura', () {
      expect(MinervaProvider.inAscolto('/run/user/1000/bus', proc: proc),
          isTrue);
    });
  });

  group('trovaCanale', () {
    test('senza niente nell\'ambiente non inventa un percorso', () {
      // Non si può cambiare l'ambiente del processo di prova, quindi si
      // verifica la sola cosa che conta e che è sempre vera: o torna vuoto, o
      // torna un percorso assoluto che finisce in `.sock`. Mai una via di
      // mezzo, mai un percorso relativo.
      final c = MinervaProvider.trovaCanale();
      expect(c.isEmpty || (c.startsWith('/') && c.endsWith('.sock')), isTrue);
    });
  });

  group('col compositore finto in ascolto', () {
    late FintoCompositore finto;
    late MinervaProvider p;
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('minerva-prova-');
      finto = FintoCompositore();
      await finto.apri('${tmp.path}/c.sock');
      p = MinervaProvider(canale: finto.percorso);
    });

    tearDown(() async {
      await p.stop();
      await finto.chiudi();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('l\'elenco delle finestre arriva come l\'ha scritto il compositore',
        () async {
      finto.risposte['finestre'] = 'ok [{"id":"0x1","titolo":"Konsole"}]';
      final r = await p.getClientsRaw();
      expect(r, '[{"id":"0x1","titolo":"Konsole"}]');
    });

    test('e non viene tradotto in lingua Hyprland per strada', () async {
      finto.risposte['finestre'] =
          'ok [{"id":"0x1","ridotta":true,"schermoIntero":false}]';
      final r = await p.getClientsRaw();
      expect(r.contains('ridotta'), isTrue);
      expect(r.contains('workspace'), isFalse);
      expect(r.contains('focusHistoryID'), isFalse);
    });

    test('una risposta che non è JSON diventa un elenco vuoto', () async {
      finto.risposte['finestre'] = 'ok bah';
      expect(await p.getClientsRaw(), '[]');
    });

    test('un «no» diventa un elenco vuoto e non fa cadere niente', () async {
      finto.risposte['finestre'] = 'no non lo so';
      expect(await p.getClientsRaw(), '[]');
    });

    test('gli schermi', () async {
      finto.risposte['schermi'] = 'ok [{"nome":"WL-1","scala":1.25}]';
      expect(await p.getMonitorsRaw(), '[{"nome":"WL-1","scala":1.25}]');
    });

    test('start() si iscrive dicendo «ascolta»', () async {
      await p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(finto.ricevuti, contains('ascolta'));
    });

    test('un annuncio del compositore diventa un evento del demone', () async {
      await p.start();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final visto = <CompositorEvent>[];
      final sub = p.events.listen(visto.add);

      finto.annuncia('evento aperta {"id":"0x7","titolo":"Konsole"}');
      finto.annuncia('evento fuoco {"id":"0x7"}');
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await sub.cancel();

      expect(visto.map((e) => e.type).toList(), [
        CompositorEventType.windowOpened,
        CompositorEventType.windowFocused,
      ]);
      expect(visto.first.payload['id'], '0x7');
    });

    test('le scrivanie sono quelle che dice il compositore', () async {
      finto.risposte['scrivanie'] = 'ok [{"id":1,"nome":"1","finestre":2,'
          '"attiva":false},{"id":3,"nome":"3","finestre":1,"attiva":true}]';
      final w = await p.getWorkspaces();
      expect(w.length, 2);
      expect(w[0].windowsCount, 2);
      expect(w[1].id, 3);
      expect(w[1].isActive, isTrue);
    });

    test('e se non risponde, una sola invece di nessuna', () async {
      // Con l'elenco vuoto la striscia dei pallini non disegna niente, e
      // «niente» somiglia troppo a «il demone è caduto». Una scrivania sola
      // dice la cosa più vicina alla verità che si possa dire senza saperla.
      finto.risposte['scrivanie'] = 'no non lo so';
      final w = await p.getWorkspaces();
      expect(w.length, 1);
      expect(w.first.isActive, isTrue);
    });

    test('«evento scrivania» esce come NUMERO, che è la forma che il nucleo '
        'sa leggere', () async {
      // `minerva_core.dart` fa `if (payload is int)`. Con una mappa quell'if
      // non scatterebbe mai: un cambio di scrivania che non risulta a
      // nessuno, e nessun errore da nessuna parte.
      final e = MinervaProvider.daRiga('evento scrivania {"attiva":3}');
      expect(e, isNotNull);
      expect(e!.type, CompositorEventType.workspaceChanged);
      expect(e.payload, 3);
      expect(MinervaProvider.daRiga('evento scrivania {"attiva":"tre"}'),
          isNull);
    });
  });
}

// Barra e dock non stanno mai dallo stesso bordo.
//
// ── Perché la regola è cambiata ───────────────────────────────────────────
//
// Fino al 4 settembre 2026 la sovrapposizione era **permessa apposta**, e il
// motivo stava scritto in tre posti: «non lo si impedisce — impedirlo vuol
// dire decidere per chi ha due schermi e una barra sola — ma le Impostazioni
// lo dicono a parole prima che succeda».
//
// Giacomo: «non mi è piaciuto ad esempio il fatto che posso mettere in alto
// anche insieme la dock e la barra uno sopra l'altro, o ci sta uno o l'altro,
// se metto la dock in alto in automatico in basso deve starci la barra».
//
// E il ragionamento non reggeva nemmeno da solo: chi ha due schermi ha
// comunque UNA barra e UNA dock. Un avviso che spiega perché la tua scrivania
// è rotta non è meglio di una scrivania che non si può rompere.
//
// ── Dove deve stare la regola, e perché non basta il pannello ─────────────
//
// `settings.json` si scrive anche a mano. Una regola che vive solo nelle
// Impostazioni è una regola che si aggira aprendo un editor di testi — ed è
// esattamente il modo in cui `bar.position` è rimasta morta per mesi: era
// scrivibile e non la leggeva nessuno.
import 'dart:io';

import 'package:test/test.dart';

File _qml(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/minerva-shell/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/$relativo');
}

String _codice(String relativo) => _qml(relativo)
    .readAsLinesSync()
    .where((r) => !r.trimLeft().startsWith('//') && !r.trimLeft().startsWith('///'))
    .join('\n');

void main() {
  group('la regola sta nel posto da cui passano tutti', () {
    late String pos;
    setUpAll(() => pos = _codice('core/Posizioni.qml'));

    test('«barraInBasso» è il valore CORRETTO, non quello scritto', () {
      // Chi legge `Core.Posizioni.barraInBasso` deve ricevere dove la barra
      // sta DAVVERO. Se la coercizione stesse altrove, i sei posti che
      // leggono di qui vedrebbero il valore grezzo e si disporrebbero uno
      // sull'altro.
      expect(pos, contains('_barraDetta'),
          reason: 'serve distinguere quello che è stato chiesto da quello che '
              'si applica');
      final i = pos.indexOf('property bool barraInBasso');
      expect(i, greaterThan(0));
      final corpo = pos.substring(i, i + 220);
      expect(corpo, contains('sovrapposte'),
          reason: '`barraInBasso` deve passare dalla correzione');
      expect(corpo, contains('dockInAlto'),
          reason: 'quando si scontrano vince la dock, e la barra prende il '
              'bordo opposto');
    });

    test('e la dock spenta lascia libera la barra', () {
      // Senza dock non c'è niente da evitare: obbligare comunque la barra
      // sarebbe una regola che decide per conto suo.
      expect(pos, contains('dockAccesa'));
      final i = pos.indexOf('property bool sovrapposte');
      expect(pos.substring(i, i + 200), contains('dockAccesa'));
    });
  });

  group('le Impostazioni spostano le due cose insieme', () {
    late String sez;
    setUpAll(() => sez = _codice('settings/sections/Dock.qml'));

    test('scegliere un bordo scrive tutte e due le chiavi', () {
      expect(sez, contains('setSettings('),
          reason: 'due `setSetting` di fila sono due scritture su disco e due '
              'ricostruzioni del tema, con un istante in cui la scrivania è '
              'mezza in un modo e mezza nell\'altro');
      expect('"dock.position"'.allMatches(sez).length, greaterThanOrEqualTo(2),
          reason: 'la chiave della dock si scrive da tutte e due i selettori');
      expect('"bar.position"'.allMatches(sez).length, greaterThanOrEqualTo(2),
          reason: 'e così quella della barra');
    });

    test('e il riquadro non promette più la sovrapposizione', () {
      expect(sez, isNot(contains('si sovrappongono')),
          reason: 'l\'avviso descriveva una cosa che adesso non può '
              'succedere: un testo che parla di un difetto impossibile è '
              'peggio di nessun testo');
    });
  });

  group('la scrittura in blocco esiste davvero', () {
    test('la shell sa chiedere più impostazioni in un messaggio solo', () {
      final ipc = _codice('core/Ipc.qml');
      expect(ipc, contains('function setSettings(mappa)'),
          reason: 'il demone sapeva già farlo (`set_settings` → `setValues`, '
              'una scrittura e un annuncio) e non gliel\'aveva mai chiesto '
              'nessuno');
      final i = ipc.indexOf('function setSettings(mappa)');
      final corpo = ipc.substring(i, i + 1400);
      expect(corpo, contains('"action": "set_settings"'));
      expect(corpo, contains('ipc.settings = copy'),
          reason: 'la copia locale si aggiorna UNA volta per tutte le chiavi: '
              'aggiornarla una chiave per volta rifarebbe partire i legami di '
              'QML a ogni passo, cioè la cosa che questa funzione esiste per '
              'non fare');
    });

    test('e il demone la sa ricevere', () {
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4 && f == null; i++) {
        for (final base in ['lib/ipc/websocket_server.dart',
                            'minervad/lib/ipc/websocket_server.dart']) {
          final c = File('${dir.path}/$base');
          if (c.existsSync()) f = c;
        }
        dir = dir.parent;
      }
      expect(f, isNotNull);
      final t = f!.readAsStringSync();
      expect(t, contains("case 'set_settings':"));
      expect(t, contains('setValues('));
    });
  });

  // ── Le finestre aperte nella barra ─────────────────────────────────────
  //
  // Il pezzo che manca allo stile «Windows»: senza dock, le finestre aperte
  // devono stare da qualche parte. Nella barra c'era solo `WindowChip`, che
  // mostra la finestra ATTIVA — una sola.
  group('la lista delle finestre nella barra', () {
    late String lista;
    setUpAll(() => lista = _codice('spine/ListaFinestre.qml'));

    test('l\'ordine è di comparsa, non di sovrapposizione', () {
      // `Core.Windows.all` è ordinato per pila: la finestra davanti è la
      // prima. Prendendolo così com'è, ogni clic riordinava la fila — e il
      // secondo clic sullo stesso pulsante finiva su un'altra finestra.
      // Misurato il 5 settembre 2026, e riparato: è la stessa lezione che la
      // dock si è scritta in testa al file.
      expect(lista, contains('_ordine'),
          reason: 'senza un ordine suo, i pulsanti si spostano sotto il dito');
      expect(lista, contains('Qt.callLater'),
          reason: 'l\'ordine si aggiorna DOPO aver disegnato: un legame che '
              'scrive la cosa da cui dipende è un anello');
    });

    test('una ridotta si RIPRENDE, non si mette a fuoco', () {
      // Dare il fuoco a una finestra che sta in un'altra scrivania non la
      // riporta indietro: il terzo clic non faceva niente.
      expect(lista, contains('Core.Windows.restore('),
          reason: '`focus` su una ridotta la lascia dov\'è');
    });

    test('il tasto destro non chiude niente', () {
      // Un pulsante largo quaranta pixel in una fila di pulsanti uguali, e il
      // gesto più distruttivo che ci sia, senza una domanda.
      expect(lista, isNot(contains('Core.Windows.close(')),
          reason: 'una finestra chiusa per sbaglio è lavoro perso; la barra '
              'di Windows apre un menù, non chiude');
    });

    test('e la chiave che la accende esiste nei valori di fabbrica', () {
      expect(lista.isNotEmpty, isTrue);
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4 && f == null; i++) {
        for (final base in ['lib/core/settings_api.dart',
                            'minervad/lib/core/settings_api.dart']) {
          final c = File('${dir.path}/$base');
          if (c.existsSync()) f = c;
        }
        dir = dir.parent;
      }
      expect(f!.readAsStringSync(), contains("'listaFinestre'"));
    });

    test('ed è dichiarata in qmldir, o non è un tipo', () {
      // «ListaFinestre is not a type»: costato un giro di prove il 5 settembre
      // 2026. Un file QML nuovo dentro una cartella con `qmldir` non basta
      // metterlo lì.
      final q = _qml('spine/qmldir').readAsStringSync();
      expect(q, contains('ListaFinestre'));
    });
  });

  // ── Gli stili ──────────────────────────────────────────────────────────
  //
  // Giacomo, 4 settembre 2026: «poi creerei dei preset come ad esempio stile
  // mac, stile windows, stile minerva, stile libero». Uno stile non aggiunge
  // manopole: scrive insieme quelle che ci sono già, sparse fra tre pagine.
  group('gli stili della scrivania', () {
    late String stile;
    setUpAll(() => stile = _codice('settings/sections/Stile.qml'));

    test('si applicano in UN messaggio, non venti', () {
      expect(stile, contains('Core.Ipc.setSettings('),
          reason: 'venti `setSetting` di fila sono venti scritture su disco e '
              'venti ricostruzioni del tema: per un istante la scrivania '
              'sarebbe mezza Mac e mezza Windows');
      expect(stile, isNot(contains('Core.Ipc.setSetting(')),
          reason: 'una sola chiave scritta a parte basta a rompere '
              'l\'atomicità');
    });

    test('«Libero» è il TUO, e si salva prima di cambiare', () {
      // Un preset che cancella una scrivania costruita in due mesi senza modo
      // di tornare indietro è un difetto, non una funzione.
      expect(stile, contains('_fotografa()'));
      final i = stile.indexOf('function applica(');
      final corpo = stile.substring(i, stile.indexOf('S.SettingRow', i) > 0
          ? stile.indexOf('Card {', i) : stile.length);
      expect(corpo, contains('page.attuale === "libero"'),
          reason: 'se si è già dentro uno stile, la fotografia da tenere è '
              'quella di PRIMA: risalvare adesso vorrebbe dire che «Libero» '
              'riporta a Mac, cioè che il tuo l\'hai perso');
    });

    test('la fotografia viaggia come testo, non come mappa annidata', () {
      // Le chiavi hanno il punto dentro (`bar.position`) e per il demone il
      // punto vuol dire «scendi di un livello»: una mappa annidata
      // spezzerebbe ogni chiave in due.
      expect(stile, contains('JSON.stringify(page._fotografa())'));
      expect(stile, contains('JSON.parse('));
    });

    test('e ogni chiave che uno stile scrive esiste nei valori di fabbrica',
        () {
      final chiavi = RegExp(r'"([a-z]+\.[A-Za-z]+)"\s*:')
          .allMatches(stile)
          .map((m) => m.group(1)!)
          .toSet();
      expect(chiavi.length, greaterThan(5),
          reason: 'non ho trovato le chiavi degli stili');

      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4 && f == null; i++) {
        for (final base in ['lib/core/settings_api.dart',
                            'minervad/lib/core/settings_api.dart']) {
          final c = File('${dir.path}/$base');
          if (c.existsSync()) f = c;
        }
        dir = dir.parent;
      }
      final fab = f!.readAsStringSync();
      final mancanti = <String>[];
      for (final k in chiavi) {
        final ultima = k.split('.').last;
        if (!fab.contains("'$ultima'")) mancanti.add(k);
      }
      expect(mancanti, isEmpty,
          reason: 'uno stile che scrive una chiave inesistente non dà errore: '
              'scrive, e non succede niente\n  ${mancanti.join('\n  ')}');
    });
  });
}

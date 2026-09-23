// I due capi del filo del bus.
//
// Nasce dalla stessa domanda che ha trovato i difetti del 12 agosto 2026:
// «cosa chiede un pezzo che l'altro non ascolta, senza che nessuno lo dica?».
// Per le scorciatoie quella prova c'era già (`scorciatoie_test.dart`) ed è
// servita; per il bus no.
//
// Un'azione mandata a un demone che non la gestisce **non dà nessun errore**:
// il messaggio parte, non risponde niente, e il pannello resta fermo. Un
// evento atteso e mai pubblicato è peggio ancora: l'interfaccia mostra per
// sempre il valore di partenza fingendo sia quello vero.

import 'dart:io';
import 'package:test/test.dart';

Directory _radice() {
  for (final base in ['.', '..', '../..']) {
    if (Directory('$base/minerva-shell').existsSync()) return Directory(base);
  }
  fail('non trovo la radice del progetto');
}

String _leggi(String relativo) => File('${_radice().path}/$relativo').readAsStringSync();

List<File> _qml() {
  final f = <File>[];
  for (final v in Directory('${_radice().path}/minerva-shell')
      .listSync(recursive: true, followLinks: false)) {
    if (v is File && v.path.endsWith('.qml')) f.add(v);
  }
  return f;
}

/// Le azioni che il demone sa ricevere: i `case` dello switch sull'azione.
Set<String> _gestite() {
  final s = _leggi('minervad/lib/ipc/websocket_server.dart');
  final i = s.indexOf('switch (azione)');
  final blocco = i >= 0 ? s.substring(i) : s;
  return RegExp(r"case\s+'([a-z0-9_]+)'\s*:")
      .allMatches(blocco)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Le azioni che la shell manda davvero: solo quelle dentro `send({...})`,
/// non i nomi delle voci di menu — che si chiamano «action» anche loro e
/// falsavano il conto di trentacinque unità.
Map<String, Set<String>> _mandate() {
  final fuori = <String, Set<String>>{};
  final re = RegExp(r'send\(\s*\{[^}]*?"action"\s*:\s*"([a-z0-9_]+)"', dotAll: true);
  for (final f in _qml()) {
    for (final m in re.allMatches(f.readAsStringSync())) {
      fuori.putIfAbsent(m.group(1)!, () => {}).add(f.uri.pathSegments.last);
    }
  }
  return fuori;
}

/// Gli eventi che il demone pubblica.
Set<String> _pubblicati() {
  final fuori = <String>{};
  for (final v in Directory('${_radice().path}/minervad/lib')
      .listSync(recursive: true, followLinks: false)) {
    if (v is! File || !v.path.endsWith('.dart')) continue;
    final t = v.readAsStringSync();
    for (final re in [
      RegExp(r"MinervaEvent\(\s*type:\s*'([a-z0-9_]+)'"),
      RegExp(r"'event'\s*:\s*'([a-z0-9_]+)'"),
    ]) {
      fuori.addAll(re.allMatches(t).map((m) => m.group(1)!));
    }
  }
  return fuori;
}

/// Gli eventi che la shell smista.
Set<String> _attesi() {
  final s = _leggi('minerva-shell/core/Ipc.qml');
  return RegExp(r'case\s+"([a-z0-9_]+)"\s*:')
      .allMatches(s)
      .map((m) => m.group(1)!)
      .toSet();
}


/// Gli eventi che il demone pubblica **sul bus** — quelli che passano da
/// `_broadcastEvent`, e quindi dal filtro delle iscrizioni.
Set<String> _sulBus() {
  final fuori = <String>{};
  for (final v in Directory('${_radice().path}/minervad/lib')
      .listSync(recursive: true, followLinks: false)) {
    if (v is! File || !v.path.endsWith('.dart')) continue;
    fuori.addAll(RegExp(r"MinervaEvent\(\s*type:\s*'([a-z0-9_]+)'")
        .allMatches(v.readAsStringSync())
        .map((m) => m.group(1)!));
  }
  return fuori;
}

/// I tipi che il demone spedisce DIRETTAMENTE ai soli iscritti, senza passare
/// dal bus: `_aTutti({'event': 'x', …}, solo: (c) => c.isSubscribed('x'))`.
/// È la seconda porta dello stesso filtro, e ha lo stesso modo di perdere le
/// cose: `system_audio_state` ci è passato il 20 settembre 2026 — spedito
/// solo agli iscritti, e nessun verbo con cui iscriversi. La pagina Audio
/// aveva perso il timer da 4 s e con lui ogni aggiornamento.
Set<String> _filtratiAMano() {
  final s = _leggi('minervad/lib/ipc/websocket_server.dart');
  return RegExp(r"isSubscribed\('([a-z0-9_]+)'\)")
      .allMatches(s)
      .map((m) => m.group(1)!)
      .toSet();
}

/// I tipi che un client riceve senza chiedere niente: l'elenco predefinito
/// dentro `WebSocketClientConnection`.
Set<String> _predefiniti() {
  final s = _leggi('minervad/lib/ipc/websocket_server.dart');
  final m = RegExp(r'List<String>\s+subscribedEvents\s*=\s*\[(.*?)\];', dotAll: true)
      .firstMatch(s);
  if (m == null) fail('non trovo più l\'elenco predefinito delle iscrizioni');
  return RegExp(r"'([a-z0-9_]+)'")
      .allMatches(m.group(1)!)
      .map((x) => x.group(1)!)
      .toSet();
}

/// I tipi che qualcuno aggiunge a mano alle iscrizioni di un client
/// (`subscribe_processes` si aggiunge «processes» da sé).
Set<String> _aggiuntiAMano() {
  final s = _leggi('minervad/lib/ipc/websocket_server.dart');
  return RegExp(r"subscribedEvents\s*=\s*\[\.\.\.client\.subscribedEvents,\s*'([a-z0-9_]+)'")
      .allMatches(s)
      .map((m) => m.group(1)!)
      .toSet();
}

/// Il corpo di un blocco, contando le graffe dalla prima dopo `da`.
String blocco(String s, int da) {
  final apre = s.indexOf('{', da);
  var n = 0;
  for (var i = apre; i < s.length; i++) {
    if (s[i] == '{') n++;
    if (s[i] == '}') {
      n--;
      if (n == 0) return s.substring(apre, i + 1);
    }
  }
  fail('blocco non chiuso a partire da $da');
}

void main() {
  group('il bus: i due capi del filo', () {
    test('ogni azione che la shell manda, il demone la ascolta', () {
      final gestite = _gestite();
      final mandate = _mandate();
      final orfane = <String>[];
      mandate.forEach((azione, dove) {
        if (!gestite.contains(azione)) {
          orfane.add('$azione (da ${dove.join(", ")})');
        }
      });
      expect(orfane, isEmpty,
          reason: 'la shell manda azioni che il demone non gestisce.\n'
              'Non danno errore: il messaggio parte, non risponde niente, e\n'
              'il pannello resta fermo per sempre.');
    });

    test('ogni evento che la shell smista, il demone lo pubblica', () {
      final pubblicati = _pubblicati();
      final orfani = _attesi().where((e) => !pubblicati.contains(e)).toList();
      expect(orfani, isEmpty,
          reason: 'la shell aspetta eventi che nessuno manda: l\'interfaccia\n'
              'mostrerebbe per sempre il valore di partenza fingendo sia\n'
              'quello vero. Orfani: ${orfani.join(", ")}');
    });


    // ── Il terzo verso, quello che mancava ────────────────────────────
    //
    // Le due prove qui sopra guardano che la shell e il demone si nominino a
    // vicenda. Non bastano: fra il `publish` e la shell c'è un filtro —
    // `_broadcastEvent` spedisce solo a chi è ISCRITTO a quel tipo — e la
    // shell non manda mai `subscribe`, quindi vale solo l'elenco predefinito.
    //
    // `scorciatoie_compositore` ci è caduto dentro e c'è rimasto: pubblicato
    // da `minerva_core.dart` a ogni modifica delle scorciatoie, gestito da
    // `Ipc.qml`, e ricevuto da nessuno. Tutte e due le prove sopra passavano.
    // Il sintomo: cambi una scorciatoia, il promemoria di Super+K si aggiorna,
    // e il tasto continua a fare quello di prima fino al riavvio della
    // sessione — che è esattamente quello che il commento accanto al `publish`
    // dichiara di aver risolto.
    test('ogni evento pubblicato sul bus arriva a qualcuno', () {
      final consegnabili = {..._predefiniti(), ..._aggiuntiAMano()};
      final persi = _sulBus().where((e) => !consegnabili.contains(e)).toList()
        ..sort();
      expect(persi, isEmpty,
          reason: 'questi tipi si pubblicano sul bus e nessun client li riceve:\n'
              '${persi.join(", ")}\n'
              'Non danno errore. `_broadcastEvent` filtra sulle iscrizioni, e\n'
              'la shell non ne chiede nessuna: vale solo l\'elenco predefinito\n'
              'in `WebSocketClientConnection`. O il tipo va in quell\'elenco, o\n'
              'qualcuno deve iscriversi, o non va pubblicato sul bus.');
    });

    test('e anche quello spedito ai soli iscritti ha un verbo per iscriversi', () {
      final consegnabili = {..._predefiniti(), ..._aggiuntiAMano()};
      final persi = _filtratiAMano().where((e) => !consegnabili.contains(e)).toList()
        ..sort();
      expect(persi, isEmpty,
          reason: 'questi tipi si mandano solo a chi è iscritto, e non c\'è\n'
              'nessun verbo che iscriva qualcuno: ${persi.join(", ")}.\n'
              'Serve un `subscribe_<cosa>` che aggiunga il tipo alle\n'
              'iscrizioni del client, come `subscribe_machine`.');
      expect(_filtratiAMano(), isNotEmpty, reason: 'la forma è cambiata?');
    });

    test('l\'elenco predefinito e i pubblicati non sono vuoti', () {
      expect(_predefiniti().length, greaterThan(3));
      expect(_sulBus().length, greaterThan(4));
    });

    test('i due elenchi non sono vuoti (è cambiata la forma dei file?)', () {
      // La stessa cautela di `scorciatoie_test.dart`: una prova che non trova
      // niente da confrontare passa sempre, e non prova niente.
      expect(_gestite().length, greaterThan(40));
      expect(_mandate().length, greaterThan(30));
      expect(_pubblicati().length, greaterThan(20));
      expect(_attesi().length, greaterThan(20));
    });
  });

  group('il demone: nessun servizio costruito e mai avviato', () {
    test('ogni servizio con init() viene avviato', () {
      // L'equivalente per il demone del difetto trovato in `Windows`:
      // `assicuraSpazio()` esisteva, era giusta, e non la chiamava nessuno
      // nella configurazione normale.
      final core = _leggi('minervad/lib/core/minerva_core.dart');
      final server = _leggi('minervad/lib/ipc/websocket_server.dart');
      final dove = '$core\n$server';

      final servizi = <String>[];
      for (final v in Directory('${_radice().path}/minervad/lib/services')
          .listSync()) {
        if (v is! File || !v.path.endsWith('.dart')) continue;
        final t = v.readAsStringSync();
        if (!t.contains('Future<void> init(')) continue;
        final m = RegExp(r'^class\s+(\w+Service)\b', multiLine: true).firstMatch(t);
        if (m != null) servizi.add(m.group(1)!);
      }
      expect(servizi, isNotEmpty);

      final dimenticati = <String>[];
      for (final s in servizi) {
        // Costruito da qualche parte, e con un `.init(` nello stesso file.
        final costruito = RegExp(r'\b' + s + r'\s*\(').hasMatch(dove);
        if (!costruito) dimenticati.add('$s: mai costruito');
      }
      expect(dimenticati, isEmpty,
          reason: 'un servizio che non nasce è una funzione che non esiste, e '
              'non lo dice nessuno');
    });
  });

  // ── Il silenzio, che è il difetto peggiore di un confine ────────────────
  //
  // Il ramo predefinito dello switch ha scritto sopra la frase giusta — «chi
  // chiede resta ad aspettare per sempre e non ha modo di sapere che nessuno
  // risponderà» — e per un anno ha fatto proprio quello: scriveva una riga sul
  // registro e taceva. Il `catch` esterno faceva lo stesso per TUTTE le
  // azioni: se una scoppia a metà, chi ha chiesto aspetta per sempre.
  //
  // Provato sul demone vivo il 7 settembre 2026: `{"action":"non_esisto"}` e
  // `{"action":"launch_app","id":123}` (un `as String?` che scoppia) non
  // ricevevano niente, e il canale restava vivo — quindi il difetto non si
  // vedeva nemmeno.
  group('il confine non tace mai', () {
    // Le due prove qui sotto si agganciano al TESTO dei due messaggi, non a
    // «il primo default» o «il primo catch»: dentro lo switch ce ne sono
    // altri, annidati, e il primo tentativo di questa prova ha agganciato
    // quelli — passando in verde su un difetto aperto.
    //
    // E guardano il codice SENZA i commenti. Il secondo tentativo passava
    // perché il commento che avevo appena scritto conteneva la parola
    // `client.send`: una prova che si accontenta di trovare una stringa la
    // trova anche in una frase in italiano che la nomina.

    /// Il file senza i commenti di riga: una guardia non deve poter diventare
    /// verde per una parola scritta in un commento.
    String senzaCommenti(String s) =>
        s.split('\n').map((r) {
          final i = r.indexOf('//');
          return i < 0 ? r : r.substring(0, i);
        }).join('\n');

    test('un\'azione sconosciuta riceve una risposta, non solo una riga di log',
        () {
      final s = senzaCommenti(_leggi('minervad/lib/ipc/websocket_server.dart'));
      final ancora = s.indexOf('Azione sconosciuta');
      expect(ancora, greaterThan(0), reason: 'non trovo più il ramo predefinito');
      final da = s.lastIndexOf('default:', ancora);
      final a = s.indexOf('break;', ancora);
      expect(s.substring(da, a), contains('_nonSonoRiuscito('),
          reason: 'il ramo predefinito scrive sul registro e non risponde a\n'
              'chi ha chiesto. Il registro lo legge chi lo cerca; chi ha\n'
              'mandato il messaggio aspetta per sempre, e il canale resta\n'
              'vivo, quindi non se ne accorge nessuno.');
    });

    test('un\'azione che scoppia riceve una risposta', () {
      final s = senzaCommenti(_leggi('minervad/lib/ipc/websocket_server.dart'));
      final ancora = s.indexOf('Errore nel processare messaggio del client');
      expect(ancora, greaterThan(0), reason: 'non trovo più il catch esterno');
      final da = s.lastIndexOf('} catch (e)', ancora);
      expect(blocco(s, da), contains('_nonSonoRiuscito('),
          reason: 'se una qualunque delle azioni solleva un\'eccezione, il\n'
              'catch esterno stampa e basta: chi ha chiesto aspetta per\n'
              'sempre. Vale per tutte le azioni insieme, comprese quelle\n'
              'che qualcuno aggiungerà domani.');
    });

    test('e quella risposta parte davvero', () {
      // Le due prove sopra pretendono che si CHIAMI l'aiutante. Questa
      // pretende che l'aiutante spedisca: senza, si sposterebbe il silenzio
      // di una funzione più in là.
      final s = senzaCommenti(_leggi('minervad/lib/ipc/websocket_server.dart'));
      final i = s.indexOf('void _nonSonoRiuscito(');
      expect(i, greaterThan(0), reason: 'non trovo più l\'aiutante');
      expect(blocco(s, i), contains('client.send('),
          reason: 'l\'aiutante che deve dire «non è andata» non spedisce '
              'niente');
    });

    test('e la shell sa cosa farsene', () {
      // Un errore che il demone manda e che la shell butta via è lo stesso
      // silenzio con un passaggio in più.
      final ipc = _leggi('minerva-shell/core/Ipc.qml');
      expect(ipc, contains('azione_fallita'),
          reason: 'il demone dice che una richiesta è fallita e la shell non '
              'ha un ramo che lo legga');
    });
  });

  // ── Trasmettere a tutti ─────────────────────────────────────────────────
  group('trasmettere a tutti si fa in un posto solo', () {
    String senzaCommenti(String s) => s.split('\n').map((r) {
          final i = r.indexOf('//');
          return i < 0 ? r : r.substring(0, i);
        }).join('\n');

    test('nessuno impacchetta lo stesso messaggio una volta per client', () {
      // `send()` fa `jsonEncode`. Un ciclo su `_clients` che chiama `send`
      // impacchetta lo STESSO messaggio una volta per finestra aperta: con
      // l'elenco dei processi sono 59 KB e fra 1,3 e 8,9 ms — misurati il 7
      // settembre 2026 — moltiplicati per quante finestre di Minerva ci sono.
      // Il demone ha un filo solo: quel tempo è fermo per tutti.
      final s = senzaCommenti(
          _leggi('minervad/lib/ipc/websocket_server.dart'));
      final cicli = RegExp(r'for \(final \w+ in _clients\)[^{]*\{(.*?)\n    \}',
              dotAll: true)
          .allMatches(s)
          .map((m) => m.group(1)!)
          .where((corpo) => corpo.contains('.send('))
          .toList();
      expect(cicli, isEmpty,
          reason: 'un ciclo su _clients chiama send(), che impacchetta ogni '
              'volta. Si passa da _aTutti, che impacchetta una volta sola.');
    });

    test('e si cammina su una COPIA dell\'elenco', () {
      // Spedire può far morire un client — un tubo rotto — e chi muore si
      // toglie da `_clients` dal `alMorire`. Camminare sull'elenco vero
      // mentre qualcuno se ne toglie è un ConcurrentModificationError in
      // mezzo a un `windows_state`, cioè fino a sedici occasioni al secondo.
      final s = senzaCommenti(
          _leggi('minervad/lib/ipc/websocket_server.dart'));
      final i = s.indexOf('void _aTutti(');
      expect(i, greaterThan(0), reason: 'non trovo più _aTutti');
      final fine = s.indexOf('\n  }', i);
      expect(s.substring(i, fine), contains('_clients.toList()'),
          reason: 'si cammina sull\'elenco vero mentre chi muore se ne toglie');
    });
  });

  // ── L'identificativo della richiesta ────────────────────────────────────
  //
  // Il protocollo riconosceva le risposte dal TIPO e da nient'altro: due
  // richieste uguali in volo insieme erano indistinguibili, e chi aspettava
  // prendeva la prima che passava. È anche la ragione per cui «questa
  // richiesta non è andata» non si poteva dire bene — per dirlo bisogna
  // sapere QUALE.
  group('una risposta sa a quale domanda risponde', () {
    String senzaCommenti(String s) => s.split('\n').map((r) {
          final i = r.indexOf('//');
          return i < 0 ? r : r.substring(0, i);
        }).join('\n');

    test('lo switch delle azioni gira dentro la zona della richiesta', () {
      final s = senzaCommenti(
          _leggi('minervad/lib/ipc/websocket_server.dart'));
      expect(s, contains('runZoned('),
          reason: 'senza la zona, l\'identificativo dovrebbe stare in un campo '
              'del client — e fra un await e il successivo il demone serve '
              'altri messaggi, quindi verrebbe sovrascritto proprio nel caso '
              'per cui esiste');
      expect(s, contains('_chiaveId: msg[\'id\']'));
      expect(s, contains('_chiaveCliente: client'));
    });

    test('e la risposta lo riporta, ma solo a chi ha chiesto', () {
      final s = senzaCommenti(
          _leggi('minervad/lib/ipc/websocket_server.dart'));
      final i = s.indexOf('void send(Map<String, dynamic> data)');
      expect(i, greaterThan(0), reason: 'non trovo più send()');
      final corpo = blocco(s, i);
      expect(corpo, contains('Zone.current[_chiaveId]'),
          reason: 'send() non riporta l\'identificativo');
      expect(corpo, contains('identical(Zone.current[_chiaveCliente], this)'),
          reason: 'mentre serviamo una richiesta possiamo spedire anche ad '
              'ALTRE finestre: senza questo controllo si porterebbero dietro '
              'l\'identificativo di una domanda che non hanno fatto');
    });

    test('e chi trasmette a tutti non lo riporta mai', () {
      // Un annuncio non è la risposta a niente: attaccargli l'identificativo
      // della richiesta che per caso era in corso vuol dire dire il falso a
      // tutte le finestre tranne una.
      final s = senzaCommenti(
          _leggi('minervad/lib/ipc/websocket_server.dart'));
      final i = s.indexOf('void _aTutti(');
      expect(i, greaterThan(0), reason: 'non trovo più _aTutti');
      expect(blocco(s, i), isNot(contains('_chiaveId')),
          reason: 'un annuncio a tutti si porta dietro l\'identificativo di '
              'una richiesta');
    });
  });

  // ── Nessun ramo dello switch diventi un programma a sé ──────────────────
  //
  // I 140 verbi del demone stanno in uno switch solo, e la prima reazione
  // guardando le sue duemila righe è «va spezzato». Contate però: sono 1383
  // righe di CODICE su 134 rami, cioè dieci a testa — il resto sono i
  // commenti, che in questo progetto sono metà del valore. Spezzare in dieci
  // file una cosa che in media è lunga dieci righe sposterebbe i difetti
  // invece di toglierli.
  //
  // Quello che serve davvero è che nessun ramo cresca fino a diventare un
  // programma dentro il programma. Uno lo era — `matrix_search`, 109 righe,
  // undici volte la media — e adesso sta in un metodo suo.
  //
  // C'è anche una ragione tecnica, non solo di lettura: in Dart i `case` di
  // uno switch senza graffe proprie CONDIVIDONO lo scopo, quindi le variabili
  // dichiarate da un ramo lungo sono visibili ai vicini.
  group('lo switch delle azioni resta leggibile', () {
    test('nessun ramo supera le quaranta righe di codice', () {
      final s = _leggi('minervad/lib/ipc/websocket_server.dart').split('\n');
      final i0 = s.indexOf('    switch (action) {');
      expect(i0, greaterThan(0), reason: 'non trovo più lo switch');
      final i1 = s.indexOf('    }', i0 + 1);
      final caso = RegExp(r"^      case '([a-z_0-9]+)':\s*$");

      final lunghi = <String>[];
      var i = i0 + 1;
      while (i < i1) {
        final m = caso.firstMatch(s[i]);
        if (m == null) {
          i++;
          continue;
        }
        final nomi = <String>[m.group(1)!];
        var j = i + 1;
        while (j < i1 && caso.hasMatch(s[j])) {
          nomi.add(caso.firstMatch(s[j])!.group(1)!);
          j++;
        }
        var k = j;
        while (k < i1 &&
            !caso.hasMatch(s[k]) &&
            !s[k].startsWith('      default:')) {
          k++;
        }
        final righe = s
            .sublist(j, k)
            .where((r) => r.trim().isNotEmpty && !r.trim().startsWith('//'))
            .length;
        if (righe > 40) lunghi.add('${nomi.join("/")} ($righe righe)');
        i = k;
      }
      expect(lunghi, isEmpty,
          reason: 'questi rami sono diventati programmi a sé e vanno in un '
              'metodo loro: ${lunghi.join(", ")}');
    });

    test('e i rami si contano ancora (è cambiata la forma del file?)', () {
      final s = _leggi('minervad/lib/ipc/websocket_server.dart');
      final n = RegExp(r"^      case '[a-z_0-9]+':\s*$", multiLine: true)
          .allMatches(s)
          .length;
      expect(n, greaterThan(100),
          reason: 'trovo solo $n rami: la prova sopra non sta guardando '
              'lo switch vero');
    });
  });
}

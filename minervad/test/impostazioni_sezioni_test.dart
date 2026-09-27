import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Le Impostazioni sono l'unico posto in Minerva dove una voce esiste in TRE
/// punti che nessun compilatore mette a confronto:
///
///   1. l'elenco `sections` — la voce nella colonna di sinistra;
///   2. lo `switch` del `Loader` — quale file aprire quando si clicca;
///   3. `sections/qmldir` — perché il file sia importabile.
///
/// Dimenticarne uno non dà nessun errore. Manca il caso nello `switch` e si
/// clicca la voce nuova ottenendo la pagina «Aspetto», che sembra un difetto
/// del clic. Manca la riga in `qmldir` e la pagina resta bianca. Sono
/// esattamente i guasti muti che questa prova esiste per rendere rumorosi.
File _trova(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

void main() {
  group('sezioni delle Impostazioni', () {
    final system = _trova('minerva-shell/settings/System.qml').codiceVivo();
    final qmldir = _trova('minerva-shell/settings/sections/qmldir').codiceVivo();

    // ── `[\w-]` e non `\w` ────────────────────────────────────────────────
    //
    // `\w` non prende il trattino, e una sezione si chiama «accesso-facile»:
    // era l'unica delle quindici che questa prova non vedeva, quindi l'unica
    // su cui i tre elenchi potevano divergere senza che nessuno se ne
    // accorgesse. Trovata il 18 agosto 2026 cambiandole l'icona.
    // ── Solo il blocco `sections`, non tutto il file ──────────────────────
    //
    // Dal 5 settembre 2026 accanto a `sections` c'è `gruppi`, che dice come le
    // pagine si presentano nella colonna. I gruppi hanno la stessa forma —
    // `{ "id": …, "icon": … }` — e cercando in tutto il file finivano
    // nell'elenco delle PAGINE: la prova pretendeva un `case "g-scrivania"`
    // che non deve esistere, perché un gruppo non è una pagina.
    // `expect` qui non si può: siamo fuori da un `test`, e il pacchetto lo
    // rifiuta. Un `StateError` dice la stessa cosa nello stesso momento.
    final bloccoSezioni = () {
      final inizio = system.indexOf('readonly property var sections: [');
      if (inizio < 0) throw StateError('l\'elenco delle sezioni non si trova');
      final fine = system.indexOf('\n    ]', inizio);
      if (fine < 0) throw StateError('l\'elenco delle sezioni non si chiude');
      return system.substring(inizio, fine);
    }();

    final elencate = RegExp(r'\{ "id": "([\w-]+)",\s*"icon"')
        .allMatches(bloccoSezioni)
        .map((m) => m.group(1)!)
        .toList();

    final caricate = <String, String>{
      for (final m in RegExp(r'case "([\w-]+)":\s*return "(sections/\w+\.qml)"')
          .allMatches(system))
        m.group(1)!: m.group(2)!
    };

    test('l\'elenco non è vuoto (è cambiata la forma del file?)', () {
      expect(elencate.length, greaterThan(8));
      expect(caricate, isNotEmpty);
    });

    test('ogni voce della colonna apre una pagina sua', () {
      // «appearance» è il `default` dello switch e non ha un `case`: è voluto,
      // ed è l'unica eccezione ammessa.
      for (final id in elencate) {
        if (id == 'appearance') continue;
        expect(caricate.keys, contains(id),
            reason: 'la voce "$id" è nella colonna ma il Loader non la '
                'conosce: cliccandola si aprirebbe «Aspetto»');
      }
    });

    test('ogni pagina caricata esiste davvero su disco', () {
      for (final entry in caricate.entries) {
        final f = File(
            '${_trova('minerva-shell/settings/System.qml').parent.path}/${entry.value}');
        expect(f.existsSync(), isTrue,
            reason: '"${entry.key}" punta a ${entry.value}, che non c\'è');
      }
    });

    test('ogni pagina è dichiarata in qmldir', () {
      for (final percorso in caricate.values) {
        final nome = percorso.split('/').last;
        expect(qmldir, contains(nome),
            reason: '$nome non è in sections/qmldir: la pagina resterebbe '
                'bianca senza dire perché');
      }
    });

    test('nessun caso dello switch punta a una voce che non esiste più', () {
      for (final id in caricate.keys) {
        expect(elencate, contains(id),
            reason: 'lo switch conosce "$id", che nella colonna non c\'è più');
      }
    });
  
    // ── E i gruppi puntano a pagine che esistono ─────────────────────────
    //
    // Un gruppo che nomina una pagina sparita non dà errore: mostra una riga
    // che non apre niente, e chi la preme conclude che le Impostazioni sono
    // rotte. È lo stesso difetto dei tre elenchi che divergono, un piano più
    // in su.
    test('ogni voce di un gruppo è una pagina vera', () {
      final blocco = () {
        final inizio = system.indexOf('readonly property var gruppi: [');
        expect(inizio, isNot(-1), reason: 'l\'elenco dei gruppi non si trova');
        final fine = system.indexOf('\n    ]', inizio);
        return system.substring(inizio, fine);
      }();

      final citate = RegExp(r'"voci": \[([^\]]*)\]')
          .allMatches(blocco)
          .expand((m) => m
              .group(1)!
              .split(',')
              .map((s) => s.trim().replaceAll('"', ''))
              .where((s) => s.isNotEmpty))
          .toList();
      expect(citate.length, greaterThan(4),
          reason: 'non ho trovato le voci dei gruppi');

      final fantasmi = citate.where((v) => !elencate.contains(v)).toList();
      expect(fantasmi, isEmpty,
          reason: 'questi gruppi nominano pagine che non esistono: '
              '${fantasmi.join(', ')}');

      // E il verso opposto: una pagina che non sta né in un gruppo né fra le
      // voci dirette non si raggiunge da nessuna parte.
      final dirette = RegExp(r'\{ "id": "([\w-]+)" \}')
          .allMatches(blocco)
          .map((m) => m.group(1)!)
          .toList();
      final irraggiungibili = elencate
          .where((p) => !citate.contains(p) && !dirette.contains(p))
          .toList();
      expect(irraggiungibili, isEmpty,
          reason: 'queste pagine esistono e non compaiono nella colonna: '
              '${irraggiungibili.join(', ')}');
    });

    // ── Un percorso si SCEGLIE, non si incolla ──────────────────────────
    //
    // Giacomo, 5 settembre 2026: «qualsiasi opzione dove c'è la scelta del
    // percorso o del file globalmente nelle impostazioni deve avere una
    // selezione che si apre il mini file manager […] ci sono parti delle
    // impostazioni dove devi incollare il percorso e a me non piace perché
    // voglio semplicità».
    //
    // Era anche incoerente: «Aspetto» aveva già «Scegli una cartella…» e
    // «Scegli dal disco…», e la schermata di accesso chiedeva di scrivere
    // `/usr/share/backgrounds/…` a mano.
    test('nessuna sezione chiede di scrivere un percorso a mano', () {
      //  cerca un FILE: la cartella si prende dal suo genitore.
      final radice = _trova('minerva-shell/settings/qmldir').parent.path;
      final colpe = <String>[];

      for (final f in Directory(radice)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final nome = f.path.split('settings/').last;
        if (nome == 'SceltaPercorso.qml') continue;
        final testo = f
            .readAsLinesSync()
            .where((r) => !r.trimLeft().startsWith('//'))
            .join('\n');

        // Un percorso che l'utente VEDE: un segnaposto o un'etichetta che
        // comincia con una barra. Non basta cercare `/usr/` nel file: in
        // `Accessibilita.qml` c'è dentro un comando di shell che controlla
        // se un tema di puntatori esiste, e quello non lo scrive nessuno a
        // mano — la prima versione di questa prova lo dava per colpevole.
        final parla = RegExp(
                r'(segnaposto|text)\s*:\s*"/(usr|home)/'
                r'|percorso di un file|file path')
            .hasMatch(testo);
        if (!parla) continue;
        if (testo.contains('SceltaPercorso')) continue;
        if (testo.contains('Scegli')) continue;
        colpe.add(nome);
      }

      expect(colpe, isEmpty,
          reason: 'qui si chiede un percorso senza un modo di sceglierlo: '
              '${colpe.join(', ')}');
    });

    // ── I cursori che dicevano il falso ──────────────────────────────────
    //
    // `ValueSlider` aveva un ripiego muto: un'unità che non riconosceva era
    // una percentuale. Così due cursori hanno detto numeri senza senso per
    // mesi, in bella vista: la sfocatura della schermata di accesso
    // (`unit: ""`) si leggeva «4700%» invece di «47 px», e il giro della
    // cornice (`unit: "secondi"`, che non è un'unità ma una traduzione)
    // «800%» invece di «8 s».
    //
    // È la stessa famiglia dei difetti che si VEDONO e che nessuna prova
    // prendeva: un numero sbagliato ha lo stesso aspetto di uno giusto.
    test('ogni cursore dichiara un\'unità che esiste', () {
      const unita = {'percento', 'pixel', 'numero', 'intero', 'niente'};
      final radice = _trova('minerva-shell/settings/qmldir').parent.path;
      final colpe = <String>[];

      for (final f in Directory(radice)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final nome = f.path.split('settings/').last;
        if (nome == 'ValueSlider.qml') continue;
        final righe = f.readAsLinesSync();
        for (var i = 0; i < righe.length; i++) {
          final r = righe[i].trim();
          if (r.startsWith('//') || !r.startsWith('unit:')) continue;
          final valore = r.substring(5).trim();
          // Deve essere una stringa fissa: un ternario che traduce il nome
          // dell'unità è esattamente il difetto del giro della cornice.
          final m = RegExp(r'^"([a-z]*)"$').firstMatch(valore);
          if (m == null || !unita.contains(m.group(1))) {
            colpe.add('$nome:${i + 1}  unit: $valore');
          }
        }
      }

      expect(colpe, isEmpty,
          reason: 'un\'unità che ValueSlider non conosce non dà errore: dà un '
              'numero sbagliato che sembra giusto\n  ${colpe.join('\n  ')}');
    });

    // ── Le opzioni che non si potevano premere ───────────────────────────
    //
    // `ChoicePicker` era una `Row`: una fila sola dentro un riquadro che la
    // ritagliava. Con sei disposizioni di tastiera se ne vedevano tre e
    // mezza, e le ultime tre non si potevano scegliere — non nascoste dietro
    // uno scorrimento: fuori dal mondo.
    test('un selettore manda a capo invece di tagliare', () {
      final cp = _trova('minerva-shell/settings/ChoicePicker.qml')
          .readAsLinesSync()
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
      expect(cp, contains('Flow {'),
          reason: 'una `Row` di opzioni più larga del riquadro non si '
              'scorre: si taglia, e le opzioni oltre il bordo non esistono');
      expect(cp, isNot(contains('\nRow {')),
          reason: 'la fila va sostituita, non affiancata');
      expect(cp, contains('parent ? parent.width'),
          reason: 'un Flow senza larghezza non va a capo da nessuna parte');
    });

    test('e il ripiego non è più una percentuale muta', () {
      final vs = _trova('minerva-shell/settings/ValueSlider.qml')
          .codiceVivo();
      expect(vs, contains('case "percento":'),
          reason: 'la percentuale dev\'essere un caso dichiarato come gli '
              'altri, non il posto dove finisce ciò che non si è capito');
      expect(vs, contains('unità sconosciuta'),
          reason: 'se un\'unità non esiste lo si deve sentire: era muto, e '
              'due cursori hanno mentito per mesi');
    });
});
}

// Ogni impostazione che la shell legge deve avere un valore di fabbrica.
//
// ── Perché serve una prova, e non la buona volontà ─────────────────────────
//
// `settings_api.dart` scrive in cima a sé stesso la regola: il file delle
// preferenze si fonde con `defaultSettings()`, e una chiave che lì non c'è
// semplicemente non esiste. La shell allora la legge col proprio ripiego —
// `Core.Ipc.get("dock.iconSize", 48)` — e tutto sembra funzionare.
//
// Sembra. Perché quel ripiego è una seconda verità, scritta in un altro file
// e da un'altra persona: il giorno che i due numeri non coincidono, la
// scrivania si comporta in un modo e le Impostazioni ne mostrano un altro. È
// già successo, ed è la ragione per cui esiste [[minerva-due-impostazioni]]:
// «non si agisce sui valori di ripiego».
//
// Il difetto vero però è un altro, e più subdolo: **una chiave senza valore di
// fabbrica non compare nel file delle impostazioni**. Chi apre
// `~/.config/minerva/settings.json` per capire cosa si può cambiare non la
// trova, e conclude che non si può cambiare.
//
// Il 18 agosto 2026 le chiavi senza valore di fabbrica erano quarantasei —
// tutta la dock compresa, cioè il pezzo di Minerva che si tocca di più dopo la
// barra. Nessun errore da nessuna parte.
//
// ── Cosa fa esattamente ────────────────────────────────────────────────────
//
// Raccoglie ogni `Ipc.get("...")` di ogni file QML, spacchetta l'albero di
// `defaultSettings()` in percorsi puntati, e pretende che il primo insieme
// stia dentro il secondo.

import 'dart:io';
import 'package:test/test.dart';

Directory _radice() {
  for (final base in ['.', '..', '../..']) {
    if (Directory('$base/minerva-shell').existsSync()) return Directory(base);
  }
  fail('non trovo minerva-shell/');
}

/// Le chiavi SCRITTE dal QML, e da quali file.
///
/// ── Perché non bastava guardare le letture ────────────────────────────────
///
/// Il 5 settembre 2026 ho scritto io stesso, durante una prova,
/// `shell.fontFamily`: una chiave che non esiste. Il demone l'ha accettata
/// senza fiatare — `_applyValue` creava i rami che non trovava — e da quel
/// momento stava nel file di Giacomo, non la leggeva nessuno, e niente da
/// nessuna parte lo diceva.
///
/// Adesso il demone la rifiuta, e questa prova trova prima chi prova a
/// scriverla: una scrittura rifiutata non dà errore all'utente, dà una
/// levetta che si muove e non cambia niente.
///
/// Si raccolgono le due strade: `setSetting("chiave", …)` e le chiavi delle
/// mappe passate a `setSettings({...})` — che sono scritte come
/// `"gruppo.chiave":` oppure `mappa["gruppo.chiave"] =`.
Map<String, Set<String>> _chiaviScritte() {
  final res = [
    RegExp(r'setSetting\(\s*"([^"]+)"'),
    RegExp(r'mappa\[\s*"([a-z][A-Za-z0-9]*\.[^"]+)"\s*\]\s*='),
    RegExp(r'"([a-z][A-Za-z0-9]*\.[A-Za-z0-9.]+)"\s*:'),
  ];
  final fuori = <String, Set<String>>{};
  final radice = _radice().path;
  for (final v in Directory('$radice/minerva-shell')
      .listSync(recursive: true, followLinks: false)) {
    if (v is! File || !v.path.endsWith('.qml')) continue;
    final testo = v
        .readAsLinesSync()
        .where((r) => !r.trimLeft().startsWith('//'))
        .join('\n');
    // La terza espressione prende anche le mappe che NON sono impostazioni
    // (i modelli dei `Repeater`, le opzioni dei selettori). Si tiene solo
    // quello che sta in un file che parla col demone.
    final scrive = testo.contains('setSettings(') || testo.contains('setSetting(');
    if (!scrive) continue;
    for (final re in res) {
      for (final m in re.allMatches(testo)) {
        final chiave = m.group(1)!;
        if (chiave.endsWith('.')) continue;
        fuori.putIfAbsent(chiave, () => <String>{}).add(
            v.path.replaceFirst('$radice/', ''));
      }
    }
  }
  return fuori;
}

/// Le chiavi lette dal QML, e da quali file.
Map<String, Set<String>> _chiaviLette() {
  final re = RegExp(r'Ipc\.get\(\s*"([^"]+)"');
  final fuori = <String, Set<String>>{};
  final radice = _radice().path;
  for (final v in Directory('$radice/minerva-shell')
      .listSync(recursive: true, followLinks: false)) {
    if (v is! File || !v.path.endsWith('.qml')) continue;
    for (final m in re.allMatches(v.readAsStringSync())) {
      final chiave = m.group(1)!;
      // Le chiavi COSTRUITE a pezzi — `Ipc.get("desktop.anim." + nome)` —
      // finiscono in questa lista con il punto in fondo. Non si possono
      // verificare da qui: il nome vero lo decide chi le legge, a tempo di
      // esecuzione. Se ne occupa chi le usa; questa prova non finge di saperlo.
      if (chiave.endsWith('.')) continue;
      fuori.putIfAbsent(chiave, () => <String>{}).add(
          v.path.replaceFirst('$radice/', ''));
    }
  }
  return fuori;
}

/// I percorsi puntati di `defaultSettings()`, spacchettando le mappe annidate.
///
/// Si legge il sorgente Dart invece di importare la classe per una ragione
/// sola: importarla vorrebbe dire che la prova e il codice concordano perché
/// sono lo stesso oggetto. Leggendo il testo, la prova può accorgersi anche di
/// una chiave scritta due volte o annidata dove non doveva.
Set<String> _valoriDiFabbrica() {
  final src = File('${_radice().path}/minervad/lib/core/settings_api.dart')
      .readAsStringSync();
  final inizio = src.indexOf('static Map<String, dynamic> defaultSettings()');
  expect(inizio, isNot(-1), reason: 'defaultSettings() non si trova più');

  var apre = src.indexOf('{', inizio);
  var livello = 0, fine = -1;
  for (var i = apre; i < src.length; i++) {
    if (src[i] == '{') livello++;
    if (src[i] == '}') {
      livello--;
      if (livello == 0) { fine = i; break; }
    }
  }
  expect(fine, isNot(-1), reason: 'defaultSettings() non si chiude');

  // Via i commenti: contengono graffe e apostrofi, e li conterebbe come
  // struttura. È lo stesso inganno di `porta_compositore_test`.
  final corpo = src
      .substring(apre, fine + 1)
      .replaceAll(RegExp(r'//[^\n]*'), '');

  final fuori = <String>{};
  final pila = <String?>[];
  String? sospeso;
  final tok = RegExp(r"'([^']*)'\s*:|(\{)|(\})");
  for (final m in tok.allMatches(corpo)) {
    if (m.group(1) != null) {
      sospeso = m.group(1);
      final percorso = [...pila.whereType<String>(), sospeso].join('.');
      fuori.add(percorso);
    } else if (m.group(2) != null) {
      pila.add(sospeso);
      sospeso = null;
    } else {
      if (pila.isNotEmpty) pila.removeLast();
      sospeso = null;
    }
  }
  return fuori;
}

void main() {
  test('ogni chiave letta dalla shell ha un valore di fabbrica', () {
    final lette = _chiaviLette();
    final fabbrica = _valoriDiFabbrica();

    // Se lo spacchettamento si rompesse, l'insieme sarebbe vuoto o quasi e la
    // prova direbbe che TUTTO manca — un rosso illeggibile invece di un
    // difetto. Meglio accorgersi qui che lo strumento non funziona più.
    expect(fabbrica.length, greaterThan(100),
        reason: 'lo spacchettamento di defaultSettings() non ha funzionato');
    expect(lette.length, greaterThan(50),
        reason: 'non ho trovato le chiamate a Ipc.get nel QML');

    final mancanti = lette.keys.where((k) => !fabbrica.contains(k)).toList()
      ..sort();

    expect(mancanti, isEmpty,
        reason: 'queste impostazioni si leggono e non esistono nel file:\n'
            '${mancanti.map((k) => '  $k  ←  ${lette[k]!.join(', ')}').join('\n')}\n'
            'Il ripiego scritto nel QML le fa sembrare funzionanti, ma non\n'
            'compaiono in settings.json e nessuno può trovarle.');
  });

  test('e ogni chiave SCRITTA dalla shell esiste davvero', () {
    final scritte = _chiaviScritte();
    final fabbrica = _valoriDiFabbrica();

    expect(scritte.length, greaterThan(20),
        reason: 'non ho trovato le scritture nel QML');

    final inventate = scritte.keys.where((k) => !fabbrica.contains(k)).toList()
      ..sort();

    expect(inventate, isEmpty,
        reason: 'queste impostazioni si scrivono e non esistono:\n'
            '${inventate.map((k) => '  $k  ←  ${scritte[k]!.join(', ')}').join('\n')}\n'
            'Il demone le rifiuta: la levetta si muove e non cambia niente.');
  });

  // ── E il verso opposto, che non c'era ──────────────────────────────────
  //
  // Questa prova guardava solo *shell-legge ⊆ fabbrica*. L'altro verso — una
  // chiave di fabbrica che NESSUNO legge — non lo sorvegliava niente, ed è il
  // motivo per cui il 5 settembre 2026 ce n'erano tre vive da mesi:
  //
  //   · `bar.opacity`          — zero occorrenze in tutto il progetto. La
  //                              trasparenza della barra ce l'ha già
  //                              `shell.membraneOpacity`.
  //   · `launcher.maxShown`    — «quante voci mostrare nel menu». Il pannello
  //                              le mostra tutte, e scorre.
  //   · `launcher.defaultView` — con scritto accanto che `'matrix'` avrebbe
  //                              dato «cerchi concentrici». Non esistono.
  //
  // È lo stesso difetto che `bar.position` ha avuto per mesi, e che il
  // commento accanto a lei condanna per iscritto: «una impostazione che
  // esiste, si può scrivere, e non fa niente — il tipo di bugia che nessun
  // errore segnala».
  //
  // Una chiave può essere letta da tre posti: il QML della shell, il demone,
  // oppure è stato interno che nessuno «legge» ma tutti scrivono. Il terzo
  // caso è un elenco corto e MOTIVATO: un elenco di eccezioni senza motivo è
  // un elenco che cresce finché la regola non vale più niente.
  test('e ogni chiave di fabbrica la legge qualcuno', () {
    final fabbrica = _valoriDiFabbrica();
    final radice = _radice().path;

    // Tutto il testo in cui una chiave può comparire: il QML della shell e il
    // Dart del demone.
    final buf = StringBuffer();
    for (final d in ['minerva-shell', 'minervad/lib']) {
      for (final v in Directory('$radice/$d')
          .listSync(recursive: true, followLinks: false)) {
        if (v is! File) continue;
        if (!v.path.endsWith('.qml') && !v.path.endsWith('.dart')) continue;
        if (v.path.endsWith('settings_api.dart')) continue;
        buf.write(v.readAsStringSync());
      }
    }
    final tutto = buf.toString();

    /// Stato che si scrive e non si legge mai, con il perché.
    const scusate = {
      'settings.lastSection':
          'la sezione aperta per ultima: la scrive il pannello e la rilegge '
          'il suo punto di ingresso, non il QML',
      'desktop.menuUsed':
          'ricorda che il menu del tasto destro è già stato usato, per non '
          'rispiegarlo: stato interno',
      'stile.libero':
          'la fotografia della scrivania prima di scegliere uno stile: la '
          'scrive e la rilegge `sections/Stile.qml`, come TESTO JSON',
    };

    final morte = <String>[];
    for (final k in fabbrica) {
      if (scusate.containsKey(k)) continue;
      // Un gruppo (`'bar'`, `'dock'`) non è una chiave da leggere: si guarda
      // solo l'ultimo pezzo di un percorso che ne ha almeno due.
      if (!k.contains('.')) continue;
      // Le chiavi si leggono col percorso intero (`Ipc.get("bar.position")`)
      // oppure prendendo il gruppo e poi il campo: si accetta l'uno o
      // l'altro, perché tutti e due sono modi veri di usarle.
      // Il percorso INTERO, fra virgolette. Accontentarsi dell'ultima
      // parola non sorveglierebbe niente: `opacity` compare in mezzo QML come
      // proprietà di Qt, e `bar.opacity` sarebbe passata per viva.
      final ultima = k.split('.').last;
      if (tutto.contains('"$k"') || tutto.contains("'$k'")) continue;
      // Il demone legge dentro la mappa: `_settings['bar']['position']` e
      // `['position']` da solo dopo aver preso il gruppo. Si accetta la forma
      // con le parentesi quadre, che è inequivocabile.
      if (tutto.contains("['$ultima']")) continue;
      morte.add(k);
    }
    morte.sort();

    expect(morte, isEmpty,
        reason: 'queste impostazioni esistono, si possono scrivere, e non le '
            'legge nessuno. O si collegano, o si tolgono, o si aggiungono '
            'alle eccezioni con il loro perché:\n  ${morte.join('\n  ')}');
  });
}

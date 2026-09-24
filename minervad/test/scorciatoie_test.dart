import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/scorciatoie.dart';

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
  // ── Si legge la SORGENTE, non il file generato ───────────────────────
  //
  // Fino al 2 settembre 2026 qui si leggeva `config/hypr/keybinds.conf` e si
  // cercava `global, quickshell:<nome>`, che è la lingua di Hyprland. Quel
  // file è sparito con la sessione Hyprland; la sorgente invece resta, e in
  // lingua nostra la stessa cosa si scrive `minerva: <nome>`.
  final sorgente =
      _trova('config/scorciatoie.minerva').readAsStringSync();
  final shell = _trova('minerva-shell/shell.qml').readAsStringSync();

  /// I nomi che la sorgente manda alla shell: `minerva: nome`.
  final chiamati = RegExp(r'minerva:\s*([\w-]+)')
      .allMatches(sorgente)
      .map((m) => m.group(1)!)
      .toSet();

  /// I nomi che la shell dichiara di saper ricevere.
  ///
  /// `Core.Scorciatoia` e non `GlobalShortcut`: dall'11 agosto 2026 la shell
  /// non nomina più Hyprland: quel tipo viene da `Quickshell.Hyprland`, e
  /// dichiararlo trentacinque volte in `shell.qml` voleva dire che cambiare
  /// compositore ne avrebbe toccati due di file invece di uno. Il guscio sta
  /// in `minerva-shell/core/Scorciatoia.qml` e tiene apposta gli stessi nomi
  /// (`name`, `onPressed`) — vedi `porta_compositore_test.dart`.
  ///
  /// Si accetta ancora anche il nome vecchio: questa prova deve poter dire
  /// «il tasto non farà niente» anche a chi scrive la forma di prima.
  final dichiarati = RegExp(
          r'(?:Core\.Scorciatoia|GlobalShortcut)\s*\{[^}]*?name:\s*"(\w+)"')
      .allMatches(shell)
      .map((m) => m.group(1)!)
      .toSet();

  group('scorciatoie: i due capi del filo', () {
    // Un `bind` verso un nome che la shell non conosce **non dà nessun
    // errore**. Hyprland manda il comando, non lo riceve nessuno, e il tasto
    // resta muto: è successo davvero con il touchpad, ed è la ragione per cui
    // questa prova esiste. Lo stesso vale al contrario — una `Scorciatoia`
    // senza bind è codice che non può scattare mai.
    test('i due elenchi non sono vuoti (è cambiata la forma dei file?)', () {
      expect(chiamati.length, greaterThan(15));
      expect(dichiarati.length, greaterThan(15));
    });

    test('ogni tasto legato trova qualcuno che lo ascolta', () {
      for (final nome in chiamati) {
        expect(dichiarati, contains(nome),
            reason: 'keybinds.conf manda "quickshell:$nome", e in shell.qml '
                'non c\'è nessuna Core.Scorciatoia con quel nome: il tasto '
                'non farà niente e non lo dirà a nessuno');
      }
    });

    test('nessuna scorciatoia della shell è irraggiungibile', () {
      for (final nome in dichiarati) {
        expect(chiamati, contains(nome),
            reason: 'shell.qml ascolta "$nome", che nessun bind manda: '
                'o manca il bind, o è codice morto');
      }
    });
  });

  // ── Nessuna combinazione dichiarata due volte ────────────────────────
  //
  // Hyprland, davanti a due `bind` sulla stessa combinazione, ne esegue UNO
  // e dell'altro non dice niente. Non è un errore di configurazione: è una
  // riga che sta nel file, compare nel promemoria delle scorciatoie, e non
  // fa niente.
  //
  // È successo davvero. `$mod CTRL` sulle frecce era insieme «restringi /
  // allarga la finestra» (riga 132) e «scrivania successiva / precedente»
  // (riga 185): due funzioni documentate, una sola viva. Trovato il 10
  // agosto 2026 contando `hyprctl binds`, non leggendo il file — leggendo
  // non si vede, perché le due coppie stanno a cinquanta righe di distanza
  // e sotto due titoli diversi.
  //
  // Si guarda la combinazione, non il tipo di bind: `bind` e `bindl` sullo
  // stesso tasto litigano esattamente allo stesso modo.
  group('scorciatoie: nessuna combinazione dichiarata due volte', () {
    /// `SUPER SHIFT` e `SHIFT SUPER` sono la stessa cosa: si ordinano.
    String normalizza(String modificatori, String tasto) {
      final mods = modificatori
          .replaceAll(r'$mod', 'SUPER')
          .toUpperCase()
          .split(RegExp(r'\s+'))
          .where((m) => m.isNotEmpty)
          .toList()
        ..sort();
      return '${mods.join(' ')} + ${tasto.trim().toLowerCase()}';
    }

    // Le combinazioni si chiedono al lettore vero invece di rifare il
    // parsing: è lo stesso codice che usa il demone, e una guardia che legge
    // diversamente da chi legge sul serio può dire verde su un file rotto.
    final combinazioni = <String, List<String>>{};
    for (final sc in Scorciatoie.leggi(sorgente).tutte) {
      final pezzi = sc.tasti.trim().split(RegExp(r'\s+'));
      final tasto = pezzi.isEmpty ? '' : pezzi.last;
      final mods = pezzi.length > 1 ? pezzi.sublist(0, pezzi.length - 1) : [];
      // Toccare e tenere premuto sono due gesti diversi sullo stesso tasto
      // (Super toccato apre il menù, tenuto mostra i tasti): il gesto fa
      // parte della combinazione.
      final gesto = [
        for (final g in const ['tocco', 'tieni', 'al-rilascio'])
          if (sc.flag.contains(g)) g,
      ].join(' ');
      combinazioni
          .putIfAbsent(
              normalizza(mods.join(' '), tasto) + (gesto.isEmpty ? '' : ' [$gesto]'),
              () => [])
          .add(sc.azione.trim());
    }

    test('la sorgente si legge ancora (è cambiata la forma delle righe?)', () {
      expect(combinazioni.length, greaterThan(50));
    });

    test('ogni combinazione fa una cosa sola', () {
      final doppi = combinazioni.entries.where((e) => e.value.length > 1);
      expect(doppi, isEmpty,
          reason: doppi
              .map((e) => '${e.key} è legata a ${e.value.length} comandi '
                  'diversi (${e.value.join(" | ")}): il compositore ne '
                  'eseguirà uno solo e gli altri resteranno muti')
              .join('\n'));
    });
  });

  group('il tema e la scala del testo sono legati ovunque', () {
    // Sei punti d'ingresso, sei processi separati: tema, accento, trasparenze
    // e scala del testo vanno legati in tutti e sei, o l'ingrandimento vale
    // per alcune finestre e non per altre — e chi lo attiva pensa che sia
    // rotto a metà.
    //
    // `app.qml` sta per quattro: Calcolatrice, Editor, Anteprima e Attività
    // girano lì dentro, e il legame scritto una volta vale per tutte e
    // quattro — che è il primo vantaggio dell'ospite che si vede leggendo.
    //
    // ── Cosa si controlla adesso, e perché è cambiato ────────────────────
    //
    // Questa prova cercava `accessibility.textScale` dentro OGNI ingresso,
    // perché ogni ingresso aveva la sua copia dei blocchi di `Binding`: sette
    // legami × sei file. Il 3 settembre 2026 sono diventati un oggetto solo,
    // `theme/LegaTema.qml`, e le sei copie non ci sono più.
    //
    // La proprietà da difendere però è la stessa, e si è spezzata in due:
    // ogni ingresso deve USARE quell'oggetto, e quell'oggetto deve legare
    // tutto ciò che serve. Continuare a cercare la vecchia stringa avrebbe
    // dato rosso su un codice migliore — e cancellare la prova avrebbe tolto
    // la guardia proprio nel momento in cui il legame è stato spostato, cioè
    // quando serviva di più.
    const ingressi = [
      'minerva-shell/shell.qml',
      'minerva-shell/settings.qml',
      'minerva-shell/app.qml',
      'minerva-shell/filemanager.qml',
      'minerva-shell/viewer.qml',
      'minerva-shell/minervamedia.qml',
    ];

    for (final f in ingressi) {
      test('$f prende tema e dimensione del testo dagli altri', () {
        final testo = _trova(f).readAsStringSync();
        expect(testo, contains('Theme.LegaTema'),
            reason: 'questa finestra resterebbe col tema e il testo di '
                'fabbrica mentre le altre cambiano');
      });
    }

    test('e LegaTema lega davvero tutto quello che serve', () {
      final lega = _trova('minerva-shell/theme/LegaTema.qml').readAsStringSync();
      // Una per una, col nome dell'impostazione: se un legame sparisce, il
      // messaggio dice quale invece di dire «manca qualcosa».
      const legami = {
        'accessibility.textScale': 'il testo non si ingrandirebbe',
        'shell.scheme': 'il tema resterebbe quello di fabbrica',
        'shell.accent': 'l\'accento resterebbe ciano',
        'shell.tintaPersonale': 'il tema personale non avrebbe la sua tinta',
        'shell.versoPersonale': 'il tema personale sarebbe sempre scuro',
        'shell.scavalca': 'i colori messi a mano non arriverebbero',
        'shell.membraneOpacity': 'la barra avrebbe la trasparenza di fabbrica',
        'shell.windowOpacity': 'le finestre avrebbero la trasparenza di fabbrica',
      };
      for (final voce in legami.entries) {
        expect(lega, contains(voce.key), reason: voce.value);
      }
    });

    test('la velocità delle animazioni la lega solo la shell', () {
      // `Theme.Motion` governa i pannelli, la dock e i menu: vivono nella
      // shell e in nessun'altra finestra. Legarlo anche nelle applicazioni
      // non farebbe danno, ma direbbe una cosa falsa — che quelle durate le
      // usano loro.
      final shell = _trova('minerva-shell/shell.qml').readAsStringSync();
      expect(shell, contains('animazioni: true'),
          reason: 'senza, spegnere le animazioni non toccherebbe i pannelli: '
              'è il difetto segnalato il 19 agosto 2026');
      for (final f in ingressi.where((f) => !f.endsWith('shell.qml'))) {
        expect(_trova(f).readAsStringSync(), isNot(contains('animazioni: true')),
            reason: '$f dichiarerebbe di animare quello che non anima');
      }
    });
  });
}

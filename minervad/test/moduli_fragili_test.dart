import 'dart:io';

import 'package:test/test.dart';

/// Le tre cartelle condivise — `theme`, `core`, `ui` — non possono nominare un
/// modulo Qt che potrebbe non essere installato.
///
/// ## Il guasto che ha scritto questa prova
///
/// Il 26 agosto 2026, sera. Un `pacman -Rns plasma kde-applications` porta via
/// 211 pacchetti, e fra questi `qt6-multimedia`, che era entrato in casa come
/// dipendenza di KDE. Da quel momento il computer **non arriva più alla
/// schermata di accesso**: schermo nero, e greetd che ci riprova cinque volte
/// prima di arrendersi.
///
/// Il log del greeter, `/var/log/minerva-greeter/schermata.log`:
///
/// ```
/// ERROR: Failed to load configuration
/// ERROR:   caused by @greeter.qml[47:13]: Type Accesso.Greeter unavailable
/// ERROR:   caused by @greeter/Greeter.qml[956:17]: Type Ui.Icon unavailable
/// ERROR:   caused by @ui/Icon.qml[-1:-1]: Type Apps unavailable
/// ERROR:   caused by @core/Apps.qml[-1:-1]: Type Compositore unavailable
/// ERROR:      … altri sei anelli …
/// ERROR:   caused by @core/Overlays.qml[-1:-1]: Type Sounds unavailable
/// ERROR:   caused by @core/Sounds.qml[4:1]: module "QtMultimedia" is not installed
/// ```
///
/// Undici anelli fra un'icona e il motore dei suoni. Il meccanismo è questo:
/// `ui/Icon.qml` importa la **cartella** `"../core"`, e risolvere una cartella
/// vuol dire compilare tutti i tipi che il suo `qmldir` dichiara. Basta che
/// **uno solo** non compili perché l'intera cartella diventi indisponibile a
/// chiunque — al greeter, alla shell, a ogni app.
///
/// Quindi il costo di un `import` sbagliato non è la funzione che si perde: è
/// tutto. E un modulo che manca **non dà un avviso**: dà uno schermo nero e
/// un'ora di terminale d'emergenza.
///
/// ## Cosa fare quando questa prova diventa rossa
///
/// Non togliere il modulo dall'elenco qui sotto. Sposta il codice che lo usa
/// in un file dentro una **sottocartella** — `core/suoni/Campioni.qml` è
/// l'esempio — e caricalo con un `Loader { source: "…" }`, cioè per indirizzo
/// e non con `sourceComponent`. Un componente scritto in linea si compila
/// insieme al file che lo contiene, quindi resta avido anche se sembra pigro:
/// era esattamente il caso di `Sounds.qml` prima del 26 agosto.
///
/// Le sottocartelle non sono nominate dal `qmldir` della cartella madre, e
/// `import "../core"` non ci entra. Se il modulo manca, fallisce quel
/// `Loader` e nient'altro.
Directory _cartella(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final d = Directory('${dir.path}/$relativo');
    if (d.existsSync()) return d;
    dir = dir.parent;
  }
  fail('non trovo la cartella $relativo');
}

/// Gli `import` veri, senza quelli citati in un commento — questo file stesso
/// ne nomina parecchi spiegando perché non si scrivono.
List<String> _moduliImportati(String qml) {
  final fuori = <String>[];
  for (final riga in qml.split('\n')) {
    final r = riga.trimLeft();
    if (r.startsWith('//')) continue;
    if (!r.startsWith('import ')) continue;
    final quale = r.substring(7).trim().split(RegExp(r'\s')).first;
    // `import "../core" as Core` — una cartella, non un modulo.
    if (quale.startsWith('"') || quale.startsWith("'")) continue;
    fuori.add(quale);
  }
  return fuori;
}

void main() {
  /// I moduli che ci sono per forza, perché li vuole `quickshell` stesso e
  /// senza di lui non c'è niente da avviare.
  ///
  /// `QtQuick`, `QtQml` e i loro sottomoduli stanno in `qt6-declarative`;
  /// `Quickshell.*` sta dentro il binario di quickshell. Se uno di questi
  /// manca, non è Minerva a non partire: è quickshell a non esistere.
  bool sicuro(String modulo) =>
      modulo == 'QtQml' ||
      modulo.startsWith('QtQml.') ||
      modulo == 'QtQuick' ||
      modulo.startsWith('QtQuick.') ||
      modulo == 'Quickshell' ||
      modulo.startsWith('Quickshell.');

  /// ── Nessuna eccezione, e questo è il punto ───────────────────────────
  ///
  /// Il 27 agosto 2026 qui c'era `core/Ipc.qml` con `QtWebSockets`: l'ultimo
  /// punto singolo di guasto rimasto: se quel pacchetto mancava, la schermata
  /// di accesso tornava nera come la sera prima.
  ///
  /// Non è stato isolato: è stato **tolto**. Il canale col demone è passato da
  /// `ws://127.0.0.1` a un socket Unix, che `Quickshell.Io/Socket` sa fare da
  /// solo — sta dentro il binario di quickshell, che è già obbligatorio. Con
  /// lui se n'è andata anche la porta TCP, che rispondeva a chiunque girasse
  /// sulla macchina.
  ///
  /// Se domani qualcuno ha bisogno di rimettere un'eccezione qui, si fermi
  /// prima e legga `core/suoni/Campioni.qml`: quasi sempre la risposta è un
  /// file in una sottocartella, non una riga in questa mappa.
  const eccezioni = <String, String>{};

  /// Le cartelle che il greeter e la shell attraversano per forza. `media/`
  /// non è qui di proposito: importa `QtMultimedia` e deve poterlo fare —
  /// se manca muore il lettore multimediale, che è il prezzo giusto.
  const condivise = ['theme', 'core', 'ui'];

  for (final nome in condivise) {
    test('«$nome» non nomina moduli che potrebbero non esserci', () {
      final dir = _cartella('minerva-shell/$nome');
      final qmldir = File('${dir.path}/qmldir');
      expect(qmldir.existsSync(), isTrue,
          reason: 'a «$nome» manca il qmldir: senza, questa prova non sa '
              'quali file una cartella importata deve poter compilare.');

      // I file DICHIARATI: sono quelli che `import "…/$nome"` deve compilare.
      // Le sottocartelle non compaiono qui, ed è precisamente il punto.
      final dichiarati = qmldir
          .readAsLinesSync()
          .map((r) => r.trim())
          .where((r) => r.isNotEmpty && !r.startsWith('#'))
          .map((r) => r.split(RegExp(r'\s+')).last)
          .where((r) => r.endsWith('.qml'))
          .toList();

      expect(dichiarati, isNotEmpty,
          reason: 'il qmldir di «$nome» non dichiara nessun .qml');

      final colpevoli = <String>[];
      for (final file in dichiarati) {
        final f = File('${dir.path}/$file');
        if (!f.existsSync()) {
          fail('«$nome/qmldir» dichiara $file, che non esiste. '
              'Una cartella con un qmldir che mente non si importa affatto.');
        }
        for (final modulo in _moduliImportati(f.readAsStringSync())) {
          if (sicuro(modulo)) continue;
          if (eccezioni['$nome/$file'] == modulo) continue;
          colpevoli.add('$nome/$file importa «$modulo»');
        }
      }

      expect(colpevoli, isEmpty,
          reason: 'Un modulo che manca qui non toglie una funzione: rende '
              'indisponibile TUTTA la cartella «$nome» a chiunque la importi, '
              'schermata di accesso compresa. Sposta il codice che lo usa in '
              'una sottocartella e caricalo con un Loader per indirizzo — '
              'vedi core/suoni/Campioni.qml. Trovati:\n  '
              '${colpevoli.join('\n  ')}');
    });
  }

  /// La prova che il rimedio è ancora al suo posto. Se qualcuno domani
  /// riportasse i campioni dentro `Sounds.qml` «per semplificare», questa
  /// riga glielo dice prima che glielo dica greetd.
  test('i suoni restano fuori dal qmldir di core', () {
    final campioni = File('${_cartella('minerva-shell/core/suoni').path}'
        '/Campioni.qml');
    expect(campioni.existsSync(), isTrue,
        reason: 'core/suoni/Campioni.qml è il posto dove QtMultimedia può '
            'essere nominato senza portare giù la schermata di accesso.');
    expect(campioni.readAsStringSync(), contains('import QtMultimedia'));

    final suoni =
        File('${_cartella('minerva-shell/core').path}/Sounds.qml');
    expect(suoni.readAsStringSync(), isNot(contains('import QtMultimedia')),
        reason: 'Sounds.qml è dichiarato in core/qmldir: un import qui vale '
            'uno schermo nero al prossimo pacchetto rimosso.');
    expect(suoni.readAsStringSync(), contains('suoni/Campioni.qml'),
        reason: 'il Loader deve caricare il file per INDIRIZZO. Un '
            'sourceComponent scritto in linea si compila insieme a Sounds.qml, '
            'quindi sarebbe pigro all\'esecuzione e avido alla compilazione — '
            'che è com\'era, e non è bastato.');
  });
}

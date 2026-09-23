import 'dart:io';

import 'package:test/test.dart';

/// Le sei app di Minerva disegnano **col processore**, non con la scheda video
/// (`QT_QUICK_BACKEND=software`, incluso da `scripts/minerva-ambiente-app`).
///
/// Il perché sta in quel file, con i numeri. Qui c'è il guardiano, e serve per
/// un motivo preciso: **senza scheda video `layer.enabled` e `QtQuick.Effects`
/// non danno errore — fanno SPARIRE l'oggetto.**
///
/// È successo davvero il 18 agosto 2026: il ritratto tondo nella pagina Utente
/// delle Impostazioni è scomparso, lasciando il nome e uno spazio vuoto. Zero
/// avvisi nel registro, zero errori a schermo. Le prove d'apertura di
/// `scripts/prove.sh` sono passate tutte, perché guardano solo che non ci
/// siano avvisi.
///
/// Chi domani scrive `layer.enabled: true` dentro il gestore file lo scopre
/// qui, e non fra tre mesi guardando una schermata in cui manca qualcosa.
///
/// Shell, blocco schermo e schermata di accesso restano sulla scheda video e
/// possono usare tutto: sono le cose più animate di Minerva, e non passano da
/// nessuno degli script qui sotto.
File _trova(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

Directory _cartella(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final d = Directory('${dir.path}/$relativo');
    if (d.existsSync()) return d;
    dir = dir.parent;
  }
  fail('non trovo la cartella $relativo');
}

/// Toglie i commenti, o il guardiano si scandalizzerebbe leggendo la
/// spiegazione del perché quelle righe non si scrivono più.
String _senzaCommenti(String qml) => qml
    .split('\n')
    .where((r) => !r.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  /// Le cartelle da cui le sei app pescano il loro QML: le loro, più le tre
  /// condivise. Ricavate dagli `import` dei sei punti d'ingresso.
  const cartelleApp = [
    'theme', 'core', 'ui',
    'files', 'settings', 'monitor', 'editor', 'viewer', 'calcolatrice', 'media',
    // Il Terminale (15 settembre 2026): disegna col Canvas, che è QPainter,
    // e vale la stessa regola di tutti — niente shader.
    'terminale',
    // `custodia` mancava, ed era un buco: la Custodia vive dentro `app.qml`
    // come la Calcolatrice e l'Editor, quindi disegna col processore esattamente
    // come loro — ma nessuno controllava che non usasse un effetto. Aggiunta il
    // 4 settembre 2026.
    'custodia',
  ];

  // I punti d'ingresso VIVI. Calcolatrice, Editor e Attività non hanno più il
  // proprio: vivono dentro `app.qml`, e provare i file vecchi voleva dire
  // controllare una strada che nessuno prende.
  const ingressi = [
    'app.qml', 'settings.qml',
    'viewer.qml', 'filemanager.qml', 'minervamedia.qml',
  ];

  const scriptApp = [
    'minerva-calcolatrice', 'minerva-editor', 'minerva-settings',
    'minerva-viewer', 'minerva-monitor', 'minerva-files', 'minerva-media',
    'minerva-terminale',
  ];

  /// Quello che senza scheda video non disegna, e non lo dice.
  final vietati = {
    'layer.enabled': 'l\'oggetto non viene disegnato affatto',
    'layer.effect': 'l\'effetto non esiste e l\'oggetto sparisce',
    'MultiEffect': 'è un programma per la GPU',
    'ShaderEffect': 'è un programma per la GPU',
    'QtQuick.Effects': 'tutto quel modulo è per la GPU',
  };

  // ── Il raggio che il processore non sa ridurre ─────────────────────────
  //
  // `Theme.Effects.radiusFull` vale **999**, ed è il modo di dire «a capsula»
  // in tutta la shell. Con la scheda video va bene dappertutto: il raggio
  // viene ridotto a metà del lato corto e la forma esce giusta.
  //
  // Col processore no. Il renderer software passa il raggio così com'è a
  // `QPainter`, che non lo riduce: su un rettangolo di sei pixel per ottanta
  // — un pollice di barra di scorrimento — quello che esce **non è una
  // capsula**, è una fila di piccole croci lungo tutta la barra.
  //
  // Trovato il 4 settembre 2026, un'ora dopo aver messo le barre di
  // scorrimento in mezza scrivania. Giacomo: «cosa sono tutti quei segno + in
  // impostazioni?». Erano i pollici.
  //
  // La regola non può essere «mai `radiusFull`»: sui pulsanti e sulle
  // pastiglie, che sono alti trenta pixel e più, è giusto e leggibile. La
  // regola è che **chi disegna una striscia sottile si calcola il raggio**.
  // ── Il renderer analitico vuole la GPU ─────────────────────────────────
  //
  // `Shape.CurveRenderer` è il renderer di Qt 6 che disegna i tracciati con
  // l'antialiasing calcolato invece che con i triangoli. È bello e vuole una
  // scheda video. La shell e le app girano col processore.
  //
  // Il sintomo non è «disegna male»: è che lascia **i pixel di oggetti che non
  // esistono più**. Riprodotto il 5 settembre 2026 cambiando tema di icone e
  // poi sezione nelle Impostazioni: un «+» bianco sospeso in mezzo alla
  // pagina, dov'era il pallino «un colore tuo» della pagina di prima. Immune a
  // qualunque ridisegno; chiudendo e riaprendo la finestra spariva, che è il
  // modo lungo per dire che erano pixel e non oggetti.
  //
  // Giacomo, quel giorno: «compaiono tutti quei segni + sovrapposti […] non mi
  // fa cambiare sezione, opzione specifica o chiudere impostazioni».
  //
  // `blocco/` e `greeter/` sono esentati: girano CON la scheda video, e il
  // test più sotto sorveglia che continuino a farlo.
  group('il renderer dei tracciati', () {
    test('nessuno usa il CurveRenderer dove si disegna col processore', () {
      const conGpu = ['blocco', 'greeter'];
      final colpe = <String>[];

      for (final v in _cartella('minerva-shell')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final nome = v.path.split('minerva-shell/').last;
        if (conGpu.any((c) => nome.startsWith('$c/'))) continue;
        if (_senzaCommenti(v.readAsStringSync()).contains('Shape.CurveRenderer')) {
          colpe.add(nome);
        }
      }

      expect(colpe, isEmpty,
          reason: 'col renderer software questi lasciano sullo schermo i pixel '
              'di oggetti distrutti — si usa `Shape.GeometryRenderer`\n'
              '${colpe.join('\n')}');
    });
  });

  // ── Nascondere una Shape non ridipinge la sua area ─────────────────────
  //
  // Col renderer software, `visible: false` su una `Shape` lascia i suoi pixel
  // sullo schermo. Uno solo non si nota; passando alle icone del tema se ne
  // nascondono **centinaia in un colpo**, e quello che resta è una scaletta di
  // trattini a mezz'aria che sparisce solo chiudendo la finestra.
  //
  // Giacomo l'ha segnalata tre volte, il 4 e il 5 settembre 2026: «cosa sono
  // tutti quei segno + in impostazioni?», «i segni + ci sono ancora», «tutti i
  // segni + ci sono ancora». Le prime due volte avevo corretto altro — il
  // renderer analitico (che era il BLOCCO) e il pollice della barra di
  // scorrimento (che era un secondo artefatto, vero anche lui).
  //
  // Isolato per bisezione: sette azioni una per volta — cambio icone nei due
  // versi, cambio tema, cambio sezione, cambio accento — misurando i pixel
  // chiari comparsi nella fascia della barra del titolo, dove non deve
  // comparire mai niente. L'artefatto compariva **solo** passando a
  // «classiche», l'unico momento in cui tante Shape spariscono insieme.
  //
  // La cura è non nasconderla: un tracciato VUOTO è un cambio di contenuto, e
  // quello Qt lo ridipinge.
  group('le Shape non si nascondono', () {
    test('l\'icona svuota il tracciato invece di sparire', () {
      final t = _senzaCommenti(
          _trova('minerva-shell/ui/Icon.qml').readAsStringSync());
      final i = t.indexOf('Shape {');
      expect(i, greaterThan(0), reason: 'la Shape di `Icon.qml` non si trova');
      final corpo = t.substring(i, i + 400);
      expect(corpo, isNot(contains('visible: !icon.classic')),
          reason: 'nascondere la Shape lascia i suoi pixel sullo schermo: '
              'si svuota il tracciato');
      expect(t, contains('icon.classic ? "" : icon._path'),
          reason: 'con le icone del tema il tracciato è vuoto, non nascosto');
    });
  });

  group('capsule sottili', () {
    test('la barra di scorrimento calcola il raggio dalla propria misura', () {
      final testo = _senzaCommenti(
          _trova('minerva-shell/ui/Scorrimento.qml').readAsStringSync());
      expect(testo, isNot(contains('radiusFull')),
          reason: 'il pollice è largo sei pixel: con 999 il renderer software '
              'lo disegna a scalini, e sullo schermo si vede una scaletta di '
              'piccole croci al posto della barra');
      expect(testo, contains('Math.min(width, height) / 2'),
          reason: 'metà del lato corto è la stessa forma, detta in un modo '
              'che regge a qualunque misura');
    });
  });

  group('quello che le sei app non possono usare', () {
    test('niente effetti da scheda video nelle cartelle delle app', () {
      final colpe = <String>[];
      for (final c in cartelleApp) {
        for (final f in _cartella('minerva-shell/$c')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.qml'))) {
          final testo = _senzaCommenti(f.readAsStringSync());
          for (final v in vietati.entries) {
            if (testo.contains(v.key)) {
              colpe.add('${f.path.split('minerva-shell/').last}: '
                  '«${v.key}» — ${v.value}');
            }
          }
        }
      }
      expect(colpe, isEmpty,
          reason: 'queste righe non danno errore: fanno sparire l\'oggetto\n'
              '${colpe.join('\n')}');
    });

    test('e nemmeno nei sei punti d\'ingresso', () {
      for (final f in ingressi) {
        final testo = _senzaCommenti(
            _trova('minerva-shell/$f').readAsStringSync());
        for (final v in vietati.keys) {
          expect(testo.contains(v), isFalse, reason: '$f usa «$v»');
        }
      }
    });
  });

  // ── Chi avvia davvero il processo ──────────────────────────────────────
  //
  // I tre script delle app ospitate non avviano più niente da soli: passano
  // tutti da `scripts/minerva-ospite`, dove la stessa manovra è scritta una
  // volta per tutte e tre.
  //
  // Quindi le due prove qui sotto seguono l'indirezione invece di leggere il
  // file che l'utente lancia. Cercare la riga nel posto sbagliato darebbe
  // rosso su codice giusto, ed è già successo in questo progetto con la
  // guardia sull'ordine dei piani del compositore: una prova che conta una
  // cosa diversa da quella che dice di controllare è peggio di nessuna prova.
  String chiAvvia(String script) {
    final testo = _trova('scripts/$script').readAsStringSync();
    if (!testo.contains('scripts/minerva-ospite')) return testo;
    return _trova('scripts/minerva-ospite').readAsStringSync();
  }

  group('l\'ambiente arriva davvero alle app', () {
    test('tutti gli script includono minerva-ambiente-app', () {
      for (final s in scriptApp) {
        expect(chiAvvia(s), contains('minerva-ambiente-app'),
            reason: '$s avvia l\'app sulla scheda video: pagherebbe da sola '
                'i 38 MB che tutte le altre non pagano più');
      }
    });

    test('e lo includono PRIMA di avviare il processo', () {
      // Dopo l'`exec` non si esegue più niente: la riga ci sarebbe, il
      // guardiano qui sopra sarebbe contento, e la variabile non arriverebbe
      // mai a Qt.
      for (final s in scriptApp) {
        final testo = chiAvvia(s);
        final inclusione = testo.indexOf('. "\$ROOT/scripts/minerva-ambiente-app"');
        final avvio = testo.indexOf('exec qs -d');
        expect(inclusione, greaterThan(0), reason: s);
        expect(avvio, greaterThan(0), reason: s);
        expect(inclusione, lessThan(avvio),
            reason: '$s include l\'ambiente dopo aver già avviato il processo');
      }
    });

    test('la variabile è quella giusta', () {
      final amb = _trova('scripts/minerva-ambiente-app').readAsStringSync();
      expect(amb, contains('QT_QUICK_BACKEND=software'));
      expect(amb, contains('export QT_QUICK_BACKEND'),
          reason: 'senza export la variabile resta nello script e non arriva '
              'al processo che disegna');
    });
  });

  // ── Le misure non si animano ─────────────────────────────────────────
  //
  // Col renderer software Qt ridipinge solo cio' che dichiara sporco. Una
  // cosa che cambia MISURA a ogni fotogramma non dichiara sporco quello che
  // si lascia dietro: restano righe di pixel che nessuno cancella piu'.
  //
  // Giacomo, 5 settembre 2026: «vedo un difetto estetico in impostazioni
  // […] e' pieno di artefatti». La ricetta era «Alimentazione, scorri,
  // Audio», e sotto c'erano quattro riempimenti animati a virgola: il
  // cursore del volume, la barra della carica, il conto alla rovescia della
  // guardia e la barretta di selezione della colonna.
  //
  // La regola vale nelle IMPOSTAZIONI, che e' una finestra ferma dove un
  // residuo resta li' finche' non si chiude. La barra e la dock si
  // ridisegnano di continuo e non hanno lo stesso problema: non si toccano
  // per simmetria.
  group('nelle Impostazioni le misure non si animano', () {
    test('nessun «Behavior on width/height» sotto settings/', () {
      final radice = _trova('minerva-shell/settings/qmldir').parent.path;
      final colpe = <String>[];
      for (final f in Directory(radice)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final righe = f.readAsLinesSync();
        for (var i = 0; i < righe.length; i++) {
          final r = righe[i].trim();
          if (r.startsWith('//')) continue;
          if (RegExp(r'^Behavior\s+on\s+(width|height|implicitWidth'
                  r'|implicitHeight)\b')
              .hasMatch(r)) {
            colpe.add('${f.path.split('settings/').last}:${i + 1}  $r');
          }
        }
      }
      expect(colpe, isEmpty,
          reason: 'una misura animata lascia i pixel di ogni fotogramma:\n  '
              '${colpe.join('\n  ')}');
    });

    test('e il cursore a barra piena ha la larghezza a pixel interi', () {
      final t = _senzaCommenti(
          _trova('minerva-shell/ui/Slider.qml').readAsStringSync());
      expect(t, contains('Math.round('),
          reason: 'una larghezza a virgola lascia una riga di pixel che '
              'nessuno ridipinge');
      expect(t, isNot(contains('Behavior on width')),
          reason: 'e la larghezza non si anima');
    });

    test('e la finestra sa ridipingersi tutta', () {
      // Tolte le quattro cause, il residuo compariva ancora al primo avvio
      // dopo una modifica — cioe' quando qualche fotogramma salta. Il conto
      // dello sporco lo tiene Qt e non e' nostro: si toglie l'occasione
      // ridipingendo tutto quando la finestra cambia da cima a fondo.
      final t = _senzaCommenti(
          _trova('minerva-shell/settings/System.qml').readAsStringSync());
      expect(t, contains('function ridipingiTutto()'));
      expect(t, contains('Qt.callLater(settings.ridipingiTutto)'),
          reason: 'si ridipinge DOPO che la pagina nuova si e\' disposta: '
              'prima non servirebbe a niente');
    });
  });

  // ── Il trascinamento che si annullava da solo ────────────────────────
  //
  // Giacomo, 6 settembre 2026: «nel file manager non posso trascinare i file
  // come un qualsiasi file manager».
  //
  // Tutti i pezzi c'erano, e al compositore non arrivava niente. Il motivo era
  // in due righe:
  //
  //     pane.trascinando = true;
  //     pane.trascinando = false;   // «tanto la riga sopra non torna»
  //
  // Accanto stava scritto che `Drag.active` fa partire un ciclo di eventi suo.
  // Non e' vero, e l'ha detto solo la misura: le due righe si eseguono nello
  // stesso istante, e lo spegnimento annullava il gesto un battito dopo
  // averlo acceso. Il commento sbagliato era piu' convincente del codice.
  group('il trascinamento si accende e basta', () {
    test('nessuno spegne Drag.active nella riga dopo averlo acceso', () {
      final colpe = <String>[];
      for (final via in [
        'minerva-shell/files/Pane.qml',
        'minerva-shell/menu/DesktopIcons.qml'
      ]) {
        final righe = _trova(via).readAsLinesSync();
        for (var i = 0; i + 1 < righe.length; i++) {
          final a = righe[i].trim();
          final b = righe[i + 1].trim();
          if (RegExp(r'trascinando = true;$').hasMatch(a) &&
              RegExp(r'trascinando = false;').hasMatch(b)) {
            colpe.add('${via.split('/').last}:${i + 1}');
          }
        }
      }
      expect(colpe, isEmpty,
          reason: 'si spegne al rilascio o quando il gesto viene rubato, non '
              'un\'istruzione dopo averlo acceso:\n  ${colpe.join('\n  ')}');
    });

    test('e non lo spegne chi PERDE LA PRESA', () {
      // Appena il trascinamento di sistema parte, Qt toglie la presa del
      // mouse alla `MouseArea`: quella perdita le arriva come `onCanceled`,
      // uguale a un'interruzione. Spegnere il gesto li' lo ANNULLA un istante
      // dopo che e' partito — misurato il 7 settembre 2026, due righe di fila
      // nel registro: «acceso», «ANNULLATO -> spengo».
      //
      // L'unico che sa quando il gesto e' finito davvero e'
      // `Drag.onDragFinished`.
      for (final via in [
        'minerva-shell/files/Pane.qml',
        'minerva-shell/menu/DesktopIcons.qml'
      ]) {
        final t = _senzaCommenti(_trova(via).readAsStringSync());
        expect(t, contains('Drag.onDragFinished'),
            reason: '$via: senza, il gesto o si annulla subito o resta acceso '
                'per sempre');
      }
      // E `onCanceled` non deve spegnerlo a scatola chiusa.
      final pane = _senzaCommenti(
          _trova('minerva-shell/files/Pane.qml').readAsStringSync());
      expect(pane, isNot(contains('onCanceled: pane.trascinando = false')),
          reason: 'perdere la presa non vuol dire che il gesto e\' finito');
    });

    test('e c\'e\' chi lo spegne, al posto giusto', () {
      // Toglierlo e basta lascerebbe il gesto acceso per sempre.
      final pane = _trova('minerva-shell/files/Pane.qml').readAsStringSync();
      expect(pane, contains('function finisciTrascinamento()'));
      expect(pane, contains('onCanceled'));
      // Sulla scrivania lo spegne `Drag.onDragFinished`, non `lascia()`:
      // `lascia()` la chiamano il rilascio e l'annullamento della
      // `MouseArea`, e l'annullamento arriva proprio perche' il gesto di
      // sistema e' partito. Era la prova di ieri, e diceva il contrario —
      // scritta prima di sapere che perdere la presa non vuol dire aver
      // finito.
      final icone = _senzaCommenti(
          _trova('minerva-shell/menu/DesktopIcons.qml').readAsStringSync());
      final i = icone.indexOf('Drag.onDragFinished');
      expect(i, greaterThan(0));
      expect(icone.substring(i, i + 200), contains('trascinando = false'));
    });
  });

  // ── «Lancia e basta» non ha una risposta ─────────────────────────────
  //
  // `Core.Exec` ha due strade: `sh()` aspetta e chiama `onDone` con quello che
  // il comando ha scritto, `fireSh()` lancia e basta — usa un `Process` senza
  // raccoglitore di stdout e senza segnale.
  //
  // Chiamare `fireSh` su un `Exec` che ha un `onDone` vuol dire che quel
  // `onDone` **non arriva mai**, e non lo dice nessuno: il comando parte, fa
  // il suo, e la risposta la butta via un processo che non ascolta.
  //
  // Giacomo, 7 settembre 2026: «nemmeno ingrandire il puntatore». La misura
  // non si applicava né all'accesso né premendo il pulsante, e la catena
  // sembrava intera in tutti e due i posti: il tema si cercava davvero, e la
  // risposta finiva nel vuoto.
  group('chi aspetta una risposta non usa «lancia e basta»', () {
    test('nessun Exec con onDone viene lanciato con fire/fireSh', () {
      final radice = _trova('minerva-shell/shell.qml').parent;
      final colpe = <String>[];
      for (final f in radice
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final t = _senzaCommenti(f.readAsStringSync());
        // Il corpo di un `Exec` si prende contando le graffe, non con
        // un'espressione: la prima versione sconfinava nel blocco dopo e
        // accusava due innocenti — `action` in Bluetooth e in Rete, che un
        // `onDone` non ce l'hanno e vanno benissimo lanciate e basta.
        for (final m in RegExp(r'Exec\s*\{').allMatches(t)) {
          var i = m.end;
          var liv = 1;
          while (i < t.length && liv > 0) {
            if (t[i] == '{') liv++;
            if (t[i] == '}') liv--;
            i++;
          }
          final corpo = t.substring(m.end, i);
          if (!corpo.contains('onDone')) continue;
          final q = RegExp(r'id:\s*(\w+)').firstMatch(corpo);
          if (q == null) continue;
          final id = q.group(1)!;
          if (RegExp('\\b$id\\.fire(Sh|ShArgs)?\\(').hasMatch(t)) {
            colpe.add('${f.path.split('minerva-shell/').last}  ($id)');
          }
        }
      }
      expect(colpe, isEmpty,
          reason: 'qui si aspetta una risposta da un comando lanciato senza '
              'ascoltarla:\n  ${colpe.join('\n  ')}');
    });
  });

  group('quello che invece la scheda video ce l\'ha ancora', () {
    test('shell, blocco e accesso non includono l\'ambiente delle app', () {
      // Sono le cose più animate di Minerva e usano gli effetti: se un giorno
      // qualcuno le includesse «per simmetria», il ritratto della schermata di
      // accesso sparirebbe nello stesso identico modo silenzioso.
      // `minerva-session` era il ponte della sessione su Hyprland: sparito il
      // 2 settembre 2026. Al suo posto c'è quello del nostro compositore, che
      // ha lo stesso mestiere e la stessa ragione di restare sulla scheda
      // video — è lui che avvia la shell.
      for (final s in [
        'minerva-session-wayland',
        'minerva-blocca',
        'minerva-greetd'
      ]) {
        final f = _trova('scripts/$s');
        expect(f.readAsStringSync().contains('minerva-ambiente-app'), isFalse,
            reason: '$s non deve disegnare col processore');
      }
    });
  });
}

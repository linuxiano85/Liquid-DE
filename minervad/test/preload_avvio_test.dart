import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Un'app «tenuta pronta» ha il suo nome scritto in QUATTRO posti che nessun
/// compilatore mette a confronto:
///
///   1. `core/TenutaPronta.qml` se lo calcola da solo — `preload.<nome>` e
///      `MINERVA_<NOME>_DORMIENTE` — dal `nome` che il punto d'ingresso gli
///      passa;
///   2. `core/AppPronte.qml` li riscrive per esteso, perché all'avvio deve
///      lanciare uno script e passargli la variabile giusta;
///   3. `minervad/lib/core/settings_api.dart` dichiara la chiave, o
///      l'impostazione vive solo come valore di ripiego e la levetta nelle
///      Impostazioni non salva niente;
///   4. `settings/sections/Avvio.qml` mostra la levetta.
///
/// Sbagliarne uno non dà nessun errore. Se diverge la variabile d'ambiente,
/// l'app parte all'accesso **con la finestra aperta**: sei finestre in faccia
/// appena si entra. Se diverge la chiave, la levetta si accende e non succede
/// niente — mai. Sono i due guasti che questa prova esiste per rendere
/// rumorosi.
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
  final appPronte = _trova('minerva-shell/core/AppPronte.qml').codiceVivo();
  final impostazioni =
      _trova('minervad/lib/core/settings_api.dart').codiceVivo();
  final avvio =
      _trova('minerva-shell/settings/sections/Avvio.qml').codiceVivo();

  /// Le voci dell'elenco di `AppPronte`, lette dal file.
  final voci = RegExp(
    r'"chiave":\s*"([\w.]+)",\s*"variabile":\s*"(\w+)",\s*'
    r'\n\s*"script":\s*"([\w-]+)"',
  ).allMatches(appPronte).toList();

  group('le app che si possono tenere pronte', () {
    test('AppPronte ne elenca sei', () {
      // Il gestore file non c'è di proposito: lo avvia `config/hyprland.conf`,
      // che è l'unico posto da cui può partire abbastanza presto. Sei dal 15
      // settembre 2026, col Terminale.
      expect(voci.length, 6,
          reason: 'lette dall\'elenco di core/AppPronte.qml');
    });

    test('la variabile d\'ambiente è quella che l\'app si aspetta', () {
      // `TenutaPronta` la costruisce come MINERVA_<NOME MAIUSCOLO>_DORMIENTE
      // partendo dal `nome`, e il `nome` è l'ultimo pezzo della chiave.
      for (final v in voci) {
        final nome = v.group(1)!.split('.').last;
        expect(v.group(2), 'MINERVA_${nome.toUpperCase()}_DORMIENTE',
            reason: 'per «$nome»: se diverge, l\'app parte all\'accesso con la '
                'finestra aperta invece che nascosta');
      }
    });

    test('lo script di avvio esiste ed è eseguibile', () {
      for (final v in voci) {
        final f = _trova('scripts/${v.group(3)}');
        expect(f.existsSync(), isTrue, reason: v.group(3));
        // Il bit di esecuzione: senza, `execDetached` fallisce in silenzio.
        expect(FileStat.statSync(f.path).mode & 0x40, isNot(0),
            reason: '${v.group(3)} non è eseguibile');
      }
    });

    test('lo script sa farsi richiamare da vivo', () {
      // Un'app tenuta pronta è accesa e senza finestra: se il suo script non
      // le parla, è irraggiungibile, non pronta. Successo al primo giro con
      // `minerva-calcolatrice`, che aveva scritto in cima «se è già aperta la
      // si porta davanti» e non lo faceva nessuno.
      // Si segue l'indirezione: i tre script delle app ospitate delegano a
      // `scripts/minerva-ospite`, che quella manovra la fa per tutti e tre.
      // Cercare la riga nel file che l'utente lancia darebbe rosso su codice
      // giusto.
      for (final v in voci) {
        final script = v.group(3)!;
        var testo = _trova('scripts/$script').codiceVivo();
        if (testo.contains('scripts/minerva-ospite')) {
          testo = _trova('scripts/minerva-ospite').codiceVivo();
        }
        expect(testo, contains('qs ipc'),
            reason: '$script non chiede niente a un\'istanza già viva');
        expect(testo, contains('ping'), reason: script);
      }
    });

    test('la chiave è dichiarata nel demone', () {
      // Senza, l'impostazione vive solo come valore di ripiego: la levetta si
      // muove, il demone non la conosce, e al riavvio non è successo niente.
      for (final v in voci) {
        final nome = v.group(1)!.split('.').last;
        expect(impostazioni, contains("'$nome':"),
            reason: 'manca «${v.group(1)}» in settings_api.dart');
      }
      expect(impostazioni, contains("'preload': {"));
      expect(impostazioni, contains("'minuti':"));
    });

    test('e c\'è la levetta per accenderla', () {
      for (final v in voci) {
        expect(avvio, contains('"${v.group(1)}"'),
            reason: '«${v.group(1)}» non compare in Avvio.qml: si può '
                'accendere solo scrivendo a mano nel file delle impostazioni');
      }
      // Più il gestore file, che ha la chiave storica sua.
      expect(avvio, contains('"files.tieniAcceso"'));
    });
  });

  group('quello che il preload NON deve rompere', () {
    test('nessuna app esce più con Qt.quit() alla chiusura', () {
      // È il punto in cui il meccanismo si spegne tutto: se un punto
      // d'ingresso torna a `Qt.quit()`, quella app non si tiene pronta e non
      // lo dice a nessuno — sembra solo che l'impostazione non funzioni.
      // I punti d'ingresso VIVI, cioè quelli che gli script spediti aprono
      // davvero. `calcolatrice.qml`, `editor.qml` e `monitor.qml` non ci sono
      // più: quelle tre app vivono dentro `app.qml`, e provare i file vecchi
      // voleva dire essere verdi su una strada che non prende nessuno.
      const ingressi = [
        'app.qml',
        'settings.qml',
        'viewer.qml',
        'filemanager.qml',
        'minervamedia.qml',
      ];
      // `qualcosa.chiudi()` e non `pronta.chiudi()`: l'ospite ha quattro
      // `TenutaPronta` e le chiama per nome (`prontaEditor.chiudi()`).
      final passaPerChiudi = RegExp(r'onRequestClose:\s*[A-Za-z_][\w]*\.chiudi\(\)');
      for (final f in ingressi) {
        final testo = _trova('minerva-shell/$f').codiceVivo();
        expect(testo, contains('Core.TenutaPronta'), reason: f);
        expect(passaPerChiudi.hasMatch(testo), isTrue,
            reason: '$f non passa da TenutaPronta per chiudersi');
        expect(testo.contains('onRequestClose: Qt.quit()'), isFalse,
            reason: '$f esce invece di tenersi pronta');
        expect(testo.contains('onClosed: Qt.quit()'), isFalse, reason: f);
      }
    });

    test('la finestra non si nasconde da sola scrivendo su «dormiente»', () {
      // `dormiente` arriva LEGATA da `TenutaPronta`. Scriverci sopra da dentro
      // spezza il legame: la finestra si nasconde una volta e poi mai più, e
      // il difetto compare alla SECONDA chiusura — cioè non durante la prova.
      const finestre = [
        'files/FileManager.qml',
        'settings/System.qml',
        'monitor/Monitor.qml',
        'editor/Editor.qml',
        'viewer/Viewer.qml',
      ];
      for (final f in finestre) {
        final testo = _trova('minerva-shell/$f').codiceVivo();
        expect(RegExp(r'dormiente\s*=').hasMatch(testo), isFalse,
            reason: '$f scrive su «dormiente» e spezza il legame');
      }
    });
  });

  // ── Preparare non è aprire ────────────────────────────────────────────
  //
  // Il difetto che questo gruppo rende rumoroso è stato vero dal 18 al 23
  // agosto 2026, ed era il contrario esatto di quello che l'utente chiede:
  // accendendo «tienila pronta» per Calcolatrice, Editor o Attività, quelle
  // finestre si APRIVANO in faccia quattro secondi dopo l'accesso.
  //
  // La catena: `AppPronte` lancia lo script con `MINERVA_<APP>_DORMIENTE=1`;
  // lo script — da quando le tre app vivono dentro `app.qml` — quella
  // variabile non la guardava più e impostava `MINERVA_APP_APRI`; `app.qml`
  // chiamava `apri()`, che chiama `risveglia()`. `preparaDormiente()`
  // esisteva già e non la chiamava nessuno.
  //
  // Nessun pezzo era sbagliato da solo: si erano solo persi di vista.
  group('preparare un\'app non vuol dire aprirla', () {
    final ospite = _trova('scripts/minerva-ospite').codiceVivo();
    final appQml = _trova('minerva-shell/app.qml').codiceVivo();

    test('l\'ospite ha una strada per «preparala e basta»', () {
      expect(ospite, contains('MINERVA_APP_PREPARA'),
          reason: 'senza, il preload apre le finestre invece di prepararle');
      expect(ospite, contains('call app prepara'),
          reason: 'con l\'ospite già acceso si chiederebbe «apri»');
    });

    test('app.qml la ascolta, e «apri» ha la precedenza', () {
      expect(appQml, contains('MINERVA_APP_PREPARA'));
      expect(appQml, contains('app.preparaDormiente(prepara)'),
          reason: 'la variabile si legge ma non porta da nessuna parte');
    });

    test('preparare una finestra già costruita non la tocca', () {
      // Senza questa guardia, ricaricare la shell rifà il giro del preload e
      // `addormenta()` fa sparire l\'editor aperto sotto le mani di chi ci
      // sta scrivendo. Successo davvero, il 23 agosto.
      expect(appQml, contains('if (caricatore.active)'),
          reason: 'preparare una app aperta la farebbe sparire');
    });

    test('i tre script dell\'ospite passano tutti di lì', () {
      for (final s in ['minerva-calcolatrice', 'minerva-editor',
                       'minerva-monitor']) {
        final testo = _trova('scripts/$s').codiceVivo();
        expect(testo, contains('scripts/minerva-ospite'),
            reason: '$s si è scritto la sua strada invece di usare quella '
                'comune: è così che il difetto è nato');
        expect(RegExp(r'^DORMIENTE=MINERVA_\w+_DORMIENTE$', multiLine: true)
            .hasMatch(testo), isTrue,
            reason: '$s non dice quale variabile lo mette in preparazione');
      }
    });

    test('e la variabile che passano è quella che AppPronte manda', () {
      // Il quinto posto in cui lo stesso nome è scritto a mano. Gli altri
      // quattro li confronta il gruppo in cima a questo file.
      for (final v in voci) {
        final script = v.group(3)!;
        final variabile = v.group(2)!;
        final testo = _trova('scripts/$script').codiceVivo();
        if (!testo.contains('scripts/minerva-ospite')) continue;
        expect(testo, contains('DORMIENTE=$variabile'),
            reason: '$script aspetta una variabile diversa da quella che '
                'AppPronte gli manda ($variabile): il preload non parte');
      }
    });
  });
}

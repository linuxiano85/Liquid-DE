import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/plugins/plugin_manager.dart';

void main() {
  group('i plugin non possono impedire l\'accesso al computer', () {
    // Il 10 agosto 2026 questa funzione ha tenuto Giacomo fuori dalla schermata
    // di accesso. Creava la cartella dei plugin se non c'era; la cartella sta
    // dentro l'installazione (`/usr/local/share/minerva/plugins`), il greeter
    // gira come utente `greeter`, che lì non può scrivere, e l'eccezione
    // risaliva fino a `main` — che stampa ed esce con 1.
    //
    // Da fuori si vedeva questo: la schermata di accesso si disegnava intera e
    // l'elenco degli utenti era VUOTO. Nessun errore, nessun modo di entrare.
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('minerva-plugin'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('una cartella che non esiste non è un errore', () async {
      final pm = PluginManager(EventBus(), dir: '${tmp.path}/mai-esistita');
      await expectLater(pm.init(), completes);
    });

    test('e non viene nemmeno creata', () async {
      // Creare una cartella vuota a ogni avvio non è mai servito a niente: un
      // plugin esiste solo se qualcuno ce lo mette, e chi ce lo mette la
      // cartella la crea nel farlo. In compenso, provarci in un percorso di
      // sola lettura era abbastanza per uccidere il demone.
      final percorso = '${tmp.path}/niente-plugin';
      await PluginManager(EventBus(), dir: percorso).init();
      expect(Directory(percorso).existsSync(), isFalse);
    });

    test('una cartella dove non si può scrivere non ferma il demone', () async {
      final vietata = Directory('${tmp.path}/vietata')..createSync();
      Process.runSync('chmod', ['500', vietata.path]);
      addTearDown(() => Process.runSync('chmod', ['700', vietata.path]));
      final pm = PluginManager(EventBus(), dir: '${vietata.path}/dentro');
      await expectLater(pm.init(), completes);
    });

    test('una cartella vuota si attraversa senza lamentarsi', () async {
      final vuota = Directory('${tmp.path}/plugins')..createSync();
      await expectLater(PluginManager(EventBus(), dir: vuota.path).init(),
          completes);
    });

    test('un plugin col manifesto rotto non trascina giù gli altri', () async {
      final root = Directory('${tmp.path}/plugins')..createSync();
      Directory('${root.path}/rotto').createSync();
      File('${root.path}/rotto/plugin.json').writeAsStringSync('{ questo non è');
      await expectLater(PluginManager(EventBus(), dir: root.path).init(),
          completes);
    });
  });
}

// Il conto della memoria nel gestore attività.
//
// Nasce l'11 agosto 2026 da Giacomo: «il task manager supera i 200 MB, le app
// create da te sono spropositate». La finestra ne occupava davvero 42; il
// numero mostrato era l'RSS, che conta per intero dentro OGNI processo le
// librerie di Qt e Mesa — le stesse pagine, contate cinque volte in cinque
// righe diverse.
//
// Queste prove guardano il codice sorgente e non il comportamento a
// runtime: leggere `/proc` in una prova darebbe numeri diversi a ogni giro e
// non proverebbe niente. Quello che deve restare vero è la FORMA della
// misura, ed è ciò che si fissa qui.

import 'dart:io';
import 'package:test/test.dart';

String _sorgente(String relativo) {
  for (final base in ['.', '..', 'minervad']) {
    final f = File('$base/$relativo');
    if (f.existsSync()) return f.readAsStringSync();
  }
  fail('non trovo $relativo');
}

void main() {
  group('il demone misura in modo onesto', () {
    late String servizio;
    setUpAll(() => servizio = _sorgente('lib/services/process_service.dart'));

    test('legge il PSS, non solo RSS e condivisa', () {
      expect(servizio, contains('smaps_rollup'));
      expect(servizio, contains("riga.startsWith('Pss:')"));
      expect(servizio, contains("'memoriaEqua': pss"));
    });

    test('il PSS si chiede solo ai processi che contano', () {
      // `smaps_rollup` fa camminare al kernel le tabelle delle pagine: venti
      // millisecondi per quaranta processi. Chiederlo per tutti e duecento a
      // ogni giro renderebbe il gestore attività il consumo che misura.
      expect(servizio, contains('if (rss >= 12 * 1024 * 1024)'));
    });

    test('le letture di /proc dentro il ciclo sono sincrone', () {
      // Ottocento letture a giro: in `async` si paga l'andata e ritorno nel
      // ciclo degli eventi molto più della lettura, e /proc non può bloccare.
      // Misurato: 5,3% di CPU contro 3,6%.
      for (final file in ['stat', 'statm', 'smaps_rollup', 'cmdline']) {
        expect(servizio, contains("File('/proc/\$pid/$file').readAsStringSync()"),
            reason: '/proc/\$pid/$file deve leggersi in modo sincrono');
      }
      expect(servizio, isNot(contains("await File('/proc/\$pid/")),
          reason: 'nessuna lettura per processo deve restare asincrona');
    });
  });

  group('il gestore attività usa il numero equo', () {
    late String monitor;
    setUpAll(() => monitor = _sorgente('../minerva-shell/monitor/Monitor.qml'));

    test('mostra il PSS quando c\'è, la stima quando manca', () {
      expect(monitor, contains('r.equa > 0 ? r.equa : (r.privata + r.condivisa)'));
    });

    test('il PSS si somma, la condivisa no', () {
      // Il PSS è additivo per costruzione: ogni pagina è già divisa fra chi la
      // usa. La «condivisa» no, e per lei resta il massimo del gruppo.
      expect(monitor, contains('g.equa += equa;'));
      expect(monitor, contains('g.condivisa = Math.max('));
    });
  });

  group('le anteprime degli sfondi non si caricano da invisibili', () {
    late String aspetto;
    setUpAll(() =>
        aspetto = _sorgente('../minerva-shell/settings/sections/Appearance.qml'));

    test('si scandisce la cartella solo nella modalità che la mostra', () {
      // Prima: `Component.onCompleted: scan()` sempre. Nella cartella di
      // Giacomo, 311 fotografie elencate e 24 decodificate a 420×260 anche
      // stando sugli sfondi di Minerva. 49 MB per una griglia invisibile.
      expect(aspetto, contains('Component.onCompleted: if (page.mode === "image") scan()'));
      expect(aspetto, contains('onFolderChanged: if (page.mode === "image") scan()'));
    });

    test('e si rifà arrivando sulla modalità immagine', () {
      // Se non si rifacesse, la griglia resterebbe vuota per sempre: ed è il
      // modo più facile di trasformare un risparmio in un difetto.
      expect(aspetto, contains('page.mode === "image" && page.images.length === 0'));
    });

    test('ogni immagine pesante è legata alla visibilità del suo riquadro', () {
      expect(aspetto, contains('ownGrid.visible ? "file://" + ownThumb.path : ""'));
      expect(aspetto, contains('grid.visible ? "file://" + thumb.modelData : ""'));
      expect(aspetto, contains('page.mode === "folder" && Core.Wallpaper.current !== ""'));
    });
  });
}

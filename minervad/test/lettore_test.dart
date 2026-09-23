// Il lettore multimediale: quello che a schermo intero era sparito, e il
// volume che diceva il falso.
//
// ── I due difetti che questa prova esiste per non far tornare ─────────────
//
// **Uno.** A schermo intero il lettore non si comandava. Non era una scelta:
// `contenuto` ritaglia (`clip: true`) e a palco pieno `zonaVideo` prende tutta
// l'altezza, quindi tempo, barra di ricerca, play, volume e scaletta — che
// sono ancorati in catena SOTTO la zona video — finivano oltre il bordo senza
// che nessuno li avesse dichiarati invisibili. Su un film a tutto schermo
// restava raggiungibile **un pulsante da 34×24 pixel**, e nient'altro.
// E in tutto `media/` non c'era una sola scorciatoia da tastiera: niente
// spazio, niente frecce, niente Esc.
//
// **Due.** `AudioOutput` non aveva `volume`, quindi partiva all'unità; il
// cursore accanto al play nasceva a 70. All'avvio il numero sullo schermo e il
// suono nelle casse dicevano due cose diverse, e nessuno dei due si ricordava
// niente al riavvio.
//
// Nessuna delle due cose dà un errore. Sono assenze, e le assenze si
// sorvegliano solo così: guardando che le righe che le hanno riparate ci siano
// ancora.
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

/// Il testo senza commenti: qui si controlla che le cose siano SCRITTE nel
/// codice, e un commento che le nomina non è codice.
String _codice(String relativo) => _qml(relativo)
    .readAsLinesSync()
    .where((r) => !r.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('a schermo intero il lettore si comanda', () {
    late String testo;
    setUpAll(() => testo = _codice('media/MediaWindow.qml'));

    test('i comandi vivono DENTRO la zona video', () {
      // È l'unica cosa che a palco pieno esiste ancora: tutto il resto è
      // fuori dal ritaglio. Un comando messo altrove tornerebbe invisibile
      // senza che nessuno se ne accorga.
      final zona = testo.indexOf('id: zonaVideo');
      final comandi = testo.indexOf('id: comandiPieno');
      final sotto = testo.indexOf('id: colonnaInfo');
      expect(zona, greaterThan(0));
      expect(comandi, greaterThan(zona),
          reason: 'la barra dei comandi a schermo intero deve stare dentro '
              '`zonaVideo`');
      expect(comandi, lessThan(sotto),
          reason: 'se finisce sotto `zonaVideo` sparisce a schermo intero, '
              'che è esattamente il difetto');
    });

    test('e ci sono tutti: tempo, ricerca, play, volume, uscita', () {
      for (final c in const [
        'id: tempoPieno',
        'id: cercaPieno',
        'alternaRiproduzione()',
        'alternaMuto()',
        'alternaPalcoPieno()',
      ]) {
        expect(testo, contains(c),
            reason: 'manca «$c» dai comandi a schermo intero');
      }
    });

    test('compaiono al movimento e se ne vanno da soli', () {
      expect(testo, contains('svegliaComandi()'));
      expect(testo, contains('onPositionChanged: finestra.svegliaComandi()'),
          reason: 'senza il movimento del mouse non si riaccendono più');
      expect(testo, contains('sopraComandi.containsMouse'),
          reason: 'non devono spegnersi sotto il dito che li sta usando: è il '
              'difetto classico di queste barre');
    });

    test('la tastiera c\'è, e non ruba i tasti a chi sta scrivendo', () {
      for (final s in const [
        '"Space"', '"Right"', '"Left"', '"Up"', '"Down"', '"M"', '"F"',
        '"Escape"',
      ]) {
        expect(testo, contains(s), reason: 'manca la scorciatoia $s');
      }
      expect(testo, contains('_scrivendo'),
          reason: '`Shortcut` scatta dovunque sia il fuoco: senza guardia, '
              'premere spazio dentro il campo dell\'indirizzo metterebbe in '
              'pausa invece di scrivere uno spazio');
      expect(testo, contains('cursorPosition !== undefined'),
          reason: 'un campo di testo si riconosce da `cursorPosition`');
    });

    test('Esc esce dallo schermo intero, non chiude la finestra', () {
      final i = testo.indexOf('"Escape"');
      expect(i, greaterThan(0));
      final blocco = testo.substring(i, i + 220);
      expect(blocco, contains('alternaPalcoPieno'));
      expect(blocco, isNot(contains('requestClose')),
          reason: 'chiudere con Esc un lettore che sta suonando è il modo più '
              'veloce di perdere il posto in cui si era');
    });
  });

  group('il volume dice la verità', () {
    late String testo;
    setUpAll(() => testo = _codice('media/MediaWindow.qml'));

    test('l\'uscita audio prende il valore dello stato', () {
      final i = testo.indexOf('id: uscitaAudio');
      expect(i, greaterThan(0));
      final blocco = testo.substring(i, i + 160);
      expect(blocco, contains('volume:'),
          reason: 'senza questa riga l\'uscita sta all\'unità mentre il '
              'cursore mostra 70: due numeri diversi per la stessa cosa');
      expect(blocco, contains('finestra.muto'));
    });

    test('e si ricorda, insieme al muto e al disegno scelto', () {
      for (final k in const [
        'media.volume', 'media.muto', 'media.disegno', 'media.ripeti',
      ]) {
        expect(testo, contains(k), reason: 'la chiave $k non viene usata');
      }
    });

    test('le chiavi esistono nei valori di fabbrica', () {
      // Senza, `valori_di_fabbrica_test` diventa rosso — ma il modo in cui si
      // rompe è che l'impostazione si legge sempre col ripiego e non si salva
      // mai davvero.
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
      expect(f, isNotNull, reason: 'non trovo settings_api.dart');
      final t = f!.readAsStringSync();
      final i = t.indexOf("'media': {");
      expect(i, greaterThan(0), reason: 'manca il gruppo `media`');
      final blocco = t.substring(i, t.indexOf('},', i));
      for (final k in const [
        "'volume'", "'muto'", "'ripeti'", "'casuale'", "'disegno'",
      ]) {
        expect(blocco, contains(k));
      }
    });
  });

  group('tutto a portata di click', () {
    // Giacomo, 4 settembre 2026: «rendi tutti i passaggi a portata di click».
    //
    // Prima l'unico modo di aprire qualcosa che non fosse nella cartella dei
    // download era **scrivere il percorso a mano**, e lo stesso per il file da
    // tagliare. Il selettore di file di Minerva — `ui/Scegli.qml` — esisteva
    // già, scritto per la Custodia, e non lo usava nessun altro.
    late String testo;
    setUpAll(() => testo = _codice('media/MediaWindow.qml'));

    test('il lettore usa il selettore di file, non chiede di scrivere', () {
      expect(testo, contains('Ui.Scegli'),
          reason: 'il selettore esiste in `ui/`: riscriverne uno o chiedere di '
              'digitare un percorso sono le due strade sbagliate');
      for (final scopo in const ['"riproduci"', '"taglia"', '"cartella"']) {
        expect(testo, contains(scopo),
            reason: 'manca il ramo $scopo di `scegli()`');
      }
    });

    test('e c\'è un modo di aprire un file da dove non c\'è niente', () {
      // Il riquadro «Niente in riproduzione» diceva solo che non c'era
      // niente. Adesso da lì si apre qualcosa.
      expect(testo, contains('id: testoVuoto'));
      final i = testo.indexOf('id: testoVuoto');
      expect(testo.substring(i, i + 1400), contains('"riproduci"'),
          reason: 'dal vuoto si deve poter uscire con un clic');
    });
  });

  group('una casella di testo sola per tutte', () {
    test('il lettore non se ne scrive più quattro', () {
      // Dentro il solo `MediaWindow.qml` la stessa casella era scritta
      // quattro volte identica: riquadro incavato, altezza 38, raggio SM,
      // bordo che si accende col fuoco, un `Text` di segnaposto sopra un
      // `TextInput`. Quattro copie della stessa cosa non sono quattro
      // caselle: sono quattro caselle che un giorno saranno diverse.
      final testo = _codice('media/MediaWindow.qml');
      expect('Ui.Campo'.allMatches(testo).length, greaterThanOrEqualTo(4),
          reason: 'i quattro campi devono passare tutti dal componente');
      expect(testo, isNot(contains('TextInput {')),
          reason: 'un `TextInput` nudo dentro il lettore è la quinta copia '
              'che comincia');
    });

    test('e il componente esiste con quello che serve', () {
      final campo = _codice('ui/Campo.qml');
      for (final p in const [
        'property alias text', 'property string segnaposto',
        'signal accettato()', 'function prendiIlFuoco()',
      ]) {
        expect(campo, contains(p), reason: 'manca «$p» da `ui/Campo.qml`');
      }
    });
  });

  group('la scaletta non ripete per forza', () {
    late String testo;
    setUpAll(() => testo = _codice('media/MediaWindow.qml'));

    test('«ripeti uno» vale quando il brano finisce, non quando premi avanti',
        () {
      // Un tasto «avanti» che non va avanti sembra rotto. Chi arriva dalla
      // fine del brano passa da `_finito()`, che è l'unico posto dove
      // «ripeti uno» conta.
      expect(testo, contains('finestra._finito()'),
          reason: 'la fine del brano deve passare da `_finito()`');
      final i = testo.indexOf('function successivo()');
      final blocco = testo.substring(i, testo.indexOf('function _finito()'));
      expect(blocco, isNot(contains('"uno"')),
          reason: '«avanti» deve andare avanti anche con «ripeti uno»');
    });

    test('e non ripete più a caso lo stesso brano di fila', () {
      expect(testo, contains('_aCaso()'));
      final i = testo.indexOf('function _aCaso()');
      expect(testo.substring(i, i + 400), contains('i === ora'),
          reason: 'sentire due volte di fila lo stesso brano non sembra il '
              'caso, sembra un difetto');
    });
  });
}

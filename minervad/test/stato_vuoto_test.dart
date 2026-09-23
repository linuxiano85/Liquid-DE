import 'dart:io';

import 'package:test/test.dart';

/// «Non c'è niente da mostrare» si dice UNA volta sola.
///
/// ── Il difetto che ha fatto scrivere questa prova ─────────────────────────
///
/// Giacomo, cancellando tutti i file di una cartella, ha visto **due scritte
/// «cartella vuota» sovrapposte**. Nel gestore file c'erano davvero due
/// blocchi con la stessa condizione — `pane.shown.length === 0` — uno
/// ancorato al riquadro e uno dentro la `GridView`, con corpo del testo e
/// icona leggermente diversi: si disegnavano insieme, sfalsati.
///
/// ── Perché non se n'era accorto nessuno ───────────────────────────────────
///
/// Perché non è un errore: sono due oggetti validi, ognuno con una condizione
/// giusta. Nessun avviso, nessun binding rotto, nessuna prova rossa. Si vede
/// solo guardando lo schermo con una cartella vuota davanti — che è la
/// situazione in cui uno ci finisce dopo aver cancellato tutto, cioè quando
/// ha già altro per la testa.
///
/// La regola che questa prova sorveglia è più stretta del difetto: in un
/// pannello, **le cose che compaiono quando l'elenco è vuoto sono una**. Se un
/// giorno ne servissero due (una scritta e un pulsante, per dire), vanno messe
/// dentro lo stesso contenitore, che di condizione ne ha una.
File _trova(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

/// Le righe che sono codice: i commenti raccontano la storia e nominano le
/// cose che sono state tolte, e cercarli lì dentro renderebbe questa prova
/// rossa proprio perché il difetto è stato spiegato.
Iterable<String> _codice(String testo) => testo
    .split('\n')
    .where((r) => !r.trimLeft().startsWith('//'));

void main() {
  group('lo stato «vuoto» del gestore file', () {
    final pane = _trova('minerva-shell/files/Pane.qml').readAsStringSync();

    test('un solo blocco compare quando l\'elenco è vuoto', () {
      final quanti = _codice(pane)
          .where((r) => r.contains('visible:') &&
              r.contains('pane.shown.length === 0'))
          .toList();
      expect(quanti.length, 1,
          reason: 'due blocchi con la stessa condizione si disegnano insieme, '
              'e si vedono come due scritte sfalsate una sopra l\'altra:\n'
              '${quanti.join('\n')}');
    });

    test('e distingue le quattro ragioni per cui non c\'è niente', () {
      // Confonderle manda a cercare il problema dalla parte sbagliata: una
      // cartella che non si è potuta LEGGERE, mostrata come «vuota», fa
      // pensare che i file siano spariti; e un filtro che non trova niente,
      // mostrato come «vuota», fa pensare lo stesso su una cartella piena.
      for (final segno in [
        'pane.error !== ""',
        'pane.filter !== ""',
        'Files.inTrash(pane.path)',
        'Cartella vuota',
      ]) {
        expect(pane.contains(segno), isTrue,
            reason: 'manca il caso «$segno» dallo stato vuoto');
      }
    });

    test('«sola lettura» e «amministratore» non si vedono insieme', () {
      // Erano ancorati allo stesso punto — `contaRoba.right`, stesso margine —
      // e le condizioni si sovrapponevano: in modalità amministratore, dentro
      // una cartella non scrivibile, comparivano tutti e due e uno copriva
      // l'altro. Giacomo: «viene coperto dalla scritta amministratore e quindi
      // non si capisce cosa c'è scritto».
      //
      // Stessa famiglia delle due «cartella vuota»: due oggetti validi,
      // nessun errore, si vede solo guardando lo schermo.
      expect(pane, contains('visible: !pane.scrivibile && !pane.amministratore'),
          reason: '«sola lettura» deve sparire quando c\'è «amministratore»: '
              'sono ancorati allo stesso punto, e le due scritte dicono cose '
              'che non stanno insieme — «qui non puoi scrivere» e «qui adesso '
              'puoi».');
    });

    test('la cornice della griglia combacia col contenuto', () {
      // Era `anchors.margins: 3` contro un contenuto disposto a
      // `gridPadding` (8): la cornice sbordava di cinque pixel per lato, e in
      // griglia — dove la cella è larga il triplo dell'icona — si vedeva come
      // un rettangolo enorme attorno a un'icona piccola.
      expect(pane, contains('anchors.margins: cell.gridMode ? pane.gridPadding : 0'),
          reason: 'la cornice si allinea a `gridPadding`, che è lo stesso '
              'margine con cui sono disposti icona e nome');
    });

    test('il testo di un errore va a capo', () {
      // Il messaggio di un errore di lettura è una frase intera e può
      // contenere un percorso lungo: senza `wrapMode` esce dai bordi del
      // riquadro, e la parte che dice COSA non va è quella che si perde.
      final i = pane.indexOf('id: emptyState');
      expect(i, greaterThan(0), reason: 'non trovo il blocco emptyState');
      final blocco = pane.substring(i, i + 2600);
      expect(blocco, contains('wrapMode: Text.WordWrap'));
    });
  });
}

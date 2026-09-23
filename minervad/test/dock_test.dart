// La dock: quello che sapeva e non diceva.
//
// ── I difetti che questa prova esiste per non far tornare ─────────────────
//
// La dock funzionava, e nascondeva tre informazioni che aveva già in mano:
//
//  · **quante finestre**. La lineetta sotto l'icona diceva «sta girando» e
//    basta: due Chrome e sette Chrome avevano lo stesso identico segno. Il
//    numero era nel modello — `addresses` è l'elenco delle finestre con i loro
//    titoli — e non lo guardava nessuno.
//  · **quali finestre**. Col tasto destro c'era «riduci a icona», che le
//    riduceva tutte, e nessun modo di arrivare a quella che si voleva.
//  · **dove finiscono le app tenute e cominciano quelle solo aperte**. Le due
//    liste erano concatenate senza niente in mezzo.
//
// E si era rifatta a mano la targhetta del nome, uguale a `ui/ToolTipHint.qml`
// tranne per la cosa che conta: il **mezzo secondo di attesa**. Attraversando
// dodici icone per arrivare all'ultima se ne accendevano dodici in fila.
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

String _codice(String relativo) => _qml(relativo)
    .readAsLinesSync()
    .where((r) => !r.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  late String dock;
  setUpAll(() => dock = _codice('dock/Dock.qml'));

  group('la dock dice quello che sa', () {
    test('quante finestre, non solo che ce ne sono', () {
      expect(dock, contains('id: contatore'));
      expect(dock, contains('addresses.length'),
          reason: 'il numero è già nel modello: non serve chiederlo a nessuno');
      final i = dock.indexOf('id: contatore');
      expect(dock.substring(i, i + 500), contains('quante > 1'),
          reason: 'su una finestra sola un «1» è rumore: la lineetta lo dice '
              'già');
    });

    test('e quali sono, col loro titolo', () {
      // `addresses` porta `{address, title, minimized}` per ognuna. Il titolo
      // è l'unica cosa che distingue due finestre dello stesso programma, ed
      // è quello che sta scritto nella loro barra.
      expect(dock, contains('"vaiA:"'),
          reason: 'dal menu della dock si deve poter andare a UNA finestra');
      expect(dock, contains('Core.Windows.focus('));
      expect(dock, contains('Senza titolo'),
          reason: 'una finestra senza titolo deve comunque comparire, o '
              'l\'elenco ne salta una e nessuno capisce perché');
    });

    test('e dove finiscono le tenute e cominciano le aperte', () {
      expect(dock, contains('slot.index === dock.quanteFisse'),
          reason: 'senza separatore la dock sembra una fila sola che cambia '
              'da sé');
    });
  });

  group('la dock usa i pezzi di tutti', () {
    test('la targhetta è quella condivisa, col suo mezzo secondo', () {
      expect(dock, contains('Ui.ToolTipHint'),
          reason: 'quella rifatta a mano non aveva l\'attesa: passando sopra '
              'una fila di icone se ne accendeva una per icona');
      expect(dock, isNot(contains('id: slotLabel')),
          reason: 'la copia a mano va tolta, non lasciata accanto');
      expect(dock, contains('import "../ui" as Ui'));
    });
  });

  group('quello che NON si tocca', () {
    // Due cose faticose, ognuna col suo commento lungo nel file. Chi le
    // semplifica rimette un difetto che è già costato.
    test('l\'ingrandimento resta senza animazioni sulla larghezza', () {
      // Il commento in testa a `Dock.qml` racconta l'anello: la larghezza
      // dipende da quanto sono grandi le icone → la dock si ricentra → le
      // icone cambiano → si torna al principio. Con un'animazione di mezzo
      // sulla larghezza il giro non converge: oscilla.
      expect(dock, contains('readonly property real restWidth'),
          reason: 'la geometria a riposo è quella che rompe l\'anello');
      expect(dock, contains('magEased'),
          reason: 'l\'unica cosa animata dell\'ingrandimento è questa');
    });

    test('si trascinano solo le app tenute', () {
      // Le altre sono lì perché stanno girando: spostarle vorrebbe dire
      // promettere un ordine che sparisce alla prossima chiusura.
      expect(dock, contains('dock.quanteFisse'));
      expect(dock, contains('sogliaTrascina'));
    });
  });
}

import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Una conferma sola per volta, nel pannello dello spegnimento.
///
/// ── Il difetto ────────────────────────────────────────────────────────────
///
/// Giacomo, 2 settembre 2026: «se clicco si riavvia e mi chiede conferma, se
/// clicco su spegni rimangono 2 voci con la conferma quando invece dovrebbe
/// scomparire da riavvia e stare solo su spegni».
///
/// La causa: `awaitingConfirm` era una proprietà **del delegato**, quindi ogni
/// riga aveva la sua e nessuno azzerava quella delle altre. Non è pignoleria
/// di aspetto: davanti a due righe che chiedono conferma insieme non si sa più
/// quale si sta per confermare, e questa è la parte del pannello dove
/// sbagliare vuol dire spegnere il computer con del lavoro aperto.
///
/// ── Cosa sorveglia questa prova ───────────────────────────────────────────
///
/// Che lo stato sia **uno solo**, del pannello. Con una variabile sola il
/// difetto non si può ripresentare: chiedere conferma per una voce toglie la
/// conferma all'altra perché è la stessa variabile. Con una variabile per
/// riga torna, e nessun errore lo dice.
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
  group('lo spegnimento chiede una conferma per volta', () {
    final p =
        _trova('minerva-shell/spine/panels/PowerPanel.qml').codiceVivo();

    test('lo stato della conferma è uno solo, del pannello', () {
      expect(p, contains('property string inAttesa'),
          reason: 'lo stato sta sul pannello, non sulla riga');
      expect(p.contains('property bool awaitingConfirm: false'), isFalse,
          reason: 'se torna una proprietà MODIFICABILE per riga, tornano anche '
              'due conferme accese insieme: ogni riga si tiene la sua e '
              'nessuno azzera quella delle altre.');
    });

    test('la riga legge lo stato del pannello, non ne tiene uno suo', () {
      expect(p, contains('readonly property bool awaitingConfirm:'),
          reason: 'la riga DERIVA da `panel.inAttesa`');
      expect(p, contains('panel.inAttesa === action.modelData.id'));
    });

    test('la conferma scade, e si dimentica chiudendo il pannello', () {
      // Una voce lasciata «armata» e dimenticata è una voce che al prossimo
      // clic distratto spegne il computer. E riaprire il pannello trovandola
      // già accesa vorrebbe dire spegnerlo con un clic solo, senza averne
      // dati due.
      expect(p, contains('id: finestraConferma'));
      expect(p, contains('onVisibleChanged'),
          reason: 'chiudendo il pannello la conferma si azzera');
    });
  });
}

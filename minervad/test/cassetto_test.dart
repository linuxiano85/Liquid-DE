// Il Cassetto degli appunti sa cancellare: una voce con la crocetta, tutto
// con «Svuota». Le prove lo aprono e lo svuotano davvero, e la storia degli
// appunti vera (`~/.cache/cliphist/db`) è di chi sta lavorando.
//
// Il 24 settembre 2026 la prova annidata ha svuotato il Cassetto: senza
// l'archivio a parte avrebbe svuotato gli appunti di Giacomo.
import 'dart:io';

import 'package:test/test.dart';

Directory _radice() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (Directory('${dir.path}/minerva-shell').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/');
}

void main() {
  final radice = _radice();
  final prova = File('${radice.path}/compositore/prova-annidata.sh').readAsStringSync();
  final cassetto = File('${radice.path}/minerva-shell/menu/Cassetto.qml').readAsStringSync();

  test('la prova annidata ha il suo archivio degli appunti', () {
    expect(prova, matches(RegExp(r'^export CLIPHIST_DB_PATH="\$CONF_PROVA/', multiLine: true)),
        reason: 'senza, «Svuota» in prova svuota gli appunti veri');
  });

  test('e la sua cartella delle immagini', () {
    // La pulizia delle anteprime toglie i file che non sono più in elenco:
    // nella cartella della sessione vera toglierebbe i suoi.
    expect(cassetto, contains('MINERVA_PROVA'));
    expect(cassetto, contains('"-prova"'));
  });

  test('i numeri di cliphist passano come argomenti, mai dentro la riga', () {
    // Il numero viene dall'uscita di `cliphist`, cioè da fuori.
    // Una stringa seguita da `+ voce…` è un numero incollato in un comando.
    expect(cassetto, isNot(matches(RegExp(r'"\s*\+\s*(String\()?voce'))));
    expect(cassetto, contains(r'cliphist decode \"$1\"'));
  });
}

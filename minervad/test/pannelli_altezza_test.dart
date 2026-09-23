// Un pannello alto meno del suo contenuto taglia l'ultima riga.
//
// ── Il difetto ─────────────────────────────────────────────────────────────
//
// Giacomo, 2 settembre 2026: «controllare perché non si adatta al contenuto la
// sezione del desktop dedicata alla connessione trasmetti eccetera perché i 3
// tasti sotto sono a malapena visibili».
//
// `Spine.qml` dà a ogni pannello l'altezza che il pannello dichiara
// (`implicitPanelHeight`). `ControlPanel` la calcolava come
// `stack.implicitHeight` e basta — cioè la sola altezza dei figli della
// colonna, senza il `topMargin: space5` con cui la colonna è ancorata e senza
// niente da lasciare sotto. Quaranta pixel di meno, e quei quaranta pixel sono
// l'ultima fila di riquadri.
//
// Gli altri pannelli il conto lo facevano già. Questo è il difetto che si vede
// solo dove il contenuto arriva davvero in fondo, e nessuna prova lo prendeva
// perché non è un errore: sono due numeri validi che non tornano fra loro.
//
// ── Perché si legge il sorgente e non si misura ────────────────────────────
//
// Misurarlo vorrebbe dire aprire ogni pannello in una sessione e fotografarlo,
// che è la verifica giusta e si fa a mano. Questa prova serve a un'altra cosa:
// che il conto non torni a essere dimenticato in un pannello nuovo.
import 'dart:io';

import 'package:test/test.dart';

void main() {
  final dir = Directory('${Directory.current.parent.path}/minerva-shell/spine/panels');

  test('ogni pannello che si àncora con un margine lo conta nell\'altezza', () {
    expect(dir.existsSync(), isTrue, reason: 'manca ${dir.path}');

    final mancanti = <String>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.qml')) continue;
      final testo = f.readAsStringSync();
      if (!testo.contains('implicitPanelHeight')) continue;

      // Il conto dichiarato: da `implicitPanelHeight:` fino alla riga vuota.
      final i = testo.indexOf('implicitPanelHeight');
      final resto = testo.substring(i);
      final conto = resto.substring(0, resto.indexOf('\n\n'));

      // Se il conto è la sola `implicitHeight` di qualcosa, non può aver
      // tenuto conto di nessun margine: `implicitHeight` è l'altezza dei
      // figli e nient'altro.
      final soloFigli = RegExp(r'implicitPanelHeight:\s*\w+\.implicitHeight\s*$')
          .hasMatch(conto.trim());
      if (!soloFigli) continue;

      // …a meno che quel qualcosa non sia ancorato con un margine.
      if (testo.contains('anchors.topMargin')) {
        mancanti.add('${f.uri.pathSegments.last}: $conto');
      }
    }

    expect(mancanti, isEmpty,
        reason: 'questi pannelli si dichiarano alti quanto i loro figli, ma la '
            'colonna è ancorata con un margine in cima: nascono più corti del '
            'contenuto e l\'ultima riga resta tagliata\n  '
            '${mancanti.join("\n  ")}');
  });

  test('e il pannello di controllo somma i suoi due margini', () {
    final f = File('${dir.path}/ControlPanel.qml');
    final testo = f.readAsStringSync();
    expect(testo, contains('Theme.Effects.space5'));
    expect(testo, contains('Theme.Effects.space4'));
    final i = testo.indexOf('implicitPanelHeight');
    final conto = testo.substring(i, testo.indexOf('\n\n', i));
    expect(conto, contains('space5'),
        reason: 'il margine in cima non è nel conto');
    expect(conto, contains('space4'),
        reason: 'sotto l\'ultima fila non resta niente');
  });
}

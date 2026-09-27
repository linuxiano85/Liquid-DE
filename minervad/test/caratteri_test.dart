// Il carattere di Minerva è UNO, e sta scritto in due posti.
//
// ── Perché due posti, e perché è pericoloso ────────────────────────────────
//
// La shell disegna tutto quello che è Minerva (`theme/Typography.qml`), ma la
// barra del titolo dei programmi ESTERNI la disegna il compositore, in C, con
// Pango (`compositore/src/barra.c`). Sono due catene di disegno diverse e non
// c'è modo di farne una: una è QML, l'altra è cairo.
//
// Se le due nominano caratteri diversi, la stessa finestra ha il titolo in una
// faccia e il contenuto in un'altra. È il genere di stonatura che si nota
// senza saper dire cos'è — e nessuna prova la prenderebbe, perché sono due
// stringhe valide in due file che non si conoscono.
//
// ── E perché quei due e non altri ──────────────────────────────────────────
//
// Giacomo, 3 settembre 2026: «un sacco di gente sta dicendo che sembra vecchio
// già dalla sua creazione [...] dicono che ha un aspetto brutto e superato».
//
// Erano Rajdhani e Share Tech Mono: due caratteri belli, e insieme una DATA —
// la firma delle scrivanie Linux personalizzate del 2016-2021. `fontDisplay`
// compare in 468 punti, cioè È l'interfaccia, e tutto quello che ci si scrive
// dentro eredita quell'epoca.
//
// Questa prova non difende Adwaita Sans: difende che siano **lo stesso**, e
// che i pesi restino cinque cose diverse. Cambiare carattere è una scelta di
// Giacomo, e resta sei righe.
import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Legge un file dell'albero. Lancia invece di usare `expect`: questa
/// funzione gira anche FUORI da un test — i due file si leggono una volta
/// sola in cima a `main` — e `expect` fuori da un test fa fallire il
/// caricamento con un messaggio che non dice niente di utile.
String _leggi(String rel) {
  final f = File('${Directory.current.parent.path}/$rel');
  if (!f.existsSync()) {
    throw StateError('manca $rel');
  }
  return f.codiceVivo();
}

void main() {
  final tipo = _leggi('minerva-shell/theme/Typography.qml');
  final barra = _leggi('compositore/src/barra.c');

  String? valoreDi(String testo, String chiave) {
    final m = RegExp('$chiave:\\s*"([^"]+)"').firstMatch(testo);
    return m?.group(1);
  }

  test('shell e compositore nominano lo stesso carattere', () {
    final dellaShell = valoreDi(tipo, 'fontDisplay');
    expect(dellaShell, isNotNull, reason: 'fontDisplay non si legge');

    final m = RegExp(r'set_family\(tenuto,\s*"([^",]+)').firstMatch(barra);
    expect(m, isNotNull, reason: 'il carattere di barra.c non si legge');
    final delCompositore = m!.group(1);

    expect(delCompositore, dellaShell,
        reason: 'la barra del titolo dei programmi esterni userebbe '
            '«$delCompositore» e tutto il resto di Minerva «$dellaShell»: '
            'la stessa finestra in due caratteri diversi');
  });

  test('i cinque pesi sono cinque numeri diversi', () {
    // Il difetto vero, e c'è stato per tre settimane: `weightRegular` e
    // `weightMedium` valevano tutti e due 500, in 263 punti che chiedevano due
    // pesi diversi. Una gerarchia tipografica che non esiste per costruzione.
    final pesi = <String, int>{};
    for (final nome in ['weightLight', 'weightRegular', 'weightMedium',
                        'weightSemiBold', 'weightBold']) {
      final m = RegExp('$nome:\\s*(\\d+)').firstMatch(tipo);
      expect(m, isNotNull, reason: '$nome non si legge');
      pesi[nome] = int.parse(m!.group(1)!);
    }
    expect(pesi.values.toSet().length, pesi.length,
        reason: 'due pesi valgono lo stesso numero, quindi non si distinguono: '
            '$pesi');
    // E in ordine crescente, o i nomi mentono su cosa fanno.
    final ordinati = pesi.values.toList();
    for (var i = 1; i < ordinati.length; i++) {
      expect(ordinati[i], greaterThan(ordinati[i - 1]),
          reason: 'i pesi non salgono: $pesi');
    }
  });

  test('i due caratteri sono dichiarati fra i pacchetti, non scaricati', () {
    // Un `curl` a GitHub dentro l'installatore è una dipendenza dalla rete nel
    // momento peggiore: se quel giorno non risponde, la scrivania nasce con un
    // ripiego che nessuno ha scelto e nessuno saprà perché.
    final inst = _leggi('scripts/install-minerva.sh');
    expect(inst, isNot(contains('fonts/main')),
        reason: 'i caratteri tornano a dipendere da GitHub');
    expect(inst, contains('adwaita-fonts'));
  });
}

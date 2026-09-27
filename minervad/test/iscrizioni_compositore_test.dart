// Gli annunci a cui la shell si iscrive esistono, e ci stanno tutti.
//
// La shell si iscrive agli annunci del compositore con una riga sola:
// `ascolta scrivania scorciatoia coperchio …`. Il canale teneva i primi
// QUATTRO nomi e buttava via il resto senza dirlo, e la shell ne chiedeva
// sette: `attivo` e `schermi` non le sono mai arrivati. Nessun errore da
// nessuna parte — il sintomo era una tenda dell'inattività che non si
// alzava da sola e uno schermo attaccato che la pagina non vedeva. Trovato
// il 23 settembre 2026 cercando perché non arrivasse l'ottavo, `bordoalto`.
//
// Il canale adesso rifiuta un'iscrizione troppo lunga invece di tagliarla
// (`compositore/prova-annunci.py` lo prova dal vivo). Questa guardia prende
// lo stesso difetto leggendo i file, prima che parta una sessione: e prende
// anche il nome scritto male, che dà un'iscrizione valida e muta.

import 'dart:io';
import 'package:test/test.dart';
import 'codice_vivo.dart';

Directory _radice() {
  for (final base in ['.', '..', '../..']) {
    if (Directory('$base/minerva-shell').existsSync()) return Directory(base);
  }
  fail('non trovo minerva-shell/');
}

void main() {
  final radice = _radice().path;

  /// I nomi della riga `ascolta …` in `core/Compositore.qml`, anche se la
  /// stringa è spezzata su più righe con `+`.
  List<String> iscrizioneDellaShell() {
    final testo = File('$radice/minerva-shell/core/Compositore.qml').codiceVivo();
    final m = RegExp(r'canale\.write\(((?:\s*\+?\s*"[^"]*")+)\s*\)')
        .allMatches(testo)
        .map((m) => RegExp(r'"([^"]*)"').allMatches(m[1]!).map((x) => x[1]!).join())
        .firstWhere((riga) => riga.startsWith('ascolta '), orElse: () => '');
    expect(m, isNotEmpty, reason: 'non trovo la riga «ascolta …» in core/Compositore.qml');
    return m.replaceAll(r'\n', '').substring(8).trim().split(RegExp(r'\s+'));
  }

  /// I nomi che il compositore annuncia davvero: quelli scritti per esteso in
  /// `canale_annuncia(…, "nome", …)` e quelli che passano da `annuncia(m,
  /// "nome", f)` per le finestre.
  Set<String> annunciDelCompositore() {
    final nomi = <String>{};
    for (final f in Directory('$radice/compositore/src').listSync()) {
      if (f is! File || !f.path.endsWith('.c')) continue;
      final testo = f.codiceVivo();
      for (final m in RegExp(r'canale_annuncia\([^,]+,\s*"(\w+)"').allMatches(testo)) {
        nomi.add(m[1]!);
      }
      for (final m in RegExp(r'\bannuncia\(\s*[\w>.-]+,\s*"(\w+)"').allMatches(testo)) {
        nomi.add(m[1]!);
      }
    }
    return nomi;
  }

  int filtriMax() {
    final testo = File('$radice/compositore/src/canale.c').codiceVivo();
    final m = RegExp(r'#define\s+FILTRI_MAX\s+(\d+)').firstMatch(testo);
    expect(m, isNotNull, reason: 'FILTRI_MAX sparito da canale.c');
    return int.parse(m![1]!);
  }

  test('ogni nome a cui la shell si iscrive è un annuncio che esiste', () {
    final annunci = annunciDelCompositore();
    expect(annunci, containsAll(['scrivania', 'inattivo', 'attivo', 'schermi']),
        reason: 'la lettura di main.c non trova più gli annunci: è cambiata la forma?');
    final ignoti = iscrizioneDellaShell().where((n) => !annunci.contains(n)).toList();
    expect(ignoti, isEmpty,
        reason: 'la shell si iscrive a nomi che il compositore non annuncia mai: '
            'l\'iscrizione vale e resta muta');
  });

  test('e ci stanno tutti nel canale', () {
    final nomi = iscrizioneDellaShell();
    expect(nomi.length, lessThanOrEqualTo(filtriMax()),
        reason: 'la shell chiede ${nomi.length} annunci e il canale ne tiene '
            '${filtriMax()}: gli ultimi non arriverebbero');
  });
}

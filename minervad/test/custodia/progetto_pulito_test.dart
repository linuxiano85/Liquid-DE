import 'dart:io';

import 'package:minervad/services/custodia/segreti.dart';
import 'package:test/test.dart';

/// Il controllo dei segreti, puntato su Minerva stessa.
///
/// ── Perché questa prova esiste ─────────────────────────────────────────────
///
/// Perché un controllo che nessuno esegue è un controllo che non c'è. Questo lo
/// esegue su **tutti i file del progetto** — quelli già nella storia e quelli
/// che ci entrerebbero adesso — a ogni giro di prove.
///
/// Serve a due cose diverse:
///
///   1. **Che Minerva resti pulita.** Se un giorno una chiave finisce qui
///      dentro, lo si sa prima del salvataggio e non dopo l'invio.
///   2. **Che il controllo resti usabile.** Se una regola nuova comincia a
///      scattare su cinquanta file di questo progetto, quella regola è
///      sbagliata — e lo si scopre qui, non il giorno che qualcuno impara a
///      premere «salvalo lo stesso» senza leggere.
///
/// La seconda è la ragione meno ovvia e la più importante. Un controllo troppo
/// severo non si nota subito: si nota dopo un mese, quando è stato disattivato
/// nella testa di chi lo usa.
///
/// Misurato il 24 agosto 2026: 150 file pronti per il primo salvataggio,
/// **nessun allarme**. L'unico che scattava era il file di prova del controllo
/// stesso, e lì i finti segreti si compongono a pezzi — vedi `segreti_test.dart`.
void main() {
  test('Minerva non fa scattare il proprio controllo dei segreti', () async {
    final radice = Directory.current.parent.path;

    Future<List<String>> chiedi(List<String> args) async {
      final r = await Process.run('git', ['-C', radice, ...args]);
      if (r.exitCode != 0) return const [];
      return [
        for (final f in '${r.stdout}'.split('\u0000'))
          if (f.isNotEmpty) f,
      ];
    }

    final tutti = <String>{
      ...await chiedi(['ls-files', '-z']),
      ...await chiedi(['ls-files', '--others', '--exclude-standard', '-z']),
    };

    if (tutti.isEmpty) {
      // Fuori da un repo git non c'è niente da controllare, e fallire qui
      // vorrebbe dire fallire su un tarball scaricato.
      return;
    }

    final trovati = await const Segreti().guarda(radice, tutti.toList());

    expect(
      trovati.map((t) => '${t.percorso}  →  ${t.perche}').toList(),
      isEmpty,
      reason: 'Su ${tutti.length} file del progetto il controllo si è fermato. '
          'O c\'è davvero una chiave da togliere PRIMA di salvarla, oppure una '
          'regola di segreti.dart è troppo larga — e una regola che scatta a '
          'vuoto si impara a ignorare.',
    );
  });
}

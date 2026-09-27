import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Le nostre applicazioni, viste da fuori: `desktop/*.desktop`.
///
/// ── Perché questo file esiste ──────────────────────────────────────────────
///
/// Un `.desktop` è l'unica cosa che il resto del computer sa di un nostro
/// programma. Ci sono scritti il nome che compare nel menu, l'icona, il
/// comando da eseguire, la classe della finestra e i tipi di file che apre.
/// Nessuno di questi campi viene mai compilato: se sono sbagliati non succede
/// niente di rumoroso, succede che il programma è nel menu senza icona, o non
/// c'è affatto, o ce n'è due che si contendono lo stesso file.
///
/// Tutti e tre sono capitati, e tutti e tre sono stati trovati a mano il 23
/// agosto 2026:
///
///  · **due programmi sullo stesso tipo.** «Suoneria» e «Media» dichiaravano
///    gli stessi sette tipi audio. Chi apre un MP3 lo decideva l'ordine dentro
///    `mimeapps.list`, cioè il caso;
///  · **un programma fuori dal menu.** `minerva-media` non era nell'elenco di
///    `install-minerva.sh`: esisteva, funzionava, e non l'aveva mai visto
///    nessuno. Un programma che non è nel menu non esiste;
///  · **un programma senza icona sua.** Tre `.desktop` su nove ricadevano su
///    icone di sistema, rompendo la catena classe = `.desktop` = icona su cui
///    dock, barra del titolo e menu risalgono da una finestra al programma.
///
/// Sono tutte cose che una macchina sa controllare in un decimo di secondo.
File _trova(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

Directory _cartella(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final d = Directory('${dir.path}/$relativo');
    if (d.existsSync()) return d;
    dir = dir.parent;
  }
  fail('non trovo la cartella $relativo');
}

/// I campi di un `.desktop`, dal solo gruppo `[Desktop Entry]`.
Map<String, String> _campi(File f) {
  final out = <String, String>{};
  var dentro = false;
  for (final riga in f.readAsLinesSync()) {
    final r = riga.trim();
    if (r.startsWith('[')) {
      dentro = r == '[Desktop Entry]';
      continue;
    }
    if (!dentro || r.isEmpty || r.startsWith('#')) continue;
    final i = r.indexOf('=');
    if (i <= 0) continue;
    out[r.substring(0, i)] = r.substring(i + 1);
  }
  return out;
}

void main() {
  final cartella = _cartella('desktop');
  final voci = cartella
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.desktop'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  String nome(File f) => f.uri.pathSegments.last.replaceAll('.desktop', '');

  group('i file .desktop delle nostre applicazioni', () {
    test('ce n\'è almeno uno, o questa prova non sta provando niente', () {
      expect(voci, isNotEmpty);
    });

    test('hanno tutti i campi che servono', () {
      for (final f in voci) {
        final c = _campi(f);
        final n = nome(f);
        expect(c['Type'], 'Application', reason: n);
        expect(c['Name'], isNotEmpty, reason: n);
        expect(c['Exec'], isNotNull, reason: n);
        expect(c['Icon'], isNotNull, reason: n);
      }
    });

    test('il comando che eseguono esiste davvero nel progetto', () {
      // Il difetto che prende: uno script archiviato e il suo `.desktop`
      // rimasto. La voce resta nel menu, si clicca, e non succede niente.
      //
      // ── E i due che non sono script ─────────────────────────────────
      //
      // `minerva-wayland` e `minerva-polkit` sono in C: non stanno in
      // `scripts/` ma nella cartella del loro progetto, e finiscono in
      // `~/.local/bin` quando si compilano. Cercarli in `scripts/` direbbe
      // rosso su una cosa che funziona — che è il modo in cui una guardia
      // smette di essere creduta.
      //
      // Si guarda il SORGENTE e non il binario compilato: il binario può
      // mancare perché nessuno ha ancora lanciato `costruisci.sh`, e quello
      // non è un `.desktop` orfano.
      const compilati = {
        'minerva-wayland': 'compositore/src/main.c',
        'minerva-polkit': 'permessi/src/minerva-polkit.c',
      };
      for (final f in voci) {
        final exec = _campi(f)['Exec']!.split(' ').first;
        if (compilati.containsKey(exec)) {
          // La radice del progetto è la cartella che CONTIENE `scripts/`:
          // `_cartella` la cerca risalendo, e questa prova gira sia da
          // `minervad/` sia dalla radice.
          final radice = _cartella('scripts').parent.path;
          final sorgente = File('$radice/${compilati[exec]}');
          expect(sorgente.existsSync(), isTrue,
              reason: '${nome(f)} lancia «$exec», che si compila da '
                  '${compilati[exec]} — e quel file non c\'è più');
          continue;
        }
        final script = File('${_cartella('scripts').path}/$exec');
        expect(script.existsSync(), isTrue,
            reason: '${nome(f)} lancia «$exec», che in scripts/ non c\'è');
      }
    });

    test('la classe della finestra combacia col nome del file', () {
      // È la catena su cui dock, Alt+Tab e barra del titolo risalgono da una
      // finestra aperta al programma che l'ha aperta: classe = `.desktop` =
      // icona. Chi non si mostra nel menu è esentato.
      for (final f in voci) {
        final c = _campi(f);
        if (c['NoDisplay'] == 'true') continue;
        expect(c['StartupWMClass'], nome(f),
            reason: '${nome(f)}: la dock non saprebbe che finestra è la sua');
      }
    });

    test('l\'icona è una nostra, e il file c\'è', () {
      // Chi non si mostra nel menu può usare un'icona di sistema: non compare
      // da nessuna parte, e disegnarne una sarebbe lavoro per nessuno.
      final icone = _cartella('assets/icons');
      for (final f in voci) {
        final c = _campi(f);
        if (c['NoDisplay'] == 'true') continue;
        expect(c['Icon'], nome(f),
            reason: '${nome(f)} usa un\'icona di sistema invece della sua');
        expect(File('${icone.path}/${c['Icon']}.svg').existsSync(), isTrue,
            reason: 'manca assets/icons/${c['Icon']}.svg');
      }
    });

    test('due nostri programmi non si contendono lo stesso tipo di file', () {
      // Il difetto vero, e la ragione principale di questo file. Con due
      // `.desktop` che dichiarano lo stesso tipo, chi apre quel file lo
      // decide l'ordine dentro `mimeapps.list` — cioè il caso.
      final chiLoApre = <String, List<String>>{};
      for (final f in voci) {
        final tipi = (_campi(f)['MimeType'] ?? '')
            .split(';')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty);
        for (final t in tipi) {
          chiLoApre.putIfAbsent(t, () => []).add(nome(f));
        }
      }
      final contesi = chiLoApre.entries.where((e) => e.value.length > 1).toList();
      expect(contesi, isEmpty,
          reason: 'tipi dichiarati da più di un nostro programma: '
              '${contesi.map((e) => "${e.key} → ${e.value.join(" e ")}").join("; ")}');
    });

    test('quelle da menu sono tutte nell\'installatore', () {
      // Un programma che non è in questo elenco non viene installato, quindi
      // non è nel menu, quindi non esiste. È successo a `minerva-media`, che
      // era pronto da giorni.
      final inst = _trova('scripts/install-minerva.sh').codiceVivo();
      for (final f in voci) {
        if (_campi(f)['NoDisplay'] == 'true') continue;
        expect(inst, contains(nome(f)),
            reason: '${nome(f)} non viene installato da nessuno');
      }
    });
  });
}

import 'dart:io';

import 'package:minervad/services/keybind_service.dart';
import 'package:test/test.dart';

/// Prove sulla lettura di `keybinds.conf`.
///
/// È il pezzo di Minerva che più merita una prova automatica: nessuno se ne
/// accorge se smette di funzionare. Un errore qui non fa sparire niente dallo
/// schermo — fa solo diventare vuoto, o sbagliato, il pannello delle
/// scorciatoie (F1), che è l'ultimo posto in cui si va a guardare.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-keybind-');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<List<KeybindEntry>> parse(String content) async {
    final file = File('${temp.path}/keybinds.conf');
    await file.writeAsString(content);
    final service = KeybindService(path: file.path);
    await service.reload();
    return service.entries;
  }

  test('legge una scorciatoia annotata', () async {
    final entries = await parse('''
@ Finestre | Chiudi la finestra
SUPER Q -> chiudi-finestra
''');

    expect(entries, hasLength(1));
    expect(entries.first.category, 'Finestre');
    expect(entries.first.description, 'Chiudi la finestra');
    expect(entries.first.combos.single.mods, ['SUPER']);
    expect(entries.first.combos.single.key, 'Q');
  });

  test('espande le variabili \$mod', () async {
    final entries = await parse('''
\$mod = SUPER
@ Finestre | Chiudi la finestra
\$mod SHIFT Q -> chiudi-finestra
''');

    expect(entries.single.combos.single.mods, ['SUPER', 'SHIFT']);
  });

  test('un bind senza annotazione non entra nell\'elenco', () async {
    // Le scorciatoie interne — quelle che non si spiegano a nessuno — non
    // devono comparire nel pannello. È il motivo per cui l'annotazione è
    // obbligatoria e non facoltativa.
    final entries = await parse('''
SUPER F12 -> avvia: qualcosa-di-interno
''');

    expect(entries, isEmpty);
  });

  test('due bind con la stessa descrizione diventano una voce sola', () async {
    // Freccia e tasto lettera per la stessa azione sono UNA cosa che si può
    // fare in due modi, non due cose.
    final entries = await parse('''
@ Finestre | Vai a sinistra
SUPER left -> fuoco: l
SUPER H -> fuoco: l
''');

    expect(entries, hasLength(1));
    expect(entries.single.combos, hasLength(2));
    expect(entries.single.combos.map((c) => c.key), ['left', 'H']);
  });

  test('la stessa combinazione ripetuta non si duplica', () async {
    final entries = await parse('''
@ Finestre | Chiudi
SUPER Q -> chiudi-finestra
SUPER Q -> chiudi-finestra
''');

    expect(entries.single.combos, hasLength(1));
  });

  test('un commento normale non spezza il gruppo', () async {
    final entries = await parse('''
@ Finestre | Vai a sinistra
# ────────────────────────────
SUPER left -> fuoco: l
''');

    expect(entries, hasLength(1));
    expect(entries.single.combos, hasLength(1));
  });

  test('riconosce i marchi [mouse] [ripete] [anche-bloccato]', () async {
    // Nella sorgente i flag di Hyprland (`bindm`, `binde`, `bindl`) sono
    // parole: chi legge il file capisce cosa vogliono dire senza sapere che
    // `l` sta per «locked».
    final entries = await parse('''
\$mod = SUPER
@ Finestre | Sposta col mouse
\$mod mouse:272 [mouse] -> sposta-finestra:
@ Volume | Alza
XF86AudioRaiseVolume [ripete] -> avvia: alza
@ Volume | Muto
XF86AudioMute [anche-bloccato] -> avvia: muto
''');

    expect(entries, hasLength(3));
    expect(entries.first.combos.single.key, 'mouse:272');
  });

  test('un file che non esiste non fa esplodere niente', () async {
    final service = KeybindService(path: '${temp.path}/non-c-e.conf');
    await service.reload();
    expect(service.entries, isEmpty);
  });

  test('le scorciatoie vere di Minerva si leggono tutte', () async {
    // Non una finta: il file vero del progetto. Se qualcuno cambia il formato
    // della sorgente senza cambiare il lettore, è qui che si scopre — e non
    // aprendo il pannello F1 tre settimane dopo.
    // Dall'11 agosto 2026 la sorgente è nostra: `keybinds.conf` è il prodotto
    // che se ne ricava, e il pannello F1 non legge più la lingua di Hyprland.
    final real = File('${Directory.current.path}/../config/scorciatoie.minerva');
    if (!await real.exists()) {
      markTestSkipped('scorciatoie.minerva non trovato accanto al progetto');
      return;
    }

    final service = KeybindService(path: real.path);
    await service.reload();

    expect(service.entries.length, greaterThan(20),
        reason: 'il file vero ha decine di scorciatoie annotate');
    for (final e in service.entries) {
      expect(e.combos, isNotEmpty, reason: '«${e.description}» senza tasti');
      expect(e.category, isNotEmpty);
      expect(e.description, isNotEmpty);
    }
  });
}

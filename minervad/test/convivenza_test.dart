// Liquid DE e Minerva sullo stesso computer.
//
// Giacomo, 23 settembre 2026: «lavoreremo lì senza toccare questo attuale
// progetto, nel caso voglio continuare». Le due scrivanie convivono solo se
// nessuna scrive mai nei posti dell'altra: cartelle, programmi installati,
// voci al login, file di sistema. Un solo percorso di Minerva rimasto nel
// codice di Liquid DE vuol dire impostazioni sovrascritte, o un login
// «Minerva» che apre Liquid DE.
//
// Questa prova legge TUTTO il codice — demone, shell, compositore, script —
// e cerca i posti di Minerva. Le righe che li nominano per una ragione giusta
// stanno nell'elenco qui sotto, ognuna col suo perché.
import 'dart:io';

import 'package:test/test.dart';

Directory _radice() {
  var d = Directory.current;
  while (!File('${d.path}/PIANO.md').existsSync()) {
    final su = d.parent;
    if (su.path == d.path) throw StateError('radice del progetto non trovata');
    d = su;
  }
  return d;
}

/// I posti di Minerva, come li scriverebbe il codice.
final _postiDiMinerva = <String, RegExp>{
  'cartelle XDG di Minerva': RegExp(
      r'(\.config|\.cache|\.local/share|\.local/state)\}?/minerva(?![\w-])|RUNTIME_DIR[^/\s]*/minerva(?![\w-])|/minerva/sessioni'),
  'programmi in ~/.local/bin': RegExp(r'(\$HOME|~)/\.local/bin/minerva-'),
  'ponti di sessione di Minerva': RegExp(r'/usr/local/bin/minerva-session'),
  'voci al login di Minerva': RegExp(r'wayland-sessions/minerva'),
  'servizio PAM di Minerva': RegExp(r'pam\.d/minerva\b'),
  'regole polkit di Minerva': RegExp(r'org\.minerva\.(radice|utente)'),
  'aiutanti di Minerva': RegExp(r'/usr/local/bin/minerva-(radice|utente)\b'),
  'portali di Minerva': RegExp(r'minerva(wayland)?-portals\.conf'),
};

/// Chi può nominarli, e perché. Percorso relativo alla radice.
const _permessi = <String, String>{
  'minervad/lib/core/minerva_paths.dart':
      'legge le impostazioni di Minerva, una volta, per importarle',
  'scripts/minerva-cartelle.sh':
      'le prove partono dalle impostazioni di Minerva finché Liquid DE non ha le sue',
  'scripts/cartelle.py': 'come sopra, per le prove in Python',
  'scripts/minerva-greetd': 'il greeter: si separa con la Tappa 5',
  'scripts/minerva-greeter-sessione': 'il greeter: si separa con la Tappa 5',
  'scripts/minerva-greeter-avvio': 'il greeter: si separa con la Tappa 5',
  'scripts/minerva-avvia-sessione': 'il greeter (lo avvia da /usr/local/lib/minerva): si separa con la Tappa 5',
  'scripts/prova-accesso.py': 'il greeter: si separa con la Tappa 5',
  'minerva-shell/greeter/Greeter.qml': 'il greeter: si separa con la Tappa 5',
  'minerva-shell/prove-greeter.qml': 'il greeter: si separa con la Tappa 5',
  'minervad/lib/services/accesso_service.dart': 'il greeter: si separa con la Tappa 5',
  'minervad/test/accesso_service_test.dart': 'il greeter: si separa con la Tappa 5',
  'minervad/test/greetd_service_test.dart': 'il greeter: si separa con la Tappa 5',
  'minervad/test/minerva_paths_test.dart': 'prova la lettura da Minerva',
  'minervad/test/convivenza_test.dart': 'è questa prova',
};

bool _commento(String riga) {
  final r = riga.trimLeft();
  return r.startsWith('//') || r.startsWith('#') || r.startsWith('*') ||
      r.startsWith('///') || r.startsWith('<!--');
}

void main() {
  test('nessun codice di Liquid DE scrive nei posti di Minerva', () {
    final radice = _radice();
    final cartelle = ['minervad/lib', 'minervad/bin', 'minervad/test',
        'minerva-shell', 'scripts', 'compositore', 'permessi', 'config',
        'desktop'];
    final estensioni = RegExp(r'\.(dart|qml|js|sh|py|c|h|conf|policy|rules|desktop|build)$');
    final colpevoli = <String>[];

    for (final nome in cartelle) {
      final dir = Directory('${radice.path}/$nome');
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final rel = f.path.substring(radice.path.length + 1);
        if (rel.contains('/subprojects/') || rel.contains('/build') ||
            rel.contains('/.dart_tool/')) {
          continue;
        }
        final eseguibile = !rel.contains('.') || rel.startsWith('scripts/');
        if (!estensioni.hasMatch(rel) && !eseguibile) continue;
        if (_permessi.containsKey(rel)) continue;
        List<String> righe;
        try {
          righe = f.readAsLinesSync();
        } catch (_) {
          continue; // un file binario
        }
        for (var i = 0; i < righe.length; i++) {
          if (_commento(righe[i])) continue;
          for (final e in _postiDiMinerva.entries) {
            if (e.value.hasMatch(righe[i])) {
              colpevoli.add('$rel:${i + 1}  (${e.key})  ${righe[i].trim()}');
            }
          }
        }
      }
    }
    expect(colpevoli, isEmpty,
        reason: 'queste righe nominano un posto di Minerva. Se scrivono, '
            'vanno portate nei posti di Liquid DE (MinervaPaths, Ipc.qml, '
            'minerva-cartelle.sh, cartelle.py); se leggono per una ragione '
            'giusta, vanno nell\'elenco dei permessi con il loro perché.\n'
            '${colpevoli.join('\n')}');
  });

  test('ogni permesso riguarda un file che esiste ancora', () {
    // Un permesso per un file sparito è una porta aperta per il prossimo che
    // prende quel nome.
    final radice = _radice();
    for (final rel in _permessi.keys) {
      expect(File('${radice.path}/$rel').existsSync(), isTrue,
          reason: '$rel non c\'è più: togli il suo permesso');
    }
  });
}

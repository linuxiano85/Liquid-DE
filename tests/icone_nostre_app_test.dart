// Prove per le icone delle nostre app che seguono il tema scelto
// (`IconResolver.nomiStandard`, 11 ottobre 2026).
//
//     dart run tests/icone_nostre_app_test.dart
//
// Gira in una HOME temporanea con un tema finto, «ProvaLiquid», che ha
// l'icona del gestore file e quella del terminale ma non quella dell'editor;
// le nostre icone stanno in un hicolor finto, come le mette l'installatore.
// La prova si rilancia da sola con quell'ambiente: `IconResolver` legge le
// cartelle dall'ambiente del processo, che in Dart non si può cambiare.
import 'dart:io';
import '../minervad/lib/services/icon_resolver.dart';

var prove = 0;

void check(bool value, String message) {
  if (!value) throw StateError(message);
  prove++;
}

const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48">'
    '<rect width="48" height="48" fill="#3a7bd5"/><rect x="8" y="8" width="32" height="32" fill="#ffd166"/></svg>';

void icona(String cartella, String nome) {
  final f = File('$cartella/$nome.svg');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(svg);
}

Future<void> main() async {
  if (Platform.environment['ICONE_PROVA_HOME'] == null) {
    final base = await Directory.systemTemp.createTemp('liquid-icone-');
    try {
      final home = base.path;
      final tema = '$home/.local/share/icons/ProvaLiquid';
      File('$tema/index.theme')
        ..createSync(recursive: true)
        ..writeAsStringSync('[Icon Theme]\nName=ProvaLiquid\nInherits=hicolor\n'
            'Directories=apps/scalable\n\n[apps/scalable]\nSize=48\nType=Scalable\nMinSize=8\nMaxSize=512\n');
      icona('$tema/apps/scalable', 'system-file-manager');
      icona('$tema/apps/scalable', 'org.gnome.Terminal');
      // Le nostre, in un hicolor finto (come le installa l'installatore), e
      // un'icona standard anche lì: hicolor NON deve vincere sulle nostre.
      final hicolor = '$home/pref/share/icons/hicolor';
      File('$hicolor/index.theme')
        ..createSync(recursive: true)
        ..writeAsStringSync('[Icon Theme]\nName=Hicolor\nDirectories=apps/scalable\n\n'
            '[apps/scalable]\nSize=48\nType=Scalable\nMinSize=8\nMaxSize=512\n');
      for (final n in ['minerva-files', 'minerva-terminale', 'minerva-editor', 'minerva-fucina']) {
        icona('$hicolor/apps/scalable', n);
      }
      icona('$hicolor/apps/scalable', 'accessories-text-editor');
      final r = await Process.run(Platform.resolvedExecutable, ['run', Platform.script.toFilePath()],
          environment: {
            'ICONE_PROVA_HOME': home,
            'HOME': home,
            'XDG_DATA_HOME': '$home/.local/share',
            'XDG_DATA_DIRS': '$home/nessuna',
            'LIQUID_PREFISSO': '$home/pref',
          });
      stdout.write(r.stdout);
      stderr.write(r.stderr);
      exitCode = r.exitCode;
    } finally {
      await base.delete(recursive: true);
    }
    return;
  }

  final home = Platform.environment['ICONE_PROVA_HOME']!;
  final r = IconResolver();
  r.setTheme('ProvaLiquid');

  final files = r.resolve('minerva-files', generic: false);
  check(files.endsWith('/ProvaLiquid/apps/scalable/system-file-manager.svg'),
      'il gestore file prende l\'icona del tema: $files');
  final terminale = r.resolve('minerva-terminale', generic: false);
  check(terminale.endsWith('/ProvaLiquid/apps/scalable/org.gnome.Terminal.svg'),
      'il terminale prende il secondo nome della lista, se il primo manca: $terminale');
  final editor = r.resolve('minerva-editor', generic: false);
  check(editor == '$home/pref/share/icons/hicolor/apps/scalable/minerva-editor.svg',
      'il tema non ha l\'editor: resta il nostro, non l\'icona standard di hicolor: $editor');
  final fucina = r.resolve('minerva-fucina', generic: false);
  check(fucina.endsWith('/hicolor/apps/scalable/minerva-fucina.svg'),
      'la Fucina non ha un equivalente: resta la sua: $fucina');

  // Tornando a nessun tema scelto (hicolor), tutte le nostre tornano nostre.
  r.setTheme('hicolor');
  final ancora = r.resolve('minerva-files', generic: false);
  check(ancora.endsWith('/hicolor/apps/scalable/minerva-files.svg'),
      'senza un tema scelto le nostre restano nostre: $ancora');

  check(IconResolver.nomiStandard.keys.every((k) => k.startsWith('minerva-')),
      'la tabella parla solo delle nostre app');
  print('icone_nostre_app: $prove prove superate');
}

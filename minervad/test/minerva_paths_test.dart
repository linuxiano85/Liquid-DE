import 'dart:io';

import 'package:minervad/core/minerva_paths.dart';
import 'package:test/test.dart';

/// Prove su «dove stanno le cose».
///
/// Sono la rete sotto il secondo dei tre problemi strutturali di Minerva: per
/// mesi la risposta è stata un percorso scritto a mano dentro quattro file, e
/// Minerva funzionava su un computer solo. Se qualcuno rimette un percorso
/// assoluto in giro, è qui che si scopre.
void main() {
  group('dove siamo', () {
    test('la radice dell\'installazione contiene la shell', () async {
      // Le prove girano dentro `minervad/`, quindi la radice è quella sopra.
      expect(Directory('${MinervaPaths.installRoot}/minerva-shell').existsSync(),
          isTrue,
          reason: 'installRoot deve puntare alla cartella di Minerva, '
              'ha detto ${MinervaPaths.installRoot}');
    });

    test('le preferenze stanno in una cartella «minerva» dell\'utente', () {
      expect(MinervaPaths.configDir, endsWith('/minerva'));
      expect(MinervaPaths.configDir, isNot(contains('Progetti')),
          reason: 'le preferenze non devono più stare dentro il progetto');
    });

    test('i file delle preferenze stanno nella cartella delle preferenze', () {
      for (final f in [
        MinervaPaths.settingsFile(),
        MinervaPaths.appUsageFile(),
      ]) {
        expect(f, startsWith('${MinervaPaths.configDir}/'));
      }
    });

    test('i moduli aggiuntivi stanno con l\'installazione, non con l\'utente',
        () {
      // I plugin sono codice: appartengono a Minerva, non a chi la usa. Se
      // finissero in ~/.config aggiornare Minerva non li aggiornerebbe.
      expect(MinervaPaths.pluginsDir(),
          startsWith('${MinervaPaths.installRoot}/'));
    });

    test('nel codice del demone non c\'è nessun percorso scritto a mano', () {
      // La prova più stupida di tutte e la più utile. Non guarda cosa fa il
      // programma: guarda cosa c\'è scritto. Il secondo problema strutturale di
      // Minerva era esattamente questo — quattro file con dentro
      // «/home/tizio/…» — e un difetto che si può reintrodurre scrivendo una
      // riga si previene solo leggendo le righe.
      final offenders = <String>[];
      for (final f in Directory('${Directory.current.path}/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // I commenti possono nominarlo: è la storia di com'era prima.
          if (line.trimLeft().startsWith('//')) continue;
          // [^/] indica un nome generico nelle regex della guardia del
          // terminale; non è il percorso personale di chi sviluppa.
          if (RegExp(r'/home/(?!\[\^/\])').hasMatch(line)) {
            offenders.add('${f.path.split('/').last}:${i + 1}  ${line.trim()}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'percorsi assoluti nel codice:\n${offenders.join('\n')}');
    });
  });

  group('trasloco delle preferenze', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('minerva-paths-');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('porta il file nella casa nuova', () async {
      final vecchio = File('${temp.path}/vecchia/settings.json');
      await vecchio.parent.create(recursive: true);
      await vecchio.writeAsString('{"accento":"ciano"}');

      final nuovo = File('${temp.path}/nuova/settings.json');
      final fatto = await MinervaPaths.migrateFile(vecchio, nuovo);

      expect(fatto, isTrue);
      expect(await nuovo.readAsString(), '{"accento":"ciano"}');
    });

    test('non cancella l\'originale', () async {
      // Se il trasloco andasse storto a metà, la copia vecchia è l'unica cosa
      // che resta fra l'utente e la perdita di tutte le sue impostazioni.
      final vecchio = File('${temp.path}/vecchia/theme.json');
      await vecchio.parent.create(recursive: true);
      await vecchio.writeAsString('{}');

      await MinervaPaths.migrateFile(vecchio, File('${temp.path}/n/theme.json'));

      expect(await vecchio.exists(), isTrue);
    });

    test('non sovrascrive quello che c\'è già nella casa nuova', () async {
      // Il trasloco avviene a ogni avvio del demone. Senza questo controllo,
      // ogni riavvio riporterebbe indietro le impostazioni di mesi fa.
      final vecchio = File('${temp.path}/vecchia/settings.json');
      await vecchio.parent.create(recursive: true);
      await vecchio.writeAsString('vecchio');

      final nuovo = File('${temp.path}/nuova/settings.json');
      await nuovo.parent.create(recursive: true);
      await nuovo.writeAsString('nuovo');

      final fatto = await MinervaPaths.migrateFile(vecchio, nuovo);

      expect(fatto, isFalse);
      expect(await nuovo.readAsString(), 'nuovo');
    });

    test('senza niente da traslocare non fa niente e non si lamenta', () async {
      final fatto = await MinervaPaths.migrateFile(
        File('${temp.path}/non-esiste.json'),
        File('${temp.path}/nuova/non-esiste.json'),
      );

      expect(fatto, isFalse);
      expect(await Directory('${temp.path}/nuova').exists(), isFalse);
    });
  });

// ─────────────────────────────────────────────────────────────────────────
//  Un posto solo per le preferenze
// ─────────────────────────────────────────────────────────────────────────
//
// Le impostazioni stavano in `config/settings.json`, dentro il progetto.
// Sono traslocate in `~/.config/minerva/`, ma la copia vecchia è rimasta
// nella cartella per mesi — e siccome `migrateFile` copia solo se la
// destinazione non c'è, non dava fastidio: stava lì e basta.
//
// «Stava lì e basta» è il modo in cui è costata mezz'ora il 10 agosto 2026.
// Le due copie dicevano cose diverse (`titleHeight` 38 nel progetto, 42 in
// ~/.config), io modificavo quella del progetto e guardavo il compositore
// non cambiare. Il file non è sbagliato: è un'ESCA, e un'esca non si
// riconosce guardandola.
//
// Questa prova non controlla il codice: controlla che l'esca non torni.

  group('le preferenze hanno un posto solo', () {
    Directory radice() {
      var dir = Directory.current;
      for (var i = 0; i < 4; i++) {
        if (Directory('${dir.path}/minerva-shell').existsSync()) return dir;
        dir = dir.parent;
      }
      fail('non trovo la radice del progetto');
    }

    for (final nome in ['settings.json', 'theme.json', 'app_usage.json']) {
      test('il progetto non contiene una copia di $nome', () {
        final f = File('${radice().path}/config/$nome');
        expect(f.existsSync(), isFalse,
            reason: 'config/$nome è tornato nel progetto. Il demone legge '
                '~/.config/minerva/$nome: questa copia non la leggerà '
                'nessuno, e chi la modifica non se ne accorgerà. '
                'Se serviva un valore di partenza, va nei predefiniti di '
                'settings_api.dart, non in un file.');
      });
    }
  });

}

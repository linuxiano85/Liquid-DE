import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/core/settings_api.dart';

// Le prove delle impostazioni.
//
// Questo file tiene TUTTE le scelte di chi usa Minerva: il tema, la lingua, le
// applicazioni fisse, la barra del titolo, il touchpad. Perderlo vuol dire
// ripartire dai valori di fabbrica — e il modo in cui si perdeva non era
// esotico, era trascinare un cursore:
//
//   1. il server IPC non aspetta la fine di un messaggio prima di consegnare
//      il successivo, quindi più `set_setting` si accavallano;
//   2. ognuno faceva un `writeAsString`, che TRONCA il file e poi lo riempie;
//   3. due scritture aperte insieme sullo stesso file possono lasciarlo a metà;
//   4. e i due ripristini della sorveglianza ne aprivano due, perdendo il
//      riferimento alla prima — che restava viva, e da lì in poi ogni modifica
//      veniva annunciata due volte.
void main() {
  late Directory tmp;
  late String percorso;
  late EventBus bus;
  late SettingsApi api;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('minerva-settings-');
    percorso = '${tmp.path}/settings.json';
    bus = EventBus();
    api = SettingsApi(bus, path: percorso);
    await api.init();
  });

  tearDown(() async {
    await api.dispose();
    await bus.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Map<String, dynamic> dalDisco() =>
      jsonDecode(File(percorso).readAsStringSync()) as Map<String, dynamic>;

  group('impostazioni', () {
    test('wobbly parte spento e conserva elasticità alla riapertura', () async {
      expect(api.getValue('windows.elastico'), 0.0);
      expect(api.getValue('windows.elasticoUltimo'), 1.0);
      expect(await api.setValue('windows.elastico', 2.4), isTrue);
      expect(await api.setValues({
        'windows.elastico': 0.0,
        'windows.elasticoUltimo': 2.4,
      }), isEmpty);
      await api.dispose();
      api = SettingsApi(bus, path: percorso);
      await api.init();
      expect(api.getValue('windows.elastico'), 0.0);
      expect(api.getValue('windows.elasticoUltimo'), 2.4);
      expect(await api.setValue('windows.elastico',
          api.getValue('windows.elasticoUltimo')), isTrue);
      expect(dalDisco()['windows']['elastico'], 2.4);
    });

    test('all\'avvio scrive un file leggibile con i valori di fabbrica', () {
      expect(File(percorso).existsSync(), isTrue);
      expect(dalDisco()['shell']['scheme'], 'notte');
    });

    test('setValue crea i livelli intermedi che mancano', () async {
      await api.setValue('input.touchpadOn', false);
      expect(api.getValue('input.touchpadOn'), isFalse);
      expect(dalDisco()['input']['touchpadOn'], isFalse);
    });

    test('un percorso malformato non scrive niente', () async {
      final prima = File(percorso).readAsStringSync();
      await api.setValue('shell..scheme', 'giorno');
      expect(File(percorso).readAsStringSync(), prima);
    });

    // ── Il difetto vero ────────────────────────────────────────────────────
    //
    // Le chiavi stanno sotto `files.desktopPositions`, che nei valori di
    // fabbrica e' una mappa VUOTA: e' l'unico posto dove le chiavi le mette
    // chi usa il computer, e quindi l'unico che questa prova puo' usare senza
    // inventarsi impostazioni. Prima usava `prova.numero0`, che dal 5
    // settembre 2026 il demone rifiuta.
    test('venti salvataggi lanciati insieme lasciano il file leggibile',
        () async {
      final tutti = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        tutti.add(api.setValue('files.desktopPositions.numero$i', i));
      }
      await Future.wait(tutti);

      final letto = dalDisco();
      for (var i = 0; i < 20; i++) {
        expect(letto['files']['desktopPositions']['numero$i'], i,
            reason: 'nessuna scrittura deve essere persa o troncata: '
                'si accavallavano sullo stesso file');
      }
    });

    test('i salvataggi concorrenti non moltiplicano le sorveglianze', () async {
      await Future.wait([
        for (var i = 0; i < 10; i++) api.setValue('prova.x$i', i),
      ]);
      expect(api.sorveglianzeAperte, 1,
          reason: 'ogni coppia sovrapposta ne apriva una in più, e quella '
              'vecchia restava viva senza che nessuno potesse più fermarla');
    });

    test('dopo dispose non resta nessuna sorveglianza', () async {
      await api.setValue('prova.y', 1);
      await api.dispose();
      expect(api.sorveglianzeAperte, 0);
      // Riaperta per il tearDown, che chiama di nuovo dispose().
    });

    test('non resta in giro il file provvisorio della scrittura', () async {
      await api.setValue('files.desktopPositions.z', 1);
      expect(File('$percorso.nuovo').existsSync(), isFalse,
          reason: 'si scrive di fianco e si sposta: dopo lo spostamento il '
              'provvisorio non esiste più');
    });

    test('setValues salva una volta sola per più valori', () async {
      var annunci = 0;
      final s = bus.filter('settings_changed').listen((_) => annunci++);
      await api.setValues({
        'files.desktopPositions.uno': 1,
        'files.desktopPositions.due': 2,
        'files.desktopPositions.tre': 3
      });
      await Future.delayed(Duration.zero);
      expect(annunci, 1);
      expect(dalDisco()['files']['desktopPositions']['tre'], 3);
      await s.cancel();
    });

    // ── Una chiave che non esiste non si scrive ──────────────────────────
    //
    // Fino al 5 settembre 2026 `_applyValue` creava i rami che non trovava:
    // qualunque percorso era buono. L'ho scoperto sbagliando io, durante una
    // prova: ho scritto `shell.fontFamily`, che non esiste, e il demone
    // l'ha accettata senza fiatare. Da quel momento stava nel file di
    // Giacomo, non la leggeva nessuno, e niente lo diceva.
    test('una chiave che non e\' nei valori di fabbrica viene rifiutata',
        () async {
      var annunci = 0;
      final s = bus.filter('settings_changed').listen((_) => annunci++);
      await api.setValue('shell.fontFamily', 'Inter');
      await Future.delayed(Duration.zero);
      expect(annunci, 0, reason: 'non si annuncia una scrittura che non c\'e\' '
          'stata');
      expect(api.getValue('shell.fontFamily'), isNull);
      expect(dalDisco()['shell'].containsKey('fontFamily'), isFalse,
          reason: 'e non deve finire nel file di chi usa il computer');
      await s.cancel();
    });

    test('e sotto una mappa dichiarata vuota invece si scrive quel che si vuole',
        () async {
      // `files.desktopPositions` e `shell.scavalca` sono mappe vuote nei
      // valori di fabbrica: vuol dire «qui le chiavi le mette l'utente».
      await api.setValue('files.desktopPositions.qualsiasi-nome', 7);
      expect(api.getValue('files.desktopPositions.qualsiasi-nome'), 7);
    });

    test('resetToDefaults riporta tutto com\'era appena installato', () async {
      await api.setValue('shell.scheme', 'giorno');
      await api.resetToDefaults();
      expect(api.getValue('shell.scheme'), 'notte');
      expect(dalDisco()['shell']['scheme'], 'notte');
    });

    test('le chiavi nuove si aggiungono senza toccare le scelte già fatte',
        () async {
      await api.setValue('shell.scheme', 'giorno');
      await api.dispose();

      // Si toglie una sezione intera, come farebbe un file scritto da una
      // versione precedente di Minerva.
      final crudo = dalDisco()..remove('viewer');
      File(percorso).writeAsStringSync(jsonEncode(crudo));

      final seconda = SettingsApi(bus, path: percorso);
      await seconda.init();
      expect(seconda.getValue('viewer.filmstrip'), isTrue,
          reason: 'la chiave mancante va aggiunta');
      expect(seconda.getValue('shell.scheme'), 'giorno',
          reason: 'e la scelta già fatta NON va toccata');
      await seconda.dispose();
    });

    test('un file illeggibile non lascia il demone senza impostazioni',
        () async {
      await api.dispose();
      File(percorso).writeAsStringSync('{ questo non è json');

      final seconda = SettingsApi(bus, path: percorso);
      await seconda.init();
      expect(seconda.getValue('shell.scheme'), 'notte',
          reason: 'meglio i valori di fabbrica che nessun valore');
      await seconda.dispose();
    });

    test('getString torna il ripiego quando il valore non è una stringa',
        () async {
      await api.setValue('shell.scheme', 42);
      expect(api.getString('shell.scheme', 'notte'), 'notte');
      expect(api.getString('non.esiste', 'ripiego'), 'ripiego');
    });
  });

  // ── Un rifiuto che non torna indietro è un silenzio ─────────────────────
  //
  // Dal 5 settembre 2026 una chiave che non esiste nei valori di fabbrica
  // viene rifiutata, e ha ragione: l'avevo inventata io per sbaglio durante
  // una prova. Ma il rifiuto finiva in una riga del registro del demone e
  // basta — `setValue` non restituiva niente e `set_setting` non risponde —
  // quindi chi aveva scritto restava convinto di aver scritto.
  //
  // Provato sul demone vivo il 7 settembre: mandato `shell.coloreInventato`,
  // la chiave NON finisce nel file (la guardia funziona) e non torna né una
  // risposta né un `settings_changed`. Una manopola delle Impostazioni legata
  // a una chiave scritta male resterebbe dov'è, per sempre, senza un errore.
  group('un rifiuto si sa', () {
    test('scrivere una chiave che non esiste risponde di no', () async {
      expect(await api.setValue('shell.coloreInventato', 'rosso'), isFalse);
      expect(await api.setValue('shell.qualsiasi.cosa.inventata', 1), isFalse);
    });

    test('scrivere una chiave vera risponde di sì', () async {
      expect(await api.setValue('shell.accent', '#ff0000'), isTrue);
    });

    test('in gruppo, torna indietro l\'elenco di quelle rifiutate', () async {
      final rifiutate = await api.setValues({
        'shell.accent': '#00ff00',
        'shell.inventata': 1,
        'windows.ancheQuesta': true,
      });
      expect(rifiutate, unorderedEquals(['shell.inventata', 'windows.ancheQuesta']));
      // E quelle buone sono passate lo stesso: un gruppo non è tutto-o-niente.
      expect(api.getValue('shell.accent'), '#00ff00');
    });
  });

  // ── Le chiavi che non esistono più se ne vanno ──────────────────────────
  //
  // Dal 5 settembre 2026 il demone RIFIUTA di scrivere una chiave che non sta
  // nei valori di fabbrica. Restava però il passato: quelle scritte prima, che
  // nessuno toglie mai perché `_fillMissingDefaults` sa solo aggiungere.
  //
  // Nel `settings.json` di Giacomo, l'8 settembre, ce n'erano sette:
  // `animations.enabled`, `bar.opacity`, `launcher.defaultView`,
  // `launcher.maxShown`, `plugins.enabled`, `windows.blur`,
  // `windows.compositorBars`. Nessuna letta da nessuno — resti di Hyprland e di
  // uno script di prova che le scriveva quando il demone accettava tutto.
  //
  // Non fanno danni, e proprio per questo restano: un file di impostazioni che
  // contiene manopole che non comandano niente è un file che, a leggerlo, dice
  // il falso su cosa fa Minerva.
  group('le chiavi che la fabbrica non conosce si potano', () {
    late Directory tmp2;
    late String percorso2;
    late EventBus bus2;
    late SettingsApi api2;

    Future<SettingsApi> conFile(Map<String, dynamic> contenuto) async {
      tmp2 = await Directory.systemTemp.createTemp('minerva-pota-');
      percorso2 = '${tmp2.path}/settings.json';
      File(percorso2).writeAsStringSync(jsonEncode(contenuto));
      bus2 = EventBus();
      api2 = SettingsApi(bus2, path: percorso2);
      await api2.init();
      return api2;
    }

    tearDown(() async {
      await api2.dispose();
      await bus2.dispose();
      if (await tmp2.exists()) await tmp2.delete(recursive: true);
    });

    test('una chiave inventata sparisce dal file', () async {
      final a = await conFile({
        'shell': {'accent': '#123456', 'fontFamily': 'Comic Sans'},
        'windows': {'compositorBars': true},
      });
      expect(a.getValue('shell.accent'), '#123456',
          reason: 'potando si è persa una scelta vera');
      expect(a.getValue('shell.fontFamily'), isNull);
      expect(a.getValue('windows.compositorBars'), isNull);

      final sul = jsonDecode(File(percorso2).readAsStringSync())
          as Map<String, dynamic>;
      expect((sul['shell'] as Map).containsKey('fontFamily'), isFalse,
          reason: 'tolta dalla memoria ma rimasta sul disco: al prossimo '
              'avvio torna');
      expect((sul['windows'] as Map).containsKey('compositorBars'), isFalse);
    });

    test('ma le mappe LIBERE restano intatte', () async {
      // Una mappa dichiarata vuota di fabbrica vuol dire «qui le chiavi le
      // mette l'utente»: le posizioni delle icone sulla scrivania e i colori
      // scavalcati. Potarle vorrebbe dire cancellare la scrivania di chi usa
      // Minerva a ogni avvio, che è la cura peggiore del male.
      final a = await conFile({
        'files': {
          'desktopPositions': {'una cosa.txt': '3,4', 'altra.desktop': '0,1'}
        },
        'shell': {'scavalca': {'sfondo': '#ff0000'}},
      });
      // Si legge dal FILE e non con `getValue`: quel percorso a punti
      // spezzerebbe «una cosa.txt» in «una cosa» e «txt», ed è la stessa
      // ragione per cui le posizioni della scrivania non si scrivono con
      // `setValue` — i nomi dei file contengono punti.
      final sul = jsonDecode(File(percorso2).readAsStringSync())
          as Map<String, dynamic>;
      final pos = (sul['files'] as Map)['desktopPositions'] as Map;
      expect(pos['una cosa.txt'], '3,4');
      expect(pos['altra.desktop'], '0,1');
      expect(((sul['shell'] as Map)['scavalca'] as Map)['sfondo'], '#ff0000');
      // `a` serve a tenere viva l'istanza per il tearDown.
      expect(a.settings, isNotEmpty);
    });

    test('e un file già pulito non si tocca', () async {
      final a = await conFile({'shell': {'accent': '#abcdef'}});
      final prima = File(percorso2).readAsStringSync();
      expect(a.getValue('shell.accent'), '#abcdef');
      // Riaprendolo non deve cambiare più niente: se la potatura non fosse
      // stabile, ogni avvio riscriverebbe il file.
      expect(File(percorso2).readAsStringSync(), prima);
    });
  });
}

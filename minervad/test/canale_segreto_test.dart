import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/core/minerva_paths.dart';
import 'package:minervad/ipc/canale_segreto.dart';

/// Le prove della parola d'ordine del canale.
///
/// Prima del 16 agosto 2026 il demone rispondeva a chiunque riuscisse a
/// collegarsi a `127.0.0.1:11432` — e nella schermata di accesso questo voleva
/// dire che un estraneo poteva aspettare che l'utente vero scrivesse la
/// password e poi chiedere lui `greeter_start` con un comando suo, eseguito
/// come quell'utente. Il perché per esteso sta in `canale_segreto.dart`.
///
/// Quello che queste prove sorvegliano non è «il codice fa quello che fa», è
/// **il buco resta chiuso**: i permessi del file, il segreto diverso ogni
/// volta, e il confronto che non si ferma al primo carattere.
void main() {
  group('la parola d\'ordine del canale', () {
    test('è diversa ogni volta', () {
      final visti = <String>{};
      for (var i = 0; i < 200; i++) {
        visti.add(CanaleSegreto.generaSegreto());
      }
      // Duecento su duecento. Con un generatore prevedibile — `Random()`
      // seminato con l'orologio — due processi avviati nello stesso
      // millisecondo darebbero lo stesso segreto.
      expect(visti.length, 200);
    });

    test('è abbastanza lunga da non si poter indovinare', () {
      final s = CanaleSegreto.generaSegreto();
      // 32 byte in base64 senza riempimento: 43 caratteri.
      expect(s.length, greaterThanOrEqualTo(43));
      // E senza caratteri che vadano scappati dentro un JSON o una riga di
      // file: base64url, quindi niente `+`, `/`, `=`.
      expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s), isTrue,
          reason: 'segreto con caratteri da scappare: $s');
    });

    test('il file nasce leggibile solo dal proprietario', () async {
      final tmp = await Directory.systemTemp.createTemp('minerva-segreto');
      addTearDown(() => tmp.delete(recursive: true));
      final path = '${tmp.path}/dentro/canale.segreto';

      final segreto = await CanaleSegreto.scriviNuovo(percorsoFile: path, socket: '/tmp/x.sock');
      final file = File(path);

      expect(await file.exists(), isTrue);
      final dentro = CanaleSegreto.leggi(await file.readAsString());
      expect(dentro['segreto'], segreto);
      expect(dentro['socket'], isNotNull,
          reason: 'nel file deve esserci anche l\'indirizzo: due sessioni '
              'possono stare accese insieme, ognuna col suo socket, e chi '
              'legge non lo può indovinare');

      // 0600 e non 0644. È l'unica riga che regge tutta la garanzia: con 0644
      // il segreto lo legge chiunque, e il canale torna aperto a tutti con un
      // passaggio in più.
      final modo = (await file.stat()).mode & 0x1FF;
      expect(modo, 0x180, // 0600
          reason: 'permessi ${modo.toRadixString(8)}, attesi 600');

      // Anche la cartella: un file 0600 dentro una cartella che chiunque può
      // attraversare è ancora al sicuro, ma una cartella scrivibile da altri
      // permette di SOSTITUIRE il file, che è peggio.
      final modoCartella = (await file.parent.stat()).mode & 0x1FF;
      expect(modoCartella, 0x1C0, // 0700
          reason: 'cartella ${modoCartella.toRadixString(8)}, attesa 700');
    });

    test('nel file ci va anche l\'indirizzo scelto', () async {
      final tmp = await Directory.systemTemp.createTemp('minerva-segreto');
      addTearDown(() => tmp.delete(recursive: true));
      final path = '${tmp.path}/canale';

      await CanaleSegreto.scriviNuovo(
          percorsoFile: path, socket: '/run/user/1000/liquid-de/prova.sock');
      final dentro = CanaleSegreto.leggi(await File(path).readAsString());
      expect(dentro['socket'], '/run/user/1000/liquid-de/prova.sock');
    });

    test('riscriverla la cambia', () async {
      final tmp = await Directory.systemTemp.createTemp('minerva-segreto');
      addTearDown(() => tmp.delete(recursive: true));
      final path = '${tmp.path}/canale.segreto';

      final primo = await CanaleSegreto.scriviNuovo(percorsoFile: path, socket: '/tmp/x.sock');
      final secondo = await CanaleSegreto.scriviNuovo(percorsoFile: path, socket: '/tmp/x.sock');

      // Un demone che riparte deve invalidare il segreto di prima: altrimenti
      // uno rubato una volta non scade mai.
      expect(secondo, isNot(primo));
      expect(CanaleSegreto.leggi(await File(path).readAsString())['segreto'],
          secondo);
      expect((await File(path).stat()).mode & 0x1FF, 0x180);
    });
  });

  group('il confronto', () {
    test('accetta solo quella giusta', () {
      const atteso = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
      expect(CanaleSegreto.combacia(atteso, atteso), isTrue);
      expect(CanaleSegreto.combacia(atteso, '$atteso '), isFalse);
      expect(CanaleSegreto.combacia(atteso, atteso.substring(1)), isFalse);
      expect(
          CanaleSegreto.combacia(
              atteso, 'Xbcdefghijklmnopqrstuvwxyz0123456789ABCDEFG'),
          isFalse);
    });

    test('niente non è una parola d\'ordine', () {
      expect(CanaleSegreto.combacia('qualcosa', null), isFalse);
      expect(CanaleSegreto.combacia('qualcosa', ''), isFalse);
    });

    test('e un demone senza segreto non accetta nessuno', () {
      // Il caso che conta: se per un errore `_segreto` restasse vuoto, un
      // confronto ingenuo (`'' == ''`) farebbe entrare **chiunque mandi una
      // stringa vuota**. Cioè il buco tornerebbe aperto proprio nel momento in
      // cui qualcosa è andato storto.
      expect(CanaleSegreto.combacia('', ''), isFalse);
      expect(CanaleSegreto.combacia('', null), isFalse);
      expect(CanaleSegreto.combacia('', 'qualcosa'), isFalse);
    });
  });

  group('dove sta il file', () {
    // `MINERVA_TOKEN_FILE` schiaccia tutta la lista su un percorso solo, ed è
    // giusto così: è un ordine, non un suggerimento. Ma le prove sulla FORMA
    // dei percorsi non hanno più niente da guardare, quindi si dichiarano
    // saltate invece di fallire — una prova rossa per una ragione voluta
    // insegna a ignorare il rosso.
    final imposto = (Platform.environment['MINERVA_TOKEN_FILE'] ?? '').isNotEmpty;

    test('la regola è la stessa che usa la shell', () async {
      // Il percorso lo devono calcolare in due: il demone in Dart e le
      // finestre in QML (`minerva-shell/core/Ipc.qml`). Sono due linguaggi e
      // due file, quindi possono divergere in silenzio — e il sintomo sarebbe
      // una scrivania che non si connette più, senza nessun errore che dica
      // perché.
      //
      // Qui non si esegue il QML: si legge, e si controlla che nomini gli
      // stessi tre posti nello stesso ordine.
      final qml = File('${Directory.current.path}/../minerva-shell/core/Ipc.qml');
      if (!await qml.exists()) {
        markTestSkipped('Ipc.qml non trovato da qui');
        return;
      }
      final tutto = await qml.readAsString();

      // Si guarda solo il CORPO della funzione, non tutto il file: i nomi
      // delle variabili d'ambiente compaiono anche nei commenti qui sopra, e
      // cercandoli nel file intero questa prova misurava l'ordine delle frasi
      // invece dell'ordine del codice. È fallita esattamente così appena
      // scritta — il commento nominava `XDG_RUNTIME_DIR` prima del codice.
      final inizio = tutto.indexOf('readonly property var _percorsiSegreto');
      expect(inizio, greaterThan(-1),
          reason: 'in Ipc.qml non c\'è più `_percorsiSegreto`: '
              'il canale ha cambiato forma e questa prova non prova niente');
      final fine = tutto.indexOf('function _senzaBarra', inizio);
      final testo = tutto.substring(inizio, fine > 0 ? fine : tutto.length);

      final iPrimo = testo.indexOf('MINERVA_TOKEN_FILE');
      final iSecondo = testo.indexOf('XDG_RUNTIME_DIR');
      // Il terzo posto è la cartella delle impostazioni, che la shell calcola
      // in `cartellaConfig` con la stessa regola del demone.
      final iTerzo = testo.indexOf('ipc.cartellaConfig');

      expect(iPrimo, greaterThan(-1),
          reason: 'la shell non guarda MINERVA_TOKEN_FILE');
      expect(iSecondo, greaterThan(iPrimo),
          reason: 'la shell non guarda XDG_RUNTIME_DIR dopo MINERVA_TOKEN_FILE');
      expect(iTerzo, greaterThan(iSecondo),
          reason: 'la shell non ripiega sulla cartella delle impostazioni per ultimo');

      final i = tutto.indexOf('readonly property string cartellaConfig');
      expect(i, greaterThan(-1), reason: 'in Ipc.qml non c\'è più `cartellaConfig`');
      final regola = tutto.substring(i, tutto.indexOf('readonly property', i + 10));
      expect(regola, contains('MINERVA_CONFIG_DIR'),
          reason: 'la shell non fa vincere MINERVA_CONFIG_DIR, il demone sì');
      expect(tutto, contains('readonly property string nome: "${MinervaPaths.nome}"'),
          reason: 'la shell e il demone chiamano le cartelle in due modi diversi');

      // E il nome del file, che è la cosa più facile da cambiare da una parte
      // sola.
      expect(tutto.contains(CanaleSegreto.nomeFile), isTrue,
          reason: 'la shell cerca un file con un altro nome: '
              '${CanaleSegreto.nomeFile} non compare in Ipc.qml');
    });

    test('i posti sono più d\'uno, e in ordine', () {
      if (imposto) {
        markTestSkipped('MINERVA_TOKEN_FILE impone un percorso solo');
        return;
      }
      // Un posto solo era il difetto in agguato: se il demone ripiega sulla
      // cartella di configurazione (dentro la schermata di accesso capita) e
      // la shell cerca solo nella cartella di runtime, i due programmi sono
      // giusti tutti e due e l'accesso non funziona.
      final lista = CanaleSegreto.candidati(
          cartellaConfigurazione: '/tmp/conf-di-prova');
      expect(lista, isNotEmpty);
      expect(lista.last, startsWith('/tmp/conf-di-prova/'),
          reason: 'la cartella di configurazione deve restare l\'ultimo '
              'ripiego, non il primo posto');
      expect(lista.first, isNot(startsWith('/tmp/conf-di-prova/')),
          reason: 'il primo posto è la cartella di runtime, non quella di '
              'configurazione: un segreto non deve sopravvivere a un riavvio');
    });

    test('il percorso porta dentro il nome della sessione', () {
      if (imposto) {
        markTestSkipped('MINERVA_TOKEN_FILE impone un percorso solo');
        return;
      }
      // Senza, due Minerva accese insieme si scriverebbero l'indirizzo l'una
      // sopra l'altra: la seconda finirebbe a comandare la scrivania della
      // prima, che è peggio di non connettersi.
      final lista = CanaleSegreto.candidati(
          cartellaConfigurazione: '/tmp/conf-di-prova');
      final ses = CanaleSegreto.sessione();
      expect(ses, isNotEmpty);
      for (final p in lista) {
        expect(p, contains('/sessioni/$ses/'),
            reason: '«$p» non distingue una sessione dall\'altra');
      }
    });

    test('un nome di sessione storto non diventa un percorso storto', () {
      // `MINERVA_SESSIONE` è una variabile d'ambiente, e quelle le riempie
      // chiunque. Il nome finisce in un percorso: `../../` dentro non deve
      // poter portare il file da un'altra parte.
      final ses = CanaleSegreto.sessione();
      expect(RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(ses), isTrue,
          reason: 'nome di sessione con caratteri da percorso: «$ses»');
    });

    test('chi ce lo dice vince su tutto', () {
      // `MINERVA_TOKEN_FILE` esiste per le prove: senza, questa stessa suite
      // riscriverebbe il segreto della sessione vera e butterebbe fuori la
      // barra di chi la sta lanciando.
      final detto = Platform.environment['MINERVA_TOKEN_FILE'];
      final scelto =
          CanaleSegreto.percorso(cartellaConfigurazione: '/tmp/qualunque');
      if (detto != null && detto.isNotEmpty) {
        expect(scelto, detto,
            reason: 'con MINERVA_TOKEN_FILE non si ripiega e non si aggiunge '
                'niente: è un ordine, non un suggerimento');
      } else {
        expect(scelto, endsWith('/${CanaleSegreto.nomeFile}'));
        expect(scelto, contains('/sessioni/'));
      }
    });
  });

  // ── Non si scrive sopra l'indirizzo di una sessione VIVA ────────────────
  //
  // Scoperto per sbaglio il 31 agosto 2026, mentre si riparava proprio il
  // guasto della dock sparita: un `minervad --test-start` con un socket suo ha
  // scritto lo stesso il proprio indirizzo nel file della sessione IN CORSO.
  // Quel socket è sparito un secondo dopo, e la scrivania di chi stava
  // lavorando è rimasta in mano a un indirizzo morto.
  //
  // Le prove che contano qui sono i RIFIUTI, e la cosa da non sbagliare è
  // l'altro verso: la guardia non deve impedire il caso normale, cioè un
  // demone che riparte e riscrive il proprio indirizzo.
  group("non si ruba il posto a un Minerva acceso", () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('minerva-canale-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('se dietro l\'indirizzo di prima risponde qualcuno, si rifiuta',
        () async {
      final vivo = '${tmp.path}/vivo.sock';
      final server = await ServerSocket.bind(
          InternetAddress(vivo, type: InternetAddressType.unix), 0);
      final file = '${tmp.path}/canale';
      File(file).writeAsStringSync('socket=$vivo\nsegreto=vecchio\n');

      await expectLater(
          CanaleSegreto.scriviNuovo(
              percorsoFile: file, socket: '${tmp.path}/mio.sock'),
          throwsA(isA<StateError>()),
          reason: 'quella sessione resterebbe senza demone');

      expect(File(file).readAsStringSync(), contains('segreto=vecchio'),
          reason: 'e il file deve essere ancora quello di prima, intatto');
      await server.close();
    });

    test('un socket rimasto per terra non ferma nessuno', () async {
      // Il caso del `kill -9`: il file c'è, il socket c'è come file, e dietro
      // non risponde nessuno. Rifiutarsi qui vorrebbe dire un demone che non
      // riparte più dopo un guasto — molto peggio del male che si cura.
      final morto = '${tmp.path}/morto.sock';
      File(morto).writeAsStringSync('');
      final file = '${tmp.path}/canale';
      File(file).writeAsStringSync('socket=$morto\nsegreto=vecchio\n');

      final segreto = await CanaleSegreto.scriviNuovo(
          percorsoFile: file, socket: '${tmp.path}/mio.sock');
      expect(segreto, isNotEmpty);
      expect(File(file).readAsStringSync(), contains('mio.sock'));
    });

    test('e un demone che riparte riscrive il PROPRIO indirizzo', () async {
      // Il caso normale, ed è quello che succede ogni volta che il guardiano
      // rimette in piedi il demone: stesso socket, segreto nuovo.
      final suo = '${tmp.path}/suo.sock';
      final server = await ServerSocket.bind(
          InternetAddress(suo, type: InternetAddressType.unix), 0);
      final file = '${tmp.path}/canale';
      File(file).writeAsStringSync('socket=$suo\nsegreto=vecchio\n');

      final segreto =
          await CanaleSegreto.scriviNuovo(percorsoFile: file, socket: suo);
      expect(segreto, isNotEmpty);
      expect(File(file).readAsStringSync(), isNot(contains('vecchio')),
          reason: 'la parola d\'ordine nuova deve aver preso il posto');
      await server.close();
    });
  });
}

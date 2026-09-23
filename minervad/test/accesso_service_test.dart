import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/accesso_service.dart';

// Tutto quello che questo servizio legge sta in file, quindi le prove si
// costruiscono la loro `/usr/share` e il loro `/etc/passwd` in una cartella
// temporanea. Nessuna prova tocca il sistema vero — e nessuna dipende da com'è
// fatto QUESTO computer, che è l'altro modo in cui una prova diventa inutile.
//
// Quello che c'è da provare non è la sessione scritta bene, ma le quattro
// scritte male: nascosta, con un programma che non c'è, con più sezioni, e
// illeggibile.

Future<File> _scrivi(Directory d, String nome, String contenuto) async {
  final f = File('${d.path}/$nome');
  await f.writeAsString(contenuto);
  return f;
}

void main() {
  late Directory tana;
  late Directory wayland;
  late Directory x11;

  setUp(() async {
    tana = await Directory.systemTemp.createTemp('minerva-accesso-prova');
    wayland = await Directory('${tana.path}/wayland-sessions').create();
    x11 = await Directory('${tana.path}/xsessions').create();
  });

  tearDown(() async => tana.delete(recursive: true));

// Le sessioni LETTE DAI FILE, senza la via di scorta che il servizio aggiunge
// sempre in fondo. Le prove qui sotto guardano come si legge una cartella di
// `.desktop`, e quella voce lì non c'entra: mescolarla renderebbe ogni conto
// più difficile da leggere e nasconderebbe l'unica cosa che stanno provando.
List<Sessione> soloScrivanie(List<Sessione> s) =>
    s.where((x) => x.tipo != 'tty').toList();

  AccessoService servizio({String? passwd, String? ritratti}) => AccessoService(
        cartelleWayland: [wayland.path],
        cartelleX11: [x11.path],
        filePasswd: passwd ?? '${tana.path}/passwd',
        cartellaRitratti: ritratti ?? '${tana.path}/icons',
      );

  group('Sessioni', () {
    test('legge nome, descrizione e comando', () async {
      await _scrivi(wayland, 'minerva.desktop', '''
[Desktop Entry]
Name=Minerva
Comment=Minerva Desktop Environment
Exec=/usr/local/bin/minerva-session
Type=Application
''');

      final s = soloScrivanie(await servizio().sessioni());

      expect(s, hasLength(1));
      expect(s.first.id, 'minerva');
      expect(s.first.nome, 'Minerva');
      expect(s.first.descrizione, 'Minerva Desktop Environment');
      expect(s.first.comando, '/usr/local/bin/minerva-session');
      expect(s.first.tipo, 'wayland');
    });

    test('legge DesktopNames, che diventerà XDG_CURRENT_DESKTOP', () async {
      // Fino al 17 agosto 2026 questa riga non la leggeva nessuno, e la
      // schermata di accesso avviava OGNI sessione con il solo
      // `XDG_SESSION_DESKTOP`: Plasma e Hyprland partivano senza sapere di
      // essere KDE e Hyprland, e i portali non sapevano a chi chiedere.
      await _scrivi(wayland, 'plasma.desktop', '''
[Desktop Entry]
Name=Plasma (Wayland)
DesktopNames=KDE
Exec=/usr/bin/startplasma-wayland
''');

      final s = await servizio().sessioni();
      expect(s.first.nomiScrivania, 'KDE');
    });

    test('più nomi restano come sono: è già il formato della variabile',
        () async {
      // `minerva.desktop` dichiara «Minerva;Hyprland;» — i nomi separati da
      // punto e virgola sono esattamente quello che `XDG_CURRENT_DESKTOP`
      // vuole. Spezzarli e ricomporli qui sarebbe lavoro per tornare al punto
      // di partenza.
      await _scrivi(wayland, 'minerva.desktop', '''
[Desktop Entry]
Name=Minerva
DesktopNames=Minerva;Hyprland;
Exec=/usr/local/bin/minerva-session
''');

      final s = await servizio().sessioni();
      expect(s.first.nomiScrivania, 'Minerva;Hyprland;');
    });

    test('senza DesktopNames si ripiega sul nome, mai sul vuoto', () async {
      // Una sessione che parte senza `XDG_CURRENT_DESKTOP` è una sessione che
      // non sa di esistere: meglio un nome approssimativo di niente.
      await _scrivi(wayland, 'sconosciuta.desktop', '''
[Desktop Entry]
Name=Qualcosa
Exec=/usr/bin/qualcosa
''');

      final s = await servizio().sessioni();
      expect(s.first.nomiScrivania, 'Qualcosa');
    });

    test('il comando resta intero anche con gli spazi dentro', () async {
      // Questo progetto vive in «…/Progetti/Minerva Shell». Una riga spezzata
      // sugli spazi qui dentro darebbe una sessione che non parte, e il
      // sintomo sarebbe uno schermo nero senza spiegazione.
      await _scrivi(wayland, 'prova.desktop', '''
[Desktop Entry]
Name=Prova
Exec=/home/tizio/Documenti/Minerva Shell/scripts/start.sh --con argomenti
''');

      final s = await servizio().sessioni();
      expect(s.first.comando,
          '/home/tizio/Documenti/Minerva Shell/scripts/start.sh --con argomenti');
    });

    test('salta le nascoste (Hidden e NoDisplay)', () async {
      await _scrivi(wayland, 'a.desktop',
          '[Desktop Entry]\nName=A\nExec=/bin/true\nHidden=true\n');
      await _scrivi(wayland, 'b.desktop',
          '[Desktop Entry]\nName=B\nExec=/bin/true\nNoDisplay=true\n');
      await _scrivi(wayland, 'c.desktop',
          '[Desktop Entry]\nName=C\nExec=/bin/true\n');

      final s = soloScrivanie(await servizio().sessioni());
      expect(s.map((x) => x.nome), ['C']);
    });

    test('salta quelle il cui TryExec non esiste', () async {
      await _scrivi(wayland, 'fantasma.desktop',
          '[Desktop Entry]\nName=Fantasma\nExec=/bin/true\nTryExec=/non/esisto\n');
      await _scrivi(wayland, 'vera.desktop',
          '[Desktop Entry]\nName=Vera\nExec=/bin/true\nTryExec=/bin/sh\n');

      final s = soloScrivanie(await servizio().sessioni());
      expect(s.map((x) => x.nome), ['Vera']);
    });

    test('non si fa ingannare dalle sezioni in fondo al file', () async {
      // `[Desktop Action …]` ha un suo `Name=` e un suo `Exec=`. Leggendo il
      // file di seguito senza guardare in che sezione si è, si finisce per
      // mostrare «Apri una finestra nuova» come nome della sessione.
      await _scrivi(wayland, 'x.desktop', '''
[Desktop Entry]
Name=Vero Nome
Exec=/bin/vero

[Desktop Action nuova]
Name=Apri una finestra nuova
Exec=/bin/sbagliato
''');

      final s = await servizio().sessioni();
      expect(s.first.nome, 'Vero Nome');
      expect(s.first.comando, '/bin/vero');
    });

    test('ignora le traduzioni: Name[it] non sostituisce Name', () async {
      await _scrivi(wayland, 'x.desktop',
          '[Desktop Entry]\nName=Session\nName[it]=Sessione\nExec=/bin/true\n');

      final s = await servizio().sessioni();
      expect(s.first.nome, 'Session');
    });

    test('senza Exec non è una sessione', () async {
      await _scrivi(wayland, 'monca.desktop', '[Desktop Entry]\nName=Monca\n');
      expect(soloScrivanie(await servizio().sessioni()), isEmpty);
    });

    test('un file illeggibile non fa sparire gli altri', () async {
      await _scrivi(wayland, 'rotto.desktop', '\x00\x01 non è testo');
      await _scrivi(wayland, 'buona.desktop',
          '[Desktop Entry]\nName=Buona\nExec=/bin/true\n');

      final s = await servizio().sessioni();
      expect(s.map((x) => x.nome), contains('Buona'));
    });

    test('wayland e x11 stanno insieme, con il tipo che li distingue',
        () async {
      await _scrivi(wayland, 'uguale.desktop',
          '[Desktop Entry]\nName=Uguale\nExec=/bin/w\n');
      await _scrivi(x11, 'uguale.desktop',
          '[Desktop Entry]\nName=Uguale\nExec=/bin/x\n');

      final s = soloScrivanie(await servizio().sessioni());
      expect(s, hasLength(2));
      expect(s.map((x) => x.tipo), ['wayland', 'x11']);
    });

    test('una cartella che non esiste vale come vuota', () async {
      final s = AccessoService(
        cartelleWayland: ['${tana.path}/non-c-e'],
        cartelleX11: const [],
        filePasswd: '${tana.path}/passwd',
      );
      expect(soloScrivanie(await s.sessioni()), isEmpty);
    });
  });

  group('Utenti', () {
    Future<String> passwd(String contenuto) async {
      final f = await _scrivi(tana, 'passwd', contenuto);
      return f.path;
    }

    test('tiene le persone e scarta i servizi', () async {
      final p = await passwd('''
root:x:0:0:root:/root:/bin/bash
daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin
http:x:33:33::/srv/http:/usr/bin/nologin
mario:x:1000:1000:Mario Bianchi,,,:/home/mario:/usr/bin/fish
ospite:x:1001:1001::/home/ospite:/bin/bash
nobody:x:65534:65534:Nobody:/:/usr/bin/nologin
''');

      final u = await servizio(passwd: p).utenti();

      expect(u.map((x) => x.nome), ['mario', 'ospite']);
      expect(u.first.uid, 1000);
      expect(u.first.casa, '/home/mario');
    });

    test('il nome per esteso viene dal GECOS, fermandosi alla prima virgola',
        () async {
      final p = await passwd(
          'mario:x:1000:1000:Mario Bianchi,ufficio 3,555,555:/home/mario:/bin/sh\n');

      final u = await servizio(passwd: p).utenti();
      expect(u.first.nomeCompleto, 'Mario Bianchi');
    });

    test('senza GECOS il nome per esteso è vuoto, non «x»', () async {
      final p = await passwd('tizio:x:1000:1000::/home/tizio:/bin/sh\n');
      final u = await servizio(passwd: p).utenti();
      expect(u.first.nomeCompleto, '');
    });

    test('scarta chi ha una shell che non entra', () async {
      final p = await passwd('''
bloccato:x:1000:1000::/home/bloccato:/usr/bin/nologin
falso:x:1001:1001::/home/falso:/bin/false
vero:x:1002:1002::/home/vero:/bin/bash
''');

      final u = await servizio(passwd: p).utenti();
      expect(u.map((x) => x.nome), ['vero']);
    });

    test('trova il ritratto di AccountsService', () async {
      final icone = await Directory('${tana.path}/icons').create();
      await _scrivi(icone, 'mario', 'finta immagine');
      final p = await passwd('mario:x:1000:1000::/home/mario:/bin/sh\n');

      final u = await servizio(passwd: p, ritratti: icone.path).utenti();
      expect(u.first.ritratto, '${icone.path}/mario');
    });

    test('ripiega su ~/.face', () async {
      final casa = await Directory('${tana.path}/casa').create();
      await _scrivi(casa, '.face', 'finta immagine');
      final p = await passwd('tizio:x:1000:1000::${casa.path}:/bin/sh\n');

      final u = await servizio(passwd: p).utenti();
      expect(u.first.ritratto, '${casa.path}/.face');
    });

    test('senza ritratto risponde vuoto invece di un percorso che non apre',
        () async {
      final p = await passwd('tizio:x:1000:1000::/home/tizio:/bin/sh\n');
      final u = await servizio(passwd: p).utenti();
      expect(u.first.ritratto, '');
    });

    test('una riga malformata non fa cadere le altre', () async {
      final p = await passwd('''
questa non ha i due punti
mario:x:1000:1000::/home/mario:/bin/sh
:::::::
''');

      final u = await servizio(passwd: p).utenti();
      expect(u.map((x) => x.nome), ['mario']);
    });

    test('un /etc/passwd che non esiste dà un elenco vuoto', () async {
      final u = await servizio(passwd: '${tana.path}/non-c-e').utenti();
      expect(u, isEmpty);
    });
  });

  // ── La via di scorta ─────────────────────────────────────────────────
  //
  // Giacomo, 23 agosto 2026: «magari aggiungere un accesso con solo il
  // terminale in caso ci siano errori con il desktop environment, per non
  // rimanere esclusi in caso non ci sia un desktop environment o si rompa».
  //
  // Non è teoria: fino a ieri KDE non entrava, e due volte una sessione morta
  // ha lasciato questo computer con uno schermo nero e nessuna strada.
  group('la riga di comando come ultima spiaggia', () {
    test('c\'è anche quando non c\'è nessuna scrivania installata', () async {
      final s = await servizio().sessioni();
      expect(s, hasLength(1));
      expect(s.single.id, AccessoService.idConsole);
      expect(s.single.tipo, 'tty');
    });

    test('sta in fondo, mai davanti alle scrivanie vere', () async {
      await _scrivi(wayland, 'minerva.desktop',
          '[Desktop Entry]\nName=Minerva\nExec=/usr/local/bin/minerva-session\n');
      final s = await servizio().sessioni();
      expect(s.last.id, AccessoService.idConsole);
      expect(s.first.id, 'minerva');
    });

    test('non dichiara nessuna scrivania: non È una scrivania', () async {
      // Se dichiarasse un nome, quello finirebbe in `XDG_CURRENT_DESKTOP` e i
      // portali xdg si metterebbero a cercare una scrivania che non esiste.
      expect(AccessoService.console.nomiScrivania, isEmpty);
    });

    test('avvia la shell VERA di chi entra, non una scritta a mano', () async {
      // La sostituisce la shell di greetd, che a quel punto ha già l'ambiente
      // di PAM. Con un ripiego, perché una variabile che manca non deve
      // diventare l'ennesimo modo di non entrare.
      expect(AccessoService.console.comando, contains(r'${SHELL:-/bin/sh}'));
      expect(AccessoService.console.comando, contains('/bin/sh'));
    });

    test('una scrivania che si chiamasse davvero così vince lei', () async {
      // La sua è vera, la nostra è di scorta: due voci con lo stesso id
      // farebbero scegliere a caso quale delle due si avvia.
      await _scrivi(wayland, 'console.desktop',
          '[Desktop Entry]\nName=Console vera\nExec=/bin/vero\n');
      final s = await servizio().sessioni();
      expect(s.where((x) => x.id == AccessoService.idConsole), hasLength(1));
      expect(s.single.nome, 'Console vera');
    });
  });

  // ── Chi avvia la sessione ────────────────────────────────────────────
  //
  // La schermata chiede al demone se l'avviatore c'è, e se non c'è avvia come
  // prima. La regola dietro a queste tre prove è una sola, e in una schermata
  // di accesso vale più di tutto il resto: **niente di quello che aggiungiamo
  // può diventare un motivo per non entrare.**
  group('l\'avviatore di sessione', () {
    late Directory tana;
    setUp(() => tana = Directory.systemTemp.createTempSync('minerva-avvio-'));
    tearDown(() => tana.deleteSync(recursive: true));

    test('se non c\'è, si dice di no invece di sollevare', () async {
      expect(
          await AccessoService.avviatoreDisponibile(
              percorso: '${tana.path}/non-c-e'),
          isFalse);
    });

    test('se c\'è ma non è eseguibile, vale come se non ci fosse', () async {
      // Dirlo presente sarebbe peggio che dirlo assente: greetd proverebbe a
      // eseguirlo, fallirebbe, e la sessione non partirebbe affatto — cioè
      // il difetto che tutto questo serve a curare, causato dalla cura.
      final f = File('${tana.path}/avviatore')..writeAsStringSync('#!/bin/sh\n');
      await Process.run('chmod', ['644', f.path]);
      expect(await AccessoService.avviatoreDisponibile(percorso: f.path),
          isFalse);
    });

    test('se c\'è ed è eseguibile, si dice di sì', () async {
      final f = File('${tana.path}/avviatore')..writeAsStringSync('#!/bin/sh\n');
      await Process.run('chmod', ['755', f.path]);
      expect(await AccessoService.avviatoreDisponibile(percorso: f.path),
          isTrue);
    });
  });
}

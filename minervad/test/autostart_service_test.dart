import 'dart:io';

import 'package:minervad/services/autostart_service.dart';
import 'package:test/test.dart';

/// Prove sui programmi che partono con la sessione.
///
/// Le due cartelle sono finte e stanno dentro una temporanea: provare contro
/// `/etc/xdg/autostart` vero vorrebbe dire che l'esito cambia a seconda di
/// quali pacchetti sono installati sulla macchina — e provare contro
/// `~/.config/autostart` vero vorrebbe dire scriverci dentro.
void main() {
  late Directory temp;
  late AutostartService avvio;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-avvio-');
    await Directory('${temp.path}/utente').create();
    await Directory('${temp.path}/sistema').create();
    avvio = AutostartService(
      cartellaUtente: '${temp.path}/utente',
      cartelleSistema: ['${temp.path}/sistema'],
    );
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<void> voce(String dove, String file, String contenuto) async {
    await File('${temp.path}/$dove/$file').writeAsString(contenuto);
  }

  Future<Map<String, dynamic>?> cerca(String file) async {
    for (final v in await avvio.elenco()) {
      if (v['file'] == file) return v;
    }
    return null;
  }

  group('leggere', () {
    test('legge nome, comando e provenienza', () async {
      await voce('utente', 'nota.desktop',
          '[Desktop Entry]\nType=Application\nName=Nota\nExec=nota --avvio\n');

      final v = await cerca('nota.desktop');

      expect(v, isNotNull);
      expect(v!['nome'], 'Nota');
      expect(v['exec'], 'nota --avvio');
      expect(v['utente'], isTrue);
      expect(v['acceso'], isTrue);
    });

    test('senza Exec la voce non esiste', () async {
      // Un `.desktop` senza comando non è un programma da avviare: mostrarlo
      // vorrebbe dire offrire una levetta che non fa partire niente.
      await voce('utente', 'vuota.desktop',
          '[Desktop Entry]\nType=Application\nName=Vuota\n');

      expect(await cerca('vuota.desktop'), isNull);
    });

    test('legge solo la sezione [Desktop Entry]', () async {
      // Le «azioni» di un `.desktop` hanno un `Exec` proprio. Chi legge il
      // file riga per riga senza guardare le sezioni fa partire l'azione
      // invece del programma.
      await voce(
          'utente',
          'azioni.desktop',
          '[Desktop Entry]\nType=Application\nName=Vero\nExec=quello-giusto\n'
          '\n[Desktop Action nuova]\nName=Falso\nExec=quello-sbagliato\n');

      final v = await cerca('azioni.desktop');

      expect(v!['exec'], 'quello-giusto');
      expect(v['nome'], 'Vero');
    });

    test('Hidden=true risulta spenta', () async {
      await voce('utente', 'ferma.desktop',
          '[Desktop Entry]\nName=Ferma\nExec=x\nHidden=true\n');

      expect((await cerca('ferma.desktop'))!['acceso'], isFalse);
    });

    test('la convenzione di GNOME vale come Hidden', () async {
      await voce('utente', 'gnomica.desktop',
          '[Desktop Entry]\nName=G\nExec=x\nX-GNOME-Autostart-enabled=false\n');

      expect((await cerca('gnomica.desktop'))!['acceso'], isFalse);
    });

    test('TryExec verso un programma che non c\'è la spegne, e lo dice',
        () async {
      await voce('utente', 'assente.desktop',
          '[Desktop Entry]\nName=A\nExec=x\nTryExec=/questo/non/esiste\n');

      final v = await cerca('assente.desktop');

      expect(v!['acceso'], isFalse);
      expect(v['motivo'], contains('non è installato'));
    });

    test('una voce di un altro ambiente resta spenta', () async {
      await voce('utente', 'gnomeonly.desktop',
          '[Desktop Entry]\nName=G\nExec=x\nOnlyShowIn=GNOME;\n');
      await voce('utente', 'nonqui.desktop',
          '[Desktop Entry]\nName=N\nExec=x\nNotShowIn=Hyprland;\n');
      await voce('utente', 'perNoi.desktop',
          '[Desktop Entry]\nName=P\nExec=x\nOnlyShowIn=Minerva;\n');

      await voce('utente', 'perNoiWayland.desktop',
          '[Desktop Entry]\nName=W\nExec=x\nOnlyShowIn=MinervaWayland;\n');

      expect((await cerca('gnomeonly.desktop'))!['acceso'], isFalse);
      expect((await cerca('nonqui.desktop'))!['acceso'], isFalse);
      // Minerva si dichiara con più nomi insieme: una voce scritta per uno
      // qualunque di quelli deve valere.
      expect((await cerca('perNoi.desktop'))!['acceso'], isTrue);
      // ── E «MinervaWayland», che è il PRIMO dei nomi ────────────────────
      //
      // Il filtro aveva un elenco scritto a mano — `{'minerva', 'hyprland'}` —
      // fermo al 2 settembre 2026, il giorno in cui la sessione ha cominciato
      // a dichiararsi anche `MinervaWayland`. Una voce scritta per la
      // scrivania su cui gira risultava «di un altro ambiente» a casa sua.
      //
      // Adesso i nomi si leggono da `XDG_CURRENT_DESKTOP`, che è dove li
      // scrive la sessione: questa prova passa sia dentro Minerva sia in un
      // terminale spoglio, e prima del 3 settembre 2026 falliva in tutte e due.
      expect((await cerca('perNoiWayland.desktop'))!['acceso'], isTrue,
          reason: 'XDG_CURRENT_DESKTOP = '
              '${Platform.environment['XDG_CURRENT_DESKTOP']}');
    });

    test('le voci di sistema si vedono ma risultano SPENTE', () async {
      // «Acceso» vuol dire «parte», non «il file non è disabilitato». Una
      // voce di sistema non parte, perché Minerva quella cartella non la
      // legge: mostrarla accesa farebbe credere che `baloo_file` stia
      // indicizzando il disco mentre non sta girando affatto.
      await voce('sistema', 'baloo.desktop',
          '[Desktop Entry]\nName=Baloo\nExec=baloo_file\n');

      final v = await cerca('baloo.desktop');

      expect(v, isNotNull);
      expect(v!['utente'], isFalse);
      expect(v['acceso'], isFalse);
    });

    test('accendere una voce di sistema la fa diventare tua, e accesa',
        () async {
      await voce('sistema', 'utile.desktop',
          '[Desktop Entry]\nName=Utile\nExec=utile\n');

      final r = await avvio.imposta('utile.desktop', true);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      final v = await cerca('utile.desktop');
      expect(v!['utente'], isTrue);
      expect(v['acceso'], isTrue);
      expect(v['copre'], isTrue);
    });

    test('la copia dell\'utente scavalca quella di sistema', () async {
      await voce('sistema', 'doppia.desktop',
          '[Desktop Entry]\nName=Di sistema\nExec=vecchio\n');
      await voce('utente', 'doppia.desktop',
          '[Desktop Entry]\nName=Mia\nExec=nuovo\n');

      final tutte = await avvio.elenco();
      final doppie = tutte.where((v) => v['file'] == 'doppia.desktop');

      expect(doppie.length, 1);
      expect(doppie.first['nome'], 'Mia');
      expect(doppie.first['copre'], isTrue);
    });
  });

  group('accendere e spegnere', () {
    test('spegnere scrive Hidden=true', () async {
      await voce('utente', 'x.desktop', '[Desktop Entry]\nName=X\nExec=x\n');

      final r = await avvio.imposta('x.desktop', false);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect((await cerca('x.desktop'))!['acceso'], isFalse);
    });

    test('riaccendere rimette Hidden=false, non aggiunge una seconda riga',
        () async {
      await voce('utente', 'x.desktop',
          '[Desktop Entry]\nName=X\nExec=x\nHidden=true\n');

      await avvio.imposta('x.desktop', true);

      final testo = await File('${temp.path}/utente/x.desktop').readAsString();
      expect('Hidden='.allMatches(testo).length, 1);
      expect((await cerca('x.desktop'))!['acceso'], isTrue);
    });

    test('spegnere una voce di sistema ne fa una copia, non la cancella',
        () async {
      // È la cosa che va per forza fatta così: `/etc/xdg/autostart` non è
      // scrivibile e non deve esserlo.
      await voce('sistema', 'sist.desktop',
          '[Desktop Entry]\nName=Sistema\nExec=cosa\n');

      final r = await avvio.imposta('sist.desktop', false);

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await File('${temp.path}/utente/sist.desktop').exists(), isTrue);
      expect(await File('${temp.path}/sistema/sist.desktop').exists(), isTrue);
      expect((await cerca('sist.desktop'))!['acceso'], isFalse);
    });

    test('accendere rimette d\'accordo anche la riga di GNOME', () async {
      // Senza questo si accende una voce che resta spenta: la levetta dice
      // «acceso» e il programma non parte, che è il peggior modo di fallire.
      await voce('utente', 'g.desktop',
          '[Desktop Entry]\nName=G\nExec=x\nX-GNOME-Autostart-enabled=false\n');

      await avvio.imposta('g.desktop', true);

      expect((await cerca('g.desktop'))!['acceso'], isTrue);
    });

    test('una voce che non esiste da nessuna parte dà un errore', () async {
      final r = await avvio.imposta('mai-vista.desktop', true);
      expect(r['ok'], isFalse);
    });
  });

  group('aggiungere e togliere', () {
    test('aggiungere crea una voce accesa', () async {
      final r = await avvio.aggiungi('Il mio programma', 'mio-programma --qui');

      expect(r['ok'], isTrue, reason: '${r['error']}');
      final v = await cerca(r['file']);
      expect(v!['nome'], 'Il mio programma');
      expect(v['exec'], 'mio-programma --qui');
      expect(v['acceso'], isTrue);
    });

    test('un nome con barre non scrive fuori dalla cartella', () async {
      // `../../.bashrc` come nome non deve poter diventare un percorso.
      final r = await avvio.aggiungi('../../cattivo', 'x');

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect((r['file'] as String).contains('/'), isFalse);
      expect(await File('${temp.path}/utente/${r['file']}').exists(), isTrue);
    });

    test('due voci con lo stesso nome non si sovrascrivono', () async {
      final a = await avvio.aggiungi('Uguale', 'uno');
      final b = await avvio.aggiungi('Uguale', 'due');

      expect(a['file'], isNot(b['file']));
      expect((await cerca(a['file']))!['exec'], 'uno');
      expect((await cerca(b['file']))!['exec'], 'due');
    });

    test('senza comando non si aggiunge niente', () async {
      final r = await avvio.aggiungi('Nome', '   ');
      expect(r['ok'], isFalse);
    });

    test('togliere cancella la voce dell\'utente', () async {
      await voce('utente', 'via.desktop', '[Desktop Entry]\nName=V\nExec=x\n');

      final r = await avvio.togli('via.desktop');

      expect(r['ok'], isTrue, reason: '${r['error']}');
      expect(await cerca('via.desktop'), isNull);
    });

    test('togliere non accetta percorsi', () async {
      final r = await avvio.togli('../../../etc/passwd');
      expect(r['ok'], isFalse);
    });

    test('togliere la copia di una voce di sistema la fa tornare com\'era',
        () async {
      await voce('sistema', 'sist.desktop',
          '[Desktop Entry]\nName=Sistema\nExec=cosa\n');
      await avvio.imposta('sist.desktop', false);

      await avvio.togli('sist.desktop');

      final v = await cerca('sist.desktop');
      expect(v, isNotNull);
      expect(v!['utente'], isFalse);
      // Torna a essere una voce di sistema, quindi di nuovo spenta: non
      // parte più, ed è esattamente com'era prima che la si toccasse.
      expect(v['acceso'], isFalse);
    });
  });
}

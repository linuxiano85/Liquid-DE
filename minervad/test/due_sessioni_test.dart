import 'dart:io';
import 'package:test/test.dart';

// La sessione di Minerva, e i portali che deve trovare.
//
// ── C'erano DUE sessioni, e adesso una ────────────────────────────────────
//
// Minerva si avviava in due modi: `start-minerva.sh` accendeva Hyprland, che
// leggeva `config/hyprland.conf`; `start-minerva-wayland.sh` accende
// minerva-wayland, che **non legge nessun file** e riceve tutto da chi lo
// avvia.
//
// Due file con lo stesso mestiere in due lingue vanno alla deriva, e il
// 30 agosto 2026 la deriva si era già accumulata: **sette variabili
// d'ambiente** stavano solo nella sessione Hyprland — una di quelle,
// `QT_WAYLAND_DISABLE_WINDOWDECORATION`, si vedeva a occhio nudo. Metà di
// questo file era la guardia che le teneva allineate.
//
// Il 2 settembre 2026 la sessione Hyprland è sparita, dopo che Giacomo ha
// provato «Minerva (recupero)» dal login. Le prove del confronto se ne sono
// andate con lei: confrontare con un file che non esiste dice verde per
// costruzione.
//
// ── Quello che resta, e perché resta ──────────────────────────────────────
//
// I portali. Quel pezzo non riguardava le due sessioni: riguarda il fatto che
// `xdg-desktop-portal` sceglie il backend leggendo `XDG_CURRENT_DESKTOP`, e
// che sbagliando file **non dà nessun errore** — niente condivisione schermo,
// niente finestre «apri file», e le password di Chrome ricifrate con una
// chiave di ripiego. È il difetto che è già costato il portachiavi l'11
// agosto, ed è vivo esattamente come prima.

File _f(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

void main() {
  group('la sessione trova i propri portali', () {
    late String wayland;

    setUpAll(() {
      wayland = _f('scripts/start-minerva-wayland.sh').readAsStringSync();
    });

    test('la sessione nostra sceglie il proprio file dei portali', () {
      // Un portale con un backend che non sa parlare col compositore non dà
      // errore: niente condivisione schermo, niente finestre «apri file», in
      // silenzio. Il nome in testa a XDG_CURRENT_DESKTOP sceglie il file.
      expect(wayland, contains('XDG_CURRENT_DESKTOP=LiquidDE:'),
          reason: 'senza «LiquidDE» davanti, xdg-desktop-portal non trova\n'
              'liquidde-portals.conf.');

      final conf = _f('config/xdg-desktop-portal/liquidde-portals.conf');
      expect(conf.existsSync(), isTrue,
          reason: 'XDG_CURRENT_DESKTOP nomina LiquidDE ma il file dei '
              'portali non c\'è.');
      final testo = conf.readAsStringSync();
      expect(testo, contains('default=wlr'),
          reason: 'il backend di wlroots parla wlr-screencopy e xdg-output, che '
              'minerva-wayland implementa; quello di Hyprland no.');
      // Senza chi risponde ai segreti, Chrome ricifra le password con una
      // chiave di ripiego e alla sessione dopo le richiede.
      expect(testo, contains('org.freedesktop.impl.portal.Secret=gnome-keyring'),
          reason: 'senza questa riga si perde chi risponde ai segreti.');
    });

    test("e l'installatore lo mette davvero al suo posto", () {
      final inst = _f('scripts/install-minerva.sh').readAsStringSync();
      expect(inst, contains('liquidde-portals.conf'),
          reason: 'il file esiste nel progetto ma non viene installato: sulla '
              'macchina vera non lo leggerebbe nessuno.');
      expect(inst, contains('DesktopNames=LiquidDE;'),
          reason: 'la voce di sessione deve annunciare lo stesso nome che '
              'start-minerva-wayland.sh esporta, o il gestore di accesso e la '
              'sessione direbbero due cose diverse.');
    });
  });

  // ── Il puntatore per chi se lo disegna da sé ───────────────────────────
  //
  // Giacomo, 5 settembre 2026: «sono su google e nella lista dei risultati il
  // mouse non compare sulla pagina web, probabilmente ci sarà lo stesso
  // errore in molte altre app o pagine».
  //
  // Il compositore il puntatore lo disegna lui, e sulle finestre di Minerva
  // c'è sempre. Sopra una pagina web no: Firefox e Chrome se lo disegnano da
  // soli, col tema che leggono da `XCURSOR_THEME` o, in mancanza, dal nome
  // scritto nelle impostazioni di GTK. Lì c'era `breeze_cursors`, che su
  // questa macchina **non è installato**: lo cercavano, non lo trovavano, e
  // non disegnavano niente.
  //
  // Il nome quindi lo dice la sessione — e lo dice DOPO aver guardato se
  // quella cartella esiste. Un tema di puntatori che non c'è fa sparire il
  // puntatore, e sparito quello non lo si rimette col mouse.
  // ── Lo sfondo della schermata di accesso ───────────────────────────────
  //
  // Giacomo, 6 settembre 2026: «il cambio sfondo della login non fa comparire
  // lo sfondo ma nero, però il resto funziona».
  //
  // Il resto funziona perché sono numeri e interruttori, e un numero si copia.
  // Lo sfondo è un percorso, e quel percorso porta dentro la cartella
  // personale, che è `drwx------`: la schermata di accesso gira come utente
  // «greeter» e lì dentro non entra. Immagine illeggibile, schermo nero.
  //
  // Il ritratto utente lo stesso muro ce l'ha e non lo sbatte, perché viene
  // COPIATO in una cartella di sistema. Adesso lo sfondo fa uguale.
  group('la schermata di accesso si porta dietro lo sfondo', () {
    late String greetd;
    setUpAll(() => greetd = _f('scripts/minerva-greetd').readAsStringSync());

    test('il file viene copiato, non solo nominato', () {
      expect(greetd, contains('copia_sfondo'),
          reason: 'un percorso dentro /home la schermata di accesso non lo '
              'può leggere: le va portato il file');
      expect(greetd, contains('chown greeter:greeter'),
          reason: 'e la copia deve essere sua, o non la legge lo stesso');
    });

    test('e le impostazioni copiate puntano alla COPIA', () {
      // Copiare il file e lasciare scritto il percorso vecchio sarebbe fatica
      // sprecata: la schermata continuerebbe a cercarlo dove non può andare.
      final i = greetd.indexOf('copia_sfondo() {');
      expect(i, greaterThan(0));
      final corpo = greetd.substring(i);
      expect(corpo, contains('"wallpaper"'),
          reason: 'dopo la copia si riscrive dove il file è finito');
    });

    test('e si può portargliela senza reinstallare tutto', () {
      // `installa` rifà la copia della shell, il demone, greetd e PAM. Per
      // spostare una sfocatura di dieci pixel è sproporzionato — e
      // sproporzionato vuol dire che uno smette di ritoccarla.
      expect(greetd, contains('    aspetto)'),
          reason: 'serve un\'azione che tocchi SOLO l\'aspetto');
      final i = greetd.indexOf('    aspetto)');
      // Fino alla fine, se mancano cinquecento caratteri: l'azione sta in
      // fondo al file, e un `substring` che sfora è un rosso che parla di
      // indici invece che del difetto.
      final corpo = greetd.substring(
          i, i + 500 > greetd.length ? greetd.length : i + 500);
      expect(corpo, contains('copia_impostazioni'));
      expect(corpo, isNot(contains('scrivi_config')),
          reason: 'l\'aspetto non deve poter toccare COME si entra: se '
              'sbaglia, deve sbagliare un colore');
      expect(corpo, isNot(contains('prepara_pam')),
          reason: 'e men che meno PAM');
    });

    test('e la copia di ieri non resta in giro', () {
      final i = greetd.indexOf('copia_sfondo() {');
      final corpo = greetd.substring(i, i + 1600);
      expect(corpo, contains(r'rm -f "$STATO"/sfondo.'),
          reason: 'senza, in quella cartella finirebbero le fotografie di '
              'tutti i cambi d\'idea — e togliendo lo sfondo resterebbe '
              'quello di prima');
    });
  });

  group('il puntatore vale anche fuori da Minerva', () {
    late String sessione;
    setUpAll(() {
      sessione = _f('scripts/start-minerva-wayland.sh').readAsStringSync();
    });

    test('la sessione dice quale tema di puntatori usare', () {
      expect(sessione, contains('XCURSOR_THEME'),
          reason: 'senza, ogni programma che si disegna il puntatore da sé se '
              'lo va a cercare per conto proprio, e se sbaglia non lo disegna');
    });

    test('e lo dice solo dopo aver guardato se esiste', () {
      // È lo stesso controllo che `settings/MisuraPuntatore.qml` fa prima di
      // applicare un tema. Vale doppio qui: questa riga la legge OGNI
      // programma della sessione, non solo i nostri.
      expect(sessione, contains('/cursors'),
          reason: 'il nome va verificato su disco: la cartella `cursors` del '
              'tema deve esistere davvero');
      expect(sessione, contains('Adwaita'),
          reason: 'e serve un ripiego installato ovunque per quando quello '
              'chiesto non c\'è');
    });

    test('e la misura è quella scelta, non un numero scritto a mano', () {
      // Era `export XCURSOR_SIZE=24` fisso: chi sceglieva «Grande» in
      // Impostazioni vedeva crescere il puntatore solo sopra Minerva, perché
      // fuori lo disegnano gli altri con la misura che dice l'ambiente.
      expect(sessione, contains('cursorSize'),
          reason: 'la misura viene dalle impostazioni, come per il '
              'compositore');
      expect(sessione, isNot(contains('export XCURSOR_SIZE=24')),
          reason: 'il numero scritto a mano è la seconda verità che '
              'contraddice la prima');
    });
  });
}

// Una porta sola verso il compositore.
//
// L'11 agosto 2026 Giacomo ha detto: «passi successivi sarebbe creare le
// nostre regole diventando indipendenti da Hyprland». Il 29 luglio la stessa
// decisione era già stata presa e non scritta da nessuna parte: nel frattempo
// le chiamate dirette al compositore erano passate da 75 a 106, sparse in
// venticinque file. Una regola che nessuna prova controlla non è una regola.
//
// Questa la controlla.

import 'dart:io';
import 'package:test/test.dart';

/// La radice del progetto, da qualunque cartella si lancino le prove.
Directory _radice() {
  for (final base in ['.', '..', '../..']) {
    if (Directory('$base/minerva-shell').existsSync()) return Directory(base);
  }
  fail('non trovo minerva-shell/');
}

List<File> _qml() {
  final fuori = <File>[];
  for (final v in Directory('${_radice().path}/minerva-shell')
      .listSync(recursive: true, followLinks: false)) {
    if (v is File && v.path.endsWith('.qml')) fuori.add(v);
  }
  fuori.sort((a, b) => a.path.compareTo(b.path));
  return fuori;
}

/// Le righe di un file senza i commenti: `// …` e `/// …`. Serve perché metà
/// del valore di questo progetto sta nei commenti, e quasi tutti nominano
/// Hyprland per spiegare perché una cosa è fatta così. Contarli come legami
/// renderebbe la prova inutile — o, peggio, spingerebbe a cancellarli.
Iterable<String> _codice(File f) => f
    .readAsLinesSync()
    .where((r) => !r.trimLeft().startsWith('//'));

/// I due soli file che possono nominare Hyprland.
bool _eLaPorta(File f) =>
    f.path.endsWith('core/Compositore.qml') ||
    f.path.endsWith('core/Scorciatoia.qml');

/// I banchi di prova (`prove-*.qml`) non sono la scrivania: non girano mai in
/// una sessione, e non contano nel bilancio delle chiamate dirette.
///
/// Non è una scappatoia. Un banco che deve verificare COSA HA RICEVUTO il
/// compositore è obbligato a chiederlo al compositore: passando dalla porta
/// chiederebbe alla shell che cosa crede di avergli mandato, e proprio quella
/// differenza è il difetto che deve scoprire. `prove-luce.qml` esiste perché il
/// 17 agosto 2026 la shell era convintissima di aver acceso la luce notturna e
/// `decoration:screen_shader` era rimasto vuoto.
bool _eUnBanco(File f) => f.path.split('/').last.startsWith('prove-');

void main() {
  group('nessuno parla direttamente al compositore', () {
    test('solo la porta importa Quickshell.Hyprland', () {
      final colpevoli = <String>[];
      for (final f in _qml()) {
        if (_eLaPorta(f)) continue;
        if (_codice(f).any((r) => r.trim() == 'import Quickshell.Hyprland')) {
          colpevoli.add(f.path.split('minerva-shell/').last);
        }
      }
      expect(colpevoli, isEmpty,
          reason: 'importano Hyprland invece di passare da core/Compositore.qml.\n'
              'Se serve un TIPO di quel modulo (come GlobalShortcut), si\n'
              'incarta in core/, come `Scorciatoia.qml`.');
    });

    test("nessuno usa l'API Hyprland fuori dalla porta", () {
      final colpevoli = <String>[];
      final api = RegExp(r'\bHyprland\.[a-zA-Z]|target:\s*Hyprland\b');
      for (final f in _qml()) {
        if (_eLaPorta(f)) continue;
        for (final r in _codice(f)) {
          if (api.hasMatch(r)) {
            colpevoli.add('${f.path.split('minerva-shell/').last}: ${r.trim()}');
          }
        }
      }
      expect(colpevoli, isEmpty,
          reason: 'devono passare da Core.Compositore: le azioni con le sue\n'
              'funzioni, gli eventi col suo segnale `evento`.');
    });
  });

  group('la porta è una porta', () {
    late String porta;
    setUpAll(() =>
        porta = File('${_radice().path}/minerva-shell/core/Compositore.qml')
            .readAsStringSync());

    test('non tiene stato: si può usare anche dentro una nostra app', () {
      // Le nostre applicazioni girano in processi loro e non hanno nessun
      // motivo di tenere l'elenco delle finestre. Se la porta cominciasse a
      // conservare roba, aprire l'Anteprima costerebbe mezza shell.
      expect(porta, isNot(contains('property var finestre')));
      expect(porta, isNot(contains('Timer {')));
    });

    test('un solo punto scrive un comando per il compositore', () {
      // L'imbuto c'è ancora, ha solo cambiato nome. Era `_dispatch`, che
      // componeva una stringa per Hyprland; dal 1º settembre 2026 è `_nostro`,
      // che scrive una riga sul socket del nostro compositore. La regola non è
      // cambiata: una scrittura sola, così che cambiando compositore si
      // riscriva quella e le funzioni che la chiamano, senza andare a caccia
      // di stringhe sparse.
      final scritture = RegExp(r'canale\.write\(').allMatches(porta).length;
      expect(scritture, 2,
          reason: 'due sole scritture, e sono due cose diverse: `_nostro()` '
              'manda i verbi, e `onConnectedChanged` manda l\'iscrizione '
              '(`ascolta …`) una volta per collegamento. Una terza vuol dire '
              'che qualcuno ha composto una riga per conto suo.');
    });

    test("accetta l'indirizzo nudo e il selettore intero", () {
      // Nel codice esistevano tutte e due le forme (`0x55…` e `address:0x55…`).
      // Riconoscerle nella porta ha evitato di convertirne venti punti.
      expect(porta, contains('function _selettore(chi)'));
      expect(porta, contains("t.indexOf(\":\") >= 0 ? t : \"address:\" + t"));
    });
  });

  // ── E il DEMONE? ────────────────────────────────────────────────────────
  //
  // La porta di sopra riguarda il QML. Il demone ha la sua, ed è
  // `providers/compositor_provider.dart` con `HyprlandProvider` dietro: il
  // commento nel codice dice da sempre che si può scambiare con un
  // `NiriProvider` o un `CosmicProvider`.
  //
  // Solo che **nessuna prova lo controllava**, e questo progetto ha già
  // imparato cosa succede a una regola che nessuno verifica: fra il 29 luglio
  // e l'11 agosto 2026 le chiamate dirette al compositore erano salite da 75 a
  // 106 senza che nessuno disobbedisse — non c'era niente a cui obbedire.
  group('il demone parla Hyprland solo dove deve', () {
    List<File> fileDart() {
      final fuori = <File>[];
      for (final v in Directory('${_radice().path}/minervad/lib')
          .listSync(recursive: true, followLinks: false)) {
        if (v is File && v.path.endsWith('.dart')) fuori.add(v);
      }
      fuori.sort((a, b) => a.path.compareTo(b.path));
      return fuori;
    }

    /// Come per il QML: i commenti non contano. Metà del valore di questo
    /// progetto sta lì dentro, e quasi tutti nominano Hyprland per spiegare
    /// perché una cosa è fatta così.
    Iterable<String> codiceDart(File f) => f.readAsLinesSync().where((r) {
          final t = r.trimLeft();
          return !t.startsWith('//') && !t.startsWith('*');
        });

    /// Chi può ancora nominarlo, e perché: **nessuno**.
    ///
    /// Erano tre. Il provider di Hyprland è stato cancellato il 1º settembre
    /// 2026; `minerva_core.dart` ha smesso di essere una cucitura lo stesso
    /// giorno — non sceglie fra due provider, ne costruisce uno; e
    /// `scorciatoie.dart` ha perso `perHyprland()` il 2 settembre, insieme
    /// alla sessione Hyprland.
    ///
    /// Da qui in avanti un `hyprctl` in un file del demone non ha nessuna
    /// scusa: non c'è più niente dall'altra parte a cui parlare.
    bool puoNominarlo(File f) => false;

    test('nessun servizio lancia hyprctl per conto suo', () {
      final colpevoli = <String>[];
      for (final f in fileDart()) {
        if (puoNominarlo(f)) continue;
        for (final r in codiceDart(f)) {
          if (r.contains('hyprctl')) {
            colpevoli.add('${f.path.split('minervad/lib/').last}: ${r.trim()}');
          }
        }
      }
      expect(colpevoli, isEmpty,
          reason: 'il compositore si tocca SOLO dal provider: un servizio che '
              'lancia hyprctl da sé è un pezzo in più da riscrivere il giorno '
              'che si cambia compositore, e nessuno si ricorderà che è lì.');
    });

    test("l'interfaccia astratta non nomina Hyprland", () {
      // È la prova che ha trovato qualcosa il 19 agosto 2026: dentro
      // `compositor_provider.dart` c'era `allowedDispatchers`, ventidue
      // parole di Hyprland (`togglefloating`, `movetoworkspacesilent`,
      // `cyclenext`) nell'interfaccia che dovrebbe essere neutra — più il
      // metodo `dispatch()` che le usava, e che non chiamava mai nessuno.
      //
      // Un'astrazione che nomina il concreto non astrae: descrive.
      final f = File(
          '${_radice().path}/minervad/lib/providers/compositor_provider.dart');
      final righe = codiceDart(f);
      final parole = RegExp(r'hyprctl|[Hh]yprland|togglefloating|'
          r'movetoworkspace|killactive|cyclenext|togglespecialworkspace');
      final colpevoli =
          righe.where((r) => parole.hasMatch(r)).map((r) => r.trim()).toList();
      expect(colpevoli, isEmpty,
          reason: 'l\'interfaccia deve poter valere per un compositore '
              'qualunque: i nomi di Hyprland stanno nell\'implementazione.\n'
              '${colpevoli.join("\n")}');
    });
  });

  group('quel che resta da portare di là', () {
    // ── Il buco che questa prova aveva ──────────────────────────────────
    //
    // La prima versione cercava `"hyprctl"` — con le virgolette, cioè la
    // forma `command: ["hyprctl", …]`. Passava mentre **ventidue** chiamate
    // vivevano nell'altra forma, dentro le righe di shell:
    // `fireSh("hyprctl keyword … ")`. Una guardia che guarda solo da una
    // parte è peggio di nessuna guardia: dà per chiuso un confine aperto.
    //
    // Adesso conta la parola, ovunque stia.
    //
    // Le due che restano caricano e scaricano il plugin, e stanno dentro un
    // `sh` che fa anche altro: crea una SENTINELLA prima di caricare e la
    // toglie dopo, così una sessione che si spegne durante il carico non
    // riprova al riavvio. Il caricamento deve stare in mezzo a quelle due
    // cose. Portarlo fuori taglierebbe attraverso un'idea nostra, non
    // attraverso il substrato — ed è la regola di MODULI.md al contrario.
    //
    // Il tetto scende con il lavoro e non risale mai: è quello che è mancato
    // fra il 29 luglio e l'11 agosto, quando nessuno guardava.
    test('le chiamate a hyprctl non aumentano', () {
      var quante = 0;
      final sparse = <String>[];
      for (final f in _qml()) {
        if (_eLaPorta(f) || _eUnBanco(f)) continue;
        for (final r in _codice(f)) {
          if (r.contains('hyprctl')) {
            quante++;
            sparse.add(f.path.split('minerva-shell/').last);
          }
        }
      }
      expect(quante, lessThanOrEqualTo(2),
          reason: 'erano quarantuno l\'11 agosto 2026 contandole in tutte e due '
              'le forme, e devono solo calare.\n'
              'Trovate in: ${sparse.toSet().join(", ")}');
    });

    // ── I VERBI sono passati, i SOSTANTIVI no ───────────────────────────
    //
    // `Hyprland.dispatch` è a zero: le AZIONI passano tutte dalla porta. Ma
    // i nomi delle chiavi di configurazione — `decoration:blur:size`,
    // `input:touchpad:natural_scroll`, `animations:enabled` — sono ancora
    // vocabolario di Hyprland scritto dentro il nostro QML, e `imposta()`
    // li lascia passare così come sono: è un imbuto, non un traduttore.
    //
    // Il commento sopra `imposta()` promette che «chi cambia compositore ha
    // qui l'elenco completo di cosa deve tradurre». Il 19 agosto 2026 quella
    // promessa era falsa: l'elenco stava in **otto file**, non lì.
    //
    // E la dispersione ha già la forma che in luglio produsse tre
    // «ingrandisci» diversi: `animations:enabled` viene scritta da TRE file
    // che non si conoscono (Accessibilita, Shell, ControlPanel), e
    // `cursor:zoom_factor` da due.
    //
    // Questo tetto scende con il lavoro e non risale mai.
    test('le chiavi del compositore nominate fuori dalla porta non aumentano',
        () {
      var quante = 0;
      final sparse = <String>[];
      final chiamata = RegExp(r'\bimposta\(');
      for (final f in _qml()) {
        if (_eLaPorta(f) || _eUnBanco(f)) continue;
        for (final r in _codice(f)) {
          if (chiamata.hasMatch(r)) {
            quante++;
            sparse.add(f.path.split('minerva-shell/').last);
          }
        }
      }
      expect(quante, isZero,
          reason: 'erano ventisette il 19 agosto 2026, in otto file, e la '
              'stessa mattina sono andate a zero: ogni chiave sta dietro '
              'un\'INTENZIONE della porta (`animazioni()`, `sfocatura()`, '
              '`margini()`, `schermo()`…), che è l\'unico posto dove può '
              'stare il nome che Hyprland le dà.\n'
              'Trovate in: ${sparse.toSet().join(", ")}');
    });
  });

  // ── Annunciare e non rispondere ────────────────────────────────────────
  //
  // Giacomo, 5 settembre 2026: «il puntatore quando sono su youtube non posso
  // vederlo se passo su un video, e anche su altre finestre come questo
  // terminale».
  //
  // Il compositore ANNUNCIAVA `cursor-shape-v1` — il protocollo con cui i
  // programmi moderni chiedono la forma del puntatore per nome — e non
  // ascoltava la richiesta. Nascondere il puntatore passa dal protocollo
  // vecchio (che ascoltavamo); rimetterlo passa da questo (che buttavamo
  // via). Quindi YouTube lo nascondeva sopra il video e non lo rimetteva
  // più, e Alacritty faceva lo stesso mentre si scrive.
  //
  // Annunciare un protocollo e non rispondergli è peggio che non annunciarlo:
  // il programma crede di aver chiesto e non chiede in nessun altro modo. È
  // la stessa famiglia del verbo che si può scrivere e non fa niente.
  group('i protocolli annunciati hanno qualcuno che risponde', () {
    late String main;
    setUpAll(() {
      final f = File('${_radice().path}/compositore/src/main.c');
      expect(f.existsSync(), isTrue, reason: 'non trovo compositore/src/main.c');
      main = f
          .readAsLinesSync()
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
    });

    test('la forma del puntatore viene ascoltata', () {
      expect(main, contains('wlr_cursor_shape_manager_v1_create'),
          reason: 'il protocollo si annuncia ancora');
      expect(main, contains('request_set_shape'),
          reason: 'e adesso qualcuno deve rispondere: senza, chi nasconde il '
              'puntatore non riesce piu\' a rimetterlo');
      expect(main, contains('wlr_cursor_shape_v1_name'),
          reason: 'il nome della forma si chiede a wlroots, non si inventa: '
              'un nome che il tema non conosce fa sparire il puntatore');
    });

    test('e solo chi ha il puntatore adesso puo\' cambiarne la forma', () {
      // La stessa guardia di `cursore_richiesto`: una finestra in secondo
      // piano non deve poter cambiare il puntatore mentre si lavora altrove.
      final i = main.indexOf('forma_cursore(struct wl_listener');
      expect(i, greaterThan(0), reason: 'non trovo il gestore della forma');
      final corpo = main.substring(i, i + 900);
      expect(corpo, contains('pointer_state.focused_client'),
          reason: 'senza questa riga, un programma in secondo piano cambia il '
              'puntatore fuori dal proprio turno');
    });
  });
}

import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/finestre_service.dart';

/// Un file della shell, cercato risalendo dalla cartella corrente.
File _qml(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/minerva-shell/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/$relativo');
}

/// Un file del demone, cercato risalendo dalla cartella corrente.
///
/// Le prove girano dentro `minervad/`, ma non sempre da lì: `dart test` può
/// essere invocato dalla radice del progetto.
File _dart(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    for (final base in [relativo, 'minervad/$relativo']) {
      final f = File('${dir.path}/$base');
      if (f.existsSync()) return f;
    }
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

/// Il testo senza i commenti: qui si controlla che certe cose siano SCRITTE nel
/// codice, e un commento che le nomina non è codice. Senza questo, ogni prova
/// passerebbe grazie al commento che spiega perché la regola esiste.
String _codice(String relativo) {
  return _qml(relativo)
      .readAsLinesSync()
      .where((r) => !r.trimLeft().startsWith('//'))
      .join('\n');
}

// ── Perché queste prove stanno nel demone e leggono il QML ─────────────────
//
// Perché non c'è nient'altro che possa leggerle. Sono regole che vivono
// dentro la shell, e la shell non ha un banco di prova suo: quello che ha è
// una sessione vera, dove ogni verifica costa un accesso e una schermata.
//
// Sono tutte e tre la stessa regola, scritta tre volte: LA RISPOSTA È IN UN
// POSTO SOLO. Ogni difetto che questo file custodisce è nato da una seconda
// copia della stessa domanda, e nessuno dei tre si vedeva guardando il codice
// — si vedeva solo guardando lo schermo, giorni dopo, sotto forma di una
// finestra fuori posto.
void main() {
  // ── Il cartello rosso che tornava, e la sua causa vera ──────────────────
  //
  // Giacomo, 19 agosto 2026, per l'ennesima volta: «ho ancora l'errore a
  // schermo».
  //
  //     Screen shader parser: Error compiling shader:
  //     0:1(1): error: syntax error, unexpected end of file
  //
  // Le due spiegazioni comode sono state provate sulla macchina e sono
  // **false**: `[[EMPTY]]` da solo non lo causa (messo a mano, schermo
  // pulito), e nemmeno il riavvio della shell né le prove della luce.
  //
  // Quello che lo causa è uno shader **vuoto** — verificato mettendone uno a
  // mano: il cartello compare. E il file generato si svuotava da sé, per
  // qualche millesimo, a OGNI scrittura: `sed … > "$file"` fa troncare il file
  // alla shell prima che `sed` cominci a scrivere.
  //
  // Il cartello poi resta appiccicato: non se ne va rimettendo `[[EMPTY]]`,
  // serve `hyprctl reload`. Quindi un istante sfortunato lascia a schermo un
  // errore che sembra permanente e che non corrisponde più a niente — ed è il
  // motivo per cui sembrava tornare «da solo».
  // ── L'interruttore delle animazioni deve toccarle TUTTE ─────────────────
  //
  // Giacomo, 19 agosto 2026: «la disabilitazione dalla barra sul desktop e
  // nelle impostazioni non porta a nessun cambiamento».
  //
  // Il movimento di Minerva viene da due posti: il COMPOSITORE anima le
  // finestre e le scrivanie, la SHELL anima pannelli, dock e menu con le
  // durate di `theme/Motion.qml`. L'interruttore ne spegneva uno solo, e
  // l'altro — quello che si nota di più — restava acceso.
  //
  // Il difetto è durato mesi perché non si vede leggendo il codice: c'era un
  // interruttore, scriveva l'impostazione, e chiamava una funzione che faceva
  // qualcosa. Semplicemente non tutto.
  group('le animazioni si spengono da tutte e due le parti', () {
    test('le durate della shell sono governate da una scala', () {
      final testo = _codice('theme/Motion.qml');
      expect(testo, contains('property real scala'),
          reason: 'senza una manopola, le durate sono numeri fissi e nessuna '
              'impostazione può toccarle: è il difetto segnalato.');
      for (final d in ['instant', 'quick', 'panel', 'surface', 'exit']) {
        expect(testo, contains('$d: Math.round('),
            reason: '«$d» non passa dalla scala: resterebbe animata anche con '
                'le animazioni spente.');
      }
    });

    test('e qualcuno le lega all\'impostazione', () {
      // Il legame non sta in `theme/Motion.qml`: un vocabolario del movimento
      // che va a leggere le preferenze è un vocabolario che non si può più
      // riusare dentro una nostra app. Stessa regola di `Typography.scala`.
      //
      // Fino al 3 settembre 2026 stava in `shell.qml`, insieme ad altri sei
      // legami ricopiati in sei file. Adesso sta in `theme/LegaTema.qml`, che
      // è un oggetto a sé e non un singleton: la regola vale ancora, perché
      // chi non lo instanzia non si porta dietro niente.
      final lega = _codice('theme/LegaTema.qml');
      expect(lega, contains('target: Theme.Motion'),
          reason: 'nessuno porta `desktop.animations` alle durate della shell');
      expect(lega, contains('desktop.animations'),
          reason: 'il legame deve guardare l\'impostazione vera');
      // E lo accende solo chi quelle durate le usa davvero.
      expect(_codice('shell.qml'), contains('animazioni: true'),
          reason: 'la shell deve chiederlo: senza, spegnere le animazioni non '
              'toccherebbe pannelli, dock e menu.');
    });
  });

  // ── Qui c'era il gruppo «la luce notturna non lascia mai uno shader a
  //    metà» ────────────────────────────────────────────────────────────
  //
  // Tre prove che sorvegliavano una catena di `sed` e `mv`: LuceNotturna.qml
  // generava un file `.frag`, lo scriveva di fianco e lo rinominava, perché
  // un rename nella stessa cartella è atomico e chi legge vede o il file di
  // prima o quello nuovo — mai uno vuoto. Il difetto vero, che le aveva fatte
  // scrivere, era un cartello di errore che restava appiccicato allo schermo
  // finché non si ricaricava il compositore.
  //
  // Il 1º settembre 2026 la catena è sparita tutta: la tinta si manda al
  // nostro compositore con un verbo, `coloreSchermo(r, g, b)`, e non c'è
  // nessun file da scrivere né nessuno shader da compilare. Una prova che
  // sorveglia una cosa che non esiste dice verde per costruzione, quindi le
  // tre se ne sono andate con lei — e al loro posto resta una guardia che
  // sorveglia il mondo che c'è: che non torni il file.
  group('la luce notturna non passa da nessun file', () {
    late String codice;
    setUpAll(() => codice = _codice('core/LuceNotturna.qml'));

    test('la tinta si manda al compositore, e basta', () {
      expect(codice, contains('Compositore.coloreSchermo('),
          reason: 'è l\'unico modo in cui la temperatura arriva allo schermo');
    });

    test('non si genera, non si scrive, non si sposta niente', () {
      for (final segno in [r'$g', 'mv ', 'Core.Exec', '.frag', 'screen_shader']) {
        expect(codice.contains(segno), isFalse,
            reason: 'torna «$segno» e torna con lui tutta la catena del file '
                'generato: la scrittura non atomica, lo shader che non compila '
                'e il cartello di errore che resta a schermo finché non si '
                'ricarica il compositore.');
      }
    });
  });

  group('finestre e spazio utile', () {
    test('schermo intero e ingrandita non si confondono', () {
      // In Hyprland `fullscreen` era un modo da 0 a 2, e trattare l'UNO (il
      // «massimizza») come schermo intero toglieva la barra alle finestre
      // ingrandite. Il nostro compositore manda due sì/no separati
      // (`schermoIntero`, `ingrandita`): la regola resta, detta nella nostra
      // lingua — «schermo intero» viene SOLO da `schermoIntero`.
      final testo = _codice('core/Compositore.qml');
      expect(testo, contains('"fullscreen": c.schermoIntero === true'),
          reason: 'lo schermo intero deve venire solo da `schermoIntero`: '
              'una finestra ingrandita che risulta a schermo intero perde la '
              'barra del titolo');
      expect(testo, contains('(c.ingrandita === true ? 1 : 0)'),
          reason: 'l\'ingrandita è il modo UNO, distinto dallo schermo intero');
    });

    test('lo spazio utile si rilegge, non si legge una volta sola', () {
      final testo = _codice('core/Windows.qml');
      final quante = 'refreshUsable()'.allMatches(testo).length;
      expect(quante, greaterThanOrEqualTo(3),
          reason: 'Le zone riservate le riserva la shell stessa: chiederle '
              'nell\'istante in cui il singleton nasce vuol dire chiederle '
              'PRIMA che la barra esista, e ricevere «riservato: niente» — '
              'per tutta la sessione. Da lì «ingrandisci» ferma ogni finestra '
              'sotto la barra della scrivania, con la propria barra del '
              'titolo nascosta e nessun modo di riprenderla col mouse. '
              'Servono almeno: la lettura iniziale, quella ritardata e '
              'quella periodica.');
    });

    test('la garanzia sullo spazio in cima sta in un posto solo', () {
      final finestre = _codice('core/Windows.qml');
      final barre = _codice('spine/TitleBars.qml');

      expect(finestre, contains('function assicuraSpazio()'),
          reason: 'Nessuna finestra deve poter finire sotto la barra della '
              'scrivania, e quanto spazio le serve sopra lo sa solo '
              '`barSopra()` — che sta qui.');
      expect(barre, contains('Core.Windows.assicuraSpazio()'),
          reason: 'La shell è l\'unico processo che deve applicarla: se la '
              'applicassero anche il gestore file e le Impostazioni, lo '
              'stesso comando partirebbe tre volte.');
      expect(barre, isNot(contains('reservedTop + bars.titleHeight')),
          reason: 'Qui c\'era il calcolo, e girava sulle sole finestre che '
              'ricevono una barra DA NOI: ne restavano fuori le finestre di '
              'Minerva e i programmi che la barra se la disegnano da soli — '
              'cioè proprio quelle che il difetto colpiva.');
    });

    test('la garanzia tace mentre una mano tiene una finestra', () {
      // Il difetto peggiore dei trascinamenti: la shell credeva la finestra
      // «parcheggiata» fuori dallo spazio utile e la spostava mentre la mano
      // la teneva — il compositore la riportava dov'era un fotogramma dopo,
      // e quello era lo sfarfallio. La shell ora sa quando un trascinamento
      // è in corso, e lo sa dall'annuncio del compositore.
      final finestre = _codice('core/Windows.qml');

      expect(finestre, contains('avvisaTrascinamento'),
          reason: 'La garanzia deve poter essere messa a tacere.');
      expect(finestre, contains('windows._trascinando'),
          reason: 'E il silenzio deve valere DENTRO `assicuraSpazio`: '
              'un interruttore che nessuno guarda non spegne niente.');
      expect(finestre, contains('n === "minervadrag"'),
          reason: 'La shell ascolta l\'annuncio del compositore.');
    });

    test('le zone di aggancio stanno dentro lo spazio utile', () {
      final barre = _codice('spine/TitleBars.qml');
      final zone = RegExp(r'function zoneRect\(zone\)\s*\{[\s\S]*?\n    \}')
          .firstMatch(barre);
      expect(zone, isNotNull, reason: 'non trovo zoneRect in TitleBars.qml');
      expect(zone!.group(0), contains('Core.Windows.usable'),
          reason: 'Il pannello delle barre copre lo schermo INTERO, zone '
              'riservate comprese. Calcolando le zone di aggancio sulla sua '
              'geometria, una finestra agganciata a sinistra o in alto finisce '
              'sotto la barra della scrivania insieme alla propria barra del '
              'titolo. Lo spazio in cui una finestra può stare lo dice il '
              'compositore, ed è lo stesso da cui dipende «ingrandisci»: se i '
              'due non coincidono, fra una finestra agganciata in alto e una '
              'ingrandita si vede il salto.');
    });

    test('la cornice della finestra non finisce fuori dallo schermo', () {
      // La cornice che Hyprland disegna sta FUORI dal rettangolo della
      // finestra: una finestra larga quanto lo spazio utile ha la propria
      // linea accesa per metà oltre il bordo dello schermo. Misurato l'11
      // agosto campionando i pixel: ingrandita dalla shell la linea non
      // c'era, ingrandita dal pulsante della barra sì.
      final finestre = _codice('core/Windows.qml');
      expect(finestre, contains('readonly property int bordo'),
          reason: 'Il numero deve stare in un posto solo: è lo stesso di '
              '`general:border_size` e di `borderSize` in TitleBars.qml.');
      expect(finestre, contains('(u.w - 2 * b)'),
          reason: '«Ingrandisci» deve lasciare fuori la cornice, o la linea '
              'accesa sparisce proprio quando la finestra è più visibile.');
      expect(_codice('spine/TitleBars.qml'), contains('Core.Windows.bordo'),
          reason: 'Anche l\'aggancio: una finestra agganciata a sinistra ha '
              'la cornice per metà fuori dallo schermo esattamente come una '
              'ingrandita.');
    });

    test('le tre strade dell\'aggancio danno la stessa finestra', () {
      // Agganciare una finestra passa da tre codici diversi, secondo chi le
      // disegna la barra del titolo:
      //
      //   · le finestre di Minerva          → `rectZona` in Windows.qml
      //   · le finestre altrui              → `aggancio.cpp` nel plugin
      //   · e «ingrandisci», che è l'aggancio in alto → `Windows.maximize`
      //
      // Se non danno lo stesso rettangolo, lo stesso gesto dà due risultati a
      // seconda del programma — e «mezzo schermo» smette di essere mezzo
      // schermo. La shell aveva otto pixel di margine su ogni lato, gli altri
      // due no.
      //
      // Il conto sta in un punto solo: `rectZona` in `core/Windows.qml`, che
      // `zoneRect` in TitleBars.qml si limita a chiamare — prima ognuno dei
      // tre faceva il conto per conto suo, e il test doveva sorvegliare che
      // le tre copie restassero uguali.
      final barre = _codice('spine/TitleBars.qml');
      expect(barre, contains('Core.Windows.rectZona(zone, u)'),
          reason: 'zoneRect non deve rifare il conto per conto suo: deve '
              'chiedere `rectZona`, o prima o poi le due copie si '
              'separano in silenzio.');
      final zone = RegExp(r'function rectZona\(zona, u\)\s*\{[\s\S]*?\n    \}')
          .firstMatch(_codice('core/Windows.qml'))!
          .group(0)!;
      expect(zone, isNot(contains('Theme.Effects.space')),
          reason: 'Un margine qui non lo hanno né `aggancio.cpp` né '
              '`maximize`: la finestra di Minerva si fermerebbe prima del '
              'bordo e quella altrui no, con lo stesso trascinamento.');
      expect(zone, contains('halfW'),
          reason: 'Metà schermo deve essere metà schermo: due finestre '
              'affiancate devono coprire tutto lo spazio utile senza '
              'grondaia in mezzo.');
      expect(zone, contains('case "top":   return { "x": u.x,         "y": u.y,         "w": u.w,    "h": u.h }'),
          reason: 'Trascinare in alto è «ingrandisci», e `Windows.maximize` '
              'riempie lo spazio utile intero: se qui si toglie qualcosa, fra '
              'i due gesti si vede il salto.');
    });
  });

  group('finestra attiva', () {
    test('non si chiede al modello di quickshell', () {
      final testo = _codice('core/Windows.qml');
      expect(testo, isNot(contains('Hyprland.activeToplevel')),
          reason: 'Quel modello va popolato con `refreshToplevels()`, che qui '
              'nessuno chiama — l\'elenco delle finestre si legge con '
              '`hyprctl clients`. Restava vuoto, e con lui la finestra '
              'attiva: nessuna barra del titolo si accendeva mai, la cornice '
              'della finestra correva con l\'accento e quella della barra no, '
              'e ogni comando senza indirizzo non faceva niente.');
    });

    test('arriva da due strade, e nessuna delle due da sola', () {
      final testo = _codice('core/Windows.qml');
      expect(testo, contains('activewindowv2'),
          reason: 'L\'evento porta l\'indirizzo e arriva subito: senza, fra il '
              'cambio di fuoco e la lettura successiva si vedono due finestre '
              'nello stesso stato.');
      expect(testo, contains('entry.stack === 0'),
          reason: '`focusHistoryID` vale 0 sulla finestra toccata per ultima, '
              'e c\'è in ogni lettura: è ciò che rimette a posto le cose se un '
              'evento si perde — una scrivania cambiata mentre la shell si '
              'ricarica, una finestra che c\'era già all\'avvio.');
    });
  });

  group('barre del titolo', () {
    test('la cornice della barra è quella della finestra', () {
      final barre = _codice('spine/TitleBars.qml');
      expect(barre, isNot(contains('Qt.rgba(1, 1, 1, 0.13)')),
          reason: 'La velatura della finestra non a fuoco deve andare nel '
              'verso del tema — bianca su fondo scuro, nera su fondo chiaro — '
              'come `Core.WindowRules.borderInactive`, o su un tema chiaro è '
              'bianco su bianco. Vedi `theme/Colors.qml`.');
      expect(barre, contains('x: -bars.borderSize'),
          reason: 'Hyprland disegna il bordo delle finestre all\'ESTERNO. '
              'Disegnando il proprio all\'interno, la linea d\'accento saliva '
              'lungo il fianco della finestra e faceva un gradino di due pixel '
              'dove cominciava la barra — che è ciò che la faceva sembrare una '
              'barra staccata, appoggiata sopra.');
    });

    test('le barre non sono contate: ci sono tutte', () {
      final barre = _codice('spine/TitleBars.qml');
      expect(barre, isNot(contains('slice(0, 6)')),
          reason: 'Il modello era tagliato a sei perché la maschera dei clic '
              'aveva sei rettangoli scritti a mano. Dalla settima finestra in '
              'poi la barra non era «non cliccabile»: era assente. Con le '
              'finestre libere sette finestre aperte sono una giornata '
              'normale.');
      expect(barre, contains('regions: bars.regioni'),
          reason: 'I rettangoli della maschera si creano uno per barra, così '
              'il numero delle barre disegnate e quello dei rettangoli '
              'cliccabili non possono più divergere.');
    });

    // ── Una regola sola, non una per finestra ────────────────────────────
    //
    // Giacomo, 4 settembre 2026, vedendo Minerva Media senza barra del titolo:
    // «ma non dovrebbe esserci in ogni app una regola del gestore finestre?
    // qui è come se ogni finestra avesse una regola a sé». Aveva ragione due
    // volte: la regola c'è ed è `ui/WindowTitleBar.qml`, e quella finestra se
    // n'era scritta una sua sopra.
    //
    // Il costo esatto: `height: palcoPieno ? 0 : implicitHeight`. Il
    // componente non dichiara `implicitHeight` — la sua altezza la decide
    // `windows.titleHeight` — e `implicitHeight` di un Item senza figli è
    // zero. Quindi la barra c'era, era `visible`, prendeva i clic, ed era alta
    // zero pixel. Nessun errore, nessun avviso: una finestra che si chiude
    // solo con Super+C.
    //
    // Questa prova non guarda l'altezza: guarda che nessuno RISCRIVA le due
    // proprietà con cui il componente decide se e quanto esistere.
    test('nessuna finestra si riscrive la barra del titolo per conto suo', () {
      final radice = _qml('ui/WindowTitleBar.qml').parent.parent;
      final colpevoli = <String>[];

      for (final f in radice
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final righe = f
            .readAsLinesSync()
            .where((r) => !r.trimLeft().startsWith('//'))
            .toList();
        for (var i = 0; i < righe.length; i++) {
          if (!righe[i].contains('Ui.WindowTitleBar {')) continue;
          // Il blocco di primo livello del componente: si scende finché le
          // graffe non si richiudono, e si guardano solo le righe rientrate
          // di uno — quelle dentro un figlio sono affari suoi.
          final dentro = ' ' * (righe[i].indexOf('Ui.WindowTitleBar') + 4);
          var livello = 0;
          for (var j = i; j < righe.length; j++) {
            livello += '{'.allMatches(righe[j]).length;
            livello -= '}'.allMatches(righe[j]).length;
            if (j > i && righe[j].startsWith('$dentro' 'visible:')) {
              colpevoli.add('${f.path.split('/').last}:${j + 1} visible');
            }
            if (j > i && righe[j].startsWith('$dentro' 'height:')) {
              colpevoli.add('${f.path.split('/').last}:${j + 1} height');
            }
            if (livello == 0) break;
          }
        }
      }

      expect(colpevoli, isEmpty,
          reason: 'Se e quanto è alta la barra del titolo lo decide '
              '`ui/WindowTitleBar.qml` per TUTTE le finestre: si nasconde da '
              'sé a schermo intero e fuori da Minerva, e la sua altezza è '
              '`windows.titleHeight`. Riscriverle da una finestra sola vuol '
              'dire che quella finestra ha una regola sua — ed è così che '
              'Minerva Media è rimasta senza barra. Chi ha bisogno che la '
              'barra sparisca in un altro caso lo aggiunga NEL componente.');
    });

    test('il titolo lascia posto ai pulsanti, non il doppio', () {
      final contenuto = _codice('ui/TitleBarContent.qml');
      expect(contenuto, contains('readonly property int ostacolo: Math.max('),
          reason: 'Da ogni lato l\'ostacolo è UNO — i pulsanti da una parte, '
              'l\'icona dall\'altra — e si sottraevano tutti e due da tutti e '
              'due i lati. Su una finestra da 350 pixel al titolo ne restavano '
              'due: nessuna finestra stretta ha mai mostrato il proprio nome.');
    });
  });

  group('barre coperte e trascinamento', () {
    test('una barra sfiorata si taglia, non si spegne', () {
      final testo = _codice('spine/TitleBars.qml');

      expect(testo.contains('coveredBy'), isFalse,
          reason: 'La vecchia regola spegneva la barra INTERA a qualunque '
              'sovrapposizione, anche di un pixel. Misurato: KCalc a '
              'x838..1478 con la barra a y187..229, Konsole davanti che '
              'finisce a x853 — quindici pixel su seicentoquaranta, e la barra '
              'spariva tutta. Era il difetto numero uno di Giacomo, quello di '
              'cui diceva «non ho capito quale sia la condizione nella quale '
              'succede»: la condizione era due finestre che si sovrappongono '
              'appena, e alternandosi si toglievano la maniglia a vicenda.');

      expect(testo, contains('function libero('),
          reason: 'ci vuole chi calcola la parte NON coperta');
      expect(testo, contains('clip: true'),
          reason: 'la barra va ritagliata, e per ritagliarla serve un '
              'contenitore che ritagli: `clip` agisce sui figli, non su sé '
              'stesso. Restringere la barra invece di tagliarla farebbe '
              'ricentrare titolo e pulsanti man mano che un\'altra finestra le '
              'passa davanti — peggio della barra che spariva.');
    });

    test('il punto di presa non fa salire la finestra', () {
      final testo = _codice('spine/TitleBars.qml');

      // `spingi()` mette la finestra a «cima della barra + titleHeight». Il
      // punto di presa deve quindi essere misurato dalla cima della BARRA, e
      // la correzione di un'altezza-di-barra serve SOLO alle finestre che la
      // barra ce l'hanno dentro.
      final press = RegExp(r'bars\.beginDrag\([\s\S]{0,400}?\);')
          .firstMatch(testo)
          ?.group(0);
      expect(press, isNotNull, reason: 'non trovo la chiamata a beginDrag');
      expect(press, contains('bars.dentro('),
          reason: 'Qui c\'era `m.y + bars.titleHeight` senza condizione, e '
              '`spingi()` aggiunge già un\'altezza di barra: insieme mettevano '
              'la finestra quarantadue pixel TROPPO IN ALTO a ogni '
              'trascinamento. Misurato col puntatore finto: KCalc da [700,300] '
              'trascinata di (-300,+150) finiva a [400,408] invece di '
              '[400,450].\n\n'
              'È il difetto che si vedeva come «spesso le finestre sono '
              'incollate alla barra»: basta spostare la stessa finestra due o '
              'tre volte — sale di quarantadue pixel per volta, arriva sotto '
              'la barra della scrivania, e lì `assicuraSpazio()` la ferma.\n\n'
              'Non si era visto perché la somma è GIUSTA per le finestre che '
              'hanno la barra dentro, cioè quelle già schiacciate in cima: '
              'proprio quelle su cui si stava lavorando quando il '
              'trascinamento è stato scritto.');
    });

    test('le coordinate del trascinamento partono dal pannello', () {
      final testo = _codice('spine/TitleBars.qml');
      expect(testo, contains('gabbia.x + bar.x + m.x'),
          reason: 'Da quando la barra sta DENTRO un contenitore che la '
              'ritaglia, `bar.x` è relativo a quello e non al pannello. Senza '
              'sommare la gabbia il trascinamento parte con uno scarto pari a '
              'quanto la barra è tagliata a sinistra — e a barra intera lo '
              'scarto è di due pixel: piccolo, costante, e quindi facile da '
              'guardare senza vederlo.');
    });
  });

  // ── Il confine fra la shell e il demone ────────────────────────────────
  //
  // Queste prove esistono per un guasto preciso, e vale la pena raccontarlo
  // perché è il tipo di guasto che nessuna prova precedente poteva vedere.
  //
  // La shell è stata riscritta per RICEVERE dal demone lo stato delle finestre
  // invece di andarselo a leggere: da `core/Windows.qml` sono spariti il
  // processo che lanciava `hyprctl clients` e il timer che rileggeva i monitor,
  // e al loro posto sono comparsi `Core.Ipc.requestWindows()` e
  // `requestMonitors()`. Metà giusta e finita.
  //
  // L'altra metà — le due azioni nel demone che dovevano rispondere — non è
  // mai stata scritta. Il risultato: la shell mandava `get_windows` a un
  // demone che non sapeva cosa fosse, il messaggio arrivava, non combaciava
  // con nessun ramo dello `switch`, e finiva nel silenzio. Nessun errore,
  // nessun avviso, nessuna traccia in nessun registro.
  //
  // E dallo schermo si vedeva questo: ZERO finestre. Nessuna barra del titolo
  // sopra nessuna finestra altrui, «ingrandisci» senza sapere dove fermarsi,
  // le finestre libere che nessuno teneva sotto la barra della scrivania.
  // Esattamente i sintomi che stavamo inseguendo da giorni per altre cause.
  //
  // La regola che queste prove custodiscono è una sola: OGNI AZIONE CHE LA
  // SHELL MANDA DEVE TROVARE QUALCUNO CHE RISPONDE. È l'unica cosa che i due
  // programmi non possono verificare da soli, perché ognuno è corretto per
  // conto proprio.
  group('shell e demone combaciano', () {
    test('ogni azione che la shell manda esiste nel demone', () {
      final ipc = _codice('core/Ipc.qml');
      final server = _dart('lib/ipc/websocket_server.dart').readAsStringSync();

      // Ogni `"action": "qualcosa"` scritto nel QML.
      final chieste = RegExp(r'"action"\s*:\s*"([a-z_]+)"')
          .allMatches(ipc)
          .map((m) => m.group(1)!)
          .toSet();
      expect(chieste, isNotEmpty,
          reason: 'nessuna azione trovata in core/Ipc.qml: '
              'la ricerca non funziona più e questa prova non prova niente');

      // Ogni `case 'qualcosa':` gestito nel demone…
      final gestite = RegExp(r"case '([a-z_]+)':")
          .allMatches(server)
          .map((m) => m.group(1)!)
          .toSet();

      // …e ogni `action == 'qualcosa'` gestito PRIMA dello switch.
      //
      // La regola che questa prova custodisce è «qualcuno risponde», non «c'è
      // un ramo dello switch»: `ciao` — la parola d'ordine del canale — si
      // gestisce al cancello, perché deve valere prima di ogni altra cosa e
      // per ogni azione, comprese quelle che qualcuno aggiungerà domani.
      // Cercando solo i `case` questa prova avrebbe chiesto di mettere un
      // ramo morto nello switch per farla tacere, che è il modo classico in
      // cui una prova comincia a mentire.
      gestite.addAll(RegExp(r"action == '([a-z_]+)'")
          .allMatches(server)
          .map((m) => m.group(1)!));

      final orfane = chieste.difference(gestite).toList()..sort();
      expect(orfane, isEmpty,
          reason: 'La shell manda queste azioni e nel demone non le gestisce '
              'nessuno: $orfane. Un messaggio che non combacia con nessun '
              'ramo dello switch non solleva niente — arriva e sparisce. Chi '
              'lo ha mandato aspetta per sempre una risposta che nessuno '
              'scriverà mai.');
    });

    test('ogni evento che la shell può ricevere, lo sa leggere', () {
      final ipc = _codice('core/Ipc.qml');
      final server = _dart('lib/ipc/websocket_server.dart').readAsStringSync();

      final chieste = RegExp(r'"action"\s*:\s*"([a-z_]+)"')
          .allMatches(ipc)
          .map((m) => m.group(1)!)
          .toSet();
      final letti = RegExp(r'case "([a-z_]+)":')
          .allMatches(ipc)
          .map((m) => m.group(1)!)
          .toSet();

      // Dove comincia ogni ramo dello switch, in ordine.
      final rami = RegExp(r"case '([a-z_]+)':").allMatches(server).toList();

      /// A quale azione appartiene un evento mandato alla posizione `pos`:
      /// l'ultimo `case` che lo precede. Nessuno se sta prima del primo —
      /// e allora è una spinta, non una risposta.
      String? azioneDi(int pos) {
        String? ultima;
        for (final r in rami) {
          if (r.start < pos) {
            ultima = r.group(1);
          } else {
            break;
          }
        }
        return ultima;
      }

      // ── Perché non basta «ogni evento va letto» ──────────────────────
      //
      // Il demone risponde anche a chi non è la shell: i plugin esterni
      // hanno le loro azioni (`get_state`, `publish_event`), e le loro
      // risposte la shell non ha nessun motivo di conoscerle. La regola
      // vera è più stretta e più utile: la shell deve saper leggere ciò
      // che PUÒ arrivarle — le spinte, e le risposte alle azioni che manda.
      final ignorati = <String>[];
      for (final m in RegExp(r"'event'\s*:\s*'([a-z_]+)'").allMatches(server)) {
        final evento = m.group(1)!;
        if (letti.contains(evento)) continue;

        final azione = azioneDi(m.start);
        final puoArrivare = azione == null || chieste.contains(azione);
        if (puoArrivare) ignorati.add('$evento (da ${azione ?? "spinta"})');
      }

      expect(ignorati..sort(), isEmpty,
          reason: 'Il demone può mandare questi eventi alla shell, e la shell '
              'non li legge: $ignorati. È lo stesso silenzio del caso opposto, '
              'dalla parte opposta: il messaggio arriva, nessun ramo lo '
              'riconosce, e la shell continua a mostrare quello che sapeva '
              'prima.');
    });

    test('lo stato delle finestre non passa dal bus a sottoscrizione', () {
      // `_broadcastEvent` manda solo a chi si è iscritto a quel tipo, e la
      // shell non si iscrive a niente: usa la lista predefinita. Mandare lo
      // stato delle finestre per quella strada vorrebbe dire dipendere da una
      // riga in un elenco dentro un'altra classe — e dimenticarla è di nuovo
      // una shell cieca senza un errore da nessuna parte.
      //
      // Va per la strada dei flussi, quella dell'avanzamento dei
      // trasferimenti: direttamente a tutti i client collegati.
      final server = _dart('lib/ipc/websocket_server.dart').readAsStringSync();
      expect(server, contains("_finestre.finestre.listen"),
          reason: 'lo stato delle finestre deve arrivare da FinestreService '
              'e andare a tutti i client, senza passare dal bus');
      expect(server, contains("_finestre.clienti(_clients.length)"),
          reason: 'il servizio deve sapere quanti processi guardano, '
              'altrimenti interroga il compositore anche quando non c\'è '
              'nessuno a cui raccontarlo');
      expect(server, contains('_finestre.spingiTutto()'),
          reason: 'chi si collega deve ricevere lo stato SUBITO: una finestra '
              'di Minerva aperta da sola su una scrivania ferma non vedrebbe '
              'mai arrivare un evento');
    });

    test('un\'azione sconosciuta si lamenta invece di sparire', () {
      final server = _dart('lib/ipc/websocket_server.dart').readAsStringSync();
      expect(server, contains('Azione sconosciuta'),
          reason: 'Senza un ramo predefinito che lo dica, shell e demone '
              'possono smettere di combaciare e nessuno se ne accorge. È '
              'esattamente come è passata inosservata la shell senza finestre: '
              'il messaggio arrivava e finiva nel silenzio.');
    });
  });

  group('interrogare il compositore', () {
    test('non si lancia nessun processo: si scrive sul socket', () {
      // Questa prova guardava `hyprland_provider.dart`, che il 1º settembre
      // 2026 è stato cancellato. La misura che l'aveva fatta scrivere però
      // vale ancora, e vale per QUALUNQUE provider: ogni `hyprctl` era un
      // processo che nasceva e moriva, 7,875 ms per lettura contro 0,389 ms
      // scrivendo sul socket. Il demone rilegge lo stato fino a sedici volte
      // al secondo mentre una finestra si muove — il 13% di un core invece
      // dello 0,6%.
      //
      // Quindi la prova si sposta sul provider che c'è, e diventa più severa:
      // non «niente hyprctl», ma **niente processi affatto**.
      final p =
          _dart('lib/providers/minerva/minerva_provider.dart').readAsStringSync();
      expect(p.contains('Process.run'), isFalse,
          reason: 'interrogare il compositore lanciando un processo costa '
              'venti volte di più, e qui si legge fino a sedici volte al '
              'secondo');
      expect(p, contains('InternetAddressType.unix'),
          reason: 'le interrogazioni vanno sul socket del compositore');
    });

    test('il passo di riposo si spegne a scrivania vuota', () {
      final s = _dart('lib/services/finestre_service.dart').readAsStringSync();
      expect(s, contains('_nessunaFinestra'),
          reason: 'Il passo di riposo costa 1,3% di un core, misurato. Senza '
              'finestre non c\'è niente da trascinare e quel costo non ha '
              'nessuna ragione di esserci — ed è proprio il caso in cui conta, '
              'un portatile lasciato su una scrivania vuota.');
    });

    test('la riconnessione al socket riconnette davvero', () {
      // Il difetto sorvegliato qui è nato in `HyprlandProvider` ed è stato
      // ricopiato pari pari in `MinervaProvider`, perché la forma è la stessa:
      // `start()` comincia con una guardia sul flag «sono acceso», e una
      // riconnessione che non azzera quel flag non riconnette niente. Caduto
      // il socket degli eventi, resta caduto per tutta la sessione — e siccome
      // TUTTO lo stato delle finestre passa da lì, vuol dire barre ferme sopra
      // finestre che si muovono, per sempre.
      //
      // Il provider di Hyprland non c'è più; la trappola sì.
      final p =
          _dart('lib/providers/minerva/minerva_provider.dart').readAsStringSync();
      final r = RegExp(r'void _riprendi\(\)\s*\{[\s\S]*?\n  \}')
          .firstMatch(p)
          ?.group(0);
      expect(r, isNotNull, reason: 'non trovo _riprendi()');
      expect(r, contains('_acceso = false'),
          reason: '`start()` comincia con `if (_acceso) return;`: senza '
              'azzerare il flag, la riconnessione chiama start() e start() '
              'torna subito senza fare niente.');
    });
  });

  group('icone dei programmi', () {
    test('cambiare tema rimanda anche l\'elenco dei programmi', () {
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4; i++) {
        final c = File('${dir.path}/lib/ipc/websocket_server.dart');
        if (c.existsSync()) {
          f = c;
          break;
        }
        dir = dir.parent;
      }
      expect(f, isNotNull, reason: 'non trovo lib/ipc/websocket_server.dart');

      final testo = f!.readAsStringSync();
      final metodo =
          RegExp(r'void _applyIconThemeFromSettings\(\)\s*\{[\s\S]*?\n  \}')
              .firstMatch(testo);
      expect(metodo, isNotNull,
          reason: 'non trovo _applyIconThemeFromSettings');
      expect(metodo!.group(0), contains("'event': 'icons'"));
      expect(metodo.group(0), contains("'event': 'all_apps'"),
          reason: 'Le icone di Minerva e quelle dei PROGRAMMI passano per due '
              'strade diverse, perché nascono in due posti diversi: le prime '
              'da un elenco di nomi nostro, le seconde dal campo `Icon=` di '
              'ogni file .desktop. Mandando solo le prime, si cambia tema e la '
              'dock resta identica — con le icone di prima, risolte una volta '
              'sola rispondendo a `get_all_apps`.');
    });

  });

  group('il passo del demone', () {
    test('un titolo che cambia non conta come finestra che si muove', () {
      // Un terminale con dentro un lavoro che gira riscrive il proprio titolo
      // dieci volte al secondo. Se quello contasse come movimento, il demone
      // resterebbe al passo veloce per sempre — e ogni lettura verrebbe
      // spedita a tutte le finestre di Minerva, che rifanno i conti delle
      // barre. Misurato a scrivania ferma: 96 letture al secondo invece di 7.
      const a = '[{"address": "0x1", "title": "- lavoro", "at": [10, 20]}]';
      const b = '[{"address": "0x1", "title": "\\ lavoro", "at": [10, 20]}]';
      expect(FinestreService.senzaTitoli(a), FinestreService.senzaTitoli(b));
    });

    test('spostare una finestra conta eccome', () {
      const fermo = '[{"address": "0x1", "title": "x", "at": [10, 20]}]';
      const mosso = '[{"address": "0x1", "title": "x", "at": [11, 20]}]';
      expect(FinestreService.senzaTitoli(fermo),
          isNot(FinestreService.senzaTitoli(mosso)));
    });

    test('e vale anche per «titolo», che è il nome di minerva-wayland', () {
      // Il filtro nominava solo `title`. Dentro il nostro compositore, dove il
      // campo si chiama `titolo`, non filtrava piu' niente — e un filtro che
      // non trova niente non da' errore: lascia passare tutto, e il demone
      // torna a sessanta millisecondi per sempre al primo terminale con la
      // rotellina animata.
      const a = '[{"id": "0x1", "titolo": "- lavoro", "x": 10}]';
      const b = '[{"id": "0x1", "titolo": "\\ lavoro", "x": 10}]';
      expect(FinestreService.senzaTitoli(a), FinestreService.senzaTitoli(b));

      const fermo = '[{"id": "0x1", "titolo": "x", "x": 10}]';
      const mosso = '[{"id": "0x1", "titolo": "x", "x": 11}]';
      expect(FinestreService.senzaTitoli(fermo),
          isNot(FinestreService.senzaTitoli(mosso)));
    });

    test('un titolo con le virgolette dentro non nasconde la geometria', () {
      // Se la cancellazione del titolo si fermasse alla prima virgolita
      // protetta, il resto della riga — dove c'è la posizione — finirebbe
      // dentro al titolo e ogni spostamento diventerebbe invisibile.
      const a = r'[{"title": "dice \"ciao\"", "at": [10, 20]}]';
      const b = r'[{"title": "dice \"ciao\"", "at": [99, 20]}]';
      expect(FinestreService.senzaTitoli(a),
          isNot(FinestreService.senzaTitoli(b)));
    });


    test('le Impostazioni non riportano il fuoco sotto il puntatore', () {
      // Fino al 27 settembre 2026 `settings/sections/Input.qml` riscriveva il
      // blocco `input` di Hyprland in `~/.config/hypr/minerva-input.conf`, e
      // questa prova pretendeva che ci fosse `follow_mouse = 2`: con `1`
      // bastava salvare un'impostazione del mouse perché il fuoco tornasse a
      // seguire il puntatore, e con due finestre sovrapposte spariva la barra
      // di quella davanti.
      //
      // Quel file non lo leggeva più nessuno ed è sparito. La scelta resta
      // (il fuoco si sposta cliccando: lo decide il compositore), e la
      // guardia resta nel verso che conta: le Impostazioni non devono né
      // parlare di `follow_mouse` né scrivere nella cartella di Hyprland.
      final qml = _qml('settings/sections/Input.qml').readAsStringSync();
      final righe = qml
          .split('\n')
          .where((r) => !r.trimLeft().startsWith('//'))
          .join('\n');
      expect(righe.contains('follow_mouse'), isFalse,
          reason: 'le Impostazioni tornano a decidere il fuoco del mouse');
      expect(righe.contains('.config/hypr') || righe.contains('/hypr"'), isFalse,
          reason: 'le Impostazioni scrivono nella cartella di Hyprland');
    });

  });
  group('centrare vuol dire centrare quello che si VEDE', () {
    late String windows;
    setUpAll(() => windows = _qml('core/Windows.qml').readAsStringSync());

    test('il blocco comprende barra e cornice, non solo la finestra', () {
      // La barra del titolo di Minerva sta FUORI dalla finestra, sopra.
      // Hyprland centra il rettangolo che conosce — la finestra senza barra —
      // e il blocco che l'occhio vede sporge in alto: il suo centro sale di
      // mezza barra, ventun pixel più in ALTO. Misurato il 12 agosto 2026 su
      // pavucontrol (blocco 212..654, centro 433, contro un centro vero di
      // 454): vale identico per la regola `center = true` e per il dispatcher
      // `centerwindow`.
      expect(windows, contains('function centra(address)'));
      expect(windows, contains('var altezzaBlocco = margine + w.h + 2 * b;'));
      expect(windows, contains('var larghezzaBlocco = w.w + 2 * b;'));
    });

    test('e poi dice dove va la FINESTRA, non il blocco', () {
      // Il compositore sa spostare la finestra: il margine della barra e il
      // bordo vanno riaggiunti dopo aver centrato il blocco, o si centra la
      // cosa giusta e si sposta quella sbagliata.
      expect(windows,
          contains('var y = u.y + Math.round((u.h - altezzaBlocco) / 2) + margine + b;'));
      expect(windows,
          contains('var x = u.x + Math.round((u.w - larghezzaBlocco) / 2) + b;'));
    });

    test('una finestra nata centrata da una regola viene corretta', () {
      // La regola `center = true` centra la finestra; la barra sta fuori da
      // lei. Alla nascita il centro coincide col centro dello spazio utile al
      // pixel: è così che si riconosce che è stata una regola e non il
      // programma.
      final regole = _qml('core/WindowRules.qml').readAsStringSync();
      expect(regole, contains('function _eraCentrata(w)'));
      expect(regole, contains('if (rules._eraCentrata(w))'));
      expect(regole, contains('Core.Windows.centra(w.address)'));
      expect(regole, contains('Core.Windows.barSopra(w) <= 0'),
          reason: 'senza barra non c\'è niente da correggere');
    });

    test('usa gli stessi due conti di «ingrandisci»', () {
      // `barSopra` e `bordo`: se un giorno cambia uno dei due, cambia in un
      // posto solo. Era questa la lezione dei tre «ingrandisci» diversi.
      expect(windows, contains('var margine = windows.barSopra(w);'));
      expect(windows, contains('var b = windows.bordo;'));
    });
  });

  group('nessuna finestra fantasma', () {
    late String windows;
    setUpAll(() => windows = _qml('core/Windows.qml').readAsStringSync());

    test('il modo «ingrandito» del compositore viene tolto', () {
      // Minerva quel modo non lo chiede MAI: «ingrandisci» qui è geometria.
      // Una finestra che ci si trova dentro ce l'ha messa qualcun altro, e in
      // quel modo il compositore manda l'ingresso a lei: le altre restano
      // disegnate e mute. Giacomo, 12 agosto 2026: «è diventata una finestra
      // fantasma, è sullo schermo ma non posso usarla».
      expect(windows, contains('function _niente_ingranditi_dal_compositore()'));
      expect(windows, contains('w.modoSchermo === 1 && !windows.disegnaLaSua(w.appClass)'));
      expect(windows, contains('Compositore.schermoIntero(w.address, false);'));
    });

    test('la guardia gira a ogni lettura, non solo con le barre della shell', () {
      // Stava dentro `assicuraSpazio()`, che la chiama `spine/TitleBars.qml`
      // — SPENTA quando le barre le disegna il plugin, cioè nella
      // configurazione normale. Una guardia in un posto che di solito non
      // gira non è una guardia.
      final i = windows.indexOf('windows.all = every;');
      final j = windows.indexOf('windows._niente_ingranditi_dal_compositore();');
      expect(i, greaterThan(0));
      expect(j, greaterThan(i),
          reason: 'va chiamata dove l\'elenco delle finestre viene riletto');
      expect(j - i, lessThan(80),
          reason: 'subito dopo, non in un altro punto del file');
    });

    test('non combatte all\'infinito con chi ci ricasca', () {
      // Un programma può richiedere il modo ogni volta che glielo si toglie.
      // Si corregge una volta per indirizzo, e ci si ricorda; quando torna
      // normale da sé, ci si dimentica.
      expect(windows, contains('property var _giaCorrette: []'));
      expect(windows, contains("windows._giaCorrette.indexOf(w.address) !== -1"));
    });

    test('non promette di ringrandirla', () {
      // C'era un «e poi la ingrandisco con i conti nostri»: partiva 150 ms
      // dopo, trovava l'elenco non ancora riletto e si tirava indietro —
      // sempre. Una cosa che a volte succede e a volte no è peggio di una che
      // non c'è.
      expect(windows, isNot(contains('_daRiingrandire')));
    });
  });

  group('le garanzie girano anche con le barre del compositore', () {
    late String windows;
    setUpAll(() => windows = _qml('core/Windows.qml').readAsStringSync());

    test('«nessuna finestra sotto la barra» non dipende più da TitleBars', () {
      // `assicuraSpazio()` aveva UN SOLO chiamante: `spine/TitleBars.qml`,
      // che è SPENTA quando le barre le disegna il plugin — cioè nella
      // configurazione normale di Minerva. La garanzia non girava.
      //
      // Dimostrato il 12 agosto 2026 mettendo una finestra a y=10: la sua
      // barra del titolo finiva a y=-32, fuori dallo schermo, e nessuno la
      // spostava. Collegata alla rilettura delle finestre: y=86, barra a 44.
      final i = windows.indexOf('windows.all = every;');
      final j = windows.indexOf('windows.assicuraSpazio();');
      expect(i, greaterThan(0));
      expect(j, greaterThan(i));
      expect(j - i, lessThan(1800),
          reason: 'va chiamata dove l\'elenco delle finestre viene riletto');
    });

    test('la porta non offre più il modo che fa le finestre fantasma', () {
      // Un attrezzo offerto è un attrezzo che qualcuno userà. `fullscreenstate
      // 1 -1` non serve a Minerva e ha già fatto danno una volta.
      final porta = _qml('core/Compositore.qml').readAsStringSync();
      expect(porta, isNot(contains('function ingrandimentoDelCompositore')));
      expect(porta, isNot(contains('"fullscreenstate " + (acceso ? "1" : "0")')));
    });
  });
}


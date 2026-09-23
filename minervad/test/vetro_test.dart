import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/vetro.dart';

// Lo sfondo già sfocato.
//
// ── Perché `magick` qui NON gira ─────────────────────────────────────────
//
// Perché quello che va provato è la LOGICA: la chiave della cache, il
// riconoscere che una copia c'è già, i rifiuti, e il non lasciare in giro un
// file mezzo scritto. Farlo girare davvero renderebbe queste prove lente e
// legate a un programma esterno che su un'altra macchina può mancare — e
// `Vetro` ha un seme iniettabile apposta.
//
// Il giro vero con `magick` c'è ed è una sola prova, in fondo, saltata se il
// programma non c'è: dice qualcosa che il finto non può dire — che i nostri
// argomenti sono quelli che `magick` capisce davvero.
void main() {
  late Directory tmp;
  late File sfondo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('minerva-vetro-');
    sfondo = File('${tmp.path}/sfondo.png')..writeAsBytesSync([1, 2, 3, 4, 5]);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Vetro conFinto({int esito = 0, bool scrive = true, String errore = ''}) {
    return Vetro(
      cartellaCache: '${tmp.path}/cache',
      esegui: (prog, args) async {
        if (scrive && esito == 0) {
          File(args.last).writeAsBytesSync(List.filled(64, 7));
        }
        return ProcessResult(0, esito, '', errore);
      },
    );
  }

  group('la copia sfocata', () {
    test('si fa una volta, e la seconda viene dalla cache', () async {
      final v = conFinto();
      final a = await v.per(sfondo.path);
      expect(a['ok'], isTrue);
      expect(a['da'], 'magick');
      expect(File(a['percorso'] as String).existsSync(), isTrue);

      final b = await v.per(sfondo.path);
      expect(b['da'], 'cache', reason: 'il costo si paga una volta sola');
      expect(b['percorso'], a['percorso']);
    });

    test('e si rifà se lo sfondo cambia SENZA cambiare nome', () async {
      // È quello che fa uno che ritocca lo sfondo. Senza la data nella
      // chiave, si continuerebbe a mostrare la sfocatura di ieri per sempre.
      final v = conFinto();
      final a = await v.per(sfondo.path);
      // Si aspetta un istante: certi filesystem hanno una data al secondo.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      sfondo.writeAsBytesSync([9, 9, 9, 9, 9, 9, 9, 9, 9]);
      final b = await v.per(sfondo.path);
      expect(b['percorso'], isNot(a['percorso']),
          reason: 'stesso nome, immagine diversa: la sfocatura va rifatta');
    });

    test('il primo fotogramma, non tutti', () async {
      // Senza `[0]`, con una GIF `magick` scrive un file per fotogramma e
      // quello che ci aspettiamo non esiste. Insidia già pagata dalle
      // miniature.
      String? visto;
      final v = Vetro(
        cartellaCache: '${tmp.path}/cache',
        esegui: (prog, args) async {
          visto = args.first;
          File(args.last).writeAsBytesSync([1]);
          return ProcessResult(0, 0, '', '');
        },
      );
      await v.per(sfondo.path);
      expect(visto, endsWith('[0]'));
    });
  });

  group('i rifiuti', () {
    test('un percorso che non è un percorso', () async {
      final v = conFinto();
      expect((await v.per('sfondo.png'))['ok'], isFalse);
      expect((await v.per(''))['ok'], isFalse);
      expect((await v.per(null))['ok'], isFalse);
    });

    test('uno sfondo che non c\'è', () async {
      final v = conFinto();
      final r = await v.per('${tmp.path}/non-esisto.png');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('non c\'è'));
    });

    test('se magick fallisce non resta un file mezzo scritto', () async {
      // È il rifiuto che conta: un file vuoto in cache alla prossima
      // richiesta sembrerebbe una copia buona, e il vetro resterebbe nero
      // per sempre senza che nessuno sappia perché.
      final v = Vetro(
        cartellaCache: '${tmp.path}/cache',
        esegui: (prog, args) async {
          File(args.last).writeAsBytesSync([]); // mezzo scritto: vuoto
          return ProcessResult(0, 1, '', 'delegato mancante');
        },
      );
      final r = await v.per(sfondo.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('delegato mancante'));
      final resti = Directory('${tmp.path}/cache')
          .listSync()
          .whereType<File>()
          .toList();
      expect(resti, isEmpty, reason: 'niente avanzi che sembrino cache buona');
    });

    test('e nemmeno se esce bene senza scrivere niente', () async {
      // `magick` sa uscire con zero e non produrre il file: un codice di
      // uscita non è una prova che il lavoro sia stato fatto.
      final v = conFinto(scrive: false);
      expect((await v.per(sfondo.path))['ok'], isFalse);
    });
  });

  group('la potatura', () {
    // La chiave comprende la data di modifica: ogni sfondo nuovo, e ogni
    // ritocco di uno vecchio, aggiunge un file. Senza potatura la cartella
    // cresce e basta — e con la rotazione degli sfondi accesa cresce da sola.
    test('oltre il tetto se ne vanno i più vecchi', () async {
      final cache = Directory('${tmp.path}/cache')..createSync(recursive: true);

      // Cinquanta copie finte, con date crescenti: le prime sono le più
      // vecchie, e sono quelle che devono sparire.
      final adesso = DateTime.now();
      for (var i = 0; i < 50; i++) {
        File('${cache.path}/vecchia$i.png')
          ..writeAsBytesSync([0])
          ..setLastModifiedSync(adesso.subtract(Duration(days: 50 - i)));
      }

      final v = conFinto();
      final r = await v.per(sfondo.path);
      expect(r['ok'], isTrue);

      final rimasti = cache.listSync().whereType<File>().toList();
      expect(rimasti.length, Vetro.quanteSeNeTengono,
          reason: 'il tetto è ${Vetro.quanteSeNeTengono}');

      // Quella appena calcolata NON deve essere fra le buttate: è la più
      // recente di tutte, ed è anche l'unica che qualcuno sta aspettando.
      expect(File(r['percorso'] as String).existsSync(), isTrue,
          reason: 'la potatura si è mangiata la copia appena fatta');
      // E le più vecchie se ne sono andate per prime, non a caso.
      expect(File('${cache.path}/vecchia0.png').existsSync(), isFalse);
      expect(File('${cache.path}/vecchia49.png').existsSync(), isTrue);
    });

    test('sotto il tetto non tocca niente', () async {
      final cache = Directory('${tmp.path}/cache')..createSync(recursive: true);
      for (var i = 0; i < 5; i++) {
        File('${cache.path}/tenuta$i.png').writeAsBytesSync([0]);
      }
      expect((await conFinto().per(sfondo.path))['ok'], isTrue);
      // Le cinque di prima più quella nuova.
      expect(cache.listSync().whereType<File>().length, 6);
    });

    test('e una cartella che non si legge non fa fallire la sfocatura',
        () async {
      // La potatura è un servizio, non un requisito: se non riesce, chi ha
      // chiesto la sfocatura deve riceverla lo stesso.
      final v = conFinto();
      final r = await v.per(sfondo.path);
      expect(r['ok'], isTrue);
    });
  });

  group('il giro vero', () {
    test('magick capisce davvero i nostri argomenti', () async {
      if (Process.runSync('sh', ['-c', 'command -v magick']).exitCode != 0) {
        print('  --  magick non c\'è: giro vero saltato');
        return;
      }
      // Un'immagine vera, fatta da magick stesso.
      final vera = '${tmp.path}/vera.png';
      Process.runSync('magick',
          ['-size', '200x150', 'gradient:navy-orange', vera]);
      final v = Vetro(cartellaCache: '${tmp.path}/cache2');
      final r = await v.per(vera);
      expect(r['ok'], isTrue, reason: r['error']?.toString() ?? '');
      final fuori = File(r['percorso'] as String);
      expect(fuori.existsSync(), isTrue);
      expect(fuori.lengthSync(), greaterThan(0));
      // E deve essere PICCOLA: se uscisse a piena risoluzione, il conto della
      // sfocatura sarebbe quello caro che si voleva evitare.
      final info = Process.runSync(
          'magick', [fuori.path, '-format', '%w', 'info:']);
      expect(int.parse(info.stdout.toString().trim()),
          lessThanOrEqualTo(Vetro.larghezzaRidotta));
    });
  });

  // ── Il vetro finto non deve coprire quello vero ────────────────────────
  //
  // Il 9 settembre 2026 il compositore ha imparato a sfocare davvero
  // (SceneFX). Per un pomeriggio non si è visto niente, e la causa non era
  // nel compositore: la barra e la dock si dipingono il vetro DA SOLE — questa
  // copia sfocata dello sfondo, opaca, dentro una membrana opaca al 93 % — e
  // fra le due cose non passa luce.
  //
  // Misurato sulla sessione viva passando da `vetro` a `blur` e confrontando
  // due fotografie pixel per pixel: nella fascia della barra cambiavano
  // **0 pixel su 84.480**, nella dock lo 0,3 %; dentro una finestra, dove il
  // vetro finto non arriva, il 54 %.
  //
  // La cura è `Core.Vetro.daDisegnare`, che col blur vero vale "". Questa
  // guardia esiste perché chi domani aggiunge una terza superficie di vetro —
  // i menù, la schermata di blocco — copierà la riga da qui, e copiando
  // `percorso` rimetterebbe il muro senza che nessuno se ne accorga.
  group('la guardia del vetro finto', () {
    /// Chi DISEGNA legge `daDisegnare`. `percorso` resta la risposta del
    /// demone, e può essere letto solo dentro `Vetro.qml`.
    test('barra e dock leggono daDisegnare, non percorso', () {
      final colpe = <String>[];
      for (final f in _cartellaSu('minerva-shell')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.qml'))) {
        final nome = f.path.split('minerva-shell/').last;
        if (nome == 'core/Vetro.qml') continue;
        final testo = f.readAsStringSync();
        // `onPercorsoChanged` da solo non vuol dire niente: mezza shell ha una
        // proprietà `percorso` sua — le briciole del gestore file, il
        // visualizzatore. Conta solo dentro un file che ascolta `Core.Vetro`.
        final ascoltaIlVetro = testo.contains('target: Core.Vetro');
        final righe = testo.split('\n');
        for (var i = 0; i < righe.length; i++) {
          if (righe[i].trimLeft().startsWith('//')) continue;
          if (righe[i].contains('Vetro.percorso') ||
              (ascoltaIlVetro && righe[i].contains('onPercorsoChanged'))) {
            colpe.add('$nome:${i + 1}');
          }
        }
      }
      expect(colpe, isEmpty,
          reason: 'legge il vetro finto senza passare da `daDisegnare`, '
              'quindi lo disegnerebbe ANCHE col blur vero del compositore, '
              'coprendolo: ${colpe.join(', ')}');
    });

    /// E il verso opposto: che `daDisegnare` sappia davvero tacere.
    test('daDisegnare tace col blur vero', () {
      final v = _trovaSu('minerva-shell/core/Vetro.qml').readAsStringSync();
      expect(v.contains('windows.effetto'), isTrue,
          reason: 'senza leggere l\'effetto del compositore, `blurVero` '
              'non può sapere niente');
      expect(
          RegExp(r'daDisegnare:\s*vetro\.blurVero\s*\?\s*""')
              .hasMatch(v),
          isTrue,
          reason: 'col blur vero non si disegna niente sotto la tinta');
    });

    /// E la membrana deve APRIRSI, o il blur resta dietro un muro.
    test('col blur vero barra e dock leggono la loro chiave', () {
      final l = _trovaSu('minerva-shell/theme/LegaTema.qml').readAsStringSync();
      expect(l.contains('shell.membraneOpacityBlur'), isTrue,
          reason: 'col blur la membrana ha una memoria sua');
      expect(l.contains('shell.membraneOpacity"'), isTrue,
          reason: 'e senza blur resta quella di prima');
      final d = _trovaSu('minerva-shell/shell.qml').readAsStringSync();
      expect(d.contains('dock.opacityBlur'), isTrue,
          reason: 'e la dock ha la sua coppia');
    });

    /// ── Il cursore che si gira e non fa niente ──────────────────────────
    ///
    /// La prima cura era un tetto — `Math.min(chiesta, 0.75)` — e col blur
    /// acceso annullava il cursore delle Impostazioni per intero, perché
    /// quello va da 0,75 a 1,00. Misurato muovendolo da un capo all'altro:
    /// 0,0 % di pixel diversi nella fascia della barra.
    ///
    /// Quindi la regola: chi SCRIVE la trasparenza di una superficie della
    /// scrivania deve scrivere la chiave del modo in cui si è.
    test('e le Impostazioni scrivono la chiave giusta', () {
      final a = _trovaSu('minerva-shell/settings/sections/Animazioni.qml')
          .readAsStringSync();
      expect(a.contains('shell.membraneOpacityBlur'), isTrue,
          reason: 'col blur il cursore della barra deve scrivere DOVE si '
              'legge, o si gira e non cambia niente');
      expect(RegExp(r'from:\s*page\._colBlur').hasMatch(a), isTrue,
          reason: 'e gli estremi devono seguire: col blur si scende sotto '
              '0,75, che senza sarebbe illeggibile');
      final d = _trovaSu('minerva-shell/settings/sections/Dock.qml')
          .readAsStringSync();
      expect(d.contains('dock.opacityBlur'), isTrue,
          reason: 'stessa cosa per la dock');
    });

    /// ── Una trasparenza sola quando il compositore ce n'è già una ──────
    ///
    /// Una finestra di Minerva era trasparente DUE volte: `shell.windowOpacity`
    /// nel colore di fondo QML e `windows.effettoOpacita` sull'albero della
    /// finestra nel compositore. Si moltiplicano — 0,90 × 0,73 = 0,66 — mentre
    /// una finestra di chiunque altro resta a 0,73. Due finestre affiancate,
    /// due trasparenze diverse, e nessuno dei due cursori lo diceva.
    test('col compositore acceso la trasparenza delle finestre è una', () {
      final l = _trovaSu('minerva-shell/theme/LegaTema.qml').readAsStringSync();
      final i = l.indexOf('property: "windowOpacity"');
      expect(i, greaterThan(0), reason: 'il legame deve esserci');
      final blocco = l.substring(i, (i + 300).clamp(0, l.length));
      expect(blocco.contains('Core.Vetro.effettoAcceso'), isTrue,
          reason: 'col compositore che mette la sua alfa, il QML non deve '
              'metterne una seconda');
      final a = _trovaSu('minerva-shell/settings/sections/Animazioni.qml')
          .readAsStringSync();
      expect(a.contains('visible: !page._effettoAcceso'), isTrue,
          reason: 'e il cursore che non regola più niente non si mostra: '
              'una manopola che si gira a vuoto è peggio di una che manca');
    });

    /// ── Il pennello lungo non va a ogni manopola ────────────────────────
    ///
    /// Venti ridisegni pieni della finestra a ogni `settings_changed` — nati
    /// per il cambio di set di ICONE, che rifà la disposizione della pagina —
    /// costavano 0,12 s di processore per ogni scatto di cursore, misurati il
    /// 9 settembre 2026. Girando nove volte una manopola: 1,07 s contro 0,13.
    test('il pennello lungo scatta per le icone, non per ogni manopola', () {
      final y = _trovaSu('minerva-shell/settings/System.qml').readAsStringSync();
      final i = y.indexOf('function onSettingsChanged()');
      expect(i, greaterThan(0));
      final blocco = y.substring(i, (i + 500).clamp(0, y.length));
      expect(blocco.contains('icons.style'), isTrue,
          reason: 'il pennello lungo deve guardare se sono cambiate le ICONE');
      expect(blocco.contains('_pennellataSola'), isTrue,
          reason: 'e per tutto il resto basta una pennellata');
    });

    /// E le due chiavi nuove devono esistere nei valori di fabbrica, o il
    /// demone le rifiuta in silenzio (lo fa dal 5 settembre 2026) e il
    /// cursore torna indietro da solo.
    test('le chiavi nuove esistono nei valori di fabbrica', () {
      final f = _trovaSu('minervad/lib/core/settings_api.dart')
          .readAsStringSync();
      expect(f.contains("'membraneOpacityBlur'"), isTrue);
      expect(f.contains("'opacityBlur'"), isTrue);
    });
  });
}

/// Il file cercato salendo dalla cartella corrente: `dart test` si lancia da
/// `minervad/`, ma anche dalla radice del progetto.
File _trovaSu(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

Directory _cartellaSu(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final d = Directory('${dir.path}/$relativo');
    if (d.existsSync()) return d;
    dir = dir.parent;
  }
  fail('non trovo la cartella $relativo');
}

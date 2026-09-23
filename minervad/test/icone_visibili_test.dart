import 'dart:io';

import 'package:minervad/services/icon_resolver.dart';
import 'package:test/test.dart';

/// Un tema di icone non promette di funzionare su tutti e due i fondi.
///
/// In Colloid `places/22/folder.svg` esiste in due versioni — scura per il
/// fondo chiaro, chiara per quello scuro — ma
/// `mimetypes/scalable/text-x-generic.svg` è UNA sola, quasi bianca. Su
/// Minerva chiaro il documento spariva, e con lui ogni file di testo del
/// gestore file.
///
/// Non ci si fida quindi del nome del tema: si guarda il file. Queste prove
/// scrivono SVG finti con colori noti, così il giudizio si misura invece di
/// guardarlo.
void main() {
  late Directory dir;
  late IconResolver r;

  File svg(String nome, String corpo) {
    final f = File('${dir.path}/$nome.svg');
    f.writeAsStringSync(corpo);
    return f;
  }

  setUp(() {
    dir = Directory.systemTemp.createTempSync('minerva-icone-');
    r = IconResolver();
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('un\'icona che non si vedrebbe non si usa', () {
    test('quasi bianca: sparisce sul chiaro, va bene sullo scuro', () {
      final f = svg('bianca', '<svg><path fill="#f4f4f4" d="M0 0"/></svg>');
      r.setInterfacciaScura(false);
      expect(r.siVedrebbe(f), isFalse);
      r.setInterfacciaScura(true);
      expect(r.siVedrebbe(f), isTrue);
    });

    test('quasi nera: il contrario', () {
      final f = svg('nera', '<svg><path fill="#0b0b0b" d="M0 0"/></svg>');
      r.setInterfacciaScura(true);
      expect(r.siVedrebbe(f), isFalse);
      r.setInterfacciaScura(false);
      expect(r.siVedrebbe(f), isTrue);
    });

    // Un'icona a più colori — Firefox, una cartella con un accento — sta in
    // mezzo e non va scartata mai: è il caso più comune di tutti.
    test('a più colori: passa da tutte e due le parti', () {
      final f = svg('firefox',
          '<svg><path fill="#ff9500"/><path fill="#0060df"/><path fill="#b5007f"/></svg>');
      for (final scuro in [true, false]) {
        r.setInterfacciaScura(scuro);
        expect(r.siVedrebbe(f), isTrue, reason: 'scuro=$scuro');
      }
    });

    // `currentColor` vuol dire «il colore me lo dai tu»: quelle si adattano
    // sempre e non c'è niente da giudicare.
    test('simbolica con currentColor: sempre buona', () {
      final f = svg('simbolica',
          '<svg><path fill="currentColor" d="M0 0"/><path fill="#363636"/></svg>');
      for (final scuro in [true, false]) {
        r.setInterfacciaScura(scuro);
        expect(r.siVedrebbe(f), isTrue, reason: 'scuro=$scuro');
      }
    });

    test('senza colori dichiarati non si giudica', () {
      final f = svg('vuota', '<svg><path d="M0 0"/></svg>');
      r.setInterfacciaScura(false);
      expect(r.siVedrebbe(f), isTrue);
    });

    // Decodificare ventitremila PNG per rispondere a una domanda che riguarda
    // le icone monocromatiche sarebbe pagare molto per poco.
    test('i PNG non si giudicano', () {
      final f = File('${dir.path}/qualcosa.png')..writeAsBytesSync([0, 1, 2]);
      r.setInterfacciaScura(false);
      expect(r.siVedrebbe(f), isTrue);
    });

    // Il giudizio dipende dal fondo: cambiando fondo va rifatto, o si
    // continuerebbe a servire le icone dell'altro.
    test('cambiando fondo il giudizio si rifà', () {
      final f = svg('bianca2', '<svg><path fill="#f8f8f8"/></svg>');
      r.setInterfacciaScura(true);
      expect(r.siVedrebbe(f), isTrue);
      r.setInterfacciaScura(false);
      expect(r.siVedrebbe(f), isFalse);
    });
  });
}

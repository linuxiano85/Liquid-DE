import 'dart:io';
import 'dart:math';
import 'package:test/test.dart';
import 'package:minervad/services/foto/doppioni.dart';
import 'package:minervad/services/foto/indice.dart';
import 'package:minervad/services/foto_service.dart';

// Le prove del cercatore di doppioni.
//
// ── Perché su file veri, e in una cartella temporanea ────────────────────
//
// Perché questo è il pezzo di Minerva che porta a **cancellare delle
// fotografie**, e una prova che finge i byte prova il finto. I file qui sotto
// si scrivono davvero sul disco, in una cartella temporanea che sparisce alla
// fine: sono piccoli, ma sono file.
//
// L'idea è di Giacomo, 26 agosto 2026, ed è la ragione per cui questa parte
// sarà provabile invece che sperabile.
//
// ── Le prove che contano di più sono i RIFIUTI ───────────────────────────
//
// Due file diversi che finiscono nello stesso gruppo sono una fotografia
// persa. Quindi metà di queste prove non verifica che trovi i doppioni:
// verifica che **non ne inventi**.

/// Un indice finto che tiene le voci che gli si danno.
class _IndiceFinto implements Indice {
  @override
  final List<Voce> voci;
  _IndiceFinto(this.voci);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Voce _voce(File f) => Voce(
      percorso: f.path,
      dimensione: f.lengthSync(),
      mtime: f.lastModifiedSync(),
      tipo: 'foto',
      fonte: 'prova',
      fiducia: 'certa',
      larghezza: 0,
      altezza: 0,
    );

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('minerva-doppioni-'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File scrivi(String nome, List<int> byte) {
    final f = File('${tmp.path}/$nome')..createSync(recursive: true);
    f.writeAsBytesSync(byte);
    return f;
  }

  /// Byte che sembrano una fotografia: abbastanza da superare l'assaggio.
  List<int> finti(int quanti, {int seme = 1}) {
    final r = Random(seme);
    return List<int>.generate(quanti, (_) => r.nextInt(256));
  }

  group('le copie esatte', () {
    test('due file identici diventano un gruppo solo', () async {
      final byte = finti(200 * 1024);
      final a = scrivi('a/foto.jpg', byte);
      final b = scrivi('b/foto.jpg', byte);
      final d = Doppioni(_IndiceFinto([_voce(a), _voce(b)]));

      final g = await d.esatti();
      expect(g.length, 1);
      expect(g.first.percorsi.length, 2);
      expect(g.first.genere, 'esatti');
      expect(g.first.byteInPiu, byte.length);
    });

    test('e si tiene quello col percorso più corto', () async {
      // Fra `Immagini/mare.jpg` e `Scaricati/DCIM/Camera/mare.jpg`, il primo è
      // dove qualcuno l'ha messo e il secondo è dove è caduto.
      final byte = finti(200 * 1024, seme: 7);
      final corto = scrivi('foto.jpg', byte);
      final lungo = scrivi('molto/piu/in/fondo/foto.jpg', byte);
      final d = Doppioni(_IndiceFinto([_voce(lungo), _voce(corto)]));

      final g = await d.esatti();
      expect(g.first.percorsi.first, corto.path,
          reason: 'il primo dell\'elenco è quello da TENERE');
    });

    test('tre copie contano due sprechi, non tre', () async {
      final byte = finti(120 * 1024, seme: 3);
      final f = [
        scrivi('uno.jpg', byte),
        scrivi('due.jpg', byte),
        scrivi('tre.jpg', byte),
      ];
      final d = Doppioni(_IndiceFinto(f.map(_voce).toList()));

      final g = await d.esatti();
      expect(g.single.percorsi.length, 3);
      expect(g.single.byteInPiu, byte.length * 2,
          reason: 'se ne tiene una: lo spreco sono le altre due');
    });
  });

  group('i rifiuti — quello che NON deve succedere', () {
    test('due file di lunghezza diversa non sono mai doppioni', () async {
      final a = scrivi('a.jpg', finti(100 * 1024, seme: 1));
      final b = scrivi('b.jpg', finti(100 * 1024 + 1, seme: 1));
      final d = Doppioni(_IndiceFinto([_voce(a), _voce(b)]));
      expect(await d.esatti(), isEmpty);
    });

    test('stessa lunghezza e contenuto diverso non sono doppioni', () async {
      final a = scrivi('a.jpg', finti(300 * 1024, seme: 11));
      final b = scrivi('b.jpg', finti(300 * 1024, seme: 22));
      final d = Doppioni(_IndiceFinto([_voce(a), _voce(b)]));
      expect(await d.esatti(), isEmpty);
    });

    test('e nemmeno se differiscono SOLO NEL MEZZO', () async {
      // È il caso che l'assaggio delle due estremità non può vedere: stessa
      // testa, stessa coda, e un byte diverso in mezzo. Senza il terzo
      // livello — la lettura intera — queste due sarebbero dichiarate
      // identiche, e una delle due finirebbe nel cestino.
      final byte = finti(400 * 1024, seme: 5);
      final altro = List<int>.from(byte);
      altro[200 * 1024] = (altro[200 * 1024] + 1) % 256;
      final a = scrivi('a.jpg', byte);
      final b = scrivi('b.jpg', altro);
      final d = Doppioni(_IndiceFinto([_voce(a), _voce(b)]));

      expect(await d.esatti(), isEmpty,
          reason: 'due fotografie diverse dichiarate uguali: qui si perde '
              'una foto per sempre');
    });

    test('un file solo non è un doppione di sé stesso', () async {
      final a = scrivi('solo.jpg', finti(50 * 1024));
      final d = Doppioni(_IndiceFinto([_voce(a)]));
      expect(await d.esatti(), isEmpty);
    });

    test('un file sparito si salta senza fermare gli altri', () async {
      // Un permesso negato o un file cancellato mentre si guarda non deve
      // costare i doppioni di tutti gli altri.
      final byte = finti(80 * 1024, seme: 9);
      final a = scrivi('a.jpg', byte);
      final b = scrivi('b.jpg', byte);
      final morto = File('${tmp.path}/non-esisto.jpg');
      final d = Doppioni(_IndiceFinto([
        Voce(
          percorso: morto.path,
          dimensione: byte.length,
          mtime: DateTime.now(),
          tipo: 'foto',
          fonte: 'prova',
          fiducia: 'certa',
          larghezza: 0,
          altezza: 0,
        ),
        _voce(a),
        _voce(b),
      ]));

      final g = await d.esatti();
      expect(g.length, 1);
      expect(g.single.percorsi, containsAll([a.path, b.path]));
      expect(g.single.percorsi, isNot(contains(morto.path)));
    });
  });

  test('i gruppi che liberano di più vengono per primi', () async {
    final grande = finti(500 * 1024, seme: 31);
    final piccolo = finti(20 * 1024, seme: 32);
    final f = [
      scrivi('g1.jpg', grande), scrivi('g2.jpg', grande),
      scrivi('p1.jpg', piccolo), scrivi('p2.jpg', piccolo),
    ];
    final d = Doppioni(_IndiceFinto(f.map(_voce).toList()));

    final g = await d.esatti();
    expect(g.length, 2);
    expect(g.first.byteInPiu, greaterThan(g.last.byteInPiu),
        reason: 'si guardano prima quelli che valgono di più');
  });

  // ══ Buttare via: i rifiuti ═══════════════════════════════════════════
  //
  // Questa è l'unica strada di Minerva verso la cancellazione di una
  // fotografia, e le prove qui sotto NON verificano che cancelli: verificano
  // che **si rifiuti**. «Butta tutte le copie» deve essere una cosa che non si
  // può nemmeno chiedere.
  group('lo scarto dei doppioni si rifiuta di perdere una foto', () {
    late FotoService fs;
    late File a;
    late File b;

    setUp(() {
      a = scrivi('a.jpg', finti(1024, seme: 1));
      b = scrivi('b.jpg', finti(1024, seme: 1));
      fs = FotoService(indice: _IndiceFinto([_voce(a), _voce(b)]));
    });

    test('senza una copia da tenere non butta niente', () {
      final r = fs.scartoDoppioni('', [a.path, b.path]);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('quale copia tenere'));
    });

    test('senza copie da buttare non butta niente', () {
      final r = fs.scartoDoppioni(a.path, const []);
      expect(r['ok'], isFalse);
    });

    test('la copia da tenere non può essere anche fra quelle da buttare', () {
      // È l'errore da un clic: si spunta «tieni questa» e poi si include
      // anche lei nell'elenco. Senza questo rifiuto, la fotografia sparisce.
      final r = fs.scartoDoppioni(a.path, [a.path, b.path]);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('si perde la fotografia'));
    });

    test('non si butta un file che non è dell\'archivio', () {
      // Questa azione non deve diventare una via per cancellare qualunque
      // cosa passando dal canale.
      final r = fs.scartoDoppioni(a.path, ['/etc/passwd']);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('archivio'));
    });

    test('e nemmeno si TIENE un file che non è dell\'archivio', () {
      // Il verso opposto: dichiarare di tenere qualcosa che non c'è
      // basterebbe a far buttare tutte le copie vere.
      final r = fs.scartoDoppioni('/etc/passwd', [a.path, b.path]);
      expect(r['ok'], isFalse);
    });

    test('quando è tutto in ordine dice cosa buttare, e non lo butta', () {
      final r = fs.scartoDoppioni(a.path, [b.path]);
      expect(r['ok'], isTrue);
      expect(r['tieni'], a.path);
      expect(r['butta'], [b.path]);
      // E i file sono ancora tutti e due lì: a buttare è un'altra cosa.
      expect(a.existsSync(), isTrue);
      expect(b.existsSync(), isTrue);
    });
  });
}
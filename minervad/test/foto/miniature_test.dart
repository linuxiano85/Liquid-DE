import 'dart:io';

import 'package:minervad/services/foto/miniature.dart';
import 'package:test/test.dart';

import 'exif_test.dart' show costruisci;

void main() {
  late Directory tana;
  late Directory cache;

  setUp(() {
    tana = Directory.systemTemp.createTempSync('minerva-mini-');
    cache = Directory('${tana.path}/cache')..createSync();
  });
  tearDown(() => tana.deleteSync(recursive: true));

  File foto(String nome, {bool conMiniatura = true, int orientamento = 1}) {
    final f = File('${tana.path}/$nome');
    f.writeAsBytesSync(costruisci(
        conMiniatura: conMiniatura, orientamento: orientamento));
    return f;
  }

  /// Un `magick` finto che scrive davvero un file: senza, la prova non
  /// distinguerebbe «ha funzionato» da «è uscito bene senza fare niente», che è
  /// esattamente il modo in cui `magick` sa fallire.
  Future<ProcessResult> Function(String, List<String>) fintoCheScrive(
          List<String> visti) =>
      (comando, argomenti) async {
        visti.add(comando);
        final uscita = argomenti.contains('-o')
            ? argomenti[argomenti.indexOf('-o') + 1]
            : argomenti.last;
        File(uscita).writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
        return ProcessResult(0, 0, '', '');
      };

  group('la strada che non costa niente', () {
    test('prende la miniatura da dentro l EXIF, senza svegliare nessuno', () async {
      final visti = <String>[];
      final m = Miniature(
          cartellaCache: cache.path, esegui: fintoCheScrive(visti));
      final r = await m.per(foto('a.jpg').path, lato: 256);

      expect(r['ok'], isTrue);
      expect(r['da'], 'exif');
      expect(visti, isEmpty, reason: 'nessun programma esterno deve partire');
      expect(File(r['percorso'] as String).existsSync(), isTrue);
    });

    test('per una cella grande la miniatura interna è troppo piccola', () async {
      // Il lato lungo di quella del telefono è 288 pixel: buona per una cella
      // da 256, sgranata per una da 512. E una miniatura sfocata è l'unico
      // errore che si vede a occhio.
      final visti = <String>[];
      final m = Miniature(
          cartellaCache: cache.path, esegui: fintoCheScrive(visti));
      final r = await m.per(foto('b.jpg').path, lato: 512);

      expect(r['ok'], isTrue);
      expect(r['da'], 'magick');
      expect(visti, ['magick']);
    });

    test('una fotografia da girare non passa dalla scorciatoia', () async {
      // Girarla vorrebbe dire decodificarla, cioè buttare via l'unico
      // vantaggio che la miniatura interna ha.
      final visti = <String>[];
      final m = Miniature(
          cartellaCache: cache.path, esegui: fintoCheScrive(visti));
      final r = await m.per(foto('c.jpg', orientamento: 6).path, lato: 128);

      expect(r['da'], 'magick');
      expect(visti, ['magick']);
    });

    test('senza miniatura interna si passa a magick', () async {
      final visti = <String>[];
      final m = Miniature(
          cartellaCache: cache.path, esegui: fintoCheScrive(visti));
      final r = await m.per(foto('d.jpg', conMiniatura: false).path);
      expect(r['da'], 'magick');
    });
  });

  group('la cache', () {
    test('la seconda volta non rifà niente', () async {
      final visti = <String>[];
      final m = Miniature(
          cartellaCache: cache.path, esegui: fintoCheScrive(visti));
      final f = foto('e.jpg', conMiniatura: false);

      final primo = await m.per(f.path);
      expect(primo['da'], 'magick');
      final secondo = await m.per(f.path);
      expect(secondo['da'], 'cache');
      expect(secondo['percorso'], primo['percorso']);
      expect(visti.length, 1, reason: 'magick una volta sola');
    });

    test('se la fotografia cambia, la miniatura non è più quella', () async {
      final m = Miniature(
          cartellaCache: cache.path, esegui: fintoCheScrive(<String>[]));
      final f = foto('f.jpg');
      final primo = await m.per(f.path);

      // Stesso nome, contenuto diverso: è il caso in cui una cache ingenua
      // mostra per sempre la fotografia di prima.
      f.writeAsBytesSync(costruisci(quando: '2020:01:01 00:00:00'));
      f.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));
      final secondo = await m.per(f.path);

      expect(secondo['percorso'], isNot(primo['percorso']));
    });

    test('lati vicini finiscono nello stesso scalino', () {
      // Un lato legato esattamente alla cella rigenererebbe l'intera libreria
      // a ogni scatto di rotellina.
      expect(Miniature.latoVicino(200), 256);
      expect(Miniature.latoVicino(256), 256);
      expect(Miniature.latoVicino(257), 512);
      expect(Miniature.latoVicino(9000), 1024);
    });

    test('pota le più vecchie quando si sfonda il tetto', () async {
      final m = Miniature(
          cartellaCache: cache.path,
          esegui: fintoCheScrive(<String>[]),
          tettoByte: 12);
      Directory('${cache.path}/aa').createSync(recursive: true);
      for (var i = 0; i < 5; i++) {
        File('${cache.path}/aa/$i.jpg').writeAsBytesSync([1, 2, 3, 4, 5]);
      }
      expect(m.quantoOccupa(), 25);
      final buttati = m.pota();
      expect(buttati, greaterThan(0));
      expect(m.quantoOccupa(), lessThanOrEqualTo(12));
    });

    test('sotto il tetto non butta niente', () {
      final m = Miniature(
          cartellaCache: cache.path,
          esegui: fintoCheScrive(<String>[]),
          tettoByte: 1000);
      Directory('${cache.path}/aa').createSync(recursive: true);
      File('${cache.path}/aa/1.jpg').writeAsBytesSync([1, 2, 3]);
      expect(m.pota(), 0);
    });
  });

  group('i rifiuti', () {
    late Miniature m;
    setUp(() => m = Miniature(
        cartellaCache: cache.path, esegui: fintoCheScrive(<String>[])));

    test('un percorso non completo', () async {
      final r = await m.per('foto.jpg');
      expect(r['ok'], isFalse);
      expect(r['error'], contains('percorso completo'));
    });

    test('un file che non esiste', () async {
      final r = await m.per('${tana.path}/mai-esistito.jpg');
      expect(r['ok'], isFalse);
    });

    test('una cartella non è una fotografia', () async {
      final r = await m.per(tana.path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('non è un file'));
    });

    test('un nome che magick leggerebbe come un comando', () async {
      // «foto.jpg[0]» per magick vuol dire «il primo fotogramma», e «@lista»
      // vuol dire «un elenco di file». Aprire un file diverso da quello chiesto
      // non è un errore che si vede: è una risposta sbagliata che sembra
      // giusta.
      for (final cattivo in ['foto[0].jpg', 'foto].jpg', '@lista.jpg']) {
        final f = File('${tana.path}/$cattivo')..writeAsBytesSync(costruisci());
        final r = await m.per(f.path);
        expect(r['ok'], isFalse, reason: cattivo);
        expect(r['error'], contains('si chiama'));
      }
    });

    test('un programma che esce bene senza scrivere niente non è un successo',
        () async {
      // È il modo in cui `magick` fallisce davvero: codice zero, nessun file.
      final bugiardo = Miniature(
        cartellaCache: cache.path,
        esegui: (c, a) async => ProcessResult(0, 0, '', ''),
      );
      final r = await bugiardo.per(foto('g.jpg', conMiniatura: false).path);
      expect(r['ok'], isFalse);
      expect(r['error'], contains('Non so aprire'));
    });

    test('un programma che non c è', () async {
      final assente = Miniature(
        cartellaCache: cache.path,
        esegui: (c, a) async => throw ProcessException(c, a, 'non trovato'),
      );
      final r = await assente.per(foto('h.jpg', conMiniatura: false).path);
      expect(r['ok'], isFalse);
    });
  });
}

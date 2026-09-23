import 'dart:io';
import 'dart:typed_data';

import 'package:minervad/services/foto/exif.dart';
import 'package:test/test.dart';

/// Costruisce un JPEG finto con dentro un EXIF vero.
///
/// Si costruisce invece di allegare una fotografia perché così la prova dice
/// **cosa** sta provando: gli scostamenti, l'ordine dei byte, i tipi. Una
/// fotografia allegata proverebbe solo che quella fotografia funziona.
///
/// Disposizione del blocco TIFF (gli scostamenti contano dall'inizio del TIFF):
///
/// ```
///   0  intestazione: ordine dei byte, il 42, dove comincia IFD0
///   8  IFD0        — 5 voci
///  74  «Minerva\0»            (marca)
///  82  «Prova 1\0»            (modello)
///  90  ExifIFD     — 2 voci
/// 120  «2026:03:17 11:27:29\0»
/// 140  «+02:00\0»
/// 148  IFD1        — 2 voci  (la miniatura)
/// 178  la miniatura, un JPEG intero
/// ```
Uint8List costruisci({
  bool piccolo = true,
  String quando = '2026:03:17 11:27:29',
  String fuso = '+02:00',
  int orientamento = 6,
  bool conMiniatura = true,
  int riempimentoMiniatura = 0,
  bool conFuso = true,
}) {
  const inizioIfd0 = 8;
  const dataMarca = 74;
  const dataModello = 82;
  const inizioExif = 90;
  const dataQuando = 120;
  const dataFuso = 140;
  const inizioIfd1 = 148;
  const dataMiniatura = 178;

  final miniatura = <int>[
    0xFF, 0xD8, 0xFF, 0xDB, // un JPEG minimo credibile
    ...List<int>.filled(20, 0x42),
    0xFF, 0xD9,
    ...List<int>.filled(riempimentoMiniatura, 0), // il riempimento del telefono
  ];

  final tiff = Uint8List(dataMiniatura + miniatura.length);
  final v = ByteData.sublistView(tiff);
  final e = piccolo ? Endian.little : Endian.big;

  void u16(int a, int x) => v.setUint16(a, x, e);
  void u32(int a, int x) => v.setUint32(a, x, e);
  void testo(int a, String s) {
    for (var i = 0; i < s.length; i++) {
      tiff[a + i] = s.codeUnitAt(i);
    }
    tiff[a + s.length] = 0;
  }

  // Intestazione TIFF
  tiff[0] = piccolo ? 0x49 : 0x4D;
  tiff[1] = piccolo ? 0x49 : 0x4D;
  u16(2, 42);
  u32(4, inizioIfd0);

  // Una voce di IFD: etichetta, tipo, quante, valore-o-scostamento.
  void voce(int a, int tag, int tipo, int quante, int valore,
      {bool eScostamento = false}) {
    u16(a, tag);
    u16(a + 2, tipo);
    u32(a + 4, quante);
    if (eScostamento) {
      u32(a + 8, valore);
    } else if (tipo == 3) {
      // Uno SHORT sta nei primi due byte dei quattro, e gli altri due restano
      // a zero. È il punto in cui un lettore distratto legge il numero
      // moltiplicato per 65.536.
      u16(a + 8, valore);
      u16(a + 10, 0);
    } else {
      u32(a + 8, valore);
    }
  }

  // ── IFD0 ────────────────────────────────────────────────────────────────
  u16(inizioIfd0, 5);
  voce(inizioIfd0 + 2, 0x010F, 2, 8, dataMarca, eScostamento: true);
  voce(inizioIfd0 + 14, 0x0110, 2, 8, dataModello, eScostamento: true);
  voce(inizioIfd0 + 26, 0x0112, 3, 1, orientamento);
  voce(inizioIfd0 + 38, 0x8769, 4, 1, inizioExif, eScostamento: true);
  voce(inizioIfd0 + 50, 0x0131, 2, 8, dataMarca, eScostamento: true); // riempitiva
  u32(inizioIfd0 + 62, conMiniatura ? inizioIfd1 : 0);

  testo(dataMarca, 'Minerva');
  testo(dataModello, 'Prova 1');

  // ── ExifIFD ─────────────────────────────────────────────────────────────
  u16(inizioExif, 2);
  voce(inizioExif + 2, 0x9003, 2, quando.length + 1, dataQuando,
      eScostamento: true);
  voce(inizioExif + 14, 0x9011, 2, conFuso ? fuso.length + 1 : 1,
      conFuso ? dataFuso : 0, eScostamento: true);
  u32(inizioExif + 26, 0);
  testo(dataQuando, quando);
  if (conFuso) testo(dataFuso, fuso);

  // ── IFD1: la miniatura ──────────────────────────────────────────────────
  if (conMiniatura) {
    u16(inizioIfd1, 2);
    voce(inizioIfd1 + 2, 0x0201, 4, 1, dataMiniatura, eScostamento: true);
    voce(inizioIfd1 + 14, 0x0202, 4, 1, miniatura.length, eScostamento: true);
    u32(inizioIfd1 + 26, 0);
    tiff.setRange(dataMiniatura, dataMiniatura + miniatura.length, miniatura);
  }

  // ── Il JPEG che lo contiene ─────────────────────────────────────────────
  final app1 = <int>[0x45, 0x78, 0x69, 0x66, 0, 0, ...tiff]; // «Exif\0\0»
  final lung = app1.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8,
    0xFF, 0xE0, 0x00, 0x10, // un APP0 di JFIF davanti: l'EXIF non è il primo
    ...List<int>.filled(14, 0),
    0xFF, 0xE1, (lung >> 8) & 0xFF, lung & 0xFF,
    ...app1,
    0xFF, 0xD9,
  ]);
}

void main() {
  group('leggere l EXIF', () {
    test('legge data, macchina e orientamento, in II', () {
      final d = DatiExif.daBytes(costruisci());
      expect(d.presente, isTrue);
      expect(d.scattata, DateTime(2026, 3, 17, 11, 27, 29));
      expect(d.macchina, 'Minerva Prova 1');
      expect(d.orientamento, 6);
      expect(d.coricata, isTrue);
      expect(d.fuso, const Duration(hours: 2));
    });

    test('legge la stessa cosa in MM', () {
      // I due ordini dei byte non sono un dettaglio: sbagliarli non dà un
      // errore, dà date del 1802 e orientamenti da 1536.
      final piccolo = DatiExif.daBytes(costruisci(piccolo: true));
      final grande = DatiExif.daBytes(costruisci(piccolo: false));
      expect(grande.scattata, piccolo.scattata);
      expect(grande.orientamento, piccolo.orientamento);
      expect(grande.macchina, piccolo.macchina);
    });

    test('salta l APP0 che sta davanti', () {
      // Il segmento EXIF non è quasi mai il primo: prima c'è il JFIF.
      final d = DatiExif.daBytes(costruisci());
      expect(d.scattata, isNotNull);
    });

    test('un fuso assente non diventa zero', () {
      // «non detto» e «UTC» sono due cose diverse, e confonderle sposta le
      // fotografie di due ore.
      final d = DatiExif.daBytes(costruisci(conFuso: false));
      expect(d.fuso, isNull);
      expect(d.scattata, isNotNull);
    });

    test('marca ripetuta nel modello non si ripete', () {
      final d = DatiExif.daBytes(costruisci());
      expect(d.macchina, isNot(contains('Minerva Minerva')));
    });
  });

  group('i rifiuti', () {
    test('un file che non è un JPEG', () {
      final d = DatiExif.daBytes(Uint8List.fromList(
          [0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0, 0, 0, 0, 0, 0]));
      expect(d.presente, isFalse);
      expect(d.scattata, isNull);
    });

    test('un JPEG senza EXIF', () {
      final d = DatiExif.daBytes(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9, 0, 0, 0, 0, 0, 0, 0, 0]));
      expect(d.presente, isFalse);
    });

    test('un file tagliato a metà non fa esplodere niente', () {
      final intero = costruisci();
      for (var quanto = 2; quanto < intero.length; quanto += 7) {
        final pezzo = Uint8List.sublistView(intero, 0, quanto);
        expect(() => DatiExif.daBytes(pezzo), returnsNormally,
            reason: 'tagliato a $quanto byte');
      }
    });

    test('l orologio mai messo non è una data', () {
      // «0000:00:00 00:00:00» è quello che scrive una macchina a cui non hanno
      // mai detto che ore sono. È un vuoto travestito.
      final d = DatiExif.daBytes(costruisci(quando: '0000:00:00 00:00:00'));
      expect(d.presente, isTrue);
      expect(d.scattata, isNull);
    });

    test('il 31 febbraio non diventa il 3 marzo', () {
      // DateTime(2026, 2, 31) in Dart vale, e vale marzo. Una data impossibile
      // deve essere nessuna data, non un'altra data.
      final d = DatiExif.daBytes(costruisci(quando: '2026:02:31 10:00:00'));
      expect(d.scattata, isNull);
    });
  });

  group('la miniatura', () {
    late Directory tana;
    setUp(() => tana = Directory.systemTemp.createTempSync('minerva-exif-'));
    tearDown(() => tana.deleteSync(recursive: true));

    File scrivi(Uint8List b) {
      final f = File('${tana.path}/prova.jpg');
      f.writeAsBytesSync(b);
      return f;
    }

    test('la trova e la estrae', () {
      final f = scrivi(costruisci());
      final d = DatiExif.leggi(f.path);
      expect(d.haMiniatura, isTrue);
      final m = DatiExif.miniatura(f.path, d);
      expect(m, isNotNull);
      expect(m![0], 0xFF);
      expect(m[1], 0xD8);
      expect(m[m.length - 2], 0xFF);
      expect(m[m.length - 1], 0xD9);
    });

    test('taglia il riempimento dichiarato di troppo', () {
      // Questo telefono dichiara 36.864 byte per una miniatura che ne occupa
      // 8.421: gli altri 28 KB sono zeri. Un decodificatore li ignora, la
      // nostra cache no — sarebbero 16 MB buttati su 454 fotografie.
      final f = scrivi(costruisci(riempimentoMiniatura: 5000));
      final d = DatiExif.leggi(f.path);
      expect(d.miniaturaLunga, greaterThan(5000));
      final m = DatiExif.miniatura(f.path, d)!;
      expect(m.length, lessThan(100));
      expect(m[m.length - 1], 0xD9);
    });

    test('senza IFD1 non c è miniatura, e non è un errore', () {
      final f = scrivi(costruisci(conMiniatura: false));
      final d = DatiExif.leggi(f.path);
      expect(d.presente, isTrue);
      expect(d.haMiniatura, isFalse);
      expect(DatiExif.miniatura(f.path, d), isNull);
    });

    test('un file che non c è non fa esplodere niente', () {
      expect(DatiExif.leggi('${tana.path}/non-esiste.jpg').presente, isFalse);
    });
  });
}

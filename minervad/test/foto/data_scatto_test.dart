import 'dart:io';

import 'package:minervad/services/foto/data_scatto.dart';
import 'package:test/test.dart';

void main() {
  group('la data scritta nel nome', () {
    // I nomi sono veri, presi dalla libreria di Giacomo il 26 agosto 2026, e
    // le date attese sono scritte a mano. Se un giorno uno schema cambia,
    // questa tabella è il posto dove si vede.
    final attese = <String, DateTime?>{
      // IMG_/VID_ — 471 file
      'IMG_20260317_112727.jpg': DateTime(2026, 3, 17, 11, 27, 27),
      'IMG_20260321_083735_1.jpg': DateTime(2026, 3, 21, 8, 37, 35),
      'VID_20260222_211501.mp4': DateTime(2026, 2, 22, 21, 15, 1),
      'PXL_20251105_083012345.jpg': DateTime(2025, 11, 5, 8, 30, 12),
      // Schermate Android — 130 file
      'Screenshot_2026-05-13-12-41-08-468_com.infomaniak.euria.jpg':
          DateTime(2026, 5, 13, 12, 41, 8),
      'Screenshot_2026-04-30-15-22-29-942_com.android.chrome.jpg':
          DateTime(2026, 4, 30, 15, 22, 29),
      // WhatsApp: solo il giorno, quindi mezzogiorno
      'IMG-20260317-WA0001.jpg': DateTime(2026, 3, 17, 12, 0, 0),
      // Le nostre, dal pannello di Stamp
      'Schermata 2026-08-16 alle 21.03.45.png':
          DateTime(2026, 8, 16, 21, 3, 45),
      // Millisecondi dal 1970 — verificato contro ffprobe sullo stesso file
      '1778685238462.mp4': DateTime.fromMillisecondsSinceEpoch(1778685238462),
      // Generici
      '20260513_171320.jpg': DateTime(2026, 5, 13, 17, 13, 20),
      '2026-05-13 17.13.20.png': DateTime(2026, 5, 13, 17, 13, 20),
      // Nessuna data nel nome: 139 file di Snapchat sono qui
      'Snapchat-841452542.jpg': null,
      'Snapchat-1540123892.mp4': null,
      'foto.jpg': null,
      'DSC_0001.JPG': null,
    };

    attese.forEach((nome, attesa) {
      test(nome, () => expect(Datatore.daNome(nome), attesa));
    });

    test('un numero di serie di tredici cifre fuori dal mondo non è una data',
        () {
      // Senza il controllo di credibilità, tredici cifre qualunque danno
      // sempre *una* data: un numero di serie diventerebbe uno scatto.
      expect(Datatore.daNome('9999999999999.jpg'), isNull);
      expect(Datatore.daNome('0000000000001.jpg'), isNull);
    });

    test('una data nel futuro non è una data di scatto', () {
      final domani = DateTime.now().add(const Duration(days: 400));
      final n = 'IMG_${domani.year}'
          '${domani.month.toString().padLeft(2, '0')}'
          '${domani.day.toString().padLeft(2, '0')}_120000.jpg';
      expect(Datatore.daNome(n), isNull);
    });

    test('un mese impossibile non slitta al mese dopo', () {
      expect(Datatore.daNome('IMG_20260231_120000.jpg'), isNull);
      expect(Datatore.daNome('IMG_20261301_120000.jpg'), isNull);
    });
  });

  group('la data dedotta dalla cartella', () {
    test('anno, mese e giorno', () {
      expect(Datatore.daCartella('/casa/Foto/2019-08-13 Mare/x.jpg'),
          DateTime(2019, 8, 13, 12));
    });

    test('anno e mese', () {
      expect(Datatore.daCartella('/casa/2019-08 Vacanze in Puglia/x.jpg'),
          DateTime(2019, 8, 1, 12));
    });

    test('solo l anno', () {
      expect(Datatore.daCartella('/casa/Foto/2019/x.jpg'), DateTime(2019, 1, 1, 12));
    });

    test('vince l antenato più vicino', () {
      // Una cartella «2019» dentro «Foto 2018» è del 2019: la cartella più
      // vicina al file sa di più di quella sopra.
      expect(Datatore.daCartella('/casa/Foto 2018/2019/x.jpg')?.year, 2019);
    });

    test('nessuna data nel percorso', () {
      expect(Datatore.daCartella('/casa/Immagini/x.jpg'), isNull);
    });
  });

  group('decidere: chi vince su chi', () {
    test('l EXIF batte il nome', () {
      final d = Datatore.decidi(
        percorso: '/casa/IMG_20260317_112727.jpg',
        exif: DateTime(2026, 3, 17, 11, 27, 29),
        mtime: DateTime(2026, 7, 8, 21, 29),
      );
      expect(d.fonte, 'exif');
      expect(d.fiducia, Fiducia.certa);
      expect(d.quando, DateTime(2026, 3, 17, 11, 27, 29));
      expect(d.daControllare, isFalse);
      expect(d.sipuoAgire, isTrue);
    });

    test('due secondi di scarto non sono un disaccordo', () {
      // Il nome dice 11:27:27, l'EXIF 11:27:29: è il tempo che passa fra il
      // momento in cui il telefono decide il nome e quello in cui scrive il
      // file. Marcarlo «da controllare» renderebbe sospetta l'intera libreria.
      final d = Datatore.decidi(
        percorso: '/casa/IMG_20260317_112727.jpg',
        exif: DateTime(2026, 3, 17, 11, 27, 29),
      );
      expect(d.daControllare, isFalse);
    });

    test('un anno di scarto è un disaccordo, e ferma le azioni', () {
      final d = Datatore.decidi(
        percorso: '/casa/IMG_20200317_112727.jpg',
        exif: DateTime(2026, 3, 17, 11, 27, 29),
      );
      expect(d.quando, DateTime(2026, 3, 17, 11, 27, 29), reason: 'usa la migliore');
      expect(d.daControllare, isTrue);
      expect(d.sipuoAgire, isFalse, reason: 'non si rinomina su una data contesa');
      expect(d.proposte.keys, containsAll(<String>['exif', 'nome']));
    });

    test('senza EXIF vince il nome, e si può agire', () {
      final d = Datatore.decidi(
        percorso: '/casa/Screenshot_2026-05-13-12-41-08-468_com.whatsapp.jpg',
        mtime: DateTime(2026, 7, 8, 21, 29),
      );
      expect(d.fonte, 'nome');
      expect(d.fiducia, Fiducia.probabile);
      expect(d.sipuoAgire, isTrue);
    });

    test('senza nome vince la cartella, ma non si agisce', () {
      final d = Datatore.decidi(
        percorso: '/casa/2019-08 Mare/Snapchat-841452542.jpg',
        mtime: DateTime(2026, 7, 8, 21, 29),
      );
      expect(d.fonte, 'cartella');
      expect(d.fiducia, Fiducia.incerta);
    });

    test('l mtime è l ultima spiaggia e non basta per agire', () {
      final d = Datatore.decidi(
        percorso: '/casa/Snapchat-841452542.jpg',
        mtime: DateTime(2026, 7, 8, 21, 29),
      );
      expect(d.fonte, 'mtime');
      expect(d.fiducia, Fiducia.ultimaSpiaggia);
      expect(d.sipuoAgire, isFalse,
          reason: 'dice quando è stato copiato, non quando è stato scattato');
    });

    test('niente di niente', () {
      final d = Datatore.decidi(percorso: '/casa/Snapchat-1.jpg');
      expect(d.quando, isNull);
      expect(d.fiducia, Fiducia.nessuna);
    });
  });

  group('regola 2: un mtime condiviso da molti non è una data', () {
    Map<String, Candidato> lotto(int quanti, DateTime quando,
            {int passoSecondi = 0}) =>
        {
          for (var i = 0; i < quanti; i++)
            '/casa/Snapchat-$i.jpg':
                Candidato(mtime: quando.add(Duration(seconds: i * passoSecondi))),
        };

    test('la copia dal telefono: 30 file nello stesso secondo', () {
      // È il caso vero: 826 file con mtime 8 luglio 2026 21:29:46. Se il
      // programma ci credesse, la galleria avrebbe un giorno solo con dentro
      // tutto.
      final r = Datatore.perLotto(lotto(30, DateTime(2026, 7, 8, 21, 29, 46)));
      expect(r.values.every((d) => d.quando == null), isTrue);
      expect(r.values.every((d) => d.fiducia == Fiducia.nessuna), isTrue);
    });

    test('pochi file nello stesso secondo restano credibili', () {
      final r = Datatore.perLotto(lotto(3, DateTime(2026, 7, 8, 21, 29, 46)));
      expect(r.values.every((d) => d.fiducia == Fiducia.ultimaSpiaggia), isTrue);
    });

    test('la regola non tocca chi ha una data vera', () {
      final quando = DateTime(2026, 7, 8, 21, 29, 46);
      final m = <String, Candidato>{
        ...lotto(30, quando),
        '/casa/IMG_20260317_112727.jpg': Candidato(
            exif: DateTime(2026, 3, 17, 11, 27, 29), mtime: quando),
      };
      final r = Datatore.perLotto(m);
      expect(r['/casa/IMG_20260317_112727.jpg']!.quando,
          DateTime(2026, 3, 17, 11, 27, 29));
      expect(r['/casa/Snapchat-0.jpg']!.quando, isNull);
    });

    test('la copia vera è sparsa su minuti, non su un secondo', () {
      // È il difetto che la prima versione aveva davvero. La copia dal telefono
      // di Giacomo si è spalmata su 24 minuti e 102 secondi distinti: contando
      // per secondo esatto, 74 fotografie di Snapchat passavano sotto la regola
      // e finivano nell'8 luglio, cioè nel giorno della copia.
      final r = Datatore.perLotto(
          lotto(40, DateTime(2026, 7, 8, 21, 29, 46), passoSecondi: 1));
      expect(r.values.every((d) => d.quando == null), isTrue,
          reason: 'quaranta file in quaranta secondi sono una copia');
    });

    test('venti a cavallo di un minuto non sfuggono', () {
      // Con i secchielli da un minuto, dieci di qua e dieci di là passerebbero
      // entrambi. La finestra scorre, e non si spezza sui minuti tondi.
      final r = Datatore.perLotto(
          lotto(24, DateTime(2026, 7, 8, 21, 29, 50), passoSecondi: 2));
      expect(r.values.every((d) => d.quando == null), isTrue);
    });

    test('fotografie sparse nel tempo restano credibili', () {
      // Una fotografia ogni dieci minuti è una libreria, non una copia.
      final m = <String, Candidato>{
        for (var i = 0; i < 40; i++)
          '/casa/x$i.jpg': Candidato(
              mtime: DateTime(2026, 1, 1, 8, 0).add(Duration(minutes: i * 10))),
      };
      final r = Datatore.perLotto(m);
      expect(r.values.every((d) => d.fiducia == Fiducia.ultimaSpiaggia), isTrue);
    });
  });

  group('i video', () {
    test('ffprobe risponde in UTC e va riportato all ora locale', () async {
      // Verificato su file vero: VID_20260222_211501.mp4 — il nome dice le
      // 21:15, ffprobe dice 20:15:06Z. Sono la stessa cosa, ed è la
      // conversione a dirlo.
      //
      // La prova NON scrive «21:15»: su una macchina con un altro fuso sarebbe
      // falsa. Confronta con la stessa conversione fatta da Dart.
      final d = Datatore(esegui: (c, a) async {
        expect(c, 'ffprobe');
        return ProcessResult(0, 0, '2026-02-22T20:15:06.000000Z\n', '');
      });
      final r = await d.daVideo('/casa/VID_20260222_211501.mp4');
      expect(r, DateTime.utc(2026, 2, 22, 20, 15, 6).toLocal());
      expect(r!.isUtc, isFalse);
    });

    test('ffprobe che non trova niente non inventa', () async {
      final d = Datatore(esegui: (c, a) async => ProcessResult(0, 0, '', ''));
      expect(await d.daVideo('/casa/x.mp4'), isNull);
    });

    test('ffprobe che fallisce non fa esplodere niente', () async {
      final d = Datatore(esegui: (c, a) async => ProcessResult(0, 1, '', 'no'));
      expect(await d.daVideo('/casa/x.mp4'), isNull);
    });

    test('un contenitore con l anno zero non è una data', () async {
      final d = Datatore(esegui: (c, a) async =>
          ProcessResult(0, 0, '1904-01-01T00:00:00.000000Z', ''));
      expect(await d.daVideo('/casa/x.mp4'), isNull);
    });
  });

  group('le schermate non sono ricordi', () {
    test('riconosce le sue', () {
      expect(
          Datatore.eSchermata(
              'Screenshot_2026-05-13-12-41-08-468_com.whatsapp.jpg'),
          isTrue);
      expect(Datatore.eSchermata('Schermata 2026-08-16 alle 21.03.45.png'),
          isTrue);
    });

    test('una fotografia non è una schermata', () {
      expect(Datatore.eSchermata('IMG_20260317_112727.jpg', haExif: true),
          isFalse);
    });
  });
}

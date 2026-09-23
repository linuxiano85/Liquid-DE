import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/foto/cartelle.dart';
import 'package:minervad/services/foto/data_scatto.dart';
import 'package:minervad/services/foto/indice.dart';
import 'package:test/test.dart';

import 'exif_test.dart' show costruisci;

void main() {
  late Directory tana;
  late Directory casa;
  late Cartelle cartelle;
  late Indice indice;

  /// Un `ffprobe` finto: i video nelle prove non hanno dentro un video.
  Datatore fintoFfprobe(String risposta) => Datatore(
      esegui: (c, a) async => ProcessResult(0, 0, risposta, ''));

  setUp(() {
    tana = Directory.systemTemp.createTempSync('minerva-indice-');
    casa = Directory('${tana.path}/casa')..createSync();
    cartelle = Cartelle(
        percorso: '${tana.path}/config/foto/cartelle.json', casa: casa.path);
    indice = Indice(
      cartelle: cartelle,
      datatore: fintoFfprobe(''),
      percorsoIndice: '${tana.path}/cache/foto/indice.json',
      percorsoPreferiti: '${tana.path}/config/foto/preferiti.json',
    );
  });
  tearDown(() => tana.deleteSync(recursive: true));

  File foto(String dove, {String quando = '2026:03:17 11:27:29',
      int orientamento = 1}) {
    final f = File('${casa.path}/$dove');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(costruisci(quando: quando, orientamento: orientamento));
    return f;
  }

  Future<List<Map<String, dynamic>>> scansiona([String id = 'prova']) async =>
      indice.scansiona(id).toList();

  Map<String, dynamic> ultimo(List<Map<String, dynamic>> pezzi) =>
      pezzi.lastWhere((p) => p['fine'] == true);

  group('senza cartelle scelte', () {
    test('non frugazza niente, e propone', () async {
      Directory('${casa.path}/Immagini').createSync();
      for (var i = 0; i < 30; i++) {
        foto('Scaricati/DCIM/IMG_2026031${i % 10}_11272$i.jpg');
      }
      final pezzi = await scansiona();
      final fine = ultimo(pezzi);
      expect(fine['nessunaCartella'], isTrue);
      expect(fine['totale'], 0);
      expect((fine['proposte'] as List).map((p) => p['percorso']),
          contains('${casa.path}/Scaricati'));
    });
  });

  group('la prima scansione', () {
    setUp(() {
      foto('Foto/IMG_20260317_112727.jpg');
      foto('Foto/IMG_20260321_083735.jpg', quando: '2026:03:21 08:37:37');
      foto('Foto/Screenshot_2026-05-13-12-41-08-468_com.whatsapp.jpg',
          quando: '0000:00:00 00:00:00');
      cartelle.aggiungi('${casa.path}/Foto');
    });

    test('trova tutto e lo mette nei suoi giorni', () async {
      final fine = ultimo(await scansiona());
      expect(fine['totale'], 3);

      final p = indice.panoramica();
      expect(p['totale'], 3);
      final giorni = (p['giorni'] as List).map((g) => g['giorno']).toList();
      expect(giorni, ['2026-05-13', '2026-03-21', '2026-03-17'],
          reason: 'dal più recente al più vecchio');
    });

    test('arriva a mazzetti, non tutto alla fine', () async {
      for (var i = 0; i < 120; i++) {
        foto('Foto/IMG_202603${(i % 28) + 1}_1127${i.toString().padLeft(2, '0')}.jpg'
            .replaceAll('IMG_2026030', 'IMG_2026031'));
      }
      final pezzi = await scansiona();
      final conVoci = pezzi.where((p) => p['voci'] != null).toList();
      expect(conVoci.length, greaterThan(1),
          reason: 'chi apre la galleria deve vedere qualcosa subito');
    });

    test('riconosce le schermate senza confonderle con le fotografie', () async {
      await scansiona();
      final p = indice.panoramica();
      expect(p['schermate'], 1);
    });

    test('nascondere le schermate le toglie dai conti', () async {
      await scansiona();
      cartelle.schermate(false);
      final p = indice.panoramica();
      expect(p['totale'], 3, reason: 'ci sono ancora');
      final somma = (p['giorni'] as List)
          .fold<int>(0, (t, g) => t + (g['quante'] as int));
      expect(somma, 2, reason: 'ma non si vedono');
    });
  });

  group('la seconda scansione non rifà il lavoro', () {
    setUp(() {
      foto('Foto/IMG_20260317_112727.jpg');
      foto('Foto/IMG_20260321_083735.jpg', quando: '2026:03:21 08:37:37');
      cartelle.aggiungi('${casa.path}/Foto');
    });

    test('riusa quello che non è cambiato', () async {
      final primo = ultimo(await scansiona());
      expect(primo['lette'], 2);
      expect(primo['riuse'], 0);

      final secondo = ultimo(await scansiona('due'));
      expect(secondo['lette'], 0, reason: 'niente da rileggere');
      expect(secondo['riuse'], 2);
    });

    test('un file cambiato si rilegge', () async {
      await scansiona();
      final f = foto('Foto/IMG_20260317_112727.jpg', quando: '2020:01:01 09:00:00');
      f.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 5)));

      final secondo = ultimo(await scansiona('due'));
      expect(secondo['lette'], 1);
      expect(secondo['riuse'], 1);
    });

    test('un file sparito sparisce anche dall indice', () async {
      await scansiona();
      File('${casa.path}/Foto/IMG_20260321_083735.jpg').deleteSync();
      final secondo = ultimo(await scansiona('due'));
      expect(secondo['totale'], 1);
    });
  });

  group('fermarsi a metà', () {
    test('chi chiude la galleria non lascia nessuno a frugare', () async {
      for (var i = 0; i < 200; i++) {
        foto('Foto/IMG_2026031${i % 9}_1127${i.toString().padLeft(2, '0')}.jpg');
      }
      cartelle.aggiungi('${casa.path}/Foto');

      final pezzi = <Map<String, dynamic>>[];
      await for (final p in indice.scansiona('taglio')) {
        pezzi.add(p);
        if (p['voci'] != null) indice.ferma('taglio');
      }
      final fine = ultimo(pezzi);
      expect(fine['fermata'], isTrue);
    });

    test('una scansione fermata non scrive un indice a metà', () async {
      foto('Foto/IMG_20260317_112727.jpg');
      cartelle.aggiungi('${casa.path}/Foto');
      await scansiona();
      final buono = File(indice.percorsoIndice).readAsStringSync();

      for (var i = 0; i < 100; i++) {
        foto('Foto/IMG_2026032${i % 9}_1127${i.toString().padLeft(2, '0')}.jpg');
      }
      await for (final p in indice.scansiona('taglio')) {
        if (p['voci'] != null) indice.ferma('taglio');
      }
      expect(File(indice.percorsoIndice).readAsStringSync(), buono,
          reason: 'meglio l indice di prima che uno monco');
    });
  });

  group('il giorno', () {
    test('le voci ordinate, dalla più recente', () async {
      foto('Foto/IMG_20260317_080000.jpg', quando: '2026:03:17 08:00:00');
      foto('Foto/IMG_20260317_200000.jpg', quando: '2026:03:17 20:00:00');
      cartelle.aggiungi('${casa.path}/Foto');
      await scansiona();

      final g = indice.giorno('2026-03-17');
      final nomi = (g['voci'] as List)
          .map((v) => (v['percorso'] as String).split('/').last)
          .toList();
      expect(nomi, ['IMG_20260317_200000.jpg', 'IMG_20260317_080000.jpg']);
    });

    test('quelle senza data non si perdono: hanno un giorno vuoto', () async {
      // Sono 94 in questa casa: file di Snapchat, che la data non ce l'hanno
      // né nel nome né dentro. L'unica cosa che resta è l'mtime — ma sono
      // arrivati tutti insieme, in un blocco, quindi quell'mtime è l'ora della
      // copia e la regola della finestra lo dichiara inservibile. Restano senza
      // data, ed è la verità: nasconderle sarebbe perderle.
      final quando = DateTime(2026, 7, 8, 21, 29, 46);
      for (var i = 0; i < 25; i++) {
        final f = File('${casa.path}/Foto/Snapchat-84145254$i.jpg');
        f.parent.createSync(recursive: true);
        f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
        f.setLastModifiedSync(quando.add(Duration(seconds: i)));
      }
      cartelle.aggiungi('${casa.path}/Foto');
      await scansiona();

      expect(indice.panoramica()['senzaData'], 25);
      expect((indice.giorno('')['voci'] as List), hasLength(25));
    });

    test('una fotografia sola, arrivata da sola, l mtime se lo tiene', () async {
      // La regola serve a smascherare una copia in blocco, non a buttare via
      // l'unica informazione che c'è quando non c'è altro.
      final f = File('${casa.path}/Foto/Snapchat-1.jpg');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      cartelle.aggiungi('${casa.path}/Foto');
      await scansiona();

      expect(indice.panoramica()['senzaData'], 0);
      expect(indice.voci.first.fiducia, 'ultimaSpiaggia');
    });
  });

  group('le misure girate', () {
    test('una verticale di telefono non si dichiara orizzontale', () async {
      // L'EXIF dà le misure PRIMA della rotazione: senza questo, una griglia
      // taglierebbe di traverso ogni fotografia scattata in piedi.
      foto('Foto/IMG_20260317_112727.jpg', orientamento: 6);
      cartelle.aggiungi('${casa.path}/Foto');
      await scansiona();
      final v = indice.voci.first;
      expect(v.orientamento, 6);
      expect(v.larghezzaVista, v.altezza);
      expect(v.altezzaVista, v.larghezza);
    });
  });

  group('i preferiti stanno con le scelte, non con la cache', () {
    setUp(() {
      foto('Foto/IMG_20260317_112727.jpg');
      cartelle.aggiungi('${casa.path}/Foto');
    });

    test('si mettono e si tolgono', () {
      final p = '${casa.path}/Foto/IMG_20260317_112727.jpg';
      expect(indice.preferito(p, true)['quanti'], 1);
      expect(indice.preferiti(), contains(p));
      expect(indice.preferito(p, false)['quanti'], 0);
    });

    test('svuotare la cache non cancella le stelle', () async {
      // Se stessero nello stesso file dell'indice, la prima pulizia della
      // cache cancellerebbe scelte di una persona senza dirle niente.
      final p = '${casa.path}/Foto/IMG_20260317_112727.jpg';
      await scansiona();
      indice.preferito(p, true);

      Directory('${tana.path}/cache').deleteSync(recursive: true);
      expect(indice.preferiti(), contains(p));
    });

    test('il giorno dice quali sono preferite', () async {
      final p = '${casa.path}/Foto/IMG_20260317_112727.jpg';
      await scansiona();
      indice.preferito(p, true);
      final v = (indice.giorno('2026-03-17')['voci'] as List).first;
      expect(v['preferito'], isTrue);
    });

    test('un percorso non completo si rifiuta', () {
      expect(indice.preferito('foto.jpg', true)['ok'], isFalse);
    });
  });

  group('l indice rotto non fa danni', () {
    test('un file di indice illeggibile si ricomincia da capo', () async {
      foto('Foto/IMG_20260317_112727.jpg');
      cartelle.aggiungi('${casa.path}/Foto');
      final f = File(indice.percorsoIndice);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('{ rotto');

      final fine = ultimo(await scansiona());
      expect(fine['totale'], 1);
    });

    test('si scrive intero o non si scrive', () async {
      foto('Foto/IMG_20260317_112727.jpg');
      cartelle.aggiungi('${casa.path}/Foto');
      await scansiona();
      expect(File('${indice.percorsoIndice}.nuovo').existsSync(), isFalse);
      final d = jsonDecode(File(indice.percorsoIndice).readAsStringSync());
      expect(d['versione'], 1);
      expect(d['voci'], hasLength(1));
    });
  });
}

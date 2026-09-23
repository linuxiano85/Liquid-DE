import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:minervad/services/foto/castv2.dart';
import 'package:minervad/services/foto/servizio_effimero.dart';

// Le prove della trasmissione a schermo.
//
// ── Perché senza televisore ───────────────────────────────────────────────
//
// Una prova che ha bisogno di un apparecchio acceso fallisce quando qualcuno
// lo spegne, e una prova che fallisce per ragioni sue smette di dire qualcosa.
// Quello che si prova qui è il FORMATO — i byte del protocollo — e i RIFIUTI
// del servizio che presta la fotografia. Tutte e due si provano con dei
// numeri e un file temporaneo.
//
// ── Che cosa si sa DAVVERO del televisore vero ───────────────────────────
//
// Provato a mano il 30 agosto 2026 sulla «TV cameretta» di Giacomo:
//
//  · la stretta di mano funziona — `RECEIVER_STATUS` con volume e app aperte;
//  · il lettore si accende — la schermata di Chromecast è comparsa sullo
//    schermo, e lui l'ha vista;
//  · il comando viene accettato — `MEDIA_STATUS`.
//
// **La fotografia però NON è comparsa: schermo nero.** Il televisore accetta e
// poi va a prendersi il file, e `ufw` lo respinge — il sì arriva subito, il no
// arriva dopo e in silenzio. Da lì la porta fissa in `ServizioEffimero`, che
// un firewall può permettere una volta sola.
//
// Sta scritto qui perché una prova che dice «funziona» quando non si è visto
// funzionare è peggio di nessuna prova.
void main() {
  group('i byte del protocollo', () {
    test('quello che si scrive è quello che si rilegge', () {
      // È l'unica prova che dica davvero se il protobuf scritto a mano è
      // giusto: se la scrittura sbagliasse un numero di campo, la rilettura
      // non ritroverebbe le stringhe al loro posto.
      final byte = CastV2.componi(
        sorgente: 'sender-minerva',
        destinazione: 'receiver-0',
        spazio: 'urn:x-cast:com.google.cast.receiver',
        payload: '{"type":"GET_STATUS","requestId":1}',
      );
      final m = CastV2.scomponi(byte);
      expect(m['sorgente'], 'sender-minerva');
      expect(m['destinazione'], 'receiver-0');
      expect(m['spazio'], 'urn:x-cast:com.google.cast.receiver');
      expect(jsonDecode(m['payload']!)['type'], 'GET_STATUS');
    });

    test('gli accenti sopravvivono al giro', () {
      // Il titolo di una fotografia può contenere qualunque cosa. Se la
      // lunghezza fosse contata in caratteri invece che in byte, «città»
      // taglierebbe il messaggio a metà e il televisore non capirebbe più
      // nulla da lì in poi.
      const titolo = '{"titolo":"Città, perché é così — 日本"}';
      final m = CastV2.scomponi(CastV2.componi(
          sorgente: 'a', destinazione: 'b', spazio: 'c', payload: titolo));
      expect(m['payload'], titolo);
    });

    test('un payload lungo passa il confine dei 127 byte', () {
      // I varint hanno sette bit per byte: a 128 la lunghezza smette di
      // stare in un byte solo. È il punto in cui una scrittura sbagliata
      // comincia a funzionare per i messaggi corti e a rompersi per gli
      // altri — cioè il difetto che si vede solo con una foto dal nome lungo.
      final lungo = '{"x":"${'a' * 500}"}';
      final m = CastV2.scomponi(CastV2.componi(
          sorgente: 'a', destinazione: 'b', spazio: 'c', payload: lungo));
      expect(m['payload'], lungo);
    });

    test('un campo che non conosciamo si salta invece di rompere tutto', () {
      // Un televisore nuovo può aggiungere un campo. Un lettore che si ferma
      // davanti a quello è un lettore che smetterà di funzionare da solo, a
      // un aggiornamento che non dipende da noi.
      final base = CastV2.componi(
          sorgente: 'a', destinazione: 'b', spazio: 'c', payload: 'd');
      // Campo 9, tipo 0 (un numero), valore 7: uno che non leggiamo.
      final conExtra = Uint8List.fromList([...base, 0x48, 0x07]);
      final m = CastV2.scomponi(conExtra);
      expect(m['payload'], 'd');
    });
  });

  group('il servizio che presta la fotografia', () {
    late Directory tmp;
    late File foto;
    late ServizioEffimero s;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('minerva-cast-');
      foto = File('${tmp.path}/foto.jpg')
        ..writeAsBytesSync(List<int>.filled(2048, 7));
      // Porta qualunque: la fissa è una sola, e due prove insieme litigherebbero.
      s = ServizioEffimero(file: foto, durata: const Duration(seconds: 30), porta: 0);
      await s.apri(versoIl: '127.0.0.1');
    });

    tearDown(() async {
      await s.chiudi();
      tmp.deleteSync(recursive: true);
    });

    test('con l\'indirizzo giusto dà la fotografia', () async {
      final r = await _prendi(s.indirizzo!);
      expect(r.$1, 200);
      expect(r.$2, 2048);
    });

    // ── I RIFIUTI: sono la ragione per cui questo file esiste ────────────

    test('la radice non dà niente', () async {
      final u = Uri.parse(s.indirizzo!);
      final r = await _prendi('${u.origin}/');
      expect(r.$1, 404, reason: 'non c\'è una cartella da servire, mai');
    });

    test('un indirizzo indovinato non dà niente', () async {
      final u = Uri.parse(s.indirizzo!);
      final r = await _prendi('${u.origin}/foto.jpg');
      expect(r.$1, 404);
    });

    test('e nemmeno risalendo di una cartella', () async {
      // Il classico: `../../etc/passwd`. Qui non può funzionare per
      // costruzione — non c'è nessuna radice da cui risalire — ma la prova
      // resta, perché «per costruzione» è vero finché qualcuno non
      // riscrive la costruzione.
      final u = Uri.parse(s.indirizzo!);
      final r = await _prendi('${u.origin}/../../../etc/passwd');
      expect(r.$1, isNot(200));
    });

    test('chiuso, non risponde più', () async {
      final dove = s.indirizzo!;
      await s.chiudi();
      expect(s.aperto, isFalse);
      await expectLater(_prendi(dove), throwsA(isA<Exception>()));
    });

    test('ogni trasmissione ha una serratura sua', () async {
      // Due trasmissioni non devono condividere l'indirizzo: chi ha ricevuto
      // quello della prima non deve poter prendere la seconda. Si aprono per
      // davvero — su una porta qualunque, per non litigare con la fissa — e
      // si confrontano le due chiavi.
      final b = ServizioEffimero(file: foto, porta: 0);
      await b.apri(versoIl: '127.0.0.1');
      try {
        final chiaveA = Uri.parse(s.indirizzo!).path;
        final chiaveB = Uri.parse(b.indirizzo!).path;
        expect(chiaveA, isNot(chiaveB));
        expect(chiaveA.length, greaterThanOrEqualTo(48),
            reason: 'ventiquattro byte in esadecimale: la serratura è questa');
      } finally {
        await b.chiudi();
      }
    });
  });
}

/// Prende un indirizzo e torna (stato, quanti byte).
Future<(int, int)> _prendi(String dove) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(dove));
    final r = await req.close();
    var n = 0;
    await for (final p in r) {
      n += p.length;
    }
    return (r.statusCode, n);
  } finally {
    c.close(force: true);
  }
}

// Che genere di cosa stiamo mandando alla televisione.
//
// Questo file prova la traduzione: da un tipo MIME alla classe DIDL, al
// numero del Chromecast, alle due intestazioni di DLNA. È aritmetica pura —
// nessun apparecchio acceso, nessuna rete — ed è deliberato: sono le
// traduzioni che, sbagliate, non danno **nessun errore**. Il televisore
// mostra nero, o mette la cornice da album fotografico attorno a un film, e
// chi guarda conclude che Minerva è rotta.
import 'package:minervad/services/foto/genere.dart';
import 'package:test/test.dart';

void main() {
  group('dal tipo al genere', () {
    test('le tre famiglie ovvie', () {
      expect(Genere.di('image/jpeg'), Genere.foto);
      expect(Genere.di('image/png'), Genere.foto);
      expect(Genere.di('video/mp4'), Genere.video);
      expect(Genere.di('video/matroska'), Genere.video);
      expect(Genere.di('audio/mpeg'), Genere.musica);
      expect(Genere.di('audio/flac'), Genere.musica);
    });

    test('HLS è un FLUSSO, non un video', () {
      // È la distinzione che conta: la sua famiglia è `application`, che da
      // sola direbbe «non so cos'è». E chiamarlo «video» sarebbe peggio che
      // non saperlo: il televisore proverebbe a saltarci dentro.
      expect(Genere.di('application/x-mpegURL'), Genere.flusso);
      expect(Genere.di('application/vnd.apple.mpegurl'), Genere.flusso);
      expect(Genere.di('application/dash+xml'), Genere.flusso);
    });

    test('quello che non sappiamo mandare lo dice', () {
      expect(Genere.di('application/pdf'), Genere.ignoto);
      expect(Genere.di('text/plain'), Genere.ignoto);
      expect(Genere.di(''), Genere.ignoto);
    });

    test('maiuscole e spazi non cambiano la risposta', () {
      expect(Genere.di('  VIDEO/MP4 '), Genere.video);
      expect(Genere.di('Image/JPEG'), Genere.foto);
    });
  });

  group('la classe DIDL, che è quella che era sbagliata', () {
    test('ognuno la sua', () {
      expect(Genere.foto.classeDidl, 'object.item.imageItem.photo');
      expect(Genere.video.classeDidl, 'object.item.videoItem');
      expect(Genere.musica.classeDidl, 'object.item.audioItem.musicTrack');
    });

    test('lo SCHERMO trasmesso è una DIRETTA, non un file', () {
      // Due difetti veri, in fila, nello stesso posto.
      //
      // Fino al 4 settembre 2026 lo schermo trasmesso viaggiava annunciato
      // come `imageItem.photo`: una fotografia. Funzionava per fortuna, non
      // per costruzione.
      //
      // Poi è diventato `videoItem`, che è meglio ed è ancora sbagliato: un
      // file. E un renderer che riceve un file si fa una scorta prima di
      // cominciare, perché di un file conviene averne un pezzo davanti.
      // Misurato lo stesso giorno sul televisore della cucina: sei secondi di
      // ritardo, e alzare la banda da 6 a 16 Mbit/s non ne toglieva nemmeno
      // uno — la scorta era in secondi, non in byte.
      //
      // `videoBroadcast` è la classe di un canale in diretta. Di una diretta
      // non si torna indietro, quindi non c'è niente da tenere davanti.
      expect(Genere.di('application/x-mpegURL').classeDidl,
          'object.item.videoItem.videoBroadcast');
      // E un file video resta un file video: la differenza è il punto.
      expect(Genere.di('video/mp4').classeDidl, 'object.item.videoItem');
    });
  });

  group('il Chromecast', () {
    test('il numero della scheda', () {
      expect(Genere.foto.metadatoCast, 4);
      expect(Genere.video.metadatoCast, 1);
      expect(Genere.musica.metadatoCast, 3);
      expect(Genere.flusso.metadatoCast, 0);
    });

    test('un file scorre, un flusso no, una foto nemmeno', () {
      expect(Genere.video.modoFlussoCast, 'BUFFERED');
      expect(Genere.musica.modoFlussoCast, 'BUFFERED');
      expect(Genere.flusso.modoFlussoCast, 'LIVE');
      expect(Genere.foto.modoFlussoCast, 'NONE');
    });

    test('e si può saltare solo dentro le cose che finiscono', () {
      expect(Genere.video.siPuoScorrere, isTrue);
      expect(Genere.musica.siPuoScorrere, isTrue);
      expect(Genere.flusso.siPuoScorrere, isFalse);
      expect(Genere.foto.siPuoScorrere, isFalse);
    });
  });

  group('le due intestazioni di DLNA', () {
    test('una foto si scarica, un film si guarda mentre arriva', () {
      expect(Genere.foto.modoTrasferimento, 'Interactive');
      expect(Genere.video.modoTrasferimento, 'Streaming');
      expect(Genere.musica.modoTrasferimento, 'Streaming');
      expect(Genere.flusso.modoTrasferimento, 'Streaming');
    });

    test('OP=01 dice «so saltare a un byte», e adesso è vero', () {
      // Prometterlo senza saperlo fare È il difetto che c'era: il televisore
      // chiedeva un intervallo, riceveva tutto il file dall'inizio, e non
      // riusciva a spostarsi nel film.
      expect(Genere.video.caratteristiche, startsWith('DLNA.ORG_OP=01;'));
      expect(Genere.foto.caratteristiche, startsWith('DLNA.ORG_OP=01;'));
    });

    test('ma su un flusso dal vivo non si salta da nessuna parte', () {
      expect(Genere.flusso.caratteristiche, startsWith('DLNA.ORG_OP=00;'));
    });

    test('i bit dei FLAGS, contati e non copiati', () {
      // 0x00900000 = interactive (0x800000) + DLNA 1.5 (0x100000)
      expect(Genere.foto.caratteristiche, contains('DLNA.ORG_FLAGS=00900000'));
      // 0x01700000 = streaming (0x1000000) + secondo piano (0x400000)
      //            + pause (0x200000) + DLNA 1.5 (0x100000)
      expect(Genere.video.caratteristiche, contains('DLNA.ORG_FLAGS=01700000'));
      // 0x8D500000 = sender paced (0x80000000) + l'inizio avanza (0x8000000)
      //            + la fine cresce (0x4000000) + streaming (0x1000000)
      //            + secondo piano (0x400000) + DLNA 1.5 (0x100000)
      // Senza il bit «pause» (0x200000): di una diretta non si riprende
      // niente. È la firma di un flusso dal vivo, e il bit che conta è il
      // primo — «il ritmo lo detto io» — perché è quello che dice al
      // televisore di non farsi la scorta.
      expect(Genere.flusso.caratteristiche, contains('DLNA.ORG_FLAGS=8D500000'));
      expect(Genere.flusso.caratteristiche, contains('DLNA.ORG_CI=0'));
      expect(Genere.flusso.caratteristiche,
          isNot(contains('DLNA.ORG_FLAGS=01700000')),
          reason: 'i flag da file su una diretta sono ciò che costava sei '
              'secondi di ritardo');
    });

    test('e il campo è lungo 32 cifre, come vuole la specifica', () {
      for (final g in Genere.values) {
        final f = RegExp(r'DLNA\.ORG_FLAGS=([0-9a-fA-F]+)')
            .firstMatch(g.caratteristiche)!
            .group(1)!;
        expect(f.length, 32, reason: '$g');
      }
    });
  });

  group('quello che un Chromecast NON sa leggere', () {
    // Il modo in cui un Chromecast rifiuta è muto: accetta il comando, dice
    // «va bene», e resta nero. Chi guarda conclude che Minerva è rotta.
    test('quello che sa leggere passa', () {
      for (final t in ['video/mp4', 'audio/mpeg', 'image/jpeg',
                       'application/x-mpegURL', 'audio/flac']) {
        expect(SaLeggere.perche(t, 'Cucina'), isNull, reason: t);
      }
    });

    test('MKV riceve un no che dice di CHI è la colpa', () {
      final m = SaLeggere.perche('video/matroska', 'Cucina');
      expect(m, isNotNull);
      expect(m, contains('MKV'));
      expect(m, contains('Cucina'));
      // Un messaggio che lascia credere che sia colpa nostra manda a cercare
      // un difetto che non c'è.
      expect(m, contains('del televisore'));
    });

    test('AVI pure, e con lo stesso tono', () {
      expect(SaLeggere.perche('video/vnd.avi', 'Cucina'), contains('AVI'));
    });

    test('e un tipo qualunque riceve comunque una frase, non un vuoto', () {
      final m = SaLeggere.perche('application/pdf', 'Salotto');
      expect(m, isNotNull);
      expect(m, contains('Salotto'));
    });

    test('i parametri dopo il punto e virgola non confondono', () {
      // `video/mp4; codecs="avc1.42E01E"` è un tipo valido.
      expect(SaLeggere.perche('video/mp4; codecs="avc1.42E01E"', 'Cucina'),
          isNull);
    });
  });
}

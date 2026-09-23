import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'genere.dart';

/// Il protocollo con cui si parla a un Chromecast o a una Google TV.
///
/// ── Perché è scritto a mano ───────────────────────────────────────────────
///
/// Perché `minervad/pubspec.yaml` dichiara **zero dipendenze esterne**, di
/// proposito, e sulla macchina non c'è nessuno degli strumenti già fatti —
/// `catt`, `go-chromecast`, `mkchromecast`. Il precedente in casa è l'EXIF,
/// scritto camminando i segmenti JPEG a mano: qui è lo stesso mestiere.
///
/// E la parte da scrivere è piccola. Un messaggio CASTV2 è un protobuf con
/// **sei campi**, di cui tre stringhe e due numeri fissi:
///
///     1 protocol_version  varint, sempre 0
///     2 source_id         stringa
///     3 destination_id    stringa
///     4 namespace         stringa
///     5 payload_type      varint, 0 = testo
///     6 payload_utf8      stringa (dentro c'è del JSON)
///
/// Davanti a ogni messaggio va la sua lunghezza in quattro byte, dal più
/// significativo. Non serve una libreria di protobuf per questo: servirebbe
/// per leggerne uno qualunque, e qui i campi si sanno tutti.
///
/// ── Il certificato è autofirmato, e va bene così ──────────────────────────
///
/// Un Chromecast presenta un certificato che nessuna autorità ha firmato: è
/// un apparecchio in casa, non un sito. Rifiutarlo vorrebbe dire non parlarci
/// mai. Si accetta — ma **solo** verso l'indirizzo e la porta che la scoperta
/// mDNS ha trovato in questa rete, e per il tempo di una trasmissione.
class CastV2 {
  final String indirizzo;
  final int porta;

  SecureSocket? _presa;
  final _pezzi = BytesBuilder();
  int _richiesta = 0;

  /// Chi risponde, per messaggio. La chiave è `requestId`: le risposte
  /// tornano fuori ordine, come le miniature.
  final _attese = <int, Completer<Map<String, dynamic>>>{};

  CastV2({required this.indirizzo, this.porta = 8009});

  static const _connessione = 'urn:x-cast:com.google.cast.tp.connection';
  static const _cuore = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _ricevitore = 'urn:x-cast:com.google.cast.receiver';
  static const _media = 'urn:x-cast:com.google.cast.media';

  /// Il lettore multimediale di serie, presente su ogni apparecchio Cast.
  static const appLettore = 'CC1AD845';

  bool get collegato => _presa != null;

  /// Apre il canale e si presenta.
  Future<void> apri({Duration pazienza = const Duration(seconds: 6)}) async {
    final s = await SecureSocket.connect(
      indirizzo,
      porta,
      // Vedi sopra: un apparecchio di casa non ha un certificato firmato da
      // nessuno, e l'unica alternativa a fidarsi è non parlargli.
      onBadCertificate: (_) => true,
      timeout: pazienza,
    );
    _presa = s;
    s.listen(_arrivato, onDone: _chiuso, onError: (_) => _chiuso());

    // «CONNECT» è obbligatorio e non ha risposta: senza, il televisore
    // chiude il collegamento dopo il primo messaggio, e il sintomo è una
    // connessione che cade da sola senza nessun errore.
    _manda(_connessione, '{"type":"CONNECT"}');
  }

  /// Chiede al televisore che cosa sta facendo. È anche il modo di sapere se
  /// il dialogo funziona: se torna, ci stiamo parlando davvero.
  Future<Map<String, dynamic>> stato({
    Duration pazienza = const Duration(seconds: 6),
  }) =>
      _chiedi(_ricevitore, {'type': 'GET_STATUS'}, pazienza);

  /// Fa comparire una fotografia sul televisore.
  ///
  /// Tre passi, e nessuno si può saltare:
  ///
  ///  1. **si accende il ricevitore.** `CC1AD845` è il lettore multimediale
  ///     di serie, quello che c'è su ogni apparecchio Cast: non va installato
  ///     niente, ma va acceso, e finché non lo è non c'è nessuno che ascolti
  ///     i comandi dei contenuti;
  ///  2. **ci si presenta a LUI.** Il `CONNECT` di prima era col televisore;
  ///     l'applicazione appena accesa è un altro interlocutore, con un suo
  ///     indirizzo (`transportId`), e senza un secondo `CONNECT` il `LOAD`
  ///     se ne va nel vuoto — senza errore;
  ///  3. **si dà l'indirizzo della fotografia.** Non i byte: l'indirizzo. È
  ///     il televisore che se la viene a prendere, ed è il motivo per cui
  ///     serve `ServizioEffimero`.
  Future<Map<String, dynamic>> mostra({
    required String indirizzoFoto,
    String tipo = 'image/jpeg',
    String titolo = '',
    // ── Venticinque secondi, e non dodici ────────────────────────────────
    //
    // Il primo passo di `mostra` è `LAUNCH`: accendere il lettore
    // multimediale. Su un televisore già sveglio è istantaneo — misurato il
    // 3 settembre 2026 sulla TV in cameretta: **259 ms** per tutto il giro. Su
    // uno che dormiva, il lettore va prima caricato, e dodici secondi non
    // bastavano.
    //
    // Il sintomo era peggio del ritardo: la trasmissione falliva con «è acceso
    // e sulla stessa rete?», e il televisore era acceso, sulla stessa rete, e
    // stava proprio accendendo il lettore. Un messaggio che manda a
    // controllare la cosa giusta e la trova a posto è un messaggio che fa
    // perdere un'ora.
    //
    // Venticinque secondi si pagano solo quando qualcosa non va: se il
    // televisore risponde, risponde subito.
    Duration pazienza = const Duration(seconds: 25),
  }) async {
    final genere = Genere.di(tipo);
    final acceso = await _chiedi(
        _ricevitore, {'type': 'LAUNCH', 'appId': appLettore}, pazienza);
    final trasporto = _trasportoDi(acceso);
    if (trasporto == null) {
      throw StateError('il televisore non ha acceso il lettore: '
          '${acceso['type']}');
    }

    _manda(_connessione, '{"type":"CONNECT"}', a: trasporto);

    final id = ++_richiesta;
    final c = Completer<Map<String, dynamic>>();
    _attese[id] = c;
    _manda(
      _media,
      jsonEncode({
        'type': 'LOAD',
        'requestId': id,
        'media': {
          'contentId': indirizzoFoto,
          'contentType': tipo,
          // ── Tre cose che il tipo sa già dire ──────────────────────────
          //
          // C'era un parametro `dalVivo` a dirlo a mano, ed era una cosa in
          // più che poteva contraddire il tipo: `application/x-mpegURL` con
          // `dalVivo: false` è una richiesta impossibile che nessuno avrebbe
          // fermato. Adesso lo decide il tipo, e la traduzione sta in
          // `genere.dart` con le sue prove.
          //
          // `streamType`: `LIVE` per lo schermo trasmesso (il lettore sta in
          // coda invece di scaricare dal principio e restare sempre più
          // indietro), `BUFFERED` per un film (barra di avanzamento e salto
          // avanti), `NONE` per una fotografia, che non scorre.
          //
          // `metadataType`: 4 è «fotografia» — con quello su un film il
          // lettore predefinito mette la cornice da album fotografico attorno
          // al filmato.
          'streamType': genere.modoFlussoCast,
          if (titolo.isNotEmpty)
            'metadata': {'metadataType': genere.metadatoCast, 'title': titolo},
        },
        'autoplay': true,
      }),
      a: trasporto,
    );
    return c.future.timeout(pazienza, onTimeout: () {
      _attese.remove(id);
      throw TimeoutException('il lettore non ha risposto al comando');
    });
  }

  /// L'indirizzo dell'applicazione appena accesa, dentro `RECEIVER_STATUS`.
  static String? _trasportoDi(Map<String, dynamic> r) {
    final st = r['status'];
    if (st is! Map) return null;
    final app = st['applications'];
    if (app is! List || app.isEmpty) return null;
    final t = (app.first as Map)['transportId'];
    return t is String ? t : null;
  }

  /// Il battito che tiene aperto il canale.
  ///
  /// Il televisore chiude un collegamento silenzioso dopo una decina di
  /// secondi. Chi trasmette deve chiamarlo ogni cinque.
  void battito() => _manda(_cuore, '{"type":"PING"}');

  Future<void> chiudi() async {
    final s = _presa;
    _presa = null;
    if (s == null) return;
    try {
      // Si saluta prima di andarsene: senza, il televisore resta a credere
      // che ci sia ancora qualcuno e rifiuta il prossimo collegamento per
      // qualche secondo.
      _mandaSu(s, _connessione, '{"type":"CLOSE"}');
      await s.flush().timeout(const Duration(seconds: 1));
    } catch (_) {
      // Chiudere non deve poter fallire: se il canale è già andato, tanto
      // meglio.
    }
    await s.close();
  }

  // ── Il dialogo ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _chiedi(
      String spazio, Map<String, dynamic> cosa, Duration pazienza) {
    final id = ++_richiesta;
    final c = Completer<Map<String, dynamic>>();
    _attese[id] = c;
    _manda(spazio, jsonEncode({...cosa, 'requestId': id}));
    return c.future.timeout(pazienza, onTimeout: () {
      _attese.remove(id);
      throw TimeoutException(
          'il televisore non ha risposto entro ${pazienza.inSeconds} secondi');
    });
  }

  void _manda(String spazio, String payload, {String a = 'receiver-0'}) {
    final s = _presa;
    if (s == null) return;
    _mandaSu(s, spazio, payload, a: a);
  }

  static void _mandaSu(SecureSocket s, String spazio, String payload,
      {String a = 'receiver-0'}) {
    final corpo = componi(
      sorgente: 'sender-minerva',
      destinazione: a,
      spazio: spazio,
      payload: payload,
    );
    // La lunghezza davanti, quattro byte dal più significativo.
    final testa = Uint8List(4);
    ByteData.view(testa.buffer).setUint32(0, corpo.length, Endian.big);
    s.add(testa);
    s.add(corpo);
  }

  void _arrivato(List<int> byte) {
    _pezzi.add(byte);
    // Un messaggio può arrivare in più pezzi, e più messaggi in un pezzo
    // solo: si accumula e si taglia sulla lunghezza dichiarata. Dare per
    // scontato che un pezzo sia un messaggio è il difetto che si vede solo
    // quando la rete è lenta.
    while (true) {
      final tutto = _pezzi.toBytes();
      if (tutto.length < 4) return;
      final quanto = ByteData.view(tutto.buffer, tutto.offsetInBytes)
          .getUint32(0, Endian.big);
      if (tutto.length < 4 + quanto) return;
      final corpo = tutto.sublist(4, 4 + quanto);
      _pezzi.clear();
      _pezzi.add(tutto.sublist(4 + quanto));
      _leggi(corpo);
    }
  }

  void _leggi(Uint8List corpo) {
    final m = scomponi(corpo);
    final payload = m['payload'];
    if (payload == null || payload.isEmpty) return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    // Al PING si risponde PONG, o il canale cade fra dieci secondi.
    if (j['type'] == 'PING') {
      _manda(_cuore, '{"type":"PONG"}');
      return;
    }
    final id = j['requestId'];
    if (id is int) {
      _attese.remove(id)?.complete(j);
    }
  }

  void _chiuso() {
    _presa = null;
    for (final c in _attese.values) {
      if (!c.isCompleted) {
        c.completeError(
            const SocketException('il televisore ha chiuso il collegamento'));
      }
    }
    _attese.clear();
  }

  // ══ Il protobuf, a mano ══════════════════════════════════════════════
  //
  // Sei campi, e nessuno annidato. Le due regole che bastano:
  //
  //   · ogni campo comincia con un byte «chiave» = numero << 3 | tipo,
  //     dove tipo 0 è un numero e tipo 2 è «lunghezza poi byte»;
  //   · i numeri sono varint: sette bit per byte, il più alto dice «continua».
  //
  // Si prova senza rete: `test/castv2_test.dart` compone un messaggio e lo
  // riscompone, che è l'unico modo di sapere che i byte sono quelli giusti
  // senza un televisore acceso.

  /// Da campi a byte.
  static Uint8List componi({
    required String sorgente,
    required String destinazione,
    required String spazio,
    required String payload,
  }) {
    final b = BytesBuilder();
    _varint(b, 0x08); // campo 1, tipo 0
    _varint(b, 0); // protocol_version = 0 (CASTV2_1_0)
    _stringa(b, 2, sorgente);
    _stringa(b, 3, destinazione);
    _stringa(b, 4, spazio);
    _varint(b, 0x28); // campo 5, tipo 0
    _varint(b, 0); // payload_type = 0 (STRING)
    _stringa(b, 6, payload);
    return b.toBytes();
  }

  /// Da byte a campi. Torna almeno `spazio` e `payload`.
  ///
  /// I campi che non conosciamo si **saltano**, non fanno fallire: un
  /// televisore nuovo può aggiungerne uno, e un lettore che si ferma davanti
  /// a un campo in più è un lettore che smetterà di funzionare da solo.
  static Map<String, String> scomponi(Uint8List byte) {
    final fuori = <String, String>{};
    const nomi = {2: 'sorgente', 3: 'destinazione', 4: 'spazio', 6: 'payload'};
    var i = 0;
    while (i < byte.length) {
      final (chiave, dopo) = _leggiVarint(byte, i);
      i = dopo;
      final numero = chiave >> 3;
      final tipo = chiave & 0x07;
      if (tipo == 0) {
        final (_, d) = _leggiVarint(byte, i);
        i = d;
      } else if (tipo == 2) {
        final (quanto, d) = _leggiVarint(byte, i);
        i = d;
        if (i + quanto > byte.length) break;
        final pezzo = byte.sublist(i, i + quanto);
        i += quanto;
        final nome = nomi[numero];
        if (nome != null) fuori[nome] = utf8.decode(pezzo, allowMalformed: true);
      } else {
        // Un tipo che non sappiamo leggere: fermarsi è l'unica cosa onesta,
        // perché da qui in poi non sappiamo più dove comincia il campo dopo.
        break;
      }
    }
    return fuori;
  }

  static void _stringa(BytesBuilder b, int numero, String s) {
    final byte = utf8.encode(s);
    _varint(b, (numero << 3) | 2);
    _varint(b, byte.length);
    b.add(byte);
  }

  static void _varint(BytesBuilder b, int v) {
    var n = v;
    while (n >= 0x80) {
      b.addByte((n & 0x7F) | 0x80);
      n >>= 7;
    }
    b.addByte(n);
  }

  static (int, int) _leggiVarint(Uint8List byte, int da) {
    var n = 0;
    var spostamento = 0;
    var i = da;
    while (i < byte.length) {
      final b = byte[i++];
      n |= (b & 0x7F) << spostamento;
      if (b & 0x80 == 0) break;
      spostamento += 7;
    }
    return (n, i);
  }
}

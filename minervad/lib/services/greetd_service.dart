import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Il dialogo con `greetd`, cioè con chi verifica la password e apre la
/// sessione.
///
/// ── Perché nel demone e non nella shell ────────────────────────────────────
///
/// Non è una scelta di gusto, è un vincolo. Il protocollo di greetd inquadra
/// ogni messaggio così:
///
///     <lunghezza: intero a 32 bit, ORDINE NATIVO><JSON in UTF-8>
///
/// Quickshell 0.3 ha `Socket`, ma l'unico analizzatore concreto che offre è
/// `SplitParser`, che taglia su un delimitatore. Un prefisso binario di
/// lunghezza non si può leggere così: il byte 0x0A dentro un numero non è un
/// a-capo, e un JSON che contiene il carattere di separazione manderebbe tutto
/// fuori sincrono. Dart legge byte, quindi il dialogo sta qui e la shell chiede
/// dal solito canale.
///
/// ── Le tre cose che questo protocollo NON garantisce ───────────────────────
///
/// 1. **Un messaggio non arriva tutto insieme.** Su un socket i byte arrivano
///    a pezzi: leggere una volta sola e aspettarsi un messaggio intero
///    funziona finché il messaggio è corto, e smette il giorno in cui PAM
///    manda una frase lunga. Per questo c'è `GreetdFramer`, che accumula.
/// 2. **In un pezzo ce ne può stare più d'uno.** Stessa ragione al contrario:
///    dopo aver letto un messaggio bisogna guardare se nel buffer ce n'è già
///    un altro, e non tornare ad aspettare.
/// 3. **Quanti giri di domande servano.** La pagina di manuale è esplicita:
///    «there are no limits on the number and type of messages that may be
///    required». Niente conti su «prima l'utente, poi la password»: si
///    risponde a quello che arriva, finché arriva.
class GreetdFramer {
  final List<int> _buffer = [];

  /// Impacchetta un messaggio: quattro byte di lunghezza più il JSON.
  ///
  /// `Endian.host` e non `Endian.little`: la pagina di manuale dice «native
  /// byte order». Su questa macchina sono la stessa cosa, e scriverlo giusto
  /// costa zero — scriverlo sbagliato si scoprirebbe solo su un'altra
  /// architettura, dove nessuno andrebbe a cercarlo qui.
  static Uint8List encode(Map<String, dynamic> messaggio) {
    final corpo = utf8.encode(jsonEncode(messaggio));
    final fuori = Uint8List(4 + corpo.length);
    ByteData.view(fuori.buffer).setUint32(0, corpo.length, Endian.host);
    fuori.setRange(4, 4 + corpo.length, corpo);
    return fuori;
  }

  /// Aggiunge byte appena arrivati e restituisce i messaggi COMPLETI che ne
  /// escono — nessuno, uno, o parecchi.
  List<Map<String, dynamic>> aggiungi(List<int> pezzo) {
    _buffer.addAll(pezzo);
    final fuori = <Map<String, dynamic>>[];

    while (true) {
      if (_buffer.length < 4) break;

      final testa = Uint8List.fromList(_buffer.sublist(0, 4));
      final quanti = ByteData.view(testa.buffer).getUint32(0, Endian.host);

      // Una lunghezza assurda vuol dire che il flusso è andato fuori sincrono:
      // continuare a leggere non lo rimette a posto, aspetterebbe per sempre
      // byte che non arriveranno. Meglio dirlo forte.
      if (quanti > _limiteMessaggio) {
        throw GreetdProtocolError(
            'Messaggio dichiarato di $quanti byte: il flusso è fuori sincrono');
      }

      if (_buffer.length < 4 + quanti) break;

      final corpo = _buffer.sublist(4, 4 + quanti);
      _buffer.removeRange(0, 4 + quanti);

      final letto = jsonDecode(utf8.decode(corpo));
      if (letto is Map<String, dynamic>) {
        fuori.add(letto);
      } else {
        throw GreetdProtocolError('Messaggio che non è un oggetto JSON');
      }
    }

    return fuori;
  }

  /// Quanti byte sono rimasti in attesa del resto. Serve alle prove e a
  /// capire, leggendo un registro, se ci si è fermati a metà messaggio.
  int get inAttesa => _buffer.length;

  /// Un messaggio di greetd è una manciata di byte. Un megabyte è già mille
  /// volte il necessario: oltre, non è un messaggio lungo, è un errore.
  static const int _limiteMessaggio = 1024 * 1024;
}

class GreetdProtocolError implements Exception {
  final String messaggio;
  const GreetdProtocolError(this.messaggio);
  @override
  String toString() => 'GreetdProtocolError: $messaggio';
}

/// Una richiesta sul filo corrisponde a una risposta, anche quando PAM
/// richiede più giri. Il chiamante deve rispondere a ogni auth_message.
/// I messaggi e i guasti non contengono mai il payload inviato.
class GreetdService {
  GreetdService({this.responseTimeout = const Duration(seconds: 45)});
  final Duration responseTimeout;
  Socket? _socket;
  Completer<Map<String, dynamic>>? _pending;
  int _generation = 0;
  bool _closed = false;
  void Function()? onDisconnect;

  static String? get percorsoSocket {
    final p = Platform.environment['GREETD_SOCK'];
    return p == null || p.isEmpty ? null : p;
  }
  String? get socketDaUsare => percorsoSocket;
  bool get connesso => _socket != null;

  static Map<String, dynamic> failure(String text) => {
    'type': 'error', 'error_type': 'error', 'description': text,
    'transport_error': true,
  };

  Future<Map<String, dynamic>> request(Map<String, dynamic> message) async {
    if (_closed) return failure('Canale greetd chiuso');
    if (_pending != null) throw StateError('Richiesta greetd già in corso');
    final pending = Completer<Map<String, dynamic>>();
    _pending = pending;
    final generation = _generation;
    final timer = Timer(responseTimeout, () => _fail('Tempo di risposta greetd scaduto'));
    // _send gestisce anche connect/flush falliti; nessun Future dimenticato.
    unawaited(_send(message, pending, generation));
    try {
      return await pending.future;
    } finally {
      timer.cancel();
    }
  }

  Future<void> _send(Map<String, dynamic> message,
      Completer<Map<String, dynamic>> pending, int generation) async {
    try {
      var socket = _socket;
      if (socket == null) {
        final path = socketDaUsare;
        if (path == null) {
          _fail('Nessuna connessione a greetd');
          return;
        }
        socket = await Socket.connect(
          InternetAddress(path, type: InternetAddressType.unix), 0,
          timeout: const Duration(seconds: 5));
        if (_closed || generation != _generation || !identical(_pending, pending)) {
          socket.destroy();
          return;
        }
        _socket = socket;
        // Il buffer appartiene al socket: i byte parziali muoiono con esso.
        final framer = GreetdFramer();
        final current = socket;
        socket.listen((bytes) {
          if (!identical(_socket, current)) return;
          try {
            final messages = framer.aggiungi(bytes);
            if (messages.isEmpty) return;
            if (messages.length != 1 || _pending == null || framer.inAttesa != 0) {
              _fail('Risposta greetd inattesa');
              return;
            }
            final reply = messages.single;
            if (!['success', 'error', 'auth_message'].contains(reply['type'])) {
              _fail('Tipo di risposta greetd non valido');
              return;
            }
            final waiting = _pending!;
            _pending = null;
            waiting.complete(reply);
          } catch (_) {
            _fail('Risposta greetd illeggibile');
          }
        }, onError: (_) {
          if (identical(_socket, current)) _fail('Errore di lettura greetd');
        }, onDone: () {
          if (identical(_socket, current)) _fail('greetd ha chiuso la connessione');
        }, cancelOnError: true);
      }
      if (_closed || generation != _generation || !identical(_pending, pending)) return;
      socket.add(GreetdFramer.encode(message));
      await socket.flush();
    } catch (_) {
      if (generation == _generation && identical(_pending, pending)) {
        _fail('Impossibile comunicare con greetd');
      }
    }
  }

  void _fail(String description) {
    _generation++;
    final socket = _socket;
    _socket = null;
    socket?.destroy();
    final waiting = _pending;
    _pending = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete(failure(description));
    onDisconnect?.call();
  }

  Future<void> chiudi() async {
    if (_closed) return;
    _closed = true;
    onDisconnect = null;
    _fail('Canale greetd chiuso');
  }
}

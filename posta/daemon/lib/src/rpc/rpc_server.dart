import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'rpc_errors.dart';

/// Firma di un metodo esposto via JSON-RPC.
///
/// [params] è sempre una mappa (i parametri posizionali non sono supportati).
/// Il valore restituito diventa il campo `result` della risposta.
typedef RpcHandler = FutureOr<Object?> Function(
    Map<String, Object?> params, RpcSession session);

/// Limiti e opzioni del server. I valori di default sono quelli di produzione;
/// i test li abbassano per provocare gli errori in fretta.
class RpcServerConfig {
  const RpcServerConfig({
    required this.token,
    this.port = 0,
    this.maxMessageBytes = 1024 * 1024,
    this.authTimeout = const Duration(seconds: 5),
    this.maxPreAuthBytes = 16 * 1024,
    this.maxPendingSessions = 32,
  });

  /// Byte grezzi accettati da una connessione non ancora autenticata. Il
  /// messaggio `auth` occupa meno di 200 byte: oltre questa soglia la
  /// connessione cade subito, senza aspettare la fine del messaggio.
  final int maxPreAuthBytes;

  /// Connessioni contemporanee in attesa di `auth`; le successive ricevono 503.
  /// Al login possono collegarsi insieme finestra, badge e notifiche: 32 è
  /// largo, e costa al massimo 32 × [maxPreAuthBytes] di memoria.
  final int maxPendingSessions;

  /// Segreto condiviso con la UI, letto dal file in $XDG_RUNTIME_DIR.
  final String token;

  /// 0 = porta scelta dal sistema (usato nei test).
  final int port;

  /// Messaggi più grandi chiudono la connessione con codice 1009.
  final int maxMessageBytes;

  /// Tempo concesso al client per autenticarsi prima della chiusura.
  final Duration authTimeout;
}

/// Una connessione WebSocket di un client (di norma la UI QML).
class RpcSession {
  RpcSession._(this._socket, this.id);

  final WebSocket _socket;
  final int id;
  bool authenticated = false;
  bool _closed = false;

  /// Invio che non lancia mai. Una risposta tardiva verso un client che se
  /// n'è andato (finestra chiusa, daemon in arresto) viene scartata: un errore
  /// qui sarebbe un'eccezione asincrona non gestita, cioè il crash del daemon.
  void _send(Map<String, Object?> message) {
    if (_closed || _socket.readyState != WebSocket.open) return;
    try {
      _socket.add(jsonEncode(message));
    } on StateError {
      _closed = true;
    }
  }

  Future<void> _close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    await _socket.close(code, reason);
  }

  /// Invia una notifica (evento push) a questo client.
  void notify(String method, Object? params) {
    _send({'jsonrpc': '2.0', 'method': method, 'params': params});
  }
}

/// Server JSON-RPC 2.0 su WebSocket, in ascolto solo su 127.0.0.1.
///
/// Sicurezza:
/// - il primo messaggio deve essere `auth` con il token corretto;
/// - le connessioni con header `Origin` (cioè da un browser) sono rifiutate,
///   così una pagina web non può pilotare il daemon via localhost;
/// - i messaggi oltre [RpcServerConfig.maxMessageBytes] chiudono la connessione.
class RpcServer {
  RpcServer(this.config);

  final RpcServerConfig config;
  final Map<String, RpcHandler> _handlers = {};
  final Set<RpcSession> _sessions = {};
  HttpServer? _http;
  int _nextSessionId = 1;

  /// Registra un metodo. Registrare due volte lo stesso nome è un errore
  /// di programmazione e viene segnalato subito.
  void register(String method, RpcHandler handler) {
    if (method == 'auth') {
      throw ArgumentError('"auth" è riservato al server');
    }
    if (_handlers.containsKey(method)) {
      throw StateError('Metodo già registrato: $method');
    }
    _handlers[method] = handler;
  }

  int get port {
    final http = _http;
    if (http == null) throw StateError('Server non avviato');
    return http.port;
  }

  int get sessionCount => _sessions.length;

  Future<void> start() async {
    if (_http != null) throw StateError('Server già avviato');
    final http =
        await HttpServer.bind(InternetAddress.loopbackIPv4, config.port);
    _http = http;
    http.listen(_onHttpRequest);
  }

  Future<void> stop() async {
    final http = _http;
    _http = null;
    for (final session in _sessions.toList()) {
      await session._close(WebSocketStatus.goingAway, 'daemon stop');
    }
    _sessions.clear();
    await http?.close(force: true);
  }

  /// Invia un evento a tutti i client autenticati.
  void broadcast(String method, Object? params) {
    for (final session in _sessions) {
      if (session.authenticated) session.notify(method, params);
    }
  }

  Future<void> _onHttpRequest(HttpRequest request) async {
    if (request.headers.value('origin') != null) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.upgradeRequired;
      await request.response.close();
      return;
    }
    final key = request.headers.value('sec-websocket-key');
    if (key == null || request.headers.value('sec-websocket-version') != '13') {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }
    if (_sessions.where((s) => !s.authenticated).length >= config.maxPendingSessions) {
      request.response.statusCode = HttpStatus.serviceUnavailable;
      await request.response.close();
      return;
    }

    // Handshake fatto qui e non con WebSocketTransformer.upgrade, per due
    // motivi: la compressione resta spenta (un messaggio compresso si
    // espanderebbe dopo ogni controllo sui byte ricevuti), e il socket
    // grezzo passa da un filtro che conta i byte di chi non si è ancora
    // autenticato. WebSocket consegna un messaggio solo quando è arrivato
    // tutto: senza il filtro, uno sconosciuto potrebbe mandare un unico
    // messaggio da qualche GB e il daemon lo terrebbe in memoria per intero
    // prima di poterlo rifiutare.
    final accept = base64.encode(sha1.convert(ascii.encode('$key$_websocketGuid')).bytes);
    final response = request.response
      ..statusCode = HttpStatus.switchingProtocols
      ..headers.set(HttpHeaders.connectionHeader, 'Upgrade')
      ..headers.set(HttpHeaders.upgradeHeader, 'websocket')
      ..headers.set('Sec-WebSocket-Accept', accept)
      ..contentLength = 0;
    final Socket raw;
    try {
      raw = await response.detachSocket();
    } on Object {
      return; // il client se n'è andato durante l'handshake
    }
    RpcSession? pending;
    var preAuthBytes = 0;
    final guarded = _GuardedSocket(raw, (bytes) {
      if (pending?.authenticated ?? false) return true;
      preAuthBytes += bytes;
      return preAuthBytes <= config.maxPreAuthBytes;
    });
    final socket = WebSocket.fromUpgradedSocket(guarded,
        serverSide: true, compression: CompressionOptions.compressionOff);
    final session = pending = RpcSession._(socket, _nextSessionId++);
    _sessions.add(session);

    final authTimer = Timer(config.authTimeout, () {
      if (!session.authenticated) {
        session._close(WebSocketStatus.policyViolation, 'auth timeout');
      }
    });

    socket.listen(
      (data) => _onMessage(session, data),
      onDone: () {
        session._closed = true;
        authTimer.cancel();
        _sessions.remove(session);
      },
      onError: (_) {
        session._closed = true;
        authTimer.cancel();
        _sessions.remove(session);
      },
      cancelOnError: true,
    );
  }

  Future<void> _onMessage(RpcSession session, Object? data) async {
    if (data is! String) {
      await session._close(WebSocketStatus.unsupportedData, 'solo messaggi di testo');
      return;
    }
    if (utf8.encode(data).length > config.maxMessageBytes) {
      await session._close(WebSocketStatus.messageTooBig, 'messaggio troppo grande');
      return;
    }

    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      session._send(_error(null, RpcErrorCode.parseError, 'JSON non valido'));
      return;
    }

    if (decoded is List) {
      session._send(_error(null, RpcErrorCode.invalidRequest,
          'Le richieste batch non sono supportate'));
      return;
    }
    if (decoded is! Map<String, Object?>) {
      session._send(_error(
          null, RpcErrorCode.invalidRequest, 'La richiesta deve essere un oggetto'));
      return;
    }

    final id = decoded['id'];
    final hasId = decoded.containsKey('id');
    if (hasId && id != null && id is! String && id is! int) {
      session._send(
          _error(null, RpcErrorCode.invalidRequest, 'id deve essere stringa o intero'));
      return;
    }
    if (decoded['jsonrpc'] != '2.0') {
      session._send(_error(id, RpcErrorCode.invalidRequest, 'jsonrpc deve essere "2.0"'));
      return;
    }
    final method = decoded['method'];
    if (method is! String || method.isEmpty) {
      session._send(_error(id, RpcErrorCode.invalidRequest, 'method mancante'));
      return;
    }
    final rawParams = decoded['params'];
    if (rawParams != null && rawParams is! Map<String, Object?>) {
      session._send(
          _error(id, RpcErrorCode.invalidParams, 'params deve essere un oggetto'));
      return;
    }
    final params = (rawParams as Map<String, Object?>?) ?? const {};

    if (method == 'auth') {
      _handleAuth(session, id, params);
      return;
    }
    if (!session.authenticated) {
      session._send(_error(id, RpcErrorCode.unauthorized, 'Autenticazione richiesta'));
      return;
    }

    final handler = _handlers[method];
    if (handler == null) {
      if (hasId) {
        session._send(
            _error(id, RpcErrorCode.methodNotFound, 'Metodo sconosciuto: $method'));
      }
      return;
    }

    try {
      final result = await handler(params, session);
      if (hasId) {
        session._send({'jsonrpc': '2.0', 'id': id, 'result': result});
      }
    } on RpcException catch (e) {
      if (hasId) session._send({'jsonrpc': '2.0', 'id': id, 'error': e.toJson()});
    } catch (e) {
      // Un handler difettoso non deve mai abbattere il daemon né far
      // trapelare dettagli interni: il client riceve un errore generico.
      stderr.writeln('[rpc] errore in $method: $e');
      if (hasId) {
        session._send(_error(id, RpcErrorCode.internalError, 'Errore interno'));
      }
    }
  }

  void _handleAuth(RpcSession session, Object? id, Map<String, Object?> params) {
    final token = params['token'];
    if (token is String && _constantTimeEquals(token, config.token)) {
      session.authenticated = true;
      session._send({'jsonrpc': '2.0', 'id': id, 'result': {'ok': true}});
    } else {
      session._send(_error(id, RpcErrorCode.unauthorized, 'Token non valido'));
      session._close(WebSocketStatus.policyViolation, 'token non valido');
    }
  }

  static Map<String, Object?> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  /// Confronto a tempo costante: non rivela quanti caratteri del token
  /// sono corretti misurando il tempo di risposta.
  static bool _constantTimeEquals(String a, String b) {
    final ba = utf8.encode(a);
    final bb = utf8.encode(b);
    var diff = ba.length ^ bb.length;
    for (var i = 0; i < ba.length; i++) {
      diff |= ba[i] ^ (i < bb.length ? bb[i] : 0);
    }
    return diff == 0;
  }
}

/// RFC 6455 §1.3.
const _websocketGuid = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

/// Socket che lascia passare i dati in arrivo solo finché [allow] risponde
/// sì; al primo no il socket viene distrutto e lo stream finisce. Tutto il
/// resto è delegato al socket vero.
class _GuardedSocket extends StreamView<Uint8List> implements Socket {
  _GuardedSocket._(this._inner, Stream<Uint8List> stream) : super(stream);

  factory _GuardedSocket(Socket inner, bool Function(int bytes) allow) {
    var cut = false;
    final stream = inner.transform<Uint8List>(StreamTransformer.fromHandlers(
      handleData: (data, sink) {
        if (cut) return;
        if (allow(data.length)) {
          sink.add(data);
        } else {
          cut = true;
          inner.destroy();
          sink.close();
        }
      },
      handleDone: (sink) {
        if (!cut) sink.close();
      },
    ));
    return _GuardedSocket._(inner, stream);
  }

  final Socket _inner;

  @override
  Encoding get encoding => _inner.encoding;
  @override
  set encoding(Encoding value) => _inner.encoding = value;
  @override
  void add(List<int> data) => _inner.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) => _inner.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _inner.addStream(stream);
  @override
  Future<void> close() => _inner.close();
  @override
  Future<void> get done => _inner.done;
  @override
  Future<void> flush() => _inner.flush();
  @override
  void write(Object? object) => _inner.write(object);
  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _inner.writeAll(objects, separator);
  @override
  void writeCharCode(int charCode) => _inner.writeCharCode(charCode);
  @override
  void writeln([Object? object = '']) => _inner.writeln(object);
  @override
  InternetAddress get address => _inner.address;
  @override
  int get port => _inner.port;
  @override
  InternetAddress get remoteAddress => _inner.remoteAddress;
  @override
  int get remotePort => _inner.remotePort;
  @override
  bool setOption(SocketOption option, bool enabled) => _inner.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _inner.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _inner.setRawOption(option);
  @override
  void destroy() => _inner.destroy();
}

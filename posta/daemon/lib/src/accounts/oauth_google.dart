import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Accesso a Gmail con OAuth 2.0, come Thunderbird: l'utente entra dalla
/// pagina di Google nel browser (dove Google chiede la conferma dal telefono
/// o il numero), e Posta riceve un token al posto della password.
///
/// Dati del provider presi dall'elenco pubblico di Thunderbird
/// (comm-central, mailnews/base/src/OAuth2Providers.sys.mjs): scope
/// `https://mail.google.com/` per IMAP e SMTP, PKCE. Gli endpoint sono quelli
/// documentati da Google per le app desktop. Il codice è nostro; il client
/// (ID e segreto) è quello del progetto Google Cloud di Liquid, letto da un
/// file fuori dal repository.
///
/// Il browser torna su `http://127.0.0.1:<porta>/` (RFC 8252 §7.3): un server
/// HTTP che vive solo durante l'accesso, accetta una sola risposta con lo
/// `state` giusto e poi si chiude.

enum OAuthErrorKind {
  /// Manca il file del client Google: si usa la password per le app.
  notConfigured,

  /// L'utente ha detto no nella pagina di Google, o ha chiuso.
  denied,

  /// L'utente ha tolto la spunta sull'accesso alla posta.
  scopeMissing,

  /// Il token di rinnovo non vale più (revocato, password cambiata):
  /// serve rifare l'accesso dal browser.
  invalidGrant,

  /// L'accesso nel browser non è finito in tempo.
  timeout,

  /// Rete assente o Google non raggiungibile: si riprova più tardi.
  network,

  /// Risposta di Google inattesa.
  protocol,

  /// Annullato da Posta.
  cancelled,
}

class OAuthException implements Exception {
  OAuthException(this.kind, this.message);
  final OAuthErrorKind kind;
  final String message;
  @override
  String toString() => 'OAuthException(${kind.name}): $message';
}

/// ID e segreto del client «App desktop» di Google. Per le app installate
/// Google non considera il segreto davvero segreto (RFC 8252 §8.5): la
/// protezione vera è PKCE. Resta comunque fuori dal repository.
class OAuthClientCredentials {
  const OAuthClientCredentials(this.clientId, this.clientSecret);

  final String clientId;
  final String clientSecret;

  /// Legge il JSON scaricato dalla console di Google (`{"installed": {...}}`).
  /// Null se il file non c'è; eccezione se c'è ma non è valido, così
  /// l'errore si vede invece di sparire nel ripiego sulla password.
  static OAuthClientCredentials? load(String path) {
    final f = File(path);
    if (!f.existsSync()) return null;
    final Object? json;
    try {
      json = jsonDecode(f.readAsStringSync());
    } on FormatException {
      throw OAuthException(OAuthErrorKind.notConfigured, 'File del client Google non leggibile: $path');
    }
    final inner = json is Map ? (json['installed'] ?? json) : null;
    final id = inner is Map ? inner['client_id'] : null;
    final secret = inner is Map ? inner['client_secret'] : null;
    if (id is! String || id.isEmpty || secret is! String || secret.isEmpty) {
      throw OAuthException(OAuthErrorKind.notConfigured,
          'Nel file del client Google mancano client_id o client_secret: $path');
    }
    return OAuthClientCredentials(id, secret);
  }

  /// Dove il servizio cerca il file: `$XDG_CONFIG_HOME/liquid-mail/oauth-google.json`.
  static String defaultPath() {
    final env = Platform.environment;
    final base = env['XDG_CONFIG_HOME'] ?? '${env['HOME']}/.config';
    return '$base/liquid-mail/oauth-google.json';
  }
}

/// Esito di uno scambio o di un rinnovo.
class OAuthTokens {
  OAuthTokens({required this.accessToken, required this.expiresAt, this.refreshToken, this.email});

  final String accessToken;
  final DateTime expiresAt;

  /// Solo al primo accesso (`access_type=offline`): va nel portachiavi.
  final String? refreshToken;

  /// Indirizzo dell'account Google che ha dato il consenso (dall'id_token).
  final String? email;

  bool validFor(Duration margin) => DateTime.now().add(margin).isBefore(expiresAt);
}

/// Un accesso in corso: [url] va aperto nel browser, [result] arriva
/// quando Google rimanda indietro il browser e il codice è stato scambiato.
class OAuthLogin {
  OAuthLogin._(this.url, this.result, this._cancel);

  final Uri url;
  final Future<OAuthTokens> result;
  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

class GoogleOAuth {
  GoogleOAuth(
    this.credentials, {
    Uri? authEndpoint,
    Uri? tokenEndpoint,
    this.loginTimeout = const Duration(minutes: 10),
    this.httpTimeout = const Duration(seconds: 30),
    SecurityContext? securityContext,
  })  : authEndpoint = authEndpoint ?? Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
        tokenEndpoint = tokenEndpoint ?? Uri.parse('https://oauth2.googleapis.com/token'),
        _securityContext = securityContext;

  static const mailScope = 'https://mail.google.com/';
  static const scopes = 'openid email $mailScope';

  final OAuthClientCredentials credentials;
  final Uri authEndpoint;
  final Uri tokenEndpoint;
  final Duration loginTimeout;
  final Duration httpTimeout;
  final SecurityContext? _securityContext;
  final _random = Random.secure();

  String _randomToken(int bytes) =>
      base64Url.encode(List.generate(bytes, (_) => _random.nextInt(256))).replaceAll('=', '');

  /// Apre il server di ritorno e prepara l'indirizzo della pagina di Google.
  Future<OAuthLogin> begin({String? loginHint}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}/';
    final verifier = _randomToken(48); // 64 caratteri, RFC 7636 §4.1
    final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
    final state = _randomToken(24);
    final url = authEndpoint.replace(queryParameters: {
      'client_id': credentials.clientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': scopes,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      // Senza offline non arriva il token di rinnovo; con consent Google lo
      // rimanda anche a chi aveva già dato il permesso in passato.
      'access_type': 'offline',
      'prompt': 'consent',
      if (loginHint != null && loginHint.isNotEmpty) 'login_hint': loginHint,
    });

    final done = Completer<OAuthTokens>();
    late final Timer timer;
    Future<void> finish(Object outcome) async {
      timer.cancel();
      await server.close(force: true);
      if (done.isCompleted) return;
      if (outcome is OAuthTokens) {
        done.complete(outcome);
      } else {
        done.completeError(outcome);
      }
    }

    timer = Timer(loginTimeout, () {
      finish(OAuthException(OAuthErrorKind.timeout, 'L\'accesso con Google non è stato completato in tempo'));
    });

    var handled = false;
    server.listen((req) async {
      final q = req.uri.queryParameters;
      // Solo la radice, solo GET, solo con lo state giusto: un'altra pagina
      // aperta sullo stesso computer non può spacciarsi per Google.
      if (handled || req.method != 'GET' || req.uri.path != '/' ||
          !_sameString(q['state'] ?? '', state)) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      handled = true;
      final error = q['error'];
      final code = q['code'];
      if (error != null || code == null || code.isEmpty) {
        await _page(req.response, ok: false);
        await finish(OAuthException(OAuthErrorKind.denied,
            error == 'access_denied' ? 'Accesso negato nella pagina di Google' : 'Google non ha concesso l\'accesso'));
        return;
      }
      try {
        final tokens = await _exchange(code, redirect, verifier);
        await _page(req.response, ok: true);
        await finish(tokens);
      } on OAuthException catch (e) {
        await _page(req.response, ok: false);
        await finish(e);
      }
    }, onError: (_) {});

    return OAuthLogin._(url, done.future, () => finish(
        OAuthException(OAuthErrorKind.cancelled, 'Accesso con Google annullato')));
  }

  /// Nuovo token d'accesso dal token di rinnovo salvato nel portachiavi.
  Future<OAuthTokens> refresh(String refreshToken) async {
    final json = await _post({
      'client_id': credentials.clientId,
      'client_secret': credentials.clientSecret,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    });
    return _tokens(json, requireRefresh: false);
  }

  Future<OAuthTokens> _exchange(String code, String redirect, String verifier) async {
    final json = await _post({
      'client_id': credentials.clientId,
      'client_secret': credentials.clientSecret,
      'code': code,
      'code_verifier': verifier,
      'redirect_uri': redirect,
      'grant_type': 'authorization_code',
    });
    final scope = json['scope'];
    // Google permette di togliere singoli permessi nella pagina di consenso.
    if (scope is! String || !scope.split(' ').contains(mailScope)) {
      throw OAuthException(OAuthErrorKind.scopeMissing,
          'Nella pagina di Google va lasciata la spunta sull\'accesso a Gmail');
    }
    return _tokens(json, requireRefresh: true);
  }

  OAuthTokens _tokens(Map<String, Object?> json, {required bool requireRefresh}) {
    final access = json['access_token'];
    final expiresIn = json['expires_in'];
    final refresh = json['refresh_token'];
    if (access is! String || access.isEmpty || expiresIn is! int || expiresIn <= 0 ||
        (requireRefresh && (refresh is! String || refresh.isEmpty))) {
      throw OAuthException(OAuthErrorKind.protocol, 'Risposta di Google incompleta');
    }
    return OAuthTokens(
      accessToken: access,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn)),
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
      email: _emailFromIdToken(json['id_token']),
    );
  }

  /// L'id_token arriva direttamente dall'endpoint di Google su TLS, non dal
  /// browser: OpenID Connect Core §3.1.3.7 consente di non verificarne la
  /// firma in questo caso. Si legge solo l'indirizzo, se verificato.
  static String? _emailFromIdToken(Object? idToken) {
    if (idToken is! String) return null;
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (payload is! Map || payload['email_verified'] != true) return null;
      final email = payload['email'];
      return email is String ? email.toLowerCase() : null;
    } on FormatException {
      return null;
    }
  }

  Future<Map<String, Object?>> _post(Map<String, String> form) async {
    final client = HttpClient(context: _securityContext)..connectionTimeout = httpTimeout;
    try {
      final req = await client.postUrl(tokenEndpoint).timeout(httpTimeout);
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      req.write(Uri(queryParameters: form).query);
      final res = await req.close().timeout(httpTimeout);
      final body = await _readLimited(res).timeout(httpTimeout);
      final Object? json;
      try {
        json = jsonDecode(body);
      } on FormatException {
        throw OAuthException(OAuthErrorKind.protocol, 'Risposta di Google non valida (HTTP ${res.statusCode})');
      }
      if (json is! Map<String, Object?>) {
        throw OAuthException(OAuthErrorKind.protocol, 'Risposta di Google non valida');
      }
      if (res.statusCode != HttpStatus.ok) {
        final error = json['error'];
        if (error == 'invalid_grant') {
          throw OAuthException(OAuthErrorKind.invalidGrant,
              'Google non riconosce più l\'accesso: entra di nuovo con Google');
        }
        if (res.statusCode >= 500) {
          throw OAuthException(OAuthErrorKind.network, 'Google non risponde (HTTP ${res.statusCode})');
        }
        throw OAuthException(OAuthErrorKind.protocol,
            'Google ha rifiutato la richiesta (${error is String ? error : res.statusCode})');
      }
      return json;
    } on OAuthException {
      rethrow;
    } on TimeoutException {
      throw OAuthException(OAuthErrorKind.network, 'Google non ha risposto in tempo');
    } on IOException {
      throw OAuthException(OAuthErrorKind.network, 'Google non raggiungibile: controlla la connessione');
    } finally {
      client.close(force: true);
    }
  }

  static Future<String> _readLimited(HttpClientResponse res) async {
    const max = 64 * 1024;
    final bytes = <int>[];
    await for (final chunk in res) {
      bytes.addAll(chunk);
      if (bytes.length > max) {
        throw OAuthException(OAuthErrorKind.protocol, 'Risposta di Google troppo grande');
      }
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<void> _page(HttpResponse res, {required bool ok}) async {
    res.headers.contentType = ContentType.html;
    res.headers.set('Cache-Control', 'no-store');
    final title = ok ? 'Fatto' : 'Accesso non riuscito';
    final text = ok
        ? 'Puoi chiudere questa scheda e tornare a Posta.'
        : 'Torna a Posta per vedere cosa è successo.';
    res.write('<!doctype html><meta charset="utf-8"><title>Liquid Posta</title>'
        '<body style="font-family:sans-serif;text-align:center;padding-top:20vh">'
        '<h1>$title</h1><p>$text</p></body>');
    await res.close();
  }

  static bool _sameString(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

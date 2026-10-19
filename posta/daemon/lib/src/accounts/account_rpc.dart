import '../rpc/rpc_errors.dart';
import '../rpc/rpc_server.dart';
import '../transport/mail_transport.dart';
import 'account_service.dart';
import 'autoconfig.dart';
import 'provider_config.dart';

/// Metodi JSON-RPC per gli account. Nessuna risposta contiene la password.
/// [onAdded] e [beforeRemove] collegano gli account alla sincronizzazione:
/// un account nuovo inizia a sincronizzare subito; uno da rimuovere smette
/// PRIMA che la sua password venga cancellata.
void registerAccountMethods(RpcServer rpc, AccountService service,
    {void Function(int id)? onAdded,
    Future<void> Function(int id)? beforeRemove,
    Future<void> Function(int id)? onReauthed}) {
  rpc.register('account.providers', (_, __) => presetCatalog());

  rpc.register('account.discover', (p, _) => _wrap(() async {
        final email = _requireString(p, 'email');
        final providerId = _optionalString(p, 'providerId');
        final config = await service.discover(email, providerId: providerId);
        return config?.toJson();
      }));

  rpc.register('account.add', (p, _) => _wrap(() async {
        // Tutti i parametri si validano PRIMA di qualsiasi lavoro: un tipo
        // sbagliato deve dare -32602, non un errore successivo che lo copre.
        final email = _requireString(p, 'email');
        final password = _requireString(p, 'password', allowEmpty: true);
        final name = _optionalString(p, 'name');
        final trustedCert = _optionalString(p, 'trustedCertSha256');
        final providerId = _optionalString(p, 'providerId');
        final rawConfig = p['config'];
        final ProviderConfig config;
        if (rawConfig == null) {
          final found = await service.discover(email, providerId: providerId);
          if (found == null) {
            throw AccountException(AccountErrorReason.invalidInput,
                'Impostazioni non trovate: inseriscile manualmente');
          }
          config = found;
        } else {
          config = parseClientConfig(rawConfig, email);
        }
        final info = await service.add(
          email: email,
          password: password,
          config: config,
          name: name,
          trustedCertSha256: trustedCert,
        );
        onAdded?.call(info.id);
        return info.toJson();
      }));

  // «Accedi con Google»: begin dà la pagina da aprire nel browser, finish
  // aspetta che l'utente finisca lì (anche minuti) e restituisce l'account.
  rpc.register('account.oauthAvailable', (_, __) => {'google': service.googleOAuthAvailable});

  rpc.register('account.oauthBegin', (p, _) => _wrap(() async {
        final r = await service.oauthBegin(_requireString(p, 'email'));
        return {'session': r.session, 'url': r.url.toString()};
      }));

  rpc.register('account.oauthFinish', (p, _) => _wrap(() async {
        final session = _requireString(p, 'session');
        final name = _optionalString(p, 'name');
        final r = await service.oauthFinish(session, name: name);
        if (r.existed) {
          await onReauthed?.call(r.info.id);
        } else {
          onAdded?.call(r.info.id);
        }
        return r.info.toJson();
      }));

  rpc.register('account.oauthCancel', (p, _) => _wrap(() async {
        await service.oauthCancel(_requireString(p, 'session'));
        return {'ok': true};
      }));

  rpc.register('account.list', (_, __) => [for (final a in service.list()) a.toJson()]);

  rpc.register('account.remove', (p, _) => _wrap(() async {
        final id = p['id'];
        if (id is! int) throw RpcException(RpcErrorCode.invalidParams, 'id deve essere un intero');
        await beforeRemove?.call(id);
        await service.remove(id);
        return {'ok': true};
      }));
}

Future<T> _wrap<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on AccountException catch (e) {
    throw RpcException(RpcErrorCode.accountError, e.message, {
      'reason': e.reason.name,
      if (e.certificateSha256 != null) 'certificateSha256': e.certificateSha256,
    });
  }
}

String _requireString(Map<String, Object?> p, String key, {bool allowEmpty = false}) {
  final v = p[key];
  if (v is! String || (!allowEmpty && v.trim().isEmpty)) {
    throw RpcException(RpcErrorCode.invalidParams, '$key mancante o non valido');
  }
  return v;
}

String? _optionalString(Map<String, Object?> p, String key) {
  final v = p[key];
  if (v == null) return null;
  if (v is! String) throw RpcException(RpcErrorCode.invalidParams, '$key deve essere una stringa');
  return v;
}

/// Configurazione inserita a mano o confermata nella UI. Viene rivalidata:
/// il daemon non si fida del client, nemmeno se è la nostra interfaccia.
ProviderConfig parseClientConfig(Object? raw, String email) {
  Never bad(String what) => throw RpcException(RpcErrorCode.invalidParams, 'config: $what');
  if (raw is! Map<String, Object?>) bad('deve essere un oggetto');

  ServerEndpoint endpoint(String key) {
    final e = raw[key];
    if (e is! Map<String, Object?>) bad('$key mancante');
    final host = e['host'];
    final port = e['port'];
    final security = e['security'];
    if (host is! String || !isValidHost(host.trim().toLowerCase())) bad('$key.host non valido');
    if (port is! int || port < 1 || port > 65535) bad('$key.port non valida');
    final sec = switch (security) {
      'tls' => ConnectionSecurity.tls,
      'starttls' => ConnectionSecurity.starttls,
      _ => bad('$key.security deve essere "tls" o "starttls"'),
    };
    return ServerEndpoint(host.trim().toLowerCase(), port, sec);
  }

  final username = raw['username'];
  if (username != null && (username is! String || username.trim().isEmpty || username.length > 320)) {
    bad('username non valido');
  }
  final auth = switch (raw['auth']) {
    null || 'password' => AuthKind.password,
    'appPassword' => AuthKind.appPassword,
    'bridge' => AuthKind.bridge,
    'oauth2' => AuthKind.oauth2,
    _ => bad('auth non valido'),
  };
  final id = raw['id'];
  return ProviderConfig(
    id: id is String && id.isNotEmpty && id.length <= 80 ? id : 'manual',
    displayName: 'Configurazione manuale',
    imap: endpoint('imap'),
    smtp: endpoint('smtp'),
    username: (username as String?)?.trim() ?? email.trim().toLowerCase(),
    auth: auth,
    source: ConfigSource.guess,
  );
}

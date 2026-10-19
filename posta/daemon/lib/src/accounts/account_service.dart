import 'dart:async';
import 'dart:math';

import '../db/mail_store.dart';
import '../secrets/secret_store.dart';
import '../transport/mail_transport.dart';
import 'autoconfig.dart';
import 'oauth_google.dart';
import 'provider_config.dart';

/// Perché un'operazione sugli account è fallita. Ogni motivo corrisponde a
/// un messaggio preciso nella UI.
enum AccountErrorReason {
  invalidInput,
  duplicate,
  notFound,
  oauthUnsupported,
  authFailed,

  /// Il provider vuole la password per le app (Gmail): la UI spiega dove
  /// crearla e dove incollarla.
  appPasswordRequired,

  /// L'accesso con Google non vale più (revocato, password dell'account
  /// cambiata): serve rifarlo dal browser. Nessun nuovo tentativo automatico.
  oauthReauth,

  /// Nella pagina di Google l'accesso è stato negato o la spunta sulla posta
  /// tolta, oppure l'account Google scelto non è quello dell'indirizzo.
  oauthDenied,
  untrustedCertificate,
  unreachable,
  keyringLocked,
  keyringUnavailable,
  storage,
}

class AccountException implements Exception {
  AccountException(this.reason, this.message, {this.certificateSha256});

  final AccountErrorReason reason;
  final String message;

  /// Per [AccountErrorReason.untrustedCertificate]: impronta da mostrare
  /// all'utente, che può approvarla e riprovare.
  final String? certificateSha256;

  @override
  String toString() => 'AccountException(${reason.name}): $message';
}

/// Vista pubblica di un account: non contiene MAI la password.
class AccountInfo {
  AccountInfo.fromRecord(AccountRecord r)
      : id = r.id!,
        name = r.name,
        email = r.email,
        provider = r.provider,
        imap = ServerEndpoint(r.imapHost, r.imapPort, _security(r.imapSecurity)),
        smtp = ServerEndpoint(r.smtpHost, r.smtpPort, _security(r.smtpSecurity)),
        username = r.loginName,
        trustedCertSha256 = r.trustedCertSha256;

  final int id;
  final String name;
  final String email;
  final String provider;
  final ServerEndpoint imap;
  final ServerEndpoint smtp;
  final String username;
  final String? trustedCertSha256;

  static ConnectionSecurity _security(String s) =>
      s == 'starttls' ? ConnectionSecurity.starttls : ConnectionSecurity.tls;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'provider': provider,
        'imap': imap.toJson(),
        'smtp': smtp.toJson(),
        'username': username,
        if (trustedCertSha256 != null) 'trustedCertSha256': trustedCertSha256,
      };
}

typedef TransportFactory = MailTransport Function(TransportConfig config);

final _fingerprint = RegExp(r'^[0-9a-fA-F]{64}$');

/// Aggiunta, elenco e rimozione degli account.
class AccountService {
  AccountService({
    required this.store,
    required this.secrets,
    required this.autoconfig,
    required this.transportFactory,
    this.verifyTimeout = const Duration(seconds: 60),
    GoogleOAuth? Function()? googleOAuth,
  }) : _googleOAuth = googleOAuth ?? (() => null);

  final MailStore store;
  final SecretStore secrets;
  final Autoconfig autoconfig;
  final TransportFactory transportFactory;
  final Duration verifyTimeout;
  final _random = Random.secure();

  /// Il client Google si rilegge a ogni accesso: il file con le sue
  /// credenziali può comparire dopo l'avvio del servizio.
  final GoogleOAuth? Function() _googleOAuth;

  /// Token d'accesso in memoria, per account. Durano un'ora; nel portachiavi
  /// sta solo il token di rinnovo.
  final Map<int, OAuthTokens> _accessTokens = {};

  /// Accessi con Google in corso, per numero di sessione.
  final Map<String, _OAuthSession> _oauthSessions = {};

  String _newRef() =>
      'acc-${List.generate(16, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  /// Vero se c'è il client Google e quindi si può offrire «Accedi con Google».
  bool get googleOAuthAvailable {
    try {
      return _googleOAuth() != null;
    } on OAuthException {
      return false;
    }
  }

  /// Indirizzi con un'aggiunta in corso: due richieste parallele per lo
  /// stesso indirizzo non devono creare due account.
  final Set<String> _inProgress = {};

  Future<ProviderConfig?> discover(String email, {String? providerId}) async {
    try {
      return await autoconfig.discover(email, providerId: providerId);
    } on AutoconfigException catch (e) {
      throw AccountException(AccountErrorReason.invalidInput, e.message);
    }
  }

  List<AccountInfo> list() => [for (final r in store.listAccounts()) AccountInfo.fromRecord(r)];

  /// Aggiunge un account dopo aver verificato le credenziali sul server.
  ///
  /// Ordine: verifica → password nel portachiavi → riga nel database.
  /// Se un passo fallisce si annullano i precedenti.
  Future<AccountInfo> add({
    required String email,
    required String password,
    required ProviderConfig config,
    String? name,
    String? trustedCertSha256,
  }) async {
    final address = normalizeAddress(email);
    if (address == null) {
      throw AccountException(AccountErrorReason.invalidInput, 'Indirizzo email non valido');
    }
    if (password.isEmpty) {
      throw AccountException(AccountErrorReason.invalidInput, 'La password è vuota');
    }
    if (trustedCertSha256 != null && !_fingerprint.hasMatch(trustedCertSha256)) {
      throw AccountException(AccountErrorReason.invalidInput, 'Impronta del certificato non valida');
    }
    final fingerprint = trustedCertSha256?.toLowerCase();
    if (config.auth == AuthKind.oauth2) {
      throw AccountException(AccountErrorReason.oauthUnsupported,
          'Questo provider accetta solo l\'accesso OAuth, non ancora disponibile');
    }
    if (store.accountExists(address) || !_inProgress.add(address)) {
      throw AccountException(AccountErrorReason.duplicate, 'Account già presente');
    }

    try {
      await _verify(config, password, fingerprint);

      final ref = _newRef();
      try {
        await secrets.store(ref, password, label: 'Liquid Mail – $address');
      } on SecretStoreLockedException {
        throw AccountException(AccountErrorReason.keyringLocked,
            'Il portachiavi è bloccato: sbloccalo e riprova');
      } on SecretStoreUnavailableException {
        throw AccountException(AccountErrorReason.keyringUnavailable,
            'Nessun portachiavi disponibile per salvare la password in modo sicuro');
      }

      final int id;
      try {
        id = store.addAccount(AccountRecord(
          name: (name == null || name.trim().isEmpty) ? address : name.trim(),
          email: address,
          provider: config.id,
          imapHost: config.imap.host,
          imapPort: config.imap.port,
          smtpHost: config.smtp.host,
          smtpPort: config.smtp.port,
          authMethod: config.auth == AuthKind.bridge ? 'bridge' : 'password',
          secretRef: ref,
          username: config.username == address ? null : config.username,
          imapSecurity: config.imap.security.name,
          smtpSecurity: config.smtp.security.name,
          trustedCertSha256: fingerprint,
        ));
      } catch (_) {
        // Rollback: nessuna password orfana nel portachiavi.
        try {
          await secrets.delete(ref);
        } catch (_) {}
        throw AccountException(AccountErrorReason.storage, 'Salvataggio dell\'account non riuscito');
      }
      return AccountInfo.fromRecord(store.getAccount(id)!);
    } finally {
      _inProgress.remove(address);
    }
  }

  /// Rimuove account e password. Se il portachiavi è bloccato o assente
  /// l'account resta: rimuovere solo la riga lascerebbe la password
  /// dimenticata nel portachiavi.
  Future<void> remove(int id) async {
    final record = store.getAccount(id);
    if (record == null) throw AccountException(AccountErrorReason.notFound, 'Account inesistente');
    final ref = record.secretRef;
    if (ref != null) {
      try {
        await secrets.delete(ref);
      } on SecretStoreLockedException {
        throw AccountException(AccountErrorReason.keyringLocked,
            'Il portachiavi è bloccato: sbloccalo per rimuovere l\'account');
      } on SecretStoreUnavailableException {
        throw AccountException(AccountErrorReason.keyringUnavailable,
            'Portachiavi non disponibile: impossibile cancellare la password');
      }
    }
    store.deleteAccount(id);
  }

  /// Configurazione di connessione completa, password compresa: IMAP per la
  /// sync, SMTP ([smtp] vero) per l'invio. Stesso utente e stessa password.
  /// Null se la password non è più nel portachiavi: la UI deve chiederla.
  Future<TransportConfig?> transportConfigFor(int id, {bool smtp = false}) async {
    final r = store.getAccount(id);
    if (r == null) throw AccountException(AccountErrorReason.notFound, 'Account inesistente');
    final ref = r.secretRef;
    if (ref == null) return null;
    final String? password;
    try {
      password = await secrets.lookup(ref);
    } on SecretStoreLockedException {
      throw AccountException(AccountErrorReason.keyringLocked, 'Il portachiavi è bloccato');
    } on SecretStoreUnavailableException {
      throw AccountException(AccountErrorReason.keyringUnavailable, 'Portachiavi non disponibile');
    }
    if (password == null) return null;
    final info = AccountInfo.fromRecord(r);
    final server = smtp ? info.smtp : info.imap;
    final accessToken = r.authMethod == 'oauth2' ? await _accessToken(id, password) : null;
    return TransportConfig(
      host: server.host,
      port: server.port,
      security: server.security,
      username: info.username,
      password: accessToken == null ? password : '',
      accessToken: accessToken,
      trustedCertSha256: info.trustedCertSha256,
    );
  }

  bool isOAuth(int id) => store.getAccount(id)?.authMethod == 'oauth2';

  /// Dimentica il token d'accesso: il prossimo [transportConfigFor] ne
  /// chiede uno nuovo a Google. Serve quando il server lo rifiuta prima
  /// della scadenza (revocato, o orologio del computer sbagliato).
  void forgetAccessToken(int id) => _accessTokens.remove(id);

  Future<String> _accessToken(int id, String refreshToken) async {
    final cached = _accessTokens[id];
    if (cached != null && cached.validFor(const Duration(minutes: 5))) return cached.accessToken;
    final oauth = _oauthClient();
    try {
      final t = await oauth.refresh(refreshToken);
      _accessTokens[id] = t;
      return t.accessToken;
    } on OAuthException catch (e) {
      throw switch (e.kind) {
        OAuthErrorKind.invalidGrant => AccountException(AccountErrorReason.oauthReauth, e.message),
        OAuthErrorKind.network => AccountException(AccountErrorReason.unreachable, e.message),
        _ => AccountException(AccountErrorReason.unreachable, e.message),
      };
    }
  }

  GoogleOAuth _oauthClient() {
    final GoogleOAuth? oauth;
    try {
      oauth = _googleOAuth();
    } on OAuthException catch (e) {
      throw AccountException(AccountErrorReason.oauthUnsupported, e.message);
    }
    if (oauth == null) {
      throw AccountException(AccountErrorReason.oauthUnsupported,
          'Accesso con Google non configurato su questo computer');
    }
    return oauth;
  }

  /// Primo passo di «Accedi con Google»: prepara la pagina di Google da aprire
  /// nel browser. Vale sia per un account nuovo sia per uno che c'è già (che
  /// passa così dalla password per le app a Google, o rientra dopo una
  /// revoca).
  Future<({String session, Uri url})> oauthBegin(String email) async {
    final address = normalizeAddress(email);
    if (address == null) {
      throw AccountException(AccountErrorReason.invalidInput, 'Indirizzo email non valido');
    }
    final config = await discover(address);
    if (config == null || config.id != 'gmail') {
      throw AccountException(AccountErrorReason.oauthUnsupported,
          'L\'accesso con il browser per ora c\'è solo per Gmail');
    }
    final oauth = _oauthClient();
    // Un solo accesso alla volta per indirizzo: il vecchio si annulla.
    for (final e in _oauthSessions.entries.where((e) => e.value.address == address).toList()) {
      _oauthSessions.remove(e.key);
      await e.value.login.cancel();
    }
    final login = await oauth.begin(loginHint: address);
    final session = _newRef();
    _oauthSessions[session] = _OAuthSession(address, config, login);
    // Se nessuno chiede mai l'esito, la sessione si toglie da sola.
    unawaited(login.result.then((_) {}, onError: (_) {}).whenComplete(() {
      Timer(const Duration(minutes: 2), () => _oauthSessions.remove(session));
    }));
    return (session: session, url: login.url);
  }

  Future<void> oauthCancel(String session) async {
    final s = _oauthSessions.remove(session);
    await s?.login.cancel();
  }

  /// Secondo passo: aspetta che l'utente finisca nel browser, verifica
  /// l'accesso IMAP con il token, salva il token di rinnovo nel portachiavi.
  /// Restituisce l'account e se esisteva già (in quel caso la
  /// sincronizzazione va riavviata con il nuovo accesso).
  Future<({AccountInfo info, bool existed})> oauthFinish(String session, {String? name}) async {
    final s = _oauthSessions[session];
    if (s == null) {
      throw AccountException(AccountErrorReason.notFound, 'Accesso con Google scaduto: riprova');
    }
    final OAuthTokens tokens;
    try {
      tokens = await s.login.result;
    } on OAuthException catch (e) {
      throw switch (e.kind) {
        OAuthErrorKind.denied || OAuthErrorKind.scopeMissing || OAuthErrorKind.cancelled =>
          AccountException(AccountErrorReason.oauthDenied, e.message),
        OAuthErrorKind.invalidGrant => AccountException(AccountErrorReason.oauthReauth, e.message),
        _ => AccountException(AccountErrorReason.unreachable, e.message),
      };
    } finally {
      _oauthSessions.remove(session);
    }
    final address = s.address;
    if (tokens.email != null && tokens.email != address) {
      throw AccountException(AccountErrorReason.oauthDenied,
          'Nella pagina di Google hai scelto ${tokens.email}, non $address: riprova scegliendo $address');
    }
    final refresh = tokens.refreshToken!;
    final existingId = store.accountIdByEmail(address);
    if (existingId == null && !_inProgress.add(address)) {
      throw AccountException(AccountErrorReason.duplicate, 'Account già presente');
    }
    try {
      await _verify(s.config, '', null, accessToken: tokens.accessToken);
      final ref = _newRef();
      try {
        await secrets.store(ref, refresh, label: 'Liquid Mail – Google – $address');
      } on SecretStoreLockedException {
        throw AccountException(AccountErrorReason.keyringLocked,
            'Il portachiavi è bloccato: sbloccalo e riprova');
      } on SecretStoreUnavailableException {
        throw AccountException(AccountErrorReason.keyringUnavailable,
            'Nessun portachiavi disponibile per salvare l\'accesso in modo sicuro');
      }
      try {
        final int id;
        if (existingId != null) {
          final old = store.getAccount(existingId)!.secretRef;
          store.setAccountAuth(existingId, authMethod: 'oauth2', secretRef: ref);
          id = existingId;
          // La password per le app di prima non serve più.
          if (old != null && old != ref) {
            try {
              await secrets.delete(old);
            } catch (_) {}
          }
        } else {
          id = store.addAccount(AccountRecord(
            name: (name == null || name.trim().isEmpty) ? address : name.trim(),
            email: address,
            provider: s.config.id,
            imapHost: s.config.imap.host,
            imapPort: s.config.imap.port,
            smtpHost: s.config.smtp.host,
            smtpPort: s.config.smtp.port,
            authMethod: 'oauth2',
            secretRef: ref,
            username: s.config.username == address ? null : s.config.username,
            imapSecurity: s.config.imap.security.name,
            smtpSecurity: s.config.smtp.security.name,
          ));
        }
        _accessTokens[id] = tokens;
        return (info: AccountInfo.fromRecord(store.getAccount(id)!), existed: existingId != null);
      } catch (_) {
        try {
          await secrets.delete(ref);
        } catch (_) {}
        throw AccountException(AccountErrorReason.storage, 'Salvataggio dell\'account non riuscito');
      }
    } finally {
      if (existingId == null) _inProgress.remove(address);
    }
  }

  Future<void> _verify(ProviderConfig config, String password, String? fingerprint,
      {String? accessToken}) async {
    final transport = transportFactory(TransportConfig(
      host: config.imap.host,
      port: config.imap.port,
      security: config.imap.security,
      username: config.username,
      password: password,
      accessToken: accessToken,
      trustedCertSha256: fingerprint,
    ));
    try {
      await transport.connect().timeout(verifyTimeout);
      final folders = await transport.listFolders().timeout(verifyTimeout);
      if (!folders.any((f) => f.role == 'inbox')) {
        throw AccountException(AccountErrorReason.unreachable,
            'Il server non ha una cartella Posta in arrivo: impostazioni errate?');
      }
    } on MailTransportException catch (e) {
      throw switch (e.kind) {
        TransportErrorKind.authFailed => AccountException(
            AccountErrorReason.authFailed, 'Nome utente o password non accettati dal server'),
        TransportErrorKind.appPasswordRequired => AccountException(
            AccountErrorReason.appPasswordRequired,
            'Il server vuole una password per le app, non quella dell\'account'),
        TransportErrorKind.tlsUntrusted => AccountException(
            AccountErrorReason.untrustedCertificate,
            e.certificateSha256 == null
                ? 'Connessione sicura non possibile con questo server'
                : 'Il certificato del server non è riconosciuto: verifica l\'impronta',
            certificateSha256: e.certificateSha256),
        _ => AccountException(AccountErrorReason.unreachable, 'Server non raggiungibile: ${e.message}'),
      };
    } on TimeoutException {
      throw AccountException(AccountErrorReason.unreachable, 'Il server non ha risposto in tempo');
    } finally {
      await transport.disconnect();
    }
  }
}

class _OAuthSession {
  _OAuthSession(this.address, this.config, this.login);
  final String address;
  final ProviderConfig config;
  final OAuthLogin login;
}

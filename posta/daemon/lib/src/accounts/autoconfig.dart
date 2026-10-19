import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../db/mail_store.dart' show normalizeAddress;
import '../transport/mail_transport.dart';
import 'provider_config.dart';

class AutoconfigException implements Exception {
  AutoconfigException(this.message);
  final String message;
  @override
  String toString() => 'AutoconfigException: $message';
}

/// Scarica un documento di autoconfigurazione con regole prudenti:
/// solo HTTPS (anche dopo i redirect), al massimo 3 redirect, dimensione
/// e tempo limitati. Restituisce null per 404 o qualunque errore: un
/// autoconfig mancante non è un errore, si passa alla fonte successiva.
class AutoconfigFetcher {
  AutoconfigFetcher({
    this.securityContext,
    this.timeout = const Duration(seconds: 8),
    this.maxBytes = 64 * 1024,
    this.maxRedirects = 3,
  });

  final SecurityContext? securityContext;
  final Duration timeout;
  final int maxBytes;
  final int maxRedirects;

  Future<String?> fetch(Uri uri) async {
    final client = HttpClient(context: securityContext)
      ..connectionTimeout = timeout
      ..userAgent = 'LiquidMail-Autoconfig';
    try {
      return await _fetch(client, uri, 0).timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> _fetch(HttpClient client, Uri uri, int redirects) async {
    if (uri.scheme != 'https') return null;
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    if (response.isRedirect) {
      await response.drain<void>();
      if (redirects >= maxRedirects) return null;
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (location == null) return null;
      return _fetch(client, uri.resolve(location), redirects + 1);
    }
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final declared = response.contentLength;
    if (declared > maxBytes) {
      await response.detachSocket().then((s) => s.destroy());
      return null;
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      // Il limite vale anche senza Content-Length (risposta chunked infinita).
      if (bytes.length > maxBytes) return null;
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }
}

/// Verifica raggiungibilità di host:porta senza inviare dati (per le ipotesi).
typedef PortProbe = Future<bool> Function(String host, int port);

Future<bool> tcpProbe(String host, int port) async {
  try {
    final s = await Socket.connect(host, port, timeout: const Duration(seconds: 3));
    s.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

final _hostname = RegExp(
    r'^(?=.{1,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$');

/// Nome host DNS o indirizzo IP valido (usato anche per validare l'input UI).
bool isValidHost(String h) =>
    _hostname.hasMatch(h) || InternetAddress.tryParse(h) != null;

/// Interpreta un documento "clientConfig" (formato Thunderbird).
/// Restituisce null se non contiene un server IMAP e uno SMTP utilizzabili:
/// connessioni senza cifratura vengono scartate, non "provate".
ProviderConfig? parseAutoconfigXml(String text, String email, ConfigSource source) {
  // Niente DTD: nessun formato di autoconfig legittimo ne ha bisogno, ed
  // entità ricorsive ("billion laughs") o esterne sono un vettore d'attacco.
  final upper = text.toUpperCase();
  if (upper.contains('<!DOCTYPE') || upper.contains('<!ENTITY')) return null;

  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text);
  } on XmlException {
    return null;
  }
  final provider = doc.findAllElements('emailProvider').firstOrNull;
  if (provider == null) return null;

  final local = email.split('@').first;
  final domain = email.split('@').last;
  String fill(String template) => template
      .replaceAll('%EMAILADDRESS%', email)
      .replaceAll('%EMAILLOCALPART%', local)
      .replaceAll('%EMAILDOMAIN%', domain);

  ({ServerEndpoint endpoint, String username, AuthKind auth})? best(
      String tag, String type) {
    final candidates = <({ServerEndpoint endpoint, String username, AuthKind auth})>[];
    for (final s in provider.findElements(tag)) {
      if (s.getAttribute('type') != type) continue;
      final host = fill(s.getElement('hostname')?.innerText.trim() ?? '').toLowerCase();
      final port = int.tryParse(s.getElement('port')?.innerText.trim() ?? '');
      final socket = s.getElement('socketType')?.innerText.trim().toUpperCase();
      final security = switch (socket) {
        'SSL' => ConnectionSecurity.tls,
        'STARTTLS' => ConnectionSecurity.starttls,
        _ => null, // "plain" o assente: mai accettato
      };
      if (security == null || port == null || port < 1 || port > 65535) continue;
      if (!isValidHost(host)) continue;
      final auths = s.findElements('authentication').map((e) => e.innerText.trim()).toList();
      final AuthKind auth;
      if (auths.any((a) => a.startsWith('password-'))) {
        auth = AuthKind.password;
      } else if (auths.contains('OAuth2')) {
        auth = AuthKind.oauth2;
      } else {
        continue;
      }
      candidates.add((
        endpoint: ServerEndpoint(host, port, security),
        username: fill(s.getElement('username')?.innerText.trim() ?? '%EMAILADDRESS%'),
        auth: auth,
      ));
    }
    if (candidates.isEmpty) return null;
    // TLS diretto prima di STARTTLS (RFC 8314); a parità, l'ordine del file.
    candidates.sort((a, b) => a.endpoint.security.index.compareTo(b.endpoint.security.index));
    return candidates.first;
  }

  final imap = best('incomingServer', 'imap');
  final smtp = best('outgoingServer', 'smtp');
  if (imap == null || smtp == null) return null;

  final name = provider.getElement('displayShortName')?.innerText.trim() ??
      provider.getElement('displayName')?.innerText.trim() ??
      domain;
  return ProviderConfig(
    id: '${source.name}:$domain',
    displayName: name.length > 60 ? name.substring(0, 60) : name,
    imap: imap.endpoint,
    smtp: smtp.endpoint,
    username: imap.username,
    auth: imap.auth == AuthKind.oauth2 ? AuthKind.oauth2 : AuthKind.password,
    source: source,
  );
}

/// Trova la configurazione di un indirizzo email.
class Autoconfig {
  Autoconfig({
    AutoconfigFetcher? fetcher,
    this.ispdbBase = 'https://autoconfig.thunderbird.net/v1.1/',
    List<Uri> Function(String domain, String email)? domainUrls,
    this.probe = tcpProbe,
  })  : fetcher = fetcher ?? AutoconfigFetcher(),
        domainUrls = domainUrls ?? _defaultDomainUrls;

  final AutoconfigFetcher fetcher;
  final String ispdbBase;
  final List<Uri> Function(String domain, String email) domainUrls;
  final PortProbe probe;

  static List<Uri> _defaultDomainUrls(String domain, String email) => [
        Uri.https('autoconfig.$domain', '/mail/config-v1.1.xml', {'emailaddress': email}),
        Uri.https(domain, '/.well-known/autoconfig/mail/config-v1.1.xml'),
      ];

  /// [providerId] forza un preset (dominio personale ospitato da un provider
  /// noto). Restituisce null se nessuna fonte dà un risultato utilizzabile.
  Future<ProviderConfig?> discover(String rawEmail, {String? providerId}) async {
    final email = normalizeAddress(rawEmail);
    if (email == null) throw AutoconfigException('Indirizzo email non valido');
    final domain = email.split('@').last;

    if (providerId != null) {
      final forced = presetById(email, providerId);
      if (forced == null) throw AutoconfigException('Provider sconosciuto: $providerId');
      return forced;
    }

    final preset = presetForDomain(email, domain);
    if (preset != null) return preset;

    // Domini internazionalizzati (es. città.it) richiedono la conversione
    // punycode per DNS e URL: non ancora gestita, si passa all'inserimento
    // manuale invece di interrogare indirizzi sbagliati.
    if (domain.codeUnits.any((c) => c > 127)) return null;

    for (final uri in domainUrls(domain, email)) {
      final text = await fetcher.fetch(uri);
      final config = text == null ? null : parseAutoconfigXml(text, email, ConfigSource.domain);
      if (config != null) return config;
    }

    final ispdb = await fetcher.fetch(Uri.parse('$ispdbBase$domain'));
    final fromDb = ispdb == null ? null : parseAutoconfigXml(ispdb, email, ConfigSource.ispdb);
    if (fromDb != null) return fromDb;

    return _guess(email, domain);
  }

  Future<ProviderConfig?> _guess(String email, String domain) async {
    Future<ServerEndpoint?> first(List<String> hosts, List<(int, ConnectionSecurity)> ports) async {
      for (final h in hosts) {
        for (final (port, sec) in ports) {
          if (await probe(h, port)) return ServerEndpoint(h, port, sec);
        }
      }
      return null;
    }

    final imap = await first(['imap.$domain', 'mail.$domain', domain],
        [(993, ConnectionSecurity.tls), (143, ConnectionSecurity.starttls)]);
    if (imap == null) return null;
    final smtp = await first(['smtp.$domain', 'mail.$domain', domain],
        [(465, ConnectionSecurity.tls), (587, ConnectionSecurity.starttls)]);
    if (smtp == null) return null;
    return ProviderConfig(
      id: 'guess:$domain',
      displayName: domain,
      imap: imap,
      smtp: smtp,
      username: email,
      auth: AuthKind.password,
      source: ConfigSource.guess,
      helpText: 'Impostazioni ipotizzate: verranno confermate dal primo accesso.',
    );
  }
}

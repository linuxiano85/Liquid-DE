import '../transport/mail_transport.dart';

/// Come l'utente si autentica. Determina cosa la UI chiede e spiega.
enum AuthKind {
  /// Password normale dell'account.
  password,

  /// Password dedicata alla posta, generata dal provider (Gmail, Fastmail,
  /// Infomaniak): quella dell'account non funziona.
  appPassword,

  /// Solo OAuth2 (Outlook): non ancora supportato, arriverà in seguito.
  oauth2,

  /// Credenziali generate da Proton Mail Bridge.
  bridge,
}

/// Da dove arriva una configurazione: la UI lo mostra, perché un'ipotesi
/// ha un grado di fiducia diverso da un preset verificato.
enum ConfigSource { preset, domain, ispdb, guess }

class ServerEndpoint {
  const ServerEndpoint(this.host, this.port, this.security);

  final String host;
  final int port;
  final ConnectionSecurity security;

  Map<String, Object?> toJson() =>
      {'host': host, 'port': port, 'security': security.name};

  @override
  bool operator ==(Object other) =>
      other is ServerEndpoint &&
      other.host == host &&
      other.port == port &&
      other.security == security;

  @override
  int get hashCode => Object.hash(host, port, security);

  @override
  String toString() => '$host:$port/${security.name}';
}

class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.displayName,
    required this.imap,
    required this.smtp,
    required this.username,
    required this.auth,
    required this.source,
    this.helpText,
  });

  final String id;
  final String displayName;
  final ServerEndpoint imap;
  final ServerEndpoint smtp;

  /// Nome utente già risolto per l'indirizzo richiesto.
  final String username;
  final AuthKind auth;
  final ConfigSource source;

  /// Spiegazione per l'utente, in italiano (es. dove generare la password).
  final String? helpText;

  Map<String, Object?> toJson() => {
        'id': id,
        'displayName': displayName,
        'imap': imap.toJson(),
        'smtp': smtp.toJson(),
        'username': username,
        'auth': auth.name,
        'source': source.name,
        if (helpText != null) 'helpText': helpText,
      };
}

/// Preset verificati sulle pagine ufficiali dei provider (ottobre 2026).
/// Ogni voce indica la fonte: aggiornarla se il provider cambia server.
class _Preset {
  const _Preset({
    required this.id,
    required this.displayName,
    required this.domains,
    required this.imap,
    required this.smtp,
    required this.auth,
    this.helpText,
  });

  final String id;
  final String displayName;
  final List<String> domains;
  final ServerEndpoint imap;
  final ServerEndpoint smtp;
  final AuthKind auth;
  final String? helpText;

  ProviderConfig resolve(String email) => ProviderConfig(
        id: id,
        displayName: displayName,
        imap: imap,
        smtp: smtp,
        // Tutti i preset usano l'indirizzo completo come nome utente.
        username: email,
        auth: auth,
        source: ConfigSource.preset,
        helpText: helpText,
      );
}

const _tls = ConnectionSecurity.tls;
const _starttls = ConnectionSecurity.starttls;

const _presets = <_Preset>[
  // Fonte: ISPDB Thunderbird (gmail.com). L'ISPDB indica solo OAuth2; finché
  // OAuth non è disponibile si usa la password per app, che Google consente
  // agli account con verifica in due passaggi.
  _Preset(
    id: 'gmail',
    displayName: 'Gmail',
    domains: ['gmail.com', 'googlemail.com'],
    imap: ServerEndpoint('imap.gmail.com', 993, _tls),
    smtp: ServerEndpoint('smtp.gmail.com', 465, _tls),
    auth: AuthKind.appPassword,
    helpText: 'Gmail richiede una password per le app: Account Google → '
        'Sicurezza → Password per le app (serve la verifica in due passaggi).',
  ),
  // Fonte: infomaniak.com/en/support/faq/2427. SMTP: 465 SSL/TLS, indicato
  // come alternativa alla 587 STARTTLS; preferiamo TLS diretto (RFC 8314).
  _Preset(
    id: 'infomaniak',
    displayName: 'Infomaniak',
    domains: ['ik.me', 'etik.com'],
    imap: ServerEndpoint('mail.infomaniak.com', 993, _tls),
    smtp: ServerEndpoint('mail.infomaniak.com', 465, _tls),
    auth: AuthKind.appPassword,
    helpText: 'Usa la password generata per la posta nel pannello Infomaniak, '
        'non quella di accesso all\'account.',
  ),
  // Fonte: fastmail.help/hc/en-us/articles/1500000278342.
  _Preset(
    id: 'fastmail',
    displayName: 'Fastmail',
    domains: ['fastmail.com', 'fastmail.fm'],
    imap: ServerEndpoint('imap.fastmail.com', 993, _tls),
    smtp: ServerEndpoint('smtp.fastmail.com', 465, _tls),
    auth: AuthKind.appPassword,
    helpText: 'Fastmail richiede una password per app: Impostazioni → '
        'Privacy e sicurezza → Password per app.',
  ),
  // Fonte: kb.mailbox.org (setup-other-e-mail-clients-manually).
  _Preset(
    id: 'mailbox-org',
    displayName: 'mailbox.org',
    domains: ['mailbox.org'],
    imap: ServerEndpoint('imap.mailbox.org', 993, _tls),
    smtp: ServerEndpoint('smtp.mailbox.org', 465, _tls),
    auth: AuthKind.password,
  ),
  // Valori predefiniti di Proton Mail Bridge (localhost, STARTTLS). L'utente
  // deve confermarli nelle impostazioni di Bridge, che può cambiarli.
  _Preset(
    id: 'proton',
    displayName: 'Proton Mail (tramite Bridge)',
    domains: ['proton.me', 'protonmail.com', 'protonmail.ch', 'pm.me'],
    imap: ServerEndpoint('127.0.0.1', 1143, _starttls),
    smtp: ServerEndpoint('127.0.0.1', 1025, _starttls),
    auth: AuthKind.bridge,
    helpText: 'Serve Proton Mail Bridge avviato. Nome utente, password, porte e '
        'certificato sono quelli mostrati da Bridge, non quelli di Proton.',
  ),
];

/// Preset per dominio dell'indirizzo (es. ik.me → Infomaniak).
ProviderConfig? presetForDomain(String email, String domain) {
  for (final p in _presets) {
    if (p.domains.contains(domain)) return p.resolve(email);
  }
  return null;
}

/// Preset scelto dall'utente per un dominio proprio
/// (es. utente@example.org ospitato su Infomaniak).
ProviderConfig? presetById(String email, String id) {
  for (final p in _presets) {
    if (p.id == id) return p.resolve(email);
  }
  return null;
}

/// Elenco per il menu "Il mio provider è…" della UI.
List<Map<String, String>> presetCatalog() =>
    [for (final p in _presets) {'id': p.id, 'displayName': p.displayName}];

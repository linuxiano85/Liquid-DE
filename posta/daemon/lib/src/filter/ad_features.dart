/// Ciò che il filtro delle pubblicità guarda di un'email. Si costruisce
/// durante la sincronizzazione, quando il messaggio è appena stato letto e
/// le intestazioni sono ancora a disposizione.
class MessageFeatures {
  MessageFeatures({
    required this.subject,
    this.fromAddress,
    this.fromName,
    this.bodyText = '',
    Map<String, String> headers = const {},
    this.providerSaysPromotion = false,
    this.trackersRemoved = 0,
  }) : headers = {for (final e in headers.entries) e.key.toLowerCase(): e.value};

  final String subject;
  final String? fromAddress;
  final String? fromName;
  final String bodyText;

  /// Intestazioni utili al filtro, con il nome in minuscolo.
  final Map<String, String> headers;

  /// Il provider l'ha già classificata come promozione (Gmail:
  /// `X-GM-RAW "category:promotions"`).
  final bool providerSaysPromotion;

  /// Pixel spia tolti dal sanificatore.
  final int trackersRemoved;

  String? get fromDomain {
    final a = fromAddress;
    if (a == null) return null;
    final at = a.lastIndexOf('@');
    return at < 0 ? null : a.substring(at + 1).toLowerCase();
  }

  bool get hasListUnsubscribe => headers.containsKey('list-unsubscribe');

  bool get isBulk {
    final p = headers['precedence']?.toLowerCase().trim();
    return p == 'bulk' || p == 'list' || p == 'junk';
  }

  /// Piattaforma di invio di massa riconosciuta dalle intestazioni, o null.
  String? get bulkPlatform {
    for (final (name, platform) in _platformHeaders) {
      if (headers.keys.any((h) => h.startsWith(name))) return platform;
    }
    final mailer = '${headers['x-mailer'] ?? ''} ${headers['feedback-id'] ?? ''}'.toLowerCase();
    for (final p in _platformNames) {
      if (mailer.contains(p)) return p;
    }
    return null;
  }

  static const _platformHeaders = [
    ('x-mc-user', 'mailchimp'),
    ('x-mailchimp', 'mailchimp'),
    ('x-sg-eid', 'sendgrid'),
    ('x-sendgrid', 'sendgrid'),
    ('x-mailgun', 'mailgun'),
    ('x-mailjet', 'mailjet'),
    ('x-klaviyo', 'klaviyo'),
    ('x-sib-id', 'brevo'),
    ('x-mkt', 'marketo'),
    ('x-sfmc', 'salesforce'),
    ('x-campaign', 'campagna'),
  ];

  static const _platformNames = [
    'mailchimp', 'sendinblue', 'brevo', 'mailjet', 'hubspot', 'klaviyo', 'salesforce',
    'exacttarget', 'acoustic', 'substack', 'mailerlite', 'activecampaign', 'constantcontact',
    'amazonses', 'sparkpost', 'mailgun', 'sendgrid',
  ];

  static final _word = RegExp(r"[\p{L}\p{N}][\p{L}\p{N}'’-]{1,29}", unicode: true);

  /// Parole e segnali dell'email, ognuno una volta sola. I prefissi tengono
  /// separati i contesti: "offerta" nell'oggetto pesa diversamente da
  /// "offerta" nel corpo.
  Set<String> tokens({int maxBodyChars = 20000, int maxTokens = 3000}) {
    final out = <String>{};
    void add(String t) {
      if (out.length < maxTokens) out.add(t);
    }

    for (final m in _word.allMatches(subject.toLowerCase())) {
      add('s:${m.group(0)}');
    }
    final domain = fromDomain;
    if (domain != null) add('fd:$domain');
    final address = fromAddress?.toLowerCase();
    if (address != null) add('fa:$address');
    if (hasListUnsubscribe) add('h:list-unsubscribe');
    if (isBulk) add('h:bulk');
    final platform = bulkPlatform;
    if (platform != null) add('h:piattaforma:$platform');
    if (trackersRemoved > 0) add('h:pixel-spia');
    if (providerSaysPromotion) add('h:promozione-del-provider');
    final body = bodyText.length > maxBodyChars ? bodyText.substring(0, maxBodyChars) : bodyText;
    for (final m in _word.allMatches(body.toLowerCase())) {
      add(m.group(0)!);
    }
    return out;
  }
}

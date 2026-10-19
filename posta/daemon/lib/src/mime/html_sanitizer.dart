import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Risultato della sanificazione, con i conteggi che la UI mostra
/// ("3 immagini remote bloccate", "1 traccia rimossa").
class SanitizedHtml {
  SanitizedHtml(this.html, {required this.remoteImagesBlocked, required this.trackersRemoved,
      required this.linksCleaned, required this.removedElements, this.deceptiveLinks = 0});

  final String html;
  final int remoteImagesBlocked;
  final int trackersRemoved;
  final int linksCleaned;

  /// Elementi pericolosi rimossi (script, iframe, form...), per diagnostica.
  final int removedElements;

  /// Link il cui testo mostra un dominio diverso da quello a cui portano
  /// ("www.poste.it" che apre un altro sito). Ognuno ha l'attributo
  /// `data-liquid-deceptive` con il dominio vero: la vista avvisa al clic.
  final int deceptiveLinks;
}

/// Sanificatore HTML a lista bianca per il corpo delle email.
///
/// Il risultato è sicuro da mostrare anche in un browser con JavaScript
/// attivo e rete libera (lo verificano i test con Chromium vero); la vista
/// del client aggiunge comunque JavaScript disattivato e rete bloccata.
///
/// Regole:
/// - solo elementi e attributi elencati; gli elementi sconosciuti si
///   "scartocciano" (resta il testo), quelli pericolosi spariscono col
///   contenuto;
/// - link solo http(s), mailto, tel; parametri di tracciamento rimossi;
/// - immagini remote bloccate (salvo [allowRemoteImages]); pixel di
///   tracciamento rimossi SEMPRE;
/// - `cid:` diventa `liquid-cid:` (risolto dalla vista con l'allegato);
/// - CSS solo inline, proprietà in lista bianca, niente url() né espressioni;
///   i blocchi `<style>` si eliminano (possono caricare risorse remote e
///   ridisegnare l'interfaccia del client).
class HtmlSanitizer {
  HtmlSanitizer({this.allowRemoteImages = false, this.maxDataUriBytes = 2 * 1024 * 1024});

  final bool allowRemoteImages;
  final int maxDataUriBytes;

  static const _allowedTags = {
    'a', 'abbr', 'address', 'article', 'aside', 'b', 'bdi', 'blockquote', 'br', 'caption', 'center',
    'cite', 'code', 'col', 'colgroup', 'dd', 'del', 'details', 'dfn', 'div', 'dl', 'dt', 'em',
    'figcaption', 'figure', 'font', 'footer', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'header', 'hr', 'i',
    'img', 'ins', 'kbd', 'li', 'main', 'mark', 'nav', 'ol', 'p', 'pre', 'q', 's', 'samp', 'section',
    'small', 'span', 'strike', 'strong', 'sub', 'summary', 'sup', 'table', 'tbody', 'td', 'tfoot',
    'th', 'thead', 'time', 'tr', 'tt', 'u', 'ul', 'var', 'wbr',
  };

  /// Eliminati CON il contenuto.
  static const _droppedTags = {
    'script', 'style', 'noscript', 'template', 'iframe', 'frame', 'frameset', 'object', 'embed',
    'applet', 'input', 'button', 'select', 'textarea', 'option', 'optgroup', 'svg', 'math', 'canvas',
    'audio', 'video', 'source', 'track', 'link', 'meta', 'base', 'title', 'head', 'xml', 'picture',
    'map', 'area', 'portal', 'dialog', 'slot', 'noembed', 'noframes', 'plaintext', 'xmp', 'listing',
    'param', 'marquee', 'blink', 'datalist', 'keygen', 'output', 'progress', 'meter',
  };

  static const _globalAttrs = {
    'align', 'valign', 'bgcolor', 'color', 'border', 'cellpadding', 'cellspacing', 'colspan',
    'rowspan', 'width', 'height', 'dir', 'lang', 'title', 'alt', 'style', 'face', 'size', 'start',
    'type', 'span', 'headers', 'scope', 'abbr', 'datetime', 'nowrap', 'reversed', 'open',
  };

  static const _cssProperties = {
    'color', 'background-color', 'font', 'font-family', 'font-size', 'font-style', 'font-weight',
    'font-variant', 'text-align', 'text-decoration', 'text-indent', 'text-transform', 'line-height',
    'letter-spacing', 'word-spacing', 'white-space', 'word-break', 'word-wrap', 'overflow-wrap',
    'vertical-align', 'margin', 'margin-top', 'margin-right', 'margin-bottom', 'margin-left',
    'padding', 'padding-top', 'padding-right', 'padding-bottom', 'padding-left', 'border',
    'border-top', 'border-right', 'border-bottom', 'border-left', 'border-color', 'border-style',
    'border-width', 'border-radius', 'border-collapse', 'border-spacing', 'width', 'height',
    'max-width', 'min-width', 'max-height', 'min-height', 'display', 'float', 'clear', 'table-layout',
    'list-style-type', 'list-style-position', 'direction', 'text-overflow',
  };

  static final _plainColor = RegExp(
      r'^(#[0-9a-fA-F]{3,8}|[a-zA-Z]{3,20}|rgba?\(\s*[\d.]+%?\s*,\s*[\d.]+%?\s*,\s*[\d.]+%?\s*(,\s*[\d.]+%?\s*)?\))(\s*!important)?$');

  static final _negative = RegExp(r'(^|[\s,(])-\s*[\d.]');
  static final _viewportUnit = RegExp(r'[\d.]\s*(vw|vh|vmin|vmax|[dsl]v[wh])\b');

  static const _displayValues = {
    'block', 'inline', 'inline-block', 'none', 'table', 'table-row', 'table-cell', 'list-item',
    'table-row-group', 'table-header-group', 'table-footer-group', 'flex', 'inline-flex',
  };

  static final _trackingParams = RegExp(
      r'^(utm_[a-z_]+|fbclid|gclid|dclid|msclkid|mc_eid|mc_cid|_hsenc|_hsmi|mkt_tok|yclid|igshid|oly_[a-z_]+|vero_[a-z_]+)$',
      caseSensitive: false);

  /// Domini noti di soli pixel di tracciamento (aggiornabile dalla fase antispam).
  static final _trackerHosts = RegExp(
      r'(^|\.)(list-manage\.com|mailtrack\.io|mandrillapp\.com|sendgrid\.net|mailchimp\.com|'
      r'hubspotlinks\.com|google-analytics\.com|mixpanel\.com|exacttarget\.com|pstmrk\.it|'
      r'mailgun\.org|sparkpostmail\.com|klclick\.com|emltrk\.com|bananatag\.com|yesware\.com)$',
      caseSensitive: false);

  int _remote = 0;
  int _trackers = 0;
  int _links = 0;
  int _removed = 0;
  int _deceptive = 0;

  SanitizedHtml sanitize(String input) {
    _remote = _trackers = _links = _removed = _deceptive = 0;
    final doc = html_parser.parse(input);
    final body = doc.body;
    final out = dom.Element.tag('div');
    // Lo stile del <body> (sfondo, font, colore) si trasferisce al contenitore:
    // il <body> non viene copiato, ma il suo aspetto sì.
    if (body != null) {
      final css = sanitizeCss(body.attributes['style'] ?? '');
      final bg = body.attributes['bgcolor'];
      final parts = [
        if (css.isNotEmpty) css,
        if (bg != null && _plainColor.hasMatch(bg.trim())) 'background-color: ${bg.trim()}',
      ];
      if (parts.isNotEmpty) out.attributes['style'] = parts.join('; ');
    }
    if (body != null) {
      for (final n in body.nodes.toList()) {
        _clean(n, out);
      }
    }
    return SanitizedHtml(out.attributes.isEmpty ? out.innerHtml : out.outerHtml,
        remoteImagesBlocked: _remote, trackersRemoved: _trackers, linksCleaned: _links,
        removedElements: _removed, deceptiveLinks: _deceptive);
  }

  /// Copia [node] ripulito dentro [parent].
  void _clean(dom.Node node, dom.Element parent) {
    if (node is dom.Text) {
      parent.append(dom.Text(node.text));
      return;
    }
    if (node is! dom.Element) return; // commenti, istruzioni: mai copiati

    final tag = (node.localName ?? '').toLowerCase();
    // Elementi con namespace (o:p di Outlook, v:shape di VML) o tag ignoti:
    // si tiene il contenuto, non l'elemento.
    if (_droppedTags.contains(tag) || node.namespaceUri == 'http://www.w3.org/2000/svg' ||
        node.namespaceUri == 'http://www.w3.org/1998/Math/MathML') {
      _removed++;
      return;
    }
    if (!_allowedTags.contains(tag)) {
      for (final c in node.nodes.toList()) {
        _clean(c, parent);
      }
      return;
    }

    if (tag == 'img') {
      final img = _cleanImage(node);
      if (img != null) parent.append(img);
      return;
    }

    final copy = dom.Element.tag(tag);
    _copyAttributes(node, copy);
    if (tag == 'a') _cleanLink(node, copy);
    parent.append(copy);
    for (final c in node.nodes.toList()) {
      _clean(c, copy);
    }
  }

  void _copyAttributes(dom.Element from, dom.Element to) {
    from.attributes.forEach((k, v) {
      final name = k.toString().toLowerCase();
      if (!_globalAttrs.contains(name)) return;
      if (name == 'style') {
        final css = sanitizeCss(v);
        if (css.isNotEmpty) to.attributes['style'] = css;
        return;
      }
      // Valori numerici o colori: niente che possa contenere un URL.
      if (v.length > 200 || v.toLowerCase().contains(':') && name != 'title' && name != 'alt' && name != 'datetime') {
        return;
      }
      to.attributes[name] = v;
    });
  }

  void _cleanLink(dom.Element from, dom.Element to) {
    final href = from.attributes['href']?.trim();
    if (href == null) return;
    final cleaned = cleanUrl(href, forLink: true);
    if (cleaned == null) return;
    if (cleaned != href) _links++;
    to.attributes['href'] = cleaned;
    to.attributes['rel'] = 'noopener noreferrer nofollow';
    final shown = _domainShownIn(from.text);
    final real = Uri.tryParse(cleaned)?.host.toLowerCase() ?? '';
    if (shown != null && real.isNotEmpty && _site(shown) != _site(real)) {
      _deceptive++;
      to.attributes['data-liquid-deceptive'] = real;
    }
  }

  static final _domainText = RegExp(
      r'^(https?://)?(([a-z0-9-]+\.)+[a-z]{2,24})(:\d+)?([/?#]\S*)?$');

  /// Dominio mostrato dal testo di un link, se il testo È un indirizzo
  /// ("www.poste.it", "https://poste.it/accedi"); null per "Clicca qui".
  static String? _domainShownIn(String text) {
    final m = _domainText.firstMatch(text.trim().toLowerCase());
    return m?.group(2);
  }

  /// Suffissi a due livelli più comuni: "banca.co.uk" è un sito, "co.uk" no.
  /// Non è la Public Suffix List intera: sbagliare qui produce al massimo un
  /// avviso in più o in meno, mai un link bloccato.
  static const _twoLevelSuffixes = {
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'com.au', 'net.au', 'org.au', 'co.nz',
    'co.jp', 'ne.jp', 'or.jp', 'com.br', 'com.mx', 'com.ar', 'com.tr', 'co.in', 'co.za',
    'com.cn', 'com.hk', 'com.sg', 'co.kr', 'com.es', 'com.pl', 'co.il',
  };

  /// Il "sito" di un host: gli ultimi due livelli (tre per co.uk e simili).
  static String _site(String host) {
    final labels = host.split('.');
    if (labels.length <= 2) return host;
    final lastTwo = labels.sublist(labels.length - 2).join('.');
    final n = _twoLevelSuffixes.contains(lastTwo) ? 3 : 2;
    return labels.sublist(labels.length - (labels.length < n ? labels.length : n)).join('.');
  }

  /// Parametri di un mailto: che il client usa. Tutti gli altri si tolgono:
  /// `attach`/`attachment` hanno fatto allegare file locali ad altri client
  /// (CVE di Thunderbird ed Evolution), e nessun uso legittimo ne ha bisogno.
  static const _mailtoParams = {'subject', 'cc', 'bcc', 'body', 'in-reply-to'};

  dom.Element? _cleanImage(dom.Element node) {
    final src = (node.attributes['src'] ?? '').trim();
    final w = int.tryParse((node.attributes['width'] ?? '').replaceAll('px', '').trim());
    final h = int.tryParse((node.attributes['height'] ?? '').replaceAll('px', '').trim());
    final style = (node.attributes['style'] ?? '').toLowerCase().replaceAll(' ', '');
    final lower = src.toLowerCase();

    final img = dom.Element.tag('img');
    _copyAttributes(node, img);

    if (lower.startsWith('cid:')) {
      img.attributes['src'] = 'liquid-cid:${src.substring(4)}';
      return img;
    }
    if (RegExp(r'^data:image/(png|jpeg|jpg|gif|webp);base64,[a-z0-9+/=\s]*$', caseSensitive: false).hasMatch(src)) {
      if (src.length > maxDataUriBytes * 4 ~/ 3 + 64) {
        _removed++;
        return null;
      }
      img.attributes['src'] = src.replaceAll(RegExp(r'\s'), '');
      return img;
    }
    final url = cleanUrl(src, forLink: false);
    if (url == null) {
      _removed++;
      return null;
    }
    final host = Uri.tryParse(url)?.host ?? '';
    final tiny = (w != null && w <= 2) || (h != null && h <= 2);
    final hidden = style.contains('display:none') || style.contains('visibility:hidden') ||
        style.contains('width:1px') || style.contains('height:1px') || style.contains('width:0') ||
        style.contains('height:0');
    if (tiny || hidden || _trackerHosts.hasMatch(host)) {
      _trackers++;
      return null; // mai caricato, nemmeno con immagini remote consentite
    }
    if (allowRemoteImages) {
      img.attributes['src'] = url;
    } else {
      _remote++;
      img.attributes['data-liquid-remote-src'] = url;
    }
    return img;
  }

  /// URL ammesso e ripulito, o null. I link accettano http(s), mailto, tel;
  /// le immagini solo http(s).
  String? cleanUrl(String raw, {required bool forLink}) {
    // Spazi, a capo e caratteri di controllo dentro lo schema servono a
    // ingannare i filtri ("java\nscript:"): si tolgono prima di decidere.
    final compact = raw.replaceAll(RegExp(r'[\u0000- \u007f-\u009f]'), '');
    if (compact.isEmpty || compact.length > 4096) return null;
    final Uri uri;
    try {
      uri = Uri.parse(compact);
    } on FormatException {
      return null;
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'http' || scheme == 'https') {
      if (uri.host.isEmpty) return null;
      if (!uri.hasQuery) return uri.toString();
      final kept = <String>[];
      var removed = false;
      for (final pair in uri.query.split('&')) {
        final key = pair.split('=').first;
        if (_trackingParams.hasMatch(Uri.decodeQueryComponent(key, encoding: const _Lenient()))) {
          removed = true;
        } else if (pair.isNotEmpty) {
          kept.add(pair);
        }
      }
      if (!removed) return uri.toString();
      // Ricostruzione esplicita: query senza i parametri di tracciamento,
      // frammento (#sezione) preservato e sempre in fondo.
      return Uri(
        scheme: uri.scheme,
        userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: uri.path,
        query: kept.isEmpty ? null : kept.join('&'),
        fragment: uri.hasFragment ? uri.fragment : null,
      ).toString();
    }
    if (forLink && scheme == 'tel') return uri.toString();
    if (forLink && scheme == 'mailto') {
      if (!uri.hasQuery) return uri.toString();
      final kept = [
        for (final pair in uri.query.split('&'))
          if (_mailtoParams.contains(Uri.decodeQueryComponent(pair.split('=').first,
              encoding: const _Lenient()).toLowerCase()))
            pair,
      ];
      return 'mailto:${uri.path}${kept.isEmpty ? '' : '?${kept.join('&')}'}';
    }
    return null;
  }

  /// CSS inline: solo proprietà in lista bianca e valori senza costrutti
  /// che caricano risorse o eseguono codice.
  static String sanitizeCss(String css) {
    final out = <String>[];
    for (final decl in css.split(';')) {
      final colon = decl.indexOf(':');
      if (colon <= 0) continue;
      final prop = decl.substring(0, colon).trim().toLowerCase();
      var value = decl.substring(colon + 1).trim();
      if (value.isEmpty || value.length > 200) continue;
      // "background: #2e7d32" è il modo più comune di colorare i pulsanti
      // nelle newsletter: senza, il testo bianco finiva su sfondo bianco.
      // Si accetta solo quando è un semplice colore, convertito in
      // background-color; immagini e gradienti restano esclusi.
      if (prop == 'background') {
        if (!_plainColor.hasMatch(value.trim())) continue;
        out.add('background-color: ${value.trim()}');
        continue;
      }
      if (!_cssProperties.contains(prop)) continue;
      final lower = value.toLowerCase();
      if (RegExp(r'url\s*\(|expression|javascript|vbscript|@import|behavior|binding|\\|/\*|<|>|&#|image-set|image\s*\(|element\s*\(|attr\s*\(|var\s*\(|env\s*\(')
          .hasMatch(lower)) {
        continue;
      }
      // Margini e rientri negativi spostano il testo sopra altro testo o
      // fuori dalla vista (testo nascosto per ingannare filtri e lettori);
      // le unità della finestra (vw, vh) misurano la finestra del client,
      // non l'email. Le newsletter vere non ne hanno bisogno.
      if ((prop.startsWith('margin') || prop == 'text-indent') && _negative.hasMatch(lower)) continue;
      if (_viewportUnit.hasMatch(lower)) continue;
      if (prop == 'display' && !_displayValues.contains(lower.replaceAll('!important', '').trim())) continue;
      value = value.replaceAll(RegExp(r'\s+'), ' ');
      out.add('$prop: $value');
    }
    return out.join('; ');
  }
}

/// Decodifica tollerante per i nomi dei parametri: un "%ZZ" non deve
/// impedire di riconoscere (e togliere) un parametro di tracciamento.
class _Lenient extends Encoding {
  const _Lenient();
  @override
  String get name => 'lenient';
  @override
  Converter<List<int>, String> get decoder => const Utf8Decoder(allowMalformed: true);
  @override
  Converter<String, List<int>> get encoder => const Utf8Encoder();
}

import 'dart:convert';
import 'dart:io';

/// WebDAV — il motore che parla coi servizi di archiviazione in rete.
///
/// ── Perché WebDAV e non le API di ognuno ───────────────────────────────────
///
/// Perché è la sola cosa che kDrive di Infomaniak, Nextcloud, ownCloud e mezza
/// dozzina d'altri parlano **tutti**, e perché non chiede niente a nessuno: né
/// un programma da installare, né una chiave dell'applicazione da registrare
/// sul sito del fornitore. Un indirizzo, un nome e una password, e si può già
/// verificare che l'accesso funzioni.
///
/// La misura che ha deciso questa strada, fatta il 25 agosto 2026 su questa
/// macchina: `rclone` **non è installato**, e gvfs **non ha il backend
/// WebDAV** (in `/usr/share/gvfs/mounts` non c'è nessun `dav.mount`). Quindi
/// oggi, qui, l'unico modo di parlare con kDrive è parlarci noi.
///
/// ── Cosa questo motore NON fa, e va detto ─────────────────────────────────
///
/// **Non monta una cartella nella home.** Per quello serve `rclone mount` o il
/// backend di gvfs, e nessuno dei due c'è. Chi lo vuole se lo installa, e
/// allora si aggiunge — ma finché non c'è, la sezione lo dice invece di
/// mostrare una cartella che non esiste.
///
/// Ed è anche l'occasione per dire la trappola, che vale il giorno che si farà:
/// una cartella montata che **perde la rete blocca ogni programma che la
/// tocca**, comprese tutte le finestre «Apri file», che si piantano insieme. È
/// il motivo per cui GNOME non mette Drive nella home ma sotto
/// `/run/user/1000/gvfs`.
class WebDav {
  const WebDav({this.chiedi = _chiediVero});

  /// La richiesta HTTP. Si può sostituire nelle prove: una prova che ha
  /// bisogno di internet è una prova che un giorno fallisce per motivi suoi e
  /// smette di essere creduta.
  final Future<RispostaDav> Function(
    String metodo,
    String url,
    String utente,
    String password,
    String? corpo,
    Map<String, String> intestazioni,
  ) chiedi;

  // ── L'indirizzo ────────────────────────────────────────────────────────

  /// L'indirizzo di kDrive a partire dal numero dell'archivio.
  ///
  /// Infomaniak dà a ogni kDrive un numero — si legge nell'indirizzo del loro
  /// sito — e il server WebDAV è `https://<numero>.connect.kdrive.infomaniak.com`.
  /// Chiedere «l'indirizzo del server» a chi non sa cos'è un server è il modo
  /// di non farsi rispondere; chiedere un numero che sta scritto sullo schermo
  /// è un'altra cosa.
  static String? kdrive(String numero) {
    final n = numero.trim();
    if (!RegExp(r'^[0-9]{1,12}$').hasMatch(n)) return null;
    return 'https://$n.connect.kdrive.infomaniak.com';
  }

  /// L'indirizzo del server kDrive **senza numero**.
  ///
  /// Misurato il 25 agosto 2026, con curl e senza credenziali:
  /// `https://connect.kdrive.infomaniak.com/` risponde a un PROPFIND con
  /// `401` e `Www-Authenticate: Basic realm="kdrive/dav"` — cioè è un server
  /// WebDAV vero, che chiede soltanto di farsi riconoscere. Un numero
  /// inventato (`https://999999.connect.kdrive.infomaniak.com/`) risponde
  /// invece `404`.
  ///
  /// Vuol dire che **il numero non va chiesto a nessuno**: si entra dalla
  /// radice con l'email e la password, e quali kDrive ci sono lo dice il
  /// server. Chiedere all'utente un numero che il computer può sapere da sé è
  /// il modo di far fallire l'accesso a chi quel numero non l'ha mai visto —
  /// ed è esattamente quello che è successo qui il 25 agosto: «il mio account
  /// chiede solo email e password e non un codice».
  static const String kdriveRadice = 'https://connect.kdrive.infomaniak.com';

  /// I kDrive che quell'account può aprire.
  ///
  /// Un PROPFIND di profondità 1 sulla radice: la risposta contiene una voce
  /// per la radice stessa e una per ogni archivio. Si scartano le prime e
  /// restano i dischi, col loro nome scritto per esteso quando il server lo
  /// manda.
  Future<ElencoKdrive> kdriveDi(String utente, String password) async {
    final r = await chiedi('PROPFIND', '$kdriveRadice/', utente, password,
        _propfindNomi,
        {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'});
    if (r.codice != 207 && r.codice != 200) {
      return ElencoKdrive(errore: _percheNo(r, kdrive: true));
    }
    return ElencoKdrive(dischi: _dischi(r.corpo));
  }

  /// Le voci di una risposta `multistatus`, tradotte in kDrive.
  static List<Kdrive> _dischi(String? xml) {
    if (xml == null) return const [];
    final fuori = <Kdrive>[];
    final visti = <String>{};
    for (final m in RegExp(
            r'<[a-z0-9]*:?response[^>]*>(.*?)</[a-z0-9]*:?response>',
            caseSensitive: false, dotAll: true)
        .allMatches(xml)) {
      final dentro = m.group(1)!;
      final href = _campo(dentro, 'href');
      if (href == null) continue;
      final pezzi = Uri.decodeComponent(href)
          .split('/')
          .where((x) => x.isNotEmpty)
          .toList();
      // La radice stessa: `/`. Non è un disco.
      if (pezzi.isEmpty) continue;
      // Solo i figli diretti della radice: `/123456/` sì, `/123456/foto/` no.
      if (pezzi.length > 1) continue;
      final id = pezzi.first;
      if (!visti.add(id)) continue;
      fuori.add(Kdrive(
        id: id,
        nome: _campo(dentro, 'displayname') ?? id,
        url: RegExp(r'^[0-9]{1,12}$').hasMatch(id)
            // La forma scritta nei documenti di Infomaniak, quella provata a
            // mano e quella che il resto del programma già sa usare.
            ? 'https://$id.connect.kdrive.infomaniak.com'
            : '$kdriveRadice/$href'.replaceAll(RegExp(r'(?<!:)//+'), '/'),
      ));
    }
    return fuori;
  }

  static String? _campo(String xml, String nome) {
    final m = RegExp('<[a-z0-9]*:?$nome[^>]*>(.*?)</[a-z0-9]*:?$nome>',
            caseSensitive: false, dotAll: true)
        .firstMatch(xml);
    if (m == null) return null;
    final v = m.group(1)!.trim();
    return v.isEmpty ? null : v;
  }

  /// Controlla un indirizzo scritto a mano, e lo mette in forma.
  ///
  /// Si rifiuta `http://` senza la esse: la password viaggerebbe in chiaro su
  /// ogni rete che si attraversa, e un programma che lo permette in silenzio
  /// sta prendendo una decisione al posto di chi non poteva saperlo.
  static String? indirizzo(String grezzo) {
    var s = grezzo.trim();
    if (s.isEmpty) return null;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'https') return null;
    // Via la barra finale: i percorsi si costruiscono qui sotto attaccandone
    // una, e due barre di fila fanno rispondere 404 a diversi server.
    var fuori = u.toString();
    while (fuori.endsWith('/')) {
      fuori = fuori.substring(0, fuori.length - 1);
    }
    return fuori;
  }

  // ── L'accesso ──────────────────────────────────────────────────────────

  /// Prova l'accesso. Torna `null` se ha funzionato, la frase da mostrare se no.
  ///
  /// Si fa con un PROPFIND di profondità zero sulla radice: è la richiesta più
  /// leggera che un server WebDAV sappia fare, e distingue le tre cose che
  /// interessano — l'indirizzo sbagliato, la password sbagliata, e il server
  /// che c'è ma non parla WebDAV.
  Future<String?> prova(String url, String utente, String password) async {
    final r = await chiedi('PROPFIND', '$url/', utente, password, _propfindVuoto,
        {'Depth': '0', 'Content-Type': 'application/xml; charset=utf-8'});
    return _percheNo(r);
  }

  static String? _percheNo(RispostaDav r, {bool kdrive = false}) {
    switch (r.codice) {
      case 207:
      case 200:
        return null;
      case 0:
        return 'Non riesco a raggiungere il server. Controlla la connessione, '
            'e che l\'indirizzo sia scritto giusto.';
      case 401:
      case 403:
        // La frase più importante di questo file. Un «password sbagliata»
        // secco, davanti a una password giusta, manda a cambiarla — e non è
        // quello il problema: il secondo passaggio (kAuth, il codice, la
        // chiave) protegge il sito, e un programma che parla WebDAV non ha
        // nessun modo di rispondere a quella domanda. Per quello esiste la
        // password per le applicazioni.
        return kdrive
            ? 'Infomaniak non ha accettato questo accesso. Se sul tuo account '
                'c\'è kAuth — o un altro secondo passaggio — la password con '
                'cui entri nel sito qui non basta, e non è colpa tua: nessun '
                'programma può rispondere a kAuth al posto tuo. Serve una '
                '«password per le applicazioni», che si crea nel tuo profilo '
                'Infomaniak, alla voce Sicurezza, e si usa solo da qui.'
            : 'Nome o password non vanno bene. Se il servizio chiede una '
                '«password per le applicazioni», serve quella e non la tua '
                'solita.';
      case 404:
        return 'Il server risponde, ma a quell\'indirizzo non c\'è niente.';
      case 405:
        return 'Quel server non parla WebDAV: risponde, ma non a questa '
            'domanda.';
      default:
        return 'Il server ha risposto ${r.codice}'
            '${r.errore != null ? ' (${r.errore})' : ''}.';
    }
  }

  // ── Lo spazio ──────────────────────────────────────────────────────────

  /// Spazio usato e disponibile, in byte. `null` in un campo vuol dire **che
  /// il server non l'ha detto**, e va mostrato così.
  ///
  /// ── Perché non si deduce ────────────────────────────────────────────────
  ///
  /// I due valori di RFC 4331 sono `quota-used-bytes` (quanto occupi) e
  /// `quota-available-bytes` (quanto ti resta), e **non tutti i server li
  /// mandano**: su molti WebDAV la risposta non li contiene proprio. La
  /// tentazione è dedurre il totale da un piano tariffario o mostrare zero;
  /// tutte e due sono numeri inventati, e un numero inventato sullo spazio
  /// libero è quello che fa perdere dei file.
  ///
  /// Quindi: se non li dice, non li diciamo.
  Future<SpazioDav> spazio(String url, String utente, String password) async {
    final r = await chiedi('PROPFIND', '$url/', utente, password, _propfindQuota,
        {'Depth': '0', 'Content-Type': 'application/xml; charset=utf-8'});
    if (r.codice != 207 && r.codice != 200) {
      return SpazioDav(errore: _percheNo(r));
    }
    return SpazioDav(
      usati: _numero(r.corpo, 'quota-used-bytes'),
      liberi: _numero(r.corpo, 'quota-available-bytes'),
    );
  }

  /// Il valore di un elemento XML, senza mettere in mezzo un lettore XML.
  ///
  /// Si cerca il nome ignorando il prefisso dello spazio dei nomi (`d:`, `D:`,
  /// `lp1:`… ogni server usa il suo) e si prende il primo numero che c'è
  /// dentro. Aggiungere una dipendenza XML per due numeri sarebbe più codice,
  /// non meno.
  static int? _numero(String? xml, String nome) {
    if (xml == null) return null;
    final m = RegExp('<[^>]*$nome[^>]*>\\s*(-?[0-9]+)\\s*</[^>]*$nome>',
            caseSensitive: false)
        .firstMatch(xml);
    if (m == null) return null;
    final v = int.tryParse(m.group(1)!);
    // I server che non sanno rispondere mandano -1 o -2 (RFC 4331: «non
    // definito», «illimitato»). Sono risposte, non numeri: si trattano come
    // «non lo dice».
    if (v == null || v < 0) return null;
    return v;
  }

  static const String _propfindVuoto = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:resourcetype/>'
      '</d:prop></d:propfind>';

  static const String _propfindNomi = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:displayname/><d:resourcetype/>'
      '</d:prop></d:propfind>';

  static const String _propfindQuota = '<?xml version="1.0" encoding="utf-8"?>'
      '<d:propfind xmlns:d="DAV:"><d:prop>'
      '<d:quota-available-bytes/><d:quota-used-bytes/>'
      '</d:prop></d:propfind>';

  // ── La richiesta vera ──────────────────────────────────────────────────
  //
  // Con `HttpClient` di Dart e non con `curl`: la password finirebbe negli
  // argomenti del processo, e `/proc/<pid>/cmdline` la legge chiunque giri
  // come te. È la stessa ragione per cui il gettone di GitHub non passa mai
  // dalla riga di comando — vedi `custodia/github_motore.dart`.
  static Future<RispostaDav> _chiediVero(
    String metodo,
    String url,
    String utente,
    String password,
    String? corpo,
    Map<String, String> intestazioni,
  ) async {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await c.openUrl(metodo, Uri.parse(url));
      req.headers.set('User-Agent', 'Minerva');
      final basic = base64.encode(utf8.encode('$utente:$password'));
      req.headers.set('Authorization', 'Basic $basic');
      intestazioni.forEach(req.headers.set);
      if (corpo != null) req.write(corpo);
      final res = await req.close().timeout(const Duration(seconds: 20));
      final testo = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 20));
      return RispostaDav(res.statusCode, testo);
    } catch (e) {
      return RispostaDav(0, null, errore: '$e');
    } finally {
      c.close(force: true);
    }
  }
}

class RispostaDav {
  const RispostaDav(this.codice, this.corpo, {this.errore});
  final int codice;
  final String? corpo;
  final String? errore;
}

class SpazioDav {
  const SpazioDav({this.usati, this.liberi, this.errore});

  /// Byte occupati, o `null` se il server non l'ha detto.
  final int? usati;

  /// Byte ancora disponibili, o `null` se il server non l'ha detto.
  final int? liberi;
  final String? errore;

  /// Il totale, quando si può fare. Somma di due cose che il server ha detto,
  /// mai una deduzione.
  int? get totale => (usati != null && liberi != null) ? usati! + liberi! : null;

  bool get loDice => usati != null || liberi != null;

  Map<String, dynamic> toJson() => {
        if (usati != null) 'usati': usati,
        if (liberi != null) 'liberi': liberi,
        if (totale != null) 'totale': totale,
        'loDice': loDice,
        if (errore != null) 'errore': errore,
      };
}

/// Un kDrive dell'account: quello che serve per usarlo, e il nome che gli ha
/// dato il suo padrone.
class Kdrive {
  const Kdrive({required this.id, required this.nome, required this.url});
  final String id;
  final String nome;
  final String url;

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'url': url};
}

class ElencoKdrive {
  const ElencoKdrive({this.dischi = const [], this.errore});
  final List<Kdrive> dischi;
  final String? errore;
}

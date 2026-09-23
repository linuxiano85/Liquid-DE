import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'genere.dart';

/// DLNA — Mostrare una fotografia su un televisore che parla UPnP.
///
/// ── Perché esiste, accanto a `castv2.dart` ─────────────────────────────────
///
/// Giacomo, 3 settembre 2026: «la cucina ha tizen os ed è samsung».
///
/// Il 3 settembre la scoperta di rete diceva questo:
///
///     Cucina        modo=airplay   192.168.1.69:7000
///     TV cameretta  modo=cast      192.168.1.55:8009
///
/// Cioè: l'unico televisore che parlava la lingua che Minerva sapeva parlare —
/// Chromecast — era quello in camera dei bambini, che è **esattamente** quello
/// che non si tocca. La funzione esisteva e il televisore che si sarebbe usato
/// davvero restava fuori.
///
/// Interrogando «Cucina» (richieste in sola lettura, che non accendono niente)
/// è venuto fuori che oltre ad AirPlay espone anche questo:
///
///     deviceType   urn:schemas-upnp-org:device:MediaRenderer:1
///     X_DLNADOC    DMR-1.50
///     modelName    UE55BU8070UXZT
///     AVTransport  http://192.168.1.69:9197/upnp/control/AVTransport1
///
/// Un **Digital Media Renderer** DLNA, che è uno standard vecchio di
/// vent'anni e straordinariamente semplice: SOAP su HTTP, due chiamate. E
/// soprattutto funziona **allo stesso modo di Chromecast** dal nostro lato —
/// non si manda il file, si manda un INDIRIZZO e il televisore va a
/// prenderselo. Quindi riusa `servizio_effimero.dart` senza cambiarci niente.
///
/// ── Perché DLNA e non AirPlay ──────────────────────────────────────────────
///
/// AirPlay 2 su un Samsung vuole un accoppiamento in stile HomeKit, con SRP e
/// scambio di chiavi. DLNA vuole due POST di XML. A parità di risultato — una
/// fotografia sullo schermo della cucina — si sceglie quello che si può
/// scrivere per intero, leggere in mezz'ora, e provare.
///
/// ── Nessuna libreria ───────────────────────────────────────────────────────
///
/// Come `castv2.dart`: XML a mano. Non per gusto — un parser XML completo per
/// leggere tre tag è più codice di quello che risparmia, e più superficie da
/// mantenere. Qui si cercano `<controlURL>` dentro il blocco del servizio
/// giusto, e nient'altro.
class Dlna {
  Dlna({required this.descrizione, HttpClient? cliente})
      : _cliente = cliente ?? HttpClient();

  /// L'indirizzo della descrizione del dispositivo:
  /// `http://192.168.1.69:9197/dmr`.
  final String descrizione;

  final HttpClient _cliente;

  /// L'indirizzo a cui si mandano i comandi di AVTransport. Si scopre dalla
  /// descrizione e si tiene: è una richiesta in meno per ogni fotografia.
  String? _controllo;

  static const _avTransport = 'urn:schemas-upnp-org:service:AVTransport:1';

  /// Il tipo di dispositivo che ci interessa, per la scoperta.
  static const tipoRenderer = 'urn:schemas-upnp-org:device:MediaRenderer:1';

  // ── Trovare i televisori: si CHIEDE a chi già si conosce ────────────────
  //
  // La strada da manuale sarebbe SSDP: un M-SEARCH in multicast su UDP 1900, e
  // le risposte che tornano. È scritta, ed è stata provata il 3 settembre 2026
  // su questa rete: **zero risposte**, anche da uno script Python nudo.
  //
  // Il motivo è dentro casa nostra: `ufw` è acceso, le risposte SSDP tornano
  // in UDP **unicast** verso la porta effimera da cui è partita la domanda, e
  // il firewall le scarta. Per farla funzionare bisognerebbe aprire la 1900 in
  // entrata — cioè un buco permanente, per una scoperta che qui si può fare
  // in un altro modo.
  //
  // L'altro modo: `avahi-browse` i televisori li trova già (Cucina si annuncia
  // via `_airplay._tcp`, la TV in cameretta via `_googlecast._tcp`), e a quel
  // punto sappiamo il loro indirizzo. Chiedere «hai un renderer DLNA?» a un
  // indirizzo noto è traffico in USCITA, che il firewall lascia passare.
  //
  // Quello che si perde, e va detto: un apparecchio che parla **solo** DLNA e
  // non si annuncia né via AirPlay né via Chromecast resta invisibile. Non è
  // il caso di nessun televisore di questa casa, e il giorno che lo diventasse
  // il rimedio è una riga di firewall — non un altro protocollo.

  /// Le porte su cui un televisore tiene la descrizione del suo renderer.
  ///
  /// 9197 è quella dei Samsung (verificata su UE55BU8070UXZT); le altre due
  /// sono le più diffuse fra gli altri. Sono poche apposta: ogni porta è
  /// un'attesa in più quando l'apparecchio non c'è.
  static const porteNote = <int, List<String>>{
    9197: ['/dmr'],
    8080: ['/description.xml', '/dmr'],
    49152: ['/description.xml', '/rootDesc.xml'],
  };

  /// Chiede a un indirizzo noto se ha un renderer DLNA, e chi è.
  ///
  /// Torna `null` se non ce l'ha. La pazienza è generosa di proposito: questo
  /// televisore, misurato, a volte impiega più di tre secondi a rispondere —
  /// e un timeout stretto lo fa risultare assente mentre è acceso davanti a
  /// te, che è il modo peggiore di sbagliare.
  static Future<Dlna?> interroga(
    String indirizzo, {
    Duration pazienza = const Duration(seconds: 8),
  }) async {
    for (final voce in porteNote.entries) {
      for (final percorso in voce.value) {
        final url = 'http://$indirizzo:${voce.key}$percorso';
        final d = Dlna(descrizione: url);
        final chi = await d.chiSei(pazienza: pazienza);
        if (chi != null) return d;
        d.chiudi();
      }
    }
    return null;
  }

  /// Legge la descrizione e ne ricava nome, modello e identificativo stabile.
  Future<Map<String, String>?> chiSei({
    Duration pazienza = const Duration(seconds: 8),
  }) async {
    final xml = await _prendi(descrizione, pazienza);
    if (xml == null) return null;
    if (!xml.contains(tipoRenderer)) return null;
    final controllo = _controlloDi(xml, _avTransport);
    if (controllo == null) return null;
    _controllo = _assoluto(descrizione, controllo);
    return {
      'nome': _tag(xml, 'friendlyName') ?? 'Televisore',
      'modello': _tag(xml, 'modelName') ?? '',
      // L'UDN è stabile fra le riaccensioni; l'IP no.
      'id': _tag(xml, 'UDN') ?? '',
      'controllo': _controllo!,
      'descrizione': descrizione,
    };
  }

  /// Mostra la fotografia che sta a `indirizzoFoto`.
  ///
  /// Due chiamate, e l'ordine è obbligato: prima si dice QUALE, poi si dice
  /// «vai». `SetAVTransportURI` da sola non mostra niente su nessun
  /// televisore — e non dà errore, il che è il modo peggiore di sbagliare.
  Future<void> mostra({
    required String indirizzoFoto,
    String tipo = 'image/jpeg',
    String titolo = '',
  }) async {
    final c = _controllo ?? (await chiSei())?['controllo'];
    if (c == null) {
      throw StateError('questo televisore non espone AVTransport');
    }
    await _soap(c, 'SetAVTransportURI', {
      'InstanceID': '0',
      'CurrentURI': indirizzoFoto,
      'CurrentURIMetaData': _didl(indirizzoFoto, tipo, titolo),
    });
    await _soap(c, 'Play', {'InstanceID': '0', 'Speed': '1'});
  }

  /// Smette di mostrarla. Non chiude niente di nostro: il servizio che presta
  /// il file lo spegne chi l'ha acceso.
  Future<void> ferma() async {
    final c = _controllo;
    if (c == null) return;
    try {
      await _soap(c, 'Stop', {'InstanceID': '0'});
    } catch (_) {
      // Un televisore spento non risponde, e non è un guasto: era proprio
      // quello che si voleva ottenere.
    }
  }

  void chiudi() => _cliente.close(force: true);

  // ── Le parti noiose ─────────────────────────────────────────────────────

  Future<void> _soap(
      String url, String azione, Map<String, String> argomenti) async {
    final corpo = StringBuffer()
      ..write('<?xml version="1.0" encoding="utf-8"?>')
      ..write('<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"')
      ..write(' s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">')
      ..write('<s:Body><u:$azione xmlns:u="$_avTransport">');
    argomenti.forEach((k, v) {
      corpo.write('<$k>${_scappa(v)}</$k>');
    });
    corpo.write('</u:$azione></s:Body></s:Envelope>');

    final r = await _cliente
        .postUrl(Uri.parse(url))
        .timeout(const Duration(seconds: 8));
    r.headers.set('Content-Type', 'text/xml; charset="utf-8"');
    r.headers.set('SOAPAction', '"$_avTransport#$azione"');
    r.write(corpo.toString());
    final risposta = await r.close().timeout(const Duration(seconds: 12));
    final testo = await risposta.transform(utf8.decoder).join();
    if (risposta.statusCode >= 400) {
      // Il televisore spiega il no dentro `<errorDescription>`, e quella
      // frase è più utile di «HTTP 500».
      final perche = _tag(testo, 'errorDescription')
          ?? _tag(testo, 'errorCode')
          ?? 'HTTP ${risposta.statusCode}';
      throw StateError('«$azione» rifiutata dal televisore: $perche');
    }
  }

  Future<String?> _prendi(String url, [Duration? pazienza]) async {
    final p = pazienza ?? const Duration(seconds: 8);
    try {
      final r = await _cliente.getUrl(Uri.parse(url)).timeout(p);
      final risposta = await r.close().timeout(p);
      if (risposta.statusCode >= 400) return null;
      return await risposta.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    }
  }

  /// Il `controlURL` del servizio richiesto.
  ///
  /// Si cerca dentro il blocco `<service>` che contiene quel `serviceType`, e
  /// non il primo `<controlURL>` del documento: una descrizione ne ha tre —
  /// RenderingControl, ConnectionManager, AVTransport — e prendere il primo
  /// vuol dire mandare i comandi del video al controllo del volume.
  static String? _controlloDi(String xml, String servizio) {
    for (final pezzo in xml.split('<service>')) {
      if (!pezzo.contains(servizio)) continue;
      return _tag(pezzo, 'controlURL');
    }
    return null;
  }

  static String? _tag(String xml, String nome) {
    final apre = xml.indexOf('<$nome>');
    if (apre < 0) return null;
    final chiude = xml.indexOf('</$nome>', apre);
    if (chiude < 0) return null;
    return xml.substring(apre + nome.length + 2, chiude).trim();
  }

  /// Un `controlURL` può essere relativo alla descrizione.
  static String _assoluto(String base, String parte) {
    if (parte.startsWith('http://') || parte.startsWith('https://')) {
      return parte;
    }
    final b = Uri.parse(base);
    return Uri(
      scheme: b.scheme,
      host: b.host,
      port: b.port,
      path: parte.startsWith('/') ? parte : '/$parte',
    ).toString();
  }

  /// La scheda che accompagna il file.
  ///
  /// Molti televisori mostrano l'immagine anche senza, ma alcuni — i Samsung
  /// fra questi — rifiutano un `SetAVTransportURI` con i metadati vuoti. È il
  /// minimo che la specifica DIDL-Lite accetta.
  ///
  /// ── La classe non è un'etichetta ─────────────────────────────────────
  ///
  /// Fino al 4 settembre 2026 qui c'era `object.item.imageItem.photo` scritto
  /// a mano, per **ogni** trasmissione: per un film, per una canzone, e anche
  /// per lo schermo trasmesso dal vivo. Funzionava per fortuna e non per
  /// costruzione — un apparecchio DLNA può confrontare la classe dichiarata
  /// con il `protocolInfo` della risorsa, e quando non tornano rifiuta o
  /// mostra nero. Adesso la classe viene dal tipo, e la traduzione sta in
  /// `genere.dart` con le sue prove.
  static String _didl(String url, String tipo, String titolo) {
    final t = titolo.isEmpty ? 'Minerva' : titolo;
    final g = Genere.di(tipo);
    return '<DIDL-Lite '
        'xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        'xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">'
        '<item id="1" parentID="0" restricted="1">'
        '<dc:title>${_scappa(t)}</dc:title>'
        '<upnp:class>${g.classeDidl}</upnp:class>'
        '<res protocolInfo="http-get:*:$tipo:${g.caratteristiche}">'
        '${_scappa(url)}</res>'
        '</item></DIDL-Lite>';
  }

  /// Il testo che finisce dentro l'XML. Un nome di file può contenere una `&`
  /// o una `<`, e senza questa funzione il televisore riceverebbe un documento
  /// rotto — e risponderebbe con un errore che non nomina la causa.
  static String _scappa(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

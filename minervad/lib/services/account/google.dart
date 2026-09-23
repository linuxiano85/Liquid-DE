import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../../util/sha256.dart';
import 'webdav.dart' show SpazioDav;

/// Google — l'accesso «con le cose classiche».
///
/// ── Cosa vede chi lo usa ───────────────────────────────────────────────────
///
/// Giacomo, 25 agosto 2026: «google invece chiede le classiche cose». Ed è
/// giusto così: si preme un pulsante, si apre il browser sulla pagina di
/// Google — quella vera, con l'email, la password e il secondo passaggio — e
/// alla fine Google chiede se Minerva può accedere. Poi la pagina dice di
/// tornare indietro, e l'account è collegato.
///
/// **La password non passa mai da qui.** Non la vediamo, non la teniamo, non
/// potremmo. È il motivo per cui questa strada è diversa da quella di kDrive,
/// e il motivo per cui funziona anche col secondo passaggio attivo: a quello
/// risponde Google nel browser, non noi.
///
/// ── Le tre parti che la rendono sicura ─────────────────────────────────────
///
///  1. **Il permesso più piccolo che serve** — `drive.file`: Minerva vede e
///     tocca **solo i file che ha creato lei**. Il resto del tuo Drive, per
///     questo programma, non esiste. È una scelta, non una limitazione subita:
///     un backup non ha nessun motivo di poter leggere tutto.
///  2. **Il ritorno sul computer** — Google rimanda il codice a
///     `http://127.0.0.1:<porta a caso>`, un indirizzo che esce dalla scheda
///     di rete di nessuno. Non c'è nessun sito di mezzo.
///  3. **PKCE** — chi altro girasse su questa macchina e riuscisse a vedere
///     quel codice non se ne farebbe niente senza il segreto che resta nella
///     memoria di questo processo. Vedi `util/sha256.dart`.
///
/// ── La chiave dell'applicazione ────────────────────────────────────────────
///
/// Google non lascia entrare un programma che non si sia registrato: serve una
/// «chiave dell'applicazione», che si crea in cinque minuti sulla sua console
/// e vale per sempre. Minerva non può metterne una dentro di sé — un progetto
/// pubblico che spedisce la propria chiave la regala a chiunque, e Google la
/// spegne. Quindi la chiede una volta e la mette nel portachiavi.
///
/// È la stessa cosa che fa `rclone`, per la stessa ragione.
class GoogleOAuth {
  const GoogleOAuth({
    this.chiedi = _chiediVero,
    this.apriPorta = _apriPortaVera,
    this.adesso = DateTime.now,
  });

  final Future<RispostaWeb> Function(
    String metodo,
    String url,
    Map<String, String> intestazioni,
    String? corpo,
  ) chiedi;

  final Future<PortaDiRitorno> Function() apriPorta;
  final DateTime Function() adesso;

  /// Il solo permesso che si chiede: i file creati da Minerva.
  static const String ambito = 'https://www.googleapis.com/auth/drive.file';

  static const String _consenso =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _gettoni = 'https://oauth2.googleapis.com/token';
  static const String _revoca = 'https://oauth2.googleapis.com/revoke';
  static const String _chiSei = 'https://www.googleapis.com/drive/v3/about'
      '?fields=user(emailAddress,displayName),storageQuota';

  // ── Collegare ──────────────────────────────────────────────────────────

  /// Il giro completo: apri il browser, aspetta, scambia il codice.
  ///
  /// `apri` riceve l'indirizzo da mostrare: qui non si lancia nessun browser,
  /// perché il demone non ha uno schermo davanti e la finestra sì.
  Future<EsitoGoogle> collega({
    required String clientId,
    required String clientSecret,
    required void Function(String url) apri,
    Duration pazienza = const Duration(minutes: 5),
  }) async {
    if (clientId.trim().isEmpty || clientSecret.trim().isEmpty) {
      return EsitoGoogle.no('Mi serve la chiave dell\'applicazione di Google: '
          'l\'identificativo e il segreto, tutti e due.');
    }

    final caso = Random.secure();
    final verificatore = _aCaso(caso, 48);
    final stato = _aCaso(caso, 16);

    final PortaDiRitorno porta;
    try {
      porta = await apriPorta();
    } catch (e) {
      return EsitoGoogle.no('Non riesco ad aprire la porta su cui Google deve '
          'rimandare la risposta ($e).');
    }

    try {
      final ritorno = 'http://127.0.0.1:${porta.numero}';
      final url = Uri.parse(_consenso).replace(queryParameters: {
        'client_id': clientId.trim(),
        'redirect_uri': ritorno,
        'response_type': 'code',
        'scope': ambito,
        // Perché il collegamento duri: senza questo, Google dà un permesso che
        // scade in un'ora e poi bisogna rifare tutto a mano.
        'access_type': 'offline',
        // E perché il permesso duraturo lo dia **ogni volta**: al secondo
        // collegamento Google, senza questo, lo omette — e il collegamento
        // sembra riuscito e muore un'ora dopo.
        'prompt': 'consent',
        'code_challenge': Sha256.base64url(ascii.encode(verificatore)),
        'code_challenge_method': 'S256',
        'state': stato,
      }).toString();

      apri(url);

      final r = await porta.attendi(pazienza, stato);
      if (r.errore != null) return EsitoGoogle.no(r.errore!);
      if (r.codice == null) {
        return EsitoGoogle.no('Google non ha risposto in tempo. Se la pagina '
            'del permesso è ancora aperta, riprova da capo.');
      }

      final scambio = await chiedi(
        'POST',
        _gettoni,
        {'Content-Type': 'application/x-www-form-urlencoded'},
        _modulo({
          'code': r.codice!,
          'client_id': clientId.trim(),
          'client_secret': clientSecret.trim(),
          'redirect_uri': ritorno,
          'grant_type': 'authorization_code',
          'code_verifier': verificatore,
        }),
      );

      final gettoni = _leggiGettoni(scambio);
      if (gettoni.errore != null) return EsitoGoogle.no(gettoni.errore!);
      if (gettoni.rinnovo == null) {
        return EsitoGoogle.no('Google ha dato il permesso ma non la chiave per '
            'rinnovarlo, e fra un\'ora sarebbe scaduto senza dire niente. '
            'Prova a togliere Minerva dai permessi del tuo account Google e a '
            'rifare il collegamento.');
      }
      return await _guarda(gettoni.accesso!, gettoni.rinnovo);
    } finally {
      await porta.chiudi();
    }
  }

  // ── Riguardare, dopo ───────────────────────────────────────────────────

  /// Con la chiave di rinnovo: un permesso nuovo, e cosa c'è nell'account.
  Future<EsitoGoogle> rinnova({
    required String clientId,
    required String clientSecret,
    required String rinnovo,
  }) async {
    final scambio = await chiedi(
      'POST',
      _gettoni,
      {'Content-Type': 'application/x-www-form-urlencoded'},
      _modulo({
        'client_id': clientId.trim(),
        'client_secret': clientSecret.trim(),
        'refresh_token': rinnovo,
        'grant_type': 'refresh_token',
      }),
    );
    final gettoni = _leggiGettoni(scambio);
    if (gettoni.errore != null) return EsitoGoogle.no(gettoni.errore!);
    return _guarda(gettoni.accesso!, rinnovo);
  }

  /// Toglie il permesso dal lato di Google, non solo da qui.
  ///
  /// Scollegare un account e lasciare a Google un permesso valido è mezzo
  /// lavoro: nell'elenco dei permessi del suo account resterebbe scritto che
  /// Minerva può entrare.
  Future<void> revoca(String gettone) async {
    try {
      await chiedi('POST', _revoca,
          {'Content-Type': 'application/x-www-form-urlencoded'},
          _modulo({'token': gettone}));
    } catch (_) {
      // Se non ci si riesce l'account viene tolto lo stesso: il permesso si
      // toglie anche dalla pagina di Google, e vale più togliere la riga.
    }
  }

  Future<EsitoGoogle> _guarda(String accesso, String? rinnovo) async {
    final r = await chiedi('GET', _chiSei, {'Authorization': 'Bearer $accesso'},
        null);
    if (r.codice != 200) {
      return EsitoGoogle.no(_perche(r, 'Non riesco a leggere i dati '
          'dell\'account'));
    }
    Map<String, dynamic> j;
    try {
      j = jsonDecode(r.corpo ?? '{}') as Map<String, dynamic>;
    } catch (_) {
      return EsitoGoogle.no('Google ha risposto qualcosa che non capisco.');
    }
    final utente = (j['user'] as Map?) ?? const {};
    final q = (j['storageQuota'] as Map?) ?? const {};
    final usati = _numero(q['usage']);
    final limite = _numero(q['limit']);
    return EsitoGoogle(
      ok: true,
      email: '${utente['emailAddress'] ?? ''}',
      nome: '${utente['displayName'] ?? ''}',
      rinnovo: rinnovo,
      accesso: accesso,
      // `limit` assente vuol dire spazio senza limite: non è zero, e non è
      // «non lo so». Si dice quanto è occupato e basta.
      spazio: SpazioDav(
        usati: usati,
        liberi: (limite != null && usati != null && limite >= usati)
            ? limite - usati
            : null,
      ),
    );
  }

  // ── Le parti noiose ────────────────────────────────────────────────────

  static int? _numero(Object? v) {
    if (v == null) return null;
    // Google manda i byte come stringhe: sono numeri a 64 bit, e in JSON non
    // ci starebbero.
    final n = int.tryParse('$v');
    return (n == null || n < 0) ? null : n;
  }

  static String _modulo(Map<String, String> campi) => campi.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  static String _aCaso(Random caso, int quanti) {
    const alfabeto =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(
        quanti, (_) => alfabeto[caso.nextInt(alfabeto.length)]).join();
  }

  static _Gettoni _leggiGettoni(RispostaWeb r) {
    Map<String, dynamic> j = const {};
    try {
      j = jsonDecode(r.corpo ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    if (r.codice != 200) {
      final quale = '${j['error'] ?? ''}';
      if (quale == 'invalid_client') {
        return _Gettoni.no('Google non riconosce questa chiave '
            'dell\'applicazione. Controlla di aver copiato per intero '
            'l\'identificativo e il segreto, e che la chiave sia del tipo '
            '«Applicazione desktop».');
      }
      if (quale == 'invalid_grant') {
        return _Gettoni.no('Google ha rifiutato il collegamento: il permesso '
            'non vale più. Ricollega l\'account.');
      }
      return _Gettoni.no(_perche(r, 'Google ha rifiutato lo scambio'));
    }
    final accesso = j['access_token'];
    if (accesso == null) {
      return _Gettoni.no('Google ha risposto senza darmi il permesso.');
    }
    return _Gettoni(accesso: '$accesso', rinnovo: j['refresh_token'] as String?);
  }

  static String _perche(RispostaWeb r, String cosa) {
    if (r.codice == 0) {
      return '$cosa: non riesco a raggiungere Google. Controlla la '
          'connessione.';
    }
    return '$cosa (Google ha risposto ${r.codice}).';
  }

  // ── La richiesta vera ──────────────────────────────────────────────────

  static Future<RispostaWeb> _chiediVero(
    String metodo,
    String url,
    Map<String, String> intestazioni,
    String? corpo,
  ) async {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await c.openUrl(metodo, Uri.parse(url));
      req.headers.set('User-Agent', 'Minerva');
      intestazioni.forEach(req.headers.set);
      if (corpo != null) req.write(corpo);
      final res = await req.close().timeout(const Duration(seconds: 25));
      final testo = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 25));
      return RispostaWeb(res.statusCode, testo);
    } catch (e) {
      return RispostaWeb(0, null, errore: '$e');
    } finally {
      c.close(force: true);
    }
  }

  static Future<PortaDiRitorno> _apriPortaVera() async =>
      PortaHttp(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
}

class RispostaWeb {
  const RispostaWeb(this.codice, this.corpo, {this.errore});
  final int codice;
  final String? corpo;
  final String? errore;
}

class _Gettoni {
  const _Gettoni({this.accesso, this.rinnovo}) : errore = null;
  const _Gettoni.no(this.errore)
      : accesso = null,
        rinnovo = null;
  final String? accesso;
  final String? rinnovo;
  final String? errore;
}

class EsitoGoogle {
  const EsitoGoogle({
    required this.ok,
    this.errore,
    this.email = '',
    this.nome = '',
    this.rinnovo,
    this.accesso,
    this.spazio,
  });

  const EsitoGoogle.no(String perche) : this(ok: false, errore: perche);

  final bool ok;
  final String? errore;
  final String email;
  final String nome;

  /// La chiave con cui si torna dentro domani. Va nel portachiavi e non esce
  /// mai da lì: nessuna risposta di questo programma la contiene.
  final String? rinnovo;
  final String? accesso;
  final SpazioDav? spazio;
}

/// Il posto dove Google rimanda il codice: una porta su questo computer.
abstract class PortaDiRitorno {
  int get numero;

  /// Aspetta la visita del browser. Controlla che sia la nostra — `stato` è
  /// un numero a caso che abbiamo mandato all'andata e che deve tornare
  /// indietro uguale: senza questo controllo, un'altra pagina aperta nel
  /// browser potrebbe far collegare a Minerva un account che non è il tuo.
  Future<RispostaConsenso> attendi(Duration quanto, String stato);

  Future<void> chiudi();
}

class RispostaConsenso {
  const RispostaConsenso({this.codice, this.errore});
  final String? codice;
  final String? errore;
}

class PortaHttp implements PortaDiRitorno {
  PortaHttp(this._server);
  final HttpServer _server;

  @override
  int get numero => _server.port;

  @override
  Future<RispostaConsenso> attendi(Duration quanto, String stato) async {
    final finito = Completer<RispostaConsenso>();
    final sottoscrizione = _server.listen((req) async {
      final q = req.uri.queryParameters;
      RispostaConsenso esito;
      if (q['error'] != null) {
        esito = RispostaConsenso(
            errore: q['error'] == 'access_denied'
                ? 'Hai detto di no nella pagina di Google, e va benissimo: '
                    'non è cambiato niente.'
                : 'Google ha risposto «${q['error']}».');
      } else if (q['state'] != stato) {
        esito = const RispostaConsenso(
            errore: 'È tornata indietro una risposta che non è quella che '
                'avevo mandato io. Non l\'ho usata. Riprova.');
      } else if (q['code'] == null) {
        esito = const RispostaConsenso(
            errore: 'Google è tornato senza il codice del permesso.');
      } else {
        esito = RispostaConsenso(codice: q['code']);
      }

      req.response.headers.contentType = ContentType.html;
      req.response.write(_pagina(esito.errore));
      await req.response.close();
      if (!finito.isCompleted) finito.complete(esito);
    }, onError: (Object e) {
      if (!finito.isCompleted) {
        finito.complete(RispostaConsenso(errore: 'La porta di ritorno si è '
            'chiusa da sola ($e).'));
      }
    });

    try {
      return await finito.future.timeout(quanto,
          onTimeout: () => const RispostaConsenso());
    } finally {
      await sottoscrizione.cancel();
    }
  }

  @override
  Future<void> chiudi() async {
    try {
      await _server.close(force: true);
    } catch (_) {}
  }

  /// La pagina che vede chi torna dal browser. Nessuno stile che si scarichi
  /// da fuori: questa pagina esiste per due secondi e non deve dipendere da
  /// niente.
  static String _pagina(String? errore) => '''<!doctype html>
<html lang="it"><head><meta charset="utf-8">
<title>Minerva</title>
<style>
 body{font-family:system-ui,sans-serif;background:#14161a;color:#e8eaee;
      display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
 div{max-width:30rem;text-align:center;line-height:1.5}
 h1{font-size:1.4rem;font-weight:600;margin:0 0 .6rem}
 p{color:#a4abb8;margin:0}
</style></head><body><div>
<h1>${errore == null ? 'Account collegato' : 'Non è andata'}</h1>
<p>${errore ?? 'Puoi chiudere questa scheda e tornare a Minerva.'}</p>
</div></body></html>''';
}

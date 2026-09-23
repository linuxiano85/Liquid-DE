import 'dart:convert';
import 'dart:io';

import 'package:minervad/services/account/google.dart';
import 'package:test/test.dart';

/// Prove sull'accesso a Google.
///
/// Con Google non si parla mai davvero: le risposte si fingono. Ma **la porta
/// di ritorno sì**, ed è quella vera — un server sull'indirizzo di questo
/// computer, chiamato da un client vero. È il pezzo che non si può fingere
/// senza smettere di provare qualcosa: è lì che arriva il permesso, ed è lì
/// che un altro programma proverebbe a rubarlo.
void main() {
  GoogleOAuth motore({
    PortaDiRitorno? porta,
    RispostaWeb? Function(String url, String? corpo)? risposte,
  }) =>
      GoogleOAuth(
        apriPorta: () async => porta ?? _Porta(codice: 'C'),
        chiedi: (metodo, url, h, corpo) async {
          final r = risposte?.call(url, corpo);
          if (r != null) return r;
          if (url.contains('/token')) {
            return const RispostaWeb(
                200, '{"access_token":"AT","refresh_token":"RT"}');
          }
          return const RispostaWeb(
              200,
              '{"user":{"emailAddress":"tizio@gmail.com","displayName":"Tizio"},'
              '"storageQuota":{"usage":"10","limit":"100"}}');
        },
      );

  // ── L'andata ───────────────────────────────────────────────────────────

  group('l\'indirizzo che si apre nel browser', () {
    test('chiede il permesso più piccolo, e con PKCE', () async {
      var url = '';
      await motore().collega(
          clientId: '1.apps.googleusercontent.com',
          clientSecret: 's',
          apri: (u) => url = u);
      final q = Uri.parse(url).queryParameters;
      expect(q['scope'], 'https://www.googleapis.com/auth/drive.file',
          reason: 'ha chiesto più di quello che gli serve');
      expect(q['code_challenge_method'], 'S256');
      expect(q['code_challenge'], isNotEmpty);
      expect(q['redirect_uri'], startsWith('http://127.0.0.1:'),
          reason: 'il permesso deve tornare su questo computer, non su un sito');
      // Senza questi due, il collegamento sembra riuscito e muore un'ora dopo.
      expect(q['access_type'], 'offline');
      expect(q['prompt'], 'consent');
    });

    test('e il segreto della verifica non parte mai insieme al codice',
        () async {
      var url = '';
      String? corpoScambio;
      await motore(risposte: (u, c) {
        if (u.contains('/token')) corpoScambio = c;
        return null;
      }).collega(
          clientId: '1.apps.googleusercontent.com',
          clientSecret: 's',
          apri: (u) => url = u);
      final sfida = Uri.parse(url).queryParameters['code_challenge']!;
      // La sfida va all'andata, il verificatore al ritorno: chi vede solo una
      // delle due non ha niente.
      expect(corpoScambio, isNot(contains(Uri.encodeQueryComponent(sfida))));
      expect(corpoScambio, contains('code_verifier='));
    });
  });

  // ── I rifiuti ──────────────────────────────────────────────────────────

  group('quello che si rifiuta di fare', () {
    test('senza chiave non parte nemmeno', () async {
      final e = await motore()
          .collega(clientId: '', clientSecret: '', apri: (_) {});
      expect(e.ok, isFalse);
    });

    test('una risposta che non è la nostra non si usa', () async {
      // Senza questo controllo, un\'altra pagina aperta nel browser potrebbe
      // far collegare a Minerva un account che non è il tuo.
      final e = await motore(porta: _Porta(statoSbagliato: true)).collega(
          clientId: '1.apps.googleusercontent.com',
          clientSecret: 's',
          apri: (_) {});
      expect(e.ok, isFalse);
      expect(e.errore, contains('Non l\'ho usata'));
    });

    test('«no grazie» nella pagina di Google non è un errore', () async {
      final e = await motore(porta: _Porta(rifiuto: true)).collega(
          clientId: '1.apps.googleusercontent.com',
          clientSecret: 's',
          apri: (_) {});
      expect(e.ok, isFalse);
      expect(e.errore, contains('va benissimo'));
    });

    test('una chiave che Google non riconosce lo dice con parole utili',
        () async {
      final e = await motore(
              risposte: (u, c) => u.contains('/token')
                  ? const RispostaWeb(401, '{"error":"invalid_client"}')
                  : null)
          .collega(
              clientId: '1.apps.googleusercontent.com',
              clientSecret: 'sbagliato',
              apri: (_) {});
      expect(e.ok, isFalse);
      expect(e.errore, contains('Applicazione desktop'));
    });

    test('un permesso senza chiave di rinnovo non si salva: scadrebbe in '
        'un\'ora fingendo di durare', () async {
      final e = await motore(
              risposte: (u, c) => u.contains('/token')
                  ? const RispostaWeb(200, '{"access_token":"AT"}')
                  : null)
          .collega(
              clientId: '1.apps.googleusercontent.com',
              clientSecret: 's',
              apri: (_) {});
      expect(e.ok, isFalse);
      expect(e.errore, contains('rinnovarlo'));
    });
  });

  // ── Lo spazio ──────────────────────────────────────────────────────────

  test('lo spazio: i byte arrivano come stringhe, e i liberi sono una '
      'sottrazione', () async {
    final e = await motore().collega(
        clientId: '1.apps.googleusercontent.com',
        clientSecret: 's',
        apri: (_) {});
    expect(e.ok, isTrue, reason: e.errore);
    expect(e.email, 'tizio@gmail.com');
    expect(e.spazio!.usati, 10);
    expect(e.spazio!.liberi, 90);
    expect(e.spazio!.totale, 100);
  });

  // ── La porta vera ──────────────────────────────────────────────────────

  group('la porta di ritorno, quella vera', () {
    test('prende il codice da una visita giusta', () async {
      final porta = PortaHttp(await HttpServer.bind(
          InternetAddress.loopbackIPv4, 0));
      final atteso = porta.attendi(const Duration(seconds: 10), 'STATO');
      final r = await _visita('http://127.0.0.1:${porta.numero}'
          '/?state=STATO&code=IL-CODICE');
      expect(r, contains('Account collegato'));
      expect((await atteso).codice, 'IL-CODICE');
      await porta.chiudi();
    });

    test('e butta via una visita con lo stato sbagliato', () async {
      final porta = PortaHttp(await HttpServer.bind(
          InternetAddress.loopbackIPv4, 0));
      final atteso = porta.attendi(const Duration(seconds: 10), 'STATO');
      await _visita('http://127.0.0.1:${porta.numero}'
          '/?state=ALTRO&code=RUBATO');
      final r = await atteso;
      expect(r.codice, isNull);
      expect(r.errore, isNotNull);
      await porta.chiudi();
    });

    test('se nessuno arriva, smette di aspettare invece di restare aperta '
        'per sempre', () async {
      final porta = PortaHttp(await HttpServer.bind(
          InternetAddress.loopbackIPv4, 0));
      final r =
          await porta.attendi(const Duration(milliseconds: 150), 'STATO');
      expect(r.codice, isNull);
      expect(r.errore, isNull);
      await porta.chiudi();
    });

    test('e dopo chiusa non risponde più a nessuno', () async {
      final porta = PortaHttp(await HttpServer.bind(
          InternetAddress.loopbackIPv4, 0));
      final numero = porta.numero;
      await porta.chiudi();
      expect(() => _visita('http://127.0.0.1:$numero/'), throwsA(anything));
    });
  });
}

Future<String> _visita(String url) async {
  final c = HttpClient();
  try {
    final req = await c.getUrl(Uri.parse(url));
    final res = await req.close();
    return await res.transform(utf8.decoder).join();
  } finally {
    c.close(force: true);
  }
}

class _Porta implements PortaDiRitorno {
  _Porta({this.codice, this.statoSbagliato = false, this.rifiuto = false});
  final String? codice;
  final bool statoSbagliato;
  final bool rifiuto;

  @override
  int get numero => 41234;

  @override
  Future<RispostaConsenso> attendi(Duration quanto, String stato) async {
    if (rifiuto) {
      return const RispostaConsenso(
          errore: 'Hai detto di no nella pagina di Google, e va benissimo: '
              'non è cambiato niente.');
    }
    if (statoSbagliato) {
      return const RispostaConsenso(
          errore: 'È tornata indietro una risposta che non è quella che avevo '
              'mandato io. Non l\'ho usata. Riprova.');
    }
    return RispostaConsenso(codice: codice ?? 'C');
  }

  @override
  Future<void> chiudi() async {}
}

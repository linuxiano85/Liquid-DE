import 'package:minervad/services/account/webdav.dart';
import 'package:test/test.dart';

/// Prove sul motore che parla coi servizi in rete.
///
/// Con nessun server si parla davvero: le risposte si fingono. Una prova che ha
/// bisogno di internet è una prova che un giorno fallisce per motivi suoi e
/// smette di essere creduta — e queste servono soprattutto a provare i casi che
/// non si riescono a provocare apposta: la password sbagliata, il server che
/// non parla WebDAV, quello che non dice quanto spazio resta.
void main() {
  WebDav finto(RispostaDav Function(String, String, Map<String, String>) r) {
    return WebDav(
      chiedi: (metodo, url, utente, password, corpo, intestazioni) async =>
          r(metodo, url, intestazioni),
    );
  }

  // ── L'indirizzo ────────────────────────────────────────────────────────

  group('l\'indirizzo', () {
    test('il kDrive si costruisce dal solo numero', () {
      expect(WebDav.kdrive('123456'),
          'https://123456.connect.kdrive.infomaniak.com');
      expect(WebDav.kdrive(' 42 '),
          'https://42.connect.kdrive.infomaniak.com');
    });

    test('e un numero che non è un numero si rifiuta', () {
      for (final brutto in ['', 'abc', '12a', '../../etc', '1;rm -rf /']) {
        expect(WebDav.kdrive(brutto), isNull, reason: 'ha accettato «$brutto»');
      }
    });

    test('senza la esse si rifiuta, e non è pignoleria', () {
      // Su `http://` la password viaggia in chiaro su ogni rete che si
      // attraversa. Lasciarlo passare in silenzio vuol dire prendere una
      // decisione al posto di chi non poteva saperlo.
      expect(WebDav.indirizzo('http://casa.example.it/dav'), isNull);
      expect(WebDav.indirizzo('ftp://casa.example.it'), isNull);
    });

    test('senza schema si assume https', () {
      expect(WebDav.indirizzo('casa.example.it/dav'),
          'https://casa.example.it/dav');
    });

    test('la barra finale si toglie', () {
      // Due barre di fila fanno rispondere 404 a diversi server, e il percorso
      // qui sotto ne attacca già una.
      expect(WebDav.indirizzo('https://casa.example.it/dav///'),
          'https://casa.example.it/dav');
    });

    test('quello che non è un indirizzo si rifiuta', () {
      for (final brutto in ['', '   ', 'https://', '::::']) {
        expect(WebDav.indirizzo(brutto), isNull,
            reason: 'ha accettato «$brutto»');
      }
    });
  });

  // ── L'accesso, e soprattutto i rifiuti ─────────────────────────────────

  group('provare l\'accesso', () {
    test('un 207 vuol dire che va', () async {
      final m = finto((metodo, url, h) {
        expect(metodo, 'PROPFIND');
        expect(h['Depth'], '0');
        return const RispostaDav(207, '<d:multistatus xmlns:d="DAV:"/>');
      });
      expect(await m.prova('https://x.example', 'tizio', 'segreto'), isNull);
    });

    test('la password sbagliata lo dice, e dice anche cosa cercare', () async {
      // Molti servizi — kDrive compreso — vogliono una «password per le
      // applicazioni» e non quella con cui si entra nel sito. Chi non lo sa
      // riprova la stessa password tre volte e dà la colpa al programma.
      final m = finto((a, b, c) => const RispostaDav(401, null));
      final e = await m.prova('https://x.example', 'tizio', 'sbagliata');
      expect(e, contains('password'));
      expect(e, contains('applicazioni'));
    });

    test('la rete che manca si distingue dal server che rifiuta', () async {
      final m = finto((a, b, c) => const RispostaDav(0, null));
      expect(await m.prova('https://x.example', 't', 'p'),
          contains('connessione'));
    });

    test('un server che non parla WebDAV lo dice', () async {
      final m = finto((a, b, c) => const RispostaDav(405, null));
      expect(await m.prova('https://x.example', 't', 'p'),
          contains('non parla WebDAV'));
    });

    test('e un codice che non conosciamo lo riporta invece di inventare',
        () async {
      final m = finto((a, b, c) => const RispostaDav(507, null));
      expect(await m.prova('https://x.example', 't', 'p'), contains('507'));
    });
  });

  // ── Lo spazio ──────────────────────────────────────────────────────────

  group('lo spazio', () {
    const risposta = '<?xml version="1.0"?>'
        '<d:multistatus xmlns:d="DAV:"><d:response><d:propstat><d:prop>'
        '<d:quota-used-bytes>1073741824</d:quota-used-bytes>'
        '<d:quota-available-bytes>3221225472</d:quota-available-bytes>'
        '</d:prop></d:propstat></d:response></d:multistatus>';

    test('si legge, e il totale è la somma di quello che ha detto lui',
        () async {
      final m = finto((a, b, c) => const RispostaDav(207, risposta));
      final s = await m.spazio('https://x.example', 't', 'p');
      expect(s.usati, 1073741824);
      expect(s.liberi, 3221225472);
      expect(s.totale, 1073741824 + 3221225472);
      expect(s.loDice, isTrue);
    });

    test('qualunque prefisso di spazio dei nomi va bene', () async {
      // `d:`, `D:`, `lp1:`… ogni server usa il suo, e un motore che ne
      // riconosce uno solo funziona con un server solo.
      const altro = '<?xml version="1.0"?><D:multistatus xmlns:D="DAV:">'
          '<D:prop><lp1:quota-used-bytes xmlns:lp1="DAV:">500'
          '</lp1:quota-used-bytes></D:prop></D:multistatus>';
      final m = finto((a, b, c) => const RispostaDav(207, altro));
      expect((await m.spazio('https://x.example', 't', 'p')).usati, 500);
    });

    test('un server che non lo dice NON diventa zero', () async {
      // È la prova più importante del file. Zero libero vuol dire «non
      // mandarci più niente»; zero usato vuol dire «è vuoto». Sono due bugie
      // sullo spazio, ed è così che si perdono dei file.
      final m = finto((a, b, c) => const RispostaDav(
          207, '<d:multistatus xmlns:d="DAV:"><d:prop/></d:multistatus>'));
      final s = await m.spazio('https://x.example', 't', 'p');
      expect(s.usati, isNull);
      expect(s.liberi, isNull);
      expect(s.totale, isNull);
      expect(s.loDice, isFalse);
    });

    test('e nemmeno un -1 diventa zero', () async {
      // RFC 4331: -1 vuol dire «non definito», -2 «illimitato». Sono risposte,
      // non numeri.
      const meno = '<d:multistatus xmlns:d="DAV:">'
          '<d:quota-available-bytes>-1</d:quota-available-bytes>'
          '<d:quota-used-bytes>-2</d:quota-used-bytes></d:multistatus>';
      final m = finto((a, b, c) => const RispostaDav(207, meno));
      final s = await m.spazio('https://x.example', 't', 'p');
      expect(s.usati, isNull);
      expect(s.liberi, isNull);
      expect(s.loDice, isFalse);
    });

    test('se il server rifiuta, lo spazio porta il perché', () async {
      final m = finto((a, b, c) => const RispostaDav(401, null));
      final s = await m.spazio('https://x.example', 't', 'p');
      expect(s.errore, contains('password'));
      expect(s.loDice, isFalse);
    });
  });

  // ── I kDrive dell'account ──────────────────────────────────────────────
  //
  // Misurato con curl il 25 agosto 2026, senza credenziali:
  // `https://connect.kdrive.infomaniak.com/` risponde 401 con
  // `Www-Authenticate: Basic realm="kdrive/dav"`, mentre un numero inventato
  // risponde 404. Il numero non va chiesto a nessuno: lo dice il server.

  group('quali kDrive ha questo account', () {
    RispostaDav elenco(String dentro) => RispostaDav(
        207, '<d:multistatus xmlns:d="DAV:">$dentro</d:multistatus>');

    test('la radice non è un archivio, e le cartelle dentro nemmeno', () async {
      final w = finto((m, url, h) => elenco(
          '<d:response><d:href>/</d:href></d:response>'
          '<d:response><d:href>/123456/</d:href>'
          '<d:propstat><d:prop><d:displayname>Comune</d:displayname>'
          '</d:prop></d:propstat></d:response>'
          '<d:response><d:href>/123456/Foto/</d:href></d:response>'));
      final e = await w.kdriveDi('tizio', 'x');
      expect(e.errore, isNull);
      expect(e.dischi.length, 1);
      expect(e.dischi.single.id, '123456');
      expect(e.dischi.single.nome, 'Comune');
      expect(e.dischi.single.url,
          'https://123456.connect.kdrive.infomaniak.com');
    });

    test('col prefisso che gli pare: ogni server usa il suo', () async {
      // `d:`, `D:`, `lp1:`… il nome dell'elemento è quello che conta.
      final w = finto((m, url, h) => RispostaDav(
          207,
          '<D:multistatus xmlns:D="DAV:">'
          '<D:response><D:href>/7/</D:href>'
          '<D:propstat><D:prop><D:displayname>Sette</D:displayname>'
          '</D:prop></D:propstat></D:response></D:multistatus>'));
      final e = await w.kdriveDi('tizio', 'x');
      expect(e.dischi.single.nome, 'Sette');
    });

    test('senza nome si usa il numero, invece di lasciare una riga vuota',
        () async {
      final w = finto((m, url, h) =>
          elenco('<d:response><d:href>/42/</d:href></d:response>'));
      final e = await w.kdriveDi('tizio', 'x');
      expect(e.dischi.single.nome, '42');
    });

    test('due volte lo stesso archivio resta uno', () async {
      final w = finto((m, url, h) => elenco(
          '<d:response><d:href>/9/</d:href></d:response>'
          '<d:response><d:href>/9/</d:href></d:response>'));
      final e = await w.kdriveDi('tizio', 'x');
      expect(e.dischi.length, 1);
    });

    test('la richiesta va sulla radice, e chiede i nomi', () async {
      var visto = '';
      var profondita = '';
      final w = WebDav(chiedi: (metodo, url, u, p, corpo, h) async {
        visto = url;
        profondita = h['Depth'] ?? '';
        return elenco('');
      });
      await w.kdriveDi('tizio', 'x');
      expect(visto, 'https://connect.kdrive.infomaniak.com/');
      expect(profondita, '1');
    });

    test('e se non lo lascia entrare, dice che il secondo passaggio non è '
        'colpa sua', () async {
      // Un «password sbagliata» secco, davanti a una password giusta, manda a
      // cambiare la password — e non è quello il problema: a kAuth nessun
      // programma può rispondere al posto tuo.
      final w = finto((m, url, h) => const RispostaDav(401, null));
      final e = await w.kdriveDi('tizio', 'x');
      expect(e.dischi, isEmpty);
      expect(e.errore, contains('kAuth'));
      expect(e.errore, contains('password per le applicazioni'));
    });
  });
}

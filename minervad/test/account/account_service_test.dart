import 'dart:io';

import 'package:minervad/services/account/google.dart';
import 'package:minervad/services/account/registro_account.dart';
import 'package:minervad/services/account/webdav.dart';
import 'package:minervad/services/account_service.dart';
import 'package:test/test.dart';

/// Prove sulla cucitura degli account online.
///
/// Quasi tutte sono **rifiuti**, come per la Custodia e per lo stesso motivo:
/// quando la regola funziona non si vede niente. Si vede il giorno che un
/// account salvato senza essere stato provato dice «collegato» e non lo è, e
/// ci si accorge dell'errore nel momento in cui si prova a mandarci un backup.
void main() {
  late Directory temp;
  late List<List<String>> comandi;

  AccountService costruisci({
    String? Function(String url, String utente)? accesso,
    SpazioDav Function()? spazio,
    Map<String, String>? portachiavi,
    List<List<String>>? dischi,
    GoogleOAuth? google,
    /// Un portachiavi che accetta e poi non ricorda: succede davvero quando
    /// il portachiavi si chiude o viene svuotato, ed è il caso in cui il
    /// programma non deve fingere che l'account funzioni.
    bool portachiaviSmemorato = false,
  }) {
    final chiavi = portachiavi ?? <String, String>{};
    return AccountService(
      registro: RegistroAccount(percorso: '${temp.path}/account.json'),
      google: google,
      dav: WebDav(
        chiedi: (metodo, url, utente, password, corpo, h) async {
          final no = accesso?.call(url, utente);
          if (no != null) return const RispostaDav(401, null);
          // L'elenco dei kDrive dell'account: la richiesta che chiede i nomi
          // sulla radice, senza numero.
          if (corpo != null && corpo.contains('displayname')) {
            final righe = (dischi ?? [
              ['123456', 'kDrive comune']
            ])
                .map((d) => '<d:response><d:href>/${d[0]}/</d:href>'
                    '<d:propstat><d:prop><d:displayname>${d[1]}</d:displayname>'
                    '</d:prop></d:propstat></d:response>')
                .join();
            return RispostaDav(
                207,
                '<d:multistatus xmlns:d="DAV:">'
                '<d:response><d:href>/</d:href></d:response>'
                '$righe</d:multistatus>');
          }
          if (corpo != null && corpo.contains('quota')) {
            final s = spazio?.call() ?? const SpazioDav();
            return RispostaDav(
                207,
                '<d:multistatus xmlns:d="DAV:">'
                '${s.usati != null ? "<d:quota-used-bytes>${s.usati}</d:quota-used-bytes>" : ""}'
                '${s.liberi != null ? "<d:quota-available-bytes>${s.liberi}</d:quota-available-bytes>" : ""}'
                '</d:multistatus>');
          }
          return const RispostaDav(207, '<d:multistatus xmlns:d="DAV:"/>');
        },
      ),
      // Il portachiavi finto. Prima del 25 agosto 2026 la scrittura passava
      // da una `Process.start` piantata nel servizio, e queste prove
      // scrivevano **davvero** nel portachiavi di questa macchina — mentre la
      // riga che controlla che una password sbagliata non ci finisca guardava
      // una lista in cui quel comando non compariva mai.
      conSegreto: (cmd, args, segreto) async {
        comandi.add([cmd, ...args]);
        if (cmd == 'secret-tool' &&
            args.first == 'store' &&
            !portachiaviSmemorato) {
          chiavi[args[args.length - 1]] = segreto;
        }
        return 0;
      },
      esegui: (cmd, args) async {
        comandi.add([cmd, ...args]);
        if (cmd == 'secret-tool' && args.first == 'lookup') {
          final id = args[args.length - 1];
          return chiavi.containsKey(id)
              ? ProcessResult(0, 0, chiavi[id], '')
              : ProcessResult(0, 1, '', '');
        }
        if (cmd == 'sh') return ProcessResult(0, 1, '', ''); // niente rclone
        return ProcessResult(0, 0, '', '');
      },
    );
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-account-');
    comandi = [];
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  // ── I rifiuti ──────────────────────────────────────────────────────────

  group('quello che si rifiuta di fare', () {
    test('un numero di kDrive che non è un numero', () async {
      final s = costruisci();
      final e = await s.collega(
          servizio: 'kdrive', utente: 'tizio', password: 'x',
          numeroKdrive: 'nonlo so');
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('cifre'));
      expect(s.registro.account, isEmpty);
    });

    test('un indirizzo senza la esse', () async {
      final s = costruisci();
      final e = await s.collega(
          servizio: 'webdav', utente: 'tizio', password: 'x',
          url: 'http://casa.example.it/dav');
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('chiaro'));
    });

    test('un servizio che non conosciamo', () async {
      final e = await costruisci().collega(
          servizio: 'piccione', utente: 'tizio', password: 'x');
      expect(e['ok'], isFalse);
    });

    test('senza password non si collega niente', () async {
      final e = await costruisci().collega(
          servizio: 'kdrive', utente: 'tizio', password: '', numeroKdrive: '1');
      expect(e['ok'], isFalse);
    });
  });

  // ── La regola: prima si prova, poi si scrive ───────────────────────────

  test('un accesso che non funziona NON entra nell\'elenco', () async {
    // Un account salvato che non funziona è una riga che dice «collegato» e
    // non lo è. Il momento in cui ci si accorge dell'errore sarebbe quello in
    // cui si prova a mandarci un backup, cioè il peggiore.
    final s = costruisci(accesso: (url, utente) => 'no');
    final e = await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'sbagliata',
        numeroKdrive: '123');
    expect(e['ok'], isFalse);
    expect(s.registro.account, isEmpty);
    expect(comandi.any((c) => c.contains('store')), isFalse,
        reason: 'ha messo nel portachiavi una password che non funziona');
  });

  test('quello che funziona entra, e la password va nel portachiavi',
      () async {
    final s = costruisci();
    final e = await s.collega(
        servizio: 'kdrive', utente: 'tizio@example.it', password: 'giusta',
        numeroKdrive: '123456', nome: 'kDrive di casa');
    expect(e['ok'], isTrue, reason: '${e['errore']}');

    final a = s.registro.account.single;
    expect(a.nome, 'kDrive di casa');
    expect(a.url, 'https://123456.connect.kdrive.infomaniak.com');
    expect(a.funziona, isTrue);

    // E la cosa che conta: nel file non c'è la password.
    final scritto = await File('${temp.path}/account.json').readAsString();
    expect(scritto, isNot(contains('giusta')));
    expect(scritto.toLowerCase(), isNot(contains('password')));
  });

  test('ricollegare aggiorna, non aggiunge una seconda riga', () async {
    // Due righe per lo stesso account sono due posti dove scade la password.
    final s = costruisci();
    await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'x', numeroKdrive: '1');
    await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'y', numeroKdrive: '2');
    expect(s.registro.account.length, 1);
    expect(s.registro.account.single.url,
        'https://2.connect.kdrive.infomaniak.com');
  });

  test('la chiave non cambia se cambia l\'indirizzo', () {
    // È la chiave con cui la password sta nel portachiavi: una chiave che
    // cambia è una password che si perde.
    expect(RegistroAccount.chiaveDa('kdrive', 'Tizio@Example.IT'),
        RegistroAccount.chiaveDa('kdrive', 'tizio@example.it'));
  });

  // ── Guardare ───────────────────────────────────────────────────────────

  test('lo spazio si mostra solo se il server lo dice', () async {
    final s = costruisci(
      portachiavi: {'kdrive:tizio': 'giusta'},
      spazio: () => const SpazioDav(),
    );
    await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'giusta',
        numeroKdrive: '1');
    final e = await s.guarda('kdrive:tizio');
    expect(e['ok'], isTrue, reason: '${e['errore']}');
    final sp = e['spazio'] as Map<String, dynamic>;
    expect(sp['loDice'], isFalse);
    expect(sp.containsKey('usati'), isFalse);
    expect(sp.containsKey('totale'), isFalse);
  });

  test('e quando lo dice, il totale è la somma dei suoi numeri', () async {
    final s = costruisci(
      portachiavi: {'kdrive:tizio': 'giusta'},
      spazio: () => const SpazioDav(usati: 100, liberi: 900),
    );
    await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'giusta',
        numeroKdrive: '1');
    final e = await s.guarda('kdrive:tizio');
    expect((e['spazio'] as Map)['totale'], 1000);
  });

  test('se la password è sparita dal portachiavi lo dice, e non finge',
      () async {
    final s = costruisci(portachiavi: {}, portachiaviSmemorato: true);
    await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'x', numeroKdrive: '1');
    final e = await s.guarda('kdrive:tizio');
    expect(e['ok'], isFalse);
    expect('${e['errore']}', contains('portachiavi'));
    expect(s.registro.cerca('kdrive:tizio')!.funziona, isFalse);
  });

  // ── Scollegare ─────────────────────────────────────────────────────────

  test('scollegare toglie anche la password, e lo dice chiaro sui file',
      () async {
    final s = costruisci(portachiavi: {'kdrive:tizio': 'x'});
    await s.collega(
        servizio: 'kdrive', utente: 'tizio', password: 'x', numeroKdrive: '1');
    final e = await s.scollega('kdrive:tizio');
    expect(e['ok'], isTrue);
    expect('${e['nota']}', contains('non cancella niente'));
    expect(s.registro.account, isEmpty);
    expect(comandi.any((c) => c.contains('clear')), isTrue,
        reason: 'la password è rimasta nel portachiavi');
  });

  // ── Cosa questa macchina sa fare ───────────────────────────────────────

  test('dice cosa NON può fare invece di offrirlo', () async {
    // `rclone` non c'è su questa macchina (misurato il 25 agosto 2026), e
    // senza non si monta nessuna cartella nella home. Un pulsante che porta a
    // un errore è peggio di un pulsante che manca.
    final e = await costruisci().elenco();
    final puo = e['puo'] as Map<String, dynamic>;
    expect(puo['webdav'], isTrue);
    expect(puo['montare'], isFalse);
    expect(puo['google'], isFalse);
  });

  // ── kDrive: il numero non si chiede a nessuno ──────────────────────────
  //
  // Giacomo, 25 agosto 2026: «il mio account chiede solo email e password e
  // non un codice». Il modulo chiedeva un numero che lui non aveva mai visto,
  // e senza quello non si entrava: una domanda sbagliata che si presenta come
  // un errore dell'utente.

  group('kDrive senza numero', () {
    test('con un solo archivio lo trova da sé', () async {
      final s = costruisci(dischi: [
        ['987654', 'kDrive di Giacomo']
      ]);
      final e = await s.collega(
          servizio: 'kdrive', utente: 'tizio@example.it', password: 'giusta');
      expect(e['ok'], isTrue, reason: '${e['errore']}');
      final a = s.registro.account.single;
      expect(a.url, 'https://987654.connect.kdrive.infomaniak.com');
      expect(a.nome, 'kDrive di Giacomo',
          reason: 'il nome glielo dà il server, non lo inventiamo noi');
    });

    test('con più archivi chiede quale, e non ne salva nessuno', () async {
      final s = costruisci(dischi: [
        ['1', 'Lavoro'],
        ['2', 'Casa']
      ]);
      final e = await s.collega(
          servizio: 'kdrive', utente: 'tizio', password: 'giusta');
      expect(e['ok'], isFalse);
      expect((e['scegli'] as List).length, 2);
      expect(s.registro.account, isEmpty);
      expect(comandi.any((c) => c.contains('store')), isFalse,
          reason: 'ha messo via una password per un account non ancora scelto');
    });

    test('e con nessun archivio lo dice, invece di collegare il vuoto',
        () async {
      final s = costruisci(dischi: []);
      final e = await s.collega(
          servizio: 'kdrive', utente: 'tizio', password: 'giusta');
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('nessun kDrive'));
      expect(s.registro.account, isEmpty);
    });
  });

  // ── Google ─────────────────────────────────────────────────────────────

  group('Google', () {
    test('senza chiave dell\'applicazione non si finge di poter entrare',
        () async {
      final s = costruisci();
      final e = await s.collegaGoogle((_) {});
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('chiave'));
    });

    test('la chiave sbagliata si riconosce prima di provarla', () async {
      // L'errore più comune di questa procedura è incollare la chiave
      // dell'API al posto dell'identificativo OAuth: Google risponde con un
      // errore che non spiega niente, e la colpa sembra dell'utente.
      final s = costruisci();
      final e = await s.salvaChiaveGoogle('AIzaSyQualcosa', 'segreto');
      expect(e['ok'], isFalse);
      expect('${e['errore']}', contains('googleusercontent'));
    });

    test('collegato, l\'account entra e la chiave di rinnovo va nel '
        'portachiavi', () async {
      var apertoConUrl = '';
      final s = costruisci(
          portachiavi: {
            'google-app': '123.apps.googleusercontent.com\nsegreto'
          },
          google: GoogleOAuth(
            apriPorta: () async => _PortaFinta(),
            chiedi: (metodo, url, h, corpo) async {
              if (url.contains('/token')) {
                return const RispostaWeb(
                    200,
                    '{"access_token":"AT","refresh_token":"RT",'
                    '"expires_in":3599}');
              }
              return const RispostaWeb(
                  200,
                  '{"user":{"emailAddress":"tizio@gmail.com",'
                  '"displayName":"Tizio"},'
                  '"storageQuota":{"usage":"1000","limit":"3000"}}');
            },
          ));

      final e = await s.collegaGoogle((u) => apertoConUrl = u);
      expect(e['ok'], isTrue, reason: '${e['errore']}');
      expect(apertoConUrl, contains('accounts.google.com'));
      expect(apertoConUrl, contains('code_challenge_method=S256'));
      expect(apertoConUrl, contains('drive.file'),
          reason: 'ha chiesto più permessi del necessario');

      final a = s.registro.account.single;
      expect(a.servizio, 'google');
      expect(a.utente, 'tizio@gmail.com');

      // E la cosa che conta: nel file non c'è nessuna chiave.
      final scritto = await File('${temp.path}/account.json').readAsString();
      expect(scritto, isNot(contains('RT')));
      expect(scritto, isNot(contains('segreto')));
      expect(comandi.any((c) => c.contains('store') && c.contains('google:tizio@gmail.com')),
          isTrue);
    });

    test('scollegare toglie il permesso anche dal lato di Google', () async {
      // Lasciarlo valido vorrebbe dire che nell'elenco dei permessi del suo
      // account Google resta scritto che Minerva può entrare, e non è vero.
      var revocato = '';
      final s = costruisci(
          portachiavi: {
            'google-app': '123.apps.googleusercontent.com\nsegreto',
            'google:tizio@gmail.com': 'RT',
          },
          google: GoogleOAuth(
            apriPorta: () async => _PortaFinta(),
            chiedi: (metodo, url, h, corpo) async {
              if (url.contains('/revoke')) {
                revocato = corpo ?? '';
                return const RispostaWeb(200, '{}');
              }
              return const RispostaWeb(200, '{}');
            },
          ));
      await s.init();
      s.registro.account.add(Account(
        id: 'google:tizio@gmail.com',
        servizio: 'google',
        nome: 'Google Drive',
        utente: 'tizio@gmail.com',
        url: 'https://drive.google.com',
        aggiunto: DateTime.now(),
      ));
      final e = await s.scollega('google:tizio@gmail.com');
      expect(e['ok'], isTrue);
      expect(revocato, contains('RT'));
    });

    test('lo spazio di Google: liberi è una sottrazione, non un\'invenzione',
        () async {
      final s = costruisci(
          portachiavi: {
            'google-app': '123.apps.googleusercontent.com\nsegreto',
            'google:tizio@gmail.com': 'RT',
          },
          google: GoogleOAuth(
            apriPorta: () async => _PortaFinta(),
            chiedi: (metodo, url, h, corpo) async {
              if (url.contains('/token')) {
                return const RispostaWeb(200, '{"access_token":"AT"}');
              }
              return const RispostaWeb(
                  200,
                  '{"user":{"emailAddress":"tizio@gmail.com"},'
                  '"storageQuota":{"usage":"400"}}');
            },
          ));
      await s.init();
      s.registro.account.add(Account(
        id: 'google:tizio@gmail.com',
        servizio: 'google',
        nome: 'Google Drive',
        utente: 'tizio@gmail.com',
        url: 'https://drive.google.com',
        aggiunto: DateTime.now(),
      ));
      final e = await s.guarda('google:tizio@gmail.com');
      expect(e['ok'], isTrue, reason: '${e['errore']}');
      final sp = e['spazio'] as Map<String, dynamic>;
      // Senza `limit` — cioè spazio senza limite — si dice quanto è occupato
      // e basta. Un totale dedotto sarebbe un numero inventato.
      expect(sp['usati'], 400);
      expect(sp.containsKey('liberi'), isFalse);
      expect(sp.containsKey('totale'), isFalse);
    });
  });
}

/// La porta su cui Google rimanda il codice, finta: nelle prove non si apre
/// nessuna porta vera e non si aspetta nessun browser.
class _PortaFinta implements PortaDiRitorno {
  @override
  int get numero => 41234;

  @override
  Future<RispostaConsenso> attendi(Duration quanto, String stato) async =>
      RispostaConsenso(codice: 'CODICE', errore: null);

  @override
  Future<void> chiudi() async {}
}

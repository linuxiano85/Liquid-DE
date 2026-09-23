import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:minervad/services/greetd_service.dart';

// Le prove dell'inquadramento non hanno bisogno di greetd: i byte si
// costruiscono a mano. Quelle del servizio sì, ma un greetd finto sta in
// trenta righe — e vale la pena averlo, perché il difetto che temo davvero
// (un messaggio spezzato in due letture) si vede SOLO su un socket vero.
//
// Quello che c'è da provare non è il caso facile — un messaggio corto che
// arriva tutto insieme non può sbagliarsi — ma i tre modi in cui i byte
// arrivano storti: a pezzi, appiccicati, e sbagliati.

Uint8List _telaio(Map<String, dynamic> m) => GreetdFramer.encode(m);

void main() {
  group('GreetdFramer — impacchettare', () {
    test('mette quattro byte di lunghezza in ordine nativo, poi il JSON', () {
      final b = _telaio({'type': 'create_session', 'username': 'me'});
      final dichiarata =
          ByteData.view(b.buffer, b.offsetInBytes, 4).getUint32(0, Endian.host);

      expect(dichiarata, b.length - 4);
      expect(utf8.decode(b.sublist(4)), contains('"create_session"'));
    });

    test('la lunghezza è in BYTE, non in caratteri', () {
      // «è» in UTF-8 sono due byte. Contare i caratteri farebbe dichiarare un
      // messaggio più corto di quello che è, e greetd leggerebbe un JSON
      // troncato: è l'errore classico di chi inquadra del testo.
      final b = _telaio({'type': 'x', 'd': 'perché è così'});
      final dichiarata =
          ByteData.view(b.buffer, b.offsetInBytes, 4).getUint32(0, Endian.host);

      expect(dichiarata, b.length - 4);
      expect(dichiarata, greaterThan(utf8.decode(b.sublist(4)).length - 1));
    });
  });

  group('GreetdFramer — spacchettare', () {
    test('un messaggio intero esce subito', () {
      final f = GreetdFramer();
      final fuori = f.aggiungi(_telaio({'type': 'success'}));

      expect(fuori, hasLength(1));
      expect(fuori.first['type'], 'success');
      expect(f.inAttesa, 0);
    });

    test('un messaggio spezzato NON esce finché non è completo', () {
      final f = GreetdFramer();
      final b = _telaio({
        'type': 'auth_message',
        'auth_message_type': 'secret',
        'auth_message': 'Password: ',
      });

      // Byte per byte: il caso peggiore, e quello che dimostra che non si sta
      // dando per scontato niente sulla dimensione delle letture.
      for (var i = 0; i < b.length - 1; i++) {
        expect(f.aggiungi([b[i]]), isEmpty,
            reason: 'non deve uscire niente al byte $i di ${b.length}');
      }

      final fuori = f.aggiungi([b.last]);
      expect(fuori, hasLength(1));
      expect(fuori.first['auth_message'], 'Password: ');
      expect(f.inAttesa, 0);
    });

    test('la testa spezzata a metà non manda in confusione', () {
      // Anche i quattro byte della lunghezza possono arrivare a pezzi.
      final f = GreetdFramer();
      final b = _telaio({'type': 'success'});

      expect(f.aggiungi(b.sublist(0, 2)), isEmpty);
      expect(f.inAttesa, 2);
      final fuori = f.aggiungi(b.sublist(2));
      expect(fuori, hasLength(1));
      expect(fuori.first['type'], 'success');
    });

    test('due messaggi appiccicati escono tutti e due', () {
      final f = GreetdFramer();
      final uno = _telaio({'type': 'success'});
      final due = _telaio({'type': 'error', 'error_type': 'auth_error'});

      final fuori = f.aggiungi([...uno, ...due]);

      expect(fuori, hasLength(2));
      expect(fuori[0]['type'], 'success');
      expect(fuori[1]['error_type'], 'auth_error');
      expect(f.inAttesa, 0);
    });

    test('un messaggio e mezzo: esce il primo, il resto aspetta', () {
      final f = GreetdFramer();
      final uno = _telaio({'type': 'success'});
      final due = _telaio({'type': 'success'});

      final fuori = f.aggiungi([...uno, ...due.sublist(0, 3)]);

      expect(fuori, hasLength(1));
      expect(f.inAttesa, 3);
      expect(f.aggiungi(due.sublist(3)), hasLength(1));
    });

    test('una lunghezza assurda si ferma invece di aspettare per sempre', () {
      final f = GreetdFramer();
      final b = Uint8List(8);
      ByteData.view(b.buffer).setUint32(0, 999999999, Endian.host);

      expect(() => f.aggiungi(b), throwsA(isA<GreetdProtocolError>()));
    });

    test('un JSON che non è un oggetto è un errore, non un messaggio vuoto', () {
      final f = GreetdFramer();
      final corpo = utf8.encode('"soltanto una stringa"');
      final b = Uint8List(4 + corpo.length);
      ByteData.view(b.buffer).setUint32(0, corpo.length, Endian.host);
      b.setRange(4, b.length, corpo);

      expect(() => f.aggiungi(b), throwsA(isA<GreetdProtocolError>()));
    });
  });

  provaSbagliataEGiusta();

  group('GreetdService — contro un greetd finto', () {
    late Directory tana;
    late ServerSocket server;
    late String percorso;
    late List<Map<String, dynamic>> ricevute;
    Socket? latoGreetd;

    setUp(() async {
      tana = await Directory.systemTemp.createTemp('minerva-greetd-prova');
      percorso = '${tana.path}/sock';
      ricevute = [];
      latoGreetd = null;

      server = await ServerSocket.bind(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);

      server.listen((client) {
        latoGreetd = client;
        final f = GreetdFramer();
        client.listen((pezzo) {
          for (final m in f.aggiungi(pezzo)) {
            ricevute.add(m);

            // Un greetd finto ma fedele: alla creazione della sessione chiede
            // la password, alla risposta dice di sì.
            if (m['type'] == 'create_session') {
              // Spezzato APPOSTA in due scritture: è il caso che il framer
              // deve reggere, e su un socket vero succede davvero.
              final r = GreetdFramer.encode({
                'type': 'auth_message',
                'auth_message_type': 'secret',
                'auth_message': 'Password: ',
              });
              client.add(r.sublist(0, 5));
              Future.delayed(const Duration(milliseconds: 20), () {
                client.add(r.sublist(5));
              });
            } else if (m['type'] == 'post_auth_message_response') {
              client.add(GreetdFramer.encode({'type': 'success'}));
            }
          }
        });
      });
    });

    tearDown(() async {
      await server.close();
      await tana.delete(recursive: true);
    });

    test('senza GREETD_SOCK non si connette e lo dice', () async {
      // Nell'ambiente delle prove la variabile non c'è: è esattamente la
      // condizione di un demone che gira in una sessione normale.
      expect(GreetdService.percorsoSocket, isNull);
      final s = GreetdService();
      expect(await s.connetti(), isFalse);
      expect(s.connesso, isFalse);
    });

    test('il giro completo: crea, viene chiesta la password, risponde, sì',
        () async {
      final s = _ServizioSuPercorso(percorso);
      expect(await s.connetti(), isTrue);

      final viste = <Map<String, dynamic>>[];
      s.risposte.listen(viste.add);

      await s.creaSessione('giacomo');
      await Future.delayed(const Duration(milliseconds: 120));

      expect(viste, hasLength(1));
      expect(viste.first['type'], 'auth_message');
      expect(viste.first['auth_message_type'], 'secret');

      await s.rispondi('segreto');
      await Future.delayed(const Duration(milliseconds: 80));

      expect(viste, hasLength(2));
      expect(viste.last['type'], 'success');

      expect(ricevute.map((m) => m['type']).toList(),
          ['create_session', 'post_auth_message_response']);
      expect(ricevute.first['username'], 'giacomo');
      expect(ricevute.last['response'], 'segreto');

      await s.chiudi();
    });

    test('rispondere senza risposta NON manda il campo', () async {
      // Per i messaggi informativi la pagina di manuale dice che la risposta
      // non va impostata. Mandare una stringa vuota è un'altra cosa, e PAM
      // può prenderla per una password sbagliata.
      final s = _ServizioSuPercorso(percorso);
      await s.connetti();
      await s.rispondi(null);
      await Future.delayed(const Duration(milliseconds: 60));

      expect(ricevute.last.containsKey('response'), isFalse);
      await s.chiudi();
    });

    test('se greetd muore, arriva un errore invece del silenzio', () async {
      final s = _ServizioSuPercorso(percorso);
      await s.connetti();

      final viste = <Map<String, dynamic>>[];
      s.risposte.listen(viste.add);

      // `server.close()` NON basta: smette di accettare connessioni nuove e
      // lascia vive quelle già aperte. Per provare «greetd è morto» bisogna
      // recidere la connessione vera — ed è la stessa distinzione che conta
      // sul campo: un greetd fermato lascia il greeter appeso a un socket che
      // sembra ancora buono.
      await s.creaSessione('giacomo');
      await Future.delayed(const Duration(milliseconds: 120));
      viste.clear();

      latoGreetd!.destroy();
      await Future.delayed(const Duration(milliseconds: 150));

      expect(viste, isNotEmpty,
          reason: 'la shell deve ricevere qualcosa, non restare in attesa');
      expect(viste.last['type'], 'error');
      expect(s.connesso, isFalse);
    });

    test('davanti a un socket che non esiste dice di no, non esplode',
        () async {
      final s = _ServizioSuPercorso('${tana.path}/questo-non-c-e');
      expect(await s.connetti(), isFalse);
      expect(s.connesso, isFalse);
    });
  });

  // ── Fuori da un greeter, e il registro che non si riempie ───────────────
  //
  // Il demone della sessione NON è un greeter, e non lo sarà mai: chiedergli
  // di parlare con greetd è una condizione strutturale, non un guasto. Ogni
  // richiesta però produceva tre righe di registro, e nel registro di una
  // sessione vera del 1º settembre 2026 se ne contavano **settantacinque
  // copie**: duecentoventicinque righe che dicono tutte la stessa cosa.
  //
  // Il costo non è lo spazio. È che un registro fatto per il 90% di rumore
  // non lo legge più nessuno, e il giorno che c'è un errore vero ci affoga
  // dentro. Questo progetto quel prezzo l'ha già pagato con gli errori buttati
  // in `/dev/null`.
  group('quando questo processo non è un greeter', () {
    /// Raccoglie quello che il codice stampa, senza stamparlo.
    Future<List<String>> ascoltando(Future<void> Function() cosa) async {
      final righe = <String>[];
      await runZoned(cosa,
          zoneSpecification: ZoneSpecification(
            print: (a, b, c, String r) => righe.add(r),
          ));
      return righe;
    }

    test('lo dice una volta sola, non a ogni richiesta', () async {
      final s = _SenzaGreetd();
      final righe = await ascoltando(() async {
        for (var i = 0; i < 5; i++) {
          await s.creaSessione('tizio');
        }
      });

      final avvisi =
          righe.where((r) => r.contains('non è un greeter')).length;
      expect(avvisi, 1,
          reason: 'cinque richieste, un avviso: quello che si toglie è la '
              'ripetizione, non l\'informazione.\n${righe.join("\n")}');

      final errori =
          righe.where((r) => r.contains('Nessuna connessione a greetd')).length;
      expect(errori, 0,
          reason: 'l\'errore va al CLIENT, non sul registro: chi deve '
              'saperlo è la schermata di accesso, e lo sa dalla risposta.');
    });

    test('ma il client la risposta la riceve, tutte le volte', () async {
      // È la metà che non si deve perdere insieme al rumore: la schermata di
      // accesso deve sapere che non si può entrare, o resterebbe ad aspettare
      // una risposta che non arriva — il difetto peggiore di tutti, perché
      // sembra che la macchina stia pensando.
      final s = _SenzaGreetd();
      final viste = <Map<String, dynamic>>[];
      final sub = s.risposte.listen(viste.add);
      await runZoned(() async {
        for (var i = 0; i < 3; i++) {
          await s.creaSessione('tizio');
        }
      }, zoneSpecification: ZoneSpecification(print: (a, b, c, d) {}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(viste.length, 3);
      for (final r in viste) {
        expect(r['type'], 'error');
        expect(r['description'], 'Nessuna connessione a greetd');
      }
    });
  });
}

/// Un servizio senza nessun greetd sotto: è la situazione di ogni sessione
/// normale, dove `GREETD_SOCK` non esiste.
class _SenzaGreetd extends GreetdService {
  @override
  String? get socketDaUsare => null;
}

/// Il servizio legge il percorso da `GREETD_SOCK`, che nelle prove non c'è e
/// non si può impostare (l'ambiente di un processo Dart è di sola lettura).
/// Questa sottoclasse cambia SOLO da dove arriva il percorso: tutto il resto —
/// inquadramento, lettura a pezzi, gestione degli errori — è il codice vero.
class _ServizioSuPercorso extends GreetdService {
  final String percorso;
  _ServizioSuPercorso(this.percorso);

  @override
  String? get socketDaUsare => percorso;
}

// ── Il giro completo: sbagliare, e poi indovinare ──────────────────────────
//
// Chiesto da Giacomo: «fai dei test sbagliando password e la corretta».
// La password vera non c'entra e non serve: quello che si prova è che il
// programma DISTINGUA i due casi e che dopo un rifiuto si possa riprovare —
// che è il difetto che si nasconde qui dentro. Dopo un `auth_error` greetd
// CHIUDE la sessione in configurazione: chi si limita a rispondere di nuovo
// parla nel vuoto, e la seconda password, anche giusta, non arriva a nessuno.
void provaSbagliataEGiusta() {
  group('sbagliare e poi indovinare', () {
    late Directory tana;
    late ServerSocket server;
    late String percorso;
    late List<String> giro;

    const giusta = 'parola-di-prova';

    setUp(() async {
      tana = await Directory.systemTemp.createTemp('minerva-greetd-auth');
      percorso = '${tana.path}/sock';
      giro = [];

      server = await ServerSocket.bind(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);

      server.listen((client) {
        final f = GreetdFramer();
        // greetd tiene UNA sessione in configurazione per volta.
        bool sessioneAperta = false;

        client.listen((pezzo) {
          for (final m in f.aggiungi(pezzo)) {
            switch (m['type']) {
              case 'create_session':
                sessioneAperta = true;
                giro.add('crea:${m['username']}');
                client.add(GreetdFramer.encode({
                  'type': 'auth_message',
                  'auth_message_type': 'secret',
                  'auth_message': 'Password: ',
                }));
                break;

              case 'post_auth_message_response':
                if (!sessioneAperta) {
                  // È ESATTAMENTE il caso da non far succedere: rispondere
                  // senza aver ricominciato.
                  giro.add('risposta-nel-vuoto');
                  client.add(GreetdFramer.encode({
                    'type': 'error',
                    'error_type': 'error',
                    'description': 'no session',
                  }));
                  break;
                }
                if (m['response'] == giusta) {
                  giro.add('giusta');
                  client.add(GreetdFramer.encode({'type': 'success'}));
                } else {
                  giro.add('sbagliata');
                  sessioneAperta = false; // come fa greetd davvero
                  client.add(GreetdFramer.encode({
                    'type': 'error',
                    'error_type': 'auth_error',
                    'description': 'Authentication failure',
                  }));
                }
                break;

              case 'start_session':
                giro.add('avvia:${(m['cmd'] as List).join(" ")}');
                client.add(GreetdFramer.encode({'type': 'success'}));
                break;

              case 'cancel_session':
                sessioneAperta = false;
                giro.add('annulla');
                break;
            }
          }
        });
      });
    });

    tearDown(() async {
      await server.close();
      await tana.delete(recursive: true);
    });

    test('una password sbagliata torna auth_error, la giusta torna success',
        () async {
      final s = _ServizioSuPercorso(percorso);
      await s.connetti();
      final viste = <Map<String, dynamic>>[];
      s.risposte.listen(viste.add);

      Future<void> respira() =>
          Future.delayed(const Duration(milliseconds: 90));

      // Primo tentativo: sbagliato.
      await s.creaSessione('giacomo');
      await respira();
      expect(viste.last['type'], 'auth_message');

      await s.rispondi('non-e-questa');
      await respira();
      expect(viste.last['type'], 'error');
      expect(viste.last['error_type'], 'auth_error');

      // Si RICOMINCIA, non si risponde di nuovo.
      await s.creaSessione('giacomo');
      await respira();
      expect(viste.last['type'], 'auth_message');

      await s.rispondi(giusta);
      await respira();
      expect(viste.last['type'], 'success');

      await s.avviaSessione(['sh', '-lc', '/usr/local/bin/minerva-session'], []);
      await respira();
      expect(viste.last['type'], 'success');

      expect(giro, [
        'crea:giacomo',
        'sbagliata',
        'crea:giacomo',
        'giusta',
        'avvia:sh -lc /usr/local/bin/minerva-session',
      ]);
      expect(giro, isNot(contains('risposta-nel-vuoto')));

      await s.chiudi();
    });

    test('rispondere senza ricominciare parla nel vuoto — il difetto da evitare',
        () async {
      // Non è una prova di quello che facciamo: è la dimostrazione di COSA
      // succede se ci si dimentica di ricominciare. Serve a chi legge fra un
      // anno e si chiede perché in `Greeter.qml` dopo un errore parte un
      // timer invece di riabilitare il campo.
      final s = _ServizioSuPercorso(percorso);
      await s.connetti();
      final viste = <Map<String, dynamic>>[];
      s.risposte.listen(viste.add);

      await s.creaSessione('giacomo');
      await Future.delayed(const Duration(milliseconds: 90));
      await s.rispondi('sbagliata');
      await Future.delayed(const Duration(milliseconds: 90));

      // Qui sarebbe l'errore: rispondere ancora.
      await s.rispondi(giusta);
      await Future.delayed(const Duration(milliseconds: 90));

      expect(giro, contains('risposta-nel-vuoto'));
      expect(viste.last['type'], 'error');
      expect(viste.last['error_type'], isNot('auth_error'),
          reason: 'non è la password a essere sbagliata: non c\'è più sessione');

      await s.chiudi();
    });
  });
}

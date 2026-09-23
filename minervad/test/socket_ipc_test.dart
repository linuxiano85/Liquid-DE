import 'package:test/test.dart';
import 'package:minervad/ipc/websocket_server.dart';

// L'indirizzo del canale fra demone e shell.
//
// Non è una preferenza: è quello che tiene separati i DUE Minerva che possono
// essere accesi insieme — quello della schermata di accesso, che gira come
// utente `greeter`, e quello della sessione di chi sta già lavorando. Con un
// indirizzo solo il demone del greeter non riesce ad ascoltare, la schermata
// si connette al demone dell'altro utente, quello risponde che greetd non c'è,
// e la schermata si mette in anteprima: si vede benissimo e non fa entrare
// nessuno, senza un errore da nessuna parte. È successo il 5 agosto 2026.
//
// Fino al 27 agosto 2026 l'indirizzo era una porta TCP e questa prova si
// chiamava `porta_ipc_test.dart`. Adesso è un socket Unix: il percorso
// contiene il nome della sessione, quindi due demoni non si incontrano per
// costruzione invece che per una caccia al numero libero.
//
// La regola provata sotto è la stessa di allora: davanti a un valore scritto
// male si torna al predefinito e si parte lo stesso. Una schermata di accesso
// che si rifiuta di partire perché qualcuno ha sbagliato a scrivere un
// percorso è un computer che non si apre più.
void main() {
  group('indirizzo del canale IPC', () {
    test('senza variabile è quello di sempre', () {
      final atteso = WebSocketServer.socketPredefinito();
      expect(WebSocketServer.socketDa(null), atteso);
      expect(WebSocketServer.socketDa(''), atteso);
      expect(WebSocketServer.socketDa('   '), atteso);
    });

    test('un percorso completo vince', () {
      expect(WebSocketServer.socketDa('/run/user/948/greeter.sock'),
          '/run/user/948/greeter.sock');
      expect(WebSocketServer.socketDa('  /tmp/prova.sock  '),
          '/tmp/prova.sock');
    });

    test('un valore che non è un percorso non impedisce di partire', () {
      final atteso = WebSocketServer.socketPredefinito();
      for (final scritto in ['pippo', '11432', 'ws://127.0.0.1:11432',
                             'run/user/1000/x.sock', './x.sock']) {
        expect(WebSocketServer.socketDa(scritto), atteso,
            reason: '«$scritto» deve cadere sul predefinito, non far morire '
                'il demone');
      }
    });

    // ── I 108 byte del kernel ───────────────────────────────────────────
    //
    // `sockaddr_un.sun_path` sono 108 byte in tutto. Non è un limite di Dart e
    // non dà un errore che si capisce: dà un `bind` fallito con un messaggio
    // che parla d'altro. Meglio accorgersene qui che dentro un terminale
    // d'emergenza.
    test('un percorso troppo lungo cade sul predefinito', () {
      final lungo = '/tmp/${'x' * 120}.sock';
      expect(WebSocketServer.socketDa(lungo),
          WebSocketServer.socketPredefinito());
    });

    test('il predefinito sta dove sta il file del canale', () {
      final p = WebSocketServer.socketPredefinito();
      // Percorso completo, dentro una cartella «minerva», e con dentro il nome
      // della sessione: sono le tre cose per cui due demoni non si incontrano.
      expect(p, startsWith('/'));
      expect(p, contains('minerva'));
      expect(p, endsWith('.sock'));
      // Sotto i 100 caratteri, o il limite del kernel lo prende in faccia il
      // demone vero invece di questa prova.
      expect(p.length, lessThan(100),
          reason: 'il percorso predefinito non deve avvicinarsi ai 108 byte '
              'di sun_path');
    });
  });
}

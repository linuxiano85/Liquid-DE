import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Il dialogo con `greetd`, cioè con chi verifica la password e apre la
/// sessione.
///
/// ── Perché nel demone e non nella shell ────────────────────────────────────
///
/// Non è una scelta di gusto, è un vincolo. Il protocollo di greetd inquadra
/// ogni messaggio così:
///
///     <lunghezza: intero a 32 bit, ORDINE NATIVO><JSON in UTF-8>
///
/// Quickshell 0.3 ha `Socket`, ma l'unico analizzatore concreto che offre è
/// `SplitParser`, che taglia su un delimitatore. Un prefisso binario di
/// lunghezza non si può leggere così: il byte 0x0A dentro un numero non è un
/// a-capo, e un JSON che contiene il carattere di separazione manderebbe tutto
/// fuori sincrono. Dart legge byte, quindi il dialogo sta qui e la shell chiede
/// dal solito canale.
///
/// ── Le tre cose che questo protocollo NON garantisce ───────────────────────
///
/// 1. **Un messaggio non arriva tutto insieme.** Su un socket i byte arrivano
///    a pezzi: leggere una volta sola e aspettarsi un messaggio intero
///    funziona finché il messaggio è corto, e smette il giorno in cui PAM
///    manda una frase lunga. Per questo c'è `GreetdFramer`, che accumula.
/// 2. **In un pezzo ce ne può stare più d'uno.** Stessa ragione al contrario:
///    dopo aver letto un messaggio bisogna guardare se nel buffer ce n'è già
///    un altro, e non tornare ad aspettare.
/// 3. **Quanti giri di domande servano.** La pagina di manuale è esplicita:
///    «there are no limits on the number and type of messages that may be
///    required». Niente conti su «prima l'utente, poi la password»: si
///    risponde a quello che arriva, finché arriva.
class GreetdFramer {
  final List<int> _buffer = [];

  /// Impacchetta un messaggio: quattro byte di lunghezza più il JSON.
  ///
  /// `Endian.host` e non `Endian.little`: la pagina di manuale dice «native
  /// byte order». Su questa macchina sono la stessa cosa, e scriverlo giusto
  /// costa zero — scriverlo sbagliato si scoprirebbe solo su un'altra
  /// architettura, dove nessuno andrebbe a cercarlo qui.
  static Uint8List encode(Map<String, dynamic> messaggio) {
    final corpo = utf8.encode(jsonEncode(messaggio));
    final fuori = Uint8List(4 + corpo.length);
    ByteData.view(fuori.buffer).setUint32(0, corpo.length, Endian.host);
    fuori.setRange(4, 4 + corpo.length, corpo);
    return fuori;
  }

  /// Aggiunge byte appena arrivati e restituisce i messaggi COMPLETI che ne
  /// escono — nessuno, uno, o parecchi.
  List<Map<String, dynamic>> aggiungi(List<int> pezzo) {
    _buffer.addAll(pezzo);
    final fuori = <Map<String, dynamic>>[];

    while (true) {
      if (_buffer.length < 4) break;

      final testa = Uint8List.fromList(_buffer.sublist(0, 4));
      final quanti = ByteData.view(testa.buffer).getUint32(0, Endian.host);

      // Una lunghezza assurda vuol dire che il flusso è andato fuori sincrono:
      // continuare a leggere non lo rimette a posto, aspetterebbe per sempre
      // byte che non arriveranno. Meglio dirlo forte.
      if (quanti > _limiteMessaggio) {
        throw GreetdProtocolError(
            'Messaggio dichiarato di $quanti byte: il flusso è fuori sincrono');
      }

      if (_buffer.length < 4 + quanti) break;

      final corpo = _buffer.sublist(4, 4 + quanti);
      _buffer.removeRange(0, 4 + quanti);

      final letto = jsonDecode(utf8.decode(corpo));
      if (letto is Map<String, dynamic>) {
        fuori.add(letto);
      } else {
        throw GreetdProtocolError('Messaggio che non è un oggetto JSON');
      }
    }

    return fuori;
  }

  /// Quanti byte sono rimasti in attesa del resto. Serve alle prove e a
  /// capire, leggendo un registro, se ci si è fermati a metà messaggio.
  int get inAttesa => _buffer.length;

  /// Butta via quello che era rimasto a metà.
  ///
  /// ── Perché serve (30 settembre 2026) ──────────────────────────────────
  ///
  /// Il buffer sopravviveva alla connessione. Se greetd cadeva a metà di un
  /// messaggio, i byte rimasti venivano letti come la TESTA della prima
  /// risposta della connessione nuova: provato, sei byte vecchi davanti a
  /// un messaggio intero danno «Control character in string». E con una
  /// lunghezza assurda rimasta in testa, ogni connessione successiva
  /// falliva allo stesso modo finché il demone non ripartiva — una
  /// schermata di accesso che non fa più entrare nessuno. Una connessione
  /// nuova comincia sempre da un buffer vuoto.
  void azzera() => _buffer.clear();

  /// Un messaggio di greetd è una manciata di byte. Un megabyte è già mille
  /// volte il necessario: oltre, non è un messaggio lungo, è un errore.
  static const int _limiteMessaggio = 1024 * 1024;
}

class GreetdProtocolError implements Exception {
  final String messaggio;
  const GreetdProtocolError(this.messaggio);
  @override
  String toString() => 'GreetdProtocolError: $messaggio';
}

/// Il servizio vero: apre il socket, manda le richieste, racconta le risposte.
///
/// Non interpreta niente. Le risposte di greetd (`success`, `error`,
/// `auth_message`) arrivano così come sono a chi ascolta, perché è la shell a
/// dover decidere cosa mostrare — e perché un servizio che «semplifica» un
/// protocollo con un numero di giri non prevedibile finisce per inventarsi
/// degli stati che il protocollo non ha.
class GreetdService {
  Socket? _socket;
  final GreetdFramer _framer = GreetdFramer();
  final StreamController<Map<String, dynamic>> _risposte =
      StreamController<Map<String, dynamic>>.broadcast();

  /// Le risposte di greetd, una per messaggio completo.
  Stream<Map<String, dynamic>> get risposte => _risposte.stream;

  /// Dove sta il socket. `null` se non siamo dentro un greeter: è così che si
  /// sa che questo demone non ha nessuno con cui parlare, e va detto invece di
  /// provare a connettersi a un percorso vuoto.
  static String? get percorsoSocket {
    final p = Platform.environment['GREETD_SOCK'];
    return (p == null || p.isEmpty) ? null : p;
  }

  /// Il percorso che questo servizio userà davvero.
  ///
  /// Esiste separato da `percorsoSocket` per una ragione sola: l'ambiente di
  /// un processo Dart è di sola lettura, quindi una prova non può fingere di
  /// essere dentro un greeter impostando `GREETD_SOCK`. Ridefinendo QUESTO si
  /// prova tutto il resto — inquadramento, letture a pezzi, guasti — sul
  /// codice vero, cambiando solo da dove arriva il percorso.
  String? get socketDaUsare => percorsoSocket;

  bool get connesso => _socket != null;

  /// Se abbiamo già detto che questo processo non è un greeter.
  ///
  /// ── Perché una volta sola ─────────────────────────────────────────────
  ///
  /// Perché non è un guasto: è una condizione **strutturale e permanente**.
  /// Il demone della sessione non sarà mai un greeter, e ogni volta che
  /// qualcuno gli chiede di parlare con greetd escono tre righe di registro —
  /// l'avviso, l'errore, e l'errore rimandato al client.
  ///
  /// Nel registro di una sessione vera del 1º settembre 2026 quelle tre righe
  /// comparivano **settantacinque volte**: duecentoventicinque righe che
  /// dicono la stessa cosa. Il costo non è lo spazio — è che un registro fatto
  /// per il 90% di rumore non lo legge più nessuno, e gli errori veri ci
  /// affogano dentro. Questo progetto quel prezzo l'ha già pagato: vedi gli
  /// errori buttati in `/dev/null`.
  ///
  /// Il client la risposta continua a riceverla: quello che si toglie è la
  /// ripetizione sul registro, non l'informazione.
  bool _dettoCheNonSiamoUnGreeter = false;

  /// Si connette, se non lo è già. Restituisce false se non c'è greetd.
  Future<bool> connetti() async {
    if (_socket != null) return true;

    final percorso = socketDaUsare;
    if (percorso == null) {
      if (!_dettoCheNonSiamoUnGreeter) {
        _dettoCheNonSiamoUnGreeter = true;
        print('[MINERVA][GREETD][WARN] GREETD_SOCK non è impostata: '
            'questo processo non è un greeter. Le richieste di accesso '
            'riceveranno un errore, e questa riga non si ripete.');
      }
      return false;
    }

    try {
      final s = await Socket.connect(
          InternetAddress(percorso, type: InternetAddressType.unix), 0);
      _framer.azzera();
      _socket = s;
      // Il guasto si racconta solo se riguarda il socket di ADESSO: la
      // chiusura di uno vecchio può arrivare dopo che ci si è già
      // riconnessi, e distruggerebbe la connessione buona.
      s.listen(
        _arrivati,
        onError: (e) {
          if (identical(_socket, s)) _guasto('Errore di lettura: $e');
        },
        onDone: () {
          if (identical(_socket, s)) {
            _guasto('greetd ha chiuso la connessione');
          }
        },
        cancelOnError: true,
      );
      print('[MINERVA][GREETD][OK] Connesso a $percorso');
      return true;
    } catch (e) {
      print('[MINERVA][GREETD][ERRORE] Non riesco a connettermi a $percorso: $e');
      return false;
    }
  }

  void _arrivati(List<int> pezzo) {
    try {
      for (final m in _framer.aggiungi(pezzo)) {
        _risposte.add(m);
      }
    } on GreetdProtocolError catch (e) {
      _guasto(e.messaggio);
    } catch (e) {
      _guasto('Messaggio illeggibile: $e');
    }
  }

  /// Un guasto del canale si racconta con la STESSA forma di un errore di
  /// greetd. Chi ascolta ha già il codice per mostrarlo, e soprattutto non
  /// resta ad aspettare per sempre una risposta che non arriverà: davanti a
  /// una schermata di accesso, «non succede niente» è il peggiore dei modi di
  /// fallire.
  void _guasto(String descrizione, {bool zitto = false}) {
    if (!zitto) print('[MINERVA][GREETD][ERRORE] $descrizione');
    if (!_risposte.isClosed) {
      _risposte.add({
        'type': 'error',
        'error_type': 'error',
        'description': descrizione,
      });
    }
    final s = _socket;
    _socket = null;
    s?.destroy();
    _framer.azzera();
  }

  /// L'ultimo invio messo in fila. Vedi `_manda`.
  Future<void> _coda = Future<void>.value();

  /// Manda un messaggio, uno alla volta.
  ///
  /// ── La fila (30 settembre 2026) ──────────────────────────────────────
  ///
  /// `add` + `flush` su un socket non si possono accavallare: un secondo
  /// `add` mentre il `flush` del primo è ancora in volo solleva «StreamSink
  /// is bound to a stream». Due richieste della schermata che arrivano
  /// vicine — l'annullamento e la nuova `create_session`, o la schermata
  /// che se ne va mentre la risposta è in volo — bastavano a far cadere la
  /// seconda con un'eccezione. Qui ogni invio aspetta il precedente, e un
  /// invio andato male non blocca quelli dopo.
  Future<void> _manda(Map<String, dynamic> messaggio) {
    final turno = _coda.then((_) => _mandaSubito(messaggio));
    _coda = turno.then((_) {}, onError: (Object _) {});
    return turno;
  }

  Future<void> _mandaSubito(Map<String, dynamic> messaggio) async {
    if (!await connetti()) {
      // `zitto` quando siamo fuori da un greeter: la ragione sta su
      // `_dettoCheNonSiamoUnGreeter`. Il client riceve la risposta lo stesso.
      _guasto('Nessuna connessione a greetd',
          zitto: socketDaUsare == null);
      return;
    }
    final s = _socket!;
    try {
      s.add(GreetdFramer.encode(messaggio));
      await s.flush();
    } catch (e) {
      // Si dice alla schermata con la forma di sempre, invece di lasciare
      // che l'eccezione salga fino al canale e la schermata resti in attesa.
      if (identical(_socket, s)) _guasto('Errore di scrittura: $e');
    }
  }

  /// Comincia il tentativo di accesso per un utente.
  Future<void> creaSessione(String utente) =>
      _manda({'type': 'create_session', 'username': utente});

  /// Risponde a una domanda di PAM. `null` per i messaggi che non chiedono
  /// niente (`info`, `error`): la pagina di manuale dice che vanno comunque
  /// confermati, ma senza risposta.
  /// Il `?` davanti a `risposta` toglie la voce quando è nulla, invece di
  /// metterla vuota: sono due cose diverse per PAM, e una stringa vuota può
  /// essere presa per una password sbagliata.
  Future<void> rispondi(String? risposta) => _manda({
        'type': 'post_auth_message_response',
        'response': ?risposta,
      });

  /// Chiede di aprire la sessione.
  ///
  /// ATTENZIONE, ed è la cosa meno ovvia di tutto il protocollo: la sessione
  /// parte **quando il greeter finisce**. Dopo un `success` a questa richiesta
  /// il nostro processo deve chiudersi, altrimenti si resta a guardare una
  /// schermata di accesso che ha già accettato la password.
  Future<void> avviaSessione(List<String> comando, List<String> ambiente) =>
      _manda({'type': 'start_session', 'cmd': comando, 'env': ambiente});

  /// Annulla il tentativo in corso. Va mandato anche quando si torna indietro
  /// a scegliere un altro utente: greetd tiene UNA sessione in configurazione,
  /// e cominciarne un'altra senza chiudere la prima è un errore.
  Future<void> annulla() => _manda({'type': 'cancel_session'});

  Future<void> chiudi() async {
    // Prima si dimentica il socket, poi lo si chiude: così la sua chiusura
    // non passa per `_guasto`, che scriverebbe su `_risposte` già chiuso.
    final s = _socket;
    _socket = null;
    await s?.close();
    s?.destroy();
    await _risposte.close();
  }
}

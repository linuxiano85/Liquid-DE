import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'genere.dart';
import 'rete_locale.dart';

/// Presta alla rete locale il FLUSSO dello schermo, per il tempo della
/// trasmissione.
///
/// ── In che cosa è diverso da ServizioEffimero, e perché non è lo stesso ───
///
/// `ServizioEffimero` presta **un file**, una volta, e quella è la sua
/// difesa: un percorso solo, pochi prelievi, poi si chiude. Qui non si può
/// fare niente di tutto questo, e va detto chiaramente invece di far finta:
///
///   · i file sono **molti** e cambiano nome mentre si trasmette
///     (`schermo0.ts`, `schermo1.ts`, …): un segmento nuovo al secondo;
///   · si prelevano **in continuazione**, non una volta: un televisore che
///     guarda dieci minuti fa seicento richieste;
///   · e il contenuto non è una fotografia scelta: è **tutto quello che c'è
///     sullo schermo**, password comprese, finché non si ferma.
///
/// Quindi la difesa cambia forma. Non è «poche volte»: è **chi**, **cosa** e
/// **per quanto**.
///
///  1. **Chi** — l'indirizzo comincia con ventiquattro byte casuali presi dal
///     generatore sicuro del sistema. Chi non l'ha ricevuto non lo indovina,
///     e senza di quello ogni richiesta è un no secco.
///  2. **Cosa** — si servono SOLO i nomi che questo servizio ha generato:
///     `schermo.m3u8` e `schermoN.ts`. Nessun percorso relativo, nessun
///     `..`, nessuna cartella. Non è una lista di divieti (che si aggira):
///     è una lista di permessi, che è l'unica che tiene.
///  3. **Dove** — solo sulla scheda di rete che parla col televisore, mai su
///     tutte (vedi `ReteLocale`).
///  4. **Per quanto** — la trasmissione ha una sveglia. Anche se chi l'ha
///     accesa se ne dimentica — la finestra che si chiude, il programma che
///     cade — questo non resta su a mostrare lo schermo di casa.
class ServizioFlusso {
  /// La cartella dove `minerva-specchio` scrive i segmenti. Vuota in modo
  /// [diretto], dove non si scrive niente da nessuna parte.
  final Directory cartella;

  /// ── Due forme, perché i televisori non sono d'accordo ────────────────
  ///
  /// **HLS** (`diretto: false`) è una lista e dei pezzi da un secondo: è
  /// quello che vuole un Chromecast, il cui lettore riceve l'indirizzo di una
  /// playlist e va a prendersi i segmenti. Costa circa tre secondi di ritardo
  /// e scrive i pezzi su disco (in RAM) mentre va.
  ///
  /// **Diretto** (`diretto: true`) è un flusso MPEG-TS che comincia a versare
  /// appena qualcuno apre l'indirizzo. È quello che vuole un apparecchio
  /// DLNA: **un Samsung non sa leggere un `.m3u8`** — riceverebbe la lista e
  /// non ne caverebbe niente, senza dire perché. In cambio il ritardo scende
  /// a uno o due secondi e **non si scrive un solo byte su disco**: i
  /// fotogrammi dello schermo esistono solo dentro il tubo, e muoiono con lui.
  final bool diretto;

  /// Il comando che produce il flusso, in modo [diretto]. Si può sostituire:
  /// serve a provare che quando la conduttura muore il servizio se ne accorge.
  final String comando;

  /// Gli argomenti da dare a [comando] dopo il verbo `flusso`.
  final List<String> argomenti;

  /// Per quanto vive al massimo, anche se nessuno lo chiude.
  ///
  /// Tre ore e non dieci minuti come per una fotografia: un film è lungo. Ma
  /// una sveglia c'è comunque, ed è deliberato — «finché non lo spegni» qui
  /// vorrebbe dire «per sempre», e il contenuto è lo schermo.
  final Duration durata;

  final int porta;

  /// La stessa porta del prestito di un file: il firewall ne apre una sola
  /// (`minerva-radice trasmetti-apri`), e se ne trasmette una per volta.
  static const portaPredefinita = 8010;

  /// I soli nomi che escono da qui. Generati da ffmpeg, e nient'altro passa.
  static final RegExp _ammessi = RegExp(r'^schermo(\.m3u8|\d+\.ts)$');

  /// In modo diretto ce n'è uno solo, e non è un file: è un rubinetto.
  static const _nomeDiretto = 'schermo.ts';

  /// La conduttura viva, in modo diretto. Una sola: un televisore che si
  /// ricollega deve trovare un flusso nuovo, non accodarsi al vecchio.
  Process? _rubinetto;

  HttpServer? _server;

  /// Il socket in ascolto, che qui apriamo NOI invece di lasciarlo aprire a
  /// `HttpServer.bind`. Serve per due ragioni: mettergli addosso la coda
  /// corta (vedi `_ZoccoloACodaCorta`), e perché `HttpServer.listenOn` non
  /// diventa il proprietario di quello che gli si dà — chiuderlo non chiude
  /// il socket, e la porta resterebbe occupata fino alla morte del demone.
  ServerSocket? _zoccolo;

  Timer? _sveglia;
  late final String _chiave;
  int _richieste = 0;

  ServizioFlusso({
    required this.cartella,
    this.durata = const Duration(hours: 3),
    this.porta = portaPredefinita,
    this.diretto = false,
    String? comando,
    this.argomenti = const [],
  })  : comando = comando ??
            (Platform.environment['MINERVA_SPECCHIO'] ?? 'minerva-specchio') {
    // `Random.secure()` e non `Random()`: il secondo è prevedibile da chi
    // conosce l'ora di avvio, e qui l'indirizzo È la serratura.
    final r = Random.secure();
    _chiave = List<int>.generate(24, (_) => r.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// L'indirizzo da dare al televisore, o `null` se non è aperto.
  String? get indirizzo => _server == null
      ? null
      : 'http://${_server!.address.address}:${_server!.port}'
          '/$_chiave/${diretto ? _nomeDiretto : 'schermo.m3u8'}';

  /// Il tipo che accompagna l'indirizzo, per chi lo deve annunciare.
  String get tipo => diretto ? 'video/mp2t' : 'application/x-mpegURL';

  bool get aperto => _server != null;

  /// Quante richieste sono state servite: è il modo di sapere se il
  /// televisore sta davvero guardando, o se ha detto sì e poi niente.
  int get richieste => _richieste;

  Future<String> apri({required String versoIl}) async {
    final mio = await ReteLocale.indirizzoVerso(versoIl);
    ServerSocket z;
    try {
      z = await ServerSocket.bind(mio, porta);
    } on SocketException {
      // La porta preferita è occupata: meglio una trasmissione che forse il
      // firewall ferma, che nessuna trasmissione affatto.
      z = await ServerSocket.bind(mio, 0);
    }
    _zoccolo = z;
    final s = HttpServer.listenOn(
        diretto ? _ZoccoloACodaCorta(z, codaInvio) : z);
    _server = s;
    s.listen(_richiesta, onError: (_) => chiudi());
    _sveglia = Timer(durata, chiudi);
    return indirizzo!;
  }

  Future<void> chiudi() async {
    _sveglia?.cancel();
    _sveglia = null;
    await _chiudiRubinetto();
    final s = _server;
    _server = null;
    await s?.close(force: true);
    // E poi il socket, che è nostro: `listenOn` non lo possiede.
    final z = _zoccolo;
    _zoccolo = null;
    try {
      await z?.close();
    } catch (_) {}
  }

  Future<void> _chiudiRubinetto() async {
    final r = _rubinetto;
    _rubinetto = null;
    if (r == null) return;
    // SIGTERM e non SIGKILL: lo script ha un `trap` che ferma cattura e
    // ffmpeg. Con SIGKILL resterebbero due processi vivi a leggere lo
    // schermo, e la spia direbbe «spento».
    r.kill(ProcessSignal.sigterm);
    try {
      await r.exitCode.timeout(const Duration(seconds: 6));
    } on TimeoutException {
      r.kill(ProcessSignal.sigkill);
    } catch (_) {}
  }

  Future<void> _richiesta(HttpRequest r) async {
    // ── La lista dei permessi, non quella dei divieti ────────────────────
    //
    // Il percorso deve essere ESATTAMENTE `/<chiave>/<nome ammesso>`: due
    // pezzi, il primo la chiave, il secondo un nome che questo servizio sa di
    // aver generato. Un percorso con dentro `..`, o una sottocartella, o un
    // nome qualunque, non arriva nemmeno a toccare il disco — non perché lo
    // vietiamo, ma perché non lo permettiamo.
    final pezzi = r.uri.pathSegments;
    final metodo = r.method;
    final ok = (metodo == 'GET' || metodo == 'HEAD') &&
        pezzi.length == 2 &&
        pezzi[0] == _chiave &&
        (diretto ? pezzi[1] == _nomeDiretto : _ammessi.hasMatch(pezzi[1]));
    if (!ok) {
      r.response.statusCode = HttpStatus.notFound;
      await r.response.close();
      return;
    }

    if (diretto) {
      await _versa(r, metodo);
      return;
    }

    final f = File('${cartella.path}/${pezzi[1]}');
    if (!await f.exists()) {
      // Succede, ed è normale: il televisore chiede un segmento che ffmpeg ha
      // già cancellato (la finestra scorre) o non ha ancora scritto.
      r.response.statusCode = HttpStatus.notFound;
      await r.response.close();
      return;
    }

    _richieste++;
    try {
      final lista = pezzi[1].endsWith('.m3u8');
      r.response.headers.contentType = ContentType.parse(lista
          ? 'application/vnd.apple.mpegurl'
          : 'video/mp2t');
      r.response.headers.contentLength = await f.length();
      // La lista cambia ogni secondo: una copia in memoria vorrebbe dire un
      // televisore fermo sull'immagine di dieci secondi fa. I segmenti invece
      // non cambiano mai, ma non ha senso conservarli: fra un minuto non
      // esistono più.
      r.response.headers.set('Cache-Control', 'no-store');
      // Perché un televisore possa saltare indietro di qualche secondo senza
      // riscaricare tutto.
      r.response.headers.set('Accept-Ranges', 'none');
      if (metodo == 'HEAD') {
        await r.response.close();
        return;
      }
      await r.response.addStream(f.openRead());
    } catch (_) {
      // Il televisore che chiude a metà segmento non è un errore da gridare:
      // succede a ogni cambio di segmento e a ogni pausa.
    } finally {
      try {
        await r.response.close();
      } catch (_) {}
    }
  }

  /// Apre il rubinetto: la conduttura parte adesso e versa nella risposta.
  ///
  /// ── Perché si accende alla richiesta e non prima ─────────────────────
  ///
  /// Perché così **lo schermo si legge solo mentre qualcuno lo guarda**. Fra
  /// il momento in cui si dice al televisore «ecco l'indirizzo» e il momento
  /// in cui lui lo apre passa un secondo o due: accendere prima vorrebbe dire
  /// comprimere lo schermo per un secondo a vuoto, e — se il televisore non
  /// venisse mai — per sempre.
  Future<void> _versa(HttpRequest r, String metodo) async {
    // ── Non accumulare, versare ──────────────────────────────────────────
    //
    // Dart tiene in memoria quello che si scrive in una risposta e lo manda a
    // blocchi: è la cosa giusta per un file, ed è ritardo puro per una
    // trasmissione dal vivo. Con l'accumulo acceso il televisore non riceve
    // niente finché non si sono raccolti abbastanza byte — e su uno schermo
    // fermo, che comprime in pochissimo, quel «finché» può essere parecchi
    // secondi. Trovato da una prova che scadeva senza ricevere niente.
    r.response.bufferOutput = false;
    r.response.headers.contentType = ContentType.parse('video/mp2t');
    // Niente `Content-Length`: non si sa quanto durerà, e dichiararlo
    // sbagliato è peggio che tacerlo.
    r.response.headers.set('Cache-Control', 'no-store');
    // Su un flusso dal vivo non si salta da nessuna parte: non c'è un byte
    // «indietro» in una cosa che sta succedendo adesso.
    r.response.headers.set(HttpHeaders.acceptRangesHeader, 'none');
    r.response.headers.set('transferMode.dlna.org',
        Genere.flusso.modoTrasferimento);
    r.response.headers.set('contentFeatures.dlna.org',
        Genere.flusso.caratteristiche);

    if (metodo == 'HEAD') {
      // Un renderer DLNA manda una HEAD prima di accettare l'indirizzo. Non
      // deve accendere niente: chiede solo se la roba esiste.
      await r.response.close();
      return;
    }

    // Uno solo alla volta. Un televisore che si ricollega — e succede: cambia
    // ingresso, si riaccende — deve trovare un flusso NUOVO. Accodarsi al
    // vecchio vorrebbe dire ricevere video che comincia in mezzo a un
    // fotogramma e non partire mai.
    await _chiudiRubinetto();

    Process p;
    try {
      p = await Process.start(comando, ['flusso', ...argomenti]);
    } catch (e) {
      r.response.statusCode = HttpStatus.internalServerError;
      await r.response.close();
      return;
    }
    _rubinetto = p;
    _richieste++;

    // Le lamentele della conduttura non si buttano: senza, «non parte» non ha
    // nessuna spiegazione.
    final lamentele = StringBuffer();
    p.stderr.transform(const SystemEncoding().decoder).listen(lamentele.write,
        onError: (_) {});

    try {
      await r.response.addStream(p.stdout);
    } catch (_) {
      // Il televisore che chiude è il modo normale di finire, non un errore:
      // succede a ogni cambio di canale.
    } finally {
      // Chiuso il collegamento, si spegne la conduttura: non ha più nessuno
      // per cui leggere lo schermo.
      if (identical(_rubinetto, p)) await _chiudiRubinetto();
      try {
        await r.response.close();
      } catch (_) {}
    }
  }
}

/// Quanti byte può tenere in coda il nucleo per il collegamento del flusso.
///
/// ── Il difetto che questa riga toglie ────────────────────────────────────
///
/// Misurato il 4 settembre 2026, su una trasmissione vera verso il televisore
/// della cucina: `ss` diceva **2,5 MB fermi nella coda di invio**. Non erano
/// «in viaggio»: erano byte già usciti da ffmpeg, ancora sul nostro computer,
/// che il televisore non aveva ancora chiesto. A 6,8 Mbit/s sono **tre secondi
/// e mezzo di ritardo**, prodotti da noi, prima ancora che la rete c'entri.
///
/// Nascono all'avvio: nel primo secondo ffmpeg produce a raffica mentre il
/// televisore sta ancora decidendo, il nucleo accetta tutto (la coda si
/// autoregola fino a qualche megabyte), e da quel momento in poi non si
/// svuota più — televisore e compressore vanno alla stessa velocità, quindi
/// quel che si è accumulato resta accumulato per sempre.
///
/// Con la coda corta il nucleo smette di accettare quasi subito, e il rifiuto
/// risale tutta la catena: Dart mette in pausa la lettura, la pipe di ffmpeg
/// si riempie, `minerva-cattura` si ferma sulla scrittura e **salta dei
/// fotogrammi** invece di accodarli. È la cosa giusta per uno specchio: di uno
/// schermo interessa com'è ADESSO, non com'era tre secondi fa.
///
/// 128 KB (che il nucleo raddoppia a 256) sono circa 0,3 s a 6,8 Mbit/s, e
/// restano otto volte il prodotto banda-ritardo del collegamento misurato
/// (6 Mbit/s × 40 ms ≈ 30 KB): non si perde velocità, si perde solo la scorta.
///
/// ⚠ Va insieme a `-use_fps_mode passthrough` e all'orologio vero in
/// `minerva-specchio`: saltare fotogrammi con gli orari finti di `rawvideo`
/// farebbe rallentare il tempo del flusso, che è il difetto peggiore.
const int codaInvio = 128 * 1024;

/// `SO_SNDBUF` su Linux. Dart non ha una costante per le opzioni del socket
/// oltre a quelle che usa lei, e il numero è quello di `<asm-generic/socket.h>`.
const int _soSndbuf = 7;

/// Un socket in ascolto che mette la coda corta a ogni collegamento accettato.
///
/// Esiste perché `HttpServer` non dà nessun modo di toccare i socket che
/// accetta: `HttpRequest` espone `connectionInfo`, che dice chi è collegato ma
/// non permette di parlargli. `HttpServer.listenOn` invece prende un
/// `ServerSocket` qualunque — e un `ServerSocket` è, prima di tutto, un flusso
/// di socket accettati. Quindi basta essere quel flusso.
class _ZoccoloACodaCorta extends Stream<Socket> implements ServerSocket {
  _ZoccoloACodaCorta(this._vero, this._byte);

  final ServerSocket _vero;
  final int _byte;

  @override
  StreamSubscription<Socket> listen(void Function(Socket)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _vero.map(_stringi).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  Socket _stringi(Socket c) {
    try {
      // ── Niente Nagle ─────────────────────────────────────────────────
      //
      // L'algoritmo di Nagle tiene indietro un pezzetto di dati finché non
      // arriva la conferma del precedente: serve a non riempire la rete di
      // pacchetti quasi vuoti, e su una trasmissione dal vivo è ritardo
      // aggiunto a ogni scrittura. `ffmpeg` con `-flush_packets 1` scrive
      // pezzetti apposta, per non farceli aspettare: sarebbe assurdo
      // rimetterli in coda qui.
      c.setOption(SocketOption.tcpNoDelay, true);
      c.setRawOption(RawSocketOption.fromInt(
          RawSocketOption.levelSocket, _soSndbuf, _byte));
    } catch (_) {
      // Un sistema che non conosce questa opzione trasmette come prima, col
      // suo ritardo: peggio di così, non è un motivo per non trasmettere.
    }
    return c;
  }

  @override
  InternetAddress get address => _vero.address;

  @override
  int get port => _vero.port;

  @override
  Future<ServerSocket> close() async {
    await _vero.close();
    return this;
  }
}

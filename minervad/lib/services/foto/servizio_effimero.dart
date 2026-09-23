import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'genere.dart';
import 'rete_locale.dart';

/// Presta UN file alla rete locale, per il tempo di farlo vedere.
///
/// ── Perché serve, e perché fa paura ───────────────────────────────────────
///
/// Un Chromecast non riceve la fotografia: se la va a **prendere**. Gli si dà
/// un indirizzo e lui lo scarica. Quindi per mostrargli una foto bisogna
/// aprire un servizio HTTP su questo computer, raggiungibile dalla rete di
/// casa — e un servizio che pubblica le fotografie di qualcuno sulla rete è
/// precisamente il difetto che non si vuole scrivere per distrazione.
///
/// Le cinque regole qui sotto sono la ragione per cui questo file esiste da
/// solo invece di essere dieci righe dentro il resto.
///
///  1. **Un file per volta, mai una cartella.** Non c'è una radice da servire:
///     c'è un file, e ogni altra richiesta è un no.
///  2. **L'indirizzo è lungo e casuale.** Ventiquattro byte dal generatore
///     sicuro del sistema: chi non l'ha ricevuto non lo indovina.
///  3. **Vive quanto la trasmissione.** Si apre quando si comincia e si chiude
///     quando si finisce, e comunque da sé dopo `durata`.
///  4. **Un solo prelievo basta**, ma se ne concedono pochi: un televisore può
///     riprovare, e negare il secondo tentativo vorrebbe dire una fotografia
///     che non compare senza motivo.
///  5. **Solo la rete locale.** Si lega all'indirizzo con cui questo computer
///     parla col televisore, non a tutti — così non compare su un'altra rete
///     a cui il portatile fosse attaccato insieme.
class ServizioEffimero {
  final File file;
  final String tipo;

  /// Dopo quanto SILENZIO si spegne da solo.
  ///
  /// ── Perché silenzio, e non «da quando si è acceso» ────────────────────
  ///
  /// Fino al 4 settembre 2026 questa era una scadenza secca: dieci minuti
  /// dall'apertura e via. Per una fotografia va benissimo — il televisore la
  /// scarica in un secondo e poi non chiede più niente. Per un **film** è un
  /// difetto grosso e ovvio: la sveglia suonava a metà visione e lo schermo
  /// diventava nero, senza che nessuno avesse fatto niente di male.
  ///
  /// Adesso il contatore si azzera a ogni richiesta servita. Un film di due
  /// ore tiene aperto il servizio perché lo sta *usando*; un televisore
  /// spento smette di chiedere e il servizio si chiude da sé. È la stessa
  /// garanzia di prima — «non resta su per sempre» — ma legata a chi guarda
  /// invece che all'orologio.
  final Duration durata;

  /// Quante volte si lascia prelevare **da capo**.
  ///
  /// Conta solo le richieste che cominciano dal byte zero, cioè «qualcuno
  /// vuole tutto il file dall'inizio». Un salto avanti in un film è un
  /// intervallo che comincia da un'altra parte e non consuma niente: contarlo
  /// vorrebbe dire che spostarsi tre volte nel film chiude il servizio.
  final int prelieviMassimi;

  /// Il genere di quello che si sta prestando, dedotto dal tipo. Decide le
  /// intestazioni DLNA e, in mancanza di indicazioni, quanti prelievi
  /// concedere.
  late final Genere genere = Genere.di(tipo);

  /// Su quale porta si mette, o `0` per «una qualunque libera».
  ///
  /// ── Perché una porta FISSA, contro ogni istinto ──────────────────────
  ///
  /// Una porta a caso a ogni trasmissione sarebbe più difficile da indovinare,
  /// e infatti è stata la prima scelta. Ma su questa macchina c'è `ufw`
  /// acceso, e un firewall non sa permettere «la porta che sceglierà fra un
  /// minuto»: o si aprono diecimila porte, o se ne apre una.
  ///
  /// Trovato guardando, il 30 agosto 2026: il televisore accettava la
  /// fotografia (`MEDIA_STATUS`), la schermata di Chromecast spariva, e
  /// restava **schermo nero** — perché il televisore veniva a prendersi il
  /// file e il firewall lo respingeva. Nessun errore da nessuna parte: il
  /// lettore aveva detto sì, e il no arrivava dopo, in silenzio.
  ///
  /// La serratura resta comunque l'indirizzo — ventiquattro byte casuali — e
  /// la porta aperta serve solo alla rete locale. Una porta nota senza la
  /// chiave non dà niente: tutte le richieste che non hanno quell'indirizzo
  /// esatto ricevono un no.
  final int porta;

  HttpServer? _server;
  Timer? _sveglia;
  int _prelievi = 0;
  late final String _chiave;

  /// La porta che Minerva usa per prestare una fotografia a un televisore.
  ///
  /// Un numero alto e poco frequentato, scelto una volta e scritto qui perché
  /// deve stare in tre posti: qui, nella regola del firewall, e nella pagina
  /// delle Impostazioni che la propone.
  static const portaPredefinita = 8010;

  ServizioEffimero({
    required this.file,
    this.tipo = 'image/jpeg',
    this.durata = const Duration(minutes: 10),
    int? prelieviMassimi,
    this.porta = portaPredefinita,
  })  :
        // Quattro per una fotografia: la si prende una volta, e le altre tre
        // sono per il televisore che ricontrolla. Ventiquattro per un film o
        // un brano: certi lettori aprono e richiudono il collegamento più
        // volte mentre partono, e quattro finiscono prima che cominci.
        prelieviMassimi = prelieviMassimi ??
            (Genere.di(tipo) == Genere.foto ? 4 : 24) {
    // `Random.secure()` e non `Random()`: il secondo è prevedibile da chi
    // conosce l'ora di avvio, e qui l'indirizzo È la serratura.
    final r = Random.secure();
    final byte = List<int>.generate(24, (_) => r.nextInt(256));
    _chiave = byte
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// L'indirizzo da dare al televisore, o `null` se non è aperto.
  String? get indirizzo => _server == null
      ? null
      : 'http://${_server!.address.address}:${_server!.port}/$_chiave';

  bool get aperto => _server != null;

  /// Apre il servizio. `versoIl` è l'indirizzo del televisore: serve a
  /// scegliere con quale scheda di rete farsi raggiungere.
  Future<String> apri({required String versoIl}) async {
    if (!await file.exists()) {
      throw ArgumentError('la fotografia non c\'è: ${file.path}');
    }
    final mio = await _mioIndirizzoVerso(versoIl);
    // Se la porta preferita è occupata — un'altra trasmissione, un altro
    // programma — si ripiega su una qualunque: meglio una trasmissione che
    // forse il firewall ferma, che nessuna trasmissione affatto.
    HttpServer s;
    try {
      s = await HttpServer.bind(mio, porta);
    } on SocketException {
      s = await HttpServer.bind(mio, 0);
    }
    _server = s;
    s.listen(_richiesta, onError: (_) => chiudi());

    // La sveglia: anche se chi l'ha aperto si dimentica di chiudere — la
    // finestra che si spegne, il programma che cade — questo non resta su.
    _sveglia = Timer(durata, chiudi);
    return indirizzo!;
  }

  Future<void> chiudi() async {
    _sveglia?.cancel();
    _sveglia = null;
    final s = _server;
    _server = null;
    await s?.close(force: true);
  }

  /// Rimanda la sveglia: qualcuno sta ancora guardando.
  void _rinviaLaSveglia() {
    if (_server == null) return;
    _sveglia?.cancel();
    _sveglia = Timer(durata, chiudi);
  }

  Future<void> _richiesta(HttpRequest r) async {
    // ── Ogni cosa che non è ESATTAMENTE quel file è un no ────────────────
    //
    // Non un 404 gentile con una spiegazione: un no e basta. Chi bussa qui
    // senza l'indirizzo giusto non deve nemmeno sapere che cosa c'è.
    // ── E «GET» da solo non basta: prima arriva una HEAD ─────────────────
    //
    // Trovato il 3 settembre 2026, provando verso il televisore della cucina.
    // Un renderer DLNA, prima di accettare `SetAVTransportURI`, manda una
    // **HEAD** per vedere che la risorsa esista davvero. Qui riceveva 404 —
    // perché si accettava solo `GET` — e il televisore rispondeva
    // «Resource not found», che è vero e indica il posto sbagliato: sembra un
    // problema di rete o di firewall, e invece eravamo noi a dire di no.
    //
    // Ci sono volute tre prove per separarlo dal firewall: la stessa
    // fotografia, servita da un servizio che rispondeva a QUALUNQUE metodo,
    // veniva accettata al primo colpo.
    final metodo = r.method;
    final suaVolta = metodo == 'GET' || metodo == 'HEAD';
    final giusta = suaVolta && r.uri.path == '/$_chiave';
    if (!giusta) {
      r.response.statusCode = HttpStatus.notFound;
      await r.response.close();
      return;
    }

    final lunghezza = await file.length();

    // ── L'intervallo, che fino al 4 settembre 2026 si prometteva e basta ──
    //
    // `contentFeatures.dlna.org` dichiara `DLNA.ORG_OP=01`, cioè «so
    // consegnare a partire da un byte qualunque». Non era vero: si mandava
    // sempre tutto dal principio, ignorando l'intestazione `Range`. Su una
    // fotografia non si notava; su un film vuol dire non potersi spostare, e
    // su certi lettori vuol dire non partire affatto.
    final Intervallo? voluto;
    try {
      voluto = Intervallo.leggi(r.headers.value(HttpHeaders.rangeHeader),
          lunghezza);
    } on RangeError {
      // Un intervallo che sta fuori dal file ha una risposta sua nella
      // specifica, e non è un 404: il televisore deve sapere quanto è lungo
      // per poter richiedere bene.
      r.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      r.response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes */$lunghezza');
      await r.response.close();
      return;
    }

    // ── La quota, che conta gli inizi e non le richieste ─────────────────
    //
    // Una HEAD non porta via niente, e un salto avanti nel film nemmeno: è
    // un pezzo di una visione già cominciata. Contarli vorrebbe dire che un
    // televisore che controlla due volte, o che si sposta tre volte, esaurisce
    // da solo il permesso di guardare.
    final daCapo = metodo == 'GET' && (voluto == null || voluto.da == 0);
    if (daCapo && _prelievi >= prelieviMassimi) {
      r.response.statusCode = HttpStatus.notFound;
      await r.response.close();
      return;
    }
    if (daCapo) _prelievi++;
    _rinviaLaSveglia();

    try {
      r.response.headers.contentType = ContentType.parse(tipo);
      // Niente cache: la fotografia dopo avrà un indirizzo suo, e un
      // televisore che tiene in memoria la precedente mostrerebbe quella.
      r.response.headers.set('Cache-Control', 'no-store');
      // «So consegnare per intervalli» — e adesso lo dice perché è vero.
      r.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      // Le due intestazioni che un apparecchio DLNA si aspetta. Non sono
      // obbligatorie per tutti, e alcuni senza non scaricano: costano due
      // righe e tolgono di mezzo una famiglia di «non funziona e non si sa
      // perché». I valori vengono dal genere: una fotografia si SCARICA
      // (`Interactive`), un film si guarda MENTRE arriva (`Streaming`), ed è
      // la differenza fra cominciare subito e aspettare tre gigabyte.
      r.response.headers.set('transferMode.dlna.org', genere.modoTrasferimento);
      r.response.headers.set('contentFeatures.dlna.org', genere.caratteristiche);

      if (voluto == null) {
        r.response.headers.contentLength = lunghezza;
        if (metodo == 'HEAD') {
          await r.response.close();
          return;
        }
        await r.response.addStream(file.openRead());
      } else {
        r.response.statusCode = HttpStatus.partialContent;
        r.response.headers.set(HttpHeaders.contentRangeHeader,
            'bytes ${voluto.da}-${voluto.a}/$lunghezza');
        r.response.headers.contentLength = voluto.quanti;
        if (metodo == 'HEAD') {
          await r.response.close();
          return;
        }
        // `openRead` esclude l'ultimo byte, l'intervallo HTTP lo comprende:
        // il `+ 1` non è una svista ed è l'errore classico di questo codice —
        // senza, ogni pezzo arriva monco di un byte e il film si ferma alla
        // fine del primo segmento.
        await r.response.addStream(file.openRead(voluto.da, voluto.a + 1));
      }
    } catch (_) {
      // Il televisore che chiude a metà scaricamento non è un errore da
      // gridare: succede quando si passa alla foto dopo, e a ogni salto
      // avanti in un film.
    } finally {
      try {
        await r.response.close();
      } catch (_) {}
    }
  }

  /// Con quale indirizzo questo computer si fa vedere dal televisore.
  ///
  /// Il conto — e la ragione per cui NON è `0.0.0.0` — stanno in
  /// `rete_locale.dart`, perché adesso serve anche al servizio che presta il
  /// flusso dello schermo, e due copie sarebbero due cose che divergono.
  static Future<InternetAddress> _mioIndirizzoVerso(String versoIl) =>
      ReteLocale.indirizzoVerso(versoIl);
}

/// Un pezzo di file chiesto con l'intestazione `Range`.
///
/// Sta fuori dalla classe perché è l'unico pezzo di questo file che si può
/// provare senza aprire un socket: gli si dà una riga di testo e dice due
/// numeri. Ed è il pezzo dove sbagliare costa di più — un byte in meno per
/// intervallo e il film si ferma senza dire perché.
class Intervallo {
  /// Il primo byte, compreso.
  final int da;

  /// L'ultimo byte, **compreso** — come vuole HTTP, e al contrario di
  /// `openRead`, che esclude l'ultimo.
  final int a;

  const Intervallo(this.da, this.a);

  int get quanti => a - da + 1;

  /// Legge l'intestazione. `null` se non c'è (o se non la capiamo: allora si
  /// manda tutto, che è la risposta giusta e non un errore).
  ///
  /// Lancia `RangeError` se l'intervallo è **fuori dal file**: quello ha una
  /// risposta sua nella specifica (416), e va distinta da «non l'ho capita».
  static Intervallo? leggi(String? intestazione, int lunghezza) {
    if (intestazione == null) return null;
    final t = intestazione.trim().toLowerCase();
    if (!t.startsWith('bytes=')) return null;
    final pezzi = t.substring(6).split(',');
    // Più intervalli in una richiesta sola è legale e nessun televisore lo
    // fa: si serve il primo, che è quello che fanno anche i server veri.
    final uno = pezzi.first.trim();
    final trattino = uno.indexOf('-');
    if (trattino < 0) return null;
    final testa = uno.substring(0, trattino).trim();
    final coda = uno.substring(trattino + 1).trim();

    if (testa.isEmpty) {
      // `bytes=-500` vuol dire «gli ultimi 500 byte», non «dal byte 0 al 500».
      // È la forma che si legge al contrario, ed è il secondo errore classico.
      final quanti = int.tryParse(coda);
      if (quanti == null || quanti <= 0) return null;
      if (lunghezza == 0) throw RangeError('file vuoto');
      final da = quanti >= lunghezza ? 0 : lunghezza - quanti;
      return Intervallo(da, lunghezza - 1);
    }

    final da = int.tryParse(testa);
    if (da == null || da < 0) return null;
    if (da >= lunghezza) throw RangeError('oltre la fine');
    if (coda.isEmpty) return Intervallo(da, lunghezza - 1);
    final a = int.tryParse(coda);
    if (a == null || a < da) return null;
    // Chiedere oltre la fine non è un errore: si dà quello che c'è.
    return Intervallo(da, a >= lunghezza ? lunghezza - 1 : a);
  }
}

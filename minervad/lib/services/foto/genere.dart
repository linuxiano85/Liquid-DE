/// Che genere di cosa stiamo mandando a un televisore, e come si dice.
///
/// ── Perché un file per una domanda sola ───────────────────────────────────
///
/// Perché la stessa domanda — «è una foto, un film o della musica?» — se la
/// fanno in quattro posti che non si parlano, e ognuno la risponde in una
/// lingua diversa:
///
///   · `dlna.dart`             una classe UPnP (`object.item.videoItem`)
///   · `castv2.dart`           un numero (`metadataType: 1`)
///   · `servizio_effimero.dart` due intestazioni HTTP di DLNA
///   · `trasmetti_service.dart` un messaggio di rifiuto da leggere
///
/// Quattro traduzioni della stessa cosa, sparse. Il giorno che si aggiunge un
/// genere, tre si aggiornano e una no — ed è il tipo di difetto che non dà
/// errore: il televisore mostra nero, o la cornice da album fotografico
/// attorno a un film.
///
/// ── E perché era già sbagliato ────────────────────────────────────────────
///
/// Fino al 4 settembre 2026 `dlna.dart` scriveva
/// `object.item.imageItem.photo` per **ogni** trasmissione. Anche per lo
/// schermo trasmesso dal vivo, che è un flusso HLS: lo annunciavamo come una
/// fotografia. Funzionava per fortuna, non per costruzione — molti apparecchi
/// (i Samsung fra questi) confrontano la classe dichiarata con il
/// `protocolInfo` e rifiutano quando non tornano.
library;

/// I generi che sappiamo mandare.
enum Genere {
  foto,
  video,
  musica,

  /// Un flusso dal vivo senza inizio né fine: lo schermo trasmesso.
  /// Non è «video» perché non ci si può spostare dentro, e dirlo cambia
  /// quello che il televisore fa vedere e quello che si aspetta.
  flusso,

  /// Qualcosa che non sappiamo mandare. Non è un errore da nascondere: è la
  /// risposta a «posso trasmettere questo?», e la risposta è no.
  ignoto;

  /// Da un tipo MIME al genere.
  ///
  /// Il tipo arriva dal demone, che per immagini, audio e video lo ricava
  /// guardando il **contenuto** e non il nome (`mime_service.dart`): un
  /// `foto.jpg` che è davvero un HEIC finisce qui col tipo giusto.
  static Genere di(String tipo) {
    final t = tipo.toLowerCase().trim();
    // HLS si riconosce prima di tutto: la sua famiglia è `application`, che
    // da sola non direbbe niente.
    if (t.startsWith('application/x-mpegurl') ||
        t.startsWith('application/vnd.apple.mpegurl') ||
        t.startsWith('audio/x-mpegurl') ||
        t.startsWith('application/dash+xml')) {
      return Genere.flusso;
    }
    final famiglia = t.split('/').first;
    switch (famiglia) {
      case 'image':
        return Genere.foto;
      case 'video':
        return Genere.video;
      case 'audio':
        return Genere.musica;
      default:
        return Genere.ignoto;
    }
  }

  /// La classe DIDL-Lite, cioè come si presenta il file a un apparecchio DLNA.
  String get classeDidl {
    switch (this) {
      case Genere.foto:
        return 'object.item.imageItem.photo';
      case Genere.video:
        return 'object.item.videoItem';
      case Genere.flusso:
        // ── Non «un video»: una DIRETTA ──────────────────────────────────
        //
        // `videoBroadcast` è la classe con cui si annuncia un canale del
        // digitale terrestre a un televisore. Fino al 4 settembre 2026 lo
        // schermo trasmesso si dichiarava `videoItem`, cioè «un file video»,
        // e un renderer che riceve un file si comporta come si comporta con
        // un file: si riempie la pancia prima di cominciare, perché di un
        // file conviene averne un pezzo davanti.
        //
        // Misurato quel giorno sul televisore della cucina, con Giacomo che
        // contava i secondi: **sei secondi di ritardo**, e alzare la banda da
        // 6 a 16 Mbit/s non ne toglieva nemmeno uno. Vuol dire che la scorta
        // del televisore si misura in SECONDI e non in byte — e i secondi non
        // si comprano con la banda, si tolgono dicendogli che non gli
        // servono.
        return 'object.item.videoItem.videoBroadcast';
      case Genere.musica:
        return 'object.item.audioItem.musicTrack';
      case Genere.ignoto:
        return 'object.item';
    }
  }

  /// Il numero che il Chromecast usa per sapere che scheda disegnare.
  ///
  /// 0 generico · 1 film · 2 serie · 3 canzone · 4 fotografia. Con 4 su un
  /// video il lettore predefinito mette la cornice da album fotografico
  /// attorno al filmato.
  int get metadatoCast {
    switch (this) {
      case Genere.foto:
        return 4;
      case Genere.video:
        return 1;
      case Genere.musica:
        return 3;
      case Genere.flusso:
      case Genere.ignoto:
        return 0;
    }
  }

  /// Ci si può saltare dentro? Un film sì, lo schermo dal vivo no.
  bool get siPuoScorrere => this == Genere.video || this == Genere.musica;

  /// `streamType` del Chromecast.
  ///
  /// `BUFFERED` è un file con un inizio e una fine: dà la barra di
  /// avanzamento e il salto avanti. `LIVE` è un flusso: il lettore sta in
  /// coda e non prova a tornare indietro. `NONE` è per una fotografia, che
  /// non scorre affatto.
  String get modoFlussoCast {
    switch (this) {
      case Genere.video:
      case Genere.musica:
        return 'BUFFERED';
      case Genere.flusso:
        return 'LIVE';
      case Genere.foto:
      case Genere.ignoto:
        return 'NONE';
    }
  }

  /// `transferMode.dlna.org`: come l'apparecchio deve venire a prendersi la
  /// roba.
  ///
  /// `Interactive` vuol dire «dammela tutta, la guardo quando ho finito» ed è
  /// il valore per le immagini. `Streaming` vuol dire «me la guardo mentre
  /// arriva», e per un film è la differenza fra cominciare subito e aspettare
  /// tre gigabyte.
  String get modoTrasferimento =>
      this == Genere.foto || this == Genere.ignoto ? 'Interactive' : 'Streaming';

  /// `contentFeatures.dlna.org`: cosa promettiamo di saper fare.
  ///
  /// ── Da dove vengono questi numeri ─────────────────────────────────────
  ///
  /// `DLNA.ORG_OP` sono due bit: il primo «so saltare a un istante», il
  /// secondo «so saltare a un byte». Noi il secondo lo sappiamo fare da oggi
  /// (`Range` in `servizio_effimero.dart`), il primo no — quindi `01`. Su un
  /// flusso dal vivo non si salta da nessuna parte: `00`.
  ///
  /// **Promettere `01` senza avere `Range` è esattamente il difetto che
  /// c'era**: il televisore chiedeva un intervallo, riceveva tutto il file
  /// dall'inizio, e non riusciva a spostarsi.
  ///
  /// `DLNA.ORG_FLAGS` sono 32 cifre esadecimali di cui contano le prime otto,
  /// e ogni bit ha un nome nella specifica:
  ///
  ///     0x01000000  modo «streaming»
  ///     0x00800000  modo «interactive»
  ///     0x00400000  trasferimento in secondo piano
  ///     0x00200000  il collegamento può fermarsi e riprendere
  ///     0x00100000  DLNA 1.5
  ///
  /// Da cui: `00900000` per una foto (interactive + 1.5), `01700000` per
  /// audio e video (streaming + secondo piano + pause + 1.5).
  String get caratteristiche {
    const zeri = '000000000000000000000000';
    if (this == Genere.foto || this == Genere.ignoto) {
      return 'DLNA.ORG_OP=01;DLNA.ORG_FLAGS=00900000$zeri';
    }
    if (this == Genere.flusso) {
      // ── I flag della diretta ─────────────────────────────────────────
      //
      // `8D500000` non è un numero scelto: è la firma con cui si annuncia un
      // flusso dal vivo, la stessa che usano i server di TV in diretta.
      // Bit per bit, e ognuno dice al televisore di NON fare qualcosa:
      //
      //     0x80000000  sender paced — il ritmo lo detta chi manda.
      //                 È la riga che conta: a un renderer che riceve un
      //                 file conviene farsi una scorta, a uno che riceve
      //                 una diretta la scorta è solo ritardo.
      //     0x08000000  l'inizio del contenuto si sposta in avanti
      //     0x04000000  la fine cresce: non finisce, sta succedendo
      //     0x01000000  modo «streaming»
      //     0x00400000  trasferimento in secondo piano
      //     0x00100000  DLNA 1.5
      //
      // E manca apposta `0x00200000`, «il collegamento può fermarsi e
      // riprendere»: di una diretta non si riprende niente, si perde.
      //
      // `DLNA.ORG_CI=0` vuol dire che il contenuto è quello vero e non una
      // conversione: alcuni apparecchi, senza, ne cercano una versione
      // trasformata che non esiste.
      return 'DLNA.ORG_OP=00;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=8D500000$zeri';
    }
    return 'DLNA.ORG_OP=01;DLNA.ORG_FLAGS=01700000$zeri';
  }

  /// Come si chiama in italiano, per i messaggi.
  String get nome {
    switch (this) {
      case Genere.foto:
        return 'fotografia';
      case Genere.video:
        return 'video';
      case Genere.musica:
        return 'brano';
      case Genere.flusso:
        return 'schermo';
      case Genere.ignoto:
        return 'file';
    }
  }
}

/// Quello che il lettore predefinito di un Chromecast sa davvero leggere.
///
/// ── Perché c'è, e perché è un elenco corto ────────────────────────────────
///
/// Perché il modo in cui un Chromecast rifiuta è **muto**: accetta il
/// comando, dice «va bene», e poi resta nero. Chi guarda conclude che Minerva
/// è rotta.
///
/// L'elenco è quello del ricevitore predefinito (`CC1AD845`), che non è un
/// lettore multimediale completo: legge H.264 e VP8 dentro MP4 e WebM, e
/// **non legge MKV** — che è il formato in cui arriva metà dei film. Dirlo
/// prima costa una riga; scoprirlo davanti alla televisione costa una serata.
class SaLeggere {
  const SaLeggere._();

  static const _chromecast = {
    'video/mp4', 'video/webm', 'video/x-m4v', 'video/quicktime',
    'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/flac', 'audio/ogg',
    'audio/vnd.wave', 'audio/wav', 'audio/x-wav', 'audio/opus',
    'audio/x-opus+ogg', 'audio/webm',
    'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/bmp',
    'application/x-mpegurl', 'application/vnd.apple.mpegurl',
    'application/dash+xml',
  };

  /// `null` se va bene, altrimenti la frase che spiega perché no.
  ///
  /// Torna una frase e non un booleano di proposito: chi chiama non deve
  /// inventarsi il messaggio, o ne nascono cinque diversi per la stessa causa.
  static String? perche(String tipo, String nomeTelevisore) {
    final t = tipo.toLowerCase().split(';').first.trim();
    if (_chromecast.contains(t)) return null;
    if (t == 'video/matroska' || t == 'video/x-matroska') {
      return '«$nomeTelevisore» non sa leggere gli MKV: il suo lettore '
          'conosce MP4 e WebM. Non è un guasto ed è del televisore, non di '
          'Minerva.';
    }
    if (t == 'video/x-msvideo' || t == 'video/vnd.avi' || t == 'video/avi') {
      return '«$nomeTelevisore» non sa leggere gli AVI: il suo lettore '
          'conosce MP4 e WebM.';
    }
    return '«$nomeTelevisore» non sa leggere i file di tipo $t.';
  }
}

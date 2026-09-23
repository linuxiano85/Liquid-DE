import 'dart:io';
import 'dart:typed_data';

/// Quello che una fotografia dice di sé stessa.
///
/// ── Perché esiste ──────────────────────────────────────────────────────────
///
/// Le 826 foto e video di questa casa hanno tutti la stessa data di modifica:
/// 8 luglio 2026 alle 21:29, cioè il momento in cui sono stati copiati dal
/// telefono. Ordinarli per `mtime` — che è quello che fa ogni gestore di file —
/// li mette **tutti nello stesso giorno**. La data vera esiste, ma sta dentro
/// il file, non intorno.
///
/// Su 826, 664 hanno l'EXIF. Leggerli tutti costa 0,64 secondi.
///
/// ── Perché scritto a mano ──────────────────────────────────────────────────
///
/// `minervad/pubspec.yaml` non ha dipendenze esterne, di proposito, ed
/// `exiftool` non è installato su questa macchina. Ma il precedente è in casa e
/// funziona: `image_dims.dart` cammina i segmenti JPEG in Dart puro. Questo fa
/// lo stesso, un passo più in là — entra nell'APP1 e legge le poche etichette
/// che servono davvero.
///
/// Non è un lettore EXIF completo e non vuole esserlo: le etichette sono nove,
/// scelte perché ognuna risponde a una domanda che il programma fa davvero.
///
/// ── La miniatura, che è il regalo ──────────────────────────────────────────
///
/// Dentro l'EXIF di ogni foto di telefono c'è **un JPEG intero da circa 6 KB**
/// (misurato: da 4.956 a 8.421 byte su questa libreria). Per riempire una
/// griglia non serve decodificare 2,7 MB: bastano i 42 KB dell'intestazione, e
/// dentro c'è già la miniatura pronta. Qui se ne restituisce l'intervallo di
/// byte; a estrarla ci pensa chi la vuole.
class DatiExif {
  /// L'ora scritta dalla macchina fotografica. È **ora locale del luogo dello
  /// scatto**, senza fuso, a meno che [fuso] non dica quale.
  final DateTime? scattata;

  /// Lo scostamento dichiarato da `OffsetTimeOriginal`, quando c'è. Quasi
  /// nessun telefono lo scrive, e per questo [scattata] non va mai convertita
  /// d'ufficio: senza questo campo, non si sa da dove convertire.
  final Duration? fuso;

  /// 1…8 come da specifica; 0 vuol dire «non detto».
  ///
  /// Serve a un difetto che c'è adesso: `image_dims.dart` dà le misure prima
  /// della rotazione, quindi una foto verticale di telefono viene dichiarata
  /// orizzontale.
  final int orientamento;

  /// Marca e modello uniti, già puliti. Vuoto se non detti.
  final String macchina;

  final double? latitudine;
  final double? longitudine;

  /// Dove sta la miniatura dentro questo file, in byte assoluti. `lunga` è 0
  /// quando non c'è.
  final int miniaturaDa;
  final int miniaturaLunga;

  /// C'era un APP1 con dentro «Exif». Distingue «non ce l'ha» da «non l'ho
  /// saputo leggere», che sono due cose diverse: la prima è un indizio (le
  /// copie di WhatsApp perdono l'EXIF), la seconda è un difetto nostro.
  final bool presente;

  const DatiExif({
    this.scattata,
    this.fuso,
    this.orientamento = 0,
    this.macchina = '',
    this.latitudine,
    this.longitudine,
    this.miniaturaDa = 0,
    this.miniaturaLunga = 0,
    this.presente = false,
  });

  static const DatiExif nessuno = DatiExif();

  bool get haMiniatura => miniaturaLunga > 0;

  /// Le misure girate, se l'orientamento lo chiede. Da 5 a 8 la fotografia è
  /// coricata e larghezza e altezza vanno scambiate.
  bool get coricata => orientamento >= 5 && orientamento <= 8;

  Map<String, dynamic> toJson() => {
        if (scattata != null) 'scattata': scattata!.toIso8601String(),
        if (fuso != null) 'fuso': fuso!.inMinutes,
        'orientamento': orientamento,
        if (macchina.isNotEmpty) 'macchina': macchina,
        if (latitudine != null) 'lat': latitudine,
        if (longitudine != null) 'lon': longitudine,
        'miniatura': miniaturaLunga,
        'presente': presente,
      };

  /// Legge l'intestazione del file. Non decodifica un solo pixel.
  ///
  /// Si leggono 128 KB: un APP1 non può superare i 65.533 byte per costruzione
  /// (la lunghezza sta in due byte), ma non è detto che sia il primo segmento —
  /// alcune macchine mettono prima un APP0 di JFIF. Il doppio basta e avanza.
  static DatiExif leggi(String percorso) {
    try {
      final f = File(percorso);
      if (!f.existsSync()) return nessuno;
      final raf = f.openSync();
      try {
        final testa = raf.readSync(128 * 1024);
        return daBytes(testa);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return nessuno;
    }
  }

  /// La parte pura, che si prova senza toccare il disco.
  static DatiExif daBytes(Uint8List b) {
    if (b.length < 12) return nessuno;
    if (!(b[0] == 0xFF && b[1] == 0xD8)) return nessuno; // non è un JPEG

    // ── Trovare l'APP1 ───────────────────────────────────────────────────
    var i = 2;
    var tiff = -1;
    for (var giri = 0; giri < 256; giri++) {
      if (i + 4 > b.length) return nessuno;
      if (b[i] != 0xFF) {
        i++; // riempimento fra un segmento e l'altro
        continue;
      }
      final marcatore = b[i + 1];
      if (marcatore == 0xD8 ||
          marcatore == 0x01 ||
          (marcatore >= 0xD0 && marcatore <= 0xD7)) {
        i += 2;
        continue;
      }
      // Inizio dei dati o fine del file: l'EXIF sta prima, non c'è più.
      if (marcatore == 0xD9 || marcatore == 0xDA) return nessuno;
      final lunghezza = (b[i + 2] << 8) | b[i + 3];
      if (lunghezza < 2) return nessuno;
      if (marcatore == 0xE1 &&
          i + 10 <= b.length &&
          b[i + 4] == 0x45 && // E
          b[i + 5] == 0x78 && // x
          b[i + 6] == 0x69 && // i
          b[i + 7] == 0x66 && // f
          b[i + 8] == 0x00 &&
          b[i + 9] == 0x00) {
        tiff = i + 10;
        break;
      }
      i += 2 + lunghezza;
    }
    if (tiff < 0 || tiff + 8 > b.length) return nessuno;

    // ── L'intestazione TIFF ──────────────────────────────────────────────
    //
    // Due byte dicono da che parte si leggono i numeri. È l'unico posto in
    // tutta Minerva dove l'ordine dei byte non è deciso da noi ma dal file, e
    // sbagliarlo non dà un errore: dà date del 1802.
    final bool piccolo;
    if (b[tiff] == 0x49 && b[tiff + 1] == 0x49) {
      piccolo = true; // «II», Intel
    } else if (b[tiff] == 0x4D && b[tiff + 1] == 0x4D) {
      piccolo = false; // «MM», Motorola
    } else {
      return nessuno;
    }
    final l = _Lettore(b, tiff, piccolo);
    if (l.u16(tiff + 2) != 42) return nessuno; // la firma, letteralmente 42
    final ifd0 = tiff + l.u32(tiff + 4);

    // ── IFD0: la macchina, l'orientamento, e i due rimandi ───────────────
    var orientamento = 0;
    var marca = '';
    var modello = '';
    var quandoIfd0 = '';
    var exifIfd = -1;
    var gpsIfd = -1;

    l.perOgniVoce(ifd0, (tag, tipo, quante, dove) {
      switch (tag) {
        case 0x0112:
          orientamento = l.interoDi(tipo, dove);
          break;
        case 0x010F:
          marca = l.testo(tipo, quante, dove);
          break;
        case 0x0110:
          modello = l.testo(tipo, quante, dove);
          break;
        case 0x0132:
          quandoIfd0 = l.testo(tipo, quante, dove);
          break;
        case 0x8769:
          exifIfd = tiff + l.interoDi(tipo, dove);
          break;
        case 0x8825:
          gpsIfd = tiff + l.interoDi(tipo, dove);
          break;
      }
    });

    // ── ExifIFD: la data che conta davvero ───────────────────────────────
    var originale = '';
    var digitalizzata = '';
    var scostamentoOriginale = '';
    var scostamento = '';
    if (exifIfd > 0) {
      l.perOgniVoce(exifIfd, (tag, tipo, quante, dove) {
        switch (tag) {
          case 0x9003:
            originale = l.testo(tipo, quante, dove);
            break;
          case 0x9004:
            digitalizzata = l.testo(tipo, quante, dove);
            break;
          case 0x9011:
            scostamentoOriginale = l.testo(tipo, quante, dove);
            break;
          case 0x9010:
            scostamento = l.testo(tipo, quante, dove);
            break;
        }
      });
    }

    // ── GPS ──────────────────────────────────────────────────────────────
    double? lat;
    double? lon;
    if (gpsIfd > 0) {
      var versoLat = '';
      var versoLon = '';
      double? gradiLat;
      double? gradiLon;
      l.perOgniVoce(gpsIfd, (tag, tipo, quante, dove) {
        switch (tag) {
          case 0x0001:
            versoLat = l.testo(tipo, quante, dove);
            break;
          case 0x0002:
            gradiLat = l.gradi(tipo, quante, dove);
            break;
          case 0x0003:
            versoLon = l.testo(tipo, quante, dove);
            break;
          case 0x0004:
            gradiLon = l.gradi(tipo, quante, dove);
            break;
        }
      });
      if (gradiLat != null) lat = versoLat == 'S' ? -gradiLat! : gradiLat;
      if (gradiLon != null) lon = versoLon == 'W' ? -gradiLon! : gradiLon;
    }

    // ── IFD1: dove sta la miniatura ──────────────────────────────────────
    var miniDa = 0;
    var miniLunga = 0;
    final prossimo = l.prossimoIfd(ifd0);
    if (prossimo > 0) {
      var off = 0;
      var lung = 0;
      l.perOgniVoce(tiff + prossimo, (tag, tipo, quante, dove) {
        if (tag == 0x0201) off = l.interoDi(tipo, dove);
        if (tag == 0x0202) lung = l.interoDi(tipo, dove);
      });
      // Gli scostamenti dell'IFD sono relativi all'inizio del TIFF, non del
      // file: sommare quello sbagliato dà byte a caso che sembrano una foto.
      if (off > 0 && lung > 0) {
        miniDa = tiff + off;
        miniLunga = lung;
      }
    }

    final macchina = _unisci(marca, modello);
    final quando = _data(originale) ?? _data(digitalizzata) ?? _data(quandoIfd0);

    return DatiExif(
      scattata: quando,
      fuso: _fuso(scostamentoOriginale.isNotEmpty
          ? scostamentoOriginale
          : scostamento),
      orientamento: orientamento,
      macchina: macchina,
      latitudine: lat,
      longitudine: lon,
      miniaturaDa: miniDa,
      miniaturaLunga: miniLunga,
      presente: true,
    );
  }

  /// Estrae la miniatura, se c'è. Una lettura sola, nessuna decodifica.
  static Uint8List? miniatura(String percorso, DatiExif dati) {
    if (!dati.haMiniatura) return null;
    try {
      final raf = File(percorso).openSync();
      try {
        raf.setPositionSync(dati.miniaturaDa);
        final b = raf.readSync(dati.miniaturaLunga);
        // Deve essere un JPEG intero. Se non comincia per FFD8 lo scostamento
        // era sbagliato, e restituire quei byte darebbe una miniatura rotta
        // invece di nessuna miniatura.
        if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
        // La lunghezza dichiarata è arrotondata: su questo telefono dice
        // 36.864 byte per una miniatura che ne occupa 8.421, e gli altri 28 KB
        // sono riempimento. Un decodificatore li ignora — la nostra cache no:
        // sarebbero 16 MB buttati su 454 foto. Si taglia all'ultimo FFD9.
        final fine = _fineJpeg(b);
        return fine > 0 && fine < b.length ? Uint8List.sublistView(b, 0, fine) : b;
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return null;
    }
  }

  /// Dove finisce davvero un JPEG: l'ultimo FFD9. Si cerca dal fondo perché
  /// FFD9 può comparire anche dentro i dati compressi, e il primo che si
  /// incontra taglierebbe l'immagine a metà.
  static int _fineJpeg(Uint8List b) {
    for (var i = b.length - 2; i >= 2; i--) {
      if (b[i] == 0xFF && b[i + 1] == 0xD9) return i + 2;
    }
    return 0;
  }

  static String _unisci(String marca, String modello) {
    final ma = marca.trim();
    final mo = modello.trim();
    if (ma.isEmpty) return mo;
    if (mo.isEmpty) return ma;
    // «Canon» + «Canon EOS 5D» non deve dare «Canon Canon EOS 5D».
    if (mo.toLowerCase().startsWith(ma.toLowerCase())) return mo;
    return '$ma $mo';
  }

  /// «2026:03:17 11:27:29» — i due punti anche nella data, che è la ragione
  /// per cui `DateTime.parse` qui non serve a niente.
  static DateTime? _data(String s) {
    final t = s.trim();
    if (t.length < 19) return null;
    final n = RegExp(r'^(\d{4}):(\d{2}):(\d{2})[ T](\d{2}):(\d{2}):(\d{2})')
        .firstMatch(t);
    if (n == null) return null;
    final anno = int.parse(n.group(1)!);
    final mese = int.parse(n.group(2)!);
    final giorno = int.parse(n.group(3)!);
    // Alcune macchine scrivono «0000:00:00 00:00:00» quando l'orologio non è
    // mai stato messo. È un vuoto travestito da data.
    if (anno < 1900 || mese < 1 || mese > 12 || giorno < 1 || giorno > 31) {
      return null;
    }
    final d = DateTime(anno, mese, giorno, int.parse(n.group(4)!),
        int.parse(n.group(5)!), int.parse(n.group(6)!));
    // Il rollover di DateTime accetta il 31 febbraio e lo sposta a marzo: se
    // il giorno cambia, la data non esisteva.
    if (d.month != mese || d.day != giorno) return null;
    return d;
  }

  /// «+02:00» o «-05:00».
  static Duration? _fuso(String s) {
    final n = RegExp(r'^([+-])(\d{2}):(\d{2})').firstMatch(s.trim());
    if (n == null) return null;
    final segno = n.group(1) == '-' ? -1 : 1;
    return Duration(
      minutes: segno *
          (int.parse(n.group(2)!) * 60 + int.parse(n.group(3)!)),
    );
  }
}

/// Il lettore di un blocco TIFF: sa da che parte stanno i byte, e dove
/// comincia a contare.
class _Lettore {
  final Uint8List b;
  final int tiff;
  final bool piccolo;
  const _Lettore(this.b, this.tiff, this.piccolo);

  bool _cSta(int i, int quanti) => i >= 0 && i + quanti <= b.length;

  int u16(int i) {
    if (!_cSta(i, 2)) return 0;
    return piccolo ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]);
  }

  int u32(int i) {
    if (!_cSta(i, 4)) return 0;
    return piccolo
        ? (b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24))
        : ((b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3]);
  }

  /// Scorre le voci di un IFD. Ogni voce è dodici byte: etichetta, tipo,
  /// quante, e o il valore o dove trovarlo.
  void perOgniVoce(
      int ifd, void Function(int tag, int tipo, int quante, int dove) fai) {
    if (!_cSta(ifd, 2)) return;
    final quante = u16(ifd);
    // Un IFD con mille voci è un file rotto, non una macchina fotografica
    // loquace.
    if (quante <= 0 || quante > 512) return;
    for (var k = 0; k < quante; k++) {
      final v = ifd + 2 + k * 12;
      if (!_cSta(v, 12)) return;
      final tag = u16(v);
      final tipo = u16(v + 2);
      final n = u32(v + 4);
      final larghezza = _larghezza(tipo) * n;
      // Fino a quattro byte il valore sta lì; oltre, lì c'è dove andarlo a
      // prendere — e quel «dove» conta dall'inizio del TIFF.
      final dove = larghezza <= 4 ? v + 8 : tiff + u32(v + 8);
      fai(tag, tipo, n, dove);
    }
  }

  int prossimoIfd(int ifd) {
    if (!_cSta(ifd, 2)) return 0;
    final quante = u16(ifd);
    if (quante <= 0 || quante > 512) return 0;
    return u32(ifd + 2 + quante * 12);
  }

  static int _larghezza(int tipo) {
    switch (tipo) {
      case 1: // BYTE
      case 2: // ASCII
      case 6: // SBYTE
      case 7: // UNDEFINED
        return 1;
      case 3: // SHORT
      case 8: // SSHORT
        return 2;
      case 4: // LONG
      case 9: // SLONG
      case 11: // FLOAT
        return 4;
      case 5: // RATIONAL
      case 10: // SRATIONAL
      case 12: // DOUBLE
        return 8;
      default:
        return 1;
    }
  }

  int interoDi(int tipo, int dove) {
    switch (tipo) {
      case 1:
        return _cSta(dove, 1) ? b[dove] : 0;
      case 3:
        return u16(dove);
      case 4:
      case 9:
        return u32(dove);
      default:
        return 0;
    }
  }

  String testo(int tipo, int quante, int dove) {
    if (tipo != 2 || quante <= 0) return '';
    if (!_cSta(dove, quante)) return '';
    final fine = dove + quante;
    final byte = <int>[];
    for (var i = dove; i < fine; i++) {
      if (b[i] == 0) break; // le stringhe EXIF finiscono con uno zero
      byte.add(b[i]);
    }
    return String.fromCharCodes(byte).trim();
  }

  /// Tre frazioni: gradi, primi, secondi.
  double? gradi(int tipo, int quante, int dove) {
    if (tipo != 5 || quante < 3) return null;
    if (!_cSta(dove, 24)) return null;
    final g = _frazione(dove);
    final m = _frazione(dove + 8);
    final s = _frazione(dove + 16);
    if (g == null || m == null || s == null) return null;
    return g + m / 60 + s / 3600;
  }

  double? _frazione(int i) {
    final num = u32(i);
    final den = u32(i + 4);
    if (den == 0) return null;
    return num / den;
  }
}

import 'dart:io';

import '../core/linux_files.dart';
import '../core/minerva_paths.dart';
import '../util/sha256.dart';

/// Il ritratto di una persona, in una forma che Qt apre con UN decoder solo.
///
/// ── Perché esiste ──────────────────────────────────────────────────────────
///
/// I ritratti di AccountsService si chiamano come l'utente — `utente`, senza
/// estensione. Davanti a un file senza estensione `QImageReader` non sa che
/// formato sia, e per scoprirlo interroga **tutti** i plugin immagine prima
/// dei decoder interni: sul computer di casa, il 18 ottobre 2026, erano 34
/// plugin e 98 librerie (97,6 MB: x265, aom, SVT-AV1, jxl, pdfium, libproxy,
/// GIO…) caricati per disegnare un PNG da 33 KB. A caldo costa 23 ms invece
/// di 4; al primo accesso dopo l'accensione l'avatar della schermata di
/// accesso arrivava dopo 3,2 secondi, e lo stesso percorso lo usa la Shell
/// per il menu Start e le Impostazioni.
///
/// E non è solo tempo: un file scelto dall'utente passava da trentaquattro
/// parser diversi, dentro la schermata di accesso.
///
/// Qui il file si legge una volta, se ne riconosce il formato dai primi byte
/// e se ne mette una copia con l'estensione giusta in una cartella privata.
/// L'estensione da sola non basta: Qt Quick carica comunque tutti i plugin
/// alla prima Image da file. La schermata di accesso la apre quindi con il
/// provider `image://icon/` di Quickshell, che usa QPixmap (vedi
/// `greeter/Greeter.qml`): senza estensione anche quello li caricherebbe tutti.
/// Un formato che non si riconosce resta com'era — il percorso originale,
/// lento come prima ma funzionante: niente ritratti spariti per una regola
/// nuova.
class RitrattiLeggibili {
  /// Dove vanno le copie. Iniettabile: una prova non scrive nella cartella
  /// di runtime vera.
  final String? cartella;

  /// Un ritratto più grande di così non è un ritratto: resta com'era. Un
  /// mega, come il tetto di AccountsService: il provider della schermata lo
  /// decodifica sul filo dell'interfaccia, e una fotografia intera lì
  /// fermerebbe l'anello.
  final int tettoByte;

  const RitrattiLeggibili({this.cartella, this.tettoByte = 1024 * 1024});

  /// Il formato dai primi byte, o null. Solo formati che Qt apre con un
  /// decoder suo e che un pannello «scegli il ritratto» produce davvero.
  static String? formato(List<int> b) {
    bool inizia(List<int> firma, [int da = 0]) {
      if (b.length < da + firma.length) return false;
      for (var i = 0; i < firma.length; i++) {
        if (b[da + i] != firma[i]) return false;
      }
      return true;
    }

    if (inizia(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
      return 'png';
    }
    if (inizia(const [0xFF, 0xD8, 0xFF])) return 'jpg';
    if (inizia(const [0x52, 0x49, 0x46, 0x46]) &&
        inizia(const [0x57, 0x45, 0x42, 0x50], 8)) {
      return 'webp';
    }
    if (inizia(const [0x47, 0x49, 0x46, 0x38, 0x37, 0x61]) ||
        inizia(const [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])) {
      return 'gif';
    }
    return null;
  }

  /// Il percorso da dare alla Shell per [sorgente]. Non solleva mai: ogni
  /// guaio restituisce [sorgente], cioè il comportamento di prima.
  Future<String> pronto(String sorgente) async {
    if (sorgente.isEmpty) return sorgente;
    LinuxRegularSource? pin;
    try {
      // Fissato l'inode prima di leggere: niente FIFO che bloccano, niente
      // file scambiato fra il controllo e la lettura.
      pin = LinuxFiles.pinRegularSource(sorgente);
      if (pin.version.size > tettoByte) return sorgente;
      final byte = <int>[];
      await for (final pezzo in pin.openRead()) {
        byte.addAll(pezzo);
        if (byte.length > tettoByte) return sorgente;
      }
      final ext = formato(byte);
      if (ext == null) return sorgente;

      final dir = _cartellaPrivata(cartella ?? _cartellaDiSerie());
      // Il nome è l'impronta del contenuto: lo stesso ritratto dà lo stesso
      // file, uno nuovo dà un nome nuovo (e Qt non ridisegna quello vecchio
      // dalla sua cache). SHA-256 e non un'impronta veloce: un altro utente
      // del computer non deve poter fabbricare un'immagine col nome del
      // ritratto di qualcun altro.
      final dest = '$dir/${Sha256.esa(byte)}.$ext';
      if (_giaPronto(dest, byte.length)) return dest;

      final tmp = File('$dir/.${DateTime.now().microsecondsSinceEpoch}-$pid');
      await tmp.create(exclusive: true);
      try {
        LinuxFiles.setPermissions(tmp.path, 0x180); // 0600
        await tmp.writeAsBytes(byte, flush: true);
        await tmp.rename(dest);
      } catch (_) {
        try {
          await tmp.delete();
        } catch (_) {}
        rethrow;
      }
      _pota(dir, dest);
      return dest;
    } catch (e) {
      stdout.writeln('[MINERVA][ACCESSO][ATTENZIONE] Ritratto lasciato com\'è: $e');
      return sorgente;
    } finally {
      try {
        pin?.close();
      } catch (_) {}
    }
  }

  /// Nella cartella di runtime se c'è (tmpfs, sparisce col logout); dentro la
  /// schermata di accesso, se manca, in quella di configurazione di
  /// `greeter`, che è sua e chiusa — la stessa regola del canale segreto.
  static String _cartellaDiSerie() {
    final env = Platform.environment;
    final r = env['XDG_RUNTIME_DIR'];
    if (r != null && r.startsWith('/') && Directory(r).existsSync()) {
      return '${MinervaPaths.runtime(env)}/ritratti';
    }
    return '${MinervaPaths.config(env)}/ritratti';
  }

  /// La cartella esiste, è una cartella (non un link), è nostra e nessun
  /// altro ci entra. Altrimenti si solleva, e il ritratto resta com'era.
  static String _cartellaPrivata(String path) {
    if (!LinuxFiles.entryExists(path)) {
      Directory(path).createSync(recursive: true);
      LinuxFiles.setPermissions(path, 0x1c0); // 0700
    }
    final v = LinuxFiles.version(path);
    if (v.kind != 0x4000 || v.uid != LinuxFiles.uid || (v.mode & 0x3f) != 0) {
      throw FileSystemException('Cartella dei ritratti non privata', path);
    }
    return path;
  }

  /// Le copie dei ritratti cambiati. Solo quando se ne scrive una nuova, cioè
  /// quasi mai, e solo le vecchie di un giorno: un ritratto di un altro utente
  /// ancora attuale, se sparisse, verrebbe solo riscritto alla richiesta dopo.
  static void _pota(String dir, String tenere) {
    final limite = DateTime.now().subtract(const Duration(days: 1));
    try {
      for (final f in Directory(dir).listSync(followLinks: false)) {
        if (f.path == tenere || f is! File) continue;
        try {
          if (f.statSync().modified.isBefore(limite)) f.deleteSync();
        } catch (_) {}
      }
    } catch (_) {}
  }

  static bool _giaPronto(String dest, int lunghezza) {
    try {
      final v = LinuxFiles.version(dest);
      return v.kind == 0x8000 && v.uid == LinuxFiles.uid && v.size == lunghezza;
    } on FileSystemException {
      return false;
    }
  }
}

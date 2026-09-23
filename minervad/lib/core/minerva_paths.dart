import 'dart:io';

/// Dove stanno le cose di Minerva.
///
/// Esiste perché per mesi la risposta è stata scritta a mano dentro quattro
/// file diversi:
///
///     '~/Minerva Shell/config/settings.json'
///
/// Che funziona su un portatile solo, quello di chi l'ha scritto. Un altro
/// utente, o la stessa persona che sposta la cartella, si ritrovava un demone
/// che crea impostazioni nuove in una cartella che non esiste e non capisce
/// perché nulla di quello che tocca resta.
///
/// Qui si separano due domande che erano diventate la stessa:
///
///  · **dov'è installata Minerva** — il codice, i moduli aggiuntivi, i suoni.
///    Si legge e basta, può stare in /usr/share, può essere di un altro
///    utente.
///  · **dove stanno le cose di CHI la usa** — impostazioni, tema, quali
///    programmi apre più spesso. Si scrivono in continuazione, e sono di una
///    persona sola: vanno in ~/.config/minerva, che è il posto che lo standard
///    freedesktop dedica esattamente a questo.
///
/// Tenerle insieme voleva dire che due utenti sullo stesso computer si
/// sarebbero sovrascritti le impostazioni a vicenda, e che Minerva installata
/// in una cartella di sistema non avrebbe potuto salvare niente.
class MinervaPaths {
  MinervaPaths._();

  static String get _home => Platform.environment['HOME'] ?? '';

  /// La cartella dove Minerva è installata.
  ///
  /// Si scopre in tre modi, in ordine di fiducia: se qualcuno ce l'ha detto
  /// (`MINERVA_ROOT`, che è quello che fa lo script di sessione), si crede a
  /// lui; altrimenti la si ricava da dove sta il demone in esecuzione, che
  /// è `<radice>/minervad/bin/minervad.dart`; se anche quello non porta da
  /// nessuna parte, resta la cartella di lavoro.
  static final String installRoot = _resolveInstallRoot();

  static String _resolveInstallRoot() {
    final told = Platform.environment['MINERVA_ROOT'];
    if (told != null && told.isNotEmpty && Directory(told).existsSync()) {
      return _trimSlash(told);
    }

    // `Platform.script` è il file .dart in esecuzione (o l'eseguibile
    // compilato). Da `<radice>/minervad/bin/minervad.dart` si risale di tre.
    try {
      var dir = File(Platform.script.toFilePath()).parent; // bin/
      final candidates = <Directory>[dir, dir.parent, dir.parent.parent];
      for (final c in candidates) {
        if (Directory('${c.path}/minerva-shell').existsSync()) {
          return _trimSlash(c.path);
        }
      }
    } catch (_) {
      // Platform.script può non essere un percorso di file (compilato in
      // AOT, avviato da uno snapshot, eseguito dal motore delle prove): non è
      // un errore, si passa oltre.
    }

    // Ultimo tentativo: si risale dalla cartella di lavoro. Vale quando il
    // demone viene avviato da dentro `minervad/` (che è come lo avvia
    // Hyprland) e quando lo esegue il motore delle prove, che sostituisce
    // `Platform.script` con un file suo in una cartella temporanea.
    var here = Directory.current;
    for (var i = 0; i < 6; i++) {
      if (Directory('${here.path}/minerva-shell').existsSync()) {
        return _trimSlash(here.path);
      }
      final up = here.parent;
      if (up.path == here.path) break;
      here = up;
    }

    return _trimSlash(Directory.current.path);
  }

  /// La cartella delle cose scritte dall'utente. Si crea se non c'è.
  static final String configDir = _resolveConfigDir();

  static String _resolveConfigDir() {
    final told = Platform.environment['MINERVA_CONFIG_DIR'];
    if (told != null && told.isNotEmpty) return _trimSlash(told);
    final xdg = Platform.environment['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return '${_trimSlash(xdg)}/minerva';
    return '$_home/.config/minerva';
  }

  static String settingsFile() => '$configDir/settings.json';
  static String appUsageFile() => '$configDir/app_usage.json';

  // Qui c'era anche `themeFile() => '$configDir/theme.json'`, e non lo leggeva
  // nessuno: il tema è una voce di `settings.json` (`shell.scheme`) da quando
  // un tema è diventato «una tinta e un verso». Il file resta sul disco di chi
  // usa Minerva da prima — innocuo, ma da non riesumare: due posti dove sta
  // scritto il tema vuol dire prima o poi due temi diversi.

  /// I moduli aggiuntivi stanno con l'installazione, non con l'utente: sono
  /// codice, e il codice non è roba da cartella delle preferenze.
  static String pluginsDir() => '$installRoot/plugins';

  /// Un file di configurazione che viene CON Minerva e non dall'utente: le
  /// scorciatoie, la configurazione di Hyprland, i suoni. Si legge dalla
  /// cartella dell'installazione.
  static String shippedFile(String relative) => '$installRoot/config/$relative';

  /// La vecchia casa di un file, dentro il progetto.
  ///
  /// Serve solo per il trasloco qui sotto e sparirà quando non ci sarà più
  /// nessuna installazione da traslocare.
  static String legacyFile(String name) => '$installRoot/config/$name';

  /// Porta un file dalla vecchia casa alla nuova, una volta sola.
  ///
  /// Chi usa Minerva da prima di questa modifica ha le sue impostazioni dentro
  /// il progetto: cambiarne il posto senza portarsele dietro vorrebbe dire
  /// svegliarsi con l'ambiente come appena installato — sfondo, accento,
  /// scorciatoie, tutto da rifare. Si copia e NON si cancella l'originale: se
  /// qualcosa va storto la vecchia copia è ancora lì.
  static Future<void> migrateIfNeeded(String name) =>
      migrateFile(File(legacyFile(name)), File('$configDir/$name'));

  /// Il trasloco vero e proprio, staccato da dove si trovano le cartelle così
  /// che si possa provarlo su file finti senza toccare quelli veri.
  ///
  /// Restituisce vero solo se ha copiato qualcosa.
  static Future<bool> migrateFile(File source, File destination) async {
    if (await destination.exists()) return false;
    if (!await source.exists()) return false;

    try {
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      print('[MINERVA][CORE][INFO] ${source.path} trasferito in '
          '${destination.parent.path}');
      return true;
    } catch (e) {
      print('[MINERVA][CORE][WARN] Trasferimento fallito (${source.path}): $e');
      return false;
    }
  }

  static String _trimSlash(String p) =>
      (p.length > 1 && p.endsWith('/')) ? p.substring(0, p.length - 1) : p;
}

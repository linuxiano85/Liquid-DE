import 'dart:io';

/// Dove stanno le cose di Liquid DE.
///
/// Due domande separate:
///
///  · **dov'è installato il codice**: la shell, i suoni, le scorciatoie di
///    serie. Si legge e basta.
///  · **dove stanno le cose di chi lo usa**: impostazioni, storia, cache. Si
///    scrivono in continuazione, e ognuna sta nella cartella che lo standard
///    freedesktop le dedica (`XDG_CONFIG_HOME`, `XDG_DATA_HOME`,
///    `XDG_CACHE_HOME`, `XDG_STATE_HOME`, `XDG_RUNTIME_DIR`).
///
/// Il nome delle cartelle sta scritto QUI e da nessun'altra parte
/// ([nome]). È la condizione perché Liquid DE e Minerva vivano sullo stesso
/// computer: se un solo punto del demone scrivesse ancora in una cartella
/// `minerva`, le due scrivanie si sovrascriverebbero le impostazioni a
/// vicenda. Una prova (`minerva_paths_test.dart`) cerca nel codice i percorsi
/// scritti a mano.
///
/// Ogni funzione accetta un ambiente al posto di quello vero: è il modo in
/// cui le prove chiedono «e se `XDG_DATA_HOME` fosse questo?» senza toccare
/// il processo.
class MinervaPaths {
  MinervaPaths._();

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

  /// Il nome delle cartelle di Liquid DE, in tutte le basi XDG.
  static const String nome = 'liquid-de';

  /// Il nome delle cartelle di Minerva: serve solo a LEGGERE, una volta, le
  /// impostazioni da importare al primo avvio ([importaDaMinerva]).
  static const String nomeMinerva = 'minerva';

  static Map<String, String> _amb(Map<String, String>? env) =>
      env ?? Platform.environment;

  /// Una base XDG: la variabile se c'è ed è un percorso assoluto, altrimenti
  /// il posto di serie sotto la casa.
  static String _base(Map<String, String> amb, String variabile, String diSerie) {
    final v = amb[variabile];
    if (v != null && v.startsWith('/')) return _trimSlash(v);
    return '${amb['HOME'] ?? '/tmp'}/$diSerie';
  }

  /// Le impostazioni. `MINERVA_CONFIG_DIR` vince su tutto: è quello che
  /// usano le sessioni di prova per non toccare le impostazioni vere.
  static String config([Map<String, String>? env]) {
    final amb = _amb(env);
    final detto = amb['MINERVA_CONFIG_DIR'];
    if (detto != null && detto.isNotEmpty) return _trimSlash(detto);
    return '${_base(amb, 'XDG_CONFIG_HOME', '.config')}/$nome';
  }

  /// I dati che si accumulano: storia, punti della Custodia, ritratti.
  static String dati([Map<String, String>? env]) =>
      '${_base(_amb(env), 'XDG_DATA_HOME', '.local/share')}/$nome';

  /// Quello che si può buttare e rifare: miniature, indici, suoni scaldati.
  static String cache([Map<String, String>? env]) =>
      '${_base(_amb(env), 'XDG_CACHE_HOME', '.cache')}/$nome';

  /// Lo stato che sopravvive a un riavvio ma non è una preferenza.
  static String stato([Map<String, String>? env]) =>
      '${_base(_amb(env), 'XDG_STATE_HOME', '.local/state')}/$nome';

  /// La cartella di runtime: socket e file della sessione. Senza una
  /// `XDG_RUNTIME_DIR` valida (l'utente `greeter` può averla impostata su una
  /// cartella che non esiste) si ripiega su /tmp, con l'utente nel nome.
  static String runtime([Map<String, String>? env]) {
    final amb = _amb(env);
    final r = amb['XDG_RUNTIME_DIR'];
    if (r != null && r.startsWith('/')) return '${_trimSlash(r)}/$nome';
    return '/tmp/$nome-${amb['USER'] ?? 'utente'}';
  }

  /// La cartella delle impostazioni di Minerva, da cui si importa.
  static String configMinerva([Map<String, String>? env]) =>
      '${_base(_amb(env), 'XDG_CONFIG_HOME', '.config')}/$nomeMinerva';

  /// La cartella delle cose scritte dall'utente. Si crea se non c'è.
  static final String configDir = config();

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

  /// Un file di configurazione che viene col codice e non dall'utente: le
  /// scorciatoie di serie, i suoni. Si legge dalla cartella dell'installazione.
  static String shippedFile(String relative) => '$installRoot/config/$relative';

  /// Al primo avvio, le impostazioni di Minerva diventano quelle di partenza.
  ///
  /// Si COPIA e non si sposta, e solo se Liquid DE non ha ancora le sue: da
  /// lì le due scrivanie vivono ognuna per conto suo, e Minerva resta
  /// esattamente com'era.
  static Future<void> importaDaMinerva(String name) => migrateFile(
      File('${configMinerva()}/$name'), File('$configDir/$name'));

  /// La copia vera e propria, staccata da dove si trovano le cartelle così
  /// che si possa provarla su file finti senza toccare quelli veri.
  ///
  /// Restituisce vero solo se ha copiato qualcosa.
  static Future<bool> migrateFile(File source, File destination) async {
    if (await destination.exists()) return false;
    if (!await source.exists()) return false;

    try {
      await destination.parent.create(recursive: true);
      await source.copy(destination.path);
      print('[MINERVA][CORE][INFO] ${source.path} importato in '
          '${destination.parent.path}');
      return true;
    } catch (e) {
      print('[MINERVA][CORE][WARN] Importazione fallita (${source.path}): $e');
      return false;
    }
  }

  static String _trimSlash(String p) =>
      (p.length > 1 && p.endsWith('/')) ? p.substring(0, p.length - 1) : p;
}

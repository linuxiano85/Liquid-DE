import 'dart:io';
import 'app_novita.dart';

/// Rappresenta un'applicazione installata sul sistema (.desktop).
class DesktopApp {
  final String id;
  final String name;
  final String exec;
  final String icon;
  String? iconPath;
  final List<String> categories;

  /// `StartupWMClass` del file .desktop: la classe che la finestra dichiarerà
  /// al compositore. È l'UNICO modo affidabile di legare una finestra aperta
  /// alla sua icona — il nome del programma non basta (`code` apre finestre di
  /// classe `Code`, `Alacritty` non c'entra con `alacritty.desktop`), e senza
  /// questo legame la dock non sa quale icona sta girando.
  final String wmClass;

  /// I tipi di file che questo programma dichiara di saper aprire
  /// (`MimeType=` nel .desktop). È l'elenco da cui nasce «Apri con…»: senza,
  /// l'unico modo di aprire un'immagine con un programma diverso da quello
  /// predefinito è saperne il nome a memoria e scriverlo in un terminale.
  final List<String> mimeTypes;

  /// `Terminal=true`: va lanciato dentro un terminale, altrimenti si apre e
  /// si chiude senza che nessuno veda niente.
  final bool needsTerminal;

  /// Che cos'è, in una parola: «Browser web», «Editor di testo». È il
  /// `GenericName` del `.desktop`, nella lingua dell'utente quando c'è.
  final String generico;

  /// Una frase su cosa fa (`Comment`).
  final String descrizione;

  /// Le parole con cui lo si cerca (`Keywords`), in tutte e due le lingue:
  /// chi scrive «navigatore» e chi scrive «browser» cercano la stessa cosa.
  final List<String> parole;

  DesktopApp({
    required this.id,
    required this.name,
    required this.exec,
    required this.icon,
    required this.categories,
    this.wmClass = '',
    this.mimeTypes = const [],
    this.needsTerminal = false,
    this.iconPath,
    this.generico = '',
    this.descrizione = '',
    this.parole = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'exec': exec,
        'icon': icon,
        'iconPath': iconPath ?? '',
        'categories': categories,
        'wmClass': wmClass,
        'mimeTypes': mimeTypes,
        'needsTerminal': needsTerminal,
        'generico': generico,
        'descrizione': descrizione,
        'parole': parole,
      };

  @override
  String toString() => 'App: $name ($exec)';
}

/// Servizio che scansiona e analizza i file .desktop del sistema.
class AppScanner {
  /// Dove stanno i .desktop. Si ricavano dalle variabili XDG invece di
  /// scriverle a mano: un elenco fisso dimentica i pacchetti Flatpak, i
  /// programmi installati per un solo utente e qualunque percorso che la
  /// distribuzione decida di usare — e un programma che non compare nel menu
  /// è, per chi lo cerca, un programma non installato.
  List<String> get _scanDirectories {
    final env = Platform.environment;
    final home = env['HOME'] ?? '';
    final dataHome = env['XDG_DATA_HOME']?.isNotEmpty == true
        ? env['XDG_DATA_HOME']!
        : (home.isEmpty ? '' : '$home/.local/share');
    final dataDirs = env['XDG_DATA_DIRS']?.isNotEmpty == true
        ? env['XDG_DATA_DIRS']!
        : '/usr/local/share:/usr/share';

    final dirs = <String>{};
    if (dataHome.isNotEmpty) dirs.add('$dataHome/applications');
    for (final d in dataDirs.split(':')) {
      if (d.trim().isEmpty) continue;
      dirs.add('${d.trim()}/applications');
    }
    // Flatpak non entra sempre in XDG_DATA_DIRS quando la sessione non è
    // partita da un login manager che lo imposta.
    dirs.add('/var/lib/flatpak/exports/share/applications');
    if (home.isNotEmpty) {
      dirs.add('$home/.local/share/flatpak/exports/share/applications');
    }
    return dirs.toList();
  }

  List<DesktopApp> _apps = [];

  AppScanner() : novita = AppNovita(percorso: AppNovita.percorsoDiSerie());
  final AppNovita novita;

  /// Uno scanner con dentro quello che gli si dice, senza toccare il disco.
  ///
  /// Serve alle prove: chi verifica chi apre che cosa deve poter descrivere i
  /// programmi installati, altrimenti l'esito dipende da quali pacchetti ci
  /// sono sulla macchina che esegue le prove — cioè è una prova che un giorno
  /// diventa rossa da sola.
  AppScanner.finto(List<DesktopApp> apps) : _apps = apps, novita = AppNovita();

  List<DesktopApp> get apps => _apps;


  /// Trova un'applicazione tramite il suo ID (.desktop)
  DesktopApp? getAppById(String id) {
    for (final app in _apps) {
      if (app.id == id) return app;
    }
    return null;
  }

  /// Legge un file .desktop da un percorso qualsiasi — un launcher messo a
  /// mano sulla scrivania, per dire — e lo interpreta come programma. Serve
  /// alle icone della scrivania: quelle non stanno nelle cartelle
  /// `applications`, ma sono .desktop a tutti gli effetti.
  Future<DesktopApp?> parseFromPath(String path) {
    return _parseDesktopFile(File(path));
  }

  /// Una scansione già in corso. Chi arriva mentre gira aspetta quella,
  /// invece di farne una seconda in parallelo sulle stesse cartelle.
  Future<void>? _inCorso;

  /// Com'erano le cartelle all'ultima scansione: i percorsi dei `.desktop` con
  /// la loro data di modifica. Vuoto = non si è mai guardato.
  String _impronta = '';

  /// Esegue la scansione dei file .desktop nelle directory configurate.
  ///
  /// ── Perché non la rifà se non è cambiato niente ──────────────────────
  ///
  /// Perché la chiede OGNI finestra di Minerva che si collega al demone: la
  /// shell all'avvio, il gestore file, le Impostazioni, ogni app. Nel registro
  /// di una sessione vera del 2 settembre 2026 se ne contavano
  /// **ottantanove**.
  ///
  /// Il tempo non era il problema — misurato: 111 ms a freddo, 40 a caldo, e
  /// la sola camminata sui 166 file è 6 ms. Il problema è la MEMORIA: ogni
  /// giro costruisce settantun oggetti e li butta, e il mucchio di Dart cresce
  /// fino al massimo che ha visto e **non lo restituisce**. Quel giorno il
  /// demone era passato da 44 a 74 MB, ed è il numero che ha fatto scattare il
  /// tetto in `prove.sh`.
  ///
  /// La camminata si fa lo stesso — è quella che dice se qualcosa è cambiato —
  /// ma i file si aprono solo se l'impronta è diversa. Sei millisecondi invece
  /// di quaranta, e zero spazzatura.
  ///
  /// `forza: true` la fa comunque: serve a chi ha appena installato qualcosa e
  /// non vuole dipendere da una data di modifica.
  Future<void> scan({bool forza = false}) {
    final gia = _inCorso;
    if (gia != null) return gia;
    final f = _scanDavvero(forza: forza);
    _inCorso = f;
    return f.whenComplete(() => _inCorso = null);
  }

  /// I `.desktop` che ci sono e quando sono stati toccati, senza aprirli.
  ///
  /// È il conto che dice «è cambiato qualcosa?»: un programma installato,
  /// tolto o corretto cambia questa stringa; aprire venti volte il gestore
  /// file no.
  Future<String> _improntaDelle() async {
    final righe = <String>[];
    for (final dirPath in _scanDirectories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: true)) {
          if (e is File && e.path.endsWith('.desktop')) {
            final st = await e.stat();
            righe.add('${e.path}:${st.modified.microsecondsSinceEpoch}');
          }
        }
      } catch (_) {
        // Una cartella che non si legge non deve impedire il confronto: si
        // lascia fuori, e al massimo si rifà una scansione in più.
      }
    }
    righe.sort();
    return righe.join('\n');
  }

  Future<void> _scanDavvero({bool forza = false}) async {
    if (!forza) {
      final adesso = await _improntaDelle();
      if (_impronta.isNotEmpty && adesso == _impronta) {
        // Non si stampa niente: ottantanove righe «non è cambiato niente»
        // sarebbero lo stesso rumore di prima con un altro testo.
        return;
      }
      _impronta = adesso;
    } else {
      _impronta = '';
    }

    final List<DesktopApp> scannedApps = [];
    print('[MINERVA][MATRIX][INFO] scan dirs: ${_scanDirectories.join(":")} '
        '(XDG_DATA_DIRS=${Platform.environment['XDG_DATA_DIRS'] ?? ""})');

    for (final dirPath in _scanDirectories) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        await for (final entity in dir.list(recursive: true, followLinks: true)) {
          if (entity is File && entity.path.endsWith('.desktop')) {
            final app = await _parseDesktopFile(entity);
            if (app != null) {
              scannedApps.add(app);
            }
          }
        }
      } catch (e) {
        print('[MINERVA][MATRIX][ERRORE] Errore nella scansione di $dirPath: $e');
      }
    }

    // Rimuove i doppioni tenendo il primo trovato: le directory sono in
    // ordine di precedenza XDG, quindi la versione dell'utente vince su
    // quella di sistema invece di essere sovrascritta da lei.
    final Map<String, DesktopApp> uniqueApps = {};
    for (final app in scannedApps) {
      uniqueApps.putIfAbsent(app.id.toLowerCase(), () => app);
    }

    _apps = uniqueApps.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await novita.aggiorna(_apps.map((a) => a.id));

    print('[MINERVA][MATRIX][OK] Scansione applicazioni completata. Trovate ${_apps.length} app.');
    // Con `forza` l'impronta era stata azzerata: si rimette adesso, o la
    // prossima chiamata rifarebbe tutto un'altra volta.
    if (_impronta.isEmpty) _impronta = await _improntaDelle();
  }

  /// La lingua di chi usa il computer, da `LC_MESSAGES` o `LANG`: «it_IT».
  static final String _lingua = (() {
    final env = Platform.environment;
    final v = env['LC_ALL'] ?? env['LC_MESSAGES'] ?? env['LANG'] ?? '';
    return v.split('.').first.split('@').first;
  })();

  /// Se la riga è una chiave che la ricerca vuole localizzata, dice quale e
  /// quanto la versione è vicina alla lingua dell'utente: 0 la versione senza
  /// lingua, 1 la lingua («it»), 2 lingua e paese («it_IT»). Le versioni in
  /// altre lingue restituiscono null e si ignorano.
  static (String, int)? _chiaveLocalizzata(String riga) {
    for (final k in const ['GenericName', 'Comment', 'Keywords']) {
      if (riga.startsWith('$k=')) return (k, 0);
      if (!riga.startsWith('$k[')) continue;
      final fine = riga.indexOf(']=');
      if (fine < 0) return null;
      final lingua = riga.substring(k.length + 1, fine);
      if (lingua == _lingua) return (k, 2);
      if (lingua == _lingua.split('_').first) return (k, 1);
      return null;
    }
    return null;
  }

  Future<DesktopApp?> _parseDesktopFile(File file) async {
    try {
      final lines = await file.readAsLines();
      
      String? name;
      String? exec;
      String? icon;
      String wmClass = '';
      List<String> categories = [];
      List<String> mimeTypes = [];
      bool needsTerminal = false;
      bool noDisplay = false;
      // Le chiavi che la ricerca per funzione vuole nella lingua di chi usa
      // il computer: `Chiave[it_IT]` batte `Chiave[it]`, che batte `Chiave`.
      final localizzate = <String, Map<int, String>>{};
      bool isDesktopEntry = false;

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty || line.startsWith('#')) continue;

        if (line.startsWith('[') && line.endsWith(']')) {
          isDesktopEntry = (line == '[Desktop Entry]');
          continue;
        }

        if (!isDesktopEntry) continue;

        final chiave = _chiaveLocalizzata(line);
        if (chiave != null) {
          localizzate
              .putIfAbsent(chiave.$1, () => {})
              [chiave.$2] = line.substring(line.indexOf('=') + 1).trim();
          continue;
        }

        if (line.startsWith('Name=')) {
          // Utilizza il nome principale dell'applicazione (non localizzato per ora)
          name = line.substring(5);
        } else if (line.startsWith('Exec=')) {
          // Pulisce parametri speciali come %U, %F, %f, %u
          exec = line.substring(5).replaceAll(RegExp(r'%[fFuUnNdDksiv]'), '').trim();
        } else if (line.startsWith('Icon=')) {
          icon = line.substring(5).trim();
        } else if (line.startsWith('NoDisplay=')) {
          noDisplay = (line.substring(10).trim().toLowerCase() == 'true');
        } else if (line.startsWith('Categories=')) {
          categories = line.substring(11).split(';').where((c) => c.isNotEmpty).toList();
        } else if (line.startsWith('StartupWMClass=')) {
          wmClass = line.substring(15).trim();
        } else if (line.startsWith('MimeType=')) {
          mimeTypes = line
              .substring(9)
              .split(';')
              .map((m) => m.trim())
              .where((m) => m.isNotEmpty)
              .toList();
        } else if (line.startsWith('Terminal=')) {
          needsTerminal = (line.substring(9).trim().toLowerCase() == 'true');
        }
      }

      if (noDisplay || name == null || exec == null) {
        return null;
      }

      final id = file.path.split('/').last;

      String migliore(String k) {
        final v = localizzate[k];
        if (v == null || v.isEmpty) return '';
        return v[v.keys.reduce((a, b) => a > b ? a : b)] ?? '';
      }
      final parole = <String>{};
      for (final valore in (localizzate['Keywords'] ?? const <int, String>{}).values) {
        parole.addAll(valore.split(';').map((w) => w.trim()).where((w) => w.isNotEmpty));
      }

      return DesktopApp(
        id: id,
        name: name,
        exec: exec,
        icon: icon ?? 'application-x-executable',
        generico: migliore('GenericName'),
        descrizione: migliore('Comment'),
        parole: parole.toList(),
        categories: categories,
        wmClass: wmClass,
        mimeTypes: mimeTypes,
        needsTerminal: needsTerminal,
      );
    } catch (_) {
      // Ignora errori di parsing su singoli file malformati
      return null;
    }
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../core/linux_files.dart';

/// CanaleSegreto — La parola d'ordine del canale fra il demone e le finestre.
///
/// ── IL BUCO CHE CHIUDE ─────────────────────────────────────────────────────
///
/// Il demone ascolta su `127.0.0.1:11432` (e su `11433` dentro la schermata di
/// accesso) e fino al 16 agosto 2026 **rispondeva a chiunque**. «Chiunque» su
/// un computer vuol dire ogni processo di ogni utente: un servizio di sistema,
/// un account di servizio, un programma dentro un contenitore.
///
/// Nella sessione questo dà a un estraneo il comando della scrivania —
/// `launch_app`, `kill_process`, `fs_delete`. Nella **schermata di accesso** dà
/// molto di più, e va detto per esteso perché è la ragione per cui questo file
/// esiste:
///
///   1. l'estraneo si collega alla 11433 e aspetta;
///   2. l'utente vero scrive la sua password, e PAM la accetta;
///   3. l'estraneo manda `greeter_start` con un comando e un ambiente SUOI;
///   4. greetd avvia quel comando **come l'utente appena autenticato**, con
///      una sessione PAM completa.
///
/// Non serve nemmeno indovinare la password: basta aspettare che la scriva chi
/// la sa. E `env` arbitrario vuol dire anche `LD_PRELOAD`, cioè codice dentro
/// ogni programma della sessione.
///
/// ── COSA GARANTISCE, E COSA NO ─────────────────────────────────────────────
///
/// Il segreto sta in un file leggibile **solo dal proprietario** (0600). Da qui
/// discende esattamente questo:
///
///  · **sì**: un altro utente del computer non può parlare col demone. Nella
///    schermata di accesso il demone è di `greeter` e il segreto è di
///    `greeter`: nessun altro lo legge, e l'attacco qui sopra non parte.
///  · **no**: un programma che gira **come te** può leggere il file, come può
///    leggere le tue chiavi SSH e i tuoi cookie. Non lo pretendiamo: sarebbe
///    una promessa falsa, e le promesse false in sicurezza sono peggio del
///    silenzio.
///
/// ── PERCHÉ NON L'AMBIENTE ──────────────────────────────────────────────────
///
/// Passarlo in una variabile d'ambiente sembrava più semplice, e sarebbe stato
/// peggio: l'ambiente si eredita, quindi il segreto finirebbe **dentro ogni
/// processo che lanci** — compreso quello che ti vuole male, che lo troverebbe
/// nel proprio `/proc/self/environ` senza nemmeno cercarlo.
///
/// ── IL SOCKET UNIX: SI È FATTO ─────────────────────────────────────────────
///
/// Qui c'era scritto che sarebbe stata la soluzione giusta — i permessi del
/// filesystem fanno tutto — ma che «il `WebSocket` di QtWebSockets, che è
/// quello che usano le finestre, parla solo `ws://` su TCP». **La premessa era
/// sbagliata:** `Quickshell.Io/Socket` è un `QLocalSocket`, sta dentro il
/// binario di quickshell, e non ha bisogno di QtWebSockets. Cercato il 27
/// agosto 2026, trovato in dieci minuti; era rimasto lì per un anno perché
/// nessuno era andato a guardare.
///
/// Dal 27 agosto 2026 il demone ascolta su un socket Unix in
/// `$XDG_RUNTIME_DIR/minerva/`, e **non ascolta più su TCP**. Quindi:
///
///  · la porta non esiste più, e con lei tutta la caccia al numero libero —
///    che serviva perché due sessioni insieme si contendevano la 11432, e che
///    su questa macchina inciampava nella 11434 di Ollama;
///  · un processo di un altro utente non può nemmeno **provare** a
///    collegarsi: `$XDG_RUNTIME_DIR` è 0700 e il socket è 0600. Prima poteva
///    collegarsi e sbagliare la parola d'ordine, che è una cosa diversa.
///
/// ── E ALLORA PERCHÉ LA PAROLA D'ORDINE RESTA ───────────────────────────────
///
/// Perché toglierla sarebbe stato cambiare due cose insieme — il tubo e la
/// serratura — e se qualcosa fosse andato storto non si sarebbe saputo quale
/// delle due. Adesso sono due serrature indipendenti: i permessi del
/// filesystem e il segreto. Togliere la seconda si può fare domani, con calma,
/// e non guadagna sicurezza: guadagna solo qualche riga in meno.
class CanaleSegreto {
  CanaleSegreto._();

  /// Nome del file. Sta accanto alle altre cose del canale, non fra le
  /// impostazioni: non è una preferenza, è l'indirizzo di casa.
  ///
  /// Dentro ci sono DUE cose, una per riga:
  ///
  ///     socket=/run/user/1000/minerva/canale-2.sock
  ///     segreto=xxxxxxxx
  ///
  /// L'indirizzo e non solo il segreto, perché due sessioni possono essere
  /// accese insieme e ognuna ha il suo socket. Chi apre una finestra scopre
  /// così **dove** e **come** parlare leggendo un file solo, invece di
  /// indovinare e trovarci il demone di un'altra sessione.
  ///
  /// Fino al 27 agosto 2026 la prima riga diceva `porta=11432`. Chi legge un
  /// file vecchio non trova più `socket=` e deve dirlo, invece di collegarsi
  /// a un posto che non c'è: vedi `Ipc.qml`.
  ///
  /// Con chiavi nominate e non due righe nude: aggiungerci qualcosa domani non
  /// deve rompere chi legge oggi.
  static const String nomeFile = 'canale';

  /// Il nome di questa sessione.
  ///
  /// **La stessa regola sta in `scripts/minerva-posti.sh` e in
  /// `minerva-shell/core/Ipc.qml`**, e c'è una prova che confronta i tre.
  /// Se divergono, il demone scrive in un posto e la shell cerca in un altro:
  /// due programmi giusti e una scrivania che non si connette.
  static String sessione() {
    final env = Platform.environment;
    var s = env['MINERVA_SESSIONE'] ?? '';
    if (s.isEmpty) s = env['XDG_SESSION_ID'] ?? '';
    if (s.isEmpty && (env['XDG_VTNR'] ?? '').isNotEmpty) {
      s = 'vt${env['XDG_VTNR']}';
    }
    if (s.isEmpty) s = 'unica';
    // Ripulito: finisce in un percorso, e una variabile d'ambiente la può
    // riempire chiunque.
    s = s.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return s.isEmpty ? 'unica' : s;
  }

  /// Dove sta il segreto.
  ///
  /// L'ordine, e il perché:
  ///
  ///  1. `MINERVA_TOKEN_FILE` — lo dice chi ci ha lanciati. Serve alle prove,
  ///     che non devono toccare il file vero di chi sta lavorando.
  ///  2. `$XDG_RUNTIME_DIR/minerva/` — il posto giusto per un segreto: è in
  ///     memoria (tmpfs), è 0700 di chi ha fatto l'accesso, e sparisce da solo
  ///     alla fine della sessione. Un segreto non deve sopravvivere a un
  ///     riavvio, e in una cartella di configurazione lo farebbe — magari
  ///     dentro un backup, o in una cartella sincronizzata.
  ///  3. la cartella di configurazione — ripiego per quando la cartella di
  ///     runtime non c'è. Dentro la schermata di accesso può capitare: la
  ///     sessione di `greeter` non è una sessione utente normale, e
  ///     `MINERVA_CONFIG_DIR` lì punta a `/var/lib/minerva-greeter`, che è
  ///     suo e chiuso.
  ///
  /// **La stessa regola sta scritta in `minerva-shell/core/Ipc.qml`**, perché
  /// il file lo devono trovare tutti e due. Se si cambia qui va cambiata lì:
  /// c'è una prova che confronta le due (`canale_segreto_test.dart`).
  static List<String> candidati({String? cartellaConfigurazione}) {
    final env = Platform.environment;
    final fuori = <String>[];

    final detto = env['MINERVA_TOKEN_FILE'];
    if (detto != null && detto.isNotEmpty) {
      // Chi ce l'ha detto vince, e da solo: se qualcuno ha scelto il posto,
      // ripiegare altrove vorrebbe dire ignorarlo in silenzio.
      return [detto];
    }

    final ses = sessione();

    final runtime = env['XDG_RUNTIME_DIR'];
    if (runtime != null && runtime.isNotEmpty) {
      fuori.add('${_senzaBarra(runtime)}/minerva/sessioni/$ses/$nomeFile');
    }

    final conf = cartellaConfigurazione ?? _cartellaConfigurazione();
    if (conf.isNotEmpty) {
      fuori.add('${_senzaBarra(conf)}/sessioni/$ses/$nomeFile');
    }

    return fuori;
  }

  /// Il primo posto della lista. Serve a chi vuole solo dire dove ANDREBBE.
  static String percorso({String? cartellaConfigurazione}) {
    final lista = candidati(cartellaConfigurazione: cartellaConfigurazione);
    return lista.isEmpty ? '' : lista.first;
  }

  static String _cartellaConfigurazione() {
    final env = Platform.environment;
    final detto = env['MINERVA_CONFIG_DIR'];
    if (detto != null && detto.isNotEmpty) return detto;
    final xdg = env['XDG_CONFIG_HOME'];
    if (xdg != null && xdg.isNotEmpty) return '${_senzaBarra(xdg)}/minerva';
    return '${env['HOME'] ?? ''}/.config/minerva';
  }

  static String _senzaBarra(String p) =>
      p.endsWith('/') && p.length > 1 ? p.substring(0, p.length - 1) : p;

  /// Un segreto nuovo: 32 byte dal generatore sicuro del sistema.
  ///
  /// `Random.secure()` in Dart legge da `/dev/urandom` (o dall'equivalente del
  /// sistema). `Random()` normale sarebbe indovinabile conoscendo l'istante di
  /// avvio, che di un demone di sessione si sa benissimo.
  static String generaSegreto() {
    final caso = Random.secure();
    final byte = List<int>.generate(32, (_) => caso.nextInt(256));
    // In base64url e senza riempimento: deve poter viaggiare dentro un JSON e
    // stare su una riga di un file, senza caratteri da scappare.
    return base64Url.encode(byte).replaceAll('=', '');
  }

  /// Dove è finito davvero, dopo `scriviNuovo`. Serve al registro: sapere in
  /// quale dei posti possibili è andato è la prima cosa da guardare quando una
  /// finestra non si connette.
  static String scrittoIn = '';

  /// Scrive un segreto nuovo e lo restituisce.
  ///
  /// **Nuovo a ogni avvio del demone**, non riusato: un segreto rubato una
  /// volta scadrebbe altrimenti mai. Le finestre lo rileggono a ogni
  /// connessione, quindi un demone che riparte non le lascia fuori.
  ///
  /// Si prova un posto dopo l'altro, e chi non riesce a scriverne nessuno
  /// muore invece di partire senza: vedi il commento dentro.
  ///
  /// I permessi si mettono con `chmod`, che è un processo esterno, perché Dart
  /// non sa cambiare i permessi di un file. È una volta sola all'avvio, e
  /// senza quella riga il file nascerebbe leggibile da tutti — cioè il buco
  /// resterebbe aperto con un passaggio in più.
  static Future<String> scriviNuovo(
      {String? percorsoFile, required String socket}) async {
    final lista = percorsoFile != null ? [percorsoFile] : candidati();
    if (lista.isEmpty) {
      throw StateError('Non so dove scrivere la parola d\'ordine del canale: '
          'né XDG_RUNTIME_DIR né una cartella di configurazione.');
    }

    Object? ultimoGuaio;
    for (final path in lista) {
      try {
        final segreto = await _scriviIn(path, socket);
        scrittoIn = path;
        return segreto;
      } catch (e) {
        // Si prova il posto dopo. Capita davvero dentro la schermata di
        // accesso: l'utente `greeter` può avere `XDG_RUNTIME_DIR` impostato su
        // una cartella che non esiste e che non ha il diritto di creare.
        //
        // La lezione è del 10 agosto 2026, e costa cara: allora fu
        // `PluginManager.init()` a creare una cartella dove non poteva
        // scrivere, e il demone del greeter moriva un istante dopo aver aperto
        // la porta. A schermo si vedeva la schermata di accesso intera, bella,
        // **con l'elenco utenti vuoto**. Un servizio accessorio non deve poter
        // chiudere fuori dal computer.
        ultimoGuaio = e;
        stdout.writeln('[MINERVA][IPC][ATTENZIONE] Non riesco a scrivere la '
            'parola d\'ordine in $path: $e');
      }
    }

    // Nessun posto ha funzionato. Si muore, e questa è una scelta:
    // partire senza parola d'ordine vorrebbe dire riaprire il canale a
    // chiunque proprio quando qualcosa è già andato storto — e nessuno se ne
    // accorgerebbe, perché tutto continuerebbe a funzionare.
    throw StateError('Non sono riuscito a scrivere la parola d\'ordine del '
        'canale in nessuno di questi posti: ${lista.join(", ")}. '
        'Ultimo errore: $ultimoGuaio');
  }

  /// C'è già un altro Minerva VIVO dietro l'indirizzo scritto in questo file?
  ///
  /// Si risponde bussando: un socket Unix a cui qualcuno risponde è un demone
  /// acceso; uno rimasto per terra dopo un `kill -9` rifiuta la connessione.
  /// Non ci sono altri modi onesti — un file che esiste non vuol dire niente.
  static Future<bool> _qualcunoRisponde(String socket) async {
    if (socket.isEmpty) return false;
    try {
      final s = await Socket.connect(
              InternetAddress(socket, type: InternetAddressType.unix), 0)
          .timeout(const Duration(milliseconds: 300));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// ── Non si scrive sopra l'indirizzo di una sessione VIVA ────────────────
  ///
  /// Scoperto il 31 agosto 2026, e per sbaglio: un `minervad --test-start`
  /// lanciato con un `MINERVA_IPC_SOCKET` suo ha scritto lo stesso il proprio
  /// indirizzo nel file della sessione IN CORSO. Il socket di prova è sparito
  /// un secondo dopo, e la scrivania di chi stava lavorando è rimasta con in
  /// mano l'indirizzo di un socket che non esisteva più: al primo riavvio
  /// della shell sarebbe rimasta senza demone — cioè senza dock e senza menù,
  /// che è esattamente il guasto che si stava riparando.
  ///
  /// Una prova non deve poter rendere inservibile la macchina su cui gira.
  ///
  /// La regola è stretta apposta, e NON impedisce il caso normale: si rifiuta
  /// solo se il file nomina un socket **diverso dal nostro** e dietro a quel
  /// socket **risponde qualcuno**. Un demone che riparte riscrive il proprio
  /// indirizzo (stesso socket) e passa; un socket rimasto per terra non
  /// risponde e passa.
  static Future<void> _nonRubareIlPosto(String path, String socket) async {
    final file = File(path);
    if (!await file.exists()) return;
    String testo;
    try {
      testo = await file.readAsString();
    } catch (_) {
      return;
    }
    final altro = leggi(testo)['socket'] ?? '';
    if (altro.isEmpty || altro == socket) return;
    if (!await _qualcunoRisponde(altro)) return;
    throw StateError(
        'In «$path» c\'è l\'indirizzo di un Minerva ancora acceso ($altro) e '
        'io ascolto altrove ($socket): non lo sovrascrivo. Sovrascriverlo '
        'lascerebbe quella scrivania senza demone — cioè senza dock e senza '
        'menù — appena la sua shell si riavvia. Se sei una prova, datti una '
        'sessione tua con MINERVA_SESSIONE.');
  }

  static Future<String> _scriviIn(String path, String socket) async {
    final file = File(path);
    final cartella = file.parent;
    // Non seguire né il nome del segreto né directory simboliche.
    for (var d = cartella.absolute; ; d = d.parent) {
      if (await FileSystemEntity.type(d.path, followLinks: false) == FileSystemEntityType.link) {
        throw FileSystemException('Directory simbolica non ammessa per il segreto', d.path);
      }
      if (d.path == d.parent.path) break;
    }
    final tipo = await FileSystemEntity.type(path, followLinks: false);
    if (tipo != FileSystemEntityType.notFound && tipo != FileSystemEntityType.file) {
      throw FileSystemException('Il segreto non è un file regolare', path);
    }
    if (!await cartella.exists()) {
      await cartella.create(recursive: true);
      await _permessi('700', cartella.path);
    }
    final owner = await Process.run('stat', ['-c', '%u', '--', cartella.path]);
    final uid = await Process.run('id', ['-u']);
    if (owner.exitCode != 0 || uid.exitCode != 0 ||
        '${owner.stdout}'.trim() != '${uid.stdout}'.trim() ||
        ((await cartella.stat()).mode & 0x12) != 0) {
      throw FileSystemException('Il segreto richiede una directory privata del nostro utente', cartella.path);
    }
    await _nonRubareIlPosto(path, socket);
    final segreto = generaSegreto();
    final staging = LinuxFiles.privateTemp(cartella, '.minerva-segreto-');
    try {
      final pronto = File('${staging.path}/canale');
      await pronto.writeAsString('');
      await _permessi('600', pronto.path);
      await pronto.writeAsString('socket=$socket\nsegreto=$segreto\n', flush: true);
      // rename sostituisce il nome, non apre il suo eventuale bersaglio.
      await pronto.rename(path);
    } finally {
      await staging.delete(recursive: true);
    }
    return segreto;
  }

  /// Legge il file e ne tira fuori le coppie `chiave=valore`.
  ///
  /// Serve alle prove e a chiunque debba sapere dove sta il canale senza
  /// essere il demone che l'ha scritto.
  static Map<String, String> leggi(String testo) {
    final fuori = <String, String>{};
    for (final riga in testo.split('\n')) {
      final r = riga.trim();
      if (r.isEmpty || r.startsWith('#')) continue;
      final i = r.indexOf('=');
      if (i <= 0) continue;
      fuori[r.substring(0, i).trim()] = r.substring(i + 1).trim();
    }
    return fuori;
  }

  static Future<void> _permessi(String modo, String path) async {
    final r = await Process.run('chmod', [modo, '--', path]);
    if (r.exitCode != 0) {
      throw FileSystemException('Impossibile proteggere il segreto: ${r.stderr}', path);
    }
  }

  /// Il confronto, a tempo costante.
  ///
  /// Un `==` normale si ferma al primo carattere diverso, e quel «si ferma
  /// prima» è misurabile: si indovina il segreto un carattere alla volta.
  /// Su un canale locale è un attacco difficile — ma costa tre righe farlo
  /// bene, e non ha senso lasciare in giro l'unica primitiva di sicurezza del
  /// progetto scritta male.
  static bool combacia(String atteso, String? offerto) {
    if (offerto == null) return false;
    if (atteso.isEmpty) return false;
    final a = utf8.encode(atteso);
    final b = utf8.encode(offerto);
    // La lunghezza sì, si può confrontare subito: non dice niente di più di
    // quanto dica il formato, che è pubblico.
    if (a.length != b.length) return false;
    var differenza = 0;
    for (var i = 0; i < a.length; i++) {
      differenza |= a[i] ^ b[i];
    }
    return differenza == 0;
  }
}

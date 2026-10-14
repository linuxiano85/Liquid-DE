import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'processo_limitato.dart';

/// Cartelle di rete e telefoni nel gestore file, attraverso gvfs.
///
/// ── Perché gvfs ──────────────────────────────────────────────────────────
///
/// gvfs è già acceso in ogni sessione (`gvfsd`), e ogni luogo che monta
/// compare anche come cartella normale sotto `/run/user/<uid>/gvfs/`. Quindi
/// il gestore file non deve imparare protocolli: una volta collegato, un
/// server Samba o un telefono si sfoglia, si copia e si apre con lo stesso
/// codice delle cartelle di casa. E i programmi GTK vedono gli stessi
/// collegamenti, senza montarli una seconda volta.
///
/// Si parla con gvfs tramite `gio mount`, sempre con `LC_ALL=C`: le domande
/// che fa («User», «Password») e le righe che stampa si riconoscono solo in
/// inglese.
///
/// ── Le password ──────────────────────────────────────────────────────────
///
/// Non passano mai sulla riga di comando (la vede chiunque con `ps`): si
/// scrivono a `gio` sul suo stdin, una alla volta, solo quando le chiede.
/// Qui non si salvano.
///
/// ── Revisione del gestore file, 11 ottobre 2026 ──────────────────────────
///
/// Prima di questo servizio non c'era nessun modo di aprire una cartella
/// condivisa o un telefono dal gestore file.
class LuoghiRemoti {
  LuoghiRemoti({
    this.gio = 'gio',
    this.cartellaProtocolli = '/usr/share/gvfs/mounts',
    Set<String> schemiInPiu = const {},
    Map<String, String> ambienteInPiu = const {},
  }) : _schemi = {..._schemiDiSerie, ...schemiInPiu},
       _ambiente = {..._ambienteDiSerie, ...ambienteInPiu};

  /// Il programma da lanciare. Le prove ne passano uno finto.
  final String gio;

  /// Dove gvfs tiene un file `.mount` per ogni protocollo installato.
  final String cartellaProtocolli;

  final Set<String> _schemi;

  /// Le prove ci mettono un bus D-Bus tutto loro, per non montare niente
  /// nella sessione di chi le lancia.
  final Map<String, String> _ambiente;

  /// Gli indirizzi che si accettano. Un elenco chiuso: `gio mount` monta
  /// anche `file://` e `trash://`, che qui non hanno senso.
  static const Set<String> _schemiDiSerie = {
    'smb',
    'sftp',
    'ssh',
    'ftp',
    'ftps',
    'dav',
    'davs',
    'nfs',
    'afp',
    'mtp',
    'gphoto2',
    'afc',
  };

  /// Quale file `.mount` serve per ogni schema, e quale pacchetto lo porta
  /// (il nome di Arch; su Debian e Ubuntu sono tutti in `gvfs-backends`).
  static const Map<String, List<String>> _backend = {
    'smb': ['smb', 'gvfs-smb'],
    'sftp': ['sftp', 'gvfs'],
    'ssh': ['sftp', 'gvfs'],
    'ftp': ['ftp', 'gvfs'],
    'ftps': ['ftps', 'gvfs'],
    'dav': ['dav', 'gvfs-dnssd'],
    'davs': ['dav', 'gvfs-dnssd'],
    'nfs': ['nfs', 'gvfs-nfs'],
    'afp': ['afp', 'gvfs-afp'],
    'mtp': ['mtp', 'gvfs-mtp'],
    'gphoto2': ['gphoto2', 'gvfs-gphoto2'],
    'afc': ['afc', 'gvfs-afc'],
  };

  static const Map<String, String> _ambienteDiSerie = {
    'LC_ALL': 'C',
    'LANG': 'C',
  };

  static const Duration _attesaCollega = Duration(seconds: 60);

  // ── Indirizzi ──────────────────────────────────────────────────────────

  /// Porta quello che si scrive nella casella a un indirizzo che `gio`
  /// capisce. `\\server\cartella` (come lo scrive Windows) e
  /// `server/cartella` senza protocollo diventano Samba, che è quello che si
  /// trova quasi sempre in una rete di casa o d'ufficio.
  ///
  /// Ritorna null se l'indirizzo non va bene.
  String? normalizza(String scritto) {
    var s = scritto.trim();
    if (s.isEmpty || s.startsWith('-')) return null;
    if (s.contains(RegExp(r'[\s\x00-\x1f]'))) return null;
    if (s.startsWith(r'\\')) {
      s = 'smb://${s.substring(2).replaceAll(r'\', '/')}';
    } else if (!s.contains('://')) {
      s = 'smb://$s';
    }
    if (_schemaUsb(s).isNotEmpty) {
      return s;
    }
    final uri = Uri.tryParse(s);
    if (uri == null || !_schemi.contains(uri.scheme)) return null;
    if (uri.host.isEmpty && !_senzaHost.contains(uri.scheme)) return null;
    return s;
  }

  /// Questi si riconoscono dal dispositivo, non da un nome di rete.
  static const Set<String> _senzaHost = {'mtp', 'gphoto2', 'afc', 'localtest'};

  // GVfs usa anche [usb:002,015] al posto dell'host: non è IPv6, quindi
  // Uri.tryParse lo rifiuta. Si ammette solo la radice USB numerica di MTP/PTP.
  static String _schemaUsb(String indirizzo) {
    final radice = RegExp(r'^(mtp|gphoto2)://\[usb:(\d{3}),(\d{3})\]/?$')
        .firstMatch(indirizzo);
    if (radice == null) {
      return '';
    }
    final bus = int.parse(radice.group(2)!);
    final dispositivo = int.parse(radice.group(3)!);
    return bus > 0 && dispositivo > 0 && dispositivo <= 127
        ? radice.group(1)! : '';
  }

  static String _schemaDi(String uri) {
    return Uri.tryParse(uri)?.scheme ?? _schemaUsb(uri);
  }

  /// Che cosa è, per l'icona: un telefono, una cartella condivisa, un server.
  static String tipoDi(String uri) {
    final schema = _schemaDi(uri);
    if (const {'mtp', 'gphoto2', 'afc'}.contains(schema)) return 'telefono';
    if (schema == 'smb' || schema == 'nfs' || schema == 'afp')
      return 'condivisa';
    return 'server';
  }

  // ── Cosa c'è ───────────────────────────────────────────────────────────

  /// I luoghi già collegati e i telefoni attaccati ma non ancora aperti.
  ///
  /// Torna anche i protocolli che questa macchina sa aprire e i pacchetti
  /// che mancano per gli altri: un telefono che non compare perché manca
  /// `gvfs-mtp` deve dirlo, non sembrare rotto.
  Future<Map<String, dynamic>> elenco() async {
    final protocolli = await _protocolliInstallati();
    final mancano = <String>{};
    for (final schema in const ['smb', 'mtp', 'gphoto2']) {
      final b = _backend[schema]!;
      if (!protocolli.contains(b[0])) mancano.add(b[1]);
    }

    UscitaLimitata r;
    try {
      r = await eseguiLimitato(gio, ['mount', '-l', '-i'], ambiente: _ambiente);
    } on ProcessException catch (e) {
      return {
        'luoghi': [],
        'mancano': mancano.toList(),
        'protocolli': protocolli.toList()..sort(),
        'error': e.message,
      };
    }
    final luoghi = <Map<String, dynamic>>[];
    for (final l in leggiElenco(r.stdout)) {
      if (l['montato'] == true) {
        l['percorso'] = await _percorsoLocale(l['uri'] as String);
      }
      luoghi.add(l);
    }
    return {
      'luoghi': luoghi,
      'mancano': mancano.toList(),
      'protocolli': protocolli.toList()..sort(),
      'error': r.ok ? '' : (r.stderr.trim().isNotEmpty
          ? r.stderr.trim() : 'GVfs non ha completato la verifica dei dispositivi.'),
    };
  }

  /// Legge l'uscita di `gio mount -l -i`.
  ///
  /// Un luogo montato è una riga `Mount(n): nome -> uri`; un telefono
  /// attaccato e non montato è un `Volume(n): nome` con sotto
  /// `activation_root=uri`. I dischi di UDisks (uri `file://`, nessuna
  /// `activation_root`) li mostra già la sezione dei dischi, e qui si
  /// saltano.
  List<Map<String, dynamic>> leggiElenco(String testo) {
    final montati = <Map<String, dynamic>>[];
    final volumi = <Map<String, dynamic>>[];
    Map<String, dynamic>? volume;
    final rigaMount = RegExp(r'^\s*Mount\(\d+\): (.*) -> (\S+)\s*$');
    final rigaVolume = RegExp(r'^\s*Volume\(\d+\): (.*?)\s*$');
    final rigaRadice = RegExp(r'^\s*activation_root=(\S+)\s*$');
    for (final riga in const LineSplitter().convert(testo)) {
      final m = rigaMount.firstMatch(riga);
      if (m != null) {
        final uri = m.group(2)!;
        if (!uri.startsWith('file:')) {
          montati.add({
            'nome': m.group(1)!,
            'uri': uri,
            'tipo': tipoDi(uri),
            'montato': true,
          });
        }
        continue;
      }
      final v = rigaVolume.firstMatch(riga);
      if (v != null) {
        volume = {'nome': v.group(1)!, 'uri': '', 'montato': false};
        volumi.add(volume);
        continue;
      }
      final a = rigaRadice.firstMatch(riga);
      if (a != null && volume != null) {
        volume['uri'] = a.group(1)!;
        volume['tipo'] = tipoDi(a.group(1)!);
      }
    }
    final fuori = [...montati];
    for (final v in volumi) {
      final uri = v['uri'] as String;
      if (uri.isEmpty || uri.startsWith('file:')) continue;
      // Già montato: c'è già la sua riga `Mount`.
      if (montati.any((m) => _stessoLuogo(m['uri'] as String, uri))) continue;
      fuori.add(v);
    }
    return fuori;
  }

  static bool _stessoLuogo(String a, String b) {
    String senzaBarra(String s) =>
        s.endsWith('/') ? s.substring(0, s.length - 1) : s;
    return senzaBarra(a) == senzaBarra(b);
  }

  Future<Set<String>> _protocolliInstallati() async {
    final fuori = <String>{};
    try {
      await for (final f in Directory(cartellaProtocolli).list()) {
        final nome = f.uri.pathSegments.last;
        if (nome.endsWith('.mount'))
          fuori.add(nome.substring(0, nome.length - 6));
      }
    } on FileSystemException {
      // Niente gvfs: nessun protocollo.
    }
    return fuori;
  }

  /// La cartella sotto `/run/user/<uid>/gvfs` dove gvfs mostra il luogo.
  Future<String> _percorsoLocale(String uri) async {
    try {
      final r = await eseguiLimitato(gio, [
        'info',
        '--',
        uri,
      ], ambiente: _ambiente);
      final m = RegExp(
        r'^local path: (.+)$',
        multiLine: true,
      ).firstMatch(r.stdout);
      return m?.group(1)?.trim() ?? '';
    } on ProcessException {
      return '';
    }
  }

  // ── Collegare ──────────────────────────────────────────────────────────

  /// Collega un luogo e ritorna la sua cartella locale.
  ///
  /// La prima volta si prova senza credenziali: una cartella aperta a tutti,
  /// un telefono, un server con la chiave SSH non chiedono niente. Se `gio`
  /// chiede utente o password e non li abbiamo, ci si ferma e si risponde
  /// `serveAccesso`; l'interfaccia li chiede e si riprova.
  ///
  /// Se il server non è conosciuto (SFTP la prima volta), gvfs chiede se
  /// fidarsi: ci si ferma con `domanda`, e si riprova con `fidati` solo
  /// dopo che la persona l'ha letta e ha detto di sì.
  Future<Map<String, dynamic>> collega(
    String scritto, {
    String utente = '',
    String dominio = '',
    String password = '',
    bool anonimo = false,
    bool fidati = false,
  }) async {
    final uri = normalizza(scritto);
    if (uri == null) {
      return {
        'ok': false,
        'error':
            'Indirizzo non valido. Esempi: smb://server/cartella, '
            'sftp://utente@server, ftp://server',
      };
    }
    final schema = _schemaDi(uri);
    final backend = _backend[schema];
    if (backend != null &&
        !(await _protocolliInstallati()).contains(backend[0])) {
      return {
        'ok': false,
        'uri': uri,
        'error':
            'Per aprire indirizzi $schema:// serve il pacchetto ${backend[1]}.',
        'manca': backend[1],
      };
    }

    final conCredenziali = password.isNotEmpty || utente.isNotEmpty;
    final argomenti = ['mount', if (anonimo) '--anonymous', '--', uri];
    Process p;
    try {
      p = await Process.start(gio, argomenti, environment: _ambiente);
    } on ProcessException catch (e) {
      return {'ok': false, 'uri': uri, 'error': e.message};
    }

    final fuori = StringBuffer();
    final errori = StringBuffer();
    var letto = 0; // fin dove si è già risposto
    var passwordChieste = 0;
    Map<String, dynamic>? fermato;
    final finito = Completer<void>();

    void ferma(Map<String, dynamic> perche) {
      fermato ??= perche;
      p.kill(ProcessSignal.sigkill);
    }

    void rispondi(String riga) {
      try {
        p.stdin.writeln(riga);
      } catch (_) {
        // Il processo è già finito: la risposta non serve più.
      }
    }

    final domanda = RegExp(
      r'(User|Domain|Password|Choice)(?: \[[^\]\n]*\])?: $',
    );

    void guarda() {
      final nuovo = fuori.toString().substring(letto);
      final m = domanda.firstMatch(nuovo);
      if (m == null) return;
      final messaggio = nuovo.substring(0, m.start).trim();
      letto += m.end;
      switch (m.group(1)) {
        case 'User':
          if (!conCredenziali) {
            ferma({'serveAccesso': true, 'messaggio': messaggio});
          } else {
            // Una riga vuota accetta il nome proposto fra parentesi.
            rispondi(utente);
          }
        case 'Domain':
          rispondi(dominio);
        case 'Password':
          passwordChieste++;
          if (!conCredenziali) {
            ferma({'serveAccesso': true, 'messaggio': messaggio});
          } else if (passwordChieste > 1) {
            // gvfs richiede la password solo se quella data era sbagliata.
            ferma({
              'serveAccesso': true,
              'sbagliate': true,
              'messaggio': messaggio,
            });
          } else {
            rispondi(password);
          }
        case 'Choice':
          // Il testo delle scelte lo scrive gvfsd, nella lingua della
          // sessione: non lo si può riconoscere. In gvfs l'unica domanda
          // all'accesso è quella di SFTP sul server sconosciuto, e la
          // scelta [1] è «Accedi comunque».
          final scelta = RegExp(
            r'^\[1\] ',
            multiLine: true,
          ).hasMatch(messaggio);
          if (fidati && scelta) {
            rispondi('1');
          } else {
            final testo = messaggio
                .split('\n')
                .where((r) => !r.startsWith('['))
                .join('\n')
                .trim();
            ferma({'domanda': testo});
          }
      }
    }

    p.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (pezzo) {
            fuori.write(pezzo);
            guarda();
          },
          onDone: () => finito.complete(),
          onError: (Object _) {},
        );
    p.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(errori.write, onError: (Object _) {});

    int codice;
    try {
      codice = await p.exitCode.timeout(_attesaCollega);
    } on TimeoutException {
      ferma({
        'error':
            'Il server non ha risposto in ${_attesaCollega.inSeconds} secondi.',
      });
      codice = await p.exitCode;
    }
    await finito.future.timeout(
      const Duration(milliseconds: 500),
      onTimeout: () {},
    );
    unawaited(p.stdin.close().then((_) {}, onError: (Object _) {}));

    if (fermato != null) {
      final r = <String, dynamic>{
        'ok': false,
        'uri': uri,
        'error': '',
        ...fermato!,
      };
      if (r['sbagliate'] == true) r['error'] = 'Utente o password sbagliati.';
      if (r['serveAccesso'] == true) r['dominio'] = schema == 'smb';
      return r;
    }
    final err = errori.toString().trim();
    // «Già montato» non si riconosce dal testo: lo scrive gvfsd, tradotto.
    // Se il luogo ha già la sua cartella, è collegato, e va bene così.
    if (codice != 0 && (await _percorsoLocale(uri)).isEmpty) {
      return {'ok': false, 'uri': uri, 'error': _spiega(err)};
    }
    // La cartella sotto `gvfs/` la crea `gvfsd-fuse`, che la prima volta
    // nella sessione parte un attimo dopo il collegamento: si aspetta un po'.
    var percorso = '';
    for (var i = 0; i < 10 && percorso.isEmpty; i++) {
      if (i > 0) await Future<void>.delayed(const Duration(milliseconds: 200));
      percorso = await _percorsoLocale(uri);
    }
    return {'ok': true, 'uri': uri, 'error': '', 'percorso': percorso};
  }

  /// `gio: smb://x/: Failed to mount Windows share: Connection refused`
  /// diventa `Failed to mount Windows share: Connection refused`: il resto
  /// lo sa già chi ha scritto l'indirizzo.
  static String _spiega(String err) {
    final riga = err
        .split('\n')
        .lastWhere((r) => r.trim().isNotEmpty, orElse: () => '');
    final m = RegExp(r'^gio: \S+: (.*)$').firstMatch(riga);
    final testo = (m?.group(1) ?? riga).trim();
    return testo.isEmpty ? 'Collegamento non riuscito.' : testo;
  }

  /// Scollega un luogo. Per gvfs è smontare; per chi guarda è chiuderlo.
  Future<Map<String, dynamic>> scollega(String uri) async {
    final valido = normalizza(uri);
    if (valido == null || valido != uri) {
      return {'ok': false, 'error': 'Indirizzo non valido.'};
    }
    try {
      final r = await eseguiLimitato(
        gio,
        ['mount', '-u', '--', uri],
        ambiente: _ambiente,
        limite: const Duration(seconds: 15),
      );
      if (r.ok) return {'ok': true, 'error': ''};
      return {
        'ok': false,
        'error': r.scaduto ? 'Non risponde.' : _spiega(r.stderr),
      };
    } on ProcessException catch (e) {
      return {'ok': false, 'error': e.message};
    }
  }
}

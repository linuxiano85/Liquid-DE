import 'dart:convert';
import 'dart:io';

import 'dbus.dart';
import 'mime_service.dart';
import 'schermi_esterni.dart';
import 'trasmetti_service.dart';

/// Mandare un file a qualcun altro: per Bluetooth, per posta, o a un programma.
///
/// ── Perché sta nel demone e non nel gestore file ───────────────────────────
///
/// Perché nessuna di queste tre cose è disegnare. Il Bluetooth è una
/// conversazione con `org.bluez.obex` sul bus, la posta è la tabella dei
/// programmi predefiniti, e «apri con» è già roba di `mime_service`. Il
/// gestore file mostra un elenco e aspetta una risposta; qui c'è chi sa
/// davvero cosa la macchina può fare adesso.
///
/// ── La regola di questo file ───────────────────────────────────────────────
///
/// **Non si offre una destinazione che non può funzionare, e quando non può si
/// dice perché.** Una voce «Email» che apre un programma incapace di allegare
/// il file è peggio che non avere la voce: chi la usa crede di aver mandato
/// qualcosa.
///
/// Per questo `destinazioni()` non restituisce un elenco di nomi ma un elenco
/// di stati, ognuno con il suo motivo scritto in italiano.
class CondivisioneService {
  CondivisioneService(this._mime, this._trasmetti);

  final MimeService _mime;

  /// Chi sa parlare ai televisori. È lo STESSO servizio che usa il menu del
  /// tasto destro e la piastrella del pannello, e non una seconda strada:
  /// due strade vorrebbero dire due trasmissioni insieme, due porte, e la
  /// seconda finirebbe nello schermo nero silenzioso che
  /// `foto/servizio_effimero.dart` racconta.
  final TrasmettiService _trasmetti;

  /// La scoperta dei televisori. Tiene in caldo l'ultimo elenco: cercarli
  /// costa due secondi di rete, e un menù che ci mette due secondi ad aprirsi
  /// non lo apre nessuno.
  final SchermiEsterni _schermi = SchermiEsterni();

  /// I programmi che sanno davvero prendere un allegato da `xdg-email`.
  ///
  /// L'elenco è di programmi di POSTA, non di browser. Un browser registrato
  /// su `mailto:` apre la sua pagina di composizione, e quella pagina non può
  /// leggere un file dal tuo disco: l'allegato sparisce e nessuno lo dice.
  /// Su questa macchina il gestore predefinito è Firefox, ed è esattamente il
  /// caso in cui la voce va mostrata spenta con la sua ragione.
  static const Set<String> _programmiDiPosta = {
    'thunderbird',
    'betterbird',
    'evolution',
    'geary',
    'kmail',
    'org.kde.kmail2',
    'claws-mail',
    'sylpheed',
    'mutt',
    'neomutt',
    'bluemail',
    'mailspring',
  };

  // Nota che resta vera anche ora che l'invio passa da `obexctl`: il servizio
  // OBEX di BlueZ vive sul bus di SESSIONE, non su quello di sistema come il
  // resto del Bluetooth. `org.bluez` è di sistema, `org.bluez.obex` è tuo — è
  // la distinzione che fa perdere più tempo a chi ci mette le mani.

  // ── Chi può ricevere ──────────────────────────────────────────────────────

  /// Che cosa si può fare adesso, con i motivi di quello che non si può.
  ///
  /// Torna sempre tutte le destinazioni, anche quelle spente: sparire è la
  /// cosa peggiore che possa fare una voce di menu, perché chi la cercava
  /// resta a chiedersi se l'ha sognata.
  Future<Map<String, dynamic>> destinazioni() async {
    final bt = await _bluetooth();
    final posta = await _posta();
    final schermo = await _schermo();
    return {
      'ok': true,
      'destinazioni': [bt, posta, schermo],
    };
  }

  /// Gli schermi esterni: i televisori trovati in rete.
  ///
  /// ── È stata spenta per venti giorni, e adesso è accesa ────────────────
  ///
  /// Fino al 4 settembre 2026 questa voce rispondeva sempre «Trovato
  /// «Cucina», ma non so ancora parlargli»: la scoperta funzionava, il
  /// protocollo no. CASTV2 è TLS su 8009 con messaggi protobuf, e un
  /// Chromecast non riceve il file — se lo va a prendere da un servizio HTTP
  /// che dobbiamo aprire noi. Era un lavoro a sé e andava fatto con calma: un
  /// servizio che pubblica le foto di casa sulla rete è precisamente il
  /// difetto da non scrivere di corsa.
  ///
  /// Adesso c'è (`trasmetti_service.dart`), è provato, e ha mandato
  /// fotografie vere su televisori veri. La voce si accende.
  ///
  /// Resta la regola che l'ha tenuta visibile mentre era spenta: **sparire è
  /// la cosa peggiore che possa fare una voce di menu**, perché chi la
  /// cercava resta a chiedersi se l'ha sognata. Quando non c'è nessun
  /// televisore, la voce c'è lo stesso e dice perché.
  Future<Map<String, dynamic>> _schermo() async {
    final trovati = await _schermi.cerca();
    if (trovati.isEmpty) {
      return {
        'id': 'schermo',
        'nome': 'Trasmetti a schermo',
        'icona': 'screen',
        'disponibile': false,
        'motivo': 'Nessun televisore trovato in rete. Deve essere acceso e '
            'sulla stessa rete di questo computer.',
        'dispositivi': const <Map<String, dynamic>>[],
      };
    }
    return {
      'id': 'schermo',
      'nome': 'Trasmetti a schermo',
      'icona': 'screen',
      'disponibile': true,
      // `motivo` è **perché non si può**, e qui si può: resta vuoto. I nomi
      // dei televisori non stanno qui ma in `dispositivi`, ed è la stessa
      // forma del Bluetooth — chi sceglie «Trasmetti a schermo» vede poi
      // l'elenco e sceglie. Metterli nel motivo passava la prova che dice
      // «una voce accesa non ha un perché», che è una regola giusta.
      'motivo': '',
      'dispositivi': [for (final s in trovati) s.toJson()],
    };
  }

  Future<Map<String, dynamic>> _bluetooth() async {
    const vuoto = <Map<String, dynamic>>[];

    if (!await Dbus.ceIlServizio('org.bluez')) {
      return {
        'id': 'bluetooth',
        'nome': 'Bluetooth',
        'icona': 'bluetooth',
        'disponibile': false,
        'motivo': 'Il Bluetooth non è attivo su questo computer.',
        'dispositivi': vuoto,
      };
    }

    final oggetti = await Dbus.oggetti('org.bluez', '/');
    if (oggetti == null) {
      return {
        'id': 'bluetooth',
        'nome': 'Bluetooth',
        'icona': 'bluetooth',
        'disponibile': false,
        'motivo': 'Il Bluetooth non risponde.',
        'dispositivi': vuoto,
      };
    }

    // L'adattatore spento e l'adattatore assente sono due cose diverse, e chi
    // guarda deve poterle distinguere: la prima si risolve con un interruttore.
    var acceso = false;
    var adattatore = false;
    for (final ifs in oggetti.values) {
      final a = ifs['org.bluez.Adapter1'];
      if (a != null) {
        adattatore = true;
        if (a['Powered'] == true) acceso = true;
      }
    }
    if (!adattatore) {
      return {
        'id': 'bluetooth',
        'nome': 'Bluetooth',
        'icona': 'bluetooth',
        'disponibile': false,
        'motivo': 'Questo computer non ha il Bluetooth.',
        'dispositivi': vuoto,
      };
    }
    if (!acceso) {
      return {
        'id': 'bluetooth',
        'nome': 'Bluetooth',
        'icona': 'bluetooth',
        'disponibile': false,
        'motivo': 'Il Bluetooth è spento. Accendilo dalla barra o dalle '
            'Impostazioni.',
        'dispositivi': vuoto,
      };
    }

    final dispositivi = <Map<String, dynamic>>[];
    for (final ifs in oggetti.values) {
      final d = ifs['org.bluez.Device1'];
      if (d == null || d['Paired'] != true) continue;
      final indirizzo = d['Address'];
      if (indirizzo is! String || indirizzo.isEmpty) continue;
      final nome = d['Alias'] is String && (d['Alias'] as String).isNotEmpty
          ? d['Alias'] as String
          : (d['Name'] is String ? d['Name'] as String : indirizzo);
      dispositivi.add({
        'indirizzo': indirizzo,
        'nome': nome,
        'connesso': d['Connected'] == true,
      });
    }
    // Prima i connessi: sono quelli a cui si sta davvero per mandare qualcosa.
    dispositivi.sort((a, b) {
      if (a['connesso'] != b['connesso']) return a['connesso'] == true ? -1 : 1;
      return (a['nome'] as String).toLowerCase().compareTo(
          (b['nome'] as String).toLowerCase());
    });

    if (dispositivi.isEmpty) {
      return {
        'id': 'bluetooth',
        'nome': 'Bluetooth',
        'icona': 'bluetooth',
        'disponibile': false,
        'motivo': 'Nessun dispositivo accoppiato. Accoppialo dalle '
            'Impostazioni, poi torna qui.',
        'dispositivi': vuoto,
      };
    }

    return {
      'id': 'bluetooth',
      'nome': 'Bluetooth',
      'icona': 'bluetooth',
      'disponibile': true,
      'motivo': '',
      'dispositivi': dispositivi,
    };
  }

  Future<Map<String, dynamic>> _posta() async {
    final desktop = await _mime.defaultFor('x-scheme-handler/mailto');
    final nudo = desktop.replaceAll('.desktop', '').toLowerCase();

    if (desktop.isEmpty) {
      return {
        'id': 'email',
        'nome': 'Email',
        'icona': 'mail',
        'disponibile': false,
        'motivo': 'Nessun programma di posta impostato su questo computer.',
        'programma': '',
      };
    }
    if (!_programmiDiPosta.contains(nudo)) {
      return {
        'id': 'email',
        'nome': 'Email',
        'icona': 'mail',
        'disponibile': false,
        'motivo': 'La posta è affidata a «$nudo», che apre il messaggio ma '
            'non sa allegare un file. Serve un programma di posta '
            'installato sul computer.',
        'programma': nudo,
      };
    }
    if (!await _ceIlComando('xdg-email')) {
      return {
        'id': 'email',
        'nome': 'Email',
        'icona': 'mail',
        'disponibile': false,
        'motivo': 'Manca «xdg-email», che è quello che passa l\'allegato al '
            'programma di posta.',
        'programma': nudo,
      };
    }
    return {
      'id': 'email',
      'nome': 'Email',
      'icona': 'mail',
      'disponibile': true,
      'motivo': '',
      'programma': nudo,
    };
  }

  static Future<bool> _ceIlComando(String nome) async {
    try {
      final r = await Process.run('sh', ['-c', 'command -v "\$1"', 'sh', nome])
          .timeout(const Duration(seconds: 2));
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Mandare ───────────────────────────────────────────────────────────────

  /// Manda dei file a una destinazione.
  ///
  /// `bersaglio` è l'indirizzo del dispositivo per il Bluetooth, e non serve
  /// per la posta.
  Future<Map<String, dynamic>> invia(
    String dove,
    List<String> file, {
    String bersaglio = '',
  }) async {
    if (file.isEmpty) {
      return {'ok': false, 'error': 'Non c\'è niente da mandare.'};
    }
    // Un file sparito fra il menu e il clic non è un caso di scuola: succede
    // ogni volta che si cestina qualcosa con il menu ancora aperto.
    for (final f in file) {
      if (!await File(f).exists() && !await Directory(f).exists()) {
        return {
          'ok': false,
          'error': 'Non trovo più «${f.split('/').last}».',
        };
      }
    }

    switch (dove) {
      case 'bluetooth':
        return _inviaBluetooth(bersaglio, file);
      case 'email':
        return _inviaEmail(file);
      case 'schermo':
        return _inviaSchermo(bersaglio, file);
      default:
        return {'ok': false, 'error': 'Non so mandare niente a «$dove».'};
    }
  }

  /// ── Il televisore ────────────────────────────────────────────────────────
  ///
  /// Passa dal servizio che già trasmette, non da una seconda strada: una
  /// trasmissione per volta è una garanzia di `TrasmettiService`, e due strade
  /// la romperebbero senza che nessuno se ne accorga.
  Future<Map<String, dynamic>> _inviaSchermo(
      String bersaglio, List<String> file) async {
    // ── Uno per volta, e detto invece che deciso in silenzio ────────────
    //
    // Un televisore mostra una cosa sola. Mandargli il primo di sei file
    // scelti e tacere è peggio che rifiutare: chi guarda crede che gli altri
    // cinque arrivino dopo.
    if (file.length > 1) {
      return {
        'ok': false,
        'error': 'Un televisore mostra una cosa per volta: scegline uno.',
      };
    }
    final trovati = await _schermi.cerca();
    SchermoEsterno? verso;
    for (final s in trovati) {
      if (s.id == bersaglio || s.nome == bersaglio) {
        verso = s;
        break;
      }
    }
    if (verso == null) {
      return {
        'ok': false,
        'error': trovati.isEmpty
            ? 'Nessun televisore in rete. Deve essere acceso e sulla stessa '
                'rete di questo computer.'
            : 'Non trovo più «$bersaglio» fra i televisori accesi.',
      };
    }
    // Il tipo lo trova il demone guardando dentro al file: un `.mp4`
    // annunciato come fotografia è uno schermo nero senza spiegazione.
    final tipo = await _mime.detect(file.first);
    final r = await _trasmetti.manda(
      file: File(file.first),
      verso: verso,
      tipo: tipo.isEmpty ? 'application/octet-stream' : tipo,
    );
    if (r['ok'] == true) {
      return {
        'ok': true,
        'messaggio': 'Sto mandando a ${verso.nome}.',
      };
    }
    return r;
  }

  /// ── Bluetooth ────────────────────────────────────────────────────────────
  ///
  /// ── Perché NON si passa da `Dbus.chiama`, e il difetto che l'ha insegnato
  ///
  /// La prima versione faceva la cosa che sembra ovvia leggendo la
  /// documentazione di BlueZ:
  ///
  ///   1. `org.bluez.obex.Client1.CreateSession(indirizzo, {Target: "opp"})`
  ///   2. `org.bluez.obex.ObjectPush1.SendFile(percorso)` sulla sessione
  ///
  /// **Non funziona, e non può funzionare.** `CreateSession` rispondeva un
  /// percorso valido (`/org/bluez/obex/client/session4`), e il `SendFile`
  /// subito dopo falliva con
  ///
  ///     Method "SendFile" ... on interface "org.bluez.obex.ObjectPush1"
  ///     doesn't exist
  ///
  /// perché **obexd distrugge la sessione quando il processo che l'ha creata
  /// si stacca dal bus.** `Dbus.chiama` lancia un `busctl` per ogni chiamata:
  /// il primo crea la sessione ed esce — e la sessione muore con lui — e il
  /// secondo la cerca dove non c'è più.
  ///
  /// Verificato il 19 agosto 2026: dopo `CreateSession`, la sessione non
  /// compare MAI in `GetManagedObjects`. Nasce e muore nello stesso istante.
  ///
  /// Quindi serve **un processo solo che resta vivo** per tutta la durata, ed
  /// è `obexctl` — che è di BlueZ, parla la stessa API, e la sessione la tiene
  /// aperta finché è aperto lui. È la stessa forma di
  /// `bluetooth_pairing_service.dart`, per la stessa ragione.
  ///
  /// ── Lo spazio nel nome del file ──────────────────────────────────────────
  ///
  /// `obexctl` divide i comandi sugli spazi: `send /una/cosa con spazi.txt`
  /// risponde «Too many arguments: 2 > 1» e non manda niente. Il percorso va
  /// fra virgolette. È lo stesso inciampo già catalogato in questo progetto
  /// per le schermate, in un posto nuovo.
  Future<Map<String, dynamic>> _inviaBluetooth(
      String indirizzo, List<String> file) async {
    if (indirizzo.isEmpty) {
      return {'ok': false, 'error': 'Non hai scelto a chi mandarlo.'};
    }

    // Le cartelle non si mandano: OBEX manda file, e un tentativo su una
    // cartella fallisce con un errore che non spiega niente.
    final cartelle = <String>[];
    for (final f in file) {
      if (await Directory(f).exists()) cartelle.add(f.split('/').last);
    }
    if (cartelle.isNotEmpty) {
      return {
        'ok': false,
        'error': cartelle.length == 1
            ? 'Il Bluetooth manda file, non cartelle: «${cartelle.first}» va '
                'prima compressa.'
            : 'Il Bluetooth manda file, non cartelle: comprimi prima '
                '${cartelle.length} cartelle.',
      };
    }

    // Un percorso con una virgoletta dentro romperebbe la citazione e
    // farebbe eseguire a `obexctl` un comando che non abbiamo scritto noi.
    // Un file si può chiamare così, quindi si controlla invece di sperare.
    for (final f in file) {
      if (f.contains('"')) {
        return {
          'ok': false,
          'error': 'Non riesco a mandare «${f.split('/').last}»: il nome '
              'contiene una virgoletta.',
        };
      }
    }

    Process sessione;
    try {
      sessione = await Process.start(
        'obexctl',
        const [],
        environment: const {'LC_ALL': 'C'},
      );
    } catch (_) {
      return {
        'ok': false,
        'error': 'Non trovo «obexctl», che è quello che manda i file via '
            'Bluetooth.',
      };
    }

    final raccolto = StringBuffer();
    final ascolto = sessione.stdout
        .transform(utf8.decoder)
        .listen(raccolto.write, onError: (_) {}, cancelOnError: false);
    final ascoltoErr = sessione.stderr
        .transform(utf8.decoder)
        .listen(raccolto.write, onError: (_) {}, cancelOnError: false);

    // In fila, ognuna dopo il `flush` della precedente (30 settembre 2026):
    // un `write` mentre il `flush` di prima è in volo solleva «StreamSink is
    // bound to a stream», e il `catch` lo inghiottiva. È il difetto che
    // faceva perdere il `connect` all'accoppiamento Bluetooth; qui oggi le
    // scritture sono distanziate da attese, ma basta toglierne una.
    var fila = Future<void>.value();
    void scrivi(String c) {
      fila = fila.then((_) async {
        try {
          sessione.stdin.write('$c\n');
          await sessione.stdin.flush();
        } catch (_) {}
      });
    }

    try {
      // `obexctl` espone il suo Client solo dopo essersi agganciato a obexd:
      // un `connect` mandato subito risponde «Client proxy not available» e
      // non prova nemmeno a connettersi. Verificato.
      await Future<void>.delayed(const Duration(seconds: 3));
      scrivi('connect $indirizzo');

      // La connessione aspetta il telefono, che può essere in tasca con lo
      // schermo spento: si guarda l'uscita invece di indovinare un'attesa.
      final connesso = await _aspetta(
        raccolto,
        riuscito: (t) => t.contains('Connection successful'),
        fallito: (t) =>
            t.contains('Failed to connect') || t.contains('not available'),
        entro: const Duration(seconds: 30),
      );
      if (!connesso) {
        return {
          'ok': false,
          'error': 'Il dispositivo non ha risposto. Controlla che sia acceso, '
              'vicino, e che accetti i file dal Bluetooth.',
        };
      }

      final falliti = <String>[];
      var mandati = 0;
      for (final f in file) {
        final primaDiQuesto = raccolto.length;
        scrivi('send "$f"');
        final andata = await _aspetta(
          raccolto,
          da: primaDiQuesto,
          riuscito: (t) => t.contains('Status: complete'),
          fallito: (t) =>
              t.contains('Status: error') ||
              t.contains('Failed to send') ||
              t.contains('Too many arguments'),
          // Un file grosso via Bluetooth è lento: 3 Mbit/s nei casi buoni.
          entro: const Duration(minutes: 5),
        );
        if (andata) {
          mandati++;
        } else {
          falliti.add(f.split('/').last);
        }
      }

      if (falliti.isEmpty) {
        return {
          'ok': true,
          'mandati': mandati,
          'messaggio': mandati == 1
              ? 'Mandato.'
              : 'Mandati $mandati file.',
        };
      }
      return {
        'ok': false,
        'mandati': mandati,
        'error': falliti.length == 1
            ? 'Non sono riuscito a mandare «${falliti.first}».'
            : 'Non sono riuscito a mandare ${falliti.length} file.',
      };
    } finally {
      scrivi('quit');
      await ascolto.cancel();
      await ascoltoErr.cancel();
      // Se «quit» non basta si insiste: `obexctl` vivo tiene aperta la
      // sessione, e il prossimo invio troverebbe il posto occupato.
      Future<void>.delayed(const Duration(seconds: 2), () => sessione.kill());
    }
  }

  /// Aspetta che dentro quello che ha detto `obexctl` compaia un segno di
  /// riuscita o di fallimento. Vero se è riuscito.
  ///
  /// Si guarda solo la parte arrivata DOPO `da`: mandando tre file, il
  /// «Status: complete» del primo farebbe risultare riuscito anche il
  /// secondo prima ancora che parta.
  static Future<bool> _aspetta(
    StringBuffer raccolto, {
    required bool Function(String) riuscito,
    required bool Function(String) fallito,
    required Duration entro,
    int da = 0,
  }) async {
    final scade = DateTime.now().add(entro);
    while (DateTime.now().isBefore(scade)) {
      final tutto = raccolto.toString();
      final testo = tutto.length > da ? tutto.substring(da) : '';
      if (riuscito(testo)) return true;
      if (fallito(testo)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  /// ── Posta ────────────────────────────────────────────────────────────────
  ///
  /// `xdg-email --attach` è la via standard, e passa il file al programma di
  /// posta predefinito. Non si compone niente a mano: il testo lo scrive chi
  /// manda, noi mettiamo solo l'allegato.
  Future<Map<String, dynamic>> _inviaEmail(List<String> file) async {
    final cartelle = <String>[];
    for (final f in file) {
      if (await Directory(f).exists()) cartelle.add(f.split('/').last);
    }
    if (cartelle.isNotEmpty) {
      return {
        'ok': false,
        'error': cartelle.length == 1
            ? 'Una cartella non si allega a un messaggio: «${cartelle.first}» '
                'va prima compressa.'
            : 'Una cartella non si allega a un messaggio: comprimi prima '
                '${cartelle.length} cartelle.',
      };
    }

    final argomenti = <String>[];
    for (final f in file) {
      argomenti.addAll(['--attach', f]);
    }
    try {
      // Staccato: `xdg-email` resta vivo quanto il programma di posta, e
      // aspettarlo vorrebbe dire tenere occupato il demone finché non si
      // chiude la finestra del messaggio.
      await Process.start('xdg-email', argomenti,
          mode: ProcessStartMode.detached);
      return {
        'ok': true,
        'mandati': file.length,
        'messaggio': file.length == 1
            ? 'Messaggio aperto con il file allegato.'
            : 'Messaggio aperto con ${file.length} file allegati.',
      };
    } catch (e) {
      return {'ok': false, 'error': 'Non sono riuscito ad aprire la posta.'};
    }
  }
}

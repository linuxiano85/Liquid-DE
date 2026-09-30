import 'dart:convert';
import 'dart:io';
import 'dart:async';
import '../core/event_bus.dart';
import '../core/state_manager.dart';
import '../core/ricorda_un_po.dart';
import '../services/manutenzione/inventario.dart';
import '../services/manutenzione/pulitore.dart';
import '../services/manutenzione/quaderno.dart';
import '../services/manutenzione/escluse.dart';
import '../services/manutenzione/setaccio.dart';
import '../core/settings_api.dart';
import '../providers/compositor_provider.dart';
import '../services/app_scanner.dart';
import '../services/vetro.dart';
import '../services/process_service.dart';
import '../services/icon_resolver.dart';
import '../services/icon_names.dart';
import '../services/schemi.dart';
import '../services/app_usage_tracker.dart';
import '../services/keybind_service.dart';
import '../services/file_service.dart';
import '../services/system_state_service.dart';
import '../services/mime_service.dart';
import '../services/finestre_service.dart';
import '../services/greetd_service.dart';
import '../services/accesso_service.dart';
import '../services/gestori_accesso_service.dart';
import '../services/radice_service.dart';
import '../services/schermi_esterni.dart';
import '../services/trasmetti_service.dart';
import '../services/account_service.dart';
import '../services/custodia_service.dart';
import '../services/archive_service.dart';
import '../services/autostart_service.dart';
import '../services/data_ora_service.dart';
import '../services/lingua_service.dart';
import '../services/meteo_service.dart';
import '../services/ricerca_service.dart';
import '../services/audio_service.dart';
import '../services/system_audio_service.dart';
import '../services/condivisione_service.dart';
import '../services/bluetooth_pairing_service.dart';
import '../services/tema_icone_service.dart';
import '../services/foto_service.dart';
import 'canale_segreto.dart';
import '../core/ambiente.dart';
import '../core/minerva_paths.dart';

/// Server IPC basato su WebSocket (ws://127.0.0.1:11432).
/// Consente la comunicazione bidirezionale tra la shell QML, i plugin e il core.
///
/// ── Perché un socket Unix e non più una porta ──────────────────────────────
///
/// Fino al 27 agosto 2026 il demone ascoltava su `127.0.0.1:11432`, e da lì
/// venivano due guai distinti.
///
/// **Il primo era di sicurezza.** Una porta di `localhost` risponde a
/// *chiunque* giri sulla macchina: un servizio di sistema, un account di
/// servizio, un programma dentro un contenitore. Nella schermata di accesso
/// dava molto di più che il comando della scrivania — l'attacco per esteso sta
/// in `canale_segreto.dart`. Ci si era messa una parola d'ordine, che chiudeva
/// il buco ma lasciava la porta: un estraneo poteva ancora collegarsi e
/// provare. Adesso non può nemmeno bussare: `$XDG_RUNTIME_DIR` è 0700 e il
/// socket è 0600.
///
/// **Il secondo era la caccia al numero.** Ce n'è più di un demone: la
/// schermata di accesso è Minerva intera — un demone e una shell — che gira
/// come utente `greeter` MENTRE la sessione di chi lavora è aperta. Con una
/// porta sola succedeva questo, ed è successo davvero:
///
///   1. il demone del greeter trovava la porta occupata da quello della
///      sessione, e rinunciava in silenzio;
///   2. la schermata si connetteva a 11432 e trovava **il demone dell'altro
///      utente**;
///   3. quel demone non è dentro un greeter, quindi rispondeva `greetd: false`;
///   4. la schermata si metteva in anteprima e la password non entrava.
///
/// La cura era una porta diversa per il greeter e una caccia alla prima libera
/// per le sessioni — con la 11433 da saltare e, su questa macchina, la 11434 di
/// Ollama in cui inciampare. **Un socket per sessione fa sparire il problema
/// invece di gestirlo:** il percorso contiene il nome della sessione, quindi
/// due demoni non si incontrano mai e non c'è niente da cercare.
/// Le due chiavi della zona che accompagna una richiesta mentre viene servita.
///
/// `_chiaveCliente` c'è per una ragione che si vede solo pensandoci: mentre
/// serviamo la richiesta di UNA finestra possiamo spedire qualcosa anche alle
/// altre. Senza il controllo su chi è il destinatario, quelle spedizioni si
/// porterebbero dietro l'identificativo di una domanda che non hanno fatto.
const Object _chiaveId = #minervaIdRichiesta;
const Object _chiaveCliente = #minervaClienteRichiesta;

class WebSocketServer {
  /// Dove si ascolta: `MINERVA_IPC_SOCKET` se qualcuno l'ha detto, altrimenti
  /// `$XDG_RUNTIME_DIR/liquid-de/canale-<sessione>.sock`.
  ///
  /// Il nome della sessione è lo stesso che sceglie il file del canale, e non
  /// è un caso: le due cose devono finire nella stessa cartella, o la
  /// schermata di accesso scriverebbe l'indirizzo in un posto e il socket in
  /// un altro. Vedi `CanaleSegreto.sessione()` e `scripts/minerva-posti.sh`.
  static String get socketConfigurato =>
      socketDa(Platform.environment['MINERVA_IPC_SOCKET']);

  /// La regola, separata da dove arriva il valore: l'ambiente di un processo
  /// Dart è di sola lettura, quindi una prova non può fingere una variabile.
  ///
  /// Un valore illeggibile NON è un motivo per non partire: si torna al
  /// predefinito e lo si dice. Una schermata di accesso che non parte perché
  /// qualcuno ha scritto male un percorso è un computer che non si apre.
  static String socketDa(String? detto) {
    final v = detto?.trim() ?? '';
    if (v.isEmpty) return socketPredefinito();
    if (!v.startsWith('/')) {
      print('[MINERVA][IPC][WARN] MINERVA_IPC_SOCKET="$detto" non è un '
          'percorso completo: uso ${socketPredefinito()}');
      return socketPredefinito();
    }
    // ── Il limite che non si vede finché non si supera ──────────────────
    //
    // `sockaddr_un.sun_path` sono 108 byte in tutto, terminatore compreso, ed
    // è un limite del kernel, non di Dart. Un percorso più lungo non dà un
    // errore chiaro: dà un `bind` fallito con un messaggio che parla d'altro.
    if (v.length > 100) {
      print('[MINERVA][IPC][WARN] MINERVA_IPC_SOCKET è troppo lungo '
          '(${v.length} caratteri, il massimo è 100): uso '
          '${socketPredefinito()}');
      return socketPredefinito();
    }
    return v;
  }

  /// `$XDG_RUNTIME_DIR/liquid-de/canale-<sessione>.sock`, con ripiego su `/tmp`
  /// per l'utente `greeter`, che può avere `XDG_RUNTIME_DIR` impostato su una
  /// cartella che non esiste e che non ha il diritto di creare — è successo il
  /// 10 agosto 2026, e allora il demone del greeter morì lasciando a schermo
  /// una schermata di accesso intera e con l'elenco utenti vuoto.
  static String socketPredefinito() {
    return '${MinervaPaths.runtime()}/canale-${CanaleSegreto.sessione()}.sock';
  }

  final EventBus _eventBus;
  final StateManager _stateManager;
  final SettingsApi _settingsApi;
  final CompositorProvider _compositorProvider;
  final AppScanner _appScanner;
  final IconResolver _iconResolver;
  final AppUsageTracker _appUsageTracker;
  final KeybindService _keybindService;
  final FileService _fileService;
  final SystemStateService _systemState;
  final FinestreService _finestre;
  final RicercaService _ricerca = RicercaService();

  /// I preferiti che puntano a programmi che non esistono più, già segnalati.
  ///
  /// Detto una volta sola per nome: il menù delle applicazioni si riapre
  /// decine di volte al giorno, e una riga per apertura riempirebbe il
  /// registro di una notizia sola ripetuta — che è il modo in cui un registro
  /// smette di servire. Vedi lo stesso schema in `core/Compositore.qml`.
  final Set<String> _preferitiSpariti = {};

  /// La galleria. Non tiene stato fra una richiesta e l'altra tranne il
  /// catalogo, che è esattamente il punto: caricarlo una volta e riusarlo.
  final FotoService _foto = FotoService();

  /// Lo sfondo già sfocato, per il vetro dietro la barra e la dock. Calcolato
  /// una volta per sfondo e tenuto in cache: costo a fotogramma zero.
  final Vetro _vetro = Vetro();
  final ProcessService _processi;

  /// Chi ha aperto il monitor. Serve per disiscrivere anche chi se ne va senza
  /// dire niente — una finestra chiusa con la X non manda `unsubscribe`, e il
  /// servizio resterebbe a leggere `/proc` per sempre.
  final Set<WebSocketClientConnection> _iscrittiProcessi = {};

  /// Chi guarda i tre numeri della macchina senza l'elenco dei processi: i
  /// widget della scrivania. Contati a parte perché costano un ventesimo, e
  /// perché restano accesi per tutto il giorno mentre il Monitor si apre e si
  /// chiude.
  final Set<WebSocketClientConnection> _iscrittiMacchina = {};
  /// Il socket su cui si ascolta davvero. Non c'è più niente da cercare: il
  /// percorso contiene il nome della sessione, quindi due demoni non si
  /// incontrano. Vedi `_ascolta`.
  final String _percorsoSocket;

  /// Chi apre che cosa. Si costruisce qui e non nel nucleo perché ha bisogno
  /// solo dell'elenco delle applicazioni, che è già a portata di mano: un
  /// parametro in più nel costruttore di tutti gli oggetti attraversati non
  /// aggiungerebbe niente.
  late final MimeService _mime = MimeService(_appScanner);

  /// Mandare un file fuori di qui: Bluetooth, posta. Ha bisogno di `_mime`
  /// per sapere chi gestisce `mailto:`, e quindi si costruisce dopo di lui.
  late final CondivisioneService _condivisione = CondivisioneService(_mime, _trasmetti);

  /// Accoppiare un dispositivo che vuole confrontare un codice — un telefono.
  /// Tiene una sessione di `bluetoothctl` aperta per volta, quindi è uno solo
  /// per tutto il demone e non uno per cliente.
  /// Installare un set di icone preso da fuori. Non tiene stato: legge e
  /// scrive quando glielo si chiede.
  final TemaIconeService _temiIcone = const TemaIconeService();

  final BluetoothPairingService _accoppiamento = BluetoothPairingService();
  StreamSubscription<Map<String, dynamic>>? _accoppiamentoSub;

  /// Comprimere ed estrarre. Non tiene stato: è un guscio attorno a `bsdtar`.
  final ArchiveService _archivi = const ArchiveService();

  /// L'onda, il cartellino e il taglio di un file audio, per Minerva Suono.
  /// Come `_archivi`: non tiene stato, è un guscio attorno a ffmpeg.
  final AudioService _audio = AudioService();
  final SystemAudioService _systemAudio = SystemAudioService();
  StreamSubscription<Map<String, dynamic>>? _systemAudioSub;

  /// I programmi che partono con la sessione. Legge le due cartelle a ogni
  /// richiesta: sono una manciata di file e cambiano da fuori (un pacchetto
  /// appena installato ne aggiunge una), quindi una copia in memoria sarebbe
  /// sbagliata più spesso di quanto sarebbe veloce.
  final AutostartService _avvio = AutostartService();

  /// Chi può entrare e in cosa. Non costa niente tenerlo sempre: legge solo
  /// quando glielo si chiede.
  final AccessoService _accesso = const AccessoService();
  final GestoriAccessoService _gestori = const GestoriAccessoService();
  final RadiceService _radice = const RadiceService();

  /// Chi manda un file a un televisore. Il permesso del firewall glielo passa
  /// come funzione e non come servizio: così le prove possono farlo girare
  /// senza far comparire una finestra della password.
  /// Da quello che ha detto il client al televisore vero, o `null` dopo aver
  /// già mandato l'errore.
  ///
  /// Il televisore si nomina per **ID stabile** e non per indirizzo: un IP
  /// cambia a ogni riaccensione del router, e «manda a 192.168.1.7» un giorno
  /// manderebbe a un altro apparecchio. Vedi `id` in `schermi_esterni.dart`.
  Future<SchermoEsterno?> _televisoreDetto(Object? id, dynamic client) async {
    final trovati = await _trasmetti.cerca();
    for (final s in trovati) {
      if (s.id == id || s.nome == id) return s;
    }
    client.send({
      'event': 'trasmetti_esito',
      'payload': {
        'ok': false,
        'error': trovati.isEmpty
            ? 'Nessun televisore in rete. Deve essere acceso e sulla stessa '
                'rete di questo computer.'
            : 'Non trovo «$id» fra i televisori accesi.',
      },
    });
    return null;
  }

  late final TrasmettiService _trasmetti =
      TrasmettiService(permesso: _radice.chiedi);

  /// La Custodia: la storia e la sicurezza delle cartelle di chi usa Minerva.
  /// Vive qui e non nella shell perché tutto quello che può perdere lavoro sta
  /// nel demone, dove ci sono le prove — come per `FileService` e
  /// `RadiceService`. Vedi `services/custodia_service.dart`.
  final CustodiaService _custodia = CustodiaService();

  /// L'inventario di quello che si può togliere da questo computer. Guarda e
  /// basta: cancellare è un mestiere diverso e sta in `scripts/minerva-radice`.
  ///
  /// Non è un campo ma una fabbrica, e la ragione è il **racconto**: chi
  /// chiede l'inventario riceve le tappe man mano (`manutenzione_passo`), e
  /// quelle tappe vanno a lui e non a chiunque sia collegato. Un oggetto solo
  /// e condiviso avrebbe un solo destinatario — il primo che l'ha chiesto — e
  /// con due finestre aperte la seconda vedrebbe la barra dell'altra.
  /// Quanto spazio Manutenzione ha recuperato da sempre. È l'unica cosa che
  /// quel programma si ricorda: tutto il resto lo rimisura ogni volta.
  final Quaderno _quaderno = Quaderno();

  /// Le cartelle che la Manutenzione non guarda, scelte da chi usa il
  /// computer. Vedi `manutenzione/escluse.dart`.
  final Escluse _escluse = Escluse();

  Inventario _perChiGuarda(WebSocketClientConnection client) => Inventario(
        racconta: (fase, testo, fatte, quante) => client.send({
          'event': 'manutenzione_passo',
          'payload': {
            'fase': fase,
            'testo': testo,
            'fatte': fatte,
            'quante': quante,
          },
        }),
      );

  /// Gli account online. Lo stesso registro che la Custodia userà
  /// come destinazioni: uno solo, o si finisce a collegare kDrive due
  /// volte. Vedi `services/account_service.dart`.
  final AccountService _account = AccountService();

  /// Data, ora e fuso orario. Tiene in memoria solo l'elenco dei fusi, che
  /// non cambia mai: tutto il resto lo rilegge da `timedatectl` ogni volta.
  final DataOraService _dataOra = DataOraService();

  /// La lingua del sistema. Senza stato: legge `/etc/locale.conf` ogni volta,
  /// che è un file di dieci righe e può cambiare da fuori.
  final LinguaService _lingua = const LinguaService();

  /// Il tempo che fa. Non parte niente finché non c'è una località scelta:
  /// vedi la testa di `meteo_service.dart` per che cosa esce da qui.
  final MeteoService _meteo = MeteoService();

  /// Il dialogo con greetd. Nasce alla PRIMA richiesta del greeter e non
  /// prima: in una sessione normale `GREETD_SOCK` non esiste, e un servizio
  /// che prova a connettersi a ogni avvio scriverebbe un avviso nel registro
  /// di ogni demone che gira sul computer.
  GreetdService? _greetd;
  StreamSubscription? _greetdSub;

  // ── Tre risposte che si ricalcolavano da capo ogni volta ────────────────
  //
  // Misurate sul demone vivo il 7 settembre 2026: `font_list` 28,8 ms,
  // `mime_categories` 29,4 ms, `fs_formats` 23,0 ms — contro gli 0,3 ms di
  // `get_state`. Nessuna delle tre cambia mentre la sessione gira, e il demone
  // ha un filo solo: quei millisecondi sono fermi per TUTTE le finestre, non
  // solo per chi ha chiesto. Vedi `core/ricorda_un_po.dart`.
  final _fontRicordati = RicordaUnPo<List<String>>(const Duration(seconds: 30));
  final _formatiRicordati =
      RicordaUnPo<Map<String, dynamic>>(const Duration(seconds: 30));
  // Questo si dimentica a mano: cambiare il programma predefinito di un tipo
  // di file CAMBIA la risposta, e mezzo minuto di attesa per vedere la propria
  // scelta sarebbe un difetto peggiore del costo che toglie.
  final _categorieRicordate =
      RicordaUnPo<List<dynamic>>(const Duration(seconds: 30));

  /// Chi ha chiesto di parlare con greetd. Le risposte vanno lì e basta: sono
  /// una conversazione, non uno stato del sistema, e mandarle a tutti
  /// significherebbe mandare i messaggi di PAM anche a chi non li ha chiesti.
  WebSocketClientConnection? _ilGreeter;

  /// Passa una richiesta a greetd e fa in modo che le sue risposte tornino a
  /// chi l'ha fatta.
  ///
  /// Le risposte NON si aspettano qui dentro: il protocollo non è a domanda e
  /// risposta. A una `create_session` greetd può rispondere con una domanda,
  /// poi con un'altra, poi con un esito — «there are no limits on the number
  /// and type of messages», dice la pagina di manuale. Chi aspettasse UNA
  /// risposta per ogni richiesta si bloccherebbe al secondo giro. Quindi si
  /// manda e basta, e tutto ciò che arriva viene inoltrato.
  Future<void> _greetdRichiesta(
      WebSocketClientConnection client, String azione, Map msg) async {
    _ilGreeter = client;

    final g = _greetd ??= GreetdService();
    _greetdSub ??= g.risposte.listen((r) {
      // Gli errori si SCRIVONO, oltre a spedirli. Il 10 agosto 2026 la
      // schermata è finita a ritentare in tondo e il registro non diceva
      // perché: si vedeva solo l'effetto, un tremito che non finiva. Il tipo
      // e la descrizione bastano a distinguere «password sbagliata» da
      // «greetd non parla più», e non contengono niente di segreto — la
      // risposta dell'utente non passa mai di qui.
      if (r['type'] == 'error') {
        // ── Tranne quella che non è greetd a dire ────────────────────
        //
        // «Nessuna connessione a greetd» non arriva da greetd: la fabbrica
        // `GreetdService` quando questo processo non è un greeter, cioè
        // sempre, in ogni sessione normale. Scriverla qui vuol dire una terza
        // riga identica alle altre due, e in una sessione vera del 1º
        // settembre 2026 se ne contavano settantacinque copie.
        //
        // Il client la riceve lo stesso — è lui che deve saperlo. Quello che
        // non serve a nessuno è ripeterla sul registro: un registro fatto di
        // rumore non lo legge più nessuno, e gli errori veri ci affogano.
        final soloRumore = r['description'] == 'Nessuna connessione a greetd';
        if (!soloRumore) {
          print('[MINERVA][GREETD][WARN] greetd risponde errore '
              '(${r['error_type']}): ${r['description']}');
        }
        // ── Un errore che NON è un guasto ─────────────────────────────
        //
        // greetd fa la conversazione con PAM dentro un processo figlio, e
        // quando `pam_authenticate` fallisce quel figlio esce. Il
        // `cancel_session` che la schermata manda subito dopo arriva quindi a
        // un morto, e greetd risponde «unable to send message: Connection
        // refused» invece di «sì».
        //
        // È la risposta NORMALE a una password sbagliata, e la schermata la
        // gestisce (vedi `annullando` in `greeter/Greeter.qml`). Ma nel
        // registro sta accanto a un errore vero e si legge come un secondo
        // guasto: il 16 agosto 2026 ci ho perso mezz'ora a chiedermi cosa
        // fosse. Un registro che spaventa per una cosa normale è un registro
        // che si smette di leggere.
        if ('${r['description']}'.contains('unable to send message')) {
          print('[MINERVA][GREETD][INFO] …ed è normale: è la risposta '
              "all'annullamento di una sessione il cui aiutante di PAM era "
              'già uscito. La schermata sa gestirla e riparte da capo.');
        }
      }
      _ilGreeter?.send({'event': 'greeter_message', 'payload': r});
    });

    switch (azione) {
      // ── L'annullamento NON si nasconde qui dentro ────────────────────
      //
      // Per un giro, questa riga mandava un `cancel_session` muto prima di
      // ogni `create_session`: greetd non chiude la sessione quando la
      // password è sbagliata, e senza annullarla il tentativo successivo
      // riceve «a session is already being configured».
      //
      // Era la cosa giusta fatta nel posto sbagliato. Per nascondere la
      // risposta dell'annullamento bisognava CONTARE le risposte in arrivo, e
      // il conto si sfasa al primo imprevisto: il 10 agosto 2026 la risposta
      // ingoiata è stata quella sbagliata, la schermata ha letto il `success`
      // dell'annullamento come «password accettata», ha chiesto di aprire la
      // sessione — «session is not ready» — ed è uscita, portandosi dietro il
      // compositore. Giacomo si è ritrovato su un terminale nero.
      //
      // L'annullamento adesso lo chiede la schermata, che è l'unica a sapere
      // in che punto della conversazione si trova, e la risposta le arriva
      // normalmente. Vedi `annullando` in `greeter/Greeter.qml`.
      case 'greeter_create_session':
        final u = msg['username'];
        if (u is String && u.isNotEmpty) await g.creaSessione(u);
        break;

      case 'greeter_respond':
        // `null` e stringa vuota sono due cose diverse: la prima è «questo
        // messaggio non chiedeva niente», la seconda è una risposta vuota.
        // Vedi `GreetdService.rispondi`.
        final r = msg['response'];
        await g.rispondi(r is String ? r : null);
        break;

      case 'greeter_start':
        final cmd = (msg['cmd'] as List?)?.cast<String>() ?? const [];
        final env = (msg['env'] as List?)?.cast<String>() ?? const [];
        if (cmd.isEmpty) {
          client.send({
            'event': 'greeter_message',
            'payload': {
              'type': 'error',
              'error_type': 'error',
              'description': 'Nessun comando di sessione',
            },
          });
          return;
        }
        // ── La riga che dice cosa si sta avviando ───────────────────────
        //
        // Se una sessione non parte, oggi non resta NIENTE: si torna alla
        // schermata di accesso senza un messaggio, e da fuori sembra che la
        // password fosse sbagliata. È lo stesso modo di rompersi che
        // `/usr/local/bin/minerva-session` racconta nei propri commenti.
        //
        // Questa riga finisce nel registro del greeter (/var/log/minerva-greeter),
        // e vale la pena tenerla anche quando tutto funziona: è la differenza
        // fra un difetto che si vede e uno che si indovina. Il 17 agosto 2026
        // per capire perché Hyprland e KDE non partivano non c'era una sola
        // riga da leggere.
        //
        // Il comando e l'ambiente NON contengono segreti: sono la riga `Exec=`
        // di un file leggibile da tutti e quattro variabili `XDG_*`. La
        // password non passa mai di qui — la manda `greeter_auth`, e non si
        // registra.
        print('[MINERVA][GREETD][SESSIONE] avvio: ${cmd.join(' ')}');
        print('[MINERVA][GREETD][SESSIONE] ambiente: ${env.join(' ')}');
        await g.avviaSessione(cmd, env);
        break;

      case 'greeter_cancel':
        await g.annulla();
        break;
    }
  }

  /// I candidati arrivano dal servizio con il NOME dell'icona (`gwenview`);
  /// per disegnarla serve il file su disco, e chi sa trovarlo è il risolutore
  /// di icone, che vive qui. Senza questo passaggio la finestra «Apri con»
  /// mostra tre nomi allineati come se avessero un'icona, e uno spazio vuoto
  /// al posto suo.
  /// Dà a ogni `.desktop` dell'elenco il NOME e l'ICONA del programma che
  /// rappresenta.
  ///
  /// ── Perché serve, e perché non lo può fare la shell ────────────────────
  ///
  /// Sulla scrivania di Giacomo c'erano cinque quadrati azzurri identici
  /// chiamati `steam.desktop`, `Tomba! Special Edition.desktop`, `Tomb Raider
  /// I-III Remastered Starring Lara Croft.desktop`. Un file `.desktop` non È
  /// un file: è il biglietto da visita di un programma, e mostrarne il nome
  /// del file con l'icona del «documento sconosciuto» è come stampare il
  /// codice a barre invece della copertina.
  ///
  /// La shell non può farlo da sé per due ragioni: leggere il file glielo
  /// impedisce il confine (è il demone che tocca il disco), e risolvere
  /// `Icon=steam` in un percorso vuol dire conoscere i temi di icone, che è
  /// esattamente il mestiere di `IconResolver`.
  ///
  /// ── Il costo ───────────────────────────────────────────────────────────
  ///
  /// Una lettura di file per ogni `.desktop`, e solo per quelli. Su una
  /// scrivania sono cinque; il tetto serve per la cartella patologica —
  /// `/usr/share/applications` ne ha quattrocento, e chi ci entra col gestore
  /// file non sta aspettando quattrocento letture per vedere l'elenco. Oltre
  /// il tetto restano file normali col loro nome, che è la verità: sono
  /// file.
  Future<void> _vestiILauncher(dynamic entries) async {
    if (entries is! List) return;
    var fatti = 0;
    for (final e in entries) {
      if (e is! Map) continue;
      final nome = '${e['name'] ?? ''}';
      if (!nome.endsWith('.desktop')) continue;
      if (++fatti > 60) return;
      try {
        final app = await _appScanner.parseFromPath('${e['path']}');
        if (app == null) continue;
        e['appName'] = app.name;
        // 48 e non la misura piccola: sulla scrivania le icone si guardano,
        // non si scorrono in una barra.
        e['appIcon'] = _iconResolver.resolve(app.icon, size: 48);
      } catch (_) {
        // Un `.desktop` illeggibile resta un file come gli altri: mostrarlo
        // col suo nome è meglio che non mostrarlo.
      }
    }
  }

  List<dynamic> _withIcons(List<dynamic> candidates) {
    for (final c in candidates) {
      if (c is Map<String, dynamic>) {
        c['iconPath'] = _iconResolver.resolve('${c['icon'] ?? ''}');
      }
    }
    return candidates;
  }

  /// Lo stato dei gruppi, con le icone già risolte in percorsi su disco.
  /// Le categorie ricalcolate da zero, e il ricordo rimesso a nuovo con loro.
  ///
  /// Le usano i tre verbi che CAMBIANO i predefiniti: senza il `dimentica`, la
  /// pagina che si riapre entro mezzo minuto mostrerebbe la scelta di prima, ed
  /// è il difetto che i commenti qui sotto raccontano di aver già chiuso una
  /// volta — chi guarda conclude che non sia successo niente.
  Future<List<dynamic>> _categorieFresche() {
    _categorieRicordate.dimentica();
    return _categorieRicordate.chiedi(_mimeCategories);
  }

  Future<List<dynamic>> _mimeCategories() async {
    final cats = await _mime.categoryState();
    for (final c in cats) {
      c['candidates'] = _withIcons(c['candidates'] as List);
      final id = c['defaultApp'];
      // Il programma in carica va mostrato con nome e icona, non con
      // `org.kde.gwenview.desktop`. È l'unico dato che il pannello non può
      // ricavarsi da solo se il programma non è fra i candidati — e capita,
      // perché una scelta vecchia può puntare a qualcosa che non dichiara
      // più quel tipo.
      if (id is String && id.isNotEmpty) {
        final app = _appScanner.getAppById(id);
        c['defaultName'] = app?.name ?? id;
        c['defaultIcon'] = _iconResolver.resolve(app?.icon ?? '');
      } else {
        c['defaultName'] = '';
        c['defaultIcon'] = '';
      }
    }
    return cats;
  }

  ServerSocket? _server;

  /// La parola d'ordine del canale, nuova a ogni avvio. Vedi
  /// `canale_segreto.dart` per che cosa garantisce e che cosa no.
  String _segreto = '';

  final List<WebSocketClientConnection> _clients = [];
  StreamSubscription? _eventBusSubscription;
  StreamSubscription? _transferSubscription;
  StreamSubscription? _statoFinestreSub;
  StreamSubscription? _statoMonitorSub;

  /// Le icone di Minerva tradotte nel tema di icone in uso.
  ///
  /// Si tiene qui già risolta invece di risolverla a ogni richiesta: sono un
  /// centinaio di ricerche su disco, e i processi di Minerva sono tre — la
  /// barra, il gestore file, le Impostazioni — che si collegano e si
  /// ricollegano molte volte in una sessione.
  Map<String, dynamic> _iconMap = const {};

  /// Rilegge le icone dal tema attivo. Va chiamata ogni volta che il tema
  /// cambia, altrimenti si continuano a mandare i percorsi di quello prima.
  void _rebuildIconMap() {
    // ── Non nella schermata di accesso ──────────────────────────────────
    //
    // Lì il conto era «Icone classiche pronte: 0/76 da hicolor»: settantasei
    // ricerche su disco per **zero** icone trovate, e comunque nessuno le
    // avrebbe guardate — `greeter.qml` non disegna una sola icona, chiede solo
    // chi può entrare e in cosa. Lavoro buttato, e buttato nei secondi
    // peggiori: quelli in cui si fissa lo schermo aspettando la casella della
    // password.
    //
    // Il cancello sta QUI dentro e non ai due punti che chiamano questa
    // funzione, per la stessa ragione per cui il controllo della parola
    // d'ordine sta prima dello switch: un elenco di posti da proteggere ne
    // dimentica sempre uno, e la dimenticanza non si vede — continua a
    // funzionare, solo per chi non doveva.
    if (Ambiente.eGreeter) return;

    _iconMap = resolveMinervaIcons(_iconResolver);
    print('[MINERVA][MATRIX][INFO] Icone classiche pronte: '
        '${_iconMap.length}/${minervaIconNames.length} da "${_iconResolver.activeTheme}"');
  }

  /// L'elenco dei programmi come lo vede la shell, con le icone GIÀ risolte
  /// nel tema attivo.
  ///
  /// Sta qui in una funzione sola e non dentro il `case 'get_all_apps'` perché
  /// serve in due momenti diversi: quando qualcuno chiede l'elenco, e quando
  /// cambia il tema delle icone. Era scritto solo nel primo, ed è questo che
  /// faceva restare la dock con le icone di prima — vedi
  /// `_applyIconThemeFromSettings()`.
  List<Map<String, dynamic>> get _allAppsPayload => [
        for (final app in _appScanner.apps)
          {
            'appId': app.id,
            'name': app.name,
            'exec': app.exec,
            // «Apri una nuova finestra» della dock (azione `new-window`).
            'nuovaFinestra': app.nuovaFinestra,
            'icon': _iconResolver.resolve(app.icon),
            'categories': app.categories,
            'isNew': _appScanner.novita.nuove.contains(app.id),
            // La classe che la finestra dichiarerà al compositore: è ciò che
            // permette alla dock di legare una finestra aperta alla sua icona
            // invece di mostrare un quadrato con l'iniziale.
            'wmClass': app.wmClass,
            // Per cercare un'app per quello che FA, non solo per nome: «browser»,
            // «navigatore», «navigare il web». Sono le parole che il programma
            // dichiara nel suo `.desktop`, nella lingua dell'utente.
            'generico': app.generico,
            'descrizione': app.descrizione,
            'parole': app.parole,
            'lanci': _appUsageTracker.lanci(app.id),
            'adesso': _appUsageTracker.adesso(app.id),
          }
      ];

  Map<String, dynamic> get _iconPayload => {
        'style': _settingsApi.getString('icons.style', 'minerva'),
        'theme': _iconResolver.activeTheme,
        // La FAMIGLIA scelta, non il nome salvato: nelle impostazioni può
        // esserci ancora «Colloid-Light», scritto quando l'elenco mostrava
        // anche le varianti, e l'elenco di oggi ha solo «Colloid».
        'chosen': _iconResolver.chosenTheme,
        'map': _iconMap,
        // ── Quanto copre il tema scelto ────────────────────────────────
        //
        // Il registro lo scriveva già («71/89 da Colloid») e nessuno lo
        // leggeva. Giacomo, guardando la barra: «ci sono icone che non si
        // trovano» — ed è vero, ma finché è una sensazione non si ripara.
        // Con un numero e un elenco diventa una cosa che si può guardare:
        // sono i nomi che QUESTO tema non ha, non difetti nostri.
        'chieste': minervaIconNames.length,
        'mancanti': (minervaIconNames.keys.toList()
              ..removeWhere(_iconMap.containsKey))
            ..sort(),
      };

  /// Il tema di icone scelto in Impostazioni può essere cambiato da qualunque
  /// finestra; chi lo scopre è il demone, leggendo le impostazioni salvate.
  /// Se è cambiato davvero, si rifà la mappa e la si manda a TUTTI — non solo
  /// a chi ha toccato l'interruttore, che è l'unico processo che non ha
  /// bisogno di essere avvisato.
  void _applyIconThemeFromSettings() {
    // Due cose possono essere cambiate, e tutte e due cambiano le icone: il
    // tema scelto, e il COLORE DI FONDO dell'interfaccia. Il secondo non è
    // ovvio — si sceglie «Rosa» pensando ai pannelli — ma i temi di icone
    // sono disegnati per un fondo preciso, e su quello sbagliato le icone
    // monocromatiche spariscono. Vedi `services/schemi.dart`.
    final scuro = Schemi.eScuro(
        _settingsApi.getString('shell.scheme', Schemi.predefinito),
        personaleScuro:
            _settingsApi.getValue('shell.versoPersonale', true) == true);
    final cambiatoSfondo = _iconResolver.setInterfacciaScura(scuro);
    final cambiatoTema =
        _iconResolver.setTheme(_settingsApi.getString('icons.theme', ''));
    if (!cambiatoTema && !cambiatoSfondo) {
      return;
    }
    _rebuildIconMap();

    // ── Due elenchi, non uno ────────────────────────────────────────────
    //
    // `icons` sono le icone di MINERVA: quelle disegnate dentro la barra, i
    // pannelli, i menu. `all_apps` sono le icone dei PROGRAMMI: quelle della
    // dock, del menu delle applicazioni, della ricerca e delle barre del
    // titolo.
    //
    // Passano per due strade diverse perché nascono in due posti diversi — le
    // prime da un elenco di nomi nostro, le seconde dal campo `Icon=` di ogni
    // file `.desktop` — e qui si mandava solo la prima. Il risultato è quello
    // che Giacomo ha visto: si cambia tema di icone, cambiano le icone della
    // shell, e la dock resta identica. Non era la dock a non ascoltare: erano
    // i percorsi dei programmi a non essere mai stati ricalcolati, perché li
    // si risolveva soltanto rispondendo a `get_all_apps`.
    final apps = _allAppsPayload;
    _aTutti({'event': 'icons', 'payload': _iconPayload});
    _aTutti({'event': 'all_apps', 'payload': apps});
  }

  // ignore: prefer_initializing_formals
  WebSocketServer(
    this._eventBus,
    this._stateManager,
    this._settingsApi,
    this._compositorProvider,
    this._appScanner,
    this._iconResolver,
    this._appUsageTracker,
    this._keybindService,
    this._fileService,
    this._systemState,
    this._finestre,
    this._processi, {
    String? socket,
  }) : _percorsoSocket = socket ?? socketConfigurato;

  /// Avvia il server e si mette in ascolto degli eventi del bus per inoltrarli ai client.
  Future<void> start() async {
    try {
      // Prima di accettare chiunque: il tema di icone scelto dall'utente e la
      // traduzione delle nostre icone in quel tema. Il primo client riceve la
      // mappa già dentro `init_state`, così la barra non compare mai con le
      // icone sbagliate per poi correggersi sotto gli occhi.
      _iconResolver.setInterfacciaScura(Schemi.eScuro(
          _settingsApi.getString('shell.scheme', Schemi.predefinito),
          personaleScuro:
              _settingsApi.getValue('shell.versoPersonale', true) == true));
      _iconResolver.setTheme(_settingsApi.getString('icons.theme', ''));
      _rebuildIconMap();

      // ── La porta ────────────────────────────────────────────────────
      //
      // Se qualcuno l'ha DETTA (`MINERVA_IPC_PORT`) è quella e nessun'altra:
      // la schermata di accesso e le prove ci contano, e ripiegare su un'altra
      // vorrebbe dire ignorare in silenzio un ordine esplicito.
      //
      // Se invece nessuno l'ha detta, si prende la prima libera a partire
      // dalla 11432. È così che due sessioni Minerva possono stare accese
      // insieme: la seconda non muore più perché la prima aveva già preso il
      // numero. Chi deve trovarci non indovina — la porta scelta finisce nel
      // file del canale, e le finestre leggono di lì.
      _server = await _ascolta();

      print('[MINERVA][IPC][OK] Server in ascolto su $_percorsoSocket');

      // Il segreto DOPO aver preso il socket, perché nel file ci va anche il
      // percorso; e prima di accettare chiunque, perché un demone che ascolta
      // e non ha ancora una parola d'ordine è un demone che non la chiede.
      _segreto = await CanaleSegreto.scriviNuovo(socket: _percorsoSocket);
      print('[MINERVA][IPC][OK] Indirizzo del canale in '
          '${CanaleSegreto.scrittoIn} (sessione «${CanaleSegreto.sessione()}»)');

      _server!.listen(_handleNewClient);

      // Ascolta tutti gli eventi del bus e li trasmette ai client interessati
      _eventBusSubscription = _eventBus.stream.listen((event) {
        if (event.type == 'settings_changed') _applyIconThemeFromSettings();
        _broadcastEvent(event);
      });

      // L'avanzamento dei trasferimenti va a TUTTI i client, senza passare dal
      // bus: è un flusso continuo e ad alta frequenza, e il bus è pensato per
      // eventi rari a cui ci si iscrive.
      _transferSubscription = _fileService.progress.listen((job) {
        _aTutti({'event': 'fs_job', 'payload': job});
      });

      // Dove sono le finestre, e quanto spazio c'è. Per la stessa ragione
      // dell'avanzamento qui sopra: è un flusso, non un annuncio. Fino a
      // sedici messaggi al secondo mentre una finestra si muove, e serve a
      // TUTTE le finestre di Minerva — la barra ci disegna le barre del
      // titolo, il gestore file e le Impostazioni ci disegnano la propria.
      // Passare dal bus vorrebbe dire dipendere da una sottoscrizione, e
      // dimenticarla è una shell cieca senza nessun errore da nessuna parte.
      _statoFinestreSub = _finestre.finestre.listen((json) {
        _aTutti({'event': 'windows_state', 'payload': json});
      });
      _statoMonitorSub = _finestre.monitor.listen((json) {
        _aTutti({'event': 'monitors_state', 'payload': json});
      });
    } catch (e) {
      // Senza canale il demone non serve a niente: la shell non lo trova, e
      // ogni finestra mostra i valori di fabbrica fingendo siano quelli di chi
      // guarda. Prima si scriveva una riga di registro e si restava vivi — ed
      // è così che la schermata di accesso è finita a parlare col demone di un
      // altro utente senza che nessuno se ne accorgesse.
      //
      // Se il socket è occupato lo si dice per nome, perché è il caso che
      // capita davvero e la causa non si indovina da «Address already in use».
      print('[MINERVA][IPC][ERRORE] Impossibile ascoltare su '
          '$_percorsoSocket: $e');
      if (e is SocketException && e.osError?.errorCode == 98) {
        print('[MINERVA][IPC][ERRORE] Il socket è già di qualcuno: c\'è un '
            'altro minervad acceso su questa stessa sessione. Se questo è il '
            'greeter, dagli un socket suo con MINERVA_IPC_SOCKET.');
      }
      rethrow;
    }
  }

  /// Apre la porta. Con `fisso` vera è quella e basta; altrimenti si sale
  /// finché non se ne trova una libera.
  /// Prende il socket, e prima di prenderlo decide se quello che trova per
  /// terra è di qualcuno o è un avanzo.
  ///
  /// ── Il socket avanzato, che è una trappola già pagata ─────────────────
  ///
  /// Un socket Unix è un file, e a differenza di una porta **non sparisce**
  /// quando il processo muore: resta lì. Se il demone è stato ucciso invece
  /// che chiuso — un `kill -9`, un riavvio brusco, una prova finita male — al
  /// prossimo avvio `bind` fallisce con «indirizzo già in uso» pur non essendo
  /// in uso da nessuno, e il demone non parte mai più finché qualcuno non
  /// cancella il file a mano.
  ///
  /// La tentazione è cancellarlo sempre. **Non si fa**, ed è esattamente lo
  /// sbaglio che in questo progetto è già costato una scrivania vuota senza un
  /// errore da nessuna parte (vedi gli annunci di minerva-wayland): cancellare
  /// il socket di un demone VIVO non lo uccide — lo rende irraggiungibile, e
  /// da quel momento ci sono due demoni, uno dei quali parla con le finestre e
  /// l'altro tiene lo stato vero.
  ///
  /// L'unico modo onesto di distinguere è **provare a collegarsi**: se
  /// qualcuno risponde, quel socket è suo e ci si ferma; se il collegamento
  /// viene rifiutato, dall'altra parte non c'è nessuno e il file è un avanzo.
  Future<ServerSocket> _ascolta() async {
    final file = File(_percorsoSocket);
    final cartella = file.parent;
    if (!await cartella.exists()) {
      await cartella.create(recursive: true);
      await Process.run('chmod', ['700', cartella.path]);
    }

    if (await file.exists()) {
      if (await _rispondeQualcuno(_percorsoSocket)) {
        throw StateError(
            'C\'è già un minervad in ascolto su $_percorsoSocket. Due demoni '
            'sulla stessa sessione non si possono: se questo è il greeter, '
            'dagli un socket suo con MINERVA_IPC_SOCKET.');
      }
      print('[MINERVA][IPC][INFO] $_percorsoSocket era rimasto per terra da un '
          'avvio precedente e non risponde a nessuno: lo tolgo.');
      await file.delete();
    }

    final s = await ServerSocket.bind(
        InternetAddress(_percorsoSocket, type: InternetAddressType.unix), 0);

    // I permessi del socket sono la serratura, adesso che non c'è più una
    // porta. `$XDG_RUNTIME_DIR` è già 0700 e da solo basterebbe, ma il file
    // del canale può finire anche in una cartella di configurazione (vedi
    // `CanaleSegreto.candidati()`) e lì la garanzia sarebbe di qualcun altro.
    // Una serratura che dipende da come è messa la porta accanto non è una
    // serratura.
    await Process.run('chmod', ['600', _percorsoSocket]);
    return s;
  }

  /// Vero se dall'altro capo di questo socket c'è qualcuno che risponde.
  ///
  /// Non si manda niente e non si aspetta una risposta: basta che la
  /// `connect` riesca. Un demone vivo accetta la connessione; un file
  /// avanzato la fa rifiutare con `ECONNREFUSED`.
  static Future<bool> _rispondeQualcuno(String percorso) async {
    try {
      final s = await Socket.connect(
          InternetAddress(percorso, type: InternetAddressType.unix), 0,
          timeout: const Duration(seconds: 2));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _handleNewClient(Socket socket) {
    final client = WebSocketClientConnection(socket);
    // Se muore da sé — una finestra uccisa con `kill -9`, o sparita insieme al
    // compositore — se ne accorge la connessione, e da lì l'elenco. Prima
    // l'unica strada era `onDone` sul flusso in LETTURA: una finestra che
    // smetteva di leggere ma teneva aperto il socket restava nell'elenco, e
    // ogni `windows_state` le veniva scritto addosso lo stesso.
    client.alMorire = () {
      if (_clients.contains(client)) _removeClient(client);
    };
    _clients.add(client);
    print('[MINERVA][IPC][INFO] Client connesso (Totale connessi: ${_clients.length})');

    // ── Prima di tutto: chi sei? ──────────────────────────────────────────
    //
    // Finché non ha detto la parola d'ordine, questo client non riceve niente
    // e non può fare niente. Nemmeno `init_state`: le impostazioni non sono
    // segrete, ma non c'è ragione di darle a chi non sappiamo chi è.
    //
    // E c'è un limite di tempo. Senza, chi si collega e sta zitto tiene una
    // connessione aperta per sempre — un modo silenzioso di riempire il
    // demone di connessioni finché non ne accetta più, cioè finché la barra
    // che si riavvia non riesce più a rientrare.
    Timer(const Duration(seconds: 5), () {
      if (!client.autenticato && _clients.contains(client)) {
        print('[MINERVA][IPC][ATTENZIONE] Un client non ha detto la parola '
            "d'ordine entro cinque secondi: chiuso.");
        _removeClient(client);
      }
    });

    // ── Dove finisce un messaggio e comincia il prossimo ────────────────
    //
    // Il WebSocket questo lo dava gratis: ogni `add` arrivava dall'altra parte
    // come un messaggio intero. Un socket è un tubo di byte — quello che si
    // scrive in una volta può arrivare in tre pezzi, e tre messaggi scritti in
    // fila possono arrivare tutti insieme. Senza un confine, il primo JSON
    // spezzato a metà manderebbe in errore il parser e la finestra resterebbe
    // in attesa per sempre, che è il guasto peggiore di questo canale (vedi
    // `EVENTS.md`).
    //
    // Il confine è l'a-capo, e si può usare perché `jsonEncode` non ne
    // produce mai uno dentro un messaggio: un a-capo dentro una stringa
    // diventa `\n`, due caratteri. Quindi una riga è sempre esattamente un
    // messaggio.
    //
    // `utf8.decoder` prima di `LineSplitter` e non dopo, perché un carattere
    // accentato può essere spezzato a metà fra due pezzi: decodificare pezzo
    // per pezzo lo romperebbe. Il decodificatore di Dart tiene i byte a metà
    // e li ricongiunge da sé.
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (riga) {
        if (riga.isNotEmpty) _handleClientMessage(client, riga);
      },
      onError: (err) {
        // ── Una finestra che si chiude non è un errore ────────────────
        //
        // Chiudendo una nostra applicazione il processo muore senza salutare,
        // e il socket cade: Dart lo riporta come `Connection reset by peer`
        // (errno 104) o `Broken pipe` (errno 32). Sono i due modi normali in
        // cui un client se ne va, e finivano sul registro marcati ERRORE.
        //
        // Nel registro di una sessione vera del 1º settembre 2026 erano
        // sedici righe su una giornata di uso normale: ogni volta che si
        // chiudeva la calcolatrice o il gestore file. Un errore che compare
        // quando NON c'è niente che non va insegna a non leggere il registro,
        // e il giorno che ce n'è uno vero passa inosservato in mezzo agli
        // altri.
        //
        // Il caso resta gestito allo stesso modo — il client si toglie — e
        // ogni altro errore continua a scriversi per intero.
        final testo = '$err';
        final normale = err is SocketException &&
            (err.osError?.errorCode == 104 || err.osError?.errorCode == 32);
        if (normale) {
          print('[MINERVA][IPC][INFO] Un client se n\'è andato senza '
              'salutare (${err.osError?.errorCode == 104 ? "reset" : "pipe"}): '
              'è come si chiude una finestra.');
        } else {
          print('[MINERVA][IPC][ERRORE] Errore di connessione del client: '
              '$testo');
        }
        _removeClient(client);
      },
      onDone: () {
        _removeClient(client);
      },
    );
  }

  /// La parola d'ordine è giusta: da qui in poi il client è uno di noi, e
  /// riceve quello che riceveva prima appena connesso.
  void _saluta(WebSocketClientConnection client) {
    client.autenticato = true;
    client.send({'event': 'ciao', 'payload': {'ok': true}});

    // Manda subito lo stato corrente, le impostazioni e il tema al client alla connessione
    client.send({
      'event': 'init_state',
      'payload': {
        'state': _stateManager.toJson(),
        'settings': _settingsApi.settings,
        'keybindings': _keybindService.toJson(),
        'icons': _iconPayload,
        'system': _systemState.state,
      }
    });

    // Adesso c'è qualcuno che guarda: il servizio riprende a interrogare il
    // compositore, e gli manda lo stato subito — senza aspettare che una
    // finestra si muova. Una finestra di Minerva aperta da sola su una
    // scrivania ferma altrimenti resterebbe senza elenco per sempre.
    _finestre.clienti(_clients.length);
    _finestre.spingiTutto();
  }

  void _removeClient(WebSocketClientConnection client) {
    _clients.remove(client);
    client.close();
    print('[MINERVA][IPC][INFO] Client disconnesso (Totale connessi: ${_clients.length})');

    // Andato via l'ultimo, si smette di guardare.
    _finestre.clienti(_clients.length);

    // Un monitor chiuso con la X non manda `unsubscribe`: se ne accorge solo
    // chi lo vede sparire. Senza questa riga il servizio continuerebbe a
    // leggere `/proc` ogni due secondi per il resto della sessione.
    if (_iscrittiProcessi.remove(client)) _processi.disiscrivi();
    if (_iscrittiMacchina.remove(client)) _processi.disiscriviMacchina();

    // Stessa ragione per il greeter: se se ne va, le risposte di PAM non
    // devono continuare a essere spedite a una connessione morta. E se se n'è
    // andato con un tentativo di accesso a metà, quel tentativo va annullato —
    // greetd tiene UNA sessione in configurazione, e lasciarla lì impedisce
    // al greeter successivo di cominciarne una.
    if (identical(_ilGreeter, client)) {
      _ilGreeter = null;
      _greetd?.annulla();
    }
  }

  /// Il comando che apre `riga` dentro un terminale.
  ///
  /// Si prova prima quello che l'utente ha scelto (`$TERMINAL`), poi quello di
  /// Minerva, poi i più diffusi. Non si dà per scontato Alacritty: chi installa
  /// Minerva su un'altra macchina può non averlo, e un programma che non parte
  /// perché manca un terminale è lo stesso difetto di prima con un nome nuovo.
  ///
  /// La riga si passa a `sh -c` DENTRO il terminale e non spezzata a mano: un
  /// `Exec=` può contenere pipe, virgolette e variabili, ed è già una riga di
  /// shell — spezzarla sugli spazi la romperebbe.
  static String dentroUnTerminale(String riga) {
    final scelto = Platform.environment['TERMINAL'];
    // Il nostro per primo (15 settembre 2026): `minerva-terminale -e` apre
    // una scheda col comando, come `alacritty -e`. `$TERMINAL` resta la
    // scelta di chi lo imposta, e viene prima.
    final candidati = [
      if (scelto != null && scelto.isNotEmpty) scelto,
      'minerva-terminale',
      'alacritty', 'foot', 'kitty', 'konsole', 'gnome-terminal',
      'xfce4-terminal', 'xterm',
    ];
    final protetta = protettaPerShell(riga);
    final quale = candidati
        .map((t) => 'command -v $t >/dev/null 2>&1 && exec $t -e sh -c \'$protetta\'')
        .join('; ');
    return quale;
  }

  /// Prepara una riga per stare DENTRO `'…'` in un comando di shell.
  ///
  /// ── La sequenza giusta, e quella che c'era ─────────────────────────────
  ///
  /// Dentro le virgolette singole la shell non interpreta niente — nemmeno la
  /// barra rovesciata — quindi una virgoletta non si può proteggere: bisogna
  /// **uscire** dalla stringa, metterla, e rientrare. Sono quattro caratteri:
  /// `'\''` — chiudi, virgoletta protetta fuori dalle virgolette, riapri.
  ///
  /// Fino al 7 settembre 2026 qui c'era `'''`, che è chiudi-apri-chiudi e
  /// lascia la riga **sbilanciata**: da quel punto in poi il resto è fuori
  /// dalle virgolette, cioè è comando. Provato:
  ///
  ///     'x''' ; echo INIETTATO ; echo '''y'   →  INIETTATO viene ESEGUITO
  ///     'x'\'' ; echo INIETTATO ; echo '\''y' →  resta il testo che era
  ///
  /// ── Quanto valeva davvero ──────────────────────────────────────────────
  ///
  /// Meno della parola «iniezione»: la riga `Exec=` di un `.desktop` finisce
  /// comunque dentro `sh -c` anche senza terminale, quindi non si guadagnava
  /// nessun potere nuovo; e `app_scanner` toglie i segnaposto `%f`/`%F`,
  /// quindi nessun nome di file arrivava mai qui. Il danno vero era che un
  /// programma da terminale con un apostrofo nel comando **non parte e non
  /// dice perché**. Sui 167 `.desktop` di questo computer non ne colpiva
  /// nessuno: era una trappola che aspettava, non un sintomo.
  ///
  /// Il modo che non ha questo problema è passare gli argomenti a uno a uno
  /// invece di comporre una riga — vedi `mime_service.dart`, che lo fa. Qui
  /// non si può: un `Exec=` **è** una riga di shell, con pipe e variabili, e
  /// spezzarla sugli spazi la romperebbe.
  static String protettaPerShell(String riga) =>
      riga.replaceAll("'", r"'\''");



  void _handleClientMessage(WebSocketClientConnection client, String rawData) async {
    // Fuori dal `try` perché serve al `catch`: per dire «questa richiesta non
    // è andata» bisogna sapere QUALE, e se la dichiarazione sta dentro il try
    // il catch non la vede. Resta `null` solo se è il `jsonDecode` a fallire,
    // cioè se non era nemmeno un messaggio.
    Object? msgAzione;
    try {
      final Map<String, dynamic> msg = jsonDecode(rawData);
      final action = msg['action'];
      msgAzione = action;

      // ── Il cancello ───────────────────────────────────────────────────
      //
      // Sta qui e non dentro lo `switch` perché deve valere per TUTTE le
      // azioni, comprese quelle che qualcuno aggiungerà domani. Un elenco di
      // azioni protette è un elenco che prima o poi dimentica qualcosa, e la
      // dimenticanza non si vede: l'azione funziona, semplicemente funziona
      // anche per chi non doveva.
      if (!client.autenticato) {
        if (action == 'ciao' &&
            CanaleSegreto.combacia(_segreto, msg['segreto'] as String?)) {
          _saluta(client);
          return;
        }
        // Non si dice se la parola d'ordine era sbagliata o se mancava, e non
        // si lascia la connessione aperta per riprovare: chi ce l'ha la dice
        // al primo colpo, chi non ce l'ha non deve poterla cercare.
        print('[MINERVA][IPC][ATTENZIONE] Rifiutato un client senza parola '
            "d'ordine (azione «$action»).");
        client.send({
          'event': 'ciao',
          'payload': {'ok': false, 'errore': "parola d'ordine mancante o errata"},
        });
        _removeClient(client);
        return;
      }

      // ── La risposta porta l'identificativo della domanda ────────────
      //
      // Il protocollo riconosce le risposte dal TIPO e da nient'altro: due
      // richieste uguali in volo insieme sono indistinguibili, e chi aspetta
      // prende la prima che passa. Con una shell sola si nota poco; con otto
      // finestre di Minerva sullo stesso demone è una corsa che aspetta il
      // suo giorno — ed è anche la ragione per cui «questa richiesta non è
      // andata» non si poteva dire bene: per dirlo bisogna sapere QUALE.
      //
      // Si passa da una ZONA e non da un campo del client: fra un `await` e
      // il successivo il demone serve altri messaggi, e un campo verrebbe
      // sovrascritto da chi arriva nel frattempo — cioè si romperebbe
      // proprio nel caso per cui esiste. La zona invece segue questa
      // esecuzione attraverso gli `await`, che è quello che serve.
      //
      // Chi non manda un `id` non ne riceve uno: la shell di oggi non lo usa
      // e le sue risposte restano identiche a prima.
      await runZoned(
        () => _eseguiAzione(client, action, msg),
        zoneValues: {
          _chiaveId: msg['id'],
          _chiaveCliente: client,
        },
      );
    } catch (e) {
      print('[MINERVA][IPC][ERRORE] Errore nel processare messaggio del client: $e');
      // ── E lo si dice a chi ha chiesto ─────────────────────────────────
      //
      // Fino al 7 settembre 2026 qui c'era solo la riga qui sopra. Se una
      // qualunque delle azioni scoppiava a metà — un `as String?` su un numero
      // basta — chi aveva mandato il messaggio restava ad aspettare per
      // sempre, e il canale RESTAVA VIVO: il difetto non si vedeva nemmeno.
      //
      // Un `client.send` dentro un `catch` non può a sua volta far cadere il
      // messaggio d'errore, o si torna al silenzio da un'altra porta.
      try {
        _nonSonoRiuscito(client, msgAzione, '$e');
      } catch (_) {}
    }
  }

  /// I 140 verbi del demone.
  ///
  /// Sta in un metodo suo e non dentro `_handleClientMessage` per una
  /// ragione precisa: il cancello, la zona dell'identificativo e la rete
  /// che prende le eccezioni valgono per TUTTE le azioni, e devono stare
  /// fuori — dove non si possano dimenticare aggiungendone una nuova.
  Future<void> _eseguiAzione(WebSocketClientConnection client, Object? action,
      Map<String, dynamic> msg) async {
    switch (action) {
      case 'subscribe':
        final List<dynamic>? events = msg['events'];
        if (events != null) {
          client.subscribedEvents = events.cast<String>();
        }
        break;
      // ── Qui c'era la SECONDA porta verso il compositore ───────────────
      //
      // `switch_workspace`, `close_window`, `focus_window` e
      // `get_active_window`: quattro verbi che il demone girava al
      // compositore. Sono stati tolti il 23 agosto 2026 perché non li
      // chiamava più nessuno da quando la shell ha la sua porta
      // (`minerva-shell/core/Compositore.qml`), e una porta aperta che non
      // usa nessuno è una porta che nessuno sorveglia.
      //
      // La regola che ne esce, e che vale anche per minerva-wayland:
      // **il demone OSSERVA il compositore, la shell lo COMANDA.**
      // Restano infatti `getClientsRaw`, `getMonitorsRaw` e `getWorkspaces`
      // — che sono domande, non ordini. Il giorno in cui si scriverà
      // `MinervaProvider` sarà tre metodi e non sette.
      //
      // Con loro se n'è andato `publish_event`, che permetteva a chiunque
      // fosse collegato di mettere sul bus del demone un evento inventato,
      // che tutti gli altri poi si bevevano. Non lo usava nessuno; toglierlo
      // è pulizia e insieme una porta in meno.
      // L'elenco delle finestre si chiede al compositore ADESSO, e non lo si
      // tiene aggiornato di continuo: era il contrario, e costava un giro di
      // IPC a ogni finestra aperta o chiusa per una risposta che nessuno
      // chiedeva mai. Vedi `core/state_manager.dart`.
      case 'get_state':
        {
          final stato = _stateManager.toJson();
          stato['windows'] = [
            for (final w in await _compositorProvider.getWorkspaces())
              w.toJson()
          ];
          client.send({'event': 'state_response', 'payload': stato});
        }
        break;
      // ── La ricerca universale ─────────────────────────────────────
      //
      // L'unico ramo di questo switch che non stava in una schermata: 109
      // righe di codice contro le dieci della media. Un `case` così lungo
      // non è solo scomodo da leggere — le variabili che dichiara sono
      // visibili ai rami vicini, perché in Dart i casi di uno switch
      // condividono lo scopo se non hanno graffe proprie.
      case 'matrix_search':
        await _ricercaUniversale(client, msg);
        break;
      // ── Lanciare un programma, anche quelli da terminale ───────────
      //
      // `Terminal=true` nel file `.desktop` vuol dire «questo programma
      // scrive su un terminale»: lanciato senza, si apre e si chiude
      // nell'istante dopo, e da fuori sembra che non parta affatto.
      //
      // Il demone la sapeva già — `app_scanner` legge quel campo e lo
      // espone — e non la usava. Sono i programmi come `arch-update`, che
      // dal menu di Minerva non si aprivano e basta: nessuna finestra,
      // nessun errore, niente. Provato l'11 agosto 2026 dal bus.
      //
      // La decisione sta QUI e non in chi chiama: un domani ci sarà un
      // altro posto da cui si lancia qualcosa, e chi lo scrive non deve
      // doversi ricordare di questa regola.
      case 'launch_app':
        final exec = msg['exec'];
        final id = (msg['id'] ?? msg['appId']) as String?;
        if (exec is String && exec.isNotEmpty) {
          final app = id == null ? null : _appScanner.getAppById(id);
          final vuoleTerminale =
              app?.needsTerminal == true || msg['terminal'] == true;
          final comando =
              vuoleTerminale ? dentroUnTerminale(exec) : exec;
          print('[MINERVA][IPC][INFO] Lancio applicazione: $comando '
              '(ID: $id${vuoleTerminale ? ", nel terminale" : ""})');
          await Process.start('sh', ['-c', comando],
              mode: ProcessStartMode.detached);
          if (id != null && id.isNotEmpty) {
            await _appUsageTracker.recordLaunch(id);
            await _appScanner.novita.vista(id);
            // Sempre, non solo per le app «nuove»: i lanci e l'ora di ogni
            // lancio sono quello che ordina «Frequenti» e «Adesso, di
            // solito». Un lancio è un evento raro: il costo è niente, e
            // senza il menù restava fermo ai conti dell'avvio.
            _aTutti({'event': 'all_apps', 'payload': _allAppsPayload});
          }
        }
        break;
      case 'launch_desktop':
        // Un file .desktop preso da un percorso qualsiasi — un launcher
        // sulla scrivania — lanciato come un programma qualunque. Senza
        // questa strada il doppio clic su un launcher della scrivania lo
        // aprirebbe come testo.
        final path = msg['path'];
        if (path is String && path.isNotEmpty) {
          final app = await _appScanner.parseFromPath(path);
          if (app != null && app.exec.isNotEmpty) {
            final comando = app.needsTerminal
                ? dentroUnTerminale(app.exec)
                : app.exec;
            print('[MINERVA][IPC][INFO] Lancio .desktop: $comando '
                '(da $path)');
            await Process.start('sh', ['-c', comando],
                mode: ProcessStartMode.detached);
            await _appUsageTracker.recordLaunch(app.id);
            _aTutti({'event': 'all_apps', 'payload': _allAppsPayload});
          } else {
            print('[MINERVA][IPC][WARN] .desktop illeggibile o senza '
                'comando: $path');
          }
        }
        break;
      case 'update_fixed_apps':
        final apps = msg['apps'];
        if (apps is List) {
          final List<String> list = apps.cast<String>();
          await _settingsApi.updateFixedApps(list);
        }
        break;
      // ── Scorciatoie ────────────────────────────────────────────────
      // Le scorciatoie già tradotte per minerva-wayland. È la SHELL a
      // portargliele, non il demone: il demone osserva il compositore, la
      // shell lo comanda — ed è lei che ha il canale in mano.
      case 'scorciatoie_compositore':
        client.send({
          'event': 'scorciatoie_compositore',
          'payload': {'righe': _keybindService.perMinervaWayland()},
        });
        break;

      case 'get_keybindings':
        client.send({
          'event': 'keybindings',
          'payload': _keybindService.toJson(),
        });
        break;

      // ── Impostazioni ───────────────────────────────────────────────
      // ── Il monitor di sistema ──────────────────────────────────
      //
      // `subscribe` e `unsubscribe` non sono un vezzo: il servizio legge
      // `/proc` solo mentre qualcuno guarda, e senza la disiscrizione
      // resterebbe acceso per tutta la sessione dopo la prima apertura.
      case 'subscribe_processes':
        // L'evento `processes` NON sta fra quelli inoltrati di default, ed è
        // voluto: è il più pesante che il demone produca — cinquanta
        // kilobyte ogni due secondi — e serve a una finestra sola. Si
        // aggiunge alla lista di CHI l'ha chiesto e si toglie quando esce.
        if (_iscrittiProcessi.add(client)) {
          _processi.iscrivi();
          if (!client.subscribedEvents.contains('processes')) {
            client.subscribedEvents = [...client.subscribedEvents, 'processes'];
          }
        }
        break;
      case 'unsubscribe_processes':
        if (_iscrittiProcessi.remove(client)) {
          _processi.disiscrivi();
          client.subscribedEvents =
              client.subscribedEvents.where((e) => e != 'processes').toList();
        }
        break;
      // ── E l'iscrizione leggera, per i widget della scrivania ────────
      //
      // Stessa forma di `subscribe_processes` e stessa ragione — si legge
      // solo mentre qualcuno guarda — ma un ventesimo del costo: nessun
      // processo, quattro file, e cinque secondi invece di due.
      //
      // I widget della scrivania stanno accesi tutto il giorno. Farli passare
      // dall'iscrizione pesante vorrebbe dire il fermo di 22 ms della visura
      // del 7 settembre 2026, per sempre.
      case 'subscribe_machine':
        if (_iscrittiMacchina.add(client)) {
          _processi.iscriviMacchina();
          if (!client.subscribedEvents.contains('machine_state')) {
            client.subscribedEvents =
                [...client.subscribedEvents, 'machine_state'];
          }
        }
        break;
      case 'unsubscribe_machine':
        if (_iscrittiMacchina.remove(client)) {
          _processi.disiscriviMacchina();
          client.subscribedEvents = client.subscribedEvents
              .where((e) => e != 'machine_state')
              .toList();
        }
        break;
      // Tre numeri, non trecento righe: vedi `soloMacchina`.
      case 'machine_state':
        client.send({
          'event': 'machine_state',
          'payload': await _processi.soloMacchina(),
        });
        break;

      case 'get_processes':
        client.send({'event': 'processes', 'payload': await _processi.leggi()});
        break;
      case 'kill_process':
        {
          final pid = msg['pid'];
          final forza = msg['force'] == true;
          if (pid is int && pid > 1) {
            final ok = forza
                ? await _processi.termina(pid)
                : await _processi.chiudi(pid);
            client.send({
              'event': 'process_killed',
              'payload': {'pid': pid, 'ok': ok, 'force': forza},
            });
          }
        }
        break;

      // ── Scrivere un'impostazione, e sapere se è andata ─────────────
      //
      // Il demone rifiuta le chiavi che non esistono nei valori di fabbrica.
      // È giusto — le chiavi inventate restavano nel file di chi usa Minerva
      // senza che le leggesse nessuno — ma fino al 7 settembre 2026 il
      // rifiuto non tornava indietro: né una risposta, né un
      // `settings_changed`. Chi aveva scritto restava convinto di aver
      // scritto, e una manopola legata a una chiave sbagliata sarebbe
      // rimasta ferma per sempre senza un errore da nessuna parte.
      case 'set_setting':
        final path = msg['path'];
        if (path is! String || path.isEmpty) {
          _nonSonoRiuscito(client, action, 'manca il percorso');
        } else if (!await _settingsApi.setValue(path, msg['value'])) {
          _nonSonoRiuscito(client, action,
              'l\'impostazione «$path» non esiste nei valori di fabbrica');
        }
        break;
      case 'set_settings':
        final values = msg['values'];
        if (values is! Map) {
          _nonSonoRiuscito(client, action, 'manca l\'elenco dei valori');
        } else {
          final rifiutate = await _settingsApi
              .setValues(Map<String, dynamic>.from(values));
          // Le altre sono passate lo stesso: un preset che ne contiene una
          // sbagliata deve applicare le altre. Ma va detto quali no.
          if (rifiutate.isNotEmpty) {
            _nonSonoRiuscito(client, action,
                'queste impostazioni non esistono nei valori di fabbrica: '
                '${rifiutate.join(", ")}');
          }
        }
        break;
      case 'reset_settings':
        await _settingsApi.resetToDefaults();
        break;

      // ── Icone ──────────────────────────────────────────────────────
      //
      // Le nostre icone tradotte nel tema installato sul computer, per chi
      // preferisce quelle di sempre a quelle disegnate da noi. Arriva già
      // con `init_state`: questa richiesta serve a rileggerle senza
      // riconnettersi, per esempio dopo aver installato un tema nuovo.

      // L'elenco dei temi installati, per il menu delle Impostazioni. Si
      // legge dal disco a ogni richiesta e non una volta all'avvio: un tema
      // installato a sessione aperta deve comparire senza riavviare niente.
      case 'get_icon_themes':
        client.send({
          'event': 'icon_themes',
          'payload': {
            'themes': _iconResolver.listThemes(),
            'detected': _iconResolver.detectedTheme,
          },
        });
        break;

      // ── Dove sono le finestre, e quanto spazio c'è ─────────────────
      //
      // Normalmente non serve chiederlo: arriva. Serve dopo aver MANDATO un
      // comando — ingrandisci, aggancia, riduci a icona — quando la shell
      // vuole vedere l'effetto senza attendere l'evento del compositore,
      // che per un ingrandimento può arrivare qualche fotogramma dopo.
      //
      // Sono le due azioni che il QML chiamava e che non trovavano nessuno:
      // `Core.Windows.refresh()` e `refreshUsable()` mandavano `get_windows`
      // e `get_monitors`, il demone non li conosceva, e la shell restava con
      // zero finestre e spazio utile sconosciuto — senza un errore da
      // nessuna parte, perché un'azione ignota qui non risponde e non si
      // lamenta. La prova in `test/finestre_test.dart` esiste per questo.
      case 'get_windows':
        client.send({
          'event': 'windows_state',
          'payload': await _compositorProvider.getClientsRaw(),
        });
        break;
      case 'get_monitors':
        client.send({
          'event': 'monitors_state',
          'payload': await _compositorProvider.getMonitorsRaw(),
        });
        break;

      // ── «Sto trascinando una finestra» ─────────────────────────────
      //
      // È l'unica cosa che il compositore non annuncia: mentre si tiene
      // premuto e si sposta, la geometria cambia sessanta volte al secondo
      // e da fuori non si sa. Il demone lo scopriva guardando — sei volte
      // al secondo, per sempre, anche a scrivania ferma: 1,05% di un core
      // misurato l'11 agosto 2026.
      //
      // Dirlo costa un messaggio quando si preme il tasto e uno quando lo
      // si molla.  alla pressione,  al rilascio.
      // ── Cercare un file dentro le cartelle ─────────────────────────
      //
      // Il filtro del gestore file guarda solo la cartella aperta: è
      // immediato e risponde a «dov'è, qui dentro». Questa risponde
      // all'altra domanda, quella che ci si fa più spesso: «dov'è, da
      // qualche parte».
      //
      // I risultati escono a mazzetti mentre cerca, e non alla fine: su una
      // cartella di casa con centomila file, aspettare la fine vuol dire
      // una finestra ferma per venti secondi.
      case 'fs_search':
        final id = '${msg['id'] ?? client.hashCode}';
        unawaited(() async {
          await for (final pezzo in _ricerca.cerca(
            id,
            '${msg['path']}',
            '${msg['query'] ?? ''}',
            ancheNascosti: msg['hidden'] == true,
          )) {
            client.send({'event': 'fs_search', 'payload': pezzo});
          }
        }());
        break;

      case 'fs_search_cancel':
        _ricerca.ferma('${msg['id'] ?? client.hashCode}');
        break;

      // ── La galleria ────────────────────────────────────────────────
      //
      // Le fotografie arrivano a mazzetti mentre si scansiona, come la
      // ricerca qui sopra e per lo stesso motivo: la prima scansione di una
      // libreria vera costa qualche secondo — quasi tutto `ffprobe` sui
      // video — e chi apre la galleria deve vedere qualcosa subito.
      case 'foto_cartelle':
        client.send({'event': 'foto_cartelle', 'payload': _foto.vediCartelle()});
        break;

      // A parte, perché costa: cercare dove sono le fotografie vuol dire
      // camminare per la casa. Non si paga a ogni apertura.
      case 'foto_proposte':
        client.send({'event': 'foto_proposte', 'payload': _foto.proposte()});
        break;

      case 'foto_cartella_aggiungi':
        client.send({
          'event': 'foto_cartelle',
          'payload': _foto.aggiungiCartella(msg['percorso'] as String?),
        });
        break;

      case 'foto_cartella_togli':
        client.send({
          'event': 'foto_cartelle',
          'payload': _foto.togliCartella(msg['percorso'] as String?),
        });
        break;

      case 'foto_escludi':
        client.send({
          'event': 'foto_cartelle',
          'payload':
              _foto.escludi(msg['percorso'] as String?, msg['si'] == true),
        });
        break;

      case 'foto_schermate':
        client.send({
          'event': 'foto_cartelle',
          'payload': _foto.schermate(msg['si'] == true),
        });
        break;

      case 'foto_scansiona':
        {
          final id = '${msg['id'] ?? client.hashCode}';
          unawaited(() async {
            await for (final pezzo in _foto.scansiona(id)) {
              client.send({'event': 'foto_scansione', 'payload': pezzo});
            }
          }());
        }
        break;

      case 'foto_scansiona_ferma':
        _foto.fermaScansione('${msg['id'] ?? client.hashCode}');
        break;

      case 'foto_panoramica':
        client.send({'event': 'foto_panoramica', 'payload': _foto.panoramica()});
        break;
      // Butta le copie in più di UN gruppo. Passa dai rifiuti di
      // `scartoDoppioni` — che rendono «butta tutte le copie» una cosa non
      // esprimibile — e poi dal cestino, che è recuperabile.
      case 'foto_doppioni_scarta':
        {
          final via = _foto.scartoDoppioni(
            msg['tieni'] as String?,
            (msg['butta'] as List?)?.cast<String>(),
          );
          if (via['ok'] != true) {
            client.send({'event': 'foto_doppioni_scarta', 'payload': via});
            break;
          }
          final r = await _fileService.trash((via['butta'] as List).cast<String>());
          client.send({
            'event': 'foto_doppioni_scarta',
            'payload': {...r, 'tenuta': via['tieni']},
          });
        }
        break;

      case 'foto_doppioni':
        // Costa: legge i file. Ma solo quelli che hanno un gemello per
        // dimensione, e di quelli solo 128 KB a testa finché non serve
        // altro. Sulle 525 fotografie di questa macchina sono pochi secondi.
        client.send({
          'event': 'foto_doppioni',
          'payload': await _foto.doppioni(),
        });
        break;

      case 'foto_giorno':
        client.send({
          'event': 'foto_giorno',
          'payload': _foto.giorno(msg['giorno'] as String?),
        });
        break;

      // La risposta porta un PERCORSO, non dei byte: una miniatura in base64
      // sul bus sarebbe un megabyte per schermata di griglia.
      case 'foto_miniatura':
        {
          final lato = (msg['lato'] as num?)?.toInt() ?? 256;
          final r =
              await _foto.miniaturaDi(msg['percorso'] as String?, lato);
          client.send({
            'event': 'foto_miniatura',
            'payload': {...r, 'percorsoFoto': msg['percorso']},
          });
        }
        break;

      // ── Lo sfondo già sfocato ───────────────────────────────────────
      //
      // Come `foto_miniatura`: la risposta porta un PERCORSO, non dei byte.
      // E come quella, il conto si paga una volta sola — qui addirittura una
      // volta per sfondo, non una per finestra.
      case 'sfondo_sfocato':
        {
          final r = await _vetro.per(msg['percorso'] as String?);
          client.send({
            'event': 'sfondo_sfocato',
            'payload': {...r, 'sfondo': msg['percorso']},
          });
        }
        break;

      case 'foto_preferito':
        client.send({
          'event': 'foto_preferito',
          'payload': {
            ..._foto.preferito(msg['percorso'] as String?, msg['si'] == true),
            'percorsoFoto': msg['percorso'],
          },
        });
        break;

      case 'windows_follow':
        _finestre.segui(msg['vicino'] == true);
        break;

      // ── Controllo finestre (menu contestuali della shell) ──────────

      // Rilegge i file `.desktop` da zero. Serve quando ne compare uno
      // nuovo mentre la sessione è in corso — l'installazione di un
      // programma, o le applicazioni di Minerva stessa che si registrano —
      // e senza, l'elenco resterebbe quello letto all'avvio del demone.
      // ── Lo stato dell'apparecchio ──────────────────────────────
      //
      // I comandi passano dal demone e non dalla finestra che li ha
      // chiesti. Non è un giro più lungo: è l'unico che funziona. Una
      // finestra che spegne il Bluetooth per conto suo non ha modo di
      // avvisare le altre — non sa nemmeno che esistono — e per dodici
      // secondi la barra continuava a mostrarlo acceso.
      case 'system_action':
        final cosa = msg['what'];
        final valore = msg['value'];
        switch (cosa) {
          case 'bluetooth':
            await _systemState.setBluetooth(valore == true);
            break;
          case 'wifi':
            await _systemState.setWifi(valore == true);
            break;
          case 'brightness':
            if (valore is num) {
              await _systemState.setBrightness(valore.round());
            }
            break;
          case 'refresh':
            await _systemState.leggi();
            break;
        }
        client.send({'event': 'system_state', 'payload': _systemState.state});
        break;

      case 'rescan_apps':
        await _appScanner.scan();
        // I candidati di ogni categoria vengono dall'elenco delle
        // applicazioni: rileggerlo e tenersi le categorie di prima vorrebbe
        // dire non vedere mai un programma appena installato.
        _categorieRicordate.dimentica();
        _aTutti({'event': 'all_apps', 'payload': _allAppsPayload});
        break;

      case 'app_seen':
        final idVista = msg['id'];
        if (idVista is String && await _appScanner.novita.vista(idVista)) {
          _aTutti({'event': 'all_apps', 'payload': _allAppsPayload});
        }
        break;

      case 'get_all_apps':
        client.send({
          'event': 'all_apps',
          'payload': _allAppsPayload,
        });
        break;

      // ── Gestore file ──────────────────────────────────────────────────
      case 'fs_list':
        {
          final path = msg['path'];
          final showHidden = msg['showHidden'] == true;
          if (path is String && path.isNotEmpty) {
            final result =
                await _fileService.list(path, showHidden: showHidden);
            await _vestiILauncher(result['entries']);
            result['pane'] = msg['pane'] ?? '';
            client.send({'event': 'fs_listing', 'payload': result});
          }
        }
        break;

      case 'fs_transfer':
        {
          final sources = (msg['sources'] as List?)?.cast<String>() ?? [];
          final destination = msg['destination'];
          if (sources.isNotEmpty && destination is String) {
            await _fileService.startTransfer(
              sources: sources,
              destination: destination,
              move: msg['move'] == true,
              conflitto: msg['conflitto'] is String
                  ? msg['conflitto'] as String
                  : 'entrambi',
            );
          }
        }
        break;

      case 'fs_pause':
        if (msg['id'] is String) _fileService.pause(msg['id']);
        break;

      case 'fs_resume':
        if (msg['id'] is String) _fileService.resume(msg['id']);
        break;

      case 'fs_cancel':
        if (msg['id'] is String) _fileService.cancel(msg['id']);
        break;

      case 'fs_jobs':
        client.send({'event': 'fs_jobs', 'payload': _fileService.jobsJson()});
        break;

      case 'fs_mkdir':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final r = await _fileService.makeDirectory(path);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_aspetto':
        {
          final path = msg['path'];
          final a = msg['aspetto'];
          if (path is String && path.isNotEmpty) {
            final r = await _fileService.impostaAspetto(
                path, a is Map ? Map<String, dynamic>.from(a) : null);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_touch':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final r = await _fileService.creaFile(path);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_delete':
        {
          final paths = (msg['paths'] as List?)?.cast<String>() ?? [];
          if (paths.isNotEmpty) {
            final r = await _fileService.eliminaDefinitivamente(paths);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_rename':
        {
          final from = msg['from'];
          final to = msg['to'];
          if (from is String && to is String) {
            final r = await _fileService.rename(from, to);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_trash':
        {
          final paths = (msg['paths'] as List?)?.cast<String>() ?? [];
          if (paths.isNotEmpty) {
            final r = await _fileService.trash(paths);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      // ── Programmi all'avvio ───────────────────────────────────────────
      //
      // Ogni comando che cambia qualcosa rimanda SUBITO l'elenco nuovo, e
      // non solo un «fatto»: la pagina si ridisegna dallo stato vero letto
      // da disco invece che dalla propria idea di cosa è appena successo.
      // Le due cose divergono al primo errore.
      // ── Il tempo che fa ───────────────────────────────────────────
      case 'weather_search':
        {
          final q = '${msg['query'] ?? ''}';
          client.send({
            'event': 'weather_places',
            'payload': {'luoghi': await _meteo.cerca(q)},
          });
        }
        break;

      case 'weather_state':
        {
          // Senza coordinate non si chiede niente a nessuno: è la garanzia
          // che finché l'utente non sceglie una località questo computer
          // non parla con l'esterno.
          final lat = (msg['lat'] as num?)?.toDouble();
          final lon = (msg['lon'] as num?)?.toDouble();
          if (lat == null || lon == null) {
            client.send({'event': 'weather', 'payload': {'spento': true}});
            break;
          }
          client.send({
            'event': 'weather',
            'payload': await _meteo.previsioni(lat, lon,
                forza: msg['force'] == true),
          });
        }
        break;

      // ── Lingua del sistema ────────────────────────────────────────
      //
      // La lingua di MINERVA non passa di qui: è un'impostazione del demone
      // come le altre (`general.language`) e la cambia `set_setting`. Qui
      // c'è solo quella di systemd, che vale per tutti i programmi.
      case 'locale_state':
        client.send({
          'event': 'locale_state',
          'payload': await _lingua.stato(),
        });
        break;

      case 'locale_set':
        {
          final r = await _lingua.impostaLocale('${msg['value'] ?? ''}');
          client.send({'event': 'locale_result', 'payload': r});
          client.send({
            'event': 'locale_state',
            'payload': await _lingua.stato(),
          });
        }
        break;

      // ── Data e ora ────────────────────────────────────────────────
      //
      // Stesso patto dell'autostart: chi cambia qualcosa si riprende lo
      // stato vero subito dopo, invece di dare per buono che sia andata.
      // Qui conta il doppio — la richiesta passa da polkit, e l'utente può
      // benissimo premere «Annulla» nella finestrella della password.
      case 'datetime_state':
        client.send({
          'event': 'datetime_state',
          'payload': await _dataOra.stato(),
        });
        break;

      case 'datetime_zones':
        client.send({
          'event': 'datetime_zones',
          'payload': {'fusi': await _dataOra.fusi()},
        });
        break;

      case 'datetime_set':
        {
          Map<String, dynamic> r;
          final campo = '${msg['field'] ?? ''}';
          switch (campo) {
            case 'timezone':
              r = await _dataOra.impostaFuso('${msg['value'] ?? ''}');
              break;
            case 'ntp':
              r = await _dataOra.impostaNtp(msg['value'] == true);
              break;
            case 'time':
              r = await _dataOra.impostaOra('${msg['value'] ?? ''}');
              break;
            default:
              r = {'ok': false, 'errore': 'Campo sconosciuto: "$campo"'};
          }
          client.send({'event': 'datetime_result', 'payload': r});
          client.send({
            'event': 'datetime_state',
            'payload': await _dataOra.stato(),
          });
        }
        break;

      case 'autostart_list':
        client.send({
          'event': 'autostart_list',
          'payload': {'voci': await _avvio.elenco()},
        });
        break;

      case 'autostart_set':
      case 'autostart_add':
      case 'autostart_remove':
        {
          Map<String, dynamic> r;
          if (action == 'autostart_set') {
            final f = msg['file'];
            r = f is String && f.isNotEmpty
                ? await _avvio.imposta(f, msg['enabled'] == true)
                : {'ok': false, 'error': 'Manca il file.'};
          } else if (action == 'autostart_add') {
            r = await _avvio.aggiungi(
                '${msg['name'] ?? ''}', '${msg['command'] ?? ''}');
          } else {
            final f = msg['file'];
            r = f is String && f.isNotEmpty
                ? await _avvio.togli(f)
                : {'ok': false, 'error': 'Manca il file.'};
          }
          client.send({'event': 'fs_result', 'payload': r});
          client.send({
            'event': 'autostart_list',
            'payload': {'voci': await _avvio.elenco()},
          });
        }
        break;

      // ── Formattare un disco ───────────────────────────────────────────
      case 'fs_conflitti':
        {
          final sources = (msg['sources'] as List?)?.cast<String>() ?? [];
          final destination = msg['destination'];
          client.send({
            'event': 'fs_conflitti',
            'payload': {
              'nomi': destination is String
                  ? _fileService.conflitti(sources, destination)
                  : <String>[],
            },
          });
        }
        break;

      case 'fs_formats':
        client.send({
          'event': 'fs_formats',
          'payload': await _formatiRicordati
              .chiedi(_fileService.formatiDisponibili),
        });
        break;

      // ── I caratteri installati ───────────────────────────────────────
      //
      // L'editor li chiede per il suo menù. `fc-list` è il catalogo del
      // sistema, e nessun file di impostazioni lo sostituisce: un elenco
      // scritto a mano dimenticherebbe il carattere che l'utente ha
      // appena installato.
      case 'font_list':
        {
          try {
            final famiglie = await _fontRicordati.chiedi(() async {
              final esito = await Process.run('fc-list', [':', 'family']);
              final visti = <String>{};
              final trovate = <String>[];
              for (final riga in esito.stdout.toString().split('\n')) {
                for (final pezzo in riga.split(',')) {
                  final nome = pezzo.trim();
                  if (nome.isNotEmpty && visti.add(nome)) trovate.add(nome);
                }
              }
              trovate.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              return trovate;
            });
            client.send({
              'event': 'fonts_list',
              'payload': {'fonts': famiglie},
            });
          } catch (e) {
            client.send({
              'event': 'fonts_list',
              'payload': {'fonts': <String>[]},
            });
          }
        }
        break;

      case 'fs_format':
        {
          final device = msg['device'];
          final fs = msg['fs'];
          if (device is String && device.isNotEmpty &&
              fs is String && fs.isNotEmpty) {
            final r = await _fileService.formatVolume(
                device, fs, '${msg['label'] ?? ''}');
            client.send({'event': 'fs_result', 'payload': r});
            // L'elenco dei dischi cambia: etichetta nuova, tipo nuovo, e
            // il punto di montaggio non è più quello di prima.
            client.send({
              'event': 'fs_volumes',
              'payload': await _fileService.volumes(),
            });
          }
        }
        break;

      // ── Cestino ───────────────────────────────────────────────────────
      case 'fs_trash_restore':
        {
          final paths = (msg['paths'] as List?)?.cast<String>() ?? [];
          if (paths.isNotEmpty) {
            final r = await _fileService.restoreFromTrash(paths);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_trash_empty':
        {
          final r = await _fileService.emptyTrash();
          client.send({'event': 'fs_result', 'payload': r});
        }
        break;

      // ── Archivi ───────────────────────────────────────────────────────
      //
      // Rispondono con `fs_result` come le altre operazioni, ma con due
      // campi in più (`percorso`, `cartella`): il gestore file ci porta
      // dentro chi ha estratto, invece di lasciarlo a cercare dove sia
      // finita la roba.
      case 'fs_compress':
        {
          final paths = (msg['paths'] as List?)?.cast<String>() ?? [];
          if (paths.isNotEmpty) {
            final r = await _archivi.comprimi(
              paths,
              formato: msg['format'] is String ? msg['format'] : 'zip',
              nome: msg['name'] is String && (msg['name'] as String).isNotEmpty
                  ? msg['name']
                  : null,
            );
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_extract':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final r = await _archivi.estrai(path);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      // ── Condividere ───────────────────────────────────────────────────
      //
      // Due richieste, e la prima è la più importante: `condivisione_dove`
      // torna TUTTE le destinazioni, comprese quelle che adesso non
      // funzionano, ognuna col suo motivo scritto. Una voce che sparisce
      // lascia chi la cercava a chiedersi se l'ha sognata; una voce spenta
      // che dice «il Bluetooth è spento» si risolve da sola in tre secondi.
      //
      // Rispondono con un evento loro e non con `fs_result` perché non sono
      // operazioni sul disco: nessuna cartella da ricaricare, nessun file
      // nuovo da mostrare. Il gestore file le tiene in un pannello a parte.
      case 'condivisione_dove':
        {
          final r = await _condivisione.destinazioni();
          client.send({'event': 'condivisione_dove', 'payload': r});
        }
        break;

      // Il Bluetooth può metterci decine di secondi: `CreateSession` aspetta
      // che il telefono in tasca risponda. Non è un problema perché ogni
      // messaggio è servito per conto suo (`_handleClientMessage` non viene
      // atteso da nessuno), quindi la shell continua a essere servita mentre
      // questo aspetta.
      // ── Accoppiare un telefono ────────────────────────────────────────
      //
      // Tre azioni e non una, perché in mezzo c'è una PERSONA: BlueZ mostra
      // un codice a sei cifre, il telefono ne mostra un altro, e qualcuno
      // deve dire se sono uguali. Il difetto che questo chiude è vecchio di
      // un mese ed era già scritto in `minerva-bluetooth`: con
      // `agent NoInputNoOutput` un telefono non si accoppia e basta.
      // ── Installare un set di icone ────────────────────────────────────
      //
      // Vale per le ICONE e non per i temi di colore, e la differenza non è
      // un capriccio: i temi di icone sono già file di uno standard che non
      // abbiamo inventato noi, mentre i colori di Minerva vivono dentro
      // `theme/Colors.qml`, che è codice. Vedi `tema_icone_service.dart`.
      case 'icone_installa':
        {
          final da = msg['path'];
          final r = da is String && da.isNotEmpty
              ? await _temiIcone.installa(da, Platform.environment['HOME'] ?? '')
              : {'ok': false, 'error': 'Non hai detto quale file.'};
          client.send({'event': 'icone_esito', 'payload': r});
        }
        break;

      case 'icone_disinstalla':
        {
          final dove = msg['path'];
          final r = dove is String && dove.isNotEmpty
              ? await _temiIcone.disinstalla(dove, Platform.environment['HOME'] ?? '')
              : {'ok': false, 'error': 'Non hai detto quale tema.'};
          client.send({'event': 'icone_esito', 'payload': r});
        }
        break;

      case 'bt_pair':
        {
          _ascoltaAccoppiamento();
          final mac = msg['mac'];
          final r = mac is String && mac.isNotEmpty
              ? await _accoppiamento.accoppia(mac)
              : {'ok': false, 'error': 'Non hai detto quale dispositivo.'};
          client.send({'event': 'bt_pair_result', 'payload': r});
        }
        break;

      case 'bt_pair_answer':
        {
          final r = await _accoppiamento.rispondi(msg['si'] == true);
          client.send({'event': 'bt_pair_result', 'payload': r});
        }
        break;

      case 'bt_pair_cancel':
        {
          final r = await _accoppiamento.annulla();
          client.send({'event': 'bt_pair_result', 'payload': r});
        }
        break;

      case 'condivisione_invia':
        {
          final dove = msg['dove'];
          final file = (msg['paths'] as List?)?.cast<String>() ?? [];
          final r = dove is String && dove.isNotEmpty
              ? await _condivisione.invia(
                  dove,
                  file,
                  bersaglio: msg['bersaglio'] is String
                      ? msg['bersaglio'] as String
                      : '',
                )
              : {'ok': false, 'error': 'Non hai scelto dove mandarlo.'};
          client.send({'event': 'condivisione_esito', 'payload': r});
        }
        break;

      // ── Minerva Suono ─────────────────────────────────────────────────
      //
      // Tre richieste e nessun abbonamento: il lettore chiede quando apre un
      // file e quando salva un pezzo, e fra un gesto e l'altro non arriva
      // niente. Non c'è nulla da seguire nel tempo — la posizione della
      // riproduzione la conosce la finestra, che è quella che suona.
      //
      // `client.send` e non un evento a tutti: due finestre di Suono aperte
      // su due canzoni diverse riceverebbero l'onda l'una dell'altra.
      // ── L'audio di sistema: uscite, ingressi, profili delle schede ────
      //
      // Una sorgente sola (`system_audio_service.dart`, `pactl` in JSON) per
      // la pagina Audio. Lo stato si CHIEDE; i cambiamenti (cuffie inserite,
      // HDMI collegato) arrivano da soli a chi si è iscritto con
      // `subscribe_audio` — come `subscribe_machine`: il `pactl subscribe`
      // parte alla prima iscrizione, e chi non guarda la pagina non riceve
      // niente. I due nomi degli eventi sono scritti per esteso, non
      // calcolati: `bus_coerenza_test` deve poterli leggere.
      case 'system_audio_state':
        await _systemAudio.start();
        client.send({'event': 'system_audio_state',
            'payload': await _systemAudio.status()});
        break;
      case 'system_audio_select':
        await _systemAudio.start();
        client.send({'event': 'system_audio_select',
            'payload': await _systemAudio.select(msg)});
        break;
      case 'subscribe_audio':
        _systemAudioSub ??= _systemAudio.changes.stream.listen((state) {
          _aTutti({'event': 'system_audio_state', 'payload': state},
              solo: (c) => c.isSubscribed('system_audio_state'));
        });
        await _systemAudio.start();
        if (!client.subscribedEvents.contains('system_audio_state')) {
          client.subscribedEvents =
              [...client.subscribedEvents, 'system_audio_state'];
        }
        break;
      case 'unsubscribe_audio':
        client.subscribedEvents = client.subscribedEvents
            .where((e) => e != 'system_audio_state')
            .toList();
        break;
      case 'audio_info':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            client.send({
              'event': 'audio_info',
              'payload': await _audio.info(path),
            });
          }
        }
        break;

      case 'audio_onda':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final barre = msg['barre'] is num
                ? (msg['barre'] as num).toInt()
                : 1200;
            client.send({
              'event': 'audio_onda',
              'payload': await _audio.onda(path, barre: barre),
            });
          }
        }
        break;

      case 'audio_taglia':
        {
          final sorgente = msg['sorgente'];
          final destinazione = msg['destinazione'];
          if (sorgente is String &&
              sorgente.isNotEmpty &&
              destinazione is String &&
              destinazione.isNotEmpty) {
            final r = await _audio.taglia(
              sorgente: sorgente,
              destinazione: destinazione,
              inizio: (msg['inizio'] as num?)?.toDouble() ?? 0,
              fine: (msg['fine'] as num?)?.toDouble() ?? 0,
              formato: msg['formato'] is String ? msg['formato'] : 'mp3',
              dissolvenzaIn:
                  (msg['dissolvenzaIn'] as num?)?.toDouble() ?? 0,
              dissolvenzaOut:
                  (msg['dissolvenzaOut'] as num?)?.toDouble() ?? 0,
              normalizza: msg['normalizza'] == true,
            );
            client.send({'event': 'audio_result', 'payload': r});
          }
        }
        break;

      case 'audio_formati':
        {
          client.send({
            'event': 'audio_formati',
            'payload': {'formati': AudioService.formati},
          });
        }
        break;

      // ── Proprietà di un file ──────────────────────────────────────────
      // ── Leggere e scrivere un documento ───────────────────────────────
      //
      // L'editor di testi legge e salva da qui, come ogni altra cosa che
      // tocca il disco in Minerva. La lettura ha un tetto: un documento
      // più grande non è testo, e spedirlo intero sul canale
      // bloccherebbe tutto il resto per niente.
      case 'fs_read':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            try {
              final file = File(path);
              final info = await file.stat();
              if (info.size > 8 * 1024 * 1024) {
                client.send({
                  'event': 'fs_text',
                  'payload': {
                    'ok': false,
                    'path': path,
                    'error': 'Il file è più grande di 8 MB: non è testo.',
                  },
                });
              } else {
                client.send({
                  'event': 'fs_text',
                  'payload': {
                    'ok': true,
                    'path': path,
                    'text': await file.readAsString(),
                  },
                });
              }
            } catch (e) {
              client.send({
                'event': 'fs_text',
                'payload': {'ok': false, 'path': path, 'error': '$e'},
              });
            }
          }
        }
        break;
      case 'fs_write':
        {
          final path = msg['path'];
          final text = msg['text'];
          if (path is String && path.isNotEmpty && text is String) {
            try {
              // Prima in un file temporaneo e poi sopra il vero: una
              // scrittura interrotta a metà non deve lasciare il documento
              // troncato.
              final temporaneo = File('$path.minerva.tmp');
              await temporaneo.writeAsString(text, flush: true);
              await temporaneo.rename(path);
              client.send({
                'event': 'fs_result',
                'payload': {'ok': true, 'path': path},
              });
            } catch (e) {
              client.send({
                'event': 'fs_result',
                'payload': {'ok': false, 'path': path, 'error': '$e'},
              });
            }
          }
        }
        break;

      // ── Proprietà di un file ──────────────────────────────────────────
      case 'fs_info':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final r = await _fileService.info(path);
            // Il tipo e chi lo apre viaggiano insieme ai dettagli: la
            // finestra «Proprietà» li mostra nella stessa schermata, e due
            // risposte separate vorrebbero dire disegnarla due volte.
            final m = await _mime.describe(path);
            r['mime'] = m['mime'];
            r['defaultApp'] = m['defaultApp'];
            r['candidates'] = _withIcons(m['candidates'] as List);
            client.send({'event': 'fs_info', 'payload': r});
          }
        }
        break;

      case 'fs_measure':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final r = await _fileService.measure(path);
            client.send({'event': 'fs_measure', 'payload': r});
          }
        }
        break;

      case 'fs_chmod':
        {
          final path = msg['path'];
          final mode = msg['mode'];
          if (path is String && mode is String) {
            final r = await _fileService.chmod(path, mode,
                recursive: msg['recursive'] == true);
            client.send({'event': 'fs_result', 'payload': r});
          }
        }
        break;

      case 'fs_places':
        client.send({
          'event': 'fs_places',
          'payload': await _fileService.places(),
        });
        break;

      // ── Dischi ────────────────────────────────────────────────────────
      case 'fs_volumes':
        client.send({
          'event': 'fs_volumes',
          'payload': await _fileService.volumes(),
        });
        break;

      case 'fs_mount':
      case 'fs_unmount':
        {
          final device = msg['device'];
          if (device is String && device.isNotEmpty) {
            final r = action == 'fs_mount'
                ? await _fileService.mountVolume(device)
                : await _fileService.unmountVolume(device);
            client.send({'event': 'fs_result', 'payload': r});
            // Dopo un monte o uno smonte l'elenco è cambiato: si rimanda
            // subito, così la barra laterale non resta a mostrare uno
            // stato che non esiste più.
            client.send({
              'event': 'fs_volumes',
              'payload': await _fileService.volumes(),
            });
          }
        }
        break;

      // ── La schermata di accesso ───────────────────────────────────────
      //
      // Perché il dialogo con greetd passa di qui invece di stare nella
      // shell: il protocollo inquadra ogni messaggio con quattro byte di
      // lunghezza in ordine nativo, e l'unico analizzatore di socket che
      // Quickshell 0.3 offre taglia su un delimitatore. Vedi
      // `services/greetd_service.dart`.

      /// Cosa mostrare prima di chiedere qualunque cosa: chi c'è e in cosa
      /// può entrare. Si risponde anche quando greetd non c'è — così la
      /// schermata si può disegnare e provare in una sessione normale.
      case 'greeter_info':
        client.send({
          'event': 'greeter_info',
          'payload': {
            'sessioni': (await _accesso.sessioni()).map((s) => s.toJson()).toList(),
            'utenti': (await _accesso.utenti()).map((u) => u.toJson()).toList(),
            'greetd': GreetdService.percorsoSocket != null,
            // Se c'è, la sessione si avvia attraverso di lui e lascia
            // scritto com'è andata. Lo dice il demone e non lo cerca la
            // schermata perché qui è una riga sola e si prova con
            // `dart test`; là sarebbe un `FileView` che legge un eseguibile
            // per sapere soltanto se esiste.
            'avviatore': await AccessoService.avviatoreDisponibile(),
          },
        });
        break;

      // ── Chi ti apre la porta all'accensione ───────────────────────────
      //
      // L'elenco dei gestori di accessi installati, e quale è acceso. Lo
      // legge il pannello Accesso. Il demone non ne accende nessuno: quello
      // richiede root e lo fa `minerva-greetd gestore`, dietro `pkexec`.
      // Qui si guarda soltanto.
      // ── La modalità amministratore del gestore file ───────────────────
      //
      // Il demone non ha nessun privilegio: chiama `pkexec` su un aiutante
      // installato, e chi decide se si può è polkit — che chiede la password
      // di un amministratore. Vedi `services/radice_service.dart`, e
      // `scripts/minerva-radice` per il perché non è una finestra da root.
      // ── La Custodia ────────────────────────────────────────────
      //
      // Una porta per ogni verbo, e non una porta sola con dentro un nome di
      // operazione: l'elenco di quello che si può chiedere deve leggersi qui
      // in venti righe. È la stessa ragione per cui `RadiceService.operazioni`
      // è un insieme chiuso.
      //
      // Tutte le risposte hanno la stessa forma — `{ok, errore?}` — perché
      // chi le legge dalla shell non deve interpretare un codice, e perché
      // quando `ok` è falso c'è **sempre** una frase in italiano da mostrare.

      case 'custodia_panoramica':
        await _custodia.init();
        client.send({
          'event': 'custodia_panoramica',
          'payload': {
            'ok': true,
            'progetti': await _custodia.panoramica(),
            'proposte': _custodia.proposte(),
          },
        });
        break;

      case 'custodia_dettaglio':
        {
          final p = msg['percorso'];
          client.send({
            'event': 'custodia_dettaglio',
            'payload': p is String && p.isNotEmpty
                ? await _custodia.dettaglio(p)
                : {'ok': false, 'errore': 'Nessun progetto.'},
          });
        }
        break;

      case 'custodia_aggiungi':
        {
          final p = msg['percorso'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && p.isNotEmpty
                ? await _custodia.aggiungi(p,
                    nome: msg['nome'] as String?,
                    motore: msg['motore'] as String?)
                : {'ok': false, 'errore': 'Nessuna cartella.'},
          });
        }
        break;

      case 'custodia_togli':
        {
          final p = msg['percorso'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && p.isNotEmpty
                ? await _custodia.togli(p)
                : {'ok': false, 'errore': 'Nessun progetto.'},
          });
        }
        break;

      case 'custodia_punto':
        {
          final p = msg['percorso'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && p.isNotEmpty
                ? await _custodia.prendiPunto(p,
                    nota: '${msg['nota'] ?? ''}')
                : {'ok': false, 'errore': 'Nessun progetto.'},
          });
        }
        break;

      case 'custodia_salva':
        {
          final p = msg['percorso'];
          final m = msg['messaggio'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && p.isNotEmpty && m is String
                ? await _custodia.salva(p, m, forza: msg['forza'] == true)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'custodia_firma':
        {
          final p = msg['percorso'];
          final n = msg['nome'];
          final e = msg['email'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && n is String && e is String
                ? await _custodia.firmaAMano(p, n, e)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'custodia_inizia':
        {
          final p = msg['percorso'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && p.isNotEmpty
                ? await _custodia.iniziaStoria(p)
                : {'ok': false, 'errore': 'Nessun progetto.'},
          });
        }
        break;

      // I due «torna indietro». Sono separati e non uniti sotto un solo verbo
      // apposta: sono due cose diverse — un salvataggio riporta i file che
      // git conosce, un punto di ritorno riporta la cartella intera — e
      // confonderle è esattamente l'equivoco che questo programma deve
      // togliere di mezzo.

      // Le destinazioni: dove un progetto va al sicuro fuori di qui.
      case 'custodia_destinazione_aggiungi':
        {
          final p = msg['percorso'];
          final t = msg['tipo'];
          final d = msg['dove'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && t is String && d is String
                ? await _custodia.aggiungiDestinazione(
                    p, t, '${msg['nome'] ?? ''}', d)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'custodia_destinazione_togli':
        {
          final p = msg['percorso'];
          final d = msg['dove'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && d is String
                ? await _custodia.togliDestinazione(p, d)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'custodia_manda':
        {
          final p = msg['percorso'];
          final d = msg['dove'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && d is String
                ? await _custodia.manda(p, d)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'custodia_torna_salvataggio':
        {
          final p = msg['percorso'];
          final id = msg['id'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && id is String
                ? await _custodia.tornaASalvataggio(p, id)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'custodia_torna_punto':
        {
          final p = msg['percorso'];
          final id = msg['id'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && id is String
                ? await _custodia.tornaAPunto(p, id)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      // ── GitHub ──────────────────────────────────────────────────
      //
      // Il gettone entra da qui e non esce mai più: nessuna di queste
      // risposte lo contiene, nemmeno accorciato. Chi vuole sapere se c'è
      // chiede `custodia_github_chi`, che risponde col nome dell'account.

      case 'custodia_github_gettone':
        {
          final g = msg['gettone'];
          client.send({
            'event': 'custodia_github',
            'payload': g is String
                ? await _custodia.gettoneGitHub(g)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      // ── Entrare senza incollare niente ──────────────────────────────
      //
      // Due verbi e non uno: il primo torna SUBITO col codice da mostrare, il
      // secondo può restare in attesa per minuti mentre l'utente conferma sul
      // sito. Uno solo vorrebbe dire una finestra ferma e muta per tutto quel
      // tempo, che è indistinguibile da una rotta.
      // ── L'inventario di Minerva Manutenzione ────────────────────────
      //
      // Lento di suo — su questa macchina `du` deve percorrere dieci gigabyte
      // di cache — e per questo NON si ricorda: un inventario vecchio di
      // mezz'ora dice il falso proprio su quello che uno ha appena pulito.
      // Chi lo chiede sa di aspettare qualche secondo.
      case 'manutenzione_inventario':
        final inventario = await _perChiGuarda(client).tutto();
        // Il totale di sempre viaggia con l'inventario invece di avere un
        // giro suo: sono due cose che si guardano insieme, e una richiesta in
        // meno è un modo in meno di vederle disallineate.
        inventario['recuperato'] = await _quaderno.leggi();
        client.send({
          'event': 'manutenzione_inventario',
          'payload': inventario,
        });
        break;

      // ── Togliere, e solo quello che è stato mostrato ────────────────────
      //
      // Arrivano **identificativi**, mai percorsi: i percorsi li ricava il
      // pulitore rifacendo l'inventario un istante prima di cancellare. Un
      // verbo `pulisci <percorso>` sarebbe la stessa riga con dentro un buco.
      //
      // Vale per la roba tua e basta — cache, cestino, temporanei. Quello che
      // sta fuori dalla tua cartella lo lascia dov'è e lo dice: passerà
      // dall'aiutante di root, che ha un elenco chiuso di verbi.
      case 'manutenzione_pulisci':
        final quali = (msg['ids'] as List?)?.cast<String>() ?? const <String>[];
        final esitoPulizia = await Pulitore(
            // Quello che sta fuori dalla tua cartella passa dall'aiutante di
            // root, che ha un elenco chiuso di verbi. Il pulitore non sa
            // nemmeno cosa sia `pkexec`: gli arriva una funzione.
            radice: _radice.chiedi,
            racconta: (fase, testo, fatte, quante) => client.send({
              'event': 'manutenzione_passo',
              'payload': {
                'fase': fase,
                'testo': testo,
                'fatte': fatte,
                'quante': quante,
              },
            }),
          ).pulisci(quali);
        // Nel quaderno ci vanno i byte USCITI, non quelli promessi: è la
        // bugia più facile da dire qui dentro, perché nessuno può
        // controllarla.
        esitoPulizia['recuperato'] =
            await _quaderno.segna((esitoPulizia['liberati'] as int?) ?? 0);
        client.send({
          'event': 'manutenzione_pulito',
          'payload': esitoPulizia,
        });
        break;

      // ── I file che ci sono due volte ───────────────────────────────────
      //
      // Il motore è quello delle fotografie (`foto/doppioni.dart`), che qui
      // gira su TUTTA la cartella di casa: dei 6,94 GB sprecati su questa
      // macchina la parte grossa sono video del telefono copiati tre volte,
      // ma dentro ci sono anche ISO, archivi e librerie. Un secondo algoritmo
      // di doppioni sarebbe un secondo posto dove sbagliarlo.
      case 'manutenzione_doppioni':
        client.send({
          'event': 'manutenzione_doppioni',
          'payload': await Setaccio(
            escluse: await _escluse.leggi(),
            racconta: (fase, testo, fatte, quante) => client.send({
              'event': 'manutenzione_passo',
              'payload': {
                'fase': fase,
                'testo': testo,
                'fatte': fatte,
                'quante': quante,
              },
            }),
          ).doppioni(),
        });
        break;

      // ── E come si tolgono ──────────────────────────────────────────────
      //
      // **Nel cestino, mai cancellati.** Sono file di Giacomo, non cache: la
      // differenza fra «hai liberato sette giga» e «hai perso i video di tuo
      // figlio» è una rete sotto, e il cestino di sistema è già quella rete
      // (`FileService.trash`, che scrive anche il `.trashinfo` per il
      // ripristino).
      //
      // E prima si rifà il giro: `daButtare` ricalcola i gruppi adesso e
      // rifiuta qualunque percorso che lascerebbe un gruppo senza copie.
      case 'manutenzione_doppioni_cestina':
        final quali =
            (msg['percorsi'] as List?)?.cast<String>() ?? const <String>[];
        final vaglio =
            await Setaccio(escluse: await _escluse.leggi()).daButtare(quali);
        if (vaglio['ok'] != true) {
          client.send({
            'event': 'manutenzione_doppioni_tolti',
            'payload': vaglio,
          });
          break;
        }
        final via = (vaglio['via'] as List).cast<String>();
        var liberati = 0;
        for (final p in via) {
          try {
            liberati += await File(p).length();
          } catch (_) {
            // Sparito nel frattempo: non è un errore, è un byte in meno nel
            // conto.
          }
        }
        final esitoCestino = via.isEmpty
            ? {'ok': true, 'cestinati': 0, 'error': ''}
            : await _fileService.trash(via);
        client.send({
          'event': 'manutenzione_doppioni_tolti',
          'payload': {
            'ok': esitoCestino['ok'] == true,
            'cestinati': esitoCestino['cestinati'] ?? 0,
            'rifiutati': vaglio['rifiutati'],
            if ('${esitoCestino['error']}'.isNotEmpty)
              'errore': esitoCestino['error'],
            'recuperato': await _quaderno
                .segna(esitoCestino['ok'] == true ? liberati : 0),
            'liberati': esitoCestino['ok'] == true ? liberati : 0,
          },
        });
        break;

      // ── Le cartelle che non si guardano ────────────────────────────────
      //
      // Percorsi assoluti, e li conserva il demone: sono una preferenza che
      // deve valere anche domani, e la finestra si chiude.
      case 'manutenzione_escluse':
        client.send({
          'event': 'manutenzione_escluse',
          'payload': {'percorsi': await _escluse.leggi()},
        });
        break;

      case 'manutenzione_escludi':
        client.send({
          'event': 'manutenzione_escluse',
          'payload': {
            'percorsi':
                await _escluse.aggiungi('${msg['percorso'] ?? ''}'),
          },
        });
        break;

      case 'manutenzione_includi':
        client.send({
          'event': 'manutenzione_escluse',
          'payload': {
            'percorsi': await _escluse.togli('${msg['percorso'] ?? ''}'),
          },
        });
        break;

      // ── I pacchetti rimasti soli ───────────────────────────────────────
      //
      // Non passano dal pulitore: non si misurano in byte e non stanno
      // nell'elenco delle voci. E l'elenco NON arriva dalla finestra — lo
      // rifà il demone un istante prima, e l'aiutante di root lo ricontrolla
      // ancora: un nome che nel frattempo ha smesso di essere orfano è un
      // pacchetto che serve a qualcosa.
      case 'manutenzione_orfani':
        final soli = await Inventario().orfani();
        if (soli.isEmpty) {
          client.send({
            'event': 'manutenzione_orfani',
            'payload': {'ok': true, 'quanti': 0, 'nomi': <String>[]},
          });
          break;
        }
        final esito = await _radice.chiedi('togli-orfani', soli);
        client.send({
          'event': 'manutenzione_orfani',
          'payload': {
            'ok': esito['ok'] == true,
            'quanti': esito['ok'] == true ? soli.length : 0,
            'nomi': soli,
            if (esito['ok'] != true)
              'errore': esito['annullato'] == true
                  ? 'Hai annullato la richiesta della password.'
                  : '${esito['error'] ?? 'Non ci sono riuscito.'}',
          },
        });
        break;

      case 'custodia_github_accedi':
        client.send({
          'event': 'custodia_github',
          'payload': await _custodia.accediGitHub(),
        });
        break;

      case 'custodia_github_attendi':
        {
          final n = msg['nostro'];
          client.send({
            'event': 'custodia_github',
            'payload': n is String && n.isNotEmpty
                ? await _custodia.attendiGitHub(n,
                    ogni: msg['ogni'] is int ? msg['ogni'] : 5,
                    scadeFra: msg['scadeFra'] is int ? msg['scadeFra'] : 900)
                : {'ok': false, 'errore': 'Manca il codice di questo accesso.'},
          });
        }
        break;

      case 'custodia_github_chi':
        client.send({
          'event': 'custodia_github',
          'payload': await _custodia.chiSeiGitHub(),
        });
        break;

      case 'custodia_github_dimentica':
        client.send({
          'event': 'custodia_github',
          'payload': await _custodia.dimenticaGitHub(),
        });
        break;

      case 'custodia_github_crea':
        {
          final p = msg['percorso'];
          final n = msg['nome'];
          client.send({
            'event': 'custodia_esito',
            'payload': p is String && n is String
                ? await _custodia.creaArchivioGitHub(p, n,
                    privato: msg['privato'] != false)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      // ── Account online ──────────────────────────────────────────
      //
      // La password attraversa `account_collega` una volta sola e in un
      // verso solo: il demone la mette nel portachiavi di sistema e da lì
      // non torna più indietro. Nessuna di queste risposte la contiene.

      case 'account_elenco':
        client.send({
          'event': 'account',
          'payload': await _account.elenco(),
        });
        break;

      case 'account_collega':
        {
          final srv = msg['servizio'];
          final ut = msg['utente'];
          final pw = msg['password'];
          client.send({
            'event': 'account_esito',
            'payload': srv is String && ut is String && pw is String
                ? await _account.collega(
                    servizio: srv,
                    utente: ut,
                    password: pw,
                    url: '${msg['url'] ?? ''}',
                    numeroKdrive: '${msg['numero'] ?? ''}',
                    nome: '${msg['nome'] ?? ''}',
                  )
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      // ── Google ──────────────────────────────────────────────────
      //
      // Qui non passa nessuna password: passa l'indirizzo di una pagina di
      // Google, che la finestra apre nel browser. Il demone non ha uno
      // schermo davanti; la finestra sì. Il permesso torna indietro su una
      // porta di questo computer, non da qui.

      case 'account_google_chiave':
        {
          final i = msg['identificativo'];
          final sg = msg['segreto'];
          client.send({
            'event': 'account_esito',
            'payload': i is String && sg is String
                ? await _account.salvaChiaveGoogle(i, sg)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'account_google_dimentica':
        client.send({
          'event': 'account_esito',
          'payload': await _account.dimenticaChiaveGoogle(),
        });
        break;

      case 'account_google_collega':
        {
          // Questa richiesta può stare aperta dei minuti — il tempo che
          // Giacomo entri in Google e dica di sì. Non blocca niente: il
          // demone continua a rispondere a tutti gli altri mentre aspetta.
          final esito = await _account.collegaGoogle((url) {
            client.send({
              'event': 'account_google_apri',
              'payload': {'url': url},
            });
          });
          client.send({'event': 'account_esito', 'payload': esito});
        }
        break;

      case 'account_scollega':
        {
          final id = msg['id'];
          client.send({
            'event': 'account_esito',
            'payload': id is String
                ? await _account.scollega(id)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      case 'account_guarda':
        {
          final id = msg['id'];
          client.send({
            'event': 'account_dettaglio',
            'payload': id is String
                ? await _account.guarda(id)
                : {'ok': false, 'errore': 'Richiesta incompleta.'},
          });
        }
        break;

      // ── La porta per trasmettere a schermo ────────────────────────
      //
      // Chiede la password una volta sola, e apre UNA porta verso la sola
      // rete di casa. Serve perché un Chromecast non riceve la fotografia:
      // se la va a prendere, e con un firewall acceso non ci arriva — il
      // televisore accetta il comando e poi mostra uno schermo nero, senza
      // che nessuno dica perché.
      // ── Mandare un file a un televisore ───────────────────────────
      //
      // I pezzi c'erano tutti da giorni e non li univa nessuno: il
      // protocollo (`foto/castv2.dart`), il servizio che presta il file
      // (`foto/servizio_effimero.dart`), la scoperta e il permesso del
      // firewall. Nel pannello la levetta aveva il corpo vuoto.
      case 'trasmetti_schermi':
        {
          final t = await _trasmetti.cerca();
          client.send({
            'event': 'trasmetti_schermi',
            'payload': {'schermi': [for (final s in t) s.toJson()]},
          });
        }
        break;

      case 'trasmetti_manda':
        {
          final percorso = msg['file'];
          final id = msg['schermo'];
          if (percorso is! String || percorso.isEmpty) {
            client.send({
              'event': 'trasmetti_esito',
              'payload': {'ok': false, 'error': 'Nessun file da mandare.'},
            });
            break;
          }
          final verso = await _televisoreDetto(id, client);
          if (verso == null) break;
          // ── Il tipo lo decide QUI, non chi chiama ───────────────
          //
          // Fino al 4 settembre 2026 il ripiego era `image/jpeg`, e la shell
          // mandava un tipo indovinato dall'estensione: **un `.mp4` sarebbe
          // partito annunciato come una fotografia**, e il televisore
          // avrebbe mostrato nero senza dire niente.
          //
          // Il demone ha il file e sa guardarci dentro: per immagini, suoni
          // e video `MimeService.detect` non si fida del nome (un
          // `IMG_1234.mp4` che è un JPEG esiste davvero, ce l'ha il
          // telefono). Chi chiama può ancora dire il tipo — serve alle
          // prove — ma non è più obbligato a indovinarlo.
          final detto = msg['tipo'];
          final tipo = detto is String && detto.isNotEmpty
              ? detto
              : await _mime.detect(percorso);
          final r = await _trasmetti.manda(
            file: File(percorso),
            verso: verso,
            tipo: tipo.isEmpty ? 'application/octet-stream' : tipo,
          );
          client.send({'event': 'trasmetti_esito', 'payload': r});
        }
        break;

      // ── Trasmettere lo SCHERMO, non un file ──────────────────────
      //
      // Stessa porta, stesso permesso, stesso canale di `trasmetti_manda`:
      // è `TrasmettiService` a garantire che non vadano insieme.
      case 'trasmetti_schermo':
        {
          final verso = await _televisoreDetto(msg['schermo'], client);
          if (verso == null) break;
          final fps = msg['fps'];
          final schermo = msg['quale'];
          final r = await _trasmetti.specchia(
            verso: verso,
            schermo: schermo is String ? schermo : '',
            fps: fps is int && fps >= 2 && fps <= 60 ? fps : 30,
            cursore: msg['cursore'] != false,
            muto: msg['muto'] == true,
          );
          client.send({'event': 'trasmetti_esito', 'payload': r});
        }
        break;

      case 'trasmetti_ferma':
        await _trasmetti.ferma();
        client.send({
          'event': 'trasmetti_esito',
          'payload': {'ok': true, 'fermato': true},
        });
        break;

      case 'trasmetti_stato':
        client.send({
          'event': 'trasmetti_stato',
          'payload': _trasmetti.stato,
        });
        break;

      case 'trasmetti_permesso':
        {
          final apri = msg['apri'] != false;
          final r = await _radice.chiedi(
              apri ? 'trasmetti-apri' : 'trasmetti-chiudi', const []);
          client.send({'event': 'trasmetti_permesso', 'payload': r});
        }
        break;

      // Chiedere il permesso e basta: la finestrella della password compare
      // quando si ACCENDE la modalità amministratore, non alla prima
      // operazione. Vedi il verbo `permesso` in `scripts/minerva-radice`.
      case 'radice_permesso':
        client.send({
          'event': 'radice_permesso',
          'payload': await _radice.chiedi('permesso', const []),
        });
        break;

      case 'radice_stato':
        client.send({
          'event': 'radice_stato',
          'payload': {'disponibile': await _radice.disponibile()},
        });
        break;

      case 'radice_elenca':
        {
          final p = msg['path'];
          client.send({
            'event': 'radice_elenco',
            'payload': p is String && p.isNotEmpty
                ? await _radice.elenca(p)
                : {'ok': false, 'error': 'Nessuna cartella.'},
          });
        }
        break;

      case 'radice_leggi':
        {
          final p = msg['path'];
          client.send({
            'event': 'radice_testo',
            'payload': p is String && p.isNotEmpty
                ? await _radice.leggi(p)
                : {'ok': false, 'error': 'Nessun file.'},
          });
        }
        break;

      case 'radice_scrivi':
        {
          final p = msg['path'];
          final t = msg['text'];
          client.send({
            'event': 'radice_esito',
            'payload': p is String && p.isNotEmpty && t is String
                ? await _radice.scrivi(p, t)
                : {'ok': false, 'error': 'Nessun file da scrivere.'},
          });
        }
        break;

      // Le operazioni che cambiano la cartella: cancellare, rinominare,
      // creare, copiare, spostare, cambiare i permessi. Una sola porta per
      // tutte, perché l'elenco di quello che si può fare da root deve stare
      // in un posto solo — ed è `RadiceService.operazioni`.
      case 'radice_azione':
        {
          final op = msg['op'];
          final args = (msg['args'] as List?)?.cast<String>() ?? const [];
          if (op is! String || args.isEmpty) {
            client.send({
              'event': 'radice_esito',
              'payload': {'ok': false, 'error': 'Richiesta incompleta.'},
            });
            break;
          }
          final r = await _radice.chiedi(op, args);
          client.send({
            'event': 'radice_esito',
            'payload': {
              'ok': r['ok'],
              'op': op,
              'path': args.first,
              'annullato': r['annullato'] ?? false,
              if (r['error'] != null) 'error': r['error'],
            },
          });
        }
        break;

      case 'gestori_accesso':
        client.send({
          'event': 'gestori_accesso',
          'payload': {
            'gestori':
                (await _gestori.elenco()).map((g) => g.toJson()).toList(),
            'attuale': await _gestori.unitaAttuale(),
          },
        });
        break;

      case 'greeter_create_session':
      case 'greeter_respond':
      case 'greeter_start':
      case 'greeter_cancel':
        await _greetdRichiesta(client, action as String, msg);
        break;

      // ── Chi apre che cosa ─────────────────────────────────────────────
      case 'mime_describe':
        {
          final path = msg['path'];
          if (path is String && path.isNotEmpty) {
            final d = await _mime.describe(path);
            d['candidates'] = _withIcons(d['candidates'] as List);
            client.send({'event': 'mime_described', 'payload': d});
          }
        }
        break;

      case 'mime_defaults':
        {
          // Per il pannello delle applicazioni predefinite: per ogni tipo
          // chiesto, chi lo apre adesso e chi potrebbe.
          final types = (msg['types'] as List?)?.cast<String>() ?? [];
          final out = <Map<String, dynamic>>[];
          for (final t in types) {
            out.add({
              'mime': t,
              'defaultApp': await _mime.defaultFor(t),
              'candidates': _withIcons(await _mime.candidatesFor(t)),
            });
          }
          client.send({'event': 'mime_defaults', 'payload': {'types': out}});
        }
        break;

      case 'mime_categories':
        {
          client.send({
            'event': 'mime_categories',
            'payload': {
                'categories':
                    await _categorieRicordate.chiedi(_mimeCategories),
                'famiglie': MimeService.famiglie,
              },
          });
        }
        break;

      case 'mime_set_category':
        {
          final id = msg['category'];
          final appId = msg['appId'];
          if (id is String && appId is String) {
            final r = await _mime.setCategory(id, appId);
            client.send({'event': 'fs_result', 'payload': r});
            // Il pannello si ridisegna da sé: lo stato che aveva in mano è
            // vecchio di un istante, e un gruppo può averne cambiati altri
            // (scegliere il browser per «pagine web» tocca anche http).
            client.send({
              'event': 'mime_categories',
              'payload': {
                'categories': await _categorieFresche(),
                'famiglie': MimeService.famiglie,
              },
            });
          }
        }
        break;

      case 'mime_set_default':
        {
          final mime = msg['mime'];
          final appId = msg['appId'];
          if (mime is String && appId is String) {
            client.send({
              'event': 'fs_result',
              'payload': await _mime.setDefault(mime, appId),
            });
            // Come per `mime_set_category`: senza questa riga una pagina
            // delle Impostazioni già aperta continuava a mostrare la scelta
            // di prima, e chi guardava concludeva che non fosse successo
            // niente.
            client.send({
              'event': 'mime_categories',
              'payload': {
                'categories': await _categorieFresche(),
                'famiglie': MimeService.famiglie,
              },
            });
          }
        }
        break;

      case 'mime_forget_default':
        {
          final mime = msg['mime'];
          if (mime is String) {
            client.send({
              'event': 'fs_result',
              'payload': await _mime.forgetDefault(mime),
            });
            client.send({
              'event': 'mime_categories',
              'payload': {
                'categories': await _categorieFresche(),
                'famiglie': MimeService.famiglie,
              },
            });
          }
        }
        break;

      case 'open_with':
        {
          final appId = msg['appId'];
          final paths = (msg['paths'] as List?)?.cast<String>() ?? [];
          if (appId is String && paths.isNotEmpty) {
            client.send({
              'event': 'fs_result',
              'payload': await _mime.openWith(appId, paths),
            });
          }
        }
        break;

      case 'open_default':
        {
          // Apre col programma predefinito, e se non ce n'è uno lo dice
          // invece di lanciare `xdg-open` e sperare. È la differenza fra
          // «non c'è un programma per questo tipo» e un doppio clic che
          // non fa niente senza spiegazione.
          final paths = (msg['paths'] as List?)?.cast<String>() ?? [];
          if (paths.isNotEmpty) {
            final mime = await _mime.detect(paths.first);
            final appId = await _mime.defaultFor(mime);
            if (appId.isEmpty) {
              client.send({
                'event': 'fs_result',
                'payload': {
                  'ok': false,
                  'error': 'nessun programma predefinito',
                  'mime': mime,
                  'needsChoice': true,
                  'paths': paths,
                },
              });
            } else {
              client.send({
                'event': 'fs_result',
                'payload': await _mime.openWith(appId, paths),
              });
            }
          }
        }
        break;

      // ── Un'azione che nessuno gestisce va detta ─────────────────────
      //
      // Non c'era, e per questo una shell riscritta per chiedere
      // `get_windows` a un demone che non lo conosceva è rimasta cieca —
      // zero finestre, nessuna barra del titolo sulle finestre altrui — per
      // un giorno intero, senza una riga di errore da nessuna parte. Il
      // messaggio arrivava, non combaciava con nessun ramo, e finiva nel
      // silenzio.
      //
      // Il silenzio è la cosa peggiore che possa fare un confine fra due
      // programmi: chi chiede resta ad aspettare per sempre e non ha modo di
      // sapere che nessuno risponderà.
      default:
        print('[MINERVA][IPC][WARN] Azione sconosciuta: "$action". '
            'Il messaggio è arrivato ma nessuno lo gestisce — '
            'shell e demone non combaciano.');
        _nonSonoRiuscito(client, action, 'azione sconosciuta');
        break;
    }
  }

  /// La ricerca universale: app, impostazioni, file, azioni.
  ///
  /// Sta qui e non dentro lo switch perché era lungo undici volte la media
  /// degli altri rami. Vedi il commento accanto al suo `case`.
  Future<void> _ricercaUniversale(
      WebSocketClientConnection client, Map<String, dynamic> msg) async {
      final query = (msg['query'] as String? ?? '').trim().toLowerCase();
      if (query.isEmpty) {
        // Recupera la lista di app fisse configurate (o fallback a default)
        final fixedIdsRaw = _settingsApi.settings['launcher']?['fixedApps'];
        final List<String> defaultFixedApps = [
          'firefox.desktop',
          'org.gnome.Nautilus.desktop',
          'Alacritty.desktop',
          'steam.desktop',
          'org.gnome.Settings.desktop',
          'org.gnome.gedit.desktop'
        ];
        final List<String> fixedIds = (fixedIdsRaw is List)
            ? fixedIdsRaw.cast<String>()
            : defaultFixedApps;

        final List<Map<String, dynamic>> fixedApps = [];
        final Set<String> addedFixed = {};

        // 1. Aggiunge le app fisse configurate
        //
        // ── E DICE quali non ci sono più ─────────────────────────────
        //
        // Qui c'era solo `if (app != null)`: un preferito che punta a un
        // programma disinstallato spariva, e basta. Sembra innocuo e non
        // lo è — il 30 agosto 2026 Giacomo ha scritto «nel menù start non
        // si vedono più le applicazioni», e la causa era esattamente
        // questa: `pacman -Rns plasma` si era portato via Dolphin e Kate,
        // due dei suoi cinque preferiti, e il menù — che si apre sui
        // preferiti — mostrava tre voci dove prima ce n'erano cinque.
        //
        // Niente era rotto. Ma per saperlo è servito aprire il menù dentro
        // una sessione annidata e guardarlo, perché **il programma non lo
        // diceva**. Una cosa che sparisce senza dire niente è il modo di
        // rompersi che questo progetto paga più caro, ed è già costata una
        // notte di terminale d'emergenza.
        for (final id in fixedIds) {
          final app = _appScanner.getAppById(id);
          if (app == null) {
            if (_preferitiSpariti.add(id)) {
              print('[MINERVA][MATRIX][WARN] Il preferito «$id» non '
                  'esiste più: quel programma è stato disinstallato. '
                  'Resta nelle impostazioni (launcher.fixedApps) finché '
                  'non lo togli, ma nel menù non si vede.');
            }
            continue;
          }
          if (!addedFixed.contains(app.id)) {
            addedFixed.add(app.id);
            fixedApps.add({
              'appId': app.id,
              'name': app.name,
              'exec': app.exec,
              'icon': _iconResolver.resolve(app.icon),
            });
          }
        }

        // Riempie fino a 6 nel caso in cui alcune app fisse non fossero installate (solo al primo avvio se la configurazione è vuota)
        if (fixedIdsRaw == null && fixedApps.length < 6) {
          for (final app in _appScanner.apps) {
            if (!addedFixed.contains(app.id)) {
              addedFixed.add(app.id);
              fixedApps.add({
                'appId': app.id,
                'name': app.name,
                'exec': app.exec,
                'icon': _iconResolver.resolve(app.icon),
              });
              if (fixedApps.length >= 6) break;
            }
          }
        }

        // 2. Recupera le app dinamiche (ordinate per frequenza di utilizzo, senza doppioni con le fisse)
        final List<Map<String, dynamic>> dynamicApps = [];
        final Set<String> excludedIds = Set.from(addedFixed);
        final Set<String> addedDynamic = {};

        final frequentIds = _appUsageTracker.getMostFrequent(limit: 50);
        for (final id in frequentIds) {
          if (excludedIds.contains(id)) continue;
          final app = _appScanner.getAppById(id);
          if (app != null && !addedDynamic.contains(app.id)) {
            addedDynamic.add(app.id);
            dynamicApps.add({
              'appId': app.id,
              'name': app.name,
              'exec': app.exec,
              'icon': _iconResolver.resolve(app.icon),
            });
            if (dynamicApps.length >= 12) break;
          }
        }

        // Riempie fino a 12 con altre app disponibili
        if (dynamicApps.length < 12) {
          for (final app in _appScanner.apps) {
            if (!excludedIds.contains(app.id) && !addedDynamic.contains(app.id)) {
              addedDynamic.add(app.id);
              dynamicApps.add({
                'appId': app.id,
                'name': app.name,
                'exec': app.exec,
                'icon': _iconResolver.resolve(app.icon),
              });
              if (dynamicApps.length >= 12) break;
            }
          }
        }

        client.send({
          'event': 'matrix_nodes',
          'payload': {
            'fixed': fixedApps,
            'dynamic': dynamicApps,
          }
        });
      } else {
        final List<Map<String, dynamic>> results = [];
        for (final app in _appScanner.apps) {
          if (app.name.toLowerCase().contains(query)) {
            final iconPath = _iconResolver.resolve(app.icon);
            results.add({
              'appId': app.id,
              'name': app.name,
              'exec': app.exec,
              'icon': iconPath,
            });
          }
        }
        client.send({
          'event': 'matrix_results',
          'payload': results,
        });
      }
  }

  /// Dice a chi ha chiesto che la sua richiesta non è andata.
  ///
  /// ── Perché esiste ──────────────────────────────────────────────────────
  ///
  /// Il ramo predefinito dello switch aveva scritto sopra la frase giusta —
  /// «il silenzio è la cosa peggiore che possa fare un confine fra due
  /// programmi: chi chiede resta ad aspettare per sempre e non ha modo di
  /// sapere che nessuno risponderà» — e poi faceva esattamente quello:
  /// scriveva una riga sul registro e taceva.
  ///
  /// Il registro lo legge chi lo cerca. Chi ha mandato il messaggio no: resta
  /// fermo, e siccome il canale continua a funzionare per tutto il resto,
  /// nessuno si accorge che una richiesta è caduta.
  ///
  /// ── Perché il motivo va per intero ─────────────────────────────────────
  ///
  /// Un messaggio d'errore di Dart può contenere un percorso o il nome di un
  /// file, e la prima versione di questo commento diceva che per prudenza non
  /// lo si mandava. Era una prudenza finta: per arrivare qui bisogna aver già
  /// detto la parola d'ordine della sessione, e chi ce l'ha può leggere i file
  /// dell'utente chiedendoli — `fs_read` è a due righe di distanza. Nascondere
  /// il motivo a un client che ha già tutto non protegge niente e toglie
  /// l'unica cosa utile.
  ///
  /// Quello che il motivo dà davvero è la differenza fra «non ha funzionato» e
  /// «type 'int' is not a subtype of type 'String?'», che dice anche DOVE
  /// guardare.
  void _nonSonoRiuscito(
      WebSocketClientConnection client, Object? azione, String perche) {
    client.send({
      'event': 'azione_fallita',
      'payload': {
        'azione': azione is String ? azione : '$azione',
        'perche': perche,
      },
    });
  }

  /// Gli eventi dell'accoppiamento vanno a tutti i clienti, e la
  /// sottoscrizione si apre una volta sola: aprirla a ogni `bt_pair`
  /// vorrebbe dire ricevere la stessa domanda tante volte quante le volte che
  /// si è provato ad accoppiare da quando il demone è acceso.
  void _ascoltaAccoppiamento() {
    _accoppiamentoSub ??= _accoppiamento.eventi.listen((e) {
      _aTutti({'event': 'bt_pairing', 'payload': e});
    });
  }

  /// Manda lo stesso messaggio a tutti, impacchettandolo UNA volta sola.
  ///
  /// `solo` filtra chi lo riceve — serve al bus, che spedisce a chi si è
  /// iscritto a quel tipo.
  ///
  /// Fino al 7 settembre 2026 ogni punto che trasmetteva a tutti chiamava
  /// `send` in un ciclo, e `send` impacchetta: lo stesso identico messaggio
  /// convertito in JSON una volta per finestra aperta. Con l'elenco dei
  /// processi — 59 KB, fra 1,3 e 8,9 ms — bastavano tre finestre per passare i
  /// venti millisecondi, e in quel tempo il demone non risponde a nessuno.
  void _aTutti(Map<String, dynamic> data,
      {bool Function(WebSocketClientConnection)? solo}) {
    if (_clients.isEmpty) return;
    final String testo;
    try {
      testo = jsonEncode(data);
    } catch (e) {
      print('[MINERVA][IPC][ERRORE] L\'evento "${data['event']}" non si lascia '
          'convertire in JSON: $e');
      return;
    }
    final evento = '${data['event']}';
    // Una copia dell'elenco: spedire può far morire un client, e chi muore si
    // toglie da `_clients` mentre ci stiamo camminando sopra.
    for (final client in _clients.toList()) {
      if (solo != null && !solo(client)) continue;
      client.sendGrezzo(testo, evento);
    }
  }

  void _broadcastEvent(MinervaEvent event) {
    final payload = {
      'event': event.type,
      'payload': event.payload,
      'timestamp': event.timestamp.toIso8601String(),
    };

    _aTutti(payload, solo: (c) => c.isSubscribed(event.type));
  }

  Future<void> stop() async {
    await _systemAudioSub?.cancel();
    await _systemAudio.close();
    await _eventBusSubscription?.cancel();
    await _transferSubscription?.cancel();
    await _statoFinestreSub?.cancel();
    await _statoMonitorSub?.cancel();
    await _greetdSub?.cancel();
    await _greetd?.chiudi();
    // Fermare le nuove connessioni prima di chiudere quelle esistenti.
    // La chiusura dei socket può rimuovere client tramite le loro callback.
    await _server?.close();
    for (final client in _clients.toList()) {
      client.close();
    }
    _clients.clear();
    // Il socket è un file e non sparisce da solo quando il processo finisce:
    // se lo si lascia per terra, il prossimo avvio deve prima capire se è di
    // qualcuno (vedi `_ascolta`). Chiudendo per bene si evita di fargli fare
    // quella domanda.
    try {
      final f = File(_percorsoSocket);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Se non si riesce non è grave: `_ascolta` sa riconoscere un avanzo.
    }
    print('[MINERVA][IPC][INFO] Server spento.');
  }
}

/// Una singola connessione col demone, con la sua lista di sottoscrizioni.
///
/// Il nome dice ancora «WebSocket» e non è più vero dal 27 agosto 2026: sotto
/// c'è un socket Unix. Rinominare la classe vorrebbe dire toccare un centinaio
/// di punti che non hanno niente a che vedere col trasporto, e il guadagno
/// sarebbe un nome più giusto in cambio di un diff illeggibile proprio nel
/// file che regge tutto il canale. Si cambia quando si tocca per altro.
class WebSocketClientConnection {
  final Socket _socket;

  /// Gli eventi che un client riceve senza doverli chiedere.
  ///
  /// C'era anche `theme_changed`, che **nessuno pubblica**: un nome rimasto da
  /// un'idea precedente — il tema passa da `settings_changed` come tutto il
  /// resto. Un'iscrizione a un evento che non esiste non rompe niente e non si
  /// nota mai, e per questo resta lì per anni a far credere che ci sia un
  /// canale che non c'è.
  List<String> subscribedEvents = [
    'state_changed',
    'settings_changed',
    'keybindings_changed',
    'plugin_terminated',
    // Batteria, luminosità, rete, Bluetooth: li legge il demone una volta per
    // tutte le finestre, e le finestre li ricevono senza chiederli. Sta fra i
    // predefiniti perché non c'è nessuna finestra di Minerva a cui non
    // servano — la barra li mostra, il pannello li comanda, le Impostazioni
    // li spiegano.
    'system_state',
    // ── Le scorciatoie tradotte per il compositore ────────────────────
    //
    // Mancava, e per questo l'annuncio che `minerva_core.dart` pubblica a ogni
    // modifica di `scorciatoie.minerva` non arrivava a NESSUNO: pubblicato,
    // gestito da `Ipc.qml`, e buttato via qui in mezzo. Il sintomo era quello
    // che il commento accanto a quel `publish` dichiara di aver risolto —
    // cambi una scorciatoia, il promemoria di Super+K si aggiorna, e il tasto
    // continua a fare quello di prima fino al riavvio della sessione.
    //
    // Trovato il 7 settembre 2026 rileggendo il demone, non usandolo: le due
    // prove del confine passavano tutte e due, perché guardavano che shell e
    // demone si nominassero a vicenda e non che l'annuncio arrivasse. La terza
    // prova, in `bus_coerenza_test.dart`, adesso guarda anche questo.
    'scorciatoie_compositore',
  ];

  /// Falso finché non ha detto la parola d'ordine. Prima di allora questa
  /// connessione non riceve niente e non può chiedere niente. Vedi
  /// `canale_segreto.dart`.
  bool autenticato = false;

  /// Chi avvisare quando questa connessione muore da sé. Lo mette il server,
  /// per togliere dall'elenco chi se n'è andato senza dirlo.
  void Function()? alMorire;

  /// ── L'errore di scrittura NON torna a chi ha scritto ────────────────────
  ///
  /// È il difetto che il 31 agosto 2026 ha lasciato Giacomo senza dock e senza
  /// menù, in tutte e due le sessioni. `send()` ha un `try/catch` intorno al
  /// `write`, e sembra coperto. Non lo è: nella traccia, fra `_IOSinkImpl.write`
  /// e l'errore, c'è `_RootZone.runUnaryGuarded`. Dart non rilancia
  /// quell'errore al chiamante — lo consegna alla ZONA. Nessuno lo raccoglieva:
  ///
  ///     Unhandled exception:
  ///     SocketException: Write failed (OS Error: Broken pipe, errno = 32)
  ///     #14 WebSocketClientConnection.send (websocket_server.dart:2968)
  ///     [MINERVA][DEMONE] Uscito con esito 255. Riparte fra 1 s.
  ///
  /// Un `catch` che sembra esserci e non c'è è il difetto peggiore di tutti:
  /// chi legge il codice conclude che il caso è coperto e va a cercare altrove.
  ///
  /// `done` è il posto dove Dart consegna la fine di un socket, errore
  /// compreso. Agganciarlo qui — nel costruttore, non nel server — vuol dire
  /// che nessuno può costruire una di queste connessioni dimenticandosi di
  /// farlo. La rete vera è comunque un'altra, ed è in `bin/minervad.dart`:
  /// questa dice CHI è morto, quella garantisce che il demone non muoia con lui.
  WebSocketClientConnection(this._socket) {
    _socket.done.then((_) => _muore(null), onError: _muore);
  }

  /// Questa connessione non riceve più. Una volta sola, qualunque sia la
  /// strada da cui si è saputo.
  void _muore(Object? errore) {
    if (_chiuso) return;
    _chiuso = true;
    if (errore != null) {
      print('[MINERVA][IPC][WARN] Una connessione si è chiusa di colpo: '
          '$errore');
    }
    alMorire?.call();
  }

  bool isSubscribed(String eventType) {
    // Di default sottoscrive a tutti gli eventi critici
    return subscribedEvents.contains(eventType) || subscribedEvents.contains('*');
  }

  /// Quante spedizioni sono fallite su questa connessione.
  int falliti = 0;
  bool _chiuso = false;

  /// Falso appena questa connessione non riceve più. Chi trasmette a tutti lo
  /// guarda per non scrivere in un tubo rotto, e il server lo usa per togliere
  /// dall'elenco chi se n'è andato senza dirlo.
  bool get vivo => !_chiuso;

  /// ── Un messaggio che non parte va detto, una volta ──────────────────────
  ///
  /// Qui c'era `catch (_) {}`: qualunque cosa andasse storta spariva senza
  /// lasciare traccia. Sono due guasti molto diversi, e tutti e due meritano
  /// una riga:
  ///
  ///   * **il JSON non si lascia scrivere** — un payload con dentro qualcosa
  ///     che non è convertibile. È un difetto NOSTRO, e silenziandolo si
  ///     ottiene una finestra che non riceve mai un certo messaggio senza che
  ///     nessuno dei due lati sappia perché;
  ///   * **il socket è morto** — normale, capita a ogni finestra chiusa. Va
  ///     detto una volta sola, altrimenti il registro si riempie di righe
  ///     identiche e smette di servire.
  void send(Map<String, dynamic> data) {
    if (_chiuso) {
      falliti++;
      return;
    }
    // ── Chi non ha detto la parola d'ordine non riceve niente ────────────
    //
    // Il controllo sta QUI e non nei punti che trasmettono a tutti, che sono
    // cinque e domani sei. Un elenco di posti da ricordare è un elenco che
    // prima o poi ne dimentica uno, e la dimenticanza non si vede: quel
    // flusso continua ad arrivare a chiunque, in silenzio.
    //
    // L'unica eccezione è la risposta al saluto, che deve poter arrivare
    // proprio a chi non è ancora autenticato — è la risposta alla domanda
    // «vado bene?».
    if (!autenticato && data['event'] != 'ciao') {
      return;
    }

    // ── L'identificativo della domanda torna con la risposta ───────────
    //
    // Solo se chi ha chiesto ne aveva messo uno, e solo verso di LUI: una
    // spedizione fatta ad altri mentre serviamo questa richiesta non c'entra
    // niente con essa. Vedi `_chiaveId`.
    final Object? idRichiesta = Zone.current[_chiaveId];
    if (idRichiesta != null &&
        identical(Zone.current[_chiaveCliente], this) &&
        !data.containsKey('id')) {
      data = {...data, 'id': idRichiesta};
    }

    final String testo;
    try {
      testo = jsonEncode(data);
    } catch (e) {
      falliti++;
      print('[MINERVA][IPC][ERRORE] L\'evento "${data['event']}" non si lascia '
          'convertire in JSON: $e');
      return;
    }
    sendGrezzo(testo, '${data['event']}');
  }

  /// Spedisce un messaggio GIÀ impacchettato.
  ///
  /// ── Perché esiste ──────────────────────────────────────────────────────
  ///
  /// Perché `jsonEncode` costa, e trasmettere a tutti lo faceva una volta per
  /// client: lo stesso identico messaggio impacchettato otto volte se ci sono
  /// otto finestre di Minerva aperte. Misurato il 7 settembre 2026: l'elenco
  /// dei processi è 59 KB e impacchettarlo costa fra 1,3 e 8,9 ms — e il
  /// demone ha un filo solo, quindi quei millisecondi sono fermi per tutti.
  /// `windows_state` arriva fino a sedici volte al secondo.
  ///
  /// Il nome dell'evento si passa a parte perché serve solo a scrivere un
  /// errore comprensibile: senza, il messaggio direbbe «un client non riceve
  /// più» e non quale flusso si è interrotto.
  void sendGrezzo(String testo, String evento) {
    if (_chiuso) {
      falliti++;
      return;
    }
    if (!autenticato && evento != 'ciao') return;
    try {
      // L'a-capo è il confine fra un messaggio e il prossimo: vedi
      // `_handleNewClient`. Senza, dall'altra parte due risposte spedite
      // vicine arriverebbero attaccate e il parser le butterebbe via
      // entrambe.
      _socket.write('$testo\n');
    } catch (e) {
      falliti++;
      if (falliti == 1) {
        print('[MINERVA][IPC][WARN] Un client non riceve più (primo mancato: '
            '"$evento"): $e');
      }
      // E si smette di provarci. Prima si contava e si continuava a scrivere:
      // un tubo rotto restava nell'elenco fino a fine sessione, e ogni
      // `windows_state` — fino a sedici al secondo — era un'altra occasione
      // per l'errore che uccideva il demone.
      _muore(null);
    }
  }

  void close() {
    _chiuso = true;
    // `destroy` e non `close`: `close` aspetta che finisca di scrivere, e se
    // dall'altra parte non legge più — una finestra uccisa — quell'attesa non
    // finisce mai e la connessione resta nell'elenco.
    _socket.destroy();
  }
}

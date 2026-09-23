import 'dart:io';

import 'account/google.dart';
import 'account/registro_account.dart';
import 'account/webdav.dart';

/// AccountService — gli account online di Minerva.
///
/// Richiesta di Giacomo, 24 agosto 2026: «perché in impostazioni non inseriamo
/// una sezione account online come fa gnome e altri desktop dove poter accedere
/// a vari servizi e vedere ad esempio spazio usato e rimanente, se il servizio
/// di sincronizzazione per quel servizio è attivo e altre informazioni?»
///
/// ── Le tre cose che questo servizio promette ───────────────────────────────
///
///  1. **Un posto solo.** Gli account stanno in un registro condiviso: le
///     Impostazioni li mostrano, la Custodia li usa come destinazioni. Chi
///     collega kDrive una volta l'ha collegato per tutti e due.
///  2. **Le password nel portachiavi.** Mai in un file, mai negli argomenti di
///     un processo. Vedi `account/registro_account.dart`.
///  3. **Niente numeri inventati.** Se il server non dice quanto spazio resta,
///     si scrive che non lo dice. Un numero dedotto sullo spazio libero è
///     quello che fa perdere dei file.
///
/// ── Cosa NON si può fare, e perché è giusto dirlo ──────────────────────────
///
/// **Il portachiavi password di Google non è leggibile da fuori.** Le password
/// salvate stanno dentro Chrome e dentro l'account Google, e non esiste nessuna
/// interfaccia per prenderle e usarle per accedere ad altro. Chi lo propone sta
/// descrivendo un furto di credenziali. La cosa che invece si fa, e che si
/// confonde con quella, è «Accedi con Google» — cioè OAuth, che dà accesso a
/// Drive e al calendario e non tocca nessuna password.
///
/// **Google Drive richiede una chiave dell'applicazione** registrata da noi sul
/// sito di Google, e finché non c'è non lo si offre: un pulsante che porta a un
/// errore è peggio di un pulsante che manca.
///
/// **Una cartella nella home non si può montare, oggi, su questa macchina.**
/// Misurato il 25 agosto 2026: `rclone` non è installato e gvfs non ha il
/// backend WebDAV (in `/usr/share/gvfs/mounts` non c'è nessun `dav.mount`).
/// Si dice, e si offre di installarlo — non si mostra una cartella che non
/// esiste.
class AccountService {
  AccountService({
    RegistroAccount? registro,
    WebDav? dav,
    GoogleOAuth? google,
    Future<ProcessResult> Function(String, List<String>)? esegui,
    Future<int> Function(String, List<String>, String)? conSegreto,
  })  : registro = registro ?? RegistroAccount(),
        dav = dav ?? const WebDav(),
        google = google ?? const GoogleOAuth(),
        _esegui = esegui ?? Process.run,
        _conSegreto = conSegreto ?? _conSegretoVero;

  final RegistroAccount registro;
  final WebDav dav;
  final GoogleOAuth google;
  final Future<ProcessResult> Function(String, List<String>) _esegui;

  /// Eseguire un comando dandogli un segreto **sullo standard input**.
  ///
  /// Sta qui, e non dentro `_mettiViaPassword`, per una ragione che è saltata
  /// fuori scrivendo le prove: finché la scrittura nel portachiavi era una
  /// `Process.start` piantata dentro il metodo, ogni prova che collegava un
  /// account **scriveva davvero nel portachiavi di Giacomo** — e la riga che
  /// controllava che una password sbagliata non ci finisse non guardava
  /// niente, perché quel comando non passava dalla lista che la prova
  /// osservava. Una prova che non può fallire non è una prova.
  final Future<int> Function(String, List<String>, String) _conSegreto;

  static Future<int> _conSegretoVero(
      String comando, List<String> args, String segreto) async {
    final p = await Process.start(comando, args);
    p.stdin.write(segreto);
    await p.stdin.close();
    return p.exitCode;
  }

  static const String _servizioPortachiavi = 'minerva-account';

  // Il registro si legge una volta sola e prima di chiunque: è lo stesso
  // difetto già pagato dalla Custodia, dove due richieste di fila si
  // rincorrevano e la seconda rispondeva «non è nell'elenco» su un elenco
  // ancora vuoto.
  Future<void>? _pronto;

  Future<void> init() {
    _pronto ??= registro.carica();
    return _pronto!;
  }

  Future<void> rileggi() {
    _pronto = registro.carica();
    return _pronto!;
  }

  // ── L'elenco ───────────────────────────────────────────────────────────

  /// Gli account, con accanto quello che si sa senza chiedere niente alla rete.
  ///
  /// Lo spazio NON si chiede qui: sono richieste in rete, una per account, e
  /// aprire una finestra non deve poter dipendere da un server lento. Si chiede
  /// per un account alla volta, quando lo si guarda.
  Future<Map<String, dynamic>> elenco() async {
    await init();
    return {
      'ok': true,
      'account': [for (final a in registro.account) a.toJson()],
      // Quello che questa macchina può fare oggi. La finestra lo mostra invece
      // di offrire cose che finirebbero in un errore.
      'puo': await capacita(),
    };
  }

  /// Cosa questa macchina sa fare adesso, misurato e non supposto.
  Future<Map<String, dynamic>> capacita() async {
    return {
      'webdav': true, // non ha bisogno di niente: parliamo noi
      'montare': await _c('rclone'),
      'portachiavi': await _c('secret-tool'),
      // Google si può fare **quando c'è la chiave dell'applicazione**. Non è
      // un «non si può» per sempre, come era scritto qui fino al 25 agosto:
      // è una cosa che manca e che si mette, e la finestra deve dire quale
      // delle due.
      'google': await chiaveGoogle() != null,
    };
  }

  Future<bool> _c(String comando) async {
    try {
      final r = await _esegui('sh', ['-c', 'command -v $comando']);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  // ── Collegare ──────────────────────────────────────────────────────────

  /// Collega un account. **Prima si prova, poi si scrive.**
  ///
  /// L'ordine non è un dettaglio: un account salvato che non funziona è una
  /// riga nell'elenco che dice «collegato» e non lo è, e il momento in cui ci
  /// si accorge dell'errore è quello in cui si prova a mandarci un backup.
  Future<Map<String, dynamic>> collega({
    required String servizio,
    required String utente,
    required String password,
    String url = '',
    String numeroKdrive = '',
    String nome = '',
  }) async {
    await init();

    if (utente.trim().isEmpty || password.isEmpty) {
      return _no('Mi servono il nome utente e la password.');
    }

    String? indirizzo;
    switch (servizio) {
      case 'kdrive':
        // ── Il numero non si chiede ──────────────────────────────────────
        //
        // Giacomo, 25 agosto 2026: «il mio account chiede solo email e
        // password e non un codice». Aveva ragione, e il modulo aveva torto:
        // il server WebDAV di Infomaniak risponde sulla radice, senza numero,
        // e i kDrive dell'account li elenca da sé. Il numero resta accettato
        // per chi ce l'ha già scritto da qualche parte, o per scegliere fra
        // più archivi — ma non è più una domanda da fare a nessuno.
        if (numeroKdrive.trim().isNotEmpty) {
          indirizzo = WebDav.kdrive(numeroKdrive);
          if (indirizzo == null) {
            return _no('Il numero del kDrive è solo cifre. Se non sai qual è, '
                'lasciarlo vuoto va benissimo: lo trovo io.');
          }
          break;
        }
        final trovati = await dav.kdriveDi(utente.trim(), password);
        if (trovati.errore != null) return _no(trovati.errore!);
        if (trovati.dischi.isEmpty) {
          return _no('L\'accesso funziona, ma su questo account non vedo '
              'nessun kDrive. Se ce n\'è uno che è di qualcun altro e lo usi '
              'in condivisione, serve il suo numero.');
        }
        if (trovati.dischi.length > 1) {
          // Più archivi: si sceglie, non si indovina. La finestra rimanda
          // qui la stessa richiesta col numero scelto, e la password non ha
          // mai lasciato lo schermo nel frattempo.
          return {
            'ok': false,
            'scegli': [for (final d in trovati.dischi) d.toJson()],
            'errore': 'Questo account ha più di un kDrive: dimmi quale.',
          };
        }
        indirizzo = trovati.dischi.first.url;
        if (nome.trim().isEmpty) nome = trovati.dischi.first.nome;
        break;
      case 'webdav':
        indirizzo = WebDav.indirizzo(url);
        if (indirizzo == null) {
          return _no('Quell\'indirizzo non va bene. Deve cominciare per '
              '«https://» — senza la esse la password viaggerebbe in chiaro.');
        }
        break;
      default:
        return _no('Non so collegarmi a un servizio di tipo «$servizio».');
    }

    final perche = await dav.prova(indirizzo, utente.trim(), password);
    if (perche != null) return _no(perche);

    final id = RegistroAccount.chiaveDa(servizio, utente);
    final messo = await _mettiViaPassword(id, password);
    if (messo != null) return _no(messo);

    final gia = registro.cerca(id);
    if (gia != null) {
      // Ricollegare non aggiunge una seconda riga: aggiorna quella che c'è.
      // Due righe per lo stesso account sono due posti dove scade la password.
      gia.url = indirizzo;
      if (nome.trim().isNotEmpty) gia.nome = nome.trim();
      gia.ultimaProva = DateTime.now();
      gia.funziona = true;
    } else {
      registro.account.add(Account(
        id: id,
        servizio: servizio,
        nome: nome.trim().isEmpty ? _nomePredefinito(servizio, utente) : nome.trim(),
        utente: utente.trim(),
        url: indirizzo,
        aggiunto: DateTime.now(),
        ultimaProva: DateTime.now(),
        funziona: true,
      ));
    }
    await registro.salva();
    return {'ok': true, 'account': registro.cerca(id)!.toJson()};
  }

  static String _nomePredefinito(String servizio, String utente) {
    switch (servizio) {
      case 'kdrive':
        return 'kDrive';
      case 'webdav':
        return 'Cartella in rete';
      case 'google':
        return 'Google Drive';
      default:
        return utente;
    }
  }

  /// Toglie un account. La roba che sta sul server **non si tocca**.
  Future<Map<String, dynamic>> scollega(String id) async {
    await init();
    final a = registro.cerca(id);
    if (a == null) return _no('Quell\'account non è nell\'elenco.');
    // Google: si toglie il permesso anche dal lato loro. Lasciarlo valido
    // vorrebbe dire che nell'elenco dei permessi del suo account resta scritto
    // che Minerva può entrare, e non sarebbe vero.
    if (a.servizio == 'google') {
      final rinnovo = await _leggiPassword(id);
      if (rinnovo != null) await google.revoca(rinnovo);
    }
    registro.account.remove(a);
    await registro.salva();
    await _dimenticaPassword(id);
    return {
      'ok': true,
      'nota': 'I file che stanno sul server restano dove sono: togliere '
          'l\'account da qui non cancella niente.',
    };
  }

  // ── Guardare ───────────────────────────────────────────────────────────

  /// Riprova l'accesso e chiede quanto spazio c'è. Due richieste in rete: si
  /// fanno quando qualcuno guarda quell'account, non all'apertura.
  Future<Map<String, dynamic>> guarda(String id) async {
    await init();
    final a = registro.cerca(id);
    if (a == null) return _no('Quell\'account non è nell\'elenco.');

    if (a.servizio == 'google') return _guardaGoogle(a);

    final password = await _leggiPassword(id);
    if (password == null) {
      a.funziona = false;
      a.ultimaProva = DateTime.now();
      await registro.salva();
      return _no('La password di questo account non è più nel portachiavi. '
          'Ricollegalo.');
    }

    final perche = await dav.prova(a.url, a.utente, password);
    a.ultimaProva = DateTime.now();
    a.funziona = perche == null;
    await registro.salva();
    if (perche != null) {
      return {'ok': false, 'errore': perche, 'account': a.toJson()};
    }

    final s = await dav.spazio(a.url, a.utente, password);
    return {'ok': true, 'account': a.toJson(), 'spazio': s.toJson()};
  }

  // ── Google ─────────────────────────────────────────────────────────────
  //
  // Qui non passa nessuna password: a quella — e al secondo passaggio, e a
  // tutto il resto — risponde Google dentro il browser. Da questa parte
  // arrivano solo due chiavi: quella dell'applicazione, che è di Minerva, e
  // quella di rinnovo, che è dell'account. Tutte e due nel portachiavi.

  static const String _contoChiaveApp = 'google-app';

  /// La chiave dell'applicazione, se è già stata messa. `null` se manca.
  Future<ChiaveGoogle?> chiaveGoogle() async {
    final v = await _leggiPassword(_contoChiaveApp);
    if (v == null) return null;
    final righe = v.split('\n');
    if (righe.length < 2 || righe[0].isEmpty || righe[1].isEmpty) return null;
    return ChiaveGoogle(righe[0], righe[1]);
  }

  /// Mette via la chiave dell'applicazione. Non prova niente: quella si prova
  /// da sola al primo collegamento, ed è lì che Google dirà se non la
  /// riconosce.
  Future<Map<String, dynamic>> salvaChiaveGoogle(
      String identificativo, String segreto) async {
    final i = identificativo.trim();
    final sg = segreto.trim();
    if (i.isEmpty || sg.isEmpty) {
      return _no('Mi servono tutte e due: l\'identificativo e il segreto.');
    }
    if (!i.contains('.apps.googleusercontent.com')) {
      // Il pezzo sbagliato incollato al posto giusto è l'errore più comune di
      // questa procedura: si copia la chiave dell'API invece che quella
      // OAuth, e Google risponde con un errore che non spiega niente.
      return _no('Quello non sembra l\'identificativo giusto: quello di '
          'Google finisce per «.apps.googleusercontent.com». Attento a non '
          'copiare la chiave dell\'API al posto suo.');
    }
    final male = await _mettiViaPassword(_contoChiaveApp, '$i\n$sg');
    if (male != null) return _no(male);
    return {
      'ok': true,
      'nota': 'Chiave salvata. Adesso il pulsante «Accedi con Google» '
          'funziona.',
    };
  }

  Future<Map<String, dynamic>> dimenticaChiaveGoogle() async {
    await _dimenticaPassword(_contoChiaveApp);
    return {'ok': true, 'nota': 'Chiave dell\'applicazione dimenticata.'};
  }

  /// Il collegamento vero. `apri` riceve l'indirizzo da aprire nel browser:
  /// il demone non ha uno schermo davanti, la finestra sì.
  Future<Map<String, dynamic>> collegaGoogle(
      void Function(String url) apri) async {
    await init();
    final chiave = await chiaveGoogle();
    if (chiave == null) {
      return _no('Prima serve la chiave dell\'applicazione di Google. È una '
          'cosa che si fa una volta sola.');
    }

    final e = await google.collega(
      clientId: chiave.identificativo,
      clientSecret: chiave.segreto,
      apri: apri,
    );
    if (!e.ok) return _no(e.errore ?? 'Non è andata.');
    if (e.email.isEmpty) {
      return _no('Google non mi ha detto di che account si tratta.');
    }

    final id = RegistroAccount.chiaveDa('google', e.email);
    // Nel portachiavi va la chiave di rinnovo, non una password: è la sola
    // cosa che permette di rientrare domani, e vale esattamente quanto una.
    final messo = await _mettiViaPassword(id, e.rinnovo!);
    if (messo != null) return _no(messo);

    final gia = registro.cerca(id);
    if (gia != null) {
      gia.ultimaProva = DateTime.now();
      gia.funziona = true;
      if (e.nome.isNotEmpty) gia.nome = 'Google Drive · ${e.nome}';
    } else {
      registro.account.add(Account(
        id: id,
        servizio: 'google',
        nome: e.nome.isEmpty ? 'Google Drive' : 'Google Drive · ${e.nome}',
        utente: e.email,
        url: 'https://drive.google.com',
        aggiunto: DateTime.now(),
        ultimaProva: DateTime.now(),
        funziona: true,
      ));
    }
    await registro.salva();
    return {
      'ok': true,
      'account': registro.cerca(id)!.toJson(),
      'nota': 'Collegato. Minerva vede soltanto i file che crea lei: il resto '
          'del tuo Drive, per questo programma, non esiste.',
    };
  }

  Future<Map<String, dynamic>> _guardaGoogle(Account a) async {
    final chiave = await chiaveGoogle();
    final rinnovo = await _leggiPassword(a.id);
    if (chiave == null || rinnovo == null) {
      a.funziona = false;
      a.ultimaProva = DateTime.now();
      await registro.salva();
      return _no('Le chiavi di questo account non sono più nel portachiavi. '
          'Ricollegalo.');
    }
    final e = await google.rinnova(
      clientId: chiave.identificativo,
      clientSecret: chiave.segreto,
      rinnovo: rinnovo,
    );
    a.ultimaProva = DateTime.now();
    a.funziona = e.ok;
    await registro.salva();
    if (!e.ok) {
      return {'ok': false, 'errore': e.errore, 'account': a.toJson()};
    }
    return {
      'ok': true,
      'account': a.toJson(),
      'spazio': (e.spazio ?? const SpazioDav()).toJson(),
    };
  }

  // ── Il portachiavi ─────────────────────────────────────────────────────
  //
  // La password entra da qui e non esce mai più: nessuna risposta di questo
  // servizio la contiene, nemmeno accorciata. Si scrive sullo standard input e
  // non negli argomenti, perché `/proc/<pid>/cmdline` la legge chiunque giri
  // come te.

  Future<String?> _mettiViaPassword(String id, String password) async {
    try {
      final uscita = await _conSegreto(
          'secret-tool',
          [
            'store', '--label=Minerva · $id',
            'servizio', _servizioPortachiavi, 'conto', id,
          ],
          password);
      if (uscita != 0) {
        return 'Il portachiavi non ha accettato la password.';
      }
      return null;
    } catch (e) {
      return 'Non trovo il portachiavi di sistema ($e).';
    }
  }

  Future<String?> _leggiPassword(String id) async {
    try {
      final r = await _esegui('secret-tool',
          ['lookup', 'servizio', _servizioPortachiavi, 'conto', id]);
      if (r.exitCode != 0) return null;
      final s = '${r.stdout}';
      return s.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<void> _dimenticaPassword(String id) async {
    try {
      await _esegui('secret-tool',
          ['clear', 'servizio', _servizioPortachiavi, 'conto', id]);
    } catch (_) {
      // Se il portachiavi non c'è, l'account è comunque tolto dall'elenco.
    }
  }

  static Map<String, dynamic> _no(String perche) =>
      {'ok': false, 'errore': perche};
}

/// La chiave dell'applicazione di Google: due pezzi che vanno insieme.
class ChiaveGoogle {
  const ChiaveGoogle(this.identificativo, this.segreto);
  final String identificativo;
  final String segreto;
}

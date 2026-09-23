import 'dart:async';
import 'dart:io';

import 'custodia/cartella_motore.dart';
import 'custodia/git_motore.dart';
import 'custodia/github_motore.dart';
import 'custodia/punti_motore.dart';
import 'custodia/registro.dart';

/// CustodiaService — la storia e la sicurezza delle cartelle di chi usa Minerva.
///
/// ── La regola, che è tutta l'architettura ──────────────────────────────────
///
/// **Nessuna operazione che può perdere lavoro parte senza aver preso prima un
/// punto di ritorno. Se il punto non riesce, l'operazione non parte.**
///
/// Non è una cortesia e non è un consiglio nel manuale: è la condizione che
/// rende offribile a Giacomo un pulsante «torna a ieri». Chi sa git sa che
/// `reset --hard` butta via tutto quello che non è salvato, e sceglie
/// consapevolmente; chi non sa git preme un pulsante che dice «torna a ieri» e
/// si aspetta di poter tornare avanti. Ha ragione lui, e il codice deve
/// garantirglielo.
///
/// Costa 90 millisecondi e 8 kilobyte — misurati su questa macchina, sulla
/// cartella di Minerva. A quel prezzo non c'è nessuna ragione per non farlo
/// sempre.
///
/// ── I due motori, e perché l'utente non li vede ────────────────────────────
///
/// · **git** tiene ogni versione per sempre. Perfetto per codice e testi.
/// · **la copia** tiene l'ultima versione, e le precedenti stanno nei punti di
///   ritorno.
///
/// La scelta la fa il programma guardando cosa c'è nella cartella (vedi
/// `Registro.suggerisciMotore`), e si può correggere. Il motivo per cui non è
/// una domanda all'utente è che la risposta giusta dipende da un fatto tecnico
/// che non gli riguarda: git conserva ogni versione di ogni file binario, e una
/// cartella di ROM Android da 286 GB in git diventa impossibile da usare. Non è
/// una preferenza — è un errore, e i programmi non devono offrire di farlo.
class CustodiaService {
  CustodiaService({
    Registro? registro,
    PuntiMotore? punti,
    GitMotore? git,
    CartellaMotore? cartella,
    GitHubMotore? github,
  })  : registro = registro ?? Registro(),
        punti = punti ?? PuntiMotore(),
        git = git ?? GitMotore(),
        cartella = cartella ?? CartellaMotore(),
        github = github ?? GitHubMotore();

  final Registro registro;
  final PuntiMotore punti;
  final GitMotore git;
  final CartellaMotore cartella;
  final GitHubMotore github;

  // ── Il registro si legge una volta sola, e prima di chiunque ───────────
  //
  // `_pronto` tiene la LETTURA, non il fatto di averla finita: chi arriva
  // mentre è in corso aspetta quella, non ne fa una seconda.
  //
  // Il difetto che questo chiude si è visto solo provando davvero. Il registro
  // lo leggeva `panoramica()`, e la finestra manda due richieste di fila —
  // «dammi la griglia» e «dammi questo progetto». Sono due gestori asincroni:
  // il secondo entrava mentre il primo stava ancora aspettando il disco, e
  // rispondeva «Quel progetto non è nell'elenco» su un elenco che era
  // semplicemente ancora vuoto. Un errore rosso perfettamente falso, e che si
  // aggiustava da solo al giro dopo — cioè il tipo di difetto che si rincorre
  // per giorni.
  Future<void>? _pronto;

  Future<void> init() {
    _pronto ??= registro.carica();
    return _pronto!;
  }

  /// Da rileggere davvero, quando il file è cambiato sotto di noi.
  Future<void> rileggi() {
    _pronto = registro.carica();
    return _pronto!;
  }

  // ── Una cosa alla volta, per progetto ──────────────────────────────────
  //
  // Salvare, mandare, prendere un punto, tornare indietro: sullo stesso
  // progetto si fanno UNA per volta, in fila. Senza questa fila, un «Manda
  // adesso» premuto mentre il salvataggio è ancora in corso (un `git add -A`
  // su una cartella grossa ci mette dei secondi) spingeva fuori la storia di
  // PRIMA e diceva «Mandato». Visto sul progetto di Giacomo il 18 settembre
  // 2026: invio alle 21:28:49, salvataggio finito alle 21:29:12, e GitHub
  // fermo a tre giorni prima con la finestra che diceva di aver fatto.
  final Map<String, Future<void>> _inFila = {};

  Future<T> _unoAllaVolta<T>(String percorso, Future<T> Function() cosa) {
    final prima = _inFila[percorso] ?? Future<void>.value();
    final completer = Completer<void>();
    _inFila[percorso] = completer.future;
    return prima.then((_) => cosa()).whenComplete(() {
      completer.complete();
      if (identical(_inFila[percorso], completer.future)) _inFila.remove(percorso);
    });
  }

  // ── La griglia ─────────────────────────────────────────────────────────

  /// Lo stato di tutti i progetti: è quello che si vede aprendo la Custodia.
  ///
  /// Ogni riquadro deve rispondere a tre domande e basta: *quanto ho da
  /// salvare, quand'è l'ultima volta che sono tornato indietro, sono al sicuro
  /// fuori di qui.* Tutto il resto è dettaglio, e sta dentro il progetto.
  Future<List<Map<String, dynamic>>> panoramica() async {
    await init();
    final fuori = <Map<String, dynamic>>[];
    for (final p in registro.progetti) {
      fuori.add(await _riquadro(p));
    }
    return fuori;
  }

  Future<Map<String, dynamic>> _riquadro(Progetto p) async {
    if (!p.esiste) {
      return {
        ...p.toJson(),
        'esiste': false,
        'avviso': 'Questa cartella non c\'è più.',
      };
    }
    final ultimi = await punti.elenca(p.chiave);
    final j = <String, dynamic>{
      ...p.toJson(),
      'esiste': true,
      'punti': ultimi.length,
      if (ultimi.isNotEmpty) 'ultimoPunto': ultimi.first.toJson(),
    };
    if (p.motore == 'git') {
      final s = await git.stato(p.percorso);
      j['stato'] = s.toJson();
      if (s.tieneStoria) {
        final storia = await git.storia(p.percorso, quanti: 1);
        if (storia.isNotEmpty) j['ultimoSalvataggio'] = storia.first.toJson();
      }
    }
    return j;
  }

  /// Il dettaglio di un progetto: le modifiche raggruppate, la storia, i punti.
  Future<Map<String, dynamic>> dettaglio(String percorso) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    return {
      'ok': true,
      ...(await _riquadro(p)),
      'storia': [
        for (final s in await git.storia(p.percorso, quanti: 50)) s.toJson(),
      ],
      'elencoPunti': [
        for (final q in await punti.elenca(p.chiave)) q.toJson(),
      ],
      'firma': (await git.firma(p.percorso)).toJson(),
      'copiaGratuita': await punti.copiaGratuita(p.percorso),
    };
  }

  // ── Le operazioni che NON possono perdere niente ───────────────────────

  /// Un punto di ritorno, chiesto a mano. Sempre lecito, sempre in più.
  Future<Map<String, dynamic>> prendiPunto(String percorso,
          {String nota = ''}) =>
      _unoAllaVolta(percorso, () => _prendiPunto(percorso, nota: nota));

  Future<Map<String, dynamic>> _prendiPunto(String percorso,
      {String nota = ''}) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    final e = await punti.crea(p.chiave, p.percorso, nota: nota);
    if (e.riuscito) {
      p.ultimoPunto = e.punto!.quando;
      await registro.salva();
    }
    return e.toJson();
  }

  /// Salva. Un salvataggio **aggiunge** alla storia e non toglie niente: è la
  /// sola operazione importante che non ha bisogno di un punto di ritorno
  /// prima, e dirlo qui evita di aggiungerlo «per simmetria» un domani.
  Future<Map<String, dynamic>> salva(
    String percorso,
    String messaggio, {
    bool forza = false,
  }) =>
      _unoAllaVolta(percorso, () async {
        await init();
        final p = registro.cerca(percorso);
        if (p == null) return _no('Quel progetto non è nell\'elenco.');
        if (p.motore != 'git') {
          return _no('Questo progetto non tiene una storia salvata: usa i '
              'punti di ritorno.');
        }
        final f = await git.firma(p.percorso);
        if (!f.completa) {
          return _no('Prima dimmi come firmare i salvataggi: manca il tuo '
              'nome o la tua email.');
        }
        return (await git.salva(p.percorso, messaggio, forza: forza)).toJson();
      });

  // ── Le operazioni che POSSONO perdere qualcosa ─────────────────────────
  //
  // Da qui in giù, ogni funzione comincia allo stesso modo. È voluto: la
  // ripetizione si vede, e una funzione nuova che non cominciasse così
  // salterebbe all'occhio.

  /// Comincia a tenere la storia di una cartella.
  Future<Map<String, dynamic>> iniziaStoria(String percorso) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');

    final rete = await _rete(p, 'prima-di-cominciare-la-storia');
    if (rete != null) return rete;

    final e = await git.inizia(p.percorso);
    if (e.riuscito) {
      p.motore = 'git';
      await registro.salva();
    }
    return e.toJson();
  }

  /// Torna a un salvataggio.
  Future<Map<String, dynamic>> tornaASalvataggio(String percorso, String id) =>
      _unoAllaVolta(percorso, () => _tornaASalvataggio(percorso, id));

  Future<Map<String, dynamic>> _tornaASalvataggio(
      String percorso, String id) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    if (p.motore != 'git') {
      return _no('Questo progetto non ha salvataggi: ha punti di ritorno.');
    }

    final rete = await _rete(p, 'prima-di-tornare-al-salvataggio');
    if (rete != null) return rete;

    final e = await git.tornaA(p.percorso, id);
    return {
      ...e.toJson(),
      if (e.riuscito)
        'annullabile':
            'Se non era quello che volevi, torna al punto di ritorno appena '
                'preso: c\'è ancora tutto com\'era un attimo fa.',
    };
  }

  /// Torna a un punto di ritorno. Il punto di sicurezza lo prende già
  /// `PuntiMotore.ripristina()`, che è anche il posto giusto: è lì che vive
  /// l'ordine delle mosse che rende il ripristino reversibile.
  Future<Map<String, dynamic>> tornaAPunto(String percorso, String id) =>
      _unoAllaVolta(percorso, () => _tornaAPunto(percorso, id));

  Future<Map<String, dynamic>> _tornaAPunto(String percorso, String id) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    final e = await punti.ripristina(p.chiave, id, p.percorso);
    return e.toJson();
  }

  /// La rete. `null` se ha retto; l'errore da restituire se non ha retto.
  ///
  /// Torna un errore invece di lanciare un'eccezione apposta: un'eccezione si
  /// può dimenticare di prendere, un valore di ritorno che si ignora lo vede
  /// l'analizzatore.
  Future<Map<String, dynamic>?> _rete(Progetto p, String nota) async {
    final e = await punti.crea(p.chiave, p.percorso, nota: nota);
    if (e.riuscito) {
      p.ultimoPunto = e.punto!.quando;
      await registro.salva();
      return null;
    }
    return _no(
      'Non sono riuscito a mettere al sicuro com\'è adesso, quindi non faccio '
      'niente. ${e.errore}',
    );
  }

  // ── Le destinazioni ────────────────────────────────────────────────────
  //
  // «Vorrei poter scegliere in fase di caricamento quale opzione voglio» —
  // parole di Giacomo. Quindi ogni progetto ha un ELENCO di posti dove andare,
  // e mandare fuori chiede quale.

  Future<Map<String, dynamic>> aggiungiDestinazione(
    String percorso,
    String tipo,
    String nome,
    String dove,
  ) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');

    if (tipo == 'cartella') {
      final no = CartellaMotore.percheNo(p.percorso, dove);
      if (no != null) return _no(no);
    } else if (tipo == 'github') {
      // Un archivio di GitHub si può aggiungere solo a un progetto che tiene
      // una storia: git manda salvataggi, e un progetto senza storia non ne ha
      // nemmeno uno. Dirlo qui, mentre si sceglie, invece che al primo invio.
      if (p.motore != 'git') {
        return _no('Questo progetto non tiene una storia salvata, e GitHub '
            'accetta solo storie. Comincia a tenere la storia, oppure mandalo '
            'in una cartella o su un disco.');
      }
      // Il collegamento si fa adesso e non al primo invio: se l'indirizzo è
      // sbagliato si scopre mentre lo si sta scegliendo, che è l'unico momento
      // in cui uno ce l'ha ancora davanti.
      final c = await github.collega(p.percorso, dove);
      if (!c.riuscito) return _no(c.errore!);
    } else {
      return _no('Non so mandare niente in un posto di tipo «$tipo».');
    }
    if (p.destinazioni.any((d) => d.tipo == tipo && d.dove == dove)) {
      return _no('Quel posto c\'è già.');
    }
    p.destinazioni.add(Destinazione(
      tipo: tipo,
      nome: nome.trim().isEmpty ? dove.split('/').last : nome.trim(),
      dove: dove,
    ));
    await registro.salva();
    return {'ok': true, 'progetto': p.toJson()};
  }

  Future<Map<String, dynamic>> togliDestinazione(
      String percorso, String dove) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    final prima = p.destinazioni.length;
    p.destinazioni.removeWhere((d) => d.dove == dove);
    if (p.destinazioni.length == prima) return _no('Quel posto non c\'è.');
    await registro.salva();
    return {
      'ok': true,
      'nota': 'La copia che c\'era là resta dov\'è: toglierlo dall\'elenco '
          'non cancella niente.',
    };
  }

  /// Manda il progetto a una delle sue destinazioni.
  ///
  /// Non prende un punto di ritorno prima, e va detto: mandare fuori **legge**
  /// il progetto e non lo tocca. Il rischio sta dall'altra parte — nella
  /// cartella di destinazione — e lì la difesa è che non si scrive mai fuori
  /// dalla sottocartella nostra. Vedi `custodia/cartella_motore.dart`.
  Future<Map<String, dynamic>> manda(String percorso, String dove,
          {DateTime? quando}) =>
      _unoAllaVolta(percorso, () => _manda(percorso, dove, quando: quando));

  Future<Map<String, dynamic>> _manda(String percorso, String dove,
      {DateTime? quando}) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    final d = p.destinazioni.where((x) => x.dove == dove).firstOrNull;
    if (d == null) return _no('Quel posto non è fra le destinazioni.');

    if (d.tipo == 'github') return _mandaSuGitHub(p, d, quando ?? DateTime.now());

    // Un giro datato a ogni invio riempirebbe il disco di date senza aggiungere
    // niente: uno al giorno basta, e il nome stesso lo garantisce perché due
    // invii dello stesso giorno chiedono la stessa cartella.
    final q = quando ?? DateTime.now();
    String due(int v) => v.toString().padLeft(2, '0');
    final data = '${q.year}-${due(q.month)}-${due(q.day)}_0000';

    final e = await cartella.manda(
      p.percorso,
      d.dove,
      chiave: p.chiave,
      dataGiro: data,
      escludi: p.escludi,
    );
    if (e.riuscito) {
      p.ultimoInvio = q;
      await registro.salva();
    }
    return e.toJson();
  }

  // ── GitHub ─────────────────────────────────────────────────────────────
  //
  // Il gettone non passa mai da qui. Sta nel portachiavi di sistema, e da lì
  // arriva a git dentro l'ambiente di un processo che muore subito dopo: vedi
  // `custodia/github_motore.dart`. Questo servizio non lo legge, non lo scrive
  // in nessuna risposta, e non lo mette in nessun registro.

  Future<Map<String, dynamic>> _mandaSuGitHub(
      Progetto p, Destinazione d, DateTime q) async {
    if (p.motore != 'git') {
      return _no('Questo progetto non tiene una storia salvata: GitHub '
          'accetta solo storie.');
    }
    if (!await git.haStoria(p.percorso)) {
      return _no('Non c\'è ancora niente da mandare: fai il primo salvataggio.');
    }
    final s = await git.stato(p.percorso);
    final e = await github.manda(p.percorso, ramo: s.ramo ?? 'principale');
    if (e.riuscito) {
      p.ultimoInvio = q;
      await registro.salva();
    }
    // ── Il messaggio dice la verità intera ──────────────────────────────
    //
    // «Mandato su GitHub.» con cinquanta modifiche non salvate è una bugia
    // per omissione: su GitHub le date restano vecchie e chi guarda non sa
    // perché. La nota c'era già, in un campo a parte che la finestra non
    // mostrava. Adesso sta DENTRO il messaggio, dove si legge.
    var messaggio = e.messaggio ?? '';
    if (e.riuscito && s.modifiche.isNotEmpty) {
      final n = s.modifiche.length;
      messaggio += ' Attenzione: ${n == 1 ? "c'è una modifica" : "ci sono $n modifiche"}'
          ' non ancora salvat${n == 1 ? "a" : "e"}, e ${n == 1 ? "quella" : "quelle"}'
          ' non ${n == 1 ? "è" : "sono"} partit${n == 1 ? "a" : "e"}: fuori va solo'
          ' quello che hai salvato. Salva, e poi «Manda adesso» di nuovo.';
    }
    return {
      'ok': e.riuscito,
      if (e.riuscito) 'messaggio': messaggio,
      if (!e.riuscito) 'errore': e.errore,
      if (e.dati != null) ...e.dati!,
      if (e.riuscito && s.modifiche.isNotEmpty)
        'nota': 'Le ${s.modifiche.length} modifiche non salvate restano qui: '
            'fuori va solo quello che hai salvato.',
    };
  }

  /// Mette via il gettone. Torna chi è, così si vede subito che funziona.
  Future<Map<String, dynamic>> gettoneGitHub(String gettone) async {
    final e = await github.salvaGettone(gettone);
    if (!e.riuscito) return _no(e.errore!);
    final chi = await github.chiSei();
    if (!chi.riuscito) {
      // Il gettone è nel portachiavi ma non vale niente: toglierlo evita di
      // ritrovarselo domani e di dare la colpa alla rete.
      await github.dimenticaGettone();
      return _no(chi.errore!);
    }
    return {'ok': true, 'chi': chi.messaggio};
  }

  /// Comincia l'accesso col device flow: torna il codice da mostrare.
  Future<Map<String, dynamic>> accediGitHub() async {
    final e = await github.iniziaAccesso();
    if (!e.riuscito) return _no(e.errore!);
    return {'ok': true, ...?e.dati};
  }

  /// Aspetta che l'utente confermi sul sito. Può durare minuti: è normale, ed
  /// è il motivo per cui chi chiama deve poter aspettare senza credersi rotto.
  Future<Map<String, dynamic>> attendiGitHub(String nostro,
      {int ogni = 5, int scadeFra = 900}) async {
    final e = await github.attendiAccesso(nostro, ogni: ogni, scadeFra: scadeFra);
    if (!e.riuscito) return _no(e.errore!);
    return {'ok': true, 'chi': e.messaggio};
  }

  Future<Map<String, dynamic>> chiSeiGitHub() async {
    final e = await github.chiSei();
    return e.riuscito
        ? {'ok': true, 'chi': e.messaggio, 'collegato': true}
        : {'ok': true, 'collegato': false, 'perche': e.errore};
  }

  Future<Map<String, dynamic>> dimenticaGitHub() async {
    final e = await github.dimenticaGettone();
    return e.riuscito ? {'ok': true} : _no(e.errore!);
  }

  /// Crea l'archivio su GitHub e lo aggiunge alle destinazioni del progetto.
  ///
  /// Due gesti in uno apposta: creare un archivio e poi non collegarlo è uno
  /// stato che non serve a nessuno, e lasciarlo possibile vuol dire lasciare a
  /// Giacomo il compito di ricordarsi il secondo passo.
  Future<Map<String, dynamic>> creaArchivioGitHub(
    String percorso,
    String nome, {
    bool privato = true,
  }) async {
    await init();
    final p = registro.cerca(percorso);
    if (p == null) return _no('Quel progetto non è nell\'elenco.');
    final e = await github.creaArchivio(nome, privato: privato);
    if (!e.riuscito) return _no(e.errore!);
    final url = e.messaggio!;
    final agg = await aggiungiDestinazione(percorso, 'github', nome, url);
    if (agg['ok'] != true) {
      return _no('L\'archivio su GitHub c\'è, ma non sono riuscito a '
          'collegarlo: ${agg['errore']}');
    }
    return {'ok': true, 'dove': url, 'progetto': (agg['progetto'])};
  }

  // ── Il registro ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> aggiungi(String cartella,
      {String? nome, String? motore}) async {
    await init();
    final e = registro.aggiungi(cartella, nome: nome, motore: motore);
    if (e.riuscito) await registro.salva();
    return e.toJson();
  }

  Future<Map<String, dynamic>> togli(String cartella) async {
    await init();
    final e = registro.togli(cartella);
    if (e.riuscito) await registro.salva();
    return {
      ...e.toJson(),
      if (e.riuscito)
        'nota': 'I punti di ritorno restano dove sono: toglierlo dall\'elenco '
            'non cancella la sua storia.',
    };
  }

  /// Cosa c'è già da adottare, senza adottarlo.
  ///
  /// Guarda nei posti dove la gente tiene i progetti e torna quello che trova,
  /// col motore suggerito accanto a ognuno. **Propone e basta**: adottarli è un
  /// clic, ignorarli è non fare niente.
  List<Map<String, dynamic>> proposte() {
    final casa = Platform.environment['HOME'] ?? '';
    final visti = {for (final p in registro.progetti) p.percorso};
    final fuori = <Map<String, dynamic>>[];
    for (final dove in ['$casa/Documenti/Progetti', '$casa/Progetti',
      '$casa/Documents/Projects', '$casa/src']) {
      for (final p in Registro.scopri(dove)) {
        if (visti.add(p.percorso)) fuori.add(p.toJson());
      }
    }
    return fuori;
  }

  static Map<String, dynamic> _no(String perche) => {
        'ok': false,
        'errore': perche,
      };
}

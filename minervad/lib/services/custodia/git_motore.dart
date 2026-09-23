import 'dart:io';

import 'segreti.dart';

/// GitMotore — i «salvataggi», cioè git senza dire mai «git».
///
/// ── Il vocabolario, che è la parte importante ──────────────────────────────
///
/// | sotto            | qui                        |
/// |------------------|----------------------------|
/// | `commit`         | **salvataggio**            |
/// | messaggio        | **«cosa hai fatto»**       |
/// | working tree     | **modifiche non salvate**  |
/// | *staging area*   | **non esiste**             |
/// | `checkout`       | **torna a…**               |
///
/// L'area di preparazione non è nascosta per semplificare: è il concetto che fa
/// scappare la gente da git, e serve solo a chi seleziona pezzi di lavoro per
/// mandarli a qualcun altro. Qui si salva sempre **tutto quello che è cambiato**
/// — `git add -A` e poi `commit`, senza eccezioni e senza scelte.
///
/// Il prezzo di questa decisione: non si possono fare due salvataggi separati
/// di due lavori intrecciati. È un prezzo che Giacomo non pagherà mai, e che
/// gli risparmia il concetto che gli avrebbe fatto chiudere il programma.
///
/// ── Perché `--porcelain=v2 -z` e mai l'uscita normale ──────────────────────
///
/// Perché `git status` normale è pensato per gli occhi: accorcia i nomi, li
/// mette fra virgolette quando contengono spazi, e cambia con la versione di
/// git e con la lingua. `-z` separa i campi con NUL, che è l'unico byte che un
/// nome di file non può contenere — la stessa ragione per cui
/// `scripts/minerva-radice elenca` usa NUL, e la stessa svista che lì era già
/// costata una riscrittura.
///
/// Una trappola che si vede solo misurando: nel record di un **rinomino** (tipo
/// `2`) il nome vecchio non sta sulla stessa riga, sta in un **campo separato**
/// subito dopo. Chi legge un record per volta si ritrova il nome vecchio come
/// se fosse un file a sé.
class GitMotore {
  GitMotore({this.esegui = _vero});

  final Future<ProcessResult> Function(List<String>, {String? dentro}) esegui;

  static Future<ProcessResult> _vero(List<String> args, {String? dentro}) {
    return Process.run(
      'git',
      args,
      // La lingua fissa: non per gli utenti — loro leggono le nostre frasi —
      // ma perché i pochi errori che traduciamo vanno riconosciuti sempre
      // uguali, anche sul computer di chi ha il sistema in tedesco.
      environment: const {'LC_ALL': 'C', 'GIT_TERMINAL_PROMPT': '0'},
      includeParentEnvironment: true,
    );
  }

  Future<ProcessResult> _git(String cartella, List<String> args) =>
      esegui(['-C', cartella, ...args]);

  // ── Questa cartella tiene una storia? ──────────────────────────────────

  Future<bool> eRepo(String cartella) async {
    final r = await _git(cartella, ['rev-parse', '--git-dir']);
    return r.exitCode == 0;
  }

  /// Ha almeno un salvataggio? Un repo appena creato non ne ha, e quasi tutti
  /// i comandi di git si comportano diversamente in quel caso.
  Future<bool> haStoria(String cartella) async {
    final r = await _git(cartella, ['rev-parse', '--verify', 'HEAD']);
    return r.exitCode == 0;
  }

  // ── Cosa è cambiato ────────────────────────────────────────────────────

  Future<StatoProgetto> stato(String cartella) async {
    if (!await eRepo(cartella)) {
      return StatoProgetto(tieneStoria: false, modifiche: const []);
    }
    final r = await _git(
      cartella,
      ['status', '--porcelain=v2', '-z', '--branch'],
    );
    if (r.exitCode != 0) {
      return StatoProgetto(
        tieneStoria: true,
        modifiche: const [],
        errore: erroreLeggibile('${r.stderr}'),
      );
    }
    return _apriLeCartelle(cartella, leggiStato('${r.stdout}'));
  }

  // ── Una cartella mai vista conta per uno, e non è vero ──────────────────
  //
  // `git status` **collassa** una cartella intera mai tracciata in una riga
  // sola, col nome che finisce per `/`:
  //
  //     ? compositore/
  //
  // È una scorciatoia sensata per chi legge `git status` in un terminale, e
  // una bugia per chi legge «1 il compositore» in una finestra: là dentro ci
  // sono sedici file e migliaia di righe. Il numero che questo programma mostra
  // deve essere il numero di cose che stanno per entrare nella storia, o non
  // serve a niente.
  //
  // Si chiede a git l'elenco vero — `ls-files --others --exclude-standard`, che
  // **rispetta il `.gitignore`**, cosa che contare i file a mano non farebbe.
  // Una chiamata sola per tutte le cartelle insieme.
  //
  // Il tetto: oltre `_troppi` file si lascia la riga collassata e la si chiama
  // per quello che è, «tutta la cartella». Enumerare una cartella da 286 GB per
  // scrivere un numero più preciso sarebbe pagare minuti per un dettaglio.
  static const int _troppi = 2000;

  Future<StatoProgetto> _apriLeCartelle(String cartella, StatoProgetto s) async {
    final cartelle = [
      for (final m in s.modifiche)
        if (m.verso == Verso.aggiunto && m.percorso.endsWith('/')) m.percorso,
    ];
    if (cartelle.isEmpty) return s;

    final r = await _git(cartella, [
      'ls-files', '--others', '--exclude-standard', '-z', '--', ...cartelle,
    ]);
    if (r.exitCode != 0) return s;

    final dentro = <String>[
      for (final f in '${r.stdout}'.split('\u0000'))
        if (f.isNotEmpty) f,
    ];
    if (dentro.length > _troppi) return s;

    final fuori = <Modifica>[
      for (final m in s.modifiche)
        if (!(m.verso == Verso.aggiunto && m.percorso.endsWith('/'))) m,
      for (final f in dentro) Modifica(percorso: f, verso: Verso.aggiunto),
    ];
    fuori.sort((a, b) => a.percorso.compareTo(b.percorso));
    return StatoProgetto(
      tieneStoria: s.tieneStoria,
      modifiche: fuori,
      ramo: s.ramo,
      daMandare: s.daMandare,
      daPrendere: s.daPrendere,
      haDestinazione: s.haDestinazione,
      errore: s.errore,
    );
  }

  /// Legge l'uscita di `status --porcelain=v2 -z --branch`.
  ///
  /// Statica e pura: si prova con testi finti, compresi quelli con dentro un
  /// nome di file che contiene una virgoletta, uno spazio o una tabulazione —
  /// che sono legali, esistono, e sono esattamente i casi in cui un parser
  /// scritto a occhio sbaglia.
  static StatoProgetto leggiStato(String grezzo) {
    final campi = grezzo.split('\u0000');
    final fuori = <Modifica>[];
    String? ramo;
    int avanti = 0, indietro = 0;
    bool haRemoto = false;

    for (var i = 0; i < campi.length; i++) {
      final c = campi[i];
      if (c.isEmpty) continue;

      if (c.startsWith('# branch.head ')) {
        ramo = c.substring(14);
        continue;
      }
      if (c.startsWith('# branch.upstream ')) {
        haRemoto = true;
        continue;
      }
      if (c.startsWith('# branch.ab ')) {
        final m = RegExp(r'\+(\d+) -(\d+)').firstMatch(c);
        if (m != null) {
          avanti = int.parse(m.group(1)!);
          indietro = int.parse(m.group(2)!);
        }
        continue;
      }
      if (c.startsWith('# ')) continue;

      if (c.startsWith('? ')) {
        fuori.add(Modifica(percorso: c.substring(2), verso: Verso.aggiunto));
        continue;
      }
      if (c.startsWith('! ')) continue; // ignorato: non ci riguarda

      if (c.startsWith('1 ')) {
        final p = _dopoCampi(c, 8);
        if (p != null) fuori.add(Modifica(percorso: p, verso: _verso(c[2], c[3])));
        continue;
      }
      if (c.startsWith('2 ')) {
        // Il nome NUOVO è in fondo a questo record; il nome VECCHIO è il campo
        // successivo, e va consumato qui o diventerebbe un file fantasma.
        final p = _dopoCampi(c, 9);
        final vecchio = (i + 1 < campi.length) ? campi[++i] : null;
        if (p != null) {
          fuori.add(Modifica(
            percorso: p,
            verso: Verso.rinominato,
            percorsoPrima: vecchio,
          ));
        }
        continue;
      }
      if (c.startsWith('u ')) {
        final p = _dopoCampi(c, 10);
        if (p != null) {
          fuori.add(Modifica(percorso: p, verso: Verso.inConflitto));
        }
        continue;
      }
    }

    fuori.sort((a, b) => a.percorso.compareTo(b.percorso));
    return StatoProgetto(
      tieneStoria: true,
      modifiche: fuori,
      ramo: ramo,
      daMandare: avanti,
      daPrendere: indietro,
      haDestinazione: haRemoto,
    );
  }

  /// Salta `quanti` campi separati da spazio e torna tutto il resto.
  ///
  /// Il resto è il **nome del file**, e non si divide oltre: un nome di file
  /// può contenere spazi, e contarli sarebbe l'errore.
  static String? _dopoCampi(String riga, int quanti) {
    var i = 0;
    for (var n = 0; n < quanti; n++) {
      i = riga.indexOf(' ', i);
      if (i < 0) return null;
      i++;
    }
    return i < riga.length ? riga.substring(i) : null;
  }

  static Verso _verso(String x, String y) {
    // Si salva sempre tutto, quindi non interessa se il cambiamento è già
    // preparato o no: interessa **cosa** è successo al file.
    for (final c in [x, y]) {
      if (c == 'A') return Verso.aggiunto;
      if (c == 'D') return Verso.tolto;
      if (c == 'R') return Verso.rinominato;
    }
    return Verso.modificato;
  }

  // ── Raggruppare per significato ────────────────────────────────────────
  //
  // «14 file nella scrivania, 3 nel demone, 2 nei documenti» dice a Giacomo
  // cosa ha fatto stamattina. Un elenco di 110 percorsi non gli dice niente:
  // è il motivo per cui non guarda mai `git status`.
  //
  // La tabella è **dati**, non logica, e si allunga senza toccare il codice.
  // Quello che non riconosce prende il nome della sua prima cartella, che è
  // sempre meglio del percorso intero e non mente mai.

  static const Map<String, String> nomiNoti = {
    'minerva-shell': 'la scrivania',
    'minervad': 'il demone',
    'compositore': 'il compositore',
    'plugins': 'i plugin',
    'scripts': 'gli script',
    'config': 'la configurazione',
    'desktop': 'le voci di menù',
    'assets': 'le immagini e i suoni',
    'test': 'le prove',
    'lib': 'il codice',
    'src': 'il codice',
    'doc': 'i documenti',
    'docs': 'i documenti',
    '.attic': 'la roba archiviata',
  };

  static List<Gruppo> raggruppa(List<Modifica> modifiche) {
    final per = <String, List<Modifica>>{};
    for (final m in modifiche) {
      per.putIfAbsent(_area(m.percorso), () => []).add(m);
    }
    final fuori = [
      for (final e in per.entries) Gruppo(nome: e.key, modifiche: e.value),
    ];
    // Prima chi è cambiato di più: è l'ordine in cui uno racconta la giornata.
    fuori.sort((a, b) {
      final d = b.modifiche.length.compareTo(a.modifiche.length);
      return d != 0 ? d : a.nome.compareTo(b.nome);
    });
    return fuori;
  }

  static String _area(String percorso) {
    final i = percorso.indexOf('/');
    if (i < 0) {
      return percorso.toLowerCase().endsWith('.md')
          ? 'i documenti'
          : 'la cartella principale';
    }
    final primo = percorso.substring(0, i);
    return nomiNoti[primo.toLowerCase()] ?? primo;
  }

  // ── Cominciare a tenere la storia ──────────────────────────────────────

  /// `git init` e un `.gitignore` scritto guardando cosa c'è davvero dentro.
  ///
  /// Il `.gitignore` non è una cortesia: senza, il primo invio a GitHub
  /// fallisce su un file da 300 MB con un messaggio che nessuno capisce, e a
  /// quel punto quel file è **già nella storia per sempre** — toglierlo vuol
  /// dire riscrivere tutti i salvataggi. È l'unico momento in cui si può
  /// evitare a costo zero.
  Future<EsitoGit> inizia(String cartella, {String ramo = 'principale'}) async {
    if (await eRepo(cartella)) {
      return EsitoGit.no('Questa cartella tiene già la sua storia.');
    }
    final r = await _git(cartella, ['init', '-b', ramo]);
    if (r.exitCode != 0) return EsitoGit.no(erroreLeggibile('${r.stderr}'));

    final f = File('$cartella/.gitignore');
    if (!await f.exists()) {
      await f.writeAsString(gitignorePer(cartella));
    }
    return EsitoGit.si('Da adesso tengo la storia di questa cartella.');
  }

  /// Le regole da ignorare, dedotte da cosa c'è nella cartella.
  static String gitignorePer(String cartella) {
    final righe = <String>[
      '# Scritto dalla Custodia di Minerva guardando cosa c\'è in questa',
      '# cartella. Puoi cambiarlo: da qui in poi comanda questo file.',
      '',
    ];
    final regole = <String, List<String>>{
      'node_modules': ['node_modules/'],
      '__pycache__': ['__pycache__/', '*.pyc'],
      'build': ['build/'],
      '.dart_tool': ['.dart_tool/'],
      'target': ['target/'],
      '.venv': ['.venv/', 'venv/'],
      '.cache': ['.cache/'],
      'dist': ['dist/'],
    };
    final trovate = <String>[];
    final grossi = <String>[];
    try {
      for (final e in Directory(cartella).listSync(followLinks: false)) {
        final nome = e.path.split('/').last;
        if (e is Directory && regole.containsKey(nome)) {
          trovate.addAll(regole[nome]!);
        }
        if (e is File) {
          try {
            if (e.lengthSync() > 100 * 1024 * 1024) grossi.add(nome);
          } catch (_) {}
        }
      }
    } catch (_) {}

    if (trovate.isNotEmpty) {
      righe.add('# Roba che si ricostruisce da sola');
      righe.addAll(trovate.toSet());
      righe.add('');
    }
    if (grossi.isNotEmpty) {
      righe.add('# Oltre i 100 MB: GitHub li rifiuta, e una volta salvati');
      righe.add('# resterebbero nella storia per sempre.');
      for (final g in grossi) {
        righe.add(g.replaceAll(RegExp(r'([*?\[\]!#])'), r'\$1'));
      }
      righe.add('');
    }
    righe.addAll(['# Roba di sistema', '.DS_Store', '*.swp', '*~', '']);
    return righe.join('\n');
  }

  // ── Salvare ────────────────────────────────────────────────────────────

  static const int limiteGitHub = 100 * 1024 * 1024;

  /// Salva tutto quello che è cambiato.
  ///
  /// Rifiuta se fra le modifiche c'è un file oltre i 100 MB, a meno che non gli
  /// si dica `forza`. Il rifiuto è qui e non al momento dell'invio per una
  /// ragione sola: **dopo il salvataggio è troppo tardi.** Un file entrato
  /// nella storia ci resta anche se lo si cancella, e per toglierlo davvero
  /// bisogna riscrivere ogni salvataggio successivo.
  Future<EsitoGit> salva(
    String cartella,
    String messaggio, {
    bool forza = false,
  }) async {
    final m = messaggio.trim();
    if (m.isEmpty) {
      return EsitoGit.no('Scrivi cosa hai fatto: servirà a te, fra un mese.');
    }
    if (!await eRepo(cartella)) {
      return EsitoGit.no('Questa cartella non tiene ancora la sua storia.');
    }

    final s = await stato(cartella);
    if (s.modifiche.isEmpty) {
      return EsitoGit.no('Non è cambiato niente da salvare.');
    }
    if (!forza) {
      // ── I segreti, prima del salvataggio ────────────────────────────
      //
      // Qui e non prima dell'invio: dopo il salvataggio è irreparabile. Una
      // chiave entrata nella storia ci resta anche se la si cancella subito,
      // e per toglierla davvero bisogna riscrivere ogni salvataggio
      // successivo — cioè fare a mano la cosa più difficile di git,
      // esattamente quando si è nel panico.
      final trovati = await const Segreti().guarda(
        cartella,
        [for (final m in s.modifiche) if (m.verso != Verso.tolto) m.percorso],
      );
      if (trovati.isNotEmpty) {
        final primo = trovati.first;
        return EsitoGit.no(
          'Fermo: «${primo.percorso}» ${primo.perche}'
          '${trovati.length > 1 ? " (e altri ${trovati.length - 1} così)" : ""}. '
          'Una chiave salvata resta nella storia per sempre, anche se la '
          'cancelli dopo. Aggiungila a quelle da ignorare, oppure dimmi che '
          'non è un segreto e la salvo.',
          segreti: [for (final t in trovati) t.toJson()],
        );
      }

      final grossi = <String>[];
      for (final mod in s.modifiche) {
        if (mod.verso == Verso.tolto) continue;
        try {
          final f = File('$cartella/${mod.percorso}');
          if (f.existsSync() && f.lengthSync() > limiteGitHub) {
            grossi.add(mod.percorso);
          }
        } catch (_) {}
      }
      if (grossi.isNotEmpty) {
        return EsitoGit.no(
          'C\'è un file troppo grosso da salvare: ${grossi.first}'
          '${grossi.length > 1 ? " (e altri ${grossi.length - 1})" : ""}. '
          'Oltre i 100 MB GitHub lo rifiuta, e una volta salvato resterebbe '
          'nella storia per sempre. Aggiungilo a quelli da ignorare, oppure '
          'dimmi di salvarlo lo stesso.',
          grossi: grossi,
        );
      }
    }

    final a = await _git(cartella, ['add', '-A', '--', '.']);
    if (a.exitCode != 0) return EsitoGit.no(erroreLeggibile('${a.stderr}'));

    final c = await _git(cartella, ['commit', '-m', m]);
    if (c.exitCode != 0) return EsitoGit.no(erroreLeggibile('${c.stderr}'));

    return EsitoGit.si('Salvato: $m');
  }

  // ── Guardare indietro ──────────────────────────────────────────────────

  /// Gli ultimi salvataggi. Il separatore è un NUL, per lo stesso motivo di
  /// prima: un messaggio scritto da una persona può contenere qualsiasi cosa,
  /// a-capo compresi.
  Future<List<Salvataggio>> storia(String cartella, {int quanti = 50}) async {
    if (!await haStoria(cartella)) return const [];
    final r = await _git(cartella, [
      'log',
      '-n',
      '$quanti',
      '--format=%H%x1f%at%x1f%an%x1f%s',
      '-z',
    ]);
    if (r.exitCode != 0) return const [];
    final fuori = <Salvataggio>[];
    for (final rec in '${r.stdout}'.split('\u0000')) {
      if (rec.trim().isEmpty) continue;
      final p = rec.split('\u001f');
      if (p.length < 4) continue;
      final t = int.tryParse(p[1]);
      if (t == null) continue;
      fuori.add(Salvataggio(
        id: p[0],
        quando: DateTime.fromMillisecondsSinceEpoch(t * 1000),
        chi: p[2],
        cosa: p[3],
      ));
    }
    return fuori;
  }

  /// Riporta la cartella a com'era a un salvataggio.
  ///
  /// **Non si chiama mai direttamente**: passa da `CustodiaService`, che prima
  /// prende un punto di ritorno. Un `reset --hard` butta via tutto quello che
  /// non è salvato, e chi preme «torna a…» non sta chiedendo *anche* quello.
  Future<EsitoGit> tornaA(String cartella, String id) async {
    if (!RegExp(r'^[0-9a-f]{7,40}$').hasMatch(id)) {
      return EsitoGit.no('«$id» non è un salvataggio.');
    }
    final v = await _git(cartella, ['cat-file', '-e', '$id^{commit}']);
    if (v.exitCode != 0) return EsitoGit.no('Quel salvataggio non esiste.');

    final r = await _git(cartella, ['reset', '--hard', id]);
    if (r.exitCode != 0) return EsitoGit.no(erroreLeggibile('${r.stderr}'));
    return EsitoGit.si('Tornato al salvataggio $id.');
  }

  // ── Chi firma ──────────────────────────────────────────────────────────

  /// Nome ed email con cui si firmano i salvataggi.
  ///
  /// Serve saperlo prima e non dopo: senza, `commit` fallisce con «Please tell
  /// me who you are», che è un messaggio in inglese in mezzo a un programma
  /// italiano. E un indirizzo finto tipo `@example.com` non è un guasto adesso
  /// ma lo diventa al primo invio: GitHub non riconosce l'autore, e i
  /// salvataggi risultano di nessuno.
  Future<Firma> firma(String cartella) async {
    final n = await _git(cartella, ['config', '--get', 'user.name']);
    final e = await _git(cartella, ['config', '--get', 'user.email']);
    final nome = '${n.stdout}'.trim();
    final mail = '${e.stdout}'.trim();
    return Firma(
      nome: nome,
      email: mail,
      completa: nome.isNotEmpty && mail.isNotEmpty,
      credibile: mail.isNotEmpty &&
          !mail.endsWith('example.com') &&
          !mail.endsWith('.local') &&
          mail.contains('@'),
    );
  }

  // ── Gli errori, in italiano ────────────────────────────────────────────

  static String erroreLeggibile(String grezzo) {
    final g = grezzo.toLowerCase();
    if (g.contains('please tell me who you are') ||
        g.contains('empty ident name')) {
      return 'Prima dimmi come firmare i salvataggi: manca il tuo nome o la '
          'tua email.';
    }
    if (g.contains('not a git repository')) {
      return 'Questa cartella non tiene la sua storia.';
    }
    if (g.contains('nothing to commit')) {
      return 'Non è cambiato niente da salvare.';
    }
    if (g.contains('permission denied')) {
      return 'Non ho il permesso di scrivere in questa cartella.';
    }
    if (g.contains('no space left')) {
      return 'Il disco è pieno.';
    }
    if (g.contains('index.lock')) {
      return 'Sta già lavorando su questa cartella qualcun altro: aspetta un '
          'momento e riprova.';
    }
    if (g.contains('could not resolve host') || g.contains('network')) {
      return 'Non riesco a raggiungere internet.';
    }
    if (g.contains('authentication failed') || g.contains('permission to')) {
      return 'Non mi hanno riconosciuto: controlla il collegamento a GitHub.';
    }
    final riga = grezzo
        .trim()
        .split('\n')
        .where((r) => r.trim().isNotEmpty)
        .toList();
    return riga.isEmpty ? 'Non è riuscito.' : riga.first;
  }
}

// ── I sostantivi ─────────────────────────────────────────────────────────

enum Verso { aggiunto, modificato, tolto, rinominato, inConflitto }

extension VersoItaliano on Verso {
  String get parola => switch (this) {
        Verso.aggiunto => 'aggiunto',
        Verso.modificato => 'cambiato',
        Verso.tolto => 'tolto',
        Verso.rinominato => 'rinominato',
        Verso.inConflitto => 'in conflitto',
      };
}

class Modifica {
  const Modifica({
    required this.percorso,
    required this.verso,
    this.percorsoPrima,
  });

  final String percorso;
  final Verso verso;
  final String? percorsoPrima;

  Map<String, dynamic> toJson() => {
        'percorso': percorso,
        'verso': verso.name,
        'parola': verso.parola,
        if (percorsoPrima != null) 'prima': percorsoPrima,
      };
}

class Gruppo {
  const Gruppo({required this.nome, required this.modifiche});

  final String nome;
  final List<Modifica> modifiche;

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'quante': modifiche.length,
        'modifiche': [for (final m in modifiche) m.toJson()],
      };
}

class StatoProgetto {
  const StatoProgetto({
    required this.tieneStoria,
    required this.modifiche,
    this.ramo,
    this.daMandare = 0,
    this.daPrendere = 0,
    this.haDestinazione = false,
    this.errore,
  });

  final bool tieneStoria;
  final List<Modifica> modifiche;
  final String? ramo;
  final int daMandare;
  final int daPrendere;
  final bool haDestinazione;
  final String? errore;

  bool get pulito => modifiche.isEmpty;

  Map<String, dynamic> toJson() => {
        'tieneStoria': tieneStoria,
        'quante': modifiche.length,
        'gruppi': [for (final g in GitMotore.raggruppa(modifiche)) g.toJson()],
        if (ramo != null) 'ramo': ramo,
        'daMandare': daMandare,
        'daPrendere': daPrendere,
        'haDestinazione': haDestinazione,
        if (errore != null) 'errore': errore,
      };
}

class Salvataggio {
  const Salvataggio({
    required this.id,
    required this.quando,
    required this.chi,
    required this.cosa,
  });

  final String id;
  final DateTime quando;
  final String chi;
  final String cosa;

  Map<String, dynamic> toJson() => {
        'id': id,
        'breve': id.length > 8 ? id.substring(0, 8) : id,
        'quando': quando.toIso8601String(),
        'chi': chi,
        'cosa': cosa,
      };
}

class Firma {
  const Firma({
    required this.nome,
    required this.email,
    required this.completa,
    required this.credibile,
  });

  final String nome;
  final String email;
  final bool completa;
  final bool credibile;

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'email': email,
        'completa': completa,
        'credibile': credibile,
      };
}

class EsitoGit {
  const EsitoGit.si(this.messaggio)
      : riuscito = true,
        errore = null,
        grossi = const [],
        segreti = const [];
  const EsitoGit.no(this.errore,
      {this.grossi = const [], this.segreti = const []})
      : riuscito = false,
        messaggio = null;

  final bool riuscito;
  final String? messaggio;
  final String? errore;

  /// I file troppo grossi, quando è per quello che ha rifiutato: servono a
  /// offrire «aggiungili a quelli da ignorare» senza farli riscrivere a mano.
  final List<String> grossi;

  /// Quello che sembra un segreto, con scritto **perché** lo sembra. Il perché
  /// non è cortesia: è quello che permette a chi legge di decidere in un
  /// secondo se è un falso allarme, invece di premere «salvalo lo stesso» per
  /// abitudine.
  final List<Map<String, dynamic>> segreti;

  Map<String, dynamic> toJson() => {
        'ok': riuscito,
        if (messaggio != null) 'messaggio': messaggio,
        if (errore != null) 'errore': errore,
        if (grossi.isNotEmpty) 'grossi': grossi,
        if (segreti.isNotEmpty) 'segreti': segreti,
      };
}

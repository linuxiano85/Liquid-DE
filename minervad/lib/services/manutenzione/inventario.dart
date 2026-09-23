import 'dart:io';

/// Una voce dell'inventario: una cosa che occupa posto, con tutto quello che
/// serve per decidere se toglierla.
class Voce {
  /// Come la chiama il programma. Non cambia mai, nemmeno cambiando lingua:
  /// è la parola che il giorno che si potrà cancellare arriverà all'aiutante
  /// di root, e un identificatore tradotto è un comando che smette di
  /// funzionare quando qualcuno passa all'inglese.
  final String id;

  /// Come si chiama per chi guarda.
  final String nome;

  /// ── A che famiglia appartiene ────────────────────────────────────────
  ///
  /// Serve alla finestra per raggrupparle e per il grafico, ma soprattutto
  /// serve a chi guarda: «4 GB di cache» e «4 GB di roba di sviluppo» sono
  /// due frasi che portano a due decisioni diverse.
  ///
  /// Le famiglie, e perché sono queste:
  ///
  ///   `cache`        i programmi la rifanno da soli usandoli
  ///   `sviluppo`     la rifà il compilatore, ma costa TEMPO: buttare
  ///                  `ccache` vuol dire la prossima compilazione lenta
  ///   `miniature`    le anteprime delle immagini
  ///   `temporanei`   file di lavoro rimasti per terra
  ///   `cestino`      l'hai buttato tu, e sta lì apposta
  ///   `registri`     servono a capire cosa è successo quando qualcosa va storto
  ///   `lingue`       traduzioni che non leggerai mai
  ///   `pacchetti`    i pacchetti già installati, per tornare indietro
  final String categoria;

  /// Dove sta, per esteso. Si mostra sempre: «cache» non vuol dire niente,
  /// `/home/giacomo/.cache/ccache` sì.
  final String dove;

  final int byte;

  /// Quanti file o quante voci. Zero quando non ha senso contarli.
  final int quante;

  /// ── Il campo che rende onesto tutto il resto ─────────────────────────
  ///
  /// Cosa succede DOPO averla tolta, e sono **tre** cose diverse:
  ///
  ///   `sola`    torna da sé quando serve: la cache di un browser torna
  ///             navigando, le miniature riaprendo una cartella. È il caso
  ///             normale, e infatti non merita nemmeno un'etichetta.
  ///   `mai`     tolta è tolta. Il cestino.
  ///   `sempre`  torna **anche se non vuoi**, ed è il caso delle lingue: al
  ///             primo aggiornamento pacman le rimette tutte.
  ///
  /// Erano due — un `siRifa` vero o falso — e le lingue finivano fra le
  /// «non tornano», cioè l'esatto contrario della verità: la finestra ci
  /// scriveva accanto «non torna» mentre l'avvertimento sotto diceva che
  /// tornano tutte. Un cartellino che contraddice la riga sotto è peggio di
  /// nessun cartellino.
  ///
  /// Un programma di pulizia che non distingue questi tre casi è un
  /// programma di cui non ci si può fidare al secondo clic.
  final String torna;

  /// Vero se per toglierla serve la password di amministratore.
  final bool vuoleLaPassword;

  /// Vero quando il conto è un MINIMO e non un totale: `du` non ha potuto
  /// leggere tutto — un permesso negato, una cartella sparita mentre
  /// guardavamo — e quello che c'è dentro pesa almeno così.
  ///
  /// Serve perché il numero, senza, sarebbe una bugia piccola e credibile: chi
  /// legge «6,5 GB» pensa che siano tutti, e non ha modo di sospettare che ce
  /// ne siano di più.
  final bool parziale;

  /// Detta a chi guarda quando c'è qualcosa che i megabyte non dicono.
  /// Vuota quasi sempre: una nota su ogni riga è una nota che non si legge.
  final String avvertenza;

  const Voce({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.dove,
    required this.byte,
    this.quante = 0,
    this.torna = 'sola',
    this.vuoleLaPassword = false,
    this.parziale = false,
    this.avvertenza = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'categoria': categoria,
        'dove': dove,
        'byte': byte,
        'quante': quante,
        'torna': torna,
        'vuoleLaPassword': vuoleLaPassword,
        if (parziale) 'parziale': true,
        if (avvertenza.isNotEmpty) 'avvertenza': avvertenza,
      };
}

/// L'inventario di quello che si può togliere da questo computer.
///
/// ── Perché esiste, e perché NON cancella niente ────────────────────────────
///
/// Giacomo, 8 settembre 2026, chiedendo un'app di manutenzione: «tipo Stacer»,
/// che è abbandonato. Stacer è un cruscotto con tre cerchi grandi e un pulsante
/// che «ottimizza».
///
/// Questo file è l'opposto: **guarda e basta**. Misurato su quella macchina, i
/// numeri dicono perché serve — sedici gigabyte sparsi in sei posti diversi,
/// che per conoscerli oggi servono sei comandi da sapere a memoria. E il disco
/// è da 950 GB con 617 liberi: non c'è nessuna emergenza da risolvere, c'è una
/// cosa da **sapere**.
///
/// Cancellare è un mestiere diverso e sta altrove: `scripts/minerva-radice`,
/// che ha un elenco chiuso di verbi. Qui dentro non c'è una sola chiamata che
/// tolga qualcosa, e non deve entrarci: il giorno che un programma di pulizia
/// cancella una cosa che serviva, non lo riapri più.
///
/// ── Perché `du` e non un giro nostro sulle cartelle ────────────────────────
///
/// Perché `~/.cache` sono decine di migliaia di file, e percorrerli in Dart
/// vuol dire tenere fermo il demone — cioè tutta la scrivania — per tutto il
/// tempo. È lo stesso difetto misurato il 7 settembre sul ciclo di `/proc`, e
/// la cura là è stata cedere il filo ogni tanto.
///
/// Qui la cura è migliore: `du` è un programma a sé, gira nel suo processo, e
/// `Process.run` lo aspetta senza bloccare niente. Il conto lo fa lui, che è
/// scritto in C e lo fa da trent'anni.
class Inventario {
  Inventario({
    Future<ProcessResult> Function(String, List<String>)? esegui,
    String? casa,
    this.racconta,
  })  : _esegui = esegui ?? _eseguiVero,
        _casa = casa ?? (Platform.environment['HOME'] ?? '/root');

  // ── Raccontare mentre si lavora ──────────────────────────────────────────
  //
  // Giacomo, 8 settembre 2026: «mettiamoci barre di progresso e live log».
  //
  // La scansione dura fra mezzo secondo e qualche secondo — `du` su
  // `~/.cache` sono decine di migliaia di file, e su `/var/cache/pacman/pkg`
  // altre migliaia — e per tutto quel tempo, senza questo, la finestra non ha
  // niente da dire. Una rotella che gira è una promessa senza contenuto: dice
  // «aspetta» e non dice **cosa** stia succedendo né se stia procedendo.
  //
  // E c'è la ragione seria, che vale più dell'attesa: il giorno che questa
  // roba si CANCELLA, il racconto è l'unica prova di cosa è stato toccato. Un
  // programma che cancella in silenzio e poi dice «fatto» chiede una fiducia
  // che non si è guadagnato. Quindi il racconto nasce adesso, con l'inventario
  // che non tocca niente, e resta lo stesso identico canale dopo.
  //
  // `fatte`/`quante` fanno la barra, `testo` fa la riga di registro. Chi non
  // passa niente non paga niente: senza ascoltatori è un puntatore nullo.
  final void Function(String fase, String testo, int fatte, int quante)?
      racconta;

  /// Quante tappe ha una scansione intera. È il fondoscala della barra, e sta
  /// qui e non nella finestra: chi aggiunge una tappa senza toccare questo
  /// numero fa una barra che arriva al 120%.
  static const int passiInTutto = 5;

  void _di(String fase, String testo, int fatte) =>
      racconta?.call(fase, testo, fatte, passiInTutto);

  /// Sostituibile per le prove: una prova che chiama `du` e `pacman` veri
  /// misurerebbe la macchina di chi la lancia, e cambierebbe risposta ogni
  /// giorno. Vedi la stessa scelta in `custodia/github_motore.dart`.
  final Future<ProcessResult> Function(String, List<String>) _esegui;
  final String _casa;

  static Future<ProcessResult> _eseguiVero(String c, List<String> a) =>
      Process.run(c, a);

  /// Quanto pesa un percorso, in byte. `-1` se non si può sapere.
  ///
  /// ── `du -s --block-size=1`, e NON `du -sb` ────────────────────────────
  ///
  /// I byte si sommano, «1,6G» no: quindi niente `-h`. Ma per un pezzo
  /// questo file ha usato `-sb`, con accanto un commento che diceva
  /// «`--apparent-size` no di proposito, quello che interessa è quanto DISCO
  /// si libera». Il commento diceva la cosa giusta e il codice faceva
  /// l'opposto: `-b` **è** `--apparent-size`.
  ///
  /// Non è pignoleria. Il registro di systemd è fatto di file bucati — file
  /// che dichiarano 118 MB e sul disco ne occupano 46 — e la finestra
  /// prometteva di liberarne 118. Misurato il 9 settembre 2026:
  ///
  ///     /var/log/journal        apparente 118 MB   sul disco  46 MB
  ///     /var/cache/pacman/pkg   apparente 6,84 GB  sul disco 6,85 GB
  ///     ~/.cache/ccache         apparente 1,63 GB  sul disco 1,66 GB
  ///
  /// Nelle altre due il disco è di poco più GRANDE — sono migliaia di file
  /// piccoli, e ognuno arrotonda al blocco. Anche quello è giusto saperlo:
  /// è lo spazio che torna davvero.
  /// ── Perché non si guarda l'esito di `du` ──────────────────────────────
  ///
  /// Perché `du` esce con **1** appena una sola sottocartella non è leggibile,
  /// e intanto stampa il totale giusto di tutto il resto. Su questa macchina
  /// `/var/cache/pacman/pkg` contiene due cartelle `download-…` di root: `du`
  /// diceva 6,5 GB ed esci va 1, e la prima versione di questo file buttava
  /// via la risposta. Risultato: la voce più grossa dell'inventario — 6,5 GB —
  /// **non compariva affatto**, e il totale diceva 9,8 invece di 16.
  ///
  /// Quindi si legge il numero, e se qualcosa non si è potuto leggere lo si
  /// **dice**: `parziale` vuol dire «almeno questo».
  Future<({int byte, bool parziale})> _peso(String percorso) async {
    try {
      final r = await _esegui('du', ['-s', '--block-size=1', percorso]);
      final primo = '${r.stdout}'.split(RegExp(r'\s')).first;
      final byte = int.tryParse(primo);
      if (byte == null) return (byte: -1, parziale: false);
      return (byte: byte, parziale: r.exitCode != 0);
    } catch (_) {
      return (byte: -1, parziale: false);
    }
  }


  // ── La tua cache, voce per voce ──────────────────────────────────────────
  //
  // Voce per voce e non in blocco, ed è una scelta e non un vezzo: su questa
  // macchina i 9,7 GB sono quasi tutti in cinque cartelle (Shelly 4,0, Chrome
  // 1,6, ccache 1,6, uv 1,1, debuginfod 0,5), e le due cose non sono uguali.
  // Buttare `ccache` vuol dire che la prossima compilazione di Minerva è
  // lenta; buttare `debuginfod_client` non lo nota nessuno. Chi guarda deve
  // poterlo scegliere, e per sceglierlo deve vederlo.
  /// Le cache che le rifà un compilatore, non l'uso.
  ///
  /// La differenza conta: `~/.cache/mozilla` torna navigando e non se ne
  /// accorge nessuno; `~/.cache/ccache` torna ricompilando, e la prossima
  /// compilazione di Minerva passa da quaranta secondi a dieci minuti. Sono
  /// due gigabyte che pesano uguale sul disco e in modo diversissimo su di te.
  static const Set<String> _diSviluppo = {
    'ccache', 'sccache', 'go-build', 'uv', 'pip', 'cargo', 'npm', 'yarn',
    'pnpm', 'electron-builder', 'ms-playwright-go', 'ms-playwright',
    'gradle', 'maven', 'pub', 'nuget', 'composer', 'bazel', 'zig',
  };

  Future<List<Voce>> cachePersonale({int soglia = 10 * 1024 * 1024}) async {
    final radice = '$_casa/.cache';
    if (!await Directory(radice).exists()) return const [];
    final fuori = <Voce>[];
    try {
      final r = await _esegui(
          'du', ['-s', '--block-size=1', '--', ...await _figli(radice)]);
      for (final riga in '${r.stdout}'.split('\n')) {
        if (riga.trim().isEmpty) continue;
        final t = riga.split(RegExp(r'\t'));
        if (t.length < 2) continue;
        final byte = int.tryParse(t[0].trim()) ?? 0;
        if (byte < soglia) continue; // sotto i dieci mega non è una voce
        final dove = t[1].trim();
        // Le miniature hanno una voce loro, con un nome che si capisce.
        // Senza questa riga comparivano DUE volte — una qui come
        // «thumbnails» e una là come «Miniature» — e il totale le contava
        // tutte e due. Un inventario che somma la stessa cosa due volte è
        // peggio di uno che non la mostra.
        if (dove.endsWith('/thumbnails')) continue;
        final nome = dove.split('/').last;
        final sviluppo = _diSviluppo.contains(nome);
        fuori.add(Voce(
          id: 'cache:$nome',
          nome: nome,
          categoria: sviluppo ? 'sviluppo' : 'cache',
          dove: dove,
          byte: byte,
          avvertenza: sviluppo
              ? 'La rifà il compilatore, ma ci mette tempo: la prossima '
                  'compilazione sarà lenta.'
              : '',
        ));
      }
    } catch (_) {
      return const [];
    }
    fuori.sort((a, b) => b.byte.compareTo(a.byte));
    return fuori;
  }

  Future<List<String>> _figli(String radice,
      {bool soloCartelle = false}) async {
    final fuori = <String>[];
    await for (final v in Directory(radice).list(followLinks: false)) {
      if (soloCartelle && v is! Directory) continue;
      fuori.add(v.path);
    }
    return fuori;
  }

  // ── Le lingue ────────────────────────────────────────────────────────────
  //
  // Il caso più delicato dell'inventario, e l'unico che ha bisogno di una
  // frase invece che di un numero: cancellarle NON funziona. Al primo
  // aggiornamento di un pacchetto tornano tutte, perché è pacman a
  // rimetterle. È la ragione per cui esiste `localepurge`, ed è la ragione per
  // cui un programma che le cancella e basta mente a chi lo usa.
  //
  // La cura che dura è una riga in `/etc/pacman.conf` che dice a pacman di non
  // installarle proprio. Qui si guarda solo se quella riga c'è già.
  Future<Voce?> lingue({List<String> tenere = const ['it', 'en', 'C']}) async {
    const radice = '/usr/share/locale';
    if (!await Directory(radice).exists()) return null;
    var byte = 0, quante = 0;
    try {
      // Solo le CARTELLE: `locale.alias` è un file di gettext e non una
      // lingua, e contandolo la voce compariva a zero megabyte — una riga
      // vera e inutile, che si spunta e si preme per niente.
      final figli = await _figli(radice, soloCartelle: true);
      if (figli.isEmpty) return null;
      final r =
          await _esegui('du', ['-s', '--block-size=1', '--', ...figli]);
      for (final riga in '${r.stdout}'.split('\n')) {
        if (riga.trim().isEmpty) continue;
        final t = riga.split(RegExp(r'\t'));
        if (t.length < 2) continue;
        final nome = t[1].trim().split('/').last;
        // «it», «it_IT», «it_IT@euro»: si guarda il pezzo prima del segno.
        final ceppo = nome.split(RegExp(r'[_.@]')).first;
        if (tenere.contains(ceppo) || tenere.contains(nome)) continue;
        byte += int.tryParse(t[0].trim()) ?? 0;
        quante++;
      }
    } catch (_) {
      return null;
    }
    // Sotto i dieci mega non è una voce, è una briciola: la stessa soglia di
    // tutto il resto dell'inventario.
    if (quante == 0 || byte < _briciola) return null;
    return Voce(
      id: 'lingue',
      nome: 'Lingue che non usi',
      categoria: 'lingue',
      dove: radice,
      byte: byte,
      quante: quante,
      torna: 'sempre',
      vuoleLaPassword: true,
      avvertenza: await _pacmanNonEstraeLingue()
          ? 'L\'inglese e la lingua che usi restano sempre. Pacman è già '
              'impostato per non reinstallare le altre.'
          : 'L\'inglese e la lingua che usi restano sempre. E cancellarle non '
              'basta: al primo aggiornamento tornano tutte, quindi va detto a '
              'pacman di non installarle più — si fa insieme.',
    );
  }

  /// C'è già la riga che impedisce a pacman di rimettere le lingue?
  ///
  /// ── Lo si chiede a pacman, invece di leggergli il file ────────────────
  ///
  /// `pacman-conf NoExtract` stampa la configurazione **come pacman la
  /// legge**, sezioni comprese. Prima questa funzione apriva
  /// `/etc/pacman.conf` e cercava la riga da sé, e per farlo doveva sapere
  /// che `NoExtract` vale solo dentro `[options]` — cioè rifare a mano un
  /// pezzo del mestiere di pacman.
  ///
  /// Rifacendolo l'ha sbagliato: il 9 settembre 2026 la riga era finita in
  /// fondo al file, dentro `[multilib]`, e questa funzione rispondeva «è già
  /// a posto» mentre le lingue sarebbero tornate tutte al primo
  /// aggiornamento. Chiedere a chi sa costa una riga in meno e non può
  /// sbagliare.
  ///
  /// Se `pacman-conf` non c'è si torna a leggere il file, ma sapendo che è
  /// un ripiego: e allora almeno si guarda dentro quale sezione sta.
  Future<bool> _pacmanNonEstraeLingue() async {
    try {
      final r = await _esegui('pacman-conf', ['NoExtract']);
      if (r.exitCode == 0) {
        return '${r.stdout}'
            .split('\n')
            .any((riga) => riga.trim().startsWith('usr/share/locale'));
      }
    } catch (_) {
      // `pacman-conf` non c'è: si prova a mano.
    }
    try {
      final righe =
          (await File('/etc/pacman.conf').readAsString()).split('\n');
      var dentroOptions = false;
      for (final riga in righe) {
        final pulita = riga.trim();
        if (pulita.startsWith('[')) {
          dentroOptions = pulita == '[options]';
          continue;
        }
        if (!dentroOptions) continue;
        if (RegExp(r'^\s*NoExtract\s*=.*usr/share/locale').hasMatch(riga)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── La cache dei pacchetti ───────────────────────────────────────────────
  //
  // 6,5 GB e 1771 file su questa macchina. Si rifà da sola riscaricando, ma
  // non del tutto: le versioni vecchie servono a tornare indietro quando un
  // aggiornamento rompe qualcosa, ed è per questo che si toglie con
  // `paccache` — che ne tiene le ultime — e non con un `rm`.
  Future<Voce?> cachePacchetti() async {
    const dove = '/var/cache/pacman/pkg';
    if (!await Directory(dove).exists()) return null;
    final p = await _peso(dove);
    if (p.byte <= 0) return null;

    // ── Quanto si può togliere NON è quanto pesa la cartella ────────────
    //
    // Giacomo, 9 settembre 2026, dopo aver premuto: «perché non è scomparsa
    // dalle voci?». Il pulsante prometteva 6,97 GB e ne sono usciti 130.
    //
    // Perché `paccache` tiene le ultime due versioni di ogni pacchetto, e su
    // una macchina aggiornata quasi ogni pacchetto ne ha una sola: quello che
    // si può togliere è la piccola parte in più, non tutto. Il numero grande
    // era vero come misura della cartella e falso come promessa — ed è la
    // prima cosa che questo programma si è messo per iscritto di non fare.
    //
    // Adesso il numero è quello che `paccache` dice che toglierebbe, chiesto
    // a lui con la prova a vuoto. Chi sa fare il conto è lui: noi non
    // possiamo indovinare quante versioni ha ogni pacchetto senza rifare il
    // suo mestiere.
    final togliibili = await _paccacheDirebbe();
    // Sotto i dieci mega non è una voce, è una briciola: la stessa soglia
    // della cache personale. Una riga che promette 172 KB è una riga che si
    // spunta e si preme per niente.
    if (togliibili.byte < _briciola) return null;

    return Voce(
      id: 'cache-pacchetti',
      // ── Il nome, e perché è cambiato ─────────────────────────────────
      //
      // Si chiamava «Pacchetti già installati», e Giacomo ha chiesto:
      // «intendi pacchetti installati?». La domanda è la prova che il nome
      // era sbagliato — in un programma che cancella, «pacchetti installati»
      // suona come i PROGRAMMI, non come le loro scatole. Chi legge si chiede
      // se stia per disinstallare metà computer, ed è la domanda che non deve
      // venire in mente.
      //
      // E c'era di peggio: la famiglia si chiamava «Pacchetti scaricati» e la
      // voce «Pacchetti già installati». Due nomi per la stessa cosa, sulla
      // stessa schermata.
      nome: 'Pacchetti scaricati',
      categoria: 'pacchetti',
      dove: dove,
      byte: togliibili.byte,
      quante: togliibili.quanti,
      vuoleLaPassword: true,
      avvertenza: 'Sono i file scaricati per installare i programmi: i '
          'programmi restano dove sono, si butta la scatola. In tutto la '
          'cartella pesa ${_inParole(p.byte)}, ma il resto sono le ultime due '
          'versioni di ogni pacchetto: si tengono, perché servono a tornare '
          'indietro se un aggiornamento rompe qualcosa.',
    );
  }

  /// Quanto toglierebbe `paccache`, chiesto a lui.
  ///
  /// Due giri, che sono due cose diverse: le versioni vecchie dei pacchetti
  /// che hai (`-k 2`, cioè tienine due) e quelle dei pacchetti che **non hai
  /// più** (`-u -k 0`, cioè tutte). I secondi sono spreco puro: sono i resti
  /// di programmi disinstallati.
  ///
  /// La prova a vuoto (`-d`) non tocca niente e stampa una riga come:
  ///
  ///     ==> finished dry run: 18 candidates (disk space saved: 130.00 MiB)
  Future<({int byte, int quanti})> _paccacheDirebbe() async {
    var byte = 0, quanti = 0;
    for (final giri in [
      ['-d', '-k', '2'],
      ['-d', '-u', '-k', '0'],
    ]) {
      try {
        final r = await _esegui('paccache', giri);
        final testo = '${r.stdout}${r.stderr}';
        final m = RegExp(r'(\d+) candidates \(disk space saved: '
                r'([\d.]+) ([KMG])iB\)')
            .firstMatch(testo);
        if (m == null) continue;
        quanti += int.tryParse(m.group(1)!) ?? 0;
        final quanto = double.tryParse(m.group(2)!) ?? 0;
        // KiB, MiB, GiB sono in base 1024: è `paccache` a scriverli così, e
        // convertirli male vorrebbe dire un numero che non torna con quello
        // che si libera davvero.
        final scala = switch (m.group(3)!) {
          'K' => 1024,
          'M' => 1024 * 1024,
          _ => 1024 * 1024 * 1024,
        };
        byte += (quanto * scala).round();
      } catch (_) {
        // `paccache` non c'è: allora non c'è nemmeno un modo onesto di dire
        // quanto si libererebbe, e la voce non si mostra.
      }
    }
    return (byte: byte, quanti: quanti);
  }

  // ── Il resto, che è piccolo ma si conta ──────────────────────────────────

  Future<List<Voce>> cosePiccole() async {
    final fuori = <Voce>[];

    Future<void> aggiungi(String id, String nome, String categoria, String dove,
        {bool root = false, String rifa = 'sola', String nota = ''}) async {
      final p = await _peso(dove);
      if (p.byte <= 0) return;
      fuori.add(Voce(
          id: id,
          nome: nome,
          categoria: categoria,
          dove: dove,
          byte: p.byte,
          parziale: p.parziale,
          torna: rifa,
          vuoleLaPassword: root,
          avvertenza: nota));
    }

    await aggiungi('cestino', 'Cestino', 'cestino',
        '$_casa/.local/share/Trash',
        rifa: 'mai', nota: 'Quello che c\'è dentro l\'hai buttato tu.');
    await aggiungi('miniature', 'Miniature', 'miniature',
        '$_casa/.cache/thumbnails');
    // ── Il registro: quello che si può POTARE, non quello che pesa ──────
    //
    // Se ne tengono cinquanta mega — gli ultimi giorni, cioè quelli che
    // servono quando qualcosa va storto adesso — e quindi quello che si
    // libera è il resto. Un registro da 44 MB non ha niente da dare, e
    // mostrarlo lo stesso vorrebbe dire promettere spazio che non c'è.
    //
    // La misura la dà `journalctl` e non `du`: i file del registro sono
    // bucati, e la loro dimensione dichiarata è il doppio di quella vera.
    await _registro(fuori);
    // ── I file temporanei ─────────────────────────────────────────────
    //
    // Solo i TUOI, e solo quelli in `/tmp`: quella cartella la svuota il
    // computer a ogni riavvio, ma fra un riavvio e l'altro ci si accumula
    // roba di programmi chiusi male. Di altri utenti non si tocca niente —
    // non per prudenza, per correttezza: non sono tuoi.
    await aggiungi('temporanei', 'File temporanei', 'temporanei',
        '/tmp',
        nota: 'Si svuota comunque al riavvio. Un programma aperto adesso '
            'potrebbe averci dentro qualcosa che gli serve.');
    return fuori;
  }

  static const int _registroDaTenere = 50 * 1000 * 1000;

  /// Sotto questa soglia non è una voce, è una briciola. È la stessa di
  /// `cachePersonale`, e sta qui perché la regola è una sola: l'inventario
  /// mostra quello su cui vale la pena decidere.
  static const int _briciola = 10 * 1024 * 1024;

  Future<void> _registro(List<Voce> fuori) async {
    const dove = '/var/log/journal';
    if (!await Directory(dove).exists()) return;
    var uso = 0;
    try {
      final r = await _esegui('journalctl', ['--disk-usage']);
      // «Archived and active journals take up 44.0M in the file system.»
      final m = RegExp(r'([\d.]+)([KMG])').firstMatch('${r.stdout}');
      if (m != null) {
        final quanto = double.tryParse(m.group(1)!) ?? 0;
        final scala = switch (m.group(2)!) {
          'K' => 1024,
          'M' => 1024 * 1024,
          _ => 1024 * 1024 * 1024,
        };
        uso = (quanto * scala).round();
      }
    } catch (_) {
      return;
    }
    final liberabili = uso - _registroDaTenere;
    if (liberabili < _briciola) return;
    fuori.add(Voce(
      id: 'registro',
      nome: 'Registro di sistema',
      categoria: 'registri',
      dove: dove,
      byte: liberabili,
      vuoleLaPassword: true,
      avvertenza: 'Serve a capire cosa è successo quando qualcosa va storto. '
          'In tutto pesa ${_inParole(uso)}: se ne tengono gli ultimi 50 MB, '
          'e si toglie il resto.',
    ));
  }

  // ── I pacchetti orfani ───────────────────────────────────────────────────
  //
  // Installati come dipendenza di qualcosa che non c'è più. Su questa macchina
  // sono TRE per zero megabyte, ed è normale: con pacman gli orfani veri sono
  // rari. Quindi questa voce serve per ordine, non per spazio — e prometterla
  // come «libera gigabyte» sarebbe la prima bugia del programma.
  //
  // Si elencano per NOME e mai come numero: tre pacchetti si leggono in tre
  // secondi, e uno di quei tre potrebbe servirti.
  Future<List<String>> orfani() async {
    try {
      final r = await _esegui('pacman', ['-Qtdq']);
      if (r.exitCode != 0) return const [];
      return '${r.stdout}'
          .split('\n')
          .map((x) => x.trim())
          .where((x) => x.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// I byte in parole, per le righe del racconto.
  ///
  /// In base **mille** come `du -sb`, e come la finestra
  /// (`manutenzione/Misure.qml`): due basi diverse vorrebbero dire che il
  /// registro e il numero grande non tornano, ed è la differenza che non si
  /// spiega mai a chi guarda.
  static String _inParole(int byte) {
    if (byte < 1000) return '$byte B';
    if (byte < 1000000) return '${(byte / 1000).round()} KB';
    if (byte < 1000000000) return '${(byte / 1000000).round()} MB';
    return '${(byte / 1000000000).toStringAsFixed(2).replaceAll('.', ',')} GB';
  }

  /// Tutto insieme, come lo vuole la finestra.
  Future<Map<String, dynamic>> tutto() async {
    // Ogni tappa si annuncia PRIMA («sto guardando lì») e si conclude DOPO
    // («ho trovato questo»). Due righe e non una: la prima dice dove si è
    // fermata se qualcosa va storto, la seconda è quella che si legge dopo.
    _di('cache', 'Guardo la tua cache — ${_casa.split('/').last}/.cache', 0);
    final cache = await cachePersonale();
    _di('cache',
        '${cache.length} voci, ${_inParole(cache.fold<int>(0, (s, v) => s + v.byte))}',
        1);

    _di('pacchetti', 'Guardo i pacchetti scaricati — /var/cache/pacman/pkg', 1);
    final pacchetti = await cachePacchetti();
    _di('pacchetti',
        pacchetti == null
            ? 'niente da qui'
            : '${pacchetti.quante} file, ${_inParole(pacchetti.byte)}',
        2);

    _di('lingue', 'Conto le lingue — /usr/share/locale', 2);
    final ling = await lingue();
    _di('lingue',
        ling == null ? 'niente da qui' : '${ling.quante} lingue, ${_inParole(ling.byte)}',
        3);

    _di('piccole', 'Cestino, miniature, registri, temporanei', 3);
    final piccole = await cosePiccole();
    _di('piccole',
        '${piccole.length} voci, ${_inParole(piccole.fold<int>(0, (s, v) => s + v.byte))}',
        4);

    _di('orfani', 'Cerco i pacchetti rimasti soli', 4);
    final orf = await orfani();
    _di('orfani',
        orf.isEmpty ? 'nessuno' : '${orf.length}: ${orf.join(', ')}', 5);

    final voci = <Voce>[
      ...cache,
      ?pacchetti,
      ?ling,
      ...piccole,
    ];
    // ── Il riassunto per famiglia ─────────────────────────────────────
    //
    // Lo fa il demone e non la finestra, e non è pigrizia: il grafico e
    // l'elenco devono dire lo STESSO numero. Sommando due volte in due posti,
    // il giorno che una voce cambia famiglia i due numeri divergono e nessuno
    // se ne accorge — è la stessa ragione per cui `finestre_service` è uno
    // solo per tutte le finestre.
    final perFamiglia = <String, int>{};
    for (final v in voci) {
      perFamiglia[v.categoria] = (perFamiglia[v.categoria] ?? 0) + v.byte;
    }

    return {
      'voci': [for (final v in voci) v.toJson()],
      'famiglie': perFamiglia,
      'totale': voci.fold<int>(0, (s, v) => s + v.byte),
      // Gli orfani stanno a parte perché non si misurano in byte: la loro
      // ragione è l'ordine, e mescolarli al conto dello spazio direbbe il
      // falso su tutti e due.
      'orfani': orf,
    };
  }
}

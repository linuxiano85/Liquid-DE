import 'catalogo.dart';
import 'rilievo.dart';
import 'scaffale.dart';
import 'sicurezza_kernel.dart';
import 'risorse_compilazione.dart';

/// La ricetta: dalle scelte di chi guarda al piano esatto di quello che si
/// farà, comando per comando.
///
/// ── Una funzione pura, e non per eleganza ───────────────────────────────
///
/// Qui non si legge un file e non si lancia un processo: entrano un rilievo e
/// delle scelte, esce un piano. Per tre ragioni:
///
///  1. **Il piano si mostra prima di eseguirlo.** È la prima regola di
///     Manutenzione — niente si tocca senza averlo mostrato — e per mostrare
///     quello che si farà bisogna poterlo calcolare senza farlo.
///  2. **La finestra manda scelte, mai comandi.** Il demone ricalcola la
///     ricetta da capo quando si preme «Compila», con le stesse scelte:
///     nessun comando arriva dal canale, quindi nessuno può farne partire uno
///     suo passando da noi. È la regola di `manutenzione_pulisci`
///     («identificativi, mai percorsi»).
///  3. **Si prova senza un kernel.** Un rilievo finto e tre scelte bastano.
class Ricetta {
  final Scelte scelte;
  final List<String> moduli;
  final Map<String, int> perFamiglia;

  /// I moduli che si sarebbero tenuti e che invece si tolgono, con il
  /// perché: tolti a mano o da un preset.
  final Map<String, String> tolti;
  final List<Impostazione> impostazioni;
  final List<Passo> passi;
  final String rilascio;
  final List<String> avvisi;
  final List<String> requisitiMancanti;
  final Map<String, dynamic> parallelismo;

  const Ricetta({
    required this.scelte,
    required this.moduli,
    required this.perFamiglia,
    required this.tolti,
    required this.impostazioni,
    required this.passi,
    required this.rilascio,
    required this.avvisi,
    this.requisitiMancanti = const [],
    this.parallelismo = const {},
  });

  Map<String, dynamic> toJson() => {
    'scelte': scelte.toJson(),
    'moduli': moduli,
    'quanti': moduli.length,
    'perFamiglia': perFamiglia,
    'tolti': tolti,
    'impostazioni': [for (final i in impostazioni) i.toJson()],
    'passi': [for (final p in passi) p.toJson()],
    'rilascio': rilascio,
    'avvisi': avvisi,
    'requisitiMancanti': requisitiMancanti,
    'parallelismo': parallelismo,
  };

  /// Il file che `localmodconfig` legge al posto di `lsmod` (variabile
  /// `LSMOD`). Ha la forma dell'uscita di `lsmod`: una riga d'intestazione,
  /// poi un modulo per riga col nome in prima colonna. Gli altri due campi
  /// non li legge nessuno, ma `streamline_config.pl` si aspetta la forma.
  String get fileLsmod => [
    'Module                  Size  Used by',
    for (final m in moduli) '${m.padRight(24)} 0  0',
  ].join('\n');
}

/// Un passo del piano.
///
/// `comando` vuoto vuol dire un passo che il demone fa da sé, in Dart —
/// scaricare, controllare, copiare — e che nel piano si mostra con la sola
/// descrizione. Un comando è un ELENCO di argomenti, mai una riga da far
/// leggere a una shell: nessun nome di cartella può diventare un secondo
/// comando.
class Passo {
  final String id;
  final String titolo;
  final String spiega;
  final List<String> comando;

  /// Se il passo si salta quando l'albero è già pronto (estratto e
  /// patchato): è la differenza fra la prima compilazione e le successive.
  final bool soloLaPrimaVolta;

  const Passo(
    this.id,
    this.titolo,
    this.spiega, {
    this.comando = const [],
    this.soloLaPrimaVolta = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'titolo': titolo,
    'spiega': spiega,
    'comando': comando,
    'soloLaPrimaVolta': soloLaPrimaVolta,
  };
}

/// Da dove vengono i sorgenti.
enum TipoSorgente { vanilla, cachyos }

class Scelte {
  final Set<String> tolti;
  final Set<String> aggiunti;
  final Set<String> scorte;
  final Set<String> preset;
  final TipoSorgente sorgente;
  final String versione;

  /// `in-uso` (la configurazione del kernel che gira adesso, da
  /// `/proc/config.gz`) o `defconfig` (quella di serie del kernel).
  final String base;
  final String compilatore;

  /// Limite facoltativo ai processi di compilazione; null usa tutti i thread.
  final int? lavori;
  final bool lto;
  final bool provaVeloce;
  final bool nativo;
  final String nome;

  /// Il kernel «pronto al profilo»: compilato con `AUTOFDO_CLANG`, così
  /// che il profilo registrato mentre lo usi si possa riportare sul codice.
  /// È il primo dei due tempi; vedi `fucina_service.dart`, «Su misura del
  /// tuo uso».
  final bool autofdo;

  /// Il secondo tempo: il rilascio del kernel su cui è stato registrato il
  /// profilo (`6.17.2-fucina-prova`), o vuoto. Il profilo vive nella cache
  /// della Fucina, accanto al `vmlinux` di quel kernel.
  final String profilo;

  /// Le regole «su misura dentro il kernel»: processori possibili, NUMA,
  /// funzioni dell'altro fornitore. Vedi `suMisura` in `catalogo.dart`.
  final bool misura;

  /// Prima di dire «pronto», avvia il kernel in QEMU e guarda se arriva
  /// allo spazio utente. Vedi `prova_avvio.dart`.
  final bool provaAvvio;

  const Scelte({
    this.tolti = const {},
    this.aggiunti = const {},
    this.scorte = const {},
    this.preset = const {},
    this.sorgente = TipoSorgente.vanilla,
    this.versione = '',
    this.base = 'in-uso',
    this.compilatore = 'gcc',
    this.lavori,
    this.lto = false,
    this.provaVeloce = false,
    this.nativo = false,
    this.nome = '',
    this.autofdo = false,
    this.profilo = '',
    this.misura = false,
    this.provaAvvio = false,
  });

  /// Dalle scelte arrivate dal canale. Ogni campo si controlla: dal canale
  /// arriva testo, e un nome di kernel con dentro una barra diventerebbe un
  /// percorso in `/boot`.
  ///
  /// Solleva [SceltaNonValida] con una frase da mostrare così com'è.
  factory Scelte.daJson(Map<String, dynamic> j) {
    Set<String> insieme(Object? v) => {
      if (v is List)
        for (final x in v)
          if (x is String && _nomeModulo.hasMatch(x)) x.replaceAll('-', '_'),
    };

    final nome = '${j['nome'] ?? ''}'.trim();
    if (!nomeValido(nome)) {
      throw const SceltaNonValida(
        'Il nome del kernel può avere solo lettere '
        'minuscole, cifre e trattini, da 1 a 24 caratteri, e non può '
        'cominciare o finire con un trattino.',
      );
    }
    final sorgente = switch ('${j['sorgente'] ?? 'vanilla'}') {
      'vanilla' => TipoSorgente.vanilla,
      'cachyos' => TipoSorgente.cachyos,
      final s => throw SceltaNonValida('Sorgente sconosciuta: «$s».'),
    };
    final versione = '${j['versione'] ?? ''}'.trim();
    if (!versioneValida(versione)) {
      throw SceltaNonValida(
        'Versione del kernel non valida: «$versione». '
        'Serve una versione rilasciata, come 6.17 o 6.17.2.',
      );
    }
    final base = '${j['base'] ?? 'in-uso'}';
    if (base != 'in-uso' && base != 'defconfig') {
      throw SceltaNonValida('Configurazione di partenza sconosciuta: «$base».');
    }
    final comp = '${j['compilatore'] ?? 'gcc'}';
    if (comp != 'gcc' && comp != 'clang') {
      throw SceltaNonValida('Compilatore sconosciuto: «$comp».');
    }
    final rawLavori = j['lavori'];
    final lavori = rawLavori == null ? null : int.tryParse('$rawLavori');
    if (rawLavori != null && (lavori == null || lavori < 1 || lavori > 512)) {
      throw const SceltaNonValida(
        'I lavori paralleli devono essere un numero da 1 a 512.',
      );
    }
    final lto = j['lto'] == true;
    if (lto && comp != 'clang') {
      throw const SceltaNonValida(
        'LTO nel kernel ufficiale esiste solo con '
        'Clang: scegli Clang o togli LTO.',
      );
    }
    // Il profilo arriva come NOME di un kernel nostro, mai come percorso: il
    // file lo trova il demone nella sua cache. Un nome che non passa il
    // controllo dell'aiutante di root non passa nemmeno qui.
    final profilo = '${j['profilo'] ?? ''}'.trim();
    if (profilo.isNotEmpty && !Scaffale.nostro(profilo)) {
      throw SceltaNonValida(
        '«$profilo» non è un kernel della Fucina: il '
        'profilo si prende solo da uno dei nostri.',
      );
    }
    final autofdo = j['autofdo'] == true || profilo.isNotEmpty;
    if (autofdo && comp != 'clang') {
      throw const SceltaNonValida(
        'AutoFDO esiste solo con Clang: il profilo '
        'lo legge Clang, GCC nel kernel non lo sa usare.',
      );
    }
    return Scelte(
      tolti: insieme(j['tolti']),
      aggiunti: insieme(j['aggiunti']),
      scorte: insieme(j['scorte']).where(_scortaNota).toSet(),
      preset: insieme(j['preset']).where(_presetNoto).toSet(),
      sorgente: sorgente,
      versione: versione,
      base: base,
      compilatore: comp,
      lavori: lavori,
      lto: lto,
      provaVeloce: j['provaVeloce'] == true,
      nativo: j['nativo'] == true,
      nome: nome,
      autofdo: autofdo,
      profilo: profilo,
      misura: j['misura'] == true,
      provaAvvio: j['provaAvvio'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'tolti': tolti.toList()..sort(),
    'aggiunti': aggiunti.toList()..sort(),
    'scorte': scorte.toList()..sort(),
    'preset': preset.toList()..sort(),
    'sorgente': sorgente.name,
    'versione': versione,
    'base': base,
    'compilatore': compilatore,
    if (lavori != null) 'lavori': lavori,
    'lto': lto,
    'provaVeloce': provaVeloce,
    'nativo': nativo,
    'nome': nome,
    'autofdo': autofdo,
    'profilo': profilo,
    'misura': misura,
    'provaAvvio': provaAvvio,
  };

  /// Il nome che finisce in `CONFIG_LOCALVERSION`, e da lì nel rilascio, nel
  /// nome del file in `/boot` e nella cartella dei moduli.
  ///
  /// Il prefisso `fucina-` non è decorazione: è il segno con cui l'aiutante
  /// di root riconosce un kernel nostro. Non installa e non toglie niente che
  /// non lo porti, e quindi il kernel della distribuzione — quello che ti
  /// riporta a casa se il nostro non parte — non è raggiungibile da qui.
  String get localversion => '-fucina-$nome';

  String get rilascio => '$versione$localversion';
}

class SceltaNonValida implements Exception {
  final String messaggio;
  const SceltaNonValida(this.messaggio);
  @override
  String toString() => messaggio;
}

final RegExp _nomeModulo = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _nome = RegExp(r'^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$');
final RegExp _versione = RegExp(r'^[1-9][0-9]?\.[0-9]{1,3}(\.[0-9]{1,4})?$');

bool nomeValido(String s) => _nome.hasMatch(s);

// Fuori dalla classe: dentro `Scelte` il nome `scorte` è il campo, non il
// catalogo, e una funzione di fabbrica non vede nemmeno quello.
bool _scortaNota(String id) => scorte.any((x) => x.id == id);
bool _presetNoto(String id) => presets.any((x) => x.id == id);

/// Solo versioni rilasciate: `6.17` o `6.17.2`. Le candidate (`-rc`) non
/// stanno su cdn.kernel.org con le altre e non hanno una somma di controllo
/// pubblicata: per ora restano fuori, ed è detto.
bool versioneValida(String s) => _versione.hasMatch(s);

/// La serie di una versione: `6.17.2` → `6.17`. È il nome della cartella
/// delle patch di CachyOS.
String serieDi(String versione) => versione.split('.').take(2).join('.');

/// Dove sta tutto quello che la Fucina scrive. Si calcola fuori (dal
/// servizio, con `MinervaPaths`) e si passa, così la ricetta resta pura.
class Cartelle {
  /// L'albero dei sorgenti, per esempio `…/alberi/6.17.2-vanilla/linux-6.17.2`.
  final String albero;

  /// Dove finisce il kernel pronto da installare: `…/uscita/<rilascio>`.
  final String uscita;

  /// Il file `LSMOD` per localmodconfig.
  final String lsmod;

  /// Il profilo AutoFDO da dare a Clang, o vuoto: `…/profili/<rilascio del
  /// kernel profilato>/autofdo.prof`.
  final String profilo;

  const Cartelle({
    required this.albero,
    required this.uscita,
    required this.lsmod,
    this.profilo = '',
  });
}

/// Calcola la ricetta.
///
/// `nuclei` è quanti lavori paralleli dare a `make`; `ccache` se c'è.
Ricetta calcola(
  Rilievo r,
  Scelte s,
  Cartelle c, {
  required int nuclei,
  bool ccache = false,
  Map<String, dynamic> risorse = const {},
}) {
  final avvisi = <String>[];
  final combinati = combinaPreset(s.preset);

  // ── I moduli ─────────────────────────────────────────────────────────
  final tenuti = <String>{};
  final tolti = <String, String>{};
  final famigliaDi = <String, String>{
    for (final v in r.moduli.values) v.nome: v.famiglia,
  };

  final togliFamiglie = combinati?.togliFamiglie ?? const <String>{};
  for (final v in r.moduli.values) {
    final essenziale = v.fonti.contains('essenziale');
    if (v.tenutoDiSerie || s.aggiunti.contains(v.nome)) {
      // Un modulo aggiunto a mano vince sul preset: la scelta fatta su QUEL
      // modulo è più precisa di quella fatta sulla sua famiglia.
      if (!essenziale &&
          togliFamiglie.contains(v.famiglia) &&
          !s.aggiunti.contains(v.nome)) {
        tolti[v.nome] = 'tolto dal preset (famiglia «${v.famiglia}»)';
        continue;
      }
      if (s.tolti.contains(v.nome)) {
        if (essenziale) {
          // Non si toglie, e lo si dice: un essenziale tolto è un computer
          // che non si avvia, e una scelta ignorata in silenzio è una
          // scelta che l'utente crede di aver fatto.
          avvisi.add(
            '«${v.nome}» serve ad avviare '
            '(${r.avvio.perche[v.nome] ?? 'essenziale'}): resta.',
          );
        } else {
          tolti[v.nome] = 'tolto a mano';
          continue;
        }
      }
      tenuti.add(v.nome);
    }
  }

  // Le scorte: quelle scelte più quelle che un preset accende da solo.
  final tutteLeScorte = {...s.scorte, ...?combinati?.scorte};
  for (final sc in scorte) {
    if (!tutteLeScorte.contains(sc.id)) continue;
    for (final m in sc.moduli) {
      if (s.tolti.contains(m)) continue;
      tenuti.add(m);
      famigliaDi.putIfAbsent(m, () => famigliaDiScorta(sc.id));
      tolti.remove(m);
    }
  }

  // Un modulo aggiunto a mano che il rilievo non conosce (non è né
  // caricato, né candidato): si tiene lo stesso, ma senza famiglia.
  for (final m in s.aggiunti) {
    if (s.tolti.contains(m)) continue;
    tenuti.add(m);
    famigliaDi.putIfAbsent(m, () => 'altro');
  }

  final moduli = tenuti.toList()..sort();
  final perFamiglia = <String, int>{};
  for (final m in moduli) {
    final f = famigliaDi[m] ?? 'altro';
    perFamiglia[f] = (perFamiglia[f] ?? 0) + 1;
  }

  // ── Le impostazioni ──────────────────────────────────────────────────
  final impostazioni = <Impostazione>[
    Impostazione(
      'LOCALVERSION',
      s.localversion,
      'Il nome del kernel: finisce nel rilascio, in /boot e nei moduli.',
    ),
    const Impostazione(
      'LOCALVERSION_AUTO',
      'n',
      'Nessun suffisso aggiunto da git: il nome è solo quello scelto.',
    ),
    ...?combinati?.impostazioni,
    if (s.provaVeloce) ...provaVeloce,
    if (s.lto) ...ltoSottile,
    // ── Con Clang, quello che non si è scelto si spegne per nome ─────────
    //
    // Trovato rileggendo la catena il 1° ottobre 2026: il kernel di CachyOS
    // è compilato con Clang, ThinLTO, AutoFDO e Propeller, e la sua
    // configurazione (`/proc/config.gz`) li porta tutti accesi. Partendo da
    // lì con GCC si spengono da soli (dipendono da Clang); con Clang no, e
    // chi aveva lasciato LTO e il profilo spenti si ritrovava un kernel con
    // ThinLTO e le opzioni di Propeller senza profilo — più lento da
    // compilare e più grosso — senza che il controllo dicesse niente,
    // perché nessuno li aveva chiesti.
    if (s.compilatore == 'clang' && !s.lto) ...ltoNessuno,
    if (s.compilatore == 'clang')
      Impostazione(
        'AUTOFDO_CLANG',
        s.autofdo ? 'y' : 'n',
        s.autofdo
            ? (s.profilo.isEmpty
                  ? 'Il kernel pronto al profilo: le informazioni che servono '
                        'a riportare sul codice quello che registrerà perf.'
                  : 'Clang ottimizza col profilo registrato su ${s.profilo}.')
            : 'Senza profilo AutoFDO non serve: spento anche se il kernel '
                  'di partenza lo aveva.',
      ),
    if (s.compilatore == 'clang')
      const Impostazione(
        'PROPELLER_CLANG',
        'n',
        'Propeller vuole un terzo passaggio e uno strumento che Arch non '
            'impacchetta: spento anche se il kernel di partenza lo aveva.',
      ),
    if (s.autofdo &&
        r.macchina['profilo'] is Map &&
        (r.macchina['profilo'] as Map)['tipo'] == 'amd-brs')
      const Impostazione(
        'PERF_EVENTS_AMD_BRS',
        'y',
        'Zen 3: il campionamento dei salti (BRS) con cui perf registra il '
            'profilo.',
      ),
    if (s.nativo) ...[
      // X86_NATIVE_CPU è una voce di scelta con GENERIC_CPU; scripts/config
      // non spegne da solo la voce già presente nel config CachyOS. La si
      // spegne prima di accendere quella nativa, altrimenti olddefconfig
      // conserva la scelta precedente e la macchina compila genericamente.
      const Impostazione(
        'GENERIC_CPU',
        'n',
        'Libera la scelta CPU da Generic-x86-64 per attivare il target nativo.',
      ),
      if (leggiConfig(r.configPartenza)['MZEN4'] == 'y')
        const Impostazione(
          'MZEN4',
          'n',
          'Libera la scelta CPU da Zen 4 per attivare il target nativo.',
        ),
      const Impostazione(
        'X86_NATIVE_CPU',
        'y',
        'Compilato per QUESTO processore (-march=native): più rapido qui, '
            'e non parte su un processore più vecchio. C\'è dal 6.16; con '
            'Clang serve la 19.1 o più recente.',
      ),
    ],
    if (s.misura) ...suMisura(r.macchina),
    for (final simbolo
        in (r.configKernel['protezioni'] as List? ?? const [])
            .whereType<String>())
      if (protezioneKernel(simbolo))
        Impostazione(
          simbolo,
          'y',
          'Protezione attiva nel kernel di partenza: viene conservata e verificata prima di compilare.',
        ),
    ...impostazioniLsmAttivi(r, avvisi),
    ..._impostazioniFilesystemAttivi(r, avvisi),
    // Si chiede BORE quando si sceglie CachyOS, ma la firma dell'archivio non
    // prova che questa opzione esista: controllaConfig verifica il Kconfig
    // scaricato e avverte senza dichiarare attivo uno scheduler assente.
    if (s.sorgente == TipoSorgente.cachyos)
      const Impostazione(
        'SCHED_BORE',
        'y',
        'Lo scheduler BORE di CachyOS, acceso come nel loro kernel.',
      ),
  ];

  if (s.provaVeloce) {
    avvisi.add(
      'Prova veloce: senza simboli di debug non c\'è BTF, e senza '
      'BTF gli scheduler sched_ext (scx_*) non partono.',
    );
  }
  if (s.sorgente == TipoSorgente.cachyos) {
    avvisi.add(
      'Dalla 6.17 si scarica l\'archivio di CachyOS, già patchato, '
      'e se ne verifica la firma (Peter Jung o Eric Naim). Per le versioni '
      'più vecchie si applicano le loro patch sopra kernel.org: quelle non '
      'sono firmate, e la somma di ognuna resta scritta nel kernel pronto.',
    );
  }
  if (s.nativo) {
    avvisi.add(
      'Ottimizzato per questo processore: se sposti il disco su un '
      'computer con un processore più vecchio, questo kernel potrebbe non avviarsi. '
      'Mantieni il kernel della distribuzione come alternativa di avvio.',
    );
  }
  if (s.base == 'in-uso' && r.configPartenza.isEmpty) {
    avvisi.add(
      'Non trovo la configurazione del kernel in uso (né '
      '/proc/config.gz, né /boot/config-${r.rilascio}, né quella nelle '
      'intestazioni): si parte da defconfig, e molti driver mancheranno.',
    );
  }
  if (s.base == 'defconfig' || r.configPartenza.isEmpty) {
    avvisi.add(
      'Da defconfig: localmodconfig toglie moduli ma non ne '
      'aggiunge. Essenziali, scorte e moduli aggiunti a mano si accendono '
      'dall\'albero dei sorgenti; gli altri driver che defconfig non ha non '
      'ci saranno, anche se sono nell\'elenco.',
    );
  }
  if (s.compilatore == 'clang' && !s.lto && s.autofdo) {
    avvisi.add(
      'AutoFDO rende di più con ThinLTO: senza, il profilo arriva '
      'ai singoli file ma non al collegamento, dove si decide quasi tutto.',
    );
  }
  if (s.autofdo && s.profilo.isEmpty) {
    final p = r.macchina['profilo'];
    avvisi.add(
      p is Map && p['possibile'] == true
          ? 'Primo tempo di AutoFDO: installa questo kernel, avvialo, usalo come '
                'sempre e registra il profilo dalla pagina Kernel. Poi «Ricompila '
                'col profilo».'
          : 'Questo kernel sarà pronto al profilo, ma su questo computer il '
                'profilo non si può registrare: ${p is Map ? p['perche'] : 'non '
                          'so dire perché'}',
    );
  }
  if (s.provaAvvio && s.nativo) {
    avvisi.add(
      'Prova d\'avvio di un kernel «solo per questo processore»: si '
      'fa con KVM (-cpu host). Senza KVM l\'emulazione può non avere le '
      'istruzioni che il kernel usa, e un fallimento non vorrebbe dire niente.',
    );
  }
  if (r.macchina['monolitico'] == true &&
      s.base == 'in-uso' &&
      r.configPartenza.isNotEmpty) {
    avvisi.add(
      'Il kernel in uso non ha moduli (è tutto dentro): partendo '
      'dalla sua configurazione la scrematura non toglie niente, e il '
      'kernel nuovo avrà dentro tutto quello che ha quello di adesso. '
      'Scorte ed essenziali che gli mancano si aggiungono dall\'albero dei '
      'sorgenti.',
    );
  }
  if (!r.modprobed.presente) {
    avvisi.add(
      'Senza modprobed-db il kernel conoscerà solo quello che è '
      'collegato adesso. Collega ora quello che usi di rado, o accendi le '
      'scorte.',
    );
  }
  final mancanti = [
    for (final a in (r.macchina['attrezzi'] as List? ?? const []))
      if (a is Map && a['indispensabile'] == true && a['presente'] != true)
        '${a['nome']}',
  ];
  bool presente(String nome) => (r.macchina['attrezzi'] as List? ?? const [])
      .any((a) => a is Map && a['nome'] == nome && a['presente'] == true);
  if (!presente(s.compilatore)) mancanti.add(s.compilatore);
  // `LLVM=1` non vuol dire solo clang: anche il linker (ld.lld) e gli
  // attrezzi binari (llvm-ar, llvm-nm, llvm-objcopy…). Senza, Kconfig si
  // ferma al primo `make` con un «linker non supportato» che non nomina il
  // pacchetto. Su Arch sono `lld` e `llvm`.
  if (s.compilatore == 'clang') {
    for (final a in const ['lld', 'llvm']) {
      if (_conosciuto(r, a) && !presente(a)) mancanti.add(a);
    }
  }
  if (s.profilo.isNotEmpty && _conosciuto(r, 'llvm') && !presente('llvm')) {
    mancanti.add('llvm');
  }
  if (!s.provaVeloce && _conosciuto(r, 'pahole') && !presente('pahole')) {
    avvisi.add(
      'Manca pahole: senza, Kconfig spegne BTF da solo, e senza BTF '
      'gli scheduler sched_ext (scx_*) non partono. Su Arch: pacman -S pahole',
    );
  }
  if (s.provaAvvio &&
      _conosciuto(r, 'qemu-system-x86') &&
      !presente('qemu-system-x86')) {
    avvisi.add(
      'Manca QEMU per la prova d\'avvio: su Arch, pacman -S '
      'qemu-system-x86. Senza, la prova si salta e lo si dice.',
    );
  }
  if (mancanti.isNotEmpty) {
    final pacchetti = mancanti.toSet().toList()..sort();
    avvisi.add(
      'Mancano programmi per compilare: ${pacchetti.join(', ')}. '
      'Su Arch e CachyOS: sudo pacman -S --needed ${pacchetti.join(' ')}',
    );
  }

  // ── I passi ──────────────────────────────────────────────────────────
  // ── Lo stesso `make` per OGNI passo ────────────────────────────────────
  //
  // Compilatore, LLVM e profilo entrano in ogni invocazione, identici:
  // Kconfig ricalcola le dipendenze dal compilatore che vede (`CC_IS_CLANG`,
  // `LD_IS_LLD`, la versione), e un `olddefconfig` lanciato con un
  // compilatore diverso da quello della compilazione riscrive il .config.
  //
  // ccache no col profilo: il profilo non è fra quello che ccache guarda
  // quando decide se un oggetto è già pronto, e il secondo tempo di AutoFDO
  // riuserebbe gli oggetti del primo — compilati SENZA profilo — dicendo
  // di averlo applicato.
  final conCcache = ccache && s.profilo.isEmpty;
  final parallelismo = scegliParallelismo(
    thread: nuclei,
    richiesti: s.lavori,
    thinLto: s.compilatore == 'clang' && s.lto,
    risorse: risorse,
  );
  final lavori = parallelismo['effettivi'] as int;
  if (parallelismo['memoriaEffettivaBytes'] == null ||
      parallelismo['manualeOltreConsiglio'] == true) {
    avvisi.add('${parallelismo['motivo']} ${parallelismo['limite']}');
  }
  final make = <String>[
    'make',
    if (s.compilatore == 'clang') 'LLVM=1',
    if (conCcache) 'CC=ccache ${s.compilatore == 'clang' ? 'clang' : 'gcc'}',
    if (s.profilo.isNotEmpty) 'CLANG_AUTOFDO_PROFILE=${c.profilo}',
  ];
  final configurazioni = <String>[
    'scripts/config',
    '--file',
    '.config',
    for (final i in impostazioni) ..._argomentiConfig(i),
  ];

  final passi = <Passo>[
    Passo(
      'scarica',
      'Scarica i sorgenti',
      s.sorgente == TipoSorgente.cachyos
          ? 'L\'archivio di CachyOS per il ${s.versione} (github.com/CachyOS/'
                'linux), verificato con la firma dei loro sviluppatori; se '
                'CachyOS non ne ha uno, linux-${s.versione}.tar.xz da '
                'cdn.kernel.org. Se c\'è già e torna, non si riscarica.'
          : 'linux-${s.versione}.tar.xz da cdn.kernel.org, con la somma di '
                'controllo SHA-256 pubblicata accanto. Se c\'è già e torna, '
                'non si riscarica.',
      soloLaPrimaVolta: true,
    ),
    Passo(
      'estrai',
      'Apri l\'archivio',
      'Una volta sola: le compilazioni successive riusano l\'albero e '
          'ricompilano solo quello che è cambiato.',
      soloLaPrimaVolta: true,
    ),
    if (s.sorgente == TipoSorgente.cachyos)
      Passo(
        'patch',
        'Sorgenti e patch CachyOS',
        'L\'archivio CachyOS è firmato e non riceve altre patch. La presenza '
            'di BORE e delle altre opzioni si controlla dal Kconfig della '
            'versione scaricata. '
            'Senza (versioni prima della 6.17): la loro serie base e BORE '
            'sopra kernel.org, ognuna provata prima a secco; se una non si '
            'applica ci si ferma, e la volta dopo l\'albero si rifà da capo.',
        soloLaPrimaVolta: true,
      ),
    Passo(
      'base',
      s.base == 'in-uso' && r.configPartenza.isNotEmpty
          ? 'Parti dalla configurazione del kernel in uso'
          : 'Parti dalla configurazione di serie',
      s.base == 'in-uso' && r.configPartenza.isNotEmpty
          ? 'Da ${r.configPartenza}: tutto quello che il kernel di adesso '
                'sa fare, prima di scremare.'
          : 'make defconfig: la configurazione minima di serie. Attenzione: '
                'localmodconfig toglie e non aggiunge, quindi un driver che '
                'defconfig non ha non ci sarà nemmeno se è nell\'elenco.',
      comando: s.base == 'in-uso' && r.configPartenza.isNotEmpty
          ? const []
          : [...make, 'defconfig'],
    ),
    Passo(
      'allinea',
      'Allinea alla nuova versione',
      'Le opzioni nuove prendono il loro valore di serie, senza domande.',
      comando: [...make, 'olddefconfig'],
    ),
    Passo(
      'screma',
      'Screma i moduli',
      'localmodconfig con l\'elenco della Fucina (${moduli.length} moduli): '
          'tutto quello che non è nell\'elenco esce dalla configurazione.',
      comando: [...make, 'LSMOD=${c.lsmod}', 'localmodconfig'],
    ),
    const Passo(
      'completa',
      'Completa essenziali e scorte',
      'Dall\'albero dei sorgenti: per ogni modulo essenziale, di scorta o '
          'aggiunto a mano che la configurazione non accende, il simbolo '
          'di Kconfig che lo costruisce, messo a «m». È quello che '
          'localmodconfig non fa: toglie e non aggiunge.',
    ),
    Passo(
      'imposta',
      'Applica preset e nome',
      '${impostazioni.length} valori, ognuno col suo perché.',
      comando: configurazioni,
    ),
    Passo(
      'riallinea',
      'Risolvi le dipendenze',
      'Kconfig sistema quello che i valori appena scritti richiedono.',
      comando: [...make, 'olddefconfig'],
    ),
    const Passo(
      'controlla',
      'Controlla che i valori ci siano',
      'Si rilegge il .config: un valore che non ha preso si dice, con il '
          'suo nome.',
    ),
    Passo(
      'compila',
      'Compila',
      'Il kernel e i moduli, con $lavori lavori in parallelo'
          '${conCcache ? ' e ccache' : ''}'
          '${s.profilo.isNotEmpty ? ', col profilo di ${s.profilo}' : ''}.',
      comando: [...make, '-j$lavori', 'bzImage', 'modules'],
    ),
    Passo(
      'rilascio',
      'Leggi il nome del kernel',
      'Deve essere ${s.rilascio}: se è diverso, qualcosa ha cambiato il '
          'nome e ci si ferma.',
      comando: [...make, '-s', 'kernelrelease'],
    ),
    Passo(
      'moduli',
      'Prepara i moduli',
      'Copiati e alleggeriti nella cartella d\'uscita, non ancora nel '
          'sistema.',
      comando: [
        ...make,
        'INSTALL_MOD_PATH=${c.uscita}',
        'INSTALL_MOD_STRIP=1',
        'modules_install',
      ],
    ),
    Passo(
      'impacchetta',
      'Prepara il kernel da installare',
      'L\'immagine e la configurazione accanto ai moduli'
          '${s.autofdo ? ', e il vmlinux da parte per il profilo' : ''}. Da '
          'qui in poi manca solo «Installa», che chiede la password.',
    ),
    if (s.provaAvvio)
      const Passo(
        'avvia',
        'Prova d\'avvio in QEMU',
        'Il kernel appena fatto parte in una macchina virtuale con un '
            'initramfs minimo, e deve arrivare allo spazio utente. Non tocca '
            '/boot e non prova i tuoi dischi: dice se il kernel parte.',
      ),
  ];

  return Ricetta(
    scelte: s,
    moduli: moduli,
    perFamiglia: perFamiglia,
    tolti: tolti,
    impostazioni: impostazioni,
    passi: passi,
    rilascio: s.rilascio,
    avvisi: avvisi,
    requisitiMancanti: mancanti.toSet().toList()..sort(),
    parallelismo: parallelismo,
  );
}

/// Mantiene la pila LSM attiva sul computer. capability è fornito sempre dal
/// kernel e non compare in CONFIG_LSM. Se compare un LSM sconosciuto, non si
/// riscrive la lista: ridurla a quelli noti potrebbe disattivare una protezione.
List<Impostazione> impostazioniLsmAttivi(Rilievo r, List<String> avvisi) {
  final stato = r.configKernel['statoLive'];
  if (stato is! Map) return const [];
  final valore = stato['lsmAttivi'];
  if (valore is! List) return const [];
  final attivi = [
    for (final x in valore)
      if (x is String && x.isNotEmpty && x != 'capability') x,
  ];
  if (attivi.isEmpty) return const [];

  const simboli = {
    'landlock': 'SECURITY_LANDLOCK',
    'yama': 'SECURITY_YAMA',
    'apparmor': 'SECURITY_APPARMOR',
    'selinux': 'SECURITY_SELINUX',
    'smack': 'SECURITY_SMACK',
    'tomoyo': 'SECURITY_TOMOYO',
    'lockdown': 'SECURITY_LOCKDOWN_LSM',
    'integrity': 'INTEGRITY',
    'bpf': 'BPF_LSM',
    'loadpin': 'SECURITY_LOADPIN',
    'safe_setid': 'SECURITY_SAFESETID',
  };
  final ignoti = attivi.where((nome) => !simboli.containsKey(nome)).toList();
  if (ignoti.isNotEmpty) {
    avvisi.add(
      'LSM attivi non riconosciuti (${ignoti.join(', ')}): non modifico automaticamente CONFIG_LSM per evitare di escludere una protezione.',
    );
    return const [];
  }

  return [
    const Impostazione(
      'SECURITY',
      'y',
      'Mantiene attivo il framework LSM rilevato sul sistema.',
    ),
    for (final nome in attivi)
      Impostazione(
        simboli[nome]!,
        'y',
        'Mantiene il modulo LSM «$nome» attivo sul sistema.',
      ),
    Impostazione(
      'LSM',
      attivi.join(','),
      'Mantiene l’ordine degli LSM attivi rilevato dal kernel in esecuzione.',
    ),
  ];
}

/// I filesystem montati e compilati direttamente nel kernel non compaiono in
/// /proc/modules: con defconfig potrebbero sparire. Quelli modulari restano
/// invece nella whitelist LSMOD raccolta dal rilievo.
List<Impostazione> _impostazioniFilesystemAttivi(
  Rilievo r,
  List<String> avvisi,
) {
  final stato = r.configKernel['statoLive'];
  final montatiRaw = stato is Map ? stato['filesystemMontati'] : null;
  if (montatiRaw is! List) return const [];
  final montati = {
    for (final x in montatiRaw)
      if (x is String && RegExp(r'^[A-Za-z0-9_.-]{1,48}$').hasMatch(x)) x,
  };
  if (montati.isEmpty) return const [];

  const simboli = <String, List<String>>{
    'ext2': ['EXT2_FS'],
    'ext3': ['EXT4_FS'],
    'ext4': ['EXT4_FS'],
    'btrfs': ['BTRFS_FS'],
    'xfs': ['XFS_FS'],
    'f2fs': ['F2FS_FS'],
    'vfat': ['FAT_FS'],
    'msdos': ['FAT_FS'],
    'exfat': ['EXFAT_FS'],
    'ntfs3': ['NTFS3_FS'],
    'ntfs': ['NTFS_FS'],
    'iso9660': ['ISO9660_FS'],
    'udf': ['UDF_FS'],
    'squashfs': ['SQUASHFS'],
    'overlay': ['OVERLAY_FS'],
    'tmpfs': ['TMPFS'],
    'ramfs': ['RAMFS'],
    'proc': ['PROC_FS'],
    'sysfs': ['SYSFS'],
    'devtmpfs': ['DEVTMPFS'],
    'efivarfs': ['EFIVAR_FS'],
    'fuse': ['FUSE_FS'],
    'fuseblk': ['FUSE_FS'],
    'cgroup': ['CGROUPS'],
    'cgroup2': ['CGROUPS'],
    'nfs': ['NFS_FS'],
    'nfs4': ['NFS_FS'],
    'cifs': ['CIFS'],
    'autofs': ['AUTOFS_FS'],
    'hugetlbfs': ['HUGETLBFS'],
    'devpts': ['UNIX98_PTYS'],
    'securityfs': ['SECURITYFS'],
    'debugfs': ['DEBUG_FS'],
    'tracefs': ['TRACING'],
    'configfs': ['CONFIGFS_FS'],
    'bpf': ['BPF_SYSCALL'],
    'pstore': ['PSTORE'],
    'rootfs': [],
    'fusectl': ['FUSE_FS'],
    'binfmt_misc': ['BINFMT_MISC'],
    'mqueue': ['POSIX_MQUEUE'],
    'rpc_pipefs': ['SUNRPC'],
  };
  final gruppi = r.configKernel['famiglie'];
  if (r.configKernel['disponibile'] != true || gruppi is! List) {
    avvisi.add(
      'I filesystem montati (${montati.join(', ')}) non si possono '
      'confrontare con la configurazione del kernel: la whitelist dei '
      'filesystem integrati non è stata estesa.',
    );
    return const [];
  }
  final integrati = <String>{};
  final modulari = <String>{};
  for (final gruppo in gruppi.whereType<Map>()) {
    integrati.addAll(
      (gruppo['integrate'] as List? ?? const []).whereType<String>().map(
        (s) => s.replaceFirst('CONFIG_', ''),
      ),
    );
    modulari.addAll(
      (gruppo['modulari'] as List? ?? const []).whereType<String>().map(
        (s) => s.replaceFirst('CONFIG_', ''),
      ),
    );
  }

  final fuori = <Impostazione>[];
  final nonMappati = <String>[];
  for (final tipo in montati) {
    final opzioni =
        simboli[tipo] ?? (tipo.startsWith('fuse.') ? simboli['fuse'] : null);
    if (opzioni == null) {
      nonMappati.add(tipo);
      continue;
    }
    for (final opzione in opzioni) {
      if (integrati.contains(opzione)) {
        fuori.add(
          Impostazione(
            opzione,
            'y',
            'Filesystem «$tipo» montato sul sistema e integrato nel kernel '
                'attuale: lo mantengo nella nuova configurazione.',
          ),
        );
      } else if (!modulari.contains(opzione)) {
        nonMappati.add('$tipo ($opzione)');
      }
    }
  }
  if (nonMappati.isNotEmpty) {
    avvisi.add(
      'Non ho trovato una corrispondenza affidabile nella configurazione '
      'per i filesystem montati: ${nonMappati.toSet().join(', ')}. '
      'Controlla questi componenti nella ricetta prima di compilare.',
    );
  }
  return {for (final i in fuori) i.simbolo: i}.values.toList();
}

/// Il rilievo conosce quell'attrezzo? Un rilievo vecchio (o finto, nelle
/// prove) che non lo elenca non deve far dire «manca».
bool _conosciuto(Rilievo r, String nome) =>
    (r.macchina['attrezzi'] as List? ?? const []).any(
      (a) => a is Map && a['nome'] == nome,
    );

/// La famiglia dei moduli di una scorta che il rilievo non ha visto.
String famigliaDiScorta(String scorta) => switch (scorta) {
  'filesystem' => 'filesystem',
  'chiavette' => 'chiavette',
  'controller' => 'controller',
  'bluetooth' => 'bluetooth',
  'vpn' => 'rete',
  'virtualizzazione' => 'virtualizzazione',
  'webcam' => 'webcam',
  'stampa' => 'stampa',
  _ => 'altro',
};

/// Gli argomenti di `scripts/config` per un valore. I booleani hanno i loro
/// verbi; numeri e stringhe no, e la differenza conta: `--set-val` scrive il
/// valore così com'è, `--set-str` lo mette fra virgolette.
List<String> _argomentiConfig(Impostazione i) {
  switch (i.valore) {
    case 'y':
      return ['--enable', i.simbolo];
    case 'n':
      return ['--disable', i.simbolo];
    case 'm':
      return ['--module', i.simbolo];
  }
  if (RegExp(r'^-?[0-9]+$').hasMatch(i.valore)) {
    return ['--set-val', i.simbolo, i.valore];
  }
  return ['--set-str', i.simbolo, i.valore];
}

/// Controlla un `.config` contro le impostazioni chieste. Restituisce le
/// righe da dire: una per valore che non ha preso.
///
/// Un valore può non prendere perché il simbolo non esiste in questa versione
/// (`X86_NATIVE_CPU` prima della 6.16), o perché Kconfig l'ha cambiato per
/// una dipendenza che manca (LTO senza Clang). Lo si segnala; il target CPU
/// nativo invece è un requisito esplicito e l'officina si ferma se non viene
/// attivato.
///
/// ── I «choice» si guardano insieme ──────────────────────────────────────
///
/// Tick, prelazione, debug, LTO, pagine enormi: in ognuno si accende una voce
/// e si spengono le altre. Se la voce chiesta non c'è, Kconfig ne accende
/// un'altra, e contando voce per voce uscirebbero due righe per lo stesso
/// fatto («PREEMPT doveva essere y» e «PREEMPT_LAZY doveva essere n»). Si
/// dice una riga sola: che cosa si era chiesto, e che cosa è rimasto.
List<String> controllaConfig(String config, List<Impostazione> chieste) {
  final valori = leggiConfig(config);
  String? visto(String s) => valori[s];
  bool uguale(Impostazione i) {
    final v = visto(i.simbolo);
    if (v == null) return i.valore == 'n';
    return v == i.valore || v == '"${i.valore}"';
  }

  final fuori = <String>[];
  final giaDetti = <String>{};
  for (final gruppo in sceltePerGruppo) {
    final chiesteQui = chieste
        .where((i) => gruppo.contains(i.simbolo))
        .toList();
    final accesa = chiesteQui.where((i) => i.valore == 'y').toList();
    if (accesa.length != 1) continue;
    giaDetti.addAll(chiesteQui.map((i) => i.simbolo));
    if (visto(accesa.single.simbolo) == 'y') continue;
    final rimasta = gruppo.where((s) => visto(s) == 'y').toList();
    fuori.add(
      rimasta.isEmpty
          ? '${accesa.single.simbolo} non ha preso, e nessun\'altra voce dello '
                'stesso gruppo è accesa: in questa versione quel gruppo non c\'è, '
                'o dipende da qualcosa che manca.'
          : '${accesa.single.simbolo} non si può scegliere in questa versione '
                '(o su questo processore): è rimasto ${rimasta.join(', ')}.',
    );
  }
  for (final i in chieste) {
    if (giaDetti.contains(i.simbolo) || uguale(i)) continue;
    final v = visto(i.simbolo);
    fuori.add(
      v == null && i.simbolo == 'SCHED_BORE'
          ? 'I sorgenti selezionati non espongono CONFIG_SCHED_BORE: '
                'non posso confermare che BORE sia presente o attivo.'
          : v == null
          ? '${i.valore} per ${i.simbolo} non ha preso: in questa versione il '
                'simbolo non esiste, o dipende da qualcosa che manca.'
          : '${i.simbolo} doveva essere ${i.valore} ed è $v: Kconfig l\'ha '
                'cambiato per una dipendenza.',
    );
  }
  return fuori;
}

/// Un `.config` letto: simbolo (senza `CONFIG_`) → valore così com'è
/// scritto, `n` per le righe «is not set». Un simbolo che non c'è non c'è.
Map<String, String> leggiConfig(String config) {
  final valori = <String, String>{};
  for (final riga in config.split('\n')) {
    final m = RegExp(r'^CONFIG_([A-Za-z0-9_]+)=(.*)$').firstMatch(riga);
    if (m != null) {
      valori[m.group(1)!] = m.group(2)!;
      continue;
    }
    final n = RegExp(r'^# CONFIG_([A-Za-z0-9_]+) is not set$').firstMatch(riga);
    if (n != null) valori[n.group(1)!] = 'n';
  }
  return valori;
}

/// I moduli che il passo «completa» deve trovare accesi: gli essenziali,
/// quelli delle scorte scelte e quelli aggiunti a mano — non i tolti.
/// Sono i moduli per cui la Fucina ha promesso qualcosa a chi guarda.
Set<String> daCompletare(Ricetta r, Rilievo ril) {
  final scelte = {
    ...r.scelte.scorte,
    ...?combinaPreset(r.scelte.preset)?.scorte,
  };
  return {
    ...ril.avvio.moduli,
    for (final sc in scorte)
      if (scelte.contains(sc.id))
        ...sc.moduli.where((m) => !r.scelte.tolti.contains(m)),
    ...r.scelte.aggiunti.where((m) => !r.scelte.tolti.contains(m)),
  }.where((m) => r.moduli.contains(m)).toSet();
}

/// I «choice» di Kconfig che la Fucina tocca. Vedi [controllaConfig].
const List<Set<String>> sceltePerGruppo = [
  {'HZ_100', 'HZ_250', 'HZ_300', 'HZ_1000'},
  {
    'PREEMPT_NONE',
    'PREEMPT_VOLUNTARY',
    'PREEMPT',
    'PREEMPT_LAZY',
    'PREEMPT_RT',
  },
  {
    'DEBUG_INFO_NONE',
    'DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT',
    'DEBUG_INFO_DWARF4',
    'DEBUG_INFO_DWARF5',
  },
  {'LTO_NONE', 'LTO_CLANG_THIN', 'LTO_CLANG_FULL', 'LTO_CLANG_THIN_DIST'},
  {'X86_NATIVE_CPU', 'GENERIC_CPU', 'MZEN4'},
  {
    'TRANSPARENT_HUGEPAGE_ALWAYS',
    'TRANSPARENT_HUGEPAGE_MADVISE',
    'TRANSPARENT_HUGEPAGE_NEVER',
  },
];

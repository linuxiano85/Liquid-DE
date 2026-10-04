import 'modprobed.dart';
import 'dart:convert';
import 'dart:io';

import 'alias.dart';
import 'catalogo.dart';

/// Il rilievo: che cosa c'è in questo computer e che cosa lo fa funzionare.
///
/// ── Da dove nasce ──────────────────────────────────────────────────────────
///
/// Giacomo, 30 settembre 2026: la vecchia utility incrociava «lspci, lsusb,
/// localmodconfig e modprobe per avere la lista esatta di tutto quello che ci
/// serve». L'idea dell'incrocio è giusta e resta. Cambiano le fonti, perché
/// `lspci` e `lsusb` vedono solo due bus: i dispositivi ACPI, I²C, platform e
/// HID — touchpad, sensori, il controller della tastiera del portatile —
/// sono proprio quelli che, dimenticati, lasciano un kernel che non si
/// avvia o non si guida.
///
/// ── Le quattro fonti, e che cosa vuol dire ognuna ────────────────────────
///
///  · **legato** — un dispositivo in `/sys` ha un driver attaccato, e quel
///    driver sta in un modulo. È la prova più forte: non «potrebbe servire»,
///    ma «sta lavorando adesso».
///  · **caricato** — il modulo è in `/proc/modules`. Comprende i moduli che
///    non guidano un dispositivo: filesystem, firewall, cifratura.
///  · **modprobed** — il modulo è nel diario di `modprobed-db`, cioè è stato
///    caricato almeno una volta da quando il diario esiste. È la sola fonte
///    che ricorda la chiavetta di martedì scorso.
///  · **essenziale** — il modulo serve ad AVVIARE: il filesystem della
///    radice, il controller del disco su cui sta, la cifratura, la tastiera
///    con cui si scrive la password del disco. Si tiene sempre, e non si può
///    togliere dall'interfaccia.
///
/// C'è una quinta parola, **candidato**, che non vuol dire «tienilo»: è un
/// modulo che saprebbe guidare un dispositivo rimasto SENZA driver. Se non ha
/// un driver adesso non lo stai usando — ma magari è la scheda Bluetooth che
/// hai spento. Si mostra, e decide chi guarda.
///
/// ── Guarda e basta ─────────────────────────────────────────────────────────
///
/// Come l'inventario di Manutenzione: qui dentro non si scrive niente, non si
/// carica niente, non si lancia niente. Una prova lo pretende.
class Rilevatore {
  /// La radice del filesystem da guardare. `/` sul computer vero; una
  /// cartella finta nelle prove, costruita con file e collegamenti veri.
  final String radice;

  /// L'ambiente, per trovare `modprobed.db` e il PATH.
  final Map<String, String> ambiente;

  /// Racconta le tappe, come l'inventario di Manutenzione.
  final void Function(String fase, String testo, int fatte, int quante)?
      racconta;

  /// Quanti processori ha la macchina. Si passa perché nelle prove non sia
  /// quello di chi le lancia.
  final int nuclei;

  Rilevatore({
    String radice = '/',
    Map<String, String>? ambiente,
    this.racconta,
    int? nuclei,
  })  : radice = radice.endsWith('/') ? radice : '$radice/',
        ambiente = ambiente ?? Platform.environment,
        nuclei = nuclei ?? Platform.numberOfProcessors;

  String _p(String relativo) => '$radice$relativo';

  void _dici(String fase, String testo, int fatte) =>
      racconta?.call(fase, testo, fatte, 5);

  Future<Rilievo> rileva() async {
    final avvisi = <String>[];

    _dici('kernel', 'Leggo il kernel in uso.', 0);
    final rilascio = (await _leggi('proc/sys/kernel/osrelease')).trim();
    final cartellaModuli = await _cartellaModuli(rilascio);
    if (cartellaModuli == null) {
      avvisi.add('Non trovo i moduli del kernel in uso ($rilascio): i '
          'dispositivi si vedono, ma non so dire quale modulo li guidi.');
    }

    _dici('dispositivi', 'Guardo tutti i dispositivi in /sys.', 1);
    // Prima i dispositivi, poi l'indice: così l'indice tiene solo le regole
    // dei bus che hanno davvero un dispositivo senza driver.
    final grezzi = await _dispositiviGrezzi();
    final busCercati = {
      for (final g in grezzi)
        if (g.driver == null &&
            !_senzaLegame.contains(_primaDeiDuePunti(g.modalias)))
          ?IndiceAlias.busDi(g.modalias),
    };
    final indice = cartellaModuli == null
        ? IndiceAlias()
        : IndiceAlias.daTesti(
            alias: await _leggi('$cartellaModuli/modules.alias'),
            dep: await _leggi('$cartellaModuli/modules.dep'),
            incorporati: await _leggi('$cartellaModuli/modules.builtin'),
            soloBus: busCercati,
          );
    final dispositivi = _dispositivi(grezzi, indice);

    _dici('moduli', 'Leggo i moduli caricati e il diario di modprobed.', 2);
    // ── Un kernel senza moduli ──────────────────────────────────────────
    //
    // Senza `CONFIG_MODULES` non c'è /proc/modules, e non ci sono gli indici
    // in /usr/lib/modules: è la macchina virtuale di prova (6.18 tutto
    // dentro), ed è il caso di parecchi kernel di macchine virtuali e di
    // schede. Il rilievo allora vede solo gli essenziali, per nome, e la
    // scrematura non ha niente da scremare. Prima del 1° ottobre 2026 non lo
    // diceva nessuno: si vedevano «8 moduli» e basta.
    final monolitico = !await File(_p('proc/modules')).exists();
    if (monolitico) {
      avvisi.add('Il kernel in uso non carica moduli: ha tutto dentro. Il '
          'rilievo vede i dispositivi ma non sa dire quale modulo li '
          'guiderebbe, e partendo dalla sua configurazione localmodconfig non '
          'toglie niente. Essenziali e scorte si cercano nei sorgenti del '
          'kernel nuovo e si accendono da lì.');
    }
    final caricati = await _caricati();
    final esterni = await _esterni();
    if (esterni.isNotEmpty) {
      avvisi.add('Moduli esterni al kernel in uso: ${esterni.join(', ')}. '
          'Non vengono dai sorgenti del kernel, quindi il kernel nuovo non li '
          'avrà: se uno di loro è il driver della scheda video (NVIDIA), il '
          'kernel nuovo partirà senza grafica.');
    }
    final diario = await _modprobed();
    if (!diario.presente) {
      avvisi.add('Il diario di modprobed-db è assente, vuoto o non leggibile. '
          'Senza, il kernel conosce solo quello che è collegato adesso: una '
          'chiavetta o un controller usati ieri non ci sono.');
    }

    _dici('avvio', 'Cerco quello che serve ad avviare.', 3);
    final avvio = await _avvio();
    if (avvio.dispositivoRadice.isNotEmpty &&
        !avvio.dispositivoRadice.startsWith('/dev/')) {
      avvisi.add('La radice sta su «${avvio.dispositivoRadice}» '
          '(${avvio.tipoRadice}), che non è un disco: la Fucina non sa '
          'seguirne la catena, e non può garantire che il kernel nuovo la '
          'monti. ZFS, per esempio, è un modulo esterno.');
    }

    _dici('macchina', 'Guardo processore, memoria e attrezzi.', 4);
    final macchina = await _macchina(rilascio);
    macchina['monolitico'] = monolitico;
    final partenza = await _configPartenza(rilascio);
    if (partenza.endsWith('/fucina-partenza.config')) {
      avvisi.add('Stai usando un kernel della Fucina: si parte dalla '
          'configurazione da cui era partito lui ($partenza), non dalla sua, '
          'che è già scremata. Altrimenti ogni kernel nuovo perderebbe quello '
          'che il precedente aveva tolto, e non lo ritroverebbe più.');
    }

    // ── L'incrocio ─────────────────────────────────────────────────────
    final moduli = <String, VoceModulo>{};
    VoceModulo voce(String nome) => moduli.putIfAbsent(
        nome,
        () => VoceModulo(
              nome,
              famigliaDi(nome, indice.percorsi[nome]),
              indice.percorsi[nome],
              indice.incorporati.contains(nome),
            ));

    for (final d in dispositivi) {
      if (d.modulo != null) {
        final v = voce(d.modulo!);
        v.fonti.add('legato');
        v.dispositivi++;
      }
    }
    for (final m in caricati) {
      voce(m).fonti.add('caricato');
    }
    for (final m in diario.moduli) {
      voce(m).fonti.add('modprobed');
    }
    for (final m in avvio.moduli) {
      voce(m).fonti.add('essenziale');
    }
    // I candidati per ultimi, e solo su voci che non hanno già una ragione
    // più forte: un modulo caricato che è ANCHE candidato di un altro
    // dispositivo è un modulo caricato.
    //
    // E non per i doppioni: lo stesso dispositivo ACPI compare spesso due
    // volte in /sys — il nodo ACPI, senza driver, e il dispositivo vero
    // creato da lui, col driver — con lo stesso modalias. Se un dispositivo
    // con quel modalias ha già un driver, il nodo senza non manca di niente.
    final legati = {
      for (final d in dispositivi)
        if (d.driver != null) d.modalias,
    };
    for (final d in dispositivi) {
      if (d.driver != null || legati.contains(d.modalias)) continue;
      for (final m in d.candidati) {
        if (moduli[m]?.tenutoDiSerie == true) continue;
        voce(m).fonti.add('candidato');
      }
    }

    _dici('fatto', 'Trovati ${dispositivi.length} dispositivi e '
        '${moduli.length} moduli.', 5);

    return Rilievo(
      rilascio: rilascio,
      macchina: macchina,
      dispositivi: dispositivi,
      moduli: moduli,
      avvio: avvio,
      modprobed: diario,
      configPartenza: partenza,
      indiceRegole: indice.regoleLette,
      avvisi: avvisi,
    );
  }

  // ── Le letture ─────────────────────────────────────────────────────────

  /// Dove sta la configurazione del kernel in uso, relativa alla radice, o
  /// una stringa vuota. Tre posti, in ordine: il kernel stesso
  /// (`/proc/config.gz`, se è compilato con `IKCONFIG_PROC`), la copia che
  /// Debian e Fedora mettono in `/boot`, e quella delle intestazioni, che su
  /// Arch c'è se è installato `linux-headers`.
  ///
  /// Su un kernel della Fucina, prima di tutto, la configurazione da cui era
  /// partito lui: l'officina la mette accanto ai suoi moduli
  /// (`fucina-partenza.config`). Ripartire da `/proc/config.gz` vorrebbe
  /// dire scremare una configurazione già scremata, e un driver tolto una
  /// volta non tornerebbe più. (Trovato rileggendo la catena il 1° ottobre
  /// 2026.)
  Future<String> _configPartenza(String rilascio) async {
    for (final c in [
      if (rilascio.contains('-fucina-')) ...[
        'usr/lib/modules/$rilascio/fucina-partenza.config',
        'lib/modules/$rilascio/fucina-partenza.config',
      ],
      'proc/config.gz',
      if (rilascio.isNotEmpty) 'boot/config-$rilascio',
      if (rilascio.isNotEmpty) 'usr/lib/modules/$rilascio/build/.config',
    ]) {
      if (await File(_p(c)).exists()) return '/$c';
    }
    return '';
  }

  /// Un file letto per intero, o una stringa vuota. In `/sys` e `/proc` un
  /// file può sparire fra l'elenco e la lettura (un dispositivo scollegato),
  /// o non essere leggibile da un utente: non è un errore del rilievo.
  Future<String> _leggi(String relativo) async {
    try {
      return await File(_p(relativo)).readAsString();
    } catch (_) {
      return '';
    }
  }

  /// `/usr/lib/modules/<rilascio>` su Arch e sulle distribuzioni unite,
  /// `/lib/modules/<rilascio>` sulle altre. Relativo alla radice.
  Future<String?> _cartellaModuli(String rilascio) async {
    if (rilascio.isEmpty) return null;
    for (final base in const ['usr/lib/modules', 'lib/modules']) {
      final c = '$base/$rilascio';
      if (await File(_p('$c/modules.dep')).exists() ||
          await File(_p('$c/modules.alias')).exists()) {
        return c;
      }
    }
    return null;
  }

  /// Ogni `modalias` sotto `/sys/devices`, con il driver che lo guida.
  ///
  /// I collegamenti NON si seguono: `/sys` ne è pieno (`subsystem`,
  /// `device`, `driver`, `port`) e molti tornano indietro. Seguirli vorrebbe
  /// dire visitare lo stesso dispositivo dieci volte, o per sempre.
  Future<List<({String cartella, String modalias, String? driver, String? modulo})>>
      _dispositiviGrezzi() async {
    final base = Directory(_p('sys/devices'));
    final fuori =
        <({String cartella, String modalias, String? driver, String? modulo})>[];
    if (!await base.exists()) return fuori;

    final tutti = await _fileModalias(base);
    tutti.sort();

    for (final f in tutti) {
      final alias = (await _leggiAssoluto(f)).trim();
      if (alias.isEmpty) continue;
      final cartella = f.substring(0, f.length - '/modalias'.length);
      final driver = await _nomeDelCollegamento('$cartella/driver');
      final modulo = driver == null
          ? null
          : await _nomeDelCollegamento('$cartella/driver/module');
      fuori.add((cartella: cartella, modalias: alias, driver: driver, modulo: modulo));
    }
    return fuori;
  }

  /// I file `modalias` sotto /sys/devices. I collegamenti non si seguono:
  /// in /sys tornano indietro (vedi sopra).
  Future<List<String>> _fileModalias(Directory base) async {
    final tutti = <String>[];
    await for (final e in base
        .list(recursive: true, followLinks: false)
        .handleError((_) {})) {
      if (e is File && e.path.endsWith('/modalias')) tutti.add(e.path);
    }
    return tutti;
  }

  List<Dispositivo> _dispositivi(
      List<({String cartella, String modalias, String? driver, String? modulo})>
          grezzi,
      IndiceAlias indice) {
    final radiceSys = Directory(_p('sys/devices')).path;
    return [
      for (final g in grezzi)
        Dispositivo(
          percorso: g.cartella.substring(radiceSys.length),
          modalias: g.modalias,
          bus: _primaDeiDuePunti(g.modalias),
          driver: g.driver,
          modulo: g.modulo == null ? null : normalizza(g.modulo!),
          candidati: g.driver == null &&
                  !_senzaLegame.contains(_primaDeiDuePunti(g.modalias))
              ? indice.moduliPer(g.modalias)
              : const {},
        ),
    ];
  }

  static String _primaDeiDuePunti(String alias) {
    final due = alias.indexOf(':');
    return due > 0 ? alias.substring(0, due) : '';
  }

  /// I bus i cui dispositivi non hanno MAI un driver legato: la CPU (i suoi
  /// alias caricano i moduli di cifratura e KVM, e udev li carica da sé) e
  /// gli ingressi (`input`, che si attaccano ai gestori e non ai driver).
  /// Presi come «dispositivi senza driver» riempirebbero l'elenco di falsi
  /// allarmi.
  static const Set<String> _senzaLegame = {'cpu', 'input'};

  Future<String> _leggiAssoluto(String percorso) async {
    try {
      return await File(percorso).readAsString();
    } catch (_) {
      return '';
    }
  }

  /// L'ultimo pezzo di dove punta un collegamento, o `null` se non c'è.
  /// `driver → ../../../bus/pci/drivers/nvme` dà `nvme`.
  Future<String?> _nomeDelCollegamento(String percorso) async {
    try {
      final t = await Link(percorso).target();
      final nome = t.split('/').where((s) => s.isNotEmpty).last;
      return nome.isEmpty ? null : nome;
    } catch (_) {
      return null;
    }
  }

  Future<Set<String>> _caricati() async {
    final fuori = <String>{};
    for (final riga in (await _leggi('proc/modules')).split('\n')) {
      final nome = riga.split(' ').first.trim();
      if (nome.isNotEmpty) fuori.add(normalizza(nome));
    }
    return fuori;
  }

  /// I moduli caricati che non vengono dall'albero del kernel: in
  /// `/proc/modules` hanno fra parentesi la «O» (fuori albero) o la «P»
  /// (proprietario). NVIDIA, VirtualBox, ZFS: si compilano con DKMS per ogni
  /// kernel, e la Fucina non lo fa.
  Future<List<String>> _esterni() async {
    final fuori = <String>[];
    for (final riga in (await _leggi('proc/modules')).split('\n')) {
      final m = RegExp(r'\(([A-Z]+)\)\s*$').firstMatch(riga.trim());
      if (m == null) continue;
      final segni = m.group(1)!;
      if (segni.contains('O') || segni.contains('P')) {
        fuori.add(normalizza(riga.split(' ').first));
      }
    }
    return fuori..sort();
  }

  Future<DiarioModprobed> _modprobed() async {
    final diario = await leggiModprobed(ambiente);
    return DiarioModprobed(diario.percorso, diario.moduli);
  }

  // ── Quello che serve ad avviare ───────────────────────────────────────

  Future<Avvio> _avvio() async {
    final moduli = <String>{};
    final perche = <String, String>{};
    void tieni(String m, String ragione) {
      final n = normalizza(m);
      if (moduli.add(n)) perche[n] = ragione;
    }

    // La tastiera che serve per scrivere la password del disco, prima che
    // il sistema sia su: è nell'initramfs o non c'è.
    for (final m in const ['hid_generic', 'usbhid', 'xhci_pci', 'xhci_hcd',
                           'ehci_pci', 'ehci_hcd', 'evdev']) {
      tieni(m, 'La tastiera USB all\'avvio, anche per la password del disco.');
    }
    if (await Directory(_p('sys/firmware/efi')).exists()) {
      tieni('efivarfs', 'Il firmware UEFI: bootloader e variabili d\'avvio.');
    }

    var dispositivoRadice = '';
    var tipoRadice = '';
    final montati = <Map<String, String>>[];
    final allAvvio = await _montaggiDAvvio();
    for (final riga in (await _leggi('proc/mounts')).split('\n')) {
      final c = riga.split(' ');
      if (c.length < 3) continue;
      final dev = _senzaOttali(c[0]);
      final dove = _senzaOttali(c[1]);
      final tipo = c[2];
      if (dove == '/') {
        dispositivoRadice = dev;
        tipoRadice = tipo;
      }
      if (!dev.startsWith('/dev/')) continue;
      montati.add({'dispositivo': dev, 'dove': dove, 'tipo': tipo});
    }

    // ── Essenziale è quello che serve AD AVVIARE ─────────────────────────
    //
    // La radice e quello che sta in /etc/fstab. Non la chiavetta montata in
    // questo momento in /run/media: quella è «in uso», si tiene di serie, ma
    // si deve poter togliere — segnarla essenziale vorrebbe dire bloccare
    // per sempre i driver USB di chi aveva una chiavetta attaccata mentre si
    // guardava.
    // ── Anche quello di fstab che adesso non è montato ─────────────────
    //
    // La partizione EFI montata con `x-systemd.automount` compare in
    // /proc/mounts solo dopo che qualcuno l'ha aperta: guardando nel momento
    // sbagliato, il suo `vfat` non c'è. Il tipo scritto in fstab c'è sempre.
    //
    // E la catena del suo disco, per la stessa ragione: il controller, la
    // cifratura, LVM di un disco d'avvio che adesso non è montato servono lo
    // stesso all'avvio. (Trovato da una revisione automatica della PR.)
    final catena = <String>[];
    for (final e in allAvvio.entries) {
      final tipo = e.value.tipo;
      if (tipo != 'auto' && !tipo.startsWith('fuse.')) {
        for (final mod in _moduliDelFilesystem(tipo)) {
          tieni(mod, 'Filesystem di «${e.key}» (da /etc/fstab).');
        }
      }
      final dev = _devDaFstab(e.value.sorgente);
      if (dev == null) continue;
      final nome = await _nomeDelBlocco(dev);
      if (nome != null) await _catena(nome, catena, tieni, e.key, 0);
    }

    for (final m in montati) {
      final dove = m['dove']!;
      if (dove != '/' && !allAvvio.containsKey(dove)) continue;
      for (final mod in _moduliDelFilesystem(m['tipo']!)) {
        tieni(mod, 'Filesystem di «$dove».');
      }
      // La catena del disco: dal blocco su fino al controller, attraverso
      // cifratura, LVM e RAID. Ogni driver trovato per strada si tiene.
      final nome = await _nomeDelBlocco(m['dispositivo']!);
      if (nome == null) continue;
      await _catena(nome, catena, tieni, dove, 0);
    }

    return Avvio(dispositivoRadice, tipoRadice, moduli, perche, montati);
  }

  /// I punti di montaggio scritti in /etc/fstab, col loro tipo, tranne
  /// quelli `noauto` (che all'avvio non si montano) e lo swap (che non ha un
  /// punto).
  Future<Map<String, ({String sorgente, String tipo})>> _montaggiDAvvio() async {
    final fuori = <String, ({String sorgente, String tipo})>{};
    for (final riga in (await _leggi('etc/fstab')).split('\n')) {
      final r = riga.trim();
      if (r.isEmpty || r.startsWith('#')) continue;
      final c = r.split(RegExp(r'\s+'));
      if (c.length < 3 || c[2] == 'swap' || c[1] == 'none') continue;
      if (c.length > 3 && c[3].split(',').contains('noauto')) continue;
      fuori[_senzaOttali(c[1])] = (sorgente: _senzaOttali(c[0]), tipo: c[2]);
    }
    return fuori;
  }

  /// Da una sorgente di fstab (`UUID=…`, `LABEL=…`, `PARTUUID=…`,
  /// `PARTLABEL=…` o `/dev/…`) al percorso in /dev che la rappresenta, o
  /// `null` se non è un disco.
  static String? _devDaFstab(String sorgente) {
    const nomi = {
      'UUID=': 'by-uuid',
      'LABEL=': 'by-label',
      'PARTUUID=': 'by-partuuid',
      'PARTLABEL=': 'by-partlabel',
    };
    for (final e in nomi.entries) {
      if (sorgente.startsWith(e.key)) {
        final v = sorgente.substring(e.key.length).replaceAll('"', '');
        return v.isEmpty ? null : '/dev/disk/${e.value}/$v';
      }
    }
    return sorgente.startsWith('/dev/') ? sorgente : null;
  }

  /// `/dev/mapper/radice` → `dm-0`, `/dev/nvme0n1p2` → `nvme0n1p2`.
  Future<String?> _nomeDelBlocco(String dev) async {
    final senza = dev.substring('/dev/'.length);
    if (await Directory(_p('sys/class/block/$senza')).exists()) return senza;
    try {
      final t = await Link(_p(senza.isEmpty ? 'dev' : 'dev/$senza')).target();
      final nome = t.split('/').last;
      if (await Directory(_p('sys/class/block/$nome')).exists()) return nome;
    } catch (_) {}
    return null;
  }

  Future<void> _catena(String blocco, List<String> visti,
      void Function(String, String) tieni, String dove, int profondita) async {
    if (profondita > 8 || visti.contains(blocco)) return;
    visti.add(blocco);
    final base = _p('sys/class/block/$blocco');

    // Device mapper: cifratura, LVM.
    final uuid = (await _leggiAssoluto('$base/dm/uuid')).trim();
    if (uuid.isNotEmpty) {
      tieni('dm_mod', 'Device mapper sotto «$dove».');
      if (uuid.startsWith('CRYPT-')) {
        // `sha256_generic` fino al 6.15, `sha256` dopo: si nominano tutti e
        // due, e il passo «completa» dell'officina tace su quello che
        // nell'albero nuovo non c'è.
        for (final m in const ['dm_crypt', 'aesni_intel', 'xts', 'cbc',
                               'essiv', 'sha256_generic', 'sha256']) {
          tieni(m, 'Il disco cifrato di «$dove».');
        }
      }
    }
    // RAID software.
    final livello = (await _leggiAssoluto('$base/md/level')).trim();
    if (livello.isNotEmpty) {
      tieni('md_mod', 'RAID software sotto «$dove».');
      if (livello.startsWith('raid')) {
        tieni(livello == 'raid4' || livello == 'raid5' || livello == 'raid6'
            ? 'raid456' : livello, 'RAID $livello sotto «$dove».');
      }
    }
    // Quello che sta sotto: le partizioni di un volume cifrato o di un RAID.
    try {
      await for (final s in Directory('$base/slaves').list()) {
        await _catena(s.path.split('/').last, visti, tieni, dove,
            profondita + 1);
      }
    } catch (_) {}

    // Su per l'albero dei dispositivi: ogni cartella che ha un driver in un
    // modulo è un anello della catena (disco → controller → bus PCI).
    String reale;
    try {
      reale = await Directory(base).resolveSymbolicLinks();
    } catch (_) {
      return;
    }
    final fine = _p('sys/devices');
    var cartella = reale;
    while (cartella.length > fine.length && cartella.startsWith(fine)) {
      final modulo = await _nomeDelCollegamento('$cartella/driver/module');
      if (modulo != null) tieni(modulo, 'Il controller del disco di «$dove».');
      cartella = cartella.substring(0, cartella.lastIndexOf('/'));
    }
  }

  /// `/proc/mounts` scrive spazi e tabulazioni come `\040` e `\011`.
  static String _senzaOttali(String s) => s.replaceAllMapped(
      RegExp(r'\\([0-7]{3})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 8)));

  /// I moduli di un filesystem. Quasi sempre il nome è lo stesso; qui le
  /// eccezioni, che sono quelle che rompono un avvio.
  static List<String> _moduliDelFilesystem(String tipo) {
    switch (tipo) {
      case 'vfat':
      case 'msdos':
        // FAT vuole anche le code page per leggere i nomi dei file: senza,
        // la partizione EFI non si monta.
        return ['vfat', 'fat', 'nls_cp437', 'nls_iso8859_1', 'nls_ascii'];
      case 'fuseblk':
        return ['fuse'];
      case 'iso9660':
        return ['isofs'];
      case 'ext2':
      case 'ext3':
      case 'ext4':
        return ['ext4'];
      case 'ntfs':
        return ['ntfs3'];
      default:
        return [tipo];
    }
  }

  // ── La macchina ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _macchina(String rilascio) async {
    final cpu = await _leggi('proc/cpuinfo');
    final modello = RegExp(r'^model name\s*:\s*(.+)$', multiLine: true)
            .firstMatch(cpu)
            ?.group(1)
            ?.trim() ??
        '';
    final flags = (RegExp(r'^flags\s*:\s*(.+)$', multiLine: true)
                .firstMatch(cpu)
                ?.group(1) ??
            '')
        .split(' ')
        .toSet();
    final fornitore = RegExp(r'^vendor_id\s*:\s*(\S+)', multiLine: true)
            .firstMatch(cpu)
            ?.group(1) ??
        '';
    final ramKb = int.tryParse(RegExp(r'^MemTotal:\s*(\d+)', multiLine: true)
                .firstMatch(await _leggi('proc/meminfo'))
                ?.group(1) ??
            '') ??
        0;

    return {
      'rilascio': rilascio,
      'cpu': modello,
      'nuclei': nuclei,
      'ramGB': (ramKb / 1024 / 1024 * 10).round() / 10,
      'livelloX86': livelloX86(flags),
      'uefi': await Directory(_p('sys/firmware/efi')).exists(),
      'fornitore': fornitore,
      'cpuPossibili':
          contaElenco(await _leggi('sys/devices/system/cpu/possible')),
      'nodiNuma': await _nodiNuma(),
      'profilo': profiloHw(fornitore, flags, await _rami()),
      'attrezzi': await _attrezzi(),
    };
  }

  /// Quanti nodi di memoria: le cartelle `node<N>` in
  /// `/sys/devices/system/node`. Zero se la cartella non c'è (un kernel
  /// senza NUMA): «non so», e la regola che lo usa non scatta.
  Future<int> _nodiNuma() async {
    var n = 0;
    try {
      await for (final e in Directory(_p('sys/devices/system/node')).list()) {
        if (RegExp(r'/node[0-9]+$').hasMatch(e.path)) n++;
      }
    } catch (_) {}
    return n;
  }

  /// Quanti salti tiene il registro dei salti del processore, come lo vede
  /// perf: `caps/branches` della PMU dei processori (`cpu`, o `cpu_core` sugli
  /// Intel con due tipi di core). Zero se non c'è.
  Future<int> _rami() async {
    for (final pmu in const ['cpu', 'cpu_core']) {
      final v = int.tryParse(
          (await _leggi('sys/bus/event_source/devices/$pmu/caps/branches'))
              .trim());
      if (v != null && v > 0) return v;
    }
    return 0;
  }

  /// `0-15` → 16, `0,2-3` → 3, vuoto → 0. È la forma di
  /// `/sys/devices/system/cpu/possible`.
  static int contaElenco(String testo) {
    var n = 0;
    for (final pezzo in testo.trim().split(',')) {
      final m = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(pezzo.trim());
      if (m == null) continue;
      final a = int.parse(m.group(1)!);
      final b = m.group(2) == null ? a : int.parse(m.group(2)!);
      if (b >= a) n += b - a + 1;
    }
    return n;
  }

  /// ── Si può registrare un profilo AutoFDO qui? ─────────────────────────
  ///
  /// AutoFDO vuole i SALTI, non i campioni normali: perf registra a ogni
  /// campione gli ultimi salti presi (`perf record -b`), e da lì Clang
  /// ricava quali rami si prendono davvero. Serve quindi un registro dei
  /// salti nel processore. Dalla documentazione del kernel
  /// (Documentation/dev-tools/autofdo.rst, 6.13 e seguenti) e dal kernel
  /// stesso (arch/x86/events):
  ///
  ///  · **Intel**: LBR, da Haswell in qua in pratica. Non ha un segno in
  ///    /proc/cpuinfo (solo `arch_lbr`, dagli Alder Lake): lo si vede da
  ///    `caps/branches` della PMU, se il kernel in uso lo espone.
  ///  · **AMD Zen 4 e successivi**: LbrExtV2, segno `amd_lbr_v2`.
  ///  · **AMD Zen 3**: solo gli EPYC con BRS (segno `brs`); i Ryzen Zen 3 no.
  ///    BRS nel kernel è `PERF_EVENTS_AMD_BRS`, che la ricetta accende.
  ///  · **Macchine virtuali**: il registro dei salti quasi mai arriva
  ///    all'ospite.
  ///
  /// L'evento non è nella risposta: lo sceglie l'aiutante di root dal
  /// `tipo`, da un elenco chiuso. Sono i nomi delle tabelle di perf
  /// (tools/perf/pmu-events), che non hanno bisogno di libpfm:
  /// `BR_INST_RETIRED.NEAR_TAKEN` (Intel, da Sandy Bridge) ed
  /// `ex_ret_brn_tkn` (AMD, Zen 1–6, codice 0xc4: lo stesso evento
  /// RETIRED_TAKEN_BRANCH_INSTRUCTIONS della documentazione).
  static Map<String, dynamic> profiloHw(
      String fornitore, Set<String> flags, int rami) {
    final virtuale = flags.contains('hypervisor');
    Map<String, dynamic> no(String perche) => {
          'possibile': false,
          'tipo': '',
          'perche': virtuale
              ? '$perche In una macchina virtuale il registro dei salti '
                  'quasi mai arriva all\'ospite.'
              : perche,
        };
    switch (fornitore) {
      case 'GenuineIntel':
        if (rami > 0 || flags.contains('arch_lbr')) {
          return {
            'possibile': true,
            'tipo': 'intel',
            'perche': 'Intel con LBR${rami > 0 ? ' ($rami salti)' : ''}.',
          };
        }
        return no('Il kernel in uso non mostra l\'LBR del processore (né '
            'caps/branches della PMU, né il segno arch_lbr).');
      case 'AuthenticAMD':
        if (flags.contains('amd_lbr_v2')) {
          return {
            'possibile': true,
            'tipo': 'amd',
            'perche': 'AMD con LbrExtV2 (Zen 4 o più recente).',
          };
        }
        if (flags.contains('brs')) {
          return {
            'possibile': true,
            'tipo': 'amd-brs',
            'perche': 'AMD Zen 3 con BRS (EPYC).',
          };
        }
        return no('Questo AMD non ha un registro dei salti che perf sappia '
            'leggere: serve Zen 4 o più recente (LbrExtV2), o uno Zen 3 EPYC '
            '(BRS). I Ryzen Zen 3 e precedenti no.');
      default:
        return no('Processore «$fornitore»: AutoFDO su x86 vuole un Intel '
            'con LBR o un AMD Zen 4 (o uno Zen 3 EPYC).');
    }
  }

  /// Il livello della micro-architettura x86-64, dai flag della CPU. Sono
  /// le liste dello standard psABI; un flag che manca ferma il livello.
  static String livelloX86(Set<String> f) {
    bool tutti(List<String> l) => l.every(f.contains);
    if (!tutti(['lm', 'cmov', 'cx8', 'fpu', 'fxsr', 'mmx', 'syscall',
                'sse', 'sse2'])) {
      return f.isEmpty ? '' : 'nessuno';
    }
    if (!tutti(['cx16', 'lahf_lm', 'popcnt', 'sse4_1', 'sse4_2', 'ssse3'])) {
      return 'v1';
    }
    if (!tutti(['avx', 'avx2', 'bmi1', 'bmi2', 'f16c', 'fma', 'abm', 'movbe',
                'xsave'])) {
      return 'v2';
    }
    if (!tutti(['avx512f', 'avx512bw', 'avx512cd', 'avx512dq', 'avx512vl'])) {
      return 'v3';
    }
    return 'v4';
  }

  /// Quello che serve per compilare, e se c'è. È la lista delle cose che
  /// mancano sempre la prima volta: `flex` e `bison` per Kconfig, le
  /// intestazioni di `libelf` per objtool, `pahole` per BTF.
  Future<List<Map<String, dynamic>>> _attrezzi() async {
    final cartelle = (ambiente['PATH'] ?? '').split(':')
      ..removeWhere((c) => c.isEmpty);
    Future<bool> programma(String nome) async {
      for (final c in cartelle) {
        final f = File('$c/$nome');
        try {
          if (await f.exists() && (await f.stat()).mode & 0x49 != 0) {
            return true;
          }
        } catch (_) {}
      }
      return false;
    }

    Future<bool> intestazione(String rel) async =>
        await File(_p('usr/include/$rel')).exists();

    return [
      for (final a in attrezzi)
        {
          'nome': a.nome,
          'serve': a.serve,
          'indispensabile': a.indispensabile,
          'presente': a.intestazione
              ? await intestazione(a.file)
              : await programma(a.file),
        },
    ];
  }
}

class Attrezzo {
  final String nome;
  final String file;
  final String serve;
  final bool indispensabile;
  final bool intestazione;
  const Attrezzo(this.nome, this.file, this.serve,
      {this.indispensabile = true, this.intestazione = false});
}

/// L'elenco che si controlla prima di compilare. Il nome è quello del
/// pacchetto di Arch, che è quello che si installa.
const List<Attrezzo> attrezzi = [
  Attrezzo('make', 'make', 'dirigere la compilazione'),
  Attrezzo('gcc', 'gcc', 'compilare con GCC', indispensabile: false),
  Attrezzo('clang', 'clang', 'compilare con Clang e LTO',
      indispensabile: false),
  Attrezzo('lld', 'ld.lld', 'collegare con LLVM', indispensabile: false),
  // `LLVM=1` usa anche llvm-ar, llvm-nm, llvm-objcopy, llvm-strip; e
  // llvm-profgen (stesso pacchetto, su Arch) converte il profilo AutoFDO.
  Attrezzo('llvm', 'llvm-ar', 'gli attrezzi di LLVM=1 e il profilo AutoFDO',
      indispensabile: false),
  Attrezzo('perf', 'perf', 'registrare il profilo AutoFDO',
      indispensabile: false),
  Attrezzo('qemu-system-x86', 'qemu-system-x86_64', 'la prova d\'avvio prima di '
      'installare', indispensabile: false),
  Attrezzo('flex', 'flex', 'leggere Kconfig'),
  Attrezzo('bison', 'bison', 'leggere Kconfig'),
  Attrezzo('bc', 'bc', 'calcolare le costanti del tempo'),
  Attrezzo('perl', 'perl', 'localmodconfig'),
  Attrezzo('cpio', 'cpio', 'impacchettare le intestazioni del kernel'),
  Attrezzo('xz', 'xz', 'aprire i sorgenti scaricati'),
  Attrezzo('patch', 'patch', 'applicare le patch di CachyOS'),
  Attrezzo('gnupg', 'gpg', 'verificare la firma del kernel'),
  Attrezzo('libelf', 'libelf.h', 'objtool', intestazione: true),
  Attrezzo('openssl', 'openssl/ssl.h', 'firmare i moduli',
      intestazione: true),
  Attrezzo('pahole', 'pahole', 'BTF, cioè sched_ext', indispensabile: false),
  Attrezzo('ccache', 'ccache', 'ricompilare in fretta', indispensabile: false),
];

// ── I risultati ─────────────────────────────────────────────────────────

class Dispositivo {
  /// Il percorso sotto `/sys/devices`, che identifica il dispositivo finché
  /// resta attaccato allo stesso posto.
  final String percorso;
  final String modalias;
  final String bus;
  final String? driver;
  final String? modulo;
  final Set<String> candidati;

  const Dispositivo({
    required this.percorso,
    required this.modalias,
    required this.bus,
    this.driver,
    this.modulo,
    this.candidati = const {},
  });

  Map<String, dynamic> toJson() => {
        'percorso': percorso,
        'modalias': modalias,
        'bus': bus,
        'driver': driver,
        'modulo': modulo,
        'candidati': candidati.toList()..sort(),
      };
}

class VoceModulo {
  final String nome;
  final String famiglia;
  final String? percorso;

  /// Già compilato dentro il kernel in uso: non si carica, quindi non
  /// compare in `/proc/modules`, ma c'è.
  final bool incorporato;
  final Set<String> fonti = {};
  int dispositivi = 0;

  VoceModulo(this.nome, this.famiglia, this.percorso, this.incorporato);

  /// Si tiene di serie? Sì, se c'è una ragione vera: tutto tranne
  /// «candidato», che è una possibilità e non una prova.
  bool get tenutoDiSerie => fonti.any((f) => f != 'candidato');

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'famiglia': famiglia,
        'percorso': percorso,
        'incorporato': incorporato,
        'fonti': fonti.toList()..sort(),
        'dispositivi': dispositivi,
        'essenziale': fonti.contains('essenziale'),
        'diSerie': tenutoDiSerie,
      };
}

class DiarioModprobed {
  final String percorso;
  final Set<String> moduli;
  const DiarioModprobed(this.percorso, this.moduli);
  bool get presente => moduli.isNotEmpty;
}

class Avvio {
  final String dispositivoRadice;
  final String tipoRadice;
  final Set<String> moduli;
  final Map<String, String> perche;
  final List<Map<String, String>> montati;
  const Avvio(this.dispositivoRadice, this.tipoRadice, this.moduli,
      this.perche, this.montati);
}

class Rilievo {
  final String rilascio;
  final Map<String, dynamic> macchina;
  final List<Dispositivo> dispositivi;
  final Map<String, VoceModulo> moduli;
  final Avvio avvio;
  final DiarioModprobed modprobed;
  /// Dove sta la configurazione del kernel in uso (percorso assoluto sul
  /// computer vero), o una stringa vuota se non si trova.
  final String configPartenza;
  final int indiceRegole;
  final List<String> avvisi;

  const Rilievo({
    required this.rilascio,
    required this.macchina,
    required this.dispositivi,
    required this.moduli,
    required this.avvio,
    required this.modprobed,
    required this.configPartenza,
    required this.indiceRegole,
    required this.avvisi,
  });

  Map<String, dynamic> toJson() {
    final elenco = moduli.values.toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
    return {
      'rilascio': rilascio,
      'macchina': macchina,
      'dispositivi': [for (final d in dispositivi) d.toJson()],
      'senzaDriver': [
        for (final d in _senzaDriver()) d.toJson(),
      ],
      'moduli': [for (final m in elenco) m.toJson()],
      'famiglie': [for (final f in famiglie) f.toJson()],
      'scorte': [for (final s in scorte) s.toJson()],
      'presets': [for (final p in presets) p.toJson()],
      'avvio': {
        'dispositivo': avvio.dispositivoRadice,
        'tipo': avvio.tipoRadice,
        'montati': avvio.montati,
        'perche': avvio.perche,
      },
      'modprobed': {
        'percorso': modprobed.percorso,
        'presente': modprobed.presente,
        'voci': modprobed.moduli.length,
      },
      'configPartenza': configPartenza,
      'regole': indiceRegole,
      'avvisi': avvisi,
    };
  }

  /// I dispositivi rimasti senza driver che vale la pena mostrare: non i
  /// doppioni ACPI (un altro dispositivo con lo stesso modalias ha già il
  /// driver), e solo se almeno un candidato è davvero fuori dal kernel.
  List<Dispositivo> _senzaDriver() {
    final legati = {
      for (final d in dispositivi)
        if (d.driver != null) d.modalias,
    };
    return [
      for (final d in dispositivi)
        if (d.driver == null &&
            !legati.contains(d.modalias) &&
            d.candidati.any((m) => moduli[m]?.tenutoDiSerie != true))
          d,
    ];
  }

  /// Per le prove e per il registro: il rilievo in una riga.
  @override
  String toString() => jsonEncode({
        'rilascio': rilascio,
        'dispositivi': dispositivi.length,
        'moduli': moduli.length,
      });
}

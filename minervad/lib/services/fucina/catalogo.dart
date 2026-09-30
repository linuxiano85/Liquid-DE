/// Quello che la Fucina sa prima di guardare la macchina: in che famiglia
/// sta un modulo, quali famiglie si tengono comunque, e che cosa cambia ogni
/// preset.
///
/// ── Tutto dichiarato, niente indovinato ─────────────────────────────────
///
/// È la terza regola di Manutenzione, e qui vale doppio: un modulo tolto per
/// un'euristica sbagliata è un computer che non legge più una chiavetta, e
/// uno messo nell'elenco sbagliato è un modulo che l'utente toglie credendo
/// di togliere un'altra cosa. Quindi:
///
///  · la famiglia di un modulo viene dal **posto** in cui sta nell'albero dei
///    sorgenti (`kernel/fs/…` è un filesystem, `kernel/sound/…` è audio), che
///    è un fatto, e non dal nome, che è un'opinione;
///  · le scorte sono elenchi di nomi scritti per esteso, uno per uno;
///  · ogni valore di un preset porta scritto il suo perché, e il perché dice
///    anche quello che NON promette.
library;

// ── Le famiglie ─────────────────────────────────────────────────────────

class Famiglia {
  final String id;
  final String nome;
  final String spiega;
  const Famiglia(this.id, this.nome, this.spiega);

  Map<String, dynamic> toJson() => {'id': id, 'nome': nome, 'spiega': spiega};
}

/// Nell'ordine in cui si mostrano: prima quello che serve ad avviare, poi
/// quello che si usa ogni giorno, in fondo il resto.
const List<Famiglia> famiglie = [
  Famiglia('dischi', 'Dischi e controller',
      'NVMe, SATA, SCSI, RAID: senza questi il sistema non trova sé stesso.'),
  Famiglia('filesystem', 'Filesystem',
      'I formati che il kernel sa leggere e scrivere.'),
  Famiglia('crypto', 'Cifratura',
      'Algoritmi usati da dischi cifrati, VPN e rete.'),
  Famiglia('video', 'Scheda video', 'Il driver della GPU e i suoi aiutanti.'),
  Famiglia('input', 'Tastiera, mouse, touchpad',
      'Dispositivi HID e d\'ingresso.'),
  Famiglia('controller', 'Controller di gioco',
      'Gamepad, volanti, joystick.'),
  Famiglia('audio', 'Audio', 'Schede audio, HDMI audio, cuffie USB.'),
  Famiglia('rete', 'Rete via cavo e protocolli',
      'Schede Ethernet e i protocolli di rete caricabili.'),
  Famiglia('wifi', 'Wi-Fi', 'Schede senza fili.'),
  Famiglia('bluetooth', 'Bluetooth', 'Adattatori e protocolli Bluetooth.'),
  Famiglia('firewall', 'Firewall e filtri',
      'nftables, iptables: li usa anche chi non sa di averli.'),
  Famiglia('usb', 'USB', 'Controller USB e periferiche generiche.'),
  Famiglia('chiavette', 'Chiavette e dischi USB',
      'Memorie di massa USB e lettori ottici.'),
  Famiglia('stampa', 'Stampanti USB',
      'Il solo driver di stampa che sta nel kernel è quello generico.'),
  Famiglia('webcam', 'Webcam e TV', 'Videocamere, sintonizzatori, cattura.'),
  Famiglia('virtualizzazione', 'Virtualizzazione',
      'KVM, VFIO, vhost: servono a far girare macchine virtuali.'),
  Famiglia('piattaforma', 'Scheda madre e sensori',
      'Sensori, ventole, ACPI, gestione dell\'energia.'),
  Famiglia('altro', 'Altro', 'Tutto quello che non sta in una famiglia sopra.'),
];

/// I controller che stanno in `drivers/hid/` insieme a tastiere e mouse.
/// Per il posto sarebbero «input»; chi guarda l'elenco li cerca fra i
/// controller, e toglierli credendo di togliere un mouse sarebbe l'errore.
const Set<String> _controllerHid = {
  'hid_playstation',
  'hid_sony',
  'hid_nintendo',
  'hid_steam',
  'hid_microsoft',
  'hid_logitech',
  'hid_logitech_hidpp',
  'hid_thrustmaster',
  'hid_gembird',
  'hid_betopff',
  'hid_dr',
  'hid_pxrc',
};

/// La famiglia di un modulo, dal suo percorso in `modules.dep`. Senza un
/// percorso — un modulo che il kernel in uso non conosce — è «altro»: meglio
/// dirlo che indovinare.
String famigliaDi(String nome, String? percorso) {
  if (_controllerHid.contains(nome)) return 'controller';
  final p = percorso ?? '';
  bool in_(String s) => p.startsWith('kernel/$s');

  if (in_('drivers/nvme/') ||
      in_('drivers/ata/') ||
      in_('drivers/scsi/') ||
      in_('drivers/md/') ||
      in_('drivers/block/') ||
      in_('drivers/mmc/')) {
    return 'dischi';
  }
  if (in_('fs/')) return 'filesystem';
  if (in_('crypto/') || in_('arch/x86/crypto/') || in_('lib/crypto/')) {
    return 'crypto';
  }
  if (in_('drivers/gpu/') || in_('drivers/video/')) return 'video';
  if (in_('drivers/input/joystick/')) return 'controller';
  if (in_('drivers/hid/') || in_('drivers/input/')) return 'input';
  if (in_('sound/')) return 'audio';
  if (in_('drivers/net/wireless/') || in_('net/wireless/') ||
      in_('net/mac80211/')) {
    return 'wifi';
  }
  if (in_('drivers/bluetooth/') || in_('net/bluetooth/')) return 'bluetooth';
  if (p.contains('/netfilter/')) return 'firewall';
  if (in_('drivers/net/') || in_('net/')) return 'rete';
  if (in_('drivers/usb/storage/') || in_('drivers/cdrom/')) return 'chiavette';
  if (in_('drivers/usb/class/usblp')) return 'stampa';
  if (in_('drivers/usb/')) return 'usb';
  if (in_('drivers/media/')) return 'webcam';
  if (in_('arch/x86/kvm/') ||
      in_('drivers/vfio/') ||
      in_('drivers/vhost/') ||
      in_('drivers/virt/') ||
      in_('drivers/virtio/')) {
    return 'virtualizzazione';
  }
  if (in_('drivers/hwmon/') ||
      in_('drivers/platform/') ||
      in_('drivers/acpi/') ||
      in_('drivers/thermal/') ||
      in_('drivers/cpufreq/') ||
      in_('drivers/edac/') ||
      in_('drivers/i2c/') ||
      in_('drivers/char/') ||
      in_('drivers/watchdog/') ||
      in_('arch/x86/')) {
    return 'piattaforma';
  }
  return 'altro';
}

// ── Le scorte ───────────────────────────────────────────────────────────
//
// Giacomo, 30 settembre 2026: il kernel deve tenere «solamente i moduli ad
// esempio per leggere tutti i vari file system disponibili, controller di
// gioco».
//
// È il buco di ogni kernel ritagliato su quello che è caricato adesso: la
// chiavetta exFAT che colleghi una volta al mese non era collegata quando si
// è guardato. Le scorte sono le famiglie che si tengono **anche se oggi non
// c'è niente che le usi**, e ognuna è un elenco chiuso di nomi.

class Scorta {
  final String id;
  final String nome;
  final String spiega;
  final List<String> moduli;
  final bool predefinita;
  const Scorta(this.id, this.nome, this.spiega, this.moduli,
      {this.predefinita = false});

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'spiega': spiega,
        'moduli': moduli,
        'predefinita': predefinita,
      };
}

const List<Scorta> scorte = [
  Scorta(
      'filesystem',
      'Tutti i filesystem comuni',
      'ext4, Btrfs, XFS, F2FS, FAT, exFAT, NTFS, CD e DVD: qualunque chiavetta '
          'o disco tu colleghi, si legge.',
      [
        'ext4', 'btrfs', 'xfs', 'f2fs', 'fat', 'vfat', 'exfat', 'ntfs3',
        'isofs', 'udf', 'fuse', 'overlay', 'squashfs', 'nls_utf8',
        'nls_cp437', 'nls_iso8859_1', 'nls_ascii',
      ],
      predefinita: true),
  Scorta(
      'chiavette',
      'Chiavette e dischi USB',
      'Memorie USB, dischi esterni, lettori ottici. Senza, una chiavetta non '
          'compare nemmeno.',
      ['usb_storage', 'uas', 'sd_mod', 'sr_mod', 'cdrom'],
      predefinita: true),
  Scorta(
      'controller',
      'Controller di gioco',
      'Xbox, PlayStation, Nintendo, Steam: anche quelli che colleghi solo '
          'quando giochi.',
      [
        'xpad', 'hid_playstation', 'hid_sony', 'hid_nintendo', 'hid_steam',
        'hid_microsoft', 'joydev', 'uinput', 'ff_memless',
      ]),
  Scorta(
      'bluetooth',
      'Bluetooth',
      'Adattatori USB, cuffie, controller senza fili.',
      ['bluetooth', 'btusb', 'btintel', 'btrtl', 'btbcm', 'btmtk', 'rfcomm',
       'bnep', 'hidp']),
  Scorta(
      'vpn',
      'VPN',
      'WireGuard e le interfacce virtuali che usano OpenVPN e le app VPN.',
      ['wireguard', 'tun', 'tap']),
  Scorta(
      'virtualizzazione',
      'Macchine virtuali',
      'KVM con QEMU, virt-manager o GNOME Boxes, e il passaggio di una scheda '
          'alla macchina virtuale.',
      ['kvm', 'kvm_amd', 'kvm_intel', 'vhost_net', 'vhost', 'tun', 'bridge',
       'vfio', 'vfio_pci', 'vfio_iommu_type1']),
  Scorta(
      'webcam',
      'Webcam',
      'Le webcam USB standard, quasi tutte (UVC).',
      ['uvcvideo', 'videodev', 'videobuf2_common', 'videobuf2_v4l2',
       'videobuf2_vmalloc', 'videobuf2_memops']),
  Scorta(
      'stampa',
      'Stampanti USB (driver del kernel)',
      'Solo il driver generico `usblp`. Attenzione: i driver veri di Canon, '
          'Epson e HP stanno in CUPS, fuori dal kernel, e di solito non usano '
          'nemmeno questo. Scremare le marche si fa togliendo pacchetti, non '
          'moduli.',
      ['usblp']),
];

// ── I preset ────────────────────────────────────────────────────────────

/// Un valore del `.config`, con la ragione per cui lo si mette.
class Impostazione {
  final String simbolo;

  /// `y`, `n`, `m`, un numero o una stringa. Le stringhe si scrivono senza
  /// virgolette: le aggiunge chi scrive il comando.
  final String valore;
  final String perche;
  const Impostazione(this.simbolo, this.valore, this.perche);

  Map<String, dynamic> toJson() =>
      {'simbolo': simbolo, 'valore': valore, 'perche': perche};
}

class Preset {
  final String id;
  final String nome;
  final String spiega;

  /// Il tick del timer. Si sceglie il più alto fra i preset scelti: vedi
  /// [combinaPreset].
  final int hz;

  /// `none`, `voluntary` o `full`, in ordine di reattività.
  final String prelazione;

  /// Le scorte che questo preset accende da solo.
  final List<String> scorte;

  /// Le famiglie che questo preset toglie anche se c'è qualcosa che le usa.
  /// Valgono solo se TUTTI i preset scelti le tolgono: vedi [combinaPreset].
  final List<String> togliFamiglie;

  final List<Impostazione> extra;

  const Preset(this.id, this.nome, this.spiega,
      {required this.hz,
      required this.prelazione,
      this.scorte = const [],
      this.togliFamiglie = const [],
      this.extra = const []});

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'spiega': spiega,
        'hz': hz,
        'prelazione': prelazione,
        'scorte': scorte,
        'togliFamiglie': togliFamiglie,
        'extra': [for (final e in extra) e.toJson()],
      };
}

/// ── Una cosa detta chiaramente sul tick ─────────────────────────────────
///
/// 1000 Hz «per il gaming» è in buona parte folklore da forum. Con `NO_HZ`
/// il timer non batte quando la CPU è ferma, e con gli scheduler di oggi la
/// latenza che si sente dipende molto più dallo scheduler che dal tick. I
/// valori qui sotto sono quelli ragionevoli per l'uso, non promesse di
/// fotogrammi: la sola prova vera è misurare, prima e dopo.
const List<Preset> presets = [
  Preset('gaming', 'Gioco',
      'Reattività prima di tutto: tick alto, prelazione piena, controller '
          'sempre pronti.',
      hz: 1000,
      prelazione: 'full',
      scorte: ['controller'],
      extra: [
        Impostazione('TRANSPARENT_HUGEPAGE_MADVISE', 'y',
            'Le pagine enormi solo a chi le chiede: evita i blocchi di '
                'compattazione nel mezzo di una partita.'),
        // Le altre due voci dello stesso «choice», spente a mano: con due
        // voci accese decide `olddefconfig`, e di solito tiene quella che
        // c'era. È successo col modello di prelazione, compilando davvero.
        Impostazione('TRANSPARENT_HUGEPAGE_ALWAYS', 'n',
            'Escluso: si usa TRANSPARENT_HUGEPAGE_MADVISE.'),
        Impostazione('TRANSPARENT_HUGEPAGE_NEVER', 'n',
            'Escluso: si usa TRANSPARENT_HUGEPAGE_MADVISE.'),
      ]),
  Preset('ufficio', 'Ufficio',
      'Un desktop tranquillo: consuma meno, risponde bene.',
      hz: 300,
      prelazione: 'voluntary'),
  Preset('studio', 'Studio audio e video',
      'Latenza bassa e costante per registrare e montare.',
      hz: 1000,
      prelazione: 'full',
      scorte: ['webcam']),
  Preset('server', 'Server',
      'Resa sostenuta: tick basso, nessuna prelazione, via audio, controller, '
          'webcam e Bluetooth anche se collegati.',
      hz: 250,
      prelazione: 'none',
      togliFamiglie: ['audio', 'controller', 'webcam', 'bluetooth']),
];

/// Il risultato di più preset scelti insieme.
class PresetCombinati {
  final int hz;
  final String prelazione;
  final Set<String> scorte;
  final Set<String> togliFamiglie;
  final List<Impostazione> impostazioni;
  const PresetCombinati(this.hz, this.prelazione, this.scorte,
      this.togliFamiglie, this.impostazioni);
}

const _ordinePrelazione = ['none', 'voluntary', 'full'];

/// ── Come si combinano ───────────────────────────────────────────────────
///
/// Giacomo voleva poterne scegliere più d'uno («gaming» e «studio» sulla
/// stessa macchina). Le regole sono due, e sono scelte perché si possano
/// dire in una riga:
///
///  · **per i valori, vince il più reattivo**: chi ha scelto anche «gioco»
///    non deve ritrovarsi il tick del server;
///  · **per le famiglie tolte, serve l'unanimità**: se uno solo dei preset
///    scelti usa l'audio, l'audio resta. Togliere è la scelta che costa, e la
///    fa solo chi la vuole tutta.
///
/// Nessun preset scelto vuol dire nessun cambiamento: il `.config` resta
/// quello di partenza, tick compreso.
PresetCombinati? combinaPreset(Iterable<String> scelti) {
  final lista = [
    for (final p in presets)
      if (scelti.contains(p.id)) p,
  ];
  if (lista.isEmpty) return null;

  var hz = 0;
  var pre = 0;
  final sc = <String>{};
  Set<String>? togli;
  final extra = <String, Impostazione>{};
  for (final p in lista) {
    if (p.hz > hz) hz = p.hz;
    final i = _ordinePrelazione.indexOf(p.prelazione);
    if (i > pre) pre = i;
    sc.addAll(p.scorte);
    togli = togli == null
        ? p.togliFamiglie.toSet()
        : togli.intersection(p.togliFamiglie.toSet());
    for (final e in p.extra) {
      extra[e.simbolo] = e;
    }
  }
  final prelazione = _ordinePrelazione[pre];
  final imp = <Impostazione>[
    ..._tick(hz),
    ..._prelazione(prelazione),
    ...extra.values,
  ];
  return PresetCombinati(hz, prelazione, sc, togli ?? {}, imp);
}

/// I simboli del tick. Si accende uno e si spengono gli altri a mano: in un
/// «choice» di Kconfig due voci accese lasciano decidere a `olddefconfig`,
/// e non si sa quale sceglie.
List<Impostazione> _tick(int hz) => [
      for (final v in const [100, 250, 300, 1000])
        Impostazione('HZ_$v', v == hz ? 'y' : 'n',
            v == hz ? 'Il timer batte $hz volte al secondo.' : 'Escluso: '
                'si usa HZ_$hz.'),
      Impostazione('HZ', '$hz', 'Il valore numerico che va col simbolo scelto.'),
    ];

/// ── Il modello di prelazione, e il kernel che cambia sotto i piedi ──────
///
/// Trovato compilando davvero il 7.2 (30 settembre 2026): su x86, che ha la
/// prelazione «pigra» (`PREEMPT_LAZY`, scelta dallo scheduler), i modelli
/// `PREEMPT_NONE` e `PREEMPT_VOLUNTARY` non si possono più scegliere, e il
/// valore di serie è proprio `PREEMPT_LAZY`. Chiedere `PREEMPT=y` senza
/// spegnere `PREEMPT_LAZY` lasciava due voci accese nello stesso «choice», e
/// Kconfig teneva quella che c'era: il preset «gioco» non cambiava niente.
///
/// Quindi: si nominano TUTTE le voci del choice, `PREEMPT_LAZY` compresa, e
/// una sola è accesa. Se la voce chiesta in quella versione non esiste, il
/// controllo dopo la configurazione lo dice e nomina quella che è rimasta
/// (vedi [controllaConfig] in `ricetta.dart`). `PREEMPT_DYNAMIC` non si
/// tocca: dove c'è, la prelazione si cambia anche all'avvio con `preempt=`.
List<Impostazione> _prelazione(String p) {
  const simboli = {
    'none': 'PREEMPT_NONE',
    'voluntary': 'PREEMPT_VOLUNTARY',
    'full': 'PREEMPT',
    'lazy': 'PREEMPT_LAZY',
  };
  const perche = {
    'none': 'Nessuna prelazione nel kernel: più resa, meno reattività.',
    'voluntary': 'Il kernel cede il passo nei punti sicuri: l\'equilibrio '
        'di un desktop.',
    'full': 'Il kernel si può interrompere quasi ovunque: la risposta più '
        'rapida all\'utente.',
  };
  return [
    for (final e in simboli.entries)
      Impostazione(e.value, e.key == p ? 'y' : 'n',
          e.key == p ? perche[p]! : 'Escluso: si usa ${simboli[p]}.'),
    // Resta la possibilità di cambiarla all'avvio con `preempt=`, se il
    // kernel di partenza l'aveva: non la si toglie a nessuno.
  ];
}

// ── Il compilatore e la prova veloce ────────────────────────────────────

/// Le impostazioni della «prova veloce»: niente simboli di debug.
///
/// È il taglio che accorcia di più la compilazione dopo quello dei moduli,
/// ma ha un prezzo che va detto prima: senza informazioni di debug non c'è
/// BTF, e senza BTF non c'è `sched_ext` — gli scheduler `scx_*` non
/// partono. Per provare se il kernel si avvia va benissimo; per il kernel di
/// tutti i giorni no.
const List<Impostazione> provaVeloce = [
  Impostazione('DEBUG_INFO_NONE', 'y',
      'Niente simboli di debug: la compilazione dura molto meno.'),
  Impostazione('DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT', 'n', 'Va con DEBUG_INFO_NONE.'),
  Impostazione('DEBUG_INFO_DWARF4', 'n', 'Va con DEBUG_INFO_NONE.'),
  Impostazione('DEBUG_INFO_DWARF5', 'n', 'Va con DEBUG_INFO_NONE.'),
  Impostazione('DEBUG_INFO_BTF', 'n',
      'Senza debug non c\'è BTF: sched_ext non sarà disponibile.'),
];

/// Clang con LTO sottile. Con GCC non si chiede: nel kernel ufficiale LTO
/// esiste solo con Clang.
const List<Impostazione> ltoSottile = [
  Impostazione('LTO_CLANG_THIN', 'y',
      'Ottimizza fra un file e l\'altro, in parallelo: kernel un po\' più '
          'rapido, compilazione più lunga.'),
  Impostazione('LTO_NONE', 'n', 'Va con LTO_CLANG_THIN.'),
  Impostazione('LTO_CLANG_FULL', 'n', 'Va con LTO_CLANG_THIN.'),
];

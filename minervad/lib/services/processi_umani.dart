/// Dire in italiano che cos'è un processo, e chi sta consumando.
///
/// ── Perché sta nel demone e non nell'interfaccia ──────────────────────────
///
/// Perché è una TABELLA, e le tabelle di Minerva stanno nel demone: la stessa
/// scelta fatta per i nomi delle icone (`icon_names.dart`). Una tabella nel
/// QML si può provare solo aprendo una finestra; qui si prova con `dart test`,
/// che è il motivo per cui questa ha centoventi voci e quella no.
///
/// ── Il difetto che risolve ────────────────────────────────────────────────
///
/// Il gestore attività scriveva sotto ogni riga la riga di comando vera:
///
///     qs -p ~/Minerva Shell/minerva-shell/app.qml
///
/// che è precisa, lunga tre volte la finestra, e non risponde alla domanda che
/// si ha in testa aprendo un gestore attività — «questa roba che cos'è, e la
/// posso chiudere?». Giacomo: «anche il task manager è da rendere più
/// intelligente come gestione e semplice».
library;

/// Che cos'è, in una riga, quel processo.
///
/// Restituisce stringa vuota quando non si sa: meglio niente che una riga di
/// comando spacciata per spiegazione. Chi mostra il risultato, se è vuoto, non
/// scrive niente — e la riga resta pulita col solo nome.
String descrizione(String nome, String comando) {
  final n = _pulisci(nome);

  // ── Le finestre di Minerva sono tutte lo stesso binario ────────────────
  //
  // Gestore file, Impostazioni, Attività, Anteprima, blocco e schermata di
  // accesso girano tutte come `qs`, e guardando il solo nome sono la stessa
  // cosa. Nel gestore attività si vedeva: la riga si chiamava «Attività» e
  // sotto diceva «La scrivania: barra, dock, menu e finestre di Minerva»,
  // che è la descrizione di un'ALTRA finestra.
  //
  // Un'informazione sbagliata è peggio di nessuna, e qui non serve
  // indovinare: quale delle sei sia sta scritto nella riga di comando, che è
  // il percorso del file QML che stanno eseguendo.
  if (n == 'qs' || n == 'quickshell') {
    for (final e in _finestreMinerva.entries) {
      if (comando.contains(e.key)) return e.value;
    }
  }

  final diretta = _tabella[n];
  if (diretta != null) return diretta;

  // I nomi che finiscono con un numero di versione o un suffisso: `python3.14`,
  // `qemu-system-x86_64`, `gjs-console`. Si prova la radice.
  for (final chiave in _tabella.keys) {
    if (n.startsWith(chiave) && chiave.length >= 4) return _tabella[chiave]!;
  }

  // I programmi lanciati da un interprete dicono il vero nome nel secondo
  // pezzo: `python3 /usr/bin/qualcosa`, `sh -c ...`, `node server.js`.
  if (_interpreti.contains(n)) {
    final pezzi = comando.split(' ').where((p) => p.isNotEmpty).toList();
    for (var i = 1; i < pezzi.length && i < 4; i++) {
      final p = pezzi[i];
      if (p.startsWith('-')) continue;
      final base = _pulisci(p.split('/').last);
      final d = _tabella[base];
      if (d != null) return d;
      if (base.isNotEmpty && base != n) return 'Avviato da $n: $base';
    }
  }

  return '';
}

/// Vero per i processi che fanno funzionare il sistema e non l'utente.
///
/// Serve a raggrupparli e tenerli chiusi: in un elenco di duecento righe, le
/// quindici che interessano sono sempre le stesse, e le altre centottantacinque
/// non si chiudono comunque.
bool eDiSistema(String nome, String comando) {
  final n = _pulisci(nome);
  if (_sistema.contains(n)) return true;
  for (final p in _prefissiSistema) {
    if (n.startsWith(p)) return true;
  }
  // I thread del kernel non hanno riga di comando: `/proc/<pid>/cmdline` è
  // vuoto, e il monitor ci rimette il nome. È il modo più affidabile di
  // riconoscerli senza leggere altro.
  if (comando == nome && n.startsWith('k')) return true;
  return false;
}

/// La frase in cima: com'è messo il computer, adesso.
///
/// Non una percentuale in più — di quelle ce ne sono già cinque in cima alla
/// finestra — ma la cosa che si andrebbe a cercare guardandole: **chi**.
///
/// Le soglie non sono tonde per caso. Sotto il 25% di un processore a quattro
/// core non c'è niente da dire: è un computer che lavora. Sopra il 60% la
/// ventola si sente, ed è il momento in cui si apre un gestore attività.
String comeSta(List<Map<String, dynamic>> processi, double cpuTotale,
    double memoriaPercentuale) {
  Map<String, dynamic>? peggiore;
  var maxCpu = 0.0;
  for (final p in processi) {
    final c = (p['cpu'] as num?)?.toDouble() ?? 0;
    if (c > maxCpu) {
      maxCpu = c;
      peggiore = p;
    }
  }

  if (memoriaPercentuale >= 90) {
    return 'La memoria è quasi piena: il computer comincerà a rallentare.';
  }

  if (cpuTotale >= 60 && peggiore != null && maxCpu >= 25) {
    final nome = etichetta(peggiore['nome']?.toString() ?? '',
        peggiore['comando']?.toString() ?? '');
    return '$nome sta usando il processore (${maxCpu.round()}%).';
  }

  if (cpuTotale >= 60) return 'Il processore è occupato, ma non da un solo programma.';
  if (cpuTotale < 25 && memoriaPercentuale < 75) return 'Tutto tranquillo.';
  return 'Il computer sta lavorando normalmente.';
}

/// Il nome da mostrare: quello del programma, non quello del binario.
String etichetta(String nome, String comando) {
  final n = _pulisci(nome);
  final bello = _nomiBelli[n];
  if (bello != null) return bello;
  if (n.isEmpty) return nome;
  return n[0].toUpperCase() + n.substring(1);
}

String _pulisci(String s) {
  var n = s.trim();
  // I thread del kernel arrivano fra parentesi quadre: `[kworker/0:1]`.
  if (n.startsWith('[') && n.endsWith(']')) n = n.substring(1, n.length - 1);
  final barra = n.indexOf('/');
  if (barra > 0) n = n.substring(0, barra);
  // ── Il nome che si dà un binario Dart compilato ────────────────────────
  //
  // `/proc/<pid>/comm` per il demone dice `dart:minervad`, non `minervad`: la
  // macchina virtuale ci mette il proprio nome davanti. Nel gestore attività
  // si leggeva «Dart:minervad», che è il nome di nessuno.
  //
  // I due punti si tagliano DOPO la barra, o `kworker/u16:3` perderebbe il
  // pezzo sbagliato — ma lì la barra ha già fatto il suo lavoro.
  final duePunti = n.lastIndexOf(':');
  if (duePunti > 0 && duePunti < n.length - 1) n = n.substring(duePunti + 1);
  return n.toLowerCase();
}

/// Quale finestra di Minerva è, riconosciuta dal file che sta eseguendo.
/// L'ordine conta: `shell.qml` va cercato per ultimo perché `filemanager.qml`
/// e gli altri stanno nella stessa cartella e non contengono quel nome, ma un
/// domani un percorso più lungo potrebbe.
const _finestreMinerva = {
  'filemanager.qml': 'Il gestore file di Minerva',
  'settings.qml': 'Le impostazioni di Minerva',
  // ── Un processo per quattro programmi ──────────────────────────────────
  //
  // Calcolatrice, Editor, Anteprima e Attività vivono qui dentro: il
  // pavimento di Qt costa 31 MB e si pagava quattro volte.
  //
  // Il nome le elenca tutte perché dal processo non si può sapere quale delle
  // quattro è aperta in questo momento, e mentire indicandone una sola sarebbe
  // peggio che dirle tutte. Chi guarda Attività per capire chi consuma trova
  // comunque il nome giusto: `app.qml` era l'unica riga che mancava, e prima
  // compariva come «qs», che è il nome di nessuno.
  'app.qml': 'Le app di Minerva: calcolatrice, editor, anteprima, attività',
  'minervamedia.qml': 'Il lettore multimediale di Minerva',
  'viewer.qml': 'Anteprima: le immagini',
  'blocco.qml': 'La schermata di blocco',
  'greeter.qml': 'La schermata di accesso',
  'shell.qml': 'La scrivania: barra, dock, menu e finestre di Minerva',
};

const _interpreti = {'sh', 'bash', 'zsh', 'fish', 'python3', 'python', 'node', 'perl', 'ruby'};

const _prefissiSistema = {
  'kworker', 'ksoftirqd', 'kthread', 'kcompactd', 'kdevtmpfs', 'kswapd',
  'irq/', 'migration', 'rcu_', 'watchdog', 'idle_inject', 'card', 'scsi_',
  'jbd2', 'ext4', 'btrfs', 'nvme', 'systemd-', 'dbus-', 'gvfs',
};

const _sistema = {
  'systemd', 'init', 'dbus', 'dbus-daemon', 'udevd', 'polkitd', 'rtkit-daemon',
  'accounts-daemon', 'upowerd', 'wpa_supplicant', 'networkmanager',
  'nm-applet', 'bluetoothd', 'cupsd', 'agetty', 'login', 'sshd', 'cron',
  'crond', 'chronyd', 'ntpd', 'avahi-daemon', 'irqbalance', 'thermald',
  'auditd', 'journald', 'logind', 'khugepaged', 'kauditd', 'oomd',
};

/// Il nome che si mostra. Solo dove il binario si chiama diversamente da come
/// il programma si presenta: `qs` è Minerva, `dartvm` è il demone.
const _nomiBelli = {
  'qs': 'Interfaccia di Minerva',
  'quickshell': 'Interfaccia di Minerva',
  'minervad': 'Demone di Minerva',
  // ── Il compositore, che mancava ─────────────────────────────────────────
  //
  // Fino al 3 settembre 2026 questa tabella conosceva `hyprland` e non
  // `minerva-wayland`: in Minerva Attività il processo più importante della
  // sessione — quello che disegna tutto — compariva col nome nudo e senza una
  // riga che dicesse cos'è, mentre il compositore che non gira più aveva la
  // sua descrizione.
  //
  // Non è una svista isolata: è la forma che prende il distacco quando una
  // tabella si scrive a mano. Il ripiego per `hyprland` resta, perché questa
  // tabella descrive i processi di CHIUNQUE — chi apre Attività può avere
  // altro sulla macchina.
  'minerva-wayland': 'Compositore di Minerva',
  // Aveva una descrizione e non un nome: in Attività si leggeva
  // «minerva-polkit», che è come si chiama il file, non come si chiama la cosa.
  'minerva-polkit': 'Permessi di Minerva',
  'hyprland': 'Hyprland',
  'alacritty': 'Alacritty',
  'firefox': 'Firefox',
  'chromium': 'Chromium',
  'chrome': 'Google Chrome',
  'code': 'Visual Studio Code',
  'dolphin': 'Dolphin',
  'konsole': 'Konsole',
  'thunderbird': 'Thunderbird',
  'libreoffice': 'LibreOffice',
  'soffice.bin': 'LibreOffice',
  'pipewire': 'PipeWire',
  'wireplumber': 'WirePlumber',
  'steam': 'Steam',
  'vlc': 'VLC',
  'mpv': 'mpv',
  'gimp': 'GIMP',
  'obs': 'OBS Studio',
};

/// Che cos'è, in una riga che si legge senza sapere niente di Linux.
const _tabella = {
  // ── Minerva ──
  'qs': 'La scrivania: barra, dock, menu e finestre di Minerva',
  'quickshell': 'La scrivania: barra, dock, menu e finestre di Minerva',
  'minervad': 'Il servizio di Minerva: impostazioni, file, rete, batteria',
  'minerva-wayland': 'Il compositore di Minerva: disegna le finestre, e riceve '
      'mouse e tastiera',
  'hyprland': 'Il compositore: disegna le finestre e riceve mouse e tastiera',
  'minerva-polkit': 'Chiede la password quando serve il permesso di root',
  'hyprlock': 'La schermata di blocco',
  'hyprpolkitagent': 'Chiede la password quando serve il permesso di root (ripiego)',

  // ── Il sistema ──
  'systemd': 'L\'avvio e i servizi del sistema',
  'systemd-journald': 'Il registro del sistema',
  'systemd-logind': 'Tiene traccia di chi ha fatto l\'accesso',
  'systemd-udevd': 'Riconosce i dispositivi che si attaccano',
  'systemd-resolved': 'Traduce i nomi dei siti in indirizzi',
  'dbus-daemon': 'Il canale con cui i programmi si parlano fra loro',
  'dbus-broker': 'Il canale con cui i programmi si parlano fra loro',
  'polkitd': 'Decide chi può fare cosa quando serve un permesso',
  'udisksd': 'Gestisce dischi e chiavette',
  'upowerd': 'Legge la batteria',
  'thermald': 'Tiene sotto controllo la temperatura',
  'irqbalance': 'Distribuisce il lavoro fra i core del processore',
  'rtkit-daemon': 'Dà la precedenza all\'audio perché non salti',
  'gvfsd': 'Apre cartelle di rete e chiavette',
  'cupsd': 'Il sistema di stampa',
  'sshd': 'Accetta collegamenti da altri computer',
  'agetty': 'Il terminale di testo (Ctrl+Alt+F1…F6)',
  'cron': 'Esegue i lavori programmati',
  'crond': 'Esegue i lavori programmati',

  // ── Audio, rete, bluetooth ──
  'pipewire': 'L\'audio: chi suona e chi registra',
  'pipewire-pulse': 'L\'audio per i programmi che parlano PulseAudio',
  'wireplumber': 'Decide da quale altoparlante esce il suono',
  'networkmanager': 'La rete: wi-fi e cavo',
  'nmbd': 'Rete Windows',
  'wpa_supplicant': 'La parte del wi-fi che si occupa della password',
  'bluetoothd': 'Il Bluetooth',
  'avahi-daemon': 'Trova stampanti e computer nella rete di casa',

  // ── Grafica ──
  'xwayland': 'Fa girare i programmi vecchi, scritti per X11',
  'xdg-desktop-portal': 'Le finestre «Apri file» e la condivisione schermo',
  'xdg-desktop-portal-hyprland': 'La condivisione dello schermo',
  'xdg-desktop-portal-gtk': 'Le finestre «Apri file» dei programmi GTK',
  'gnome-keyring-daemon': 'Custodisce le password salvate',
  'kwalletd6': 'Custodisce le password salvate (KDE)',

  // ── Programmi ──
  'firefox': 'Il browser web',
  'chromium': 'Il browser web',
  'chrome': 'Il browser web',
  'thunderbird': 'La posta elettronica',
  'code': 'L\'editor di codice',
  'alacritty': 'Il terminale',
  'konsole': 'Il terminale di KDE',
  'dolphin': 'Il gestore file di KDE',
  'steam': 'Il negozio e la libreria dei giochi',
  'vlc': 'Il riproduttore video',
  'mpv': 'Il riproduttore video',
  'gimp': 'L\'editor di immagini',
  'obs': 'La registrazione e la diretta',
  'libreoffice': 'Documenti, fogli di calcolo, presentazioni',
  'soffice.bin': 'Documenti, fogli di calcolo, presentazioni',
  'dart': 'Il linguaggio Dart: qui ci gira il servizio di Minerva',
  'cliphist': 'Ricorda quello che copi negli appunti',
  'wl-paste': 'Legge gli appunti',
  'grim': 'Fotografa lo schermo',
  'ananicy-cpp': 'Dà a ogni programma la priorità giusta',
};

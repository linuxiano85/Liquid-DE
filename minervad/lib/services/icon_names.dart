import 'icon_resolver.dart';

/// Da come Minerva chiama un'icona a come la chiama il resto del mondo.
///
/// La shell disegna le proprie icone (`minerva-shell/ui/Icon.qml`) e le chiama
/// per quello che fanno: «settings», «trash», «grid». I temi di icone
/// installati sul computer — Papirus, Breeze, Adwaita, Tela — le chiamano
/// invece con i nomi della specifica freedesktop: «preferences-system»,
/// «user-trash», «view-grid». Questa tabella è il ponte fra i due mondi, e
/// serve a chi preferisce le icone di sempre a quelle disegnate da noi.
///
/// Ogni voce è un ELENCO di candidati, non un nome solo, e l'ordine conta: si
/// prende il primo che esiste. Non è pignoleria — nessun nome funziona
/// ovunque. «check» è `object-select` su Papirus, `dialog-ok` su Breeze e
/// `object-select-symbolic` su Adwaita; con un nome solo, due utenti su tre
/// vedrebbero un buco al posto della spunta.
///
/// Un nome che manca da questa tabella, o che nessun tema ha, non è un errore:
/// la shell disegna il proprio tracciato come sempre. È la ragione per cui si
/// può aggiungere un'icona a `Icon.qml` senza toccare questo file — l'icona
/// nuova semplicemente non avrà, per un po', una controparte classica.
///
/// ⚠ Le chiavi qui sotto devono esistere in `_paths` di `ui/Icon.qml`.
const Map<String, List<String>> minervaIconNames = {
  // ── Navigazione e azioni ───────────────────────────────────────────────
  'apps': ['applications-all', 'view-app-grid-symbolic', 'application-menu'],
  'search': ['system-search', 'edit-find'],
  'close': ['window-close', 'dialog-close'],
  'chevron': ['pan-down', 'go-down'],
  'chevronUp': ['pan-up', 'go-up'],
  'plus': ['list-add'],
  'minus': ['list-remove'],
  'check': ['object-select', 'dialog-ok', 'object-select-symbolic'],
  'back': ['go-previous'],

  // ── Sistema ────────────────────────────────────────────────────────────
  'wifi': ['network-wireless', 'network-wireless-signal-excellent'],
  'bluetooth': ['bluetooth', 'preferences-system-bluetooth'],
  'volume': ['audio-volume-high'],
  'muted': ['audio-volume-muted'],
  'battery': ['battery', 'battery-good'],
  'bell': ['notifications', 'preferences-desktop-notification'],
  'power': ['system-shutdown'],
  'lock': ['system-lock-screen', 'changes-prevent'],
  'moon': ['weather-clear-night', 'night-light'],
  'restart': ['system-reboot', 'view-refresh'],
  'logout': ['system-log-out'],
  'sun': ['weather-clear', 'display-brightness'],
  // «sliders» e «settings» sono due icone diverse per noi — le manopole e
  // l'ingranaggio — e devono restare due icone diverse anche qui, altrimenti
  // nel pannello di controllo la piastrella «Animazioni» e il pulsante
  // «Impostazioni» diventano lo stesso disegno.
  'sliders': ['settings-configure', 'configure', 'preferences-other'],
  'accessibilita': ['preferences-desktop-accessibility', 'accessibility'],
  // Le frecce dello schermo intero e del ritorno. Sono comandi di finestra, e
  // ogni tema ne ha il disegno.
  'expand': ['view-fullscreen', 'window-maximize-symbolic'],
  'collapse': ['view-restore', 'zoom-fit-best'],
  // Il microfono acceso e chiuso, come `volume`/`muted`: due stati della
  // stessa cosa, e vanno presi dallo stesso tema o non si riconoscono come
  // tali.
  'mic': ['audio-input-microphone', 'microphone-sensitivity-high'],
  'micOff': ['audio-input-microphone-muted', 'microphone-sensitivity-muted'],
  // `cursor` disegna il TOUCHPAD, non un puntatore: vedi il commento accanto
  // al tracciato in `Icon.qml`. Il nome è vecchio, il disegno no.
  'cursor': ['input-touchpad', 'preferences-desktop-touchpad'],
  'rotate': ['object-rotate-right', 'transform-rotate'],
  'settings': ['preferences-system', 'systemsettings', 'configure'],
  'minimize': ['window-minimize', 'window-minimize-symbolic'],
  'maximize': ['window-maximize', 'window-maximize-symbolic'],
  'restore': ['window-restore', 'window-restore-symbolic'],
  'cpu': ['cpu', 'computer'],
  // I simboli dei widget della barra (14 settembre 2026). Nei temi classici
  // esistono quasi tutti: la memoria come «media-memory», il termometro
  // come sonda, la GPU come scheda video. Il carico non ha un'icona sua da
  // nessuna parte, e si traduce col cronometro dell'utilizzazione.
  'memoria': ['media-memory', 'memory', 'nvidia-ram'],
  'termometro': ['temperature', 'sensors-temperature-symbolic', 'thermometer'],
  'gpu': ['video-display', 'gpu', 'graphics-card'],
  'carico': ['utilities-system-monitor', 'system-run'],
  'rete': ['network-transmit-receive', 'network-wired'],
  // Gli apparecchi Bluetooth del widget (14 settembre 2026).
  'mouse': ['input-mouse', 'input-mouse-symbolic'],
  'cuffie': ['audio-headphones', 'audio-headset'],
  'telefono': ['phone', 'smartphone', 'phone-symbolic'],

  // ── Contenuti ──────────────────────────────────────────────────────────
  //
  // «Copia» e «Taglia» erano nel menu del gestore file da sempre e non erano
  // qui: con le icone classiche accese restavano gli unici due comandi del
  // menu disegnati da noi, in mezzo a tutti gli altri.
  'copy': ['edit-copy'],
  'cut': ['edit-cut'],
  // ── Condividi e Scarica ────────────────────────────────────────────────
  //
  // Arrivate con la condivisione via Bluetooth e posta e rimaste senza
  // controparte: `icon_names_test.dart` era rosso da allora, e col tema di
  // icone acceso erano gli unici due comandi disegnati da noi in mezzo agli
  // altri — lo stesso difetto di «Copia» e «Taglia» qui sopra.
  //
  // I candidati sono in quest'ordine perché nessun nome esiste ovunque:
  // `document-send` è quello di Adwaita e GNOME, `document-share` sta in
  // hicolor (quindi c'è quasi sempre), `send-to` e `emblem-shared` sono i
  // ripieghi di Papirus e dei temi che vengono da GNOME 2.
  'share': ['document-send', 'document-share', 'send-to', 'emblem-shared'],
  // Per «scarica» la specifica freedesktop non ha un nome: `edit-download` è
  // di Breeze, `browser-download` di Papirus, `folder-download` è la cartella
  // (sbagliata come azione, ma meglio di un buco) e `go-down` c'è dappertutto.
  'download': ['edit-download', 'browser-download', 'document-save-as',
               'folder-download', 'go-down'],
  'clipboard': ['edit-paste', 'klipper'],
  'keyboard': ['input-keyboard', 'preferences-desktop-keyboard'],
  'folder': ['folder'],
  // ── Le cartelle di casa ────────────────────────────────────────────────
  //
  // Ogni tema di icone curato le disegna a parte: Documenti con un foglio,
  // Immagini con una fotografia, Scaricati con una freccia in giù. Chiedere
  // «folder» per tutte vorrebbe dire buttare via quel lavoro e ritrovarsi
  // dodici quadrati identici in cui l'occhio non riconosce niente — che è
  // esattamente com'era il gestore file di Minerva fino al 10 agosto 2026.
  //
  // I nomi di ripiego contano: `folder-download` e `folder-downloads` esistono
  // tutti e due a seconda del tema, e chi ne dichiara uno solo su metà dei
  // temi non trova niente.
  'cartella-documenti': ['folder-documents', 'folder-document'],
  'cartella-scaricati': ['folder-download', 'folder-downloads'],
  'cartella-immagini': ['folder-pictures', 'folder-images', 'folder-image'],
  'cartella-musica': ['folder-music', 'folder-sound'],
  'cartella-video': ['folder-videos', 'folder-video'],
  'cartella-scrivania': ['user-desktop', 'folder-desktop'],
  'cartella-pubblici': ['folder-publicshare', 'folder-public'],
  'cartella-modelli': ['folder-templates', 'folder-template'],
  'cartella-casa': ['user-home', 'folder-home'],
  // Una cartella fissata è una CARTELLA, e chi ha scelto un tema classico si
  // aspetta di vederla come tale. Prima la colonna le disegnava tutte con una
  // puntina: la puntina resta sul pulsante che fissa, dove vuol dire un'azione.
  // L'ordine è misurato, non a naso: su Papirus `folder-bookmark` è una
  // STELLA e basta, mentre `folder-favorites` è una cartella con la stella
  // dentro — che è quello che serve, perché una cartella fissata resta una
  // cartella. Su Breeze ci sono tutti e due e valgono uguale. `bookmarks` sta
  // in fondo come ultima spiaggia: è un'azione, non un posto.
  // I nomi «preferito» sono i più sparsi di tutta la specifica: Breeze dice
  // `folder-favorites`, Papirus `folder-bookmark`, Pop `user-bookmarks` e
  // `emblem-favorite`, GNOME `emblem-favorite-symbolic`. Con i primi tre soli,
  // col tema Pop restava disegnata da noi — una cartella fissata in mezzo a
  // cartelle di sistema.
  'cartella-fissata': ['folder-favorites', 'folder-bookmark', 'bookmarks',
                       'user-bookmarks', 'emblem-favorite', 'emblem-favorites',
                       'emblem-favorite-symbolic'],
  // «home» è la casa delle BRICIOLE del percorso — «dove abito» come primo
  // pezzo di un indirizzo — ed è un'altra cosa dalla cartella nell'elenco.
  'home': ['go-home', 'user-home'],
  // I due dispositivi. Erano `cpu` e `clipboard`: un processore e una
  // lavagnetta per appunti al posto di un disco fisso e di una chiavetta.
  'disco': ['drive-harddisk'],
  'chiavetta': [
    'drive-removable-media-usb',
    'drive-removable-media',
    'media-removable'
  ],
  'globe': ['applications-internet', 'web-browser', 'network-workgroup'],
  // La nuvola degli account online. Nei temi classici la «nuvola» non esiste
  // come cosa a sé: quello che le corrisponde è la cartella in rete, che è poi
  // esattamente ciò che un account di archiviazione è.
  'cloud': [
    'folder-remote',
    'network-server',
    'goa-panel',
    'cloud-upload'
  ],
  'terminal': ['utilities-terminal'],
  'star': ['starred', 'bookmarks'],
  'gamepad': ['applications-games', 'input-gaming'],
  'image': ['image-x-generic'],
  'music': ['audio-x-generic'],
  'video': ['video-x-generic'],
  'document': ['text-x-generic'],
  // I tipi di file. Ogni tema curato ne ha un disegno proprio: chiedere
  // «text-x-generic» per tutti vorrebbe dire buttarlo via.
  'pdf': ['application-pdf', 'application-x-pdf', 'x-office-document'],
  'table': ['x-office-spreadsheet', 'application-vnd.oasis.opendocument.spreadsheet'],
  'slides': [
    'x-office-presentation',
    'application-vnd.oasis.opendocument.presentation'
  ],
  'code': ['text-x-script', 'text-x-source', 'text-x-generic'],
  'font': ['font-x-generic', 'application-x-font-ttf'],
  'archive': ['package-x-generic', 'application-x-archive'],
  'mail': ['mail-message', 'internet-mail', 'mail-unread-symbolic'],
  'wrench': ['applications-utilities', 'configure'],
  'pin': ['pin', 'window-pin', 'bookmark-new'],
  'split': ['tab-new'],
  'trash': ['user-trash'],
  'dock': ['preferences-system-windows'],
  'shuffle': ['media-playlist-shuffle'],
  // Ripeti: la specifica freedesktop ha il nome per tutti e due gli
  // stati, «tutto» e «questo brano». Il ripiego del secondo sul primo è
  // voluto: un tema che ha solo l'anello semplice disegna quello, e si
  // perde la distinzione ma non l'icona.
  'repeat': ['media-playlist-repeat'],
  'repeat1': ['media-playlist-repeat-song', 'media-playlist-repeat'],
  'timer': ['chronometer', 'alarm-symbolic', 'alarm'],
  'clock': ['clock', 'preferences-system-time', 'time-admin'],
  'info': ['dialog-information', 'help-about', 'documentinfo'],
  // Il tempo: i temi di sistema li chiamano `weather-*`, che è il nome della
  // specifica freedesktop per le previsioni.
  'nuvole': ['weather-many-clouds', 'weather-overcast', 'weather-clouds'],
  'nuvole-sole': ['weather-few-clouds', 'weather-partly-cloudy'],
  'pioggia': ['weather-showers', 'weather-showers-scattered', 'weather-rain'],
  'neve': ['weather-snow', 'weather-snow-scattered'],
  'temporale': ['weather-storm', 'weather-thundershower'],
  'nebbia': ['weather-fog', 'weather-mist'],
  // «Ritaglia»: `transform-crop` è di Breeze/KDE, `image-crop` di Pop e dei
  // temi che vengono da GNOME. Nessuno dei due esiste dove c'è l'altro.
  'crop': ['transform-crop', 'edit-image-crop', 'select-rectangular',
           'image-crop', 'image-crop-symbolic', 'tool-crop'],
  // Lo schermo e la finestra come OGGETTI, non come comandi della barra del
  // titolo: `window-maximize` e `window-restore` sono una freccia e un rombo,
  // e messi a dire «tutto lo schermo» e «solo una finestra» non si capiscono.
  'screen': ['video-display', 'preferences-desktop-display', 'computer'],
  'window': ['window', 'preferences-system-windows', 'window-duplicate'],
  'camera': ['camera-photo', 'applets-screenshooter', 'accessories-screenshot'],

  // ── Come si guarda un elenco ───────────────────────────────────────────
  'list': ['view-list', 'view-list-details', 'view-list-symbolic'],
  'grid': ['view-grid', 'view-list-icons', 'view-grid-symbolic'],
  'sort': ['view-sort', 'view-sort-ascending'],
};

/// Le due dimensioni a cui si risolve ogni icona.
///
/// La shell disegna icone da 13 a 48 pixel. Un tema curato non ha «l'icona»,
/// ha la stessa icona ridisegnata per le dimensioni piccole, con meno
/// dettagli: dare alla barra il file da 48 rimpicciolito la fa sembrare
/// sfocata. Due misure coprono tutto senza far diventare la mappa un catalogo.
const int iconSizeSmall = 22;
const int iconSizeLarge = 48;

/// Risolve tutta la tabella nel tema attivo.
///
/// Torna `{ "settings": { "s": "/percorso/22.svg", "l": "/percorso/48.svg" }, … }`,
/// senza le voci che il tema non ha: quelle la shell le disegna da sé, e
/// mandarle vuote costringerebbe ogni icona a distinguere «assente» da
/// «stringa vuota».
Map<String, dynamic> resolveMinervaIcons(IconResolver resolver) {
  final map = <String, dynamic>{};

  for (final entry in minervaIconNames.entries) {
    for (final candidate in entry.value) {
      // `generic: false`: senza, un nome che nessun tema conosce tornerebbe
      // l'icona dell'eseguibile generico, e nella barra comparirebbe un
      // ingranaggio al posto di «ordina» — peggio di un'icona mancante,
      // perché sembra voluto.
      final small = resolver.resolve(candidate, size: iconSizeSmall, generic: false);
      if (small.isEmpty) continue;
      final large = resolver.resolve(candidate, size: iconSizeLarge, generic: false);
      map[entry.key] = {'s': small, 'l': large.isEmpty ? small : large};
      break;
    }
  }

  return map;
}

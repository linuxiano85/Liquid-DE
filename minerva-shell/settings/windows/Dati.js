.pragma library

// I dati delle Impostazioni nel preset Windows, presi da Windows 11 vero (12
// ottobre 2026): una macchina virtuale con Windows 11 25H2 italiano
// (build 26100), letta con UI Automation e fotografata. Fonte e metodo in
// `docs/impostazioni-windows-specifica.md` e in
// `../Liquid_test-principale/vm-windows11/LEGGIMI.md`.
//
// Nessun testo è inventato: ogni etichetta è quella che Windows mostra. Le
// lingue sono tabelle: aggiungere una lingua vuol dire aggiungere una
// tabella, fotografata allo stesso modo. Una voce che manca in una lingua
// ripiega sull'italiano.

var testi = {
    "it": {
        // La finestra
        "impostazioni": "Impostazioni",
        "cerca": "Trova un'impostazione",
        "indietro": "Indietro",
        "accountLocale": "Account locale",
        "nonDisponibile": "Non ancora disponibile",
        "attivato": "Attivato",
        "disattivato": "Disattivato",
        // Le categorie della barra laterale
        "home": "Home",
        "sistema": "Sistema",
        "dispositivi": "Bluetooth e dispositivi",
        "rete": "Rete e Internet",
        "personalizzazione": "Personalizzazione",
        "app": "App",
        "account": "Account",
        "ora": "Data/ora e lingua",
        "giochi": "Giochi",
        "accessibilita": "Accessibilità",
        "privacy": "Privacy e sicurezza",
        "update": "Liquid Update",
        // Personalizzazione
        "selezionaTema": "Seleziona un tema da applicare",
        "sfondo": "Sfondo",
        "sfondoDescr": "Immagine di sfondo, colore, presentazione",
        "colori": "Colori",
        "coloriDescr": "Colore principale, effetti di trasparenza, tema colore",
        "temi": "Temi",
        "temiDescr": "Installa, crea, gestisci",
        "illuminazione": "Illuminazione dinamica",
        "illuminazioneDescr": "Dispositivi connessi, effetti, impostazioni app",
        "blocco": "Schermata di blocco",
        "bloccoDescr": "Immagini della schermata di blocco, app, animazioni",
        "immissione": "Immissione di testo",
        "immissioneDescr": "Tastiera virtuale, digitazione vocale, emoji e altro ancora, editor di metodi di input",
        "start": "Start",
        "startDescr": "App ed elementi recenti, cartelle",
        "barra": "Barra delle applicazioni",
        "barraDescr": "Comportamenti barra delle applicazioni, elementi di sistema ancorati",
        "caratteri": "Caratteri",
        "caratteriDescr": "Installa, gestisci",
        // Sfondo
        "anteprima": "Anteprima del desktop",
        "personalizzaSfondo": "Personalizza lo sfondo",
        "personalizzaSfondoDescr": "Un'immagine di sfondo si applica al desktop corrente. Gli sfondi a tinta unita o con presentazioni si applicano a tutti i desktop.",
        "immagine": "Immagine",
        "tintaUnita": "Tinta unita",
        "presentazione": "Presentazione",
        "inEvidenza": "Contenuti in evidenza di Windows",
        "immaginiRecenti": "Immagini recenti",
        "scegliFoto": "Scegli una foto",
        "sfogliaFoto": "Sfoglia le foto",
        "adattamento": "Scegli un adattamento per l'immagine del desktop",
        "riempi": "Riempi", "adatta": "Adatta", "allunga": "Allunga",
        "affianca": "Affianca", "centra": "Centra", "estendi": "Estendi",
        "coloreSfondo": "Scegli il tuo colore di sfondo",
        "coloriPersonalizzati": "Colori personalizzati",
        "visualizzaColori": "Visualizza colori",
        "album": "Scegli un album di immagini per una presentazione",
        "sfoglia": "Sfoglia",
        "cambiaOgni": "Cambia immagine ogni",
        "casuale": "Riproduci in modo casuale l'ordine delle immagini",
        "correlate": "Impostazioni correlate",
        "contrasto": "Temi a contrasto",
        "contrastoDescr": "Temi a colori per ipovisione, sensibilità alla luce",
        "supporto": "Supporto correlato",
        "aiutoSfondo": "Aiuto con lo sfondo",
        "informazioni": "Informazioni",
        // Colori
        "modalita": "Scegli la modalità",
        "modalitaDescr": "Modifica i colori visualizzati in Windows e nelle tue app",
        "chiara": "Chiara", "scura": "Scura", "personalizzata": "Personalizzata",
        "modalitaWindows": "Scegli la modalità predefinita di Windows",
        "modalitaApp": "Scegli la modalità predefinita dell'app",
        "trasparenza": "Effetti di trasparenza",
        "trasparenzaDescr": "Rende traslucidi Start, barra e pannelli. Gli effetti delle finestre si regolano nella pagina Finestre.",
        "colorePrincipale": "Colore principale",
        "automatico": "Automatico", "manuale": "Manuale",
        "coloriRecenti": "Colori recenti",
        "coloriWindows": "Colori di Liquid",
        "accentoStart": "Mostra il colore principale su Start e sulla barra delle applicazioni",
        "soloScura": "Questa impostazione è disponibile solo nella modalità scura di Windows.",
        "accentoBarre": "Mostra il colore principale sulle barre dei titoli e sui bordi delle finestre",
        "coloreSelezionato": "Selezionato",
        // Temi
        "temaCorrente": "Tema corrente",
        "temaCorrenteDescr": "Scegli una combinazione di sfondi, suoni e colori per dare al tuo desktop più personalità",
        "personalizzato": "Personalizzato",
        "colore": "Colore",
        "suoni": "Suoni",
        "cursore": "Cursore del mouse",
        "salva": "Salva",
        "altriTemi": "Ottieni altri temi da Microsoft Store",
        "sfogliaTemi": "Sfoglia temi",
        "iconeDesktop": "Impostazioni delle icone del desktop",
        "aiutoTemi": "Aiuto con Temi",
        // Le opzioni di Liquid in coda alle pagine (decisione del manutentore)
        "opzioniLiquid": "Opzioni di Liquid",
        "opzioniLiquidDescr": "Funzioni di Liquid che Windows non ha"
    },
    "en": {
        "impostazioni": "Settings",
        "cerca": "Find a setting",
        "indietro": "Back",
        "accountLocale": "Local account",
        "nonDisponibile": "Not available yet",
        "attivato": "On",
        "disattivato": "Off",
        "home": "Home",
        "sistema": "System",
        "dispositivi": "Bluetooth & devices",
        "rete": "Network & internet",
        "personalizzazione": "Personalization",
        "app": "Apps",
        "account": "Accounts",
        "ora": "Time & language",
        "giochi": "Gaming",
        "accessibilita": "Accessibility",
        "privacy": "Privacy & security",
        "update": "Liquid Update",
        "selezionaTema": "Select a theme to apply",
        "sfondo": "Background",
        "sfondoDescr": "Background image, color, slideshow",
        "colori": "Colors",
        "coloriDescr": "Accent color, transparency effects, color theme",
        "temi": "Themes",
        "temiDescr": "Install, create, manage",
        "illuminazione": "Dynamic Lighting",
        "illuminazioneDescr": "Connected devices, effects, app settings",
        "blocco": "Lock screen",
        "bloccoDescr": "Lock screen images, apps, animations",
        "immissione": "Text input",
        "immissioneDescr": "Touch keyboard, voice typing, emoji and more, input method editor",
        "start": "Start",
        "startDescr": "Apps and recent items, folders",
        "barra": "Taskbar",
        "barraDescr": "Taskbar behaviors, pinned system items",
        "caratteri": "Fonts",
        "caratteriDescr": "Install, manage",
        "anteprima": "Desktop preview",
        "personalizzaSfondo": "Personalize your background",
        "personalizzaSfondoDescr": "A background image applies to the current desktop. Solid colors and slideshows apply to all desktops.",
        "immagine": "Picture",
        "tintaUnita": "Solid color",
        "presentazione": "Slideshow",
        "inEvidenza": "Windows spotlight",
        "immaginiRecenti": "Recent images",
        "scegliFoto": "Choose a photo",
        "sfogliaFoto": "Browse photos",
        "adattamento": "Choose a fit for your desktop image",
        "riempi": "Fill",
        "adatta": "Fit",
        "allunga": "Stretch",
        "affianca": "Tile",
        "centra": "Center",
        "estendi": "Span",
        "coloreSfondo": "Choose your background color",
        "coloriPersonalizzati": "Custom colors",
        "visualizzaColori": "View colors",
        "album": "Choose a picture album for a slideshow",
        "sfoglia": "Browse",
        "cambiaOgni": "Change picture every",
        "casuale": "Shuffle the picture order",
        "correlate": "Related settings",
        "contrasto": "Contrast themes",
        "contrastoDescr": "Color themes for low vision and light sensitivity",
        "supporto": "Related support",
        "aiutoSfondo": "Help with background",
        "informazioni": "About",
        "modalita": "Choose your mode",
        "modalitaDescr": "Change the colors that appear in Windows and your apps",
        "chiara": "Light",
        "scura": "Dark",
        "personalizzata": "Custom",
        "modalitaWindows": "Choose your default Windows mode",
        "modalitaApp": "Choose your default app mode",
        "trasparenza": "Transparency effects",
        "trasparenzaDescr": "Makes Start, taskbar and panels translucent. Window effects are configured on the Windows page.",
        "colorePrincipale": "Accent color",
        "automatico": "Automatic",
        "manuale": "Manual",
        "coloriRecenti": "Recent colors",
        "coloriWindows": "Liquid colors",
        "accentoStart": "Show accent color on Start and taskbar",
        "soloScura": "This setting is only available in Windows dark mode.",
        "accentoBarre": "Show accent color on title bars and window borders",
        "coloreSelezionato": "Selected",
        "temaCorrente": "Current theme",
        "temaCorrenteDescr": "Choose a combination of backgrounds, sounds and colors to personalize your desktop",
        "personalizzato": "Custom",
        "colore": "Color",
        "suoni": "Sounds",
        "cursore": "Mouse cursor",
        "salva": "Save",
        "altriTemi": "Get more themes from Microsoft Store",
        "sfogliaTemi": "Browse themes",
        "iconeDesktop": "Desktop icon settings",
        "aiutoTemi": "Help with Themes",
        "opzioniLiquid": "Liquid options",
        "opzioniLiquidDescr": "Additional Liquid features"
    }
};

/// Un testo nella lingua chiesta; se manca, l'italiano.
function t(lingua, chiave) {
    var tab = testi[lingua] || {};
    if (tab[chiave] !== undefined)
        return tab[chiave];
    return testi.it[chiave] !== undefined ? testi.it[chiave] : chiave;
}

/// Le categorie della barra laterale, nell'ordine di Windows. `icona` è il
/// file a colori in `settings/windows/icone/` (Fluent MIT; vedi SOURCE.md).
var categorie = [
    { "id": "home", "icona": "home" },
    { "id": "sistema", "icona": "sistema" },
    { "id": "dispositivi", "icona": "dispositivi" },
    { "id": "rete", "icona": "rete" },
    { "id": "personalizzazione", "icona": "personalizzazione" },
    { "id": "app", "icona": "app" },
    { "id": "account", "icona": "account" },
    { "id": "ora", "icona": "ora" },
    { "id": "giochi", "icona": "giochi" },
    { "id": "accessibilita", "icona": "accessibilita" },
    { "id": "privacy", "icona": "privacy" },
    { "id": "update", "icona": "update" }
];

/// Le voci della pagina Personalizzazione, nell'ordine di Windows. `pagina`
/// è la pagina Windows costruita; `liquid` la pagina di Liquid che fa le sue
/// veci finché quella Windows non c'è; nessuna delle due: grigia.
var personalizzazione = [
    { "id": "sfondo", "icona": "image", "pagina": "w-sfondo" },
    { "id": "colori", "icona": "colori", "pagina": "w-colori" },
    { "id": "temi", "icona": "temi", "pagina": "w-temi" },
    { "id": "illuminazione", "icona": "illuminazione" },
    { "id": "blocco", "icona": "lock", "liquid": "accesso" },
    { "id": "immissione", "icona": "tastiera", "liquid": "input" },
    { "id": "start", "icona": "grid", "pagina": "w-start" },
    { "id": "barra", "icona": "barra", "pagina": "w-barra" },
    { "id": "caratteri", "icona": "caratteri" }
];

/// I 48 «Colori di Liquid», con i nomi che Windows legge allo schermo.
/// Valori misurati sui pixel della pagina Colori.
var coloriWindows = [
    ["#FFB900", "Giallo oro"], ["#FF8C00", "Oro"], ["#F7630C", "Arancione brillante"],
    ["#CA5010", "Arancione scuro"], ["#DA3B01", "Ruggine"], ["#EF6950", "Ruggine pallido"],
    ["#D13438", "Rosso mattone"], ["#FF4343", "Rosso moderno"], ["#E74856", "Rosso pallido"],
    ["#E81123", "Rosso"], ["#EA005E", "Rosa brillante"], ["#C30052", "Rosa"],
    ["#E3008C", "Prugna chiaro"], ["#BF0077", "Prugna"], ["#C239B3", "Orchidea chiaro"],
    ["#9A0089", "Orchidea"], ["#0078D4", "Blu"], ["#0063B1", "Blu scuro"],
    ["#8E8CD8", "Viola"], ["#6B69D6", "Viola scuro"], ["#8764B8", "Iris pastello"],
    ["#744DA9", "Iris primaverile"], ["#B146C2", "Rosso viola chiaro"], ["#881798", "Rosso viola"],
    ["#0099BC", "Blu freddo brillante"], ["#2D7D9A", "Blu freddo"], ["#00B7C3", "Spuma marina"],
    ["#038387", "Verde acqua"], ["#00B294", "Verde menta chiaro"], ["#018574", "Verde menta scuro"],
    ["#00CC6A", "Verde erba"], ["#10893E", "Verde sport"], ["#7A7574", "Grigio"],
    ["#5D5A58", "Marrone grigio"], ["#68768A", "Blu acciaio"], ["#515C6B", "Blu metallico"],
    ["#567C73", "Verde muschio pallido"], ["#486860", "Verde muschio"], ["#498205", "Verde prato"],
    ["#107C10", "Verde"], ["#767676", "Grigio plumbeo"], ["#4C4A48", "Grigio temporale"],
    ["#69797E", "Grigio blu"], ["#4A5459", "Grigio scuro"], ["#647C64", "Verde ninfea"],
    ["#525E54", "Salvia"], ["#847545", "Mimetico deserto"], ["#7E735F", "Mimetico"]
];

/// I 24 colori di «Tinta unita» dello sfondo.
var coloriSfondo = [
    ["#FF8C00", "Oro"], ["#E81123", "Rosso"], ["#D13438", "Rosso mattone"], ["#C30052", "Rosa"],
    ["#BF0077", "Prugna"], ["#9A0089", "Orchidea"], ["#881798", "Rosso viola"], ["#744DA9", "Iris primaverile"],
    ["#10893E", "Verde sport"], ["#107C10", "Verde"], ["#018574", "Verde menta scuro"], ["#2D7D9A", "Blu freddo"],
    ["#0063B1", "Blu scuro"], ["#6B69D6", "Viola scuro"], ["#8E8CD8", "Viola"], ["#8764B8", "Iris pastello"],
    ["#038387", "Verde acqua"], ["#486860", "Verde muschio"], ["#525E54", "Salvia"], ["#7E735F", "Mimetico"],
    ["#4C4A48", "Grigio temporale"], ["#515C6B", "Blu metallico"], ["#4A5459", "Grigio scuro"], ["#000000", "Nero"]
];

/// Il nome di un colore, se è uno di quelli di Windows; altrimenti
/// «Colore personalizzato», come in Windows.
function nomeColore(hex) {
    var h = String(hex).toUpperCase();
    for (var i = 0; i < coloriWindows.length; i++)
        if (coloriWindows[i][0] === h)
            return coloriWindows[i][1];
    for (var j = 0; j < coloriSfondo.length; j++)
        if (coloriSfondo[j][0] === h)
            return coloriSfondo[j][1];
    return "Colore personalizzato";
}

/// «Cambia immagine ogni»: da verificare sulla tendina vera (non ancora
/// fotografata aperta); minuti.
var intervalli = [[1, "1 minuto"], [10, "10 minuti"], [30, "30 minuti"], [60, "1 ora"], [360, "6 ore"], [1440, "1 giorno"]];

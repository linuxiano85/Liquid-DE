pragma Singleton
import QtQuick

// Palette Minerva — «Continuum»
//
// L'idea: la shell è UN SOLO MATERIALE, non una raccolta di riquadri. Un vetro
// spesso, colorato, attraverso cui si vede quello che c'è dietro; la luce entra
// dagli accenti e si diffonde.
//
// Perciò le superfici non sono colori indipendenti ma una scala di profondità
// ricavata da un'unica base. Prima ogni pannello sceglieva il proprio
// `rgba(1,1,1,0.05)` e il risultato era un collage: superfici della stessa
// profondità apparivano diverse a seconda di cosa avevano dietro.
//
// Regola: non scrivere MAI un colore letterale in un widget. Se manca una
// tonalità, si aggiunge qui.
//
// ── Perché questo file è stato rifatto ────────────────────────────────────
//
// Giacomo: «questo scuro un po' mi sta stancando. ad esempio avere il bianco
// con vetro sfocato e unificato, rosa, verde, sempre effetto blur gaussiano,
// nessuno lo fa».
//
// Aggiungere una tavolozza chiara accanto a quella scura non funzionava, e il
// motivo sta in quattro righe che c'erano prima:
//
//     readonly property color raised: Qt.rgba(1, 1, 1, 0.055)
//     readonly property color hover:  Qt.rgba(1, 1, 1, 0.075)
//     readonly property color edge:   Qt.rgba(1, 1, 1, 0.11)
//     readonly property color text:   "#EEF4FF"
//
// Le velature erano BIANCHE e il testo CHIARO, cioè la scurezza non era un
// colore fra i tanti: era cotta dentro la derivazione. Su un fondo bianco un
// velo bianco al 5% non si vede, e un testo #EEF4FF nemmeno.
//
// Adesso un tema è due cose sole — una TINTA e un VERSO (chiara o scura) — e
// tutto il resto si ricava. Le velature schiariscono su fondo scuro e
// scuriscono su fondo chiaro; il testo va verso il bianco o verso il nero
// restando nella famiglia della tinta, così un tema rosa ha un grigio rosato
// e non un grigio qualunque.
QtObject {
    id: palette

    // ── I temi ───────────────────────────────────────────────────────────
    //
    // Ognuno è una tinta e un verso. Tre scuri e tre chiari, e non è
    // simmetria per bellezza: chi cambia tema di solito vuole cambiare
    // LUMINOSITÀ, e trovarne uno solo dell'altro verso vuol dire non avere
    // scelta ma un interruttore.
    //
    // `base` è il colore del vetro. Tutto il resto — superfici, veli, bordi,
    // testo — esce da qui.
    readonly property var schemes: ({
        "notte":    { "base": "#070A12", "scura": true,
                      "accento": "#22D3EE", "alt": "#8B5CF6",
                      "it": "Notte",    "en": "Night" },
        "carbone":  { "base": "#0D0D0F", "scura": true,
                      "accento": "#A3A3A3", "alt": "#78716C",
                      "it": "Carbone",  "en": "Charcoal" },
        "ametista": { "base": "#140A1E", "scura": true,
                      "accento": "#C084FC", "alt": "#F0ABFC",
                      "it": "Ametista", "en": "Amethyst" },
        "giorno":   { "base": "#EDF0F7", "scura": false,
                      "accento": "#0284C7", "alt": "#7C3AED",
                      "it": "Giorno",   "en": "Day" },
        "rosa":     { "base": "#FBEBF2", "scura": false,
                      "accento": "#DB2777", "alt": "#9333EA",
                      "it": "Rosa",     "en": "Rose" },
        "verde":    { "base": "#E9F4EC", "scura": false,
                      "accento": "#059669", "alt": "#0D9488",
                      "it": "Verde",    "en": "Green" }
    })

    /// Il tema in uso. Lo lega alle impostazioni `theme/LegaTema.qml`, che
    /// ogni punto d'ingresso instanzia una volta: sono processi diversi e non
    /// possono leggersi le proprietà a vicenda, ma la sorgente è la stessa.
    property string scheme: "notte"

    // ── Il settimo tema è tuo ────────────────────────────────────────────
    //
    // Giacomo, 3 settembre 2026: «se voglio il colore delle finestre rosa i
    // caratteri viola e altre cose stravaganti?».
    //
    // I sei qui sopra sono scelte fatte da noi: una tinta e un verso che si
    // sposano. «personale» non è un settimo elenco — è la stessa derivazione
    // con la tinta e il verso decisi da chi usa il computer. Tutto quello che
    // c'è sotto continua a valere: superfici, veli, bordi e testo escono da
    // `mix`, `alza` e `velo` come per gli altri sei.
    //
    // Sta FUORI da `schemes` di proposito. Dentro sarebbe una voce con una
    // tinta scritta a mano che poi nessuno usa, e soprattutto con un `scura`
    // finto: il demone legge quell'elenco per sapere su che fondo staranno le
    // icone (`services/schemi.dart`), e per il tema personale quel bit non è
    // un dato dell'elenco, è una scelta di adesso.
    property color tintaPersonale: "#101018"
    property bool versoPersonale: true

    readonly property bool personale: palette.scheme === "personale"

    readonly property var _s: palette.schemes[palette.scheme]
                              || palette.schemes["notte"]

    /// Vero quando il vetro è scuro. Da qui dipende il VERSO di tutto il
    /// resto: quale direzione prendono le velature e da che parte va il testo.
    readonly property bool scura: palette.personale ? palette.versoPersonale
                                                    : palette._s.scura

    // ── Gli scavalcamenti ────────────────────────────────────────────────
    //
    // «I caratteri viola» non è una tinta: è un colore preciso messo al posto
    // di uno che la derivazione avrebbe calcolato. Qui ci sono quelli che si
    // possono scavalcare uno per uno, e sono sette perché di più non
    // servirebbero a niente: gli altri quaranta escono da questi.
    //
    // ── E perché è una libertà pericolosa, detta chiaramente ─────────────
    //
    // I numeri di questo file sono MISURATI, non scelti: `windowOpacityMin`
    // viene da un conto di contrasto su una fotografia chiara, `textFaint` è
    // stato alzato due volte perché a occhio sembrava a posto e non lo era.
    // Uno scavalcamento libero rende falsi tutti quei conti in un istante.
    //
    // La risposta non è impedirlo — è la scrivania di chi la usa — ma dirlo:
    // `contrasto()` qui sotto è lo stesso conto, e le Impostazioni lo mostrano
    // accanto alla scelta mentre la si fa. Avvisare, non vietare.
    //
    // Il ripiego è `{}`: nessuno scavalcamento, la derivazione intatta.
    property var scavalca: ({})

    /// Da «#RRGGBB» a un colore. Serve perché gli scavalcamenti arrivano dal
    /// file delle impostazioni, cioè come testo, e alcuni di loro finiscono
    /// dentro `Qt.rgba(c.r, …)`: una stringa lì non ha `.r`, e il colore
    /// uscirebbe nero senza che nessuno segnali niente.
    function tinta(hex) {
        var t = String(hex).trim();
        if (t.charAt(0) !== "#" || (t.length !== 7 && t.length !== 4))
            return palette._nero;
        if (t.length === 4)
            t = "#" + t[1] + t[1] + t[2] + t[2] + t[3] + t[3];
        return Qt.rgba(parseInt(t.substr(1, 2), 16) / 255,
                       parseInt(t.substr(3, 2), 16) / 255,
                       parseInt(t.substr(5, 2), 16) / 255, 1);
    }

    /// Il valore scavalcato, se c'è; altrimenti quello che la derivazione
    /// aveva calcolato.
    function _ov(nome, valore) {
        var v = palette.scavalca ? palette.scavalca[nome] : undefined;
        if (v === undefined || v === null || String(v).trim() === "")
            return valore;
        return palette.tinta(v);
    }

    /// I nomi che si possono scavalcare. Uno solo, qui, così le Impostazioni
    /// non se ne inventano uno che nessuno legge — è già successo con
    /// `bar.position`, che si poteva scrivere e non faceva niente.
    readonly property var scavalcabili: [
        "base", "testo", "membrana", "bordo", "positivo", "avviso", "pericolo"
    ]

    // ── Gli attrezzi della derivazione ───────────────────────────────────

    /// Mescola due colori. `t` a 0 dà il primo, a 1 il secondo.
    function mix(a, b, t) {
        return Qt.rgba(a.r + (b.r - a.r) * t,
                       a.g + (b.g - a.g) * t,
                       a.b + (b.b - a.b) * t,
                       a.a + (b.a - a.a) * t);
    }

    readonly property color _bianco: Qt.rgba(1, 1, 1, 1)
    readonly property color _nero:   Qt.rgba(0, 0, 0, 1)

    /// La direzione «verso la luce» per questo tema.
    readonly property color _luce: palette.scura ? palette._bianco : palette._nero

    /// Alza una superficie di `quanto`, cioè la porta verso il bianco. Vale
    /// in tutti e due i versi: un pannello che galleggia sopra la scrivania è
    /// più chiaro del fondo sia sul nero sia sul bianco. È il motivo per cui
    /// qui non si usa `_luce` — «più in alto» e «più leggibile» non sono la
    /// stessa direzione.
    function alza(quanto) {
        return palette.mix(palette.base, palette._bianco, quanto);
    }

    /// Una velatura: bianca sul fondo scuro, nera sul fondo chiaro.
    ///
    /// Le due non pesano uguale. Un velo nero al 5% su fondo bianco si vede
    /// molto più di un velo bianco al 5% su fondo nero — è come funziona
    /// l'occhio, non un difetto dei numeri — quindi sul chiaro si calca meno.
    function velo(quanto) {
        return Qt.rgba(palette._luce.r, palette._luce.g, palette._luce.b,
                       palette.scura ? quanto : quanto * 0.72);
    }

    // ── Base ─────────────────────────────────────────────────────────────
    //
    // Sul tema scuro il nero non è nero: è blu notte molto desaturato. Il nero
    // puro accanto al ciano fa sembrare l'accento stridulo; una base fredda lo
    // integra. Lo stesso ragionamento vale al contrario sui temi chiari, dove
    // il bianco puro accanto a un accento saturo sembra spento: «Giorno» è un
    // bianco appena azzurrato, «Rosa» un bianco appena rosato.
    readonly property color base:
        palette._ov("base", palette.personale ? palette.tintaPersonale
                                              : palette._s.base)

    // ── Superfici ────────────────────────────────────────────────────────
    //
    // `scrim`     — l'oscuramento dietro ai pannelli a schermo intero
    // `membrane`  — LA superficie continua: barra e pannelli agganciati
    // `panel`     — pannelli fluttuanti (menu contestuali, schede)
    // `raised`    — un gradino sopra il pannello che lo contiene
    // `sunken`    — campi di testo, incavi
    //
    // La membrana è deliberatamente molto coprente: contiene testo da leggere
    // sopra finestre di qualunque colore. Il blur del compositore la
    // ammorbidisce, non deve essere lui a renderla leggibile.
    //
    // `membraneOpacity` è una delle poche cose qui dentro che si possono
    // cambiare da fuori: la lega alle impostazioni la shell. Sotto 0,75 il
    // testo sopra una finestra di colore opposto comincia a perdersi, per
    // questo il cursore si ferma lì.
    property real membraneOpacity: 0.93

    /// Quanto sono trasparenti le FINESTRE di Minerva — il gestore file, le
    /// impostazioni. È una manopola diversa da quella della membrana: la barra
    /// sta sempre sopra qualcosa e deve restare leggibile, una finestra ha
    /// dietro di sé la scrivania e può permettersi molto di più.
    ///
    /// Il vetro vero — la sfocatura — lo fa il compositore (l'effetto «blur»,
    /// `Compositore.effetto`), e si vede SOLO se il pixel è trasparente. È il motivo per cui questo numero non è cosmesi:
    /// a 1.0 la finestra è opaca e il blur non esiste, qualunque cosa dica la
    /// configurazione del compositore.
    property real windowOpacity: 0.88

    /// Il fondo minimo sotto cui una finestra smette di essere leggibile.
    ///
    /// Non è prudenza: è misurato. Con la scrivania su una foto chiara — neve,
    /// cielo, un muro bianco — il fondo effettivo di una finestra al 55% è un
    /// grigio a 114 su 255, e il testo secondario sopra ci arriva a un rapporto
    /// di contrasto di 2,5:1. La soglia sotto cui un testo piccolo non si legge
    /// più senza sforzo è 4,5:1. Alla stessa scrivania, un terminale al 85% —
    /// che è il valore con cui li spedisce quasi tutto il mondo — sta a 6:1.
    ///
    /// Il cursore delle Impostazioni si ferma qui, e questo controllo esiste
    /// perché la configurazione può contenere un valore più basso scritto
    /// quando il cursore arrivava fin laggiù. Una finestra illeggibile non è
    /// una preferenza: è un guasto che l'utente si è potuto infliggere.
    ///
    /// Sui temi CHIARI il minimo sale: il testo scuro sopra un vetro
    /// troppo trasparente diventa grigio sopra qualunque cosa ci passi
    /// dietro — misurato al 78%, su un terminale chiaro i nomi dei file
    /// scendevano a 2,6:1, cioè sotto la soglia. Il testo chiaro su fondo
    /// scuro perdona molto di più dello stesso valore al contrario.
    readonly property real windowOpacityMin: palette.scura ? 0.78 : 0.93

    readonly property color window:
        Qt.rgba(palette.base.r, palette.base.g, palette.base.b,
                Math.max(palette.windowOpacityMin, palette.windowOpacity))

    /// Lo scurimento dietro ai pannelli è sempre NERO, anche sui temi chiari:
    /// serve a spingere indietro ciò che copre, e solo il buio lo fa. Su
    /// fondo chiaro basta molto meno perché lo stacco si veda.
    readonly property color scrim:
        Qt.rgba(0, 0, 0, palette.scura ? 0.55 : 0.30)

    // Lo scavalcamento tocca la TINTA, non la trasparenza: quella è una
    // manopola a sé, e chi sceglie un colore per la barra non sta chiedendo
    // anche di renderla opaca.
    readonly property color membrane: {
        var c = palette._ov("membrana", palette.alza(palette.scura ? 0.02 : 0.30));
        return Qt.rgba(c.r, c.g, c.b, palette.membraneOpacity);
    }

    readonly property color panel: {
        var c = palette._ov("membrana", palette.alza(palette.scura ? 0.045 : 0.55));
        return Qt.rgba(c.r, c.g, c.b,
                       Math.min(1, palette.membraneOpacity + 0.03));
    }

    readonly property color raised:     palette.velo(0.055)
    readonly property color raisedHigh: palette.velo(0.09)

    /// L'incavo è sempre più SCURO di ciò che lo contiene, in tutti e due i
    /// versi: un campo di testo è un buco, e un buco non si illumina.
    readonly property color sunken:
        Qt.rgba(0, 0, 0, palette.scura ? 0.28 : 0.055)

    // ── La superficie su cui si LEGGE ────────────────────────────────────
    //
    // Il vetro è il segno di Minerva e non si tocca — ma vale per ciò che
    // GALLEGGIA: la barra, i pannelli, i menu. Stanno sopra la scrivania per
    // un attimo, e vedere attraverso li lega a quello che c'è sotto.
    //
    // Un elenco di file non galleggia: ci si sta dentro dei minuti, e si
    // legge. Con il solo velo del riquadro il fondo arrivava al 91%, e il
    // nove per cento restante era abbastanza perché il terminale dietro si
    // leggesse FRA i nomi dei file. Non illeggibile: disordinato, che in un
    // programma è quasi peggio.
    //
    // Quindi due materiali, e una regola che si dice in una riga: **vetro
    // per quello che galleggia, superficie piena per quello che si legge.**
    // La finestra resta di vetro ai bordi — barra degli strumenti, colonna
    // dei posti — e il vetro si vede ancora, dove serve a far vedere che
    // c'è una scrivania dietro.
    readonly property color lettura: {
        var c = palette.alza(palette.scura ? 0.005 : 0.35);
        return Qt.rgba(c.r, c.g, c.b, 0.985);
    }

    // ── Interazione ──────────────────────────────────────────────────────
    readonly property color hover:    palette.velo(0.075)
    readonly property color pressed:  palette.velo(0.12)

    /// La selezione prende il colore dell'accento, non un ciano fisso. Prima
    /// era scritto a mano: cambiando accento la selezione restava ciano, ed
    /// era l'unica cosa in tutta la shell a non seguire.
    readonly property color selected: Qt.alpha(palette.accent, 0.15)

    // ── Contorni ─────────────────────────────────────────────────────────
    // Il bordo non serve a delimitare: serve a far cogliere la curvatura.
    readonly property color edge:       palette._ov("bordo", palette.velo(0.11))
    readonly property color edgeBright: palette.velo(0.20)
    readonly property color edgeAccent: Qt.alpha(palette.accent, 0.42)

    // ── Accenti ──────────────────────────────────────────────────────────
    /// L'accento lo sceglie chi usa il computer: la shell lo lega alle
    /// impostazioni. Il valore qui sotto è quello suggerito dal tema, ed è
    /// anche quello che si rimette scegliendo un tema nuovo — un ciano acceso
    /// su un fondo rosa chiaro non è una scelta, è una dimenticanza.
    property color accent: palette._s.accento

    readonly property color accentAlt:     palette._s.alt
    readonly property color accentWarm:    "#F0ABFC"


    // ── Testo ────────────────────────────────────────────────────────────
    //
    // Non bianco e non nero: la tinta del tema portata quasi fino in fondo.
    // Un grigio neutro su un fondo rosa si legge come una macchia sporca; lo
    // stesso grigio con dentro un soffio di rosa appartiene alla superficie.
    readonly property color text: palette._ov("testo", palette.scura
        ? palette.mix(palette.base, palette._bianco, 0.97)
        : palette.mix(palette.base, palette._nero, 0.93))

    /// I due gradi di «meno importante». Le trasparenze NON sono le stesse
    /// nei due versi, e non è una svista: un testo chiaro su fondo scuro
    /// rende molto più contrasto della stessa percentuale al contrario —
    /// l'occhio è più sensibile alle differenze in basso alla scala. Con i
    /// numeri del tema scuro, sul tema chiaro le icone della barra degli
    /// strumenti sbiadivano fino a sembrare tutte disattivate.
    //
    // Alzate il 2 agosto 2026 su segnalazione di Giacomo («colori più visibili
    // nella modalità chiara o scura, sono poco leggibili»). La più colpevole
    // era `textFaint` al 34%: le descrizioni sotto ogni impostazione, le unità
    // di misura e le etichette delle icone finivano sotto la soglia in cui si
    // leggono senza sforzo. Un testo che c'è ma non si legge è peggio di un
    // testo che non c'è: occupa spazio e chiede attenzione per niente.
    //
    // Alzate di nuovo il 3 agosto, insieme al fondo minimo delle finestre
    // (`windowOpacityMin`). Il conto: su una finestra all'85% sopra una foto
    // chiara, `textFaint` al 52% rendeva 4,7:1 — appena sopra la soglia, cioè
    // «tecnicamente leggibile» e in pratica no. Al 66% rende 6,2:1.
    //
    // Restano tre gradini e non due, perché servono a dire tre cose diverse —
    // questo conta, questo è di contorno, questo è un dettaglio — ma tutti e
    // tre stanno adesso sopra la soglia. La gerarchia si fa con la distanza
    // fra i gradini, non spingendo l'ultimo fuori dal leggibile.
    readonly property color textMuted: Qt.alpha(palette.text,
                                                palette.scura ? 0.85 : 0.88)
    readonly property color textFaint: Qt.alpha(palette.text,
                                                palette.scura ? 0.66 : 0.72)

    /// Il testo SOPRA l'accento. Non si può fissare: un accento chiaro vuole
    /// scritte scure e uno scuro le vuole chiare, e l'accento lo sceglie chi
    /// usa il computer. Si guarda quanta luce ha — la formula è quella della
    /// luminanza percepita, dove il verde pesa più del rosso e il blu quasi
    /// niente — e si prende il contrario.
    readonly property color textOnAccent: {
        var l = 0.2126 * palette.accent.r + 0.7152 * palette.accent.g
              + 0.0722 * palette.accent.b;
        return l > 0.55 ? Qt.rgba(0.02, 0.07, 0.10, 1)
                        : Qt.rgba(0.98, 0.99, 1.00, 1);
    }

    // ── Stati ────────────────────────────────────────────────────────────
    //
    // Sui temi chiari vanno scuriti: un verde menta che si legge benissimo su
    // nero, su bianco è una scritta che sbiadisce.
    readonly property color positive:
        palette._ov("positivo", palette.scura ? "#34D399" : "#047857")
    readonly property color warning:
        palette._ov("avviso",   palette.scura ? "#FBBF24" : "#B45309")
    readonly property color danger:
        palette._ov("pericolo", palette.scura ? "#FB7185" : "#BE123C")

    // ── Il conto del contrasto ───────────────────────────────────────────
    //
    // Lo stesso che ha alzato `textFaint` due volte, messo dove chiunque può
    // rifarlo invece di doverselo ricordare.
    //
    // ── E NON è la formula di `textOnAccent` ─────────────────────────────
    //
    // Quella somma le componenti così come sono, e serve a rispondere a una
    // domanda binaria: «questo accento è chiaro o scuro?». Un RAPPORTO di
    // contrasto è un'altra cosa: le componenti vanno prima linearizzate,
    // perché il valore che sta in un pixel non è la luce che ne esce — lo
    // schermo applica una curva. Saltare quel passaggio dà numeri che
    // sembrano giusti e sono ottimisti proprio dove serve la verità: sui grigi
    // di mezzo.
    function luminanzaRelativa(c) {
        function lin(v) {
            return v <= 0.03928 ? v / 12.92
                                : Math.pow((v + 0.055) / 1.055, 2.4);
        }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
    }

    /// Da 1 (identici, illeggibile) a 21 (nero su bianco). La soglia sotto cui
    /// un testo piccolo non si legge senza sforzo è 4,5.
    function contrasto(a, b) {
        var la = palette.luminanzaRelativa(a);
        var lb = palette.luminanzaRelativa(b);
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }

}

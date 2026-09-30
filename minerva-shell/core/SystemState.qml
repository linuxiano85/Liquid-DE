pragma Singleton
import QtQuick
import Quickshell
// `Quickshell.Io` non serve più: qui non si lancia più nessun processo.
import Quickshell.Services.Pipewire
// La propria cartella, dichiarata: è da lì che arriva `Sounds`.
import "." as Core

// SystemState — Lo stato dell'apparecchio, come lo vede questa finestra.
//
// ── Il nome è rimasto, il mestiere è cambiato ────────────────────────────
//
// Questo file INTERROGAVA il sistema: quattro comandi di shell ogni dodici
// secondi per batteria, luminosità, rete e Bluetooth. Ed era già un passo
// avanti, perché prima li interrogava ogni widget per conto suo.
//
// Restava un difetto che da qui non si poteva vedere: è un singleton **per
// processo**, e i processi di Minerva sono tre — la barra, il gestore file,
// le Impostazioni. Tre giri indipendenti, tre volte i comandi lanciati, e
// soprattutto **i tre non si parlavano**. Spegnendo il Bluetooth dalle
// Impostazioni, la barra continuava a mostrarlo acceso fino al proprio giro:
// fino a dodici secondi, in media sei. È il ritardo che Giacomo aveva
// segnalato, e non era lentezza — era una finestra che non poteva sapere.
//
// Adesso legge il demone, che interroga una volta per tutti e annuncia il
// risultato nello stesso istante a chiunque sia collegato. Vedi
// `minervad/lib/services/system_state_service.dart`.
//
// Chi usa questo file non se ne accorge: i nomi sono gli stessi
// (`bluetoothOn`, `brightness`, `setBluetooth`…), e restano l'unica cosa da
// conoscere.
//
// ── Il volume no, e non è una dimenticanza ───────────────────────────────
//
// PipeWire lo ANNUNCIA nell'istante in cui cambia, chiunque l'abbia
// cambiato, e ogni processo lo riceve da sé senza interrogare niente. Farlo
// passare dal demone aggiungerebbe un rimbalzo a un dato che arriva già
// istantaneo. La regola è quella, e vale per il prossimo pezzo di stato che
// aggiungeremo: **si sposta nel demone ciò che va INTERROGATO, resta qui ciò
// che il sistema già ANNUNCIA.**
QtObject {
    id: sys

    // ── Batteria ─────────────────────────────────────────────────────────
    property int batteryPercent: -1        // -1 = nessuna batteria
    property bool batteryCharging: false
    readonly property bool hasBattery: batteryPercent >= 0

    // ── Audio ────────────────────────────────────────────────────────────
    //
    // Il volume non si legge lanciando `pactl`: lo dice PipeWire, e lo dice
    // nell'istante in cui cambia, chiunque l'abbia cambiato — il cursore del
    // pannello, il tasto del volume, un altro programma.
    //
    // Prima era una lettura a intervalli, ogni 1,2 secondi per sempre: sei
    // processi lanciati e attesi ogni volta, giorno e notte, per un dato che
    // resta uguale per ore. È quello che rendeva «lentissima» la reazione ai
    // tasti del volume — l'avviso a schermo aspettava il prossimo giro invece
    // di sapere — e che rubava fotogrammi alle animazioni dei pannelli.
    // Adesso non c'è nessun giro da aspettare e nessun processo da lanciare.
    readonly property PwNode sink: Pipewire.defaultAudioSink

    property PwObjectTracker _sinkTracker: PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    readonly property int volume: sys.sink && sys.sink.audio
                                  ? Math.round(sys.sink.audio.volume * 100) : 0
    readonly property bool muted: sys.sink && sys.sink.audio
                                  ? sys.sink.audio.muted : false

    // ── Il tetto del 100% ────────────────────────────────────────────────
    //
    // PipeWire lascia salire il volume ben oltre il 100%: è amplificazione
    // software vera, non un numero finto, ma è anche il modo più rapido di
    // ottenere un suono gracchiante da altoparlanti che non hanno più niente
    // da dare. Premendo il tasto del volume si arrivava al 500% senza che
    // niente si opponesse, e il suono da un pezzo aveva smesso di crescere.
    //
    // Quindi: 100 è il massimo, e chi vuole di più lo dice di proposito
    // dalle Impostazioni. Se lo si trova già oltre — l'ha alzato un altro
    // programma — si riporta giù, una volta sola e senza far storie.
    // Lo lega la shell alle impostazioni, come fa col colore d'accento: qui
    // non si sa che esiste un demone, e uno stato di sistema che va a leggere
    // le preferenze è uno stato che non si può più riusare altrove.
    property int volumeCeiling: 100

    // `Qt.callLater` e non l'assegnazione diretta: PipeWire annuncia il
    // volume nuovo di `sink.audio.volume` in modo SINCRONO, dentro questo
    // stesso gestore — scrivere qui rientrerebbe nel legame di `volume`
    // mentre è ancora in corso di valutazione, ed è esattamente quello che
    // QML chiama «Binding loop detected». Il taglio resta giusto (si
    // ricontrolla il tetto quando il giro riparte), sparisce solo l'avviso.
    onVolumeChanged: {
        if (sys.volume > sys.volumeCeiling)
            Qt.callLater(sys._tagliaVolume);
    }

    function _tagliaVolume() {
        if (sys.volume > sys.volumeCeiling && sys.sink && sys.sink.audio)
            sys.sink.audio.volume = sys.volumeCeiling / 100;
    }

    // ── Luminosità ───────────────────────────────────────────────────────
    property int brightness: -1            // -1 = non regolabile
    readonly property bool hasBrightness: brightness >= 0

    // ── Rete ─────────────────────────────────────────────────────────────
    property string networkName: ""
    property int networkStrength: 0        // 0–100
    property bool networkWired: false
    readonly property bool networkConnected: networkName !== ""

    /// ── La RADIO, che non è la connessione ───────────────────────────────
    ///
    /// L'interruttore del Wi-Fi guardava `networkConnected`, e sbagliava in
    /// tutti e due i versi. Col cavo attaccato la connessione c'è, quindi
    /// risultava acceso anche a radio spenta. E con la radio accesa ma nessuna
    /// rete agganciata — appena arrivati in un posto nuovo — risultava spento,
    /// così premerlo la spegneva davvero invece di accenderla.
    ///
    /// Adesso il demone legge `/sys/class/rfkill`, che è dove `nmcli radio
    /// wifi off` scrive: nessun processo lanciato, solo file.
    property bool wifiOn: false
    /// Falso su un fisso senza scheda Wi-Fi: lì l'interruttore non si mostra.
    property bool wifiPresent: false

    // ── Bluetooth ────────────────────────────────────────────────────────
    property bool bluetoothOn: false
    property string bluetoothDevice: ""
    /// Tutti gli apparecchi accoppiati: `{nome, icona, connesso, batteria, mac}`.
    /// `icona` è la classe di BlueZ (`input-mouse`, `audio-headset`, `phone`…),
    /// `batteria` è −1 quando l'apparecchio non la dice o non è connesso.
    property var bluetoothDevices: []
    /// Vero se esiste un adattatore, comunque sia messo.
    property bool bluetoothPresent: true
    /// Bloccato da `rfkill`. "soft" si toglie via software, "hard" è
    /// l'interruttore fisico del portatile e non c'è comando che lo apra.
    property string bluetoothBlock: ""

    // ── Lettura: arriva, non si va a prendere ────────────────────────────
    //
    // I valori sono proprietà semplici e non legami su `Core.Ipc.system`, e
    // la ragione è il momento in cui si preme un interruttore: lì si scrive
    // il valore voluto SUBITO — l'interruttore deve scattare sotto il dito —
    // e un istante dopo arriva quello vero dal demone e lo conferma o lo
    // corregge. Con un legame non si potrebbe scrivere niente, e ogni
    // comando avrebbe mezzo secondo di interruttore che non si muove.

    function _prendi(s) {
        if (!s || typeof s !== "object")
            return;
        if (s.batteryPercent !== undefined)   sys.batteryPercent = s.batteryPercent;
        if (s.batteryCharging !== undefined)  sys.batteryCharging = s.batteryCharging;
        if (s.brightness !== undefined)       sys.brightness = s.brightness;
        if (s.networkName !== undefined)      sys.networkName = s.networkName;
        if (s.networkStrength !== undefined)  sys.networkStrength = s.networkStrength;
        if (s.networkWired !== undefined)     sys.networkWired = s.networkWired;
        if (s.wifiOn !== undefined)           sys.wifiOn = s.wifiOn;
        if (s.wifiPresent !== undefined)      sys.wifiPresent = s.wifiPresent;
        if (s.bluetoothPresent !== undefined) sys.bluetoothPresent = s.bluetoothPresent;
        if (s.bluetoothOn !== undefined)      sys.bluetoothOn = s.bluetoothOn;
        if (s.bluetoothBlock !== undefined)   sys.bluetoothBlock = s.bluetoothBlock;
        if (s.bluetoothDevice !== undefined)  sys.bluetoothDevice = s.bluetoothDevice;
        if (s.bluetoothDevices !== undefined) sys.bluetoothDevices = s.bluetoothDevices;
    }

    property Connections _dalDemone: Connections {
        target: Core.Ipc
        function onSystemReceived() { sys._prendi(Core.Ipc.system); }
    }


    Component.onCompleted: sys._prendi(Core.Ipc.system)

    // ── Comandi ──────────────────────────────────────────────────────────

    /// Una regolazione fatta DA MINERVA è appena avvenuta.
    ///
    /// Esiste perché `volumeChanged` non basta, e il caso in cui non basta è
    /// proprio quello che dà più fastidio: al massimo, premendo «alza», il
    /// valore non cambia — quindi nessun segnale, quindi nessun avviso a
    /// schermo e nessun suono. Chi preme si ritrova senza risposta
    /// esattamente quando vorrebbe sapere perché non succede niente.
    ///
    /// `atLimit` è vero quando la richiesta è stata TAGLIATA: si è chiesto
    /// più del massimo o meno del minimo. È l'informazione che serve per dire
    /// «sei in fondo» invece di non dire niente.
    signal adjusted(string what, bool atLimit)

    /// ── Chiedere un volume vuol dire voler sentire ────────────────────────
    ///
    /// Chi alza il volume mentre l'audio è muto **toglie il muto**. Detto
    /// così sembra ovvio; non lo era, e il difetto lo ha segnalato Giacomo il
    /// 5 agosto 2026: «se metto muto e poi clicco su alza o abbassa volume
    /// rimane muto, per riavere l'audio devo premere su muto».
    ///
    /// Il modo in cui falliva è il peggiore possibile: **il numero saliva**.
    /// L'avviso a schermo mostrava 40, 45, 50 mentre non usciva un suono, e
    /// il tasto sembrava rotto invece che ignorato. Un comando che risponde
    /// «fatto» senza fare è peggio di uno che non risponde.
    ///
    /// La regola vale anche per il cursore, non solo per i tasti: sono due
    /// modi di dire la stessa cosa, e due comportamenti diversi per la stessa
    /// intenzione sono una cosa in più da imparare a memoria.
    ///
    /// Portare il volume a zero invece **non** mette il muto: sono due stati
    /// diversi: da zero si risale con un tasto, dal muto no. Confonderli
    /// significa togliere a chi ascolta il modo di distinguerli.
    /// La decisione, separata da chi la esegue, così si può provare senza
    /// PipeWire — stessa scelta di `Core.Media.scegli`. Restituisce il volume
    /// da scrivere, se il muto va tolto, e se la richiesta è stata tagliata.
    function decidiVolume(chiesto, muted, tetto) {
        var voluto = Math.round(chiesto);
        var v = Math.max(0, Math.min(tetto, voluto));
        return {
            "volume": v,
            "smuta": v > 0 && muted === true,
            "tagliato": (voluto > tetto) || (voluto < 0)
        };
    }

    function setVolume(percent) {
        if (!sys.sink || !sys.sink.audio)
            return;
        var d = sys.decidiVolume(percent, sys.sink.audio.muted, sys.volumeCeiling);

        sys.sink.audio.volume = d.volume / 100;

        // Prima il volume, poi il muto: al contrario si sentirebbe un istante
        // del volume VECCHIO, che può essere molto più alto di quello chiesto.
        if (d.smuta)
            sys.sink.audio.muted = false;

        sys.adjusted("volume", d.tagliato);
        if (d.tagliato)
            Core.Sounds.limit();
        else
            Core.Sounds.volumeStep(d.volume);
    }

    /// Alza o abbassa di qualche punto. La usano i tasti del volume.
    function stepVolume(delta) {
        sys.setVolume(sys.volume + delta);
    }

    function toggleMute() {
        if (!sys.sink || !sys.sink.audio)
            return;
        var now = !sys.sink.audio.muted;
        sys.sink.audio.muted = now;
        sys.adjusted("volume", false);
        Core.Sounds.mute(now);
    }

    /// La luminosità non ha un PipeWire che la racconti: va scritta e
    /// riletta. La scrive il demone, così il nuovo valore arriva anche alle
    /// altre finestre — il cursore nelle Impostazioni e quello nel pannello
    /// di controllo sono due cursori diversi sulla stessa luminosità.
    ///
    /// Il valore si scrive anche qui, subito: il cursore deve seguire il dito
    /// senza aspettare il giro di ritorno.
    function setBrightness(percent) {
        var wanted = Math.round(percent);
        var v = Math.max(1, Math.min(100, wanted));
        sys.brightness = v;
        sys._luceDaMandare = v;
        if (!sys._ritmoLuce.running)
            sys._mandaLuce();
        // Anche qui l'avviso deve comparire quando si è già in fondo: è lo
        // stesso motivo del volume, e la stessa risposta.
        sys.adjusted("brightness", (wanted > 100) || (wanted < 1));
    }

    // ── Al demone al più una luminosità ogni ottanta millisecondi ────────
    //
    // Il cursore chiama `setBrightness` a ogni movimento del mouse, cioè
    // sessanta volte al secondo, e ogni chiamata era un messaggio e — dal
    // demone — un `brightnessctl` lanciato per conto suo, senza aspettare il
    // precedente. Un secondo di trascinata erano sessanta processi in gara:
    // vinceva l'ultimo a FINIRE, non l'ultimo lanciato, e la luminosità
    // restava su un valore di mezzo. A demone fermo, poi, sessanta valori
    // diversi riempivano la coda di `Core.Ipc` e buttavano fuori il resto.
    // Trovato in revisione il 30 settembre 2026.
    //
    // Adesso il primo valore parte subito, i successivi si tengono da parte
    // e parte l'ULTIMO a ogni scatto: il dito vede la luce muoversi, il
    // demone riceve una manciata di valori, e quello finale arriva sempre.
    property int _luceDaMandare: -1
    property int _luceMandata: -1

    function _mandaLuce() {
        if (sys._luceDaMandare < 0 || sys._luceDaMandare === sys._luceMandata) {
            // Fermi: la prossima volta si manda comunque, anche lo stesso
            // numero — nel frattempo i tasti possono aver cambiato la luce.
            sys._luceMandata = -1;
            return;
        }
        sys._luceMandata = sys._luceDaMandare;
        Core.Ipc.send({ "action": "system_action", "what": "brightness",
                        "value": sys._luceMandata });
        sys._ritmoLuce.restart();
    }

    property Timer _ritmoLuce: Timer {
        interval: 80
        onTriggered: sys._mandaLuce()
    }

    function stepBrightness(delta) {
        if (sys.brightness < 0)
            return;
        sys.setBrightness(sys.brightness + delta);
    }

    /// Accende o spegne il Bluetooth.
    ///
    /// Il comando lo esegue il DEMONE, e la differenza si vede: prima ogni
    /// finestra lo eseguiva per conto suo e le altre restavano indietro fino
    /// al proprio giro — l'interruttore nella barra e quello nelle
    /// Impostazioni raccontavano due Bluetooth diversi. Il perché del
    /// `rfkill unblock` prima dell'accensione sta là, insieme al comando.
    ///
    /// Qui si scrive comunque il valore voluto, subito: l'interruttore deve
    /// scattare sotto il dito. Un istante dopo arriva quello vero.
    function setBluetooth(on) {
        sys.bluetoothOn = on;
        Core.Ipc.send({ "action": "system_action", "what": "bluetooth", "value": on });
    }

    function setWifi(on) {
        // Si scrive subito, come per il Bluetooth: l'interruttore deve
        // scattare sotto il dito. Il demone corregge un istante dopo se il
        // comando non ha funzionato.
        sys.wifiOn = on === true;
        Core.Ipc.send({ "action": "system_action", "what": "wifi", "value": on });
    }

    // ── Il touchpad ──────────────────────────────────────────────────────
    //
    // Il tasto per spegnerlo esiste su questa tastiera (`KEY_TOUCHPAD_TOGGLE`,
    // fra i tasti WMI dell'Acer) e non faceva niente: nessuno lo ascoltava, e
    // soprattutto **non compariva niente a schermo**. Un tasto che non dà
    // risposta è un tasto rotto, anche quando funziona — e qui non funzionava
    // nemmeno.
    //
    // Chi lo spegne di solito ha un mouse attaccato e non vuole sfiorare il
    // touchpad mentre scrive. Quindi la scelta si RICORDA: il demone la
    // conserva fra un accesso e l'altro, come tutte le altre.
    //
    // La via di ritorno è sempre aperta: il tasto è sulla tastiera, quindi
    // anche restando senza mouse si riaccende con lo stesso gesto con cui lo
    // si è spento.

    /// ── CHI SCRIVE E CHI APPLICA ─────────────────────────────────────────
    ///
    /// Qui c'è solo la PREFERENZA, che vive nel demone e la può cambiare
    /// chiunque: il tasto Fn, un interruttore nelle Impostazioni, domani
    /// qualcos'altro.
    ///
    /// **Ad applicarla al compositore è la sola shell** (`avviaTouchpad()`,
    /// chiamata da `shell.qml`). Se lo facesse questo singleton, lo farebbero
    /// tutte e cinque le finestre di Minerva: cinque `hyprctl -j devices`
    /// all'avvio e cinque scritture identiche a ogni pressione del tasto.
    /// È la stessa regola del Bluetooth qui sopra — uno esegue, gli altri
    /// guardano.
    readonly property bool touchpadOn: Core.Ipc.get("input.touchpadOn", true)

    function setTouchpad(acceso) {
        Core.Ipc.setSetting("input.touchpadOn", acceso === true);
    }

    function toggleTouchpad() {
        sys.setTouchpad(!sys.touchpadOn);
    }

    // ── Qui c'erano quattro processi e due cadenze ───────────────────────
    //
    // `batteryProc`, `brightnessProc`, `networkProc`, `bluetoothProc`, più il
    // giro da dodici secondi e la riverifica dopo un comando. Sono tutti nel
    // demone adesso, con gli stessi comandi di shell — dentro ci sono
    // dettagli pagati cari, come `LC_ALL=C` per `nmcli` (che in italiano
    // risponde «sì» dove il codice cercava «yes») e `bluetoothctl list` al
    // posto della riga `Address:` che BlueZ 5.7x non stampa più.
    //
    // Restava anche `applyProc`, che eseguiva i comandi. Non serve più:
    // eseguirli qui voleva dire che le altre finestre non lo sapevano.
}

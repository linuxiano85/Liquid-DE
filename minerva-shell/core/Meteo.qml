pragma Singleton
import QtQuick
import "." as Core

// Meteo — Che tempo fa, per chi lo deve disegnare.
//
// Uno solo per tutta la shell: la barra mostra il simbolo e la temperatura, il
// pannello mostra i dettagli e i sette giorni, e tutti e due leggono di qui.
// Due copie vorrebbero dire due richieste e, prima o poi, due numeri diversi
// sullo stesso schermo.
//
// ── NON PARTE NIENTE FINCHÉ NON SCEGLI UN POSTO ────────────────────────────
//
// `attivo` è falso finché non ci sono coordinate scritte nelle impostazioni,
// e senza coordinate il demone non chiama nessuno. È una garanzia, non una
// gentilezza: chi non vuole il meteo non manda niente da nessuna parte, e non
// deve fidarsi della nostra parola — basta che non scelga una località.
QtObject {
    id: meteo

    readonly property bool acceso: Core.Ipc.get("weather.enabled", false)
    readonly property real lat:    Core.Ipc.get("weather.lat", 0)
    readonly property real lon:    Core.Ipc.get("weather.lon", 0)
    readonly property string luogo: Core.Ipc.get("weather.name", "")

    /// Vero quando c'è tutto per chiedere: acceso E con un posto scelto.
    readonly property bool attivo: meteo.acceso && meteo.luogo !== ""

    /// Il tempo adesso: temperatura, umidità, vento, codice WMO.
    property var adesso: null
    /// I prossimi sette giorni.
    property var giorni: []
    /// Le prossime dodici ore, da quella in corso: `{ ora: "18:00",
    /// temperatura, codice, pioggia, giorno }`.
    property var ore: []
    /// Vero quando quello che si mostra è l'ultima copia buona e non è fresca.
    property bool vecchio: false

    readonly property bool pronto: meteo.adesso !== null

    /// Il nome del tracciato da disegnare, dal codice WMO.
    ///
    /// La tabella vera sta nel demone (`tempoDaCodice`), che è anche l'unico
    /// posto in cui è provata. Qui c'è la sola parte che serve a disegnare, e
    /// tenerla corta è ciò che la tiene uguale all'altra.
    function icona(codice, giorno) {
        if (codice === undefined || codice === null || codice < 0) return "nuvole";
        if (codice <= 1) return giorno === false ? "moon" : "sun";
        if (codice === 2) return "nuvole-sole";
        if (codice === 3) return "nuvole";
        if (codice === 45 || codice === 48) return "nebbia";
        if (codice >= 95) return "temporale";
        if ((codice >= 71 && codice <= 77) || codice === 85 || codice === 86)
            return "neve";
        if (codice >= 51) return "pioggia";
        return "nuvole";
    }

    function descrizione(codice) {
        var it = Core.Strings.lang === "it";
        if (codice === undefined || codice === null || codice < 0)
            return it ? "Nuvoloso" : "Cloudy";
        if (codice === 0) return it ? "Sereno" : "Clear";
        if (codice === 1) return it ? "Quasi sereno" : "Mainly clear";
        if (codice === 2) return it ? "Poco nuvoloso" : "Partly cloudy";
        if (codice === 3) return it ? "Nuvoloso" : "Overcast";
        if (codice === 45 || codice === 48) return it ? "Nebbia" : "Fog";
        if (codice >= 95) return it ? "Temporale" : "Thunderstorm";
        if ((codice >= 71 && codice <= 77) || codice === 85 || codice === 86)
            return it ? "Neve" : "Snow";
        if (codice === 65 || codice === 82)
            return it ? "Pioggia forte" : "Heavy rain";
        if (codice >= 61) return it ? "Pioggia" : "Rain";
        if (codice >= 51) return it ? "Pioviggine" : "Drizzle";
        return it ? "Nuvoloso" : "Cloudy";
    }

    function gradi(v) {
        return (v === undefined || v === null) ? "—" : Math.round(v) + "°";
    }

    function aggiorna(forza) {
        if (!meteo.attivo)
            return;
        Core.Ipc.weatherState(meteo.lat, meteo.lon, forza === true);
    }

    readonly property var _ascolto: Connections {
        target: Core.Ipc
        function onWeatherReceived(m) {
            if (m.spento === true) {
                meteo.adesso = null;
                meteo.giorni = [];
                meteo.ore = [];
                return;
            }
            if (m.adesso !== undefined) meteo.adesso = m.adesso;
            if (m.giorni !== undefined) meteo.giorni = m.giorni;
            if (m.ore !== undefined) meteo.ore = m.ore;
            meteo.vecchio = m.vecchio === true;
        }
        function onConnectedChanged() { if (Core.Ipc.connected) meteo.aggiorna(); }
    }

    // Un quarto d'ora, che è anche il passo con cui open-meteo aggiorna i suoi
    // dati: chiedere più spesso non darebbe un numero diverso, darebbe solo
    // traffico e una radio che si sveglia per niente.
    readonly property var _ronda: Timer {
        interval: 15 * 60 * 1000
        repeat: true
        running: meteo.attivo
        triggeredOnStart: true
        onTriggered: meteo.aggiorna()
    }

    // Cambiando località non si aspetta il prossimo giro: si mostrerebbe per
    // un quarto d'ora il tempo del posto di prima.
    readonly property var _cambioLuogo: Connections {
        target: meteo
        function onLuogoChanged() { meteo.aggiorna(true); }
    }
}

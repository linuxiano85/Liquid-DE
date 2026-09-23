import QtQuick
import "../../theme" as Theme

// Aurora — Lo sfondo vivo della schermata di accesso.
//
// Tre correnti di luce che si spostano lentamente su un fondo scuro. Non è
// un'immagine e non è un video: è calcolato dalla scheda grafica un
// fotogramma alla volta, quindi non pesa niente sul disco, non si ripete mai
// uguale, e si adatta a qualunque risoluzione senza sgranarsi.
//
// ── Perché uno shader e non delle forme animate ────────────────────────────
//
// La stessa cosa si può fare in QML con dei cerchi sfocati che si muovono. Ma
// sfocare un oggetto grande quanto lo schermo a ogni fotogramma costa molto
// più che calcolarne il colore: la sfocatura legge e riscrive tutti i pixel
// più volte, lo shader li scrive una volta sola. Su una schermata che resta
// aperta a batteria, la differenza non è accademica.
//
// ── Perché i periodi sono numeri strani ────────────────────────────────────
//
// 0.081, 0.063, 0.047… Se i tre movimenti avessero periodi in rapporto
// semplice, tornerebbero insieme al punto di partenza a intervalli regolari e
// l'occhio riconoscerebbe il ciclo. Uno sfondo che si vede ripetere smette di
// essere vivo e diventa una GIF.
//
// ── I colori ───────────────────────────────────────────────────────────────
//
// Vengono dal tema. Cambiando accento cambia l'aurora, senza toccare niente
// qui: è la stessa regola del resto di Minerva — un tema è una tinta e un
// verso, e le cose che lo seguono devono seguirlo tutte.
ShaderEffect {
    id: aurora

    /// Quanto le correnti sono accese. Sotto, resta quasi nero.
    property real forza: 0.55

    /// Fermo, disegna un fotogramma solo. Serve quando la schermata non è in
    /// primo piano: un'animazione che nessuno guarda è consumo e basta.
    property bool vivo: true

    property color tinta1: Theme.Colors.accent
    property color tinta2: Theme.Colors.accentAlt
    property color tinta3: Theme.Colors.accentWarm
    property color fondo: Theme.Colors.base

    // ── Le uniformi che lo shader legge ──────────────────────────────────
    //
    // I nomi devono combaciare con quelli del blocco `buf` nei due sorgenti:
    // Qt le collega per nome, e una che non combacia non dà errore — resta
    // semplicemente a zero, e si scopre guardando uno schermo nero.

    property vector2d misura: Qt.vector2d(aurora.width, aurora.height)
    property real tempo: 0

    NumberAnimation on tempo {
        running: aurora.vivo && aurora.visible
        from: 0
        // Non `Infinite` su un valore che cresce senza fine: dopo ore i
        // numeri diventano grandi abbastanza da far perdere precisione al
        // seno, e il movimento comincia a scattare. 3600 secondi di corsa e
        // poi si ricomincia — e siccome i seni sono periodici, il salto non
        // si vede.
        to: 3600
        duration: 3600 * 1000
        loops: Animation.Infinite
    }

    vertexShader: Qt.resolvedUrl("aurora.vert.qsb")
    fragmentShader: Qt.resolvedUrl("aurora.frag.qsb")
}

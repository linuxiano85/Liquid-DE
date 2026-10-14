// I colori del preset Windows: gettoni veri e sfumature dell'accento.
//
//     node --test tests/windows11-colori.test.mjs
//
// Carica i file VERI della shell (`windows11/ColorMath.js`, `Gettoni.js`)
// e prova, per i 48 accenti della griglia di Windows 11 e per 200 colori
// manuali a caso, le regole che `windows11/Style.qml` dà per scontate.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const radice = fileURLToPath(new URL("../minerva-shell/windows11/", import.meta.url));

function carica(nome, extra = {}) {
    const ambiente = { Math, String, parseInt, Object, Array, ...extra };
    vm.createContext(ambiente);
    // `.pragma` e `.import` sono di QML: qui le librerie si passano a mano.
    const sorgente = readFileSync(radice + nome, "utf8")
        .replace(/^\.pragma library/m, "")
        .replace(/^\.import .*$/gm, "");
    vm.runInContext(sorgente, ambiente);
    return ambiente;
}

const cm = carica("ColorMath.js");
const g = carica("Gettoni.js", { ColorMath: cm });

// La griglia dei colori d'accento di Windows 11 (Impostazioni ›
// Personalizzazione › Colori), nell'ordine in cui la si vede.
const griglia = [
    "#FFB900", "#FF8C00", "#F7630C", "#CA5010", "#DA3B01", "#EF6950", "#D13438", "#FF4343",
    "#E74856", "#E81123", "#EA005E", "#C30052", "#E3008C", "#BF0077", "#C239B3", "#9A0089",
    "#0078D4", "#0063B1", "#8E8CD8", "#6B69D6", "#8764B8", "#744DA9", "#B146C2", "#881798",
    "#0099BC", "#2D7D9A", "#00B7C3", "#038387", "#00B294", "#018574", "#00CC6A", "#10893E",
    "#7A7574", "#5D5A58", "#68768A", "#515C6B", "#567C73", "#486860", "#498205", "#107C10",
    "#767676", "#4C4A48", "#69797E", "#4A5459", "#647C64", "#525E54", "#847545", "#7E735F"
];

function aCaso(quanti) {
    let seme = 0x4d696e65;
    const out = [];
    for (let i = 0; i < quanti; i++) {
        seme = (seme * 1664525 + 1013904223) >>> 0;
        out.push("#" + (seme & 0xffffff).toString(16).padStart(6, "0"));
    }
    return out;
}
const tutti = griglia.concat(aCaso(200));
const ordine = ["light3", "light2", "light1", "dark1", "dark2", "dark3"];

test("l'azzurro di serie riproduce la luminosità della tavolozza di Windows", () => {
    const p = cm.palette(g.azzurroDiSerie.accento);
    for (const nome of ordine) {
        const scarto = Math.abs(cm.oklch(p[nome]).l - cm.oklch(g.azzurroDiSerie[nome]).l);
        assert.ok(scarto < 0.005, `${nome}: ${p[nome]} contro ${g.azzurroDiSerie[nome]} (${scarto})`);
    }
});

test("le sei sfumature sono colori validi e in ordine di luminosità, per ogni accento", () => {
    for (const accento of tutti) {
        const p = cm.palette(accento);
        let prima = Infinity;
        for (const nome of ordine) {
            assert.match(p[nome], /^#[0-9a-f]{6}$/, `${accento} ${nome}`);
            const l = cm.oklch(p[nome]).l;
            assert.ok(l < prima, `${accento}: ${nome} non è più scura della precedente`);
            prima = l;
        }
    }
});

for (const [tema, scuro] of [["scuro", true], ["chiaro", false]]) {
    const gettoni = scuro ? g.scuro : g.chiaro;
    const ricette = scuro ? g.acrylic.scuro : g.acrylic.chiaro;
    const superficie = ricette["default"].ripiego;

    test(`${tema}: testo e testo secondario si leggono sui flyout`, () => {
        assert.ok(cm.contrast(cm.over(gettoni.textPrimary, superficie), superficie) >= 7);
        assert.ok(cm.contrast(cm.over(gettoni.textSecondary, superficie), superficie) >= 4.5);
    });

    test(`${tema}: per ogni accento il riempimento si distingue e il testo sopra si legge`, () => {
        for (const accento of tutti) {
            const p = cm.palette(accento);
            const riempimento = scuro ? p.light2 : p.dark1;
            const voluto = gettoni.textOnAccent.replace(/^#FF/, "#");
            const testo = cm.contrast(voluto, riempimento) >= 4.5 ? voluto : cm.foreground(riempimento);
            assert.ok(cm.contrast(testo, riempimento) >= 4.5, `${accento}: testo su ${riempimento}`);
            const leggibile = cm.readable(riempimento, superficie, 3);
            assert.ok(cm.contrast(leggibile, superficie) >= 3, `${accento}: indicatore su ${superficie}`);
        }
    });
}

test("accento su Start e barra: c'è sempre una sfumatura scura col testo bianco leggibile", () => {
    for (const accento of tutti) {
        const p = cm.palette(accento);
        const usata = ["dark1", "dark2", "dark3"].find((n) => cm.contrast("#ffffff", p[n]) >= 4.5);
        assert.ok(usata, `${accento}: nessuna sfumatura scura regge il testo bianco (${p.dark3})`);
    }
});

test("i gettoni trasparenti restano trasparenti: le schede lasciano vedere il vetro", () => {
    for (const gettoni of [g.scuro, g.chiaro]) {
        for (const nome of ["cardBackground", "subtleSecondary", "subtleTertiary", "cardStroke"]) {
            const a = cm.alpha(gettoni[nome]);
            assert.ok(a > 0 && a < 1, `${nome}: alfa ${a}`);
        }
    }
});

test("la ricetta del vetro: i gettoni dei flyout, o la sfumatura scura leggibile dell'accento", () => {
    const chiaro = g.ricettaVetro(false, false, "#0078D4");
    assert.equal(chiaro.tinta, "#FCFCFC");
    assert.equal(chiaro.luminositaOpacita, 0.85);
    const scuro = g.ricettaVetro(true, false, "#0078D4");
    assert.equal(scuro.tinta, "#2C2C2C");
    assert.equal(scuro.tintaOpacita, 0.15);
    for (const accento of tutti) {
        const r = g.ricettaVetro(true, true, accento);
        assert.ok(cm.contrast("#ffffff", r.tinta) >= 4.5 || r.tinta === cm.palette(accento).dark3, accento);
        assert.equal(r.luminositaOpacita, 0.8);
    }
});

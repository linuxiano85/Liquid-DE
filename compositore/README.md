# Minerva Wayland

Compositore Wayland di Liquid DE, basato sul fork wlroots incluso in
`subprojects/wlroots`. Gestisce finestre, input, schermi, desktop virtuali,
tiling, decorazioni ed effetti della sessione.

## Compilazione

Dalla radice del progetto:

```sh
./compositore/costruisci.sh --build-only
```

Il risultato è `compositore/build-native/minerva-wayland`. Le dipendenze
vengono controllate dall'installer; la configurazione è in `meson.build`.
La compilazione predefinita usa il processore locale. Per una destinazione
diversa, impostare `MINERVA_MARCH` sul target supportato dal compilatore.

Le prove e i rapporti di sviluppo sono conservati separatamente in Liquid_test.
Non avviare un secondo compositore sulla sessione grafica in uso.

## Provenienza

Le modifiche a wlroots sono documentate in `subprojects/wlroots/MINERVA.md`.
Le licenze delle dipendenze rimangono nei rispettivi sorgenti.

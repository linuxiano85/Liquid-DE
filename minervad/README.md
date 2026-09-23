# minervad — il demone di Minerva

Il programma che risponde. Non ha finestre, non ha interfaccia: sta in ascolto
su un socket Unix in `$XDG_RUNTIME_DIR/minerva/` e risponde a chi chiede, in
JSON, un messaggio per riga.

Tutto quello che l'interfaccia non può sapere da sola passa da qui: lo stato
del sistema (batteria, rete, audio, Bluetooth, luminosità), i processi in
esecuzione, le impostazioni, gli archivi, le icone dei temi di sistema, la
scansione delle applicazioni installate e il dialogo con `greetd` per la
schermata di accesso.

L'elenco completo delle azioni sta in [`../EVENTS.md`](../EVENTS.md).

## Nessuna dipendenza esterna

Guardando `pubspec.yaml` si nota che sotto `dependencies:` non c'è niente: solo
`lints` e `test`, che servono a chi sviluppa e non finiscono nel binario. È
voluto. Il demone parla D-Bus, legge `/proc`, apre socket e analizza JSON con
la sola libreria standard di Dart — così l'unica cosa che serve per compilarlo
è l'SDK, e non c'è nessun pacchetto di terze parti che un domani possa
cambiare sotto i piedi.

## Come si compila

Dalla radice del progetto:

```bash
./scripts/minerva-compila
```

Compila in `build/minervad`, un eseguibile nativo di circa 8,6 MB. Lo script
compila in un file a parte e lo sposta solo a compilazione riuscita: se
qualcosa va storto, il binario che sta girando resta quello di prima.

Per usarlo subito, senza uscire dalla sessione:

```bash
./scripts/minerva-reload.sh tutto
```

## Come si prova

```bash
dart analyze     # deve dire «No issues found!»
dart test        # 383 prove
```

Fra queste ce n'è una che non prova il comportamento ma **il testo del
codice**: `test/minerva_paths_test.dart` legge ogni file di `lib/` e fallisce
se trova un percorso assoluto scritto a mano. È la prova più stupida di tutte
e la più utile — un difetto che si reintroduce scrivendo una riga si previene
solo leggendo le righe.

## Com'è fatto dentro

| Cartella | Cosa contiene |
|---|---|
| `bin/` | i due punti d'ingresso: il demone e lo strumento delle scorciatoie |
| `lib/core/` | il bus, lo stato condiviso, i percorsi, le impostazioni |
| `lib/services/` | un file per servizio: audio, rete, file, processi, accesso… |
| `test/` | le prove, una per servizio |

La regola dei confini — quando una cosa è un modulo e quando è solo
un'abitudine sparsa — sta in [`../MODULI.md`](../MODULI.md).

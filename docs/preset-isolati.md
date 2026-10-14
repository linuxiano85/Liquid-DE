# Preferenze separate per preset

In **Impostazioni → Aspetto**, scegli Liquid, Minerva, Mac, Windows 11 o
Libero, poi personalizza la scrivania. Tornando a quel preset ritrovi le sue
ultime preferenze, anche dopo un riavvio. Un preset non viene rimesso ai
valori di fabbrica quando lo selezioni di nuovo.

Per esempio, puoi attivare l'acquerello in Liquid e usare finestre opache
in Windows. Se lo attivi anche in Windows, entrambi lo conserveranno.
Lo stesso vale per gli angoli attivi e le altre preferenze della scrivania.

| Separate per preset | Comuni alla sessione e al sistema |
|---|---|
| Effetti, colori, icone, sfondo, animazioni, barra, dock, menu, widget | Rete, audio, luminosità, luce notturna, controller e dispositivi di input |
| Tiling, regole delle finestre, angoli attivi, scorciatoie disabilitate | Lingua, località meteo, applicazioni predefinite, credenziali e sicurezza |
| Dimensione del testo e del puntatore, preferenze visive delle app Liquid, disposizione delle icone | File, documenti aperti, finestre in esecuzione, zoom dello schermo e stato delle notifiche |

## Compatibilità

L'aggiornamento conserva le impostazioni del preset attivo e recupera la
vecchia fotografia di Libero. Liquid recupera le preferenze visive che prima
erano condivise. Gli altri preset partono dai propri valori iniziali, perché
le versioni precedenti non ne registravano le personalizzazioni.

## Implementazione e verifica

`SettingsApi` salva le preferenze in `stile.profili` nel file delle impostazioni.
Le applicazioni continuano a leggere le chiavi consuete del preset attivo.
Il cambio salva quello precedente e ripristina quello scelto con una sola
scrittura atomica e un solo evento. Se la scrittura fallisce, entrambi restano
intatti. I dati di un preset non possono modificare le impostazioni comuni.

```sh
dart run tests/desktop_profiles_probe.dart
python3 tests/prova_windows11.py
```

La prima prova usa il gestore reale su file temporanei. La seconda usa
un compositore privato e input reali nell'interfaccia, senza inviarli alla
sessione dell'utente. Coprono il ritorno tra preset, riavvii, migrazione,
impostazioni danneggiate, modifiche concorrenti e mancati salvataggi.

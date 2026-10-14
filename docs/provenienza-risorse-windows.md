# Provenienza delle risorse del preset Windows

Verifica del 12 ottobre 2026. Questo inventario descrive le risorse controllate;
non costituisce una valutazione legale dell'interfaccia complessiva.

| Risorsa | Provenienza e licenza | Stato |
| --- | --- | --- |
| Fluent System Icons | Microsoft, MIT | Provenienza, commit e licenza conservati in `minerva-shell/windows11/fluent-SOURCE.md` e `fluent-LICENSE.txt`. |
| Selawik | Microsoft, SIL OFL 1.1 | Provenienza e licenza in `minerva-shell/windows11/fonts/`. Conservare gli avvisi e rispettare il nome riservato in caso di modifica. |
| Marchio Liquid | Disegni realizzati per Liquid | Inventario in `assets/marchio/liquid/README.md`; la scritta usa Selawik. L'originalità dichiarata non equivale a una ricerca di anteriorità sui marchi. |
| Icone del gestore file | Disegni realizzati per Liquid, GPL-3.0-or-later | Licenza in `minerva-shell/files/artwork/LICENSE.md`. |
| Sfondi Bloom | Microsoft / Six N. Five | Non è stata individuata una licenza di ridistribuzione. I JPG sono ignorati da Git; il solo file SOURCE.md è tracciato. |

## Limiti della verifica

L'esclusione da Git non impedisce ogni altra copia: attualmente
`scripts/minerva-installa-radice` include tutta `minerva-shell`, e
`scripts/minerva-greetd` la copia con rsync o cp. Se i JPG Bloom sono presenti
nel checkout locale, questi percorsi possono copiarli nell'installazione.
Non usare tale albero locale per produrre un archivio pubblico senza verificare
ed escludere le risorse prive di autorizzazione.

Controllato da Claude il 12 ottobre: nessuno script del progetto produce un
pacchetto o un archivio; le due copie installano solo sul computer di chi ha
il checkout, e il progetto si distribuisce con Git, che i JPG li ignora.
Per questo gli script non li escludono: toglierli lì cancellerebbe lo sfondo
a chi li ha. Chi un giorno scriverà uno script di pacchetto dovrà escludere
`minerva-shell/windows11/wallpapers/*.jpg`. Non è stata verificata ogni
possibile procedura di distribuzione o ogni tema installato dall'utente.

Il codice implementato indipendentemente e le licenze delle singole risorse
non risolvono la questione della riproduzione visiva complessiva. La sentenza
[CGUE C-393/09](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX%3A62009CJ0393)
riconosce che un'interfaccia grafica può essere protetta come opera originale.
Le [linee guida sui marchi Microsoft](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks)
disciplinano separatamente marchi e risorse del brand. Le licenze MIT e OFL
dei progetti citati non autorizzano una presentazione come prodotto Microsoft.

Non è stata svolta una verifica legale di copyright, disegni/modelli o marchi
sull'interfaccia completa. Prima di distribuire e promuovere una replica
indistinguibile occorre una valutazione specifica. L'alternativa raccomandata
è conservare un'organizzazione familiare con identità e sfondi Liquid.

# Temi: ripristino dello sfondo — 20 ottobre 2026

Corretto un errore di Salva tema: uno sfondo a tinta unita veniva riapplicato come immagine, perdendo il colore scelto.

I nuovi temi conservano modalità dello sfondo, immagine o cartella, tinta unita, adattamento, intervallo e casualità della rotazione, scelta dello sfondo automatico e modalità separata delle applicazioni. L’anteprima dei temi a tinta unita usa il colore salvato.

I temi precedenti rimangono leggibili con il comportamento originale. Non vengono rimossi né convertiti automaticamente.

Il demone verifica le preferenze incluse nei nuovi temi: soltanto le chiavi previste, con tipi e valori validi. Una richiesta non valida viene rifiutata senza sostituire i temi già salvati. I nomi dei temi di serie usano il marchio Liquid anche nella traduzione inglese.

## Verifiche

Prove GUI con salvataggio, modifica di tutte le preferenze e ripristino tramite tastiera su cinque configurazioni: tinta, immagine, cartella, raccolta Liquid e sfondo automatico. Controllo dei pixel dell’anteprima a tinta unita e compatibilità con il vecchio formato. Verifiche separate del demone per valori malformati, persistenza e isolamento dei preset.

Il binario del demone compilato è stato avviato e arrestato in un ambiente isolato, con filesystem host in sola lettura, rete e bus separati: sessione, greeter, diagnostica disattivata e file delle impostazioni corrotto. Queste prove non sostituiscono un login su hardware reale e non certificano l’intera pagina Temi.

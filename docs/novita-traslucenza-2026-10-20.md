# Traslucenza della barra — 20 ottobre 2026

Corretto un doppio disegno dello sfondo nella barra del preset Familiare. Quando il compositore applica il materiale Acrylic nativo, la barra non carica più anche l’immagine memorizzata dal vecchio filtro.

La stessa immagine viene esclusa quando gli effetti di trasparenza sono disattivati o entra in funzione il risparmio energetico. Il percorso di compatibilità per i compositori che confermano soltanto il blur rimane disponibile.

La correzione riguarda il disegno della barra. Non modifica le preferenze salvate, le scorciatoie o la ricetta del materiale del compositore.

## Verifica

Il difetto è stato riprodotto con un compositore Wayland isolato, renderer GLES2, sfondi controllati e confronto dei pixel: un’immagine memorizzata diversa alterava la barra anche con lo sfondo reale invariato. Le prove coprono tema chiaro e scuro, sfondo reale, vecchia immagine memorizzata, trasparenza disattivata e risparmio energetico forzato nel compositore di prova.

Questa verifica non certifica l’intera corrispondenza visiva con il riferimento né tutte le combinazioni di GPU, driver e schermi.

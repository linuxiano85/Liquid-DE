# Piano di eliminazione dei difetti della Shell

Perimetro: Shell, login, blocco, autorizzazioni e Impostazioni. Le app autonome
sono escluse. Nessuna nuova funzione; correzioni a sicurezza e comportamento
esistente. Stato riferito alla PR in bozza #2, non al branch principale.

Ogni pezzo segue lo stesso percorso: verificare il flusso completo, riprodurre
il difetto con dati innocui, applicare una patch circoscritta, aggiungere una
regressione sul codice reale e registrare prove e limiti. Un test simulato non
chiude una verifica nativa. Le correzioni restano sul ramo della PR fino alla
validazione e all'approvazione del merge.

| Pezzo | Rilievi | Criterio per chiuderlo | Stato |
|---|---|---|---|
| 0. Prima serie | R-04/05/06/07/08/10, parte R-26, R-33/34, orari luce notturna | Suite JS, argv senza segreto, limiti notifiche; poi prove native | 22 test locali e CI passati; prove native aperte |
| 1. Confine root/login | R-01 | Symlink/hardlink e corse sui file non modificano bersagli esterni; letture come chiamante, scritture come greeter; snapshot di autorizzazione separato | Patch e CI passate; integrazione nativa aperta |
| 2. Launcher desktop | R-02 | Conferma monouso legata a client, percorso canonico e contenuto; modifica, annullamento, scadenza e replay bloccati | Patch e CI passate; dialogo nativo da provare |
| 3. Segreti Wi-Fi | R-03 | Credenziale assente da argv, diagnostica e coda; input nmcli e cancellazione del client verificati | Patch e CI passate (89 test); NetworkManager/radio nativi da provare |
| 4. Autenticazione e IPC | R-12/15/17/18/19 | Nessun replay di credenziali, buffer pulito, cancellazione e conversazioni multiple corrette | 4a: login offline e socket obsoleti corretti, CI in verifica; resto aperto |
| 5. Impostazioni e comandi | R-13/14/24/27 | Schema, risposta di salvataggio, coda/timeout e rollback verificati | Da correggere |
| 6. Notifiche residue | R-09/11 | Replacement, close, timeout e transient conformi; nessuna azione obsoleta | Da correggere |
| 7. Bluetooth | R-20/21/22/23 | Messaggi strutturati, PIN e annullamento; successo soltanto dopo connessione reale | Da correggere |
| 8. Profili e integrazioni | R-16/25/26/28/29/30/31 | NSS, workspace visibili, ripristino, account distinti, HTTP limitato e desktop entry corretti | Da correggere |
| 9. Accessibilità e stabilità | R-32 e matrice nativa | Tastiera, focus, login/lock, monitor e prestazioni misurate sulla macchina Linux | Da verificare |

Per R-05 restano fuori dalla patch SSID con newline o byte arbitrari. R-26 non
è chiuso per crash, cambi energetici concorrenti e reingresso rapido. R-06
richiede misure sul server DBus vero. Non sommare il numero di test al numero
di bug risolti.

Il pezzo 1 aggiunge un modulo Python installato con il helper della login.
Root non legge le impostazioni della sessione né lo sfondo; un figlio perde
permanentemente UID/GID root prima di aprirli. Un altro figlio scrive i dati
runtime come greeter. I dati usati per generare la configurazione di greetd
sono conservati in uno snapshot root-only, mai riletti dalla directory del
greeter. Il vecchio snapshot runtime non viene usato per migrare l'autologin:
dopo aggiornamento eseguire `sudo minerva-greetd configura` dalla sessione
dell'utente prima di attivare il gestore. Python 3 è ora obbligatorio per la
configurazione sicura della login.

Per i comandi e i controlli di integrazione consultare
`tests/README-shell-regressions.md`. Gli esiti dei nuovi test di permessi devono
essere registrati prima di dichiarare completato il pezzo 1.

Il pezzo 2 chiede consenso a ogni apertura da percorso `.desktop`, senza
memorizzare fiducia permanente né cambiare i permessi del file. Il dialogo
condiviso IPC mostra il percorso risolto e il comando effettivo come testo
semplice, rendendo visibili i caratteri di controllo/bidi. Il servizio verifica
il contenuto approvato e lancia la copia già mostrata. I messaggi del consenso
non passano nella coda offline. `launch_app` per le voci installate del menu è
un percorso distinto, non modificato da questa correzione. Non è una sandbox
contro processi dello stesso UID, che possono già avviare programmi.

Il pezzo 3 sostituisce Core.Exec con un processo dedicato per la connessione
Wi-Fi. La password non compare in argv, ambiente, ultimo comando o coda.
`nmcli --ask` la riceve una volta su stdin, solo dopo un prompt Wi-Fi noto;
la copia pendente è rimossa dopo invio/errore/timeout/chiusura della pagina.
Non conservare output grezzo nei messaggi di errore. Le password con tasti di
controllo vengono rifiutate perché readline li interpreta come operazioni di
editing. Il prefisso Ctrl-U elimina il valore eventualmente precompilato dal
SecretAgent di nmcli. Rivelazione solo mentre premuto; Annulla/Esc svuotano il
campo. Terminare nmcli interrompe il client locale, non garantisce il rollback
di un'attivazione già consegnata a NetworkManager.

La CI prova il vero nmcli/readline/SecretAgent con NetworkManager simulato su
un bus privato, senza avviare un servizio di rete reale. Restano native le
prove di associazione/DHCP, credenziale errata, profili salvati, radio e QML.
La pagina mantiene il supporto esistente per PSK/WEP; configurazione completa
802.1X con identità/certificati resta fuori da questa correzione.

Per sostituire la password di un profilo salvato, il pezzo 3 confronta l'SSID
letterale e attiva il relativo UUID con `connection up --ask`. Non confonde
il nome del profilo con quello della rete. Le query sono di sola lettura e
non ricevono segreti; UUID non validi, errori e risposte tardive bloccano
l'avvio. Il test del SecretAgent segue questo percorso anche con nmcli 1.46.

Il pezzo 4a impedisce l'accodamento dei messaggi greeter di autenticazione,
compresi creazione, risposta, avvio e annullamento; greeter_info resta una
lettura iniziale accodabile. Anche lo svuotamento elimina eventuali vecchie
voci della login. I callback dei socket sostituiti non modificano il canale
corrente. La perdita del canale pulisce campo e stato del greeter, ferma i
retry automatici e richiede un nuovo tentativo esplicito. Un invio rifiutato
non lascia la schermata in attesa. I messaggi tardivi vengono ignorati fino
al nuovo tentativo.

R-12 NON è interamente chiuso: la coda delle altre azioni (account, pairing,
impostazioni e operazioni) deve ancora essere classificata. Restano aperti
correlazione delle risposte greetd, proprietà della conversazione fra client
e passaggi concorrenti sul demone. I test JS non provano PAM né caricano Qt.

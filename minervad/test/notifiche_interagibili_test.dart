import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Le notifiche devono poter essere cliccate.
///
/// ── Il difetto, ed era peggio di come è stato segnalato ───────────────────
///
/// Giacomo, 2 settembre 2026: «le notifiche quando compaiono devono essere
/// interagibili, ad esempio se scatto uno screenshot e compare la notifica e
/// ci clicco devo poter vedere l'immagine con anteprima o un altro
/// visualizzatore impostato come predefinito e questo per tutte le notifiche».
///
/// Guardando il codice è saltato fuori che non era solo «manca il clic»:
/// `core/Notifications.qml` dichiarava ai programmi `actionsSupported: true`
/// — quindi le azioni ce le mandavano **davvero** — e poi il gestore
/// `onNotification` copiava sette campi in una mappa e buttava via l'oggetto,
/// azioni comprese. Un istante dopo non c'era più niente da invocare.
///
/// Prometteva e non manteneva, ed è la forma di difetto che questo progetto
/// insegue da mesi: nessun errore da nessuna parte, il clic semplicemente non
/// fa niente.
///
/// ── Perché queste prove guardano il TESTO ────────────────────────────────
///
/// Perché il pezzo che conta non si può eseguire senza un bus D-Bus, un
/// programma che manda una notifica e uno schermo su cui cliccare. Quello che
/// si può sorvegliare è che le tre righe da cui tutto dipende non spariscano:
/// se `tracked` se ne va, le azioni tornano a morire — e il difetto torna
/// **identico**, in silenzio.
File _trova(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

void main() {
  group('una notifica si può cliccare', () {
    final notif =
        _trova('minerva-shell/core/Notifications.qml').codiceVivo();
    final toast = _trova('minerva-shell/spine/Toasts.qml').codiceVivo();
    final pannello =
        _trova('minerva-shell/spine/panels/NotificationsPanel.qml')
            .codiceVivo();

    test('la notifica si tiene viva, o le azioni muoiono con lei', () {
      expect(notif, contains('notif.tracked = true'),
          reason: 'senza `tracked`, Quickshell considera la notifica finita '
              'appena il gestore ritorna: l\'oggetto muore e con lui '
              '`invoke()`. Il clic torna a non fare niente, e nessun errore '
              'lo dice.');
    });

    test('e si tiene l\'oggetto, non solo una copia del testo', () {
      expect(notif, contains('"notif": notif'),
          reason: 'le azioni sono oggetti con un metodo: una copia in una '
              'lista nostra perderebbe proprio quello');
      expect(notif, contains('"azioni": notif.actions'));
    });

    test('quello che dichiariamo di sapere fare, lo sappiamo fare', () {
      // Dichiarare `actionsSupported` e poi buttare le azioni è la parte
      // peggiore del difetto: i programmi si comportano di conseguenza.
      expect(notif, contains('actionsSupported: true'));
      expect(notif, contains('function apri('),
          reason: 'se si dichiara di accettare le azioni, ci deve essere chi '
              'le invoca');
    });

    test('prima l\'azione del programma, poi il nostro file', () {
      // L'ordine non è arbitrario: un lettore musicale che manda «apri
      // l'album» sa meglio di noi cosa vuol dire cliccare la sua notifica.
      final i = notif.indexOf('"default"');
      final j = notif.indexOf('openDefault');
      expect(i, greaterThan(0), reason: 'manca il caso dell\'azione «default»');
      expect(j, greaterThan(0), reason: 'manca l\'apertura del file');
      expect(i, lessThan(j),
          reason: 'il file si apre solo se il programma non ha detto lui cosa '
              'fare');
    });

    test('il file si legge da un SUGGERIMENTO, non dal testo', () {
      // Un percorso dentro una frase è una cosa che si somiglia, non una cosa
      // che è: aprire il file sbagliato perché il corpo conteneva una barra
      // sarebbe peggio che non aprire niente.
      expect(notif, contains('x-minerva-file'));
      expect(notif, contains('notif.hints'));
    });

    test('e chi manda quel suggerimento esiste davvero', () {
      // Una chiave che nessuno scrive è una funzione che non si accende mai.
      final schermata = _trova('scripts/minerva-schermata').codiceVivo();
      expect(schermata, contains('string:x-minerva-file:'),
          reason: 'la schermata è il primo caso che Giacomo ha nominato: se '
              'non mette il suggerimento, cliccare la sua notifica non apre '
              'niente');
    });

    test('cliccano tutti e due: l\'avviso e il pannello', () {
      // «e questo per tutte le notifiche»: non solo l'avviso che compare e
      // sparisce, ma anche l'elenco, dove si va a ripescare quella di prima.
      expect(toast, contains('Core.Notifications.apriPerId('));
      expect(pannello, contains('Core.Notifications.apri('));
    });

    test('e il puntatore non promette un clic che non fa niente', () {
      // Una mano a dito su una notifica inerte è dire il falso col puntatore.
      expect(notif, contains('function siPuoAprire('));
      expect(toast, contains('toast.apribile ? Qt.PointingHandCursor'));
      expect(pannello, contains('note.apribile ? Qt.PointingHandCursor'));
    });

    test('la X del pannello continua a chiudere', () {
      // L'area del clic riempie tutta la riga ed è dichiarata DOPO il pulsante
      // di chiusura: senza `z: -1` gli starebbe sopra e gli ruberebbe il clic.
      // La X smetterebbe di funzionare, e nessun errore lo direbbe.
      final i = pannello.indexOf('id: closeMouse');
      final j = pannello.indexOf('id: noteMouse');
      expect(i, greaterThan(0));
      expect(j, greaterThan(i),
          reason: 'se un giorno l\'ordine si inverte questa prova va rifatta, '
              'non cancellata');
      expect(pannello.substring(j - 200, j + 200), contains('z: -1'),
          reason: 'senza, la riga cliccabile copre il pulsante di chiusura');
    });
  });
}

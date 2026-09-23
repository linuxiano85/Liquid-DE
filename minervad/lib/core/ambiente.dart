import '../ipc/canale_segreto.dart';

/// Chi è questo demone.
///
/// Ce n'è di due specie, e fanno lo stesso mestiere in due mondi diversi:
///
///  · quello di una **sessione**, che serve la scrivania di una persona che è
///    già entrata: dock, menu, impostazioni, finestre;
///  · quello della **schermata di accesso**, che gira come utente `greeter`
///    prima che qualcuno sia entrato, vive dieci secondi, e ha un solo
///    interlocutore — `greeter.qml`, che gli chiede chi può entrare e in cosa.
///
/// Il secondo faceva anche tutto il lavoro del primo, perché non aveva modo di
/// sapere di essere il secondo. Questa classe è quel modo.
///
/// ── Perché il segno è il nome della sessione ───────────────────────────────
///
/// Perché c'è già, ed è uno solo. La configurazione del greeter imposta
/// `MINERVA_SESSIONE=greeter` (vedi `scripts/minerva-greetd`), e da quel nome
/// discendono la cartella del canale e quella dei registri: il demone del
/// greeter è **già** l'unico che si chiama così.
///
/// Aggiungere una seconda variabile — `MINERVA_GREETER=1` — vorrebbe dire due
/// segni per un fatto solo, che possono smentirsi a vicenda: una configurazione
/// che ne imposta uno e dimentica l'altro dà un demone che scrive nella
/// cartella del greeter credendosi una sessione, e nessun errore da nessuna
/// parte.
class Ambiente {
  Ambiente._();

  /// Il nome che la schermata di accesso si dà.
  static const String sessioneGreeter = 'greeter';

  /// Vero se questo demone è quello della schermata di accesso.
  static bool get eGreeter => eNomeDelGreeter(CanaleSegreto.sessione());

  /// La regola, staccata da dove si legge il nome: quella qui sopra dipende
  /// dall'ambiente del processo e in una prova non si può cambiare, questa sì.
  static bool eNomeDelGreeter(String nomeSessione) =>
      nomeSessione == sessioneGreeter;
}

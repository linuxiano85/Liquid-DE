import 'dart:async';

/// Tiene da parte per un po' la risposta a una domanda che costa.
///
/// ── Perché esiste ──────────────────────────────────────────────────────────
///
/// Tre risposte del demone si ricalcolavano da capo a ogni richiesta, e nessuna
/// delle tre cambia mentre la sessione gira. Misurate sul demone vivo il 7
/// settembre 2026, cinque giri ciascuna:
///
///   font_list        28,8 ms   lancia `fc-list`
///   mime_categories  29,4 ms   ricostruisce le categorie e risolve le icone
///   fs_formats       23,0 ms   lancia CINQUE processi `busctl`
///
/// Per confronto, `get_state` risponde in 0,3 ms e `get_icon_themes` in 1,1.
///
/// ── E la seconda cosa, che conta quanto la prima ───────────────────────────
///
/// Le domande in corso si UNISCONO. Otto finestre di Minerva sono otto client
/// sullo stesso demone: se si aprono insieme e chiedono la stessa cosa, oggi il
/// lavoro si fa otto volte di fila — cinque `busctl` moltiplicati per otto — e
/// il demone ha un filo solo, quindi quelle otto volte sono in coda una dietro
/// l'altra. Con questo, la prima calcola e le altre sette aspettano lei.
///
/// ── Perché un tempo, e non «per sempre» ────────────────────────────────────
///
/// Perché le tre risposte dipendono da cosa c'è installato sul computer, e
/// installare un carattere o `ntfs-3g` mentre la sessione gira è raro ma
/// legittimo. «Per sempre» vorrebbe dire che chi lo fa deve riavviare la
/// sessione per vederlo, e non avrebbe modo di saperlo. Mezzo minuto è
/// indistinguibile da «sempre fresco» per chi guarda un pannello, e toglie il
/// costo a tutte le aperture tranne la prima.
///
/// ── Un errore non si ricorda ───────────────────────────────────────────────
///
/// Se il calcolo fallisce, il ricordo resta vuoto: un `busctl` che non risponde
/// una volta non deve far dire «non si può formattare niente» per i trenta
/// secondi successivi. Un guasto passeggero ricordato diventa un guasto lungo.
class RicordaUnPo<T> {
  RicordaUnPo(this.quanto);

  /// Per quanto vale il ricordo.
  final Duration quanto;

  T? _valore;
  DateTime? _quando;
  Future<T>? _inCorso;

  /// Quante volte si è risposto senza rifare il lavoro. Serve alle prove e a
  /// poter dire, con un numero, se è servito a qualcosa.
  int risparmiate = 0;

  /// La risposta: quella di prima se è ancora buona, altrimenti calcolata.
  Future<T> chiedi(Future<T> Function() calcola) {
    final ora = DateTime.now();
    final q = _quando;
    if (q != null && ora.difference(q) < quanto) {
      risparmiate++;
      return Future.value(_valore as T);
    }
    // Una domanda già in volo non se ne fa una seconda: la si aspetta.
    final volo = _inCorso;
    if (volo != null) {
      risparmiate++;
      return volo;
    }
    final mia = calcola().then((v) {
      _valore = v;
      _quando = DateTime.now();
      return v;
    }).whenComplete(() {
      _inCorso = null;
    });
    _inCorso = mia;
    return mia;
  }

  /// Dimentica: la prossima domanda rifà il lavoro. Da chiamare quando si sa
  /// che la risposta è cambiata, senza aspettare che scada.
  void dimentica() {
    _valore = null;
    _quando = null;
  }
}

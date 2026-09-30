import 'dart:typed_data';

/// TagliaRighe — Dove finisce un messaggio del canale, con un tetto.
///
/// ── Perché non basta più `LineSplitter` ────────────────────────────────────
///
/// `LineSplitter` tiene da parte tutto quello che arriva finché non vede un
/// a-capo, e non ha un limite. Provato il 30 settembre 2026 sul demone vivo:
/// un client che NON aveva ancora detto la parola d'ordine ha mandato 1,1 GB
/// senza un a-capo in quattro secondi e mezzo, e il demone è passato da 250 MB
/// a 2,6 GB. Il limite dei cinque secondi per salutare non serviva a niente:
/// in cinque secondi su un socket Unix ci passano gigabyte. Con due o tre
/// connessioni così arriva l'OOM killer — che sceglie lui chi uccidere.
///
/// Qui ogni riga ha un tetto, e il tetto lo decide chi chiama riga per riga:
/// strettissimo prima del saluto (un `ciao` sono cento byte), largo dopo (un
/// documento dell'editor viaggia dentro `fs_write`).
///
/// ── Perché si taglia sui BYTE e si decodifica dopo ─────────────────────────
///
/// L'a-capo in UTF-8 è il byte 0x0A e non compare mai dentro un carattere di
/// più byte, quindi tagliare sui byte è sicuro; e decodificando una riga
/// intera alla volta un carattere accentato spezzato fra due pezzi si
/// ricongiunge da sé, che era la ragione per cui prima c'era `utf8.decoder`
/// davanti al `LineSplitter`.
class TagliaRighe {
  final BytesBuilder _qui = BytesBuilder(copy: false);

  /// Vero mentre si sta buttando una riga troppo lunga, fino al suo a-capo.
  bool _scarta = false;

  /// Quante righe sono state buttate perché troppo lunghe, da sempre.
  int troppoLunghe = 0;

  /// Aggiunge un pezzo arrivato dal socket e consegna a [riga] ogni riga
  /// completa, in ordine.
  ///
  /// [massimo] si chiede di nuovo per ogni riga, e non una volta per pezzo:
  /// il saluto e il primo messaggio vero arrivano spesso nello stesso pezzo, e
  /// il secondo deve già avere il tetto largo di chi si è presentato.
  ///
  /// Una riga oltre il tetto non si consegna: si chiama [troppoLunga] una
  /// volta e si butta tutto fino al prossimo a-capo.
  void aggiungi(List<int> pezzo, int Function() massimo,
      void Function(Uint8List riga) riga, void Function() troppoLunga) {
    var inizio = 0;
    while (inizio <= pezzo.length) {
      final a = pezzo.indexOf(0x0A, inizio);
      final fine = a < 0 ? pezzo.length : a;
      if (!_scarta && fine > inizio) {
        if (_qui.length + (fine - inizio) > massimo()) {
          _scarta = true;
          troppoLunghe++;
          _qui.clear();
          troppoLunga();
        } else {
          _qui.add(Uint8List.fromList(pezzo.sublist(inizio, fine)));
        }
      }
      if (a < 0) return;
      if (_scarta) {
        _scarta = false;
      } else {
        riga(_qui.takeBytes());
      }
      inizio = a + 1;
    }
  }

  /// Quello che è rimasto senza a-capo quando il client ha chiuso. Vuoto se
  /// non c'è niente, o se era il pezzo di una riga già buttata.
  Uint8List resto() {
    if (_scarta) {
      _scarta = false;
      _qui.clear();
      return Uint8List(0);
    }
    return _qui.takeBytes();
  }
}

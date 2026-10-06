import 'dart:async';
import 'dart:io';

/// Avvisa chi guarda una cartella quando il suo contenuto cambia.
///
/// ── Perché esiste ────────────────────────────────────────────────────────
///
/// Il gestore file rileggeva una cartella solo entrandoci, o dopo un'azione
/// sua (copia, rinomina, cestino). Tutto quello che succedeva da FUORI non
/// si vedeva: lo scaricamento di Chrome che arriva in «Scaricati», un file
/// salvato da un altro programma, uno cancellato dal terminale. Trovato il
/// 6 ottobre 2026 provandolo: un file creato con `touch` non compariva
/// nemmeno dopo sedici secondi, e uno cancellato restava in elenco.
///
/// Qui ogni riquadro che riceve un elenco viene messo a guardare la sua
/// cartella con inotify (`Directory.watch`, non ricorsivo: si guarda solo
/// quello che si vede). Più riquadri sulla stessa cartella condividono un
/// solo osservatore.
///
/// ── Una raffica, un avviso ───────────────────────────────────────────────
///
/// Uno scaricamento sono decine di eventi (crea `.crdownload`, scrive,
/// scrive, rinomina); una copia di mille file ne fa mille. Si avvisa una
/// volta sola, `_calma` dopo l'ultimo evento di una raffica — e comunque al
/// più ogni `_almeno`, perché durante una copia lunga la cartella che si
/// riempie si deve vedere riempirsi, non solo alla fine.
class OsservatoreCartelle {
  OsservatoreCartelle(this._invia);

  /// Come si manda un messaggio a un client: il servizio non conosce il tipo
  /// della connessione, e così si prova senza un server vero.
  final void Function(Object client, Map<String, dynamic> messaggio) _invia;

  static const _calma = Duration(milliseconds: 250);
  static const _almeno = Duration(seconds: 1);

  /// Chi guarda cosa: per ogni client, riquadro → cartella.
  final Map<Object, Map<String, String>> _chi = {};

  /// Un osservatore per cartella, con chi lo ascolta.
  final Map<String, _Osservazione> _dove = {};

  /// Quante cartelle si stanno guardando: per le prove e per il registro.
  int get quante => _dove.length;

  /// Il riquadro `riquadro` di `client` adesso mostra `cartella`.
  void guarda(Object client, String riquadro, String cartella) {
    if (riquadro.isEmpty || cartella.isEmpty) return;
    final suoi = _chi.putIfAbsent(client, () => {});
    final prima = suoi[riquadro];
    if (prima == cartella) return;
    if (prima != null) _lascia(client, riquadro, prima);
    suoi[riquadro] = cartella;

    final oss = _dove[cartella] ?? _apri(cartella);
    if (oss == null) {
      // Non si può guardare (non è una cartella, o inotify ha finito gli
      // osservatori): il riquadro funziona come prima, solo senza avvisi.
      suoi.remove(riquadro);
      return;
    }
    oss.ascoltatori.add(_Chi(client, riquadro));
  }

  /// Il riquadro non c'è più (scheda chiusa).
  void smettiRiquadro(Object client, String riquadro) {
    final cartella = _chi[client]?.remove(riquadro);
    if (cartella != null) _lascia(client, riquadro, cartella);
  }

  /// Il client se n'è andato: tutti i suoi riquadri smettono di guardare.
  void smetti(Object client) {
    final suoi = _chi.remove(client);
    if (suoi == null) return;
    suoi.forEach((riquadro, cartella) => _lascia(client, riquadro, cartella));
  }

  void _lascia(Object client, String riquadro, String cartella) {
    final oss = _dove[cartella];
    if (oss == null) return;
    oss.ascoltatori.removeWhere((c) => c.client == client && c.riquadro == riquadro);
    if (oss.ascoltatori.isEmpty) {
      oss.chiudi();
      _dove.remove(cartella);
    }
  }

  _Osservazione? _apri(String cartella) {
    final dir = Directory(cartella);
    if (!dir.existsSync()) return null;
    final oss = _Osservazione();
    try {
      oss.flusso = dir.watch().listen(
        (_) => _evento(cartella, oss),
        // inotify esaurito, o la cartella sparita sotto i piedi: si avvisa
        // un'ultima volta (il riquadro rilegge e mostra l'errore vero) e si
        // smette, senza far cadere il demone.
        onError: (Object _) => _muore(cartella, oss),
        onDone: () => _muore(cartella, oss),
        cancelOnError: true,
      );
    } on FileSystemException {
      return null;
    }
    _dove[cartella] = oss;
    return oss;
  }

  /// L'osservatore non funziona più. Si dimentica del tutto — anche chi lo
  /// ascoltava — così il prossimo elenco di quella cartella ne apre uno nuovo
  /// invece di appendersi a uno morto.
  void _muore(String cartella, _Osservazione oss) {
    if (_dove[cartella] != oss) return;
    _avvisa(cartella, oss);
    _dove.remove(cartella);
    for (final c in oss.ascoltatori) {
      _chi[c.client]?.remove(c.riquadro);
    }
    oss.chiudi();
  }

  void _evento(String cartella, _Osservazione oss) {
    oss.calma?.cancel();
    oss.calma = Timer(_calma, () => _avvisa(cartella, oss));
    // Il tetto: in una raffica lunga si avvisa lo stesso ogni `_almeno`.
    oss.tetto ??= Timer(_almeno, () => _avvisa(cartella, oss));
  }

  void _avvisa(String cartella, _Osservazione oss) {
    oss.calma?.cancel();
    oss.calma = null;
    oss.tetto?.cancel();
    oss.tetto = null;
    for (final c in List.of(oss.ascoltatori)) {
      _invia(c.client, {
        'event': 'fs_changed',
        'payload': {'path': cartella, 'pane': c.riquadro},
      });
    }
  }

  /// Chiude tutto: allo spegnimento del demone.
  void chiudi() {
    for (final oss in _dove.values) {
      oss.chiudi();
    }
    _dove.clear();
    _chi.clear();
  }
}

class _Chi {
  _Chi(this.client, this.riquadro);
  final Object client;
  final String riquadro;
}

class _Osservazione {
  StreamSubscription<FileSystemEvent>? flusso;
  Timer? calma;
  Timer? tetto;
  final List<_Chi> ascoltatori = [];

  void chiudi() {
    calma?.cancel();
    tetto?.cancel();
    flusso?.cancel();
  }
}

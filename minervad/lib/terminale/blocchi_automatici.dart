import 'emulatore.dart';

/// Metadati osservativi, mai usati per decidere dove mandare la tastiera.
/// Snapshot testuali limitati: non pretendono di essere una registrazione VT.
class BlocchiAutomatici {
  BlocchiAutomatici(this.emulatore, this.annuncia);
  final Emulatore emulatore;
  final void Function(Map<String, dynamic>) annuncia;
  Map<String, dynamic>? _attuale;
  final _tempo = Stopwatch();
  int _id = 0;
  int _inizio = 0;
  int _alt = 0;
  bool _pronto = false;

  void marcatore(String tipo, int codice, String comando, String cartella) {
    switch (tipo) {
      case 'A':
        if (_attuale != null) termina(-1);
        _pronto = true;
      case 'C':
        if (!_pronto || _attuale != null) return;
        _pronto = false;
        _inizio = emulatore.rigaAssoluta(emulatore.cy);
        _alt = emulatore.ingressiAlternativo;
        _tempo..reset()..start();
        _attuale = {'t': 'bloccoAutomatico', 'id': ++_id,
          'comando': comando, 'cartella': cartella, 'stato': 'corsa',
          'codice': -1, 'durata': 0, 'uscita': '', 'troncato': false,
          'interattivo': false};
        annuncia(Map.of(_attuale!));
      case 'D':
        termina(codice);
    }
  }

  void termina(int codice) {
    final b = _attuale;
    if (b == null) return;
    _attuale = null;
    _tempo.stop();
    final e = emulatore;
    final fine = e.rigaAssoluta(e.cy);
    final disponibile = e.righeUscite - e.scrollback.length;
    var da = _inizio;
    var troncato = false;
    if (da < disponibile) { da = disponibile; troncato = true; }
    if (fine - da > 200) { da = fine - 200; troncato = true; }
    final interattivo = e.ingressiAlternativo != _alt;
    final righe = <String>[];
    if (!interattivo) {
      for (var i = da; i <= fine; i++) {
        final r = e.rigaStoria(i - e.righeUscite);
        if (r != null) righe.add(r.testo());
      }
    }
    var uscita = righe.join('\n').trimRight();
    if (uscita.length > 16384) {
      uscita = uscita.substring(uscita.length - 16384); troncato = true;
    }
    annuncia({...b, 'stato': 'finito', 'codice': codice,
      'durata': _tempo.elapsedMilliseconds, 'uscita': uscita,
      'troncato': troncato, 'interattivo': interattivo});
  }
}

// Il codice di un file, SENZA i commenti: quello che le guardie devono
// leggere.
//
// ── Perché esiste ──────────────────────────────────────────────────────────
//
// Il 27 settembre 2026 si è messo alla prova ogni guardia che pretende una
// riga nel codice («deve esserci `Core.TenutaPronta`»): si è trasformata
// quella riga in un commento, con lo stesso testo dentro. Sette su otto sono
// rimaste verdi. In questo progetto chi toglie qualcosa lascia scritto «qui
// c'era X» — ed è giusto — ma una guardia che legge anche i commenti vede
// quella X e continua a dire che il codice c'è.
//
// Si tolgono solo i commenti di riga intera e quelli a blocco: un `//` in
// mezzo a una riga può stare dentro una stringa («https://…»), e toglierlo
// cambierebbe il codice invece di pulirlo.
import 'dart:io';

/// Toglie i commenti secondo la lingua del file, riconosciuta dal nome:
/// `//` e `/* */` per QML, JavaScript, Dart e C; `#` per gli script, le
/// configurazioni e Python (tranne la prima riga `#!`). Gli altri file
/// (JSON, testo, registri) restano come sono.
String senzaCommenti(String testo, String nome) {
  final punto = nome.lastIndexOf('.');
  final barra = nome.lastIndexOf('/');
  final est = punto > barra ? nome.substring(punto + 1) : '';
  const barre = {'qml', 'js', 'mjs', 'dart', 'c', 'h', 'cpp'};
  const cancelletti = {'', 'sh', 'bash', 'conf', 'py', 'desktop', 'rules',
    'toml', 'ini', 'minerva', 'service', 'build'};
  final righe = testo.split('\n');
  final fuori = <String>[];
  if (barre.contains(est)) {
    var dentroBlocco = false;
    for (final r in righe) {
      final s = r.trimLeft();
      if (dentroBlocco) {
        if (s.contains('*/')) dentroBlocco = false;
        continue;
      }
      if (s.startsWith('//')) continue;
      if (s.startsWith('/*')) {
        if (!s.contains('*/')) dentroBlocco = true;
        continue;
      }
      fuori.add(r);
    }
    return fuori.join('\n');
  }
  if (cancelletti.contains(est)) {
    for (var i = 0; i < righe.length; i++) {
      final s = righe[i].trimLeft();
      if (s.startsWith('#') && !(i == 0 && s.startsWith('#!'))) continue;
      fuori.add(righe[i]);
    }
    return fuori.join('\n');
  }
  return testo;
}

extension CodiceVivo on File {
  /// Il contenuto del file senza commenti: vedi `senzaCommenti`.
  String codiceVivo() => senzaCommenti(readAsStringSync(), path);
}

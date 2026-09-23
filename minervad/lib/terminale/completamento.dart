// Operazioni conservative sul testo: nessuna espansione o esecuzione shell.
library;

bool contieneControlli(String testo) =>
    RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(testo);

/// Completa solo il token in corso, oppure il prossimo se preceduto da
/// uno spazio. Mai aggiungere pipe, redirezioni o sostituzioni di comando.
String prossimaParola(String testo, String proposta) {
  if (!proposta.startsWith(testo) || contieneControlli(proposta)) return '';
  String? quote;
  var escape = false;
  for (var i = 0; i < proposta.length; i++) {
    final c = proposta[i];
    if (escape) { escape = false; continue; }
    if (c == r'\' && quote != "'") { escape = true; continue; }
    if (quote != null) {
      if (c == quote) { quote = null; continue; }
      if (quote == '"' && (c == r'$' || c == '`')) return '';
      continue;
    }
    if (c == "'" || c == '"') { quote = c; continue; }
    if (r'|&;<>($`'.contains(c)) return '';
    if (c == ' ' && i >= testo.length) {
      return i > testo.length ? proposta.substring(0, i) : '';
    }
  }
  if (quote != null || escape || proposta.length <= testo.length) return '';
  return proposta;
}

/// L'ultimo token, con spazi protetti; sintassi complessa non indovinata.
({int inizio, String valore})? ultimoPercorso(String testo) {
  var inizio = 0;
  var valore = StringBuffer();
  var escape = false;
  for (var i = 0; i < testo.length; i++) {
    final c = testo[i];
    if (escape) { valore.write(c); escape = false; continue; }
    if (c == r'\') { escape = true; continue; }
    if ('\'"|&;<>(\$`'.contains(c) || contieneControlli(c)) return null;
    if (c == ' ') { inizio = i + 1; valore = StringBuffer(); }
    else { valore.write(c); }
  }
  if (escape || inizio == 0) return null;
  return (inizio: inizio, valore: valore.toString());
}

String proteggiPercorso(String testo) => testo.runes.map(String.fromCharCode).map((c) =>
    RegExp(r'[a-zA-Z0-9_./-]').hasMatch(c) ? c : '\\$c').join();

/// ESC non deve poter chiudere il bracketed paste e introdurre tasti.
String pulisciIncolla(String testo) => testo
    .replaceAll('\r\n', '\n').replaceAll('\r', '\n')
    .replaceAll(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]'), '');

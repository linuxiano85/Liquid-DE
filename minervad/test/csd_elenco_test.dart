import 'dart:io';
import 'package:test/test.dart';

/// L'elenco delle applicazioni che si disegnano la barra da sole esiste in
/// DUE posti: le impostazioni del demone (la sorgente) e la lista di riserva
/// del compositore, che vale finché la shell non ha ancora spinto la sua.
///
/// Due elenchi che dicono la stessa cosa vanno alla deriva. Il sintomo è
/// preciso e antipatico: una finestra con DUE barre del titolo per il mezzo
/// secondo che passa fra l'avvio del compositore e il primo `csd` della
/// shell — o per sempre, se il compositore parte e la shell no.
void main() {
  String radice() {
    var d = Directory.current;
    while (!File('${d.path}/MODULI.md').existsSync()) {
      final su = d.parent;
      if (su.path == d.path) throw StateError('radice del progetto non trovata');
      d = su;
    }
    return d.path;
  }

  List<String> dalDemone() {
    final t = File('${radice()}/minervad/lib/core/settings_api.dart')
        .readAsStringSync();
    final i = t.indexOf("'csdApps': [");
    expect(i, isNot(-1), reason: 'csdApps sparito da settings_api.dart');
    // Via i commenti PRIMA di cercare le stringhe: dentro c'è più di un
    // apostrofo italiano, e per una espressione regolare un apostrofo è una
    // virgoletta. Senza questo, il commento diventava tre voci dell'elenco.
    final blocco = t
        .substring(i, t.indexOf(']', i))
        .split('\n')
        .where((r) => !r.trimLeft().startsWith('//'))
        .join('\n');
    return RegExp(r"'([^']+)'")
        .allMatches(blocco)
        .map((m) => m.group(1)!)
        .where((v) => v != 'csdApps')
        .toList();
  }

  List<String> dalCompositore() {
    final t = File('${radice()}/compositore/src/main.c').readAsStringSync();
    final i = t.indexOf('static const char *riserva[] = {');
    expect(i, isNot(-1), reason: 'la lista di riserva sparita da main.c');
    final blocco = t.substring(i, t.indexOf('};', i));
    return RegExp(r'"([^"]*)"').allMatches(blocco).map((m) => m.group(1)!).toList();
  }

  test('l\'elenco CSD di riserva del compositore dice quel che dicono le impostazioni', () {
    expect(dalCompositore(), dalDemone());
  });

  test('Antigravity ci sta: si disegna la barra da sé', () {
    // Editor derivato da VS Code: `window.titleBarStyle` vale «custom» su
    // Linux. Segnalato da Giacomo il 12 agosto 2026 — «ha 2 barre del titolo,
    // una sua e la nostra sopra».
    expect(dalDemone(), contains('antigravity'));
  });
}

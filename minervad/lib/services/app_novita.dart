import 'dart:convert';
import 'dart:io';

/// Confronta identità desktop, non date dei pacchetti: un aggiornamento
/// non rende nuova un'app già conosciuta. Primo avvio = fotografia iniziale.
class AppNovita {
  AppNovita({this.percorso});
  final String? percorso;
  Set<String>? _conosciute;
  final Set<String> nuove = {};
  bool _caricato = false;
  Future<void> _scrittura = Future.value();

  static String percorsoDiSerie() {
    final env = Platform.environment;
    final base = env['XDG_STATE_HOME'];
    final dir = base != null && base.startsWith('/')
        ? base : '${env['HOME'] ?? Directory.systemTemp.path}/.local/state';
    return '$dir/minerva/app-novita.json';
  }

  Future<void> aggiorna(Iterable<String> ids) async {
    if (!_caricato) {
      _caricato = true;
      try {
        final f = File(percorso!);
        if (await f.length() <= 1024 * 1024) {
          final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          final conosciute = (m['conosciute'] as List).cast<String>().toSet();
          final pending = (m['nuove'] as List).cast<String>().toSet();
          _conosciute = conosciute;
          nuove.addAll(pending.intersection(conosciute));
        }
      } catch (_) { /* Primo avvio o stato illeggibile: nessuna falsa novità. */ }
    }
    final attuali = ids.toSet();
    final prima = _conosciute;
    if (prima != null) nuove.addAll(attuali.difference(prima));
    nuove.retainAll(attuali);
    _conosciute = attuali;
    await _salva();
  }

  Future<bool> vista(String id) async {
    if (!nuove.remove(id)) return false;
    await _salva();
    return true;
  }

  Future<void> _salva() {
    final p = percorso;
    if (p == null) return Future.value();
    final dati = jsonEncode({'conosciute': _conosciute!.toList()..sort(),
      'nuove': nuove.toList()..sort()});
    // Serializza le scritture: lancio e scansione non devono sovrascriversi.
    _scrittura = _scrittura.then((_) async {
      Directory? temp;
      try {
        final destinazione = File(p);
        await destinazione.parent.create(recursive: true);
        temp = await destinazione.parent.createTemp('.app-novita-');
        final f = File('${temp.path}/stato.json');
        await f.writeAsString(dati, flush: true);
        await f.rename(p);
      } catch (e) {
        stderr.writeln('[MINERVA][APPS] Stato novità non salvato: $e');
      } finally {
        if (temp != null) {
          try { await temp.delete(recursive: true); } catch (_) {}
        }
      }
    });
    return _scrittura;
  }
}

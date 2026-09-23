import 'dart:async';
import 'dart:io';

/// Cercare un file dentro le cartelle, e potersi fermare.
///
/// ── Perché non basta `fs_list` ─────────────────────────────────────────────
///
/// Il gestore file sa filtrare la cartella aperta: si scrive e restano solo le
/// righe che contengono quel testo. È immediato e onesto, ma risponde a una
/// domanda sola — «dov'è, qui dentro». La domanda che si fa più spesso è
/// l'altra: «dov'è, da qualche parte».
///
/// ── Le tre cose che rendono una ricerca usabile ────────────────────────────
///
/// 1. **I risultati arrivano mentre cerca.** Una ricerca che risponde solo
///    alla fine, su una cartella di casa con centomila file, è una finestra
///    ferma per venti secondi. Qui si mandano a mazzetti, e il primo mazzetto
///    arriva quasi subito perché le cartelle vicine si guardano per prime.
///
/// 2. **Si può fermare.** Chi ha trovato quello che cercava non deve aspettare
///    che finisca, e chi ha sbagliato a scrivere nemmeno.
///
/// 3. **Non esce di casa.** `/proc`, `/sys`, `/dev` e le cartelle montate non
///    si attraversano: sono milioni di voci che non sono file di nessuno, e
///    scendendoci una ricerca in `/` non finisce più.
class RicercaService {
  /// Le ricerche in corso, per identificativo. Ognuna si può fermare da sé.
  final Map<String, bool> _vive = {};

  /// Quante voci si mandano insieme. Poche fanno tanti messaggi, tante fanno
  /// una finestra che si aggiorna a scatti: cinquanta è il punto in cui i due
  /// fastidi si equivalgono.
  static const int _mazzetto = 50;

  /// Il tetto: oltre questo si smette e lo si dice. Una ricerca che torna con
  /// ottomila risultati non ha trovato niente — ha solo scritto tanto.
  static const int _massimo = 2000;

  /// Le cartelle che non si attraversano MAI.
  ///
  /// Non è prudenza: `/proc` contiene una cartella per ogni processo e cambia
  /// mentre la si legge; `/sys` è il kernel che si racconta. Una ricerca che
  /// ci scende dentro non finisce e intanto tiene occupato il disco.
  static const _mai = {
    '/proc', '/sys', '/dev', '/run', '/tmp/.X11-unix',
    '/var/lib/docker', '/var/lib/flatpak/repo',
  };

  /// Ferma una ricerca in corso. Se non c'è, non fa niente e non si lamenta:
  /// il messaggio di stop può arrivare dopo che è finita da sola.
  void ferma(String id) => _vive[id] = false;

  /// Cerca `testo` dentro `radice`, e restituisce i risultati a mazzetti.
  ///
  /// Il confronto è sul NOME e non sul percorso: chi cerca «fattura» non vuole
  /// tutto quello che sta dentro una cartella chiamata «fatture».
  Stream<Map<String, dynamic>> cerca(
    String id,
    String radice,
    String testo, {
    bool ancheNascosti = false,
  }) async* {
    _vive[id] = true;
    final ago = testo.trim().toLowerCase();
    if (ago.isEmpty) {
      _vive.remove(id);
      yield {'id': id, 'fine': true, 'trovati': 0, 'fermata': false};
      return;
    }

    var trovati = 0;
    var guardate = 0;
    var mazzo = <Map<String, dynamic>>[];

    // In ampiezza e non in profondità: le cartelle vicine si guardano per
    // prime, quindi il primo mazzetto arriva subito ed è quello che ha più
    // probabilità di contenere ciò che si cerca. Scendendo in profondità si
    // finirebbe in fondo al primo ramo mentre il file sta nella cartella
    // accanto.
    final coda = <String>[radice];

    while (coda.isNotEmpty) {
      if (_vive[id] != true) {
        yield {'id': id, 'fine': true, 'trovati': trovati, 'fermata': true};
        _vive.remove(id);
        return;
      }

      final qui = coda.removeAt(0);
      if (_mai.any((v) => qui == v || qui.startsWith('$v/'))) continue;

      List<FileSystemEntity> voci;
      try {
        voci = await Directory(qui).list(followLinks: false).toList();
      } catch (_) {
        // Cartella senza permessi, o sparita mentre cercavamo. Non è un
        // errore da raccontare: è normale, e fermarsi sarebbe peggio.
        continue;
      }

      for (final e in voci) {
        final nome = e.path.split(Platform.pathSeparator).last;
        if (!ancheNascosti && nome.startsWith('.')) continue;

        final isDir = e is Directory;
        if (isDir) coda.add(e.path);

        if (nome.toLowerCase().contains(ago)) {
          trovati++;
          mazzo.add({
            'name': nome,
            'path': e.path,
            'isDir': isDir,
            // La cartella che lo contiene, perché in una ricerca il percorso
            // conta quanto il nome: tre file chiamati «appunti.txt» si
            // distinguono solo da lì.
            'dove': e.path.substring(0, e.path.length - nome.length - 1),
          });
          if (mazzo.length >= _mazzetto) {
            yield {'id': id, 'voci': mazzo, 'fine': false};
            mazzo = <Map<String, dynamic>>[];
          }
          if (trovati >= _massimo) {
            if (mazzo.isNotEmpty) yield {'id': id, 'voci': mazzo, 'fine': false};
            yield {
              'id': id,
              'fine': true,
              'trovati': trovati,
              'troppi': true,
              'fermata': false,
            };
            _vive.remove(id);
            return;
          }
        }
      }

      // Ogni tanto si lascia respirare il resto del demone: senza, una
      // ricerca su una cartella grande tiene il filo occupato e il canale con
      // le finestre non risponde più — la barra si ferma mentre si cerca.
      guardate++;
      if (guardate % 20 == 0) await Future<void>.delayed(Duration.zero);
    }

    if (mazzo.isNotEmpty) yield {'id': id, 'voci': mazzo, 'fine': false};
    yield {'id': id, 'fine': true, 'trovati': trovati, 'fermata': false};
    _vive.remove(id);
  }
}

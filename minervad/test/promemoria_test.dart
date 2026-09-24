// Il promemoria dei tasti (F1) deve dire il vero.
//
// Un elenco di scorciatoie sbagliato è peggio di nessun elenco: chi lo legge
// prova il tasto, non succede quel che c'è scritto, e da quel momento non si
// fida più di nessuna riga.
//
// ── Si guarda la SORGENTE, non un prodotto ────────────────────────────────
//
// Fino al 2 settembre 2026 queste prove leggevano `config/hypr/keybinds.conf`
// — il file generato per Hyprland — e ne rifacevano il parsing a mano, con tre
// espressioni regolari. Quel file è sparito con la sessione Hyprland.
//
// Adesso si legge `config/scorciatoie.minerva`, che è la sorgente, **e con il
// lettore vero** (`Scorciatoie.leggi`): è lo stesso codice che usa il demone
// per costruire il pannello. Prima le prove interpretavano il file a modo
// loro, e una guardia che legge diversamente da chi legge sul serio può dire
// verde su un pannello sbagliato.
//
// Il lettore porta già `categoria` e `descrizione` dentro ogni scorciatoia:
// il raggruppamento non va più ricostruito, si chiede.

import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/scorciatoie.dart';

File _file(String relativo) {
  for (final base in ['.', '..', '../..']) {
    final f = File('$base/$relativo');
    if (f.existsSync()) return f;
  }
  fail('non trovo $relativo');
}

Scorciatoie _sorgente() =>
    Scorciatoie.leggi(_file('config/scorciatoie.minerva').readAsStringSync());

class _Voce {
  final int riga;
  final String tasto;
  final String azione;
  _Voce(this.riga, this.tasto, this.azione);
}

/// Le combinazioni raggruppate per annotazione, come le vede il demone.
///
/// Chi non ha annotazione — perché prima non ce n'era nessuna, o perché una
/// `@-` l'ha spenta — resta fuori, ed è giusto: fuori dal promemoria è
/// esattamente dove deve stare.
Map<String, List<_Voce>> _blocchi() {
  final fuori = <String, List<_Voce>>{};
  for (final s in _sorgente().tutte) {
    if (s.categoria == null || s.descrizione == null) continue;
    final chiave = '${s.categoria} | ${s.descrizione}';
    fuori.putIfAbsent(chiave, () => []);
    fuori[chiave]!.add(_Voce(s.riga, s.tasti, s.azione));
  }
  return fuori;
}

/// I gruppi in cui più tasti fanno cose DIVERSE sotto una descrizione sola, e
/// va bene così: sono famiglie, e la descrizione le copre tutte davvero.
///
/// Vive qui e non nel file perché aggiungerne una deve essere una DECISIONE.
/// Ogni nome nuovo che compare qui è qualcuno che ha guardato e detto «sì,
/// questa descrizione è onesta anche per il tasto nuovo».
/// Le scorciatoie che stanno fuori dal promemoria APPOSTA.
///
/// Si scrivono per azione, e ognuna è una decisione presa guardando: il
/// rilascio di Alt che conferma l'Alt+Tab non è «un modo di tornare indietro»
/// e nel pannello F1 direbbe il falso.
///
/// Vive qui e non nel file per la stessa ragione di `_famiglieAmmesse`:
/// aggiungerne una deve costare una riga scritta a mano da qualcuno.
const _fuoriApposta = <String>[
  // Il rilascio di Alt che conferma l'Alt+Tab. Sotto «Torna indietro
  // nell'elenco delle finestre» il pannello F1 lo mostrava come un modo di
  // tornare indietro, e non lo è: è la riga da cui nasce tutta questa prova.
  'minerva: switchercommit',
];

const _famiglieAmmesse = {
  'Muoversi | Vai alla stanza 1…10',
  'Muoversi | Vai alla stanza 1…10 portando la finestra',
  'Mouse | Super + rotellina: la stanza accanto',
  'Sistema | Accende o spegne il touchpad',
};

void main() {
  group('il promemoria non dice il falso', () {
    test('ogni descrizione copre davvero tutti i suoi tasti', () {
      // ── Il difetto da cui nasce questa prova ────────────────────────────
      //
      // L'annotazione `#@` vale per TUTTI i bind che la seguono, finché non
      // ne arriva un'altra. Il rilascio di Alt (che conferma l'Alt+Tab) stava
      // sotto «Torna indietro nell'elenco delle finestre», e il pannello F1
      // lo mostrava come un modo di tornare indietro. Non lo è.
      //
      // Chi scriveva pensava che bastasse NON mettere l'annotazione. Non
      // basta: adesso c'è `#@-`, che la spegne.
      final colpevoli = <String>[];
      _blocchi().forEach((descrizione, voci) {
        if (_famiglieAmmesse.contains(descrizione)) return;
        final azioni = voci.map((v) => v.azione).toSet();
        if (azioni.length > 1) {
          colpevoli.add('«$descrizione»\n'
              '${voci.map((v) => '      riga ${v.riga}: ${v.tasto} → ${v.azione}').join('\n')}');
        }
      });
      expect(colpevoli, isEmpty,
          reason: 'sotto una descrizione sola ci sono tasti che fanno cose\n'
              'diverse. O la descrizione è falsa per uno di loro — e allora\n'
              'serve un `#@` suo, oppure `#@-` per tenerlo fuori — o è una\n'
              'famiglia vera, e va aggiunta a `_famiglieAmmesse` GUARDANDOLA.');
    });

    test('nessuna scorciatoia resta fuori dal promemoria per sbaglio', () {
      // Il contrario del difetto sopra: un bind prima di qualunque `#@` non
      // comparirebbe da nessuna parte, e nessuno lo direbbe.
      // Il lettore mette `categoria` a null quando la scorciatoia non ha
      // un'annotazione sopra. Distinguere «non ne ha mai avuta una» da
      // «l'ha spenta con `@-`» non si può, e non serve: quello che conta è
      // che chi resta fuori sia stato messo fuori APPOSTA, e le uniche
      // ammesse sono qui sotto per nome.
      final orfani = _sorgente()
          .tutte
          .where((s) => s.categoria == null)
          .where((s) => !_fuoriApposta.any((x) => s.azione.startsWith(x)))
          .map((s) => 'riga ${s.riga}: ${s.tasti} -> ${s.azione}')
          .toList();
      expect(orfani, isEmpty,
          reason: 'scorciatoie senza annotazione: non compaiono nel pannello\n'
              'F1 e nessuno se ne accorge. Dagliene una, oppure — se devono\n'
              'restare fuori — aggiungile a `_fuoriApposta` GUARDANDOLE.');
    });

    test('il lettore della sorgente conosce `@-`', () {
      // Se sparisse dal lettore, il file continuerebbe a contenerlo e la riga
      // tornerebbe nel pannello sotto la descrizione sbagliata — in silenzio,
      // che è il modo peggiore.
      //
      // Il lettore si è spostato: dall'11 agosto 2026 il formato è nostro
      // (`@-`) e sta in `scorciatoie.dart`; `keybind_service` non fa più il
      // parsing della lingua di Hyprland.
      final s = _file('minervad/lib/services/scorciatoie.dart').readAsStringSync();
      expect(s, contains('_spegni'));
      expect(s, contains(r"RegExp(r'^@\s*-\s*$')"));
    });

    test('il rilascio di Alt sta fuori dal promemoria', () {
      // La riga concreta da cui è partito tutto, tenuta ferma per nome.
      final blocchi = _blocchi();
      for (final voci in blocchi.values) {
        for (final v in voci) {
          expect(v.azione, isNot(contains('switchercommit')),
              reason: 'il rilascio di Alt conferma la scelta: non è una '
                  'scorciatoia da imparare, e nel promemoria non ci va');
        }
      }
    });
  });
}

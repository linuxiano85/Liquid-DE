import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// I widget della scrivania esistono in TRE elenchi che nessun compilatore
/// mette a confronto:
///
///   1. `settings/sections/Scrivania.qml` — `disponibili`, cioè quelli che si
///      possono aggiungere, più `righeRiassunto` e `perLaBarra`;
///   2. `widget/Contenuto.qml` — da dove ognuno prende il suo numero e come
///      si chiama;
///   3. `core/Macchina.qml` — chi ha una storia da disegnare.
///
/// ── Perché serve una guardia, e non è teoria ──────────────────────────────
///
/// Il 9 settembre 2026 il riassunto mostrava «—» al posto dei valori. Non era
/// un dato mancante: era un tipo che arrivava sbagliato, e `Contenuto` per un
/// tipo che non conosce restituisce **un trattino** — cioè esattamente quello
/// che mostra quando il dato non c'è ancora.
///
/// È la peggiore delle forme: **un difetto travestito da caso normale**. Chi
/// guarda pensa «sta ancora caricando» e aspetta per sempre.
///
/// Quindi: ogni tipo che una pagina offre deve avere il suo `case` in tutti e
/// due i posti in cui `Contenuto` decide qualcosa — il valore e il nome — o
/// aggiungerne uno nuovo vuol dire pubblicare un trattino.
File _trova(String relativo) {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/$relativo');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo $relativo');
}

/// I valori di un elenco QML fatto di stringhe:
///
///     readonly property var perLaBarra: [
///         "processore", "memoria"
///     ]
List<String> _elenco(String qml, String nome) {
  final m = RegExp('property var $nome:\\s*\\[(.*?)\\]', dotAll: true)
      .firstMatch(qml);
  if (m == null) fail('non trovo l\'elenco `$nome`');
  return RegExp('"([a-z]+)"')
      .allMatches(m.group(1)!)
      .map((x) => x.group(1)!)
      .toList();
}

void main() {
  final scrivania =
      _trova('minerva-shell/settings/sections/Scrivania.qml').codiceVivo();
  final contenuto =
      _trova('minerva-shell/widget/Contenuto.qml').codiceVivo();
  final macchina =
      _trova('minerva-shell/core/Macchina.qml').codiceVivo();

  /// I tipi offerti dalla pagina: `{ "tipo": "processore", …`.
  final offerti = RegExp('"tipo":\\s*"([a-z]+)"')
      .allMatches(scrivania)
      .map((m) => m.group(1)!)
      .toSet()
      .toList();

  /// I COMPOSITI non sono un valore: sono caselle che ne contengono altri, e
  /// ognuno ha il suo file — `Riassunto.qml`, `Prestazioni.qml`,
  /// `Bluetooth.qml`. Non passano da `Contenuto`, ma devono avere il loro
  /// `Component` in `Widgets.qml`, o si aprirebbero come «un numero e una
  /// parola» con dentro un trattino.
  const compositi = ['riassunto', 'prestazioni', 'bluetooth'];
  final valori = offerti.where((t) => !compositi.contains(t)).toList();

  group('i widget della scrivania', () {
    test('la pagina offre qualcosa, o questa prova non prova niente', () {
      expect(offerti.length, greaterThan(5),
          reason: 'i tipi si leggono da `disponibili` in Scrivania.qml: '
              'se qui ne risulta uno solo, è la lettura a essersi rotta');
      expect(offerti, contains('riassunto'));
    });

    // ── Tre tabelle, tre fette del file ─────────────────────────────────
    //
    // In `Contenuto.qml` gli `switch` stanno in quest'ordine: `valore`,
    // `icona`, `nome`. Cercare `case "x":` in tutto il file farebbe passare
    // un tipo che ha il simbolo e non il numero — che è il caso da prendere.
    final iniziaIcona = contenuto.indexOf('readonly property string icona');
    final iniziaNome = contenuto.indexOf('readonly property string nome');
    final fettaValore = contenuto.substring(0, iniziaIcona);
    final fettaIcona = contenuto.substring(iniziaIcona, iniziaNome);
    final fettaNome = contenuto.substring(iniziaNome);

    test('ogni tipo offerto sa dire il suo VALORE', () {
      final muti = <String>[];
      for (final t in valori) {
        if (!fettaValore.contains('case "$t":')) muti.add(t);
      }
      expect(muti, isEmpty,
          reason: 'questi tipi si possono aggiungere dalla pagina e '
              'mostrerebbero un trattino: ${muti.join(", ")}');
    });

    test('ogni tipo offerto ha un SIMBOLO, e il simbolo esiste', () {
      // Giacomo, 14 settembre 2026: «quelli sulla barra sono confusionari
      // perché non hanno un simbolo». Un tipo senza `case` prenderebbe
      // «info», cioè un simbolo che non dice niente — e un nome di icona
      // che non esiste in `ui/Icon.qml` disegnerebbe un quadrato vuoto.
      final icone = _trova('minerva-shell/ui/Icon.qml').codiceVivo();
      final senza = <String>[];
      final inesistenti = <String>[];
      for (final t in valori) {
        final m = RegExp('case "$t":\\s*return "([a-z-]+)";').firstMatch(fettaIcona);
        if (m == null) {
          senza.add(t);
          continue;
        }
        if (!icone.contains('"${m.group(1)}":')) inesistenti.add('$t → ${m.group(1)}');
      }
      expect(senza, isEmpty, reason: 'senza simbolo: ${senza.join(", ")}');
      expect(inesistenti, isEmpty,
          reason: 'simboli che Icon.qml non ha: ${inesistenti.join(", ")}');
    });

    test('ogni tipo offerto sa dire il suo NOME', () {
      final senzaNome = <String>[];
      for (final t in valori) {
        if (!fettaNome.contains('case "$t":')) senzaNome.add(t);
      }
      expect(senzaNome, isEmpty,
          reason: 'questi tipi comparirebbero con il proprio nome interno '
              'invece che con una parola: ${senzaNome.join(", ")}');
    });

    test('ogni composito ha il suo pezzo in Widgets.qml', () {
      final widgets = _trova('minerva-shell/widget/Widgets.qml').codiceVivo();
      for (final t in compositi) {
        expect(offerti, contains(t),
            reason: '«$t» è dichiarato composito ma la pagina non lo offre');
        expect(widgets, contains('cella.tipo === "$t"'),
            reason: '«$t» non ha un ramo nel Loader di Widgets.qml: '
                'si aprirebbe come widget singolo, con un trattino');
      }
    });

    test('le righe del riassunto e i valori della barra sono tipi veri', () {
      for (final nome in <String>['righeRiassunto', 'perLaBarra']) {
        for (final t in _elenco(scrivania, nome)) {
          expect(offerti, contains(t),
              reason: '`$nome` offre «$t», che non è fra i tipi di '
                  '`disponibili`: mostrerebbe un trattino');
        }
      }
      // Il riassunto è una colonna: metterlo dentro sé stesso, o dentro una
      // barra alta trentaquattro pixel, non è una svista che si vede subito.
      expect(_elenco(scrivania, 'righeRiassunto'), isNot(contains('riassunto')));
      expect(_elenco(scrivania, 'perLaBarra'), isNot(contains('riassunto')));
    });

    test('chi ha una storia la sa dire una volta sola', () {
      // `Contenuto` non tiene un secondo elenco: chiede a `Macchina`, che è
      // l'unica che le storie ce l'ha davvero. Due elenchi vorrebbero dire
      // aggiungere una grandezza in uno e dimenticarla nell'altro.
      expect(contenuto, contains('Core.Macchina.haStoria('),
          reason: 'se `Contenuto` si riscrive il proprio elenco delle '
              'grandezze con storia, prima o poi diverge da `Macchina`');
      expect(macchina, contains('function haStoria('));

      // E chi ha una storia deve avere anche la lista dove tenerla.
      final conStoria = RegExp('case "([a-z]+)":\\s*return macchina.storia')
          .allMatches(macchina)
          .map((m) => m.group(1)!)
          .toList();
      final dichiarati = RegExp('quale === "([a-z]+)"')
          .allMatches(macchina.substring(macchina.indexOf('function haStoria(')))
          .map((m) => m.group(1)!)
          .toSet();
      for (final t in dichiarati) {
        expect(offerti, contains(t),
            reason: '«$t» ha una storia e non è un widget che si può mettere');
      }
      expect(dichiarati.length, conStoria.length,
          reason: '`haStoria` e `storia` dicono cose diverse: '
              'un grafico chiesto e mai riempito resta una riga vuota');
    });
  });
}

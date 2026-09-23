import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/schemi.dart';

/// La tavolozza, che è l'unico posto in cui si sceglie un colore.
File _colorsQml() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    final f = File('${dir.path}/minerva-shell/theme/Colors.qml');
    if (f.existsSync()) return f;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/theme/Colors.qml');
}

/// I temi dichiarati in `Colors.qml`, con il loro verso.
///
/// Si legge il QML invece di ripetere l'elenco qui: ripeterlo vorrebbe dire
/// avere due verità e nessun modo di sapere quale è quella buona.
Map<String, bool> _temiDalQml() {
  final testo = _colorsQml().readAsStringSync();
  final righe = RegExp(r'"(\w+)":\s*\{\s*"base":\s*"#[0-9A-Fa-f]{6}",\s*'
          r'"scura":\s*(true|false)')
      .allMatches(testo);
  return {
    for (final m in righe) m.group(1)!: m.group(2) == 'true',
  };
}

void main() {
  group('temi di colore', () {
    test('la tavolozza dichiara dei temi, e si riescono a leggere', () {
      final temi = _temiDalQml();
      expect(temi, isNotEmpty,
          reason: 'nessun tema letto da Colors.qml: cambiata la forma?');
      expect(temi.keys, contains(Schemi.predefinito));
    });

    test('c\'è almeno un tema chiaro e almeno uno scuro', () {
      // Giacomo: «questo scuro un po' mi sta stancando… il bianco con vetro
      // sfocato». Un tema chiaro solo, o scuro solo, non è una scelta: è un
      // interruttore.
      final temi = _temiDalQml();
      expect(temi.values.where((s) => s), isNotEmpty, reason: 'nessun tema scuro');
      expect(temi.values.where((s) => !s), isNotEmpty, reason: 'nessun tema chiaro');
    });

    test('il demone sa per ogni tema se è chiaro o scuro', () {
      // È il vincolo vero. Il demone non legge QML: sa quali temi sono chiari
      // da una lista scritta a mano (`services/schemi.dart`), e la usa per
      // scegliere la variante del tema di icone. Aggiungendo un tema chiaro
      // in Colors.qml e dimenticando questa lista, le icone monocromatiche
      // sparirebbero su quel tema — ci sono e non si vedono, che è il difetto
      // più difficile da riconoscere di tutti.
      final temi = _temiDalQml();
      for (final voce in temi.entries) {
        expect(Schemi.eScuro(voce.key), equals(voce.value),
            reason: 'il tema "${voce.key}" è '
                '${voce.value ? "scuro" : "chiaro"} in Colors.qml, e il demone '
                'lo crede ${Schemi.eScuro(voce.key) ? "scuro" : "chiaro"}. '
                'Aggiorna `Schemi.chiari` in services/schemi.dart.');
      }
      // E nessun nome di troppo dall'altra parte.
      for (final chiaro in Schemi.chiari) {
        expect(temi.keys, contains(chiaro),
            reason: 'il demone conosce un tema chiaro "$chiaro" che in '
                'Colors.qml non esiste più');
      }
    });

    test('la tavolozza non ha più colori del testo scritti a mano', () {
      // Il difetto per cui questo file esiste: `text: "#EEF4FF"` e
      // `raised: Qt.rgba(1,1,1,0.055)` cuocevano la SCUREZZA dentro la
      // derivazione, e su fondo bianco erano invisibili. Adesso tutto passa
      // da `velo()` e da `mix()`, che conoscono il verso del tema.
      final testo = _colorsQml().readAsStringSync();
      final corpo = testo
          .split('\n')
          .where((r) => !r.trimLeft().startsWith('//'))
          .where((r) => !r.trimLeft().startsWith('///'))
          .join('\n');
      // Le velature bianche fisse sono la firma del difetto.
      expect(corpo.contains('Qt.rgba(1, 1, 1, 0.0'), isFalse,
          reason: 'una velatura bianca fissa è tornata nella tavolozza');
      expect(corpo.contains('Qt.rgba(1, 1, 1, 0.1'), isFalse,
          reason: 'una velatura bianca fissa è tornata nella tavolozza');
    });
  
    // ── Il settimo tema, quello scelto a mano ────────────────────────────
    //
    // Non sta in `Colors.qml` fra i sei, e non deve starci: il suo verso non è
    // un dato dell'elenco ma una scelta che si cambia dal pannello. La regola
    // che conta è che il demone la SEGUA — perché da quel bit dipende quale
    // variante del tema di icone si prende, e sbagliarla fa sparire le icone
    // monocromatiche senza nessun errore.
    test('il tema personale segue il verso scelto, non un elenco', () {
      expect(Schemi.eScuro(Schemi.personale, personaleScuro: true), isTrue);
      expect(Schemi.eScuro(Schemi.personale, personaleScuro: false), isFalse);
    });

    test('«personale» non è uno dei sei, e non lo diventa per sbaglio', () {
      // Se un giorno finisse dentro `schemes` con un `scura` scritto a mano,
      // quel valore vincerebbe sulla scelta dell'utente e il verso resterebbe
      // fisso — cioè la manopola smetterebbe di fare qualcosa senza dirlo.
      final temi = _temiDalQml();
      expect(temi.keys, isNot(contains(Schemi.personale)),
          reason: 'il tema personale ha il verso in `shell.versoPersonale`, '
              'non in Colors.qml: due sorgenti per lo stesso bit divergono.');
      expect(Schemi.chiari, isNot(contains(Schemi.personale)));
    });

    // ── Gli scavalcamenti: ognuno deve fare qualcosa ─────────────────────
    //
    // È la lezione di `bar.position`, che si poteva scrivere e non la leggeva
    // nessuno. Qui i nomi vivono in tre posti — l'elenco `scavalcabili`, le
    // chiamate `_ov("…")` che li applicano, e le righe del pannello Aspetto —
    // e basta che uno dei tre resti indietro perché compaia un quadratino che
    // si può cambiare e non cambia niente.
    //
    // Nessuno se ne accorgerebbe: il colore si salva, il pannello lo mostra,
    // e sullo schermo non succede nulla.
    test('ogni colore scavalcabile è davvero applicato, e viceversa', () {
      final tavolozza = _colorsQml().readAsStringSync();

      final elenco = RegExp(r'scavalcabili:\s*\[([^\]]*)\]')
          .firstMatch(tavolozza);
      expect(elenco, isNotNull,
          reason: 'non trovo `scavalcabili` in Colors.qml: cambiata la forma?');
      final dichiarati = RegExp('"([a-z]+)"')
          .allMatches(elenco!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      final applicati = RegExp(r'_ov\("([a-z]+)"')
          .allMatches(tavolozza)
          .map((m) => m.group(1)!)
          .toSet();

      expect(dichiarati, isNotEmpty);
      expect(dichiarati.difference(applicati), isEmpty,
          reason: 'questi si possono scegliere e non li applica nessuno: '
              'un quadratino che si cambia e non cambia niente');
      expect(applicati.difference(dichiarati), isEmpty,
          reason: 'questi si applicano ma non sono nell\'elenco: il pannello '
              'non li offrirà mai, e nessuno saprà che esistono');
    });

    test('il pannello Aspetto offre esattamente quei colori', () {
      var dir = Directory.current;
      File? f;
      for (var i = 0; i < 4; i++) {
        final c = File('${dir.path}/minerva-shell/settings/sections/'
            'Appearance.qml');
        if (c.existsSync()) {
          f = c;
          break;
        }
        dir = dir.parent;
      }
      expect(f, isNotNull, reason: 'non trovo Appearance.qml');

      final pannello = f!.readAsStringSync();
      final offerti = RegExp(r'"nome":\s*"([a-z]+)"')
          .allMatches(pannello)
          .map((m) => m.group(1)!)
          .toSet();

      final tavolozza = _colorsQml().readAsStringSync();
      final elenco = RegExp(r'scavalcabili:\s*\[([^\]]*)\]')
          .firstMatch(tavolozza)!;
      final dichiarati = RegExp('"([a-z]+)"')
          .allMatches(elenco.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();

      expect(offerti, equals(dichiarati),
          reason: 'il pannello e la tavolozza non dicono gli stessi nomi: '
              'uno scavalcamento offerto e non applicato non fa niente, uno '
              'applicato e non offerto non si può scegliere.');
    });
});
}

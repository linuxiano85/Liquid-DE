// Ogni superficie che scorre dice dove sei, e si può prendere.
//
// ── Il difetto che questa prova esiste per non far tornare ────────────────
//
// Contato il 4 settembre 2026: in tutta la shell c'erano **tre** barre di
// scorrimento, ed erano quelle di serie di Qt — le uniche tre cose in Minerva
// che avessero l'aspetto di un'altra scrivania. Le altre venticinque superfici
// scorrevano alla cieca: la griglia da 311 file, i processi del monitor, i
// fusi orari, il testo dell'editor, tutte e diciotto le pagine delle
// Impostazioni.
//
// Giacomo, quel giorno: «nel file manager manca la barretta laterale che posso
// trascinare con il mouse per spostare la discesa e slitta più velocemente».
//
// Non è un difetto che una prova possa vedere — non c'è nessun errore, c'è
// un'assenza — ma è un difetto che si può impedire di RITORNARE: da qui in poi
// una superficie nuova che scorre senza barra fa diventare rossa questa prova
// il giorno in cui la si scrive, non sei mesi dopo quando qualcuno se ne
// accorge usando il computer.
import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

/// La radice del progetto, risalendo: `dart test` gira sia da `minervad/` sia
/// dalla radice.
Directory _radice() {
  var dir = Directory.current;
  for (var i = 0; i < 4; i++) {
    if (Directory('${dir.path}/minerva-shell').existsSync()) return dir;
    dir = dir.parent;
  }
  fail('non trovo minerva-shell/');
}

/// Il testo senza commenti: un commento che nomina `Scorrimento` non è una
/// barra di scorrimento. Senza questa riga la prova passerebbe grazie alle
/// spiegazioni che raccontano perché la regola esiste.
String _codice(File f) => f
    .readAsLinesSync()
    .where((r) => !r.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final radice = _radice().path;

  // TUTTI i file della shell, e non un elenco di cartelle scritto a mano: il
  // 27 settembre 2026 l'elenco non conteneva `terminale` e `manutenzione`,
  // nate dopo, e in `terminale/Blocchi.qml` c'era proprio la barra di serie
  // di Qt che queste prove vietano. Una cartella nuova non deve poter restare
  // fuori per dimenticanza. Le prove QML (`prove-*.qml`) non sono interfaccia.
  List<File> tuttiIQml() => Directory('$radice/minerva-shell')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.qml'))
      .where((f) {
        final n = f.path.split('/').last;
        return !n.startsWith('prove-') && !n.startsWith('prova-');
      })
      .toList();

  /// Chi scorre, in QML.
  final scorrevoli = RegExp(r'^\s*(Flickable|ListView|GridView)\s*\{',
      multiLine: true);

  /// Le eccezioni, ognuna con il suo perché. Un elenco di eccezioni senza
  /// motivo è un elenco che cresce finché la regola non vale più niente.
  const scusate = {
    'custodia/Custodia.qml':
        'la sua griglia è un Flickable dentro un Component caricato da un '
        'Loader: la barra lo nomina come `corpo.item`, che una regola sul '
        'testo non può seguire. La barra c\'è, fuori dal Loader.',
    'custodia/DentroProgetto.qml':
        'la sua radice È il Flickable, e da dentro un Flickable non si può '
        'disegnare una barra: ogni figlio si sposta insieme al contenuto. '
        'Gliela mette `custodia/Custodia.qml`, che è il suo genitore e tiene '
        'una barra sola per tutte e due le pagine del Loader.',
  };

  test('nessuna superficie scorre senza la sua barra', () {
    // Superficie per superficie, non file per file. Prima bastava che in un
    // file comparisse `Scorrimento` una volta perché ogni elenco dello stesso
    // file fosse assolto: un secondo ListView senza barra, accanto a uno che
    // l'aveva, passava inosservato (provato il 27 settembre 2026 mettendone
    // uno apposta in `files/Transfers.qml`: la prova restava verde).
    //
    // Adesso ogni Flickable, ListView o GridView deve avere un `id`, e nello
    // stesso file una barra che lo nomina: `bersaglio: <id>`.
    final superficie = RegExp(r'^([ \t]*)(Flickable|ListView|GridView)\s*\{',
        multiLine: true);
    final nudi = <String>[];
    var viste = 0;

    for (final f in tuttiIQml()) {
      final nome = f.path.split('minerva-shell/').last;
      if (scusate.containsKey(nome)) continue;
      final testo = _codice(f);
      final righe = testo.split('\n');
      for (final m in superficie.allMatches(testo)) {
        viste++;
        final riga = '\n'.allMatches(testo.substring(0, m.start)).length;
        final rientro = m.group(1)!.length;
        String? id;
        for (final r in righe.skip(riga + 1).take(25)) {
          final mm = RegExp(r'^([ \t]*)id:\s*(\w+)').firstMatch(r);
          if (mm != null && mm.group(1)!.length == rientro + 4) {
            id = mm.group(2);
            break;
          }
        }
        final coperta = id != null &&
            RegExp('bersaglio:\\s*${RegExp.escape(id)}\\b').hasMatch(testo);
        if (!coperta) {
          nudi.add('$nome:${riga + 1}  ${m.group(2)}'
              '${id == null ? " (senza id)" : " «$id»"}');
        }
      }
    }

    // E una prova che non ha visto niente non ha provato niente: se la forma
    // dei file cambia e la regola smette di riconoscere le superfici, deve
    // dirlo invece di passare.
    expect(viste, greaterThan(20),
        reason: 'la regola non riconosce più le superfici che scorrono');
    expect(nudi, isEmpty,
        reason: 'Queste superfici scorrono e non lo dicono: chi le usa non sa '
            'né dove si trova né quanto manca, e non ha niente da afferrare '
            'per andare in fondo in un gesto. Si dà un `id` alla superficie e '
            'le si mette accanto `Ui.Scorrimento { bersaglio: <id> }` come '
            'FRATELLA (mai figlia: i figli di un Flickable si spostano già di '
            '-contentY), oppure si aggiunge il file alle eccezioni motivate qui '
            'sopra.\n${nudi.join('\n')}');
  });

  test('e nessuna usa più quella di serie di Qt', () {
    // Le tre `ScrollBar` di `QtQuick.Controls` erano l'unica cosa in Minerva
    // che non avesse il nostro aspetto: colore, spessore e forma di un'altra
    // scrivania, in mezzo alla nostra.
    final colpe = <String>[];
    {
      for (final f in tuttiIQml()) {
        // Il nome secco no: `ui/Scorrimento.qml` dichiara
        // `Accessible.role: Accessible.ScrollBar`, ed è giusto che lo faccia —
        // è una barra di scorrimento, e chi legge lo schermo deve saperlo. Si
        // cerca l'USO del componente di Qt, non la parola.
        if (RegExp(r'ScrollBar\s*\{|ScrollBar\.(vertical|horizontal)')
            .hasMatch(_codice(f))) {
          colpe.add(f.path.split('minerva-shell/').last);
        }
      }
    }
    expect(colpe, isEmpty,
        reason: 'la barra di Minerva è `ui/Scorrimento.qml`\n'
            '${colpe.join('\n')}');
  });

  test('la barra si ancora fuori dalla superficie, non dentro', () {
    // La trappola è scritta in `editor/Editor.qml`: «i figli di un Flickable
    // stanno dentro il suo contenuto, che si sposta già di `-contentY` per
    // conto proprio». Una barra messa lì dentro scorre via insieme a quello
    // che dovrebbe misurare — ed è già successo una volta, in
    // `files/Transfers.qml`, il giorno stesso in cui la barra è nata.
    //
    // Non si può controllare l'albero QML da qui. Si controlla la cosa che lo
    // rende possibile: che il componente lo dica, per esteso, a chi lo apre.
    final f = File('$radice/minerva-shell/ui/Scorrimento.qml');
    expect(f.existsSync(), isTrue);
    // Qui si cerca apposta in un COMMENTO: la regola deve essere scritta per
    // chi apre il file. Il resto, che è codice, si cerca nel codice vivo.
    expect(f.readAsStringSync(), contains('FUORI'),
        reason: 'chi apre questo file deve trovare subito la regola che gli '
            'evita il difetto');
    expect(f.codiceVivo(), contains('originY'),
        reason: 'un ListView che cresce dal basso — le notifiche — non parte '
            'da zero: senza `originY` il pollice sta sempre in cima');
  });

  // ── I resti del pollice ────────────────────────────────────────────────
  //
  // 4 e 5 settembre 2026, Giacomo: «cosa sono tutti quei segno + in
  // impostazioni?», e il giorno dopo «i segni + ci sono ancora».
  //
  // Non erano segni: erano **i resti del pollice**. Col renderer software un
  // rettangolo alto 87,3 pixel a y = 123,456 non si ridisegna pulito — quando
  // si sposta o cambia lunghezza lascia dietro una riga sottile, e la riga
  // resta. Il pollice cambia tutte e due le cose ogni volta che il contenuto
  // cresce o si accorcia: cambiando set di icone, per esempio, dove compare e
  // sparisce la fila dei temi. Il risultato è una scaletta di trattini a
  // mezz'aria, che spariva solo chiudendo la finestra.
  //
  // Isolato per esclusione: spegnendo `Ui.Scorrimento` la stessa sequenza non
  // produceva niente.
  group('il pollice non lascia resti', () {
    late String comp;
    setUpAll(() => comp = _codice(File(
        '${_radice().path}/minerva-shell/ui/Scorrimento.qml')));

    test('posizione e lunghezza sono numeri interi', () {
      final i = comp.indexOf('id: pollice');
      expect(i, greaterThan(0));
      final corpo = comp.substring(i, i + 900);
      expect(corpo, contains('x: Math.round('),
          reason: 'una posizione frazionaria col renderer software lascia una '
              'riga dietro di sé a ogni spostamento');
      expect(corpo, contains('y: Math.round('));
      expect(comp, contains('return Math.round('),
          reason: 'anche la LUNGHEZZA: cambia a ogni cambio di contenuto');
    });

    test('e la misura non si anima', () {
      final i = comp.indexOf('id: pollice');
      final corpo = comp.substring(i, i + 900);
      expect(corpo, isNot(contains('Behavior on width')),
          reason: 'animare la lunghezza vuol dire ridisegnare il pollice a '
              'decine di misure intermedie, ognuna col suo raggio: ognuna può '
              'lasciare il suo resto');
      expect(corpo, isNot(contains('Behavior on height')));
      expect(corpo, contains('Behavior on color'),
          reason: 'il colore si anima: è quello che non lascia resti');
    });
  });
}

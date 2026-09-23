import 'dart:io';

import 'package:minervad/services/mime_database.dart';
import 'package:minervad/services/mime_service.dart';
import 'package:test/test.dart';

/// Prove sul database dei tipi di freedesktop.
///
/// ── Perché questo file esiste ──────────────────────────────────────────────
///
/// Perché Giacomo ha fatto doppio clic su `joca.sh` e si sono aperte le
/// PROPRIETÀ. La catena si spezzava in un punto solo: `file --mime-type` dice
/// `text/x-shellscript`, il suo `mimeapps.list` dice
/// `application/x-shellscript`, e sono LO STESSO TIPO con due nomi — cosa che
/// sta scritta in `/usr/share/mime/aliases` e che il demone non leggeva.
///
/// ── Perché la base è finta ────────────────────────────────────────────────
///
/// Tre file scritti a mano dentro una cartella temporanea. Provare contro
/// `/usr/share/mime` vero vorrebbe dire che l'esito cambia a seconda di quale
/// versione di `shared-mime-info` è installata sulla macchina che esegue le
/// prove — cioè una prova che un giorno diventa rossa senza che nessuno abbia
/// toccato niente.
///
/// L'ultima prova invece la base VERA la guarda apposta, ed è saltata dove non
/// c'è: serve a controllare che i nomi scritti nella tabella dei gruppi siano
/// quelli canonici, che è l'errore da cui è nato tutto.
void main() {
  late Directory temp;
  late MimeDatabase base;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('minerva-mime-');
    await Directory('${temp.path}/mime').create();

    await File('${temp.path}/mime/globs2').writeAsString('''
# generato a mano per le prove
50:text/x-shellscript:*.sh
50:text/markdown:*.md
10:application/x-sega-pico-rom:*.md
50:application/gzip:*.gz
50:application/x-compressed-tar:*.tar.gz
50:application/xml:*.xml
50:text/x-maven+xml:pom.xml
50:text/x-makefile:Makefile
50:text/x-c++src:*.C:cs
50:text/x-csrc:*.c:cs
50:application/x-troff-man:*.[1-9]
50:application/x-desktop:*.desktop
''');

    await File('${temp.path}/mime/aliases').writeAsString('''
application/x-shellscript text/x-shellscript
text/x-sh text/x-shellscript
''');

    await File('${temp.path}/mime/subclasses').writeAsString('''
text/x-shellscript application/x-executable
text/x-csh text/x-shellscript
''');

    base = MimeDatabase(cartelle: [temp.path]);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  // ── Dal nome al tipo ─────────────────────────────────────────────────────

  group('il nome del file', () {
    test('uno script è uno script', () async {
      expect(await base.perNome('/casa/joca.sh'), 'text/x-shellscript');
    });

    test('il nome intero batte il modello', () async {
      // Chi ha scritto `pom.xml` sta nominando un file preciso, non una
      // famiglia: deve battere `*.xml`.
      expect(await base.perNome('pom.xml'), 'text/x-maven+xml');
      expect(await base.perNome('altro.xml'), 'application/xml');
    });

    test('un nome senza punto vale come modello letterale', () async {
      expect(await base.perNome('/src/Makefile'), 'text/x-makefile');
    });

    test('il modello più lungo vince', () async {
      // Altrimenti un archivio compresso diventa un file compresso e basta.
      expect(await base.perNome('roba.tar.gz'), 'application/x-compressed-tar');
      expect(await base.perNome('roba.gz'), 'application/gzip');
    });

    test('a parità di modello vince il peso', () async {
      // Le due righe vere del database: `.md` è testo per peso 50 e una
      // cartuccia del Sega Pico per peso 10.
      expect(await base.perNome('LEGGIMI.md'), 'text/markdown');
    });

    test('le maiuscole non contano, tranne dove è scritto che contano',
        () async {
      expect(await base.perNome('FOTO.SH'), 'text/x-shellscript');
      // `*.C` e `*.c` sono due linguaggi diversi, e il database lo marca `cs`.
      expect(await base.perNome('main.C'), 'text/x-c++src');
      expect(await base.perNome('main.c'), 'text/x-csrc');
    });

    test('un modello con le parentesi resta un modello', () async {
      expect(await base.perNome('manuale.3'), 'application/x-troff-man');
    });

    test('un nome che non somiglia a niente non inventa un tipo', () async {
      expect(await base.perNome('gradlew'), '');
    });

    test('una base che non c'"'"'è non fa esplodere niente', () async {
      final vuota = MimeDatabase(cartelle: ['/non/esiste/da/nessuna/parte']);
      expect(await vuota.perNome('joca.sh'), '');
      expect(await vuota.canonico('text/plain'), 'text/plain');
      // Le due regole implicite valgono lo stesso: non stanno in nessun file.
      expect(await vuota.catena('text/x-shellscript'),
          contains('text/plain'));
    });
  });

  // ── Alias ────────────────────────────────────────────────────────────────

  group('gli alias', () {
    test('un alias si riduce al nome canonico', () async {
      expect(await base.canonico('application/x-shellscript'),
          'text/x-shellscript');
      expect(await base.canonico('text/x-sh'), 'text/x-shellscript');
    });

    test('un nome che non è alias di niente resta sé stesso', () async {
      expect(await base.canonico('text/plain'), 'text/plain');
    });

    test('dal canonico si risale a tutti i suoi nomi', () async {
      // È questo che permette di trovare una scelta scritta anni fa con il
      // nome vecchio, come nel `mimeapps.list` di Giacomo.
      final nomi = await base.nomiDi('text/x-shellscript');
      expect(nomi, contains('text/x-shellscript'));
      expect(nomi, contains('application/x-shellscript'));
      expect(nomi, contains('text/x-sh'));
    });

    test('i nomi di un alias sono quelli del suo canonico', () async {
      expect(await base.nomiDi('application/x-shellscript'),
          containsAll(['text/x-shellscript', 'text/x-sh']));
    });
  });

  // ── Genitori ─────────────────────────────────────────────────────────────

  group('la parentela dei tipi', () {
    test('il tipo stesso è il primo anello', () async {
      final c = await base.catena('text/x-shellscript');
      expect(c.first, 'text/x-shellscript');
    });

    test('si eredita dal padre scritto nel file', () async {
      expect(await base.catena('text/x-csh'), contains('text/x-shellscript'));
    });

    test('ogni text/ discende da text/plain anche se il file non lo dice',
        () async {
      // LA PROVA DEL DIFETTO. `subclasses` dà a `text/x-shellscript` un solo
      // padre — `application/x-executable` — che nessun `.desktop` dichiara.
      // Senza la regola implicita, uno script resta senza nessuno che lo apra.
      final c = await base.catena('text/x-shellscript');
      expect(c, contains('application/x-executable'));
      expect(c, contains('text/plain'));
    });

    test('la radice è ultima, e solo se la si chiede', () async {
      final con = await base.catena('text/markdown');
      expect(con.last, 'application/octet-stream');
      final senza = await base.catena('text/markdown', conRadice: false);
      expect(senza, isNot(contains('application/octet-stream')));
    });

    test('gli antenati arrivano dal più vicino al più lontano', () async {
      final c = await base.catena('text/x-csh');
      expect(c.indexOf('text/x-shellscript'), lessThan(c.indexOf('text/plain')));
    });

    test('una cartella non ha antenati', () async {
      expect(await base.catena('inode/directory'), ['inode/directory']);
    });

    test('un indirizzo web non è un file e non ha antenati', () async {
      // Senza questa guardia si finirebbe a proporre un editor di testo per
      // aprire `https://…`.
      expect(await base.catena('x-scheme-handler/https'),
          ['x-scheme-handler/https']);
    });

    test('un anello nel file non manda in ciclo la visita', () async {
      final girotondo = await Directory.systemTemp.createTemp('minerva-ciclo-');
      await Directory('${girotondo.path}/mime').create();
      await File('${girotondo.path}/mime/subclasses')
          .writeAsString('a/uno a/due\na/due a/uno\n');
      final b = MimeDatabase(cartelle: [girotondo.path]);
      final c = await b.catena('a/uno');
      expect(c, contains('a/due'));
      expect(c.where((x) => x == 'a/uno').length, 1);
      await girotondo.delete(recursive: true);
    });
  });

  // ── La tabella dei gruppi contro la base vera ────────────────────────────

  test('i tipi dei gruppi sono già scritti col nome canonico', () async {
    // Questa guarda il database VERO, ed è saltata dove non c'è. Serve a
    // fermare l'errore da cui è nato tutto: `application/x-shellscript` scritto
    // nella tabella al posto di `text/x-shellscript`. Un alias funziona lo
    // stesso — adesso — ma è il nome che finisce nel `mimeapps.list` di tutti
    // gli altri ambienti, e lì si scrive quello vero.
    if (!Directory('/usr/share/mime').existsSync()) {
      markTestSkipped('shared-mime-info non è installato');
      return;
    }
    final vera = MimeDatabase();
    final storti = <String>[];
    for (final cat in MimeService.categories) {
      for (final m in (cat['mimes'] as List).cast<String>()) {
        if (m.startsWith('x-scheme-handler/')) continue;
        final c = await vera.canonico(m);
        if (c != m) storti.add('$m → $c');
      }
    }
    expect(storti, isEmpty,
        reason: 'nomi non canonici nella tabella dei gruppi');
  });

  test('ogni gruppo dichiara la famiglia in cui sta', () {
    final famiglie =
        MimeService.famiglie.map((f) => f['id'] as String).toSet();
    for (final cat in MimeService.categories) {
      expect(famiglie, contains(cat['famiglia']),
          reason: 'il gruppo «${cat['id']}» sta in una famiglia che non esiste');
    }
  });
}

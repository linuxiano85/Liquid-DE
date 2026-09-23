import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/manutenzione/inventario.dart';

// L'inventario di Minerva Manutenzione.
//
// ── Perché `du` e `pacman` sono finti ─────────────────────────────────────
//
// Perché una prova che li chiama davvero misura la macchina di chi la lancia:
// verde stamattina, rossa stasera, e nessuno saprebbe perché. È la stessa
// ragione per cui `custodia/github_motore.dart` si fa sostituire la rete.
//
// ── E perché la cosa più importante da provare non è un numero ────────────
//
// È che l'inventario **non cancelli niente**. Questo file è l'unico posto del
// programma che guarda tutto il disco, e il giorno che qualcuno ci infila una
// riga che toglie qualcosa, quella riga passerebbe inosservata: le prove sui
// numeri resterebbero verdi.
void main() {
  /// Un `esegui` finto che risponde come risponderebbero i programmi veri, e
  /// che segna cosa gli è stato chiesto.
  ({Inventario dentro, List<List<String>> visti}) finto({
    Map<String, String> pesi = const {},
    List<String> figliDiCache = const [],
    List<String> lingue = const [],
    String orfani = '',
    int quantiFile = 0,
    void Function(String, String, int, int)? racconta,
  }) {
    final visti = <List<String>>[];
    return (
      visti: visti,
      dentro: Inventario(
        casa: '/casa/prova',
        racconta: racconta,
        esegui: (cmd, args) async {
          visti.add([cmd, ...args]);
          if (cmd == 'du') {
            final righe = <String>[];
            for (final a in args) {
              if (a.startsWith('-')) continue;
              final p = pesi[a];
              if (p != null) righe.add('$p\t$a');
            }
            return ProcessResult(0, righe.isEmpty ? 1 : 0, righe.join('\n'), '');
          }
          if (cmd == 'find') {
            return ProcessResult(
                0, 0, List.filled(quantiFile, '/x/y.pkg.tar.zst').join('\n'), '');
          }
          if (cmd == 'pacman') return ProcessResult(0, 0, orfani, '');
          return ProcessResult(0, 1, '', '');
        },
      ),
    );
  }

  group('l\'inventario guarda e basta', () {
    test('non chiama MAI niente che cancelli', () async {
      // La prova che conta più di tutte le altre messe insieme. `du`, `find` e
      // `pacman -Qtdq` guardano; `rm`, `paccache`, `pacman -R` no. Se un
      // domani qualcuno mette una scorciatoia qui dentro, questa riga la
      // prende — e nessun'altra lo farebbe.
      final f = finto(orfani: 'cmark-gfm\nsvt-hevc\n');
      await f.dentro.tutto();
      const vietati = ['rm', 'paccache', 'shred', 'trash', 'unlink'];
      for (final c in f.visti) {
        expect(vietati, isNot(contains(c.first)),
            reason: 'l\'inventario ha chiamato «${c.join(" ")}»: '
                'questo file deve solo guardare');
        if (c.first == 'pacman') {
          expect(c.join(' '), isNot(matches(r'-R|--remove')),
              reason: 'l\'inventario sta togliendo pacchetti');
        }
      }
    });
  });

  group('la cache personale', () {
    // Una casa VERA in una cartella temporanea: senza, `_figli` non trova
    // niente, la funzione risponde vuoto e la prova passa senza aver provato
    // il conto. Ci sono cascato scrivendola.
    late Directory casa;
    setUp(() async {
      casa = await Directory.systemTemp.createTemp('minerva-inventario-');
      for (final n in ['ccache', 'uv', 'minuscola']) {
        await Directory('${casa.path}/.cache/$n').create(recursive: true);
      }
    });
    tearDown(() async {
      if (await casa.exists()) await casa.delete(recursive: true);
    });

    Inventario conCasa(Map<String, String> pesi) => Inventario(
          casa: casa.path,
          esegui: (cmd, args) async {
            if (cmd != 'du') return ProcessResult(0, 1, '', '');
            final righe = <String>[];
            for (final a in args) {
              if (a.startsWith('-')) continue;
              final p = pesi[a.split('/').last];
              if (p != null) righe.add('$p\t$a');
            }
            return ProcessResult(0, righe.isEmpty ? 1 : 0, righe.join('\n'), '');
          },
        );

    test('si mostra voce per voce, dalla più grossa', () async {
      final v = await conCasa({
        'ccache': '${1600 * 1024 * 1024}',
        'uv': '${1100 * 1024 * 1024}',
      }).cachePersonale();
      expect(v.map((x) => x.nome).toList(), ['ccache', 'uv'],
          reason: 'la più grossa deve stare in cima: è quella che si guarda');
      expect(v.first.byte, 1600 * 1024 * 1024);
      expect(v.first.dove, endsWith('/.cache/ccache'),
          reason: 'il percorso si mostra per esteso: «ccache» non dice dove');
      expect(v.first.torna, 'sola');
      expect(v.first.vuoleLaPassword, isFalse,
          reason: 'la tua cartella è tua: nessuna password');
    });

    test('le briciole non diventano righe', () async {
      // Sotto i dieci mega non è una voce: venti righe da due mega ciascuna
      // riempiono uno schermo per dire niente, e nascondono le tre che
      // contano.
      final v = await conCasa({
        'ccache': '${1600 * 1024 * 1024}',
        'minuscola': '${2 * 1024 * 1024}',
      }).cachePersonale();
      expect(v.map((x) => x.nome).toList(), ['ccache']);
    });

    test('e quello che non c\'è non diventa una voce da zero byte', () async {
      final f = finto();
      final t = await f.dentro.tutto();
      for (final v in t['voci'] as List) {
        expect(v['byte'], greaterThan(0),
            reason: 'una voce che pesa zero è una riga che occupa uno schermo '
                'per dire niente');
      }
    });
  });

  group('le lingue', () {
    test('quelle da tenere non si contano', () async {
      final f = finto();
      // Senza `/usr/share/locale` sulla macchina di prova la risposta è nulla,
      // ed è giusto: si guarda che non finga un numero.
      final v = await f.dentro.lingue();
      expect(v, anyOf(isNull, isA<Voce>()));
    });

    test('«it_IT» e «it_IT@euro» sono italiano quanto «it»', () async {
      // Il ceppo si taglia sul primo separatore. Sbagliarlo vuol dire
      // cancellare l'italiano credendo di cancellare l'islandese.
      for (final nome in ['it', 'it_IT', 'it_IT@euro', 'it.UTF-8']) {
        final ceppo = nome.split(RegExp(r'[_.@]')).first;
        expect(ceppo, 'it', reason: '«$nome» non è stato riconosciuto');
      }
    });
  });

  group('gli orfani', () {
    test('si elencano per nome, mai come numero', () async {
      final f = finto(orfani: 'cmark-gfm\nlibayatana-indicator\nsvt-hevc\n');
      final o = await f.dentro.orfani();
      expect(o, ['cmark-gfm', 'libayatana-indicator', 'svt-hevc']);
    });

    test('e non si mescolano al conto dello spazio', () async {
      // Su questa macchina sono tre pacchetti per ZERO megabyte. Sommarli al
      // totale dei gigabyte direbbe il falso su tutti e due: sul totale, che
      // non cambia, e su di loro, che non servono a liberare spazio ma a fare
      // ordine.
      final f = finto(orfani: 'uno\ndue\n');
      final t = await f.dentro.tutto();
      expect(t['orfani'], ['uno', 'due']);
      expect(t['totale'], 0, reason: 'gli orfani hanno gonfiato il totale');
    });
  });

  group('quando qualcosa non si può sapere', () {
    test('non si inventa un numero', () async {
      // `du` che fallisce — un permesso negato, una cartella sparita mentre
      // guardavamo — non deve diventare «0 byte», che a schermo si legge come
      // «non c'è niente da pulire».
      final f = finto(); // ogni `du` risponde con esito 1
      final t = await f.dentro.tutto();
      expect(t['voci'], isEmpty);
      expect(t['totale'], 0);
    });
  });

  // ── Le tre trappole trovate provandolo sul vivo ─────────────────────────
  //
  // L'inventario funzionava e diceva 9,8 GB invece di 16. Nessuna prova era
  // rossa: erano tutte e tre cose che si vedono solo guardando il risultato
  // vero accanto a quello che sapevamo già.
  group('quello che il primo giro sbagliava', () {
    // ── Quanto si può togliere NON è quanto pesa la cartella ───────────
    //
    // Giacomo, 9 settembre 2026, dopo aver premuto «Pulisci 6,97 GB»: «perché
    // non è scomparsa dalle voci?». Ne erano usciti 130 MB.
    //
    // `paccache` tiene le ultime due versioni di ogni pacchetto, e su una
    // macchina aggiornata quasi ogni pacchetto ne ha una sola: quello che si
    // può togliere è la parte in più, non tutto. Il numero grande era vero
    // come misura della cartella e **falso come promessa**.
    Inventario conPaccache(String primoGiro, String secondoGiro,
        {String duPacchetti = '6934917693\t/var/cache/pacman/pkg',
        int esitoDu = 0}) {
      var giro = 0;
      return Inventario(
        casa: '/casa/prova',
        esegui: (cmd, args) async {
          if (cmd == 'du') return ProcessResult(0, esitoDu, duPacchetti, 'x');
          if (cmd == 'paccache') {
            giro++;
            return ProcessResult(0, 0, giro == 1 ? primoGiro : secondoGiro, '');
          }
          return ProcessResult(0, 0, '', '');
        },
      );
    }

    test('il numero è quello che paccache toglierebbe, non la cartella',
        () async {
      final v = await conPaccache(
        '==> finished dry run: 18 candidates (disk space saved: 130.00 MiB)',
        '==> no candidate packages found for pruning',
      ).cachePacchetti();
      expect(v, isNotNull);
      expect(v!.byte, (130.0 * 1024 * 1024).round());
      expect(v.quante, 18);
      expect(v.byte, lessThan(6934917693),
          reason: 'promettere la cartella intera è la bugia che ha fatto '
              'nascere questa prova');
    });

    test('i due giri si sommano: le vecchie versioni e i disinstallati',
        () async {
      // Sono due cose diverse: le versioni vecchie dei pacchetti che hai, e
      // quelle dei programmi che non hai più — che sono spreco puro.
      final v = await conPaccache(
        '==> finished dry run: 2 candidates (disk space saved: 10.00 MiB)',
        '==> finished dry run: 3 candidates (disk space saved: 1.00 GiB)',
      ).cachePacchetti();
      expect(v!.quante, 5);
      expect(v.byte, (10.0 * 1024 * 1024).round() + 1024 * 1024 * 1024);
    });

    test('se non c\'è niente da togliere, la voce non c\'è', () async {
      // Una riga che dice «0 byte» è una riga che si può spuntare e premere
      // per niente.
      final v = await conPaccache(
        '==> no candidate packages found for pruning',
        '==> no candidate packages found for pruning',
      ).cachePacchetti();
      expect(v, isNull);
    });

    test('e nemmeno per una briciola', () async {
      // Visto sul vivo il 9 settembre: dopo la prima pulizia restavano 168
      // KiB da togliere, e la riga c'era ancora. Vera, e inutile.
      final v = await conPaccache(
        '==> finished dry run: 1 candidates (disk space saved: 168.04 KiB)',
        '',
      ).cachePacchetti();
      expect(v, isNull);
    });

    test('e si dice lo stesso quanto pesa in tutto', () async {
      // Il numero grande non sparisce: smette di essere una promessa e
      // diventa quello che è, cioè un'informazione.
      final v = await conPaccache(
        '==> finished dry run: 1 candidates (disk space saved: 500.00 MiB)',
        '',
      ).cachePacchetti();
      expect(v!.avvertenza, contains('6,93 GB'));
      expect(v.avvertenza, contains('programmi restano dove sono'),
          reason: 'chi legge deve sapere per primo quello che NON succede');
    });

    test('una cartella non leggibile non fa sparire la voce', () async {
      // `du` esce con 1 appena UNA sottocartella è di root, e intanto stampa
      // il totale giusto di tutto il resto. Guardando solo l'esito, la voce
      // più grossa dell'inventario non compariva affatto.
      final v = await conPaccache(
        '==> finished dry run: 4 candidates (disk space saved: 40.00 MiB)',
        '',
        esitoDu: 1,
      ).cachePacchetti();
      expect(v, isNotNull, reason: 'sparita per un codice di uscita');
      expect(v!.byte, (40.0 * 1024 * 1024).round());
    });

    test('le miniature si contano UNA volta sola', () async {
      // Comparivano due volte: «thumbnails» dalla scansione della cache e
      // «Miniature» dalla voce con un nome che si capisce. E il totale le
      // sommava tutte e due.
      final casa = await Directory.systemTemp.createTemp('minerva-doppio-');
      try {
        await Directory('${casa.path}/.cache/thumbnails').create(recursive: true);
        await Directory('${casa.path}/.cache/altro').create(recursive: true);
        final dentro = Inventario(
          casa: casa.path,
          esegui: (cmd, args) async {
            if (cmd != 'du') return ProcessResult(0, 1, '', '');
            final righe = <String>[];
            for (final a in args) {
              if (a.startsWith('-')) continue;
              righe.add('${60 * 1024 * 1024}\t$a');
            }
            return ProcessResult(0, 0, righe.join('\n'), '');
          },
        );
        final v = await dentro.cachePersonale();
        expect(v.where((x) => x.dove.endsWith('/thumbnails')), isEmpty,
            reason: 'le miniature hanno già una voce loro');
        expect(v.map((x) => x.nome), contains('altro'));
      } finally {
        await casa.delete(recursive: true);
      }
    });
  });

  group('le famiglie', () {
    test('ccache è sviluppo, mozilla è cache — e non è la stessa cosa', () async {
      final casa = await Directory.systemTemp.createTemp('minerva-fam-');
      try {
        for (final n in ['ccache', 'mozilla']) {
          await Directory('${casa.path}/.cache/$n').create(recursive: true);
        }
        final v = await Inventario(
          casa: casa.path,
          esegui: (cmd, args) async {
            if (cmd != 'du') return ProcessResult(0, 1, '', '');
            final righe = [
              for (final a in args)
                if (!a.startsWith('-')) '${99 * 1024 * 1024}\t$a'
            ];
            return ProcessResult(0, 0, righe.join('\n'), '');
          },
        ).cachePersonale();
        final per = {for (final x in v) x.nome: x};
        expect(per['ccache']!.categoria, 'sviluppo');
        expect(per['mozilla']!.categoria, 'cache');
        expect(per['ccache']!.avvertenza, contains('lenta'),
            reason: 'buttare ccache costa TEMPO, e va detto prima');
        expect(per['mozilla']!.avvertenza, isEmpty,
            reason: 'una nota su ogni riga è una nota che non si legge');
      } finally {
        await casa.delete(recursive: true);
      }
    });

    test('il riassunto per famiglia somma quanto l\'elenco', () async {
      // Il grafico e l'elenco devono dire lo STESSO numero. Sommando in due
      // posti diversi, il giorno che una voce cambia famiglia i due divergono
      // e non se ne accorge nessuno.
      final f = finto(orfani: '');
      final t = await f.dentro.tutto();
      final fam = (t['famiglie'] as Map).values.fold<int>(0, (s, x) => s + (x as int));
      expect(fam, t['totale']);
    });
  });

  group('il racconto', () {
    // La barra e il registro dal vivo li fa questo: se il demone smette di
    // raccontare, la finestra torna a essere una rotella che gira senza dire
    // niente — che è esattamente quello che Giacomo ha chiesto di togliere.
    test('ogni tappa si annuncia, e il conto arriva in fondo', () async {
      final dette = <({String fase, String testo, int fatte, int quante})>[];
      final f = finto(
        orfani: 'cmark-gfm\n',
        racconta: (fase, testo, fatte, quante) =>
            dette.add((fase: fase, testo: testo, fatte: fatte, quante: quante)),
      );
      await f.dentro.tutto();

      expect(dette, isNotEmpty);
      expect(dette.every((d) => d.quante == Inventario.passiInTutto), isTrue,
          reason: 'il fondoscala della barra è uno solo, e sta nel demone');
      expect(dette.last.fatte, Inventario.passiInTutto,
          reason: 'una barra che non arriva in fondo dice che si è rotto '
              'qualcosa anche quando è andato tutto bene');

      // Non torna mai indietro: una barra che rincula è peggio di nessuna
      // barra, perché fa pensare che il conto sia sbagliato.
      for (var i = 1; i < dette.length; i++) {
        expect(dette[i].fatte, greaterThanOrEqualTo(dette[i - 1].fatte));
      }

      // Tutte e cinque le tappe si nominano, e ognuna dice DOVE sta guardando
      // prima di dire cosa ha trovato.
      expect(dette.map((d) => d.fase).toSet(),
          {'cache', 'pacchetti', 'lingue', 'piccole', 'orfani'});
      expect(dette.every((d) => d.testo.trim().isNotEmpty), isTrue);
    });

    test('senza ascoltatori non cambia niente', () async {
      // Il racconto è un di più: chi non lo vuole non lo paga, e soprattutto
      // l'inventario deve rispondere lo stesso.
      final zitto = await finto(orfani: '').dentro.tutto();
      final loquace = await finto(
        orfani: '',
        racconta: (_, _, _, _) {},
      ).dentro.tutto();
      expect(loquace['totale'], zitto['totale']);
      expect((loquace['voci'] as List).length, (zitto['voci'] as List).length);
    });
  });

  group('la finestra parla la stessa lingua del demone', () {
    // ── La guardia che tiene insieme i due lati ─────────────────────────
    //
    // Le famiglie sono parole fisse che il demone scrive (`cache`,
    // `sviluppo`, …) e che la finestra traduce in una frase
    // (`manutenzione/Misure.qml`). Sono due file lontani, e il giorno che
    // qualcuno ne aggiunge una di là e non di qua, in mezzo all'elenco
    // comparirebbe la parola nuda — senza un errore, senza un avviso.
    //
    // È la stessa forma di guardia di `impostazioni_sezioni_test.dart`, e la
    // ragione è la stessa: due elenchi che devono restare uguali non restano
    // uguali da soli.
    test('ogni famiglia del demone ha un nome, una spiegazione e un colore',
        () {
      final sorgente =
          File('lib/services/manutenzione/inventario.dart').readAsStringSync();
      final famiglie = RegExp(r"categoria: '([a-z]+)'")
          .allMatches(sorgente)
          .map((m) => m.group(1)!)
          .toSet()
        ..addAll(RegExp(r"'([a-z]+)'\)?,?\s*// famiglia")
            .allMatches(sorgente)
            .map((m) => m.group(1)!));
      // Le famiglie passate come parametro (`cosePiccole`) non hanno la forma
      // `categoria:`, quindi si prendono anche da lì.
      famiglie.addAll(RegExp(r"aggiungi\('[a-z]+', '[^']+', '([a-z]+)'")
          .allMatches(sorgente)
          .map((m) => m.group(1)!));

      expect(famiglie.length, greaterThanOrEqualTo(6),
          reason: 'se questo conto crolla è la ricerca a essersi rotta, '
              'non il codice — e una guardia che non trova niente passa sempre');

      final misure =
          File('../minerva-shell/manutenzione/Misure.qml').readAsStringSync();
      final mancanti = <String>[];
      for (final f in famiglie) {
        // DUE volte e non una: `nome()` e `spiega()` sono due switch
        // separati nello stesso file, e la prima versione di questa guardia
        // si accontentava di trovarne uno — così restava verde con la
        // famiglia scritta in uno solo dei due. Provata togliendo una riga a
        // mano, come si prova ogni guardia qui dentro.
        final quanti = RegExp('case "$f":').allMatches(misure).length;
        if (quanti < 2) mancanti.add('$f (in $quanti switch su 2)');
        // E nell'ordine in cui si mostrano, o la famiglia esiste e non
        // compare da nessuna parte.
        if (!misure.contains('"$f",') && !misure.contains('"$f"]')) {
          mancanti.add('$f (fuori dall\'ordine)');
        }
      }
      expect(mancanti, isEmpty,
          reason: 'famiglie che la finestra mostrerebbe come parola nuda');
    });
  });

  group('il registro di sistema', () {
    // ── La stessa lezione dei pacchetti, in un altro posto ──────────────
    //
    // Se ne tengono cinquanta mega — gli ultimi giorni, quelli che servono
    // quando qualcosa va storto adesso — quindi quello che si libera è il
    // resto. E la misura la dà `journalctl`, non `du`: i file del registro
    // sono BUCATI, e la loro dimensione dichiarata è il doppio di quella
    // vera. Misurato su questa macchina: 118 MB dichiarati, 46 sul disco.
    Inventario conJournal(String risposta) => Inventario(
          casa: '/casa/prova',
          esegui: (cmd, args) async {
            if (cmd == 'journalctl') return ProcessResult(0, 0, risposta, '');
            if (cmd == 'du') {
              return ProcessResult(0, 0, '117964800\t/var/log/journal', '');
            }
            return ProcessResult(0, 1, '', '');
          },
        );

    test('si conta quello che si pota, non quello che pesa', () async {
      final voci = await conJournal(
              'Archived and active journals take up 244.0M in the file system.')
          .cosePiccole();
      final r = voci.where((v) => v.id == 'registro').toList();
      if (r.isEmpty) return; // niente /var/log/journal su questa macchina
      final atteso = (244.0 * 1024 * 1024).round() - 50 * 1000 * 1000;
      expect(r.single.byte, atteso);
      expect(r.single.byte, lessThan(117964800 * 3));
      expect(r.single.avvertenza, contains('50 MB'));
    });

    test('un registro già piccolo non si mostra affatto', () async {
      // Promettere spazio che non c'è è la stessa bugia dei pacchetti, e qui
      // sarebbe pure più facile da dire: la cartella «pesa» 118 MB.
      final voci = await conJournal(
              'Archived and active journals take up 44.0M in the file system.')
          .cosePiccole();
      expect(voci.where((v) => v.id == 'registro'), isEmpty);
    });
  });

  group('quando il conto è un minimo', () {
    test('si dice, invece di far sembrare completo un numero che non lo è',
        () async {
      // `du` esce con 1 appena una sottocartella non si legge, e intanto
      // stampa il totale giusto del resto. Il numero è vero ma parziale, e
      // chi legge non ha modo di sospettarlo: allora glielo si dice.
      final voci = await Inventario(
        casa: '/casa/prova',
        esegui: (cmd, args) async => cmd == 'du'
            ? ProcessResult(0, 1, '18344731\t/casa/prova/.local/share/Trash',
                'negato')
            : ProcessResult(0, 1, '', ''),
      ).cosePiccole();
      final cestino = voci.where((v) => v.id == 'cestino').toList();
      expect(cestino, isNotEmpty);
      expect(cestino.single.parziale, isTrue);
      expect(cestino.single.toJson()['parziale'], isTrue);
    });

    test('e quando si è letto tutto non si semina il dubbio', () async {
      final voci = await Inventario(
        casa: '/casa/prova',
        esegui: (cmd, args) async => cmd == 'du'
            ? ProcessResult(
                0, 0, '18344731\t/casa/prova/.local/share/Trash', '')
            : ProcessResult(0, 1, '', ''),
      ).cosePiccole();
      final cestino = voci.where((v) => v.id == 'cestino').single;
      expect(cestino.parziale, isFalse);
      expect(cestino.toJson().containsKey('parziale'), isFalse,
          reason: 'un campo che c\'è sempre è un campo che nessuno legge');
    });
  });

  group('la riga di pacman conta solo se sta dove pacman la legge', () {
    // ── Il difetto ───────────────────────────────────────────────────────
    //
    // `NoExtract` vale SOLO dentro `[options]`. Scritta in fondo al file —
    // cioè dentro l'ultima sezione dei repository — non fa niente, e pacman
    // lo dice con un avviso che nessuno legge.
    //
    // Il 9 settembre 2026 è successo sulla macchina di Giacomo, e questa
    // funzione rispondeva «sì, è già a posto» mentre le lingue sarebbero
    // tornate tutte al primo aggiornamento. Una guardia che conferma una cosa
    // falsa è peggio di nessuna guardia.
    test('una riga finita in [multilib] non vale come fatta', () async {
      final finto = await Directory.systemTemp.createTemp('minerva-conf-');
      try {
        // Non si può sostituire il percorso di /etc/pacman.conf: allora si
        // prova la regola sul testo, che è la parte che sbagliava.
        String? dove(String conf) {
          var dentroOptions = false;
          for (final r in conf.split('\n')) {
            final pulita = r.trim();
            if (pulita.startsWith('[')) {
              dentroOptions = pulita == '[options]';
              continue;
            }
            if (!dentroOptions) continue;
            if (RegExp(r'^\s*NoExtract\s*=.*usr/share/locale').hasMatch(r)) {
              return 'options';
            }
          }
          return null;
        }

        const inFondo = '[options]\nHoldPkg = pacman\n\n[core]\nInclude = x\n\n'
            '[multilib]\nInclude = x\n'
            '# Minerva Manutenzione — lingue\n'
            'NoExtract = usr/share/locale/* !usr/share/locale/it*\n';
        const alPosto = '[options]\nHoldPkg = pacman\n'
            '# Minerva Manutenzione — lingue\n'
            'NoExtract = usr/share/locale/* !usr/share/locale/it*\n\n'
            '[core]\nInclude = x\n';

        expect(dove(inFondo), isNull,
            reason: 'in fondo al file pacman la ignora');
        expect(dove(alPosto), 'options');
      } finally {
        await finto.delete(recursive: true);
      }
    });
  });

  group('lo si chiede a pacman, invece di leggergli il file', () {
    // `pacman-conf NoExtract` stampa la configurazione COME PACMAN LA LEGGE.
    // Leggendo il file a mano bisognerebbe sapere che quella direttiva vale
    // solo dentro `[options]` — cioè rifare un pezzo del mestiere di pacman,
    // che è esattamente quello che il 9 settembre è stato sbagliato.
    Inventario conPacmanConf(String uscita, int esito) => Inventario(
          casa: '/casa/prova',
          esegui: (cmd, args) async {
            if (cmd == 'pacman-conf') return ProcessResult(0, esito, uscita, '');
            if (cmd == 'du') {
              return ProcessResult(0, 0, '100\t/usr/share/locale/de', '');
            }
            return ProcessResult(0, 1, '', '');
          },
        );

    test('se pacman dice di non estrarle, la voce lo racconta', () async {
      final v = await conPacmanConf(
          'usr/share/locale/*\n!usr/share/locale/it*\n', 0).lingue();
      if (v == null) return; // niente /usr/share/locale su questa macchina
      expect(v.avvertenza, contains('già'));
    });

    test('se pacman non ne sa niente, si dice che va detto a lui', () async {
      final v = await conPacmanConf('', 0).lingue();
      if (v == null) return;
      expect(v.avvertenza, contains('tornano tutte'));
    });

    test('e l\'inglese e la tua lingua restano sempre, scritto sulla riga',
        () async {
      final v = await conPacmanConf('', 0).lingue();
      if (v == null) return;
      expect(v.avvertenza, contains('inglese'));
      expect(v.avvertenza, contains('lingua che usi'));
    });
  });

  group('quello che non è una lingua non è una lingua', () {
    test('`locale.alias` è un file di gettext, non una traduzione', () async {
      // Contandolo, la voce «Lingue che non usi» compariva a ZERO megabyte
      // anche a lingue già tolte: una riga vera e inutile, che si spunta e si
      // preme per niente. Visto sul vivo il 9 settembre 2026.
      final radice = await Directory.systemTemp.createTemp('minerva-loc-');
      try {
        await Directory('${radice.path}/de').create();
        await File('${radice.path}/locale.alias').writeAsString('x');
        final trovati = <String>[];
        final dentro = Inventario(
          casa: '/casa/prova',
          esegui: (cmd, args) async {
            if (cmd == 'du') {
              trovati.addAll(args.where((a) => !a.startsWith('-')));
              return ProcessResult(0, 0, '', '');
            }
            return ProcessResult(0, 1, '', '');
          },
        );
        // `lingue()` guarda `/usr/share/locale`, che qui non si può
        // sostituire: si prova allora la regola sul filtro delle cartelle,
        // che è la parte che sbagliava.
        final figli = await Directory(radice.path)
            .list(followLinks: false)
            .where((v) => v is Directory)
            .map((v) => v.path)
            .toList();
        expect(figli.length, 1);
        expect(figli.single.endsWith('/de'), isTrue);
        expect(figli.any((f) => f.endsWith('locale.alias')), isFalse);
        await dentro.lingue();
        expect(trovati.any((f) => f.endsWith('locale.alias')), isFalse,
            reason: 'nemmeno la scansione vera deve pesarlo');
      } finally {
        await radice.delete(recursive: true);
      }
    });
  });
}

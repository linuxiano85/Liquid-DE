import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/manutenzione/inventario.dart';
import 'package:minervad/services/manutenzione/pulitore.dart';

// Il pulitore di Minerva Manutenzione.
//
// ── Perché l'inventario qui è un finto scritto a mano ─────────────────────
//
// Perché quello vero legge il disco vero, e su una macchina di prova
// risponderebbe «non c'è niente» — cioè il pulitore non cancellerebbe niente
// e ogni prova sarebbe verde **per il motivo sbagliato**. È l'errore che
// questo progetto ha già fatto più di una volta: un'impalcatura più comoda
// della realtà non prova la realtà.
//
// Con un inventario scritto a mano si possono invece mettere sul tavolo
// proprio le voci che non devono essere toccate: una fuori dalla tua
// cartella, una che chiede la password, una che punta alla radice di
// `.cache`. Nessun file vero viene toccato: la cancellazione è sostituita, e
// ogni prova guarda **cosa avrebbe cancellato**.
class InventarioFinto extends Inventario {
  InventarioFinto(this.voci, {super.casa = '/casa'});

  final List<Map<String, dynamic>> voci;

  @override
  Future<Map<String, dynamic>> tutto() async => {
        'voci': voci,
        'famiglie': const <String, int>{},
        'totale': voci.fold<int>(0, (s, v) => s + (v['byte'] as int)),
        'orfani': const <String>[],
      };
}

Map<String, dynamic> voce(String id, String dove, int byte,
        {bool password = false}) =>
    {
      'id': id,
      'nome': id,
      'categoria': 'cache',
      'dove': dove,
      'byte': byte,
      'quante': 0,
      'torna': 'sola',
      'vuoleLaPassword': password,
    };

void main() {
  ({Pulitore dentro, List<String> tolti}) pulitoreCon(
      List<Map<String, dynamic>> voci) {
    final tolti = <String>[];
    return (
      tolti: tolti,
      dentro: Pulitore(
        casa: '/casa',
        inventario: InventarioFinto(voci),
        togli: (percorso) async => tolti.add(percorso),
      ),
    );
  }

  group('toglie quello che è stato mostrato', () {
    test('e lo toglie davvero', () async {
      final p = pulitoreCon([voce('cache:mozilla', '/casa/.cache/mozilla', 99)]);
      final r = await p.dentro.pulisci(['cache:mozilla']);
      expect(p.tolti, ['/casa/.cache/mozilla']);
      expect(r['liberati'], 99);
      expect(r['quante'], 1);
    });

    test('e solo quello: le altre voci restano dove sono', () async {
      // La spunta è una scelta voce per voce, e il pulitore la deve
      // rispettare alla lettera. Se togliesse «già che c'è» anche il resto
      // della famiglia, la spunta non vorrebbe dire niente.
      final p = pulitoreCon([
        voce('cache:mozilla', '/casa/.cache/mozilla', 99),
        voce('cache:ccache', '/casa/.cache/ccache', 500),
      ]);
      await p.dentro.pulisci(['cache:mozilla']);
      expect(p.tolti, ['/casa/.cache/mozilla']);
    });
  });

  group('il cancello dei posti', () {
    test('fuori dalla tua cartella non si tocca niente', () async {
      // La voce è nell'inventario, ha il suo identificativo giusto e NON
      // chiede la password: tutto in regola tranne il posto. Deve bastare
      // quello. È la guardia che protegge dal giorno in cui l'inventario
      // imparerà a mostrare una cartella nuova e nessuno si ricorderà di
      // guardare qui.
      final p = pulitoreCon([voce('roba', '/etc/importante', 10)]);
      final r = await p.dentro.pulisci(['roba']);
      expect(p.tolti, isEmpty);
      final fatte = (r['fatte'] as List).cast<Map<String, dynamic>>();
      expect(fatte.single['ok'], isFalse);
      expect(r['liberati'], 0);
    });

    test('nemmeno risalendo con i due punti', () async {
      final p = pulitoreCon([voce('roba', '/casa/.cache/../../etc', 10)]);
      await p.dentro.pulisci(['roba']);
      expect(p.tolti, isEmpty);
    });

    test('la cartella `.cache` intera non è un posto permesso', () async {
      // Toglierla vorrebbe dire portarsi via anche quello che l'elenco non
      // mostra: le briciole sotto i dieci mega, che non sono mai state
      // messe sotto gli occhi di nessuno.
      final p = pulitoreCon([voce('tutta', '/casa/.cache', 9000)]);
      await p.dentro.pulisci(['tutta']);
      expect(p.tolti, isEmpty);
    });

    test('e la radice men che meno', () async {
      final p = pulitoreCon([voce('radice', '/', 9000), voce('casa', '/casa', 1)]);
      await p.dentro.pulisci(['radice', 'casa']);
      expect(p.tolti, isEmpty);
    });
  });

  group('quello che chiede la password', () {
    test('si lascia dov\'è, e si dice perché', () async {
      final p = pulitoreCon([
        voce('cache-pacchetti', '/var/cache/pacman/pkg', 6900000000,
            password: true),
      ]);
      final r = await p.dentro.pulisci(['cache-pacchetti']);
      expect(p.tolti, isEmpty);
      final fatte = (r['fatte'] as List).cast<Map<String, dynamic>>();
      expect(fatte.single['ok'], isFalse);
      expect('${fatte.single['perche']}', contains('password'));
      expect(r['liberati'], 0,
          reason: 'contarli fra i liberati sarebbe la bugia più facile');
    });
  });

  group('gli identificativi che non esistono', () {
    test('non cancellano niente, e non sono un errore', () async {
      // Fra il momento in cui hai guardato l'elenco e il momento in cui premi
      // possono passare minuti: una cache può essersi svuotata da sola.
      final p = pulitoreCon([voce('cache:mozilla', '/casa/.cache/mozilla', 99)]);
      final r = await p.dentro.pulisci(['cache:sparita', '/etc/passwd']);
      expect(p.tolti, isEmpty);
      expect(r['ok'], isTrue);
      expect(r['liberati'], 0);
    });

    test('senza spunte non fa niente e lo dice', () async {
      final p = pulitoreCon([]);
      final r = await p.dentro.pulisci([]);
      expect(p.tolti, isEmpty);
      expect(r['ok'], isFalse);
      expect(r['errore'], isNotEmpty);
    });
  });

  group('i megabyte promessi', () {
    test('non si contano quelli che non si sono potuti togliere', () async {
      final p = Pulitore(
        casa: '/casa',
        inventario:
            InventarioFinto([voce('cache:x', '/casa/.cache/x', 12345678)]),
        togli: (percorso) async => throw const PathAccessException(
            '/casa/.cache/x', OSError('negato', 13)),
      );
      final r = await p.pulisci(['cache:x']);
      expect(r['liberati'], 0);
      expect(r['nonRiuscite'], 1);
      final fatte = (r['fatte'] as List).cast<Map<String, dynamic>>();
      expect('${fatte.single['perche']}', contains('permesso'));
    });
  });

  group('il racconto della pulizia', () {
    test('dice una riga per voce, e arriva in fondo', () async {
      final dette = <({String testo, int fatte, int quante})>[];
      final p = Pulitore(
        casa: '/casa',
        inventario: InventarioFinto([
          voce('cache:a', '/casa/.cache/a', 10),
          voce('cache:b', '/casa/.cache/b', 20),
        ]),
        togli: (percorso) async {},
        racconta: (fase, testo, fatte, quante) =>
            dette.add((testo: testo, fatte: fatte, quante: quante)),
      );
      await p.pulisci(['cache:a', 'cache:b']);
      // Il registro di una cancellazione è l'unica prova di cosa è stato
      // toccato: se sparisce, resta solo la parola del programma.
      expect(dette.length, greaterThanOrEqualTo(3));
      expect(dette.last.fatte, dette.last.quante);
      expect(dette.any((d) => d.testo.contains('cache:a')), isTrue);
      expect(dette.any((d) => d.testo.contains('cache:b')), isTrue);
    });
  });

  group('quello che chiede la password passa dall\'aiutante di root', () {
    ({Pulitore dentro, List<(String, List<String>)> chieste})
        conAiutante(List<Map<String, dynamic>> voci,
            {bool ok = true, bool annullato = false}) {
      final chieste = <(String, List<String>)>[];
      return (
        chieste: chieste,
        dentro: Pulitore(
          casa: '/casa',
          inventario: InventarioFinto(voci),
          togli: (percorso) async =>
              throw StateError('non deve toccare niente da sé'),
          radice: (operazione, argomenti) async {
            chieste.add((operazione, argomenti));
            if (annullato) return {'ok': false, 'annullato': true};
            return ok ? {'ok': true} : {'ok': false, 'error': 'no'};
          },
        ),
      );
    }

    test('ogni voce ha il SUO verbo, e nessuno è generico', () async {
      final p = conAiutante([
        voce('cache-pacchetti', '/var/cache/pacman/pkg', 6900000000,
            password: true),
        voce('lingue', '/usr/share/locale', 360000000, password: true),
        voce('registro', '/var/log/journal', 118000000, password: true),
      ]);
      final r = await p.dentro.pulisci(['cache-pacchetti', 'lingue', 'registro']);

      final verbi = p.chieste.map((c) => c.$1).toList();
      expect(verbi,
          ['pulisci-cache-pacchetti', 'pulisci-lingue', 'pulisci-registro']);
      // Nessun percorso finisce mai negli argomenti: il verbo dice cosa fare,
      // non dove. È la differenza fra questo e un `pulisci <percorso>`.
      for (final c in p.chieste) {
        for (final a in c.$2) {
          expect(a, isNot(contains('/')), reason: 'un percorso in «${c.$1}»');
        }
      }
      expect(r['quante'], 3);
      expect(r['liberati'], 6900000000 + 360000000 + 118000000);
    });

    test('le lingue si chiedono per quelle da TENERE, mai da togliere',
        () async {
      // Se un domani quell'elenco arrivasse storto o vuoto, il peggio che può
      // succedere è che non si tolga niente. Al contrario — un elenco storto
      // di cose da togliere — è un disastro.
      final p = conAiutante([
        voce('lingue', '/usr/share/locale', 360000000, password: true),
      ]);
      await p.dentro.pulisci(['lingue']);
      final tenere = p.chieste.single.$2;
      expect(tenere, contains('en'),
          reason: 'senza inglese mezzo software del mondo resta muto');
      expect(tenere, contains('C'),
          reason: '«C» non è una lingua: è il ripiego di chi non trova la sua');
      expect(tenere.length, greaterThanOrEqualTo(2));
    });

    test('annullare la password non è un guasto, ed è la TUA risposta',
        () async {
      final p = conAiutante([
        voce('lingue', '/usr/share/locale', 360000000, password: true),
      ], annullato: true);
      final r = await p.dentro.pulisci(['lingue']);
      expect(r['ok'], isTrue, reason: 'la pulizia è finita, non è esplosa');
      expect(r['liberati'], 0);
      final fatte = (r['fatte'] as List).cast<Map<String, dynamic>>();
      expect('${fatte.single['perche']}', contains('annullato'));
    });

    test('senza aiutante si rifiuta, come prima', () async {
      // È il caso di tutte le prove che non lo passano, e deve restare quello
      // di prima: si dice di no con la ragione scritta, non si prova a
      // cancellare a mano quello che sta fuori dalla tua cartella.
      final tolti = <String>[];
      final p = Pulitore(
        casa: '/casa',
        inventario: InventarioFinto([
          voce('lingue', '/usr/share/locale', 360000000, password: true),
        ]),
        togli: (percorso) async => tolti.add(percorso),
      );
      final r = await p.pulisci(['lingue']);
      expect(tolti, isEmpty);
      final fatte = (r['fatte'] as List).cast<Map<String, dynamic>>();
      expect('${fatte.single['perche']}', contains('password'));
    });

    test('una voce di sistema che non conosciamo NON si prova a indovinare',
        () async {
      final p = conAiutante([
        voce('roba-nuova', '/var/qualcosa', 100, password: true),
      ]);
      final r = await p.dentro.pulisci(['roba-nuova']);
      expect(p.chieste, isEmpty);
      final fatte = (r['fatte'] as List).cast<Map<String, dynamic>>();
      expect(fatte.single['ok'], isFalse);
    });
  });

  group('i due che si svuotano invece di essere cancellati', () {
    // ── Il difetto ───────────────────────────────────────────────────────
    //
    // Il cestino e `/tmp` sono contenitori: si tolgono i figli, non la
    // cartella. Ma il cancello dei posti pretendeva che il percorso stesse
    // DENTRO un posto permesso, e `/casa/.local/share/Trash` non sta dentro
    // `/casa/.local/share/Trash/`: il cestino si rifiutava da solo.
    //
    // Giacomo l'ha trovato usandolo: aveva spuntato il cestino e il cestino
    // era rimasto pieno.
    //
    // ── E la PRIMA versione di questa prova era falsa ────────────────────
    //
    // Creava un cestino finto con `Directory.systemTemp`, cioè sotto `/tmp`.
    // E `/tmp` è già un posto permesso: la prova passava per il motivo
    // sbagliato, e restava verde anche togliendo la correzione. Adesso i
    // percorsi sono finti per davvero e l'elenco dei figli si sostituisce,
    // come `togli`.
    ({Pulitore dentro, List<String> tolti}) contenitore(
        String id, String dove, List<String> figli,
        {Map<String, DateTime>? quando}) {
      final tolti = <String>[];
      return (
        tolti: tolti,
        dentro: Pulitore(
          casa: '/casa',
          inventario: InventarioFinto([voce(id, dove, 18000000)]),
          togli: (percorso) async => tolti.add(percorso),
          figliDa: (percorso) async => percorso == dove ? figli : [],
          quandoToccato: (percorso) async =>
              quando?[percorso] ?? DateTime.now(),
        ),
      );
    }

    test('il cestino si può svuotare', () async {
      final p = contenitore('cestino', '/casa/.local/share/Trash',
          ['/casa/.local/share/Trash/files', '/casa/.local/share/Trash/info']);
      final r = await p.dentro.pulisci(['cestino']);
      expect(p.tolti, [
        '/casa/.local/share/Trash/files',
        '/casa/.local/share/Trash/info',
      ], reason: 'il cestino si rifiutava da solo');
      expect((r['fatte'] as List).single['ok'], isTrue);
    });

    test('e si svuota, non si cancella', () async {
      // La cartella del cestino deve restare: cancellarla vorrebbe dire
      // togliere il cestino invece di vuotarlo.
      final p = contenitore('cestino', '/casa/.local/share/Trash',
          ['/casa/.local/share/Trash/files']);
      await p.dentro.pulisci(['cestino']);
      expect(p.tolti, isNot(contains('/casa/.local/share/Trash')));
    });

    test('`/tmp` sì, ma solo la roba più vecchia di un giorno', () async {
      // Un programma aperto da un'ora ci tiene dentro cose che gli servono, e
      // togliergliele sotto vuol dire farlo cadere. Si svuota comunque al
      // riavvio, quindi la fretta qui non serve a niente.
      final vecchio = DateTime.now().subtract(const Duration(days: 3));
      final p = contenitore('temporanei', '/tmp',
          ['/tmp/vecchio', '/tmp/appena-fatto'],
          quando: {'/tmp/vecchio': vecchio});
      await p.dentro.pulisci(['temporanei']);
      expect(p.tolti, ['/tmp/vecchio']);
    });

    test('ma `~/.cache` per intero resta vietata', () async {
      // Toglierla porterebbe via anche le briciole sotto i dieci mega, che
      // nell'elenco non compaiono: roba che nessuno ha messo sotto gli occhi
      // di nessuno.
      final p = pulitoreCon([voce('tutta', '/casa/.cache', 9000)]);
      await p.dentro.pulisci(['tutta']);
      expect(p.tolti, isEmpty);
    });
  });
}

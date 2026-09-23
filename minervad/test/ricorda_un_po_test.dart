import 'package:test/test.dart';
import 'package:minervad/core/ricorda_un_po.dart';

// Il ricordo breve che toglie il costo alle tre risposte che si
// ricalcolavano da capo ogni volta. Vedi la testa di `ricorda_un_po.dart`
// per i numeri misurati.
//
// Le prove che contano qui sono due, e sono quelle che un ricordo scritto male
// sbaglia: che due domande FATTE INSIEME non facciano il lavoro due volte, e
// che un errore non resti appiccicato.
void main() {
  group('un ricordo che dura un po\'', () {
    test('la seconda domanda non rifà il lavoro', () async {
      final r = RicordaUnPo<int>(const Duration(seconds: 30));
      var volte = 0;
      Future<int> lavoro() async {
        volte++;
        return 7;
      }

      expect(await r.chiedi(lavoro), 7);
      expect(await r.chiedi(lavoro), 7);
      expect(await r.chiedi(lavoro), 7);
      expect(volte, 1, reason: 'il lavoro si è rifatto');
      expect(r.risparmiate, 2);
    });

    test('scaduto, il lavoro si rifà', () async {
      final r = RicordaUnPo<int>(const Duration(milliseconds: 40));
      var volte = 0;
      Future<int> lavoro() async => ++volte;

      expect(await r.chiedi(lavoro), 1);
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(await r.chiedi(lavoro), 2, reason: 'scaduto e non ha rifatto');
    });

    test('due domande insieme fanno UN lavoro solo', () async {
      // È il caso vero: otto finestre di Minerva che si aprono insieme e
      // chiedono la stessa cosa allo stesso demone.
      final r = RicordaUnPo<int>(const Duration(seconds: 30));
      var volte = 0;
      Future<int> lento() async {
        volte++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        return 42;
      }

      final tutte = await Future.wait(List.generate(8, (_) => r.chiedi(lento)));
      expect(tutte, everyElement(42));
      expect(volte, 1,
          reason: 'otto domande insieme hanno fatto il lavoro $volte volte');
    });

    test('un errore NON si ricorda', () async {
      final r = RicordaUnPo<int>(const Duration(seconds: 30));
      var volte = 0;
      Future<int> ballerino() async {
        volte++;
        if (volte == 1) throw StateError('il busctl di oggi non risponde');
        return 5;
      }

      await expectLater(r.chiedi(ballerino), throwsStateError);
      // Il guasto passeggero non deve diventare la risposta dei prossimi
      // trenta secondi.
      expect(await r.chiedi(ballerino), 5);
      expect(volte, 2);
    });

    test('e dimenticare fa rifare subito', () async {
      final r = RicordaUnPo<int>(const Duration(seconds: 30));
      var volte = 0;
      Future<int> lavoro() async => ++volte;

      expect(await r.chiedi(lavoro), 1);
      r.dimentica();
      expect(await r.chiedi(lavoro), 2);
    });
  });
}

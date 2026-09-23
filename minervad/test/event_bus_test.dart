import 'dart:async';

import 'package:test/test.dart';
import 'package:minervad/core/event_bus.dart';

// Le prove del bus.
//
// Il bus non aveva prove: quarantadue righe che sembravano troppo semplici per
// sbagliare. Ma è il punto da cui passa TUTTO, e i modi in cui falliva erano
// tre, tutti silenziosi:
//
//   1. pubblicare dopo la chiusura lancia `StateError` e fa cadere il demone
//      proprio mentre si sta fermando, quando nessuno legge più i registri;
//   2. un ascoltatore che si rompe non si sente: su uno stream broadcast
//      l'eccezione finisce alla zona, cioè da nessuna parte, e gli altri
//      iscritti continuano — guasto parziale e invisibile;
//   3. non c'era modo di sapere quanti eventi passassero, cioè la prima cosa
//      da guardare quando il demone consuma a riposo.
void main() {
  group('bus degli eventi', () {
    test('un evento pubblicato arriva a chi ascolta', () async {
      final bus = EventBus();
      final visti = <MinervaEvent>[];
      bus.stream.listen(visti.add);

      expect(bus.publish(MinervaEvent(type: 'ciao', payload: 1)), isTrue);
      await Future.delayed(Duration.zero);

      expect(visti, hasLength(1));
      expect(visti.first.type, 'ciao');
      expect(visti.first.payload, 1);
      await bus.dispose();
    });

    test('arriva a TUTTI quelli che ascoltano', () async {
      final bus = EventBus();
      final uno = <String>[];
      final due = <String>[];
      bus.stream.listen((e) => uno.add(e.type));
      bus.stream.listen((e) => due.add(e.type));

      bus.publish(MinervaEvent(type: 'ciao'));
      await Future.delayed(Duration.zero);

      expect(uno, ['ciao']);
      expect(due, ['ciao']);
      await bus.dispose();
    });

    test('filter() consegna solo il tipo chiesto', () async {
      final bus = EventBus();
      final visti = <String>[];
      bus.filter('battito').listen((e) => visti.add(e.type));

      bus.publish(MinervaEvent(type: 'battito'));
      bus.publish(MinervaEvent(type: 'altro'));
      bus.publish(MinervaEvent(type: 'battito'));
      await Future.delayed(Duration.zero);

      expect(visti, ['battito', 'battito']);
      await bus.dispose();
    });

    // ── Il difetto numero uno ────────────────────────────────────────────
    test('pubblicare dopo la chiusura non lancia: torna false e si conta',
        () async {
      final bus = EventBus();
      await bus.dispose();

      expect(bus.chiuso, isTrue);
      expect(() => bus.publish(MinervaEvent(type: 'tardivo')), returnsNormally,
          reason: 'con lo StreamController nudo qui volava uno StateError, '
              'e il demone moriva a metà arresto');
      expect(bus.publish(MinervaEvent(type: 'tardivo')), isFalse);
      expect(bus.pubblicatiDopoLaChiusura, 2);
    });

    test('chiudere due volte non è un errore', () async {
      final bus = EventBus();
      await bus.dispose();
      expect(bus.dispose(), completes);
    });

    // ── Il difetto numero due ────────────────────────────────────────────
    test('un ascoltatore che si rompe non ferma gli altri', () async {
      final bus = EventBus();
      final sani = <String>[];

      bus.ascolta((_) => throw StateError('mi sono rotto'), chi: 'il rotto');
      bus.ascolta((e) => sani.add(e.type), chi: 'il sano');

      bus.publish(MinervaEvent(type: 'ciao'));
      await Future.delayed(Duration.zero);

      expect(sani, ['ciao'],
          reason: 'chi funziona deve ricevere anche se un altro è caduto');
      await bus.dispose();
    });

    test('ascolta() continua a consegnare DOPO che il gestore è caduto',
        () async {
      final bus = EventBus();
      final visti = <String>[];

      bus.ascolta((e) {
        visti.add(e.type);
        if (e.type == 'brutto') throw StateError('ahi');
      }, chi: 'il fragile');

      bus.publish(MinervaEvent(type: 'brutto'));
      await Future.delayed(Duration.zero);
      bus.publish(MinervaEvent(type: 'bello'));
      await Future.delayed(Duration.zero);

      expect(visti, ['brutto', 'bello'],
          reason: 'una caduta non deve chiudere la sottoscrizione: '
              'sarebbe una parte del demone che smette di sapere le cose '
              'senza che nessuno lo dica');
      await bus.dispose();
    });

    // ── Il difetto numero tre ────────────────────────────────────────────
    test('il conto degli eventi si tiene per tipo', () async {
      final bus = EventBus();
      bus.publish(MinervaEvent(type: 'battito'));
      bus.publish(MinervaEvent(type: 'battito'));
      bus.publish(MinervaEvent(type: 'raro'));

      expect(bus.conteggio['battito'], 2);
      expect(bus.conteggio['raro'], 1);
      expect(bus.conteggio['mai'], isNull);
      await bus.dispose();
    });

    test('il conto non si può modificare da fuori', () async {
      final bus = EventBus();
      bus.publish(MinervaEvent(type: 'x'));
      expect(() => bus.conteggio['x'] = 99, throwsUnsupportedError);
      await bus.dispose();
    });

    test('gli eventi buttati NON entrano nel conto', () async {
      final bus = EventBus();
      bus.publish(MinervaEvent(type: 'x'));
      await bus.dispose();
      bus.publish(MinervaEvent(type: 'x'));

      expect(bus.conteggio['x'], 1,
          reason: 'il conto serve a capire quanto lavoro fa il bus: '
              'un evento buttato non è lavoro');
    });

    test('l\'evento porta con sé il momento in cui è nato', () {
      final prima = DateTime.now();
      final e = MinervaEvent(type: 'x');
      expect(e.timestamp.isBefore(prima), isFalse);
      expect(e.toJson()['timestamp'], e.timestamp.toIso8601String());
    });
  });
}

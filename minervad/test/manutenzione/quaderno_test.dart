import 'dart:io';

import 'package:test/test.dart';
import 'package:minervad/services/manutenzione/quaderno.dart';

// Il quaderno di quanto Manutenzione ha recuperato da sempre.
//
// È l'unica cosa che quel programma si RICORDA: l'inventario si rimisura ogni
// volta apposta, perché un conto vecchio di mezz'ora direbbe il falso proprio
// su quello che hai appena pulito. Questo invece è una storia, e una storia si
// scrive.
//
// La prova che conta più delle altre è la prima: che ci finiscano solo i byte
// usciti davvero. Un totale gonfiato è la bugia più facile da dire qui dentro,
// perché nessuno può controllarla.
void main() {
  late Directory casa;
  late Quaderno quaderno;

  setUp(() async {
    casa = await Directory.systemTemp.createTemp('minerva-quaderno-');
    quaderno = Quaderno(percorso: '${casa.path}/manutenzione.json');
  });

  tearDown(() async => casa.delete(recursive: true));

  test('a quaderno bianco non si inventa niente', () async {
    final r = await quaderno.leggi();
    expect(r['byte'], 0);
    expect(r['volte'], 0);
    expect(r['dal'], isEmpty);
  });

  test('si somma quello che è uscito, pulizia dopo pulizia', () async {
    await quaderno.segna(1000);
    await quaderno.segna(2500);
    final r = await quaderno.leggi();
    expect(r['byte'], 3500);
    expect(r['volte'], 2);
  });

  test('zero byte non è una pulizia', () async {
    // Se non è uscito niente — perché era già pulito, o perché hai annullato
    // la password — non si segna niente. Un contatore di «volte» che cresce
    // senza che sia successo nulla rende inutile anche il numero accanto.
    await quaderno.segna(0);
    await quaderno.segna(-5);
    final r = await quaderno.leggi();
    expect(r['volte'], 0);
    expect(r['byte'], 0);
  });

  test('il giorno del primo non cambia più', () async {
    await quaderno.segna(10);
    final primo = (await quaderno.leggi())['dal'];
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await quaderno.segna(10);
    final dopo = await quaderno.leggi();
    expect(dopo['dal'], primo, reason: '«da quando» è una data sola');
    expect(dopo['ultima'], isNot(primo));
  });

  test('un quaderno illeggibile non impedisce una pulizia', () async {
    // Ricominciare da zero è meglio che non funzionare: il conto è un di
    // più, la pulizia no.
    await File('${casa.path}/manutenzione.json').writeAsString('{rotto');
    expect((await quaderno.leggi())['byte'], 0);
    await quaderno.segna(700);
    expect((await quaderno.leggi())['byte'], 700);
  });

  test('si scrive di fianco e poi al suo posto', () async {
    // Se manca la corrente a metà scrittura, il quaderno è quello di prima e
    // intero, non mezzo. È la stessa regola con cui si salvano le
    // impostazioni.
    await quaderno.segna(42);
    final rimasti = casa
        .listSync()
        .map((f) => f.path.split('/').last)
        .where((n) => n.startsWith('manutenzione'))
        .toList();
    expect(rimasti, ['manutenzione.json'],
        reason: 'il file di appoggio non deve restare lì');
  });
}

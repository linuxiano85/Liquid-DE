// Il canale verso i servizi di sistema.
//
// Queste prove girano contro il D-Bus VERO di questa macchina, e quindi
// devono saper dire «non lo so» senza fallire: su un computer senza Bluetooth
// o dentro un contenitore senza bus, `null` è la risposta giusta e non un
// errore. Ciò che si prova è che il canale non menta MAI — né inventando né
// esplodendo.

import 'dart:io';
import 'package:test/test.dart';
import 'package:minervad/services/dbus.dart';

void main() {
  final ceBusctl = Process.runSync('sh', ['-c', 'command -v busctl'])
          .exitCode ==
      0;

  group('il canale D-Bus non mente', () {
    test('un servizio che non esiste non è un errore: è un «non so»', () async {
      final v = await Dbus.proprieta('org.minerva.NonEsisteDavvero', '/', 'X', 'Y');
      expect(v, isNull);
      final o = await Dbus.oggetti('org.minerva.NonEsisteDavvero', '/');
      expect(o, isNull);
    }, skip: ceBusctl ? null : 'busctl non installato');

    test('scrivere dove non si può torna false, non esplode', () async {
      final ok = await Dbus.scrivi(
          'org.minerva.NonEsisteDavvero', '/', 'X', 'Y', 'b', 'true');
      expect(ok, isFalse);
    }, skip: ceBusctl ? null : 'busctl non installato');

    test('il bus di sistema c\'è, e sa dire chi c\'è sopra', () async {
      // `org.freedesktop.DBus` è il bus stesso: se non risponde lui, non
      // risponde nessuno, e la prova non starebbe provando niente.
      final c = await Dbus.ceIlServizio('org.freedesktop.DBus');
      expect(c, isTrue);
      final no = await Dbus.ceIlServizio('org.minerva.NonEsisteDavvero');
      expect(no, isFalse);
    }, skip: ceBusctl ? null : 'busctl non installato');
  });

  group('BlueZ, se c\'è', () {
    test('gli oggetti arrivano spacchettati, non nel loro involucro', () async {
      if (!await Dbus.ceIlServizio('org.bluez')) {
        markTestSkipped('nessun BlueZ su questa macchina');
        return;
      }
      final o = await Dbus.oggetti('org.bluez', '/');
      expect(o, isNotNull);

      // Il punto della prova: `busctl` incarta ogni valore in
      // `{"type": "b", "data": true}`. Se l'involucro arrivasse fin qui,
      // `adattatore['Powered'] == true` sarebbe SEMPRE falso — e il Bluetooth
      // risulterebbe spento su una macchina accesa. È il difetto del 2026,
      // ripetuto in una forma nuova.
      final adattatori = o!.values
          .where((i) => i.containsKey('org.bluez.Adapter1'))
          .map((i) => i['org.bluez.Adapter1']!)
          .toList();
      if (adattatori.isEmpty) {
        markTestSkipped('BlueZ c\'è ma senza adattatori');
        return;
      }
      final acceso = adattatori.first['Powered'];
      expect(acceso, isA<bool>(),
          reason: '`Powered` deve essere un booleano vero, non una mappa '
              '{type, data} né una stringa');
    }, skip: ceBusctl ? null : 'busctl non installato');
  });
}

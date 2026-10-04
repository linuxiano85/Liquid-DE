import 'dart:convert';

import 'processo_limitato.dart';

/// Il canale verso i servizi di sistema: D-Bus.
///
/// ── Perché esiste ────────────────────────────────────────────────────────
///
/// Il demone chiedeva lo stato del sistema leggendo l'uscita *per umani* di
/// altri programmi:
///
///     bluetoothctl show | grep 'Powered: yes'
///
/// Funziona finché quel programma stampa esattamente com'è abituato. Poi non
/// più: su BlueZ 5.7x la riga `Address:` è sparita da `bluetoothctl show`, e
/// Minerva dichiarava «nessun adattatore Bluetooth» su un computer col
/// Bluetooth acceso e funzionante. Non era rotto: era invisibile. È scritto
/// nei commenti di `system_state_service.dart`, e l'abbiamo pagato una volta.
///
/// Il canale vero del desktop Linux è D-Bus: interfacce con un nome, un tipo
/// e un contratto che i progetti mantengono fra le versioni proprio perché
/// sanno che qualcuno ci si appoggia. `org.bluez.Adapter1.Powered` è un
/// booleano oggi ed è un booleano fra due anni; `Powered: yes` dentro una
/// riga di testo non lo promette nessuno.
///
/// ── Perché passa ancora da un processo ───────────────────────────────────
///
/// Dart non ha un client D-Bus nella libreria standard, e questo demone ha
/// **zero dipendenze** — è ciò che lo tiene a 22 MB e lo fa compilare in
/// pochi secondi. `busctl --json=short` è il compromesso: paghiamo un
/// processo, ma quello che torna è JSON tipato, non prosa.
///
/// **Questo file è il confine.** Il giorno in cui scriveremo (o aggiungeremo)
/// un client D-Bus vero, cambia solo lui: nessuno dei servizi sa che sotto
/// c'è `busctl`. Vedi `MODULI.md`.
class Dbus {
  const Dbus._();

  /// Quanto si aspetta una risposta. D-Bus è locale: se non risponde in tre
  /// secondi non risponderà, e restare appesi vorrebbe dire un pannello di
  /// sistema che non si aggiorna più.
  static const Duration _attesa = Duration(seconds: 3);

  // `eseguiLimitato` e non `Process.run(...).timeout(...)`: il secondo
  // smetteva di aspettare ma lasciava vivo `busctl`, che davanti a un servizio
  // impallato restava lì i suoi venticinque secondi — uno in più a ogni giro
  // dello stato di sistema (30 settembre 2026).
  static Future<String?> _busctl(List<String> argomenti) async {
    try {
      final r = await eseguiLimitato('busctl', ['--json=short', ...argomenti],
          limite: _attesa);
      if (!r.ok) return null;
      final s = r.stdout.trim();
      return s.isEmpty ? null : s;
    } catch (_) {
      // `busctl` assente, bus assente, servizio spento, tempo scaduto: sono
      // tutti «non lo so», e chi chiama deve trattarli allo stesso modo.
      return null;
    }
  }

  static List<String> _dove(bool sistema) => sistema ? ['--system'] : ['--user'];

  /// Il valore di una proprietà, già spacchettato dal suo involucro
  /// `{"type": …, "data": …}`. `null` quando non si sa.
  ///
  ///     await Dbus.proprieta('org.bluez', '/org/bluez/hci0',
  ///                          'org.bluez.Adapter1', 'Powered')   // true
  static Future<dynamic> proprieta(
    String servizio,
    String percorso,
    String interfaccia,
    String nome, {
    bool sistema = true,
  }) async {
    final out = await _busctl([
      ..._dove(sistema),
      'get-property',
      servizio,
      percorso,
      interfaccia,
      nome,
    ]);
    if (out == null) return null;
    try {
      final m = jsonDecode(out);
      return m is Map ? m['data'] : null;
    } catch (_) {
      return null;
    }
  }

  /// Tutti gli oggetti di un servizio, con le loro interfacce e proprietà.
  ///
  /// Torna una mappa `percorso → interfaccia → proprietà → valore`, con i
  /// valori già spacchettati. È **una sola chiamata** per sapere tutto di un
  /// servizio: per il Bluetooth prima ce ne volevano quattro, e tre di quelle
  /// erano `grep`.
  static Future<Map<String, Map<String, Map<String, dynamic>>>?> oggetti(
    String servizio,
    String percorso, {
    bool sistema = true,
  }) async {
    final out = await _busctl([
      ..._dove(sistema),
      'call',
      servizio,
      percorso,
      'org.freedesktop.DBus.ObjectManager',
      'GetManagedObjects',
    ]);
    if (out == null) return null;
    try {
      final radice = jsonDecode(out);
      if (radice is! Map) return null;
      // `busctl` incarta il risultato in `data: [ … ]`: un elemento per
      // argomento di ritorno, e questo metodo ne ha uno solo.
      final dati = radice['data'];
      if (dati is! List || dati.isEmpty) return null;
      final primo = dati.first;
      if (primo is! Map) return null;

      final fuori = <String, Map<String, Map<String, dynamic>>>{};
      primo.forEach((percorsoOggetto, interfacce) {
        if (interfacce is! Map) return;
        final perOggetto = <String, Map<String, dynamic>>{};
        interfacce.forEach((nomeInterfaccia, proprieta) {
          if (proprieta is! Map) return;
          final valori = <String, dynamic>{};
          proprieta.forEach((nomeProprieta, involucro) {
            valori[nomeProprieta as String] =
                involucro is Map ? involucro['data'] : involucro;
          });
          perOggetto[nomeInterfaccia as String] = valori;
        });
        fuori[percorsoOggetto as String] = perOggetto;
      });
      return fuori;
    } catch (_) {
      return null;
    }
  }

  /// Scrive una proprietà. `firma` è quella di D-Bus: `b` booleano, `s`
  /// stringa, `u` intero senza segno.
  ///
  /// Torna `false` quando non è andata — e chi chiama NON deve fidarsi di
  /// `true` come prova che il mondo sia cambiato: il modo giusto è riscrivere
  /// e poi RILEGGERE, che è quello che fa `system_state_service`.
  static Future<bool> scrivi(
    String servizio,
    String percorso,
    String interfaccia,
    String nome,
    String firma,
    String valore, {
    bool sistema = true,
  }) async {
    try {
      final r = await eseguiLimitato('busctl', [
        ..._dove(sistema),
        'set-property',
        servizio,
        percorso,
        interfaccia,
        nome,
        firma,
        valore,
      ], limite: _attesa);
      return r.ok;
    } catch (_) {
      return false;
    }
  }

  /// Chiama un metodo e restituisce quello che ha risposto, già spacchettato.
  ///
  /// `firma` descrive gli argomenti (`s` una stringa, `sa{sv}` una stringa più
  /// un dizionario, `""` nessun argomento), e `argomenti` sono i pezzi nella
  /// forma che `busctl` si aspetta.
  ///
  ///     await Dbus.chiama('org.freedesktop.login1', '/org/freedesktop/login1',
  ///                       'org.freedesktop.login1.Manager', 'Suspend', 'b',
  ///                       ['false'])
  ///
  /// ── IL LIMITE, che è costato mezza serata ──────────────────────────────
  ///
  /// **Ogni chiamata è un `busctl` a sé: una connessione al bus che nasce,
  /// chiama e muore.** Quindi questa funzione serve solo per i metodi che
  /// stanno in piedi da soli. Tutto ciò che apre qualcosa da usare DOPO — una
  /// sessione, un abbonamento, un oggetto che vive finché vive il chiamante —
  /// **non si può fare da qui**, e il modo in cui fallisce non lo dice.
  ///
  /// Successo davvero il 19 agosto 2026 con l'invio di un file via Bluetooth:
  /// `CreateSession` rispondeva un percorso valido, e il `SendFile` subito
  /// dopo diceva che il metodo «doesn't exist». Non era vero: obexd aveva già
  /// distrutto la sessione, perché il `busctl` che l'aveva creata era uscito.
  ///
  /// Per quei casi ci vuole **un processo che resta vivo**: vedi
  /// `condivisione_service.dart` (obexctl) e `bluetooth_pairing_service.dart`
  /// (bluetoothctl), che fanno così per questa ragione e non per capriccio.
  ///
  /// Torna `null` quando non è andata: servizio assente, metodo rifiutato,
  /// tempo scaduto. Sono tutti «non è successo», e chi chiama li tratta uguale.
  ///
  /// ── Perché serviva, e non c'era ────────────────────────────────────────
  ///
  /// Fin qui il demone al bus faceva tre cose: leggere una proprietà, leggerle
  /// tutte, scriverne una. Bastava perché tutto quello che chiedeva era lo
  /// STATO del sistema. Mandare un file per Bluetooth non è leggere uno stato:
  /// è chiedere a `org.bluez.obex` di fare qualcosa, e per quello ci vuole una
  /// chiamata a un metodo.
  static Future<dynamic> chiama(
    String servizio,
    String percorso,
    String interfaccia,
    String metodo, {
    String firma = '',
    List<String> argomenti = const [],
    bool sistema = true,
    Duration? attesa,
  }) async {
    try {
      final r = await eseguiLimitato('busctl', [
        '--json=short',
        ..._dove(sistema),
        'call',
        servizio,
        percorso,
        interfaccia,
        metodo,
        firma,
        ...argomenti,
      ], limite: attesa ?? _attesa);
      if (!r.ok) return null;
      final out = r.stdout.trim();
      if (out.isEmpty) return true; // metodo senza valore di ritorno: è andata
      final m = jsonDecode(out);
      return m is Map ? m['data'] : null;
    } catch (_) {
      return null;
    }
  }

  /// C'è qualcuno dietro questo nome?
  ///
  /// Serve a distinguere «il servizio non c'è» da «il servizio dice di no»:
  /// sono due risposte diverse e l'interfaccia le mostra in modo diverso —
  /// un interruttore spento contro una sezione che non compare.
  static Future<bool> ceIlServizio(String servizio, {bool sistema = true}) async {
    final out = await _busctl([
      ..._dove(sistema),
      'call',
      'org.freedesktop.DBus',
      '/org/freedesktop/DBus',
      'org.freedesktop.DBus',
      'NameHasOwner',
      's',
      servizio,
    ]);
    if (out == null) return false;
    try {
      final m = jsonDecode(out);
      final dati = m is Map ? m['data'] : null;
      return dati is List && dati.isNotEmpty && dati.first == true;
    } catch (_) {
      return false;
    }
  }
}

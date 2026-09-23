import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'foto/dlna.dart';

/// Uno schermo esterno trovato in rete.
class SchermoEsterno {
  /// Il nome che l'utente riconosce: «TV cameretta», «Cucina».
  final String nome;
  final String indirizzo;
  final int porta;

  /// `cast` (Chromecast / Google TV), `dlna` (UPnP MediaRenderer: i Samsung
  /// Tizen, e quasi ogni televisore degli ultimi vent'anni) oppure `airplay`.
  ///
  /// L'ordine conta: `dlna` vince su `airplay` quando lo stesso apparecchio
  /// parla tutti e due. Vedi `unisci()`.
  final String modo;

  /// Per un renderer DLNA, l'indirizzo della sua descrizione:
  /// `http://192.168.1.69:9197/dmr`. Vuoto per gli altri modi.
  final String descrizione;

  /// Il modello dichiarato, quando c'è: «AI PONT». Serve a distinguere due
  /// televisori che si chiamano uguale, non a mostrarlo per primo.
  final String modello;

  /// L'identificativo stabile del dispositivo. **Non** l'indirizzo IP: quello
  /// cambia a ogni riaccensione del router, e ricordarsi «l'ultimo televisore
  /// usato» tramite l'IP vuol dire ricordarsi la casa di ieri.
  final String id;

  const SchermoEsterno({
    required this.nome,
    required this.indirizzo,
    required this.porta,
    required this.modo,
    this.modello = '',
    this.id = '',
    this.descrizione = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id.isEmpty ? '$indirizzo:$porta' : id,
        'nome': nome,
        'indirizzo': indirizzo,
        'porta': porta,
        'modo': modo,
        if (modello.isNotEmpty) 'modello': modello,
        if (descrizione.isNotEmpty) 'descrizione': descrizione,
      };
}

/// Trova i televisori e gli schermi a cui si potrebbe trasmettere.
///
/// ── Perché `avahi-browse` e non una libreria ──────────────────────────────
///
/// Perché `avahi` è già acceso su questa macchina e `avahi-browse` è già
/// installato: è il modo di avere la scoperta **senza una dipendenza nuova**,
/// che è la regola che questo progetto si è dato dopo la notte del 26 agosto.
/// Il demone dichiara zero dipendenze esterne di proposito.
///
/// ── E perché la scoperta è separata dalla trasmissione ────────────────────
///
/// Perché trovare un televisore e sapergli parlare sono due lavori di
/// dimensioni molto diverse. La scoperta costa questa manciata di righe e ha
/// un valore suo: il menù «Condividi» può mostrare **il nome vero** del
/// televisore fin dal primo giorno, con accanto scritto che non sappiamo
/// ancora parlargli.
///
/// Una voce spenta con scritto perché è la verità. Una voce che manca sembra
/// un difetto — ed è la regola che `condivisione_service.dart` applica già a
/// Bluetooth e posta.
class SchermiEsterni {
  /// Quanto si aspetta la risposta della rete. Tre secondi: mDNS risponde in
  /// poche centinaia di millisecondi su una rete di casa, e chi apre un menù
  /// non aspetta di più.
  final Duration pazienza;

  /// L'ultimo elenco trovato, e quando. Una scoperta costa tre secondi di
  /// attesa: rifarla a ogni apertura di menù vorrebbe dire tre secondi di
  /// menù vuoto ogni volta.
  List<SchermoEsterno> _ultimi = const [];
  DateTime _quando = DateTime.fromMillisecondsSinceEpoch(0);

  /// Per quanto tempo va bene l'elenco di prima. Mezzo minuto: un televisore
  /// non compare e sparisce di continuo, e chi lo ha appena acceso riprova.
  static const freschezza = Duration(seconds: 30);

  SchermiEsterni({this.pazienza = const Duration(seconds: 3)});

  bool get fresco => DateTime.now().difference(_quando) < freschezza;
  List<SchermoEsterno> get ultimi => _ultimi;

  /// Cerca in rete. Con `subito: true` non aspetta e torna l'ultimo elenco.
  Future<List<SchermoEsterno>> cerca({bool subito = false}) async {
    if (subito || fresco) return _ultimi;
    final tutti = <SchermoEsterno>[];
    for (final servizio in const ['_googlecast._tcp', '_airplay._tcp']) {
      tutti.addAll(await _sfoglia(servizio));
    }
    _ultimi = await _conDlna(unisci(tutti));
    _quando = DateTime.now();
    return _ultimi;
  }

  // ── E poi si chiede a ciascuno se parla anche DLNA ──────────────────────
  //
  // Giacomo, 3 settembre 2026: «la cucina ha tizen os ed è samsung». Un
  // Samsung Tizen non parla Chromecast: si annuncia via AirPlay (che vuole un
  // accoppiamento in stile HomeKit) e, in silenzio, espone un renderer DLNA
  // su una porta che nessuno annuncia. Senza questo giro, l'unico televisore
  // con cui Minerva sapeva parlare era quello in camera dei bambini.
  //
  // Si chiede solo agli indirizzi che la scoperta ha già trovato: le risposte
  // SSDP le blocca il nostro stesso firewall (vedi `foto/dlna.dart`), e
  // interrogare un indirizzo noto è traffico in uscita.
  //
  // In parallelo, e non uno dopo l'altro: ogni televisore assente costa fino a
  // otto secondi di attesa, e in fila sarebbero mezzo minuto per aprire un
  // menù.
  Future<List<SchermoEsterno>> _conDlna(List<SchermoEsterno> trovati) async {
    if (trovati.isEmpty) return trovati;
    final risposte = await Future.wait([
      for (final s in trovati)
        // Chi già parla Chromecast lo lasciamo com'è: `castv2.dart` è nostro,
        // provato, e non ha bisogno di un intermediario.
        s.modo == 'cast'
            ? Future<Dlna?>.value(null)
            : Dlna.interroga(s.indirizzo)
    ]);
    final fuori = <SchermoEsterno>[];
    for (var i = 0; i < trovati.length; i++) {
      final s = trovati[i];
      final d = risposte[i];
      if (d == null) {
        fuori.add(s);
        continue;
      }
      final chi = await d.chiSei();
      d.chiudi();
      if (chi == null) {
        fuori.add(s);
        continue;
      }
      // Il nome resta quello che l'utente ha dato al televisore, e l'ID
      // diventa l'UDN: stabile fra le riaccensioni, mentre l'IP no. Cucina
      // via AirPlay non aveva nessun ID.
      fuori.add(SchermoEsterno(
        nome: chi['nome']!.isEmpty ? s.nome : chi['nome']!,
        indirizzo: s.indirizzo,
        porta: s.porta,
        modo: 'dlna',
        modello: chi['modello'] ?? s.modello,
        id: chi['id']!.isEmpty ? s.id : chi['id']!,
        descrizione: chi['descrizione'] ?? '',
      ));
    }
    return fuori;
  }

  Future<List<SchermoEsterno>> _sfoglia(String servizio) async {
    ProcessResult r;
    try {
      r = await Process.run('avahi-browse', ['-tpr', servizio])
          .timeout(pazienza);
    } on TimeoutException {
      return const [];
    } catch (_) {
      // `avahi-browse` non installato, o avahi spento. Non è un errore da
      // gridare: è una scrivania senza scoperta di rete, e il menù lo dirà.
      return const [];
    }
    if (r.exitCode != 0) return const [];
    return leggiUscita(r.stdout as String,
        servizio.startsWith('_googlecast') ? 'cast' : 'airplay');
  }

  // ── Da qui in giù è CONTO PURO, e ha le sue prove ────────────────────
  //
  // Separato dal lancio del processo di proposito: una prova che ha bisogno
  // di un televisore acceso fallisce quando qualcuno lo spegne, e una prova
  // che fallisce per ragioni sue smette di dire qualcosa. Il formato di
  // `avahi-browse`, invece, si prova con una stringa.
  // Vedi `test/schermi_esterni_test.dart`.

  /// Legge l'uscita di `avahi-browse -tpr`.
  static List<SchermoEsterno> leggiUscita(String uscita, String modo) {
    final fuori = <SchermoEsterno>[];
    for (final riga in const LineSplitter().convert(uscita)) {
      // Le righe risolte cominciano con `=`. Le altre sono «ho visto» e «se
      // n'è andato», e non portano né indirizzo né porta: prenderle vorrebbe
      // dire un televisore a cui non si sa dove scrivere.
      if (!riga.startsWith('=')) continue;
      final c = riga.split(';');
      if (c.length < 10) continue;

      final indirizzo = c[7];
      final porta = int.tryParse(c[8]) ?? 0;
      if (indirizzo.isEmpty || porta == 0) continue;

      final txt = leggiTxt(c.sublist(9).join(';'));
      // `fn` è il nome che l'utente ha dato al televisore dal telecomando —
      // «TV cameretta» — ed è l'unico che significhi qualcosa per lui. Il
      // nome del servizio è una stringa come
      // `AI-PONT-cf6bacd1cbcc48531667d8890e49312c`, che non dice niente a
      // nessuno; senza `fn` almeno se ne toglie la coda esadecimale.
      final nome = txt['fn'] ??
          sciogliFuga(c[3]).replaceAll(RegExp(r'-[0-9a-f]{4,}$'), '');
      fuori.add(SchermoEsterno(
        nome: nome.isEmpty ? indirizzo : nome,
        indirizzo: indirizzo,
        porta: porta,
        modo: modo,
        modello: txt['md'] ?? '',
        id: txt['id'] ?? '',
      ));
    }
    return fuori;
  }

  /// Lo stesso apparecchio annunciato più volte diventa uno solo.
  ///
  /// Un televisore si annuncia in IPv4 **e** in IPv6: senza raggrupparli, nel
  /// menù comparirebbe due volte con lo stesso nome, e chi lo vede pensa di
  /// avere due televisori.
  ///
  /// Fra le due si tiene l'IPv4: il servizio che dovrà passargli la
  /// fotografia si fa raggiungere lì, e su una rete di casa è quello che
  /// funziona sempre.
  static List<SchermoEsterno> unisci(List<SchermoEsterno> tutti) {
    final trovati = <String, SchermoEsterno>{};
    for (final s in tutti) {
      final chiave = s.id.isEmpty ? '${s.nome}|${s.modo}' : s.id;
      final prima = trovati[chiave];
      if (prima == null || (prima.indirizzo.contains(':')
                            && !s.indirizzo.contains(':'))) {
        trovati[chiave] = s;
      }
    }
    return trovati.values.toList()
      ..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
  }

  /// I campi `TXT` dell'annuncio: `"fn=TV cameretta" "md=AI PONT"`.
  static Map<String, String> leggiTxt(String resto) {
    final fuori = <String, String>{};
    for (final m in RegExp(r'"([^"]*)"').allMatches(resto)) {
      final v = m.group(1)!;
      final i = v.indexOf('=');
      if (i <= 0) continue;
      fuori[v.substring(0, i)] = v.substring(i + 1);
    }
    return fuori;
  }

  /// `avahi-browse` scrive gli spazi come `\032`: «TV\032cameretta».
  ///
  /// **Il numero è DECIMALE, non ottale**, e le tre cifre con lo zero davanti
  /// fanno pensare il contrario: lo spazio è 32 in decimale e 040 in ottale.
  /// Leggendolo in ottale «TV\032cameretta» diventa «TV\x1Acameretta» — cioè
  /// un carattere di controllo invisibile in mezzo al nome del televisore, che
  /// nel menù si vedrebbe come uno spazio storto o come niente. L'ha trovato
  /// la sua prova, scrivendola.
  static String sciogliFuga(String s) => s.replaceAllMapped(
      RegExp(r'\\(\d{3})'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)));
}

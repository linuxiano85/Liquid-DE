import 'dart:io';

import 'processo_limitato.dart';

/// DataOraService — Data, ora, fuso orario e sincronizzazione.
///
/// Mancava del tutto, ed è una delle prime cose che si cerca su un computer
/// appena acceso: l'orologio sta in mezzo alla barra, si vede sempre, e se
/// segna l'ora sbagliata non c'era **nessun** posto in Minerva dove
/// correggerlo — bisognava aprire un terminale e conoscere `timedatectl`.
///
/// ── PERCHÉ `timedatectl show` E NON `timedatectl status` ───────────────────
///
/// `status` stampa un paragrafo per esseri umani, tradotto nella lingua del
/// sistema: su questa macchina dice «Fuso orario: Europe/Rome (CEST, +0200)».
/// Leggerlo con un'espressione regolare vuol dire scrivere un lettore che
/// funziona in italiano e si rompe in inglese — e il guasto sarebbe muto: il
/// pannello mostrerebbe il fuso vuoto senza dire perché.
///
/// `show` stampa `chiave=valore`, sempre uguale in ogni lingua. È l'uscita
/// pensata per essere letta da un programma, ed è quella che usiamo.
///
/// ── I PERMESSI ─────────────────────────────────────────────────────────────
///
/// Cambiare l'ora di sistema tocca tutti gli utenti, quindi `systemd-timedated`
/// chiede a polkit, e polkit chiede la password all'utente con la finestrella
/// dell'agente. Non lo facciamo noi e non ci proviamo: l'agente è già avviato
/// dalla sessione (vedi `hyprland.conf`), e se manca il comando resta appeso
/// invece di fallire — motivo per cui l'errore che riportiamo qui distingue
/// «rifiutato» da «non ha risposto nessuno».
///
/// ── COSA NON FA ────────────────────────────────────────────────────────────
///
/// Non tocca l'orologio hardware in modo diretto e non offre `LocalRTC`: è
/// l'opzione che serve solo a chi ha Windows sullo stesso disco, e messa in
/// una pagina di base fa più danni che altro. Si legge, si mostra se è accesa,
/// e basta.
class DataOraService {
  DataOraService({this.comando = 'timedatectl'});

  /// Iniettabile: le prove non devono cambiare l'ora della macchina.
  final String comando;

  List<String>? _fusiCache;

  /// Lo stato attuale, già pronto per il pannello.
  Future<Map<String, dynamic>> stato() async {
    try {
      final r = await eseguiLimitato(comando, const ['show'],
          limite: const Duration(seconds: 10));
      if (r.scaduto) {
        return _statoVuoto('$comando show non ha risposto');
      }
      if (r.codice != 0) {
        return _statoVuoto('$comando show è uscito con ${r.codice}');
      }
      return statoDaShow(r.stdout);
    } on ProcessException catch (e) {
      // Su un sistema senza systemd `timedatectl` non esiste. Non è un errore
      // da nascondere: la pagina deve poter dire «qui non posso fare niente»
      // invece di mostrare campi vuoti che sembrano un guasto.
      return _statoVuoto('$comando non è disponibile: ${e.message}');
    }
  }

  Map<String, dynamic> _statoVuoto(String motivo) => {
        'timezone': '',
        'ntp': false,
        'ntpPossibile': false,
        'sincronizzato': false,
        'rtcLocale': false,
        'errore': motivo,
      };

  /// L'elenco dei fusi orari, in ordine alfabetico.
  ///
  /// Sono quasi seicento e non cambiano mai mentre il computer è acceso:
  /// si leggono una volta sola. Rileggerli a ogni apertura del pannello
  /// vorrebbe dire lanciare un processo e passare 12 KB sul canale per una
  /// lista identica a quella di prima.
  Future<List<String>> fusi() async {
    final gia = _fusiCache;
    if (gia != null) return gia;
    try {
      final r = await eseguiLimitato(comando, const ['list-timezones'],
          limite: const Duration(seconds: 10));
      if (!r.ok) return const [];
      final lista = r.stdout
          .split('\n')
          .map((r) => r.trim())
          .where((r) => r.isNotEmpty)
          .toList();
      return _fusiCache = lista;
    } on ProcessException {
      return const [];
    }
  }

  /// Cambia il fuso orario.
  Future<Map<String, dynamic>> impostaFuso(String fuso) async {
    // Il controllo non serve contro un'iniezione — `Process.run` senza shell
    // passa l'argomento intero, virgole e punti e virgola compresi. Serve a
    // dare un errore leggibile invece di far comparire la richiesta della
    // password per un comando che fallirà comunque.
    if (!_fusoPlausibile(fuso)) {
      return {'ok': false, 'errore': 'Fuso orario non valido: "$fuso"'};
    }
    final elenco = await fusi();
    if (elenco.isNotEmpty && !elenco.contains(fuso)) {
      return {'ok': false, 'errore': 'Fuso orario sconosciuto: "$fuso"'};
    }
    return _esegui(['set-timezone', fuso]);
  }

  /// Accende o spegne la sincronizzazione automatica dell'ora.
  Future<Map<String, dynamic>> impostaNtp(bool acceso) =>
      _esegui(['set-ntp', acceso ? 'true' : 'false']);

  /// Imposta data e ora a mano. Formato: `AAAA-MM-GG hh:mm:ss`.
  ///
  /// Fallisce di proposito se la sincronizzazione è accesa, e lo dice: è ciò
  /// che fa `timedatectl`, ed è giusto — un'ora scritta a mano mentre il
  /// computer la sta prendendo da internet verrebbe sovrascritta entro un
  /// minuto, e sembrerebbe che il pannello non funzioni.
  Future<Map<String, dynamic>> impostaOra(String quando) async {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}(:\d{2})?$').hasMatch(quando)) {
      return {
        'ok': false,
        'errore': 'Data e ora vanno scritte come "AAAA-MM-GG hh:mm:ss"',
      };
    }
    final s = await stato();
    if (s['ntp'] == true) {
      return {
        'ok': false,
        'errore': 'Spegni prima la sincronizzazione automatica: '
            'con quella accesa l\'ora scritta a mano viene subito rimpiazzata.',
      };
    }
    return _esegui(['set-time', quando]);
  }

  /// ── Il tempo massimo (30 settembre 2026) ─────────────────────────────
  ///
  /// L'intestazione del file promette di distinguere «rifiutato» da «non ha
  /// risposto nessuno», ma qui non c'era nessun limite: senza un agente di
  /// polkit la richiesta restava appesa, e la pagina con lei. Due minuti
  /// bastano a chiunque per scrivere la password nella finestrella.
  Future<Map<String, dynamic>> _esegui(List<String> argomenti) async {
    try {
      final r = await eseguiLimitato(comando, argomenti,
          limite: const Duration(minutes: 2));
      if (r.scaduto) {
        return {
          'ok': false,
          'errore': 'Nessuno ha risposto alla richiesta della password: '
              'manca l\'agente di autorizzazione?',
        };
      }
      if (r.codice == 0) return {'ok': true};
      final detto = (r.stderr.trim().isNotEmpty ? r.stderr : r.stdout).trim();
      return {'ok': false, 'errore': detto.isEmpty ? 'Rifiutato' : detto};
    } on ProcessException catch (e) {
      return {'ok': false, 'errore': e.message};
    }
  }
}

/// Un nome di fuso è `Area/Città`, oppure una delle poche parole singole che
/// systemd accetta (`UTC`). Niente barre iniziali, niente `..`: quelli
/// arriverebbero fino a `timedatectl` e otterrebbero solo una richiesta di
/// password buttata via.
bool _fusoPlausibile(String fuso) {
  if (fuso.isEmpty || fuso.length > 64) return false;
  if (fuso.contains('..') || fuso.startsWith('/') || fuso.endsWith('/')) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+){0,2}$').hasMatch(fuso);
}

/// Traduce l'uscita di `timedatectl show` nella forma che usa il pannello.
///
/// Funzione pura e separata dal servizio: è l'unico pezzo che può sbagliare
/// in silenzio, ed è l'unico che si può provare senza toccare l'orologio della
/// macchina su cui girano le prove.
Map<String, dynamic> statoDaShow(String uscita) {
  final campi = <String, String>{};
  for (final riga in uscita.split('\n')) {
    final i = riga.indexOf('=');
    if (i <= 0) continue;
    campi[riga.substring(0, i).trim()] = riga.substring(i + 1).trim();
  }
  return {
    'timezone': campi['Timezone'] ?? '',
    'ntp': campi['NTP'] == 'yes',
    'ntpPossibile': campi['CanNTP'] == 'yes',
    'sincronizzato': campi['NTPSynchronized'] == 'yes',
    'rtcLocale': campi['LocalRTC'] == 'yes',
  };
}

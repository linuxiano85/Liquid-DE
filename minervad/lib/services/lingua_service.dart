import 'dart:io';

/// LinguaService — La lingua del sistema e le convenzioni locali.
///
/// Minerva è già bilingue: `Strings.qml` traduce tutta l'interfaccia e ogni
/// finestra lega la propria lingua a `general.language`. Mancava **il posto
/// dove sceglierla**: l'impostazione esisteva, aveva un valore di fabbrica
/// («auto»), e nessuna pagina la mostrava. Si poteva cambiare solo scrivendo
/// a mano nel file di configurazione del demone.
///
/// Le lingue sono due cose diverse e vanno tenute separate, perché si
/// comportano in modo diverso:
///
///   · **la lingua di Minerva** è nostra, cambia all'istante e non chiede
///     niente a nessuno: è una proprietà a cui tutta l'interfaccia è legata;
///   · **la lingua del sistema** è di systemd, vale per tutti i programmi
///     (Firefox, il terminale, i menu di KDE), passa da polkit e ha effetto
///     al prossimo accesso. Non c'è modo di farla valere subito, e dirlo è
///     parte del lavoro: senza, si cambia, non succede niente, e sembra rotto.
///
/// ── PERCHÉ SI LEGGE `/etc/locale.conf` E NON `localectl status` ────────────
///
/// Stessa ragione di `DataOraService`: `status` stampa prosa tradotta. Ma qui
/// c'è un motivo in più — questa versione di `localectl` **non ha** il verbo
/// `show`, quindi non esiste nemmeno un'uscita per programmi. `locale.conf` è
/// `chiave=valore`, è il file che `localectl set-locale` scrive, ed è quindi
/// la fonte vera invece che un suo racconto.
class LinguaService {
  const LinguaService({
    this.comando = 'localectl',
    this.percorsoConf = '/etc/locale.conf',
  });

  final String comando;
  final String percorsoConf;

  /// Che cosa è impostato adesso, e che cosa si può scegliere.
  Future<Map<String, dynamic>> stato() async {
    var testo = '';
    try {
      final f = File(percorsoConf);
      if (f.existsSync()) testo = f.readAsStringSync();
    } catch (_) {
      // Illeggibile: si va avanti con l'elenco vuoto. Meglio una pagina che
      // dice «non lo so» di una che indovina.
    }
    final campi = localeDaConf(testo);
    return {
      'lang': campi['LANG'] ?? '',
      'campi': campi,
      'disponibili': await disponibili(),
    };
  }

  /// Le lingue installate sul computer.
  ///
  /// Sono POCHE, non tutte quelle esistenti: su Arch bisogna generarle
  /// (`locale-gen`), e qui ne risultano tre. È giusto mostrare solo queste —
  /// offrire una lingua non generata vorrebbe dire farla scegliere e poi far
  /// ricadere tutto sull'inglese senza spiegazioni.
  Future<List<String>> disponibili() async {
    try {
      final r =
          await Process.run(comando, const ['list-locales'], runInShell: false);
      if (r.exitCode != 0) return const [];
      return (r.stdout as String)
          .split('\n')
          .map((r) => r.trim())
          .where((r) => r.isNotEmpty)
          .toList();
    } on ProcessException {
      return const [];
    }
  }

  /// Cambia la lingua del sistema.
  Future<Map<String, dynamic>> impostaLocale(String locale) async {
    final elenco = await disponibili();
    if (elenco.isNotEmpty && !elenco.contains(locale)) {
      return {
        'ok': false,
        'errore': 'Questa lingua non è installata sul computer: "$locale"',
      };
    }
    if (!RegExp(r'^[A-Za-z0-9_.@-]+$').hasMatch(locale)) {
      return {'ok': false, 'errore': 'Nome di lingua non valido: "$locale"'};
    }

    var testo = '';
    try {
      final f = File(percorsoConf);
      if (f.existsSync()) testo = f.readAsStringSync();
    } catch (_) {}

    try {
      final r = await Process.run(
          comando, argomentiPerCambio(localeDaConf(testo), locale),
          runInShell: false);
      if (r.exitCode == 0) return {'ok': true};
      final detto = ((r.stderr as String).trim().isNotEmpty
              ? r.stderr as String
              : r.stdout as String)
          .trim();
      return {'ok': false, 'errore': detto.isEmpty ? 'Rifiutato' : detto};
    } on ProcessException catch (e) {
      return {'ok': false, 'errore': e.message};
    }
  }
}

/// Legge `LANG=it_IT.UTF-8` e compagni.
Map<String, String> localeDaConf(String testo) {
  final campi = <String, String>{};
  for (final riga in testo.split('\n')) {
    final pulita = riga.trim();
    if (pulita.isEmpty || pulita.startsWith('#')) continue;
    final i = pulita.indexOf('=');
    if (i <= 0) continue;
    final chiave = pulita.substring(0, i).trim();
    if (chiave != 'LANG' && !chiave.startsWith('LC_')) continue;
    campi[chiave] = pulita.substring(i + 1).trim().replaceAll('"', '');
  }
  return campi;
}

/// Quali argomenti passare a `localectl set-locale`.
///
/// **Non basta `LANG=`**, ed è la trappola di questa pagina. Su questa
/// macchina `locale.conf` ha dieci righe: `LANG` più nove `LC_*` tutte
/// inchiodate a `it_IT.UTF-8` — le scrive l'installatore di Arch, e le mette
/// anche KDE. Le `LC_*` hanno la precedenza su `LANG`: cambiando il solo
/// `LANG` in inglese, i menu restano in italiano, le date restano italiane, e
/// da fuori sembra che il comando non abbia fatto niente.
///
/// Quindi si riscrive ogni chiave che c'è GIÀ, e nessuna che non c'era: chi
/// ha impostato apposta `LC_MEASUREMENT` diverso dal resto se lo ritrova
/// cambiato, ma è l'unico modo perché «metti tutto in inglese» faccia quello
/// che dice. Chi non ha nessuna `LC_*` si ritrova con il solo `LANG`.
List<String> argomentiPerCambio(Map<String, String> attuali, String locale) {
  final chiavi = <String>['LANG', ...attuali.keys.where((k) => k != 'LANG')];
  return ['set-locale', for (final k in chiavi) '$k=$locale'];
}

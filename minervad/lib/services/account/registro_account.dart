import 'dart:convert';
import 'dart:io';
import '../../core/minerva_paths.dart';

/// RegistroAccount — l'unico posto in cui vivono gli account online.
///
/// ── Perché uno solo, e perché è importante ─────────────────────────────────
///
/// Perché altrimenti si finisce a fare l'accesso a kDrive **due volte**: una
/// nella Custodia, come posto dove mandare i backup, e una nelle Impostazioni,
/// per vedere lo spazio e avere la cartella. Due accessi vogliono dire due
/// password da tenere aggiornate, due posti dove scade il collegamento, e due
/// volte la stessa fatica per chi usa il computer — che è la definizione di un
/// programma fatto male.
///
/// Quindi: qui dentro. Le Impostazioni li mostrano e li aggiungono, la Custodia
/// li usa come destinazioni. Un account collegato una volta vale per tutti e
/// due.
///
/// ── Cosa NON c'è in questo file ────────────────────────────────────────────
///
/// **Le password.** Mai. Stanno nel portachiavi di sistema, con `secret-tool`,
/// esattamente come il gettone di GitHub (vedi `custodia/github_motore.dart` per
/// il perché lungo). Qui c'è il nome utente, l'indirizzo e a che servizio
/// appartiene: cose che si scrivono su un foglietto senza pensarci.
///
/// È il difetto di serie di `rclone`, che mette le credenziali in chiaro dentro
/// `~/.config/rclone/rclone.conf`: un file che finisce in ogni copia di backup e
/// in ogni punto di ritorno.
class RegistroAccount {
  RegistroAccount({String? percorso}) : percorso = percorso ?? _predefinito();

  final String percorso;
  final List<Account> account = [];

  static String _predefinito() {
    return '${MinervaPaths.config()}/account/account.json';
  }

  Future<void> carica() async {
    account.clear();
    final f = File(percorso);
    if (!await f.exists()) return;
    try {
      final dentro = jsonDecode(await f.readAsString());
      if (dentro is! List) return;
      for (final v in dentro) {
        if (v is Map<String, dynamic>) {
          final a = Account.daJson(v);
          if (a != null) account.add(a);
        }
      }
    } catch (_) {
      // Un file rotto non deve impedire di aggiungerne uno nuovo: si riparte
      // da vuoto invece di rifiutarsi di funzionare.
    }
  }

  /// Si scrive accanto e si rinomina, come ogni file di stato di Minerva: un
  /// registro mezzo scritto è un account che sparisce.
  Future<void> salva() async {
    final f = File(percorso);
    await f.parent.create(recursive: true);
    final nuovo = File('$percorso.nuovo');
    await nuovo.writeAsString(
        const JsonEncoder.withIndent('  ').convert([
          for (final a in account) a.toJson(),
        ]),
        flush: true);
    await nuovo.rename(percorso);
  }

  Account? cerca(String id) {
    for (final a in account) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// La chiave con cui l'account si nomina, e con cui la sua password sta nel
  /// portachiavi.
  ///
  /// Si costruisce dal servizio e dal nome utente e **non cambia** se si
  /// modifica l'indirizzo: è la chiave di una password, e una chiave che
  /// cambia è una password che si perde.
  static String chiaveDa(String servizio, String utente) {
    final pulito = utente.trim().toLowerCase().replaceAll(
        RegExp(r'[^a-z0-9._@-]'), '-');
    return '$servizio:$pulito';
  }
}

/// Un account collegato. Senza password: quella sta nel portachiavi.
class Account {
  Account({
    required this.id,
    required this.servizio,
    required this.nome,
    required this.utente,
    required this.url,
    this.aggiunto,
    this.ultimaProva,
    this.funziona,
  });

  /// `kdrive:mario@example.it`. Vedi `RegistroAccount.chiaveDa`.
  final String id;

  /// `kdrive`, `webdav`, `github`. È quello che decide con che motore parlarci.
  final String servizio;

  /// Il nome che si vede: «kDrive di casa». Lo sceglie chi lo aggiunge.
  String nome;

  final String utente;
  String url;

  final DateTime? aggiunto;

  /// Quando si è provato l'ultima volta, e com'è andata. Si mostrano insieme:
  /// «funziona» senza «quando» è una rassicurazione che non si può verificare.
  DateTime? ultimaProva;
  bool? funziona;

  static Account? daJson(Map<String, dynamic> j) {
    final id = j['id'];
    final servizio = j['servizio'];
    final utente = j['utente'];
    if (id is! String || servizio is! String || utente is! String) return null;
    return Account(
      id: id,
      servizio: servizio,
      nome: '${j['nome'] ?? utente}',
      utente: utente,
      url: '${j['url'] ?? ''}',
      aggiunto: DateTime.tryParse('${j['aggiunto']}'),
      ultimaProva: DateTime.tryParse('${j['ultimaProva']}'),
      funziona: j['funziona'] is bool ? j['funziona'] as bool : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'servizio': servizio,
        'nome': nome,
        'utente': utente,
        'url': url,
        if (aggiunto != null) 'aggiunto': aggiunto!.toIso8601String(),
        if (ultimaProva != null) 'ultimaProva': ultimaProva!.toIso8601String(),
        if (funziona != null) 'funziona': funziona,
      };
}

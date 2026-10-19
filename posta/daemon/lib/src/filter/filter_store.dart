import 'dart:convert';

import '../db/database.dart';
import 'bayes.dart';

/// Come si comporta il filtro.
enum FilterMode {
  /// Non giudica niente.
  off,

  /// Giudica e segna (etichetta "Pubblicità?" nella lista), non sposta.
  /// È il modo iniziale: l'utente vede i giudizi prima di fidarsi.
  mark,

  /// Sposta nel Cestino le pubblicità sicure. Solo per scelta dell'utente.
  move,
}

enum FilterLabel { ad, ham }

/// Persistenza del filtro: conteggi delle parole, addestramenti, registro.
class FilterStore {
  FilterStore(this.database);

  final MailDatabase database;

  String? _state(String key) {
    final rows = database.db.select('SELECT value FROM filter_state WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first.columnAt(0) as String;
  }

  void _setState(String key, String value) => database.db.execute(
      'INSERT INTO filter_state(key, value) VALUES (?, ?) '
      'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [key, value]);

  FilterMode get mode => FilterMode.values.asNameMap()[_state('mode')] ?? FilterMode.mark;
  set mode(FilterMode m) => _setState('mode', m.name);

  int get totalAds => int.tryParse(_state('totalAds') ?? '') ?? 0;
  int get totalHams => int.tryParse(_state('totalHams') ?? '') ?? 0;

  /// Conteggi delle parole indicate (le parole mai viste non compaiono).
  Map<String, TokenCounts> counts(Iterable<String> tokens) {
    final list = tokens.toList();
    final out = <String, TokenCounts>{};
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(i, i + 500 > list.length ? list.length : i + 500);
      final marks = List.filled(chunk.length, '?').join(',');
      for (final r in database.db
          .select('SELECT token, ad, ham FROM filter_tokens WHERE token IN ($marks)', chunk)) {
        out[r['token'] as String] = (ad: r['ad'] as int, ham: r['ham'] as int);
      }
    }
    return out;
  }

  /// Etichetta con cui è stata imparata l'email [key], o null.
  FilterLabel? trainedLabel(String key) {
    final rows = database.db.select('SELECT label FROM filter_trained WHERE key = ?', [key]);
    return rows.isEmpty ? null : FilterLabel.values.byName(rows.first.columnAt(0) as String);
  }

  /// Impara che l'email [key], con queste parole, è [label]. Se era già
  /// stata imparata al contrario, prima si toglie quell'addestramento: il
  /// modello resta quello che sarebbe se l'utente non avesse mai sbagliato.
  /// Ripetere lo stesso addestramento non cambia niente.
  void train(String key, Set<String> tokens, FilterLabel label) {
    database.transaction(() {
      final previous = database.db
          .select('SELECT label, tokens FROM filter_trained WHERE key = ?', [key]);
      if (previous.isNotEmpty) {
        final oldLabel = FilterLabel.values.byName(previous.first['label'] as String);
        if (oldLabel == label) return;
        final oldTokens = (jsonDecode(previous.first['tokens'] as String) as List).cast<String>();
        _apply(oldTokens, oldLabel, -1);
      }
      _apply(tokens, label, 1);
      database.db.execute(
          'INSERT INTO filter_trained(key, label, tokens) VALUES (?, ?, ?) '
          'ON CONFLICT(key) DO UPDATE SET label = excluded.label, tokens = excluded.tokens',
          [key, label.name, jsonEncode(tokens.toList())]);
    });
  }

  void _apply(Iterable<String> tokens, FilterLabel label, int delta) {
    final column = label == FilterLabel.ad ? 'ad' : 'ham';
    final stmt = database.db.prepare(
        'INSERT INTO filter_tokens(token, $column) VALUES (?, max(?, 0)) '
        'ON CONFLICT(token) DO UPDATE SET $column = max($column + ?, 0)');
    try {
      for (final t in tokens) {
        stmt.execute([t, delta, delta]);
      }
    } finally {
      stmt.close();
    }
    database.db.execute('DELETE FROM filter_tokens WHERE ad = 0 AND ham = 0');
    final key = label == FilterLabel.ad ? 'totalAds' : 'totalHams';
    final current = label == FilterLabel.ad ? totalAds : totalHams;
    _setState(key, '${(current + delta).clamp(0, 1 << 40)}');
  }

  /// Parole con cui il filtro ha giudicato la riga [messageId] di messages.
  void rememberTokens(int messageId, Set<String> tokens, int score) {
    database.db.execute(
        'INSERT INTO filter_message_tokens(message_id, tokens) VALUES (?, ?) '
        'ON CONFLICT(message_id) DO UPDATE SET tokens = excluded.tokens',
        [messageId, jsonEncode(tokens.toList())]);
    database.db.execute('UPDATE messages SET spam_score = ? WHERE id = ?', [score, messageId]);
  }

  Set<String>? tokensOf(int messageId) {
    final rows = database.db
        .select('SELECT tokens FROM filter_message_tokens WHERE message_id = ?', [messageId]);
    if (rows.isEmpty) return null;
    return (jsonDecode(rows.first.columnAt(0) as String) as List).cast<String>().toSet();
  }

  /// Chiave di addestramento e dati salvati di una riga di messages, o null
  /// se la riga non esiste. La chiave è il Message-ID (resta uguale quando
  /// l'email cambia cartella); senza, la riga stessa.
  ({String key, String subject, String? fromAddress, String bodyText})? storedMessage(int id) {
    final rows = database.db.select(
        'SELECT message_id, subject, from_address, body_text FROM messages WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final mid = r['message_id'] as String?;
    return (
      key: (mid != null && mid.trim().isNotEmpty) ? mid.trim() : 'riga:$id',
      subject: r['subject'] as String,
      fromAddress: r['from_address'] as String?,
      bodyText: (r['body_text'] as String?) ?? '',
    );
  }

  /// L'utente ha scritto a questo indirizzo (è tra i destinatari di
  /// un'email in una cartella "Inviata") o lo ha in rubrica.
  bool isKnownCorrespondent(String address) {
    final a = address.toLowerCase();
    final rows = database.db.select('''
      SELECT 1 FROM contact_addresses WHERE address = ?1
      UNION ALL
      SELECT 1 FROM messages m JOIN folders f ON f.id = m.folder_id
      WHERE f.role = 'sent' AND (
        EXISTS (SELECT 1 FROM json_each(m.to_json) WHERE lower(value) = ?1) OR
        EXISTS (SELECT 1 FROM json_each(m.cc_json) WHERE lower(value) = ?1))
      LIMIT 1''', [a]);
    return rows.isNotEmpty;
  }

  /// Il Message-ID indicato è di un'email inviata dall'utente.
  bool isOwnMessage(String messageId) => database.db.select('''
      SELECT 1 FROM messages m JOIN folders f ON f.id = m.folder_id
      WHERE f.role = 'sent' AND m.message_id = ? LIMIT 1''', [messageId]).isNotEmpty;

  int recordAction({
    required int accountId,
    required String messageKey,
    required String subject,
    required String? fromAddress,
    required int score,
    required String action,
    DateTime? at,
  }) {
    database.db.execute('''
      INSERT INTO filter_actions(account_id, message_key, subject, from_address, score, action, at)
      VALUES (?, ?, ?, ?, ?, ?, ?)''', [
      accountId, messageKey, subject, fromAddress, score, action,
      (at ?? DateTime.now()).millisecondsSinceEpoch,
    ]);
    return database.db.lastInsertRowId;
  }

  void markUndone(int actionId) =>
      database.db.execute('UPDATE filter_actions SET undone = 1 WHERE id = ?', [actionId]);

  /// Quante email sono state segnate e spostate da [since] in poi.
  ({int marked, int moved}) summarySince(DateTime since) {
    final rows = database.db.select('''
      SELECT action, count(*) AS n FROM filter_actions
      WHERE at >= ? AND undone = 0 GROUP BY action''', [since.millisecondsSinceEpoch]);
    var marked = 0;
    var moved = 0;
    for (final r in rows) {
      if (r['action'] == 'marked') marked = r['n'] as int;
      if (r['action'] == 'moved') moved = r['n'] as int;
    }
    return (marked: marked, moved: moved);
  }
}

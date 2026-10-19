import 'dart:convert';

import '../db/database.dart';
import '../db/mail_store.dart';
import '../mime/message_content.dart';
import '../mime/message_reader.dart';

/// Stato del corpo di un messaggio (colonna `body_state`).
abstract final class BodyState {
  /// Scaricato, letto e salvato.
  static const saved = 1;

  /// Troppo grande per lo scaricamento automatico: si scarica all'apertura.
  static const tooLarge = 2;

  /// Illeggibile (il parser è stato fermato): mai riprovato in automatico.
  static const unreadable = 3;
}

/// Dove sta un messaggio: serve per agire sul server.
class MessageLocation {
  MessageLocation(this.messageId, this.accountId, this.folderId, this.path, this.role, this.uid);
  final int messageId;
  final int accountId;
  final int folderId;
  final String path;
  final String role;
  final int uid;
}

/// Letture per l'interfaccia e salvataggio dei corpi.
class MessageStore {
  MessageStore(this.database);

  final MailDatabase database;

  static Map<String, Object?> _flagsJson(int flags) => {
        'seen': flags & MessageFlags.seen != 0,
        'flagged': flags & MessageFlags.flagged != 0,
        'answered': flags & MessageFlags.answered != 0,
      };

  /// Cartelle con i conteggi; di un account o di tutti.
  List<Map<String, Object?>> folders({int? accountId}) {
    final rows = database.db.select('''
      SELECT f.id, f.account_id, f.path, f.role,
        (SELECT count(*) FROM messages m WHERE m.folder_id = f.id) AS total,
        (SELECT count(*) FROM messages m WHERE m.folder_id = f.id AND (m.flags & 1) = 0) AS unread
      FROM folders f
      ${accountId == null ? '' : 'WHERE f.account_id = ?'}
      ORDER BY f.account_id,
        CASE f.role WHEN 'inbox' THEN 0 WHEN 'drafts' THEN 1 WHEN 'sent' THEN 2
          WHEN 'archive' THEN 3 WHEN 'spam' THEN 4 WHEN 'trash' THEN 5 ELSE 6 END,
        f.path COLLATE NOCASE''', [?accountId]);
    return [
      for (final r in rows)
        {
          'id': r['id'],
          'accountId': r['account_id'],
          'path': r['path'],
          'role': r['role'],
          'name': folderDisplayName(r['path'] as String),
          'total': r['total'],
          'unread': r['unread'],
        }
    ];
  }

  /// Nome breve di una cartella: l'ultimo pezzo del percorso ("[Gmail]/Spam"
  /// → "Spam", "Lavoro.Clienti" → "Clienti").
  static String folderDisplayName(String path) {
    final parts = path.split(RegExp(r'[/.]'));
    return parts.lastWhere((p) => p.isNotEmpty, orElse: () => path);
  }

  static const _summaryColumns = '''
      m.id, m.folder_id, f.account_id, m.uid, m.subject, m.from_name, m.from_address, m.date,
      m.flags, m.ad_marked, substr(coalesce(m.body_text, ''), 1, 240) AS preview,
      (m.attachment_names != '' OR EXISTS (SELECT 1 FROM attachments a
         WHERE a.message_id = m.id AND a.kind IN ('file', 'message'))) AS has_attachments''';

  Map<String, Object?> _summary(Map<String, Object?> r) => {
        'id': r['id'],
        'folderId': r['folder_id'],
        'accountId': r['account_id'],
        'uid': r['uid'],
        'subject': r['subject'],
        'fromName': r['from_name'],
        'fromAddress': r['from_address'],
        'date': r['date'],
        ..._flagsJson(r['flags'] as int),
        'adMarked': r['ad_marked'] == 1,
        'preview': (r['preview'] as String).replaceAll(RegExp(r'\s+'), ' ').trim(),
        'hasAttachments': r['has_attachments'] == 1,
      };

  /// Pagina della lista di una cartella, dal più recente. [cursor] è
  /// `{date, id}` dell'ultimo della pagina precedente.
  ({List<Map<String, Object?>> messages, Map<String, int>? next}) list(int folderId,
      {int limit = 50, ({int date, int id})? cursor}) {
    if (limit < 1 || limit > 500) throw RangeError.range(limit, 1, 500, 'limit');
    final rows = database.db.select('''
      SELECT $_summaryColumns FROM messages m JOIN folders f ON f.id = m.folder_id
      WHERE m.folder_id = ? ${cursor == null ? '' : 'AND (m.date, m.id) < (?, ?)'}
      ORDER BY m.date DESC, m.id DESC LIMIT ?''',
        [folderId, if (cursor != null) ...[cursor.date, cursor.id], limit + 1]);
    final page = [for (final r in rows.take(limit)) _summary(r)];
    final more = rows.length > limit;
    return (
      messages: page,
      next: more ? {'date': page.last['date'] as int, 'id': page.last['id'] as int} : null,
    );
  }

  /// Ricerca in tutto l'indice (oggetto, corpo, mittente, nomi degli allegati).
  List<Map<String, Object?>> search(String query, {int limit = 50, int? accountId}) {
    final q = buildFtsQuery(query);
    if (q.isEmpty) return const [];
    final rows = database.db.select('''
      SELECT $_summaryColumns FROM fts_messages s
      JOIN messages m ON m.id = s.rowid JOIN folders f ON f.id = m.folder_id
      WHERE fts_messages MATCH ? ${accountId == null ? '' : 'AND f.account_id = ?'}
      ORDER BY m.date DESC LIMIT ?''', [q, ?accountId, limit]);
    return [for (final r in rows) _summary(r)];
  }

  MessageLocation? locate(int messageId) {
    final rows = database.db.select('''
      SELECT m.id, f.account_id, f.id AS folder_id, f.path, f.role, m.uid
      FROM messages m JOIN folders f ON f.id = m.folder_id WHERE m.id = ?''', [messageId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return MessageLocation(r['id'] as int, r['account_id'] as int, r['folder_id'] as int,
        r['path'] as String, r['role'] as String, r['uid'] as int);
  }

  /// Cartella di un account con il ruolo indicato ('trash', 'sent'...).
  ({int id, String path})? folderByRole(int accountId, String role) {
    final rows = database.db.select(
        'SELECT id, path FROM folders WHERE account_id = ? AND role = ? ORDER BY id LIMIT 1',
        [accountId, role]);
    return rows.isEmpty ? null : (id: rows.first['id'] as int, path: rows.first['path'] as String);
  }

  ({int id, String path, int accountId})? folder(int folderId) {
    final rows = database.db.select('SELECT id, path, account_id FROM folders WHERE id = ?', [folderId]);
    return rows.isEmpty
        ? null
        : (id: folderId, path: rows.first['path'] as String, accountId: rows.first['account_id'] as int);
  }

  int? bodyState(int messageId) => database.db
      .select('SELECT body_state FROM messages WHERE id = ?', [messageId]).firstOrNull?['body_state'] as int?;

  void setBodyState(int messageId, int state) => database.db
      .execute('UPDATE messages SET body_state = ? WHERE id = ?', [state, messageId]);

  /// Messaggi senza corpo, dal più recente: da scaricare in sottofondo.
  List<({int id, int uid})> needingBody(int folderId, {int limit = 50}) => [
        for (final r in database.db.select('''
          SELECT id, uid FROM messages WHERE folder_id = ? AND body_state IS NULL
          ORDER BY date DESC, id DESC LIMIT ?''', [folderId, limit]))
          (id: r['id'] as int, uid: r['uid'] as int),
      ];

  /// Salva il corpo letto e l'elenco degli allegati ([shaByIndex]: SHA-256
  /// del file salvato per ogni allegato, nello stesso ordine). Tutto in una
  /// transazione: indice di ricerca compreso (lo aggiornano i trigger).
  void saveBody(int messageId, ReadMessage read, List<String> shaByIndex) {
    if (shaByIndex.length != read.attachments.length) {
      throw ArgumentError('un hash per allegato');
    }
    final visible = [
      for (final a in read.attachments)
        if (a.kind == AttachmentKind.file || a.kind == AttachmentKind.message) a.filename,
    ];
    database.transaction(() {
      database.db.execute('''
        UPDATE messages SET body_text = ?, body_html_sanitized = ?, attachment_names = ?,
          body_state = ?, body_meta = ? WHERE id = ?''', [
        read.textPlain,
        read.html?.html,
        visible.join(' '),
        BodyState.saved,
        jsonEncode({
          'remoteImagesBlocked': read.html?.remoteImagesBlocked ?? 0,
          'trackersRemoved': read.html?.trackersRemoved ?? 0,
          'linksCleaned': read.html?.linksCleaned ?? 0,
          'deceptiveLinks': read.html?.deceptiveLinks ?? 0,
          'encrypted': read.encrypted,
          'defects': read.defects.take(20).toList(),
        }),
        messageId,
      ]);
      database.db.execute('DELETE FROM attachments WHERE message_id = ?', [messageId]);
      for (var i = 0; i < read.attachments.length; i++) {
        final a = read.attachments[i];
        database.db.execute('''
          INSERT INTO attachments(message_id, sha256, filename, mime, size, kind, content_id)
          VALUES (?, ?, ?, ?, ?, ?, ?)''',
            [messageId, shaByIndex[i], a.filename, a.mimeType, a.size, a.kind.name, a.contentId]);
      }
    });
  }

  /// Tutto ciò che la vista di lettura mostra di un messaggio salvato.
  Map<String, Object?>? detail(int messageId) {
    final rows = database.db.select('''
      SELECT m.*, f.account_id, f.path, f.role FROM messages m JOIN folders f ON f.id = m.folder_id
      WHERE m.id = ?''', [messageId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    final meta = r['body_meta'] == null
        ? const <String, Object?>{}
        : jsonDecode(r['body_meta'] as String) as Map<String, Object?>;
    return {
      'id': r['id'],
      'accountId': r['account_id'],
      'folderId': r['folder_id'],
      'folderRole': r['role'],
      'uid': r['uid'],
      'messageId': r['message_id'],
      'subject': r['subject'],
      'fromName': r['from_name'],
      'fromAddress': r['from_address'],
      'to': jsonDecode(r['to_json'] as String),
      'cc': jsonDecode(r['cc_json'] as String),
      'date': r['date'],
      ..._flagsJson(r['flags'] as int),
      'adMarked': r['ad_marked'] == 1,
      'bodyState': r['body_state'],
      'text': r['body_text'],
      'html': r['body_html_sanitized'],
      ...meta,
      'attachments': attachments(messageId),
    };
  }

  List<Map<String, Object?>> attachments(int messageId) => [
        for (final a in database.db.select('''
          SELECT id, sha256, filename, mime, size, kind, content_id FROM attachments
          WHERE message_id = ? ORDER BY id''', [messageId]))
          {
            'id': a['id'],
            'sha256': a['sha256'],
            'filename': a['filename'],
            'mime': a['mime'],
            'size': a['size'],
            'kind': a['kind'],
            'contentId': a['content_id'],
          }
      ];

  Map<String, Object?>? attachment(int attachmentId) {
    final rows = database.db.select(
        'SELECT id, message_id, sha256, filename, mime, size FROM attachments WHERE id = ?',
        [attachmentId]);
    if (rows.isEmpty) return null;
    final a = rows.first;
    return {
      'id': a['id'], 'messageId': a['message_id'], 'sha256': a['sha256'],
      'filename': a['filename'], 'mime': a['mime'], 'size': a['size'],
    };
  }

  /// Hash degli allegati ancora citati (per la pulizia dell'archivio).
  Set<String> referencedAttachmentHashes() =>
      {for (final r in database.db.select('SELECT DISTINCT sha256 FROM attachments')) r['sha256'] as String};

  /// Applica subito in locale un cambio di flag fatto dall'utente: la lista
  /// si aggiorna senza aspettare il server (la sync poi conferma).
  void applyFlags(List<int> messageIds, int mask, {required bool add}) {
    if (messageIds.isEmpty) return;
    final marks = List.filled(messageIds.length, '?').join(',');
    database.db.execute(
        add
            ? 'UPDATE messages SET flags = flags | ? WHERE id IN ($marks)'
            : 'UPDATE messages SET flags = flags & ~? WHERE id IN ($marks)',
        [mask, ...messageIds]);
  }

  /// Toglie i messaggi dalla cartella locale (spostati o cancellati).
  void removeLocal(List<int> messageIds) {
    if (messageIds.isEmpty) return;
    final marks = List.filled(messageIds.length, '?').join(',');
    database.db.execute('DELETE FROM messages WHERE id IN ($marks)', messageIds);
  }

  void setAdMarked(int messageId, bool marked) => database.db
      .execute('UPDATE messages SET ad_marked = ? WHERE id = ?', [marked ? 1 : 0, messageId]);
}

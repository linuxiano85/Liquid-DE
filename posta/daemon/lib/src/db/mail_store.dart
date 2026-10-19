import 'dart:convert';

import 'database.dart';

/// Flag IMAP come bitmask, così una sola colonna intera li contiene tutti.
abstract final class MessageFlags {
  static const seen = 1;
  static const answered = 2;
  static const flagged = 4;
  static const deleted = 8;
  static const draft = 16;
}

class AccountRecord {
  const AccountRecord({
    required this.name,
    required this.email,
    required this.provider,
    required this.imapHost,
    required this.imapPort,
    required this.smtpHost,
    required this.smtpPort,
    required this.authMethod,
    this.secretRef,
    this.username,
    this.imapSecurity = 'tls',
    this.smtpSecurity = 'tls',
    this.trustedCertSha256,
    this.id,
  });

  /// Assegnato dal database; null prima dell'inserimento.
  final int? id;

  /// Nome utente per il login; null = l'indirizzo email.
  final String? username;

  /// 'tls' o 'starttls'.
  final String imapSecurity;
  final String smtpSecurity;

  /// Impronta del certificato approvato dall'utente, minuscola.
  final String? trustedCertSha256;

  String get loginName => username ?? email;

  final String name;
  final String email;
  final String provider;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;

  /// 'password', 'oauth2' o 'bridge'.
  final String authMethod;

  /// Chiave dell'elemento in libsecret: la password non passa mai di qui.
  final String? secretRef;
}

class MessageRecord {
  const MessageRecord({
    required this.uid,
    required this.date,
    this.messageId,
    this.inReplyTo,
    this.references,
    this.fromAddress,
    this.fromName,
    this.to = const [],
    this.cc = const [],
    this.subject = '',
    this.flags = 0,
    this.bodyText,
    this.bodyHtmlSanitized,
    this.attachmentNames = const [],
  });

  final int uid;
  final DateTime date;
  final String? messageId;
  final String? inReplyTo;
  final String? references;
  final String? fromAddress;
  final String? fromName;
  final List<String> to;
  final List<String> cc;
  final String subject;
  final int flags;
  final String? bodyText;
  final String? bodyHtmlSanitized;
  final List<String> attachmentNames;
}

class StoredMessage {
  StoredMessage(this.id, this.folderId, this.uid, this.subject, this.fromAddress,
      this.date, this.flags);

  final int id;
  final int folderId;
  final int uid;
  final String subject;
  final String? fromAddress;
  final DateTime date;
  final int flags;
}

class FolderSyncState {
  const FolderSyncState({this.uidValidity, this.highestModseq, this.uidNext});
  final int? uidValidity;
  final int? highestModseq;
  final int? uidNext;
}

/// Posizione nella lista messaggi, opaca per la UI.
class PageCursor {
  const PageCursor(this.dateMillis, this.id);

  factory PageCursor.of(StoredMessage m) =>
      PageCursor(m.date.millisecondsSinceEpoch, m.id);

  final int dateMillis;
  final int id;
}

/// Normalizza un indirizzo email per confrontare i contatti:
/// toglie spazi e parentesi angolari, porta tutto in minuscolo.
/// Restituisce null se non sembra un indirizzo valido.
String? normalizeAddress(String raw) {
  var s = raw.trim();
  final lt = s.lastIndexOf('<');
  final gt = s.lastIndexOf('>');
  if (lt >= 0 && gt > lt) s = s.substring(lt + 1, gt);
  s = s.trim().toLowerCase();
  final at = s.indexOf('@');
  if (at <= 0 || at != s.lastIndexOf('@') || at == s.length - 1) return null;
  if (s.contains(RegExp(r'\s'))) return null;
  final domain = s.substring(at + 1);
  if (!domain.contains('.') || domain.startsWith('.') || domain.endsWith('.')) {
    return null;
  }
  return s;
}

/// Trasforma il testo digitato dall'utente in una query FTS5 sicura.
///
/// FTS5 ha una sua sintassi (AND, OR, NEAR, virgolette, asterischi, due punti):
/// passare il testo così com'è farebbe fallire la query con un errore di
/// sintassi appena l'utente scrive un apice o una parola come "OR".
/// Ogni parola diventa una frase tra virgolette; l'ultima vale come prefisso,
/// così la ricerca funziona mentre si digita.
String buildFtsQuery(String userInput) {
  // I caratteri di controllo (NUL compreso) troncano la stringa nel parser
  // FTS5 e producono "unterminated string": possono arrivare incollando
  // testo da PDF o pagine web, quindi vanno tolti.
  final words = userInput
      .replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]'), '')
      .split(RegExp(r'\s+'))
      .map((w) => w.trim())
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '';
  final quoted = [for (final w in words) '"${w.replaceAll('"', '""')}"'];
  quoted[quoted.length - 1] = '${quoted.last}*';
  return quoted.join(' ');
}

/// Accesso ai dati di posta. Tutte le scritture multiple sono atomiche.
class MailStore {
  MailStore(this.database);

  final MailDatabase database;

  int addAccount(AccountRecord a) {
    database.db.execute('''
      INSERT INTO accounts (name, email, provider, imap_host, imap_port,
        smtp_host, smtp_port, auth_method, secret_ref, created_at,
        username, imap_security, smtp_security, trusted_cert_sha256)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [
      a.name, a.email, a.provider, a.imapHost, a.imapPort, a.smtpHost,
      a.smtpPort, a.authMethod, a.secretRef,
      DateTime.now().millisecondsSinceEpoch,
      a.username, a.imapSecurity, a.smtpSecurity, a.trustedCertSha256,
    ]);
    return database.db.lastInsertRowId;
  }

  /// Cambia il modo di accesso (password ↔ OAuth) di un account esistente.
  void setAccountAuth(int accountId, {required String authMethod, required String secretRef}) =>
      database.db.execute('UPDATE accounts SET auth_method = ?, secret_ref = ? WHERE id = ?',
          [authMethod, secretRef, accountId]);

  int? accountIdByEmail(String email) {
    final rows = database.db
        .select('SELECT id FROM accounts WHERE email = ? COLLATE NOCASE', [email]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  void deleteAccount(int accountId) =>
      database.db.execute('DELETE FROM accounts WHERE id = ?', [accountId]);

  bool accountExists(String email) => database.db
      .select('SELECT 1 FROM accounts WHERE email = ? COLLATE NOCASE', [email])
      .isNotEmpty;

  List<AccountRecord> listAccounts() => [
        for (final r in database.db.select('SELECT * FROM accounts ORDER BY id'))
          _toAccount(r),
      ];

  AccountRecord? getAccount(int id) {
    final rows = database.db.select('SELECT * FROM accounts WHERE id = ?', [id]);
    return rows.isEmpty ? null : _toAccount(rows.first);
  }

  AccountRecord _toAccount(Map<String, Object?> r) => AccountRecord(
        id: r['id'] as int,
        name: r['name'] as String,
        email: r['email'] as String,
        provider: r['provider'] as String,
        imapHost: r['imap_host'] as String,
        imapPort: r['imap_port'] as int,
        smtpHost: r['smtp_host'] as String,
        smtpPort: r['smtp_port'] as int,
        authMethod: r['auth_method'] as String,
        secretRef: r['secret_ref'] as String?,
        username: r['username'] as String?,
        imapSecurity: r['imap_security'] as String,
        smtpSecurity: r['smtp_security'] as String,
        trustedCertSha256: r['trusted_cert_sha256'] as String?,
      );

  int upsertFolder(int accountId, String path, {String role = 'other'}) {
    database.db.execute('''
      INSERT INTO folders (account_id, path, role) VALUES (?, ?, ?)
      ON CONFLICT (account_id, path) DO UPDATE SET role = excluded.role''',
        [accountId, path, role]);
    return database.db.select(
        'SELECT id FROM folders WHERE account_id = ? AND path = ?',
        [accountId, path]).first.columnAt(0) as int;
  }

  /// Stato registrato all'ultima sincronizzazione COMPLETATA della cartella.
  FolderSyncState folderSyncState(int folderId) {
    final rows = database.db.select(
        'SELECT uidvalidity, highest_modseq, uid_next FROM folders WHERE id = ?', [folderId]);
    if (rows.isEmpty) throw StateError('Cartella $folderId inesistente');
    final r = rows.first;
    return FolderSyncState(
      uidValidity: r['uidvalidity'] as int?,
      highestModseq: r['highest_modseq'] as int?,
      uidNext: r['uid_next'] as int?,
    );
  }

  /// Primo passo di ogni sync: confronta UIDVALIDITY. Se è cambiata, svuota
  /// la cartella e azzera MODSEQ e UIDNEXT (sync iniziale). Restituisce true
  /// in caso di reset. Non tocca MODSEQ/UIDNEXT se non cambia nulla: quelli
  /// si salvano solo a sync completata ([commitFolderSync]).
  bool applyUidValidity(int folderId, int uidValidity) {
    return database.transaction(() {
      final previous = folderSyncState(folderId).uidValidity;
      if (previous == uidValidity) return false;
      if (previous != null) {
        database.db.execute('DELETE FROM messages WHERE folder_id = ?', [folderId]);
      }
      database.db.execute(
          'UPDATE folders SET uidvalidity = ?, highest_modseq = NULL, uid_next = NULL WHERE id = ?',
          [uidValidity, folderId]);
      return previous != null;
    });
  }

  /// Ultimo passo di una sync riuscita. Se la sync si interrompe prima,
  /// MODSEQ e UIDNEXT restano quelli vecchi e la prossima sync rifà il
  /// lavoro: tutto è idempotente, quindi nessun duplicato e nulla di perso.
  void commitFolderSync(int folderId, {int? highestModseq, required int uidNext}) {
    if (uidNext < 1) throw RangeError.value(uidNext, 'uidNext');
    database.db.execute(
        'UPDATE folders SET highest_modseq = ?, uid_next = ? WHERE id = ?',
        [highestModseq, uidNext, folderId]);
  }

  Set<int> localUids(int folderId) => {
        for (final r in database.db.select('SELECT uid FROM messages WHERE folder_id = ?', [folderId]))
          r['uid'] as int,
      };

  /// Allinea l'elenco cartelle dell'account a quello del server: aggiunge le
  /// nuove, aggiorna i ruoli, elimina quelle sparite (con i loro messaggi).
  /// Restituisce percorso → id.
  Map<String, int> syncFolderList(int accountId, List<({String path, String role})> remote) {
    return database.transaction(() {
      final ids = <String, int>{};
      for (final f in remote) {
        ids[f.path] = upsertFolder(accountId, f.path, role: f.role);
      }
      final existing = database.db.select('SELECT id, path FROM folders WHERE account_id = ?', [accountId]);
      for (final r in existing) {
        if (!ids.containsKey(r['path'])) {
          database.db.execute('DELETE FROM folders WHERE id = ?', [r['id']]);
        }
      }
      return ids;
    });
  }

  int? messageIdForUid(int folderId, int uid) {
    final rows = database.db.select('SELECT id FROM messages WHERE folder_id = ? AND uid = ?', [folderId, uid]);
    return rows.isEmpty ? null : rows.first['id'] as int;
  }

  /// Aggiorna lo stato di sincronizzazione di una cartella.
  ///
  /// Se UIDVALIDITY è cambiata, il server ha rinumerato i messaggi: gli UID
  /// locali non valgono più nulla e la cartella va svuotata e riscaricata
  /// (RFC 3501, sezione 2.3.1.1). Restituisce true in quel caso.
  bool updateFolderSyncState(int folderId,
      {required int uidValidity, int? highestModseq}) {
    return database.transaction(() {
      final row = database.db
          .select('SELECT uidvalidity FROM folders WHERE id = ?', [folderId]);
      if (row.isEmpty) throw StateError('Cartella $folderId inesistente');
      final previous = row.first.columnAt(0) as int?;
      final reset = previous != null && previous != uidValidity;
      if (reset) {
        database.db.execute('DELETE FROM messages WHERE folder_id = ?', [folderId]);
      }
      database.db.execute(
          'UPDATE folders SET uidvalidity = ?, highest_modseq = ? WHERE id = ?',
          [uidValidity, reset ? null : highestModseq, folderId]);
      return reset;
    });
  }

  /// Inserisce o aggiorna più messaggi in un'unica transazione.
  /// Se uno solo fallisce, nessuno viene salvato.
  void upsertMessages(int folderId, List<MessageRecord> messages) {
    if (messages.isEmpty) return;
    database.transaction(() {
      final stmt = database.db.prepare('''
        INSERT INTO messages (folder_id, uid, message_id, in_reply_to,
          references_header, from_address, from_name, to_json, cc_json,
          subject, date, flags, body_text, body_html_sanitized, attachment_names)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (folder_id, uid) DO UPDATE SET
          -- In IMAP un messaggio con un dato UID è immutabile: cambiano solo
          -- i flag. Intestazioni e oggetto restano quelli già salvati; il corpo
          -- e gli allegati si completano solo se prima mancavano (scaricamento
          -- del corpo su richiesta, dopo le sole intestazioni).
          flags = excluded.flags,
          body_text = COALESCE(messages.body_text, excluded.body_text),
          body_html_sanitized =
            COALESCE(messages.body_html_sanitized, excluded.body_html_sanitized),
          attachment_names = CASE WHEN messages.attachment_names = ''
            THEN excluded.attachment_names ELSE messages.attachment_names END''');
      try {
        for (final msg in messages) {
          stmt.execute([
            folderId, msg.uid, msg.messageId, msg.inReplyTo, msg.references,
            msg.fromAddress == null ? null : normalizeAddress(msg.fromAddress!) ?? msg.fromAddress,
            msg.fromName,
            jsonEncode(msg.to), jsonEncode(msg.cc), msg.subject,
            msg.date.millisecondsSinceEpoch, msg.flags, msg.bodyText,
            msg.bodyHtmlSanitized, msg.attachmentNames.join(' '),
          ]);
        }
      } finally {
        stmt.close();
      }
    });
  }

  /// Aggiorna solo i flag (risposta a FETCH FLAGS / CONDSTORE).
  /// UID sconosciuti vengono ignorati: arriveranno con la prossima sync.
  void updateFlags(int folderId, Map<int, int> flagsByUid) {
    database.transaction(() {
      for (final e in flagsByUid.entries) {
        database.db.execute(
            'UPDATE messages SET flags = ? WHERE folder_id = ? AND uid = ?',
            [e.value, folderId, e.key]);
      }
    });
  }

  void deleteByUid(int folderId, Iterable<int> uids) {
    database.transaction(() {
      for (final uid in uids) {
        database.db.execute(
            'DELETE FROM messages WHERE folder_id = ? AND uid = ?', [folderId, uid]);
      }
    });
  }

  int countMessages(int folderId) => database.db
      .select('SELECT count(*) FROM messages WHERE folder_id = ?', [folderId])
      .first
      .columnAt(0) as int;

  /// Pagina della lista messaggi, dal più recente.
  ///
  /// [after] è il cursore dell'ultimo messaggio della pagina precedente.
  /// Il cursore usa data E id: con la sola data, i messaggi arrivati nello
  /// stesso istante a cavallo di due pagine andrebbero persi.
  List<StoredMessage> listMessages(int folderId,
      {int limit = 50, PageCursor? after}) {
    if (limit <= 0 || limit > 500) {
      throw RangeError.range(limit, 1, 500, 'limit');
    }
    final rows = after == null
        ? database.db.select('''
            SELECT id, folder_id, uid, subject, from_address, date, flags
            FROM messages WHERE folder_id = ?
            ORDER BY date DESC, id DESC LIMIT ?''', [folderId, limit])
        : database.db.select('''
            SELECT id, folder_id, uid, subject, from_address, date, flags
            FROM messages
            WHERE folder_id = ? AND (date, id) < (?, ?)
            ORDER BY date DESC, id DESC LIMIT ?''',
            [folderId, after.dateMillis, after.id, limit]);
    return [for (final r in rows) _toStored(r)];
  }

  List<StoredMessage> search(String userInput, {int limit = 50}) {
    final query = buildFtsQuery(userInput);
    if (query.isEmpty) return const [];
    final rows = database.db.select('''
      SELECT m.id, m.folder_id, m.uid, m.subject, m.from_address, m.date, m.flags
      FROM fts_messages f JOIN messages m ON m.id = f.rowid
      WHERE fts_messages MATCH ?
      ORDER BY rank
      LIMIT ?''', [query, limit]);
    return [for (final r in rows) _toStored(r)];
  }

  /// Verifica che l'indice full-text sia coerente con la tabella messaggi.
  /// Lancia SqliteException se non lo è.
  void checkSearchIndex() => database.db
      .execute("INSERT INTO fts_messages(fts_messages, rank) VALUES ('integrity-check', 1)");

  StoredMessage _toStored(Map<String, Object?> r) => StoredMessage(
        r['id'] as int,
        r['folder_id'] as int,
        r['uid'] as int,
        r['subject'] as String,
        r['from_address'] as String?,
        DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
        r['flags'] as int,
      );
}

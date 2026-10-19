/// Migrazioni dello schema. Regole:
/// - non modificare MAI una migrazione già rilasciata: aggiungerne una nuova;
/// - ogni migrazione gira in una transazione: o passa tutta, o niente;
/// - la versione corrente è in `PRAGMA user_version`.
class Migration {
  const Migration(this.version, this.description, this.statements);

  final int version;
  final String description;
  final List<String> statements;
}

const migrations = <Migration>[
  Migration(1, 'Schema iniziale: account, cartelle, messaggi, contatti, FTS5', [
    '''
    CREATE TABLE accounts (
      id           INTEGER PRIMARY KEY,
      name         TEXT NOT NULL,
      email        TEXT NOT NULL UNIQUE COLLATE NOCASE,
      provider     TEXT NOT NULL,
      imap_host    TEXT NOT NULL,
      imap_port    INTEGER NOT NULL CHECK (imap_port BETWEEN 1 AND 65535),
      smtp_host    TEXT NOT NULL,
      smtp_port    INTEGER NOT NULL CHECK (smtp_port BETWEEN 1 AND 65535),
      auth_method  TEXT NOT NULL CHECK (auth_method IN ('password', 'oauth2', 'bridge')),
      secret_ref   TEXT,
      created_at   INTEGER NOT NULL
    )''',
    '''
    CREATE TABLE folders (
      id              INTEGER PRIMARY KEY,
      account_id      INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      path            TEXT NOT NULL,
      role            TEXT NOT NULL DEFAULT 'other'
                      CHECK (role IN ('inbox', 'sent', 'drafts', 'spam', 'trash', 'archive', 'other')),
      uidvalidity     INTEGER,
      highest_modseq  INTEGER,
      UNIQUE (account_id, path)
    )''',
    '''
    CREATE TABLE contacts (
      id            INTEGER PRIMARY KEY,
      display_name  TEXT
    )''',
    '''
    CREATE TABLE contact_addresses (
      address     TEXT PRIMARY KEY,
      contact_id  INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE
    )''',
    '''
    CREATE TABLE threads (
      id          INTEGER PRIMARY KEY,
      account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE
    )''',
    '''
    CREATE TABLE messages (
      id                   INTEGER PRIMARY KEY,
      folder_id            INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      uid                  INTEGER NOT NULL CHECK (uid > 0),
      message_id           TEXT,
      in_reply_to          TEXT,
      references_header    TEXT,
      thread_id            INTEGER REFERENCES threads(id) ON DELETE SET NULL,
      from_address         TEXT,
      from_name            TEXT,
      to_json              TEXT NOT NULL DEFAULT '[]',
      cc_json              TEXT NOT NULL DEFAULT '[]',
      subject              TEXT NOT NULL DEFAULT '',
      date                 INTEGER NOT NULL,
      flags                INTEGER NOT NULL DEFAULT 0,
      spam_score           INTEGER CHECK (spam_score BETWEEN 0 AND 100),
      body_text            TEXT,
      body_html_sanitized  TEXT,
      attachment_names     TEXT NOT NULL DEFAULT '',
      UNIQUE (folder_id, uid)
    )''',
    'CREATE INDEX messages_folder_date ON messages(folder_id, date DESC)',
    'CREATE INDEX messages_message_id ON messages(message_id)',
    'CREATE INDEX messages_from ON messages(from_address)',
    '''
    CREATE TABLE attachments (
      id          INTEGER PRIMARY KEY,
      message_id  INTEGER NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
      sha256      TEXT NOT NULL CHECK (length(sha256) = 64),
      filename    TEXT NOT NULL,
      mime        TEXT NOT NULL,
      size        INTEGER NOT NULL CHECK (size >= 0)
    )''',
    'CREATE INDEX attachments_sha ON attachments(sha256)',
    // Indice full-text "external content": i testi stanno solo in `messages`,
    // l'indice li referenzia per rowid. I trigger lo tengono allineato.
    '''
    CREATE VIRTUAL TABLE fts_messages USING fts5(
      subject, body_text, from_name, from_address, attachment_names,
      content='messages', content_rowid='id',
      tokenize='unicode61 remove_diacritics 2'
    )''',
    '''
    CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN
      INSERT INTO fts_messages(rowid, subject, body_text, from_name, from_address, attachment_names)
      VALUES (new.id, new.subject, new.body_text, new.from_name, new.from_address, new.attachment_names);
    END''',
    '''
    CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN
      INSERT INTO fts_messages(fts_messages, rowid, subject, body_text, from_name, from_address, attachment_names)
      VALUES ('delete', old.id, old.subject, old.body_text, old.from_name, old.from_address, old.attachment_names);
    END''',
    '''
    CREATE TRIGGER messages_au AFTER UPDATE OF subject, body_text, from_name, from_address, attachment_names
    ON messages BEGIN
      INSERT INTO fts_messages(fts_messages, rowid, subject, body_text, from_name, from_address, attachment_names)
      VALUES ('delete', old.id, old.subject, old.body_text, old.from_name, old.from_address, old.attachment_names);
      INSERT INTO fts_messages(rowid, subject, body_text, from_name, from_address, attachment_names)
      VALUES (new.id, new.subject, new.body_text, new.from_name, new.from_address, new.attachment_names);
    END''',
  ]),
  Migration(2, 'Account: nome utente, sicurezza IMAP/SMTP, certificato approvato', [
    // Il nome utente può differire dall'indirizzo (iCloud usa la sola parte
    // locale). NULL = usa l'indirizzo, così gli account esistenti restano validi.
    'ALTER TABLE accounts ADD COLUMN username TEXT',
    "ALTER TABLE accounts ADD COLUMN imap_security TEXT NOT NULL DEFAULT 'tls' "
        "CHECK (imap_security IN ('tls', 'starttls'))",
    "ALTER TABLE accounts ADD COLUMN smtp_security TEXT NOT NULL DEFAULT 'tls' "
        "CHECK (smtp_security IN ('tls', 'starttls'))",
    'ALTER TABLE accounts ADD COLUMN trusted_cert_sha256 TEXT '
        "CHECK (trusted_cert_sha256 IS NULL OR "
        "(length(trusted_cert_sha256) = 64 AND trusted_cert_sha256 NOT GLOB '*[^0-9a-f]*'))",
  ]),
  Migration(3, 'Cartelle: UIDNEXT dell\'ultima sincronizzazione completata', [
    // NULL = cartella mai sincronizzata del tutto: la prossima sync è iniziale.
    'ALTER TABLE folders ADD COLUMN uid_next INTEGER CHECK (uid_next IS NULL OR uid_next > 0)',
  ]),
  Migration(4, 'Filtro delle pubblicità: parole imparate, addestramenti, azioni', [
    // Conteggi per parola: in quante pubblicità e in quante email normali
    // è comparsa. È tutto il "modello": pochi KB, nessun dato esce dal PC.
    '''
    CREATE TABLE filter_tokens (
      token  TEXT PRIMARY KEY,
      ad     INTEGER NOT NULL DEFAULT 0 CHECK (ad >= 0),
      ham    INTEGER NOT NULL DEFAULT 0 CHECK (ham >= 0)
    ) WITHOUT ROWID''',
    // Impostazioni e totali (numero di pubblicità e di email normali imparate).
    '''
    CREATE TABLE filter_state (
      key    TEXT PRIMARY KEY,
      value  TEXT NOT NULL
    ) WITHOUT ROWID''',
    // Cosa è stato imparato da ogni email, con le sue parole: se l'utente
    // cambia idea (ripristina dal Cestino) si toglie esattamente ciò che si
    // era aggiunto. La chiave è il Message-ID, che resta uguale quando
    // l'email cambia cartella (e quindi riga e UID).
    '''
    CREATE TABLE filter_trained (
      key     TEXT PRIMARY KEY,
      label   TEXT NOT NULL CHECK (label IN ('ad', 'ham')),
      tokens  TEXT NOT NULL
    ) WITHOUT ROWID''',
    // Parole di ogni email giudicata, per addestrare su ciò che il filtro
    // ha visto davvero (comprese le intestazioni, che non stanno in messages).
    '''
    CREATE TABLE filter_message_tokens (
      message_id  INTEGER PRIMARY KEY REFERENCES messages(id) ON DELETE CASCADE,
      tokens      TEXT NOT NULL
    )''',
    // Registro delle decisioni: riepilogo del giorno e "Annulla".
    '''
    CREATE TABLE filter_actions (
      id            INTEGER PRIMARY KEY,
      account_id    INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
      message_key   TEXT NOT NULL,
      subject       TEXT NOT NULL,
      from_address  TEXT,
      score         INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
      action        TEXT NOT NULL CHECK (action IN ('marked', 'moved')),
      undone        INTEGER NOT NULL DEFAULT 0 CHECK (undone IN (0, 1)),
      at            INTEGER NOT NULL
    )''',
    'CREATE INDEX filter_actions_at ON filter_actions(at)',
  ]),
  Migration(5, 'Corpi scaricati: stato, dettagli della lettura, allegati inline', [
    // NULL = corpo mai scaricato; 1 = scaricato e salvato; 2 = troppo grande
    // per lo scaricamento automatico (si scarica all'apertura); 3 = illeggibile
    // (parser fermato dal timeout): mai riprovato in automatico.
    'ALTER TABLE messages ADD COLUMN body_state INTEGER CHECK (body_state IS NULL OR body_state BETWEEN 1 AND 3)',
    // Conteggi del sanificatore e anomalie del parser, in JSON.
    'ALTER TABLE messages ADD COLUMN body_meta TEXT',
    // Il filtro l'ha segnata come pubblicità (etichetta nella lista).
    'ALTER TABLE messages ADD COLUMN ad_marked INTEGER NOT NULL DEFAULT 0 CHECK (ad_marked IN (0, 1))',
    "ALTER TABLE attachments ADD COLUMN kind TEXT NOT NULL DEFAULT 'file' "
        "CHECK (kind IN ('file', 'inlineImage', 'signature', 'message'))",
    'ALTER TABLE attachments ADD COLUMN content_id TEXT',
    'CREATE INDEX attachments_message ON attachments(message_id)',
  ]),
];

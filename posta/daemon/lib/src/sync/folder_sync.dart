import 'dart:math';

import '../db/mail_store.dart';
import '../transport/mail_transport.dart';

class SyncReport {
  SyncReport({
    required this.folderId,
    required this.path,
    this.added = 0,
    this.removed = 0,
    this.flagsChanged = 0,
    this.reset = false,
    this.initial = false,
  });

  final int folderId;
  final String path;
  int added;
  int removed;
  int flagsChanged;

  /// UIDVALIDITY cambiata: la cartella è stata svuotata e riscaricata.
  bool reset;

  /// Prima sincronizzazione (o dopo un reset): finestra temporale.
  bool initial;

  bool get changed => added > 0 || removed > 0 || flagsChanged > 0 || reset;

  Map<String, Object?> toJson() => {
        'folderId': folderId,
        'path': path,
        'added': added,
        'removed': removed,
        'flagsChanged': flagsChanged,
        'reset': reset,
      };

  @override
  String toString() => 'SyncReport($path: +$added -$removed ~$flagsChanged'
      '${reset ? ' reset' : ''}${initial ? ' iniziale' : ''})';
}

typedef Clock = DateTime Function();

/// Sincronizza UNA cartella dal server al database locale.
///
/// Ogni passo è idempotente e lo stato del server (MODSEQ, UIDNEXT) viene
/// registrato solo alla fine: se la sync si interrompe in qualunque punto
/// (rete, crash, spegnimento) la successiva rifà il lavoro mancante senza
/// duplicati e senza perdere modifiche.
class FolderSync {
  FolderSync(this.store, this.transport,
      {this.window = const Duration(days: 30), this.batchSize = 200, Clock? clock})
      : _clock = clock ?? DateTime.now {
    if (batchSize < 1) throw ArgumentError.value(batchSize, 'batchSize');
  }

  final MailStore store;
  final MailTransport transport;

  /// Alla prima sync si scaricano solo i messaggi consegnati in questo arco.
  final Duration window;

  /// Intestazioni scaricate per richiesta: limita memoria e dimensione dei
  /// comandi IMAP con cartelle da decine di migliaia di messaggi.
  final int batchSize;
  final Clock _clock;

  Future<SyncReport> sync(int folderId, String path) async {
    final report = SyncReport(folderId: folderId, path: path);

    // 1. Stato del server al momento della SELECT. Ciò che cambia dopo verrà
    //    comunque visto (e riapplicato senza danni) alla prossima sync.
    final status = await transport.selectFolder(path);

    // 2. UIDVALIDITY: se cambiata, gli UID locali non valgono più nulla.
    report.reset = store.applyUidValidity(folderId, status.uidValidity);
    final saved = store.folderSyncState(folderId);
    report.initial = saved.uidNext == null;

    // 3. Elenco completo degli UID sul server: dice cosa è stato cancellato.
    final serverUids = (await transport.searchUids()).toSet();

    // 4. Cancellazioni: locali che il server non ha più.
    final local = store.localUids(folderId);
    final gone = local.difference(serverUids);
    if (gone.isNotEmpty) {
      store.deleteByUid(folderId, gone);
      report.removed = gone.length;
    }

    // 5. Nuovi messaggi. Alla prima sync: quelli consegnati nella finestra.
    //    Poi: UID >= UIDNEXT dell'ultima sync completata.
    final List<int> fresh;
    if (report.initial) {
      final since = _clock().subtract(window);
      fresh = (await transport.searchUids(since: since))
          .where((u) => serverUids.contains(u) && !local.contains(u))
          .toList();
    } else {
      fresh = serverUids.where((u) => u >= saved.uidNext! && !local.contains(u)).toList();
    }
    fresh.sort();
    var maxUid = 0;
    for (var i = 0; i < fresh.length; i += batchSize) {
      final batch = fresh.sublist(i, min(i + batchSize, fresh.length));
      final headers = await transport.fetchHeadersByUids(batch);
      // Ogni lotto è una transazione: un'interruzione lascia lotti interi.
      store.upsertMessages(folderId, headers);
      report.added += headers.length;
      for (final h in headers) {
        maxUid = max(maxUid, h.uid);
      }
    }

    // 6. Flag dei messaggi già presenti (letto, importante, risposto...).
    //    Anche durante una sync iniziale: se una precedente si era interrotta,
    //    i messaggi salvati allora possono aver cambiato flag nel frattempo,
    //    e il MODSEQ registrato alla fine li coprirebbe per sempre.
    final known = local.intersection(serverUids).toList()..sort();
    if (known.isNotEmpty) {
      final Map<int, int> changes;
      if (transport.supportsCondstore && saved.highestModseq != null) {
        changes = await transport.fetchFlags(changedSince: saved.highestModseq);
        changes.removeWhere((uid, _) => !local.contains(uid));
      } else {
        changes = {};
        for (var i = 0; i < known.length; i += batchSize) {
          changes.addAll(await transport.fetchFlags(
              uids: known.sublist(i, min(i + batchSize, known.length))));
        }
      }
      report.flagsChanged = _applyFlags(folderId, changes);
    }

    // 7. Solo ora: lo stato del server diventa il punto di partenza.
    //    Si salva il MODSEQ letto alla SELECT, non uno più recente: le
    //    modifiche avvenute durante la sync verranno rilette la prossima volta.
    store.commitFolderSync(folderId,
        highestModseq: status.highestModseq,
        uidNext: max(status.uidNext, maxUid + 1));
    return report;
  }

  /// Applica solo i flag davvero diversi e restituisce quanti sono cambiati.
  int _applyFlags(int folderId, Map<int, int> flagsByUid) {
    if (flagsByUid.isEmpty) return 0;
    final current = {
      for (final r in store.database.db.select(
          'SELECT uid, flags FROM messages WHERE folder_id = ?', [folderId]))
        r['uid'] as int: r['flags'] as int,
    };
    final different = {
      for (final e in flagsByUid.entries)
        if (current.containsKey(e.key) && current[e.key] != e.value) e.key: e.value,
    };
    store.updateFlags(folderId, different);
    return different.length;
  }
}

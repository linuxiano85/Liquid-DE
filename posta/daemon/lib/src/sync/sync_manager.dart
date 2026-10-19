import 'dart:async';

import 'package:dbus/dbus.dart';

import '../accounts/account_service.dart';
import '../db/mail_store.dart';
import '../transport/mail_transport.dart';
import '../transport/retry.dart';
import 'account_sync.dart';

/// Un gestore di sincronizzazione per ogni account.
class SyncManager {
  SyncManager({
    required this.accounts,
    required this.store,
    required this.transportFactory,
    required this.onEvent,
    Backoff Function()? backoffFactory,
    this.otherFoldersEvery = const Duration(minutes: 15),
    this.afterFolderSync,
  }) : _backoffFactory = backoffFactory ?? Backoff.new;

  /// Vedi [AccountSyncRunner.afterFolderSync]; riceve anche l'account.
  final Future<void> Function(MailTransport t, int accountId, int folderId, String path, String role)?
      afterFolderSync;

  final AccountService accounts;
  final MailStore store;
  final TransportFactory transportFactory;
  final void Function(SyncEvent event) onEvent;
  final Backoff Function() _backoffFactory;
  final Duration otherFoldersEvery;
  final Map<int, AccountSyncRunner> _runners = {};

  Iterable<int> get running => _runners.keys;

  void startAll() {
    for (final a in store.listAccounts()) {
      startAccount(a.id!);
    }
  }

  void startAccount(int id) {
    if (_runners.containsKey(id)) return;
    final r = AccountSyncRunner(
      accountId: id,
      accounts: accounts,
      store: store,
      transportFactory: transportFactory,
      onEvent: onEvent,
      backoff: _backoffFactory(),
      otherFoldersEvery: otherFoldersEvery,
      afterFolderSync: afterFolderSync == null
          ? null
          : (t, folderId, path, role) => afterFolderSync!(t, id, folderId, path, role),
    );
    _runners[id] = r;
    r.start();
  }

  /// Da chiamare PRIMA di rimuovere l'account: altrimenti il gestore
  /// tenterebbe di ricollegarsi con una password appena cancellata.
  Future<void> stopAccount(int id) async {
    final r = _runners.remove(id);
    await r?.stop();
  }

  Future<void> stopAll() async {
    final all = _runners.values.toList();
    _runners.clear();
    await Future.wait(all.map((r) => r.stop()));
  }

  /// Sync immediata di un account o di tutti (risveglio dalla sospensione).
  void syncNow([int? id]) {
    if (id != null) {
      _runners[id]?.syncNow();
    } else {
      for (final r in _runners.values) {
        r.syncNow();
      }
    }
  }

  List<Map<String, Object?>> status() => [
        for (final e in _runners.entries)
          e.value.lastState?.toJson() ?? {'accountId': e.key, 'phase': e.value.phase.name},
      ];
}

/// Risvegli dalla sospensione, dal segnale PrepareForSleep di systemd-logind
/// (false = il sistema si è appena risvegliato). Al risveglio le connessioni
/// sono quasi sempre morte senza che il socket lo sappia: conviene
/// ricollegarsi subito invece di aspettare il rinnovo dell'IDLE.
///
/// Senza bus di sistema (container, chroot) la libreria D-Bus non riporta
/// l'errore sullo stream ma lo lancia da una funzione asincrona interna: una
/// sottoscrizione diretta farebbe cadere il daemon all'avvio. Per questo la
/// sottoscrizione avviene in una zona isolata; un errore chiude lo stream
/// con un errore normale, che il daemon gestisce.
Stream<void> logindResumes(DBusClient systemBus) {
  StreamSubscription<DBusSignal>? sub;
  late final StreamController<void> out;
  var closed = false;
  void fail(Object e) {
    if (closed) return;
    closed = true;
    out.addError(e);
    out.close();
  }

  out = StreamController<void>(
    onListen: () {
      runZonedGuarded(() {
        sub = DBusSignalStream(
          systemBus,
          sender: 'org.freedesktop.login1',
          interface: 'org.freedesktop.login1.Manager',
          name: 'PrepareForSleep',
          path: DBusObjectPath('/org/freedesktop/login1'),
          signature: DBusSignature('b'),
        ).listen((s) {
          if (!closed && s.values.first.asBoolean() == false) out.add(null);
        }, onError: fail);
      }, (e, _) => fail(e));
    },
    onCancel: () async {
      closed = true;
      await sub?.cancel();
    },
  );
  return out.stream;
}

import 'dart:async';
import 'dart:io';

import 'accounts/account_rpc.dart';
import 'accounts/account_service.dart';
import 'filter/ad_filter.dart';
import 'filter/filter_rpc.dart';
import 'mail/mail_rpc.dart';
import 'mail/mail_service.dart';
import 'rpc/rpc_errors.dart';
import 'rpc/rpc_server.dart';
import 'runtime_files.dart';
import 'sync/account_sync.dart';
import 'sync/sync_manager.dart';

const daemonVersion = '0.3.0';

/// Punto di raccolta dei servizi del daemon.
class Daemon {
  Daemon({
    required this.runtimeFiles,
    int port = 0,
    String? token,
    this.accounts,
    this.sync,
    this.resumes,
    this.filter,
    this.mail,
  })  : token = token ?? RuntimeFiles.generateToken(),
        _port = port;

  /// Null nei test che non sincronizzano.
  final SyncManager? sync;

  /// Filtro delle pubblicità; null nei test che non lo usano.
  final AdFilter? filter;

  /// Lettura e gestione della posta; null nei test che non la usano.
  final MailService? mail;

  /// Risvegli dalla sospensione (logind); null se non disponibili.
  final Stream<void>? resumes;
  StreamSubscription<void>? _resumeSub;

  /// Inoltra gli eventi di sincronizzazione alla UI. Va passato come
  /// `onEvent` al [SyncManager].
  void forwardSyncEvent(SyncEvent e) {
    if (!_started) return;
    switch (e) {
      case SyncStateEvent():
        rpc.broadcast('event.sync.state', e.toJson());
      case MailChangedEvent():
        rpc.broadcast('event.mail.changed', e.toJson());
    }
  }

  /// Avvisa la UI che delle cartelle sono cambiate per un'azione fatta qui
  /// (spostamento, cancellazione, corpi scaricati, filtro): ricarica le liste.
  void notifyFoldersChanged(int accountId, Set<int> folderIds) {
    if (!_started || folderIds.isEmpty) return;
    rpc.broadcast('event.folders.changed', {'accountId': accountId, 'folderIds': folderIds.toList()});
  }

  bool _started = false;

  final RuntimeFiles runtimeFiles;
  final String token;
  final int _port;

  /// Null solo nei test che verificano il server RPC da solo.
  final AccountService? accounts;

  late final RpcServer rpc;
  final DateTime _startedAt = DateTime.now();

  Future<void> start() async {
    rpc = RpcServer(RpcServerConfig(token: token, port: _port));
    rpc.register('ping', (_, __) => 'pong');
    rpc.register('daemon.info', (_, __) => {
          'version': daemonVersion,
          'pid': pid,
          'uptimeSeconds': DateTime.now().difference(_startedAt).inSeconds,
        });
    final a = accounts;
    final s = sync;
    if (a != null) {
      registerAccountMethods(rpc, a, onAdded: s?.startAccount, beforeRemove: (id) async {
        await s?.stopAccount(id);
        await mail?.forgetAccount(id);
      }, onReauthed: (id) async {
        // Nuovo modo di accesso: si riparte con il token al posto della
        // vecchia password.
        await s?.stopAccount(id);
        await mail?.forgetAccount(id);
        s?.startAccount(id);
      });
    }
    final f = filter;
    if (f != null) registerFilterMethods(rpc, f);
    final m = mail;
    if (m != null) registerMailMethods(rpc, m);
    if (s != null) {
      rpc.register('sync.status', (_, __) => s.status());
      rpc.register('sync.now', (p, _) {
        final id = p['accountId'];
        if (id != null && id is! int) {
          throw RpcException(RpcErrorCode.invalidParams, 'accountId deve essere un intero');
        }
        s.syncNow(id as int?);
        return {'ok': true};
      });
    }
    await rpc.start();
    _started = true;
    await runtimeFiles.write(token: token, port: rpc.port);
    s?.startAll();
    // Senza bus di sistema (container, sessioni particolari) il segnale non
    // arriva: si continua senza, affidandosi a backoff e rinnovo dell'IDLE.
    _resumeSub = resumes?.listen((_) => s?.syncNow(), onError: (Object e) {
      stderr.writeln('[daemon] risvegli dalla sospensione non disponibili: $e');
    });
  }

  Future<void> stop() async {
    await _resumeSub?.cancel();
    await sync?.stopAll();
    await mail?.closeAll();
    _started = false;
    await rpc.stop();
    await runtimeFiles.clear();
  }
}

import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// Una email nuova da annunciare.
class NewMail {
  NewMail({required this.from, required this.subject});
  final String from;
  final String subject;
}

/// Notifiche di posta nuova sul servizio standard della scrivania
/// (`org.freedesktop.Notifications`, in Liquid DE lo serve la shell).
///
/// Il clic apre la finestra Posta. Se il servizio delle notifiche non c'è
/// (sessione senza scrivania, test) non succede niente: la posta arriva lo
/// stesso, si vede aprendo la finestra.
class DesktopNotifier {
  DesktopNotifier({DBusClient? bus, this.launcher = 'minerva-posta'}) : _busOverride = bus;

  final DBusClient? _busOverride;
  final String launcher;
  DBusClient? _bus;
  StreamSubscription<DBusSignal>? _actions;
  final Set<int> _ours = {};

  static const _name = 'org.freedesktop.Notifications';
  static const _path = '/org/freedesktop/Notifications';

  DBusClient get _client => _bus ??= _busOverride ?? DBusClient.session();

  /// Testo sicuro per il corpo: il servizio delle notifiche interpreta un
  /// po' di markup, e un oggetto con "<b>" o "&" non deve diventare altro.
  static String escape(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  Future<void> announce(List<NewMail> mails) async {
    if (mails.isEmpty) return;
    final String summary;
    final String body;
    if (mails.length == 1) {
      summary = mails.single.from;
      body = mails.single.subject.isEmpty ? '(senza oggetto)' : mails.single.subject;
    } else if (mails.length <= 3) {
      summary = '${mails.length} nuovi messaggi';
      body = mails.map((m) => '${m.from}: ${m.subject}').join('\n');
    } else {
      summary = '${mails.length} nuovi messaggi';
      body = 'Da ${mails.take(3).map((m) => m.from).toSet().join(', ')} e altri';
    }
    try {
      _listenOnce();
      final reply = await DBusRemoteObject(_client, name: _name, path: DBusObjectPath(_path))
          .callMethod(_name, 'Notify', [
        const DBusString('Posta'),
        const DBusUint32(0),
        const DBusString('minerva-posta'),
        DBusString(escape(summary)),
        DBusString(escape(body)),
        DBusArray.string(const ['default', 'Apri']),
        DBusDict.stringVariant({
          'desktop-entry': const DBusString('minerva-posta'),
          'category': const DBusString('email.arrived'),
        }),
        const DBusInt32(-1),
      ]).timeout(const Duration(seconds: 5));
      _ours.add(reply.returnValues.first.asUint32());
    } on Object catch (e) {
      stderr.writeln('[posta] notifica non mostrata: $e');
    }
  }

  void _listenOnce() {
    if (_actions != null) return;
    _actions = DBusSignalStream(_client,
            interface: _name, name: 'ActionInvoked', path: DBusObjectPath(_path))
        .listen((s) {
      final id = s.values[0].asUint32();
      if (!_ours.remove(id)) return;
      Process.start(launcher, const [], mode: ProcessStartMode.detached).catchError((Object e) {
        stderr.writeln('[posta] apertura della finestra non riuscita: $e');
        return Future<Process>.error(e);
      }).ignore();
    }, onError: (Object _) {});
  }

  Future<void> close() async {
    await _actions?.cancel();
    if (_busOverride == null) await _bus?.close();
  }
}

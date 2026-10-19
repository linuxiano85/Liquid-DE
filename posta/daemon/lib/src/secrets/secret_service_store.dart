import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dbus/dbus.dart';

import 'dh_session.dart';
import 'secret_store.dart';

/// [SecretStore] sul Secret Service di freedesktop.org (gnome-keyring,
/// KeePassXC, KWallet recenti), parlato direttamente via D-Bus.
///
/// Non usa `secret-tool`: con un portachiavi bloccato `secret-tool lookup`
/// restituisce lo stesso risultato di un segreto mancante, e il daemon
/// chiederebbe all'utente una password che invece esiste.
///
/// Gli elementi usano lo schema generico di libsecret, così restano visibili
/// e gestibili da Seahorse e da `secret-tool search service liquid-mail`.
class SecretServiceStore implements SecretStore {
  SecretServiceStore({
    DBusClient? client,
    this.promptTimeout = const Duration(seconds: 60),
    this.callTimeout = const Duration(seconds: 10),
  }) : _clientOverride = client;

  static const _bus = 'org.freedesktop.secrets';
  static const _service = 'org.freedesktop.Secret.Service';
  static const _collection = 'org.freedesktop.Secret.Collection';
  static const _item = 'org.freedesktop.Secret.Item';
  static const _prompt = 'org.freedesktop.Secret.Prompt';
  static const serviceAttribute = 'liquid-mail';

  final DBusClient? _clientOverride;
  final Duration promptTimeout;
  final Duration callTimeout;
  DBusClient? _client;
  DBusObjectPath? _sessionPath;
  DhSession? _dh;

  DBusClient get _dbus => _client ??= _clientOverride ?? DBusClient.session();
  DBusRemoteObject get _root =>
      DBusRemoteObject(_dbus, name: _bus, path: DBusObjectPath('/org/freedesktop/secrets'));

  Map<String, String> _attributes(String ref) => {
        'xdg:schema': 'org.freedesktop.Secret.Generic',
        'service': serviceAttribute,
        'ref': ref,
      };

  @override
  Future<void> store(String ref, String secret, {required String label}) => _guard(() async {
        validateSecretArgs(ref, secret);
        final session = await _session();
        final collection = await _defaultCollection();
        await _unlock([collection]);
        final enc = _encode(secret);
        final reply = await _call(
            DBusRemoteObject(_dbus, name: _bus, path: collection), _collection, 'CreateItem', [
          DBusDict.stringVariant({
            'org.freedesktop.Secret.Item.Label': DBusString(label),
            'org.freedesktop.Secret.Item.Attributes': DBusDict(DBusSignature('s'),
                DBusSignature('s'), {
              for (final e in _attributes(ref).entries) DBusString(e.key): DBusString(e.value),
            }),
          }),
          _secretStruct(session, enc.iv, enc.value),
          const DBusBoolean(true), // sostituisce un elemento con gli stessi attributi
        ]);
        final prompt = reply.returnValues[1].asObjectPath();
        if (prompt.value != '/') {
          final ok = await _runPrompt(prompt);
          if (!ok) throw SecretStoreLockedException('salvataggio annullato');
        }
      });

  @override
  Future<String?> lookup(String ref) => _guard(() async {
        validateSecretArgs(ref);
        final items = await _search(ref);
        if (items.isEmpty) return null;
        await _unlock(items);
        final session = await _session();
        final reply = await _call(_root, _service, 'GetSecrets', [
          DBusArray.objectPath([items.first]),
          session,
        ]);
        final secrets = reply.returnValues[0].asDict();
        if (secrets.isEmpty) {
          throw SecretStoreLockedException('il servizio non ha restituito il segreto');
        }
        final parts = secrets.values.first.asStruct();
        final iv = parts[1].asByteArray().toList();
        final value = parts[2].asByteArray().toList();
        return _decode(iv, value);
      });

  @override
  Future<void> delete(String ref) => _guard(() async {
        validateSecretArgs(ref);
        final items = await _search(ref);
        for (final item in items) {
          await _unlock([item]);
          final reply =
              await _call(DBusRemoteObject(_dbus, name: _bus, path: item), _item, 'Delete', []);
          final prompt = reply.returnValues[0].asObjectPath();
          if (prompt.value != '/' && !await _runPrompt(prompt)) {
            throw SecretStoreLockedException('cancellazione annullata');
          }
        }
      });

  @override
  Future<void> close() async {
    final path = _sessionPath;
    _sessionPath = null;
    _dh = null;
    final c = _client;
    _client = null;
    if (c == null) return;
    if (path != null) {
      try {
        await DBusRemoteObject(c, name: _bus, path: path)
            .callMethod('org.freedesktop.Secret.Session', 'Close', [])
            .timeout(callTimeout);
      } catch (_) {}
    }
    if (_clientOverride == null) await c.close();
  }

  Future<List<DBusObjectPath>> _search(String ref) async {
    final reply = await _call(_root, _service, 'SearchItems', [
      DBusDict(DBusSignature('s'), DBusSignature('s'), {
        DBusString('service'): DBusString(serviceAttribute),
        DBusString('ref'): DBusString(ref),
      }),
    ]);
    return [
      ...reply.returnValues[0].asObjectPathArray(),
      ...reply.returnValues[1].asObjectPathArray(),
    ];
  }

  /// Sblocca gli oggetti se necessario. Se serve un prompt (finestra di
  /// sblocco del portachiavi) lo avvia e ne attende l'esito.
  Future<void> _unlock(List<DBusObjectPath> objects) async {
    final reply = await _call(_root, _service, 'Unlock', [DBusArray.objectPath(objects)]);
    final prompt = reply.returnValues[1].asObjectPath();
    if (prompt.value == '/') return;
    if (!await _runPrompt(prompt)) {
      throw SecretStoreLockedException('sblocco annullato o non possibile');
    }
  }

  Future<bool> _runPrompt(DBusObjectPath path) async {
    final object = DBusRemoteObject(_dbus, name: _bus, path: path);
    final completed = DBusRemoteObjectSignalStream(
        object: object, interface: _prompt, name: 'Completed');
    final result = completed.first.timeout(promptTimeout);
    try {
      await object.callMethod(_prompt, 'Prompt', [const DBusString('')]).timeout(callTimeout);
      final signal = await result;
      final dismissed = signal.values[0].asBoolean();
      return !dismissed;
    } on TimeoutException {
      try {
        await object.callMethod(_prompt, 'Dismiss', []);
      } catch (_) {}
      return false;
    } on DBusMethodResponseException {
      return false;
    }
  }

  Future<DBusObjectPath> _defaultCollection() async {
    final reply = await _call(_root, _service, 'ReadAlias', [const DBusString('default')]);
    final path = reply.returnValues[0].asObjectPath();
    if (path.value == '/') {
      throw SecretStoreUnavailableException('nessuna raccolta predefinita nel portachiavi');
    }
    return path;
  }

  /// Algoritmo della sessione corrente: DH se il servizio lo supporta,
  /// altrimenti "plain" (es. gnome-keyring 46 di Ubuntu 24.04, compilato
  /// senza DH). È lo stesso ripiego di libsecret: il bus di sessione è
  /// comunque accessibile solo all'utente stesso.
  String? get sessionAlgorithm =>
      _sessionPath == null ? null : (_dh == null ? 'plain' : DhSession.algorithm);

  Future<DBusObjectPath> _session() async {
    final existing = _sessionPath;
    if (existing != null) return existing;
    final dh = DhSession.generate();
    try {
      final reply = await _call(_root, _service, 'OpenSession', [
        const DBusString(DhSession.algorithm),
        DBusVariant(DBusArray.byte(dh.publicKey)),
      ]);
      dh.complete(reply.returnValues[0].asVariant().asByteArray().toList());
      _dh = dh;
      return _sessionPath = reply.returnValues[1].asObjectPath();
    } on DBusMethodResponseException catch (e) {
      if (e.errorName != 'org.freedesktop.DBus.Error.NotSupported') rethrow;
      final reply = await _call(_root, _service, 'OpenSession', [
        const DBusString('plain'),
        const DBusVariant(DBusString('')),
      ]);
      _dh = null;
      return _sessionPath = reply.returnValues[1].asObjectPath();
    }
  }

  ({List<int> iv, List<int> value}) _encode(String secret) {
    final dh = _dh;
    if (dh == null) return (iv: const [], value: utf8.encode(secret));
    final enc = dh.encrypt(utf8.encode(secret));
    return (iv: enc.iv, value: enc.ciphertext);
  }

  String _decode(List<int> iv, List<int> value) {
    final dh = _dh;
    return utf8.decode(dh == null ? value : dh.decrypt(iv, value));
  }

  DBusStruct _secretStruct(DBusObjectPath session, List<int> iv, List<int> value) => DBusStruct([
        session,
        DBusArray.byte(iv),
        DBusArray.byte(value),
        const DBusString('text/plain; charset=utf8'),
      ]);

  Future<DBusMethodSuccessResponse> _call(
          DBusRemoteObject object, String interface, String method, List<DBusValue> args) =>
      object.callMethod(interface, method, args).timeout(callTimeout);

  void _resetSession() {
    _sessionPath = null;
    _dh = null;
  }

  /// Traduce gli errori D-Bus nei tre casi che il resto del daemon conosce.
  ///
  /// Se il servizio è stato riavviato (aggiornamento, logout e login), la
  /// sessione memorizzata non esiste più: se ne apre una nuova e l'operazione
  /// viene ripetuta una volta, senza disturbare l'utente.
  Future<T> _guard<T>(Future<T> Function() action, {bool retried = false}) async {
    try {
      return await action();
    } on ArgumentError {
      rethrow;
    } on SecretStoreLockedException {
      rethrow;
    } on SecretStoreUnavailableException {
      rethrow;
    } on DBusMethodResponseException catch (e) {
      final name = e.errorName;
      if (name == 'org.freedesktop.Secret.Error.IsLocked') {
        throw SecretStoreLockedException('oggetto bloccato');
      }
      if (name == 'org.freedesktop.Secret.Error.NoSession') {
        _resetSession();
        if (!retried) return _guard(action, retried: true);
        throw SecretStoreUnavailableException('sessione rifiutata dal servizio');
      }
      if (name == 'org.freedesktop.DBus.Error.ServiceUnknown' ||
          name == 'org.freedesktop.DBus.Error.NameHasNoOwner' ||
          name.startsWith('org.freedesktop.DBus.Error.Spawn')) {
        // Il servizio è sparito: con lui la sessione. Al suo ritorno se ne
        // aprirà una nuova.
        _resetSession();
        throw SecretStoreUnavailableException('nessun servizio dei segreti attivo');
      }
      throw SecretStoreUnavailableException('errore del servizio dei segreti: $name');
    } on SocketException {
      throw SecretStoreUnavailableException('bus di sessione non raggiungibile');
    } on DBusClosedException {
      _client = null;
      _sessionPath = null;
      throw SecretStoreUnavailableException('connessione al bus chiusa');
    } on TimeoutException {
      throw SecretStoreUnavailableException('il servizio dei segreti non risponde');
    } on FormatException catch (e) {
      // Errore di decifratura: non deve mai restituire una password sbagliata.
      _sessionPath = null;
      _dh = null;
      throw SecretStoreUnavailableException('sessione cifrata non valida: ${e.message}');
    }
  }
}

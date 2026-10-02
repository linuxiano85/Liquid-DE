import 'greetd_service.dart';

/// A single owner and a single outstanding greetd request. Cancellation can
/// supersede an in-flight exchange, but its reply is consumed before cancel
/// is sent: a previous success can never acknowledge cancellation.
class GreetdConversation<T extends Object> {
  GreetdConversation(this.service, this.deliver) {
    service.onDisconnect = () {
      _needsReset = true;
      if (!_busy && _owner != null && !_abandoned) {
        _state = 'failed';
        deliver(_owner!, GreetdService.failure('Collegamento a greetd interrotto'));
      }
    };
  }
  final GreetdService service;
  final void Function(T, Map<String, dynamic>) deliver;
  T? _owner;
  bool _busy = false, _cancel = false, _abandoned = false;
  bool _needsReset = false, _closed = false;
  String _state = 'idle';
  String? _pendingAction;

  void _reject(T client, String message) => deliver(client, {
    'type': 'error', 'error_type': 'error', 'description': message,
    'request_rejected': true,
  });

  Future<void> handle(T client, String action, Map message) async {
    if (_closed) return;
    if (_owner != null && !identical(_owner, client)) {
      _reject(client, 'Conversazione di accesso già occupata');
      return;
    }
    if (_busy) {
      if (action == 'greeter_cancel' && _pendingAction != 'greeter_start') {
        _cancel = true;
      } else {
        _reject(client, 'Richiesta di accesso già in corso');
      }
      return;
    }
    Map<String, dynamic>? request;
    switch (action) {
      case 'greeter_create_session':
        if (!['idle', 'failed'].contains(_state) ||
            message['username'] is! String || (message['username'] as String).isEmpty) {
          break;
        }
        request = {'type': 'create_session', 'username': message['username']};
        break;
      case 'greeter_respond':
        if (_state != 'prompt' || _owner == null ||
            (message['response'] != null && message['response'] is! String)) {
          break;
        }
        request = {'type': 'post_auth_message_response'};
        if (message['response'] != null) request['response'] = message['response'];
        break;
      case 'greeter_start':
        if (_state != 'authenticated' || _owner == null) break;
        final cmd = message['cmd'], env = message['env'] ?? <String>[];
        if (cmd is! List || cmd.isEmpty || cmd.any((v) => v is! String) ||
            env is! List || env.any((v) => v is! String)) {
          break;
        }
        request = {'type': 'start_session', 'cmd': List<String>.from(cmd),
          'env': List<String>.from(env)};
        break;
      case 'greeter_cancel':
        if (_state == 'started') break;
        request = {'type': 'cancel_session'};
        break;
    }
    if (request == null) {
      _reject(client, 'Richiesta di accesso non valida nello stato corrente');
      return;
    }
    _owner ??= client;
    _busy = true;
    _pendingAction = action;
    try {
      // A broken channel may have left server-side state. Reset it explicitly
      // before any new creation; never assume closing a socket cancels PAM.
      if (_needsReset && action != 'greeter_cancel') {
        final reset = await service.request({'type': 'cancel_session'});
        if (_closed) return;
        if (reset['type'] != 'success') {
          _state = 'failed';
          if (!_abandoned) deliver(client, reset);
          return;
        }
        _needsReset = false;
        _state = 'idle';
        if (action != 'greeter_create_session') {
          if (!_abandoned) _reject(client, 'Ripetere il tentativo di accesso');
          return;
        }
      }
      // Disconnection while the reset awaited must never send saved input.
      if (_abandoned || _cancel) {
        await _cancelNow(client);
        return;
      }
      final reply = await service.request(request);
      if (_closed) return;
      if (action == 'greeter_start' && reply['type'] == 'success' && _abandoned) {
        _release();
        return;
      }
      if ((_abandoned || _cancel) && action != 'greeter_cancel') {
        await _cancelNow(client);
        return;
      }
      _apply(action, reply);
      if (!_abandoned) deliver(client, {...reply, 'request_action': action});
      if (action == 'greeter_cancel') _release();
    } finally {
      if (!_closed && _abandoned && _owner != null) await _cancelNow(client);
      _pendingAction = null;
      _busy = false;
    }
  }

  void _apply(String action, Map<String, dynamic> reply) {
    if (reply['transport_error'] == true) _needsReset = true;
    if (action == 'greeter_cancel') {
      _needsReset = reply['type'] != 'success';
      _state = 'idle';
    } else if (reply['type'] == 'error') {
      _state = 'failed';
    } else if (reply['type'] == 'auth_message' && action != 'greeter_start') {
      _state = 'prompt';
    } else if (reply['type'] == 'success') {
      _state = action == 'greeter_start' ? 'started' : 'authenticated';
    } else {
      _needsReset = true;
      _state = 'failed';
    }
  }

  Future<void> _cancelNow(T client) async {
    _cancel = false;
    final reply = await service.request({'type': 'cancel_session'});
    if (_closed) return;
    _apply('greeter_cancel', reply);
    if (!_abandoned) deliver(client, {...reply, 'request_action': 'greeter_cancel'});
    _release();
  }

  void _release() {
    _owner = null;
    _state = 'idle';
    _cancel = false;
    _abandoned = false;
  }

  Future<void> forget(T client) async {
    if (_closed || !identical(_owner, client)) return;
    _abandoned = true;
    // After start succeeded the greeter must exit; cancelling here would
    // interfere with the session that was deliberately started.
    if (_state == 'started') { _release(); return; }
    if (_busy) { _cancel = true; return; }
    _busy = true;
    try { await _cancelNow(client); } finally { _busy = false; }
  }

  Future<void> close() async {
    _closed = true;
    _release();
    await service.chiudi();
  }
}

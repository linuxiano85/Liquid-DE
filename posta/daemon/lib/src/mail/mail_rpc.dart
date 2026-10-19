import '../rpc/rpc_errors.dart';
import '../rpc/rpc_server.dart';
import 'mail_service.dart';

/// Metodi JSON-RPC per leggere e gestire la posta. Errori delle operazioni:
/// codice -32004 con il motivo in `error.data.reason` (vedi proto/api.md).
void registerMailMethods(RpcServer rpc, MailService mail) {
  final store = mail.messages;

  rpc.register('folder.list', (p, _) => store.folders(accountId: _optionalInt(p, 'accountId')));

  rpc.register('message.list', (p, _) {
    final folderId = _requireInt(p, 'folderId');
    final limit = _optionalInt(p, 'limit') ?? 50;
    if (limit < 1 || limit > 500) throw RpcException(RpcErrorCode.invalidParams, 'limit tra 1 e 500');
    final c = p['cursor'];
    ({int date, int id})? cursor;
    if (c != null) {
      if (c is! Map<String, Object?> || c['date'] is! int || c['id'] is! int) {
        throw RpcException(RpcErrorCode.invalidParams, 'cursor deve essere {date, id}');
      }
      cursor = (date: c['date'] as int, id: c['id'] as int);
    }
    final page = store.list(folderId, limit: limit, cursor: cursor);
    return {'messages': page.messages, 'next': page.next};
  });

  rpc.register('message.search', (p, _) {
    final q = p['query'];
    if (q is! String) throw RpcException(RpcErrorCode.invalidParams, 'query deve essere una stringa');
    final limit = _optionalInt(p, 'limit') ?? 50;
    if (limit < 1 || limit > 500) throw RpcException(RpcErrorCode.invalidParams, 'limit tra 1 e 500');
    return store.search(q, limit: limit, accountId: _optionalInt(p, 'accountId'));
  });

  rpc.register('message.get', (p, _) => _wrap(() {
        final remote = p['allowRemoteImages'];
        if (remote != null && remote is! bool) {
          throw RpcException(RpcErrorCode.invalidParams, 'allowRemoteImages deve essere vero o falso');
        }
        return mail.getMessage(_requireInt(p, 'id'), allowRemoteImages: remote == true);
      }));

  rpc.register('message.setFlags', (p, _) => _wrap(() async {
        final ids = _requireIds(p);
        final seen = _optionalBool(p, 'seen');
        final flagged = _optionalBool(p, 'flagged');
        await mail.setFlags(ids, seen: seen, flagged: flagged);
        return {'ok': true};
      }));

  rpc.register('message.move', (p, _) => _wrap(() async {
        await mail.move(_requireIds(p), _requireInt(p, 'folderId'));
        return {'ok': true};
      }));

  rpc.register('message.delete', (p, _) => _wrap(() async {
        await mail.delete(_requireIds(p));
        return {'ok': true};
      }));

  rpc.register('message.archive', (p, _) => _wrap(() async {
        await mail.archive(_requireIds(p));
        return {'ok': true};
      }));

  rpc.register('message.send', (p, _) => _wrap(() {
        List<String> strings(String key, {bool required = false}) {
          final v = p[key];
          if (v == null && !required) return const [];
          if (v is! List || v.any((x) => x is! String)) {
            throw RpcException(RpcErrorCode.invalidParams, '$key deve essere una lista di stringhe');
          }
          return v.cast<String>();
        }

        String text(String key) {
          final v = p[key] ?? '';
          if (v is! String) throw RpcException(RpcErrorCode.invalidParams, '$key deve essere una stringa');
          if (v.length > 2 * 1024 * 1024) throw RpcException(RpcErrorCode.invalidParams, '$key troppo lungo');
          return v;
        }

        return mail.send(
          accountId: _requireInt(p, 'accountId'),
          to: strings('to'),
          cc: strings('cc'),
          bcc: strings('bcc'),
          subject: text('subject'),
          text: text('text'),
          replyToId: _optionalInt(p, 'replyToId'),
          attachmentPaths: strings('attachments'),
        );
      }));

  rpc.register('attachment.save', (p, _) => _wrap(() async {
        final path = p['path'];
        if (path is! String) throw RpcException(RpcErrorCode.invalidParams, 'path deve essere una stringa');
        return {'path': await mail.saveAttachment(_requireInt(p, 'id'), path)};
      }));
}

Future<T> _wrap<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on MailOperationException catch (e) {
    throw RpcException(RpcErrorCode.mailError, e.message, {'reason': e.reason});
  } on RangeError catch (e) {
    throw RpcException(RpcErrorCode.invalidParams, '${e.message}');
  }
}

int _requireInt(Map<String, Object?> p, String key) {
  final v = p[key];
  if (v is! int) throw RpcException(RpcErrorCode.invalidParams, '$key deve essere un intero');
  return v;
}

int? _optionalInt(Map<String, Object?> p, String key) {
  final v = p[key];
  if (v != null && v is! int) throw RpcException(RpcErrorCode.invalidParams, '$key deve essere un intero');
  return v as int?;
}

bool? _optionalBool(Map<String, Object?> p, String key) {
  final v = p[key];
  if (v != null && v is! bool) throw RpcException(RpcErrorCode.invalidParams, '$key deve essere vero o falso');
  return v as bool?;
}

List<int> _requireIds(Map<String, Object?> p) {
  final v = p['ids'];
  if (v is! List || v.isEmpty || v.length > 1000 || v.any((x) => x is! int)) {
    throw RpcException(RpcErrorCode.invalidParams, 'ids deve essere una lista di 1-1000 interi');
  }
  return v.cast<int>().toSet().toList();
}

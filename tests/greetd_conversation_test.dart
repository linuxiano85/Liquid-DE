import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../minervad/lib/services/greetd_service.dart';
import '../minervad/lib/services/greetd_conversation.dart';

void check(bool value, String message) { if (!value) throw StateError(message); }
Future<void> tick() => Future<void>.delayed(Duration.zero);
const success = <String, dynamic>{'type': 'success'};
const prompt = <String, dynamic>{'type': 'auth_message', 'auth_message_type': 'secret', 'auth_message': 'Password:'};
class FakeGreetd extends GreetdService {
  final requests = <Map<String, dynamic>>[];
  final waiting = <Completer<Map<String, dynamic>>>[];
  @override
  Future<Map<String, dynamic>> request(Map<String, dynamic> message) {
    requests.add(Map.of(message));
    final c = Completer<Map<String, dynamic>>(); waiting.add(c); return c.future;
  }
  void reply(Map<String, dynamic> value) { waiting.removeAt(0).complete(value); }
}
class Fixture {
  final service = FakeGreetd();
  final a = Object(), b = Object();
  final replies = <(Object, Map<String, dynamic>)>[];
  late final broker = GreetdConversation<Object>(service, (c, r) => replies.add((c, r)));
  Future<void> create() async {
    final pending = broker.handle(a, 'greeter_create_session', {'username': 'demo'});
    service.reply(prompt); await pending;
  }
  Future<void> authenticate() async {
    await create();
    final pending = broker.handle(a, 'greeter_respond', {'response': 'fictional'});
    service.reply(success); await pending;
  }
}
class TestService extends GreetdService {
  TestService(this.path, {Duration timeout = const Duration(seconds: 2)}) : super(responseTimeout: timeout);
  final String path;
  @override String? get socketDaUsare => path;
}
class Peer {
  Peer(this.socket, this.message);
  final Socket socket;
  final Map<String, dynamic> message;
  Future<void> reply(Map<String, dynamic> value) async { socket.add(GreetdFramer.encode(value)); await socket.flush(); }
}
class Server {
  Server(this.dir, this.server) {
    server.listen((s) {
      sockets.add(s); final framer = GreetdFramer();
      s.listen((bytes) { for (final m in framer.aggiungi(bytes)) arrivals.add(Peer(s, m)); }, onError: (_) {});
    });
    incoming = StreamIterator(arrivals.stream);
  }
  final Directory dir;
  final ServerSocket server;
  final sockets = <Socket>[];
  final arrivals = StreamController<Peer>();
  late final StreamIterator<Peer> incoming;
  String get path => '${dir.path}/greetd.sock';
  static Future<Server> start() async {
    final dir = await Directory.systemTemp.createTemp('liquid-greetd-');
    return Server(dir, await ServerSocket.bind(InternetAddress('${dir.path}/greetd.sock', type: InternetAddressType.unix), 0));
  }
  Future<Peer> next() async {
    check(await incoming.moveNext().timeout(const Duration(seconds: 3)), 'server stream ended');
    return incoming.current;
  }
  Future<void> close() async {
    for (final s in sockets) { s.destroy(); }
    await server.close(); await incoming.cancel(); await arrivals.close(); await dir.delete(recursive: true);
  }
}
Future<void> main() async {
  var count = 0;
  Future<void> test(String name, Future<void> Function() run) async {
    await run().timeout(const Duration(seconds: 8)); count++; print('PASS $name');
  }
  await test('another client cannot steal, answer, start or cancel the owner conversation', () async {
    final f = Fixture(); await f.create();
    for (final action in ['greeter_create_session','greeter_respond','greeter_start','greeter_cancel'])
      await f.broker.handle(f.b, action, {'username':'other','response':'fake','cmd':['true']});
    check(f.service.requests.length == 1, 'foreign request reached greetd');
    check(f.replies.skip(1).every((r) => identical(r.$1, f.b) && r.$2['request_rejected'] == true), 'foreign reply leaked');
  });
  await test('start requires successful authentication by the same client', () async {
    final f = Fixture(); await f.create();
    await f.broker.handle(f.a, 'greeter_start', {'cmd':['true']});
    check(f.service.requests.length == 1, 'start before authentication');
  });
  await test('multi-round authentication preserves null versus empty response', () async {
    final f = Fixture(); await f.create();
    for (final value in [null, '', 'fictitious second factor']) {
      final p = f.broker.handle(f.a, 'greeter_respond', {'response':value});
      check(value == null ? !f.service.requests.last.containsKey('response') : f.service.requests.last['response'] == value, 'wrong response');
      f.service.reply(prompt); await p;
    }
  });
  await test('cancellation waits for and suppresses the previous success', () async {
    final f = Fixture(); await f.create(); f.replies.clear();
    final p = f.broker.handle(f.a, 'greeter_respond', {'response':'fictional'});
    await f.broker.handle(f.a, 'greeter_cancel', {});
    check(f.service.requests.length == 2, 'cancel overlapped request');
    f.service.reply(success); await tick();
    check(f.replies.isEmpty, 'old success leaked');
    check(f.service.requests.last['type'] == 'cancel_session', 'cancel not sent');
    f.service.reply(success); await p;
    check(f.replies.single.$2['request_action'] == 'greeter_cancel', 'wrong cancellation acknowledgement');
  });
  await test('disconnect holds ownership until cleanup and discards old replies', () async {
    final f = Fixture(); final p = f.broker.handle(f.a, 'greeter_create_session', {'username':'demo'});
    await f.broker.forget(f.a);
    await f.broker.handle(f.b, 'greeter_create_session', {'username':'other'});
    f.service.reply(prompt); await tick();
    check(f.service.requests.last['type'] == 'cancel_session', 'missing cleanup');
    f.service.reply(success); await p;
    check(f.replies.every((r) => identical(r.$1,f.b) && r.$2['request_rejected'] == true), 'abandoned reply delivered');
    final q = f.broker.handle(f.b, 'greeter_create_session', {'username':'other'});
    f.service.reply(prompt); await q;
    check(identical(f.replies.last.$1,f.b) && f.replies.last.$2['type']=='auth_message', 'new owner failed');
  });
  await test('malformed session argv cannot throw or reach greetd', () async {
    final f = Fixture(); await f.authenticate();
    for (final cmd in [null, [], [1], 'true']) await f.broker.handle(f.a, 'greeter_start', {'cmd':cmd});
    check(f.service.requests.length==2, 'malformed argv sent');
  });
  await test('normal start and greeter exit do not cancel a started session', () async {
    final f=Fixture(); await f.authenticate();
    final p=f.broker.handle(f.a,'greeter_start',{'cmd':['true'],'env':[]}); f.service.reply(success); await p;
    await f.broker.forget(f.a);
    check(f.service.requests.length==3, 'started session cancelled');
  });
  await test('disconnect during successful start does not issue cancel', () async {
    final f=Fixture(); await f.authenticate();
    final p=f.broker.handle(f.a,'greeter_start',{'cmd':['true']}); await f.broker.forget(f.a);
    f.service.reply(success); await p;
    check(f.service.requests.length==3, 'late successful start cancelled');
  });
  await test('transport failure requires a successful reset before another create', () async {
    final f=Fixture();
    final p=f.broker.handle(f.a,'greeter_create_session',{'username':'demo'});
    f.service.reply(GreetdService.failure('fake disconnect')); await p;
    final q=f.broker.handle(f.a,'greeter_create_session',{'username':'demo'});
    check(f.service.requests.last['type']=='cancel_session','no reset barrier');
    f.service.reply(success); await tick();
    check(f.service.requests.last['type']=='create_session','creation not resumed');
    f.service.reply(prompt); await q;
  });
  await test('duplicate response cannot create concurrent secret writes', () async {
    final f=Fixture(); await f.create();
    final p=f.broker.handle(f.a,'greeter_respond',{'response':'first'});
    await f.broker.handle(f.a,'greeter_respond',{'response':'second'});
    check(f.service.requests.length==2 && f.service.requests.last['response']=='first','duplicate secret sent');
    f.service.reply(success); await p;
  });
  await test('real Unix socket accepts fragmented UTF-8 reply', () async {
    final server=await Server.start(); final service=TestService(server.path);
    try {
      final result=service.request({'type':'create_session','username':'demo'});
      final peer=await server.next(); final bytes=GreetdFramer.encode({...prompt,'auth_message':'Città 🔑'});
      for(final b in bytes) { peer.socket.add([b]); await peer.socket.flush(); }
      check((await result)['auth_message']=='Città 🔑','fragmented reply corrupted');
    } finally { await service.chiudi(); await server.close(); }
  });
  await test('partial frame from closed connection cannot poison the next socket', () async {
    final server=await Server.start(); final service=TestService(server.path);
    try {
      final first=service.request({'type':'create_session','username':'demo'});
      final peer=await server.next(); peer.socket.add([42,0]); await peer.socket.flush(); peer.socket.destroy();
      check((await first)['transport_error']==true,'EOF not reported');
      final second=service.request({'type':'cancel_session'}); await (await server.next()).reply(success);
      check((await second)['type']=='success','old frame survived reconnection');
    } finally { await service.chiudi(); await server.close(); }
  });
  await test('timeout closes the real socket and permits a fresh request', () async {
    final server=await Server.start(); final service=TestService(server.path,timeout:const Duration(milliseconds:100));
    try {
      final first=service.request({'type':'cancel_session'}); await server.next();
      check((await first)['transport_error']==true && !service.connesso,'timeout did not close channel');
      final second=service.request({'type':'cancel_session'}); await (await server.next()).reply(success);
      check((await second)['type']=='success','timeout poisoned next request');
    } finally { await service.chiudi(); await server.close(); }
  });
  await test('closing during a request reports once and remains closed', () async {
    final server=await Server.start(); final service=TestService(server.path);
    try {
      final p=service.request({'type':'cancel_session'}); await server.next(); await service.chiudi();
      check((await p)['transport_error']==true,'pending request not completed');
      check((await service.request({'type':'cancel_session'}))['transport_error']==true,'closed service reopened');
      await service.chiudi();
    } finally { await service.chiudi(); await server.close(); }
  });
  await test('malformed JSON never copies wire data into the error', () async {
    final server=await Server.start(); final service=TestService(server.path);
    try {
      final p=service.request({'type':'cancel_session'}); final peer=await server.next();
      final bytes=Uint8List(8); ByteData.view(bytes.buffer).setUint32(0,4,Endian.host); bytes.setRange(4,8,[83,69,67,82]);
      peer.socket.add(bytes); await peer.socket.flush(); final result=await p;
      check(result['transport_error']==true && !result.toString().contains('SECR'),'wire data leaked');
    } finally { await service.chiudi(); await server.close(); }
  });
  await test('two wire responses for one request fail closed', () async {
    final server=await Server.start(); final service=TestService(server.path);
    try {
      final p=service.request({'type':'cancel_session'}); final peer=await server.next();
      peer.socket.add([...GreetdFramer.encode(success),...GreetdFramer.encode(success)]); await peer.socket.flush();
      check((await p)['transport_error']==true,'unsolicited success accepted');
    } finally { await service.chiudi(); await server.close(); }
  });
  print('GREETD_CONVERSATION_TESTS_PASSED=$count');
}

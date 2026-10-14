// Private test daemon: real SettingsApi, recorded actions, real test clients.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/core/settings_api.dart';
import 'package:minervad/services/keybind_service.dart';
import 'package:minervad/services/notizie_service.dart';
import 'package:minervad/services/file_service.dart';
import 'package:minervad/services/liquid_update_service.dart';
Future<void> main(List<String> args) async {
  final directory = args.single;
  if (!directory.startsWith('/tmp/minerva-tiling-windows11-')) {
    throw ArgumentError('private Windows test directory required');
  }
  final root = Platform.environment['LIQUID_DE']!;
  final bus = EventBus();
  final settings = SettingsApi(bus, path:'$directory/settings.json');
  final keys = KeybindService(path:'$root/config/scorciatoie.minerva');
  await settings.init();
  await keys.reload();
  final files = FileService();
  final clients = <Socket>{};
  final updateClients = <Socket>{};
  final updateApi = Uri.parse(Platform.environment['MINERVA_UPDATE_TEST_API'] ?? 'http://127.0.0.1:9/');
  final updates = LiquidUpdateService(root:'$directory/update-install',
    directory:'$directory/updates',state:'$directory/updates-state.json',
    api:updateApi,archive:updateApi,test:true);
  await updates.init();
  final processes = <Process>[];
  final actions = <Map>[];
  final audioSubscribers = <Socket>{};
  var audioFailure = false;
  var audioStall = false;
  var audioState = <String, dynamic>{
    'ok': true,
    'defaultSink': 'speakers',
    'sinks': [
      {'name': 'speakers', 'description': 'Altoparlanti'},
      {'name': 'headphones', 'description': 'Cuffie USB'},
      {'name': 'hdmi', 'description': 'Monitor HDMI'},
    ],
  };
  void send(Socket socket, String event, dynamic payload) {
    socket.write('${jsonEncode({'event':event,'payload':payload})}\n');
  }
  final updateSubscription = updates.changes.stream.listen((state) {
    for (final client in updateClients.toList()) send(client,'liquid_update',state);
  });
  final subscription = bus.stream.listen((event) {
    for (final socket in clients.toList()) send(socket,event.type,event.payload);
  });
  final server = await ServerSocket.bind(InternetAddress('$directory/settings.sock',type:InternetAddressType.unix),0);
  server.listen((socket) {
    clients.add(socket);
    socket.cast<List<int>>().transform(utf8.decoder).transform(const LineSplitter()).listen((line) async {
      final msg = jsonDecode(line) as Map;
      if (msg['action']=='ciao') {
        send(socket,'ciao',{'ok':true});
        send(socket,'init_state',{'settings':settings.settings});
      } else if ('${msg['action']}'.startsWith('liquid_update_')) {
        actions.add(msg);
        switch (msg['action']) {
          case 'liquid_update_subscribe':
            updateClients.add(socket);
            send(socket,'liquid_update',updates.state);
            break;
          case 'liquid_update_unsubscribe':
            updateClients.remove(socket);
            break;
          case 'liquid_update_check':
            await updates.check();
            break;
          case 'liquid_update_download':
            await updates.download(msg['revision'] as String);
            break;
          case 'liquid_update_cancel':
            updates.cancel();
            break;
          case 'liquid_update_pause':
            await updates.pause(msg['days'] as int);
            break;
        }
      } else if (msg['action'] == 'rescan_apps') {
        // Il catalogo della prova può cambiare dopo l'avvio del launcher.
        // Senza file lasciamo invariati i cataloghi delle prove esistenti.
        actions.add(msg);
        final catalog = File('$directory/catalogo-app.json');
        if (catalog.existsSync()) {
          send(socket, 'all_apps', jsonDecode(catalog.readAsStringSync()));
        }
      } else if (msg['action']=='scorciatoie_compositore') {
        send(socket,'scorciatoie_compositore',{'righe':keys.perMinervaWayland()});
      } else if (msg['action']=='get_keybindings') {
        send(socket,'keybindings',keys.toJson());
      } else if (msg['action']=='set_setting') {
        final ok = await settings.setValue(msg['path'] as String,msg['value']);
        actions.add({...msg,'accepted':ok});
      } else if (msg['action']=='set_settings') {
        final rejected = await settings.setValues(Map<String,dynamic>.from(msg['values'] as Map));
        actions.add({...msg,'rejected':rejected});
      } else if (msg['action'] == 'subscribe_audio') {
        audioSubscribers.add(socket);
        actions.add(msg);
      } else if (msg['action'] == 'unsubscribe_audio') {
        audioSubscribers.remove(socket);
        actions.add(msg);
      } else if (msg['action'] == 'system_audio_state') {
        send(socket, 'system_audio_state', audioState);
        actions.add(msg);
      } else if (msg['action'] == 'system_audio_select') {
        actions.add(msg);
        if (audioStall) {
          // Nessuna risposta: si verifica il timeout del client.
        } else if (audioFailure) {
          send(socket, 'system_audio_select', {
            'ok': false,
            'error': 'Uscita non disponibile',
            'state': audioState,
          });
        } else {
          audioState['defaultSink'] = msg['name'];
          send(socket, 'system_audio_select', audioState);
        }
      } else if (msg['action'] == 'fixture_audio') {
        // Solo il demone privato comprende questa azione: nessuna prova può
        // cambiare le uscite reali, neppure quando simula un guasto.
        audioFailure = msg['fail'] == true;
        audioStall = msg['stall'] == true;
        if (msg['state'] is Map) {
          audioState = Map<String, dynamic>.from(msg['state'] as Map);
          for (final client in audioSubscribers.toList()) {
            send(client, 'system_audio_state', audioState);
          }
        }
        send(socket, 'fixture_audio', {'ok': true});
      } else if (msg['action']=='launch_app') {
        actions.add(msg);
        // The fixture catalog has only this executable. No shell interpolation.
        if (msg['id']=='test-files.desktop') {
          final p = await Process.start('qs',['-p','$directory/files.qml'],environment:{
            'MINERVA_SCRIVANIA':'0',
            if (msg['activationToken'] is String) 'XDG_ACTIVATION_TOKEN':msg['activationToken'] as String,
          });
          processes.add(p);
          p.stdout.drain<void>();p.stderr.drain<void>();
        }
      } else if (msg['action'] == 'fs_places') {
        send(socket, 'fs_places', {'places': [
          {'kind': 'pictures', 'path': '$directory/photos-personnalisees', 'name': 'Photos', 'nellaBarra': true},
        ]});
      } else if (msg['action'] == 'fs_list') {
        // Elenchi veri su file temporanei, senza osservare cartelle dell'utente.
        final result = await files.list(msg['path'] as String, showHidden: msg['showHidden'] == true);
        result['pane'] = msg['pane'];
        send(socket, 'fs_listing', result);
        actions.add(msg);
      } else if (msg['action'] == 'fs_mkdir') {
        final path = msg['path'] as String;
        if (!path.startsWith('$directory/')) throw StateError('mkdir outside fixture');
        final result = await files.makeDirectory(path);
        if (result['ok'] == true) result['creati'] = [path];
        send(socket, 'fs_result', result);
        actions.add(msg);
      } else if (msg['action'] == 'fs_unwatch') {
        actions.add(msg);
      } else if (msg['action']=='fs_recenti') {
        send(socket,'fs_search',{'id':msg['id'],'fine':true,'voci':[
          {'name':'Progetto.txt','path':'$directory/Progetto.txt','isDir':false,'dove':'Documenti'},
          {'name':'Appunti.txt','path':'$directory/Appunti.txt','isDir':false,'dove':'Documenti'},
        ]});
      } else if (msg['action']=='fs_search') {
        send(socket,'fs_search',{'id':msg['id'],'fine':true,'voci':[
          {'name':'Progetto.txt','path':'$directory/Progetto.txt','isDir':false,'dove':'Documenti'}
        ]});
      } else if (msg['action']=='notizie') {
        // Notizie finte, senza rete: due per interesse, una con l'immagine
        // (un file locale, come quelle che scarica il demone vero). Si filtra
        // per interessi come fa `NotizieService`.
        final img = File('$directory/notizia.png');
        if (!img.existsSync()) {
          img.writeAsBytesSync(base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='));
        }
        final scelti = msg['interessi'] is List ? (msg['interessi'] as List).whereType<String>().toList() : NotizieService.interessi;
        final articoli = <Map<String,dynamic>>[];
        for (final i in NotizieService.interessi.where(scelti.contains)) {
          for (var n = 1; n <= 2; n++) {
            articoli.add({'titolo':'Notizia $n di $i','fonte':'Fonte $i','link':'https://esempio.it/$i/$n',
              'data':'2026-10-11T12:0$n:00.000Z','interesse':i,'immagine':n == 1 ? img.path : ''});
          }
        }
        send(socket,'notizie',{'articoli':articoli,'error':'','fonti':[]});
        actions.add({'action':'notizie','interessi':scelti});
      } else if (msg['action']=='notizie_fonti') {
        final spente = msg['spente'] is List ? (msg['spente'] as List).whereType<String>().toList() : <String>[];
        send(socket,'notizie_fonti',{'fonti':NotizieService().elencoFonti('${msg['lingua']}' == 'en' ? 'en' : 'it', spente)});
      } else if (['system_action','open_default'].contains(msg['action'])) {
        actions.add(msg);
      }
      File('$directory/actions.json').writeAsStringSync(jsonEncode(actions));
    },onDone: () {
      clients.remove(socket);
      updateClients.remove(socket);
      audioSubscribers.remove(socket);
    });
  });
  print('READY');
  ProcessSignal.sigterm.watch().listen((_) async {
    await updateSubscription.cancel();
    await updates.close();
    for(final p in processes)p.kill();
    for(final socket in clients.toList())socket.destroy();
    await server.close();await subscription.cancel();await settings.dispose();await bus.dispose();exit(0);
  });
}

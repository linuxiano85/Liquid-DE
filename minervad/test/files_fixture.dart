// API dei file reale, impostazioni private e nessuna azione sul sistema host.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:minervad/core/event_bus.dart';
import 'package:minervad/core/settings_api.dart';
import 'package:minervad/services/file_service.dart';
import 'package:minervad/services/ricerca_service.dart';

Future<void> main(List<String> args) async {
  final directory = args.single;
  if (!directory.startsWith('/tmp/liquid-files-test-')) {
    throw ArgumentError('Serve una cartella privata della prova');
  }
  final bus = EventBus();
  final settings = SettingsApi(bus, path: '$directory/settings.json');
  final files = FileService(cestinoDiProva: '$directory/cestino');
  final ricerca = RicercaService();
  await settings.init();
  await settings.setValues({
    'stile.attuale': 'windows',
    'shell.scheme': 'giorno',
    'files.sfondiAutomatici': false,
    'files.tieniAcceso': false,
  });
  final clients = <Socket>{};
  final actions = <Map>[];
  // I telefoni e le cartelle di rete simulati dalla prova. `Files.qml` li
  // richiede da solo ogni otto secondi: se qui si rispondesse sempre «nessuno»,
  // quella domanda cancellerebbe lo stato simulato a metà prova.
  var remoti = <String, dynamic>{'luoghi': [], 'mancano': []};
  void send(Socket client, String event, dynamic payload) {
    client.write('${jsonEncode({'event': event, 'payload': payload})}\n');
  }

  final subscription = bus.stream.listen((event) {
    for (final client in clients.toList()) {
      send(client, event.type, event.payload);
    }
  });
  final progress = files.progress.listen((job) {
    for (final client in clients.toList()) {
      send(client, 'fs_job', job);
    }
  });
  final server = await ServerSocket.bind(
    InternetAddress('$directory/daemon.sock', type: InternetAddressType.unix),
    0,
  );
  server.listen((client) {
    clients.add(client);
    client
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) async {
          final message = jsonDecode(line) as Map;
          actions.add(message);
          final action = message['action'];
          if (action == 'ciao') {
            send(client, 'ciao', {'ok': true});
            send(client, 'init_state', {'settings': settings.settings});
          } else if (action == 'set_setting') {
            await settings.setValue(
              message['path'] as String,
              message['value'],
            );
          } else if (action == 'fs_list') {
            final listing = await files.list(
              message['path'] as String,
              showHidden: message['showHidden'] == true,
            );
            send(client, 'fs_listing', {...listing, 'pane': message['pane']});
          } else if (action == 'fs_places') {
            send(client, 'fs_places', await files.places());
          } else if (action == 'fs_volumes') {
            send(client, 'fs_volumes', {'volumes': []});
          } else if (action == 'fs_remoti') {
            send(client, 'fs_remoti', remoti);
          } else if (action == 'fixture_remoti') {
            remoti = Map<String, dynamic>.from(message['stato'] as Map);
          } else if (action == 'fs_jobs') {
            send(client, 'fs_jobs', files.jobsJson());
          } else if (action == 'radice_disponibile') {
            send(client, 'radice_stato', {'disponibile': false});
          } else if (action == 'fs_conflitti') {
            send(client, 'fs_conflitti', {'nomi': []});
          } else if (action == 'fs_transfer') {
            final sources = List<String>.from(message['sources'] as List);
            final destination = message['destination'] as String;
            if (!sources.every((path) => path.startsWith('$directory/')) ||
                !destination.startsWith('$directory/')) {
              throw StateError('Trasferimento fuori dalla cartella privata');
            }
            await files.startTransfer(
              sources: sources,
              destination: destination,
              move: message['move'] == true,
            );
          } else if (action == 'fs_search') {
            final path = message['path'] as String;
            final id = message['id'] as String;
            if (!path.startsWith('$directory/')) {
              throw StateError('Ricerca fuori dalla cartella privata');
            }
            await for (final part in ricerca.cerca(id, path, message['query'] as String,
                ancheNascosti: message['hidden'] == true)) {
              send(client, 'fs_search', {...part, 'id': id});
            }
          } else if (action == 'fs_search_cancel') {
            ricerca.ferma(message['id'] as String);
          } else if (action == 'fs_rename') {
            final from = message['from'] as String;
            final to = message['to'] as String;
            if (!from.startsWith('$directory/') ||
                !to.startsWith('$directory/')) {
              throw StateError('Rinomina fuori dalla cartella privata');
            }
            final result = await files.rename(from, to);
            send(client, 'fs_result', {
              ...result,
              'operazione': 'rinomina',
              'da': from,
              'a': to,
            });
          } else if (action == 'fs_anteprima') {
            final path = message['path'] as String;
            if (!path.startsWith('$directory/')) {
              throw StateError('Anteprima fuori dalla cartella privata');
            }
            // Un attimo di ritardo voluto: così la prova può cambiare
            // selezione prima che arrivi la risposta di quella vecchia.
            if (path.contains('lenta')) {
              await Future.delayed(const Duration(milliseconds: 600));
            }
            send(client, 'fs_anteprima',
                {...await files.anteprima(path), 'richiesta': message['richiesta']});
          } else if (action == 'fs_touch') {
            final path = message['path'] as String;
            if (!path.startsWith('$directory/')) {
              throw StateError('Creazione fuori dalla cartella privata');
            }
            send(client, 'fs_result', await files.creaFile(path));
          } else if (action == 'fs_trash') {
            final paths = List<String>.from(message['paths'] as List);
            if (!paths.every((path) => path.startsWith('$directory/'))) {
              throw StateError('Cestino fuori dalla cartella privata');
            }
            send(client, 'fs_result', await files.trash(paths));
          }
          File(
            '$directory/actions.json',
          ).writeAsStringSync(jsonEncode(actions));
        }, onDone: () => clients.remove(client));
  });
  print('READY');
  ProcessSignal.sigterm.watch().listen((_) async {
    for (final client in clients.toList()) {
      client.destroy();
    }
    await server.close();
    await progress.cancel();
    await subscription.cancel();
    files.dispose();
    await settings.dispose();
    await bus.dispose();
    exit(0);
  });
}

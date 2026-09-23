import 'dart:convert';
import 'dart:io';
import '../core/event_bus.dart';
import '../core/minerva_paths.dart';
import '../ipc/websocket_server.dart';

/// Gestisce l'avvio e l'arresto dei plugin esterni (processi separati).
class PluginManager {
  final EventBus _eventBus;
  final String _pluginsDir;
  final List<Process> _activeProcesses = [];

  PluginManager(this._eventBus, {String? dir})
      : _pluginsDir = dir ?? MinervaPaths.pluginsDir();

  /// Scansiona la cartella plugins ed esegue i plugin abilitati.
  ///
  /// ── QUESTA FUNZIONE NON PUÒ FALLIRE ────────────────────────────────────
  ///
  /// Prima creava la cartella se non c'era, e se la creazione falliva
  /// l'eccezione risaliva fino a `main`, che stampa e chiama `exit(1)`. Il
  /// risultato, il 10 agosto 2026, è stato il guasto peggiore visto finora:
  ///
  ///   · la cartella dei plugin sta DENTRO l'installazione
  ///     (`/usr/local/share/minerva/plugins`);
  ///   · la schermata di accesso gira come utente `greeter`, che lì non può
  ///     scrivere;
  ///   · quindi il demone del greeter partiva, apriva la porta 11433, e
  ///     moriva subito dopo con «Permission denied»;
  ///   · la schermata restava in piedi, bella, con l'elenco degli utenti
  ///     VUOTO — e non c'era modo di entrare nel computer.
  ///
  /// Un accessorio che nessuno usa non deve poter impedire l'accesso alla
  /// macchina. Quindi: non si crea più niente, e qualunque cosa vada storta
  /// resta un avviso.
  ///
  /// Non creare la cartella non toglie niente: un plugin esiste solo se
  /// qualcuno ce lo mette, e chi ce lo mette la cartella la crea nel farlo.
  /// Una cartella vuota fabbricata a ogni avvio non è mai servita a nessuno.
  Future<void> init() async {
    try {
      final dir = Directory(_pluginsDir);
      if (!await dir.exists()) return;

      for (final entity in await dir.list().toList()) {
        if (entity is Directory) {
          await _loadPluginFromDir(entity);
        }
      }
    } catch (e) {
      print('[MINERVA][CORE][WARN] I plugin non sono stati caricati: $e');
    }
  }

  Future<void> _loadPluginFromDir(Directory dir) async {
    final manifestFile = File('${dir.path}/plugin.json');
    if (!await manifestFile.exists()) return;

    try {
      final content = await manifestFile.readAsString();
      final Map<String, dynamic> manifest = jsonDecode(content);

      final name = manifest['name'] ?? dir.uri.pathSegments.last;
      final bool enabled = manifest['enabled'] ?? true;
      final String? execCmd = manifest['executable'];

      if (!enabled) {
        print('[MINERVA][CORE][INFO] Plugin "$name" disabilitato.');
        return;
      }

      if (execCmd == null || execCmd.isEmpty) {
        print('[MINERVA][CORE][WARN] Plugin "$name" non contiene un comando eseguibile.');
        return;
      }

      print('[MINERVA][CORE][INFO] Avvio del plugin "$name" in corso...');
      _runPluginProcess(name, execCmd, dir.path);
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] Impossibile caricare il plugin da ${dir.path}: $e');
    }
  }

  void _runPluginProcess(String name, String cmd, String workingDir) async {
    final parts = cmd.split(' ');
    final executable = parts.first;
    final arguments = parts.sublist(1);

    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDir,
        environment: {
          // L'indirizzo è quello su cui questo demone ascolta davvero, non
          // una costante: dentro la schermata di accesso è un altro.
          //
          // Dal 27 agosto 2026 è un socket Unix e non più `ws://`. Il nome
          // della variabile cambia con lui: un plugin che cercasse ancora
          // `MINERVA_CORE_WS` non la trova, e non trovare niente è meglio che
          // trovare un indirizzo dove non risponde nessuno.
          'MINERVA_CORE_SOCK': WebSocketServer.socketConfigurato,
          'MINERVA_PLUGIN_NAME': name,
        },
      );

      _activeProcesses.add(process);
      print('[MINERVA][CORE][OK] Plugin "$name" avviato con successo (PID: ${process.pid}).');

      // Reindirizza l'output del plugin sui log di Minerva
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        print('[MINERVA][PLUGIN][$name] $line');
      });

      process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        print('[MINERVA][PLUGIN][$name][ERRORE] $line');
      });

      process.exitCode.then((code) {
        _activeProcesses.remove(process);
        print('[MINERVA][CORE][WARN] Il plugin "$name" è terminato con codice d\'uscita: $code');
        _eventBus.publish(MinervaEvent(
          type: 'plugin_terminated',
          payload: {'name': name, 'exitCode': code},
        ));
      });
    } catch (e) {
      print('[MINERVA][CORE][ERRORE] Impossibile avviare il processo del plugin "$name": $e');
    }
  }

  /// Ferma tutti i processi dei plugin attivi.
  Future<void> dispose() async {
    print('[MINERVA][CORE][INFO] Arresto di tutti i plugin attivi in corso...');
    for (final process in _activeProcesses) {
      process.kill();
    }
    _activeProcesses.clear();
  }
}

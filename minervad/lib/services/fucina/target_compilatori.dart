import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Interroga il driver, senza compilare o eseguire programmi generati.
/// I comandi e gli argomenti sono fissi: l'IPC non sceglie un eseguibile.
class TargetCompilatori {
  final Map<String, String> ambiente;
  final Duration limite;
  TargetCompilatori({
    Map<String, String>? ambiente,
    this.limite = const Duration(seconds: 3),
  }) : ambiente = ambiente ?? Platform.environment;

  static const comandi = {
    'gcc': ['-Q', '--help=target', '-march=native', '-mtune=native'],
    'clang': [
      '-###',
      '-march=native',
      '-x',
      'c',
      '-c',
      '/dev/null',
      '-o',
      '/dev/null',
    ],
  };
  static const massimo = 64 * 1024;
  Future<List<Map<String, dynamic>>>? _inCorso;

  Future<List<Map<String, dynamic>>> leggi(
    Map<String, dynamic> macchina,
  ) async {
    if (!RegExp(r'^v[1-4]$').hasMatch('${macchina['livelloX86'] ?? ''}')) {
      return [];
    }
    final attiva = _inCorso;
    if (attiva != null) return attiva;
    final nuova = Future.wait([for (final nome in comandi.keys) _sonda(nome)]);
    _inCorso = nuova;
    try {
      return await nuova;
    } finally {
      if (identical(_inCorso, nuova)) _inCorso = null;
    }
  }

  static Map<String, dynamic> interpreta(String nome, String testo) {
    String token(String? s) =>
        s != null &&
            s != 'native' &&
            RegExp(r'^[a-zA-Z0-9_+.-]{1,80}$').hasMatch(s)
        ? s
        : '';
    String cpu = '', tune = '';
    if (nome == 'gcc') {
      cpu = token(
        RegExp(
          r'^\s*-march=\s+(\S+)\s*$',
          multiLine: true,
        ).firstMatch(testo)?.group(1),
      );
      tune = token(
        RegExp(
          r'^\s*-mtune=\s+(\S+)\s*$',
          multiLine: true,
        ).firstMatch(testo)?.group(1),
      );
    } else if (nome == 'clang') {
      cpu = token(
        RegExp(r'"-target-cpu"\s+"([^"]+)"').firstMatch(testo)?.group(1),
      );
    }
    return {
      'compilatore': nome,
      'rilevato': cpu.isNotEmpty,
      'cpu': cpu,
      'tuning': tune,
      'messaggio': cpu.isEmpty
          ? 'Il compilatore non ha restituito un target native riconoscibile.'
          : 'Target dichiarato dal compilatore sul PC corrente; non certifica la ricetta Kbuild o le prestazioni.',
    };
  }

  Future<Map<String, dynamic>> _sonda(String nome) async {
    Map<String, dynamic> no(String motivo) => {
      'compilatore': nome,
      'rilevato': false,
      'cpu': '',
      'tuning': '',
      'messaggio': motivo,
    };
    Process? p;
    StreamSubscription<List<int>>? stdout, stderr;
    final a = Completer<void>(), b = Completer<void>();
    final bytes = <int>[];
    var troppo = false;
    var terminato = false;
    var letturaFallita = false;
    try {
      p = await Process.start(
        nome,
        comandi[nome]!,
        workingDirectory: '/tmp',
        environment: {...ambiente, 'LC_ALL': 'C'},
        includeParentEnvironment: false,
      );
      final processo = p;
      await p.stdin.close();
      void ricevi(List<int> pezzo) {
        if (troppo) return;
        if (bytes.length + pezzo.length > massimo) {
          troppo = true;
          if (!terminato) processo.kill(ProcessSignal.sigkill);
        } else {
          bytes.addAll(pezzo);
        }
      }

      stdout = p.stdout.listen(
        ricevi,
        onDone: () {
          if (!a.isCompleted) a.complete();
        },
        onError: (Object _) {
          letturaFallita = true;
          if (!a.isCompleted) a.complete();
        },
        cancelOnError: true,
      );
      stderr = p.stderr.listen(
        ricevi,
        onDone: () {
          if (!b.isCompleted) b.complete();
        },
        onError: (Object _) {
          letturaFallita = true;
          if (!b.isCompleted) b.complete();
        },
        cancelOnError: true,
      );
      final codice = p.exitCode.then((c) {
        terminato = true;
        return c;
      });
      await Future.wait([codice, a.future, b.future]).timeout(limite);
      if (troppo) {
        return no(
          'Diagnostica del compilatore oltre il limite: target non verificato.',
        );
      }
      if (letturaFallita) {
        return no(
          'Diagnostica del compilatore incompleta: target non verificato.',
        );
      }
      if (await codice != 0) {
        return no(
          'Il compilatore non ha completato la verifica del target native.',
        );
      }
      return interpreta(nome, utf8.decode(bytes, allowMalformed: true));
    } on TimeoutException {
      return no('La verifica del compilatore ha superato il tempo limite.');
    } on ProcessException {
      return no('Compilatore non disponibile o non avviabile.');
    } catch (_) {
      return no('Non riesco a verificare il target del compilatore.');
    } finally {
      if (!terminato) p?.kill(ProcessSignal.sigkill);
      await stdout?.cancel();
      await stderr?.cancel();
      if (!a.isCompleted) a.complete();
      if (!b.isCompleted) b.complete();
      if (p != null) {
        try {
          await p.exitCode.timeout(const Duration(seconds: 1));
        } catch (_) {}
      }
    }
  }
}

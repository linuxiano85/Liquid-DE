import 'dart:async';
import 'dart:math';

import 'mail_transport.dart';

/// Attesa esponenziale con jitter: 1 s, 2 s, 4 s ... fino a [max].
/// Il jitter evita che, dopo un guasto del provider, tutti i client
/// si ricolleghino nello stesso istante.
class Backoff {
  Backoff({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(minutes: 5),
    this.jitter = 0.2,
    Random? random,
  })  : assert(jitter >= 0 && jitter < 1),
        _random = random ?? Random();

  final Duration initial;
  final Duration max;
  final double jitter;
  final Random _random;
  int _attempt = 0;

  Duration next() {
    // Calcolo in double ed esponente limitato: con gli interi pow(2, 64)
    // va in overflow e restituisce 0, cioè nessuna attesa tra i tentativi
    // dopo una lunga assenza di rete.
    final base = initial.inMicroseconds * pow(2.0, min(_attempt, 40));
    _attempt++;
    final capped = min(base, max.inMicroseconds.toDouble());
    final factor = 1 + (_random.nextDouble() * 2 - 1) * jitter;
    return Duration(microseconds: min(capped * factor, max.inMicroseconds.toDouble()).round());
  }

  void reset() => _attempt = 0;
}

typedef Sleep = Future<void> Function(Duration);

/// Esegue [attempt] finché riesce, fallisce con un errore non ritentabile
/// o esaurisce [maxAttempts]. Rilancia l'ultimo errore.
Future<T> retryTransport<T>(
  Future<T> Function() attempt, {
  required Backoff backoff,
  int maxAttempts = 8,
  Sleep sleep = _defaultSleep,
  void Function(int attempt, MailTransportException error, Duration wait)? onRetry,
}) async {
  if (maxAttempts < 1) throw ArgumentError.value(maxAttempts, 'maxAttempts');
  for (var i = 1;; i++) {
    try {
      final result = await attempt();
      backoff.reset();
      return result;
    } on MailTransportException catch (e) {
      if (!e.kind.retryable || i >= maxAttempts) rethrow;
      final wait = backoff.next();
      onRetry?.call(i, e, wait);
      await sleep(wait);
    }
  }
}

Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);

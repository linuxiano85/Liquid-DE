import 'dart:io';

import '../services/app_scanner.dart';

/// Lanciatori — Quando un file `.desktop` si può eseguire senza domande.
///
/// ── Il buco, provato il 30 settembre 2026 ──────────────────────────────────
///
/// Un `.desktop` è un pulsante: dentro c'è una riga `Exec=` che il demone
/// passa a `sh -c`. Fino a oggi qualunque `.desktop`, in qualunque cartella,
/// partiva al doppio clic — nel gestore file e sulla scrivania — e
/// nell'elenco compariva col NOME e l'ICONA che dichiarava lui.
///
/// Messo insieme fa questo: in `~/Scaricati` arriva `Fattura_2026.pdf.desktop`
/// (0644, `Name=Fattura_2026.pdf`, `Icon=application-pdf`). Il gestore file lo
/// mostra come «Fattura_2026.pdf» con l'icona di un PDF, e il doppio clic
/// esegue il suo comando. Provato: il file di prova `ESEGUITO` è comparso.
/// Per `joca.sh`, che è un eseguibile vero, invece ci si ferma a chiedere.
///
/// ── La regola, che è quella di tutti gli altri ─────────────────────────────
///
///  · dentro le cartelle delle applicazioni (quelle XDG che legge già
///    `AppScanner`) si lancia e basta: là dentro ci scrive chi installa
///    programmi, e il menù li lancia già senza chiedere;
///  · altrove si lancia solo se ha il permesso di esecuzione — è la regola di
///    KDE, e un file scaricato dal browser non lo ha mai;
///  · e il nome e l'icona dichiarati si mostrano solo per i lanciatori di cui
///    ci si fida (i primi, o quelli eseguibili). Un `.desktop` scaricato si
///    vede col suo nome di file, che è l'unica cosa che non può mentire.
///
/// Il percorso si confronta DOPO aver risolto i collegamenti: un collegamento
/// in `~/Scaricati` verso `/usr/share/applications/firefox.desktop` è
/// Firefox; uno dentro `~/.local/share/applications` che punta a
/// `~/Scaricati/qualcosa.desktop` non lo è.
class Lanciatori {
  const Lanciatori._();

  /// Il file, con i collegamenti risolti, sta in una cartella di applicazioni?
  static Future<bool> inCartellaApplicazioni(String percorso,
      {Map<String, String>? ambiente}) async {
    final vero = await _risolto(percorso);
    if (vero == null) return false;
    for (final c in AppScanner.cartelleDa(ambiente ?? Platform.environment)) {
      final cartella = await _risolto(c) ?? c;
      if (vero.startsWith('$cartella/')) return true;
    }
    return false;
  }

  /// `null` se il `.desktop` si può lanciare senza chiedere; altrimenti il
  /// motivo, in una frase da mostrare a chi ha fatto doppio clic.
  static Future<String?> percheNo(String percorso,
      {Map<String, String>? ambiente}) async {
    if (await inCartellaApplicazioni(percorso, ambiente: ambiente)) {
      return null;
    }
    final vero = await _risolto(percorso);
    if (vero == null) return 'Il lanciatore «$percorso» non c\'è.';
    try {
      final modo = (await File(vero).stat()).mode;
      if (modo & 0x49 != 0) return null; // 0o111: qualcuno può eseguirlo
    } catch (_) {
      return 'Non riesco a leggere il lanciatore «$percorso».';
    }
    final nome = percorso.split('/').last;
    return 'Non lancio «$nome»: è un lanciatore fuori dalle cartelle delle '
        'applicazioni e non è segnato come eseguibile. Può venire da '
        'Internet e mostrare un nome falso. Se ti fidi, rendilo eseguibile '
        'e riprova.';
  }

  static Future<String?> _risolto(String p) async {
    try {
      return await File(p).resolveSymbolicLinks();
    } catch (_) {
      return null;
    }
  }
}

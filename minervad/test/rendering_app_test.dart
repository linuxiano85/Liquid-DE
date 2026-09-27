// Chi disegna col processore e chi chiede la scheda video.
//
// ── Il difetto che questa prova esiste per non far tornare ────────────────
//
// Le nostre app girano con `QT_QUICK_BACKEND=software`: è una scelta
// misurata che vale una quarantina di MB per finestra e un avvio più rapido,
// e `scripts/minerva-ambiente-app` la spiega app per app coi numeri.
//
// Ma col renderer software `VideoOutput` di Qt Multimedia **non disegna
// niente**. Non un errore, non un riquadro nero: l'audio parte, il tempo
// scorre, e l'immagine semplicemente non c'è.
//
// Costo reale: Minerva Media — che è un lettore audio E video — per settimane
// ha mostrato di sé solo la metà musicale, con lo spettro animato e la
// scaletta di mp3. Giacomo l'ha detto senza sapere perché, il 4 settembre
// 2026: «i file video li apre minerva media che è un lettore musicale». Non
// lo sembrava: non poteva essere altro.
//
// Nessuna prova poteva prenderlo — non è un errore, è un'assenza — e nemmeno
// questa lo prende davvero. Quello che questa fa è sorvegliare la RIGA che
// l'ha riparato: se un domani sparisce da `minerva-media`, o se l'interruttore
// smette di essere onorato in `minerva-ambiente-app`, qui diventa rosso.
import 'dart:io';

import 'package:test/test.dart';
import 'codice_vivo.dart';

void main() {
  final radice = Directory.current.parent.path;
  String leggi(String s) => File('$radice/$s').codiceVivo();

  test('minerva-media chiede la scheda video, e prima di includere l\'ambiente',
      () {
    final t = leggi('scripts/minerva-media');
    expect(t, contains('MINERVA_APP_GPU=1'),
        reason: 'senza questa riga Minerva Media torna a suonare i video '
            'senza mostrarli');
    // L'ordine conta: l'interruttore va letto QUANDO si include l'ambiente,
    // non dopo. Metterlo sotto non dà errore e non fa niente.
    expect(t.indexOf('MINERVA_APP_GPU=1'),
        lessThan(t.indexOf('scripts/minerva-ambiente-app')),
        reason: 'MINERVA_APP_GPU va impostata PRIMA di includere '
            'minerva-ambiente-app, o non la legge nessuno');
  });

  test('l\'ambiente onora l\'interruttore invece di ignorarlo', () {
    final t = leggi('scripts/minerva-ambiente-app');
    expect(t, contains('MINERVA_APP_GPU'));
    expect(t, contains('unset QT_QUICK_BACKEND'),
        reason: 'non basta non impostarla: se arriva dall\'ambiente di chi '
            'lancia va tolta');
  });

  test('le altre app restano sul processore: è lì che stanno i 40 MB', () {
    // Se un giorno qualcuno mettesse la GPU dappertutto «per sicurezza», la
    // scrivania tornerebbe a pesare quello che pesava. Le app senza video
    // devono restare come sono.
    for (final app in const [
      'minerva-files',
      'minerva-settings',
      'minerva-editor',
      'minerva-calcolatrice',
      'minerva-monitor',
      'minerva-viewer',
      'minerva-terminale',
    ]) {
      final f = File('$radice/scripts/$app');
      if (!f.existsSync()) continue;
      expect(f.codiceVivo(), isNot(contains('MINERVA_APP_GPU=1')),
          reason: '$app non mostra video: la scheda video le costerebbe una '
              'quarantina di MB per niente');
    }
  });
}

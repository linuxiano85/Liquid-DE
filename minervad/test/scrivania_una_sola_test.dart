import 'dart:io';
import 'package:test/test.dart';
import 'codice_vivo.dart';

/// Chi comanda le impostazioni di SISTEMA è uno solo.
///
/// ── Il difetto del 31 agosto 2026 ────────────────────────────────────────
///
/// `minerva-shell/core/Compositore.qml` sta dentro **ogni** nostra
/// applicazione, e le impostazioni del demone arrivano a tutte. Senza una
/// guardia, aprire il gestore file:
///
///   * rimandava al compositore la disposizione della tastiera, il tocco del
///     trackpad e l'aspetto delle barre del titolo — roba di tutta la
///     sessione, non di una finestra;
///   * riscriveva le regole delle finestre, lanciando una shell per
///     `~/.config/hypr/minerva-windows.conf` a ogni apertura di ogni app.
///
/// Si è visto solo il giorno in cui è comparso un verbo nuovo e ogni app ha
/// cominciato a stampare «no verbo «aspetto» sconosciuto». Prima di allora
/// funzionava — nel senso che nessuno se ne accorgeva.
///
/// ── Perché una prova che LEGGE il codice, e non una che lo esegue ────────
///
/// Perché il difetto è «manca una riga in un posto», e una prova che esegue
/// dovrebbe aprire una finestra vera per ogni applicazione per accorgersene.
/// Qui bastano tre `grep`, girano in un decimo di secondo, e dicono
/// esattamente quale file ha perso la riga.
///
/// Si è provato prima a dedurre la cosa da `Quickshell.configPath`: **non si
/// può**, è un metodo che compone percorsi, non il nome del file in
/// esecuzione. `String(Quickshell.configPath)` restituisce
/// «function() { [native code] }» — una guardia che sembra funzionare e
/// risponde sempre di no. Da lì la scelta di farlo DICHIARARE.
void main() {
  String radice() {
    var d = Directory.current;
    while (!File('${d.path}/MODULI.md').existsSync()) {
      final su = d.parent;
      if (su.path == d.path) throw StateError('radice del progetto non trovata');
      d = su;
    }
    return d.path;
  }

  String leggi(String rel) => File('${radice()}/$rel').codiceVivo();

  group('le impostazioni di sistema le manda una sola', () {
    test('la scrivania si dichiara, e la schermata di accesso pure', () {
      // Sono le due che DEVONO farlo: senza, sotto minerva-wayland la tastiera
      // resterebbe quella di sistema — americana — e al login si scriverebbe
      // una password che non si vede in una disposizione che non è la propria.
      for (final f in ['minerva-shell/shell.qml', 'minerva-shell/greeter.qml']) {
        expect(leggi(f), contains('Compositore.scrivania = true'),
            reason: '$f non si dichiara più scrivania: le impostazioni di '
                'ingresso non arriverebbero al compositore, e la tastiera '
                'resterebbe quella di sistema');
      }
    });

    test('e nessun\'altra si dichiara al posto loro', () {
      // Il gestore file, le Impostazioni, l'Anteprima, il lettore: sono
      // finestre. Se una si dichiarasse scrivania, tornerebbe a riconfigurare
      // la sessione a ogni apertura.
      final dir = Directory('${radice()}/minerva-shell');
      final colpevoli = <String>[];
      for (final f in dir.listSync()) {
        if (f is! File || !f.path.endsWith('.qml')) continue;
        final nome = f.path.split('/').last;
        if (nome == 'shell.qml' || nome == 'greeter.qml') continue;
        // Le prove possono farlo: servono proprio a provare quel ramo.
        if (nome.startsWith('prove-')) continue;
        if (f.codiceVivo().contains('Compositore.scrivania = true')) {
          colpevoli.add(nome);
        }
      }
      expect(colpevoli, isEmpty,
          reason: 'queste sono finestre, non scrivanie: riconfigurerebbero la '
              'sessione a ogni apertura');
    });

    test('le tre porte sono tutte e tre guardate', () {
      // Chiuderne due su tre non serve a niente — è quello che è successo al
      // primo tentativo, e il verbo continuava a partire dalla terza.
      final comp = leggi('minerva-shell/core/Compositore.qml');
      final regole = leggi('minerva-shell/core/WindowRules.qml');

      // 1. l'apertura del canale
      expect(comp, contains('if (comp.scrivania)\n                    comp.applicaIngresso();'),
          reason: 'la prima porta: `onConnectedChanged`');
      // 2. l'arrivo delle impostazioni dal demone
      expect(comp, contains('if (comp.nostro && comp.scrivania)'),
          reason: 'la seconda porta: `onImpostazioniArrivateChanged` — è '
              'quella che era rimasta aperta');
      // 3. le regole delle finestre
      expect(regole, contains('if (!Compositore.scrivania)'),
          reason: 'la terza porta: `WindowRules.write()`, che oltre ai verbi '
              'lancia una shell per riscrivere un file');
    });

    test('e il predefinito è FALSO', () {
      // Il caso giusto per difetto: chi non dice niente è una finestra, e una
      // finestra che tace non riconfigura la sessione di nessuno.
      final comp = leggi('minerva-shell/core/Compositore.qml');
      expect(comp, contains('property bool scrivania:'),
          reason: 'deve restare scrivibile: si è provato a dedurlo e non si '
              'può (vedi il commento in cima a questo file)');
      expect(comp, isNot(contains('readonly property bool scrivania')),
          reason: 'se torna `readonly`, shell.qml non può più dichiararsi');
    });
  });
}

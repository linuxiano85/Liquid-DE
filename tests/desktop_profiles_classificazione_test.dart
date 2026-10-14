// Ogni impostazione deve dire se appartiene al PRESET o è COMUNE.
//
//     dart run tests/desktop_profiles_classificazione_test.dart
//
// ── Perché esiste ────────────────────────────────────────────────────────
//
// I preset (Liquid, Minerva, Mac, Windows, Libero) ricordano ciascuno le
// proprie scelte: `DesktopProfiles` in `minervad/lib/core/desktop_profiles.dart`
// decide QUALI impostazioni sono del preset con un elenco di gruppi e di
// chiavi. Un'impostazione estetica nuova, dimenticata in quell'elenco,
// diventerebbe comune a tutti i preset in silenzio: la si cambia in Liquid e
// la si ritrova cambiata in Windows (revisione di Claude, 11 ottobre 2026).
//
// Questa prova percorre TUTTE le impostazioni di serie: ognuna deve essere o
// del preset (`DesktopProfiles.scoped`) o in questo elenco di comuni. Una
// chiave nuova che non è né l'una né l'altra fa fallire la prova, e il
// messaggio dice cosa fare.
import '../minervad/lib/core/settings_api.dart';
import '../minervad/lib/core/desktop_profiles.dart';

/// Le impostazioni che valgono per tutti i preset: hardware, lingua,
/// accesso, energia, volume, preferenze di lavoro che non sono «aspetto».
const comuni = <String>{
  'accessibility.zoom',
  'audio.allowOverdrive',
  'audio.feedbackSounds',
  'audio.feedbackVolume',
  'desktop.menuUsed',
  'display.nightLight',
  'display.nightLightAuto',
  'display.nightLightFrom',
  'display.nightLightTemp',
  'display.nightLightTo',
  'editor.piega',
  'files.confermaCestino',
  'files.pinned',
  'files.tieniAcceso',
  'general.language',
  'greeter.auroraStrength',
  'greeter.autologin',
  'greeter.background',
  'greeter.blur',
  'greeter.clock24',
  'greeter.lato',
  'greeter.meteo',
  'greeter.saluto',
  'greeter.scrim',
  'greeter.session',
  'greeter.showClock',
  'greeter.stato',
  'greeter.user',
  'greeter.wallpaper',
  'input.controllerAutomatico',
  'input.controllerPad',
  'input.controllerTipo',
  'input.disableWhileTyping',
  'input.layout',
  'input.naturalScroll',
  'input.repeatDelay',
  'input.repeatRate',
  'input.sensitivity',
  'input.tapToClick',
  'input.touchpadOn',
  'launcher.defaultTerminal',
  'media.casuale',
  'media.muto',
  'media.radioPreferite',
  'notizie.attive',
  'notizie.fontiSpente',
  'notizie.interessi',
  'media.ripeti',
  'media.volume',
  'memoria.respiro',
  'notifications.bloccoMostra',
  'notifications.doNotDisturb',
  'power.dimAfter',
  'power.lidAction',
  'power.lockAfter',
  'power.screenOffAfter',
  'power.suspendAfter',
  'preload.anteprima',
  'preload.attivita',
  'preload.calcolatrice',
  'preload.editor',
  'preload.impostazioni',
  'preload.minuti',
  'preload.terminale',
  'settings.lastSection',
  'settings.schedeAperte',
  'shell.hotReload',
  'stile.attuale',
  'stile.libero',
  'stile.profili',
  'terminale.campanello',
  'terminale.scrollback',
  'weather.enabled',
  'weather.lat',
  'weather.lon',
  'weather.name',
};

void main() {
  final profili = DesktopProfiles(SettingsApi.defaultSettings(), (_, __) => true);
  final senzaCasa = <String>[];
  final doppie = <String>[];
  var viste = 0;
  void percorri(Map valori, String prefisso) {
    valori.forEach((k, v) {
      final percorso = prefisso.isEmpty ? '$k' : '$prefisso.$k';
      if (v is Map && v.isNotEmpty) {
        percorri(v, percorso);
        return;
      }
      viste++;
      final delPreset = profili.scoped(percorso);
      final comune = comuni.contains(percorso);
      if (!delPreset && !comune) senzaCasa.add(percorso);
      if (delPreset && comune) doppie.add(percorso);
    });
  }
  percorri(SettingsApi.defaultSettings(), '');
  final inventate = comuni.where((c) => !_esiste(SettingsApi.defaultSettings(), c)).toList();

  var errori = 0;
  if (senzaCasa.isNotEmpty) {
    errori++;
    print('Impostazioni senza casa: ${senzaCasa.join(', ')}');
    print('  Se è «aspetto», aggiungila a DesktopProfiles.groups o .individual;');
    print('  se vale per tutti i preset, aggiungila a `comuni` in questa prova.');
  }
  if (doppie.isNotEmpty) {
    errori++;
    print('Impostazioni sia del preset sia comuni: ${doppie.join(', ')}');
  }
  if (inventate.isNotEmpty) {
    errori++;
    print('In `comuni` ci sono chiavi che non esistono più: ${inventate.join(', ')}');
  }
  if (errori > 0) {
    throw StateError('classificazione dei preset: $errori problemi');
  }
  print('classificazione dei preset: $viste impostazioni, ${comuni.length} comuni, tutte con una casa');
}

bool _esiste(Map albero, String percorso) {
  dynamic nodo = albero;
  for (final parte in percorso.split('.')) {
    if (nodo is! Map || !nodo.containsKey(parte)) return false;
    nodo = nodo[parte];
  }
  return true;
}

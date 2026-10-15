import 'dart:io';

/// null significa che il kernel non espone questa informazione. Una batteria
/// che non sta caricando può essere collegata alla rete con carica limitata:
/// status=Not charging non basta per scegliere la politica a batteria.
bool? leggiAlimentazioneEsterna({String cartella = '/sys/class/power_supply'}) {
  var osservata = false;
  try {
    for (final voce in Directory(cartella).listSync()) {
      try {
        final tipo = File('${voce.path}/type').readAsStringSync().trim().toLowerCase();
        if (tipo != 'mains' && tipo != 'wireless' && tipo != 'apple_brick_id' &&
            tipo != 'usb' && !tipo.startsWith('usb_')) {
          continue;
        }
        final online = File('${voce.path}/online').readAsStringSync().trim();
        if (online == '1') return true;
        if (online == '0') osservata = true;
      } on FileSystemException {
        // Hotplug e file facoltativi non devono interrompere gli altri dati.
      }
    }
  } on FileSystemException {
    return null;
  }
  return osservata ? false : null;
}

// Prove per `LuoghiRemoti`: cartelle di rete e telefoni nel gestore file.
//
//     dart run tests/luoghi_remoti_test.dart
//
// Due parti.
//
// 1. Un `gio` finto (uno script) fa le stesse domande di quello vero: utente,
//    dominio, password, «ti fidi di questo server?». Così si prova il dialogo
//    senza un server Samba o SSH.
// 2. gvfs vero, col suo protocollo di prova `localtest`, su un bus D-Bus
//    privato e una cartella runtime privata: si collega, compare
//    nell'elenco con la sua cartella, si sfoglia, si scollega. La sessione di
//    chi lancia la prova non vede niente.
import 'dart:convert';
import 'dart:io';
import '../minervad/lib/services/luoghi_remoti.dart';

var prove = 0;

void check(bool value, String message) {
  if (!value) throw StateError(message);
  prove++;
}

const gioFinto = r'''#!/bin/bash
echo "$*" >> "$REGISTRO"
if [ "$1" = info ]; then
  # Un luogo che non si è collegato non ha una cartella.
  case "$3" in ftp://rifiuta*) echo "gio: $3: not mounted" >&2; exit 1 ;; esac
  echo "uri: $3"
  echo "local path: /run/user/1000/gvfs/finto"
  exit 0
fi
if [ "$1 $2" = "mount -l" ]; then
  cat "$ELENCO"
  exit 0
fi
if [ "$1 $2" = "mount -u" ]; then
  exit 0
fi
uri="${@: -1}"
case "$uri" in
  smb://aperto/*|mtp://*|gphoto2://*) exit 0 ;;
  smb://chiuso/*)
    echo "Authentication Required"
    echo "Enter user and password for share “x” on “chiuso”:"
    printf "User [utente]: "; read u
    printf "Domain [WORKGROUP]: "; read d
    printf "Password: "; read p
    echo "$u|$d|$p" >> "$RISPOSTE"
    if [ "$p" = giusta ]; then exit 0; fi
    echo "Authentication Required"
    printf "Password: "; read p
    exit 2 ;;
  sftp://nuovo*)
    echo "The identity of the remote computer (nuovo) is unknown."
    echo "This happens when you log in to a computer the first time."
    echo "[1] Log In Anyway"
    echo "[2] Cancel Login"
    printf "Choice: "; read c
    if [ "$c" = 1 ]; then exit 0; fi
    echo "gio: sftp://nuovo/: Login dialog cancelled" >&2
    exit 2 ;;
  ftp://rifiuta*)
    echo "gio: ftp://rifiuta/: Connection refused" >&2
    exit 2 ;;
esac
exit 3
''';

const elencoFinto = '''Drive(0): HS-SSD 1024G
  Type: GProxyDrive (GProxyVolumeMonitorUDisks2)
Volume(0): Chiavetta
  Type: GProxyVolume (GProxyVolumeMonitorUDisks2)
  Mount(0): Chiavetta -> file:///run/media/tizio/Chiavetta
    Type: GProxyMount (GProxyVolumeMonitorUDisks2)
Volume(1): Pixel 8
  Type: GProxyVolume (GProxyVolumeMonitorMTP)
  activation_root=mtp://Google_Pixel_8_123/
Volume(2): Galaxy S24
  Type: GProxyVolume (GProxyVolumeMonitorMTP)
  activation_root=mtp://SAMSUNG_Android_456/
  Mount(1): Galaxy S24 -> mtp://SAMSUNG_Android_456/
    Type: GProxyMount (GProxyVolumeMonitorMTP)
Mount(2): condivisa su nas -> smb://nas/condivisa/
  Type: GDaemonMount
''';

Future<void> conGioFinto(Directory base) async {
  final gio = File('${base.path}/gio');
  await gio.writeAsString(gioFinto);
  await Process.run('chmod', ['+x', gio.path]);
  final registro = '${base.path}/registro';
  final risposte = '${base.path}/risposte';
  final elenco = File('${base.path}/elenco')..writeAsStringSync(elencoFinto);
  final protocolli = Directory('${base.path}/mounts')..createSync();
  for (final p in ['smb', 'sftp', 'ftp']) {
    File('${protocolli.path}/$p.mount').writeAsStringSync('');
  }
  final l = LuoghiRemoti(
    gio: gio.path,
    cartellaProtocolli: protocolli.path,
    ambienteInPiu: {'REGISTRO': registro, 'RISPOSTE': risposte, 'ELENCO': elenco.path},
  );

  // ── Indirizzi ──
  check(l.normalizza(r'\\nas\foto') == 'smb://nas/foto', 'indirizzo alla Windows');
  check(l.normalizza('nas/foto') == 'smb://nas/foto', 'senza protocollo è Samba');
  check(l.normalizza('sftp://io@server:2222/casa') != null, 'sftp con utente e porta');
  check(l.normalizza('file:///etc') == null, 'file:// rifiutato');
  check(l.normalizza('trash:///') == null, 'trash:// rifiutato');
  check(l.normalizza('--help') == null, 'un\'opzione non passa per indirizzo');
  check(l.normalizza('smb://nas/a b') == null, 'spazi rifiutati');
  check(l.normalizza('smb:///solo-cartella') == null, 'samba senza server rifiutato');
  check(l.normalizza('mtp://Pixel/') != null, 'un telefono non ha un server');
  for (final schema in ['mtp', 'gphoto2']) {
    final usb = '$schema://[usb:002,015]/';
    check(l.normalizza(usb) == usb, '$schema accetta la radice USB di GVfs');
    check(LuoghiRemoti.tipoDi(usb) == 'telefono', '$schema USB classificato come dispositivo');
    check(l.normalizza('$schema://[usb:000,015]/') == null, '$schema rifiuta bus zero');
    check(l.normalizza('$schema://[usb:002,999]/') == null, '$schema rifiuta indirizzo dispositivo impossibile');
    check(l.normalizza('$schema://[usb:002,015]/;touch') == null, '$schema non ammette suffissi arbitrari');
  }

  // ── Elenco ──
  final e = await l.elenco();
  final luoghi = (e['luoghi'] as List).cast<Map>();
  check(luoghi.length == 3, 'due collegati e un telefono da aprire: $luoghi');
  check(!luoghi.any((x) => '${x['uri']}'.startsWith('file:')), 'le chiavette restano fra i dischi');
  final pixel = luoghi.firstWhere((x) => x['nome'] == 'Pixel 8');
  check(pixel['montato'] == false && pixel['tipo'] == 'telefono', 'il telefono non aperto: $pixel');
  final galaxy = luoghi.where((x) => x['nome'] == 'Galaxy S24').toList();
  check(galaxy.length == 1 && galaxy.first['montato'] == true, 'il telefono aperto compare una volta: $galaxy');
  final nas = luoghi.firstWhere((x) => x['nome'] == 'condivisa su nas');
  check(nas['tipo'] == 'condivisa' && nas['percorso'] == '/run/user/1000/gvfs/finto', 'la cartella condivisa: $nas');
  check((e['mancano'] as List).contains('gvfs-mtp')
      && (e['mancano'] as List).contains('gvfs-gphoto2')
      && !(e['mancano'] as List).contains('gvfs-smb'),
      'si dice che per i telefoni manca gvfs-mtp: ${e['mancano']}');
  check((e['protocolli'] as List).contains('smb'), 'capacità installate esposte');


  // ── Collegare ──
  var r = await l.collega('smb://aperto/foto');
  check(r['ok'] == true && r['percorso'] == '/run/user/1000/gvfs/finto', 'cartella aperta a tutti: $r');

  r = await l.collega('smb://chiuso/x');
  check(r['ok'] == false && r['serveAccesso'] == true && r['dominio'] == true,
      'senza credenziali si ferma e chiede l\'accesso, col dominio per Samba: $r');
  check(!File(risposte).existsSync(), 'senza credenziali non si risponde niente');

  r = await l.collega('smb://chiuso/x', utente: 'mario', password: 'giusta');
  check(r['ok'] == true, 'con la password giusta si collega: $r');
  check(File(risposte).readAsLinesSync().last == 'mario||giusta',
      'utente e password arrivano dallo stdin, il dominio resta quello proposto');

  r = await l.collega('smb://chiuso/x', password: 'sbagliata');
  check(r['ok'] == false && r['sbagliate'] == true && r['error'] == 'Utente o password sbagliati.',
      'password sbagliata: si dice, non si riprova all\'infinito: $r');
  check(File(risposte).readAsLinesSync().last == '||sbagliata',
      'utente vuoto: si accetta quello proposto');

  final argomenti = File(registro).readAsStringSync();
  check(!argomenti.contains('giusta') && !argomenti.contains('sbagliata'),
      'la password non compare mai fra gli argomenti');

  r = await l.collega('sftp://nuovo');
  check(r['ok'] == false && '${r['domanda']}'.contains('is unknown') && !'${r['domanda']}'.contains('[1]'),
      'server sconosciuto: si ferma e mostra la domanda: $r');
  r = await l.collega('sftp://nuovo', fidati: true);
  check(r['ok'] == true, 'dopo il sì si collega: $r');

  r = await l.collega('ftp://rifiuta');
  check(r['ok'] == false && r['error'] == 'Connection refused', 'l\'errore di gio, senza il prefisso: $r');

  r = await l.collega('mtp://Pixel/');
  check(r['ok'] == false && r['manca'] == 'gvfs-mtp', 'senza gvfs-mtp si dice cosa installare: $r');

  File('${protocolli.path}/mtp.mount').writeAsStringSync('');
  File('${protocolli.path}/gphoto2.mount').writeAsStringSync('');
  final dopoBackend = await l.elenco();
  check(!(dopoBackend['mancano'] as List).contains('gvfs-mtp')
      && !(dopoBackend['mancano'] as List).contains('gvfs-gphoto2'),
      'MTP e PTP non risultano mancanti dopo l\'installazione');
  check((await l.scollega('mtp://[usb:002,015]/'))['ok'] == true,
      'scollegamento della radice USB ammesso');
  for (final schema in ['mtp', 'gphoto2']) {
    check((await l.collega('$schema://[usb:002,015]/'))['ok'] == true,
        '$schema collega la radice USB senza trattarla come IPv6');
  }

  r = await l.scollega('smb://nas/condivisa/');
  check(r['ok'] == true, 'scollega');
  r = await l.scollega('file:///');
  check(r['ok'] == false, 'non si smonta un file://');
}

/// gvfs vero, su un bus privato.
Future<void> conGvfsVero(Directory base) async {
  if (!File('/usr/share/gvfs/mounts/localtest.mount').existsSync()) {
    print('(gvfs vero saltato: manca localtest.mount)');
    return;
  }
  final runtime = Directory('${base.path}/runtime')..createSync();
  await Process.run('chmod', ['700', runtime.path]);
  // Il bus lancia gvfsd col SUO ambiente: senza la cartella runtime privata,
  // gvfsd proverebbe a usare quella vera della sessione.
  final bus = await Process.start('dbus-daemon', ['--session', '--nofork', '--print-address=1'],
      environment: {'XDG_RUNTIME_DIR': runtime.path});
  final indirizzo = await bus.stdout.transform(utf8.decoder).transform(const LineSplitter()).first;
  final ambiente = {'DBUS_SESSION_BUS_ADDRESS': indirizzo, 'XDG_RUNTIME_DIR': runtime.path};
  try {
    final l = LuoghiRemoti(schemiInPiu: {'localtest'}, ambienteInPiu: ambiente);
    var r = await l.collega('localtest:///');
    check(r['ok'] == true, 'gvfs vero: collegato $r');
    final percorso = '${r['percorso']}';
    check(percorso.startsWith(runtime.path), 'la cartella è in quella runtime privata: $percorso');
    check(Directory(percorso).listSync().isNotEmpty, 'si sfoglia come una cartella normale');

    final e = await l.elenco();
    final voce = (e['luoghi'] as List).cast<Map>().where((x) => x['uri'] == 'localtest:///').toList();
    check(voce.length == 1 && voce.first['percorso'] == percorso, 'gvfs vero: compare nell\'elenco $e');

    r = await l.collega('localtest:///');
    check(r['ok'] == true, 'collegarlo due volte non è un errore: $r');

    r = await l.scollega('localtest:///');
    check(r['ok'] == true, 'gvfs vero: scollegato $r');
    final dopo = await l.elenco();
    check(!(dopo['luoghi'] as List).cast<Map>().any((x) => x['uri'] == 'localtest:///'),
        'e non c\'è più: $dopo');
  } finally {
    // gvfsd e gvfsd-fuse se ne vanno col loro bus; se la cartella FUSE è
    // rimasta montata, si stacca a mano.
    bus.kill();
    await bus.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await Process.run('fusermount3', ['-u', '-z', '${runtime.path}/gvfs']);
  }
}

Future<void> main() async {
  final base = await Directory.systemTemp.createTemp('liquid-luoghi-');
  try {
    await conGioFinto(base);
    await conGvfsVero(base);
  } finally {
    await base.delete(recursive: true);
  }
  print('luoghi_remoti: $prove prove superate');
}

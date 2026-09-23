/// Che cos'è una fotografia, che cos'è un video, e dove NON si va a cercarli.
///
/// ── Perché le esclusioni stanno qui e non in un'opzione ────────────────────
///
/// Perché senza, la richiesta «cerca le foto nella cartella personale» dà una
/// risposta assurda. Misurato il 26 agosto 2026 sulla casa di Giacomo:
///
/// ```
///   88.982  file immagine o video in tutta la home
///   64.115  dentro Documenti/Progetti      ← risorse di programmi
///   17.303  dentro .local/share            ← temi di icone
///      826  fotografie e video veri
/// ```
///
/// Il 94% di quello che si trova frugando ovunque sono icone. Una galleria che
/// le mostrasse non sarebbe «completa»: sarebbe inservibile. Quindi ci sono due
/// elenchi, e fanno due mestieri diversi:
///
/// - [sempreEscluse] non si discute: sono posti dove i file immagine ci sono
///   per forza e non sono mai ricordi.
/// - Le esclusioni **sue** stanno nella configurazione, si aggiungono e si
///   tolgono, e servono per i casi personali — «Scaricati no» è il primo che ha
///   chiesto.
library;

/// Le code dei file che mostriamo.
///
/// Fatte apposta minuscole e col punto davanti: si confronta
/// `nome.toLowerCase()` con `endsWith`, così `FOTO.JPG` e `foto.jpg` sono la
/// stessa cosa.
const Set<String> codeFoto = {
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.tif', '.tiff',
  '.heic', '.heif', '.avif', '.ico', '.svg',
  // Grezzi di macchina fotografica: li elenchiamo perché esistono nella sua
  // libreria, ma Qt non li apre — la miniatura dovrà farla il demone.
  '.dng', '.cr2', '.cr3', '.nef', '.arw', '.raf', '.orf', '.rw2', '.pef',
};

const Set<String> codeVideo = {
  '.mp4', '.mov', '.mkv', '.webm', '.3gp', '.m4v', '.avi',
  '.mpg', '.mpeg', '.wmv', '.flv', '.ts', '.mts',
};

/// I grezzi, che nessun programma di disegno apre da solo.
const Set<String> codeGrezze = {
  '.dng', '.cr2', '.cr3', '.nef', '.arw', '.raf', '.orf', '.rw2', '.pef',
};

/// Quelle che Qt sa aprire da sé, senza passare dal demone.
const Set<String> codeChePuoDisegnare = {
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.svg', '.ico',
};

String codaDi(String percorso) {
  final punto = percorso.lastIndexOf('.');
  final barra = percorso.lastIndexOf('/');
  if (punto <= barra || punto < 0) return '';
  return percorso.substring(punto).toLowerCase();
}

bool eFoto(String percorso) => codeFoto.contains(codaDi(percorso));
bool eVideo(String percorso) => codeVideo.contains(codaDi(percorso));
bool eMedia(String percorso) {
  final c = codaDi(percorso);
  return codeFoto.contains(c) || codeVideo.contains(c);
}

/// Le cartelle in cui non si entra mai, per nessun motivo.
///
/// Si confrontano col **nome** della cartella, non col percorso: una
/// `node_modules` è da saltare ovunque si trovi.
const Set<String> sempreEscluse = {
  // Roba di programmi: qui stanno le 64.115 icone.
  'node_modules', '.git', '.svn', '.hg', 'build', 'target',
  '__pycache__', '.dart_tool', '.gradle', '.pub-cache', '.cargo',
  'vendor', 'Pods', '.venv', 'venv',
  // Cache e stato: qui stanno le altre 17.303.
  '.cache', '.local', '.config', '.thumbnails', '.trash', '.Trash-1000',
  // Il cestino, che non è una galleria.
  'Trash', 'lost+found',
  // Sistemi che non sono nostri.
  '.wine', '.steam', 'Steam',
};

/// Cartelle di primo livello nella casa che di serie non si guardano.
///
/// Non sono vietate: sono **spente all'inizio**. `Scaricati` è quella che
/// Giacomo ha nominato per primo — e infatti le sue foto ci sono dentro, quindi
/// il programma gliela propone e lui decide, invece di deciderlo noi.
const Set<String> spenteDiSerie = {
  'Documenti/Progetti',
  'Android',
  'flutter',
  'Modelli',
  'Pubblici',
};

/// Si entra in questa cartella?
///
/// [nome] è solo il nome, non il percorso.
bool siEntra(String nome, {bool ancheNascoste = false}) {
  if (nome.isEmpty) return false;
  if (sempreEscluse.contains(nome)) return false;
  if (!ancheNascoste && nome.startsWith('.')) return false;
  return true;
}

pragma Singleton
import QtQuick
import QtCore

// Ordine dalla pagina Cartelle della VM Windows. QStandardPaths legge i
// percorsi XDG: non presumiamo che Documenti si chiami così o stia nella home.
QtObject {
    readonly property var entries: [
        { id: "settings", icon: "settings", it: "Impostazioni", en: "Settings" },
        { id: "files", icon: "folder", it: "Esplora file", en: "File Explorer" },
        { id: "documents", icon: "document", it: "Documenti", en: "Documents" },
        { id: "downloads", icon: "download", it: "Download", en: "Downloads" },
        { id: "music", icon: "music", it: "Musica", en: "Music" },
        { id: "pictures", icon: "immagine", it: "Immagini", en: "Pictures" },
        { id: "videos", icon: "video", it: "Video", en: "Videos" },
        // Non abbiamo ancora una vista delle risorse di rete nel gestore file.
        { id: "network", icon: "globe", it: "Rete", en: "Network", available: false },
        { id: "home", icon: "personalFolder", it: "Cartella personale", en: "Personal folder" }
    ]

    function pathFor(id) {
        var type;
        switch (id) {
        case "files":
        case "home":
            type = StandardPaths.HomeLocation;
            break;
        case "documents":
            type = StandardPaths.DocumentsLocation;
            break;
        case "downloads":
            type = StandardPaths.DownloadLocation;
            break;
        case "music":
            type = StandardPaths.MusicLocation;
            break;
        case "pictures":
            type = StandardPaths.PicturesLocation;
            break;
        case "videos":
            type = StandardPaths.MoviesLocation;
            break;
        default:
            return "";
        }
        var url = String(StandardPaths.writableLocation(type));
        return url.indexOf("file://") === 0 ? decodeURIComponent(url.slice(7)) : "";
    }
}

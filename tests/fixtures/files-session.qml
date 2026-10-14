import QtQuick
import Quickshell
import Quickshell.Io
import "@FILES@" as FilesUi
import "@CORE@" as Core
import "@THEME@" as Theme

ShellRoot {
    id: root

    property var managers: [main]
    property string lingua: "it"
    // Quante volte la finestra principale ha chiesto di chiudersi: qui nessuno
    // la chiude, così la prova clicca «chiudi» e continua.
    property int closeRequests: 0
    Connections {
        target: main
        function onRequestClose() {
            root.closeRequests++;
        }
    }
    Theme.LegaTema {}
    Binding {
        target: Core.Strings
        property: "requestedLanguage"
        value: root.lingua
    }
    FilesUi.FileManager {
        id: main
        title: "File prova principale"
        initialPath: Quickshell.env("TEST_FILES_ROOT")
    }
    Component {
        id: factory
        FilesUi.FileManager {
            title: "File prova secondaria"
        }
    }

    function collect(item, result, base) {
        if (!item.visible)
            return;
        if (item.objectName && item.width > 0 && item.height > 0) {
            var point = item.mapToItem(base, item.width / 2, item.height / 2);
            result[item.objectName] = {x: point.x, y: point.y, width: item.width, height: item.height,
                contentWidth: item.larghezzaVisibile === undefined ? item.width : item.larghezzaVisibile,
                text: item.text === undefined ? "" : item.text,
                enabled: item.enabled,
                color: item.color === undefined ? "" : String(item.color),
                mode: item.mode === undefined ? "" : item.mode,
                caption: item.caption === undefined ? "" : item.caption,
                supporto: item.supporto === undefined ? "" : item.supporto};
        }
        for (var child of item.children || [])
            collect(child, result, base);
    }

    function describe(manager) {
        var controls = {};
        collect(manager.contentItem, controls, manager.contentItem);
        function find(item, name) {
            if (item.objectName === name)
                return item;
            for (var child of item.children || []) {
                var match = find(child, name);
                if (match)
                    return match;
            }
            return null;
        }
        var commands = find(manager.contentItem, "filesWindowsCommands");
        if (commands && commands.menuVisible)
            collect(commands.menuContent, controls, manager.contentItem);
        var context = manager.contextMenuForTest;
        if (context.visible) {
            var menuControls = {};
            collect(context.contentItem, menuControls, context.contentItem);
            for (var name in menuControls) {
                menuControls[name].global = true;
                menuControls[name].x += context.screen ? context.screen.x : 0;
                menuControls[name].y += context.screen ? context.screen.y : 0;
                controls[name] = menuControls[name];
            }
        }
        return {
            current: manager.currentIndex,
            presentation: {windows: FilesUi.FileStyle.windows,
                accent: String(FilesUi.FileStyle.accent),
                paper: String(FilesUi.FileStyle.lettura),
                text: String(FilesUi.FileStyle.text),
                font: FilesUi.FileStyle.font},
            titleInk: String(find(manager.contentItem, "minervaWindowTitleBar").foreground),
            typing: manager.typing,
            dialogOpen: manager.dialogOpen,
            contextOpen: context.visible,
            contextScreen: context.screen ? context.screen.name : "",
            contextItems: context.items,
            tabbed: manager.tabbed,
            count: manager.tabs.count,
            pending: manager.apertureRemote,
            controls: controls,
            panes: manager.panes.map(function(pane) {
                return {
                    id: pane.paneId, path: pane.path, visible: pane.visible,
                    enabled: pane.enabled, focused: pane.focused,
                    width: pane.width, selection: pane.selection,
                    history: pane.history, error: pane.error,
                    viewMode: pane.viewMode, sort: pane.sortBy, descending: pane.sortDesc,
                    hidden: pane.showHidden,
                    filter: pane.filter, searching: pane.cercando, searchDone: pane.ricercaFinita,
                    shown: pane.shown.map(function(entry) { return entry.path; }),
                    entries: pane.entries.map(function(entry) { return entry.name; })
                };
            })
        };
    }

    IpcHandler {
        target: "files-test"
        function status(): string {
            return JSON.stringify({connected: Core.Ipc.connected,
                clipboardText: Quickshell.clipboardText,
                closeRequests: root.closeRequests,
                fileClipboard: FilesUi.Files.clipboard,
                managers: root.managers.map(root.describe), settings: Core.Ipc.settings});
        }
        function selectFile(path: string): void {
            main.current.selection = path === "" ? [] : [path];
            main.current.focusContents();
        }
        // Più percorsi separati da «|»: `qs ipc` spezza gli argomenti anche
        // sulle virgole, quindi niente JSON qui.
        function selectFiles(paths: string): void {
            main.current.selection = paths.split("|");
            main.current.focusContents();
        }
        // Una selezione dopo l'altra, come scorrendo con le frecce.
        function selectInTurn(paths: string): void {
            for (var path of paths.split("|"))
                main.current.selection = [path];
        }
        function clipboard(text: string): void {
            Quickshell.clipboardText = text;
        }
        function add(path: string): void {
            main.addTab(path);
        }
        function select(index: int): void {
            main.focusIndex(index);
        }
        function close(index: int): void {
            main.closeTab(index);
        }
        function move(from: int, to: int): void {
            main.moveTab(from, to);
        }
        function preference(path: string, json: string): void {
            Core.Ipc.setSetting(path, JSON.parse(json).value);
        }
        function another(path: string): void {
            var manager = factory.createObject(root, {initialPath: path});
            root.managers = root.managers.concat([manager]);
        }
        function lateReply(id: string, path: string): void {
            Core.Ipc.fileListingReceived({pane: id, path: path, entries: [
                {name: "RISPOSTA-OBSOLETA", path: path + "/RISPOSTA-OBSOLETA", isDir: false, size: 1}
            ]});
        }
        function phoneState(json: string): void {
            // Anche al demone di prova, che lo ripete alla prossima domanda
            // periodica invece di cancellarlo.
            Core.Ipc.send({ "action": "fixture_remoti", "stato": JSON.parse(json) });
            FilesUi.Files.remoti = JSON.parse(json).luoghi || [];
            FilesUi.Files.remotiMancano = JSON.parse(json).mancano || [];
            FilesUi.Files.remotiNoti = true;
            FilesUi.Files.remotiErrore = JSON.parse(json).error || "";
        }
        function language(lang: string): void {
            root.lingua = lang;
        }
        function connectRemote(uri: string): void {
            main.apriRemoto({uri: uri, montato: false});
        }
        function connectReply(request: string, path: string): void {
            Core.Ipc.connessoReceived({richiesta: request, ok: true, percorso: path});
        }
    }
}

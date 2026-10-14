import QtQuick
import Quickshell

// Le voci non espongono children: ogni livello richiede un QsMenuOpener.
// Il modello vive soltanto mentre si consulta il menu, mai nella tray inattiva.
Item {
    id: tree
    property var source: null
    property string prefix: ""
    property int depth: 0
    property int revision: 0
    visible: false
    readonly property var entries: opener.children ? opener.children.values : []
    readonly property var items: {
        var revision = tree.revision;
        var result = [];
        var count = rows.count;
        for (var i = 0; i < count; i++) {
            var row = rows.itemAt(i);
            if (row)
                result.push(row.descriptor);
        }
        return result;
    }

    function find(action) {
        for (var i = 0; i < rows.count; i++) {
            var row = rows.itemAt(i);
            if (!row)
                continue;
            if (row.action === action)
                return row.modelData;
            var child = row.childTree;
            if (child) {
                var result = child.find(action);
                if (result)
                    return result;
            }
        }
        return null;
    }

    QsMenuOpener {
        id: opener
        menu: tree.source
    }
    Repeater {
        id: rows
        onItemAdded: tree.revision++
        onItemRemoved: tree.revision++
        model: tree.entries
        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property string action: tree.prefix + "/" + index
            readonly property var childTree: childLoader.item
            readonly property var descriptor: {
                var entry = modelData;
                if (entry.isSeparator)
                    return { separator: true };
                var value = {
                    // DBusMenu usa & per le mnemoniche e && per una & reale.
                    label: String(entry.text || "").replace(/&&/g, "\u0001").replace(/&/g, "").replace(/\u0001/g, "&"),
                    action: action,
                    enabled: entry.enabled !== false,
                    iconUrl: entry.icon || "",
                    checkable: entry.buttonType !== QsMenuButtonType.None,
                    radio: entry.buttonType === QsMenuButtonType.RadioButton,
                    checked: entry.checkState === Qt.Checked,
                    mixed: entry.checkState === Qt.PartiallyChecked
                };
                if (entry.hasChildren) {
                    value.children = childTree ? childTree.items : [];
                    // Non mostriamo un sottomenu vuoto mentre D-Bus risponde.
                    if (!value.children.length)
                        value.children = [{ label: Style.label("Caricamento…", "Loading…"), enabled: false }];
                    if (tree.depth >= 6)
                        value.enabled = false;
                }
                return value;
            }
            Loader {
                id: childLoader
                // Il Loader evita una definizione QML ricorsiva immediata.
                active: row.modelData.hasChildren && tree.depth < 6
                source: active ? Qt.resolvedUrl("TrayMenuModel.qml") : ""
                onLoaded: {
                    item.depth = tree.depth + 1;
                    item.prefix = row.action;
                    item.source = row.modelData;
                }
            }
        }
    }
}

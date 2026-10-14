import QtQuick

// Le schede devono sopravvivere ai cambi di titolo e di focus. Sostituire
// un array in Repeater distruggeva la MouseArea fra pressione e rilascio,
// rendendo impossibile ripristinare terminali con titoli dinamici.
ListModel {
    id: root

    function update(windows) {
        // L'ordine delle anteprime resta quello di apertura: attivare una
        // finestra non deve spostare sotto il mouse la scheda di un'altra.
        var sorted = windows.slice().sort(function(a, b) {
            return a.birth - b.birth || a.address.localeCompare(b.address);
        });
        var identities = sorted.map(function(w) {
            return w.address + ":" + w.birth;
        });
        for (var index = root.count - 1; index >= 0; index--) {
            if (identities.indexOf(root.get(index).identity) < 0)
                root.remove(index);
        }
        sorted.forEach(function(window, position) {
            var key = identities[position];
            var existing = -1;
            for (var index = 0; index < root.count; index++) {
                if (root.get(index).identity === key) {
                    existing = index;
                    break;
                }
            }
            var data = JSON.stringify(window);
            if (existing < 0) {
                root.insert(position, {identity: key, rowJson: data});
            } else {
                if (existing !== position)
                    root.move(existing, position, 1);
                if (root.get(position).rowJson !== data)
                    root.setProperty(position, "rowJson", data);
            }
        });
    }
}

#!/usr/bin/env python3
"""Un mouse finto su /dev/uinput: serve solo a provare che un clic arrivi
davvero dove diciamo che arriva.

    prova-clic.py left 400 300           clic sinistro lì
    prova-clic.py rotella 400 300 -5     cinque scatti di rotellina in giù
    prova-clic.py trascina 400 100 5 500 prende in (400,100) e lascia in (5,500)
    prova-clic.py muovi 400 100 5 500    ci passa sopra senza premere niente

La rotellina serve a provare le pagine lunghe — le Impostazioni sono alte il
doppio dello schermo, e senza si può fotografare solo la loro cima.
"""
import fcntl, os, struct, sys, time

UI_SET_EVBIT   = 0x40045564
UI_SET_KEYBIT  = 0x40045565
UI_SET_RELBIT  = 0x40045566
UI_DEV_CREATE  = 0x5501
UI_DEV_DESTROY = 0x5502

EV_SYN, EV_KEY, EV_REL = 0, 1, 2
SYN_REPORT = 0
BTN_LEFT, BTN_RIGHT, BTN_MIDDLE = 0x110, 0x111, 0x112
REL_X, REL_Y, REL_WHEEL = 0, 1, 8

what = sys.argv[1] if len(sys.argv) > 1 else "right"
scroll = what == "rotella"
# Trascinamento: premi qui, arriva là, lascia. Serve a provare l'aggancio ai
# bordi, che è l'unica cosa di Minerva che non si può provare con un clic solo.
dragging = what == "trascina"
# «muovi» è un trascinamento senza pulsante: serve a provare tutto ciò che
# reagisce al PASSAGGIO del puntatore — la dock che si nasconde da sola, gli
# ingrandimenti, i suggerimenti. `hyprctl dispatch movecursor` non basta:
# sposta il cursore senza dire niente a chi ci sta sotto, e infatti con quello
# nessun `containsMouse` si accende mai.
hovering = what == "muovi"
drag_to = (int(sys.argv[4]), int(sys.argv[5])) \
    if (dragging or hovering) and len(sys.argv) > 5 else None
# Quanti scatti, e da che parte: positivo su, negativo giù. Sta in quarta
# posizione perché le prime tre sono le stesse di un clic (che cosa, dove).
notches = int(sys.argv[4]) if scroll and len(sys.argv) > 4 else -3
button = BTN_LEFT if (scroll or dragging or hovering) else {
    "left": BTN_LEFT, "right": BTN_RIGHT, "middle": BTN_MIDDLE}[what]

fd = open("/dev/uinput", "wb", buffering=0)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_REL)
fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
for b in (BTN_LEFT, BTN_RIGHT, BTN_MIDDLE):
    fcntl.ioctl(fd, UI_SET_KEYBIT, b)
for r in (REL_X, REL_Y, REL_WHEEL):
    fcntl.ioctl(fd, UI_SET_RELBIT, r)

name = b"minerva-prova-mouse".ljust(80, b"\0")
fd.write(name + struct.pack("HHHH", 0x03, 0x1234, 0x5678, 1)
         + struct.pack("i", 0) + b"\0" * (4 * 64 * 4))
fcntl.ioctl(fd, UI_DEV_CREATE)
time.sleep(1.0)

# Il puntatore si posiziona DOPO aver creato il dispositivo: agganciare un
# mouse nuovo fa saltare il cursore altrove, e mirare prima è tempo perso.
#
# E non basta spostarlo una volta: il salto può arrivare ANCHE dopo, quando il
# compositore finisce di configurare il dispositivo appena comparso. Un clic
# tirato a indovinare finisce da un'altra parte e il difetto che si voleva
# provare risulta assente — che è il modo peggiore di sbagliare una prova.
# Quindi si mira, si controlla, e si riprova finché il puntatore non è dove
# deve stare.
if len(sys.argv) > 3:
    want = (int(sys.argv[2]), int(sys.argv[3]))
    _mirato = None   # si mira dopo aver definito `ev`, più sotto

def ev(t, c, v):
    fd.write(struct.pack("qqHHi", 0, 0, t, c, v))


def canale():
    """Il socket di comando del compositore di questa sessione.

    Il nome lo compone `minerva-wayland` dal proprio `WAYLAND_DISPLAY`:
    `$XDG_RUNTIME_DIR/minerva-wayland-<display>.sock`. Così due sessioni
    accese insieme non si parlano addosso.
    """
    corsa = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
    display = os.environ.get("WAYLAND_DISPLAY", "")
    if not display:
        return None
    via = os.path.join(corsa, "minerva-wayland-%s.sock" % display)
    return via if os.path.exists(via) else None


def cursor_now():
    """Dov'è il puntatore, in pixel logici.

    ── Perché non `hyprctl cursorpos` ────────────────────────────────────

    Perché non c'è più. Fino al 4 settembre 2026 qui c'erano due chiamate a
    `hyprctl` — una per leggere la posizione, una per spostare il cursore —
    ed erano codice morto dal distacco del 2 settembre: `hyprctl` non è
    installato, la lettura tornava `None`, e questo strumento **rifiutava
    ogni clic** con «il puntatore non è arrivato».

    È il difetto peggiore che potesse avere: prova-clic serve a GUARDARE, ed
    è il modo con cui questo progetto verifica le cose che le prove
    automatiche non prendono. Rotto lui, la verifica visiva era ferma e
    nessuna prova diventava rossa.
    """
    via = canale()
    if via is None:
        return None
    import socket as _s
    try:
        c = _s.socket(_s.AF_UNIX, _s.SOCK_STREAM)
        c.settimeout(3)
        c.connect(via)
        c.sendall(b"puntatore\n")
        r = c.recv(256).decode("utf-8", "replace").strip()
        c.close()
        # «ok 1211, 94» — lo stesso formato di hyprctl, di proposito.
        if not r.startswith("ok "):
            return None
        x, y = r[3:].split(",")
        return (int(x), int(y))
    except Exception:
        return None


def passo(d):
    """Quanto muoversi verso il bersaglio.

    Proporzionale a quanto manca: lontano si va spediti, vicino si rallenta.
    Un passo fisso non converge mai, perché l'ultimo scatto è sempre più
    lungo di quanto manca — e chi guarda lo schermo vede il mouse TREMARE.
    """
    if d == 0:
        return 0
    v = max(1, min(12, int(abs(d) * 0.6)))
    return v if d > 0 else -v


def mira(want, ev_, giri=120):
    """Porta il puntatore su `want` a scatti relativi, guardando dove arriva.

    Sotto Hyprland si chiedeva al compositore di METTERE il cursore in un
    punto. Il nostro non ha quel verbo, e non gliene serve uno: il puntatore
    si sposta come lo sposta una mano — a scatti relativi — e si controlla
    dov'è arrivato. È anche più onesto: prova la strada vera.
    """
    for _ in range(giri):
        at = cursor_now()
        if at is None:
            return False
        dx, dy = want[0] - at[0], want[1] - at[1]
        # Tre pixel di tolleranza, non due: l'accelerazione del puntatore
        # moltiplica gli scatti, e con due superava il bersaglio a ogni
        # correzione rimbalzandoci attorno.
        if abs(dx) <= 3 and abs(dy) <= 3:
            return True
        ev_(EV_REL, REL_X, passo(dx))
        ev_(EV_REL, REL_Y, passo(dy))
        ev_(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.02)
    return False


if len(sys.argv) > 3:
    if not mira(want, ev):
        print("prova-clic: il puntatore non è arrivato in %s, è in %s "
              "— clic annullato" % (want, cursor_now()), file=sys.stderr)
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        fd.close()
        sys.exit(1)
    time.sleep(0.3)


if dragging or hovering:
    if drag_to is None:
        print("prova-clic: trascina vuole quattro numeri: x1 y1 x2 y2",
              file=sys.stderr)
        fcntl.ioctl(fd, UI_DEV_DESTROY)
        fd.close()
        sys.exit(1)

    if dragging:
        ev(EV_KEY, BTN_LEFT, 1)
        ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.25)

    # Si muove a piccoli passi e non in un salto solo: chi riceve il
    # trascinamento aggiorna la finestra a ogni movimento, e un salto unico
    # gli fa saltare tutti i passaggi intermedi — compresa la zona di aggancio
    # su cui si voleva finire.
    #
    # Il movimento è RELATIVO, quindi l'accelerazione del puntatore lo
    # allunga o lo accorcia: si guarda dove si è arrivati e si corregge,
    # invece di fidarsi dei conti.
    mira(drag_to, ev, giri=90)

    time.sleep(0.4)
    if dragging:
        ev(EV_KEY, BTN_LEFT, 0)
        ev(EV_SYN, SYN_REPORT, 0)
    time.sleep(0.5)
elif scroll:
    # Uno scatto per volta con una pausa in mezzo: mandarli tutti insieme fa
    # saltare la pagina invece di scorrerla, e chi guarda la fotografia non
    # capisce dov'è finito.
    step = 1 if notches > 0 else -1
    for _ in range(abs(notches)):
        ev(EV_REL, REL_WHEEL, step)
        ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.09)
else:
    times = 2 if os.environ.get("DOPPIO") == "1" else 1
    for _ in range(times):
        ev(EV_KEY, button, 1)
        ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.05)
        ev(EV_KEY, button, 0)
        ev(EV_SYN, SYN_REPORT, 0)
        time.sleep(0.08)
time.sleep(0.4)

fcntl.ioctl(fd, UI_DEV_DESTROY)
fd.close()
if dragging or hovering:
    print(f"{'trascinato' if dragging else 'passato'} fino a {cursor_now()}")
elif scroll:
    print(f"rotella {notches} fatta")
else:
    print(f"clic {what} fatto")

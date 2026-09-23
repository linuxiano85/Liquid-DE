#!/usr/bin/env python3
"""I quattro verbi di manutenzione dell'aiutante di root, provati per davvero.

── Perché una prova a parte, e perché così ────────────────────────────────

Perché `scripts/minerva-radice` gira come root e cancella roba di sistema: è
il file del progetto in cui un difetto costa di più, ed è anche l'unico che
una prova normale non può eseguire — si rifiuta di partire se non è root.

Allora si fa così: si prende il file VERO, si sostituiscono le tre cartelle
di sistema con altrettante cartelle finte dentro una temporanea, e lo si
lancia sotto `fakeroot` (che fa dire «0» a `id -u`). Il codice provato è
quello vero riga per riga; cambiano solo i posti su cui lavora, e i programmi
di sistema — `pacman`, `paccache`, `journalctl` — sono finti e stanno in un
PATH tutto nostro.

**Niente di quello che segue tocca la macchina di chi la lancia.** È la
regola di `minerva-non-toccare-in-prova`, che qui vale doppio.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

QUI = os.path.dirname(os.path.abspath(__file__))
VERO = os.path.join(QUI, "minerva-radice")

passate = 0
fallite = 0


def verifica(nome, condizione, dettaglio=""):
    global passate, fallite
    if condizione:
        passate += 1
        print("  ok   %s" % nome)
    else:
        fallite += 1
        print("  NO   %s%s" % (nome, ("\n       " + dettaglio) if dettaglio else ""))


def prepara(base):
    """Il file vero, con le cartelle di sistema spostate dentro `base`."""
    testo = open(VERO, encoding="utf-8").read()
    for vero, finto in (
        ("/var/cache/pacman/pkg", base + "/cache-pkg"),
        ("/usr/share/locale", base + "/locale"),
        ("/etc/pacman.conf", base + "/pacman.conf"),
        ("/var/log/journal", base + "/journal"),
        ("/var/log/minerva-radice.log", base + "/registro.log"),
        ("/etc/pacman.conf.minerva.XXXXXX", base + "/pacman.conf.minerva.XXXXXX"),
        ("/etc/locale.conf", base + "/locale.conf"),
    ):
        testo = testo.replace(vero, finto)
    copia = base + "/radice"
    open(copia, "w", encoding="utf-8").write(testo)
    os.chmod(copia, 0o755)
    return copia


def finti(base, orfani="cmark-gfm\nlibayatana-indicator\n"):
    """`pacman`, `paccache` e `journalctl` finti, in un PATH tutto nostro."""
    cestino = base + "/bin"
    os.makedirs(cestino, exist_ok=True)
    scritti = base + "/chiamate"

    def scrivi(nome, corpo):
        p = os.path.join(cestino, nome)
        open(p, "w", encoding="utf-8").write("#!/bin/sh\n" + corpo)
        os.chmod(p, 0o755)

    scrivi("pacman", (
        'echo "pacman $*" >> %s\n'
        'if [ "$1" = "-Qtdq" ]; then printf %s; exit 0; fi\n'
        'exit 0\n'
    ) % (scritti, "'" + orfani + "'"))
    scrivi("paccache", (
        'echo "paccache $*" >> %s\n'
        # Toglie tutto tranne le ultime due versioni: qui basta che tolga
        # QUALCOSA, perché la prova guarda che il verbo lo chiami con -k 2.
        'rm -f %s/cache-pkg/vecchio-*.pkg.tar.zst\n'
        'exit 0\n'
    ) % (scritti, base))
    scrivi("journalctl", (
        'echo "journalctl $*" >> %s\n'
        'rm -f %s/journal/vecchio.journal\n'
        'exit 0\n'
    ) % (scritti, base))
    return cestino, scritti


def esegui(copia, cestino, argomenti):
    amb = dict(os.environ)
    amb["PATH"] = cestino + ":" + amb["PATH"]
    amb["PKEXEC_UID"] = "1000"
    r = subprocess.run(["fakeroot", "sh", copia] + argomenti,
                       capture_output=True, text=True, env=amb, timeout=60)
    return r


def main():
    if shutil.which("fakeroot") is None:
        print("SALTATA: manca fakeroot")
        return 0

    base = tempfile.mkdtemp(prefix="minerva-radice-prova-")
    try:
        copia = prepara(base)
        cestino, scritti = finti(base)

        # ── La cache dei pacchetti ────────────────────────────────────────
        os.makedirs(base + "/cache-pkg")
        for n in range(3):
            open("%s/cache-pkg/vecchio-%d.pkg.tar.zst" % (base, n), "w").write("x" * 1000)
        open(base + "/cache-pkg/nuovo.pkg.tar.zst", "w").write("y" * 100)

        r = esegui(copia, cestino, ["pulisci-cache-pacchetti"])
        chiamate = open(scritti).read() if os.path.exists(scritti) else ""
        verifica("la cache dei pacchetti passa da paccache, non da rm",
                 "paccache -r -k 2" in chiamate,
                 "chiamate: %r  err: %s" % (chiamate, r.stderr.strip()))
        verifica("e fa i DUE giri, come il conto promesso all'inventario",
                 "paccache -r -u -k 0" in chiamate, chiamate)
        verifica("e tiene le ultime DUE versioni, non una",
                 "-k 2" in chiamate and "-k 1" not in chiamate)
        verifica("dice quanto pesava prima e quanto pesa dopo",
                 r.stdout.startswith("fatto "), r.stdout.strip())

        # ── Le lingue ─────────────────────────────────────────────────────
        os.makedirs(base + "/locale")
        for l in ["it", "it_IT", "it_IT@euro", "en", "en_GB", "de", "fr",
                  "ru", "zh_CN", "C"]:
            os.makedirs("%s/locale/%s/LC_MESSAGES" % (base, l))
            open("%s/locale/%s/LC_MESSAGES/x.mo" % (base, l), "w").write("z" * 500)
        open(base + "/locale/locale.alias", "w").write("alias\n")
        # Un pacman.conf come quello vero: `[options]` in cima e le sezioni
        # dei repository in fondo. È la forma che ha fatto nascere il difetto
        # del 9 settembre — la riga finiva in coda, cioè dentro `[multilib]`,
        # dove `NoExtract` non vale niente.
        open(base + "/locale.conf", "w").write("LANG=it_IT.UTF-8\n")
        open(base + "/pacman.conf", "w").write(
            "[options]\nHoldPkg = pacman glibc\n#NoExtract =\n\n"
            "[core]\nInclude = /etc/pacman.d/mirrorlist\n\n"
            "[multilib]\nInclude = /etc/pacman.d/mirrorlist\n")

        r = esegui(copia, cestino, ["pulisci-lingue", "it", "en", "C"])
        rimaste = sorted(os.listdir(base + "/locale"))
        verifica("le lingue da tenere restano, con le loro varianti",
                 set(["it", "it_IT", "it_IT@euro", "en", "en_GB", "C"]) <= set(rimaste),
                 str(rimaste))
        verifica("le altre se ne vanno",
                 not (set(["de", "fr", "ru", "zh_CN"]) & set(rimaste)), str(rimaste))
        verifica("il file che non è una cartella non si tocca",
                 "locale.alias" in rimaste)

        conf = open(base + "/pacman.conf", encoding="utf-8").read()
        verifica("e a pacman si dice di non installarle più",
                 "NoExtract = usr/share/locale/*" in conf, conf)
        verifica("con le eccezioni per quelle che tieni",
                 "!usr/share/locale/it*" in conf and "!usr/share/locale/en*" in conf,
                 conf)
        verifica("resta scritto come si disfa",
                 "per disfare" in conf, conf)

        # ── Dove finisce la riga, che è tutto ─────────────────────────────
        #
        # `NoExtract` vale SOLO dentro `[options]`. In fondo al file c'è
        # l'ultima sezione dei repository, e lì pacman la ignora — dicendolo
        # con un avviso che nessuno legge. Le lingue tornerebbero al primo
        # aggiornamento: cioè il verbo avrebbe cancellato senza risolvere.
        righe = conf.split("\n")
        dove_riga = next(i for i, r in enumerate(righe)
                         if r.startswith("NoExtract = usr/share/locale/"))
        dove_options = righe.index("[options]")
        prima_altra = next((i for i, r in enumerate(righe)
                            if r.startswith("[") and r != "[options]"), len(righe))
        verifica("la riga sta DENTRO [options], non in fondo al file",
                 dove_options < dove_riga < prima_altra,
                 "riga %d, [options] %d, sezione dopo %d"
                 % (dove_riga, dove_options, prima_altra))

        verifica("e `locale.alias` non finisce fra le vittime",
                 "!usr/share/locale/locale.alias" in conf,
                 "è un file di gettext, non una traduzione: senza eccezione "
                 "pacman smetterebbe di installarlo")
        verifica("e c'è una copia del file com'era prima",
                 os.path.exists(base + "/pacman.conf.minerva-prima"))
        verifica("il resto di pacman.conf non si perde",
                 "HoldPkg = pacman glibc" in conf, conf)
        verifica("e nemmeno le sezioni dei repository",
                 "[core]" in conf and "[multilib]" in conf, conf)

        # Due volte di fila: la copia di prima non si sovrascrive, e la riga
        # non si duplica. È la prova che nessuno ha mai scritto e che qui
        # serve.
        esegui(copia, cestino, ["pulisci-lingue", "it", "en", "C"])
        conf2 = open(base + "/pacman.conf", encoding="utf-8").read()
        verifica("pulendo due volte la riga resta UNA",
                 conf2.count("NoExtract = usr/share/locale/") == 1, conf2)
        prima = open(base + "/pacman.conf.minerva-prima", encoding="utf-8").read()
        verifica("e la copia di prima è ancora quella originale",
                 "NoExtract = usr/share/locale" not in prima, prima)


        # ── Le due che non si tolgono mai ─────────────────────────────────
        #
        # Giacomo: «facciamo in modo che lasci sempre l'inglese in qualsiasi
        # caso [...] e lasci la lingua usata». La garanzia sta nell'aiutante e
        # non solo in chi lo chiama: è l'ultimo che decide.
        #
        # Si chiede di tenere SOLO il tedesco, e devono sopravvivere lo stesso
        # l'inglese, il `C` e l'italiano (che è la lingua di /etc/locale.conf).
        for l in ["it", "it_IT", "en", "en_GB", "de", "fr", "C"]:
            os.makedirs("%s/locale/%s" % (base, l), exist_ok=True)
        esegui(copia, cestino, ["pulisci-lingue", "de"])
        rimaste = sorted(os.listdir(base + "/locale"))
        verifica("chiedendo SOLO il tedesco, l'inglese resta comunque",
                 "en" in rimaste and "en_GB" in rimaste, str(rimaste))
        verifica("e resta la lingua che il sistema usa davvero",
                 "it" in rimaste and "it_IT" in rimaste, str(rimaste))
        verifica("e il «C», che è il ripiego di chi non trova la sua",
                 "C" in rimaste, str(rimaste))
        verifica("il tedesco chiesto resta anche lui",
                 "de" in rimaste, str(rimaste))
        verifica("e il francese, che non ha chiesto nessuno, se ne va",
                 "fr" not in rimaste, str(rimaste))

        conf3 = open(base + "/pacman.conf", encoding="utf-8").read()
        riga3 = [r for r in conf3.split("\n")
                 if r.startswith("NoExtract = usr/share/locale/")][0]
        verifica("e la riga per pacman le nomina tutte, una volta sola",
                 riga3.count("!usr/share/locale/en*") == 1
                 and "!usr/share/locale/it*" in riga3
                 and "!usr/share/locale/de*" in riga3, riga3)

        # Un nome di lingua che è un percorso non è un nome di lingua.
        for cattivo in ["../etc", "/usr", "-rf", "it/../..", ".ssh"]:
            r = esegui(copia, cestino, ["pulisci-lingue", cattivo])
            verifica("«%s» non è un nome di lingua" % cattivo,
                     r.returncode != 0, r.stdout + r.stderr)

        # ── Il registro ───────────────────────────────────────────────────
        os.makedirs(base + "/journal")
        open(base + "/journal/vecchio.journal", "w").write("w" * 2000)
        r = esegui(copia, cestino, ["pulisci-registro"])
        chiamate = open(scritti).read()
        verifica("il registro si POTA con journalctl, non si cancella",
                 "journalctl --vacuum-size=50M" in chiamate, chiamate)
        verifica("e se ne tengono gli ultimi giorni, non zero",
                 "--vacuum-size=50M" in chiamate)

        # ── Gli orfani ────────────────────────────────────────────────────
        open(scritti, "w").close()
        r = esegui(copia, cestino,
                   ["togli-orfani", "cmark-gfm", "linux", "sudo"])
        chiamate = open(scritti).read()
        verifica("si tolgono solo i pacchetti che pacman dice orfani ADESSO",
                 "pacman -Rns --noconfirm -- cmark-gfm" in chiamate, chiamate)
        verifica("e «linux» non finisce nella riga, anche se glielo chiedi",
                 " linux" not in chiamate.split("-Rns")[-1], chiamate)
        verifica("nemmeno «sudo»",
                 " sudo" not in chiamate.split("-Rns")[-1], chiamate)

        for cattivo in ["../qualcosa", "-Rns", "linux; rm -rf /", ""]:
            r = esegui(copia, cestino, ["togli-orfani", cattivo])
            verifica("«%s» non è un nome di pacchetto" % cattivo,
                     r.returncode != 0 or "niente da togliere" in r.stdout,
                     r.stdout + r.stderr)

        # ── E il verbo che non esiste ─────────────────────────────────────
        r = esegui(copia, cestino, ["pulisci", "/etc"])
        verifica("non esiste nessun «pulisci <percorso>» generico",
                 r.returncode != 0 and "sconosciuta" in r.stderr, r.stderr)

    finally:
        shutil.rmtree(base, ignore_errors=True)

    print()
    if fallite:
        print("FALLITE %d su %d" % (fallite, passate + fallite))
        return 1
    print("TUTTE PASSATE (%d)" % passate)
    return 0


if __name__ == "__main__":
    sys.exit(main())

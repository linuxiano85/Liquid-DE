"""cartelle.py — Le cartelle di Liquid DE, per le prove scritte in Python.

Le stesse regole di `minervad/lib/core/minerva_paths.dart`, di `core/Ipc.qml`
e di `minerva-cartelle.sh`, e lo stesso nome: Liquid DE e Minerva convivono
sullo stesso computer solo se non scrivono mai nella stessa cartella.
"""
import os

NOME = "liquid-de"
NOME_MINERVA = "minerva"


def _base(variabile, di_serie):
    v = os.environ.get(variabile, "")
    if v.startswith("/"):
        return v.rstrip("/") or "/"
    return os.path.join(os.path.expanduser("~"), di_serie)


def config():
    """Le impostazioni. `MINERVA_CONFIG_DIR` vince: è quello delle prove."""
    detto = os.environ.get("MINERVA_CONFIG_DIR", "")
    if detto:
        return detto.rstrip("/")
    return os.path.join(_base("XDG_CONFIG_HOME", ".config"), NOME)


def stato():
    return os.path.join(_base("XDG_STATE_HOME", ".local/state"), NOME)


def runtime():
    r = os.environ.get("XDG_RUNTIME_DIR", "")
    if r.startswith("/"):
        return os.path.join(r.rstrip("/"), NOME)
    return "/tmp/%s-%s" % (NOME, os.environ.get("USER", "utente"))


def config_di_partenza():
    """Le impostazioni VERE da cui parte una prova: quelle di Liquid DE, o
    quelle di Minerva finché Liquid DE non ha ancora le sue. Si leggono e
    basta: una prova non scrive mai qui."""
    base = _base("XDG_CONFIG_HOME", ".config")
    nostra = os.path.join(base, NOME)
    if os.path.isfile(os.path.join(nostra, "settings.json")):
        return nostra
    return os.path.join(base, NOME_MINERVA)


def prefisso():
    """Dove si installano i programmi di Liquid DE (`~/.local/bin` è di
    Minerva)."""
    return os.environ.get("LIQUID_PREFISSO") or os.path.join(
        os.path.expanduser("~"), ".local", "opt", NOME)


def cartella_bin():
    """I programmi installati; `MINERVA_BIN` la sostituisce nelle prove."""
    return os.environ.get("MINERVA_BIN") or os.path.join(prefisso(), "bin")

"""Use the distribution's Qt Python binding for the isolated print worker."""
from importlib import import_module
from importlib.util import find_spec

BINDING = 'PySide6' if find_spec('PySide6') is not None else 'PyQt6'


def __getattr__(name):
    if name.startswith('__'):
        raise AttributeError(name)
    for module_name in ('QtCore', 'QtGui', 'QtPdf'):
        module = import_module(BINDING + '.' + module_name)
        if hasattr(module, name):
            return getattr(module, name)
    raise AttributeError(name)

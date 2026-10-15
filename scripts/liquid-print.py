#!/usr/bin/env python3
"""Ponte locale CUPS: richieste JSON, nessuna shell o privilegio aggiuntivo."""
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote

# Python -I non importa moduli dalla cartella corrente: carichiamo soltanto
# il nostro adattatore con percorso derivato da questo file.
_spec = importlib.util.spec_from_file_location('liquid_print_discovery', Path(__file__).with_name('liquid_print_discovery.py'))
discovery = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(discovery)

ATTRIBUTES = ['printer-state', 'printer-is-accepting-jobs', 'printer-state-reasons',
              'printer-info', 'printer-location', 'printer-make-and-model',
              'sides-supported', 'media-supported', 'print-color-mode-supported',
              'copies-supported', 'document-format-supported', 'printer-commands',
              'marker-names', 'marker-types', 'marker-colors', 'marker-levels',
              'marker-low-levels', 'marker-high-levels', 'marker-change-time',
              'media-default', 'media-ready', 'media-type-supported', 'media-source-supported',
              'printer-resolution-supported', 'print-quality-supported']
JOB_ATTRIBUTES = ['job-id', 'job-name', 'job-state', 'job-printer-uri',
                  'job-k-octets', 'job-media-sheets-completed']


MAINTENANCE = {'self-test': 'PrintSelfTestPage', 'clean': 'Clean',
               'levels': 'ReportLevels'}


def values(value):
    if value is None:
        return []
    return value if isinstance(value, (list, tuple)) else [value]


def consumables(attrs):
    levels = values(attrs.get('marker-levels'))
    names = values(attrs.get('marker-names'))
    colors = values(attrs.get('marker-colors'))
    types = values(attrs.get('marker-types'))
    lows = values(attrs.get('marker-low-levels'))
    highs = values(attrs.get('marker-high-levels'))
    rows = []
    for index in range(max(len(levels), len(names), len(types))):
        def at(items, fallback):
            return items[index] if index < len(items) else fallback
        raw = at(levels, -1)
        # IPP distingue non disponibile (-1), sconosciuto (-2) e non pieno
        # (-3): nessuno dei tre significa cartuccia vuota o zero percento.
        level = raw if type(raw) is int and 0 <= raw <= 100 else None
        color = at(colors, '')
        if not isinstance(color, str) or not re.fullmatch(r'#[0-9A-Fa-f]{6}', color):
            color = '#808080'
        threshold = at(lows, None)
        high = at(highs, None)
        waste = str(at(types, '')).startswith('waste-')
        rows.append({'name': str(at(names, '')), 'type': str(at(types, '')),
                     'color': color, 'level': level,
                     'high': waste and level is not None and type(high) is int and 0 <= high < 100 and level >= high,
                     'low': not waste and level is not None and type(threshold) is int
                            and 0 <= threshold <= 100 and level <= threshold})
    return rows


def maintenance_commands(attrs):
    commands = []
    for item in values(attrs.get('printer-commands')):
        commands.extend(str(item).split(','))
    available = {command.strip().lower() for command in commands}
    return [key for key, command in MAINTENANCE.items() if command.lower() in available]


def inventory(connection):
    configured = connection.getPrinters()
    # getDests comprende anche destinazioni DNS-SD temporanee. Non si devono
    # mostrare come seconde code installate della stessa stampante di rete.
    default = connection.getDefault()
    # getDefault reports the server default, while lpoptions -d selects a
    # personal destination. Temporary DNS-SD destinations are not installed.
    if hasattr(connection, 'getDests'):
        for (name, instance), destination in connection.getDests().items():
            if name in configured and destination.is_default:
                default = name
                break
    printers = []
    for name, basic in sorted(configured.items(), key=lambda row: row[0].casefold()):
        attrs = connection.getPrinterAttributes(name=name, requested_attributes=ATTRIBUTES)
        printers.append({
            'name': name, 'description': attrs.get('printer-info', basic.get('printer-info', name)),
            'model': attrs.get('printer-make-and-model', basic.get('printer-make-and-model', '')),
            'state': attrs.get('printer-state', 0),
            'accepting': attrs.get('printer-is-accepting-jobs'),
            'reasons': values(attrs.get('printer-state-reasons')),
            'connection': 'usb' if str(basic.get('device-uri', '')).startswith('usb:') else
                'network' if str(basic.get('device-uri', '')).startswith(('ipp:', 'ipps:', 'dnssd:', 'socket:', 'lpd:')) else 'unknown',
            'default': name == default,
            'media': values(attrs.get('media-supported')),
            'sides': values(attrs.get('sides-supported', ['one-sided'])),
            'colors': values(attrs.get('print-color-mode-supported')),
            'copies': attrs.get('copies-supported', [1, 1]),
            'formats': values(attrs.get('document-format-supported')),
            'supplies': consumables(attrs),
            'suppliesChanged': attrs.get('marker-change-time'),
            'maintenance': maintenance_commands(attrs),
            'paperDefault': attrs.get('media-default', ''),
            'paperReady': values(attrs.get('media-ready')),
            'paperTypes': values(attrs.get('media-type-supported')),
            'paperSources': values(attrs.get('media-source-supported')),
            'resolutions': values(attrs.get('printer-resolution-supported')),
            'qualities': values(attrs.get('print-quality-supported')),
        })
    jobs = []
    for identifier, attrs in connection.getJobs(which_jobs='not-completed', my_jobs=True,
                                               limit=100, requested_attributes=JOB_ATTRIBUTES).items():
        jobs.append({'id': identifier, 'title': attrs.get('job-name', ''),
                     'state': attrs.get('job-state', 0),
                     'printer': unquote(attrs.get('job-printer-uri', '').rsplit('/', 1)[-1]),
                     'sizeKiB': attrs.get('job-k-octets', 0),
                     'sheets': attrs.get('job-media-sheets-completed', 0)})
    return {'ok': True, 'printers': printers, 'default': default or '',
            'jobs': sorted(jobs, key=lambda row: row['id'], reverse=True)}


def integer(value, low, high):
    if isinstance(value, bool) or not isinstance(value, int) or not low <= value <= high:
        raise ValueError('invalid-integer')
    return value


def print_options(request, printer):
    options = request.get('options', {})
    if not isinstance(options, dict):
        raise ValueError('invalid-options')
    permitted = {'copies', 'media', 'sides', 'color', 'orientation', 'pages'}
    if options.keys() - permitted:
        raise ValueError('unknown-option')
    copies = integer(options.get('copies', 1), 1, 999)
    bounds = printer.get('copies') or [1, 1]
    if copies < bounds[0] or copies > bounds[-1]:
        raise ValueError('unsupported-copies')
    result = {'copies': str(copies)}
    for field, allowed, target in [('media', printer['media'], 'media'),
                                   ('sides', printer['sides'], 'sides'),
                                   ('color', printer['colors'], 'print-color-mode')]:
        value = options.get(field)
        if value is not None:
            if not isinstance(value, str) or value not in allowed:
                raise ValueError('unsupported-' + field)
            result[target] = value
    orientation = options.get('orientation')
    if orientation is not None:
        if orientation not in ['portrait', 'landscape']:
            raise ValueError('invalid-orientation')
        result['orientation-requested'] = '3' if orientation == 'portrait' else '4'
    pages = options.get('pages')
    if pages is not None:
        if not isinstance(pages, str) or not re.fullmatch(r'[1-9][0-9]*(?:-[1-9][0-9]*)?(?:,[1-9][0-9]*(?:-[1-9][0-9]*)?)*', pages):
            raise ValueError('invalid-pages')
        for interval in pages.split(','):
            pair = interval.split('-')
            if len(pair) == 2 and int(pair[0]) > int(pair[1]):
                raise ValueError('invalid-pages')
        result['page-ranges'] = pages
    return result


DRIVER_PACKAGES = {
    'gutenprint': 'Gutenprint',
    'hplip': 'HP HPLIP',
    'brlaser': 'Brother brlaser',
    'splix': 'Samsung SPL',
    'epson-inkjet-printer-escpr': 'Epson ESC/P-R',
    'epson-inkjet-printer-escpr2': 'Epson ESC/P-R 2',
}


def repository_packages(runner=subprocess.run):
    # Solo repository già configurati dall'amministratore. Nessun helper AUR,
    # script scaricato o aggiornamento parziale del database dei pacchetti.
    if not Path('/usr/bin/pacman').is_file():
        return {'ok': True, 'packages': [], 'packageInstallSupported': False}
    packages = []
    for name, title in DRIVER_PACKAGES.items():
        available = runner(['/usr/bin/pacman', '-Si', '--', name],
            capture_output=True, text=True, timeout=5, check=False)
        if available.returncode:
            continue
        installed = runner(['/usr/bin/pacman', '-Q', '--', name],
            capture_output=True, text=True, timeout=5, check=False)
        packages.append({'id': name, 'title': title, 'installed': installed.returncode == 0})
    return {'ok': True, 'packages': packages, 'packageInstallSupported': True}


def install_driver(request, runner=subprocess.run):
    name = request.get('package')
    if not isinstance(name, str) or name not in DRIVER_PACKAGES:
        raise ValueError('unsupported-driver-package')
    state = repository_packages(runner)
    package = next((row for row in state['packages'] if row['id'] == name), None)
    if package is None:
        raise ValueError('driver-package-unavailable')
    if not package['installed']:
        result = runner(['/usr/bin/pkexec', '/usr/bin/pacman', '-S', '--needed', '--noconfirm', '--', name],
            capture_output=True, text=True, timeout=540, check=False)
        if result.returncode:
            raise RuntimeError('\n'.join(result.stderr.strip().splitlines()[-8:]) or 'driver-install-failed')
    state = repository_packages(runner)
    if not any(row['id'] == name and row['installed'] for row in state['packages']):
        raise RuntimeError('driver-install-not-confirmed')
    state['installedPackage'] = name
    return state


def admin_call(method, signature, arguments):
    # Il servizio di sistema richiede l'autorizzazione Polkit per la singola
    # operazione. Non eseguiamo come root script scrivibili dall'utente.
    try:
        from gi.repository import Gio, GLib
        bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        reply = bus.call_sync('org.opensuse.CupsPkHelper.Mechanism', '/',
            'org.opensuse.CupsPkHelper.Mechanism', method,
            GLib.Variant(signature, arguments), GLib.VariantType('(s)'),
            Gio.DBusCallFlags.ALLOW_INTERACTIVE_AUTHORIZATION, 120000, None)
        error = reply.unpack()[0]
        if error:
            raise RuntimeError(error)
    except ImportError as error:
        raise RuntimeError('cups-pk-helper/python-gobject required') from error
    except Exception as error:
        raise RuntimeError(str(error)) from error


def cups_administrator(connection, fallback=admin_call):
    """Use CUPS permissions first; ask Polkit only for an authorization denial."""
    import cups
    # libcups must never prompt on stdin: this process speaks JSON to QML.
    # Returning None still permits local peer credentials before a password
    # would be needed. Polkit owns any subsequent interactive authentication.
    cups.setPasswordCB2(lambda *args: None)

    def dispatch(method, signature, arguments):
        operations = {
            'PrinterAdd': ('(sssss)', lambda name, uri, driver, info, location:
                connection.addPrinter(name, device=uri, ppdname=driver, info=info, location=location)),
            'PrinterDelete': ('(s)', connection.deletePrinter),
            'PrinterSetShared': ('(sb)', connection.setPrinterShared),
            'PrinterSetEnabled': ('(sb)', lambda name, enabled:
                connection.enablePrinter(name) if enabled else connection.disablePrinter(name)),
            'PrinterSetAcceptJobs': ('(sbs)', lambda name, accepting, reason:
                connection.acceptJobs(name) if accepting else connection.rejectJobs(name, reason=reason)),
        }
        if method not in operations or signature != operations[method][0]:
            raise ValueError('unsupported-printer-administration')
        try:
            operations[method][1](*arguments)
        except cups.IPPError as error:
            if error.args[0] not in (cups.IPP_FORBIDDEN, cups.IPP_NOT_AUTHORIZED):
                raise
            fallback(method, signature, arguments)
    return dispatch


def catalog(connection, query):
    if not isinstance(query, str) or not 1 <= len(query.strip()) <= 160:
        raise ValueError('invalid-driver-query')
    found = connection.getPPDs(limit=80, ppd_make_and_model=query.strip())
    return {name: attrs for name, attrs in found.items()
            if attrs.get('ppd-type') != 'fax' and not name.startswith('driverless-fax:')}


def configure(request, connection, state, administrator):
    name, uri, driver = request.get('name'), request.get('uri'), request.get('driver')
    if not isinstance(name, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_-]{0,62}', name):
        raise ValueError('invalid-printer-name')
    if any(row['name'].lower() == name.lower() for row in state['printers']):
        raise ValueError('printer-already-exists')
    configured = connection.getPrinters()
    if any(attrs.get('device-uri') == uri for attrs in configured.values()):
        raise ValueError('device-already-configured')
    if not isinstance(uri, str) or not uri.startswith(('usb:', 'ipp:', 'ipps:', 'dnssd:', 'socket:', 'lpd:')):
        raise ValueError('unsupported-device')
    devices = connection.getDevices(timeout=5)
    if uri not in devices:
        raise ValueError('device-no-longer-discovered')
    if driver == 'everywhere':
        if not uri.startswith(('ipp:', 'ipps:')):
            raise ValueError('driverless-requires-ipp')
    else:
        allowed = ({row['id'] for row in discovery.recommended_drivers(connection, uri)}
                   if request.get('automatic') is True else catalog(connection, request.get('query')))
        if not isinstance(driver, str) or driver not in allowed:
            raise ValueError('driver-not-in-catalog')
    description = str(devices[uri].get('device-info', name))[:160]
    administrator('PrinterAdd', '(sssss)', (name, uri, driver, description, ''))
    administrator('PrinterSetShared', '(sb)', (name, False))
    administrator('PrinterSetEnabled', '(sb)', (name, True))
    administrator('PrinterSetAcceptJobs', '(sbs)', (name, True, ''))
    return inventory(connection)


def handle(request, connection, runner=subprocess.run, administrator=None):
    if not isinstance(request, dict):
        raise ValueError('invalid-request')
    action = request.get('action', 'status')
    if action not in ['status', 'default', 'cancel', 'print', 'test-page', 'maintenance', 'discover', 'drivers', 'configure', 'remove']:
        raise ValueError('unknown-action')
    if administrator is None and action in ('configure', 'remove'):
        administrator = cups_administrator(connection)
    state = inventory(connection)
    if action == 'status':
        return state
    if action == 'drivers':
        uri = request.get('uri')
        if uri is not None:
            state['drivers'] = discovery.recommended_drivers(connection, uri)
        else:
            drivers = catalog(connection, request.get('query'))
            state['drivers'] = [{'id': name, 'model': attrs.get('ppd-make-and-model', name),
                'recommended': False, 'fit': 'manual', 'reason': 'manual-search'}
                for name, attrs in sorted(drivers.items())]
        return state
    if action == 'configure':
        return configure(request, connection, state, administrator)
    if action == 'remove':
        name = request.get('printer')
        if not isinstance(name, str) or not any(row['name'] == name for row in state['printers']):
            raise ValueError('unknown-printer')
        active = connection.getJobs(which_jobs='not-completed', my_jobs=False,
            requested_attributes=['job-printer-uri'])
        if any(unquote(attrs.get('job-printer-uri', '').rsplit('/', 1)[-1]) == name for attrs in active.values()):
            raise ValueError('printer-has-active-jobs')
        administrator('PrinterDelete', '(s)', (name,))
        # Si rimuovono solo le preferenze della coda eliminata, mai quelle
        # di altre stampanti. La vecchia preferenza non deve puntare al vuoto.
        cleanup = runner(['lpoptions', '-x', name], capture_output=True, text=True, timeout=10, check=False)
        state = inventory(connection)
        state['removedPrinter'] = name
        if cleanup.returncode:
            state['warning'] = 'personal-printer-options-cleanup-failed'
        return state
    if action == 'discover':
        # I dettagli dei dispositivi servono al dialogo locale, mai ai log o
        # alla telemetria. Non inviamo indirizzi o identificativi a servizi web.
        found = connection.getDevices(timeout=5)
        state['discovered'], state['grouping'] = discovery.group_devices(found, connection.getPrinters())
        return state
    if action == 'cancel':
        identifier = integer(request.get('job'), 1, 2**31-1)
        # Il pannello amministra solo i lavori dell'utente corrente.
        if not any(row['id'] == identifier for row in state['jobs']):
            raise ValueError('unknown-job')
        connection.cancelJob(identifier)
    else:
        name = request.get('printer')
        printer = next((row for row in state['printers'] if row['name'] == name), None)
        if printer is None:
            raise ValueError('unknown-printer')
        if action == 'default':
            # lpoptions scrive la preferenza personale, non la stampante
            # predefinita di tutto il sistema mediante setDefault/lpadmin.
            result = runner(['lpoptions', '-d', name], capture_output=True, text=True,
                            timeout=10, check=False)
            if result.returncode:
                return {'ok': False, 'code': 'default-failed', 'message': result.stderr.strip()}
        elif action == 'maintenance':
            operation = request.get('operation')
            if operation not in printer['maintenance']:
                raise ValueError('unsupported-maintenance')
            # Non inviare sequenze ESC/P generiche a un modello non verificato.
            # Il filtro CUPS deve pubblicizzare esplicitamente questo comando.
            with tempfile.NamedTemporaryFile(mode='w', suffix='.command') as command_file:
                command_file.write('#CUPS-COMMAND\n' + MAINTENANCE[operation] + '\n')
                command_file.flush()
                identifier = connection.printFile(name, command_file.name,
                    'Liquid DE - ' + operation, {'document-format': 'application/vnd.cups-command'})
            state = inventory(connection)
            state['submittedJob'] = identifier
            return state
        else:
            source = ('/usr/share/cups/data/default-testpage.pdf' if action == 'test-page'
                      else request.get('file'))
            if not isinstance(source, str) or not source or '\0' in source:
                raise ValueError('invalid-file')
            path = Path(source).expanduser().resolve(strict=True)
            if not path.is_file() or not os.access(path, os.R_OK):
                raise ValueError('unreadable-file')
            if path.suffix.lower() not in ['.pdf', '.png', '.jpg', '.jpeg', '.tif', '.tiff', '.txt']:
                raise ValueError('unsupported-file')
            if action == 'test-page':
                request = dict(request, options=dict(request.get('options', {})))
                request['options']['color'] = 'monochrome'
            options = print_options(request, printer)
            identifier = connection.printFile(name, str(path), path.name, options)
            updated = inventory(connection)
            updated['submittedJob'] = identifier
            return updated
    return inventory(connection)


def main():
    if len(sys.argv) == 2:
        try:
            request = json.loads(sys.argv[1])
            if isinstance(request, dict) and request.get('action') == 'packages':
                return repository_packages()
            if isinstance(request, dict) and request.get('action') == 'install-driver':
                return install_driver(request)
            if request == {'action': 'support'}:
                return {'ok': True, 'manager': shutil.which('system-config-printer') or '',
                        'scanner': bool(shutil.which('scanimage'))}
        except (ValueError, TypeError, OSError, RuntimeError, subprocess.TimeoutExpired) as error:
            return {'ok': False, 'code': 'support-operation-failed', 'message': str(error)}
    try:
        import cups
    except ImportError:
        return {'ok': False, 'code': 'cups-module-missing', 'message': 'Python CUPS support is not installed.'}
    try:
        if len(sys.argv) != 2:
            raise ValueError('one-json-request-required')
        request = json.loads(sys.argv[1])
        return handle(request, cups.Connection())
    except (ValueError, OSError, RuntimeError, cups.IPPError, subprocess.TimeoutExpired) as error:
        return {'ok': False, 'code': 'print-operation-failed', 'message': str(error)}


if __name__ == '__main__':
    print(json.dumps(main(), ensure_ascii=False))

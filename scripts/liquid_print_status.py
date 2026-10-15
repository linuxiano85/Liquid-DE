"""Explicit, bounded IPP status reads. Never submit a job or change a device."""
import json
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import quote, unquote, urlsplit

ATTRIBUTES = ['marker-names', 'marker-levels', 'marker-colors', 'marker-types',
    'marker-low-levels', 'marker-high-levels', 'printer-state', 'printer-state-reasons',
    'media-default', 'printer-resolution-supported', 'print-quality-supported']


def resolve_service(name, service_type, domain):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    reply = bus.call_sync('org.freedesktop.Avahi', '/', 'org.freedesktop.Avahi.Server',
        'ResolveService', GLib.Variant('(iisssiu)', (-1, -1, name, service_type, domain, -1, 0)),
        None, Gio.DBusCallFlags.NONE, 1500, None).unpack()
    txt = {}
    for row in reply[9]:
        key, _, value = bytes(row).decode('utf-8', 'replace').partition('=')
        txt[key.lower()] = value
    return reply[7], reply[8], txt.get('rp', 'ipp/print')


def endpoint(uri, resolver=resolve_service):
    if not isinstance(uri, str) or not uri or len(uri) > 4096 or any(ord(c) < 32 for c in uri):
        raise ValueError('unsupported-device-status')
    parsed = urlsplit(uri)
    if parsed.scheme not in ('ipp', 'ipps', 'dnssd') or parsed.username or parsed.password or not parsed.hostname:
        raise ValueError('unsupported-device-status')
    host = unquote(parsed.hostname)
    service = re.fullmatch(r'(.+)\.(_ipps?\._tcp)\.(.+?)\.?', host, re.I)
    if service:
        host, port, resource = resolver(*service.groups())
        secure = service[2].lower() == '_ipps._tcp' or parsed.scheme == 'ipps'
    else:
        if parsed.scheme == 'dnssd':
            raise ValueError('unsupported-device-status')
        host, port, resource = host, parsed.port or 631, unquote(parsed.path or '/')
        secure = parsed.scheme == 'ipps'
    if not isinstance(host, str) or not host or any(ord(c) < 32 or c.isspace() or c in '/@?#' for c in host):
        raise ValueError('unsupported-device-status')
    if type(port) is not int or not 1 <= port <= 65535 or any(ord(c) < 32 for c in resource):
        raise ValueError('unsupported-device-status')
    authority = '[' + host + ']' if ':' in host else host
    target = ('ipps' if secure else 'ipp') + '://' + authority + ':' + str(port) + '/' + quote(resource.lstrip('/'), safe='/')
    return host, port, secure, target


def query(uri):
    import cups
    host, port, secure, target = endpoint(uri)
    cups.setPasswordCB2(lambda *args: None)
    connection = cups.Connection(host=host, port=port,
        encryption=cups.HTTP_ENCRYPT_ALWAYS if secure else cups.HTTP_ENCRYPT_IF_REQUESTED)
    return connection.getPrinterAttributes(uri=target, requested_attributes=ATTRIBUTES)


def read(uri, runner=subprocess.run):
    # The worker bounds DNS, TCP, TLS and IPP together, including libcups calls
    # that do not expose a per-request timeout through pycups.
    try:
        result = runner([sys.executable, '-I', str(Path(__file__).resolve()), uri],
            capture_output=True, text=True, timeout=8, check=False)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError('device-status-timeout') from error
    if result.returncode:
        raise RuntimeError('device-status-unavailable')
    data = json.loads(result.stdout)
    if not isinstance(data, dict):
        raise RuntimeError('invalid-device-status')
    return data


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('one-device-required')
        print(json.dumps(query(sys.argv[1])))
    except Exception:
        # Network addresses and device errors remain outside user-facing logs.
        sys.exit(1)

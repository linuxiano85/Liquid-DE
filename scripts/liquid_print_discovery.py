"""Ricerca e scelta del driver: identità hardware, corrispondenze verificabili."""
import re
import time
from urllib.parse import parse_qs, unquote, urlsplit
from uuid import UUID


def device_uuid(uri, resolver=None):
    """Non raggruppare mai due stampanti solo perché hanno lo stesso modello."""
    try:
        parsed = urlsplit(uri)
    except ValueError:
        return None
    value = parse_qs(parsed.query).get('uuid', [''])[0]
    if not value and resolver:
        host = unquote(parsed.hostname or '')
        match = re.fullmatch(r'(.+)\.(_ipps?\._tcp)\.(.+?)\.?', host, re.I)
        if match:
            try:
                value = resolver(*match.groups()) or ''
            except Exception:
                return None
    try:
        return str(UUID(value.removeprefix('urn:uuid:')))
    except (ValueError, AttributeError):
        return None


def resolve_service(name, service_type, domain):
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
    reply = bus.call_sync('org.freedesktop.Avahi', '/', 'org.freedesktop.Avahi.Server',
        'ResolveService', GLib.Variant('(iisssiu)', (-1, -1, name, service_type, domain, -1, 0)),
        None, Gio.DBusCallFlags.NONE, 1500, None)
    for entry in reply.unpack()[9]:
        text = bytes(entry).decode('utf-8', errors='replace')
        if text.lower().startswith('uuid='):
            return text.split('=', 1)[1]
    return None


def scp_groups(devices):
    # Lo stesso servizio pubblico interrogato da KDE. Non apriamo la GUI GTK
    # di ricerca/download dei driver per ottenere un semplice raggruppamento.
    from gi.repository import Gio, GLib
    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    data = {uri: {key: str(value) for key, value in attrs.items()} for uri, attrs in devices.items()}
    reply = bus.call_sync('org.fedoraproject.Config.Printing', '/org/fedoraproject/Config/Printing',
        'org.fedoraproject.Config.Printing', 'GroupPhysicalDevices',
        GLib.Variant('(a{sa{ss}})', (data,)), GLib.VariantType('(aas)'),
        Gio.DBusCallFlags.NONE, 7000, None)
    return reply.unpack()[0]


def group_devices(found, configured=None, grouper=scp_groups, resolver=resolve_service):
    devices = {uri: attrs for uri, attrs in found.items()
               if uri.startswith(('usb:', 'ipp:', 'ipps:', 'dnssd:', 'socket:', 'lpd:'))}
    parents = {uri: uri for uri in devices}
    identities = {}
    deadline = time.monotonic() + 4
    for uri in devices:
        identities[uri] = device_uuid(uri, resolver if time.monotonic() < deadline else None)
    def root(uri):
        while parents[uri] != uri:
            uri = parents[uri]
        return uri
    def merge(left, right):
        a, b = root(left), root(right)
        ids = {identities[u] for u in devices if root(u) in (a, b) and identities[u]}
        # Anche un suggerimento del servizio non prevale su due UUID distinti.
        if len(ids) <= 1:
            parents[b] = a
    by_uuid = {}
    for uri, identity in identities.items():
        if identity:
            if identity in by_uuid:
                merge(uri, by_uuid[identity])
            by_uuid[identity] = uri
    grouping = 'identity'
    try:
        for group in grouper(devices):
            members = [uri for uri in group if uri in devices]
            for member in members[1:]:
                merge(members[0], member)
    except Exception:
        grouping = 'identity-only'
    groups = {}
    for uri in devices:
        groups.setdefault(root(uri), []).append(uri)
    priority = {'usb': 0, 'ipps': 1, 'ipp': 2, 'dnssd': 3, 'socket': 4, 'lpd': 5}
    result = []
    for members in groups.values():
        members.sort(key=lambda uri: (priority.get(urlsplit(uri).scheme, 9), uri))
        uri = members[0]
        attrs = devices[uri]
        queues = sorted(name for name, data in (configured or {}).items() if data.get('device-uri') in members)
        result.append({'uri': uri, 'description': attrs.get('device-info', ''),
            'model': attrs.get('device-make-and-model', ''),
            'kind': 'usb' if uri.startswith('usb:') else 'network',
            'connections': [{'uri': member, 'kind': urlsplit(member).scheme} for member in members],
            'configured': bool(queues), 'queues': queues})
    return sorted(result, key=lambda row: row['description'].casefold()), grouping


def describe_driver(connection, name):
    import cups
    import cupshelpers
    from pathlib import Path
    temporary = Path(connection.getServerPPD(name))
    try:
        ppd = cups.PPD(str(temporary))
        options = []
        def visit(groups):
            for group in groups:
                for option in group.options:
                    if option.keyword == 'PageRegion':
                        continue  # Duplicato tecnico di PageSize, non un'altra funzione.
                    options.append({'key': option.keyword, 'title': getattr(option, 'text', option.keyword),
                        'choices': [{'value': row['choice'], 'label': row['text']} for row in option.choices]})
                visit(getattr(group, 'subgroups', []))
        visit(ppd.optionGroups)
        return {'verified': True, 'options': options, 'missingFilters': cupshelpers.missingExecutables(ppd)}
    except Exception as error:
        return {'verified': False, 'options': [], 'missingFilters': [], 'error': str(error)}
    finally:
        temporary.unlink(missing_ok=True)


def recommended_drivers(connection, uri):
    try:
        import cupshelpers
        from cupshelpers.ppds import PPDs
    except ImportError as error:
        raise RuntimeError('driver-recommendation-support-missing') from error
    if not isinstance(uri, str) or not uri or len(uri) > 4096:
        raise ValueError('unsupported-device')
    devices = connection.getDevices(timeout=5)
    if uri not in devices:
        raise ValueError('device-no-longer-discovered')
    device = devices[uri]
    model = device.get('device-make-and-model', '')
    identifier = cupshelpers.parseDeviceID(device.get('device-id', ''))
    if not identifier.get('MFG') or not identifier.get('MDL'):
        from cupshelpers.ppds import ppdMakeModelSplit
        manufacturer, product = ppdMakeModelSplit(model)
        identifier.update(MFG=manufacturer, MDL=product)
    ppds = PPDs(connection.getPPDs(), language='en')
    fit = ppds.getPPDNamesFromDeviceID(identifier.get('MFG', ''), identifier.get('MDL', ''),
        identifier.get('DES', ''), identifier.get('CMD', []), uri, model)
    order = ppds.orderPPDNamesByPreference(list(fit), make_and_model=model, devid=identifier, fit=fit)
    rows = []
    for name in order:
        attrs = ppds.ppds[name]
        if fit[name] == 'none' or name.startswith('driverless-fax:') or attrs.get('ppd-type') == 'fax':
            continue
        rows.append({'id': name, 'model': attrs.get('ppd-make-and-model', name),
            'fit': fit[name], 'recommended': False, 'reason': 'model-match'})
    # «Close» non viene trasformato in «Consigliato»: un modello simile può
    # usare un linguaggio diverso e produrre pagine vuote o caratteri casuali.
    exact = [row for row in rows if row['fit'] in ('exact', 'exact-cmd')]
    for row in exact[:4]:
        try:
            row['details'] = describe_driver(connection, row['id'])
        except Exception as error:
            row['details'] = {'verified': False, 'options': [], 'missingFilters': [], 'error': str(error)}
    usable = [row for row in exact if row.get('details', {}).get('verified')
              and not row['details']['missingFilters']]
    if usable:
        usable[0]['recommended'] = True
        usable[0]['reason'] = 'model-and-language' if usable[0]['fit'] == 'exact-cmd' else 'exact-model'
    return rows

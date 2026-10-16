"""Group SANE links only when discovery identifies the same eSCL endpoint."""
import ipaddress
import re
from urllib.parse import urlsplit,unquote


def host_key(value):
    value=unquote(value).strip('[]')
    try:return str(ipaddress.ip_address(value))
    except ValueError:return value.casefold().rstrip('.')


def endpoint(uri):
    parsed=urlsplit(uri)
    if parsed.scheme not in ('http','https') or not parsed.hostname:return None
    return (host_key(parsed.hostname),parsed.port or (443 if parsed.scheme=='https' else 80),parsed.path.rstrip('/') or '/eSCL')


def services(output):
    rows=[]
    for line in output.splitlines():
        match=re.fullmatch(r'\s*(.*?)\s*=\s*(https?://\S+),\s*(eSCL|WSD)\s*',line)
        if match:
            try:key=endpoint(match[2])
            except ValueError:continue
            if key:rows.append({'name':match[1],'endpoint':key,'protocol':match[3]})
    return rows


def group(devices,advertised):
    rows=[]
    for device in devices:
        name=device['name'];identity=None
        if name.startswith('escl:'):
            try:identity=endpoint(name[5:])
            except ValueError:pass
        elif name.startswith('airscan:e'):
            display=name.split(':',2)[-1]
            address=re.search(r'(?:^|\s)ip=([^\s,]+)',device.get('type',''))
            candidates={row['endpoint'] for row in advertised if row['name']==display and row['protocol']=='eSCL'
                and address and row['endpoint'][0]==host_key(address[1])}
            if len(candidates)==1:identity=next(iter(candidates))
        key=('endpoint',identity) if identity else ('device',name)
        existing=next((row for row in rows if row['_key']==key),None)
        connection={'id':name,'backend':name.split(':',1)[0]}
        if existing:existing['connections'].append(connection)
        else:rows.append({'_key':key,'id':name,'name':device.get('model') or name,
            'vendor':device.get('vendor',''),'connections':[connection]})
    for row in rows:
        row['connections'].sort(key=lambda item:(not item['id'].startswith('airscan:'),item['id']))
        row['id']=row['connections'][0]['id'];del row['_key']
    return sorted(rows,key=lambda row:row['name'].casefold())

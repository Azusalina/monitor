"""Read nearby networks/devices; connect saved entries only on explicit clicks."""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import threading
import time

SETTINGS_COMMANDS = {'proton': ['protonvpn-app'],
                     'wifi': ['kcmshell6', 'kcm_networkmanagement'],
                     'bluetooth': ['kcmshell6', 'kcm_bluetooth']}


def run(args, trim=True):
    output = subprocess.run(args,capture_output=True,text=True,timeout=3,check=True,
                            env={**os.environ,'LC_ALL':'C'}).stdout
    return output.strip() if trim else output.removesuffix('\n')


def unbox(value):
    if isinstance(value,dict):
        if 'type' in value and 'data' in value:
            return unbox(value['data'])
        return {key:unbox(item) for key,item in value.items()}
    if isinstance(value,list):
        return [unbox(item) for item in value]
    return value


def dbus(*args):
    value = unbox(json.loads(run(['busctl','--system','--json=short','--timeout=1',*args])))
    return value[0] if isinstance(value,list) and len(value) == 1 else value


def split_nmcli(line):
    """NetworkManager's terse format escapes both colons and backslashes."""
    parts = []
    text = ''
    escaped = False
    for character in line:
        if escaped:
            text += character
            escaped = False
        elif character == '\\':
            escaped = True
        elif character == ':':
            parts.append(text); text = ''
        else:
            text += character
    parts.append(text)
    return parts


def parse_active(text):
    vpn = None
    wifi = None
    for line in text.splitlines():
        fields = split_nmcli(line)
        if len(fields) < 4:
            continue
        name, uuid, kind, device = fields[:4]
        if kind in ('vpn','wireguard') and name.lower().startswith('protonvpn'):
            vpn = {'connected':True,'server':name.removeprefix('ProtonVPN ').strip()}
        elif kind == '802-11-wireless':
            wifi = {'connected':True,'network':name,'device':device}
    return vpn or {'connected':False,'server':''}, wifi or {'connected':False,'network':''}


def proton_settings():
    path = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home()/'.config'))) / 'Proton/VPN/settings.json'
    try:
        if path.stat().st_size > 100_000:
            return None
        data = json.loads(path.read_text())
        value = data.get('killswitch')
        return {0:'Off',1:'Standard',2:'Advanced'}.get(value)
    except (OSError,ValueError,AttributeError):
        return None


def network_state():
    proton = {'connected':None,'server':'','kill_switch':proton_settings(),
              'can_open':bool(shutil.which('protonvpn-app'))}
    wifi = {'enabled':None,'connected':None,'network':'','can_open':bool(shutil.which('kcmshell6'))}
    try:
        active = run(['nmcli','-t','-f','NAME,UUID,TYPE,DEVICE','connection','show','--active'])
        vpn, wireless = parse_active(active)
        proton.update(vpn)
        wifi.update(wireless)
        wifi['enabled'] = dbus('get-property','org.freedesktop.NetworkManager','/org/freedesktop/NetworkManager',
                               'org.freedesktop.NetworkManager','WirelessEnabled')
    except (OSError,subprocess.SubprocessError,ValueError,TypeError):
        pass
    try:
        wifi['networks'] = wifi_networks(run(['nmcli','-t','-f','SSID,SIGNAL,SECURITY,IN-USE','device','wifi','list','--rescan','no']))
    except (OSError,subprocess.SubprocessError,ValueError):
        wifi['networks'] = []
    try:
        wifi['saved'] = saved_wifi_cached()
    except (OSError,subprocess.SubprocessError,ValueError,TypeError):
        wifi['saved'] = []
    return proton,wifi


_saved_wifi = {'at':0, 'rows':[]}


def saved_wifi_cached():
    """Read only profile metadata, bounded and cached; never request secrets."""
    now = time.monotonic()
    if _saved_wifi['at'] and now - _saved_wifi['at'] < 60:
        return _saved_wifi['rows']
    profiles = []
    for line in run(['nmcli','-t','-f','UUID,TYPE,TIMESTAMP','connection','show']).splitlines():
        fields = split_nmcli(line)
        if len(fields) == 3 and fields[1] == '802-11-wireless' and re.fullmatch(r'[0-9a-fA-F-]{36}',fields[0]):
            stamp = int(fields[2] or 0)
            if stamp > 0:
                profiles.append((stamp,fields[0]))
    rows = []
    seen = set()
    for stamp, uuid in sorted(profiles,reverse=True)[:64]:
        try:
            ssid = run(['nmcli','--escape','no','-g','802-11-wireless.ssid','connection','show','uuid',uuid], trim=False)
            if ssid and ssid not in seen:
                rows.append({'id':ssid,'name':ssid});seen.add(ssid)
        except (OSError,subprocess.SubprocessError):
            continue
    _saved_wifi.update(at=now,rows=rows)
    return rows


def wifi_networks(text):
    networks = {}
    for line in text.splitlines():
        fields = split_nmcli(line)
        if len(fields) != 4 or not fields[0]:
            continue
        ssid, signal, security, active = fields
        try: signal = max(0, min(100, int(signal)))
        except ValueError: continue
        row = {'id':ssid, 'name':ssid, 'signal':signal, 'available':True, 'connected':active == '*', 'security':security}
        if ssid not in networks or signal > networks[ssid]['signal']:
            row['connected'] = row['connected'] or networks.get(ssid, {}).get('connected', False)
            networks[ssid] = row
        elif row['connected']:
            networks[ssid]['connected'] = True
    return sorted(networks.values(), key=lambda row:(not row['connected'], -row['signal'], row['name']))[:100]


def parse_bluetooth(objects):
    adapters = []
    connected = []
    known = []
    for path,interfaces in objects.items():
        if 'org.bluez.Adapter1' in interfaces:
            props = interfaces['org.bluez.Adapter1']
            adapters.append({'name':props.get('Alias') or 'Bluetooth','enabled':bool(props.get('Powered'))})
        if 'org.bluez.Device1' in interfaces:
            props = interfaces['org.bluez.Device1']
            address = props.get('Address', '')
            adapter = objects.get(props.get('Adapter', ''), {}).get('org.bluez.Adapter1', {})
            if re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', address):
                known.append({'id':address.upper(), 'name':props.get('Alias') or props.get('Name') or address,
                              'connected':bool(props.get('Connected')), 'paired':bool(props.get('Paired')),
                              'available':True if props.get('Connected') or (adapter.get('Discovering') and 'RSSI' in props) else None})
            if props.get('Connected'):
                connected.append(props.get('Alias') or props.get('Name') or 'Connected device')
    return {'enabled': any(a['enabled'] for a in adapters) if adapters else None,
            'adapters':len(adapters),'devices':connected,'known':known[:100]}


def connect_saved(kind, identifier, action='connect'):
    if action not in ('connect','disconnect'):
        raise ValueError('Unknown connection action')
    if not isinstance(identifier, str) or not identifier or len(identifier) > 256:
        raise ValueError('Invalid connection')
    if kind == 'wifi':
        profiles = run(['nmcli','-t','-f','UUID,TYPE','connection','show', *(['--active'] if action == 'disconnect' else [])])
        for line in profiles.splitlines():
            fields = split_nmcli(line)
            if len(fields) == 2 and fields[1] == '802-11-wireless' and re.fullmatch(r'[0-9a-fA-F-]{36}', fields[0]):
                ssid = run(['nmcli','--escape','no','-g','802-11-wireless.ssid','connection','show','uuid',fields[0]], trim=False)
                if ssid == identifier:
                    subprocess.run(['nmcli','--wait','8','connection','up' if action == 'connect' else 'down','uuid',fields[0]], capture_output=True, timeout=10, check=True)
                    return
        if action == 'disconnect':
            raise ValueError('Saved Wi-Fi profile no longer exists')
        open_settings('wifi')  # Native secret agent/pairing UI owns credentials.
    elif kind == 'bluetooth' and re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}', identifier):
        objects = dbus('call','org.bluez','/','org.freedesktop.DBus.ObjectManager','GetManagedObjects')
        for path, interfaces in objects.items():
            props = interfaces.get('org.bluez.Device1', {})
            if props.get('Address', '').upper() == identifier.upper():
                if bool(props.get('Connected')) == (action == 'connect'): return
                if action == 'connect' and not props.get('Paired'): break
                subprocess.run(['busctl','--system','--timeout=8','call','org.bluez',path,'org.bluez.Device1','Connect' if action == 'connect' else 'Disconnect'], capture_output=True, timeout=10, check=True)
                return
        if action == 'disconnect':
            raise ValueError('Bluetooth device no longer exists')
        open_settings('bluetooth')
    else:
        raise ValueError('Unknown connection kind')


def bluetooth_state():
    result = {'enabled':None,'adapters':0,'devices':[], 'can_open':bool(shutil.which('kcmshell6'))}
    try:
        result.update(parse_bluetooth(dbus('call','org.bluez','/','org.freedesktop.DBus.ObjectManager','GetManagedObjects')))
    except (OSError,subprocess.SubprocessError,ValueError,TypeError,AttributeError):
        pass
    return result


def open_settings(target):
    if target not in SETTINGS_COMMANDS:
        raise ValueError('Unknown settings target')
    command = SETTINGS_COMMANDS[target]
    if not shutil.which(command[0]):
        raise RuntimeError('Native settings application is not installed')
    # Fixed native application destinations; no user-supplied commands or network mutations.
    process = subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL,start_new_session=True)
    threading.Thread(target=process.wait,daemon=True).start()


class ConnectivityCollector:
    def __init__(self):
        self.lock = threading.Lock()
        self.stop = threading.Event()
        self.snapshot = {'proton':{},'wifi':{},'bluetooth':{},'checked_at':None,'stale':True}
        self.thread = threading.Thread(target=self.collect,daemon=True,name='connectivity')

    def collect(self):
        while not self.stop.is_set():
            started = time.monotonic()
            proton,wifi = network_state()
            bluetooth = bluetooth_state()
            with self.lock:
                self.snapshot = {'proton':proton,'wifi':wifi,'bluetooth':bluetooth,'checked_at':time.time(),'stale':False}
            self.stop.wait(max(1,5-(time.monotonic()-started)))

    def get(self):
        with self.lock:
            value = json.loads(json.dumps(self.snapshot))
        value['stale'] = not value['checked_at'] or time.time()-value['checked_at'] > 20
        return value

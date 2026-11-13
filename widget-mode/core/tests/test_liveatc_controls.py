import io
import json
from pathlib import Path
import subprocess
import sys
import threading
import unittest
from http.server import ThreadingHTTPServer
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).parents[1]/'backend'))
import liveatc as a
import connectivity as c
import monitor_service as m
from widget_config import validate

class LiveAtcTests(unittest.TestCase):
    def test_listen_and_playlist_resolution(self):
        self.assertEqual(a.station_url('https://www.liveatc.net/hlisten.php?mount=kjfk_twr&icao=kjfk'),'https://www.liveatc.net/play/kjfk_twr.pls')
        with patch.object(a,'urlopen',return_value=io.BytesIO(b'[playlist]\nFile1=https://d.liveatc.net/kjfk_twr\n')):
            self.assertEqual(a.resolve('https://www.liveatc.net/play/kjfk_twr.pls'),'https://d.liveatc.net/kjfk_twr')
        for value in ('file:///etc/passwd','https://liveatc.net.evil/a','http://evil/liveatc.net','https://user@liveatc.net/a'):
            with self.assertRaises(ValueError):a.station_url(value)
        with patch.object(a,'urlopen',return_value=io.BytesIO(b'File1=https://evil/stream')):
            with self.assertRaises(ValueError):a.resolve('https://liveatc.net/play/a.pls')

    def test_search_deduplicates_and_denial_not_bypassed(self):
        html=b'<a href="/hlisten.php?mount=abc_twr&amp;icao=KABC">Listen</a><a href="/play/abc_twr.pls">PLS</a>'
        with patch.object(a,'urlopen',return_value=io.BytesIO(html)) as fetch:
            self.assertEqual(a.search('kabc'),[{'name':'abc_twr','url':'https://www.liveatc.net/play/abc_twr.pls'}])
            self.assertIn('icao=KABC',fetch.call_args.args[0].full_url)
        with patch.object(a,'urlopen',side_effect=HTTPError('https://liveatc.net',403,'Forbidden',{},None)) as fetch:
            with self.assertRaises(HTTPError):a.search('KABC')
            self.assertEqual(fetch.call_count,1)
        for code in ('','../../','KJFK&url=x'):
            with self.assertRaises(ValueError):a.search(code)

    def test_pin_and_station_config_validation(self):
        settings={'wifiPins':json.dumps([{'id':'A: B','name':'A: B'}]),'bluetoothPins':json.dumps([{'id':'AA:BB:CC:DD:EE:FF','name':'Headset'}]),'noteShortcut':'Meta+Ctrl+N','liveAtcUrl':'https://d.liveatc.net/test'}
        self.assertEqual(validate(settings),settings)
        for pins in ('{}','[{}]',json.dumps([{'id':'a','name':'b'}]*13)):
            with self.assertRaises(ValueError):validate({'wifiPins':pins})

    def test_wifi_scan_escapes_dedupes_and_saved_uuid_only(self):
        rows=c.wifi_networks('A\\:B:20:WPA2:\nA\\:B:80:WPA2:*\nOther:60:WPA3:\n:99::')
        self.assertEqual([p['id'] for p in rows],['A:B','Other'])
        self.assertTrue(rows[0]['connected']);self.assertEqual(rows[0]['signal'],80)
        uuid='12345678-1234-1234-1234-123456789abc'
        with patch.object(c,'run',side_effect=[uuid+':802-11-wireless','A:B']),patch.object(c.subprocess,'run') as run:
            c.connect_saved('wifi','A:B')
            self.assertEqual(run.call_args.args[0],['nmcli','--wait','8','connection','up','uuid',uuid])
        with patch.object(c,'run',return_value=''),patch.object(c,'open_settings') as opened:
            c.connect_saved('wifi','new');opened.assert_called_once_with('wifi')

    def test_bluetooth_unknown_is_not_claimed_online(self):
        objects={'/a':{'org.bluez.Adapter1':{'Powered':True}},'/d':{'org.bluez.Device1':{'Address':'AA:BB:CC:DD:EE:FF','Alias':'Headset','Paired':True,'RSSI':-50,'Adapter':'/a'}}}
        self.assertIsNone(c.parse_bluetooth(objects)['known'][0]['available'])
        objects['/a']['org.bluez.Adapter1']['Discovering']=True
        self.assertTrue(c.parse_bluetooth(objects)['known'][0]['available'])
        with patch.object(c,'dbus',return_value=objects),patch.object(c.subprocess,'run') as run:
            c.connect_saved('bluetooth','AA:BB:CC:DD:EE:FF')
            self.assertEqual(run.call_args.args[0][-2:],['org.bluez.Device1','Connect'])

class MediaApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),m.Handler)
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
    @classmethod
    def tearDownClass(cls):cls.server.shutdown();cls.server.server_close()
    def post(self,data):
        req=Request(f'http://127.0.0.1:{self.server.server_port}/media/control',data=json.dumps(data).encode(),headers={'X-Monitor-Client':'plasma-widget','Content-Type':'application/json'})
        try:
            with urlopen(req,timeout=2) as response:return response.status,json.load(response)
        except HTTPError as error:return error.code,json.load(error)
    def test_capabilities_and_track_identity(self):
        name='org.mpris.MediaPlayer2.Test';props={'CanControl':True,'CanSeek':True,'CanGoNext':True,'CanGoPrevious':True,'CanPause':True,'Metadata':{'mpris:trackid':'/track/1'}}
        with patch.object(m,'player_names',return_value=[name]),patch.object(m,'bus',return_value=props),patch.object(m,'command') as command:
            for action,method in [('next','Next'),('previous','Previous'),('pause','Pause')]:
                self.assertEqual(self.post({'service':name,'action':action})[0],200)
                self.assertEqual(command.call_args.args[0][-1],method)
            self.assertEqual(self.post({'service':name,'action':'position','position':42.5,'track_id':'/track/1'})[0],200)
            self.assertEqual(command.call_args.args[0][-4:],['SetPosition','ox','/track/1','42500000'])
            count=command.call_count
            self.assertEqual(self.post({'service':name,'action':'position','position':3,'track_id':'/track/old'})[0],409)
            self.assertEqual(self.post({'service':name,'action':'evil'})[0],400)
            props['CanSeek']=False
            self.assertEqual(self.post({'service':name,'action':'position','position':3,'track_id':'/track/1'})[0],409)
            self.assertEqual(command.call_count,count)

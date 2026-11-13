import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'backend'))
import connectivity as c


class ConnectivityTests(unittest.TestCase):
    def test_escaped_wifi_and_proton_detection(self):
        text = 'Office\\: room\\\\2:PRIVATE_UUID:802-11-wireless:wlan0\nProtonVPN TW#32:OTHER_UUID:vpn:tun0'
        proton, wifi = c.parse_active(text)
        self.assertEqual(proton, {'connected': True, 'server': 'TW#32'})
        self.assertEqual(wifi['network'], 'Office: room\\2')
        self.assertNotIn('UUID', json.dumps([proton, wifi]))

    def test_unrelated_vpn_and_ipv6_protection_are_not_proton_connection(self):
        proton, wifi = c.parse_active('pvpn-killswitch-ipv6:1:dummy:pvpnksintrf0\nWork VPN:2:vpn:tun0')
        self.assertFalse(proton['connected'])
        self.assertFalse(wifi['connected'])

    def test_kill_switch_is_configured_mode_not_interface_inference(self):
        with tempfile.TemporaryDirectory() as temp, patch.dict(os.environ, {'XDG_CONFIG_HOME': temp}):
            path = Path(temp)/'Proton/VPN/settings.json'
            path.parent.mkdir(parents=True)
            for value, label in [(0, 'Off'), (1, 'Standard'), (2, 'Advanced'), (99, None)]:
                path.write_text(json.dumps({'killswitch': value, 'private': 'SECRET'}))
                self.assertEqual(c.proton_settings(), label)

    def test_bluetooth_only_connected_device_names(self):
        state = c.parse_bluetooth({
            '/org/bluez/hci0': {'org.bluez.Adapter1': {'Powered': True, 'Address': 'PRIVATE_MAC'}},
            '/org/bluez/hci0/dev_1': {'org.bluez.Device1': {'Connected': True, 'Alias': 'Headphones', 'Address': 'PRIVATE_MAC'}},
            '/org/bluez/hci0/dev_2': {'org.bluez.Device1': {'Connected': False, 'Alias': 'Other'}}})
        self.assertEqual(state['devices'], ['Headphones'])
        self.assertTrue(state['enabled'])
        self.assertNotIn('PRIVATE', json.dumps(state))
        self.assertIsNone(c.parse_bluetooth({})['enabled'])

    def test_fixed_native_destinations_and_reject_commands(self):
        with patch.object(c.shutil, 'which', return_value='/usr/bin/native'), patch.object(c.subprocess, 'Popen') as launch:
            for target, expected in c.SETTINGS_COMMANDS.items():
                c.open_settings(target)
                self.assertEqual(launch.call_args.args[0], expected)
            with self.assertRaises(ValueError):
                c.open_settings('wifi; nmcli radio wifi off')
            self.assertEqual(launch.call_count, 3)
        with patch.object(c.shutil, 'which', return_value=None):
            with self.assertRaises(RuntimeError):
                c.open_settings('wifi')


if __name__ == '__main__':
    unittest.main()

class QuickConnectionTests(unittest.TestCase):
    def test_wifi_disconnect_targets_only_matching_active_profile(self):
        uuid='12345678-1234-1234-1234-123456789abc'
        with patch.object(c,'run',side_effect=[uuid+':802-11-wireless',' Home:WiFi ']) as read,patch.object(c.subprocess,'run') as change:
            c.connect_saved('wifi',' Home:WiFi ','disconnect')
            self.assertEqual(read.call_args_list[0].args[0][-1],'--active')
            self.assertIn('--escape',read.call_args_list[1].args[0])
            self.assertFalse(read.call_args_list[1].kwargs['trim'])
            self.assertEqual(change.call_args.args[0],['nmcli','--wait','8','connection','down','uuid',uuid])
        with patch.object(c,'run',return_value=''),patch.object(c.subprocess,'run') as change:
            with self.assertRaises(ValueError):c.connect_saved('wifi','Gone','disconnect')
            change.assert_not_called()

    def test_bluetooth_disconnect_does_not_forget_or_power_off(self):
        objects={'/org/bluez/hci0/dev_AA':{'org.bluez.Device1':{'Address':'AA:BB:CC:DD:EE:FF','Connected':True,'Paired':True}}}
        with patch.object(c,'dbus',return_value=objects),patch.object(c.subprocess,'run') as change:
            c.connect_saved('bluetooth','AA:BB:CC:DD:EE:FF','disconnect')
            self.assertEqual(change.call_args.args[0][-2:],['org.bluez.Device1','Disconnect'])
            objects['/org/bluez/hci0/dev_AA']['org.bluez.Device1']['Connected']=False
            change.reset_mock();c.connect_saved('bluetooth','AA:BB:CC:DD:EE:FF','disconnect');change.assert_not_called()
        for action in ('toggle','off','; rm'):
            with self.assertRaises(ValueError):c.connect_saved('wifi','Home',action)

    def test_common_wifi_uses_recent_metadata_and_cache_without_secrets(self):
        a='12345678-1234-1234-1234-123456789abc';b='23456789-1234-1234-1234-123456789abc'
        with patch.dict(c._saved_wifi,at=0,rows=[]),patch.object(c,'run',side_effect=[f'{a}:802-11-wireless:5\n{b}:802-11-wireless:99','Recent','Older']) as read:
            rows=c.saved_wifi_cached();self.assertEqual([r['name'] for r in rows],['Recent','Older'])
            self.assertEqual(c.saved_wifi_cached(),rows);self.assertEqual(read.call_count,3)
            self.assertNotIn('secret',str(read.call_args_list).lower())

class HistoryEligibilityTests(unittest.TestCase):
    def test_never_used_saved_profile_is_not_eligible(self):
        a='12345678-1234-1234-1234-123456789abc';b='23456789-1234-1234-1234-123456789abc'
        with patch.dict(c._saved_wifi,at=0,rows=[]),patch.object(c,'run',side_effect=[f'{a}:802-11-wireless:0\n{b}:802-11-wireless:99','Used']) as read:
            self.assertEqual(c.saved_wifi_cached(),[{'id':'Used','name':'Used'}])
            self.assertEqual(read.call_count,2)

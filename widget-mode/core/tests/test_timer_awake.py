from pathlib import Path
import sys,tempfile,unittest
from unittest.mock import MagicMock,patch
sys.path.insert(0,str(Path(__file__).parents[1]/'backend'))
from timers import TimerManager
from timecount import TimecountStore
from power import AwakeManager,AutomaticAwake

class TimerActivityTests(unittest.TestCase):
    def test_countdown_completion_stopwatch_pause_and_expiry(self):
        now=[0.];manager=TimerManager(clock=lambda:now[0]);token=manager.create(3,0)['session']
        self.assertFalse(manager.any_running());manager.control(token,'countdown','start');self.assertTrue(manager.any_running())
        now[0]=4;self.assertFalse(manager.any_running())
        manager.control(token,'stopwatch','start');self.assertTrue(manager.any_running())
        manager.control(token,'stopwatch','pause');self.assertFalse(manager.any_running())
        other=manager.create(30,0)['session'];manager.control(other,'stopwatch','start')
        now[0]=63;self.assertTrue(manager.any_running())
        now[0]=65;self.assertFalse(manager.any_running());self.assertNotIn(other,manager.sessions)

    def test_timecount_activity_does_not_extend_lease_or_change_history(self):
        now=[0.]
        with tempfile.TemporaryDirectory() as tmp:
            store=TimecountStore(Path(tmp)/'history.sqlite3',monotonic=lambda:now[0])
            payload={'profile':'default','client':'test','projects':[{'id':'study','name':'Study'}],'project':'study'}
            try:
                self.assertFalse(store.any_running());store.control({**payload,'action':'start'});self.assertTrue(store.any_running())
                now[0]=5;self.assertTrue(store.any_running());now[0]=7;self.assertFalse(store.any_running())
                store.control({**payload,'action':'start'});self.assertTrue(store.any_running())
                store.control({**payload,'action':'pause'});self.assertFalse(store.any_running())
            finally:store.shutdown()

class AutoAwakeTests(unittest.TestCase):
    def test_automatic_release_retains_manual_lease(self):
        now=[0.];running=[False];manager=AwakeManager(clock=lambda:now[0]);process=MagicMock();process.poll.return_value=None;process.stdout.readline.return_value=b'ready\n'
        auto=AutomaticAwake(manager,lambda:running[0])
        with patch('power.subprocess.Popen',return_value=process),patch('power.select.select',return_value=([process.stdout],[],[])):
            manual=manager.control('enable')['token'];running[0]=True;auto.update()
            token=auto.token;self.assertTrue(auto.get()['active']);self.assertNotEqual(manual,token)
            now[0]=5;auto.update();self.assertEqual(auto.token,token)
            running[0]=False;auto.update();self.assertEqual(set(manager.leases),{manual});process.terminate.assert_not_called()
            manager.control('disable',manual);process.terminate.assert_called_once()

    def test_late_acquire_failure_recovery_and_shutdown(self):
        running=[True];manager=MagicMock();manager.control.return_value={'token':'auto'}
        auto=AutomaticAwake(manager,lambda:running[0])
        def late(action,*args):
            if action=='enable':running[0]=False
            return {'token':'late'}
        manager.control.side_effect=late;auto.update();self.assertFalse(auto.get()['active']);manager.control.assert_any_call('disable','late')
        running[0]=True;manager.control.side_effect=RuntimeError('No KDE');auto.update();self.assertTrue(auto.get()['error'])
        manager.control.side_effect=None;auto.update();self.assertTrue(auto.get()['active'])
        auto.shutdown();manager.control.assert_called_with('disable','auto')

    def test_union_of_timer_sessions_and_timecount(self):
        from types import SimpleNamespace
        from monitor_service import Telemetry
        now=[0.];timers=TimerManager(clock=lambda:now[0]);pair=timers.create(20,0)['session']
        with tempfile.TemporaryDirectory() as tmp:
            store=TimecountStore(Path(tmp)/'history.sqlite3',monotonic=lambda:now[0])
            state=SimpleNamespace(timers=timers,_timecount=store);manager=MagicMock();manager.control.return_value={'token':'shared'}
            auto=AutomaticAwake(manager,lambda:Telemetry.any_timer_running(state))
            payload={'profile':'default','client':'test','projects':[{'id':'study','name':'Study'}],'project':'study'}
            try:
                timers.control(pair,'countdown','start');auto.update();self.assertTrue(auto.get()['active'])
                store.control({**payload,'action':'start'});timers.control(pair,'countdown','pause');auto.update();self.assertTrue(auto.get()['active'])
                store.control({**payload,'action':'pause'});auto.update();self.assertFalse(auto.get()['active'])
                manager.control.assert_called_with('disable','shared')
            finally:auto.shutdown();store.shutdown()

    def test_invalidated_helper_lease_is_reacquired(self):
        manager=MagicMock();manager.control.return_value={'token':'new'};auto=AutomaticAwake(manager,lambda:True);auto.token='expired'
        def action(kind,*args):
            if kind=='heartbeat':raise KeyError('expired')
            return {'token':'new'}
        manager.control.side_effect=action;auto.update();self.assertEqual(auto.token,'new');self.assertTrue(auto.get()['active'])

import json
from pathlib import Path
import sys
import tempfile
import unittest
from datetime import datetime
from zoneinfo import ZoneInfo
sys.path.insert(0, str(Path(__file__).parents[1]/'backend'))
from timecount import TimecountStore
from widget_config import validate

PROJECTS = [{'id':'project','name':'Project'}, {'id':'econ','name':'Econ'}]

class TimecountTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.now=0.0
        self.wall=datetime(2026,10,29,12,tzinfo=ZoneInfo('UTC')).timestamp()
        self.path=Path(self.temp.name)/'timecount.sqlite3'
        self.store=self.open()

    def open(self):
        return TimecountStore(self.path,monotonic=lambda:self.now,wall=lambda:self.wall,timezone=ZoneInfo('UTC'))

    def tearDown(self):
        self.store.shutdown()
        self.temp.cleanup()

    def call(self,action='sync',project='',client='test',profile='default',projects=None):
        return self.store.control({'action':action,'project':project,'profile':profile,'client':client,'projects':projects or PROJECTS})

    def advance(self,seconds):
        while seconds>0:
            step=min(seconds,2);seconds-=step
            self.now+=step;self.wall+=step
            self.call()

    def test_accumulates_pause_switch_and_renames_without_reset(self):
        self.call('start','project');self.advance(5)
        self.call('start','econ');self.advance(3)
        state=self.call('pause','econ')
        self.assertEqual([p['total'] for p in state['projects']],[5,3])
        renamed=[{'id':'project','name':'BAFS'},PROJECTS[1]]
        self.assertEqual(self.call(projects=renamed)['projects'][0]['total'],5)
        for action in ('reset','subtract','delete'):
            with self.assertRaises(ValueError):self.call(action,'project')
        self.assertEqual(self.call()['projects'][0]['total'],5)

    def test_shutdown_and_offline_do_not_add_time(self):
        self.call('start','project');self.advance(3.25)
        self.store.shutdown()
        self.now+=86400;self.wall+=86400
        self.store=self.open()
        state=self.call()
        self.assertEqual(state['running'],'')
        self.assertEqual(state['projects'][0]['total'],3.25)
        self.call('start','project');self.advance(1)
        self.assertEqual(self.call()['projects'][0]['total'],4.25)

    def test_release_and_expiry_stop_unattended_recording(self):
        self.call('start','project');self.advance(2)
        self.call('release')
        self.now+=100;self.wall+=100
        self.assertEqual(self.call()['projects'][0]['total'],2)
        self.call('start','project')
        self.now+=60;self.wall+=60
        state=self.call()
        self.assertEqual(state['running'],'')
        self.assertEqual(state['projects'][0]['total'],8)

    def test_two_views_share_one_counter_and_last_close_pauses(self):
        self.call('start','project');self.call(client='child')
        self.advance(2);self.call('release')
        self.now+=2;self.wall+=2
        state=self.call(client='child')
        self.assertEqual(state['projects'][0]['total'],4)
        self.assertEqual(state['running'],'project')
        self.call('release',client='child')
        self.now+=30;self.wall+=30
        self.assertEqual(self.call()['projects'][0]['total'],4)

    def test_midnight_statistics_and_heatmap_are_real_days(self):
        self.wall=datetime(2026,10,31,23,59,58,tzinfo=ZoneInfo('UTC')).timestamp()
        self.call('start','project');self.advance(4)
        state=self.call('pause','project')['projects'][0]
        self.assertEqual(state['today'],2)
        self.assertEqual(state['month'],2)
        self.assertEqual(state['week'],4)
        self.assertEqual(state['streak'],2)
        self.assertEqual(state['longest_streak'],2)
        self.assertEqual(state['active_days'],2)
        self.assertEqual(len(state['days']),371)
        self.assertEqual(sum(d['seconds'] for d in state['days']),4)
        self.assertFalse(any(d['future'] for d in state['days']))  # This fixture ends on Sunday.

    def test_dst_day_boundary_and_wall_rollback_do_not_subtract(self):
        self.store.timezone=ZoneInfo('America/New_York')
        self.wall=datetime(2026,11,1,23,59,58,tzinfo=self.store.timezone).timestamp()
        self.call('start','project');self.advance(4)
        self.assertEqual(self.call()['projects'][0]['today'],2)
        total=self.call()['projects'][0]['total']
        self.wall-=3600
        self.advance(2)
        self.assertEqual(self.call()['projects'][0]['total'],total+2)

    def test_fractional_time_and_profiles_are_isolated(self):
        self.call('start','project');self.advance(.125)
        self.assertEqual(self.call()['projects'][0]['total'],.125)
        self.assertEqual(self.call(profile='study')['projects'][0]['total'],0)
        self.assertEqual(self.call(profile='study')['running'],'')

    def test_empty_project_list_pauses_without_erasing_history(self):
        self.call('start','project');self.advance(2)
        payload={'action':'sync','profile':'default','client':'test','projects':[]}
        state=self.store.control(payload)
        self.assertEqual(state['projects'],[])
        self.assertEqual(state['running'],'')
        self.now+=30;self.wall+=30
        self.assertEqual(self.call()['projects'][0]['total'],2)
        validate({'timecountProjects':'[]'})

    def test_inactive_view_release_cannot_remove_another_views_project(self):
        self.call('start','econ');self.advance(2)
        self.call('release',client='inactive',projects=[PROJECTS[0]])
        self.assertEqual(self.call()['running'],'econ')
        self.assertEqual(self.call()['projects'][1]['total'],2)

    def test_stopping_clears_current_session_but_keeps_total_and_last_interval(self):
        start=self.wall
        self.call('start','project');self.advance(5)
        running=self.call()['projects'][0]
        self.assertEqual(running['session_seconds'],5)
        self.assertIsNone(running['last_session'])
        stopped=self.call('pause','project')['projects'][0]
        self.assertEqual(stopped['session_seconds'],0)
        self.assertEqual(stopped['total'],5)
        self.assertEqual(stopped['last_session'],{'started_at':start,'ended_at':start+5,'seconds':5})
        self.call('pause','project')  # Repeated stop cannot replace the interval.
        self.call('start','project');self.advance(2)
        next_run=self.call()['projects'][0]
        self.assertEqual(next_run['session_seconds'],2)
        self.assertEqual(next_run['total'],7)
        self.assertEqual(next_run['last_session']['seconds'],5)
        self.assertEqual(self.call('pause','project')['projects'][0]['last_session']['seconds'],2)

    def test_interval_survives_restart_and_crash_recovery_excludes_offline(self):
        self.call('start','project');self.advance(3.25)
        checkpoint=self.wall
        # Simulate loss after a durable checkpoint, without a graceful finish.
        self.store.db.close()
        self.now+=10000;self.wall+=10000
        self.store=self.open()
        recovered=self.call()['projects'][0]
        self.assertEqual(recovered['session_seconds'],0)
        self.assertEqual(recovered['last_session']['seconds'],3.25)
        self.assertEqual(recovered['last_session']['ended_at'],checkpoint)
        self.store.shutdown();self.store=self.open()
        self.assertEqual(self.call()['projects'][0]['last_session'],recovered['last_session'])

    def test_switch_and_expiry_finish_intervals_once(self):
        self.call('start','project');self.advance(2)
        self.call('start','econ')
        old=self.call()['projects'][0]
        self.assertEqual(old['session_seconds'],0)
        self.assertEqual(old['last_session']['seconds'],2)
        start=self.wall
        self.now+=60;self.wall+=60
        expired=self.call()['projects'][1]
        self.assertEqual(expired['session_seconds'],0)
        self.assertEqual(expired['last_session']['seconds'],6)
        self.assertEqual(expired['last_session']['ended_at'],start+6)
        self.assertEqual(self.store.db.execute('SELECT count(*) FROM sessions').fetchone()[0],2)

    def test_legacy_daily_data_migrates_without_invented_interval(self):
        self.store.db.execute('INSERT INTO daily VALUES(?,?,?,?)',('default','project','2026-10-28',12500))
        self.store.db.commit()
        self.store.shutdown();self.store=self.open()
        legacy=self.call()['projects'][0]
        self.assertEqual(legacy['total'],12.5)
        self.assertEqual(legacy['session_seconds'],0)
        self.assertIsNone(legacy['last_session'])

    def test_configuration_validation_rejects_bad_and_duplicate_ids(self):
        for projects in ([{'id':'../bad','name':'Econ'}],[PROJECTS[0],PROJECTS[0]],[{'id':'econ','name':''}]):
            with self.assertRaises(ValueError):validate({'timecountProjects':json.dumps(projects)})
        validate({'timecountProjects':json.dumps(PROJECTS),'timecountColor':'#aabbcc'})

if __name__=='__main__':unittest.main()

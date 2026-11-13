"""Real KDE auto-inhibition with a unique test reason; no real user timers touched."""
import json,sys,tempfile,time,uuid,subprocess
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'backend'))
import power
from power import AwakeManager,AutomaticAwake
from timers import TimerManager
from connectivity import unbox
reason='Automatic timer test '+uuid.uuid4().hex

def rows():
    text=subprocess.check_output(['busctl','--user','--json=short','get-property','org.kde.Solid.PowerManagement.PolicyAgent','/org/kde/Solid/PowerManagement/PolicyAgent','org.kde.Solid.PowerManagement.PolicyAgent','ActiveInhibitions'],text=True)
    return [row for row in unbox(json.loads(text)) if row[1]=='someProducts-monitor' and row[2]==reason]

with tempfile.TemporaryDirectory(prefix='monitor-auto-awake-test-') as tmp:
    helper=Path(power.__file__).with_name('awake_helper.py').read_text().replace("REASON = 'Keep awake: automatic sleep and screen off'",'REASON = '+repr(reason))
    Path(tmp,'awake_helper.py').write_text(helper);power.__file__=str(Path(tmp,'power.py'))
    now=[0.];timers=TimerManager(clock=lambda:now[0]);pair=timers.create(3,0)['session'];manager=AwakeManager();auto=AutomaticAwake(manager,timers.any_running)
    try:
        timers.control(pair,'countdown','start');auto.update()
        assert auto.get()['active'];assert rows(),'KDE did not confirm the automatic inhibition'
        assert any({'sleep','idle'}<=set(row[0].split(':')) for row in rows())
        manual=manager.control('enable')['token'];token=auto.token
        timers.control(pair,'stopwatch','start');now[0]=4;auto.update();assert auto.token==token
        assert auto.get()['active'],'Stopwatch must retain the lease after countdown ends'
        timers.control(pair,'stopwatch','pause');auto.update()
        assert not auto.get()['active'] and set(manager.leases)=={manual} and rows()
        manager.control('disable',manual)
        deadline=time.monotonic()+3
        while rows() and time.monotonic()<deadline:time.sleep(.05)
        assert not rows(),'Only our isolated inhibitor should be released'
        print('Real KDE timer acquisition, countdown completion with stopwatch still running, final pause release and independent manual preservation passed.')
    finally:auto.shutdown();manager.shutdown()

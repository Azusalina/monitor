"""Production HTTP handler + private durable DB, no telemetry/hardware collection."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
from http.server import ThreadingHTTPServer
from types import SimpleNamespace
sys.path.insert(0,str(Path(__file__).parents[1]/'backend'))
from monitor_service import Handler
from timecount import TimecountStore

class Fixture(Handler):
    def reply(self,code,value):
        try:super().reply(code,value)
        except (BrokenPipeError,ConnectionResetError):pass

with tempfile.TemporaryDirectory(prefix='monitor-timecount-test-') as directory:
    store=TimecountStore(Path(directory)/'timecount.sqlite3')
    server=ThreadingHTTPServer(('127.0.0.1',17344),Fixture)
    server.daemon_threads=True
    server.telemetry=SimpleNamespace(timecount=store)
    thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
    store.thread.start()
    try:
        env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
        env.setdefault('QT_QUICK_CONTROLS_STYLE','org.kde.desktop')
        result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input','tests/tst_timecount.qml'],cwd=Path(__file__).parents[1],env=env,capture_output=True,text=True,timeout=45)
        print(result.stdout,end='')
        print(result.stderr,end='',file=sys.stderr)
        result.check_returncode()
        assert not any(word in result.stdout+result.stderr for word in ('TypeError:', 'ReferenceError:', 'Binding loop')), 'Unexpected QML runtime diagnostic'
        if '--native' in sys.argv:
            core=Path(__file__).parents[1]
            subprocess.run([str(core/'build/native/monitor_native_probe'),str(core/'plasmoid'),'http://127.0.0.1:17344'],env=env,check=True,timeout=30)
        print('Timecount HTTP/QML navigation, exclusive cumulative recording, configuration and close/reopen passed.')
    finally:
        server.shutdown();server.server_close();store.shutdown()

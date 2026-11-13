"""Local decoded-audio integration fixture; never contacts LiveATC or changes networks."""
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
from pathlib import Path
import io,json,os,subprocess,threading,wave
buffer=io.BytesIO()
with wave.open(buffer,'wb') as wav:
    wav.setnchannels(1);wav.setsampwidth(2);wav.setframerate(8000);wav.writeframes(b'\0\0'*8000*12)
audio=buffer.getvalue()
events=[]
class Fixture(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def do_POST(self):
        events.append(json.loads(self.rfile.read(int(self.headers.get('Content-Length','0')))))
        payload=b'{"ok":true}'
        self.send_response(200);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
    def do_GET(self):
        payload=json.dumps(events).encode() if self.path == '/events' else json.dumps({'url':'http://127.0.0.1:17345/radio.wav'}).encode() if self.path.startswith('/liveatc/') else audio
        start,end=0,len(payload)-1
        requested=self.headers.get('Range','')
        if requested.startswith('bytes='):
            bounds=requested[6:].split('-',1)
            start=int(bounds[0] or 0);end=min(end,int(bounds[1]) if bounds[1] else end)
            self.send_response(206);self.send_header('Content-Range',f'bytes {start}-{end}/{len(payload)}')
            payload=payload[start:end+1]
        else:self.send_response(200)
        self.send_header('Accept-Ranges','bytes');self.send_header('Content-Type','application/json' if self.path.startswith('/liveatc/') else 'audio/wav');self.send_header('Content-Length',str(len(payload)));self.end_headers()
        try:self.wfile.write(payload)
        except (BrokenPipeError,ConnectionResetError):pass
server=ThreadingHTTPServer(('127.0.0.1',17345),Fixture)
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
    env=dict(os.environ,QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software')
    env.setdefault('QT_QUICK_CONTROLS_STYLE','org.kde.desktop')
    result=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-input','tests/tst_media_extensions.qml'],cwd=Path(__file__).parents[1],env=env,capture_output=True,text=True,timeout=60)
    print(result.stdout);print(result.stderr)
    result.check_returncode()
    assert not any(word in result.stdout+result.stderr for word in ('TypeError:','ReferenceError:','Binding loop'))
finally:server.shutdown();server.server_close()

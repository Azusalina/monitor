import QtQuick
import QtTest
import QtMultimedia
import "../plasmoid/contents/ui"
Item {
    id:root
    width:520;height:700
    QtObject {
        id:prefs
        property string noteText:"Private draft"
        property int noteHeight:85
        property string noteExportUrl:""
        property string wifiPins:"[]"
        property string bluetoothPins:"[]"
    }
    MediaCard { id:media; width:320;height:implicitHeight; detached:true;cavaEnabled:false;players:[{service:"test",status:"Paused",duration:120,position:30,observed_at:Date.now()/1000,can_control:true,can_seek:true,can_next:true,can_previous:true,can_pause:true,can_play:true,track_id:"/track/1"}] }
    RadioStream { id:broadcast; objectName:"standaloneBroadcast"; y:210;width:320;height:implicitHeight }
    NoteCard { id:note; y:260;width:320;height:implicitHeight;preferences:prefs }
    ConnectivityCard { id:wifi;y:380;width:280;kind:"wifi";preferences:prefs;status:({enabled:true,saved:[{id:"Home",name:"Home"}],networks:[{id:"Home",name:"Home",available:true,connected:false,signal:80}]}) }
    SignalSpy { id:control;target:media;signalName:"controlRequested" }
    TestCase {
        name:"MediaExtensions"
        when:windowShown
        function test_01_externalSeekArrowsAndSkip() {
            media.seek(55);tryCompare(control,"count",1)
            compare(control.signalArguments[0][1],"position");compare(control.signalArguments[0][2],55)
            media.step(1);media.step(-1)
            compare(control.signalArguments[1][1],"next");compare(control.signalArguments[2][1],"previous")
            const focus=findChild(media,"mediaSeekFocus");focus.forceActiveFocus();keyClick(Qt.Key_Right)
            tryCompare(control,"count",4);compare(control.signalArguments[3][2],35)
            keyClick(Qt.Key_Left);tryCompare(control,"count",5);compare(control.signalArguments[4][2],25)
            const start=control.count
            for(let i=0;i<100;i++)media.seek(i)
            tryCompare(control,"count",start+1);compare(control.signalArguments[start][2],99)
        }
        function test_02_curtainNeverAltersDraft() {
            const editor=findChild(note,"noteEditor")
            editor.text="Unsaved private draft"
            note.covered=true
            compare(prefs.noteText,"Unsaved private draft")
            verify(!editor.visible);verify(!editor.activeFocus)
            wait(250);verify(findChild(note,"noteCurtain").height>60)
            note.covered=false;verify(findChild(note,"noteRendered").visible);compare(editor.text,"Unsaved private draft")
            wait(250);compare(findChild(note,"noteCurtain").height,0)
        }
        function test_03_pinsAndAvailability() {
            wifi.pin({id:"Home",name:"Home"});compare(wifi.pins.length,1);compare(wifi.pinState(wifi.pins[0]),"Available")
            wifi.stale=true;compare(wifi.pinState(wifi.pins[0]),"Unknown");wifi.stale=false
            wifi.status={enabled:true,networks:[]};compare(wifi.pinState(wifi.pins[0]),"Not seen")
            wifi.toggleChooser();wait(40)
            wifi.pin({id:"Home",name:"Home"});compare(JSON.parse(prefs.wifiPins).length,0)
            wifi.toggleChooser()
        }
        function events() {
            let done=false,result=[]
            const xhr=new XMLHttpRequest()
            xhr.onreadystatechange=function(){if(xhr.readyState===XMLHttpRequest.DONE){result=JSON.parse(xhr.responseText);done=true}}
            xhr.open("GET","http://127.0.0.1:17345/events");xhr.send();tryVerify(()=>done,2000);return result
        }
        function test_035_commonQuickConnectAndDisconnect() {
            prefs.wifiPins=JSON.stringify([{id:"Home",name:"Home"}]);prefs.bluetoothPins=JSON.stringify([{id:"AA:BB:CC:DD:EE:FF",name:"Headset"}])
            wifi.endpoint="http://127.0.0.1:17345/connectivity/connect"
            wifi.status={enabled:true,saved:[{id:"Home",name:"Home"}],networks:[{id:"Home",name:"Home",connected:false,available:true}]}
            wait(40);compare(wifi.commonEntries.length,1)
            let button=findChild(wifi,"quickConnection_Home");verify(button)
            wifi.status=JSON.parse(JSON.stringify(wifi.status));wait(40)
            compare(findChild(wifi,"quickConnection_Home"),button)
            mouseClick(findChild(wifi,"connectionStatus_Home"));tryVerify(()=>!wifi.request,2000)
            let rows=events();compare(rows[rows.length-1].action,"connect");compare(rows[rows.length-1].id,"Home")
            wifi.status={enabled:true,saved:[{id:"Home",name:"Home"}],networks:[{id:"Home",name:"Home",connected:true,available:true}]}
            wait(40);button=findChild(wifi,"quickConnection_Home");mouseClick(findChild(wifi,"connectionStatus_Home"));tryVerify(()=>!wifi.request,2000)
            rows=events();compare(rows[rows.length-1].action,"disconnect");compare(rows[rows.length-1].kind,"wifi")
            wifi.kind="bluetooth";wifi.status={enabled:true,known:[{id:"AA:BB:CC:DD:EE:FF",name:"Headset",paired:true,connected:true}]}
            wait(40);compare(wifi.commonEntries.length,1)
            button=findChild(wifi,"quickConnection_AA:BB:CC:DD:EE:FF");verify(button);mouseClick(findChild(wifi,"connectionStatus_AA:BB:CC:DD:EE:FF"));tryVerify(()=>!wifi.request,2000)
            rows=events();compare(rows[rows.length-1].action,"disconnect");compare(rows[rows.length-1].kind,"bluetooth");compare(rows[rows.length-1].id,"AA:BB:CC:DD:EE:FF")
            prefs.wifiPins="[]";prefs.bluetoothPins="[]"
            wifi.kind="wifi";wifi.status={enabled:true,networks:[{id:"Home",name:"Home",connected:false,available:true,signal:80}]};wifi.message=""
        }
        function test_04_detachedOnlyElements() {
            verify(findChild(media,"musicRecord").visible);compare(findChild(media,"atcRadio"),null);verify(broadcast.visible)
            media.detached=false
            wait(40)
            verify(!findChild(media,"musicRecord").visible);compare(findChild(media,"atcRadio"),null)
            compare(media.implicitHeight,40);media.detached=true;wait(40)
        }
        function test_05_parallelDecodedAudioAndLocalQueue() {
            const radio=broadcast
            radio.endpoint="http://127.0.0.1:17345/liveatc/resolve"
            radio.station="https://d.liveatc.net/test"
            media.chooseFiles(["http://127.0.0.1:17345/music.wav","http://127.0.0.1:17345/second.wav"])
            const music=findChild(media,"localMusicPlayer")
            tryVerify(()=>music.playbackState === MediaPlayer.PlayingState,5000)
            radio.toggle();tryVerify(()=>radio.playing,5000)
            const audio=findChild(radio,"atcAudioPlayer")
            tryVerify(()=>music.position>100 && audio.position>100,5000)
            music.pause();verify(radio.playing)
            media.seek(2);tryVerify(()=>Math.abs(music.position-2000)<200,3000)
            media.step(1);compare(media.localIndex,1)
            tryVerify(()=>music.playbackState === MediaPlayer.PlayingState,3000)
            radio.toggle();tryVerify(()=>!radio.playing)
            verify(music.playbackState === MediaPlayer.PlayingState)
            music.stop()
        }
        function test_06_detachedPreview() {
            media.localIndex=-1;media.localFiles=[]
            wait(40)
            let saved=false
            verify(media.grabToImage(result=>{verify(result.saveToFile("../docs/media-detached-preview.png"));saved=true}))
            tryVerify(()=>saved,3000)
        }
    }
}

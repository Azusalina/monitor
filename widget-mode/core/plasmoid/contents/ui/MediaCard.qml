pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
import "AudioTools.js" as AudioTools

Item {
    id: card
    property bool detached: false
    property var localFiles: []
    property int localIndex: -1
    readonly property var music: musicLoader.item ? (musicLoader.item as LocalMusic).player : null
    readonly property bool localMode: detached && localIndex >= 0 && localFiles.length > 0
    readonly property bool musicPlaying: localMode ? !!music && music.playbackState === MediaPlayer.PlayingState : !!player && player.status === "Playing"
    property string musicError: ""
    property var pendingSeek: null
    signal controlRequested(string service, string action, real value, string trackId)
    function seek(seconds) {
        const target = Math.max(0, Math.min(localMode ? music.duration/1000 : (player ? player.duration || 0 : 0), seconds))
        if (localMode) music.position = Math.round(target*1000)
        else if (player && player.can_seek && player.can_control) {
            pendingSeek = {service:player.service,position:target,track:player.track_id || ""}
            if (!seekThrottle.running) seekThrottle.start()
        }
    }
    Timer { id: seekThrottle; interval:100; onTriggered:{ const pending=card.pendingSeek;card.pendingSeek=null;if(pending && card.player && card.player.service === pending.service && card.player.track_id === pending.track)card.controlRequested(pending.service,"position",pending.position,pending.track) } }
    function step(direction) {
        if (localMode) {
            const index = localIndex + direction
            if (index < 0 || index >= localFiles.length) return
            localIndex = index; music.source = localFiles[index]; music.play()
        } else if (player) controlRequested(player.service,direction > 0 ? "next" : "previous",0,"")
    }
    function chooseFiles(files) {
        if (!files.length) return
        if (player && player.status === "Playing" && player.can_pause) controlRequested(player.service,"pause",0,"")
        localFiles = files; localIndex = 0; musicError = ""; music.source = files[0]; music.play()
    }
    FileDialog { id: files; objectName: "musicFileDialog"; title: "Choose music files"; fileMode: FileDialog.OpenFiles; nameFilters: ["Audio (*.mp3 *.flac *.ogg *.opus *.wav *.m4a *.aac *.aiff)","All files (*)"]; onAccepted: card.chooseFiles(selectedFiles) }
    Loader {
        id: musicLoader
        active: card.localMode
        sourceComponent: LocalMusic {
            onPlaybackError: message => card.musicError=message
            onEnded: card.step(1)
        }
    }
    property int audioRefreshInterval: 100
    property color ink: "#f5f5f4"
    property color flowInk: ink
    property var players: []
    property string selectedService: ""
    readonly property var player: players.find(p => p.service === selectedService) || players[0] || null
    property bool cavaEnabled: true
    property real cavaOpacity: 0.4
    property int cavaBarCount: 32
    property color cavaBarColor: flowInk
    property int cavaHeadroom: 20
    property var audioBars: []
    readonly property var audioLevels: AudioTools.enhance(audioBars)
    property var audioRequest: null
    property real clock: Date.now() / 1000
    readonly property real position: {
        if (localMode) return music ? music.position/1000 : 0
        if (!player || player.position === null || player.position === undefined) return 0
        const elapsed = player.status === "Playing" ? Math.max(0, clock - (player.observed_at || clock)) * (player.rate || 1) : 0
        return Math.max(0, player.position + elapsed)
    }
    readonly property bool hasProgress: localMode ? !!music && music.duration > 0 : !!player && player.duration > 0 && player.position !== null && player.position !== undefined
    readonly property real progress: hasProgress ? Math.min(1, position / (localMode ? music.duration/1000 : player.duration)) : 0
    signal toggleRequested(string service)
    implicitHeight: detached ? 158 + (musicError ? 24 : 0) : 40
    clip: true
    function pollAudio() {
        if (audioRequest) return
        const xhr = new XMLHttpRequest()
        audioRequest = xhr
        audioTimeout.restart()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || card.audioRequest !== xhr) return
            audioTimeout.stop()
            audioRequest = null
            try { audioBars = xhr.status === 200 ? JSON.parse(xhr.responseText).bars || [] : [] }
            catch (error) { audioBars = [] }
        }
        xhr.open("GET", "http://127.0.0.1:17341/audio")
        xhr.setRequestHeader("X-Monitor-Client", "plasma-widget")
        xhr.send()
    }
    Timer { interval: 100; running: !!card.player && card.player.status === "Playing"; repeat: true; onTriggered: card.clock = Date.now() / 1000 }
    Timer {
        interval: card.audioRefreshInterval
        running: card.visible && card.cavaEnabled
        repeat: true
        onTriggered: card.pollAudio()
        onRunningChanged: if (!running) {
            const pending = card.audioRequest; card.audioRequest = null
            audioTimeout.stop(); if (pending) pending.abort()
            card.audioBars = []
        }
    }
    Timer {
        id: audioTimeout
        interval: 2000
        onTriggered: { const pending = card.audioRequest; card.audioRequest = null; if (pending) pending.abort(); card.audioBars = [] }
    }
    Component.onDestruction: { if (audioRequest) audioRequest.abort(); if (music) music.stop() }
    Item {
        objectName: "cavaBackground"
        anchors.fill: parent
        visible: card.cavaEnabled && card.audioBars.length > 0
        opacity: card.cavaOpacity
        CavaWave {
            objectName: "cavaFlow"
            anchors.fill: parent
            ink: card.flowInk
            blockInk: card.cavaBarColor
            blockCount: card.cavaBarCount
            headroomPercent: card.cavaHeadroom
            values: card.audioLevels
            transitionDuration: Math.round(card.audioRefreshInterval*0.9)
        }
    }
    RowLayout {
        id: controls
        anchors.fill: parent
        anchors.topMargin: card.detached ? 120 : 0
        anchors.bottomMargin: 0
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        spacing: 12
        SmallButton { visible: card.detached; ink: card.ink; text: "‹"; Accessible.name: "Previous track"; enabled: card.localMode ? card.localIndex > 0 : !!card.player && card.player.can_control && !!card.player.can_previous; onClicked: card.step(-1) }
        Item {
            Layout.fillWidth: true
            implicitHeight: 12
            Accessible.role: Accessible.ProgressBar
            Accessible.name: "Media playback progress"
            Accessible.description: card.hasProgress ? Math.round(card.progress * 100) + "%" : "Player has no progress information"
            Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 2; color: card.ink; opacity: 0.2 }
            Rectangle { objectName: "mediaProgress"; anchors.verticalCenter: parent.verticalCenter; width: parent.width * card.progress; height: 2; color: card.ink }
            MouseArea {
                anchors.fill: parent
                anchors.topMargin: -8; anchors.bottomMargin: -8
                enabled: card.detached && card.hasProgress && (card.localMode ? !!card.music && card.music.seekable : !!card.player && card.player.can_control && !!card.player.can_seek)
                cursorShape: Qt.PointingHandCursor
                preventStealing: true
                onPressed: mouse => { seekFocus.forceActiveFocus(); card.seek(mouse.x/width * (card.localMode ? card.music.duration/1000 : card.player.duration)) }
                onPositionChanged: mouse => { if (pressed) card.seek(mouse.x/width * (card.localMode ? card.music.duration/1000 : card.player.duration)) }
            }
            FocusScope {
                id: seekFocus
                objectName: "mediaSeekFocus"
                anchors.fill: parent
                Keys.onLeftPressed: card.seek(card.position-5)
                Keys.onRightPressed: card.seek(card.position+5)
            }
        }
        SmallButton {
            objectName: "mediaToggle"
            text: card.musicPlaying ? "Ⅱ" : "▷"
            ink: card.ink
            Accessible.name: card.musicPlaying ? "Pause media" : "Resume media"
            enabled: card.localMode || (!!card.player && card.player.can_control && (card.player.status === "Playing" ? card.player.can_pause : card.player.can_play))
            onClicked: { if(card.localMode) { if(card.musicPlaying) card.music.pause(); else card.music.play() } else card.toggleRequested(card.player.service) }
        }
        SmallButton { visible: card.detached; ink: card.ink; text: "›"; Accessible.name: "Next track"; enabled: card.localMode ? card.localIndex+1 < card.localFiles.length : !!card.player && card.player.can_control && !!card.player.can_next; onClicked: card.step(1) }
    }
    RecordDisc { objectName: "musicRecord"; visible: card.detached; anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; width: 112; height: 112; ink: card.ink; playing: card.musicPlaying; onClicked: files.open() }
    Text { visible: card.detached && !!card.musicError; anchors.left: parent.left; anchors.top: parent.top; width: parent.width; text: card.musicError; color: card.ink; font.pixelSize: 9; wrapMode: Text.Wrap; textFormat: Text.PlainText }
}

import QtQuick
import QtQuick.Layouts
import QtMultimedia

RowLayout {
    id: radio
    property color ink: "#f5f5f4"
    property string station: ""
    property string endpoint: "http://127.0.0.1:17341/liveatc/resolve"
    property string message: ""
    property var request: null
    readonly property bool playing: audio.playbackState === MediaPlayer.PlayingState
    spacing: 8
    function toggle() {
        if (playing || request) {
            audio.stop()
            const pending = request; request = null; timeout.stop()
            if (pending) pending.abort()
            return
        }
        message = ""
        const xhr = new XMLHttpRequest()
        request = xhr; timeout.start()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || request !== xhr) return
            request = null; timeout.stop()
            try {
                const result = JSON.parse(xhr.responseText)
                if (xhr.status !== 200) { message = result.error || "Broadcast unavailable"; return }
                audio.source = result.url; audio.play()
            } catch (e) { message = "Broadcast unavailable" }
        }
        xhr.open("GET", endpoint + "?url=" + encodeURIComponent(station))
        xhr.setRequestHeader("X-Monitor-Client", "plasma-widget"); xhr.send()
    }
    onStationChanged: { audio.stop(); const pending = request; request = null; if (pending) pending.abort(); timeout.stop(); message = "" }
    Component.onDestruction: { audio.stop(); if (request) request.abort() }
    Timer { id: timeout; interval: 10000; onTriggered: { const pending=radio.request; radio.request=null; if(pending) pending.abort(); radio.message="Broadcast timed out" } }
    MediaPlayer { id: audio; objectName:"atcAudioPlayer"; audioOutput: AudioOutput {}
 onErrorOccurred: (error, errorString) => radio.message = errorString }
    Text { text: "ATC"; color: radio.ink; font.pixelSize: 9; opacity: 0.6 }
    Item { Layout.fillWidth: true }
    Text { Layout.fillWidth: true; visible: !!radio.message; text: radio.message; color: radio.ink; font.pixelSize: 9; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    SmallButton { objectName: "atcToggle"; text: radio.playing || radio.request ? "■" : "▷"; ink: radio.ink; enabled: !!radio.station; Accessible.name: radio.playing ? "Stop ATC broadcast" : "Play ATC broadcast"; onClicked: radio.toggle() }
}

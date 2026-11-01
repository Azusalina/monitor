pragma ComponentBehavior: Bound
import QtQuick
import "AudioTools.js" as AudioTools

Item {
    id: ambient
    property int refreshInterval: 100
    property color ink: "#f5f5f4"
    property color blockInk: ink
    property int blockCount: 32
    property int headroomPercent: 20
    readonly property real rasterScale: Math.min(1,960/Math.max(1,width),540/Math.max(1,height))
    property real glow: 0.35+energy*0.65
    Behavior on glow { NumberAnimation { duration: Math.round(ambient.refreshInterval*1.8) } }
    property var audioBars: []
    readonly property var levels: AudioTools.enhance(audioBars)
    readonly property real energy: levels.length ? levels.reduce((sum, value) => sum + value, 0) / levels.length : 0
    property var request: null
    clip: true
    function poll() {
        if (request) return
        const xhr = new XMLHttpRequest()
        request = xhr
        timeout.restart()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || ambient.request !== xhr) return
            timeout.stop(); ambient.request = null
            try { ambient.audioBars = xhr.status === 200 ? JSON.parse(xhr.responseText).bars || [] : [] }
            catch (error) { ambient.audioBars = [] }
        }
        xhr.open("GET", "http://127.0.0.1:17341/audio")
        xhr.setRequestHeader("X-Monitor-Client", "plasma-widget")
        xhr.send()
    }
    Timer {
        interval: ambient.refreshInterval; repeat: true
        running: ambient.enabled && ambient.visible
        onTriggered: ambient.poll()
        onRunningChanged: if (!running) {
            const pending = ambient.request; ambient.request = null
            timeout.stop(); if (pending) pending.abort()
            ambient.audioBars = []
        }
    }
    Timer {
        id: timeout; interval: 2000
        onTriggered: {
            const pending = ambient.request; ambient.request = null
            if (pending) pending.abort()
            ambient.audioBars = []
        }
    }
    Component.onDestruction: if (request) request.abort()
    CavaWave {
        objectName: "focusCavaWave"
        width: ambient.width*ambient.rasterScale
        height: ambient.height*ambient.rasterScale
        scale: 1/ambient.rasterScale
        transformOrigin: Item.TopLeft
        strokeWidth: 1.25
        values: ambient.levels
        ink: ambient.ink
        blockInk: ambient.blockInk
        blockCount: ambient.blockCount
        headroomPercent: ambient.headroomPercent
        opacity: ambient.glow
        blockOpacity: 1
        curveOpacity: 0.4
        gradientBlocks: true
        transitionDuration: Math.round(ambient.refreshInterval*0.9)
    }
}

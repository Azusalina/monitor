pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "ConnectionPins.js" as ConnectionPins
Item {
    id: card
    property color ink: "#f5f5f4"
    property string kind: "proton"
    property var status: ({})
    property bool stale: false
    property bool opening: false
    property var preferences: null
    readonly property int statusFontSize: Math.max(8,Math.min(28,preferences && preferences[kind + "StatusFontSize"] !== undefined ? preferences[kind + "StatusFontSize"] : 12))
    readonly property string statusColorSetting: preferences ? preferences[kind + "StatusColor"] || "" : ""
    readonly property color statusInk: /^#[0-9a-fA-F]{6}$/.test(statusColorSetting) ? statusColorSetting : ink
    readonly property string pinKey: kind === "wifi" ? "wifiPins" : "bluetoothPins"
    readonly property var pins: {
        try { const list = JSON.parse(preferences ? preferences[pinKey] || "[]" : "[]"); return Array.isArray(list) ? list : [] } catch(e) { return [] }
    }
    property var request: null
    property string endpoint: "http://127.0.0.1:17341/connectivity/connect"
    property string pendingId: ""
    readonly property string commonEntryData: {
        return JSON.stringify(ConnectionPins.visible(kind,status,pins))
    }
    readonly property var commonEntries: JSON.parse(commonEntryData)
    property string message: ""
    function pin(entry) {
        if (!preferences) return
        const next = pins.filter(p => p.id !== entry.id)
        if (next.length === pins.length && next.length < 12) next.push(entry)
        preferences[pinKey] = JSON.stringify(next)
    }
    function connectTo(identifier) {
        if (request || stale) return
        const connected = connectionRow(identifier).connected === true
        const action = connected ? "disconnect" : "connect"
        const xhr = new XMLHttpRequest(); request=xhr; pendingId=identifier; message=connected ? "Disconnecting…" : "Connecting…"; timeout.start()
        xhr.onreadystatechange=function() {
            if(xhr.readyState !== XMLHttpRequest.DONE || card.request !== xhr) return
            card.request=null; card.pendingId=""; timeout.stop()
            try { card.message=xhr.status === 200 ? (connected ? "Disconnect requested" : "Connection requested") : JSON.parse(xhr.responseText).error } catch(e) { card.message="Connection unavailable" }
        }
        xhr.open("POST",endpoint)
        xhr.setRequestHeader("X-Monitor-Client","plasma-widget"); xhr.setRequestHeader("Content-Type","application/json")
        xhr.send(JSON.stringify({kind:kind,id:identifier,action:action}))
    }
    function connectionRow(identifier) {
        const rows=kind === "wifi" ? status.networks || [] : status.known || []
        return rows.find(p=>p.id === identifier) || ({})
    }
    function pinState(entry) {
        if (stale) return "Unknown"
        const rows=kind === "wifi" ? status.networks || [] : status.known || []
        const row=rows.find(p=>p.id === entry.id)
        if (status.enabled === false) return "Off"
        if (!row) return kind === "wifi" ? "Not seen" : "Unverified"
        return row.connected ? "Connected" : row.available ? "Available" : "Unverified"
    }
    function toggleChooser() { if(chooser.opened) chooser.close(); else chooser.open() }
    Timer { id:timeout; interval:15000; onTriggered:{ const pending=card.request;card.request=null;card.pendingId="";if(pending)pending.abort();card.message="Connection timed out" } }
    Component.onDestruction: if(request) request.abort()
    signal openRequested(string target)
    readonly property string stateText: {
        if (stale) return "Waiting for status"
        if (kind === "proton") return status.connected === true ? "Connected" : status.connected === false ? "Disconnected" : "Unavailable"
        return status.enabled === true ? "On" : status.enabled === false ? "Off" : "Unavailable"
    }
    implicitHeight: kind === "proton" ? proton.implicitHeight : content.implicitHeight
    ProtonButton {
        id: proton
        width: Math.min(card.width, implicitWidth)
        visible: card.kind === "proton"
        ink: card.ink
        status: card.status
        stale: card.stale
        opening: card.opening
        onOpenRequested: card.openRequested("proton")
    }
    ColumnLayout {
        id: content
        visible: card.kind !== "proton"
        width: card.width
        spacing: 6
        SmallButton { text: card.stateText; ink: card.statusInk; font.pixelSize:card.statusFontSize; Accessible.name: "Choose " + card.kind; onClicked: card.toggleChooser() }
        Text {
            Layout.fillWidth: true
            visible: card.kind === "proton"
            text: "Kill Switch: Menu → Settings → Features"
            color: card.ink; opacity: 0.4; font.pixelSize: 9; wrapMode: Text.Wrap
        }
        Repeater {
            model: card.commonEntries
            delegate: RowLayout {
                id: pinned
                required property var modelData
                Layout.fillWidth: true
                SmallButton { objectName:"quickConnection_" + pinned.modelData.id; Layout.fillWidth:true; Layout.minimumWidth:0; implicitWidth:0; labelElide:Text.ElideRight; text:pinned.modelData.name; ink:card.ink; enabled:!card.request && !card.stale; Accessible.name:(card.connectionRow(pinned.modelData.id).connected ? "Disconnect " : "Connect ") + pinned.modelData.name; onClicked:card.connectTo(pinned.modelData.id) }
                Text { objectName:"connectionStatus_" + pinned.modelData.id; Layout.minimumWidth:0; Layout.maximumWidth:card.width*0.55; wrapMode:Text.Wrap; text:card.pendingId === pinned.modelData.id ? "…" : card.pinState(pinned.modelData); color:card.statusInk; opacity:card.statusColorSetting ? 1 : 0.6; font.pixelSize:card.statusFontSize
                    enabled: !card.request && !card.stale
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: (card.connectionRow(pinned.modelData.id).connected ? "Disconnect " : "Connect ") + pinned.modelData.name
                    Accessible.onPressAction: card.connectTo(pinned.modelData.id)
                    Keys.onSpacePressed: card.connectTo(pinned.modelData.id)
                    Keys.onReturnPressed: card.connectTo(pinned.modelData.id)
                    MouseArea { anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{parent.forceActiveFocus();card.connectTo(pinned.modelData.id)} }
                }
            }
        }
        Text { Layout.fillWidth:true; visible:!!card.message; text:card.message; color:card.ink; font.pixelSize:9; wrapMode:Text.Wrap; textFormat:Text.PlainText }
    }
    ConnectionChooser {
        id:chooser
        kind:card.kind;status:card.status;pins:card.pins;ink:card.ink;message:card.message;busy:!!card.request
        allowedEntries: card.commonEntries.map(p => Object.assign({},card.connectionRow(p.id),p))
        allowPinning: false
        statusFontSize: card.statusFontSize
        statusInk: card.statusInk
        onConnectRequested:identifier=>card.connectTo(identifier)
        onSettingsRequested:card.openRequested(card.kind)
    }
}

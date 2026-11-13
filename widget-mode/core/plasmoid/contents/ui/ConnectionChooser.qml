pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Popup {
    id: chooser
    property string kind: "wifi"
    property var status: ({})
    property var pins: []
    property color ink: "#f5f5f4"
    property string message: ""
    property bool busy: false
    property bool allowPinning: true
    property int statusFontSize: 12
    property color statusInk: ink
    property var allowedEntries: null
    signal pinRequested(var entry)
    signal connectRequested(string identifier)
    signal settingsRequested()
    readonly property string entriesData: JSON.stringify(allowedEntries !== null ? allowedEntries : kind === "wifi" ? status.networks || [] : status.known || [])
    readonly property var entries: JSON.parse(entriesData)
    width: Math.min(360, parent ? parent.width : 360)
    height: Math.min(360, list.contentHeight + 90)
    padding: 10
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: "#171717"; border.color: Qt.rgba(chooser.ink.r,chooser.ink.g,chooser.ink.b,0.25) }
    contentItem: ColumnLayout {
        spacing: 8
        Label { text: chooser.kind === "wifi" ? "Wi-Fi" : "Bluetooth"; color: chooser.ink }
        ListView {
            id: list
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; model: chooser.entries
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
            delegate: RowLayout {
                id: row
                required property var modelData
                width: list.width
                SmallButton {
                    visible: chooser.allowPinning
                    text: chooser.pins.some(p => p.id === row.modelData.id) ? "★" : "☆"; ink: chooser.ink
                    Accessible.name: "Pin " + row.modelData.name
                    onClicked: chooser.pinRequested({id:row.modelData.id,name:row.modelData.name})
                }
                SmallButton {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    implicitWidth: 0
                    labelElide: Text.ElideRight
                    text: row.modelData.name
                    ink: chooser.ink
                    enabled: !chooser.busy
                    Accessible.name: (row.modelData.connected ? "Disconnect " : "Connect ") + row.modelData.name
                    onClicked: chooser.connectRequested(row.modelData.id)
                }
                Text { Layout.minimumWidth:0; Layout.maximumWidth:list.width*0.45; wrapMode:Text.Wrap; text: row.modelData.connected ? "Connected" : row.modelData.available ? (chooser.kind === "wifi" ? row.modelData.signal+"%" : "Available") : "Unverified"; font.pixelSize:chooser.statusFontSize; color:chooser.statusInk
                    enabled: !chooser.busy
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: (row.modelData.connected ? "Disconnect " : "Connect ") + row.modelData.name
                    Accessible.onPressAction: chooser.connectRequested(row.modelData.id)
                    Keys.onSpacePressed: chooser.connectRequested(row.modelData.id)
                    Keys.onReturnPressed: chooser.connectRequested(row.modelData.id)
                    MouseArea { anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:{parent.forceActiveFocus();chooser.connectRequested(row.modelData.id)} }
                }
            }
        }
        Label { visible: !chooser.entries.length; text: chooser.allowPinning ? "No cached entries. Open native settings to scan." : "No eligible pins. Configure → Connections."; color: chooser.ink; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: !!chooser.message; text: chooser.message; color: chooser.ink; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        SmallButton { text: chooser.kind === "wifi" ? "Scan / passwords…" : "Scan / pair…"; ink: chooser.ink; onClicked: chooser.settingsRequested() }
    }
}

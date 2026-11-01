import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    id: page
    property string cfg_mediaService: ""
    property bool cfg_cavaEnabled: true
    property int cfg_cavaOpacity: 40
    property int cfg_cavaBarCount: 32
    property string cfg_cavaBarColor: ""
    property int cfg_cavaHeadroom: 20
    property var players: []
    readonly property var choices: [{service: "", name: "Automatic — prefer playing media"}].concat(players)
    implicitWidth: 480
    implicitHeight: 560
    contentWidth: availableWidth
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    ColumnLayout {
    width: page.availableWidth
    spacing: 16
    Label { text: "Media player"; font.bold: true }
    ComboBox {
        Layout.fillWidth: true
        model: page.choices
        textRole: "name"
        currentIndex: Math.max(0, page.choices.findIndex(p => p.service === page.cfg_mediaService))
        onActivated: page.cfg_mediaService = page.choices[currentIndex].service
    }
    CheckBox { text: "CAVA background from system playback audio"; checked: page.cfg_cavaEnabled; onClicked: page.cfg_cavaEnabled = checked }
    RowLayout {
        Label { text: "Visualizer opacity (%)" }
        SpinBox { from: 0; to: 100; value: page.cfg_cavaOpacity; enabled: page.cfg_cavaEnabled; onValueModified: page.cfg_cavaOpacity = value }
    }
    RowLayout {
        Label { text: "Block density (count)" }
        SpinBox { objectName: "cavaBarCountSetting"; from: 8; to: 128; stepSize: 8; editable: true; value: page.cfg_cavaBarCount; enabled: page.cfg_cavaEnabled; onValueModified: page.cfg_cavaBarCount = value }
    }
    RowLayout {
        Label { text: "Top gap (%)" }
        SpinBox { objectName: "cavaHeadroomSetting"; from: 5; to: 60; editable: true; value: page.cfg_cavaHeadroom; enabled: page.cfg_cavaEnabled; onValueModified: page.cfg_cavaHeadroom = value }
    }
    Label { text: "Block color · #rrggbb" }
    HexField { objectName: "cavaBarColorSetting"; Layout.fillWidth: true; hexValue: page.cfg_cavaBarColor; allowEmpty: true; placeholderText: "Follow the CAVA curve color"; onValidEdited: value => page.cfg_cavaBarColor = value }
    Label { Layout.fillWidth: true; text: "Blocks follow the curve throughout the animation. Density, block color and top gap apply to the desktop and fullscreen backgrounds. Curve color and animation update interval are in Flows → CAVA."; wrapMode: Text.Wrap; opacity: 0.7 }
    Label { Layout.fillWidth: true; text: "The desktop element shows only progress and a pause/resume icon. CAVA reads the current output monitor, never the microphone. If the player has no duration/position, the progress track remains empty."; wrapMode: Text.Wrap; opacity: 0.7 }
    Item { Layout.fillHeight: true }
    }
    function loadPlayers() {
        const xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || xhr.status !== 200) return
            try { players = JSON.parse(xhr.responseText).media.players || [] } catch (error) {}
        }
        xhr.open("GET", "http://127.0.0.1:17341/snapshot")
        xhr.setRequestHeader("X-Monitor-Client", "plasma-widget")
        xhr.send()
    }
    Component.onCompleted: loadPlayers()
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ScrollView {
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    id: page
    property string cfg_liveAtcUrl: ""
    property var feeds: []
    property var searchRequest: null
    property string searchMessage: ""
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
    Label { text: "LiveATC · independent broadcast module"; font.bold: true }
    TextField { objectName:"atcAddress"; Layout.fillWidth:true; text:page.cfg_liveAtcUrl; placeholderText:"LiveATC stream, .pls or hlisten.php URL"; onTextEdited:page.cfg_liveAtcUrl=text.trim() }
    RowLayout {
        TextField { id: airport; objectName:"atcAirport"; Layout.fillWidth:true; placeholderText:"Airport code · KJFK"; maximumLength:4; onAccepted:page.searchAirport() }
        Button { text:"Search"; enabled:!page.searchRequest; onClicked:page.searchAirport() }
        Button { text:"Website"; onClicked:Qt.openUrlExternally("https://www.liveatc.net/search/?icao="+encodeURIComponent(airport.text.trim().toUpperCase())) }
    }
    Label { visible:!!page.searchMessage; text:page.searchMessage; Layout.fillWidth:true; wrapMode:Text.Wrap; textFormat:Text.PlainText }
    Repeater {
        model:page.feeds
        delegate:Button {
            required property var modelData
            Layout.fillWidth:true
            text:modelData.name
            onClicked:page.cfg_liveAtcUrl=modelData.url
        }
    }
    Label { Layout.fillWidth:true; wrapMode:Text.Wrap; opacity:0.7; text:"Enable LiveATC in Modules; drag it out independently of music. Broadcast and music may play together. Search needs LiveATC access; when unavailable, use Website and paste its feed URL. No broadcast starts automatically." }
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
    function searchAirport() {
        if(searchRequest) return
        feeds=[];searchMessage="Searching…"
        const xhr=new XMLHttpRequest();searchRequest=xhr;searchTimeout.start()
        xhr.onreadystatechange=function(){
            if(xhr.readyState !== XMLHttpRequest.DONE || page.searchRequest !== xhr) return
            searchTimeout.stop();page.searchRequest=null
            try {
                const result=JSON.parse(xhr.responseText)
                if(xhr.status === 200){ page.feeds=result.feeds || [];page.searchMessage=page.feeds.length ? "Select a feed, then Apply." : "No feeds found. Try Website." }
                else page.searchMessage=result.error || "Search unavailable. Try Website."
            }catch(e){page.searchMessage="Search unavailable. Try Website."}
        }
        xhr.open("GET","http://127.0.0.1:17341/liveatc/search?code="+encodeURIComponent(airport.text.trim()))
        xhr.setRequestHeader("X-Monitor-Client","plasma-widget");xhr.send()
    }
    Timer { id:searchTimeout;interval:10000;onTriggered:{const pending=page.searchRequest;page.searchRequest=null;if(pending)pending.abort();page.searchMessage="Search timed out. Try Website."} }
    Component.onDestruction: if(searchRequest) searchRequest.abort()
    Component.onCompleted: loadPlayers()
}

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../ConnectionPins.js" as ConnectionPins

ScrollView {
    id: page
    property string cfg_wifiPins: "[]"
    property string cfg_bluetoothPins: "[]"
    property int cfg_wifiStatusFontSize: 12
    property int cfg_bluetoothStatusFontSize: 12
    property string cfg_wifiStatusColor: ""
    property string cfg_bluetoothStatusColor: ""
    property var connectivity: ({})
    property var request: null
    property string message: ""
    property bool autoRefresh: true
    contentWidth: availableWidth
    implicitWidth: 480
    implicitHeight: 560
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
    function setPin(kind,entry,checked) {
        const key=kind === "wifi" ? "cfg_wifiPins" : "cfg_bluetoothPins"
        const pins=ConnectionPins.parse(page[key]).filter(p=>p.id !== entry.id)
        if(checked && pins.length<12) pins.push({id:entry.id,name:entry.name})
        page[key]=JSON.stringify(pins)
    }
    function refresh() {
        if(request) return
        const xhr=new XMLHttpRequest();request=xhr;timeout.start();message=""
        xhr.onreadystatechange=function(){
            if(xhr.readyState !== XMLHttpRequest.DONE || page.request !== xhr)return
            page.request=null;timeout.stop()
            try { if(xhr.status !== 200)throw Error();page.connectivity=JSON.parse(xhr.responseText).connectivity || ({}) }
            catch(e){page.message="Connection history unavailable. Try Refresh."}
        }
        xhr.open("GET","http://127.0.0.1:17341/snapshot")
        xhr.setRequestHeader("X-Monitor-Client","plasma-widget");xhr.send()
    }
    Timer { id:timeout;interval:6000;onTriggered:{const pending=page.request;page.request=null;if(pending)pending.abort();page.message="Refresh timed out"} }
    Component.onCompleted: if(autoRefresh) refresh()
    Component.onDestruction: if(request)request.abort()
    ColumnLayout {
        width: page.availableWidth
        spacing: 12
        Label { Layout.fillWidth:true; text:"Connected entries always appear first. Other entries require a pin from connection history / paired devices. Apply saves pins and status text settings.";wrapMode:Text.Wrap }
        Button { text:"Refresh";enabled:!page.request;onClicked:page.refresh() }
        Label { visible:!!page.message;text:page.message;wrapMode:Text.Wrap;Layout.fillWidth:true }
        Repeater {
            model:["wifi","bluetooth"]
            delegate: ColumnLayout {
                id:section
                required property string modelData
                readonly property var entries:ConnectionPins.eligible(modelData,page.connectivity[modelData] || ({}))
                readonly property var pins:ConnectionPins.parse(modelData === "wifi" ? page.cfg_wifiPins : page.cfg_bluetoothPins)
                Layout.fillWidth:true
                Label { text:section.modelData === "wifi" ? "Wi-Fi" : "Bluetooth";font.bold:true }
                RowLayout {
                    Label { text:"Status text size (px)" }
                    SpinBox { from:8;to:28;editable:true;value:page["cfg_" + section.modelData + "StatusFontSize"];onValueModified:page["cfg_" + section.modelData + "StatusFontSize"]=value }
                }
                Label { text:"Status color · #rrggbb" }
                HexField { Layout.fillWidth:true;allowEmpty:true;placeholderText:"Follow widget text color";hexValue:page["cfg_" + section.modelData + "StatusColor"];onValidEdited:value=>page["cfg_" + section.modelData + "StatusColor"]=value }
                Label { visible:!section.entries.length;text:"No previously connected / paired entries available.";Layout.fillWidth:true;wrapMode:Text.Wrap }
                Repeater {
                    model:section.entries
                    delegate: CheckBox {
                        required property var modelData
                        objectName:"pin_" + section.modelData + "_" + modelData.id
                        Layout.fillWidth:true
                        text:modelData.name
                        checked:section.pins.some(p=>p.id === modelData.id)
                        enabled:checked || section.pins.length<12
                        onClicked:page.setPin(section.modelData,modelData,checked)
                    }
                }
                Button { text:"Clear pins";enabled:section.pins.length>0;onClicked:{if(section.modelData === "wifi")page.cfg_wifiPins="[]";else page.cfg_bluetoothPins="[]"} }
            }
        }
    }
}

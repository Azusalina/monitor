pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

ScrollView {
    ScrollBar.vertical.policy: ScrollBar.AlwaysOff
    id:page
    property string cfg_timecountProjects: '[{"id":"project","name":"Project"},{"id":"bafs","name":"BAFS"},{"id":"econ","name":"Econ"}]'
    property string cfg_timecountColor: ""
    property var editorRows: []
    property bool updating: false
    readonly property var projects: editorRows
    function loadRows() { try { editorRows=JSON.parse(cfg_timecountProjects) } catch(e) { editorRows=[] } }
    function saveRows() {
        updating=true
        cfg_timecountProjects=JSON.stringify(editorRows.filter(row=>row.name.trim()).map(row=>({id:row.id,name:row.name.trim()})))
        updating=false
    }
    function rename(index,name) {
        if (index<0 || index>=editorRows.length) return
        const value=name.trim().slice(0,64)
        if (editorRows[index].name===value) return
        editorRows[index].name=value;saveRows()
    }
    function renameById(id,name) { rename(editorRows.findIndex(row=>row.id===id),name) }
    function removeById(id) { removeRow(editorRows.findIndex(row=>row.id===id)) }
    function removeRow(index) {
        if (index<0 || index>=editorRows.length) return
        const next=editorRows.slice();next.splice(index,1);editorRows=next;saveRows()
    }
    onCfg_timecountProjectsChanged: if (!updating) loadRows()
    Component.onCompleted: loadRows()
    Connections {
        target:page.Window.window
        function onVisibleChanged() { if (page.Window.window.visible) page.loadRows() }
    }
    implicitWidth:480;implicitHeight:520
    contentWidth:availableWidth
    ScrollBar.horizontal.policy:ScrollBar.AlwaysOff
    ColumnLayout {
        width:page.availableWidth;spacing:10
        Label { Layout.fillWidth:true;text:"Start/Stop records a new project session. The main clock clears after stopping; the last interval appears beside it. Cumulative totals and daily history remain on the > page. Only one project runs at a time; offline time is excluded.";wrapMode:Text.Wrap }
        Label { Layout.fillWidth:true;text:"Project names · rename without losing history";wrapMode:Text.Wrap }
        Repeater {
            model:page.projects
            RowLayout {
                id:row
                required property var modelData
                required property int index
                Layout.fillWidth:true
                ColumnLayout {
                    Layout.fillWidth:true
                    TextField {
                    id:nameField
                    objectName:"timecountName_"+row.modelData.id
                    Layout.fillWidth:true
                    text:row.modelData.name
                    placeholderText:"Project name"
                    maximumLength:64
                    onEditingFinished:page.renameById(row.modelData.id,text)
                    Keys.priority:Keys.BeforeItem
                    Keys.onDeletePressed: event => {
                        if (!text.trim()) { page.removeById(row.modelData.id);event.accepted=true }
                        else event.accepted=false
                    }
                }
                    Label {
                        objectName:"timecountNamePreview_"+row.modelData.id
                        Layout.fillWidth:true
                        visible:nameField.contentWidth>nameField.width-nameField.leftPadding-nameField.rightPadding
                        text:nameField.text;textFormat:Text.PlainText
                        wrapMode:Text.Wrap
                        font.pixelSize:10;opacity:0.7
                    }
                }
                Button {
                    objectName:"timecountRemove_"+row.modelData.id
                    text:"×"
                    implicitWidth:32
                    enabled:!nameField.text.trim()
                    Accessible.name:"Remove empty project row"
                    onClicked:page.removeById(row.modelData.id)
                }
            }
        }
        Button {
            objectName:"timecountAddProject"
            text:"Add project";enabled:page.projects.length<32
            onClicked: {
                const next=page.projects.slice()
                next.push({id:"p"+Date.now().toString(36)+Math.random().toString(36).slice(2),name:""})
                page.editorRows=next;page.saveRows()
            }
        }
        Label { Layout.fillWidth:true;text:"Time and heatmap color · #rrggbb";wrapMode:Text.Wrap }
        TextField {
            objectName:"timecountColorSetting"
            Layout.fillWidth:true;text:page.cfg_timecountColor;placeholderText:"Use text color"
            validator:RegularExpressionValidator { regularExpression:/^(#[0-9a-fA-F]{6})?$/ }
            onTextEdited:page.cfg_timecountColor=text
        }
        Label { Layout.fillWidth:true;text:"Delete or × removes an empty row. Blank placeholders are not saved. Existing project IDs keep their historical totals when names change. Time records are stored separately from widget configuration.";wrapMode:Text.Wrap;opacity:0.65 }
    }
}

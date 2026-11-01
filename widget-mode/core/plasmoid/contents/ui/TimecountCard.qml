pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: card
    required property var owner
    required property var preferences
    property color ink: "#f5f5f4"
    readonly property color accent: /^#[0-9a-fA-F]{6}$/.test(preferences.timecountColor || "") ? preferences.timecountColor : ink
    property bool details: false
    property string selected: ""
    readonly property var project: owner.snapshot.projects.find(p=>p.id===selected) || owner.snapshot.projects[0] || null
    readonly property bool running: !!project && project.running
    property real clock: Date.now()/1000
    readonly property real liveElapsed: running ? Math.max(0,Math.min(6,clock-(owner.snapshot.observed_at || clock))) : 0
    readonly property real sessionSeconds: running ? (project.session_seconds || 0)+liveElapsed : 0
    readonly property var lastSession: project ? project.last_session || null : null
    readonly property bool wideSession: !details && width>=340
    readonly property real total: project ? project.total+liveElapsed : 0
    property string dayDetail: "Hover a day to see its recorded time"
    implicitHeight: contents.implicitHeight+4
    function duration(value) {
        const seconds=Math.max(0,Math.floor(value || 0))
        return String(Math.floor(seconds/3600)).padStart(2,"0")+":"+String(Math.floor(seconds/60)%60).padStart(2,"0")+":"+String(seconds%60).padStart(2,"0")
    }
    function lastRange() {
        if (!lastSession) return ""
        const start=new Date(lastSession.started_at*1000),end=new Date(lastSession.ended_at*1000)
        return Qt.formatDateTime(start,"MM/dd HH:mm:ss")+" → "+Qt.formatDateTime(end,start.toDateString()===end.toDateString()?"HH:mm:ss":"MM/dd HH:mm:ss")
    }
    Timer { interval:100;repeat:true;running:card.visible && card.running && card.owner.active && !card.owner.error;onTriggered:card.clock=Date.now()/1000 }
    Connections { target:card.owner;function onSnapshotChanged() { card.clock=Date.now()/1000; if (!card.owner.snapshot.projects.length) {card.details=false;card.selected=""} } }
    ColumnLayout {
        id:contents
        width:card.width
        spacing:6
        RowLayout {
            Layout.fillWidth:true
            spacing:6
            SmallButton { objectName:"timecountBack";visible:card.details;text:"<";implicitWidth:24;ink:card.ink;Accessible.name:"Back to Timecount stopwatch";onClicked:card.details=false }
            ComboBox {
                id:chooser
                objectName:"timecountProject"
                Layout.fillWidth:true
                visible:card.owner.projects.length>0
                padding:0
                leftPadding:0;rightPadding:0;topPadding:0;bottomPadding:0
                model:card.owner.projects
                textRole:"name"
                currentIndex:Math.max(0,card.owner.projects.findIndex(p=>p.id===card.selected))
                indicator: Text { x:chooser.width-width-6;anchors.verticalCenter:parent.verticalCenter;text:"⌄";color:card.ink;font.pixelSize:12 }
                background: Item {}
                contentItem: TextField {
                    text:chooser.displayText;color:"transparent";font:chooser.font
                    padding:0;readOnly:true;enabled:false;selectByMouse:false;background:null
                    Text {
                        id:projectTitle
                        objectName:"timecountProjectTitle"
                        anchors.left:parent.left;anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter
                        anchors.leftMargin:6;anchors.rightMargin:22
                        text:chooser.displayText;textFormat:Text.PlainText;color:card.ink;font:chooser.font
                        wrapMode:Text.Wrap
                    }
                }
                implicitHeight:Math.max(32,projectTitle.implicitHeight+12)
                delegate: ItemDelegate {
                    id:option
                    required property var modelData
                    required property int index
                    width:chooser.popup.width
                    highlighted:chooser.highlightedIndex===index
                    implicitHeight:Math.max(32,contentItem.implicitHeight+12)
                    contentItem:Text { text:option.modelData.name;textFormat:Text.PlainText;font:chooser.font;color:option.palette.text;wrapMode:Text.Wrap }
                }
                font.pixelSize:11
                Accessible.name:"Timecount project"
                onActivated: index => {
                    const next=card.owner.projects[index].id
                    card.selected=next
                    if(card.owner.snapshot.running && card.owner.snapshot.running!==next)card.owner.command("start",next)
                }
            }
            SmallButton {
                objectName:"timecountDetails";visible:!card.details && !!card.project
                text:">";implicitWidth:24;ink:card.ink
                Accessible.name:"Timecount statistics and activity heatmap"
                onClicked:card.details=true
            }
        }
        Text { Layout.fillWidth:true;visible:card.owner.projects.length===0;text:"Add a project in Configure → Timecount";color:card.ink;font.pixelSize:10;wrapMode:Text.Wrap }
        RowLayout {
            Layout.fillWidth:true
            spacing:12
            TimecountPrevious {
                objectName:"timecountPreviousWide"
                visible:card.wideSession && !!card.lastSession
                Layout.preferredWidth:120;Layout.maximumWidth:140;Layout.minimumWidth:80
                ink:card.ink;timeRange:card.lastRange();durationText:card.lastSession?card.duration(card.lastSession.seconds):""
            }
            Text {
                objectName:"timecountTotal"
                Layout.fillWidth:true
                text:card.duration(card.details?card.total:card.sessionSeconds)
                horizontalAlignment:Text.AlignHCenter
                font.family:"monospace";font.pixelSize:card.details?24:30
                font.weight:Font.Light;color:card.accent
                Accessible.name:(card.details?"Total recorded time ":"Current session ")+text
            }
        }
        RowLayout {
            Layout.fillWidth:true
            TimecountPrevious {
                objectName:"timecountPreviousNarrow"
                visible:!card.details && !card.wideSession && !!card.lastSession
                Layout.fillWidth:true
                ink:card.ink;timeRange:card.lastRange();durationText:card.lastSession?card.duration(card.lastSession.seconds):""
            }
            Text {
                Layout.fillWidth:true
                visible:card.details || card.wideSession || !card.lastSession
                text:card.details?"Total recorded time":card.running?"Recording · current session":"Stopped · ready for a new session"
                color:card.ink;opacity:0.6;font.pixelSize:9;wrapMode:Text.Wrap
            }
            SmallButton {
                objectName:"timecountToggle";text:card.running?"■":"▶";implicitWidth:34;implicitHeight:26;ink:card.accent
                enabled:!!card.project && !card.owner.busy && !card.owner.error
                Accessible.name:card.running?"Stop current session":"Start a new session"
                onClicked:card.owner.command(card.running?"pause":"start",card.project.id)
            }
        }
        GridLayout {
            visible:card.details
            Layout.fillWidth:true
            columns:2;columnSpacing:12;rowSpacing:4
            Repeater {
                model:card.project ? ["Today  "+card.duration(card.project.today),"This week  "+card.duration(card.project.week),"This month  "+card.duration(card.project.month),"Active days  "+card.project.active_days,"Streak  "+card.project.streak+" days","Best streak  "+card.project.longest_streak+" days"] : []
                Text { required property string modelData;text:modelData;color:card.ink;font.pixelSize:9;Layout.fillWidth:true }
            }
        }
        Text { visible:card.details;text:"ACTIVITY · LAST 53 WEEKS";font.pixelSize:8;font.letterSpacing:0.7;color:card.ink;opacity:0.55 }
        Flickable {
            objectName:"timecountHeatmap"
            visible:card.details
            Layout.fillWidth:true
            implicitHeight:70
            contentWidth:53*9;contentHeight:63
            clip:true;boundsBehavior:Flickable.StopAtBounds
            ScrollBar.horizontal:ScrollBar { policy:ScrollBar.AsNeeded }
            Grid {
                flow:Grid.TopToBottom;rows:7;spacing:2
                Repeater {
                    model:card.project?card.project.days:[]
                    Rectangle {
                        required property var modelData
                        width:7;height:7
                        color:card.accent
                        opacity:modelData.future?0.03:[0.1,0.3,0.5,0.75,1][modelData.level]
                        Accessible.name:modelData.date+" · "+card.duration(modelData.seconds)
                        HoverHandler { onHoveredChanged: if(hovered)card.dayDetail=parent.modelData.date+" · "+card.duration(parent.modelData.seconds) }
                    }
                }
            }
        }
        Text { visible:card.details;Layout.fillWidth:true;text:card.dayDetail;color:card.ink;opacity:0.6;font.pixelSize:9;wrapMode:Text.Wrap }
        RowLayout {
            visible:card.details;Layout.fillWidth:true;spacing:4
            Text { text:"Less";color:card.ink;font.pixelSize:8;opacity:0.6 }
            Repeater { model:[0.1,0.3,0.5,0.75,1];Rectangle { required property real modelData;width:7;height:7;color:card.accent;opacity:modelData } }
            Text { text:"More · daily recorded time";color:card.ink;font.pixelSize:8;opacity:0.6 }
        }
        Text { visible:card.details;Layout.fillWidth:true;text:"History is saved automatically. No reset or subtraction.\nProject names and color: Configure → Timecount.";color:card.ink;opacity:0.45;font.pixelSize:9;wrapMode:Text.Wrap }
        Text { visible:!!card.owner.error;Layout.fillWidth:true;text:card.owner.error;color:card.ink;font.pixelSize:9;wrapMode:Text.Wrap }
    }
}

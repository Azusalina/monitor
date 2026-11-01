import QtQuick
import QtQuick.Layouts

ColumnLayout {
    property color ink: "#f5f5f4"
    property string timeRange: ""
    property string durationText: ""
    spacing: 2
    Text { text: "Last"; color: parent.ink; font.pixelSize: 8; opacity: 0.45 }
    Text {
        objectName: "timecountLastRange"
        Layout.fillWidth: true
        text: parent.timeRange; color: parent.ink; textFormat: Text.PlainText
        font.pixelSize: 8; font.family: "monospace"; opacity: 0.65
        wrapMode: Text.Wrap
    }
    Text {
        objectName: "timecountLastDuration"
        text: parent.durationText; color: parent.ink
        font.pixelSize: 9; font.family: "monospace"; opacity: 0.8
    }
}

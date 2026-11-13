import QtQuick
Item {
    id: disc
    property color ink: "#f5f5f4"
    property bool playing: false
    signal clicked()
    implicitWidth: 112
    implicitHeight: 112
    Rectangle {
        anchors.centerIn: parent
        width: Math.max(0, Math.min(parent.width,parent.height)-4)
        height: width
        radius: width/2
        color: "transparent"
        border.color: disc.ink
        border.width: 1
        Rectangle { anchors.centerIn: parent; width:5; height:5; radius:width/2; color:"transparent"; border.color:disc.ink; border.width:1 }
    }
    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked:disc.clicked() }
    Accessible.role: Accessible.Button
    Accessible.name: "Choose music files"
    Accessible.onPressAction: disc.clicked()
}

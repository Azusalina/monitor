pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtCore
import "ResizeTools.js" as ResizeTools
import "../native" as Native

Item {
    id: card
    objectName: "noteCard"
    property bool covered: false
    onCoveredChanged: if (covered) { flush(); editor.focus = false }
    property bool editing: false
    readonly property bool markdown: preferences.noteMarkdown !== false
    readonly property string noteFamily: preferences.noteFontFamily || Qt.font({pixelSize:noteSize}).family
    readonly property string noteStyle: preferences.noteFontStyle || ""
    readonly property int noteSize: preferences.noteFontSize === undefined ? 12 : preferences.noteFontSize
    function beginEdit() {
        if(covered)return
        editing=true
        Qt.callLater(() => editor.forceActiveFocus())
    }
    property color ink: "#f5f5f4"
    required property var preferences
    property string endpoint: "http://127.0.0.1:17341/notes/save"
    property bool useNativeDialog: true
    property bool initialized: false
    property bool dirty: false
    property string savedText: preferences.noteText
    property real resizedHeight: -1
    property var request: null
    readonly property bool exporting: request !== null
    property string exportStatus: ""
    property bool exportFailed: false
    implicitHeight: resizedHeight >= 0 ? resizedHeight : Math.max(48, Math.min(800, preferences.noteHeight === undefined ? 85 : preferences.noteHeight))
    function flush() {
        if (initialized && dirty) {
            preferences.noteText = editor.text
            dirty = false
        }
    }
    function loadText() {
        if (editor.text === savedText) return
        save.stop()
        initialized = false
        editor.text = savedText
        viewport.contentY = 0
        initialized = true
        dirty = false
    }
    onSavedTextChanged: if (initialized) loadText()
    function chooseSaveFile() {
        if (exporting) return
        flush()
        const previous = preferences.noteExportUrl || ""
        const documents = String(StandardPaths.writableLocation(StandardPaths.DocumentsLocation))
        const folder = documents.startsWith("file:") ? documents : "file://" + documents.split("/").map(encodeURIComponent).join("/")
        saveDialog.currentFolder = previous.startsWith("file:") ? previous.slice(0, previous.lastIndexOf("/")) : folder
        saveDialog.selectedFile = previous.startsWith("file:") ? previous : folder + (markdown ? "/note.md" : "/note.txt")
        saveDialog.open()
    }
    function exportNote(url) {
        if (exporting) return
        flush()
        exportStatus = "Saving…"
        exportFailed = false
        const xhr = new XMLHttpRequest()
        request = xhr
        exportTimeout.restart()
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || request !== xhr) return
            exportTimeout.stop()
            request = null
            try {
                const result = JSON.parse(xhr.responseText)
                if (xhr.status === 200) {
                    preferences.noteExportUrl = result.url
                    exportStatus = "Saved to " + decodeURIComponent(result.url.replace(/^file:\/\//, ""))
                } else {
                    exportFailed = true
                    exportStatus = result.error || "Could not save note"
                }
            } catch (e) {
                exportFailed = true
                exportStatus = "Note bridge unavailable"
            }
        }
        xhr.open("POST", endpoint)
        xhr.setRequestHeader("X-Monitor-Client", "plasma-widget")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify({url: String(url), text: editor.text}))
    }
    FileDialog {
        id: saveDialog
        objectName: "noteSaveDialog"
        title: "Save note"
        fileMode: FileDialog.SaveFile
        defaultSuffix: card.markdown ? "md" : "txt"
        nameFilters: ["Markdown (*.md)", "Text files (*.txt)", "All files (*)"]
        options: card.useNativeDialog ? 0 : FileDialog.DontUseNativeDialog
        onAccepted: card.exportNote(selectedFile)
    }
    Timer { id: save; interval: 400; onTriggered: card.flush() }
    Timer {
        id: exportTimeout
        interval: 6000
        onTriggered: {
            const xhr = card.request
            card.request = null
            if (xhr) xhr.abort()
            card.exportFailed = true
            card.exportStatus = "Save timed out"
        }
    }
    Flickable {
        id: viewport
        visible: !card.covered
        enabled: !card.covered
        objectName: "noteViewport"
        anchors.fill: parent
        anchors.bottomMargin: 8
        clip: true
        contentWidth: width
        contentHeight: editor.visible ? editor.height : rendered.height
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }
        TextArea {
            id: editor
            objectName: "noteEditor"
            visible: !card.markdown || card.editing || !text.length
            width: viewport.width
            height: Math.max(viewport.height, implicitHeight)
            padding: 0
            color: card.ink
            selectionColor: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.25)
            selectedTextColor: card.ink
            placeholderText: "Leave a thought here…"
            placeholderTextColor: Qt.rgba(card.ink.r, card.ink.g, card.ink.b, 0.4)
            font.family: card.noteFamily
            font.styleName: card.noteStyle
            font.pixelSize: card.noteSize
            wrapMode: TextEdit.Wrap
            textFormat: TextEdit.PlainText
            selectByMouse: true
            background: null
            onTextChanged: if (card.initialized) { card.dirty = true; save.restart() }
            onActiveFocusChanged: { if (!activeFocus) { card.flush(); card.editing=false } else card.editing=true }
            Keys.onEscapePressed: { card.flush(); focus=false; card.editing=false }
            onCursorRectangleChanged: {
                if (!activeFocus) return
                if (cursorRectangle.y < viewport.contentY) viewport.contentY = cursorRectangle.y
                else if (cursorRectangle.y + cursorRectangle.height > viewport.contentY + viewport.height)
                    viewport.contentY = cursorRectangle.y + cursorRectangle.height - viewport.height
            }
        }
        TextEdit {
            id: rendered
            objectName: "noteRendered"
            visible: card.markdown && !editor.visible
            width: viewport.width
            height: Math.max(viewport.height,contentHeight)
            text: card.markdown && !card.editing && !card.covered ? editor.text : ""
            textFormat: TextEdit.MarkdownText
            readOnly: true
            wrapMode: TextEdit.Wrap
            color: card.ink
            font.family: card.noteFamily
            font.styleName: card.noteStyle
            font.pixelSize: card.noteSize
            activeFocusOnTab: true
            Accessible.name: "Note Markdown preview. Click to edit."
            Keys.onReturnPressed: card.beginEdit()
            MouseArea {
                anchors.fill:parent
                cursorShape:Qt.IBeamCursor
                onClicked:mouse=> {
                    const link=rendered.linkAt(mouse.x,mouse.y)
                    if((mouse.modifiers & Qt.ControlModifier) && /^(https?:|mailto:)/.test(link))Qt.openUrlExternally(link)
                    else card.beginEdit()
                }
            }
            Native.NoteHighlighter { document: rendered.textDocument; dark:card.ink.hslLightness>0.5 }
        }
    }
    Rectangle {
        objectName: "noteCurtain"
        anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
        height: card.covered ? card.height-8 : 0
        color: card.ink
        opacity: 0.8
        clip: true
        Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.InOutCubic } }
        Repeater {
            model: Math.ceil(parent.width/12)
            Rectangle { required property int index; x:index*12; width:1; height:parent.height; color:"#171717"; opacity:0.22 }
        }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
    }
    BorderGrip {
        anchors.fill: parent
        edges: ["top"]
        ink: card.ink
        onMoved: (edge,delta) => card.resizedHeight=Math.max(48,Math.min(800,(card.preferences.noteHeight || 85)-delta))
        onFinished: (edge,delta) => { card.preferences.noteHeight=Math.round(card.resizedHeight < 0 ? card.height : card.resizedHeight);card.resizedHeight=-1 }
        onCanceled: card.resizedHeight=-1
    }
    MouseArea {
        id: resizeHandle
        objectName: "noteResizeHandle"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 8
        hoverEnabled: true
        preventStealing: true
        cursorShape: Qt.SizeVerCursor
        property real startY: 0
        property real startHeight: 0
        onPressed: mouse => {
            startY = mapToItem(null, mouse.x, mouse.y).y
            startHeight = card.implicitHeight
            card.resizedHeight = startHeight
        }
        onPositionChanged: mouse => {
            if (pressed) card.resizedHeight = Math.max(48, Math.min(800, startHeight + mapToItem(null, mouse.x, mouse.y).y - startY))
        }
        onReleased: {
            card.preferences.noteHeight = Math.round(card.resizedHeight)
            card.resizedHeight = -1
        }
        onCanceled: card.resizedHeight = -1
        Accessible.name: "Drag to resize note height"
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 1
            color: card.ink
            opacity: resizeHandle.containsMouse || resizeHandle.pressed ? 0.55 : ResizeTools.isDetached(card) ? 0 : 0.18
        }
        ToolTip.visible: containsMouse && !pressed
        ToolTip.text: "Drag to resize note height"
    }
    Component.onCompleted: {
        editor.text = savedText
        initialized = true
    }
    Component.onDestruction: { flush(); if (request) request.abort() }
}

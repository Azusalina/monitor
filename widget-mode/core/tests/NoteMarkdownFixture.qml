import QtQuick
import QtQuick.Controls
import "../plasmoid/contents/ui"
Item {
    width:420;height:460
    QtObject {
        id:prefs
        objectName:"markdownPreferences"
        property string noteText:"# Heading\n\n**Bold** and *italic*\n\n- item one\n- item two\n\n```python\ndef answer():\n    return 42\n```"
        property int noteHeight:360
        property string noteExportUrl:""
        property string noteFontFamily:"monospace"
        property string noteFontStyle:""
        property int noteFontSize:16
        property bool noteMarkdown:true
    }
    NoteCard { objectName:"markdownCard";width:400;height:360;preferences:prefs }
    TextField { objectName:"outsideFocus";y:400;width:300 }
}

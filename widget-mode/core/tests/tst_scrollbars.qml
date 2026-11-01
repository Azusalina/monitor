import QtQuick
import QtQuick.Controls
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/ui/config"
Item {
    id:root
    width:520;height:480
    QtObject {
        id:prefs
        property string noteText:Array(80).fill("A saved note line").join("\n")
        property int noteHeight:85
        property string noteExportUrl:""
        property string layoutHeights:"{}"
        property string layoutColumnWeights:"[1,1,1]"
        property string layoutSplits:"{}"
        property string enabledModules:"note"
        property string moduleOrder:"note"
        property string targetsText:""
        property int columns:1
    }
    NoteCard { id:note;width:250;height:85;preferences:prefs }
    Component { id:modulesFactory;ConfigModules {} }
    Component { id:flowsFactory;ConfigFlows {} }
    Component { id:timersFactory;ConfigTimers {} }
    Component { id:todosFactory;ConfigTodos {} }
    Component { id:mediaFactory;ConfigMedia {} }
    Component { id:timecountFactory;ConfigTimecount {} }
    Component { id:pingFactory;ConfigPing {} }
    Component { id:dashboardFactory;Dashboard {} }
    TestCase {
        name:"HiddenVerticalScrollbars"
        when:windowShown
        function test_01_allScrollableConfigPagesHideIndicators() {
            for(const factory of [modulesFactory,flowsFactory,timersFactory,todosFactory,mediaFactory,timecountFactory]) {
                const page=createTemporaryObject(factory,root,{x:260,width:240,height:160})
                verify(page)
                compare(page.ScrollBar.vertical.policy,ScrollBar.AlwaysOff)
                compare(page.ScrollBar.vertical.visible,false)
                page.destroy()
            }
            const ping=createTemporaryObject(pingFactory,root,{x:260,width:240,height:300})
            const scroll=findChild(ping,"pingTargetsScroll")
            compare(scroll.ScrollBar.vertical.policy,ScrollBar.AlwaysOff)
            compare(scroll.ScrollBar.vertical.visible,false)
        }
        function test_02_noteStillScrollsWithWheel() {
            const viewport=findChild(note,"noteViewport")
            tryVerify(()=>viewport.contentHeight>viewport.height,1500)
            compare(viewport.ScrollBar.vertical.policy,ScrollBar.AlwaysOff)
            compare(viewport.ScrollBar.vertical.visible,false)
            mouseWheel(viewport,60,40,0,-120)
            tryVerify(()=>viewport.contentY>0,1500)
        }
        function test_03_dashboardHidesRightBar() {
            const board=createTemporaryObject(dashboardFactory,root,{width:240,height:160,preferences:prefs,runtimeReady:false})
            const scroll=findChild(board,"dashboardScroll")
            compare(scroll.ScrollBar.vertical.policy,ScrollBar.AlwaysOff)
            compare(scroll.ScrollBar.vertical.visible,false)
        }
    }
}

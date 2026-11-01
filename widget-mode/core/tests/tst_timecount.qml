import QtQuick
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/ui/config"
Item {
    id:root
    width:520;height:520
    Rectangle { anchors.fill:parent;color:"#151515";z:-1 }
    QtObject {
        id:prefs
        property string settingsProfile:"test"
        property string timecountProjects:'[{"id":"project","name":"Project"},{"id":"bafs","name":"BAFS"},{"id":"econ","name":"Econ"}]'
        property string timecountColor:"#66ddaa"
    }
    TimecountOwner { id:owner;preferences:prefs;serviceUrl:"http://127.0.0.1:17344" }
    TimecountCard { id:card;width:500;height:implicitHeight;owner:owner;preferences:prefs }
    ConfigTimecount { id:config;visible:false;width:480;height:500 }
    TestCase {
        name:"Timecount"
        when:windowShown
        function saveItem(item,path) {
            let saved=false
            verify(item.grabToImage(result=>{verify(result.saveToFile(path));saved=true}))
            tryVerify(()=>saved,3000)
        }
        function initTestCase() {
            owner.active=true
            tryVerify(()=>owner.snapshot.projects.length===3,5000)
        }
        function test_01_defaultIsSessionStopwatchAndDetails() {
            compare(card.details,false)
            compare(findChild(card,"timecountTotal").text,"00:00:00")
            mouseClick(findChild(card,"timecountDetails"))
            compare(card.details,true)
            wait(100)
            grabImage(root).save("/tmp/timecount-ui.png")
            compare(card.project.days.length,371)
            verify(findChild(card,"timecountHeatmap").visible)
            mouseClick(findChild(card,"timecountBack"))
            wait(100)
            compare(card.details,false)
        }
        function test_02_startPauseAndSwitchDoNotResetTotals() {
            mouseClick(findChild(card,"timecountToggle"))
            tryVerify(()=>card.running,4000)
            wait(1200)
            verify(card.total>=1)
            tryCompare(owner,"busy",false,3000)
            const chooser=findChild(card,"timecountProject")
            mouseClick(chooser,chooser.width-10,chooser.height/2)
            tryCompare(chooser.popup,"visible",true,2000)
            wait(100)
            const option=chooser.popup.contentItem.itemAtIndex(2)
            verify(option)
            mouseClick(option)
            tryVerify(()=>card.project.id==="econ",3000)
            tryCompare(owner,"busy",false,3000)
            tryCompare(owner.snapshot,"running","econ",4000)
            verify(owner.snapshot.projects.find(p=>p.id==="project").total>=1)
            card.selected="econ"
            wait(400)
            mouseClick(findChild(card,"timecountToggle"))
            tryVerify(()=>!card.running,4000)
            const total=card.total
            wait(400)
            compare(card.total,total)
        }
        function test_03_renameKeepsHistoryAndConfigurationStages() {
            const previous=owner.snapshot.projects[0].total
            config.cfg_timecountProjects=prefs.timecountProjects
            config.rename(0,"BAFS study")
            compare(owner.projects[0].name,"Project")
            prefs.timecountProjects=config.cfg_timecountProjects
            tryVerify(()=>owner.snapshot.projects[0].name==="BAFS study",5000)
            verify(owner.snapshot.projects[0].total>=previous)
            const oldIds=config.projects.map(p=>p.id).join(",")
            config.visible=true
            mouseClick(findChild(config,"timecountAddProject"))
            compare(config.projects.length,4)
            compare(config.projects.slice(0,3).map(p=>p.id).join(","),oldIds)
            config.visible=false
        }
        function test_04_closeReopenPreservesAndPauses() {
            owner.command("start","project")
            tryVerify(()=>owner.snapshot.running==="project",4000)
            wait(350)
            owner.active=false
            wait(250)
            owner.active=true
            tryVerify(()=>owner.snapshot.running==="" && !owner.error,4000)
            verify(owner.snapshot.projects[0].total>1)
            compare(card.duration(100*3600+125),"100:02:05")
        }
        function test_045_mainResetsAndLastSessionStaysVisible() {
            card.selected="project";card.details=false
            const clock=findChild(card,"timecountTotal")
            compare(clock.text,"00:00:00")
            const previousTotal=card.total
            mouseClick(findChild(card,"timecountToggle"))
            tryVerify(()=>card.running,4000)
            wait(1150)
            verify(card.sessionSeconds>=1)
            mouseClick(findChild(card,"timecountToggle"))
            tryVerify(()=>!card.running && !!card.lastSession,4000)
            compare(clock.text,"00:00:00")
            verify(card.total>=previousTotal+1)
            const history=findChild(card,"timecountPreviousWide")
            verify(history.visible)
            verify(findChild(history,"timecountLastRange").text.indexOf("→")>0)
            compare(findChild(history,"timecountLastDuration").text,card.duration(card.lastSession.seconds))
            saveItem(card,"../docs/timecount-session-stopped.png")
            card.details=true
            compare(clock.text,card.duration(card.total))
            card.details=false
            mouseClick(findChild(card,"timecountToggle"))
            tryVerify(()=>card.running,4000)
            verify(card.sessionSeconds<1)
            mouseClick(findChild(card,"timecountToggle"))
            tryVerify(()=>!card.running,4000)
        }
        function test_05_longTitlesFitWithoutClipping() {
            const rows=JSON.parse(prefs.timecountProjects)
            rows[0].name="Financial Accounting and Business Studies project revision"
            prefs.timecountProjects=JSON.stringify(rows)
            card.selected=rows[0].id;card.width=180
            const chooser=findChild(card,"timecountProject"), title=findChild(card,"timecountProjectTitle")
            tryVerify(()=>title.lineCount>1,3000)
            tryVerify(()=>chooser.height>=title.height+10,1500)
            verify(title.y>=0)
            verify(title.y+title.height<=chooser.contentItem.height)
            saveItem(card,"../docs/title-long-project-preview.png")
            config.cfg_timecountProjects=prefs.timecountProjects
            config.visible=true;config.width=260
            wait(50)
            const fullName=findChild(config,"timecountNamePreview_"+rows[0].id)
            verify(fullName.visible)
            verify(fullName.lineCount>1)
            saveItem(config,"../docs/title-project-config-preview.png")
            config.visible=false;config.width=480
            mouseClick(chooser,chooser.width-8,chooser.height/2)
            tryCompare(chooser.popup,"visible",true,2000)
            wait(60)
            const option=chooser.popup.contentItem.itemAtIndex(0)
            verify(!option.contentItem.truncated)
            verify(option.contentItem.lineCount>1 || option.contentItem.width>=option.contentItem.implicitWidth)
            verify(option.height>=option.contentItem.implicitHeight)
            chooser.popup.close()
            card.width=500
        }
        function test_06_deleteEmptyPlaceholderAndNoBlankSavedRows() {
            config.visible=true
            config.cfg_timecountProjects=prefs.timecountProjects
            const saved=config.cfg_timecountProjects
            mouseClick(findChild(config,"timecountAddProject"))
            compare(config.projects.length,4)
            compare(config.cfg_timecountProjects,saved)
            const id=config.projects[3].id
            const field=findChild(config,"timecountName_"+id)
            mouseClick(field)
            keyClick(Qt.Key_Delete)
            tryCompare(config.projects,"length",3,1000)
            verify(!findChild(config,"timecountName_"+id))
            mouseClick(findChild(config,"timecountAddProject"))
            const second=config.projects[3].id
            mouseClick(findChild(config,"timecountRemove_"+second))
            tryCompare(config.projects,"length",3,1000)
            compare(JSON.parse(config.cfg_timecountProjects).length,3)
            config.visible=false
        }
        function test_07_removeAllPlaceholdersIsValidEmptyState() {
            config.cfg_timecountProjects=prefs.timecountProjects
            while(config.projects.length)config.removeRow(0)
            compare(config.cfg_timecountProjects,"[]")
            prefs.timecountProjects="[]"
            tryVerify(()=>owner.snapshot.projects.length===0,4000)
            compare(card.project,null)
            compare(findChild(card,"timecountProject").visible,false)
            compare(findChild(card,"timecountToggle").enabled,false)
        }
        function cleanupTestCase() { owner.active=false }
    }
}

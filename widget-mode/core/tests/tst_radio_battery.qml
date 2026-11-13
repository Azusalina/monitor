import QtQuick
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/ui/LayoutTools.js" as LayoutTools
Item {
    id:root
    width:360;height:300
    QtObject { id: owner; property bool busy:false; property bool awake:false; property string error:""; property string operation:"" }
    BatteryCard { id:battery;width:300;height:implicitHeight;owner:owner;stale:false;vertical:true;status:({battery:{percent:71,state:"Charging",watts:20},profiles:[]}) }
    TestCase {
        name:"RadioAndBattery"
        when:windowShown
        function test_01_catalogReorderToggle() {
            verify(LayoutTools.modules.includes("liveatc"));compare(LayoutTools.label("liveatc"),"LiveATC")
            verify(LayoutTools.sequence("cpu,media").includes("liveatc"))
            compare(LayoutTools.toggle("media","liveatc"),"media,liveatc")
            compare(LayoutTools.toggle("media,liveatc","media"),"liveatc")
        }
        function test_02_chargingOnRightAndLarger() {
            const percent=findChild(battery,"batteryPercent"),charging=findChild(battery,"batteryCharging")
            wait(50);verify(charging.visible);compare(charging.text,"Charging");compare(charging.font.pixelSize,18)
            const a=percent.mapToItem(root,0,0), b=charging.mapToItem(root,0,0)
            verify(b.x>=a.x+percent.width);verify(Math.abs(b.y-a.y)<5)
            let saved=false;verify(battery.grabToImage(result=>{verify(result.saveToFile("../docs/split-battery-preview.png"));saved=true}));tryVerify(()=>saved)
            battery.width=80;wait(50);verify(charging.width>=0);verify(battery.height<300)
            battery.stale=true;verify(!charging.visible)
            battery.stale=false;battery.status={battery:{percent:71,state:"Discharging"},profiles:[]};verify(!charging.visible)
        }
    }
}

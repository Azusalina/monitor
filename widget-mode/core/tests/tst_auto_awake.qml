import QtQuick
import QtTest
import "../plasmoid/contents/ui"
Item {
    width:320;height:240
    QtObject { id:owner;property bool awake:false;property bool busy:false;property string operation:"";property string error:"";function toggle(){awake=!awake} }
    BatteryCard { id:card;width:300;height:implicitHeight;owner:owner;stale:false;status:({timer_awake:{required:true,active:false,error:""}}) }
    TestCase {name:"AutomaticKeepAwakeDisplay";when:windowShown
        function test_timerAndManualAreIndependent() {
            const button=findChild(card,"keepAwakeButton")
            verify(button.text.includes("Starting · Timer"));verify(!owner.awake)
            card.status={timer_awake:{required:true,active:true,error:""}}
            verify(button.text.includes("On · Timer"));verify(button.outlined)
            button.clicked();verify(owner.awake);verify(button.text.includes("Timer + manual"))
            card.status={timer_awake:{required:false,active:false,error:""}}
            verify(owner.awake);verify(button.text.endsWith("On"))
            button.clicked();verify(!owner.awake);verify(button.text.endsWith("Off"))
        }
    }
}

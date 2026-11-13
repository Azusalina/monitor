import QtQuick
import QtTest
import "../plasmoid/contents/ui"
import "../plasmoid/contents/ui/config"
Item {
    id:root;width:600;height:700
    QtObject { id:prefs;property string wifiPins:"[]";property string bluetoothPins:"[]";property int wifiStatusFontSize:20;property int bluetoothStatusFontSize:16;property string wifiStatusColor:"#aabbcc";property string bluetoothStatusColor:"#dd6633" }
    ConfigConnections { id:config;width:480;height:400;autoRefresh:false }
    ConnectivityCard { id:card;y:420;width:300;kind:"wifi";preferences:prefs }
    TestCase {
        name:"ConfiguredConnectionPins";when:windowShown
        function test_01_configDraftAndStrictIntersection() {
            const history={wifi:{saved:[{id:"Home",name:"Home"},{id:"Work",name:"Work"}],networks:[{id:"Home",name:"Home",connected:true},{id:"Unknown",name:"Unknown",connected:true}]},bluetooth:{known:[{id:"AA:BB:CC:DD:EE:FF",name:"Paired",paired:true,connected:false},{id:"11:22:33:44:55:66",name:"Nearby",paired:false,connected:true}]}}
            config.connectivity=history;card.status=history.wifi;wait(40)
            compare(card.commonEntries.length,2)
            const home=findChild(config,"pin_wifi_Home");verify(home);mouseClick(home)
            verify(JSON.parse(config.cfg_wifiPins).some(p=>p.id==="Home"))
            compare(prefs.wifiPins,"[]");compare(card.commonEntries.length,2)
            prefs.wifiPins=config.cfg_wifiPins
            compare(card.commonEntries.length,2);compare(card.commonEntries[0].id,"Home")
            const label=findChild(card,"connectionStatus_Home");verify(label);compare(label.font.pixelSize,20);compare(label.color,"#aabbcc")
            config.cfg_wifiPins=prefs.wifiPins
            config.setPin("wifi",{id:"Work",name:"Work"},true)
            compare(card.commonEntries.length,2) // draft changes are not applied
            config.cfg_wifiPins=prefs.wifiPins // Cancel/reopen restores the saved draft
            compare(JSON.parse(config.cfg_wifiPins).length,1)
            prefs.wifiPins=JSON.stringify([{id:"Home",name:"Home"},{id:"Unknown",name:"Unknown"}])
            compare(card.commonEntries.length,2)
            card.status={saved:[],networks:history.wifi.networks};compare(card.commonEntries.length,2)
            card.status={saved:history.wifi.saved,networks:[{id:"Home",name:"Home",connected:false},{id:"Unknown",name:"Unknown",connected:false}]};compare(card.commonEntries.length,1);compare(card.commonEntries[0].id,"Home")
            card.kind="bluetooth";prefs.bluetoothPins=JSON.stringify([{id:"AA:BB:CC:DD:EE:FF",name:"Paired"},{id:"11:22:33:44:55:66",name:"Nearby"}]);card.status=history.bluetooth
            compare(card.commonEntries.length,2);compare(card.commonEntries[0].name,"Nearby")
            card.status={known:[{id:"AA:BB:CC:DD:EE:FF",name:"Paired",paired:true,connected:false},{id:"11:22:33:44:55:66",name:"Nearby",paired:false,connected:false}]};compare(card.commonEntries.length,1);compare(card.commonEntries[0].name,"Paired")
            verify(!findChild(config,"pin_bluetooth_11:22:33:44:55:66"))
            card.status={known:[]};compare(card.commonEntries.length,0)
        }
    }
}

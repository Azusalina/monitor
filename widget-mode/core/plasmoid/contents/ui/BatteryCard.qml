pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

ColumnLayout {
    id: card
    required property var owner
    property var status: ({})
    property color ink: "#f5f5f4"
    property bool vertical: false
    property bool stale: true
    readonly property var battery: status.battery || ({})
    readonly property bool charging: !stale && ["Charging", "Pending charge"].includes(battery.state)
    readonly property var timerAwake: status.timer_awake || ({required:false,active:false,error:""})
    spacing: 3
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 3
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text { objectName: "batteryPercent"; text: !card.stale && card.battery.percent != null ? Math.round(card.battery.percent) + "%" : "—"; color: card.ink; font.pixelSize: 18 }
            Text {
                objectName: "batteryCharging"
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                visible: card.charging
                text: card.battery.state || ""
                color: card.ink
                font.pixelSize: 18
                font.weight: Font.DemiBold
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 10
                elide: Text.ElideRight
            }
        }
        Text {
            Layout.fillWidth: true
            text: card.stale ? "Waiting for battery" : [card.charging ? "" : card.battery.state || "Unavailable", card.battery.watts != null ? card.battery.watts.toFixed(1) + " W" : "", card.battery.remaining_seconds ? Math.ceil(card.battery.remaining_seconds / 60) + " min" : ""].filter(Boolean).join(" · ")
            color: card.ink; opacity: 0.65; font.pixelSize: 9; wrapMode: Text.Wrap
        }
    }
    GridLayout {
        Layout.fillWidth: true
        columns: card.vertical ? 1 : 3
        columnSpacing: 2; rowSpacing: 3
        Repeater {
            model: [{key: "power-saver", label: "Powersave"}, {key: "balanced", label: "Regular"}, {key: "performance", label: "Performance"}]
            delegate: SmallButton {
                required property var modelData
                objectName: "power_" + modelData.key
                text: modelData.label
                ink: card.ink
                Layout.fillWidth: true
                implicitWidth: 0
                implicitHeight: 24
                font.pixelSize: 9
                outlined: card.status.profile === modelData.key
                enabled: !card.stale && !card.owner.busy && (card.status.profiles || []).includes(modelData.key)
                Accessible.name: "Power mode: " + modelData.label
                onClicked: card.owner.setProfile(modelData.key)
            }
        }
    }
    SmallButton {
        objectName: "keepAwakeButton"
        Layout.fillWidth: true
        implicitHeight: card.vertical ? 36 : 24
        font.pixelSize: card.vertical ? 9 : 10
        ink: card.ink
        outlined: card.owner.awake || !!card.timerAwake.active
        text: "Keep awake" + (card.vertical ? "\n" : " · ") + (card.owner.busy && ["enable", "disable"].includes(card.owner.operation) ? "Applying…" : card.timerAwake.active ? (card.owner.awake ? (card.vertical ? "On · Timer\n+ manual" : "On · Timer + manual") : "On · Timer") : card.timerAwake.required && !card.timerAwake.error ? "Starting · Timer" : card.owner.awake ? "On" : "Off")
        enabled: !card.owner.busy
        Accessible.name: "Prevent automatic sleep and screen off"
        ToolTip.visible: hovered
        ToolTip.text: card.timerAwake.required ? "A running timer keeps the system awake automatically. Click to toggle an independent manual request that can remain on after timers stop." : "Prevents automatic sleep, screen off and idle locking. Manual locking remains available."
        onClicked: card.owner.toggle()
    }
    Text { Layout.fillWidth: true; visible: card.owner.error.length > 0 || !!card.timerAwake.error || !!card.status.degraded; text: card.owner.error || card.timerAwake.error || card.status.degraded || ""; textFormat: Text.PlainText; wrapMode: Text.Wrap; color: card.ink; font.pixelSize: 9; opacity: 0.65 }
}

import QtQuick

Item {
    id: owner
    required property var preferences
    property bool active: false
    property string serviceUrl: "http://127.0.0.1:17341"
    readonly property string client: "timecount"+Date.now().toString(36)+Math.random().toString(36).slice(2)
    readonly property string profile: preferences.settingsProfile || "default"
    readonly property var projects: {
        try { return JSON.parse(preferences.timecountProjects || '[{"id":"project","name":"Project"},{"id":"bafs","name":"BAFS"},{"id":"econ","name":"Econ"}]') }
        catch(e) { return [] }
    }
    property var snapshot: ({projects:[],running:""})
    property var request: null
    property string operation: ""
    property var pending: null
    readonly property bool busy: pending !== null || (request !== null && operation !== "sync")
    property string error: ""
    property string previousProfile: ""
    function poll() { if (active && !request && !pending) send("sync","") }
    function command(action,project) {
        if (!active) return
        if (request) { if (operation === "sync" && !pending) pending={action:action,project:project}; return }
        send(action,project)
    }
    function dispatch() {
        if (!active || request || !pending) return
        const next=pending;pending=null
        send(next.action,next.project)
    }
    function send(action,project) {
        if (request) return
        const xhr=new XMLHttpRequest(), requestedProfile=profile
        operation=action;request=xhr;timeout.restart()
        xhr.onreadystatechange=function() {
            if (xhr.readyState !== XMLHttpRequest.DONE || owner.request !== xhr) return
            timeout.stop();owner.request=null;owner.operation=""
            if (requestedProfile !== owner.profile) { Qt.callLater(owner.poll);return }
            try {
                const value=JSON.parse(xhr.responseText)
                if (xhr.status !== 200) throw new Error(value.error || "Timecount unavailable")
                owner.snapshot=value;owner.error=""
            } catch(e) { owner.error="Timecount unavailable · saved history is retained" }
            Qt.callLater(owner.dispatch)
        }
        xhr.open("POST",serviceUrl+"/timecount")
        xhr.setRequestHeader("X-Monitor-Client","plasma-widget")
        xhr.setRequestHeader("Content-Type","application/json")
        xhr.send(JSON.stringify({action:action,profile:profile,client:client,projects:projects,project:project}))
    }
    function release(name) {
        const xhr=new XMLHttpRequest()
        xhr.open("POST",serviceUrl+"/timecount")
        xhr.setRequestHeader("X-Monitor-Client","plasma-widget")
        xhr.setRequestHeader("Content-Type","application/json")
        xhr.send(JSON.stringify({action:"release",profile:name,client:client,projects:projects}))
    }
    function close() {
        const xhr=request;request=null;operation="";pending=null;timeout.stop()
        if (xhr) xhr.abort()
        release(profile)
    }
    onProfileChanged: {
        if (previousProfile) release(previousProfile)
        previousProfile=profile;pending=null;snapshot={projects:[],running:""}
        if (active) Qt.callLater(poll)
    }
    onProjectsChanged: if (active) Qt.callLater(poll)
    onActiveChanged: if (active) Qt.callLater(poll); else close()
    Timer { interval:2000;repeat:true;running:owner.active;onTriggered:owner.poll() }
    Timer {
        id:timeout;interval:5000
        onTriggered: {
            const xhr=owner.request;owner.request=null;owner.operation="";owner.pending=null
            if(xhr)xhr.abort()
            owner.error="Timecount connection timed out · saved history is retained"
        }
    }
    Component.onDestruction: close()
}

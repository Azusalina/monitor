.pragma library

function eligible(kind, status) {
    return kind === "wifi" ? status.saved || [] : (status.known || []).filter(p => p.paired)
}

function parse(value) {
    try { const pins=JSON.parse(value || "[]"); return Array.isArray(pins) ? pins : [] } catch(e) { return [] }
}

function visible(kind, status, pins) {
    const known=eligible(kind,status)
    const active=(kind === "wifi" ? status.networks || [] : status.known || []).filter(p=>p.connected)
    const rows=[],seen=new Set()
    for(const p of active.concat(pins.filter(p=>known.some(row=>row.id === p.id)).map(p=>known.find(row=>row.id === p.id)))) {
        if(!seen.has(p.id)){rows.push({id:p.id,name:p.name});seen.add(p.id)}
    }
    return rows
}

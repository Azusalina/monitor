import QtQuick

// One animated envelope drives both the stroke and the blocks beneath it.
Canvas {
    id: wave
    property var values: []
    property color ink: "#f5f5f4"
    property color blockInk: ink
    property int blockCount: 32
    property int headroomPercent: 20
    property int transitionDuration: 90
    property real strokeWidth: 2.5
    property real blockOpacity: 0.35
    property real curveOpacity: 0.8
    property bool gradientBlocks: false
    readonly property int sampleCount: 0
    property var previous: []
    property var current: []
    property real mix: 1
    readonly property real sideInset: Math.min(width/2, 2+strokeWidth/2)
    readonly property real topGap: height*Math.max(5,Math.min(60,headroomPercent))/100
    readonly property real plotBottom: Math.max(0,height-2-strokeWidth/2)
    readonly property real ceiling: Math.min(plotBottom,topGap+strokeWidth/2)
    readonly property int density: Math.max(8,Math.min(128,blockCount))
    clip: true
    function normalized(value) { return typeof value === "number" && isFinite(value) ? Math.max(0,Math.min(1,value)) : 0 }
    function resample(samples, count) {
        if (!samples.length) return Array(count).fill(0)
        if (count===1) return [normalized(samples[0])]
        return Array.from({length:count},(_,index)=>{
            const at=index*(samples.length-1)/(count-1), first=Math.floor(at), blend=at-first
            return normalized(samples[first])*(1-blend)+normalized(samples[Math.min(samples.length-1,first+1)])*blend
        })
    }
    function displayed() {
        return current.map((value,index)=>previous[index]+(value-previous[index])*mix)
    }
    function points() {
        if (plotBottom<=ceiling || width<=2*sideInset) return []
        let samples=displayed()
        if (samples.length===1) samples=[samples[0],samples[0]]
        return samples.map((value,index)=>({x:sideInset+index/Math.max(1,samples.length-1)*Math.max(0,width-2*sideInset),
            y:plotBottom-value*Math.max(0,plotBottom-ceiling)}))
    }
    function trace(context, samples) {
        context.moveTo(samples[0].x,samples[0].y)
        for (let index=1;index<samples.length;index++) {
            const a=samples[index-1],b=samples[index],middle=(a.x+b.x)/2
            context.bezierCurveTo(middle,a.y,middle,b.y,b.x,b.y)
        }
    }
    onValuesChanged: {
        const before=displayed(),next=(values || []).slice(0,256).map(normalized)
        transition.stop()
        previous=resample(before,next.length)
        current=next
        mix=0
        if (next.length) transition.restart()
        else mix=1
        requestPaint()
    }
    NumberAnimation { id:transition;target:wave;property:"mix";from:0;to:1;duration:wave.transitionDuration }
    onMixChanged:requestPaint()
    onInkChanged:requestPaint()
    onBlockInkChanged:requestPaint()
    onDensityChanged:requestPaint()
    onTopGapChanged:requestPaint()
    onStrokeWidthChanged:requestPaint()
    onBlockOpacityChanged:requestPaint()
    onCurveOpacityChanged:requestPaint()
    onGradientBlocksChanged:requestPaint()
    onWidthChanged:requestPaint()
    onHeightChanged:requestPaint()
    onPaint: {
        const ctx=getContext("2d")
        ctx.clearRect(0,0,width,height)
        const samples=points()
        if (!samples.length || width<=0 || height<=0) return
        // Clip the vertical rectangles to the SAME cubic path as the stroke.
        // The block tops follow every slope, even between analyzer bins.
        ctx.save()
        ctx.beginPath();trace(ctx,samples)
        ctx.lineTo(samples[samples.length-1].x,plotBottom)
        ctx.lineTo(samples[0].x,plotBottom);ctx.closePath();ctx.clip()
        const color=Qt.rgba(blockInk.r,blockInk.g,blockInk.b,Math.max(0,Math.min(1,blockOpacity)))
        if (gradientBlocks) {
            const gradient=ctx.createLinearGradient(0,ceiling,0,Math.max(ceiling+1,plotBottom))
            gradient.addColorStop(0,Qt.rgba(blockInk.r,blockInk.g,blockInk.b,0))
            gradient.addColorStop(1,color);ctx.fillStyle=gradient
        } else ctx.fillStyle=color
        const step=Math.max(0,width-2*sideInset)/density, gap=Math.min(2,step*0.22)
        for(let index=0;index<density;index++)
            ctx.fillRect(sideInset+index*step+gap/2,ceiling,Math.max(0,step-gap),Math.max(0,plotBottom-ceiling))
        ctx.restore()
        ctx.beginPath();trace(ctx,samples)
        ctx.strokeStyle=Qt.rgba(ink.r,ink.g,ink.b,Math.max(0,Math.min(1,curveOpacity)))
        ctx.lineWidth=strokeWidth;ctx.lineCap="round";ctx.lineJoin="round";ctx.stroke()
    }
}

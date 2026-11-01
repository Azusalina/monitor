import QtQuick
import QtTest
import "../plasmoid/contents/ui"
Item {
    width:400;height:220
    CavaWave { id:wave;width:360;height:100;ink:"#44aaff";blockInk:"#ff5533";transitionDuration:120 }
    TestCase {
        name:"FittedCavaWave"
        when:windowShown
        function save(path) {
            let done=false
            verify(wave.grabToImage(result=>{verify(result.saveToFile(path));done=true}))
            tryVerify(()=>done,3000)
        }
        function init() { wave.values=[];wave.width=360;wave.height=100;wave.headroomPercent=20;wave.blockCount=32;wave.gradientBlocks=false;wave.blockInk="#ff5533" }
        function test_01_peakAndStrokeStayBelowTopGap() {
            wave.values=Array(32).fill(1)
            tryCompare(wave,"mix",1,1000)
            for(const point of wave.points())verify(point.y-wave.strokeWidth/2>=20-0.001)
            save("../docs/cava-headroom-max.png")
        }
        function test_02_densityOnlyChangesBlocksNotCurve() {
            wave.values=[0.05,0.8,0.2,0.95,0.35,0.7,0.1]
            tryCompare(wave,"mix",1,1000)
            const before=JSON.stringify(wave.points())
            wave.blockCount=8;compare(wave.density,8)
            save("../docs/cava-blocks-8.png")
            wave.blockCount=64;compare(wave.density,64)
            compare(JSON.stringify(wave.points()),before)
            save("../docs/cava-blocks-64.png")
        }
        function test_03_interruptedTransitionPreservesEnvelope() {
            wave.values=[0.1,0.8,0.2,0.5]
            tryCompare(wave,"mix",1,1000)
            wave.values=[0.8,0.2,1,0.3]
            wait(50)
            const before=wave.displayed()
            wave.values=[0.4,1,0.1,0.8]
            const after=wave.displayed()
            for(let i=0;i<before.length;i++)fuzzyCompare(after[i],before[i],0.0001)
            tryCompare(wave,"mix",1,1000)
            for(const point of wave.points())verify(point.y-wave.strokeWidth/2>=wave.topGap-0.001)
        }
        function test_04_gapAndColorCustomization() {
            wave.values=Array(32).fill(1)
            wave.headroomPercent=40;wave.blockInk="#99cc55"
            tryCompare(wave,"mix",1,1000)
            compare(wave.topGap,40)
            compare(wave.blockInk,"#99cc55")
            save("../docs/cava-headroom-custom.png")
            wave.gradientBlocks=true
            save("../docs/cava-focus-gradient.png")
        }
        function test_045_tinySurfaceDoesNotClipPeaks() {
            wave.values=[1,1,1]
            tryCompare(wave,"mix",1,1000)
            wave.height=3
            compare(wave.points().length,0)
        }
        function test_05_invalidSamplesAndEmptyAreSafe() {
            wave.values=[NaN,Infinity,-1,2]
            tryCompare(wave,"mix",1,1000)
            compare(wave.displayed().join(","),"0,0,0,1")
            wave.values=[]
            compare(wave.points().length,0)
            save("../docs/cava-empty.png")
        }
    }
}

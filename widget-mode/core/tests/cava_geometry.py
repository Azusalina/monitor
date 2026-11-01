"""Inspect rendered CAVA fixtures: clear headroom and blocks inside the curve."""
import math
from pathlib import Path
from PIL import Image
root=Path(__file__).parents[2]/'docs'
for filename,gap in [('cava-headroom-max.png',20),('cava-headroom-custom.png',40),('cava-focus-gradient.png',40)]:
    im=Image.open(root/filename).convert('RGBA')
    assert im.getchannel('A').crop((0,0,im.width,gap-1)).getbbox() is None, filename
    assert im.getchannel('A').getbbox() is not None, filename
samples=[0.05,0.8,0.2,0.95,0.35,0.7,0.1]
for filename in ('cava-blocks-8.png','cava-blocks-64.png'):
    im=Image.open(root/filename).convert('RGBA')
    points=[(3.25+i/6*(360-6.5),96.75-v*75.5) for i,v in enumerate(samples)]
    red=blue=0
    for x in range(im.width):
        if not points[0][0]<=x+0.5<=points[-1][0]:continue
        segment=min(5,int((x+0.5-points[0][0])/(points[-1][0]-points[0][0])*6))
        ax,ay=points[segment];bx,by=points[segment+1];mid=(ax+bx)/2
        low,high=0.,1.
        for _ in range(28):
            t=(low+high)/2;u=1-t
            cx=u*u*u*ax+3*u*u*t*mid+3*u*t*t*mid+t*t*t*bx
            if cx<x+0.5:low=t
            else:high=t
        t=(low+high)/2;smooth=3*t*t-2*t*t*t
        top=ay+(by-ay)*smooth
        for y in range(im.height):
            r,g,b,a=im.getpixel((x,y))
            if a and r>g*1.5 and r>b*1.5:
                red+=1
                assert y+0.5>=top-1.1,(filename,x,y,top)
            if a and b>r*1.5:blue+=1
    assert red>100 and blue>50,(filename,red,blue)
im=Image.open(root/'cava-headroom-custom.png').convert('RGBA')
assert any(a>40 and abs(r-153)<4 and abs(g-204)<4 and abs(b-85)<4 for r,g,b,a in (im.getpixel((x,y)) for y in range(im.height) for x in range(im.width)))
assert Image.open(root/'cava-empty.png').getchannel('A').getbbox() is None
print('Rendered CAVA blocks follow the shared curve at both densities; custom colors and transparent top gaps passed.')

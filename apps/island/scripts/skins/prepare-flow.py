"""Solve steady incompressible flow inside the official brand silhouette.

Each connected component is a small channel: fixed potential at its diagonal
inlet/outlet, reflecting (zero normal flux) walls. Red/black SOR solves Laplace's
equation; midpoint integration traces its velocity field. This runs at build
time, so the app only interpolates a compact set of original-shape streamlines.
No network or replacement lettering is involved.
"""
from pathlib import Path
from collections import deque
import json, math
import numpy as np
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[2] / 'SettingsWeb/dist'
geometry = json.loads((root / 'brand-geometry.json').read_text())
w, h, pad = 840, 189, 3
mask = np.zeros((h + 2*pad, w + 2*pad), bool)
for poly in geometry['paths']:
    raster = Image.new('1', (w + 2*pad, h + 2*pad))
    ImageDraw.Draw(raster).polygon([(pad+x*(w-1), pad+y*(h-1)) for x,y in poly], fill=1)
    mask ^= np.asarray(raster)

remaining = mask.copy()
components = []
for sy, sx in zip(*np.nonzero(mask)):
    if not remaining[sy,sx]: continue
    queue=deque([(sy,sx)]); remaining[sy,sx]=False; coords=[]
    while queue:
        y,x=queue.popleft(); coords.append((y,x))
        for yy,xx in [(y-1,x),(y+1,x),(y,x-1),(y,x+1)]:
            if remaining[yy,xx]: remaining[yy,xx]=False; queue.append((yy,xx))
    if len(coords)>8: components.append(np.array(coords))

lanes=[]; diagnostics=[]
for coords in components:
    y0,x0=coords.min(axis=0)-2; y1,x1=coords.max(axis=0)+3
    m=mask[y0:y1,x0:x1].copy(); yy,xx=np.indices(m.shape)
    # Exclude nearby but disconnected glyphs from this component's solve.
    m[:]=False; m[coords[:,0]-y0,coords[:,1]-x0]=True
    along=(xx-yy).astype(float); lo,hi=along[m].min(),along[m].max()
    q=(along-lo)/max(1,hi-lo)
    inlet=m&(q<.02); outlet=m&(q>.98); fixed=inlet|outlet
    phi=np.clip(q,0,1); phi[~m]=0
    neighbors=[np.roll(m,d,axis) for axis,d in [(0,1),(0,-1),(1,1),(1,-1)]]
    degree=sum(n.astype(float) for n in neighbors); degree[degree==0]=1
    parity=(xx+yy)%2; unknown=m&~fixed
    for iteration in range(2200):
        delta=0
        for color in [0,1]:
            total=sum(np.roll(phi,d,axis)*n for (axis,d),n in zip([(0,1),(0,-1),(1,1),(1,-1)],neighbors))
            residual=total/degree-phi
            active=unknown&(parity==color)
            if iteration%100==0 and active.any(): delta=max(delta,float(abs(residual[active]).max()))
            phi[active]+=1.85*residual[active]
        if iteration>100 and iteration%100==0 and delta<1e-5: break
    # Centered derivative with mirrored wall samples gives zero wall-normal flow.
    right=np.where(neighbors[3],np.roll(phi,-1,1),phi)
    left=np.where(neighbors[2],np.roll(phi,1,1),phi)
    down=np.where(neighbors[1],np.roll(phi,-1,0),phi)
    up=np.where(neighbors[0],np.roll(phi,1,0),phi)
    vx=(right-left)/2; vy=(down-up)/2
    def sample(x,y):
        ix,iy=int(x),int(y)
        if ix<0 or iy<0 or ix+1>=m.shape[1] or iy+1>=m.shape[0]: return None
        fx,fy=x-ix,y-iy
        weights=np.array([(1-fx)*(1-fy),fx*(1-fy),(1-fx)*fy,fx*fy])
        cells=[(iy,ix),(iy,ix+1),(iy+1,ix),(iy+1,ix+1)]
        weights*=np.array([m[a,b] for a,b in cells]); norm=weights.sum()
        if norm<.45:return None
        return np.array([sum(vx[a,b]*c for (a,b),c in zip(cells,weights)),sum(vy[a,b]*c for (a,b),c in zip(cells,weights))])/norm
    # Seed by area, then trace in both directions. Channels carry their own
    # width/flux weighting, retaining coverage at branches and in small glyphs.
    candidates=coords[::max(1,len(coords)//120)]
    accepted=[]
    for sy,sx in candidates:
        x,y=float(sx-x0),float(sy-y0)
        if any((x-a)**2+(y-b)**2<7 for a,b in accepted):continue
        def trace(direction):
            p=np.array([x,y]); result=[]
            for step in range(900):
                v=sample(*p)
                if v is None:break
                speed=np.linalg.norm(v)
                if speed<1e-6:break
                mid=sample(*(p+direction*.3*v/speed))
                if mid is None:break
                norm=np.linalg.norm(mid)
                if norm<1e-6:break
                p+=direction*.6*mid/norm
                if step%3==0:result.append([round((p[0]+x0-pad)/(w-1),5),round((p[1]+y0-pad)/(h-1),5)])
                px,py=int(round(p[0])),int(round(p[1]))
                if px<0 or py<0 or py>=m.shape[0] or px>=m.shape[1] or not m[py,px]:break
            return result
        back=trace(-1); forward=trace(1)
        points=back[::-1]+forward
        if len(points)<4:continue
        # Keep a dense but bounded set. Length is in isotropic brand-width units.
        length=sum(math.hypot(b[0]-a[0],(b[1]-a[1])/geometry['aspect']) for a,b in zip(points,points[1:]))
        lanes.append({'points':points,'length':round(length,6),'speed':round(float(np.linalg.norm(sample(x,y))),6)})
        accepted.append((x,y))
    diagnostics.append({'pixels':len(coords),'iterations':iteration+1,'residual':delta,'lanes':len(accepted)})

(root/'brand-flow.json').write_text(json.dumps({'aspect':geometry['aspect'],'lanes':lanes,'solver':'laplace-neumann-sor','diagnostics':diagnostics},separators=(',',':')))
# A geometry-only preview makes wrong direction, holes and disconnected paths visible.
out=Image.new('RGB',(w,h),'#101112'); draw=ImageDraw.Draw(out)
for lane in lanes:draw.line([(x*(w-1),y*(h-1)) for x,y in lane['points']],fill='#a0aaa6',width=1)
out.save(root.parents[1]/'verification/skins-v2/brand-streamlines.png')
print(f'Solved {len(components)} components, {len(lanes)} streamlines')

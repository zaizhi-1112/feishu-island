"""Preserve official pixels, trim transparent padding, flatten official brand paths.
Sources are recorded in skins.json; no model-generated replacement artwork.
"""
from pathlib import Path
from PIL import Image,ImageDraw
import json,re,math
import numpy as np
root=Path(__file__).resolve().parents[2]/'SettingsWeb/dist'
for name in ['codex','claude','workbuddy']:
 p=root/f'pet-{name}.png'; im=Image.open(p).convert('RGBA'); box=im.getbbox()
 im=im.crop(box); im.thumbnail((720,720),Image.Resampling.LANCZOS); im.save(p)
 # Small avatar is the recognisable face, rather than an illegible full-body thumbnail.
 small=im.crop((0,0,im.width,min(im.height,int(im.width*.94))))
 small.thumbnail((192,192),Image.Resampling.LANCZOS);small.save(root/f'avatar-{name}.png')
s=(root/'virxact-logo.svg').read_text();paths=re.findall(r'<path[^>]+d="([^"]+)"',s)
polygons=[]
for d in paths:
 tokens=re.findall(r'[MLCZ]|-?\d+(?:\.\d+)?',d);i=0;current=[];point=(0,0)
 def norm(p):return [(p[0]-404.31)/1111.38,(p[1]-414.96)/249.7]
 while i<len(tokens):
  op=tokens[i];i+=1
  if op=='M':
   if current: polygons.append(current)
   point=tuple(map(float,tokens[i:i+2]));i+=2;current=[norm(point)]
  elif op=='L':point=tuple(map(float,tokens[i:i+2]));i+=2;current.append(norm(point))
  elif op=='C':
   a=point;b=tuple(map(float,tokens[i:i+2]));c=tuple(map(float,tokens[i+2:i+4]));e=tuple(map(float,tokens[i+4:i+6]));i+=6
   for step in range(1,13):
    t=step/12;u=1-t;current.append(norm((u**3*a[0]+3*u*u*t*b[0]+3*u*t*t*c[0]+t**3*e[0],u**3*a[1]+3*u*u*t*b[1]+3*u*t*t*c[1]+t**3*e[1])))
   point=e
  elif op=='Z':
   if current: current.append(current[0]);polygons.append(current);current=[]
 if current:polygons.append(current)
(root/'brand-geometry.json').write_text(json.dumps({'aspect':1111.38/249.7,'paths':polygons},separators=(',',':')))
# Rasterise exact official polygons once. Even/odd XOR preserves counters in lettering.
w,h=1600,360
mask=Image.new('1',(w,h))
for poly in polygons:
 part=Image.new('1',(w,h));ImageDraw.Draw(part).polygon([(x*w,y*h) for x,y in poly],fill=1)
 mask=Image.fromarray(np.logical_xor(np.asarray(mask),np.asarray(part)))
rgb=Image.new('RGBA',(w,h),'white');rgb.putalpha(mask.convert('L'));rgb.save(root/'virxact-logo.png')
small=rgb.crop((0,0,int(w*254.82/1111.38),h));small.thumbnail((192,192));small.save(root/'avatar-virxact.png')
print('Prepared official portraits and',len(polygons),'brand contours')

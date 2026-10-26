# Mide el error de convertir cada sala a HiRes 8x1 (2 colores por 8 pixeles, sin limite de tiles) frente al actual de tiles (208).
# Uso (desde SCUMM/V2): python TOOLS/medir8x1.py "Zak McKracken" carpeta_salida 1 2 3 ...   (hay que ejecutarlo con TOOLS en el path)
import sys,os
sys.path.insert(0,'.')
import lfl2gfx as L
d,out=sys.argv[1],sys.argv[2]
rooms=[int(x) for x in sys.argv[3:]]
em=L.default_map({})
tot=[0,0,0]
for r in rooms:
    b=L.load_lfl(os.path.join(d,'%02d.LFL'%r))
    try: w,h,img0=L.decode_room(b)
    except Exception: continue
    if h!=128 or w%8: continue
    img=[[em[p] for p in row] for row in img0]
    L.COLW={}
    new=[]
    for row in img:
        o=[]
        for x in range(0,w,8):
            o+=list(L.row_spec(tuple(row[x:x+8]))[0])
        new.append(o)
    e8=sum(new[y][x]!=img[y][x] for y in range(h) for x in range(w))/(w*h)
    L.RARITY=0.0; L.KEEP=[]; L.PROTECT=[]
    render,cur,nt,mw,et=L.convert_windowed(w,h,img,208,33)
    print('sala %02d %dx%d  tiles208: %.1f%%   8x1 libre: %.1f%%'%(r,w,h,et*100,e8*100),flush=True)
    sep=[[(255,0,255)]*w]
    L.write_png(os.path.join(out,'q%02d.png'%r),[[L.EGA[p] for p in row] for row in img0]+sep+render+sep+[[L.CHROMA[p] for p in row] for row in new])

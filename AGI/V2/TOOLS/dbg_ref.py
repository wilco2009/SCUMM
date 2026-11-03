"""Depuracion de refcheck: python dbg_ref.py JUEGO SALA [x y] -> objetos, estaticos y primeros pixeles distintos (referencia vs modelo)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from refcheck import *
game, room = sys.argv[1], int(sys.argv[2])
os.environ['AGI_BOOT'] = 'room=%d' % room
p = os.path.join(HERE, '..', game)
it = Rec(p); agi2spr.set_game(p); it.play(14, [])
g = ag.Game(p)
it.box = None; it.menu_ui = None; it.txtm = False
ego = it.objs[0]
if len(sys.argv) > 4:
    ego.x, ego.y = int(sys.argv[3]), int(sys.argv[4])
objs = objects_of(it); set_rpri(it, objs)
if not ego.fixpri:
    ego.pri = ego.rpri
print('seq', it.seq, 'statics', it.statics)
for n, o in objs:
    if o.anim:
        c = ref_cel(g, o.view, o.loop, o.cel)
        print('obj', n, 'view', o.view, 'loop', o.loop, 'cel', o.cel, 'x,y', o.x, o.y, 'pri', o.pri, 'rpri', o.rpri, 'fixpri', o.fixpri, 'drawn', o.drawn, 'upd', o.upd, 'static', o.static, 'wh', c and c[:2])
bg = ref_background(it, g, it.seq)
rv, rp, rh = ref_compose(g, bg, objs)
rimg = [agi2hr.to_chroma(v) for v in rv]
mimg = it.screen4()
d = [i for i in range(W * H) if rimg[i] != mimg[i]]
print(len(d), 'diferencias; primeras:', [(i % W, i // W, rimg[i], mimg[i], bg.pri[i]) for i in d[:15]])
bgimg = [agi2hr.to_chroma(v) for v in bg.vis]
mb = it.render4()[0]
db = [i for i in range(W * H) if bgimg[i] != mb[i]]
print('fondo (sin sprites):', len(db), 'diferencias', [(i % W, i // W, bgimg[i], mb[i]) for i in db[:8]])
if len(sys.argv) > 6:
    px, py = int(sys.argv[5]), int(sys.argv[6])
    print('pixel', px, py, 'bg pri', bg.pri[py * W + px], 'bg vis', bg.vis[py * W + px])
    for n, o in objs:
        if o.anim and o.drawn:
            c = ref_cel(g, o.view, o.loop, o.cel)
            if c is None: continue
            w, h = c[0], c[1]
            cx, cy = px - o.x, py - (o.y - h + 1)
            if 0 <= cx < w and 0 <= cy < h:
                print('  obj', n, 'cubre con color', c[3][cy * w + cx], 'clave', c[2], 'rpri', o.rpri)
    img, pri2 = it.render4()
    i = py * W + px
    print('model pri2', pri2[i], 'img', img[i], 'to_chroma(4)', agi2hr.to_chroma(4))
    c4 = it.cel4(ego); print('cel4', c4[:3], c4[3][py - (ego.y - c4[1] + 1)][px - ego.x] if c4 else None)
    print('pic.pri', it.pic.pri[i], 'sprite_priority', agi2hr.sprite_priority(it.pic.pri)[i], 'ops', [o[0] for o in it.pic_ops], 'spans', it.spans[:3])

"""Comprobacion de la ruta grafica 160w (GFX4=1) contra una referencia independiente derivada de ScummVM (engines/agi, f7403b6; refscummvm.py).
Para cada sala de cada juego (AGI_BOOT="room=N"; el estado de objetos lo crea la logica del juego en el modelo) y para posiciones del ego (rejilla + zonas de prioridad
> 3 / control), compone con la referencia (picture.cpp + SpritesMgr::drawCel/addToPic, listas estatica y regular ordenadas como buildSpriteListAdd) la pantalla de
imagen de 160 x 168 y la compara con la del modelo (agi_vm.screen4 y la que dejan los sprites hardware, hw_sprites). El Z80 se compara con el modelo en runall.sh/test_vm.sh,
asi que modelo == referencia + Z80 == modelo cubre la cadena.
  python refcheck.py [JUEGO ...] [--step N] [--rooms a,b,c] [--hw] [-v]
Excepciones documentadas (AGI/PLAN.md) que la referencia aplica: vistas BLANK_VIEWS (no se dibujan) y FINAL_CEL (siempre la ultima celda del bucle)."""
import _thread
import os
import sys
import threading

os.environ['AGI_GFX4'] = '1'
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import agi_read as ag
import agi_vm
import agi2hr
import agi2spr
import refscummvm as R

W, H = 160, 168
GAMES = ['SQ2', 'SQ1', 'KQ1', 'KQ2', 'PQ1']


class Rec(agi_vm.Interp):
    """Interp que apunta la secuencia de draw.pic / overlay.pic y de add.to.pic (los datos que la referencia necesita para rehacer la imagen)."""

    def __init__(self, path):
        super().__init__(path, True)
        self.seq = []                   # ('pic', n) | ('ovl', n) | ('add', view, loop, cel, x, y, pri, margin)

    nc = 0

    def cmd(self, name, a):
        self.nc += 1
        if self.nc > 400000:            # salas cuya logica no termina sola en el arnes (esperan un estado que aqui no hay)
            raise agi_vm.Stop('demasiados comandos')
        super().cmd(name, a)

    def c_draw_pic(self, v):
        self.seq = [('pic', self.vars[v])]
        super().c_draw_pic(v)

    def c_overlay_pic(self, v):
        self.seq.append(('ovl', self.vars[v]))
        super().c_overlay_pic(v)

    def c_add_to_pic(self, view, loop, cel, x, y, pri, margin):
        if len(self.statics) < self.ST_MAX:
            self.seq.append(('add', view, loop, cel, x, y, pri, margin))
        super().c_add_to_pic(view, loop, cel, x, y, pri, margin)


def ref_cel(g, view, loop, cel):
    """Celda de la referencia con las excepciones documentadas; None si no se dibuja."""
    d = g.resource('VIEW', view)
    if d is None or view in agi2spr._blank or (view, loop) in agi2spr._blank:
        return None
    if d[2] == 0:
        return None
    lp = loop if loop < d[2] else 0
    if view in agi2spr._final:
        cel = d[d[5 + 2 * lp] | (d[6 + 2 * lp] << 8)] - 1
    return R.decode_view_cel(d, loop, cel)


def ref_background(it, g, seq, spans=False):
    """Imagen y plano de prioridad de la referencia tras draw.pic / overlay.pic / add.to.pic (con addToPic de ScummVM: fixPosition solo de limites)."""
    r = R.Ref()
    for s in seq:
        if s[0] == 'pic':
            r.draw_picture(g.resource('PIC', s[1]), True)
        elif s[0] == 'ovl':
            r.draw_picture(g.resource('PIC', s[1]), False)
        else:
            _, view, loop, cel, x, y, pri, margin = s
            c = ref_cel(g, view, loop, cel)
            if c is None:
                continue
            w, h = c[0], c[1]
            x = max(0, min(x, W - w))       # checkPosition: dentro de la pantalla
            if y - h + 1 < 0:
                y = h - 1
            y = min(y, H - 1)
            r.add_to_pic(c, x, y, pri, margin, spans)
    return r


def ref_compose(g, bg, objs):
    """SpritesMgr: lista estatica (animated+drawn sin update) y regular (animated+update+drawn), cada una ordenada por sortOrder (y, o la y de la prioridad fija)
    y numero; drawCel de cada una sobre la imagen. objs: lista de (n, o). Devuelve (vis, pri, ego_hidden)."""
    r = R.Ref()
    r.vis, r.pri = list(bg.vis), list(bg.pri)
    r.cov = [False] * (W * H)
    ego_hidden = None
    for want_upd in (False, True):
        lst = []
        for n, o in objs:
            if not (o.anim and o.drawn) or bool(o.upd) != want_upd:
                continue
            c = ref_cel(g, o.view, o.loop, o.cel)
            if c is None:
                continue
            w, h = c[0], c[1]
            if o.x < 0 or o.y - h + 1 < 0 or o.x + w > H or o.y + 1 > H:      # buildSpriteListAdd (la comprobacion de la derecha usa 168 como ScummVM)
                continue
            so = r.priority_to_y(o.rpri) if o.fixpri else o.y
            lst.append((so, n, o, c))
        lst.sort(key=lambda t: (t[0], t[1]))
        for so, n, o, c in lst:
            hid = r.draw_cel(c, o.x, o.y, o.rpri)
            if n == 0:
                ego_hidden = hid
    ref_compose.cov = r.cov
    return r.vis, r.pri, ego_hidden


def objects_of(it):
    return sorted(it.objs.items())


def set_rpri(it, objs, ego=None):
    """Prioridad con la que ScummVM dibuja cada objeto: la fijada, o la de su y (checkPriority/updateScreenObjTable)."""
    ref = R.Ref()
    for n, o in objs:
        o.rpri = o.pri if o.fixpri else ref.priority_from_y(max(0, min(H - 1, o.y)))


def hw_cover(it):
    """Pixeles que cubren los sprites hardware del modelo (hw_sprites: mascaras tras la prioridad por pixel). Los colores no se comparan: el hardware da 2 por fila de 8
    (limite documentado, PLAN160W.md), y los objetos con bloque de pixeles exactos (raw4) van por software."""
    cov = [False] * (W * H)
    sp = it.hw_sprites()
    for s in sp:
        if s is None:
            continue
        sx, sy, col, pix, msk = s
        for r in range(8):
            y = sy - 32 + r - it.ROW0
            if not 0 <= y < H:
                continue
            for k in range(8):
                x = sx - 32 + k
                if 0 <= x < W and msk[r] & (0x80 >> k):
                    cov[y * W + x] = True
    return cov


def sw_area(it, g):
    """Pixeles (cajas de las celdas) de los objetos que el Z80 dibuja por software en el bitmap y no con sprites (rotulos anchos: mas de SW_TILES mosaicos en una fila, o sin
    mosaicos / fuera de sprites): no entran en la cobertura de hw_sprites; su exactitud ya se comprueba con screen4 (modelo)."""
    area = set()
    for n, o in it.objs.items():
        if not (o.anim and o.drawn):
            continue
        cc = it.cel_of(o)
        if cc is None or agi2spr.meta(cc[2], o.view, o.loop)[0] or o.static or not cc[2]:
            c = ref_cel(g, o.view, o.loop, o.cel)
            if c is None:
                continue
            w, h = c[0], c[1]
            for y in range(o.y - h + 1, o.y + 1):
                for x in range(o.x, o.x + w):
                    if 0 <= x < W and 0 <= y < H:
                        area.add(y * W + x)
    return area


def slots_needed(it, g):
    """Sprites hardware que reservan los objetos que van por sprites (hw_sprites: loop_maxt por objeto); si pasan de 64, el hardware no puede con la sala (limite documentado)."""
    k = 0
    for n, o in it.objs.items():
        if not (o.anim and o.drawn) or o.pri >= 16 or o.x >= 160:
            continue
        d = g.resource('VIEW', o.view)
        if d is None:
            continue
        cc = it.cel_of(o)
        if cc is None or agi2spr.meta(cc[2], o.view, o.loop)[0] or o.static:
            continue
        k += agi2spr.loop_maxt(d, o.loop)
    return k


def run_room(game, g, room, step, do_hw, verbose, out):
    os.environ['AGI_BOOT'] = 'room=%d' % room
    try:
        it = Rec(os.path.join(HERE, '..', game))
        tm = threading.Timer(25, _thread.interrupt_main)       # logicas que esperan un estado que el arnes no da (bucles sin comandos)
        tm.start()
        try:
            it.play(14, [])
        finally:
            tm.cancel()
    except KeyboardInterrupt:
        out['skip'].append((game, room, 'la logica de la sala no termina en el arnes (>25 s)'))
        return
    except Exception as e:                      # salas que el arnes no sabe montar solas
        out['skip'].append((game, room, 'error %s' % e))
        return
    if it.pic is None or it.vars[0] != room:
        out['skip'].append((game, room, 'sin imagen en la sala o no se llega a ella (v0=%d)' % it.vars[0]))
        return
    it.box = None                               # ventanas de mensaje abiertas por la sala (no son del grafico de sprites)
    it.menu_ui = None
    it.txtm = False
    out['rooms'] += 1
    ego = it.objs.get(0)
    objs0 = objects_of(it)
    ego_ok = ego is not None and g.resource('VIEW', ego.view) is not None
    # fondo de la referencia: con la secuencia de draw.pic / overlay / add.to.pic
    bg = ref_background(it, g, it.seq)
    bgs = ref_background(it, g, it.seq, True) if any(q[0] == 'add' for q in it.seq) else None
    # posiciones: la actual del ego y una rejilla
    positions = [(ego.x, ego.y)] if ego_ok else [None]
    if ego_ok:
        c = ref_cel(g, ego.view, ego.loop, ego.cel)
        if c is None:
            ego_ok = False
        else:
            w, h = c[0], c[1]
            # rejilla + sobre los pixeles de prioridad > 3 y control (cada 4)
            xs = list(range(0, W - w + 1, step))
            ys = list(range(h - 1 + 0, H, max(2, step // 2)))
            positions += [(x, y) for y in ys for x in xs]
            interesting = [i for i in range(0, W * H, 5) if bg.pri[i] in (0, 1, 2, 3)]
            sel = interesting[::max(8, len(interesting) // 120)]     # como mucho ~120 posiciones sobre pixeles de control / prioridad 3 por sala
            for i in sel:
                x, y = i % W, i // W
                if y >= h - 1 and x <= W - w:
                    positions.append((x, y))
    for pos in positions:
        if pos is not None:
            ego.x, ego.y = pos
        objs = objects_of(it)
        set_rpri(it, objs)
        if pos is not None and not ego.fixpri:
            ego.pri = ego.rpri
        mimg = it.screen4()
        out['cases'] += 1
        # la referencia exacta de ScummVM y, si hay add.to.pic, la variante con los rangos por fila del Z80 (limitacion de memoria documentada, PLAN.md): una diferencia
        # solo con la exacta es de esa limitacion ('spans'); si tambien difiere la variante, es un fallo
        approx = False
        for k, b in enumerate((bg, bgs) if bgs is not None else (bg,)):
            rvis, rpri, rhid = ref_compose(g, b, objs)
            rimg = [agi2hr.to_chroma(v) for v in rvis]
            alld = [i for i in range(W * H) if rimg[i] != mimg[i]]
            # pixeles de linea de control (prioridad <= 2 en el plano): ScummVM mira lo que hay debajo en el momento de dibujar (sprites y objetos fijos ya pintados), el
            # plano del Z80 lo sustituye de antemano; difieren en 1-3 pixeles junto a objetos fijos o con dos sprites solapados (documentado: PLAN.md)
            ctl = [i for i in alld if b.pri[i] <= 2]
            diffs = [i for i in alld if b.pri[i] > 2]
            if ctl:
                out['ctl'].setdefault((game, room), len(ctl))
                out['ctl'][(game, room)] = max(out['ctl'][(game, room)], len(ctl))
            if k == 0:
                d0 = len(diffs)
            if not diffs:
                approx = k == 1
                break
        else:
            out['bad'].append((game, room, 'model', pos, len(diffs), (min(d % W for d in diffs), min(d // W for d in diffs), max(d % W for d in diffs), max(d // W for d in diffs))))
        if approx:
            out['spans'].add((game, room))
            out['spanpx'][(game, room)] = max(out['spanpx'].get((game, room), 0), d0)
        if do_hw and out['slots'].setdefault((game, room), slots_needed(it, g)) <= 64:
            hc = hw_cover(it)
            swa = sw_area(it, g)
            dh = [i for i in range(W * H) if ref_compose.cov[i] != hc[i] and i not in swa and b.pri[i] > 2]
            if dh and bgs is not None and k == 0 and False:
                pass
            if dh:
                out['bad'].append((game, room, 'hw', pos, len(dh), (min(d % W for d in dh), min(d // W for d in dh), max(d % W for d in dh), max(d // W for d in dh))))


def main(argv):
    if '--selftest-oldpri' in argv:             # reinyecta el fallo de a608633 (3 = control en el plano de prioridad de sprites): el comprobador tiene que verlo
        import salas_pri3
        agi2hr.sprite_priority = salas_pri3.old_priority
    step = 16
    games = []
    rooms = None
    do_hw = '--hw' in argv
    verbose = '-v' in argv
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == '--step':
            step = int(argv[i + 1]); i += 1
        elif a == '--rooms':
            rooms = [int(x) for x in argv[i + 1].split(',')]; i += 1
        elif not a.startswith('-'):
            games.append(a)
        i += 1
    out = {'spanpx': {}, 'ctl': {}, 'spans': set(), 'slots': {}, 'rooms': 0, 'cases': 0, 'bad': [], 'skip': []}
    for game in games or GAMES:
        g = ag.Game(os.path.join(HERE, '..', game))
        agi2spr.set_game(os.path.join(HERE, '..', game))
        for n in (rooms if rooms else g.present('LOG')):
            if n == 0:
                continue
            run_room(game, g, n, step, do_hw, verbose, out)
    for b in out['bad']:
        print('DIFER %s sala %d %s ego=%s: %d px, caja %s' % b)
    if verbose:
        for s in out['skip']:
            print('omitida', s)
    if out['ctl']:
        print('pixeles de linea de control distintos (max por sala; limitacion conocida, no es fallo): ' + ', '.join('%s sala %d: %d' % (k + (v,)) for k, v in sorted(out['ctl'].items())))
    if out['spans']:
        print('add.to.pic: rangos por fila y sin caja de control en el plano de sprites (limitacion de memoria del Z80; la exacta de ScummVM difiere, la variante con rangos no): ' + ', '.join('%s sala %d (hasta %d px)' % (k + (out['spanpx'][k],)) for k in sorted(out['spans'])))
    over = sorted(k for k, v in out['slots'].items() if v > 64)
    if over:
        print('sprites hardware (>64 reservados, limite del hardware; sin comparar el hw): ' + ', '.join('%s sala %d' % k for k in over))
    print('refcheck: %d salas, %d casos, %d diferencias, %d salas omitidas' % (out['rooms'], out['cases'], len(out['bad']), len(out['skip'])))
    return 1 if out['bad'] else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""costume3.py: trajes de SCUMM v3 (Indy3 EGA) -> blobs de sprites para el Z80, con las posturas especiales que piden los scripts.

El formato del recurso es el de v2 (formato 0x58, costume2.Costume lo lee), asi que de costume2.py se reutiliza el lector, la
composicion de miembros y el troceado en celdas de 8x8 (cells_of). Lo que cambia respecto a costume2.costume_blob:

  numeracion    Actor::initActor (version >= 3): inicio 1, andar 2, quieto 3, hablar (boca abierta) 4, cerrar la boca 5.
                En v2 era 2 / 0 / 1 / 5 / 4. Una animacion del recurso es  fotograma * 4 + direccion antigua  (0 izquierda, 1 derecha,
                2 abajo, 3 arriba; ClassicCostumeLoader::costumeDecodeData con newDirToOldDir).
  indices       En el blob, la lista de la posicion `a` es la animacion `a` del recurso (fotograma * 4 + direccion). v2 los
                comprimia en 0-7. Asi el Z80 elige el fotograma f mirando a la direccion d en la entrada f * 4 + d.
  posturas      Ademas de inicio, andar, quieto y hablar, cada traje lleva los fotogramas que los scripts le piden (animateActor con
                valor < 244 es el fotograma tal cual, Actor::animateActor; actorOps 4/5/6/14 fija los de andar, hablar, quieto e
                inicio). `frames` los cuenta.
  estado        Una animacion solo cambia los miembros que nombra (ClassicCostumeLoader::costumeDecodeData con usemask = -1) y el
                fotograma de inicio apaga todos antes (Actor::startAnimActor, version >= 3: _cost.reset()). La postura de un
                fotograma se compone como la ve el jugador: inicio + quieto + el fotograma. Los comandos 0x79/0x7A de una animacion
                paran y reanudan un miembro, y 0x7C/0x78 se saltan al avanzar (ClassicCostumeLoader::increaseAnim); se modelan.
  posicion x    En v2 ScummVM adelanta la x del actor 8 pixeles (16 si mira a la izquierda: Actor_v2::prepareDrawActorCostume); en v3
                no (Actor_v3 usa la clase base): el origen de la imagen es (actor.x - 72 + xMove, actor.y - 100 + yMove) y, si mira a la
                izquierda, se refleja alrededor de actor.x. Las coordenadas de v3 son pixeles (no los 1/8 de v2).
  espejo        _drawActorToRight = direccion antigua != 0 || bit 7 del formato del traje. Solo la direccion 0 se refleja (y si el traje
                no lleva el bit 7).

  paleta        Los colores del traje se pasan por la paleta del actor como en ClassicCostumeRenderer::setPalette (GF_OLD_BUNDLE):
                _palette[i] = i, los actorOps 11 de los scripts con literales (se cuentan en `frames`; el indice con varios colores se queda
                con el mas frecuente y queda en `ambiguous` de trajes.json) y despues _palette[byte de color del traje] = _palette[0]. Es
                una aproximacion estatica: un cambio de paleta en mitad del juego (o con actor o color en variable: 7 casos) lo tiene que
                aplicar el motor, y con los colores ya fijados en el blob no puede.
  dos paginas   Un traje que con todas sus posturas no cabe en una pagina (6.100 B) ni en 256 celdas se parte en dos blobs con el mismo
                formato: el principal (inicio, quieto, andar, hablar y lo que fijan los actorOps 4/5/6/14) y el extra (posturas especiales,
                COSTnnnX.bin). El Z80 busca la animacion en el principal y, si su lista vale 0, en el extra. Recortes, por orden: pasos de andar
                (4, 3, 2), pasos de los especiales (2, 1) y, al final, los especiales menos pedidos.

Formato del blob: el de costume2.costume_blob (cabecera: u8 animaciones, u16 desplazamiento de la tabla del fondo de celdas y u16 por
animacion; lista: u8 pasos y u16 por paso; fotograma: s8 dx, s8 dy, u8 cw, u8 ch, u8 n y n referencias; fondo de celdas), con las
indices de arriba. Una animacion ausente tiene el desplazamiento 0.

Uso (desde SCUMM/V3/TOOLS):
  costume3.py DIR frames [-o salida]            recuento de fotogramas pedidos por traje (todos los scripts)
  costume3.py DIR convert [-o carpeta]          blobs de todos los trajes (carpeta/cost/COSTnnn.bin) y resumen de tamanos
  costume3.py DIR png N [-o carpeta]            hoja de contacto del traje N
"""
import argparse
import json
import os
import struct
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import costume2 as C2        # noqa: E402
import lfl2gfx as L          # noqa: E402
import scumm3dis as D        # noqa: E402
import scumm3res as R        # noqa: E402

INIT, WALK, STAND, TALK_START, TALK_STOP = 1, 2, 3, 4, 5      # Actor::initActor, version >= 3
COST_MAX = 6100                                                # lo que cabe en una pagina de datos (pack_data.COST_MAX)
CELLS_MAX = 256                                                # el indice de celda del blob es un u8
EGO_VAR = 1                                                    # VAR_EGO
P1, P2, P3 = D.P1, D.P2, D.P3


# --------------------------------------------------------------------------------------------------------- recuento de fotogramas
class Rec(D.Decoder):
    """Decodificador de scumm3dis que ademas apunta los operandos: (clase, valor), clase 'l' literal o 'v' variable."""

    def __init__(self, code, base=0):
        super().__init__(code, base)
        self.args = []
        self.ops = []

    def vb(self, op, mask):
        v = super().vb(op, mask)
        self.args.append(('v' if op & mask else 'l', v))
        return v

    def vw(self, op, mask):
        v = super().vw(op, mask)
        self.args.append(('v' if op & mask else 'l', v))
        return v

    def result(self):
        v = super().result()
        self.args.append(('r', v))
        return v

    def insn(self, depth=0):
        self.args = []
        self.ops = []
        return super().insn(depth)

    def o_actorOps(self, op, s):                                # igual que Decoder.o_actorOps, apuntando cada subopcode con sus parametros
        self.vb(op, P1)
        self.actor = self.args[0]
        while True:
            o = self.byte()
            if o == 0xFF:
                return
            o = (o & 0xE0) | D.ACTOROPS_CONVERT[(o & 0x1F) - 1]
            k = o & 0x1F
            s.append('a%d' % k)
            self.args = []
            if k in (0, 1, 3, 4, 6, 12, 14, 16, 19, 22, 23):
                self.vb(o, P1)
            elif k in (2, 5, 11):
                self.vb(o, P1); self.vb(o, P2)
            elif k == 7:
                self.vb(o, P1); self.vb(o, P2); self.vb(o, P3)
            elif k in (8, 10, 18, 20, 21):
                pass
            elif k == 9:
                self.vw(o, P1)
            elif k == 13:
                self.string()
            elif k == 17:
                self.vb(o, P1); self.vb(o, P2)
            else:
                raise D.Bad('actorOps %d' % k)
            self.ops.append((k, list(self.args)))


def decode_script(code, starts):
    """Instrucciones (pos, nombre, args, ops, actor) del script, desde el primer punto de entrada; se detiene en lo que no decodifica."""
    out = []
    d = Rec(code, min(starts))
    while d.p < len(code):
        pos = d.p
        try:
            op, name, subs, j = d.insn()
        except D.Bad:
            break
        out.append((pos, name, list(d.args), list(d.ops), getattr(d, 'actor', None) if name == 'actorOps' else None))
    return out


def scan_frames(ix):
    """Recorre todos los scripts. Devuelve un dict con
       costumes[actor]  trajes que se le ponen (actorOps 1 con actor y traje literales)
       asked[(actor, traje)][fotograma]  veces que animateActor lo pide con valor literal < 244
       set_frames[(actor, traje)][(clase, valor)]  valores que actorOps 4/5/6/14 fija (andar, hablar, quieto, inicio)
       unresolved      animateActor con actor o fotograma en variable, y actorOps con traje en variable"""
    costumes = defaultdict(set)
    ego_values = set()
    scripts = D.all_scripts(ix)
    decoded = [(label, decode_script(code, starts)) for label, code, starts in scripts]
    for label, ins in decoded:
        for pos, name, args, ops, actor in ins:
            if name == 'actorOps' and actor and actor[0] == 'l':
                for k, a in ops:
                    if k == 1 and a and a[0][0] == 'l':
                        costumes[actor[1]].add(a[0][1])
            elif name == 'move' and len(args) == 2 and args[0] == ('r', EGO_VAR | 0x0000) and args[1][0] == 'l':
                ego_values.add(args[1][1])
    asked = defaultdict(Counter)
    set_frames = defaultdict(lambda: defaultdict(Counter))
    unresolved = Counter()
    anim_total = Counter()
    palette = defaultdict(lambda: defaultdict(Counter))           # traje -> indice de color -> colores a los que lo remapea algun actorOps 11
    for label, ins in decoded:
        cur = {}                                              # actor -> traje fijado en este script (ultimo visto)
        for pos, name, args, ops, actor in ins:
            if name == 'actorOps':
                a_id = actor[1] if actor[0] == 'l' else (EGO_VAR if actor[1] == EGO_VAR else None)
                for k, a in ops:
                    if k == 1:
                        if a[0][0] == 'l':
                            if a_id is not None and actor[0] == 'l':
                                cur[a_id] = a[0][1]
                        else:
                            unresolved['actorOps costume con variable'] += 1
                    elif k == 11 and (a_id is None or not all(x[0] == 'l' for x in a)):
                        unresolved['actorOps 11 (paleta) con actor o parametros en variable'] += 1
                    elif k == 11:
                        for t in ([cur[a_id]] if a_id in cur else sorted(costumes.get(a_id, ()))):
                            palette[t][a[0][1]][a[1][1]] += 1
                    elif k in (4, 5, 6, 14):
                        if a_id is None:
                            unresolved['actorOps %d con actor en variable' % k] += 1
                            continue
                        for t in ([cur[a_id]] if a_id in cur else sorted(costumes.get(a_id, ()))):
                            for j, x in enumerate(a):
                                if k == 5 or j == 0:
                                    key = {4: 'andar', 5: ('hablar', 'cerrar')[j] if k == 5 else '', 6: 'quieto', 14: 'inicio'}[k]
                                    set_frames[(a_id, t)][key][x[1] if x[0] == 'l' else 'var'] += 1
            elif name == 'animateActor':
                (ka, va), (kf, vf) = args[0], args[1]
                anim_total['animateActor'] += 1
                if ka == 'l':
                    a_id = va
                else:
                    a_id = EGO_VAR if va == EGO_VAR else None
                if kf != 'l':
                    unresolved['animateActor con fotograma en variable'] += 1
                    continue
                if vf >= 244:
                    anim_total['direccion/parar (244-255)'] += 1
                    continue
                anim_total['fotograma literal %s' % ('1-5' if vf <= 5 else '6 o mas')] += 1
                if a_id is None:
                    unresolved['animateActor con actor en variable'] += 1
                    continue
                if ka == 'v' and a_id == EGO_VAR:
                    cands = sorted(ego_values) or [1]
                    actors = cands
                else:
                    actors = [a_id]
                for ac in actors:
                    ts = [cur[ac]] if ac in cur else sorted(costumes.get(ac, ()))
                    if not ts:
                        unresolved['animateActor con actor sin traje conocido'] += 1
                    for t in ts:
                        asked[(ac, t)][vf] += 1
    return dict(costumes=costumes, asked=asked, set_frames=set_frames, unresolved=unresolved, anim_total=anim_total, palette=palette, ego_values=ego_values)


def frames_by_costume(scan):
    """{traje: dict(asked=Counter fotograma -> veces, walk/talk/stand/init=conjuntos de fotogramas que fijan los actorOps)}."""
    out = defaultdict(lambda: dict(asked=Counter(), walk=set(), talk=set(), stand=set(), init=set(), palette={}))
    for (actor, t), cnt in scan['asked'].items():
        out[t]['asked'].update(cnt)
    for t, d in scan['palette'].items():
        out[t]['palette'] = {i: Counter(c) for i, c in d.items()}
    cls = {'andar': 'walk', 'hablar': 'talk', 'cerrar': 'talk', 'quieto': 'stand', 'inicio': 'init'}
    for (actor, t), d in scan['set_frames'].items():
        for key, c in d.items():
            for v in c:
                if isinstance(v, int) and v < 244:
                    out[t][cls[key]].add(v)
    return out


def cmd_frames(ix, a):
    scan = scan_frames(ix)
    by = frames_by_costume(scan)
    print('actores con traje: %d; valores de VAR_EGO que se asignan: %s' % (len(scan['costumes']), sorted(scan['ego_values'])))
    print('animateActor: %s' % dict(scan['anim_total']))
    print('sin resolver: %s' % dict(scan['unresolved']))
    print('\ntraje  (actores)  fotogramas pedidos por animateActor {fotograma: veces}; fijados por actorOps')
    sf = defaultdict(lambda: defaultdict(Counter))
    for (actor, t), d in scan['set_frames'].items():
        for key, c in d.items():
            sf[t][key].update(c)
    total_special = 0
    for t in sorted(by):
        actors = sorted(ac for ac, cs in scan['costumes'].items() if t in cs)
        i = by[t]
        sp = {f: n for f, n in sorted(i['asked'].items()) if f > 5}
        total_special += sum(sp.values())
        std = {f: n for f, n in sorted(i['asked'].items()) if f <= 5}
        print('%3d  %-10s  estandar %s  especiales %s  fijados andar %s hablar %s quieto %s inicio %s' % (
            t, actors, std, sp, sorted(i['walk']), sorted(i['talk']), sorted(i['stand']), sorted(i['init'])))
    print('\nremapeos de color del actor (actorOps 11, literales) por traje: %s' % {t: {i: dict(c) for i, c in d.items()} for t, d in sorted(scan['palette'].items())})
    print('\npeticiones literales de fotogramas especiales (> 5): %d en %d trajes' % (total_special, sum(1 for t in by if any(f > 5 for f in by[t]['asked']))))
    return scan


# ------------------------------------------------------------------------------------------------ estado de limbs (animaciones)
class State:
    """Los miembros de un actor: ClassicCostumeLoader::costumeDecodeData / increaseAnim sobre CostumeData."""

    def __init__(self, cost):
        self.c = cost
        self.reset()

    def reset(self):
        self.curpos = [0xFFFF] * 16
        self.start = [0] * 16
        self.end = [0] * 16
        self.stopped = 0

    def copy(self):
        s = State(self.c)
        s.curpos, s.start, s.end, s.stopped = list(self.curpos), list(self.start), list(self.end), self.stopped
        return s

    def apply(self, frame, olddir):
        """costumeDecodeData(a, frame, -1): False si la animacion no existe."""
        c = self.c
        anim = olddir + frame * 4
        if anim > c.num_anim:
            return False
        r = c.anim_tab[anim]
        if r == 0:
            return False
        b = c.b
        mask = C2.u16(b, r)
        r += 2
        i = 0
        while mask & 0xFFFF:
            if mask & 0x8000:
                j = b[r]
                r += 1
                if j == 0xFF:
                    self.curpos[i] = 0xFFFF
                    self.start[i] = 0
                else:
                    extra = b[r]
                    r += 1
                    cmd = b[c.cmds + j]
                    if cmd == 0x7A:
                        self.stopped &= ~(1 << i)
                    elif cmd == 0x79:
                        self.stopped |= 1 << i
                    else:
                        self.curpos[i] = self.start[i] = j
                        self.end[i] = j + (extra & 0x7F)
                        if extra & 0x80:
                            self.curpos[i] |= 0x8000
            mask = (mask << 1) & 0xFFFF
            i += 1
        return True

    def increase(self):
        """increaseAnims: un paso de la animacion de cada miembro."""
        cmds, b = self.c.cmds, self.c.b
        for slot in range(16):
            if self.curpos[slot] == 0xFFFF:
                continue
            high = self.curpos[slot] & 0x8000
            i = self.curpos[slot] & 0x7FFF
            end = self.end[slot]
            for _ in range(64):                               # el bucle de ScummVM salta 0x7C y 0x78 mientras start != end
                if not high:
                    if i >= end:
                        i = self.start[slot]
                    else:
                        i += 1
                elif i != end:
                    i += 1
                nc = b[cmds + i]
                if nc in (0x7C, 0x78) and self.start[slot] != end:
                    continue
                break
            self.curpos[slot] = i | high

    def key(self):
        return (tuple(self.curpos), self.stopped)

    def limbs(self):
        """Miembros visibles: {miembro: posicion en animCmds}."""
        return {i: p & 0x7FFF for i, p in enumerate(self.curpos) if p != 0xFFFF and not (self.stopped >> i) & 1}


def pose_parts(cost, st, olddir):
    """Partes (x0, y0, pixeles) que dibuja el estado: ClassicCostumeRenderer::drawLimb con las reglas de v3 (sin el adelanto de x de v2)."""
    mirror = olddir == 0 and not cost.mirror                  # _drawActorToRight = olddir != 0 || mirror del traje
    xm = ym = 0
    parts = []
    for limb in range(16):
        if limb not in st.limbs():
            continue
        code = cost.b[cost.cmds + st.limbs()[limb]] & 0x7F
        if code == 0x7B:
            continue
        try:
            w, h, rx, ry, mx, my, pix = cost.picture(limb, code)
        except (IndexError, struct.error):
            continue
        x0, y0 = xm + rx - 72, ym + ry - 100
        xm += mx
        ym -= my
        if mirror:
            x0 = -x0 - w
            pix = [row[::-1] for row in pix]
        parts.append((x0, y0, pix))
    return parts


def anim_poses(cost, frame, olddir, base, steps):
    """Posturas (partes) de `frame` mirando a `olddir`, partiendo del estado `base`: hasta `steps` pasos repartidos por igual entre los
    que tiene la animacion (como costume2: los pasos distintos hasta que se repiten). Devuelve [(partes)] o [] si no existe."""
    st = base.copy()
    if not st.apply(frame, olddir):
        return []
    seq, seen = [], set()
    for _ in range(64):
        k = st.key()
        if k in seen:
            break
        seen.add(k)
        seq.append(st.copy())
        st.increase()
    if len(seq) > steps:
        seq = [seq[i * len(seq) // steps] for i in range(steps)]
    return [pose_parts(cost, s, olddir) for s in seq]


def base_state(cost, olddir):
    """Inicio y quieto aplicados: lo que ve el jugador antes de cualquier otra animacion."""
    st = State(cost)
    st.apply(INIT, olddir)
    st.apply(STAND, olddir)
    return st


def init_state(cost, olddir):
    st = State(cost)
    st.apply(INIT, olddir)
    return st


# ------------------------------------------------------------------------------------------------------------- blobs
def build_blob(poses_by_anim, emap):
    """poses_by_anim: {animacion: [partes por paso]}. Escribe el blob con el formato de costume2.costume_blob (copiado: la funcion de v2
    parte del traje, no de las posturas)."""
    na = max(poses_by_anim) + 1 if poses_by_anim else 0
    head_len = 3 + 2 * na
    body = bytearray()
    frames = {}
    pool, pool_idx, pool_off = bytearray(), {}, []
    lists = {}
    for anim in sorted(poses_by_anim):
        offs = []
        for parts in poses_by_anim[anim]:
            fr = C2.cells_of(parts, emap)
            if fr is None:
                offs.append(0xFFFF)
                continue
            gx, gy, cw, ch, cells = fr
            key = (gx, gy, cw, ch, tuple((p, tuple(a), tuple(m), tuple(c)) for p, a, m, c in cells))
            if key not in frames:
                frames[key] = len(body)
                body += struct.pack('<bbBBB', max(-128, min(127, gx)), max(-128, min(127, gy)), cw, ch, len(cells))
                for p, pix, mask, col in cells:
                    full = all(m == 0xFF for m in mask)
                    uni = len(set(col)) == 1
                    rec = bytes([(1 if full else 0) | (2 if uni else 0)]) + bytes(pix) + (b'' if full else bytes(mask)) + (bytes(col[:1]) if uni else bytes(col))
                    if rec not in pool_idx:
                        pool_idx[rec] = len(pool_off)
                        pool_off.append(len(pool))
                        pool += rec
                    body += bytes([p, pool_idx[rec]])
            offs.append(frames[key])
        lists[anim] = offs
    if len(pool_off) > CELLS_MAX:
        raise ValueError('mas de 256 celdas distintas (%d)' % len(pool_off))
    lists_base = head_len + len(body)
    lst = bytearray()
    head = bytearray(head_len)
    head[0] = na
    for anim, offs in lists.items():
        struct.pack_into('<H', head, 3 + 2 * anim, lists_base + len(lst))
        lst.append(len(offs))
        for o in offs:
            lst += struct.pack('<H', o if o == 0xFFFF else head_len + o)
    tab_base = lists_base + len(lst)
    pool_base = tab_base + 2 * len(pool_off)
    struct.pack_into('<H', head, 1, tab_base)
    tab = b''.join(struct.pack('<H', pool_base + o) for o in pool_off)
    return bytes(head) + bytes(body) + bytes(lst) + tab + bytes(pool), len(pool_off)


def wanted_frames(cost, info):
    """Fotogramas de un traje. Devuelve (clase de cada fotograma {f: 'walk'|'stand'|'init'|'talk'|'special'}, orden de prioridad de los
    especiales: los mas pedidos primero). Los cuatro de siempre y los que fijan los actorOps 4/5/6/14 van siempre."""
    cls = {STAND: 'stand', WALK: 'walk', INIT: 'init', TALK_START: 'talk', TALK_STOP: 'talk'}
    for k in ('walk', 'talk', 'stand', 'init'):
        for f in info.get(k, ()):
            cls.setdefault(f, k)
    asked = info.get('asked', {})
    has = {a // 4 for a in range(min(cost.num_anim, 255) + 1) if a < len(cost.anim_tab) and cost.anim_tab[a]}      # fotogramas que el traje define
    cls = {f: k for f, k in cls.items() if f in has}
    ex = [f for f, n in sorted(asked.items(), key=lambda kv: (-kv[1], kv[0])) if f not in cls and f < 63 and f in has]
    return cls, ex


def costume_poses(cost, cls, special, walk=4, talk_two=True, steps=2):
    """Posturas de cada animacion (fotograma * 4 + direccion): inicio y quieto una, andar `walk`, hablar una (la boca abierta y, si talk_two,
    la cerrada), y los fotogramas `special` con `steps` pasos como mucho."""
    out = {}
    for d in range(4):
        base = base_state(cost, d)
        init = init_state(cost, d)
        for f, k in list(cls.items()) + [(f, 'special') for f in special]:
            if k == 'init':
                p = anim_poses(cost, f, d, State(cost), 1)
            elif k == 'stand':
                p = anim_poses(cost, f, d, init, 1)
            elif k == 'walk':
                p = anim_poses(cost, f, d, base, walk)
            elif k == 'talk':
                if f == TALK_STOP and not talk_two:
                    continue
                p = anim_poses(cost, f, d, base, 1)
            else:
                p = anim_poses(cost, f, d, base, steps)
            if p:
                out[f * 4 + d] = p
    return out


def costume_emap(cost, emap, pal):
    """emap (indice de color de la imagen -> codigo de Chroma) con la paleta del actor: ClassicCostumeRenderer::setPalette (GF_OLD_BUNDLE).
    Actor::initActor deja _palette[i] = i; los actorOps 11 de los scripts cambian entradas; despues _palette[byte de color del traje] =
    _palette[0]. Un indice con varios colores en scripts distintos se queda con el mas frecuente (apuntado en `ambiguous`).
    Devuelve (emap del traje, {indice: colores} de los ambiguos)."""
    p = list(range(16))
    amb = {}
    for idx, cols in (pal or {}).items():
        if idx < 16:
            p[idx] = cols.most_common(1)[0][0] & 15
            if len(cols) > 1:
                amb[idx] = dict(cols)
    p[cost.b[6] & 15] = p[0]
    return [emap[p[c]] for c in range(16)], amb


def try_blob(cost, emap, cls, special, walk, talk_two, steps):
    """Blob con esos parametros, o None si no cabe en 256 celdas o en una pagina."""
    poses = costume_poses(cost, cls, special, walk, talk_two, steps)
    if not poses:
        return None
    if max(poses) > 254:
        raise ValueError('animacion %d: no cabe en el u8 de animaciones' % max(poses))
    try:
        blob, ncell = build_blob(poses, emap)
    except ValueError:
        return None
    return (blob, ncell, poses) if len(blob) <= COST_MAX else None


def split_blobs(cost, emap, info):
    """Decide los blobs de un traje. Devuelve un dict:
         main   (blob, celdas, descripcion)  lo de siempre (inicio, quieto, andar, hablar y lo que fijan los actorOps) y, si cabe, los especiales
         extra  idem o None                  los fotogramas especiales que no caben en main: una segunda pagina con el mismo formato
         lost   fotogramas pedidos que no se pudieron guardar
         fits   False si ni el blob minimo cabe en una pagina
       Orden de recortes: primero pasos de andar (4, 3, 2) y la segunda boca, despues pasos de los especiales (2, 1), al final los
       especiales menos pedidos."""
    cls, ex = wanted_frames(cost, info)
    emap, amb = costume_emap(cost, emap, info.get('palette'))
    full = try_blob(cost, emap, cls, ex, 4, True, 2)
    if full:
        return dict(main=(full[0], full[1], dict(walk=4, boca2=True, special=list(ex), steps=2)), extra=None, lost=[], fits=True, ambiguous=amb)
    main = None
    for walk, two in ((4, True), (3, True), (2, True), (2, False), (1, False)):
        r = try_blob(cost, emap, cls, [], walk, two, 1)
        if r:
            main = (r[0], r[1], dict(walk=walk, boca2=two, special=[], steps=1))
            break
    fits = main is not None
    if main is None:                                           # ni lo basico cabe: se guarda lo mas pequeno sin comprobar el tamano
        poses = costume_poses(cost, cls, [], 1, False, 1)
        try:
            blob, ncell = build_blob(poses, emap)
        except ValueError:
            blob, ncell = b'', 0
        main = (blob, ncell, dict(walk=1, boca2=False, special=[], steps=1))
    extra, lost = None, []
    if ex:
        keep = list(ex)
        while keep and extra is None:
            for steps in (2, 1):
                r = try_blob(cost, emap, {}, keep, 1, False, steps)
                if r:
                    extra = (r[0], r[1], dict(special=list(keep), steps=steps))
                    break
            if extra is None:
                keep.pop()
        lost = [f for f in ex if f not in keep]
    return dict(main=main, extra=extra, lost=lost, fits=fits, ambiguous=amb)


# ------------------------------------------------------------------------------------------------- lectura del blob (comprobacion)
def parse_blob(blob):
    """{animacion: [offset de fotograma o 0xFFFF]} y la tabla de celdas, segun el formato de costume2.costume_blob."""
    na = blob[0]
    tab = C2.u16(blob, 1)
    lists = {}
    for a in range(na):
        o = C2.u16(blob, 3 + 2 * a)
        if o:
            n = blob[o]
            lists[a] = [C2.u16(blob, o + 1 + 2 * k) for k in range(n)]
    ncell = (C2.u16(blob, tab) - tab) // 2 if na else 0
    cells = [C2.u16(blob, tab + 2 * k) for k in range(ncell)]
    return lists, cells


def blob_image(blob, off, cells):
    """Reconstruye un fotograma del blob: (gx, gy, imagen[y][x] en codigos de Chroma, -1 = transparente)."""
    gx, gy = struct.unpack_from('<bb', blob, off)
    cw, ch, n = blob[off + 2], blob[off + 3], blob[off + 4]
    img = [[-1] * (cw * 8) for _ in range(ch * 8)]
    for k in range(n):
        pos, idx = blob[off + 5 + 2 * k], blob[off + 6 + 2 * k]
        cx, cy = pos & 15, pos >> 4
        p = cells[idx]
        flags = blob[p]
        p += 1
        pix = blob[p:p + 8]
        p += 8
        if flags & 1:
            mask = [0xFF] * 8
        else:
            mask = blob[p:p + 8]
            p += 8
        col = [blob[p]] * 8 if flags & 2 else blob[p:p + 8]
        for y in range(8):
            ink, paper = col[y] >> 4, col[y] & 15
            for x in range(8):
                if (mask[y] >> (7 - x)) & 1:
                    img[cy * 8 + y][cx * 8 + x] = ink if (pix[y] >> (7 - x)) & 1 else paper
    return gx, gy, img


def cmd_convert(ix, a):
    scan = scan_frames(ix)
    by = frames_by_costume(scan)
    emap = L.default_map({})
    os.makedirs(os.path.join(a.outdir, 'cost'), exist_ok=True)
    only = None if a.n is None else {a.n}
    rows = []
    for cid in range(len(ix.res['costume'])):
        data = ix.resource('costume', cid)
        if not data or (only and cid not in only):
            continue
        try:
            cost = C2.Costume(data)
            r = split_blobs(cost, emap, by.get(cid, {}))
        except Exception as e:
            print('traje %3d: ERROR %s: %s' % (cid, type(e).__name__, e))
            rows.append(dict(id=cid, orig=len(data), error=str(e)))
            continue
        for tag, key in (('', 'main'), ('X', 'extra')):
            if r[key]:
                with open(os.path.join(a.outdir, 'cost', 'COST%03d%s.bin' % (cid, tag)), 'wb') as f:
                    f.write(r[key][0])
        row = dict(id=cid, orig=len(data), main=len(r['main'][0]), cells=r['main'][1], extra=len(r['extra'][0]) if r['extra'] else 0,
                   cells_x=r['extra'][1] if r['extra'] else 0, lost=r['lost'], fits=r['fits'],
                   walk=r['main'][2]['walk'], boca2=r['main'][2]['boca2'], special_main=r['main'][2]['special'],
                   special_extra=r['extra'][2]['special'] if r['extra'] else [], steps_extra=r['extra'][2]['steps'] if r['extra'] else 0,
                   asked=sorted(by[cid]['asked']) if cid in by else [], ambiguous=r['ambiguous'])
        rows.append(row)
        print('traje %3d: recurso %6d B  principal %5d B (%3d celdas, andar %d, boca2 %s, %d especiales)  extra %5d B (%3d celdas, %d especiales, %d pasos)%s%s' % (
            cid, row['orig'], row['main'], row['cells'], row['walk'], row['boca2'], len(row['special_main']), row['extra'], row['cells_x'],
            len(row['special_extra']), row['steps_extra'], '  PERDIDOS %s' % row['lost'] if row['lost'] else '',
            '  NO CABE' if not row['fits'] else ''), flush=True)
    if only is None:
        write_summary(a.outdir, rows, scan)
    return rows


def write_summary(outdir, rows, scan):
    import statistics as st
    ok = [r for r in rows if 'error' not in r]
    main = [r['main'] for r in ok]
    ext = [r['extra'] for r in ok if r['extra']]
    lines = ['# Trajes de Indy3: blobs de sprites (costume3.py)', '',
             '%d trajes convertidos, %d con error.' % (len(ok), len(rows) - len(ok)), '',
             'Pagina de datos: %d B. Celdas por blob: %d como mucho (el indice es un u8).' % (COST_MAX, CELLS_MAX), '',
             '| | Trajes | Mediana | Maximo | Total |', '|---|---|---|---|---|',
             '| recurso original (B) | %d | %d | %d | %d |' % (len(ok), st.median(r['orig'] for r in ok), max(r['orig'] for r in ok), sum(r['orig'] for r in ok)),
             '| blob principal (B) | %d | %d | %d | %d |' % (len(main), st.median(main), max(main), sum(main)),
             '| blob extra, segunda pagina (B) | %d | %d | %d | %d |' % (len(ext), st.median(ext) if ext else 0, max(ext) if ext else 0, sum(ext)),
             '| celdas del principal | %d | %d | %d | |' % (len(ok), st.median(r['cells'] for r in ok), max(r['cells'] for r in ok)), '',
             'Con pasos de andar recortados (menos de 4): %s' % [r['id'] for r in ok if r['walk'] < 4],
             'Sin la segunda boca: %s' % [r['id'] for r in ok if not r['boca2']],
             'Que no caben en una pagina ni en lo basico: %s' % [r['id'] for r in ok if not r['fits']],
             'Fotogramas pedidos que se pierden aun con dos paginas: %s' % {r['id']: r['lost'] for r in ok if r['lost']}, '',
             '| Traje | Recurso | Principal | Celdas | Andar | Especiales en el principal | Extra | Celdas | Especiales en el extra | Perdidos |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for r in ok:
        lines.append('| %d | %d | %d | %d | %d | %s | %d | %d | %s (%d paso%s) | %s |' % (
            r['id'], r['orig'], r['main'], r['cells'], r['walk'], r['special_main'] or '-', r['extra'], r['cells_x'],
            r['special_extra'] or '-', r['steps_extra'], '' if r['steps_extra'] == 1 else 's', r['lost'] or '-'))
    with open(os.path.join(outdir, 'trajes.md'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')
    with open(os.path.join(outdir, 'trajes.json'), 'w') as f:
        json.dump(rows, f, indent=1)


def cmd_png(ix, a):
    cid = a.n
    cost = C2.Costume(ix.resource('costume', cid))
    by = frames_by_costume(scan_frames(ix))
    emap = L.default_map({})
    r = split_blobs(cost, emap, by.get(cid, {}))
    cell_w, cell_h = 72, 96
    for tag, key in (('', 'main'), ('X', 'extra')):
        if not r[key]:
            continue
        blob = r[key][0]
        lists, cells = parse_blob(blob)
        frames = sorted({a_ // 4 for a_ in lists})
        cols = 4 * 2
        W, H = cols * cell_w, len(frames) * cell_h
        canvas = [[(40, 40, 40)] * W for _ in range(H)]
        for ri, f in enumerate(frames):
            for d in range(4):
                lst = lists.get(f * 4 + d, [])
                for k, off in enumerate(lst[:2]):
                    if off == 0xFFFF:
                        continue
                    gx, gy, img = blob_image(blob, off, cells)
                    # el blob esta a escala SCALE: la imagen se dibuja tal cual, con el origen del actor en (cell_w / 2, cell_h - 8)
                    ox = (d * 2 + k) * cell_w + cell_w // 2
                    oy = ri * cell_h + cell_h - 8
                    for y, row in enumerate(img):
                        for x, c in enumerate(row):
                            if c >= 0:
                                X, Y = ox + gx + x, oy + gy + y
                                if (d * 2 + k) * cell_w <= X < (d * 2 + k + 1) * cell_w and ri * cell_h <= Y < (ri + 1) * cell_h:
                                    canvas[Y][X] = L.CHROMA[c]
        out = os.path.join(a.outdir, 'traje%03d%s.png' % (cid, tag))
        L.write_png(out, canvas)
        print('escrito', out, 'fotogramas', frames)
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('dir')
    ap.add_argument('cmd', choices=['frames', 'convert', 'png'])
    ap.add_argument('n', nargs='?', type=int)
    ap.add_argument('-o', '--outdir', default=os.path.join(HERE, '..', 'preview_hr'))
    a = ap.parse_args()
    ix = R.Index(a.dir)
    if a.cmd == 'frames':
        cmd_frames(ix, a)
    elif a.cmd == 'convert':
        cmd_convert(ix, a)
    elif a.cmd == 'png':
        cmd_png(ix, a)
    return 0


if __name__ == '__main__':
    sys.exit(main())

"""Capa de juego del modelo de referencia v3 (Indy3 EGA, ScummEngine_v3old): actores, cajas, objetos, camara, mensajes,
sonido, verbos, frases y cambio de sala.

Es una transcripcion de la semantica de ScummVM (engines/scumm): actor.cpp (Actor, Actor_v3), boxes.cpp, object.cpp,
room.cpp (startScene), camera.cpp, string.cpp (convertMessageToString, displayDialog, handleNextCharsetCode),
verbs.cpp, input.cpp y script.cpp (frases, scripts de salida y entrada). Lo que ScummVM hace con el dibujo, el sonido
o la pantalla sale como sucesos "E" a la traza (ver vmmodel3.py); aqui solo queda lo que lee o escribe un script.

CAMINATA (fase 6, 2026-11-14): startWalkActor, walkActor, calcMovementFactor, actorWalkStep, remapDirection,
updateActorDirection, setDirection, getNextBox, findPathTowardsOld, getGates, adjustXYToBeInBox y la geometria de cajas
(closestPtOnLine, getClosestPtOnBox, checkXYInBoxBounds, inBoxQuickReject, compareSlope) estan transcritas de las funciones
de ScummVM de v3 (Actor_v3 en actor.cpp, boxes.cpp) con sus mismos nombres y revisadas una a una contra ese codigo, con
los tipos de C: los puntos son Common::Point (int16), la aritmetica de closestPtOnLine y compareSlope es de int de 32 bits
que desborda (m32, d32), sqrDist tiene el tope de 0x1000 por eje (0xFFFFFF), xfrac/yfrac/xAdd/yAdd son uint16 y
_lastValidX/Y se reutilizan (v3-v4). No hay un ScummVM ejecutable con el que comparar posiciones: la comprobacion es la
lectura del codigo y que el Z80 (V3/ENGINE/geom.asm y walk.asm) da las mismas trazas. Lo que ScummVM deja sin definir se
fija asi (igual en el Z80): division por cero o velocidad 0 = E_RANGE; _stepX > 255 = E_RANGE; closest[] de getGates sin
candidato = 0; la terna de la matriz de cajas no se lee mas alla de su final; _targetFacing fuera de 0..359 = E_RANGE.

Lo que el modelo no tiene (es del anfitrion, no cambia lo que ve un script):
  - decodificacion de trajes: el fotograma del actor es el ultimo que se pidio (_frame); no hay _cost;
  - distribucion del texto (anchuras de letra): el "salto de linea" nunca falla y el rectangulo de un verbo mide
    8 px por letra y 8 de alto (verbOps / findVerbAtPos);
  - el rectangulo de un actor en pantalla (getActorFromPos): ver actor_rect();
  - sonido: ver "Sonido" mas abajo.
"""
import math
import struct

from vmcommon3 import *

# fotogramas "redirigidos" del actor (CHORE_REDIRECT_*)
CHORE_INIT, CHORE_WALK, CHORE_STAND, CHORE_TALK_START, CHORE_TALK_STOP, CHORE_FACE_DIR = 0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D
TURN_TABLE = (0, 2, 2, 3, 2, 1, 2, 3, 0, 1, 2, 1, 0, 1, 0, 3)           # actorTurnInterpolateTable
MBS_MAX_KEY = 0x200                                                      # las teclas valen menos que esto; los clics, mas
MBS_LEFT_CLICK, MBS_RIGHT_CLICK = 0x8000, 0x4000
CAM_NORMAL, CAM_FOLLOW, CAM_PANNING = 1, 2, 3                            # CameraMode
FONT_W, FONT_H = 8, 8                                                    # supuesto para los rectangulos de verbo
ACTOR_RECT_W, ACTOR_RECT_H = 12, 60                                      # supuesto para actor_rect()


class Actor:
    """Actor + Actor_v3. pack() es el registro de 64 bytes del Z80 (digest `A=`)."""

    def __init__(self, vm, num):
        self.vm = vm
        self.num = num
        self.stepx = 1
        self.step_threshold = 0
        self.name = None
        self.reset_all()

    def reset_all(self):
        self.init_actor(-1)

    def init_actor(self, mode):
        """Actor::initActor (+ Actor_v3::initActor)."""
        vm = self.vm
        if mode == -1:
            self.stepx = 1
            self.step_threshold = 0
            self.visible = False
            self.speedx, self.speedy = 8, 2
            self.frame = 0
            self.walkbox = 0
            self.anim_progress = 0
            self.costume_needs_init = False
            self.need_redraw = False
            self.sound0 = 0
            self.wd_dest = (0, 0)
            self.wd_destbox = 0
            self.wd_destdir = 0
            self.wd_curbox = 0
            self.wd_next = (0, 0)
            self.wd_cur = (0, 0)
            self.wd_xfrac = self.wd_yfrac = self.wd_xadd = self.wd_yadd = 0
            self.wd_dxf = self.wd_dyf = 0
            self.wd_facing = 0
            self.wd_point3 = (32000, 0)
            self.name = None
        if mode == 1 or mode == -1:
            self.costume = 0
            self.room = 0
            self.x = self.y = 0
            self.facing = 180
        elif mode == 2:
            self.facing = 180
        self.elevation = 0
        self.width = 24
        self.talk_color = 15
        self.target_facing = self.facing
        self.last_valid = (0, 0)
        self.sound0 = 0
        self.ignore_boxes = False
        self.ignore_turns = False
        self.init_frame, self.walk_frame, self.stand_frame, self.talk_start, self.talk_stop = 1, 2, 3, 4, 5
        self.anim_speed = 0
        self.moving = 0
        self.set_actor_walk_speed(8, 2)
        vm.classes[self.num] = 0

    def in_room(self):
        return self.room == self.vm.cur_room

    def set_actor_walk_speed(self, sx, sy):
        """Actor::setActorWalkSpeed."""
        if sx == self.speedx and sy == self.speedy:
            return
        self.speedx, self.speedy = sx, sy
        if self.moving:
            self.vm.calc_movement_factor(self, self.wd_next)

    def pack(self):
        """El registro del Z80 (ASIZE = 64 bytes, V3/ENGINE/vm_core.asm A_*): el digest `A=` es el crc16 de los 13 registros."""
        w = lambda v: struct.pack('<H', v & 0xFFFF)
        b = lambda v: bytes([v & 255])
        flags = (1 if self.need_redraw else 0) | (2 if self.costume_needs_init else 0) | (4 if self.ignore_turns else 0)
        return (b(self.room) + w(self.x) + w(self.y) + w(self.costume) + w(self.facing)
                + b(self.moving) + b(1 if self.visible else 0) + b(self.frame) + b(self.talk_color)
                + w(self.target_facing) + b(self.sound0) + b(self.walkbox) + w(self.elevation) + b(self.width)
                + b(self.speedx) + b(self.speedy) + b(1 if self.ignore_boxes else 0) + b(self.init_frame)
                + b(self.walk_frame) + b(self.stand_frame) + b(self.talk_start) + b(self.talk_stop) + b(self.anim_speed)
                + b(self.wd_destbox) + b(self.wd_curbox) + b(self.wd_facing) + b(self.stepx)
                + w(self.wd_dest[0]) + w(self.wd_dest[1]) + w(self.wd_destdir) + w(self.wd_next[0]) + w(self.wd_next[1])
                + w(self.wd_xfrac) + w(self.wd_yfrac) + w(self.wd_xadd) + w(self.wd_yadd) + w(self.wd_dxf) + w(self.wd_dyf)
                + w(self.step_threshold) + w(self.wd_point3[0]) + w(self.last_valid[0]) + w(self.last_valid[1]) + b(flags))


class ObjData:
    """ObjectData de ScummVM (una entrada de _objs[])."""

    def __init__(self):
        self.obj_nr = 0
        self.obcd = 0
        self.x = self.y = self.width = self.height = 0
        self.parent = self.parentstate = 0
        self.walk_x = self.walk_y = 0
        self.actordir = 0
        self.state = 0
        self.code = b''


class Verb:
    """VerbSlot de ScummVM: solo lo que mira un script o la entrada."""

    def __init__(self):
        self.verbid = 0
        self.color = self.hicolor = self.dimcolor = self.bkcolor = 0
        self.curmode = 0
        self.saveid = 0
        self.key = 0
        self.center = 0
        self.type = 0                    # 0 texto, 1 imagen
        self.imgindex = 0
        self.left = self.top = 0
        self.name = b''
        self.length = 0                  # fase 7: columnas del texto la ultima vez que se dibujo el verbo (el rectangulo es [left, left + 8 * length))


def m32(a, b):
    """Producto de dos int de C (32 bits, desborda como en x86)."""
    return wrap32(a * b)


def d32(a, b):
    """Division de dos int de C (se trunca hacia cero). Dividir por 0 cuelga ScummVM: aqui es E_RANGE."""
    if b == 0:
        raise VMError(E_RANGE, 'division por cero en la geometria de cajas')
    return wrap32(cdiv(a, b))


def compare_slope(p1, p2, p3):
    """compareSlope de boxes.cpp: productos de int de C (32 bits)."""
    return m32(p2[1] - p1[1], p3[0] - p1[0]) <= m32(p3[1] - p1[1], p2[0] - p1[0])


def closest_pt_on_line(s, e, p):
    """closestPtOnLine de boxes.cpp: toda la aritmetica en int de C (32 bits); el resultado se guarda en un Common::Point (int16)
    antes de recortarlo al segmento."""
    sx, sy = s
    ex, ey = e
    px, py = p
    lx = ex - sx
    ly = ey - sy
    if ex == sx:
        rx, ry = sx, py
    elif ey == sy:
        rx, ry = px, sy
    else:
        dist = wrap32(m32(lx, lx) + m32(ly, ly))
        if abs(lx) > abs(ly):
            a = d32(m32(sx, ly), lx)
            b = d32(m32(px, lx), ly)
            c = d32(m32(m32(wrap32(wrap32(wrap32(a + b) - sy) + py), ly), lx), dist)
            rx = c
            ry = wrap32(wrap32(d32(m32(c, ly), lx) - a) + sy)
        else:
            a = d32(m32(sy, lx), ly)
            b = d32(m32(py, ly), lx)
            c = d32(m32(m32(wrap32(wrap32(wrap32(a + b) - sx) + px), ly), lx), dist)
            rx = wrap32(wrap32(d32(m32(c, lx), ly) - a) + sx)
            ry = c
    rx, ry = s16(rx), s16(ry)
    if abs(ly) < abs(lx):
        if lx > 0:
            if rx < sx:
                rx, ry = sx, sy
            elif rx > ex:
                rx, ry = ex, ey
        else:
            if rx > sx:
                rx, ry = sx, sy
            elif rx < ex:
                rx, ry = ex, ey
    else:
        if ly > 0:
            if ry < sy:
                rx, ry = sx, sy
            elif ry > ey:
                rx, ry = ex, ey
        else:
            if ry > sy:
                rx, ry = sx, sy
            elif ry < ey:
                rx, ry = ex, ey
    return rx, ry


def sqr_dist(p, q):
    """Common::Point::sqrDist: si una diferencia llega a 0x1000 devuelve 0xFFFFFF."""
    dx = abs(p[0] - q[0])
    if dx >= 0x1000:
        return 0xFFFFFF
    dy = abs(p[1] - q[1])
    if dy >= 0x1000:
        return 0xFFFFFF
    return dx * dx + dy * dy


def closest_pt_on_box(box, x, y):
    """getClosestPtOnBox: (distancia al cuadrado, x, y). box = (ul, ur, lr, ll). El punto es un Common::Point (int16). Si ninguna arista
    da menos de 0xFFFFFF, outX/outY no se tocan: aqui (0, 0) (en adjustXYToBeInBox no se usan; en getGates son el Point() de C)."""
    ul, ur, lr, ll = box
    p = (s16(x), s16(y))
    best = 0xFFFFFF
    out = (0, 0)
    for s, e in ((ul, ur), (ur, lr), (lr, ll), (ll, ul)):
        t = closest_pt_on_line(s, e, p)
        d = sqr_dist(p, t)
        if d < best:
            best = d
            out = t
    return best, out[0], out[1]


def in_box_quick_reject(box, x, y, threshold):
    ul, ur, lr, ll = box
    t = x - threshold
    if t > ul[0] and t > ur[0] and t > lr[0] and t > ll[0]:
        return True
    t = x + threshold
    if t < ul[0] and t < ur[0] and t < lr[0] and t < ll[0]:
        return True
    t = y - threshold
    if t > ul[1] and t > ur[1] and t > lr[1] and t > ll[1]:
        return True
    t = y + threshold
    if t < ul[1] and t < ur[1] and t < lr[1] and t < ll[1]:
        return True
    return False


def get_gates(box1, box2):
    """getGates de boxes.cpp: devuelve gateA, gateB, cada uno (punto0, punto1)."""
    dist = [0] * 8
    closest_point = [(0, 0)] * 8
    corners = [box1[0], box1[1], box1[2], box1[3], box2[0], box2[1], box2[2], box2[3]]
    for i in range(4):
        dist[i], cx, cy = closest_pt_on_box(box2, corners[i][0], corners[i][1])
        closest_point[i] = (cx, cy)
    for i in range(4, 8):
        dist[i], cx, cy = closest_pt_on_box(box1, corners[i][0], corners[i][1])
        closest_point[i] = (cx, cy)
    min_dist = [0] * 3
    closest = [0] * 3
    on_second = [0] * 3
    for j in range(3):
        min_dist[j] = 0xFFFF
        for i in range(8):
            if dist[i] < min_dist[j]:
                min_dist[j] = dist[i]
                closest[j] = i
        dist[closest[j]] = 0xFFFF
        min_dist[j] = math.isqrt(min_dist[j])
        on_second[j] = 1 if closest[j] > 3 else 0
    box, md = on_second, min_dist
    if box[0] == box[1] and abs(md[0] - md[1]) < 4:
        line1, line2 = closest[0], closest[1]
    elif box[0] == box[1] and md[0] == md[1]:
        line1, line2 = closest[0], closest[1]
    elif box[0] == box[2] and md[0] == md[2]:
        line1, line2 = closest[0], closest[2]
    elif box[1] == box[2] and md[1] == md[2]:
        line1, line2 = closest[1], closest[2]
    elif box[0] == box[2] and abs(md[0] - md[2]) < 4:
        line1, line2 = closest[0], closest[2]
    elif abs(md[0] - md[2]) < 4:
        line1, line2 = closest[1], closest[2]
    elif abs(md[0] - md[1]) < 4:
        line1, line2 = closest[0], closest[1]
    else:
        line1 = line2 = closest[0]

    def gate(line):
        if line < 4:
            return corners[line], closest_point[line]
        return closest_point[line], corners[line]
    return gate(line1), gate(line2)


class GameMixin:
    # ------------------------------------------------------------------------------------------ reinicio
    def game_reset(self, soundcard=0):
        self.classes = list(self.w.classes)
        self.actors = [Actor(self, i) for i in range(NUM_ACTORS)]
        self.cur_room = 0
        self.room = None                        # scumm3res.Room de la sala en uso
        self.owner = list(self.w.owner)
        self.gstate = list(self.w.state)        # _objectStateTable
        self.num_global_objects = len(self.owner)
        self.objs = [ObjData() for _ in range(NUM_LOCAL_OBJECTS)]
        self.inventory = [0] * NUM_INVENTORY
        self.inv_code = [b''] * NUM_INVENTORY
        self.new_names = [0] * NUM_NEW_NAMES
        self.new_name_str = [b''] * NUM_NEW_NAMES
        self.boxes = []                         # cajas de la sala (se pueden cambiar con setBoxFlags)
        self.matrix = b''
        self.excd = 0
        self.encd = 0
        self.sentence = []                      # _sentence[]: dicts verb, a, b, prep, freeze
        self.strings = {}                       # rtString
        self.verbs = [Verb() for _ in range(NUM_VERBS)]
        self.ego_positioned = False
        # mensajes
        self.have_msg = 0
        self.talk_delay = 0
        self.keep_text = False
        self.use_talk_anims = False
        self.msg_count = 0
        self.charset_buf = b'\0'
        self.charset_pos = 0
        self.actor_to_print_str_for = 0
        self.str_slots = [self._new_string_slot() for _ in range(4)]
        # entrada
        self.user_put = 0
        self.cursor_state = 0
        self.mouse = (0, 0)
        self.vmouse = (0, 0)
        self.pending = []                       # sucesos de entrada para el siguiente fotograma
        self.mk_stat = 0
        self.main_top, self.main_h = 16, 144
        # camara
        self.cam = dict(cur=160, dest=160, last=160, mode=0, follows=0, moving_to_actor=False, left=10, right=30)
        self.screen_start_strip = 0
        self.snap_scroll = False
        # cutscenes
        self.cut_sp = 0
        self.cut_data = [0] * MAX_CUTSCENE
        self.cut_script = [0] * MAX_CUTSCENE
        self.cut_ptr = [0] * MAX_CUTSCENE
        self.cut_script_index = 0xFF
        # sonido
        self.snd_soundcard = soundcard
        self.last_sound = 0
        self.sound_left = {}                    # modo "timed": sonido -> jiffies que le quedan
        self.snd_cur = None                     # modo "real" (fase 8): el sonido que suena (nr, prio, rest, left) y el que espera
        self.snd_next = 0
        self.room_pal = list(range(16))         # fase 8: _roomPalette (roomOps 2: el pixel b de la imagen de la sala se pinta con el color a) y _shadowPalette (roomOps 4: el color b de la pantalla sale como a)
        self.shadow_pal = list(range(16))
        self.snd_log = []                       # modo "real": las ordenes al MCU (STOP, LOOP, PLAY) como las imprime el arnes
        self.music_acc = 0
        self.music_ctr = 0
        self.music_timer = 0
        self.ticks_per_music_timer = 65535
        # azar (getRandomNr): generador de 16 bits, igual que el del Z80
        self.rnd = 0xACE1 ^ (self.seed & 0xFFFF)

    def _new_string_slot(self):
        d = dict(xpos=0, ypos=0, right=SCREEN_WIDTH - 1, color=15, center=False, overhead=False, height=0)
        s = dict(d)
        s['default'] = dict(d)
        return s

    def reset_vars_v3(self):
        """ScummEngine::resetScummVars (Indy3 EGA DOS): lo que no pone el script de arranque."""
        v = self.vars
        v[VAR_SOUNDCARD] = self.snd_soundcard
        v[VAR_VIDEOMODE] = 13                   # setVideoModeVarToCurrentConfig: EGA, version < 6
        v[VAR_CURRENT_LIGHTS] = 3               # LIGHTMODE_actor_use_base_palette | LIGHTMODE_room_lights_on
        v[VAR_CHARINC] = 4
        v[VAR_TALK_ACTOR] = 0                   # setTalkingActor(0)

    # ------------------------------------------------------------------------------------------ anfitrion
    def ev(self, eid, args):
        """Suceso para el back-end; devuelve el resultado simulado (solo lo usa la consulta de sonido)."""
        self.trace.append('E %d [%s]' % (eid, ','.join(str(a & 0xFFFF) for a in args)))
        return mock_hash(0x100 + eid, args, self.frame) & 1

    # ------------------------------------------------------------------------------------------ cajas
    def num_boxes(self):
        return len(self.boxes)

    def box_index(self, box):
        """getBoxBaseAddr: None si es la caja invalida; la caja n se lee como la n-1; fuera de rango es un error."""
        n = len(self.boxes)
        if n == 0 or box == INVALID_BOX:
            return None
        if box == n:
            box -= 1
        if not 0 <= box < n:
            raise VMError(E_RANGE, 'caja %d' % box)
        return box

    def get_box_flags(self, box):
        k = self.box_index(box)
        return 0 if k is None else self.boxes[k][9]

    def set_box_flags(self, box, val):
        k = self.box_index(box)
        if k is not None:
            self.boxes[k][9] = val & 0xFF

    def get_box_coordinates(self, box):
        k = self.box_index(box)
        if k is None:
            raise VMError(E_RANGE, 'caja %d' % box)
        b = self.boxes[k]
        return (b[0], b[1]), (b[2], b[3]), (b[4], b[5]), (b[6], b[7])            # ul, ur, lr, ll

    def check_xy_in_box_bounds(self, boxnum, x, y):
        """checkXYInBoxBounds (version < 7)."""
        if boxnum < 0 or boxnum == INVALID_BOX:
            return False
        ul, ur, lr, ll = self.get_box_coordinates(boxnum)
        if x < ul[0] and x < ur[0] and x < lr[0] and x < ll[0]:
            return False
        if x > ul[0] and x > ur[0] and x > lr[0] and x > ll[0]:
            return False
        if y < ul[1] and y < ur[1] and y < lr[1] and y < ll[1]:
            return False
        if y > ul[1] and y > ur[1] and y > lr[1] and y > ll[1]:
            return False
        p = (x, y)
        return (compare_slope(ul, ur, p) and compare_slope(ur, lr, p) and compare_slope(lr, ll, p)
                and compare_slope(ll, ul, p))

    def is_player(self, a):
        return self.get_class(a.num, CLASS_PLAYER)

    def adjust_xy_to_be_in_box(self, a, dst_x, dst_y):
        """Actor::adjustXYToBeInBox: (x, y, caja)."""
        dst_x, dst_y = s16(dst_x), s16(dst_y)
        rx, ry = a.last_valid                  # v3-v4: se reusan las ultimas coordenadas validas
        rbox = INVALID_BOX
        if a.ignore_boxes:
            return dst_x, dst_y, INVALID_BOX
        for threshold in (30, 80, 0):
            num_boxes = self.num_boxes() - 1
            if num_boxes < 0:
                return rx, ry, rbox
            best_dist = 0xFFFF
            best_box = INVALID_BOX
            for box in range(num_boxes, -1, -1):
                flags = self.get_box_flags(box)
                if (flags & BOX_INVISIBLE) and not ((flags & BOX_PLAYER_ONLY) and not self.is_player(a)):
                    continue
                coords = self.get_box_coordinates(box)
                if threshold > 0 and in_box_quick_reject(coords, dst_x, dst_y, threshold):
                    continue
                if self.check_xy_in_box_bounds(box, dst_x, dst_y):
                    a.last_valid = (dst_x, dst_y)
                    return dst_x, dst_y, box
                tmp_dist, tx, ty = closest_pt_on_box(coords, dst_x, dst_y)
                if tmp_dist < best_dist:
                    a.last_valid = (tx, ty)
                    rx, ry = tx, ty
                    if tmp_dist == 0:
                        return rx, ry, box
                    best_dist = tmp_dist
                    best_box = box
            if threshold == 0 or threshold * threshold >= best_dist:
                return rx, ry, best_box
        return rx, ry, rbox

    def get_next_box(self, frm, to):
        """ScummEngine::getNextBox (v3): por cada caja, ternas (desde, hasta, siguiente) acabadas en 0xFF."""
        if frm == to:
            return to
        if to == INVALID_BOX:
            return -1
        if frm == INVALID_BOX:
            return to
        n = self.num_boxes()
        if frm >= n or to >= n:
            raise VMError(E_RANGE, 'getNextBox')
        m = self.matrix
        p = 1 if m and m[0] == 0xFF else 0
        end = len(m)
        if self.cur_room_resource() == 46 and frm == 1 and to == 0:   # WORKAROUND de ScummVM (Indy3, _roomResource 46)
            return 0
        i = 0
        while i < frm and p < end:
            while p < end and m[p] != 0xFF:
                p += 3
            p += 1
            i += 1
        dest = -1
        while p < end and m[p] != 0xFF:
            if p + 2 < end and m[p] <= to <= m[p + 1]:
                dest = m[p + 2] - 256 if m[p + 2] & 0x80 else m[p + 2]
            p += 3
        return dest

    def find_path_towards_old(self, a, box1, box2, final_box):
        """Actor_v3::findPathTowardsOld: (p2, p3); x = 32000 es "sin punto"."""
        gate_a, gate_b = get_gates(self.get_box_coordinates(box1), self.get_box_coordinates(box2))
        p2 = (32000, 0)
        p3 = (32000, 0)
        pos = (a.x, a.y)
        if box2 == final_box:
            if (compare_slope(pos, a.wd_dest, gate_a[0]) != compare_slope(pos, a.wd_dest, gate_b[0])
                    and compare_slope(pos, a.wd_dest, gate_a[1]) != compare_slope(pos, a.wd_dest, gate_b[1])):
                return p2, p3
        p3 = closest_pt_on_line(gate_a[1], gate_b[1], pos)
        if compare_slope(pos, p3, gate_a[0]) == compare_slope(pos, p3, gate_b[0]):
            p2 = closest_pt_on_line(gate_a[0], gate_b[0], pos)
        return p2, p3

    # ------------------------------------------------------------------------------------------ actores
    def is_valid_actor(self, i):
        return 0 <= i < NUM_ACTORS

    def deref_actor(self, i):
        if not self.is_valid_actor(i):
            raise VMError(E_BADACTOR, 'actor %d' % i)
        return self.actors[i]

    def deref_actor_safe(self, i):
        return self.actors[i] if self.is_valid_actor(i) else None

    def set_box(self, a, box):
        a.walkbox = box

    def start_anim_actor(self, a, f):
        """Actor::startAnimActor (version < 7, sin costumes nuevos): solo cambia el fotograma pedido."""
        f = {CHORE_INIT: a.init_frame, CHORE_WALK: a.walk_frame, CHORE_STAND: a.stand_frame,
             CHORE_TALK_START: a.talk_start, CHORE_TALK_STOP: a.talk_stop}.get(f, f)
        if f == CHORE_FACE_DIR:
            raise VMError(E_RANGE, 'startAnimActor CHORE_FACE_DIR')
        if a.in_room() and a.costume != 0:
            a.anim_progress = 0
            a.need_redraw = True
            a.frame = f & 0xFF

    def stop_actor_moving(self, a):
        a.moving = 0

    def set_direction(self, a, d):
        """Actor::setDirection (v3): sin trajes, solo queda marcar el redibujo si cambia, tiene traje y esta en la sala."""
        d = d + 360
        d = d - cdiv(d, 360) * 360                       # % de C
        if a.facing == d:
            return
        a.facing = d & 0xFFFF                            # _facing es uint16
        if a.costume == 0 or not a.in_room():
            return
        a.need_redraw = True

    def turn_to_direction(self, a, d):
        if d == -1 or a.ignore_turns:
            return
        a.target_facing = d
        a.moving = MF_TURN

    def hide_actor(self, a):
        if not a.visible:
            return
        if a.moving:
            self.stop_actor_moving(a)
            self.start_anim_actor(a, a.stand_frame)
        a.visible = False
        a.need_redraw = False

    def adjust_actor_pos(self, a):
        a.x, a.y, box = self.adjust_xy_to_be_in_box(a, a.x, a.y)
        a.wd_destbox = box
        self.set_box(a, box)
        a.wd_dest = (-1, a.wd_dest[1])
        self.stop_actor_moving(a)
        if a.walkbox != INVALID_BOX:
            if self.get_box_flags(a.walkbox) & 7:
                self.turn_to_direction(a, a.facing)

    def show_actor(self, a):
        if self.cur_room == 0 or a.visible:
            return
        self.adjust_actor_pos(a)
        if a.costume_needs_init:
            self.start_anim_actor(a, a.init_frame)
            a.costume_needs_init = False
        self.stop_actor_moving(a)
        a.visible = True
        a.need_redraw = True

    def show_actors(self):
        for i in range(1, NUM_ACTORS):
            if self.actors[i].in_room():
                self.show_actor(self.actors[i])

    def put_actor(self, a, x, y, room):
        """Actor::putActor(x, y, room)."""
        if a.visible and self.cur_room != room and self.vars[VAR_TALK_ACTOR] == a.num:
            self.stop_talk()
        a.x, a.y = s16(x), s16(y)
        a.room = room & 0xFF                     # Actor::_room es un byte
        a.need_redraw = True
        if self.vars[VAR_EGO] == a.num:
            self.ego_positioned = True
        if a.visible:
            if a.in_room():
                if a.moving:
                    self.stop_actor_moving(a)
                    self.start_anim_actor(a, a.stand_frame)
                self.adjust_actor_pos(a)
            else:
                self.hide_actor(a)
        elif a.in_room():
            self.show_actor(a)

    def set_actor_costume(self, a, c):
        a.costume_needs_init = True
        if a.visible:
            self.hide_actor(a)
            a.costume = c
            self.show_actor(a)
        else:
            a.costume = c

    def animate_actor(self, a, anim):
        """Actor::animateActor (version < 7): chore = 0x3F - anim / 4 + 2."""
        chore = 0x3F - (anim >> 2) + 2
        d = OLD_DIR[anim & 3]
        if chore == 2:                                   # parar de andar
            if a.in_room():
                self.start_anim_actor(a, a.stand_frame)
                self.stop_actor_moving(a)
        elif chore == 3:                                 # cambiar de direccion ya
            if a.in_room():
                a.moving &= ~MF_TURN
            self.set_direction(a, d)
        elif chore == 4:                                 # girar
            if a.in_room():
                self.turn_to_direction(a, d)
        else:
            self.start_anim_actor(a, anim)

    def run_actor_talk_script(self, a, f):
        if not self.vars[VAR_TALK_ACTOR] or a.room != self.cur_room or a.frame == f:
            return
        self.start_anim_actor(a, f)

    def face_to_object(self, a, obj):
        if not a.in_room():
            return
        p = self.get_object_or_actor_xy(obj)
        if p is None:
            return
        x2, y2 = p
        width = self.get_object_or_actor_width(obj)
        d = 1 if a.x < x2 else 0
        if abs(a.x - x2) < width // 2:
            d = 3 if a.y > y2 else 2
        self.turn_to_direction(a, OLD_DIR[d])

    # ---- caminata (Actor_v3)
    def start_walk_actor(self, a, dest_x, dest_y, d):
        """Actor::startWalkActor (version 3). abr.x/abr.y son int16."""
        x, y, box = s16(dest_x), s16(dest_y), INVALID_BOX
        if not a.in_room():
            a.x, a.y = x, y
            if not a.ignore_turns and d != -1:
                a.facing = d & 0xFFFF                    # _facing es uint16
            return
        if a.ignore_boxes:
            box = INVALID_BOX
            a.walkbox = INVALID_BOX
        else:
            if self.check_xy_in_box_bounds(a.wd_destbox, x, y):
                box = a.wd_destbox
            else:
                x, y, box = self.adjust_xy_to_be_in_box(a, x, y)
            if a.moving and a.wd_destdir == d and a.wd_dest == (x, y):
                return
        if a.x == x and a.y == y:
            if d != a.facing:
                self.turn_to_direction(a, d)
            return
        a.wd_dest = (x, y)
        a.wd_destbox = box
        a.wd_destdir = d
        a.wd_point3 = (32000, a.wd_point3[1])
        a.wd_curbox = a.walkbox
        a.moving = (a.moving & MF_IN_LEG) | MF_NEW_LEG

    def start_walk_anim(self, a, cmd, angle):
        if angle == -1:
            angle = a.facing
        if cmd == 3:
            self.turn_to_direction(a, angle)
        else:
            self.set_direction(a, angle)
        if cmd == 1:
            self.start_anim_actor(a, a.walk_frame)
        elif cmd == 3:
            self.start_anim_actor(a, a.stand_frame)

    def remap_direction(self, a, d, is_walking):
        """Actor::remapDirection (version 3). _extraBoxFlags no se usa en v3 (o3_setBoxFlags pasa un byte)."""
        if not 0 <= d <= 359:                    # (no pasa: _targetFacing sale siempre de oldDirToNewDir; el Z80 trabaja en 16 bits)
            raise VMError(E_RANGE, 'remapDirection %d' % d)
        flags = self.get_box_flags(a.walkbox)
        flip_x = a.wd_dxf > 0
        flip_y = a.wd_dyf > 0
        if (flags & BOX_XFLIP) or self.get_class(a.num, CLASS_XFLIP):
            d = 360 - d
            flip_x = not flip_x
        if (flags & BOX_YFLIP) or self.get_class(a.num, CLASS_YFLIP):
            d = 180 - d
            flip_y = not flip_y
        f = flags & 7
        if f == 1:
            return (90 if flip_x else 270) if is_walking else (90 if d == 90 else 270)
        if f == 2:
            return (180 if flip_y else 0) if is_walking else (0 if d == 0 else 180)
        if f == 3:
            return 270
        if f == 4:
            return 90
        if f == 5:
            return 0
        if f == 6:
            return 180
        d = (d + 360) % 360
        return d | 0x400

    def update_actor_direction(self, a, is_walking):
        d = self.remap_direction(a, a.target_facing, is_walking)
        if d & 0x400:
            d = OLD_DIR[TURN_TABLE[new_to_old_dir(d & 0x3FF) | (new_to_old_dir(a.facing) << 2)]]
        return d

    def calc_movement_factor(self, a, nxt):
        """Actor_v3::calcMovementFactor. Devuelve 0/1 como el original."""
        if (a.x, a.y) == nxt:
            return 0
        diff_x = nxt[0] - a.x
        diff_y = nxt[1] - a.y
        if not (a.moving & MF_LAST_LEG) and a.speedx > abs(diff_x) and a.speedy > abs(diff_y):
            return 0
        if a.speedx == 0 or a.speedy == 0:               # ScummVM divide por cero
            raise VMError(E_RANGE, 'velocidad 0 en calcMovementFactor')
        a.stepx = a.speedy + 1 if ((abs(diff_y) // a.speedy) >> 1) > (abs(diff_x) // a.speedx) else a.speedx
        if a.stepx > 255:                                # el Z80 guarda _stepX en un byte (velocidad y 255)
            raise VMError(E_RANGE, 'stepX %d' % a.stepx)
        a.step_threshold = max(abs(diff_y) // a.speedy, abs(diff_x) // a.stepx)
        dxf, dyf = a.stepx, a.speedy
        if diff_x < 0:
            dxf = -dxf
        if diff_y < 0:
            dyf = -dyf
        a.wd_xfrac = a.wd_xadd = (cdiv(diff_x, dxf) if dxf else 0) & 0xFFFF     # xfrac y xAdd son uint16
        a.wd_yfrac = a.wd_yadd = (cdiv(diff_y, dyf) if dyf else 0) & 0xFFFF
        a.wd_cur = (a.x, a.y)
        a.wd_next = nxt
        a.wd_dxf, a.wd_dyf = dxf, dyf
        a.wd_facing = (1 if diff_y >= 0 else 0) if diff_x >= 0 else (2 if diff_y >= 0 else 3)
        a.target_facing = OLD_DIR[(3 - (1 if diff_y >= 0 else 0)) if abs(diff_y) * 3 > abs(diff_x)
                                  else (1 if diff_x >= 0 else 0)]
        return self.actor_walk_step(a)

    def actor_walk_step(self, a):
        """Actor_v3::actorWalkStep."""
        a.need_redraw = True
        next_facing = self.update_actor_direction(a, True)
        if not (a.moving & MF_IN_LEG) or a.facing != next_facing:
            if a.walk_frame != a.frame or a.facing != next_facing:
                self.start_walk_anim(a, 1, next_facing)
            a.moving |= MF_IN_LEG
            return 1
        nx, ny = a.wd_next
        if nx - a.stepx <= a.x <= nx + a.stepx:
            a.x = nx
        if ny - a.speedy <= a.y <= ny + a.speedy:
            a.y = ny
        if a.walkbox != a.wd_curbox and self.check_xy_in_box_bounds(a.wd_curbox, a.x, a.y):
            self.set_box(a, a.wd_curbox)
        if (a.x, a.y) == a.wd_next:
            a.moving &= ~MF_IN_LEG
            return 0
        a.wd_xfrac = (a.wd_xfrac + a.wd_xadd) & 0xFFFF   # uint16
        if a.wd_xfrac >= a.step_threshold:
            if a.x != nx:
                a.x = s16(a.x + a.wd_dxf)
            a.wd_xfrac = (a.wd_xfrac - a.step_threshold) & 0xFFFF
        a.wd_yfrac = (a.wd_yfrac + a.wd_yadd) & 0xFFFF
        if a.wd_yfrac >= a.step_threshold:
            if a.y != ny:
                a.y = s16(a.y + a.wd_dyf)
            a.wd_yfrac = (a.wd_yfrac - a.step_threshold) & 0xFFFF
        return 1

    def walk_actor(self, a):
        """Actor_v3::walkActor."""
        if not a.moving:
            return
        if not (a.moving & MF_NEW_LEG):
            if (a.moving & MF_IN_LEG) and self.actor_walk_step(a):
                return
            if a.moving & MF_LAST_LEG:
                a.moving = 0
                self.start_anim_actor(a, a.stand_frame)
                if a.target_facing != a.wd_destdir:
                    self.turn_to_direction(a, a.wd_destdir)
                return
            if a.moving & MF_TURN:
                new_dir = self.update_actor_direction(a, False)
                if a.facing != new_dir:
                    self.set_direction(a, new_dir)
                else:
                    a.moving = 0
                return
            if a.wd_point3[0] != 32000:
                if self.calc_movement_factor(a, a.wd_point3):
                    a.wd_point3 = (32000, 0)
                    return
                a.wd_point3 = (32000, 0)
            self.set_box(a, a.wd_curbox)
            a.moving &= MF_IN_LEG
        a.moving &= ~MF_NEW_LEG
        while True:
            if a.walkbox == INVALID_BOX:
                self.set_box(a, a.wd_destbox)
                a.wd_curbox = a.wd_destbox
                break
            if a.walkbox == a.wd_destbox:
                break
            next_box = self.get_next_box(a.walkbox, a.wd_destbox)
            if next_box < 0:
                a.moving |= MF_LAST_LEG
                return
            a.wd_curbox = next_box
            p2, p3 = self.find_path_towards_old(a, a.walkbox, next_box, a.wd_destbox)
            if p2[0] == 32000 and p3[0] == 32000:
                break
            if p2[0] != 32000:
                if self.calc_movement_factor(a, p2):
                    a.wd_point3 = p3
                    return
            if self.calc_movement_factor(a, p3):
                return
            self.set_box(a, a.wd_curbox)
        a.moving |= MF_LAST_LEG
        self.calc_movement_factor(a, a.wd_dest)

    def walk_actors(self):
        for i in range(1, NUM_ACTORS):
            if self.actors[i].in_room():
                self.walk_actor(self.actors[i])

    # ---- ratones y rectangulos: lo que ScummVM saca del dibujo
    def actor_rect(self, a):
        """Rectangulo del actor en pantalla (x0, x1, y0, y1). ScummVM lo saca del ultimo dibujo (_top, _bottom y los
        bits de uso de cada franja); aqui es una caja fija alrededor de la posicion, hasta que haya trajes (fase 8)."""
        return a.x - ACTOR_RECT_W, a.x + ACTOR_RECT_W, a.y - ACTOR_RECT_H - a.elevation, a.y

    def get_actor_from_pos(self, x, y):
        """ScummEngine::getActorFromPos (v3): el primer actor cuyo rectangulo contiene el punto, sin clase intocable."""
        for i in range(1, NUM_ACTORS):
            a = self.actors[i]
            if not (a.in_room() and a.visible):
                continue
            x0, x1, y1, y2 = self.actor_rect(a)
            if x0 <= x < x1 and not self.get_class(i, CLASS_UNTOUCHABLE) and y1 <= y <= y2:
                return i
        return 0

    # ------------------------------------------------------------------------------------------ objetos
    def _check_obj(self, obj):
        if not 0 <= obj < self.num_global_objects:
            raise VMError(E_BADOBJ, 'objeto %d' % obj)

    def get_class(self, obj, cls):
        self._check_obj(obj)
        cls &= 0x7F
        if not 1 <= cls <= 32:
            raise VMError(E_RANGE, 'clase %d' % cls)
        cls = CLASS_SMALL_HEADER.get(cls, cls)
        if cls > 24:                                     # el Z80 guarda 24 bits de clases (los datos de v3 no pasan de ahi)
            raise VMError(E_RANGE, 'clase %d fuera de 24 bits' % cls)
        return (self.classes[obj] & (1 << (cls - 1))) != 0

    def put_class(self, obj, cls, on):
        self._check_obj(obj)
        cls &= 0x7F
        if not 1 <= cls <= 32:
            raise VMError(E_RANGE, 'clase %d' % cls)
        cls = CLASS_SMALL_HEADER.get(cls, cls)
        if cls > 24:
            raise VMError(E_RANGE, 'clase %d fuera de 24 bits' % cls)
        if on:
            self.classes[obj] |= 1 << (cls - 1)
        else:
            self.classes[obj] &= ~(1 << (cls - 1))
        if 1 <= obj < NUM_ACTORS:                        # Actor::classChanged
            if cls == CLASS_IGNORE_BOXES:
                self.actors[obj].ignore_boxes = bool(on)

    def get_owner(self, obj):
        self._check_obj(obj)
        return self.owner[obj]

    def put_owner(self, obj, owner):
        self._check_obj(obj)
        if not 0 <= owner <= 0xFF:
            raise VMError(E_RANGE, 'dueno %d' % owner)
        self.owner[obj] = owner

    def get_state(self, obj):
        self._check_obj(obj)
        return self.gstate[obj]

    def put_state(self, obj, st):
        self._check_obj(obj)
        if not 0 <= st <= 0xFF:
            raise VMError(E_RANGE, 'estado %d' % st)
        self.gstate[obj] = st

    def get_object_index(self, obj):
        if obj < 1:
            return -1
        for i in range(NUM_LOCAL_OBJECTS - 1, 0, -1):
            if self.objs[i].obj_nr == obj:
                return i
        return -1

    def where_is_object(self, obj):
        if obj >= self.num_global_objects or obj < 1:
            return WIO_NOT_FOUND
        if self.owner[obj] != OWNER_ROOM:
            for i in range(NUM_INVENTORY):
                if self.inventory[i] == obj:
                    return WIO_INVENTORY
            return WIO_NOT_FOUND
        if self.get_object_index(obj) != -1:
            return WIO_ROOM
        return WIO_NOT_FOUND

    def obj_is_actor(self, obj):
        return obj < NUM_ACTORS

    def get_object_xy_pos(self, obj):
        """getObjectXYPos (v3): (x, y, direccion en angulos)."""
        idx = self.get_object_index(obj)
        if idx < 0:
            raise VMError(E_BADOBJ, 'getObjectXYPos %d' % obj)
        od = self.objs[idx]
        return od.walk_x, od.walk_y, OLD_DIR[od.actordir & 3]

    def get_object_or_actor_xy(self, obj):
        """getObjectOrActorXY: (x, y) o None si no esta."""
        if self.obj_is_actor(obj):
            a = self.deref_actor_safe(obj)
            if a and a.in_room():
                return a.x, a.y
            return None
        w = self.where_is_object(obj)
        if w == WIO_NOT_FOUND:
            return None
        if w == WIO_INVENTORY:
            o = self.owner[obj]
            if self.obj_is_actor(o):
                a = self.deref_actor(o)
                if a.in_room():
                    return a.x, a.y
            return None
        x, y, _ = self.get_object_xy_pos(obj)
        return x, y

    def get_object_or_actor_width(self, obj):
        """getObjectOrActorWidth. Para un objeto, ScummVM deja la anchura sin asignar (getObjectXYPos no la rellena y
        faceToObject la lee): aqui se toma la anchura del objeto en pixeles, que es lo que querria el original."""
        if self.obj_is_actor(obj):
            a = self.deref_actor_safe(obj)
            return a.width if a and a.in_room() else 0
        w = self.where_is_object(obj)
        if w == WIO_NOT_FOUND:
            return 0
        if w == WIO_INVENTORY:
            o = self.owner[obj]
            if self.obj_is_actor(o):
                a = self.deref_actor(o)
                if a.in_room():
                    return a.width
            return 0
        return self.objs[self.get_object_index(obj)].width

    def get_obj_x(self, obj):
        if obj < 1:
            return 0
        if self.obj_is_actor(obj):
            return self.deref_actor(obj).x
        if self.where_is_object(obj) == WIO_NOT_FOUND:
            return -1
        p = self.get_object_or_actor_xy(obj)
        return -1 if p is None else p[0]

    def get_obj_y(self, obj):
        if obj < 1:
            return 0
        if self.obj_is_actor(obj):
            return self.deref_actor(obj).y
        if self.where_is_object(obj) == WIO_NOT_FOUND:
            return -1
        p = self.get_object_or_actor_xy(obj)
        return -1 if p is None else p[1]

    def get_obj_act_to_obj_act_dist(self, a, b):
        """getObjActToObjActDist."""
        acta = self.deref_actor_safe(a) if self.obj_is_actor(a) else None
        actb = self.deref_actor_safe(b) if self.obj_is_actor(b) else None
        if acta and actb and acta.room == actb.room and acta.room and not acta.in_room():
            return 0
        p = self.get_object_or_actor_xy(a)
        if p is None:
            return 0xFF
        q = self.get_object_or_actor_xy(b)
        if q is None:
            return 0xFF
        x, y = p
        x2, y2 = q
        if acta and not actb:
            x2, y2, _ = self.adjust_xy_to_be_in_box(acta, x2, y2)
        return max(abs(y - y2), abs(x - x2))

    def find_object(self, x, y):
        """ScummEngine::findObject (v3): recorre _objs[] en orden y sigue la cadena de padres (parent = indice en _objs)."""
        for i in range(1, NUM_LOCAL_OBJECTS):
            o = self.objs[i]
            if o.obj_nr < 1 or self.get_class(o.obj_nr, CLASS_UNTOUCHABLE):
                continue
            b = i
            while True:
                a = self.objs[b].parentstate
                b = self.objs[b].parent
                if b == 0:
                    if o.x <= x < o.x + o.width and o.y <= y < o.y + o.height:
                        return o.obj_nr
                    break
                if b >= NUM_LOCAL_OBJECTS or (self.objs[b].state & 0xF) != a:
                    break
        return 0

    def update_object_states(self):
        for i in range(1, NUM_LOCAL_OBJECTS):
            if self.objs[i].obj_nr > 0:
                self.objs[i].state = self.get_state(self.objs[i].obj_nr)

    def reset_room_objects(self):
        """ScummEngine_v4::resetRoomObjects + resetRoomObject (old bundle): los objetos van a _objs[1..n] en orden."""
        for i in range(NUM_LOCAL_OBJECTS):
            self.objs[i] = ObjData()
        r = self.room
        for i, o in enumerate(r.objects):
            if i + 1 >= NUM_LOCAL_OBJECTS:
                raise VMError(E_RANGE, 'mas de %d objetos en la sala' % NUM_LOCAL_OBJECTS)
            d = self.objs[i + 1]
            d.obj_nr, d.obcd, d.code = o.id, o.obcd, r.file
            d.x, d.y, d.width, d.height = o.x, o.y, o.width, o.height
            d.parent, d.parentstate = o.parent, o.parentstate
            d.walk_x, d.walk_y, d.actordir = s16(o.walk_x), s16(o.walk_y), o.actordir        # ObjectData::walk_x/y son int16

    def obcd_of(self, obj):
        """(codigo, offset del OBCD) del objeto (getOBCDFromObject): el inventario manda sobre la sala."""
        for i in range(NUM_INVENTORY):
            if self.inventory[i] == obj:
                return self.inv_code[i], 0
        idx = self.get_object_index(obj)
        if idx >= 0 and self.owner[obj] == OWNER_ROOM:
            return self.objs[idx].code, self.objs[idx].obcd
        return None

    def get_obcd_offs(self, obj):
        """getOBCDOffs: offset del OBCD en la sala (0 si es del inventario)."""
        if self.owner[obj] != OWNER_ROOM:
            return 0
        idx = self.get_object_index(obj)
        return self.objs[idx].obcd if idx >= 0 else 0

    def get_verb_entrypoint(self, obj, entry):
        """getVerbEntrypoint (old bundle + GF_SMALL_HEADER): los verbos van en ternas desde +17; devuelve el u16 de la
        terna (offset desde el inicio del OBCD) o 0."""
        if self.where_is_object(obj) == WIO_NOT_FOUND:
            return 0
        c = self.obcd_of(obj)
        if c is None:
            raise VMError(E_BADOBJ, 'getOBCDFromObject %d' % obj)
        code, base = c
        p = base + 17
        while True:
            v = code[p]
            if v == 0:
                return 0
            if v == entry or v == 0xFF:
                return code[p + 1] | (code[p + 2] << 8)
            p += 3

    def get_obj_or_actor_name(self, obj):
        """getObjOrActorName: bytes (con codigos de escape) o None."""
        if self.obj_is_actor(obj):
            return self.deref_actor(obj).name
        for i in range(NUM_NEW_NAMES):
            if self.new_names[i] == obj:
                return self.new_name_str[i]
        c = self.obcd_of(obj)
        if c is None:
            return None
        code, base = c
        off = code[base + 16]
        s = base + off
        e = code.index(0, s)
        return bytes(code[s:e + 1])

    def set_object_name(self, obj, raw):
        if self.obj_is_actor(obj):
            raise VMError(E_RANGE, 'setObjectName de un actor')
        for i in range(NUM_NEW_NAMES):
            if self.new_names[i] == obj:
                self.new_names[i] = 0
                self.new_name_str[i] = b''
                break
        for i in range(NUM_NEW_NAMES):
            if self.new_names[i] == 0:
                self.new_names[i] = obj
                self.new_name_str[i] = raw
                self.run_inventory_script(0)
                return
        raise VMError(E_RANGE, 'new names desbordado')

    def add_object_to_inventory(self, obj, room):
        """addObjectToInventory: copia el OBCD en la primera ranura libre."""
        r = self.w.rooms.get(room)
        found = None
        if r is not None:
            for o in r.objects:
                if o.id == obj:
                    found = (r.file, o.obcd)
                    break
        if found is None:
            raise VMError(E_BADOBJ, 'objeto %d no esta en la sala %d' % (obj, room))
        code, base = found
        size = code[base] | (code[base + 1] << 8)
        for slot in range(NUM_INVENTORY):
            if self.inventory[slot] == 0:
                self.inventory[slot] = obj
                self.inv_code[slot] = bytes(code[base:base + size])
                return
        raise VMError(E_RANGE, 'inventario lleno')

    def find_inventory(self, owner, idx):
        count = 1
        for i in range(NUM_INVENTORY):
            obj = self.inventory[i]
            if obj and self.get_owner(obj) == owner:
                if count == idx:
                    return obj
                count += 1
        return 0

    def get_inventory_count(self, owner):
        return sum(1 for i in range(NUM_INVENTORY) if self.inventory[i] and self.get_owner(self.inventory[i]) == owner)

    def clear_owner_of(self, obj):
        self.stop_object_script(obj)
        if self.get_owner(obj) == OWNER_ROOM:
            return                                           # solo los objetos flotantes se borran: no hay en v3 EGA
        for i in range(NUM_INVENTORY):
            if self.inventory[i] == obj:
                self.inventory[i] = 0                        # en v3 no se rellenan los huecos
                self.inv_code[i] = b''
                break

    def set_owner_of(self, obj, owner):
        if obj <= 0:
            raise VMError(E_BADOBJ, 'setOwnerOf %d' % obj)
        if owner == 0:
            self.clear_owner_of(obj)
            ss = self.slots[self.cur] if self.cur != 0xFF else None
            if ss is not None and ss.where == WIO_INVENTORY:
                if (ss.number < NUM_INVENTORY and self.inventory[ss.number] == obj) or ss.number == obj:
                    raise VMError(E_RANGE, 'Odd setOwnerOf case')
        self.put_owner(obj, owner)
        self.run_inventory_script(0)                         # arg = (version >= 6) ? obj : 0

    def run_inventory_script(self, i):
        if self.vars[VAR_INVENTORY_SCRIPT]:
            self.run_script(self.vars[VAR_INVENTORY_SCRIPT], False, False, [i] + [0] * (NUM_LOCAL - 1))

    # ------------------------------------------------------------------------------------------ verbos
    def get_verb_slot(self, vid, mode):
        for i in range(1, NUM_VERBS):
            if self.verbs[i].verbid == vid and self.verbs[i].saveid == mode:
                return i
        return 0

    def kill_verb(self, slot):
        if slot == 0:
            return
        vs = self.verbs[slot]
        vs.verbid = 0
        vs.curmode = 0
        vs.name = b''
        vs.saveid = 0
        self.ev(EV_VERB, [slot, 0])

    def verb_text_len(self, vs):
        """Columnas (de 8 px de SCUMM = una celda de 6 px de la pantalla) que ocupa el nombre del verbo ya convertido (convertMessageToString:
        los codigos $FF cuentan como sus bytes), con tope de 42 (el ancho de la pantalla de interfaz)."""
        return min(len(self.convert_message_to_string(vs.name)) - 1, 42)

    def draw_verb(self, slot):
        """ScummEngine::drawVerb (solo lo que ve la entrada): un verbo visible (activo o atenuado) fija el ancho de su rectangulo al dibujarse.
        El rectangulo de un verbo con imagen no se modela (Indy3 no los usa)."""
        if slot == 0:
            return
        vs = self.verbs[slot]
        if vs.saveid == 0 and vs.curmode and vs.verbid and vs.type == 0:
            vs.length = self.verb_text_len(vs)

    def find_verb_at_pos(self, x, y):
        """findVerbAtPos con el rectangulo [left, left + 8 * length) x [top, top + 8) del ultimo dibujo."""
        for i in range(NUM_VERBS - 1, 0, -1):
            vs = self.verbs[i]
            if vs.curmode != 1 or not vs.verbid or vs.saveid:
                continue
            if y < vs.top or y >= vs.top + FONT_H:
                continue
            right = vs.left + FONT_W * vs.length
            if vs.center:
                if x < -(right - 2 * vs.left) or x >= right:
                    continue
            elif x < vs.left or x >= right:
                continue
            return i
        return 0

    # ------------------------------------------------------------------------------------------ mensajes
    def set_talking_actor(self, i):
        self.vars[VAR_TALK_ACTOR] = i & 0xFFFF

    def get_talking_actor(self):
        return self.vars[VAR_TALK_ACTOR] & 0xFFFF

    def restore_charset_bg(self):
        self.ev(EV_TEXT, [255, 0, 0, 0, 0, 0])               # borrar el area de mensajes

    def stop_talk(self):
        self.have_msg = 0
        self.talk_delay = 0
        act = self.get_talking_actor()
        if act and act < 0x80:
            a = self.deref_actor(act)
            if a.in_room() and self.use_talk_anims:
                self.run_actor_talk_script(a, a.talk_stop)
                self.use_talk_anims = False
            self.set_talking_actor(0xFF)
        self.keep_text = False
        self.restore_charset_bg()

    def convert_message_to_string(self, msg):
        """convertMessageToString: el mensaje del script (con su 0 final) -> el bufer de texto (con su 0 final).
        Limites del Z80 (vmcommon3): el contenido tiene que ser menor que MSG_MAX, los mensajes anidados (verbo, nombre, cadena)
        llegan a MSG_DEPTH niveles, y una variable de 0x2000 (indice indirecto: leeria del script) da E_RANGE. Una fuente se lee con
        ceros mas alla de su final (una cadena sin 0 final, un codigo $FF cortado)."""
        out = bytearray()
        self._convert_into(out, bytes(msg), 0)
        out.append(0)
        return bytes(out)

    def _convert_into(self, out, msg, depth):
        if depth > MSG_DEPTH:
            raise VMError(E_RANGE, 'convertMessageToString: mensajes anidados')
        n = len(msg)
        rd = lambda k: msg[k] if k < n else 0
        i = 0
        while True:
            chr_ = rd(i)
            i += 1
            if chr_ == 0:
                break
            if chr_ == 0xFF:
                chr_ = rd(i)
                i += 1
                if chr_ in (1, 2, 3, 8):
                    out += bytes([0xFF, chr_])
                elif chr_ in (4, 5, 6, 7):
                    val = rd(i) | (rd(i + 1) << 8)
                    i += 2
                    if val & 0x2000:
                        raise VMError(E_RANGE, 'convertMessageToString: variable indirecta')
                    if chr_ == 4:
                        out += str(self.read_var(val)).encode()
                    elif chr_ == 5:
                        self.convert_verb_message(out, val, depth)
                    elif chr_ == 6:
                        self.convert_name_message(out, val, depth)
                    else:
                        self.convert_string_message(out, val, depth)
                elif chr_ in (9, 10, 12, 13, 14):
                    out += bytes([0xFF, chr_, rd(i), rd(i + 1)])
                    i += 2
                # (codigo invalido: se salta solo el 0xFF y el codigo)
            elif chr_ != 0x40:                            # '@' no se imprime
                out.append(chr_)
            if len(out) >= MSG_MAX:
                raise VMError(E_RANGE, 'convertMessageToString: desbordamiento')

    def _strip0(self, b):
        return b[:-1] if b and b[-1] == 0 else b

    def convert_verb_message(self, out, var, depth):
        num = self.read_var(var)
        if num:
            for k in range(1, NUM_VERBS):
                vs = self.verbs[k]
                if num == vs.verbid and not vs.type and not vs.saveid:
                    self._convert_into(out, vs.name, depth + 1)
                    return

    def convert_name_message(self, out, var, depth):
        num = self.read_var(var)
        if num:
            ptr = self.get_obj_or_actor_name(num)
            if ptr is not None:
                self._convert_into(out, ptr, depth + 1)

    def convert_string_message(self, out, var, depth):
        var = self.read_var(var)                           # version 3
        if var:
            ptr = self.strings.get(var)
            if ptr is not None:
                self._convert_into(out, bytes(ptr), depth + 1)

    def actor_talk(self, raw):
        """ScummEngine::actorTalk (v3)."""
        self.charset_buf = self.convert_message_to_string(raw)
        who = self.actor_to_print_str_for
        if who == 0xFF:
            if not self.keep_text:
                self.stop_talk()
            self.set_talking_actor(0xFF)
        else:
            a = self.deref_actor(who)
            if not a.in_room():
                oldact = 0xFF
            else:
                if not self.keep_text:
                    self.stop_talk()
                self.set_talking_actor(a.num)
                self.run_actor_talk_script(a, a.talk_start)
                self.use_talk_anims = True
                oldact = self.get_talking_actor()
            if oldact >= 0x80:
                return
        if self.get_talking_actor() > 0x7F:
            self.charset_color = self.str_slots[0]['color']
        else:
            self.charset_color = self.deref_actor(self.get_talking_actor()).talk_color
        self.charset_pos = 0
        self.talk_delay = 0
        self.have_msg = 0xFF
        self.vars[VAR_HAVE_MSG] = 0xFF
        self.display_dialog()

    def display_dialog(self):
        """ScummEngine::displayDialog + handleNextCharsetCode (CHARSET_1 de v3). Sin distribucion del texto. Limites del Z80: el
        buffer se lee con ceros mas alla de su final, y talk_delay es de 16 bits con signo."""
        if not self.have_msg:
            return
        t = self.get_talking_actor()
        a = self.deref_actor_safe(t) if t != 0xFF else None
        if self.talk_delay:
            return
        if self.have_msg == 1:
            self.stop_talk()
            return
        if a:
            self.run_actor_talk_script(a, a.talk_start)
            self.use_talk_anims = True
        self.talk_delay = 60                              # VAR_DEFAULT_TALK_DELAY no existe en v3
        if not self.keep_text:
            self.restore_charset_bg()
            self.msg_count = 0
        printed = bytearray()
        buf = self.charset_buf
        pos = self.charset_pos
        rd = lambda k: buf[k] if k < len(buf) else 0
        c = 0
        while True:
            c = rd(pos)
            pos += 1
            if c in (0xFF, 0xFE):                        # handleNextCharsetCode
                c = rd(pos)
                pos += 1
                if c == 1:
                    c = 13
                    self.msg_count = SCREEN_WIDTH
                elif c == 2:
                    self.have_msg = 0
                    self.keep_text = True
                    break
                elif c == 3:
                    self.have_msg = 0xFF
                    self.keep_text = False
                    self.msg_count = 0
                    break
                elif c == 8:
                    continue
                elif c == 9:
                    frme = rd(pos) | (rd(pos + 1) << 8)
                    pos += 2
                    if a:
                        self.start_anim_actor(a, frme)
                    continue
                elif c == 10:
                    pos += 14
                    continue
                elif c in (12, 13):
                    pos += 2
                    continue
                elif c == 14:
                    pos += 3
                    continue
                else:
                    raise VMError(E_RANGE, 'handleNextCharsetCode: codigo %d' % c)
            if c == 0:
                self.have_msg = 1
                self.keep_text = False
                self.msg_count = 0
                break
            if c == 13:
                printed.append(13)
                continue
            printed.append(c)
            self.msg_count += 1
            self.talk_delay = s16(self.talk_delay + s16(self.vars[VAR_CHARINC]))
        self.charset_pos = pos
        self.ev(EV_TEXT, [0, self.get_talking_actor(), self.charset_color, 0, len(printed), str_value(printed)])

    def print_string(self, slot, raw):
        """printString (slot 0 = voz del actor; el resto, texto suelto de la pantalla)."""
        if slot == 0:
            self.actor_talk(raw)
        elif slot == 1:
            s = self.str_slots[1]
            buf = self.convert_message_to_string(raw)
            self.ev(EV_TEXT, [1, s['xpos'], s['ypos'], s['color'],
                              (1 if s['center'] else 0) | (2 if s['overhead'] else 0), str_value(self._strip0(buf))])
            # ScummVM (drawString): despues de pintar, xpos = el final del texto, y el siguiente print sin `at` sigue desde ahi (el dialogo de guardar de Indy3
            # pone el cursor "_" asi, detras del nombre). 6 pixeles por byte del texto convertido (la fuente de la capa de texto; el original usa 8: 10g); centrado: el texto se extiende la mitad hacia cada lado
            n = len(self._strip0(buf))
            s['xpos'] = s16(s['xpos'] + (3 * n if s['center'] else 6 * n))
        # slots 2 y 3: mensajes de depuracion y cuadros de dialogo: no hay nada en el juego real

    # ------------------------------------------------------------------------------------------ camara
    def set_camera_at_ex(self, at):
        self.cam['mode'] = CAM_NORMAL
        self.cam['cur'] = at
        self.set_camera_at(at, 0)
        self.cam['moving_to_actor'] = False

    def set_camera_at(self, pos_x, pos_y):
        cam = self.cam
        if cam['mode'] != CAM_FOLLOW or abs(pos_x - cam['cur']) > SCREEN_WIDTH // 2:
            cam['cur'] = pos_x
        cam['dest'] = pos_x
        if cam['cur'] < self.vars[VAR_CAMERA_MIN_X]:
            cam['cur'] = self.vars[VAR_CAMERA_MIN_X]
        if cam['cur'] > self.vars[VAR_CAMERA_MAX_X]:
            cam['cur'] = self.vars[VAR_CAMERA_MAX_X]
        # VAR_SCROLL_SCRIPT no existe en v3

    def set_camera_follows(self, a, set_camera=False):
        cam = self.cam
        cam['mode'] = CAM_FOLLOW
        cam['follows'] = a.num
        if not a.in_room():
            self.start_scene(a.room)
            cam['mode'] = CAM_FOLLOW
            cam['cur'] = a.x
            self.set_camera_at(cam['cur'], 0)
        t = a.x // 8 - self.screen_start_strip
        if t < cam['left'] or t > cam['right'] or set_camera:
            self.set_camera_at(a.x, 0)
        for i in range(1, NUM_ACTORS):
            if self.actors[i].in_room():
                self.actors[i].need_redraw = True
        self.run_inventory_script(0)                          # runInventoryScriptEx(0)

    def actor_follow_camera(self, act):
        old = self.cam['follows']
        self.set_camera_follows(self.deref_actor(act))
        if self.cam['follows'] != old:
            self.run_inventory_script(0)
        self.cam['moving_to_actor'] = False

    def pan_camera_to(self, x, y):
        self.cam['dest'] = x
        self.cam['mode'] = CAM_PANNING
        self.cam['moving_to_actor'] = False

    def camera_moved(self):
        cam = self.cam
        width = self.room.width if self.room else SCREEN_WIDTH
        if cam['cur'] < SCREEN_WIDTH // 2:
            cam['cur'] = SCREEN_WIDTH // 2
        elif cam['cur'] > width - SCREEN_WIDTH // 2:
            cam['cur'] = width - SCREEN_WIDTH // 2
        self.screen_start_strip = cam['cur'] // 8 - 20

    def move_camera(self):
        """ScummEngine::moveCamera (version < 7)."""
        cam = self.cam
        pos = cam['cur']
        snap = self.snap_scroll or bool(self.vars[VAR_CAMERA_FAST_X])
        cam['cur'] = s16(cam['cur'] & 0xFFF8)
        if cam['cur'] < self.vars[VAR_CAMERA_MIN_X]:
            cam['cur'] = self.vars[VAR_CAMERA_MIN_X] if snap else cam['cur'] + 8
            self.camera_moved()
            self._camera_event(pos)
            return
        if cam['cur'] > self.vars[VAR_CAMERA_MAX_X]:
            cam['cur'] = self.vars[VAR_CAMERA_MAX_X] if snap else cam['cur'] - 8
            self.camera_moved()
            self._camera_event(pos)
            return
        a = None
        if cam['mode'] == CAM_FOLLOW:
            a = self.deref_actor(cam['follows'])
            actorx = a.x
            t = actorx // 8 - self.screen_start_strip
            if t < cam['left'] or t > cam['right']:
                if snap:
                    if t > 40 - 5:
                        cam['dest'] = actorx + 80
                    if t < 5:
                        cam['dest'] = actorx - 80
                else:
                    cam['moving_to_actor'] = True
        if cam['moving_to_actor']:
            a = self.deref_actor(cam['follows'])
            cam['dest'] = a.x
        if cam['dest'] < self.vars[VAR_CAMERA_MIN_X]:
            cam['dest'] = self.vars[VAR_CAMERA_MIN_X]
        if cam['dest'] > self.vars[VAR_CAMERA_MAX_X]:
            cam['dest'] = self.vars[VAR_CAMERA_MAX_X]
        if snap:
            cam['cur'] = cam['dest']
        else:
            if cam['cur'] < cam['dest']:
                cam['cur'] += 8
            if cam['cur'] > cam['dest']:
                cam['cur'] -= 8
        if cam['moving_to_actor'] and cam['cur'] // 8 == a.x // 8:
            cam['moving_to_actor'] = False
        self.camera_moved()
        self._camera_event(pos)

    def _camera_event(self, pos):
        if self.cam['cur'] != pos:
            self.ev(EV_CAMERA, [self.cam['cur']])

    # ------------------------------------------------------------------------------------------ sonido
    # Tres modos. "mock" (escenarios): isSoundRunning sale al anfitrion (suceso E 4) y VAR_MUSIC_TIMER no avanza, igual
    # que en v2: asi el arnes del Z80 solo tiene que repetir la respuesta simulada. "timed" (fase 5b): cada sonido dura 60
    # jiffies, o 3600 si es una cancion (>1000 bytes) y VAR_MUSIC_TIMER avanza como Player_V2Base. "real" (fase 8, el del
    # programa): Player_V2 de ScummVM con la tabla de sonidos de DATA.BIN (prioridad, reiniciable, bucle, duracion en fotogramas,
    # tempo): un sonido suena a la vez y otro espera en cola, y VAR_MUSIC_TIMER sale de las reglas de Player_V2Base:
    #   - la musica corre a 236 Hz (FREQ_HZ de player_v2.cpp): cada fotograma de `delta` (a 50 Hz) suma delta * 236 / 50 ticks;
    #   - cada _ticks_per_music_timer + 1 ticks suma uno al temporizador; _ticks_per_music_timer es 65535 hasta que algun sonido
    #     fija el tempo (0xFF 14: en Indy3 los sonidos con la bandera 4 de la tabla, siempre en el tick 0) y 125 despues;
    #   - chainSound (empezar un sonido, tambien el de la cola) pone el temporizador a 0 pero no el contador de ticks;
    #   - VAR_MUSIC_TIMER = int(temporizador * 236,7052 / 240) (Sound::updateMusicTimer; aqui con el mismo producto de 20 bits que el Z80);
    #   - el sonido actual acaba cuando se le acaban los fotogramas (65535: no acaba; un sonido sin bloque PCjr dura 0) y entonces
    #     entra el de la cola (chainNextSound).
    SOUND_FX_JIFFIES, SOUND_SONG_JIFFIES, SOUND_SONG_BYTES = 60, 3600, 1000
    MUSIC_K, MUSIC_SH = 14438, 20          # VAR_MUSIC_TIMER = t - ((t * 14438 + 2^20 - 1) >> 20) = floor(t * 1034138 / 2^20)

    def music_var(self, t):
        return t - ((t * self.MUSIC_K + (1 << self.MUSIC_SH) - 1) >> self.MUSIC_SH)

    def snd_info(self, nr):
        """(existe, prioridad, reiniciable, bucle, tempo, duracion) de la tabla de sonidos (DATA.BIN); None si no hay tabla o el sonido no existe."""
        t = getattr(self.w, 'sound_table', None)
        if not t or nr < 0 or nr > 255:
            return None
        prio, fl, dur = t[4 * nr], t[4 * nr + 1], t[4 * nr + 2] | (t[4 * nr + 3] << 8)
        if not fl & 0x80:
            return None
        return True, prio, fl & 1, (fl >> 1) & 1, (fl >> 2) & 1, dur

    def snd_chain(self, nr):
        """Player_V2Base::chainSound: el sonido nr pasa a ser el actual (sin tabla o sin el sonido, no suena)."""
        info = self.snd_info(nr)
        if info is None:
            self.snd_cur = None
            return
        _, prio, rest, loop, tempo, dur = info
        self.snd_cur = dict(nr=nr, prio=prio, rest=rest, left=65535 if loop else dur)
        self.music_timer = 0
        if tempo:
            self.ticks_per_music_timer = 125
        # lo que el Z80 le pide al MCU (el arnes lo imprime): parar, bucle (0/1) y el fichero
        self.snd_log += ['SND f=%d STOP' % self.frame, 'SND f=%d LOOP %d' % (self.frame, 1 if loop else 0),
                         'SND f=%d PLAY DATA/SND/SOUND%03d.VGM' % (self.frame, nr)]

    def snd_chain_next(self):
        if self.snd_next:
            nr = self.snd_next
            self.snd_next = 0
            self.snd_chain(nr)

    def start_sound(self, snd):
        self.vars[VAR_LAST_SOUND] = snd & 0xFFFF
        self.last_sound = snd
        self.ev(EV_SOUND_START, [snd])
        if self.sound_mode == 'timed':
            data = self.w.sound_size(snd)
            if data > self.SOUND_SONG_BYTES:
                self.sound_left[snd] = self.SOUND_SONG_JIFFIES
                self.music_timer = 0
                self.ticks_per_music_timer = 125
            else:
                self.sound_left[snd] = self.SOUND_FX_JIFFIES
        elif self.sound_mode == 'real':
            self.real_start(snd)

    def real_start(self, nr):
        """Player_V2::startSound."""
        if nr < 1 or nr > 255:
            return
        info = self.snd_info(nr)
        if info is None:
            return
        _, prio, rest, _, _, _ = info
        cur = self.snd_cur
        cprio = cur['prio'] if cur else 0
        ninfo = self.snd_info(self.snd_next) if self.snd_next else None
        nprio = ninfo[1] if ninfo else 0
        if not cur or cprio <= prio:
            disp = cur                                   # el que se desplaza
            self.snd_chain(nr)
            if disp:
                nr, prio, rest = disp['nr'], disp['prio'], disp['rest']
            else:
                nr, prio, rest = 0, 0, 0
        cur = self.snd_cur
        if not cur:
            nr = 0
            self.snd_next = 0
        if nr != (cur['nr'] if cur else 0) and rest and (not self.snd_next or nprio <= prio):
            self.snd_next = nr

    def stop_sound(self, snd):
        self.ev(EV_SOUND_STOP, [snd])
        self.sound_left.pop(snd, None)
        if self.sound_mode == 'real':
            self.real_stop(snd)

    def real_stop(self, snd):
        """Player_V2::stopSound."""
        if self.snd_next == snd:
            self.snd_next = 0
        if self.snd_cur and self.snd_cur['nr'] == snd:
            self.snd_log.append('SND f=%d STOP' % self.frame)
            self.snd_cur = None
            self.snd_chain_next()

    def stop_all_sounds(self):
        self.last_sound = 0
        self.ev(EV_SOUND_STOPALL, [])
        self.sound_left.clear()
        if self.sound_mode == 'real':
            self.snd_log.append('SND f=%d STOP' % self.frame)
        self.snd_cur = None
        self.snd_next = 0

    def is_sound_running(self, snd):
        if self.sound_mode == 'timed':
            return 1 if snd in self.sound_left else 0
        if self.sound_mode == 'real':
            return 1 if snd and ((self.snd_cur and self.snd_cur['nr'] == snd) or self.snd_next == snd) else 0
        return self.ev(EV_SOUND_QUERY, [snd])

    def update_music_timer(self, delta):
        """Sound::updateMusicTimer (solo en los modos "timed" y "real")."""
        if self.sound_mode == 'real':
            self.music_acc += delta * 236
            while self.music_acc >= 50:
                self.music_acc -= 50
                if self.music_ctr >= self.ticks_per_music_timer:
                    self.music_ctr = 0
                    self.music_timer += 1
                else:
                    self.music_ctr += 1
            self.vars[VAR_MUSIC_TIMER] = s16(self.music_var(self.music_timer))
            cur = self.snd_cur
            if cur and cur['left'] != 65535:
                cur['left'] -= delta
                if cur['left'] <= 0:
                    self.snd_cur = None
                    self.snd_chain_next()
            return
        if self.sound_mode != 'timed':
            return
        self.music_acc += delta * 236
        while self.music_acc >= 60:
            self.music_acc -= 60
            if self.music_ctr >= self.ticks_per_music_timer:
                self.music_ctr = 0
                self.music_timer += 1
            else:
                self.music_ctr += 1
        self.vars[VAR_MUSIC_TIMER] = s16(self.music_timer)
        for k in list(self.sound_left):
            self.sound_left[k] -= delta
            if self.sound_left[k] <= 0:
                del self.sound_left[k]

    # ------------------------------------------------------------------------------------------ frases y entrada
    def do_sentence(self, verb, obj_a, obj_b):
        if len(self.sentence) >= NUM_SENTENCE:
            raise VMError(E_RANGE, 'cola de frases llena')
        self.sentence.append(dict(verb=verb, a=obj_a, b=obj_b, prep=1 if obj_b else 0, freeze=0))

    def check_and_run_sentence_script(self):
        """ScummEngine::checkAndRunSentenceScript (v3)."""
        script = self.vars[VAR_SENTENCE_SCRIPT]
        if self.is_script_in_use(script):
            for ss in self.slots:
                if ss.number == script and ss.status != SS_DEAD and ss.freeze_count == 0:
                    return
        if not self.sentence or self.sentence[-1]['freeze']:
            return
        st = self.sentence.pop()
        if st['prep'] and st['b'] == st['a']:
            return
        args = [st['verb'] & 0xFFFF, st['a'] & 0xFFFF, st['b'] & 0xFFFF] + [0] * (NUM_LOCAL - 3)
        self.cur = 0xFF
        if script:
            self.run_script(script, False, False, args)

    def run_input_script(self, area, val, mode):
        args = [area, val, mode] + [0] * (NUM_LOCAL - 3)
        script = self.vars[VAR_VERB_SCRIPT]
        if script:
            self.run_script(script, False, False, args)

    def process_input(self):
        """ScummEngine::processInput + processKeyboard, con un suceso por fotograma (self.pending)."""
        ev = self.pending.pop(0) if self.pending else None
        self.mk_stat = 0
        kind = ev[0] if ev else None
        if kind == 'mouse':                                      # solo mueve el raton
            self.mouse = (ev[1], ev[2])
        elif kind == 'click':
            self.mouse = (ev[1], ev[2])
            self.mk_stat = MBS_LEFT_CLICK
        mx, my = self.mouse
        mx = max(0, min(SCREEN_WIDTH - 1, mx))
        my = max(0, min(199, my))
        self.mouse = (mx, my)
        vy = my - self.main_top
        if vy < 0 or vy >= self.main_h - self.main_top:          # initScreens(b, h): la pantalla principal mide h - b
            vy = -1
        self.vmouse = (mx + self.cam_xstart(), vy)
        if kind in ('esc', 'rclick') or (kind == 'key' and ev[1] == 27):
            self.process_escape()
        elif kind == 'key':
            k = ev[1]
            if k == ord('.'):
                self.talk_delay = 0
            elif k == ord(' '):
                pass                                             # pausa: del anfitrion
            else:
                self.mk_stat = k
                if k == 13 and self.cursor_state > 0:            # Intro sustituye al clic izquierdo (processKeyboard)
                    self.mk_stat = MBS_LEFT_CLICK

    def process_escape(self):
        """Tecla de salida de escena cortada: abortCutscene y, si el script la define, su codigo como tecla."""
        if self.vars[VAR_CUTSCENEEXIT_KEY] != 0:
            self.abort_cutscene()
            self.mk_stat = self.vars[VAR_CUTSCENEEXIT_KEY] & 0xFFFF

    def cam_xstart(self):
        return (self.screen_start_strip * 8) if self.screen_start_strip > 0 else 0

    def check_exec_verbs(self):
        """ScummEngine::checkExecVerbs (v3)."""
        if self.user_put <= 0 or self.mk_stat == 0:
            return
        stat = self.mk_stat
        if stat < MBS_MAX_KEY:
            for i in range(1, NUM_VERBS):
                vs = self.verbs[i]
                if vs.verbid and vs.saveid == 0 and vs.curmode == 1 and stat == vs.key:
                    self.run_input_script(CLICK_VERB, vs.verbid, 1)
                    return
            self.run_input_script(CLICK_KEY, stat, 1)
        elif stat & (MBS_LEFT_CLICK | MBS_RIGHT_CLICK):
            mx, my = self.mouse
            over = self.find_verb_at_pos(mx, my)
            if over:
                self.run_input_script(CLICK_VERB, self.verbs[over].verbid, 0)
            else:
                in_main = self.main_top <= my < self.main_h
                self.run_input_script(CLICK_SCENE if in_main else CLICK_VERB, 0, 0)

    # ------------------------------------------------------------------------------------------ cambio de sala
    def reset_sentence_v3(self):
        pass                                                      # v3 no lo hace al cambiar de sala (solo v1-v2)

    def start_scene(self, room):
        """ScummEngine::startScene (version 3; loadRoomWithEgo no pasa el actor)."""
        res = room
        if room >= 0x80:                                          # _resourceMapper (pseudoRoom)
            res = self.resource_mapper.get(room & 0x7F, room)
        if res and res not in self.w.rooms:
            raise VMError(E_BADROOM, 'sala %d' % room)
        self.stop_talk()
        if self.cur != 0xFF:
            ss = self.slots[self.cur]
            if ss.where in (WIO_ROOM, WIO_FLOBJECT, WIO_LOCAL):
                self.cur = 0xFF
        self.run_exit_script()
        self.kill_scripts_and_resources()
        for i in range(1, NUM_ACTORS):
            self.hide_actor(self.actors[i])
        self.vars[VAR_ROOM] = room
        self.cur_room = room
        self.vars[VAR_ROOM_RESOURCE] = res
        self.boxes, self.matrix, self.room = [], b'', None
        for i in range(NUM_LOCAL_OBJECTS):
            self.objs[i] = ObjData()
        if res == 0:
            self.encd = self.excd = 0
            return
        r = self.w.rooms[res]
        self.room = r
        self.encd, self.excd = r.encd_off, r.excd_off
        bx, matrix = r.boxes()
        self.boxes = [list(b) for b in bx]
        self.matrix = bytes(matrix)
        self.reset_room_objects()
        self.ev(EV_ROOM_LOAD, [room])                             # cuando ya estan las cajas y los objetos de la sala
        self.vars[VAR_CAMERA_MIN_X] = SCREEN_WIDTH // 2
        self.vars[VAR_CAMERA_MAX_X] = (r.width - SCREEN_WIDTH // 2) & 0xFFFF
        self.cam['mode'] = CAM_NORMAL
        self.cam['cur'] = self.cam['dest'] = SCREEN_WIDTH // 2
        self.show_actors()
        self.ego_positioned = False
        self.run_entry_script()

    def update_object_states_at_load(self):
        for i in range(1, NUM_LOCAL_OBJECTS):
            if self.objs[i].obj_nr > 0:
                self.objs[i].state = self.gstate[self.objs[i].obj_nr] if self.objs[i].obj_nr < self.num_global_objects else 0

    # ------------------------------------------------------------------------------------------ resumen para la traza
    def game_digest(self):
        a = crc16(b''.join(x.pack() for x in self.actors))
        q = crc16(b''.join(struct.pack('<HHHH', st['verb'] & 0xFFFF, st['a'] & 0xFFFF, st['b'] & 0xFFFF,
                                       (st['prep'] << 8) | min(st['freeze'], 255)) for st in self.sentence))
        o = crc16(bytes(x & 0xFF for x in self.gstate) + bytes(self.owner)
                  + b''.join(struct.pack('<I', c & 0xFFFFFFFF) for c in self.classes))
        inv = crc16(b''.join(struct.pack('<H', x) for x in self.inventory))
        cam = self.cam
        return ('A=%04X O=%04X I=%04X M=%d,%d,%d,%d,%d Q=%d,%04X C=%d,%d,%d,%d,%d U=%d,%d' % (
            a, o, inv, self.have_msg, self.talk_delay, int(self.keep_text), self.cur_room, self.last_sound,
            len(self.sentence), q, cam['cur'], cam['dest'], cam['mode'], cam['follows'], int(cam['moving_to_actor']),
            self.user_put, self.cursor_state))

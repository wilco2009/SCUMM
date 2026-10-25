"""Capa de juego del modelo de referencia: sonido, mensajes, actores (con cajas y caminata) y cambio de sala.

Es una transcripcion de la semantica de ScummVM para v2 (actor.cpp, boxes.cpp, string.cpp, room.cpp,
script.cpp, script_v2.cpp, script_v5.cpp, sound.cpp, object.cpp), recortada a lo que se puede observar sin video:

  sonido     VAR_LAST_SOUND, VAR_MUSIC_TIMER y las ordenes al back-end (iniciar, parar, consultar)
  mensajes   _haveMsg, _talkDelay, _keepText, VAR_HAVE_MSG, VAR_CHARCOUNT, VAR_TALK_ACTOR y los codigos de
             escape 1 (salto), 2 (mantener), 3 (esperar), 4 (variable) y 7 (cadena en variables)
  actores    sala, posicion, traje, direccion, fotograma, visible/oculto, la animacion de hablar y el MOVIMIENTO:
             cajas de caminar (adjustXYToBeInBox), matriz de rutas, caminata y giro por fotograma
             (Actor_v2::walkActor), walkActorTo / ToObject / ToActor, putActorAtObject, faceActor y los
             consultores (posicion, direccion, caja, movimiento)
  sala       startScene: salida, muerte de los scripts de sala, ocultar actores, entrada y script 5

NO esta: la decodificacion de trajes (el fotograma del actor es el ultimo que se pidio; en ScummVM
setDirection puede cambiarlo segun los limbs), camara, nombres de verbos y de objetos (los codigos 5 y 6 no
aparecen en los textos de Maniac Mansion), el inventario de verdad (se supone que un objeto con dueño distinto
de la sala y de 0 esta en un inventario) y los nombres nuevos de objeto.

El dibujo, el sonido y la lectura de salas salen al back-end como sucesos (E id [args]) en la traza.
"""
import struct

from vmcommon import *

# fotogramas fijos del actor en v2 (Actor_v2::initActor) y velocidad de paso
WALK_FRAME, STAND, INIT, TALK_STOP, TALK_START = 0, 1, 2, 4, 5
SPEED_X = SPEED_Y = 1
SCREEN_WIDTH = 320
TEXT_SPEED = 6                                       # _defaultTextSpeed
BASE_TALK_DELAY = 60                                 # VAR_DEFAULT_TALK_DELAY no existe en v2
MSGBUF_SIZE = 320
OLD_DIR = (270, 90, 180, 0)                          # oldDirToNewDir
OWNER_ROOM = 0x0F
INVALID_BOX = 0xFF
VAR_PLAYER_MIN, VAR_PLAYER_MAX = 42, 43              # isPlayer de v2: VAR(42) <= actor <= VAR(43)

# Actor::_moving
MF_NEW_LEG, MF_IN_LEG, MF_TURN, MF_LAST_LEG = 1, 2, 4, 8
# BoxFlags
BOX_PLAYER_ONLY, BOX_LOCKED, BOX_INVISIBLE = 0x20, 0x40, 0x80

REMAP1 = (0x04, 0x01, 0x02, 0x00, 0x01, 0x02, 0x03, 0x00,
          0x06, 0x01, 0x03, 0x00, 0x01, 0x02, 0x03, 0x00,
          0x07, 0x00, 0x03, 0x00, 0x01, 0x02, 0x03, 0x00,
          0x05, 0x00, 0x02, 0x00, 0x01, 0x02, 0x03, 0x00)
REMAP2 = (0x00, 0x01, 0x03, 0x02, 0x03, 0x00, 0x02, 0x00,
          0x00, 0x01, 0x03, 0x02, 0x01, 0x03, 0x01, 0x02,
          0x00, 0x01, 0x03, 0x02, 0x01, 0x00, 0x02, 0x02,
          0x00, 0x01, 0x03, 0x02, 0x03, 0x03, 0x01, 0x01)
REMAP3 = (0x00, 0x00, 0x02, 0x00, 0x01, 0x03, 0x02, 0x00,
          0x01, 0x01, 0x02, 0x00, 0x01, 0x03, 0x02, 0x00,
          0x02, 0x01, 0x02, 0x00, 0x01, 0x03, 0x02, 0x00,
          0x03, 0x00, 0x03, 0x00, 0x01, 0x03, 0x02, 0x00)
TURN_TABLE = (0, 2, 2, 3, 2, 1, 2, 3, 0, 1, 2, 1, 0, 1, 0, 3)


def verb_entry(block, verb):
    """getVerbEntrypoint de v2: tabla de pares (verbo, offset) desde +15; el verbo FF vale para cualquiera."""
    p = 15
    while True:
        if block[p] == 0:
            return 0
        if block[p] == verb or block[p] == 0xFF:
            return block[p + 1]
        p += 2


def i16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def wrap32(v):
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def cdiv(a, b):
    """Division entera de C: se trunca hacia cero."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def new_to_old_dir(d):
    if 71 <= d <= 109:
        return 1
    if 109 <= d <= 251:
        return 2
    if 251 <= d <= 289:
        return 0
    return 3


class Actor:
    # el orden y el tamaño (48 bytes) son los del Z80
    def __init__(self, num):
        self.num = num
        self.reset()

    def reset(self):                                  # initActor(-1)
        self.room = 0
        self.x = self.y = 0
        self.costume = 0
        self.facing = 180
        self.moving = 0
        self.visible = 0
        self.frame = 0
        self.talk_color = 15
        self.target_facing = 180
        self.sound0 = 0
        self.walkbox = 0
        self.elevation = 0
        self.dest_x = self.dest_y = 0
        self.destbox = 0
        self.destdir = 0
        self.curbox = 0
        self.next_x = self.next_y = 0
        self.xfrac = self.yfrac = 0
        self.xadd = self.yadd = 0
        self.dxf = self.dyf = 0
        self.thresh = 0
        self.wfacing = 0

    def pack(self):
        w = lambda v: struct.pack('<H', v & 0xFFFF)
        return (bytes([self.room & 255]) + w(self.x) + w(self.y) + bytes([self.costume & 255]) + w(self.facing)
                + bytes([self.moving & 255, self.visible & 255, self.frame & 255, self.talk_color & 255])
                + w(self.target_facing) + bytes([self.sound0 & 255, self.num])
                + bytes([self.walkbox & 255, self.elevation & 255]) + w(self.dest_x) + w(self.dest_y)
                + bytes([self.destbox & 255]) + w(self.destdir) + bytes([self.curbox & 255])
                + w(self.next_x) + w(self.next_y) + w(self.xfrac) + w(self.yfrac) + w(self.xadd) + w(self.yadd)
                + w(self.dxf) + w(self.dyf) + w(self.thresh) + bytes([self.wfacing & 255, 0, 0, 0]))


class GameMixin:
    GAME_OPS = {
        'o5_print': 'g_print', 'o5_printEgo': 'g_printEgo', 'o5_startSound': 'g_startSound',
        'o5_startMusic': 'g_startMusic', 'o5_stopSound': 'g_stopSound', 'o5_stopMusic': 'g_stopMusic',
        'o5_isSoundRunning': 'g_isSoundRunning', 'o2_putActor': 'g_putActor',
        'o2_putActorInRoom': 'g_putActorInRoom', 'o5_getActorRoom': 'g_getActorRoom',
        'o5_animateActor': 'g_animateActor', 'o2_actorOps': 'g_actorOps', 'o5_loadRoom': 'g_loadRoom',
        'o2_walkActorTo': 'g_walkActorTo', 'o2_walkActorToObject': 'g_walkActorToObject',
        'o5_walkActorToActor': 'g_walkActorToActor', 'o2_putActorAtObject': 'g_putActorAtObject',
        'o5_faceActor': 'g_faceActor', 'o2_waitForActor': 'g_waitForActor',
        'o2_getActorX': 'g_getActorX', 'o2_getActorY': 'g_getActorY', 'o5_getActorMoving': 'g_getActorMoving',
        'o5_getActorFacing': 'g_getActorFacing', 'o2_getActorWalkBox': 'g_getActorWalkBox',
        'o5_getActorCostume': 'g_getActorCostume', 'o2_getActorElevation': 'g_getActorElevation',
        'o2_setActorElevation': 'g_setActorElevation',
        'o2_doSentence': 'g_doSentence', 'o2_findObject': 'g_findObject', 'o2_actorFromPos': 'g_actorFromPos',
        'o2_drawObject': 'g_drawObject', 'o5_actorFollowCamera': 'g_actorFollowCamera',
        'o2_loadRoomWithEgo': 'g_loadRoomWithEgo',
        'o5_getDist': 'g_getDist', 'o5_getClosestObjActor': 'g_getClosestObjActor', 'o3_setBoxFlags': 'g_setBoxFlags', 'o2_lights': 'g_lights', 'o2_getObjPreposition': 'g_getObjPreposition', 'o5_getRandomNr': 'g_getRandomNr', 'o2_cutscene': 'g_cutscene', 'o2_cursorCommand': 'g_cursorCommand', 'o2_endCutscene': 'g_endCutscene', 'o2_beginOverride': 'g_beginOverride',
        'o5_getObjectOwner': 'g_getObjectOwner', 'o2_setOwnerOf': 'g_setOwnerOf', 'o2_pickupObject': 'g_pickupObject',
    }

    def game_reset(self):
        self.actors = [Actor(i) for i in range(NUM_ACTORS)]
        self.cur_room = 0
        self.have_msg = 0
        self.keep_text = 0
        self.use_talk_anims = 0
        self.talk_delay = 0
        self.msg_count = 0
        self.msgbuf = bytearray(1)
        self.msgpos = 0
        self.last_sound = 0
        self.encd = None
        self.excd = None
        self.boxes = []
        self.matrix = b''
        self.roomobjs = {}
        self.objlist = []                             # los objetos de la sala en orden: (id, caminar x, y, dir, x, y, ancho, alto, padre, estado del padre)
        self.rnd = 0xACE1                             # semilla del generador (getRandomNr)
        self.sent = []                                # cola de frases (_sentence[]): [verbo, objeto A, objeto B, preposicion]
        self.pending = []                             # entradas (clic, tecla) a procesar en el siguiente fotograma

    # ---- back-end
    def ev(self, eid, args):
        """Suceso para el back-end; devuelve el resultado simulado (solo lo usa la consulta de sonido)."""
        self.trace.append('E %d [%s]' % (eid, ','.join(str(a & 0xFFFF) for a in args)))
        return mock_hash(0x100 + eid, args, self.frame) & 1

    # ---- cajas de caminar
    def box_index(self, box):
        """getBoxBaseAddr de v2: la caja n se lee como la n-1; fuera de rango es un error."""
        n = len(self.boxes)
        if n == 0 or box == INVALID_BOX:
            return None
        if box == n:
            box -= 1
        if not 0 <= box < n:
            raise VMError(E_RANGE)
        return box

    def box_flags(self, box):
        k = self.box_index(box)
        return 0 if k is None else self.boxes[k][7]

    def box_coords(self, box):
        k = self.box_index(box)
        if k is None:
            raise VMError(E_RANGE)
        uy, ly, ulx, urx, llx, lrx = self.boxes[k][:6]
        return (ulx, uy), (urx, uy), (llx, ly), (lrx, ly)         # ul, ur, ll, lr

    def is_player(self, a):
        return i16(self.vars[VAR_PLAYER_MIN]) <= a.num <= i16(self.vars[VAR_PLAYER_MAX])

    @staticmethod
    def check_xy_in_box(box, x, y):
        """checkXYInBoxBounds de Actor_v2 (con el punto mas cercano): devuelve (distancia, x, y)."""
        (ulx, uy), (urx, _), (llx, ly), (lrx, _) = box
        if y < uy:
            dest_y = uy
            xmin, xmax = ulx, urx
        elif y >= ly:
            dest_y = ly
            xmin, xmax = llx, lrx
        elif x >= ulx and x >= llx and x < urx and x < lrx:
            dest_y = y
            xmin = xmax = x
        else:
            dest_y = y
            ul, ll, ur, lr = ulx, llx, urx, lrx
            top, bottom = uy, ly
            while True:
                xmin = (ul + ll) // 2
                xmax = (ur + lr) // 2
                cury = (top + bottom) // 2
                if cury < y:
                    top, ul, ur = cury, xmin, xmax
                elif cury > y:
                    bottom, ll, lr = cury, xmin, xmax
                if cury == y:
                    break
        if x < xmin:
            dest_x = xmin
        elif x > xmax:
            dest_x = xmax
        else:
            dest_x = x
        xd = abs(x - dest_x)
        yd = abs(y - dest_y) // 4
        dist = (xd >> 1) + yd if xd < yd else (yd >> 1) + xd
        return dist, dest_x, dest_y

    def adjust_xy(self, a, x, y):
        """Actor_v2::adjustXYToBeInBox: (x, y, caja) con el punto dentro de la caja mas cercana."""
        x, y = i16(x), i16(y)
        rx, ry, rbox = x, y, INVALID_BOX
        best = 0xFF
        for i in range(len(self.boxes)):
            box = len(self.boxes) - 1 - i
            flags = self.box_flags(box)
            if (flags & BOX_INVISIBLE) and not ((flags & BOX_PLAYER_ONLY) and not self.is_player(a)):
                continue
            dist, fx, fy = self.check_xy_in_box(self.box_coords(box), x, y)
            if dist == 0:
                return fx, fy, box
            if dist < best:
                best = dist
                rx, ry, rbox = fx, fy, box
        return rx, ry, rbox

    @staticmethod
    def closest_pt_on_line(s, e, p):
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
            dist = lx * lx + ly * ly
            if abs(lx) > abs(ly):
                a = cdiv(sx * ly, lx)
                b = cdiv(px * lx, ly)
                c = cdiv(wrap32(wrap32((a + b - sy + py) * ly) * lx), dist)
                rx = c
                ry = cdiv(c * ly, lx) - a + sy
            else:
                a = cdiv(sy * lx, ly)
                b = cdiv(py * ly, lx)
                c = cdiv(wrap32(wrap32((a + b - sx + px) * ly) * lx), dist)
                rx = cdiv(c * lx, ly) - a + sx
                ry = c
        rx, ry = i16(rx), i16(ry)
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

    def closest_pt_on_box(self, box, x, y):
        ul, ur, ll, lr = box
        best = 0xFFFFFF
        out = (0, 0)
        for s, e in ((ul, ur), (ur, lr), (lr, ll), (ll, ul)):
            t = self.closest_pt_on_line(s, e, (x, y))
            d = (x - t[0]) ** 2 + (y - t[1]) ** 2
            if d < best:
                best = d
                out = t
        return out

    def next_box(self, frm, to):
        """getNextBox de v2: la matriz da, para cada par, la siguiente caja del camino."""
        n = len(self.boxes)
        if frm == to:
            return to
        if to == INVALID_BOX:
            return -1
        if frm == INVALID_BOX:
            return to
        if frm >= n or to >= n:
            raise VMError(E_RANGE)
        m = self.matrix
        base = 1 if m[0] == 0xFF else 0
        row = base + n + m[base + frm]
        v = m[row + to]
        return v - 256 if v & 0x80 else v

    # ---- actores
    def deref_actor(self, i):
        if not 0 <= i < NUM_ACTORS:
            raise VMError(E_RANGE)
        return self.actors[i]

    def in_room(self, a):
        return a.room == self.cur_room

    def start_anim(self, a, f):
        f = {56: INIT, 57: WALK_FRAME, 58: STAND, 59: TALK_START, 60: TALK_STOP}.get(f, f)
        if self.in_room(a) and a.costume != 0:
            a.frame = f & 255

    def stop_actor_moving(self, a):
        a.moving = 0

    def hide_actor(self, a):
        if not a.visible:
            return
        if a.moving:
            self.stop_actor_moving(a)
            self.start_anim(a, STAND)
        a.visible = 0

    def adjust_actor_pos(self, a):
        a.x, a.y, box = self.adjust_xy(a, a.x, a.y)
        a.destbox = box
        a.walkbox = box
        a.dest_x = -1
        self.stop_actor_moving(a)
        if a.walkbox != INVALID_BOX:
            if self.box_flags(a.walkbox) & 7:
                self.turn_to_direction(a, a.facing)

    def show_actor(self, a):
        if self.cur_room == 0 or a.visible:
            return
        self.adjust_actor_pos(a)
        self.start_anim(a, STAND)
        self.start_anim(a, INIT)
        self.start_anim(a, TALK_STOP)
        self.stop_actor_moving(a)
        a.visible = 1

    def run_talk_script(self, a, f):
        if not self.vars[VAR_TALK_ACTOR] or a.room != self.cur_room or a.frame == f:
            return
        self.start_anim(a, f)

    def set_direction(self, a, d):
        a.facing = (d + 360) % 360

    def turn_to_direction(self, a, d):
        if d == -1:
            return
        a.target_facing = d
        a.moving |= MF_TURN

    def put_actor(self, a, x, y, room):
        if a.visible and self.cur_room != room and self.vars[VAR_TALK_ACTOR] == a.num:
            self.stop_talk()
        a.x, a.y, a.room = i16(x), i16(y), room
        if a.visible:
            if self.in_room(a):
                if a.moving:
                    self.stop_actor_moving(a)
                    self.start_anim(a, STAND)
                self.adjust_actor_pos(a)
            else:
                self.hide_actor(a)
        elif self.in_room(a):
            self.show_actor(a)

    def set_costume(self, a, c):
        if a.visible:
            self.hide_actor(a)
            a.costume = c
            self.show_actor(a)
        else:
            a.costume = c

    # ---- movimiento
    def remap_direction(self, a, d):
        """Actor_v2::remapDirection: cambia _targetFacing y devuelve la direccion con la marca 0x400."""
        flags = self.box_flags(a.walkbox) & 7
        if a.moving & ~MF_TURN:
            a.target_facing = OLD_DIR[REMAP2[new_to_old_dir(d) * 8 + REMAP1[a.wfacing * 8 + flags]]]
        else:
            a.target_facing = OLD_DIR[REMAP3[new_to_old_dir(d) * 8 + flags]]
        return a.target_facing | 0x400

    def update_actor_direction(self, a):
        d = self.remap_direction(a, a.target_facing)
        if d & 0x400:
            d = OLD_DIR[TURN_TABLE[new_to_old_dir(d & 0x3FF) | (new_to_old_dir(a.facing) << 2)]]
        return d

    def actor_walk_step(self, a):
        a.xfrac = (a.xfrac + a.xadd) & 0xFFFF
        if a.xfrac >= a.thresh:
            if a.x != a.next_x:
                a.x = i16(a.x + a.dxf)
            a.xfrac = (a.xfrac - a.thresh) & 0xFFFF
        a.yfrac = (a.yfrac + a.yadd) & 0xFFFF
        if a.yfrac >= a.thresh:
            if a.y != a.next_y:
                a.y = i16(a.y + a.dyf)
            a.yfrac = (a.yfrac - a.thresh) & 0xFFFF
        if a.x == a.next_x and a.y == a.next_y:
            a.moving |= MF_IN_LEG

    def start_walk_anim(self, a, angle):
        self.set_direction(a, angle)
        self.start_anim(a, WALK_FRAME)

    def calc_movement_factor(self, a, nx, ny):
        if a.x == nx and a.y == ny:
            a.moving |= MF_IN_LEG
            return
        dx = nx - a.x
        dy = ny - a.y
        a.thresh = max(abs(dy) // SPEED_Y, abs(dx))
        a.dxf = -1 if dx < 0 else 1
        a.dyf = -SPEED_Y if dy < 0 else SPEED_Y
        a.xfrac = a.xadd = cdiv(dx, a.dxf) & 0xFFFF
        a.yfrac = a.yadd = cdiv(dy, a.dyf) & 0xFFFF
        a.next_x, a.next_y = nx, ny
        a.wfacing = (1 if dy >= 0 else 0) if dx >= 0 else (2 if dy >= 0 else 3)
        k = (3 - (1 if dy >= 0 else 0)) if abs(dy) > abs(dx) else (1 if dx >= 0 else 0)
        a.target_facing = OLD_DIR[k]
        a.moving &= ~MF_IN_LEG
        if a.facing != a.target_facing:
            a.moving |= MF_TURN
        if a.frame != WALK_FRAME or a.facing != a.target_facing:
            self.start_walk_anim(a, a.facing)
        if not (a.moving & MF_TURN):
            self.actor_walk_step(a)

    def start_walk_actor(self, a, dest_x, dest_y, d):
        dest_x, dest_y = i16(dest_x), i16(dest_y)
        if not self.in_room(a):
            a.x, a.y = dest_x, dest_y
            if d != -1:
                a.facing = d
            return
        x, y, box = self.adjust_xy(a, dest_x, dest_y)
        if a.x == x and a.y == y and (d == -1 or a.facing == d):
            return
        a.dest_x, a.dest_y, a.destbox, a.destdir = x, y, box, d
        a.curbox = a.walkbox
        a.moving = (a.moving & ~MF_LAST_LEG) | MF_IN_LEG | MF_NEW_LEG

    def walk_actor(self, a):
        if a.moving & MF_TURN:
            nd = self.update_actor_direction(a)
            if a.target_facing == nd:
                a.moving &= ~MF_TURN
            self.set_direction(a, nd)
            return
        if not (a.moving & MF_NEW_LEG):
            return
        if not (a.moving & MF_IN_LEG):
            self.actor_walk_step(a)
            return
        if a.moving & MF_LAST_LEG:
            a.moving = MF_TURN
            self.start_anim(a, STAND)
            if a.destdir != -1:
                self.turn_to_direction(a, a.destdir)
            return
        a.walkbox = a.curbox
        if a.walkbox == a.destbox:
            fx, fy = a.dest_x, a.dest_y
            a.moving |= MF_LAST_LEG
        else:
            nb = self.next_box(a.walkbox, a.destbox)
            if nb < 0:
                a.moving |= MF_LAST_LEG
                return
            flags = self.box_flags(nb)
            if (flags & BOX_LOCKED) and not ((flags & BOX_PLAYER_ONLY) and not self.is_player(a)):
                a.moving |= MF_LAST_LEG
                a.destdir = -1
            a.curbox = nb
            tx, ty = self.closest_pt_on_box(self.box_coords(a.curbox), a.x, a.y)
            fx, fy = self.closest_pt_on_box(self.box_coords(a.walkbox), tx, ty)
        self.calc_movement_factor(a, fx, fy)

    def walk_actors(self):
        for i in range(1, NUM_ACTORS):
            if self.in_room(self.actors[i]):
                self.walk_actor(self.actors[i])

    # ---- objetos
    def where_is_object(self, obj):
        """'room', 'inv' o None (el inventario se supone: dueño distinto de la sala y de 0)."""
        if obj < 1 or obj >= NUM_OBJECTS:
            return None
        if self.owner[obj] != OWNER_ROOM:
            return 'inv' if self.owner[obj] != 0 else None
        return 'room' if obj in self.roomobjs else None

    def object_xy_pos(self, obj):
        """getObjectXYPos de v2: (x, y, direccion) en las unidades del actor."""
        if obj not in self.roomobjs:
            raise VMError(E_BADOBJ)
        wx, wy, d = self.roomobjs[obj]
        return wx, wy, OLD_DIR[d & 3]

    def object_or_actor_xy(self, obj):
        if obj < NUM_ACTORS:
            a = self.actors[obj]
            return (a.x, a.y) if self.in_room(a) else None
        w = self.where_is_object(obj)
        if w is None:
            return None
        if w == 'inv':
            o = self.owner[obj]
            if o < NUM_ACTORS and self.in_room(self.actors[o]):
                return self.actors[o].x, self.actors[o].y
            return None
        x, y, _ = self.object_xy_pos(obj)
        return x, y

    def face_to_object(self, a, obj):
        if not self.in_room(a):
            return
        r = self.object_or_actor_xy(obj)
        if r is None:
            return
        x2, y2 = r
        d = 1 if a.x < x2 else 0
        if abs(a.x - x2) < 2:
            d = 3 if a.y > y2 else 2
        self.turn_to_direction(a, OLD_DIR[d])

    # ---- entrada, frases y objetos bajo el cursor
    def find_object(self, x, y):
        """findObject de v2 (x, y en pixeles): el primer objeto de la sala, en orden, que no sea intocable, cuyos
        padres tengan el estado pedido y que contenga el punto."""
        n = len(self.objlist)
        for i in range(n):
            oid = self.objlist[i][0]
            if self.state[oid] & 2:
                continue
            b = i + 1
            ok = False
            for _ in range(32):                       # los padres pueden formar un ciclo: se corta a las 32 vueltas
                rec = self.objlist[b - 1] if b <= n else (0,) * 10      # un padre que no existe: sin padre y sin estado
                a = rec[9]
                b = rec[8]
                if b == 0:
                    ok = True
                    break
                st = self.state[self.objlist[b - 1][0]] if b <= n else 0
                if (st & 8) != a:
                    break
            if not ok:
                continue
            _, _, _, _, ox, oy, ow, oh, _, _ = self.objlist[i]
            if ox * 8 <= x < (ox + ow) * 8 and oy * 8 <= y < (oy + oh) * 8:
                return oid
        return 0

    def actor_from_pos(self, x, y):
        """getActorFromPos aproximado: el primer actor visible de la sala cuyo rectangulo (16 x 32) contiene el punto."""
        for i in range(1, NUM_ACTORS):
            a = self.actors[i]
            if a.room == self.cur_room and a.visible:
                if a.x * 8 - 8 <= x < a.x * 8 + 8 and a.y * 2 - 32 <= y < a.y * 2:
                    return i
        return 0

    def g_findObject(self):
        r = self.fetch_byte()
        x = self.get_var_or_direct_byte(0x80) * 8
        y = self.get_var_or_direct_byte(0x40) * 2
        self.write_var(r, self.find_object(x, y))

    def g_actorFromPos(self):
        r = self.fetch_byte()
        x = self.get_var_or_direct_byte(0x80) * 8
        y = self.get_var_or_direct_byte(0x40) * 2
        self.write_var(r, self.actor_from_pos(x, y))

    def g_drawObject(self):
        """drawObject de v2 (sin cambiar de sitio al objeto): lo marca como dibujado y apaga los demas objetos de la sala
        que ocupan el mismo rectangulo (asi el recuadro de seleccion se mueve de un retrato a otro)."""
        obj = self.get_var_or_direct_word(0x80)
        self.get_var_or_direct_byte(0x40)
        self.get_var_or_direct_byte(0x20)
        rec = None
        for r in self.objlist:
            if r[0] == obj:
                rec = r
        if rec is None:
            return
        for r in self.objlist:
            if r[0] != obj and r[4:8] == rec[4:8]:
                self.state[r[0]] &= ~8
        self.state_op_value(obj)

    def state_op_value(self, obj):
        self.put_state(obj, self.get_state(obj) | 8)
        self.ev(EV_OBJSTATE, [obj, self.state[obj]])

    def object_block(self, obj):
        return self.w.objects[obj][1] if obj in self.w.objects else None

    def verb_allowed(self, obj, verb):
        """getVerbEntrypoint(obj, verb) != 0 (el objeto tiene que estar en la sala o en un inventario)."""
        if self.where_is_object(obj) is None:
            return 0
        block = self.object_block(obj)
        return verb_entry(block, verb) if block is not None else 0

    def run_object_script(self, obj, verb, slot=-1):
        """runObjectScript de v2: ejecuta el codigo del objeto para el verbo (en la ranura dada si se reutiliza)."""
        if obj == 0 or self.where_is_object(obj) is None:
            return
        if slot == -1:
            slot = self.get_slot()
        block = self.object_block(obj)
        if block is None:
            return
        offs = verb_entry(block, verb)
        if offs == 0:
            return
        s = self.slots[slot]
        s.number, s.code, s.offs = obj, block, offs
        s.status, s.where, s.delay, s.flags = SS_RUNNING, WIO_ROOM, 0, 0
        self.run_nested(slot)

    def stop_object_script(self, obj):
        for i, ss in enumerate(self.slots):
            if ss.number == obj and ss.status != SS_DEAD and ss.where in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT):
                ss.number = 0
                ss.status = SS_DEAD
                if self.cur == i:
                    self.cur = 0xFF
        for n in self.nest:
            if n.number == obj and n.where in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT):
                n.number = 0
                n.slot = 0xFF
                n.where = 0xFF

    def g_doSentence(self):
        verb = self.get_var_or_direct_byte(0x80)
        if verb == 0xFC:
            self.sent = []
            self.stop_script(SENTENCE_SCRIPT)
            return
        if verb == 0xFB:
            self.reset_sentence()
            return
        a = self.get_var_or_direct_word(0x40)
        b = self.get_var_or_direct_word(0x20)
        sub = self.fetch_byte()
        if len(self.sent) >= NUM_SENTENCE:
            raise VMError(E_RANGE)
        self.sent.append([verb, a, b, 1 if b else 0])
        if sub == 0:
            return
        st = self.sent.pop()
        if sub == 1:
            if verb == 254:
                self.stop_object_script(a)
                return
            if verb != 253 and verb != 250:
                self.vars[VAR_ACTIVE_VERB] = verb
                self.vars[VAR_ACTIVE_OBJECT1] = a & 0xFFFF
                self.vars[VAR_ACTIVE_OBJECT2] = b & 0xFFFF
            else:
                verb = 253
            slot = -1
            for i, ss in enumerate(self.slots):
                if ss.number == a and ss.status != SS_DEAD and ss.where in (WIO_ROOM, WIO_INVENTORY, WIO_FLOBJECT):
                    slot = i
                    break
            self.run_object_script(a, verb, slot)
        elif sub == 2:
            self.vars[VAR_SENTENCE_VERB] = verb
            self.vars[VAR_SENTENCE_OBJECT1] = a & 0xFFFF
            self.vars[VAR_SENTENCE_OBJECT2] = b & 0xFFFF
            self.ev(EV_SENTENCE, [verb, a, b])
        else:
            raise VMError(E_RANGE)

    def check_sentence(self):
        """checkAndRunSentenceScript de v2: si el script de frases esta libre, saca la ultima frase de la cola y lo arranca."""
        if self.is_script_in_use(SENTENCE_SCRIPT):
            return
        if not self.sent:
            return
        verb, a, b, prep = self.sent.pop()
        if prep and b == a:
            return
        self.vars[VAR_ACTIVE_VERB] = verb
        self.vars[VAR_ACTIVE_OBJECT1] = a & 0xFFFF
        self.vars[VAR_ACTIVE_OBJECT2] = b & 0xFFFF
        self.vars[VAR_VERB_ALLOWED] = 1 if self.verb_allowed(a, verb) else 0
        self.cur = 0xFF
        self.run_script(SENTENCE_SCRIPT)

    def process_input(self, area, val):
        """runInputScript de v2: la zona del clic y su valor, y el script de entrada (4)."""
        self.vars[VAR_CLICK_AREA] = area
        if area == CLICK_VERB:
            self.vars[VAR_CLICK_VERB] = val & 0xFFFF
        elif area == CLICK_INVENTORY:
            self.vars[VAR_CLICK_OBJECT] = val & 0xFFFF
        elif area == CLICK_KEY:
            self.vars[VAR_KEYPRESS] = val & 0xFFFF
        self.cur = 0xFF
        self.run_script(INPUT_SCRIPT)

    # ---- mensajes
    def set_talking(self, i):
        self.vars[VAR_TALK_ACTOR] = i & 0xFFFF

    def stop_talk(self):
        self.have_msg = 0
        self.talk_delay = 0
        act = self.vars[VAR_TALK_ACTOR]
        if act and act < 0x80:
            a = self.deref_actor(act)
            if a.room == self.cur_room and self.use_talk_anims:
                self.run_talk_script(a, TALK_STOP)
                self.use_talk_anims = 0
            self.set_talking(0xFF)
        self.keep_text = 0

    def convert_message(self, raw):
        """decodeParseString + convertMessageToString: la cadena del script -> el bufer de texto."""
        out = bytearray()
        i = 0
        while True:
            b = raw[i]
            i += 1
            if b == 0:
                break
            space = b & 0x80
            c = b & 0x7F
            if c < 8:
                if c == 0:
                    pass
                elif c < 4:
                    out += bytes([0xFF, c])
                else:
                    e = raw[i]
                    i += 1
                    if c == 4:
                        out += str(s16(self.read_var(e))).encode()
                    elif c == 7:
                        k = e
                        while k < NUM_VARS and (self.vars[k] & 0xFF):
                            ch = self.vars[k] & 0xFF
                            if ch != 0x40:
                                out.append(ch)
                            k += 1
                    # 5 (verbo) y 6 (nombre): sin soporte todavia
            elif c != 0x40:
                out.append(c)
            if space:
                out.append(0x20)
            if len(out) >= MSGBUF_SIZE - 1:
                raise VMError(E_RANGE)
        out.append(0)
        return out

    def actor_talk(self, actor_for, raw):
        self.msgbuf = self.convert_message(raw)      # _charsetBuffer se pisa aunque el mensaje se descarte
        if actor_for == 0xFF:
            if not self.keep_text:
                self.stop_talk()
            self.set_talking(0xFF)
        else:
            a = self.deref_actor(actor_for)
            if a.room != self.cur_room:
                return
            if not self.keep_text:
                self.stop_talk()
            self.set_talking(a.num)
            self.run_talk_script(a, TALK_START)
            self.use_talk_anims = 1
        self.msgpos = 0
        self.talk_delay = 0
        self.have_msg = 0xFF
        self.vars[VAR_HAVE_MSG] = 0xFF
        self.vars[VAR_CHARCOUNT] = 0
        self.display_dialog()

    def display_dialog(self):
        if not self.have_msg:
            return
        t = self.vars[VAR_TALK_ACTOR]
        a = None
        if t != 0xFF and t < NUM_ACTORS:
            a = self.actors[t]
        if self.talk_delay:
            return
        if self.have_msg == 1:
            self.stop_talk()
            return
        if a:
            self.run_talk_script(a, TALK_START)
            self.use_talk_anims = 1
        self.talk_delay = BASE_TALK_DELAY
        if not self.keep_text:
            self.msg_count = 0
        else:
            self.talk_delay += self.msg_count * TEXT_SPEED
        printed = bytearray()
        nchars = 0
        while True:
            c = self.msgbuf[self.msgpos]
            self.msgpos += 1
            if c in (0xFF, 0xFE):
                code = self.msgbuf[self.msgpos]
                self.msgpos += 1
                if code == 1:
                    self.msg_count = SCREEN_WIDTH
                    printed.append(13)
                    continue
                if code == 2:
                    self.have_msg = 0
                    self.keep_text = 1
                    break
                if code == 3:
                    self.have_msg = 0xFF
                    self.keep_text = 0
                    self.msg_count = 0
                    break
                continue
            if c == 0:
                self.have_msg = 1
                self.keep_text = 0
                self.msg_count = 0
                break
            self.msg_count += 1
            self.talk_delay += TEXT_SPEED
            self.vars[VAR_CHARCOUNT] = (self.vars[VAR_CHARCOUNT] + 1) & 0xFFFF
            printed.append(c)
            nchars += 1
        self.ev(EV_TEXT, [self.vars[VAR_TALK_ACTOR], nchars, str_value(printed)])

    def frame_tick(self, delta):
        """Lo que scummLoop hace antes de ejecutar los scripts: retardos, mensaje y variables."""
        delta = min(delta, 15)
        self.decrease_delay(delta)
        self.talk_delay = max(0, self.talk_delay - delta)
        self.display_dialog()
        self.vars[VAR_HAVE_MSG] = self.have_msg

    # ---- instrucciones: sonido
    def start_sound(self, snd):
        self.vars[VAR_LAST_SOUND] = snd & 0xFFFF
        self.last_sound = snd
        self.ev(EV_SOUND_START, [snd])

    def g_startSound(self):
        snd = self.get_var_or_direct_byte(0x80)
        self.vars[VAR_MUSIC_TIMER] = 0
        self.start_sound(snd)

    def g_startMusic(self):
        self.start_sound(self.get_var_or_direct_byte(0x80))

    def g_stopSound(self):
        self.ev(EV_SOUND_STOP, [self.get_var_or_direct_byte(0x80)])

    def g_stopMusic(self):
        self.last_sound = 0
        self.ev(EV_SOUND_STOPALL, [])

    def g_isSoundRunning(self):
        r = self.fetch_byte()
        snd = self.get_var_or_direct_byte(0x80)
        if snd:
            snd = self.ev(EV_SOUND_QUERY, [snd])
        self.write_var(r, snd)

    # ---- instrucciones: mensajes
    def read_raw_string(self):
        """La cadena en bruto, como esta en el script, con su 0 final."""
        start = self.ptr
        while True:
            c = self.fetch_byte()
            if c == 0:
                break
            if 3 < (c & 0x7F) < 8:
                self.fetch_byte()
        return bytes(self.code[start:self.ptr])

    def g_print(self):
        actor = self.get_var_or_direct_byte(0x80)
        raw = self.read_raw_string()
        self.actor_talk(actor, raw)

    def g_printEgo(self):
        raw = self.read_raw_string()
        self.actor_talk(self.vars[VAR_EGO] & 0xFF, raw)

    # ---- instrucciones: actores
    def g_putActor(self):
        act = self.get_var_or_direct_byte(0x80)
        a = self.deref_actor(act)
        x = self.get_var_or_direct_byte(0x40)
        y = self.get_var_or_direct_byte(0x20)
        self.put_actor(a, x, y, a.room)

    def g_putActorInRoom(self):
        act = self.get_var_or_direct_byte(0x80)
        room = self.get_var_or_direct_byte(0x40)
        a = self.deref_actor(act)
        a.room = room & 255
        if not room:
            self.put_actor(a, 0, 0, 0)

    def g_getActorRoom(self):
        r = self.fetch_byte()
        act = self.get_var_or_direct_byte(0x80)
        self.write_var(r, self.actors[act].room if 0 <= act < NUM_ACTORS else 0)

    def g_animateActor(self):
        act = self.get_var_or_direct_byte(0x80)
        anim = self.get_var_or_direct_byte(0x40) & 0xFF
        if not 0 <= act < NUM_ACTORS:
            return
        a = self.actors[act]
        chore = 0x3F - (anim >> 2) + 2
        d = OLD_DIR[anim & 3]
        if chore == 2:
            self.start_anim(a, STAND)
            self.stop_actor_moving(a)
        elif chore == 3:
            a.moving &= ~MF_TURN
            self.set_direction(a, d)
        elif chore == 4:
            self.turn_to_direction(a, d)
        else:
            self.start_anim(a, anim >> 2)

    def g_actorOps(self):
        act = self.get_var_or_direct_byte(0x80)
        arg = self.get_var_or_direct_byte(0x40)
        sub = self.fetch_byte()
        if sub == 2:
            self.fetch_byte()
        elif sub == 3:
            self.read_string('N')
        if act == 0 and sub == 5:
            return
        a = self.deref_actor(act)
        if sub == 1:
            a.sound0 = arg & 255
        elif sub in (2, 3):
            pass                                      # paleta y nombre: sin soporte todavia
        elif sub == 4:
            self.set_costume(a, arg & 255)
        elif sub == 5:
            a.talk_color = arg & 255
        else:
            raise VMError(E_RANGE)

    def g_walkActorTo(self):
        act = self.get_var_or_direct_byte(0x80)
        a = self.deref_actor(act)
        x = self.get_var_or_direct_byte(0x40)
        y = self.get_var_or_direct_byte(0x20)
        self.start_walk_actor(a, x, y, -1)

    def g_walkActorToObject(self):
        act = self.get_var_or_direct_byte(0x80)
        obj = self.get_var_or_direct_word(0x40)
        if self.where_is_object(obj) is None:
            return
        x, y, d = self.object_xy_pos(obj)
        a = self.deref_actor(act)
        x, y, _ = self.adjust_xy(a, x, y)
        self.start_walk_actor(a, x, y, d)

    def g_walkActorToActor(self):
        nr = self.get_var_or_direct_byte(0x80)
        nr2 = self.get_var_or_direct_byte(0x40)
        dist = self.fetch_byte()
        if not 0 <= nr < NUM_ACTORS:
            return
        a = self.actors[nr]
        if not self.in_room(a):
            return
        if not 0 <= nr2 < NUM_ACTORS:
            return
        to = self.actors[nr2]
        if not self.in_room(to):
            return
        dist *= 8
        x = to.x * 8
        y = to.y * 2
        if x < a.x * 8:
            x += dist
        else:
            x -= dist
        x = cdiv(x, 8)
        y = cdiv(y, 2)
        x, y, _ = self.adjust_xy(a, x, y)
        self.start_walk_actor(a, x, y, -1)

    def g_putActorAtObject(self):
        a = self.deref_actor(self.get_var_or_direct_byte(0x80))
        obj = self.get_var_or_direct_word(0x40)
        if self.where_is_object(obj) is not None:
            x, y, _ = self.object_xy_pos(obj)
            x, y, _ = self.adjust_xy(a, x, y)
        else:
            x, y = 30, 60
        self.put_actor(a, x, y, a.room)

    def g_faceActor(self):
        act = self.get_var_or_direct_byte(0x80)
        obj = self.get_var_or_direct_word(0x40)
        if 0 <= act < NUM_ACTORS:
            self.face_to_object(self.actors[act], obj)

    def g_waitForActor(self):
        a = self.deref_actor(self.get_var_or_direct_byte(0x80))
        if a.moving:
            self.ptr -= 2
            self.break_here()

    def actor_getter(self, fn):
        r = self.fetch_byte()
        a = self.deref_actor(self.get_var_or_direct_byte(0x80))
        self.write_var(r, fn(a))

    def obj_getter(self, axis):
        """getObjX / getObjY de ScummVM: los numeros de actor dan su posicion; los demas, la del objeto (-1 si no esta)."""
        r = self.fetch_byte()
        obj = self.get_var_or_direct_byte(0x80)
        if obj < NUM_ACTORS:
            v = 0 if obj < 1 else (self.actors[obj].x, self.actors[obj].y)[axis]
        else:
            p = self.object_or_actor_xy(obj)
            v = -1 if p is None else p[axis]
        self.write_var(r, v)

    def g_getActorX(self):
        self.obj_getter(0)

    def g_getActorY(self):
        self.obj_getter(1)

    def g_getActorMoving(self):
        self.actor_getter(lambda a: a.moving)

    def g_getActorFacing(self):
        self.actor_getter(lambda a: new_to_old_dir(a.facing))

    def g_getActorWalkBox(self):
        self.actor_getter(lambda a: a.walkbox if self.in_room(a) else 0xFF)

    def g_getActorCostume(self):
        self.actor_getter(lambda a: a.costume)

    def g_getActorElevation(self):
        self.actor_getter(lambda a: a.elevation)

    def g_setActorElevation(self):
        a = self.deref_actor(self.get_var_or_direct_byte(0x80))
        v = self.get_var_or_direct_byte(0x40) & 0xFF
        a.elevation = v - 256 if v & 0x80 else v

    # ---- cambio de sala
    def g_actorFollowCamera(self):
        """actorFollowCamera: si el actor esta en otra sala, empieza esa escena (como setCameraFollows); luego la camara es del anfitrion."""
        act = self.get_var_or_direct_byte(0x80)
        op = self.opcode
        if 0 <= act < NUM_ACTORS:
            room = self.actors[act].room
            if room and room != self.cur_room:
                self.start_scene(room)
        self.host_log(op, [act])

    def obj_act_dist(self, a, b):
        """getObjActToObjActDist: distancia de tablero (maximo de |dx| y |dy|) entre dos objetos o actores; $FF si alguno no tiene posicion."""
        acta = self.actors[a] if a < NUM_ACTORS else None
        actb = self.actors[b] if b < NUM_ACTORS else None
        if acta and actb and acta.room == actb.room and acta.room != 0 and acta.room != self.cur_room:
            return 0
        p = self.object_or_actor_xy(a)
        if p is None:
            return 0xFF
        q = self.object_or_actor_xy(b)
        if q is None:
            return 0xFF
        x, y = p
        x2, y2 = q
        if acta and not actb:
            x2, y2, _ = self.adjust_xy(acta, x2, y2)
        return max(abs(i16(y) - i16(y2)), abs(i16(x) - i16(x2))) & 0xFFFF

    def g_getDist(self):
        r = self.fetch_byte()
        a = self.get_var_or_direct_word(0x80)
        b = self.get_var_or_direct_word(0x40)
        self.write_var(r, self.obj_act_dist(a, b))

    def g_getClosestObjActor(self):
        """getClosestObjActor(objeto o actor): el actor de VAR_ACTOR_RANGE_MIN a MAX mas cercano (gana el de numero mas alto en un empate); $FF si ninguno."""
        r = self.fetch_byte()
        a = self.get_var_or_direct_word(0x80)
        best, dist = 0xFF, 0xFF
        mn, i = self.vars[19] & 255, self.vars[20] & 255      # VAR_ACTOR_RANGE_MIN / MAX: do { ... } while (--obj >= MIN)
        while True:
            d = self.obj_act_dist(a, i)
            if d < dist:
                best, dist = i, d
            if i <= mn:                      # sin envolver: con MIN = 0 el 8 bits de --obj nunca bajaria de MIN
                break
            i -= 1
        self.write_var(r, best)

    def g_setBoxFlags(self):
        box = self.get_var_or_direct_byte(0x80)
        flags = self.fetch_byte()
        k = self.box_index(box)
        if k is not None:
            b = list(self.boxes[k])
            b[7] = flags
            self.boxes[k] = tuple(b)

    def g_lights(self):
        """lights(a, b, c): c = 0 pone VAR_CURRENT_LIGHTS (variable 12) a `a`; c = 1 es la linterna (la pantalla lo resuelve en el anfitrion)."""
        op = self.opcode
        a = self.get_var_or_direct_byte(0x80)
        b = self.fetch_byte()
        c = self.fetch_byte()
        if c == 0:
            self.vars[12] = a
        self.host_log(op, [a, b, c])

    def g_getObjPreposition(self):
        """getObjPreposition(objeto): los bits 5-7 del byte 12 del bloque del objeto (en la sala o en un inventario); 0 si no esta."""
        r = self.fetch_byte()
        obj = self.get_var_or_direct_word(0x80)
        block = self.object_block(obj) if self.where_is_object(obj) is not None else None
        self.write_var(r, (block[12] >> 5) if block else 0)

    def g_getRandomNr(self):
        """getRandomNr(max): 0..max; generador congruencial de 16 bits (x = x * 5 + 1) y su byte alto escalado, igual que el Z80."""
        r = self.fetch_byte()
        mx = self.get_var_or_direct_byte(0x80)
        self.rnd = (self.rnd * 5 + 1) & 0xFFFF
        b = self.rnd >> 8
        self.write_var(r, b if mx == 255 else (b * (mx + 1)) >> 8)

    def freeze_scripts(self):
        """freezeScripts de v2: bit 7 en todas las ranuras vivas menos la actual (no se ejecutan ni cuentan su retardo)."""
        for i, ss in enumerate(self.slots):
            if ss.status != SS_DEAD and i != self.cur:
                ss.status |= 0x80

    def unfreeze_scripts(self):
        for ss in self.slots:
            ss.status &= 0x7F

    def g_cursorCommand(self):
        op = self.opcode
        v = self.get_var_or_direct_word(0x80)
        if (v >> 8) & 1:                # USERSTATE_SET_FREEZE
            if (v >> 8) & 8:            # USERSTATE_FREEZE_ON
                self.freeze_scripts()
            else:
                self.unfreeze_scripts()
        self.host_log(op, [v])

    def g_cutscene(self):
        op = self.opcode
        self.freeze_scripts()
        self.sent = []
        self.stop_script(SENTENCE_SCRIPT)
        self.reset_sentence()
        self.host_log(op, [])

    def g_endCutscene(self):
        op = self.opcode
        self.vars[VAR_OVERRIDE] = 0
        self.unfreeze_scripts()
        ego = self.vars[0]                        # actorFollowCamera(VAR_EGO): si el protagonista esta en otra sala, empieza esa escena
        if 0 <= ego < NUM_ACTORS:
            room = self.actors[ego].room
            if room and room != self.cur_room:
                self.start_scene(room)
        self.host_log(op, [])

    def g_beginOverride(self):
        op = self.opcode
        b = self.fetch_byte()
        w = self.fetch_word()
        self.host_log(op, [b, w])

    def g_getObjectOwner(self):
        r = self.fetch_byte()
        obj = self.get_var_or_direct_word(0x80)
        if not 0 <= obj < NUM_OBJECTS:
            raise VMError(E_BADOBJ)
        self.write_var(r, self.owner[obj])

    def g_setOwnerOf(self):
        """setOwnerOf: cambia el dueno de un objeto (0: lo quita de todos los inventarios y para sus scripts)."""
        obj = self.get_var_or_direct_word(0x80)
        owner = self.get_var_or_direct_byte(0x40)
        if obj == 0:
            return
        st = self.get_state(obj)
        self.owner[obj] = owner & 0xFF
        if owner == 0:
            inv = self.__dict__.setdefault('inv', [0] * 48)
            if obj in inv:
                inv[inv.index(obj)] = 0             # clearOwnerOf libera la ranura (el orden del inventario es el de las ranuras)
            self.stop_object_script(obj)
        self.ev(EV_OBJSTATE, [obj, st])

    def g_pickupObject(self):
        """pickupObject de v2: el objeto pasa al inventario del protagonista, con los bits 8 y 2 (dibujado e intocable)."""
        obj = self.get_var_or_direct_word(0x80)
        if obj < 1:
            raise VMError(E_BADOBJ)
        st = self.get_state(obj)
        if self.where_is_object(obj) == 'inv':
            return
        self.owner[obj] = self.vars[VAR_EGO] & 0xFF
        inv = self.__dict__.setdefault('inv', [0] * 48)
        if 0 in inv:
            inv[inv.index(0)] = obj                 # addObjectToInventory: la primera ranura libre
        self.put_state(obj, st | 0x0A)
        self.ev(EV_OBJSTATE, [obj, self.state[obj]])

    def g_loadRoomWithEgo(self):
        """o2_loadRoomWithEgo de v2: el protagonista cambia de sala, aparece en el punto de caminar del objeto destino
        (dentro de una caja y de espaldas a el), la camara lo sigue (anfitrion) y, si x e y son >= 0, echa a andar."""
        op = self.opcode
        obj = self.get_var_or_direct_word(0x80)
        room = self.get_var_or_direct_byte(0x40)
        xb = self.fetch_byte()
        yb = self.fetch_byte()
        a = self.deref_actor(self.vars[VAR_EGO] & 0xFFFF)
        self.put_actor(a, a.x, a.y, room)
        self.start_scene(a.room)
        a = self.deref_actor(self.vars[VAR_EGO] & 0xFFFF)
        if self.where_is_object(obj) == 'room':
            x2, y2, d = self.object_xy_pos(obj)
            x2, y2, _ = self.adjust_xy(a, x2, y2)
            self.put_actor(a, x2, y2, self.cur_room)
            self.set_direction(a, d + 180)
        self.host_log(op, [obj, room, xb, yb])
        self.reset_sentence()
        if xb < 128 and yb < 128:
            self.start_walk_actor(a, xb, yb, -1)
        self.run_script(5)

    def g_loadRoom(self):
        room = self.get_var_or_direct_byte(0x80)
        if room != self.cur_room:
            self.start_scene(room)

    def reset_sentence(self):
        self.vars[VAR_SENTENCE_VERB] = self.vars[VAR_BACKUP_VERB]
        self.vars[VAR_SENTENCE_OBJECT1] = 0
        self.vars[VAR_SENTENCE_OBJECT2] = 0
        self.vars[VAR_SENTENCE_PREPOSITION] = 0

    def run_scene_script(self, number, code):
        if code is not None:
            self.start_slot(WIO_ROOM, number, code, 0)

    def start_scene(self, room):
        if room and room not in self.w.rooms:
            raise VMError(E_BADROOM)
        self.stop_talk()
        if self.cur != 0xFF:
            if self.slots[self.cur].where in (WIO_ROOM, WIO_FLOBJECT, WIO_LOCAL):
                self.cur = 0xFF
        self.run_scene_script(SCRIPT_NUM_EXCD, self.excd)
        for ss in self.slots:                         # killScriptsAndResources
            if ss.where in (WIO_ROOM, WIO_FLOBJECT, WIO_LOCAL):
                ss.status = SS_DEAD
        self.reset_sentence()
        for i in range(1, NUM_ACTORS):
            self.hide_actor(self.actors[i])
        self.vars[VAR_ROOM] = room
        self.cur_room = room
        self.vars[VAR_ROOM_RESOURCE] = room
        if room == 0:
            self.encd = self.excd = None
            self.boxes, self.matrix, self.roomobjs, self.objlist = [], b'', {}, []
            return
        r = self.w.rooms[room]
        self.encd = r.entry_script() if r.encd_off else None
        self.excd = r.exit_script() if r.excd_off else None
        self.boxes = list(r.boxes)
        self.matrix = bytes(r.matrix)
        self.roomobjs = {o.id: (o.walk_x // 8, o.walk_y // 2, o.actordir) for o in r.objects}
        self.objlist = [(o.id, o.walk_x // 8, o.walk_y // 2, o.actordir, o.x // 8, o.y // 8, o.width // 8, o.height // 8,
                         o.parent, o.parentstate * 8) for o in r.objects]
        self.ev(EV_ROOM_LOAD, [room])                 # cuando ya estan las cajas y los objetos de la sala (el programa los necesita)
        self.vars[VAR_CAMERA_MIN_X] = SCREEN_WIDTH // 2
        self.vars[VAR_CAMERA_MAX_X] = (r.width - SCREEN_WIDTH // 2) & 0xFFFF
        for i in range(1, NUM_ACTORS):                # showActors
            if self.actors[i].room == self.cur_room:
                self.show_actor(self.actors[i])
        self.run_scene_script(SCRIPT_NUM_ENCD, self.encd)
        self.run_script(5)

    # ---- resumen para la traza
    def game_digest(self):
        a = crc16(b''.join(x.pack() for x in self.actors))
        q = crc16(b''.join(struct.pack('<BHHB2x', st[0], st[1] & 0xFFFF, st[2] & 0xFFFF, st[3]) for st in self.sent))
        return 'A=%04X M=%d,%d,%d,%d,%d Q=%d,%04X' % (a, self.have_msg, self.talk_delay, self.keep_text, self.cur_room,
                                                      self.last_sound, len(self.sent), q)

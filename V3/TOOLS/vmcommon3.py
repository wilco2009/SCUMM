"""Constantes y utilidades comunes del modelo de referencia v3 (vmmodel3.py, vmgame3.py) y del arnes del Z80.

Es el equivalente de SCUMM/V2/TOOLS/vmcommon.py, con los numeros de ScummEngine::setupScummVars de v3 (Indy3 EGA,
ScummEngine_v3old) y las magnitudes de ScummEngine::readMAXS para "old bundle". Las funciones crc16, mock_hash y
str_value son las mismas que las de v2: el arnes de C++ las repite igual.
"""
import binascii

# --- magnitudes (ScummVM: resource.cpp readMAXS de v3old)
# Limites del Z80 (fase 3, V3/FASE3.md): el modelo usa los mismos para que las trazas sean comparables. Indy3 cabe con holgura.
NUM_VARS = 256               # ScummVM: 800 (readMAXS); Indy3 usa hasta la 253. Fuera de 0-255: E_RANGE
NUM_LOCAL = 16               # ScummVM: 25 y readVar/writeVar dejan 0..20; Indy3 usa hasta la 15 y listas de 7. Fuera de 0-15: E_RANGE
NUM_SLOT = 24                # ScummVM: 80; el maximo medido en Indy3 es 17 (arranque y escenarios). Sin ranura libre: E_NOSLOT
MAX_ARGS = 32                # argumentos de una instruccion que va al anfitrion (modo nucleo); el maximo de Indy3 es 22
MAX_ESTACK = 32              # pila de expression (ScummVM: 150)
MAX_NEST = 15                # kMaxScriptNesting
MAX_CUTSCENE = 5             # kMaxCutsceneNum
NUM_ACTORS = 13
NUM_SENTENCE = 6
NUM_INVENTORY = 80
NUM_OBJECTS = 1000           # objetos globales de Indy3 (DATA.BIN: NOBJ)
NUM_VERBS = 52               # ranuras de verbo, la 0 incluida (ScummVM: 100): el arranque de Indy3 llega a 30 vivos. Sin ranura libre: E_RANGE
NUM_STRINGS = 40             # ids de cadena 0..31 (ScummVM: 100; Indy3 usa hasta la 24). Fuera de rango: E_RANGE
STR_HEAP = 1248              # bytes del monton de cadenas (incluido el 0 final de cada una); Indy3 llega a 355 en el arranque y a ~1.155 con el dialogo de guardar y cargar (fase 9). Desbordado: E_RANGE
MAX_STRLEN = 255             # longitud maxima de una cadena (con su 0 final)
MSG_MAX = 320                # bufer de texto del mensaje (MSGBUF): el mensaje convertido y su 0 final caben en 320 bytes; mas: E_RANGE (ScummVM: 2048)
MSG_DEPTH = 4                # niveles de anidamiento de un mensaje (verbo, nombre o cadena dentro de otro): mas: E_RANGE
NUM_NEW_NAMES = 50           # ScummEngine_v4::readMAXS (v3old la hereda); v5 sube a 150
NUM_LOCAL_OBJECTS = 200
NUM_GLOBAL_SCRIPTS = 200     # los scripts locales de sala llevan numero >= 200
SCREEN_WIDTH = 320
MAX_INSN = 200000

# --- WhereIsObject / estados de ranura
WIO_NOT_FOUND, WIO_INVENTORY, WIO_ROOM, WIO_GLOBAL, WIO_LOCAL, WIO_FLOBJECT = -1, 0, 1, 2, 3, 4
SS_DEAD, SS_PAUSED, SS_RUNNING = 0, 1, 2
OWNER_ROOM = 0x0F
SCRIPT_NUM_EXCD, SCRIPT_NUM_ENCD = 10001, 10002          # kScriptNumEXCD / kScriptNumENCD

# --- variables (ScummEngine::setupScummVars + ScummEngine_v5::setupScummVars, version 3)
VAR_KEYPRESS, VAR_EGO, VAR_CAMERA_POS_X, VAR_HAVE_MSG, VAR_ROOM, VAR_OVERRIDE = 0, 1, 2, 3, 4, 5
VAR_MACHINE_SPEED, VAR_ME, VAR_NUM_ACTOR, VAR_CURRENT_LIGHTS = 6, 7, 8, 9
VAR_TMR_1, VAR_TMR_2, VAR_TMR_3, VAR_MUSIC_TIMER = 11, 12, 13, 14
VAR_ACTOR_RANGE_MIN, VAR_ACTOR_RANGE_MAX, VAR_CAMERA_MIN_X, VAR_CAMERA_MAX_X = 15, 16, 17, 18
VAR_TIMER_NEXT, VAR_VIRT_MOUSE_X, VAR_VIRT_MOUSE_Y, VAR_ROOM_RESOURCE, VAR_LAST_SOUND = 19, 20, 21, 22, 23
VAR_CUTSCENEEXIT_KEY, VAR_TALK_ACTOR, VAR_CAMERA_FAST_X = 24, 25, 26
VAR_ENTRY_SCRIPT, VAR_ENTRY_SCRIPT2, VAR_EXIT_SCRIPT, VAR_EXIT_SCRIPT2 = 28, 29, 30, 31
VAR_VERB_SCRIPT, VAR_SENTENCE_SCRIPT, VAR_INVENTORY_SCRIPT = 32, 33, 34
VAR_CUTSCENE_START_SCRIPT, VAR_CUTSCENE_END_SCRIPT, VAR_CHARINC, VAR_WALKTO_OBJ = 35, 36, 37, 38
VAR_HEAPSPACE, VAR_RESTART_KEY, VAR_PAUSE_KEY = 40, 42, 43
VAR_MOUSE_X, VAR_MOUSE_Y, VAR_TIMER, VAR_TIMER_TOTAL, VAR_SOUNDCARD, VAR_VIDEOMODE = 44, 45, 46, 47, 48, 49
VARS_INDY3_TIMERS = (39, 40, 41)          # Indy3 PC: tres temporizadores mas (scummLoop)

# --- clases de objeto (ScummVM: kObjectClass*) y su traduccion en GF_SMALL_HEADER
CLASS_NEVER_CLIP, CLASS_ALWAYS_CLIP, CLASS_IGNORE_BOXES = 20, 21, 22
CLASS_YFLIP, CLASS_XFLIP, CLASS_PLAYER, CLASS_UNTOUCHABLE = 29, 30, 31, 32
CLASS_SMALL_HEADER = {CLASS_UNTOUCHABLE: 24, CLASS_PLAYER: 23, CLASS_XFLIP: 19, CLASS_YFLIP: 18}

# --- Actor::_moving y BoxFlags
MF_NEW_LEG, MF_IN_LEG, MF_TURN, MF_LAST_LEG = 1, 2, 4, 8
BOX_XFLIP, BOX_YFLIP, BOX_PLAYER_ONLY, BOX_LOCKED, BOX_INVISIBLE = 0x08, 0x10, 0x20, 0x40, 0x80
INVALID_BOX = 0xFF

# --- zonas de clic (ClickArea)
CLICK_VERB, CLICK_SCENE, CLICK_INVENTORY, CLICK_KEY = 1, 2, 3, 4

# --- errores (codigos que compara el arnes). Son los "error()" de ScummVM
E_NOSLOT, E_NEST, E_RANGE, E_NOSCRIPT, E_BADOBJ, E_BADROOM, E_BADACTOR, E_BADOP, E_BUDGET = 1, 2, 3, 4, 5, 6, 7, 8, 9
E_CUTSCENE = 10        # pila de escenas cortadas desbordada o vacia
E_BADSUB = 11          # subopcode desconocido (error("o5_xxx: unknown subopcode"))
E_HALT = 12            # systemOps de reinicio o salida (solo en modo nucleo: el Z80 vuelve con este error)

# --- sucesos para el "back-end" (video, sonido, disco): puerto $F2 en el Z80. Los 1-8 son los de v2.
EV_SOUND_START, EV_SOUND_STOP, EV_SOUND_STOPALL, EV_SOUND_QUERY, EV_TEXT, EV_ROOM_LOAD, EV_SENTENCE, EV_OBJSTATE = 1, 2, 3, 4, 5, 6, 7, 8
EV_DRAWOBJ, EV_CAMERA, EV_VERB, EV_ACTOR = 9, 10, 11, 12
EV_PALETTE = 13          # fase 8: cambia _roomPalette o _shadowPalette (roomOps 2 y 4); sin operandos
EV_ARGC = {EV_SOUND_START: 1, EV_SOUND_STOP: 1, EV_SOUND_STOPALL: 0, EV_SOUND_QUERY: 1, EV_TEXT: 3, EV_ROOM_LOAD: 1,
           EV_SENTENCE: 3, EV_OBJSTATE: 2, EV_DRAWOBJ: 4, EV_CAMERA: 1, EV_VERB: 2, EV_ACTOR: 3, EV_PALETTE: 0}


class VMError(Exception):
    def __init__(self, code, msg=''):
        Exception.__init__(self, 'ERR %d %s' % (code, msg))
        self.code = code


class Halt(Exception):
    """systemOps de reinicio o salida: el modelo para."""


def crc16(data, crc=0xFFFF):
    """CRC-16/CCITT (polinomio 0x1021, sin reflejar, sin xor final): el arnes de C++ usa el mismo."""
    return binascii.crc_hqx(bytes(data), crc)


def mock_hash(op, args, frame):
    """Resultado simulado del anfitrion: el arnes de C++ hace exactamente lo mismo."""
    s = (op * 131 + frame * 17) & 0xFFFF
    for i, a in enumerate(args):
        s = (s * 31 + (a & 0xFFFF) + i + 1) & 0xFFFF
    return s


def str_value(data):
    """Valor de una cadena como argumento: suma de bytes + longitud*257, 16 bits."""
    return (sum(data) + len(data) * 257) & 0xFFFF


def s16(v):
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
    """newDirToOldDir (util.cpp): angulo -> 0 izquierda, 1 derecha, 2 abajo, 3 arriba."""
    if 71 <= d <= 109:
        return 1
    if 109 <= d <= 251:
        return 2
    if 251 <= d <= 289:
        return 0
    return 3


OLD_DIR = (270, 90, 180, 0)          # oldDirToNewDir


def old_to_new_dir(d):
    return OLD_DIR[d]

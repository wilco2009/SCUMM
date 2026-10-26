"""Constantes y utilidades comunes del modelo de referencia (vmmodel.py, vmgame.py) y del arnes del Z80."""
import binascii

# --- constantes (de ScummVM)
WIO_INVENTORY, WIO_ROOM, WIO_GLOBAL, WIO_LOCAL, WIO_FLOBJECT = 0, 1, 2, 3, 4
SS_DEAD, SS_PAUSED, SS_RUNNING = 0, 1, 2
NUM_SLOT = 24                # el Z80 usa 24 (ScummVM 80); se mide cuantas hacen falta
MAX_NEST = 15
NUM_VARS = 256
NUM_OBJECTS = 780
NUM_ACTORS = 25              # Maniac Mansion
SCRIPT_NUM_EXCD, SCRIPT_NUM_ENCD = 10001, 10002
MAX_INSN = 200000

# variables de v2 (ScummEngine_v2::setupScummVars)
VAR_EGO, VAR_CAMERA_POS_X, VAR_HAVE_MSG, VAR_ROOM, VAR_OVERRIDE = 0, 2, 3, 4, 5
VAR_CHARCOUNT, VAR_MUSIC_TIMER = 7, 17
VAR_CAMERA_MIN_X, VAR_CAMERA_MAX_X = 23, 24
VAR_SENTENCE_VERB, VAR_SENTENCE_OBJECT1, VAR_SENTENCE_OBJECT2, VAR_SENTENCE_PREPOSITION = 26, 27, 28, 29
VAR_ROOM_RESOURCE, VAR_LAST_SOUND, VAR_BACKUP_VERB = 36, 37, 38
VAR_CUTSCENEEXIT_KEY, VAR_TALK_ACTOR = 40, 41
VAR_ACTIVE_VERB, VAR_ACTIVE_OBJECT1, VAR_ACTIVE_OBJECT2, VAR_VERB_ALLOWED = 8, 9, 10, 18
VAR_VIRT_MOUSE_X, VAR_VIRT_MOUSE_Y, VAR_CLICK_AREA, VAR_CLICK_VERB, VAR_CLICK_OBJECT, VAR_KEYPRESS = 30, 31, 32, 33, 35, 39
NUM_SENTENCE = 6
SENTENCE_SCRIPT, INPUT_SCRIPT = 2, 4
CLICK_VERB, CLICK_SCENE, CLICK_INVENTORY, CLICK_KEY, CLICK_SENTENCE = 1, 2, 3, 4, 5

# errores (codigos que compara el arnes)
E_NOSLOT, E_NEST, E_RANGE, E_NOSCRIPT, E_BADOBJ, E_BADROOM, E_BUDGET = 1, 2, 3, 4, 5, 6, 9

# sucesos para el "back-end" (video, sonido, disco): puerto $F2 en el Z80
EV_SOUND_START, EV_SOUND_STOP, EV_SOUND_STOPALL, EV_SOUND_QUERY, EV_TEXT, EV_ROOM_LOAD, EV_SENTENCE, EV_OBJSTATE = 1, 2, 3, 4, 5, 6, 7, 8
EV_ARGC = {EV_SOUND_START: 1, EV_SOUND_STOP: 1, EV_SOUND_STOPALL: 0, EV_SOUND_QUERY: 1, EV_TEXT: 3, EV_ROOM_LOAD: 1, EV_SENTENCE: 3, EV_OBJSTATE: 2}


class VMError(Exception):
    def __init__(self, code):
        Exception.__init__(self, 'ERR %d' % code)
        self.code = code


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

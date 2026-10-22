#!/usr/bin/env python3
"""Parser de recursos de SCUMM v2 (ficheros .LFL de DOS, "Enhanced V2": Maniac Mansion, Zak McKracken).

Lee el indice (00.LFL) y las salas (NN.LFL) y saca scripts, objetos, cajas, sonidos y trajes.
Formatos tomados de ScummVM (engines/scumm: resource.cpp, resource_v2.cpp, resource_v3.cpp, room.cpp,
object.cpp, script.cpp). Cada fichero esta cifrado con XOR 0xFF.

Uso:
  scumm2.py DIR index                 resumen del indice
  scumm2.py DIR room N                resumen de la sala N (cabecera, objetos, scripts, cajas)
  scumm2.py DIR extract SALIDA        escribe todos los scripts (globales, de sala y de objeto) en SALIDA
  scumm2.py DIR check                 comprueba la coherencia de todos los recursos
  scumm2.py DIR dump SALIDA [DESCUMM] volcado de texto de cada sala (y, si se da la ruta de descumm,
                                      con el listado de cada script); compara los verbos con descumm
"""
import os
import struct
import sys


def u16(b, o):
    return struct.unpack_from('<H', b, o)[0]


def load(path):
    with open(path, 'rb') as f:
        return bytes(x ^ 0xFF for x in f.read())


class Index:
    """00.LFL. Tablas de objetos globales y directorios de recursos (sala/fichero, offset)."""

    TYPES = ('room', 'costume', 'script', 'sound')

    def __init__(self, directory):
        self.dir = directory
        b = load(os.path.join(directory, '00.LFL'))
        self.raw = b
        magic = u16(b, 0)
        if magic != 0x0100:
            raise ValueError('no es un indice de v2 "enhanced" (magia %04X)' % magic)
        p = 2
        self.num_objects = u16(b, p)
        p += 2
        self.obj_owner_state = list(b[p:p + self.num_objects])     # bits 0-3 dueño, 4-7 estado
        p += self.num_objects
        self.res = {}
        for t in self.TYPES:
            n = b[p]
            p += 1
            if t == 'room':
                files = list(range(n))
                p += n                                              # numero de disco, sin uso
            else:
                files = list(b[p:p + n])
                p += n
            offs = [u16(b, p + 2 * i) for i in range(n)]
            p += 2 * n
            self.res[t] = [(f, None if o == 0xFFFF else o) for f, o in zip(files, offs)]
        self.end = p

    def owner(self, obj):
        return self.obj_owner_state[obj] & 0x0F

    def state(self, obj):
        return self.obj_owner_state[obj] >> 4


class Obj:
    """Un objeto de sala: bloque OBCD (codigo y verbos) y offset de la imagen (OBIM)."""
    pass


class Room:
    """Recurso de sala (primer recurso de NN.LFL)."""

    def __init__(self, directory, num):
        self.num = num
        self.file = load(os.path.join(directory, '%02d.LFL' % num))
        b = self.file
        self.size = u16(b, 0)
        self.width, self.height = u16(b, 4), u16(b, 6)
        self.image_off = u16(b, 0x0A)
        self.num_objects = b[0x14]
        self.box_off = b[0x15]
        self.num_sounds = b[0x16]
        self.num_scripts = b[0x17]
        self.excd_off = u16(b, 0x18)
        self.encd_off = u16(b, 0x1A)
        self.header = b[:0x1C]
        p = 0x1C
        self.obim_offs = [u16(b, p + 2 * i) for i in range(self.num_objects)]
        p += 2 * self.num_objects
        self.obcd_offs = [u16(b, p + 2 * i) for i in range(self.num_objects)]
        p += 2 * self.num_objects
        self.sound_ids = list(b[p:p + self.num_sounds])
        p += self.num_sounds
        self.script_ids = list(b[p:p + self.num_scripts])
        p += self.num_scripts
        self.tables_end = p
        self.matrix = b''
        self.boxes_end = self.box_off
        self.boxes = self._boxes()
        self.objects = [self._object(i) for i in range(self.num_objects)]

    def _object(self, i):
        b = self.file
        o = Obj()
        o.index = i
        o.obim = self.obim_offs[i]
        o.obcd = self.obcd_offs[i]
        c = o.obcd
        o.size = u16(b, c)
        o.id = u16(b, c + 4)
        o.x = b[c + 7] * 8
        o.y = (b[c + 8] & 0x7F) * 8
        o.parentstate = (b[c + 8] >> 7) & 1
        o.width = b[c + 9] * 8
        o.parent = b[c + 10]
        o.walk_x = b[c + 11] * 8
        o.walk_y = (b[c + 12] & 0x1F) * 8
        o.preposition = b[c + 12] >> 5
        o.actordir = b[c + 13] & 7
        o.height = b[c + 13] & 0xF8
        o.name_off = b[c + 14]
        # tabla de verbos: pares (verbo, offset relativo al OBCD) terminada en 0
        p = c + 15
        o.verbs = []
        while b[p] != 0:
            o.verbs.append((b[p], b[p + 1]))
            p += 2
        o.verbs_end = p + 1
        s = c + o.name_off
        e = b.index(0, s)
        o.name = bytes(b[s:e]).decode('latin1')
        o.block = b[c:c + o.size]
        return o

    def _boxes(self):
        b = self.file
        if self.box_off == 0:
            return []
        p = self.box_off
        n = b[p]
        # SIZEOF_BOX_V2 = 8: uy, ly, ulx, urx, llx, lrx, mask, flags (ScummVM boxes.cpp);
        # le sigue la matriz de rutas, n*(n+1) bytes
        boxes = [tuple(b[p + 1 + 8 * k:p + 9 + 8 * k]) for k in range(n)]
        self.matrix = b[p + 1 + 8 * n:p + 1 + 8 * n + n * (n + 1)]
        self.boxes_end = p + 1 + 8 * n + n * (n + 1)
        return boxes

    def entry_script(self):
        """Codigo de entrada (ENCD): desde encd_off hasta el final del recurso de sala."""
        return self.file[self.encd_off:self.size] if self.encd_off else b''

    def exit_script(self):
        """Codigo de salida (EXCD): desde excd_off hasta encd_off."""
        return self.file[self.excd_off:self.encd_off] if self.excd_off else b''


def resource(directory, index, kind, idx):
    """Devuelve los bytes completos (con cabecera de 4 bytes) de un recurso de costume/script/sound."""
    f, off = index.res[kind][idx]
    if off is None:
        return None
    b = load(os.path.join(directory, '%02d.LFL' % f))
    size = u16(b, off)
    return b[off:off + size]


def extract(d, ix, out):
    """Escribe los recursos en ficheros: scripts con la cabecera que espera descumm -2."""
    os.makedirs(out, exist_ok=True)
    n = 0

    def w(name, data):
        nonlocal n
        with open(os.path.join(out, name), 'wb') as f:
            f.write(data)
        n += 1
    for kind in ('script', 'sound', 'costume'):
        for i in range(len(ix.res[kind])):
            if resource_ok(d, ix, kind, i):
                w('%s-%03d.bin' % (kind, i), resource(d, ix, kind, i))
    for rn in range(len(ix.res['room'])):
        if not os.path.exists(os.path.join(d, '%02d.LFL' % rn)):
            continue
        r = Room(d, rn)
        w('room-%02d-header.bin' % rn, r.file[:r.size])
        if r.encd_off:
            w('room-%02d-entry.bin' % rn, b'\x00\x00\x00\x00' + r.entry_script())
        if r.excd_off:
            w('room-%02d-exit.bin' % rn, b'\x00\x00\x00\x00' + r.exit_script())
        for o in r.objects:
            w('room-%02d-obj-%04d.bin' % (rn, o.id), o.block)
    return n


def resource_ok(d, ix, kind, i):
    """True si la entrada del indice apunta a un recurso que cabe en su fichero.

    El indice trae entradas sobrantes con basura (por ejemplo salas 54-60 con offsets que son texto
    ASCII); ScummVM las lee igual y nunca las usa.
    """
    f, off = ix.res[kind][i]
    path = os.path.join(d, '%02d.LFL' % f)
    if off is None or not os.path.exists(path):
        return False
    b = load(path)
    return off + 4 <= len(b) and u16(b, off) >= 4 and off + u16(b, off) <= len(b)


def check(d, ix):
    """Coherencia del indice y de las salas."""
    bad = 0
    for kind in ('costume', 'script', 'sound'):
        unused = [i for i in range(len(ix.res[kind])) if not resource_ok(d, ix, kind, i)]
        print('%-8s %3d entradas, %3d sin recurso (sobrantes): %s' % (
            kind, len(ix.res[kind]), len(unused), unused))
    rooms = [rn for rn in range(len(ix.res['room'])) if os.path.exists(os.path.join(d, '%02d.LFL' % rn))]
    print('salas con fichero: %d de %d entradas' % (len(rooms), len(ix.res['room'])))
    for rn in rooms:
        r = Room(d, rn)
        if r.size > len(r.file):
            print('sala %d: size %d > fichero %d' % (rn, r.size, len(r.file)))
            bad += 1
        # cada script/sonido que la sala dice cargar tiene que existir (puede estar en otro fichero)
        for kind, ids in (('script', r.script_ids), ('sound', r.sound_ids)):
            for i in ids:
                if i >= len(ix.res[kind]) or not resource_ok(d, ix, kind, i):
                    print('sala %d: %s %d no existe (indice: %s)' % (
                        rn, kind, i, ix.res[kind][i] if i < len(ix.res[kind]) else '?'))
                    bad += 1
                elif ix.res[kind][i][0] != rn:
                    print('  nota: sala %d carga %s %d que esta en %02d.LFL' % (rn, kind, i, ix.res[kind][i][0]))
        blocks = sorted((o.obcd, o.obcd + o.size, 'OBCD obj %d' % o.id) for o in r.objects)
        if r.excd_off:
            blocks.append((r.excd_off, r.encd_off, 'EXCD'))
        if r.encd_off:
            blocks.append((r.encd_off, r.size, 'ENCD'))
        blocks.sort()
        for a, b2 in zip(blocks, blocks[1:]):
            if a[1] != b2[0]:
                print('sala %d: hueco o solape entre %s [%d,%d) y %s [%d,%d)' % (
                    rn, a[2], a[0], a[1], b2[2], b2[0], b2[1]))
                bad += 1
        if blocks and blocks[-1][1] != r.size:
            print('sala %d: el ultimo bloque acaba en %d y el recurso en %d' % (rn, blocks[-1][1], r.size))
            bad += 1
        for o in r.objects:
            for v, off in o.verbs:
                if off >= o.size:
                    print('sala %d obj %d: verbo %02X con offset %d fuera del bloque (%d)' % (rn, o.id, v, off, o.size))
                    bad += 1
    print('comprobacion terminada: %d problemas' % bad)
    return bad


def room_text(r):
    """Volcado de una sala en texto, con las mismas cifras que imprime descumm (offsets en hexadecimal)."""
    L = ['ROOM %d  %dx%d  size=%d  image@%04X  boxes@%02X  ENCD@%04X  EXCD@%04X' % (
        r.num, r.width, r.height, r.size, r.image_off, r.box_off, r.encd_off, r.excd_off),
        'sounds: %s' % r.sound_ids, 'scripts: %s' % r.script_ids, '']
    for o in r.objects:
        L.append('OBJECT %d "%s"  pos=%d,%d size=%dx%d  parent=%d state-bit=%d  walk=%d,%d dir=%d prep=%d  '
                 'OBIM@%04X OBCD@%04X size=%d' % (
                     o.id, o.name, o.x, o.y, o.width, o.height, o.parent, o.parentstate, o.walk_x, o.walk_y,
                     o.actordir, o.preposition, o.obim, o.obcd, o.size))
        L.append('Events:')
        for v, off in o.verbs:
            L.append('  %2X - %.4X' % (v, off))
    L.append('')
    L.append('BOXES (uy, ly, ulx, urx, llx, lrx, mask, flags):')
    for k, bx in enumerate(r.boxes):
        L.append('  %2d  %s' % (k, ' '.join('%3d' % v for v in bx)))
    return '\n'.join(L) + '\n'


def dump(d, ix, out, descumm=None):
    """Escribe sala-RR.txt y, con descumm, los listados de cada script; devuelve las diferencias de verbos."""
    import re
    import subprocess
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, 'tmp.bin')
    diffs = 0
    compared = 0
    pad = bytes(4)
    verb_re = re.compile(r'^\s+([0-9A-F]+) - ([0-9A-F]{4})$', re.M)

    def run(data):
        with open(tmp, 'wb') as f:
            f.write(data)
        res = subprocess.run([descumm, '-2', tmp], capture_output=True, text=True)
        return res.stdout + ('' if res.returncode == 0 else '\n; descumm: ' + res.stderr.strip() + '\n')
    for rn in range(len(ix.res['room'])):
        if not os.path.exists(os.path.join(d, '%02d.LFL' % rn)):
            continue
        r = Room(d, rn)
        text = room_text(r)
        if descumm:
            parts = []
            if r.encd_off:
                parts.append('== ENTRY script\n' + run(pad + r.entry_script()))
            if r.excd_off:
                parts.append('== EXIT script\n' + run(pad + r.exit_script()))
            for o in r.objects:
                txt = run(o.block)
                parts.append('== OBJECT %d "%s"\n%s' % (o.id, o.name, txt))
                theirs = [(int(a, 16), int(b, 16)) for a, b in verb_re.findall(txt)]
                compared += 1
                if theirs != o.verbs:
                    diffs += 1
                    print('sala %d obj %d: verbos distintos: mio %s, descumm %s' % (rn, o.id, o.verbs, theirs))
            text += '\n' + '\n'.join(parts)
        with open(os.path.join(out, 'sala-%02d.txt' % rn), 'w', encoding='utf-8') as f:
            f.write(text)
    if descumm:
        for i in range(len(ix.res['script'])):
            if resource_ok(d, ix, 'script', i):
                with open(os.path.join(out, 'script-%03d.txt' % i), 'w', encoding='utf-8') as f:
                    f.write(run(resource(d, ix, 'script', i)))
    if os.path.exists(tmp):
        os.remove(tmp)
    print('objetos comparados con descumm: %d, diferencias: %d' % (compared, diffs))
    return diffs


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    d, cmd = sys.argv[1], sys.argv[2]
    ix = Index(d)
    if cmd == 'index':
        print('objetos globales: %d' % ix.num_objects)
        for t in ix.TYPES:
            valid = [i for i, (f, o) in enumerate(ix.res[t]) if o is not None]
            print('%-8s %3d entradas, %3d validas' % (t, len(ix.res[t]), len(valid)))
        print('fin del indice en +%d de %d bytes' % (ix.end, len(ix.raw)))
    elif cmd == 'room':
        r = Room(d, int(sys.argv[3]))
        print('sala %d: %dx%d, imagen en +%04X, %d objetos, cajas en +%02X, ENCD +%04X EXCD +%04X' % (
            r.num, r.width, r.height, r.image_off, r.num_objects, r.box_off, r.encd_off, r.excd_off))
        print('sonidos:', r.sound_ids, 'scripts:', r.script_ids)
        for o in r.objects:
            print('  obj %4d "%s" %d,%d %dx%d walk %d,%d dir %d verbos %s' % (
                o.id, o.name, o.x, o.y, o.width, o.height, o.walk_x, o.walk_y, o.actordir,
                ' '.join('%02X:%02X' % v for v in o.verbs)))
        print('cajas (uy, ly, ulx, urx, llx, lrx, mask, flags):')
        for k, bx in enumerate(r.boxes):
            print('  %2d' % k, bx)
    elif cmd == 'extract':
        print('%d ficheros en %s' % (extract(d, ix, sys.argv[3]), sys.argv[3]))
    elif cmd == 'dump':
        return 1 if dump(d, ix, sys.argv[3], sys.argv[4] if len(sys.argv) > 4 else None) else 0
    elif cmd == 'check':
        return 1 if check(d, ix) else 0
    else:
        print('orden desconocida', cmd)
        return 1


if __name__ == '__main__':
    sys.exit(main())

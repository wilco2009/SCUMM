#!/usr/bin/env python3
"""Lector de recursos de SCUMM v3 "old bundle" (Indiana Jones and the Last Crusade y Loom en EGA, DOS).

Es la clase ScummEngine_v3old de ScummVM (engines/scumm): resource_v3.cpp (indice), room.cpp
(ScummEngine_v3old::setupRoomSubBlocks y resetRoomSubBlocks), object.cpp (ScummEngine_v3old::resetRoomObjects,
ScummEngine_v4::resetRoomObject), script.cpp (getVerbEntrypoint), gfx.cpp (drawStrip, drawStripEGA,
decompressMaskImg, getZPlanes) y boxes.cpp (SIZEOF_BOX_V3). Los ficheros van cifrados con XOR 0xFF, como en v2.

Diferencias con v2 (SCUMM/V2/TOOLS/scumm2.py), todas de ScummVM:
  indice     4 bytes por objeto global (24 bits de clases + dueño/estado) en vez de 1
  sala       cabecera de 29 bytes (no 28): cajas en u16 (+0x15), sonidos +0x17, scripts +0x18, EXCD +0x19, ENCD +0x1B;
             tras los ids de sonidos y scripts, la lista de scripts LOCALES (id >= 200, u16 offset) acabada en 0
  objeto     OBCD: id +4, x +7, y +8, ancho +9, padre +10, walk_x u16 +11, walk_y u16 +13, dir/alto +15, nombre +16,
             verbos desde +17 en triples (verbo, u16 offset)
  cajas      18 bytes (4 esquinas en s16, mascara, flags) y la matriz hasta la imagen
  imagen     franjas de 8 px (u16 longitud, u16 offset por franja) con el RLE de drawStripEGA; la mascara
             (zplane 1) empieza en smap + u16(smap), una franja por offset u16 y el RLE de decompressMaskImg
  trajes     el mismo formato 0x58 que v2 (ClassicCostumeLoader con GF_OLD_BUNDLE)

Uso:
  scumm3res.py DIR index           resumen del indice
  scumm3res.py DIR room N          cabecera, objetos, scripts locales y bloques de la sala N
  scumm3res.py DIR check           decodifica todas las salas (imagen, mascara, objetos) y comprueba los bloques
"""
import os
import struct
import sys


def u16(b, o):
    return b[o] | (b[o + 1] << 8)


def s16(b, o):
    v = u16(b, o)
    return v - 0x10000 if v & 0x8000 else v


def load(path):
    with open(path, 'rb') as f:
        return bytes(x ^ 0xFF for x in f.read())


NUM_GLOBAL_SCRIPTS = 200          # ScummEngine_v4::readMAXS: _numGlobalScripts


class Index:
    """00.LFL de v3old (ScummEngine_v3old::readIndexFile y ScummEngine_v4::readGlobalObjects)."""

    TYPES = ('room', 'costume', 'script', 'sound')

    def __init__(self, directory):
        self.dir = directory
        b = load(os.path.join(directory, '00.LFL'))
        self.raw = b
        if u16(b, 0) != 0x0100:
            raise ValueError('magia %04X: no es un indice v3old' % u16(b, 0))
        n = u16(b, 2)
        self.num_objects = n
        p = 4
        self.classes, self.owner, self.state = [], [], []
        for i in range(n):
            self.classes.append(b[p] | (b[p + 1] << 8) | (b[p + 2] << 16))
            self.owner.append(b[p + 3] & 0x0F)
            self.state.append(b[p + 3] >> 4)
            p += 4
        self.res = {}
        for t in self.TYPES:
            k = b[p]
            p += 1
            if t == 'room':
                files = list(range(k))
                p += k
            else:
                files = list(b[p:p + k])
                p += k
            offs = [u16(b, p + 2 * i) for i in range(k)]
            p += 2 * k
            self.res[t] = [(f, None if o == 0xFFFF else o) for f, o in zip(files, offs)]
        self.end = p
        self._files = {}

    def file(self, num):
        if num not in self._files:
            path = os.path.join(self.dir, '%02d.LFL' % num)
            self._files[num] = load(path) if os.path.exists(path) else None
        return self._files[num]

    def resource(self, kind, i):
        """Bytes del recurso con su cabecera de 4 bytes (u16 tamaño, 2 bytes), o None si no existe."""
        if i >= len(self.res[kind]):
            return None
        f, off = self.res[kind][i]
        if off is None:
            return None
        b = self.file(f)
        if b is None or off + 4 > len(b):
            return None
        size = u16(b, off)
        if size < 4 or off + size > len(b):
            return None
        return b[off:off + size]

    def rooms(self):
        # 97-99.LFL son los juegos de caracteres (ScummEngine_v3::loadCharset abre 99 - n), no salas
        return [r for r in range(len(self.res['room'])) if r < 97 and self.file(r) is not None]


class Obj:
    pass


def decode_strips(b, smap, nstrips, height):
    """Imagen de 16 colores: devuelve img[y][x] (indices EGA) y el tamaño en bytes del bloque de franjas."""
    w = nstrips * 8
    img = [[0] * w for _ in range(height)]
    smap_len = u16(b, smap)
    for s in range(nstrips):
        if s * 2 + 2 >= smap_len:
            break
        src = smap + u16(b, smap + s * 2 + 2)
        x = y = 0
        x0 = s * 8

        def put(c):
            nonlocal x, y
            img[y][x0 + x] = c
            y += 1
            if y >= height:
                y = 0
                x += 1
        while x < 8:
            c = b[src]
            src += 1
            if c & 0x80:
                run = c & 0x3F
                if c & 0x40:
                    col = b[src]
                    src += 1
                    if run == 0:
                        run = b[src]
                        src += 1
                    for z in range(run):
                        if x >= 8:
                            break
                        put((col & 0x0F) if (z & 1) else (col >> 4))
                else:
                    if run == 0:
                        run = b[src]
                        src += 1
                    for z in range(run):
                        if x >= 8:
                            break
                        put(img[y][x0 + x - 1] if x0 + x > 0 else 0)
            else:
                run = c >> 4
                if run == 0:
                    run = b[src]
                    src += 1
                for z in range(run):
                    if x >= 8:
                        break
                    put(c & 0x0F)
    return img, smap_len


def decode_mask(b, zp, nstrips, height):
    """Plano de mascara (zplane 1): mask[y][strip] = byte (bit 7 = el pixel de la izquierda). Devuelve (mask, bytes)."""
    mask = [[0] * nstrips for _ in range(height)]
    end = zp + 2 * nstrips
    for s in range(nstrips):
        off = u16(b, zp + 2 * s)
        if off == 0:
            continue
        src = zp + off
        y = 0
        while y < height:
            c = b[src]
            src += 1
            if c & 0x80:
                n = c & 0x7F
                v = b[src]
                src += 1
                while n and y < height:
                    mask[y][s] = v
                    y += 1
                    n -= 1
            else:
                n = c
                while n and y < height:
                    mask[y][s] = b[src]
                    src += 1
                    y += 1
                    n -= 1
        end = max(end, src)
    return mask, end - zp


class Room:
    """Recurso de sala (al principio de NN.LFL)."""

    def __init__(self, ix, num):
        self.num = num
        b = ix.file(num)
        self.file = b
        self.size = u16(b, 0)
        self.width, self.height = u16(b, 4), u16(b, 6)
        if self.width == 1793:                       # WORKAROUND de ScummVM: sala 64 de Indy3 DOS/EGA 1.0
            self.width = 320
        self.image_off = u16(b, 0x0A)
        self.num_objects = b[20]
        self.box_off = u16(b, 0x15)
        self.num_sounds = b[23]
        self.num_scripts = b[24]
        self.excd_off = u16(b, 0x19)
        self.encd_off = u16(b, 0x1B)
        p = 29
        n = self.num_objects
        self.obim_offs = [u16(b, p + 2 * i) for i in range(n)]
        self.obcd_offs = [u16(b, p + 2 * n + 2 * i) for i in range(n)]
        p += 4 * n
        self.sound_ids = list(b[p:p + self.num_sounds])
        p += self.num_sounds
        self.script_ids = list(b[p:p + self.num_scripts])
        p += self.num_scripts
        self.local_scripts = []                      # (id, offset del codigo)
        while b[p]:
            self.local_scripts.append((b[p], u16(b, p + 1)))
            p += 3
        self.header_end = p + 1
        self.objects = [self._object(i) for i in range(n)]
        self._blocks()

    def _object(self, i):
        b = self.file
        o = Obj()
        o.index = i
        o.obim = self.obim_offs[i]
        c = o.obcd = self.obcd_offs[i]
        o.size = u16(b, c)
        o.id = u16(b, c + 4)
        o.x = b[c + 7] * 8
        o.y = (b[c + 8] & 0x7F) * 8
        o.parentstate = (b[c + 8] >> 7) & 1
        o.width = b[c + 9] * 8
        o.parent = b[c + 10]
        o.walk_x = u16(b, c + 11)
        o.walk_y = u16(b, c + 13)
        o.actordir = b[c + 15] & 7
        o.height = b[c + 15] & 0xF8
        o.name_off = b[c + 16]
        p = c + 17
        o.verbs = []
        while b[p] != 0:
            o.verbs.append((b[p], u16(b, p + 1)))
            p += 3
        o.verbs_end = p + 1 - c
        s = c + o.name_off
        e = b.index(0, s)
        o.name = bytes(b[s:e]).decode('latin1')
        o.block = b[c:c + o.size]
        return o

    def _blocks(self):
        """Parte el recurso en bloques: cada uno llega hasta el siguiente que empieza (como los HACK de ScummVM)."""
        starts = [(0, 'cabecera')]
        if self.box_off:
            starts.append((self.box_off, 'cajas'))
        if self.image_off:
            starts.append((self.image_off, 'imagen'))
        for o in self.objects:
            if o.obim and o.obim != self.image_off:
                starts.append((o.obim, 'obim'))
            starts.append((o.obcd, 'obcd'))
        if self.excd_off:
            starts.append((self.excd_off, 'excd'))
        if self.encd_off:
            starts.append((self.encd_off, 'encd'))
        for sid, off in self.local_scripts:
            starts.append((off, 'local'))
        starts = sorted(set(starts))
        self.blocks = []
        for k, (a, kind) in enumerate(starts):
            e = starts[k + 1][0] if k + 1 < len(starts) else self.size
            self.blocks.append((a, e, kind))
        self.by_kind = {}
        for a, e, kind in self.blocks:
            self.by_kind[kind] = self.by_kind.get(kind, 0) + (e - a)
        self.local_code = {}
        for sid, off in self.local_scripts:
            e = min([a for a, _, _ in self.blocks if a > off] + [self.size])
            self.local_code[sid] = self.file[off:e]

    def boxes(self):
        b = self.file
        if not self.box_off:
            return [], b''
        p = self.box_off
        n = b[p]
        bx = []
        for k in range(n):
            q = p + 1 + 18 * k
            bx.append(tuple(s16(b, q + 2 * j) for j in range(8)) + (b[q + 16], b[q + 17]))
        m0 = p + 1 + 18 * n
        return bx, b[m0:self.image_off]

    def image(self):
        """(img[y][x], bytes de las franjas, mask[y][strip], bytes de la mascara)."""
        b = self.file
        ns = self.width // 8
        img, n_img = decode_strips(b, self.image_off, ns, self.height)
        zp = self.image_off + u16(b, self.image_off)
        mask, n_mask = decode_mask(b, zp, ns, self.height)
        return img, n_img, mask, n_mask

    def object_image(self, o):
        """Imagen del objeto (o None si no tiene): (img, bytes, mask, bytes de mascara)."""
        if not o.obim or o.width == 0 or o.height == 0:
            return None
        b = self.file
        ns = o.width // 8
        # los objetos sin imagen comparten un OBIM pequeño (de otro objeto o vacio): drawStrip de ScummVM
        # no dibuja franjas cuyo offset no cabe en smapLen; aqui se tratan como "sin imagen"
        sl = u16(b, o.obim)
        if sl < 2 + 2 * ns or any(u16(b, o.obim + 2 + 2 * s) >= sl for s in range(ns)):
            return None                              # (assertRange de drawStrip: ScummVM tampoco lo dibujaria)
        img, n_img = decode_strips(b, o.obim, ns, o.height)
        zp = o.obim + u16(b, o.obim)
        mask, n_mask = decode_mask(b, zp, ns, o.height)
        return img, n_img, mask, n_mask

    def entry_script(self):
        e = min([a for a, _, _ in self.blocks if a > self.encd_off] + [self.size])
        return self.file[self.encd_off:e] if self.encd_off else b''

    def exit_script(self):
        e = min([a for a, _, _ in self.blocks if a > self.excd_off] + [self.size])
        return self.file[self.excd_off:e] if self.excd_off else b''


def check(ix):
    bad = 0
    for rn in ix.rooms():
        try:
            r = Room(ix, rn)
            img, ni, mask, nm = r.image()
            for o in r.objects:
                r.object_image(o)
                for v, off in o.verbs:
                    if off >= o.size:
                        print('sala %d obj %d: verbo %d fuera del bloque' % (rn, o.id, v))
                        bad += 1
            if r.size > len(r.file):
                print('sala %d: tamaño %d > fichero %d' % (rn, r.size, len(r.file)))
                bad += 1
        except Exception as e:
            print('sala %d: %s: %s' % (rn, type(e).__name__, e))
            bad += 1
    print('salas: %d, problemas: %d' % (len(ix.rooms()), bad))
    return bad


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 1
    ix = Index(sys.argv[1])
    cmd = sys.argv[2]
    if cmd == 'index':
        print('objetos globales: %d' % ix.num_objects)
        for t in ix.TYPES:
            ok = [i for i in range(len(ix.res[t])) if t == 'room' and ix.file(i) is not None or
                  t != 'room' and ix.resource(t, i) is not None]
            print('%-8s %3d entradas, %3d validas' % (t, len(ix.res[t]), len(ok)))
    elif cmd == 'room':
        r = Room(ix, int(sys.argv[3]))
        print('sala %d: %dx%d, %d bytes, imagen +%04X, cajas +%04X, %d objetos, ENCD +%04X EXCD +%04X' % (
            r.num, r.width, r.height, r.size, r.image_off, r.box_off, r.num_objects, r.encd_off, r.excd_off))
        print('sonidos', r.sound_ids, 'scripts', r.script_ids, 'locales', [s for s, _ in r.local_scripts])
        for k, v in sorted(r.by_kind.items()):
            print('  %-9s %6d' % (k, v))
        for o in r.objects:
            print('  obj %4d %-20s %3d,%3d %3dx%3d verbos %s' % (o.id, '"%s"' % o.name, o.x, o.y, o.width, o.height,
                                                                ' '.join('%d' % v for v, _ in o.verbs)))
    elif cmd == 'check':
        return 1 if check(ix) else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
"""Lector de datos AGI v3 (Sierra), copia de ScummVM engines/agi: loader_v3.cpp, lzw.cpp, picture.cpp (modo nibble) y logic.cpp (mensajes sin cifrar si la
logica va comprimida).

Formato v3:
  - Un solo directorio xxDIR (BCDIR...): cabecera de 8 bytes con 4 desplazamientos LE (logicas, imagenes, vistas, sonidos); entradas de 3 bytes como en v2
    (volumen = nibble alto del primer byte, desplazamiento = 24 bits BE & $FFFFF; $FFFFF = vacia). El de sonidos se corta en 256 entradas.
  - Volumenes xxVOL.n; cabecera de recurso de 7 bytes: $12 $34, byte 2 (bit 7 = imagen con parametros de color en nibbles, nibble bajo = volumen),
    tamano descomprimido (LE) y tamano comprimido (LE).
  - Bit 7 del byte 2: imagen "comprimida" (no lleva LZW: F0 y F2 toman un nibble en vez de un byte). Si no, tamano == comprimido: sin comprimir;
    si no, LZW. Los mensajes de una logica comprimida no van cifrados.

Game3 tiene la misma interfaz que agi_read.Game: resource(t, n) devuelve los bytes en el formato v2 (lo que leen las herramientas y el convertidor):
  - LOG: los mensajes cifrados con "Avis Durgan" (si la logica venia comprimida se cifran aqui, igual que la v2);
  - PIC: los nibbles de F0/F2 pasados a bytes (pic_nibble_to_v2; el dibujo es identico, ver check);
  - VIEW y SND: tal cual.
raw(t, n) devuelve (bytes tal y como los usa ScummVM, flags).

Uso:
    agi_v3.py JUEGO list                 # recursos (volumen, desplazamiento, tamano, comprimido, flags)
    agi_v3.py JUEGO check                # LZW + imagenes: modo nibble de ScummVM == imagen convertida a v2, pixel a pixel
    agi_v3.py JUEGO compare JUEGOV2      # recurso a recurso contra otro juego (p. ej. BC v2): bytes, mensajes e imagenes dibujadas
    agi_v3.py JUEGO dump SALIDA          # escribe LOGDIR/PICDIR/VIEWDIR/SNDDIR + VOL.n v2 equivalentes (para probar las herramientas v2)
JUEGO es la carpeta con xxDIR, xxVOL.n, WORDS.TOK y OBJECT (WORDS.TOK y OBJECT tienen el mismo formato que en v2).
"""
import os
import sys

import agi_read as ag
import refscummvm

EMPTY = 0xFFFFF
RES_COMPRESSED = 0x40
RES_PICTURE_V3_NIBBLE_PARM = 0x80


# --------------------------------------------------------------------------- LZW (lzw.cpp)

def lzw_expand(inp, length):
    """LZWDecoder::lzwExpand, literal: codigos de 9 bits que crecen hasta 11 (setBits(12) no cambia nada: MAXBITS = 12 devuelve sin tocar BITS),
    256 = empezar de nuevo, 257 = fin. inp lleva 32 bytes de ceros detras, como el calloc(clen + 32) de loadVolumeResource."""
    MAXBITS, TABLE_SIZE, START_BITS = 12, 18041, 9
    src = bytes(inp) + bytes(32)
    st = {'pos': 0, 'cnt': 0, 'buf': 0, 'BITS': 0, 'MAX_CODE': 0}
    prefix = [0] * TABLE_SIZE
    append = [0] * TABLE_SIZE

    def set_bits(v):
        if v == MAXBITS:
            return True
        st['BITS'] = v
        st['MAX_CODE'] = ((1 << v) - 1) - 1
        return False

    def input_code():
        while st['cnt'] <= 24:
            b = src[st['pos']] if st['pos'] < len(src) else 0
            st['pos'] += 1
            st['buf'] = (st['buf'] | (b << st['cnt'])) & 0xFFFFFFFF
            st['cnt'] += 8
        r = (st['buf'] & 0x7FFF) % (1 << st['BITS'])
        st['buf'] >>= st['BITS']
        st['cnt'] -= st['BITS']
        return r

    def decode_string(stack, code):
        """decodeString: anade a stack los caracteres en orden inverso; el ultimo es el primero de la cadena."""
        i = 0
        while code > 255:
            stack.append(append[code])
            code = prefix[code]
            if i >= 4000:
                raise ValueError('lzw: error in code expansion')
            i += 1
        stack.append(code & 0xFF)
        return stack

    out = bytearray()
    set_bits(START_BITS)
    lzwnext = 257
    lzwold = input_code()
    c = lzwold
    lzwnew = input_code()
    while len(out) < length and lzwnew != 0x101:
        if lzwnew == 0x100:
            lzwnext = 258
            set_bits(START_BITS)
            lzwold = input_code()
            c = lzwold
            out.append(c & 0xFF)
            lzwnew = input_code()
        else:
            if lzwnew >= lzwnext:
                s = decode_string([c & 0xFF], lzwold)
            else:
                s = decode_string([], lzwnew)
            c = s[-1]
            out += bytes(reversed(s))
            if lzwnext > st['MAX_CODE']:
                set_bits(st['BITS'] + 1)
            prefix[lzwnext] = lzwold
            append[lzwnext] = c
            lzwnext += 1
            lzwold = lzwnew
            lzwnew = input_code()
    # el bufer de ScummVM es calloc(len + 32): lo que no se escribe queda a cero y lo escrito de mas no se usa
    return bytes(out[:length]) + bytes(max(0, length - len(out)))


# --------------------------------------------------------------------------- imagenes con nibbles (picture.cpp)

class RefV3(refscummvm.Ref):
    """PictureMgr::drawPicture con el modo nibble (getNextByte/getNextNibble con _dataOffsetNibble). data: el bufer tal cual (clen bytes); size: dirPic.len
    (_dataSize, el tamano descomprimido de la cabecera); detras del bufer hay ceros (calloc(clen + 32))."""
    def nb(self):
        d, p = self.d, self.p
        if not self.half:
            self.p = p + 1
            return d[p] if p < len(d) else 0
        cur = ((d[p] if p < len(d) else 0) << 4) & 0xFF
        self.p = p + 1
        return ((d[p + 1] if p + 1 < len(d) else 0) >> 4) | cur

    def nibble(self):
        d, p = self.d, self.p
        v = d[p] if p < len(d) else 0
        if not self.half:
            self.half = True
            return v >> 4
        self.half = False
        self.p = p + 1
        return v & 0x0F

    def draw_picture_v3(self, data, size, nibble_mode, clear=True):
        if clear:
            self.clear()
        self.d = data
        self.p = 0
        self.half = False
        self.pat_code = self.pat_num = 0
        self.pri_on = self.scr_on = False
        self.scr_color, self.pri_color = 15, 4
        while self.p < size:
            b = self.nb()
            if b == 0xF0:
                self.scr_color = self.nibble() if nibble_mode else self.nb()
                self.scr_on = True
            elif b == 0xF1:
                self.scr_on = False
            elif b == 0xF2:
                self.pri_color = self.nibble() if nibble_mode else self.nb()
                self.pri_on = True
            elif b == 0xF3:
                self.pri_on = False
            elif b == 0xF4:
                self.y_corner()
            elif b == 0xF5:
                self.x_corner()
            elif b == 0xF6:
                self.line_abs()
            elif b == 0xF7:
                self.line_short()
            elif b == 0xF8:
                while True:
                    c = self.coords()
                    if c is None:
                        break
                    self.fill(*c)
            elif b == 0xF9:
                self.pat_code = self.nb()
            elif b == 0xFA:
                self.plot_brush()
            elif b == 0xFF:
                return


def pic_nibble_to_v2(data, size):
    """Imagen v3 con nibbles -> la misma imagen en bytes (v2). Se lee con las mismas reglas que drawPicture: todas las lecturas son getNextByte salvo el color de
    F0/F2 (getNextNibble); los parametros de cualquier orden (y los bytes sueltos, que drawPicture ignora uno a uno) se leen hasta el siguiente byte >= $F0,
    que se devuelve (getNextParamByte). F9 lee su byte sin mirar si es >= $F0. La salida acaba en $FF."""
    r = RefV3()
    r.d, r.p, r.half = data, 0, False
    out = bytearray()
    while r.p < size:
        b = r.nb()
        out.append(b)
        if b in (0xF0, 0xF2):
            out.append(r.nibble())
        elif b == 0xF9:
            out.append(r.nb())
        elif b == 0xFF:
            return bytes(out)
        else:
            while r.p < size:
                v = r.nb()
                if v >= 0xF0:
                    r.p -= 1
                    break
                out.append(v)
    out.append(0xFF)
    return bytes(out)


# --------------------------------------------------------------------------- juego

class Game3:
    TYPES = ('LOG', 'PIC', 'VIEW', 'SND')

    def __init__(self, path):
        self.path = path
        dname = [f for f in os.listdir(path) if len(f) > 3 and f.upper().endswith('DIR') and os.path.isfile(os.path.join(path, f))]
        if not dname:
            raise FileNotFoundError('%s: no hay fichero xxDIR (no es un juego AGI v3)' % path)
        dname = sorted(dname)[0]
        self.name = dname[:-3]
        with open(os.path.join(path, dname), 'rb') as f:
            d = f.read()
        offs = [d[2 * i] | (d[2 * i + 1] << 8) for i in range(4)]
        lens = [offs[1] - offs[0], offs[2] - offs[1], offs[3] - offs[2], len(d) - offs[3]]
        lens[3] = min(lens[3], 256 * 3)
        self.dirs = {}
        for t, o, ln in zip(self.TYPES, offs, lens):
            ents = []
            i = 0
            while i + 2 < ln:
                b0, b1, b2 = d[o + i:o + i + 3]
                off = ((b0 << 16) | (b1 << 8) | b2) & EMPTY
                ents.append(None if off == EMPTY else (b0 >> 4, off))
                i += 3
            self.dirs[t] = ents
        self.vols = {}
        self.cache = {}

    def vol(self, n):
        if n not in self.vols:
            fn = [f for f in os.listdir(self.path) if f.upper() == ('%sVOL.%d' % (self.name, n)).upper()]
            with open(os.path.join(self.path, fn[0] if fn else '%sVOL.%d' % (self.name, n)), 'rb') as f:
                self.vols[n] = f.read()
        return self.vols[n]

    def header(self, t, n):
        """(volumen, desplazamiento, byte 2, tamano, comprimido) o None."""
        e = self.dirs[t][n] if n < len(self.dirs[t]) else None
        if e is None:
            return None
        v, off = e
        try:
            d = self.vol(v)
        except FileNotFoundError:
            return None
        h = d[off:off + 7]
        if h[:2] != b'\x12\x34':
            raise ValueError('%s %d: cabecera erronea en %sVOL.%d+%X' % (t, n, self.name, v, off))
        return v, off, h[2], h[3] | (h[4] << 8), h[5] | (h[6] << 8)

    def raw(self, t, n):
        """loadVolumeResource: (datos, flags, tamano) o None. Imagen con nibbles: datos = los clen bytes tal cual y tamano = len (dirPic.len, el _dataSize de
        drawPicture). Si no, datos de len bytes."""
        key = (t, n)
        if key in self.cache:
            return self.cache[key]
        h = self.header(t, n)
        if h is None:
            return None
        v, off, b2, ln, cln = h
        comp = self.vol(v)[off + 7:off + 7 + cln]
        if b2 & 0x80:
            r = (comp, RES_PICTURE_V3_NIBBLE_PARM, ln)
        elif ln == cln:
            r = (comp, 0, ln)
        else:
            r = (lzw_expand(comp, ln), RES_COMPRESSED, ln)
        self.cache[key] = r
        return r

    def resource(self, t, n):
        """Datos del recurso en formato v2 (ver el docstring del modulo) o None."""
        r = self.raw(t, n)
        if r is None:
            return None
        d, flags, ln = r
        if t == 'PIC' and flags & RES_PICTURE_V3_NIBBLE_PARM:
            return pic_nibble_to_v2(d, ln)
        if t == 'LOG' and flags & RES_COMPRESSED:
            return encrypt_logic(d)
        return bytes(d)

    def present(self, t):
        return [i for i, e in enumerate(self.dirs[t]) if e is not None]


def logic_strings_range(d):
    """(stringsPos, stringsSize) de decodeLogic."""
    code = d[0] | (d[1] << 8)
    ms = 2 + code
    cnt = d[ms]
    msize = d[ms + 1] | (d[ms + 2] << 8)
    sp = ms + 3 + 2 * cnt
    return sp, msize - 2 - 2 * cnt, cnt


def encrypt_logic(d):
    """Logica comprimida (mensajes en claro) -> la misma con los mensajes cifrados como en v2. decodeLogic descifra stringsSize bytes desde stringsPos con la
    clave desde el principio; agi_read.logic_messages descifra desde ahi hasta el final: se cifra solo lo que ScummVM descifra (lo de detras, si lo hay, no
    son mensajes) y se comprueba que logic_messages da lo mismo que ScummVM."""
    d = bytearray(d)
    sp, ss, cnt = logic_strings_range(d)
    if cnt > 0:
        for i in range(max(0, ss)):
            if sp + i < len(d):
                d[sp + i] ^= ag.KEY[i % len(ag.KEY)]
    return bytes(d)


def scummvm_messages(d, compressed):
    """Mensajes como los deja decodeLogic (lista, None = desplazamiento 0)."""
    d = bytearray(d)
    sp, ss, cnt = logic_strings_range(d)
    if not compressed and cnt > 0:
        for i in range(max(0, ss)):
            if sp + i < len(d):
                d[sp + i] ^= ag.KEY[i % len(ag.KEY)]
    ms = 2 + (d[0] | (d[1] << 8))
    out = []
    for i in range(cnt):
        so = d[ms + 3 + 2 * i] | (d[ms + 4 + 2 * i] << 8)
        if so == 0:
            out.append(None)
            continue
        p = so + ms + 1
        q = d.find(b'\x00', p)
        out.append(bytes(d[p:q if q >= 0 else len(d)]).decode('latin-1'))
    return out


def is_v3(path):
    """Hay un xxDIR (y no LOGDIR): juego v3."""
    fs = [f.upper() for f in os.listdir(path)]
    return 'LOGDIR' not in fs and any(len(f) > 3 and f.endswith('DIR') for f in fs)


# --------------------------------------------------------------------------- comprobaciones

def check(g):
    """Todos los recursos se leen; las logicas comprimidas: logic_messages(resource) == mensajes de ScummVM; las imagenes: el modo nibble de ScummVM
    (RefV3) y la imagen convertida a v2 dibujada con refscummvm.Ref dan los mismos pixeles (visual y prioridad). Devuelve el numero de fallos."""
    bad = 0
    for t in Game3.TYPES:
        cnt = {'nibble': 0, 'lzw': 0, 'plano': 0}
        for n in g.present(t):
            try:
                d, flags, ln = g.raw(t, n)
            except Exception as e:                  # noqa: BLE001
                print('%s %d: error al leer: %s' % (t, n, e))
                bad += 1
                continue
            cnt['nibble' if flags & RES_PICTURE_V3_NIBBLE_PARM else 'lzw' if flags & RES_COMPRESSED else 'plano'] += 1
            if t == 'LOG':
                a = ag.logic_messages(g.resource('LOG', n))
                b = scummvm_messages(d, bool(flags & RES_COMPRESSED))
                if a != b:
                    print('LOG %d: mensajes distintos de ScummVM' % n)
                    bad += 1
            elif t == 'PIC':
                r1 = RefV3()
                r1.draw_picture_v3(d, ln, bool(flags & RES_PICTURE_V3_NIBBLE_PARM))
                r2 = refscummvm.Ref()
                r2.draw_picture(g.resource('PIC', n))
                if r1.vis != r2.vis or r1.pri != r2.pri:
                    print('PIC %d: la imagen convertida a v2 no dibuja igual' % n)
                    bad += 1
        print('%-4s %3d recursos: %s' % (t, len(g.present(t)), ', '.join('%s %d' % kv for kv in cnt.items() if kv[1])))
    return bad


def compare(g3, g2):
    """Recurso a recurso contra un juego v2 (agi_read.Game): bytes iguales; si no, logicas: codigo y mensajes; imagenes: pixeles."""
    for t in Game3.TYPES:
        p3, p2 = set(g3.present(t)), set(g2.present(t))
        same, diff = [], []
        for n in sorted(p3 & p2):
            a, b = g3.resource(t, n), g2.resource(t, n)
            if a == b:
                same.append(n)
                continue
            why = '%d/%d bytes' % (len(a), len(b))
            if t == 'LOG':
                ca, cb = a[2:2 + (a[0] | (a[1] << 8))], b[2:2 + (b[0] | (b[1] << 8))]
                ma, mb = ag.logic_messages(a), ag.logic_messages(b)
                why = 'codigo %s, mensajes %s' % ('igual' if ca == cb else 'distinto (%d/%d)' % (len(ca), len(cb)),
                                                 'iguales' if ma == mb else 'distintos (%d de %d/%d)' % (
                                                     sum(1 for x, y in zip(ma, mb) if x != y) + abs(len(ma) - len(mb)), len(ma), len(mb)))
                if ca == cb and ma == mb:
                    why += ' (solo cambia el relleno)'
            elif t == 'PIC':
                r1, r2 = refscummvm.Ref(), refscummvm.Ref()
                r1.draw_picture(a)
                r2.draw_picture(b)
                nv = sum(1 for x, y in zip(r1.vis, r2.vis) if x != y)
                npr = sum(1 for x, y in zip(r1.pri, r2.pri) if x != y)
                why = 'dibujo igual' if nv == npr == 0 else 'pixeles distintos: visual %d, prioridad %d' % (nv, npr)
                if nv == npr == 0:
                    same.append(n)
                    continue
            diff.append((n, why))
        print('%-4s v3 %3d, v2 %3d: iguales %d, distintos %d, solo v3 %s, solo v2 %s' % (
            t, len(p3), len(p2), len(same), len(diff), sorted(p3 - p2) or '-', sorted(p2 - p3) or '-'))
        for n, why in diff:
            print('     %3d: %s' % (n, why))


def dump(g, out):
    """Directorios y volumenes v2 con los recursos en formato v2 (cabecera de 5 bytes, todo en VOL.0... segun el volumen original)."""
    os.makedirs(out, exist_ok=True)
    vols = {}
    for t in Game3.TYPES:
        ents = bytearray()
        for n in range(len(g.dirs[t])):
            d = g.resource(t, n) if g.dirs[t][n] else None
            if d is None:
                ents += b'\xFF\xFF\xFF'
                continue
            v = g.dirs[t][n][0]
            buf = vols.setdefault(v, bytearray())
            off = len(buf)
            buf += bytes((0x12, 0x34, v, len(d) & 255, len(d) >> 8)) + d
            ents += bytes(((v << 4) | (off >> 16), (off >> 8) & 255, off & 255))
        with open(os.path.join(out, t + 'DIR'), 'wb') as f:
            f.write(ents)
    for v, buf in vols.items():
        with open(os.path.join(out, 'VOL.%d' % v), 'wb') as f:
            f.write(buf)
    import shutil
    for fn in os.listdir(g.path):
        if fn.upper() in ('WORDS.TOK', 'OBJECT'):
            shutil.copy(os.path.join(g.path, fn), os.path.join(out, fn.upper()))
    print('escrito en', out)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = Game3(argv[1])
    cmd = argv[2]
    if cmd == 'list':
        for t in Game3.TYPES:
            pr = g.present(t)
            print('%s: %d de %d' % (t, len(pr), len(g.dirs[t])))
            for n in pr:
                v, off, b2, ln, cln = g.header(t, n)
                kind = 'nibble' if b2 & 0x80 else 'plano' if ln == cln else 'lzw'
                print('  %3d  VOL.%d+%05X  %5d  %5d  %s' % (n, v, off, ln, cln, kind))
    elif cmd == 'check':
        bad = check(g)
        print('fallos:', bad)
        return 1 if bad else 0
    elif cmd == 'compare':
        compare(g, ag.Game(argv[3]))
    elif cmd == 'dump':
        dump(g, argv[3])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

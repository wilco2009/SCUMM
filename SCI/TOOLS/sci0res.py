#!/usr/bin/env python3
"""Lector de recursos de SCI0 (RESOURCE.MAP + RESOURCE.00x), como ScummVM.

Referencia: engines/sci/resource/resource.cpp (readResourceMapSCI0,
readResourceInfo) y resource/decompressor.cpp (LZW SCI0 LSB, Huffman).
Solo lectura: no escribe nada.
"""
import os
import struct
import sys

TYPES = ['view', 'pic', 'script', 'text', 'sound', 'memory', 'vocab', 'font',
         'cursor', 'patch', 'bitmap', 'palette', 'cdaudio', 'audio', 'sync',
         'message', 'map', 'heap']


class BitReader:
    def __init__(self, data):
        self.d = data
        self.p = 0
        self.bits = 0
        self.n = 0

    def _byte(self):
        if self.p < len(self.d):
            b = self.d[self.p]
        else:
            b = 0
        self.p += 1
        return b

    def lsb(self, n):
        while self.n < n:
            self.bits |= self._byte() << self.n
            self.n += 8
        r = self.bits & ((1 << n) - 1)
        self.bits >>= n
        self.n -= n
        return r

    def msb(self, n):
        # como fetchBitsMSB: buffer de 32 bits alineado a la izquierda
        while self.n < n:
            self.bits = (self.bits << 8) | self._byte()
            self.n += 8
        r = (self.bits >> (self.n - n)) & ((1 << n) - 1)
        self.n -= n
        self.bits &= (1 << self.n) - 1
        return r


def unpack_lzw0(data, size):
    """DecompressorLZW::unpackLZW con kCompLZW (SCI0, LSB primero)."""
    br = BitReader(data)
    out = bytearray()
    bitlen, table, limit = 9, 258, 512
    offs = [0] * 4096
    lens = [0] * 4096
    while len(out) < size:
        code = br.lsb(bitlen)
        if code >= table:
            break
        if code == 257:
            break
        if code == 256:
            bitlen, table, limit = 9, 258, 512
            continue
        start = len(out)
        if code <= 255:
            out.append(code)
        else:
            o = offs[code]
            for i in range(lens[code]):
                if len(out) >= size:
                    break
                out.append(out[o + i])
        if table >= 4096:
            continue
        if table == limit and bitlen < 12:
            bitlen += 1
            limit = 1 << bitlen
        offs[table] = start
        lens[table] = len(out) - start + 1
        table += 1
    return bytes(out[:size])


def unpack_huffman(data, size):
    numnodes = data[0]
    term = data[1] | 0x100
    nodes = data[2:2 + numnodes * 2]
    br = BitReader(data[2 + numnodes * 2:])
    out = bytearray()
    while len(out) < size:
        i = 0
        c = None
        while nodes[i + 1]:
            if br.msb(1):
                nxt = nodes[i + 1] & 0x0F
                if nxt == 0:
                    c = br.msb(8) | 0x100
                    break
            else:
                nxt = nodes[i + 1] >> 4
            i += nxt * 2
        if c is None:
            c = nodes[i] | (nodes[i + 1] << 8)
        if c == term or c < 0:
            break
        out.append(c & 0xFF)
    return bytes(out)


class ResMan:
    def __init__(self, path):
        self.path = path
        self.map = {}       # (tipo, num) -> (vol, offset)
        self.cache = {}
        self.info = {}      # (tipo, num) -> (empaquetado, desempaquetado, metodo)
        with open(os.path.join(path, 'RESOURCE.MAP'), 'rb') as f:
            m = f.read()
        for i in range(0, len(m) - 5, 6):
            rid, off = struct.unpack_from('<HI', m, i)
            if off == 0xFFFFFFFF:
                break
            t, n = rid >> 11, rid & 0x7FF
            key = (TYPES[t], n)
            if key not in self.map:
                self.map[key] = (off >> 26, off & 0x3FFFFFF)

    def keys(self, t=None):
        return sorted(k for k in self.map if t is None or k[0] == t)

    def raw_info(self, key):
        if key in self.info:
            return self.info[key]
        vol, off = self.map[key]
        fn = os.path.join(self.path, 'RESOURCE.%03d' % vol)
        if not os.path.exists(fn):
            return None
        with open(fn, 'rb') as f:
            f.seek(off)
            hdr = f.read(8)
        rid, packed, unpacked, method = struct.unpack('<HHHH', hdr)
        self.info[key] = (packed - 4, unpacked, method)
        return self.info[key]

    def get(self, t, n=None):
        key = t if n is None else (t, n)
        if key in self.cache:
            return self.cache[key]
        if key not in self.map:
            return None
        vol, off = self.map[key]
        fn = os.path.join(self.path, 'RESOURCE.%03d' % vol)
        if not os.path.exists(fn):
            return None
        with open(fn, 'rb') as f:
            f.seek(off)
            hdr = f.read(8)
            rid, packed, unpacked, method = struct.unpack('<HHHH', hdr)
            data = f.read(packed - 4)
        self.info[key] = (packed - 4, unpacked, method)
        if method == 0:
            res = data[:unpacked]
        elif method == 1:
            res = unpack_lzw0(data, unpacked)
        elif method == 2:
            res = unpack_huffman(data, unpacked)
        else:
            raise ValueError('compresion %d en %s' % (method, key))
        if len(res) != unpacked:
            print('aviso: %s %d != %d' % (key, len(res), unpacked), file=sys.stderr)
        self.cache[key] = res
        return res


# ---------------------------------------------------------------- vocabularios

def vocab_strings(rm, n):
    """Vocab 997 (selectores) y 999 (kernel): tabla de cadenas con longitud."""
    d = rm.get('vocab', n)
    if d is None:
        return []
    cnt = struct.unpack_from('<H', d, 0)[0]
    out = []
    for i in range(cnt + 1):
        if 2 + i * 2 + 2 > len(d):
            break
        o = struct.unpack_from('<H', d, 2 + i * 2)[0]
        if o + 2 > len(d):
            break
        ln = struct.unpack_from('<H', d, o)[0]
        out.append(d[o + 2:o + 2 + ln].decode('latin-1'))
    return out


def class_table(rm):
    """Vocab 996: por clase, (puntero, script)."""
    d = rm.get('vocab', 996)
    return [struct.unpack_from('<H', d, i + 2)[0] for i in range(0, len(d) - 3, 4)]


# ------------------------------------------------------------------- scripts

BLOCKS = ['end', 'object', 'code', 'synonyms', 'said', 'strings', 'class',
          'exports', 'pointers', 'preload', 'locals']


def script_blocks(buf, early=False):
    p = 2 if early else 0
    out = []
    while p + 4 <= len(buf):
        t, sz = struct.unpack_from('<HH', buf, p)
        if t == 0:
            break
        if sz == 0:
            break
        out.append((t, p, sz))
        p += sz
    return out


def cstr(buf, o):
    e = buf.find(b'\0', o)
    return buf[o:e].decode('latin-1')


def script_objects(buf, early=False):
    """Objetos y clases: (tipo, pos, nvars, vars, metodos[(sel, off)])."""
    objs = []
    for t, p, sz in script_blocks(buf, early):
        if t not in (1, 6):
            continue
        pos = p + 12
        nvars = struct.unpack_from('<H', buf, p + 10)[0]
        funcarea = struct.unpack_from('<H', buf, p + 8)[0]
        vars_ = list(struct.unpack_from('<%dH' % nvars, buf, pos))
        mbo = pos + funcarea - 2
        mc = struct.unpack_from('<H', buf, mbo)[0]
        sels = struct.unpack_from('<%dH' % mc, buf, mbo + 2)
        offs = struct.unpack_from('<%dH' % mc, buf, mbo + 2 + mc * 2 + 2)
        objs.append(dict(type='class' if t == 6 else 'object', pos=pos,
                         block=(p, sz), nvars=nvars, vars=vars_,
                         methods=list(zip(sels, offs))))
    return objs


def detect_early(rm):
    """SCI0 'early' lleva un u16 delante de los bloques del script 0."""
    b = rm.get('script', 0)
    t = struct.unpack_from('<H', b, 0)[0]
    return not (1 <= t <= 10)


if __name__ == '__main__':
    rm = ResMan(sys.argv[1])
    for t in TYPES[:10]:
        ks = rm.keys(t)
        if not ks:
            continue
        tot = sum((rm.raw_info(k) or (0, 0, 0))[1] for k in ks)
        print('%-7s %4d recursos  %8d B' % (t, len(ks), tot))

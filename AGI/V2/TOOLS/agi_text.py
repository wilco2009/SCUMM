#!/usr/bin/env python3
"""Texto del interprete AGI en el HiRes 8x1 (256x192): modelo de referencia de ENGINE/agitxt.asm.

Fuente de 6x8 (font6.bin: 96 glifos desde ASCII 32, los 6 bits de arriba de cada linea), 42 columnas x 24 filas de texto: la fila 0 es la barra de
estado, las 1-21 son la imagen (lineas 8-175) y las 22-23 el pie. Cada linea de texto se compone por celdas HiRes de 8 pixeles: una celda
cubierta entera por el texto pasa a papel = fondo, tinta = color del texto con el bitmap de los glifos; una celda a medias recibe solo los pixeles
cubiertos, uno a uno, con la regla de agi_vm.plot_hr.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agi2hr

FONT = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'V2', 'ENGINE', 'font6.bin'), 'rb').read()
FONT = FONT[:512] + bytes([0, 0b00100000, 0b00010000, 0, 0, 0, 0, 0]) + FONT[520:]      # ASCII 96: acento grave en vez de la libra (comillas ``asi'' de AGI)
GFX4 = os.environ.get('AGI_GFX4') == '1'        # modo 160w (AGI/PLAN160W.md): el texto va al plano de 40x25 codigos de la FPGA
COLS, ROWS = (40 if GFX4 else 42), 24


class TextPlane(bytearray):
    """GFX4: los 40 x 25 codigos del plano de texto (fila * 40 + columna). 0 = celda transparente; 32-127 = el caracter en negro sobre blanco; +128 = blanco sobre negro
    (la FPGA solo tiene un par de colores: fondo 0 = inverso, cualquier otro = negro sobre blanco)."""


def plane_put(tp, row, col, text, bg):
    inv = 0 if bg & 15 else 128
    for i, ch in enumerate(text[:max(0, 40 - col)]):
        o = ord(ch)
        tp[row * 40 + col + i] = (o if 32 <= o <= 127 else 32) | inv


def plane_fill(tp, row, col, n, bg):
    for i in range(col, min(col + n, 40)):
        tp[row * 40 + i] = 32 if bg & 15 else 160


def plot_hr(bm, at, y, x, c):
    """Un pixel HiRes: cada celda de 8 pixeles solo tiene dos colores; si c no es ninguno, sustituye al mas parecido."""
    i = y * 32 + (x >> 3)
    bit = 0x80 >> (x & 7)
    paper, ink = at[i] >> 4, at[i] & 15
    if paper == ink:                    # celda de un solo color: sus bits estan a 0 y hay que dejarlos asi si el color es el mismo
        if c == ink:
            bm[i] &= ~bit & 255
        else:
            at[i] = (paper << 4) | c
            bm[i] |= bit
    elif c == ink:
        bm[i] |= bit
    elif c == paper:
        bm[i] &= ~bit & 255
    elif agi2hr.sdist(c, paper) < agi2hr.sdist(c, ink):
        at[i] = (c << 4) | ink
        bm[i] &= ~bit & 255
    else:
        at[i] = (paper << 4) | c
        bm[i] |= bit


def put_line(bm, at, base, row, col, text, fg, bg, x0=None):
    """Escribe `text` (sin saltos de linea) en la fila de texto `row`, columna `col`. base = linea de pantalla que es la linea 0 del plano."""
    if isinstance(bm, TextPlane):
        plane_put(bm, row, col if x0 is None else x0 >> 3, text, bg)
        return
    if x0 is None:
        text = text[:max(0, COLS - col)]        # el texto no pasa de la ultima columna (como draw_line del Z80)
    n = len(text)
    if n == 0:
        return
    if x0 is None:
        x0 = col * 6
    ca = x0 >> 3
    cb = (x0 + 6 * n - 1) >> 3
    fgc = agi2hr.to_chroma(fg & 15)
    bgc = agi2hr.to_chroma(bg & 15)
    for k in range(8):
        line = row * 8 + k - base
        bits = [0] * 34
        mask = [0] * 34
        for i, ch in enumerate(text):
            o = ord(ch)
            if o < 32 or o > 127:
                o = 32
            g = FONT[(o - 32) * 8 + k] & 0xFC
            s = x0 + 6 * i - 8 * ca
            q, sh = s >> 3, s & 7
            v = (g << 8) >> sh
            m = (0xFC << 8) >> sh
            bits[q] |= v >> 8
            bits[q + 1] |= v & 255
            mask[q] |= m >> 8
            mask[q + 1] |= m & 255
        for j in range(cb - ca + 1):
            cell = ca + j
            idx = line * 32 + cell
            b, m = bits[j], mask[j]
            if m == 255:
                bm[idx] = b if fgc != bgc else 0     # una celda de un solo color lleva el bitmap a 0
                at[idx] = (bgc << 4) | fgc
            elif m:
                for bit in range(8):
                    if m & (0x80 >> bit):
                        plot_hr(bm, at, line, cell * 8 + bit, fgc if b & (0x80 >> bit) else bgc)


def fill_row(bm, at, base, row, colour):
    if isinstance(bm, TextPlane):
        plane_fill(bm, row, 0, 40, colour)
        return
    c = agi2hr.to_chroma(colour & 15)
    for k in range(8):
        line = row * 8 + k - base
        for cell in range(32):
            bm[line * 32 + cell] = 0
            at[line * 32 + cell] = (c << 4) | c


def draw_box_px(img, geom, pic):
    """160w: la ventana de print en la imagen de 160x168 (lista de codigos de Chroma): 4 pixeles por columna, 8 lineas por fila; blanco con un marco rojo de un pixel y,
    con show.obj, los mosaicos de la celda (ancho, [(tx, ty, color, dato, mascara)]) centrados (x par) en la parte util."""
    top, cxl, boxw, nrows = geom
    white, red = agi2hr.to_chroma(15), agi2hr.to_chroma(4)
    x0, y0, w, h = cxl * 4, top * 8 - 8, boxw * 4, nrows * 8
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            edge = y in (y0, y0 + h - 1) or x in (x0, x0 + w - 1)
            img[y * 160 + x] = red if edge else white
    if pic:
        pw, tiles = pic
        px = x0 + 4 + (((boxw - 2) * 4 - pw) >> 1 & ~1)
        py = y0 + 8
        for tx, ty, col, pix, msk in tiles:
            for r in range(8):
                for k in range(8):
                    if msk[r] & (0x80 >> k):
                        img[(py + ty * 8 + r) * 160 + px + tx * 8 + k] = (col[r] >> 4) if pix[r] & (0x80 >> k) else (col[r] & 15)


def printable(s):
    return ''.join(ch if 32 <= ord(ch) <= 127 else ' ' for ch in s)


# ------------------------------------------------------------------------------------------------------------------ ventanas de mensaje (print)
MAXLINES = 19


def wrap(text, width):
    """Reparte el mensaje en lineas de como mucho `width` caracteres: las palabras (separadas por espacios o por cualquier caracter que no se imprima) se
    juntan de una en una; una palabra mas larga que la linea se parte en trozos de `width`; un salto de linea cierra la linea (aunque este vacia).
    Como mucho MAXLINES lineas."""
    lines = []
    for para in text.split('\n'):
        cur = ''
        for tok in printable(para).split(' '):
            if not tok:
                continue
            while len(tok) > width:
                if cur:
                    lines.append(cur)
                    cur = ''
                lines.append(tok[:width])
                tok = tok[width:]
            if not cur:
                cur = tok
            elif len(cur) + 1 + len(tok) <= width:
                cur += ' ' + tok
            else:
                lines.append(cur)
                cur = tok
        lines.append(cur)
    return lines[:MAXLINES]


def box_geom(lines, row=None, col=None, minw=0):
    """(fila de texto de arriba, celda de la izquierda, celdas de ancho, filas de alto) de la ventana de unas lineas. Una celda de relleno a cada lado y una fila
    arriba y otra abajo; centrada en la imagen (filas 1-21) o, con print.at, en (row, col * 6 pixeles) sin salirse de la imagen."""
    maxlen = max(len(l) for l in lines)
    boxw = max(maxlen + 2, minw) if GFX4 else max(((maxlen * 6 + 7) >> 3) + 2, minw)       # 160w: una columna (4 pixeles de la imagen) por caracter
    nrows = len(lines) + 2
    cells = 40 if GFX4 else 32
    if row is None:
        top = 1 + ((21 - nrows) >> 1)
        cxl = (cells - boxw) >> 1
    else:
        top = min(max(row, 1), 22 - nrows)
        cxl = min(col if GFX4 else (col * 6) >> 3, cells - boxw)
    return top, cxl, boxw, nrows


def draw_box(bm, at, lines, geom, pic=None):
    """Pinta la ventana en los planos de pantalla completa (192 lineas): blanco con letras negras y un marco rojo de un pixel."""
    top, cxl, boxw, nrows = geom
    if isinstance(bm, TextPlane):               # 160w: la ventana (blanco, marco rojo y dibujo) son pixeles de la imagen (draw_box_px); en el plano, celdas transparentes y las lineas (inversas)
        for r in range(top, top + nrows):
            for i in range(cxl, cxl + boxw):
                bm[r * 40 + i] = 0
        for i, l in enumerate(lines):
            if l:
                plane_put(bm, top + 1 + i, cxl + 1, l, 15)
        return
    white, red = agi2hr.to_chroma(15), agi2hr.to_chroma(4)
    for k in range(nrows * 8):
        line = top * 8 + k
        for c in range(cxl, cxl + boxw):
            bm[line * 32 + c] = 0
            at[line * 32 + c] = (white << 4) | red
    for i, l in enumerate(lines):
        if l:
            put_line(bm, at, 0, top + 1 + i, 0, l, 0, 15, x0=8 * (cxl + 1))
    for c in range(cxl, cxl + boxw):
        bm[top * 8 * 32 + c] = 255
        bm[((top + nrows) * 8 - 1) * 32 + c] = 255
    for k in range(nrows * 8):
        line = top * 8 + k
        bm[line * 32 + cxl] |= 0x80
        bm[line * 32 + cxl + boxw - 1] |= 0x01

    if pic:                                 # show.obj: mosaicos (tx, ty, color, dato, mascara) de la celda, centrados en la ventana
        w, tiles = pic
        c0 = cxl + 1 + ((boxw - 2 - ((w + 7) >> 3)) >> 1)
        y0 = (top + 1) * 8
        for tx, ty, col, pix, msk in tiles:
            for r in range(8):
                if not msk[r]:
                    continue
                i = (y0 + ty * 8 + r) * 32 + c0 + tx
                if msk[r] == 255:
                    bm[i] = pix[r]
                    at[i] = ((col[r] << 4) | (col[r] >> 4)) & 255
                else:
                    bm[i] = pix[r] & msk[r]
                    at[i] = 0xF0 | (col[r] >> 4)

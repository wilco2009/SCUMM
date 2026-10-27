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
COLS, ROWS = 42, 24


def plot_hr(bm, at, y, x, c):
    """Un pixel HiRes: cada celda de 8 pixeles solo tiene dos colores; si c no es ninguno, sustituye al mas parecido."""
    i = y * 32 + (x >> 3)
    bit = 0x80 >> (x & 7)
    paper, ink = at[i] >> 4, at[i] & 15
    if c == ink:
        bm[i] |= bit
    elif c == paper:
        bm[i] &= ~bit & 255
    elif paper == ink:
        at[i] = (paper << 4) | c
        bm[i] |= bit
    elif agi2hr.sdist(c, paper) < agi2hr.sdist(c, ink):
        at[i] = (c << 4) | ink
        bm[i] &= ~bit & 255
    else:
        at[i] = (paper << 4) | c
        bm[i] |= bit


def put_line(bm, at, base, row, col, text, fg, bg):
    """Escribe `text` (sin saltos de linea) en la fila de texto `row`, columna `col`. base = linea de pantalla que es la linea 0 del plano."""
    n = len(text)
    if n == 0:
        return
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
                bm[idx] = b
                at[idx] = (bgc << 4) | fgc
            elif m:
                for bit in range(8):
                    if m & (0x80 >> bit):
                        plot_hr(bm, at, line, cell * 8 + bit, fgc if b & (0x80 >> bit) else bgc)


def fill_row(bm, at, base, row, colour):
    c = agi2hr.to_chroma(colour & 15)
    for k in range(8):
        line = row * 8 + k - base
        for cell in range(32):
            bm[line * 32 + cell] = 0
            at[line * 32 + cell] = (c << 4) | c


def printable(s):
    return ''.join(ch if 32 <= ord(ch) <= 127 else ' ' for ch in s)

#!/usr/bin/env python3
"""agi2snd.py: sonidos de AGI v2 (recursos SND, PCjr / Tandy de 3 voces de tono y 1 de ruido) -> SNDnnn.VGM del chip AY (los reproduce el MCU en segundo plano).

Formato del recurso: cuatro desplazamientos u16 a los canales (0-2 tono, 3 ruido); cada canal son notas de 5 bytes (duracion u16 en 1/60 s, b2, b3, b4) hasta una
duracion 0xFFFF. Tono: divisor de 10 bits ((b2 & 0x3F) << 4) | (b3 & 0x0F) sobre 111860 Hz, igual que el periodo del AY con el reloj del interface (1789772,8 Hz);
atenuacion b4 & 15 (pasos de 2 dB, 15 = silencio). Ruido: b3 & 7 (bit 2 = blanco, bits 0-1 = velocidad, 3 = la del canal 2); el AY solo tiene volumen por canal, asi que
el ruido va en un canal de tono libre (como TOOLS de SCUMM, sound2vgm.py).
Uso: agi2snd.py JUEGO SALIDA_DIR  -> SALIDA_DIR/SND/SND000.VGM ...
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..', 'V2', 'TOOLS'))
import agi_read as ag
import sound2vgm as S

S.TICK_HZ = 60                       # los eventos van en 1/60 s


def channels(d):
    out = []
    for c in range(4):
        p = d[2 * c] | (d[2 * c + 1] << 8)
        notes, t = [], 0
        while p + 5 <= len(d):
            dur = d[p] | (d[p + 1] << 8)
            if dur == 0xFFFF:
                break
            notes.append((t, t + dur, d[p + 2], d[p + 3], d[p + 4]))
            t += dur
            p += 5
        out.append(notes)
    return out


def regs_at(chs, t):
    period, vol, tone_on = [0, 0, 0], [0, 0, 0], [False] * 3
    div2 = 0
    for i in range(3):
        for a, b, b2, b3, b4 in chs[i]:
            if a <= t < b:
                div = ((b2 & 0x3F) << 4) | (b3 & 0x0F)
                if i == 2:
                    div2 = div
                v = S.ay_volume(b4 & 15)
                if v and div > 0:
                    tone_on[i] = True
                    period[i] = min(div, 4095)
                    vol[i] = v
    noise_p, noise_ch = 0, -1
    for a, b, b2, b3, b4 in chs[3]:
        if a <= t < b:
            v = S.ay_volume(b4 & 15)
            n = b3 & 3
            pn = div2 if n == 3 else (1 << (5 + n))
            pn = max(1, min(31, pn // 2 if n != 3 else pn))
            free = [i for i in range(3) if not tone_on[i]]
            if v and free:
                noise_ch, noise_p = free[-1], pn
                vol[noise_ch] = v
    mixer = 0xFF
    for i in range(3):
        if tone_on[i]:
            mixer &= ~(1 << i)
    if noise_ch >= 0:
        mixer &= ~(8 << noise_ch)
    regs = {}
    for i in range(3):
        regs[2 * i] = period[i] & 0xFF
        regs[2 * i + 1] = period[i] >> 8
        regs[8 + i] = vol[i]
    regs[6] = noise_p
    regs[7] = mixer
    return regs


def convert(d):
    chs = channels(d)
    total = max((n[-1][1] for n in chs if n), default=0)
    bounds = sorted({x for n in chs for note in n for x in (note[0], note[1])} | {0})
    last, ev = {}, []
    for t in bounds:
        if t >= total:
            break
        r = regs_at(chs, t)
        ch = {k: v for k, v in r.items() if last.get(k) != v}
        if ch:
            ev.append((t, ch))
            last.update(ch)
    ev.append((total, {8: 0, 9: 0, 10: 0, 7: 0xFF}))
    return S.vgm(ev, total), total


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 1
    g = ag.Game(argv[1])
    os.makedirs(os.path.join(argv[2], 'SND'), exist_ok=True)
    n = 0
    for k in g.present('SND'):
        try:
            d = g.resource('SND', k)
        except ValueError:
            continue
        if not d or len(d) < 8:
            continue
        data, total = convert(d)
        with open(os.path.join(argv[2], 'SND', 'SND%03d.VGM' % k), 'wb') as f:
            f.write(data)
        n += 1
    print('%d sonidos' % n)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

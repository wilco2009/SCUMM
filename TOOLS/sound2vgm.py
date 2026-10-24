#!/usr/bin/env python3
"""Convierte los sonidos de SCUMM v2 (recursos de sonido PCjr de Maniac Mansion / Zak) a ficheros VGM del chip AY y a la tabla de sonidos
del perfil de juego. Es una transcripcion de Player_V2Base / Player_V2 (PCjr) de ScummVM (engines/scumm/players/player_v2base.cpp,
player_v2.cpp): el secuenciador se simula en el PC tick a tick (236 Hz) y cada tick escribe en el AY los registros que corresponden.

El PCjr (3 voces de tono y 1 de ruido, divisor de 10 bits sobre 111860 Hz) se parece al AY (reloj del interface 1789772,8 Hz: un
periodo de AY = el divisor del PCjr). El ruido del PCjr se pone en un canal del AY que este libre (el AY solo tiene volumen por canal).

Uso: sound2vgm.py DIRECTORIO_LFL SALIDA_DIR [--nnn N]  -> SALIDA_DIR/SOUND000.VGM ... y SALIDA_DIR/SOUNDS.TXT (id prioridad reiniciable ticks inicio_del_bucle)
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scumm2

TICK_HZ = 236
SAMPLE_RATE = 44100
MAX_TICKS = 236 * 180            # 3 minutos: un sonido que no acaba antes se corta (bucle)

NOTE_LENGTHS = [0, 0, 0, 2, 0, 3, 4, 5, 6, 8, 9, 12, 16, 18, 24, 32, 36, 48, 64, 72, 96]
HULL_OFFSETS = [0, 12, 24, 36, 48, 60, 72, 88, 104, 120, 136, 256, 152, 164, 180]
FREQMOD_LENGTHS = [0x1000, 0x1000, 0x20, 0x2000, 0x1000]
FREQMOD_OFFSETS = [0, 0x100, 0x200, 0x302, 0x202]
PCJR_FREQ_TABLE = [65472, 61760, 58304, 55040, 52032, 49024, 46272, 43648, 41216, 38912, 36736, 34624]

# campos de channel_data como indices de uint16 (channel->array[]), ver player_v2base.h
F = dict(time_left=0, next_cmd=1, base_freq=2, freq_delta=3, freq=4, volume=5, volume_delta=6, tempo=7, inter_note_pause=8,
         transpose=9, note_length=10, hull_curve=11, hull_offset=12, hull_counter=13, freqmod_table=14, freqmod_offset=15,
         freqmod_incr=16, freqmod_multiplier=17, freqmod_modulo=18, music_timer=23, music_script_nr=24)
NFIELDS = 25


def load_tables():
    """Las tablas hulls y freqmod_table, tal cual estan en el codigo de ScummVM (SCUMM/TOOLS/player_v2_tables.py las genera)."""
    import player_v2_tables as T
    return T.HULLS, T.FREQMOD


class Sim:
    def __init__(self, data, hulls, freqmod):
        self.d = data
        self.hulls = hulls
        self.fm = freqmod
        self.ch = [[0] * NFIELDS for _ in range(5)]
        self.cur = 0
        self.retaddr = 0
        self.header_len = 4                      # GF_OLD_BUNDLE (v2)
        self.chain(1)

    def chain(self, nr):
        off = self.header_len + 10                # PCjr
        self.cur = nr
        for i in range(4):
            self.ch[i] = [0] * NFIELDS
            self.ch[i][F['music_script_nr']] = nr
            nc = struct.unpack_from('<H', self.d, off + 2 * i)[0] if off + 2 * i + 2 <= len(self.d) else 0
            self.ch[i][F['next_cmd']] = nc
            if nc:
                self.ch[i][F['time_left']] = 1

    def clear(self, c):
        for k in ('next_cmd', 'base_freq', 'freq_delta', 'freq', 'volume', 'volume_delta', 'inter_note_pause', 'transpose', 'hull_curve',
                  'hull_offset', 'hull_counter', 'freqmod_table', 'freqmod_offset', 'freqmod_incr', 'freqmod_multiplier', 'freqmod_modulo'):
            c[F[k]] = 0

    def execute(self, ci):
        chs = self.ch
        channel = chs[ci]
        cur_ci = ci
        d = self.d
        end_reached = False
        if channel[F['next_cmd']] != 0:
            sp = channel[F['next_cmd']]
            while True:
                op = d[sp]
                sp += 1
                if op >= 0xF8:
                    if op == 0xF8:
                        channel[F['hull_curve']] = HULL_OFFSETS[d[sp] // 2]
                        sp += 1
                    elif op == 0xF9:
                        channel[F['freqmod_table']] = FREQMOD_OFFSETS[d[sp] // 4]
                        channel[F['freqmod_modulo']] = FREQMOD_LENGTHS[d[sp] // 4]
                        sp += 1
                    elif op in (0xFD, 0xFA):
                        if op == 0xFD:
                            v = struct.unpack_from('<H', d, sp)[0] // 50          # sizeof(ChannelInfo) = 50
                            sp += 2
                            if v >= 5:
                                v = 4
                            channel = chs[v]
                        self.clear(channel)
                    elif op == 0xFB:
                        sp = self.retaddr
                    elif op == 0xFC:
                        off = struct.unpack_from('<h', d, sp)[0]
                        sp += 2
                        self.retaddr = sp
                        sp = off
                    elif op == 0xFE:
                        p = d[sp]
                        sp += 1
                        off = struct.unpack_from('<h', d, sp)[0]
                        sp += 2
                        if not channel[p // 2]:
                            sp += off
                        else:
                            channel[p // 2] = (channel[p // 2] - 1) & 0xFFFF
                            if channel[p // 2]:
                                sp += off
                    elif op == 0xFF:
                        p = d[sp]
                        sp += 1
                        channel[p // 2] = struct.unpack_from('<H', d, sp)[0]
                        sp += 2
                        if p == 0:
                            end_reached = True
                            break
                else:
                    stop = False
                    while True:
                        dest = chs[(op >> 5) & 3]
                        if not (op & 0x80):
                            tempo = channel[F['tempo']] or 1
                            channel[F['time_left']] = (tempo * NOTE_LENGTHS[op & 0x1F]) & 0xFFFF
                            note = d[sp]
                            sp += 1
                            last = note & 0x80
                            note &= 0x7F
                            if note == 0x7F:
                                stop = True
                                break
                        else:
                            channel[F['time_left']] = (((op & 7) << 8) | d[sp]) & 0xFFFF
                            sp += 1
                            if op & 0x10:
                                stop = True
                                break
                            last = 0
                            note = d[sp] & 0x7F
                            sp += 1
                        dest[F['time_left']] = channel[F['time_left']]
                        dest[F['note_length']] = (channel[F['time_left']] - dest[F['inter_note_pause']]) & 0xFFFF
                        t = dest[F['transpose']]
                        t = t - 0x10000 if t & 0x8000 else t
                        note += t
                        while note < 0:
                            note += 12
                        octave = note // 12
                        note = note % 12
                        dest[F['hull_offset']] = 0
                        dest[F['hull_counter']] = 1
                        if dest is chs[3]:
                            dest[F['hull_curve']] = 196 + note * 12
                            myfreq = 384 - 64 * octave
                        else:
                            myfreq = PCJR_FREQ_TABLE[note] >> octave
                        dest[F['freq']] = dest[F['base_freq']] = myfreq & 0xFFFF
                        if last:
                            stop = True
                            break
                        op = d[sp]
                        sp += 1
                    if stop:
                        break
            channel = chs[cur_ci]
            if channel[F['time_left']]:
                channel[F['next_cmd']] = sp
                return
            channel[F['next_cmd']] = 0
        for i in range(4):
            if self.ch[i][F['time_left']]:
                return
        self.cur = 0

    def next_freqs(self, ci):
        c = self.ch[ci]
        c[F['volume']] = (c[F['volume']] + c[F['volume_delta']]) & 0xFFFF
        c[F['base_freq']] = (c[F['base_freq']] + c[F['freq_delta']]) & 0xFFFF
        if c[F['freqmod_modulo']] > 0:
            c[F['freqmod_offset']] = (c[F['freqmod_offset']] + c[F['freqmod_incr']]) % c[F['freqmod_modulo']]
        else:
            c[F['freqmod_offset']] = 0
        m = self.fm[c[F['freqmod_table']] + (c[F['freqmod_offset']] >> 4)]
        mult = c[F['freqmod_multiplier']]
        prod = m * mult
        c[F['freq']] = (int(prod / 256) + c[F['base_freq']]) & 0xFFFF          # division de C++: trunca hacia cero
        if c[F['note_length']]:
            c[F['note_length']] = (c[F['note_length']] - 1) & 0xFFFF
            if not c[F['note_length']]:
                c[F['hull_offset']] = 16
                c[F['hull_counter']] = 1
        c[F['time_left']] = (c[F['time_left']] - 1) & 0xFFFF
        if not c[F['time_left']]:
            self.execute(ci)
        if c[F['hull_counter']]:
            c[F['hull_counter']] = (c[F['hull_counter']] - 1) & 0xFFFF
            if not c[F['hull_counter']]:
                while True:
                    p = c[F['hull_curve']] + c[F['hull_offset']] // 2
                    v, dd = self.hulls[p], self.hulls[p + 1]
                    if dd == -1:
                        c[F['volume']] = v & 0xFFFF
                        if v == 0:
                            c[F['volume_delta']] = 0
                        c[F['hull_offset']] += 4
                    else:
                        c[F['volume_delta']] = v & 0xFFFF
                        c[F['hull_counter']] = dd & 0xFFFF
                        c[F['hull_offset']] += 4
                        break

    def tick(self):
        for i in range(4):
            if self.ch[i][F['time_left']]:
                self.next_freqs(i)


# amplitud relativa de los 16 niveles de volumen del AY (tabla del chip)
AY_AMP = [0.0, 0.0100, 0.0145, 0.0211, 0.0307, 0.0455, 0.0645, 0.1073, 0.1266, 0.2050, 0.2922, 0.3728, 0.4925, 0.6353, 0.8055, 1.0]


def ay_volume(att):
    """Atenuacion PCjr (0-15, pasos de 2 dB; 15 = silencio) -> volumen AY mas cercano en amplitud."""
    if att >= 15:
        return 0
    a = 10 ** (-2.0 * att / 20.0)
    return min(range(1, 16), key=lambda v: abs(AY_AMP[v] - a))


def ay_regs(sim):
    """Registros del AY (0-10) para el estado actual del secuenciador."""
    c = sim.ch
    period, vol, tone_on = [0, 0, 0], [0, 0, 0], [False] * 3
    for i in range(3):
        n = c[i][F['freq']] >> 6
        if c[i][F['volume']] and c[i][F['time_left']] and 0 < n:
            att = (65535 - c[i][F['volume']]) >> 12
            v = ay_volume(att)
            if v:
                tone_on[i] = True
                period[i] = min(n, 4095)
                vol[i] = v
    noise_p, noise_ch = 0, -1
    n3 = c[3]
    if n3[F['volume']] and n3[F['time_left']]:
        v = ay_volume((65535 - n3[F['volume']]) >> 12)
        f = n3[F['freq']] >> 6
        n = f & 3
        pn = (2 * (c[2][F['freq']] >> 6)) if n == 3 else (1 << (5 + n))
        pn = max(1, min(31, pn // 2))
        free = [i for i in range(3) if not tone_on[i]]
        if v and free:
            noise_ch = free[-1]
            noise_p = pn
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


def render(data, hulls, freqmod):
    """Devuelve (cambios [(tick, {reg: valor})], ticks totales, inicio del bucle o None). Un sonido que vuelve exactamente al mismo estado
    del secuenciador se repite para siempre: se corta al volver a pasar por el estado del tick `inicio del bucle`."""
    sim = Sim(data, hulls, freqmod)
    last, out, t = {}, [], 0
    seen = {}
    global TIMER
    TIMER = []                                       # (tick, valor) de VAR_MUSIC_TIMER: lo que el sonido escribe en el canal 0
    while sim.cur and t < MAX_TICKS:
        sim.tick()
        if not TIMER or TIMER[-1][1] != sim.ch[0][F['music_timer']]:
            TIMER.append((t, sim.ch[0][F['music_timer']]))
        sig = (sim.cur, sim.retaddr, tuple(tuple(c) for c in sim.ch[:4]))
        if sig in seen:
            return out, t, seen[sig]
        seen[sig] = t
        regs = ay_regs(sim)
        ch = {r: v for r, v in regs.items() if last.get(r) != v}
        if ch:
            out.append((t, ch))
            last.update(ch)
        t += 1
    return out, t, None


def timer_params(tm, sid):
    """VAR_MUSIC_TIMER como (valor inicial, ticks entre dos incrementos): solo vale si sube de 1 en 1 a intervalos iguales (0, 0: no se usa)."""
    if len(tm) < 2 and (not tm or tm[0][1] == 0):
        return 0, 0
    if len(tm) < 2:
        return tm[0][1], 0
    step = tm[1][0] - tm[0][0]
    if all(b[1] == a[1] + 1 and b[0] - a[0] == step for a, b in zip(tm, tm[1:])):
        return tm[0][1], step
    print('sonido %3d: VAR_MUSIC_TIMER no es regular (no se usara)' % sid)
    return 0, 0


def vgm(events, total_ticks):
    """VGM 1.61 con solo el chip AY8910: las escrituras A0 aa dd y las esperas 61 nn nn (muestras a 44100 Hz)."""
    body = bytearray()
    acc_ticks = 0
    done_samples = 0
    pending_regs = []
    t_prev = 0

    def wait_to(tick):
        nonlocal done_samples
        target = round(tick * SAMPLE_RATE / TICK_HZ)
        d = target - done_samples
        while d > 0:
            n = min(d, 65535)
            body.extend(b'\x61' + struct.pack('<H', n))
            d -= n
            done_samples += n

    for t, ch in events:
        wait_to(t)
        for r in sorted(ch):
            body.extend(bytes([0xA0, r, ch[r]]))
    wait_to(total_ticks)
    body.append(0x66)
    hdr = bytearray(0x100)
    hdr[0:4] = b'Vgm '
    struct.pack_into('<I', hdr, 4, len(hdr) + len(body) - 4)
    struct.pack_into('<I', hdr, 8, 0x161)
    struct.pack_into('<I', hdr, 0x18, done_samples)
    struct.pack_into('<I', hdr, 0x34, 0x100 - 0x34)
    struct.pack_into('<I', hdr, 0x74, 1789773)       # reloj del AY
    hdr[0x78] = 0                                    # AY8910
    return bytes(hdr + body)


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 1
    d, out = args[0], args[1]
    os.makedirs(out, exist_ok=True)
    hulls, freqmod = load_tables()
    ix = scumm2.Index(d)
    lines = []
    for sid in range(0, 256):
        try:
            b = scumm2.resource(d, ix, 'sound', sid)
        except Exception:
            continue
        if not b or len(b) < 22:
            continue
        hl = 4
        prio, restart = b[hl], b[hl + 1]
        offs = [struct.unpack_from('<H', b, hl + 10 + 2 * i)[0] for i in range(4)]
        if not any(offs) or any(o and o >= len(b) for o in offs):
            continue
        try:
            ev, ticks, loop_at = render(b, hulls, freqmod)
        except Exception as e:
            print('sonido', sid, 'no se puede convertir:', e)
            continue
        if not ev:
            continue
        with open(os.path.join(out, 'SOUND%03d.VGM' % sid), 'wb') as f:
            f.write(vgm(ev, ticks))
        tstart, tstep = timer_params(TIMER, sid)
        lines.append('%d %d %d %d %d %d %d' % (sid, prio, restart, ticks, -1 if loop_at is None else loop_at, tstart, tstep))
        print('sonido %3d: prioridad %3d reiniciable %d  %5d ticks (%.1f s)%s  %d cambios' % (sid, prio, restart, ticks, ticks / TICK_HZ,
              ('  bucle desde el tick %d' % loop_at) if loop_at is not None else '', len(ev)))
    with open(os.path.join(out, 'SOUNDS.TXT'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())

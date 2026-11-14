#!/usr/bin/env python3
"""sound3vgm.py: sonidos de SCUMM v3 (Indy3 EGA, bloque PCjr) -> ficheros VGM del AY y SOUNDS.TXT.

El formato es el de v2 (ScummVM usa Player_V2 / Player_V2Base para PCSPK y PCjr en v3 y v4, con cabecera de 4 bytes por GF_OLD_BUNDLE), asi que
el secuenciador, el paso a registros del AY y el VGM son los de V2/TOOLS/sound2vgm.py, importado tal cual. Aqui solo cambia el indice
(scumm3res.Index) y lo que hace falta para VAR_MUSIC_TIMER, que en v3 sale de otro sitio:

  v2   Player_V2Base::getMusicTimer devuelve el campo music_timer del canal 0, que el propio sonido escribe (0xFF con el parametro 46).
  v3   (_isV3Game) devuelve _music_timer, un contador del reproductor:
         - nextTick() (236 veces por segundo, siempre, haya sonido o no) hace  if (_music_timer_ctr++ >= _ticks_per_music_timer) { ctr = 0; _music_timer++ }
           o sea, +1 cada _ticks_per_music_timer + 1 ticks;
         - _ticks_per_music_timer vale 65535 al crear el reproductor y pasa a 125 la PRIMERA vez que algun sonido ejecuta 0xFF con el
           parametro 14 (la variable `tempo`, execute_cmd). No vuelve atras: dura hasta salir del juego, sea cual sea el sonido que suene despues;
         - chainSound() (cada vez que empieza un sonido, tambien al encadenar el siguiente) pone _music_timer a 0 pero NO _music_timer_ctr;
         - cada fotograma Sound::updateMusicTimer hace  VAR(VAR_MUSIC_TIMER) = int(_music_timer * timerFrequency / 240.0)  con
           timerFrequency = 1193182 / 5041 = 236,70 Hz en DOS v3 (ScummEngine::setTimerAndShakeFrequency); es decir, x 0,98625 truncando.
       Lo que necesita el motor del Z80: un contador de ticks de 236 Hz (4,72 por fotograma a 50 Hz) que corre siempre, el marcador global
       "tempo ya fijado" (periodo 126 ticks si esta, si no 65536), la puesta a 0 del valor al empezar un sonido y la conversion
       VAR = valor * 0,98625. SOUNDS.TXT dice que sonidos fijan el tempo (columna 6) y en que tick (columna 7).

Formato de SOUNDS.TXT (lineas '#' = comentarios): id prioridad reiniciable ticks inicio_del_bucle fija_tempo tick_del_tempo
  ticks = duracion en ticks de 236 Hz; inicio_del_bucle = -1 si acaba; fija_tempo = 1 si el sonido ejecuta 0xFF 14 (-1: no); tick_del_tempo
  = el primero en que lo hace.  Las cinco primeras columnas son las de sound2vgm.py.

Uso (desde SCUMM/V3/TOOLS):  python sound3vgm.py "../Indy Last Crusade" ../preview_hr/snd
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'V2', 'TOOLS'))
import scumm3res as R        # noqa: E402
import sound2vgm as S        # noqa: E402

TEMPO_FIELD = S.F['tempo']                     # array[7]: parametro 14 de 0xFF
TICKS_PER_TIMER = 125                          # _ticks_per_music_timer tras el primer tempo (el contador da +1 cada 126 ticks)
TIMER_SCALE = (1193182.0 / 5041.0) / 240.0     # VAR_MUSIC_TIMER = int(_music_timer * TIMER_SCALE)


class HookList(list):
    """Lista de un canal que avisa cuando el secuenciador escribe `tempo` (0xFF con el parametro 14)."""

    def __init__(self, sim, data):
        super().__init__(data)
        self.sim = sim

    def __setitem__(self, i, v):
        if i == TEMPO_FIELD and self.sim.tempo_tick is None:
            self.sim.tempo_tick = self.sim.now
        super().__setitem__(i, v)


class Sim3(S.Sim):
    def __init__(self, data, hulls, freqmod):
        self.tempo_tick = None
        self.now = 0
        super().__init__(data, hulls, freqmod)

    def chain(self, nr):
        super().chain(nr)
        self.ch = [HookList(self, c) for c in self.ch]


def render(data, hulls, freqmod):
    """Como sound2vgm.render, apuntando el tick en que el sonido fija el tempo. Devuelve (cambios, ticks, inicio del bucle, tick del tempo)."""
    sim = Sim3(data, hulls, freqmod)
    last, out, t = {}, [], 0
    seen = {}
    while sim.cur and t < S.MAX_TICKS:
        sim.now = t
        sim.tick()
        sig = (sim.cur, sim.retaddr, tuple(tuple(c) for c in sim.ch[:4]))
        if sig in seen:
            return out, t, seen[sig], sim.tempo_tick
        seen[sig] = t
        regs = S.ay_regs(sim)
        ch = {r: v for r, v in regs.items() if last.get(r) != v}
        if ch:
            out.append((t, ch))
            last.update(ch)
        t += 1
    return out, t, None, sim.tempo_tick


def main():
    args = sys.argv[1:]
    if len(args) < 2:
        print(__doc__)
        return 1
    d, outdir = args[0], args[1]
    os.makedirs(outdir, exist_ok=True)
    hulls, freqmod = S.load_tables()
    ix = R.Index(d)
    lines = ['# SOUNDS.TXT de v3 (sound3vgm.py): id prioridad reiniciable ticks inicio_del_bucle fija_tempo tick_del_tempo',
             '# VAR_MUSIC_TIMER: ver sound3vgm.py (contador de 236 Hz, +1 cada 126 ticks tras el primer tempo, a 0 al empezar cada sonido, x %.5f)' % TIMER_SCALE]
    done = skipped = 0
    for sid in range(len(ix.res['sound'])):
        b = ix.resource('sound', sid)
        if not b or len(b) < 22:
            skipped += 1
            continue
        hl = 4
        prio, restart = b[hl], b[hl + 1]
        offs = [struct.unpack_from('<H', b, hl + 10 + 2 * i)[0] for i in range(4)]
        if not any(offs) or any(o and o >= len(b) for o in offs):
            print('sonido %3d: sin bloque PCjr valido' % sid)
            skipped += 1
            continue
        try:
            ev, ticks, loop_at, tempo_tick = render(b, hulls, freqmod)
        except Exception as e:
            print('sonido %3d: no se puede convertir: %s: %s' % (sid, type(e).__name__, e))
            skipped += 1
            continue
        if not ev:
            print('sonido %3d: sin cambios en el AY' % sid)
            skipped += 1
            continue
        with open(os.path.join(outdir, 'SOUND%03d.VGM' % sid), 'wb') as f:
            f.write(S.vgm(ev, ticks))
        lines.append('%d %d %d %d %d %d %d' % (sid, prio, restart, ticks, -1 if loop_at is None else loop_at,
                                              0 if tempo_tick is None else 1, -1 if tempo_tick is None else tempo_tick))
        print('sonido %3d: prioridad %3d reiniciable %d  %6d ticks (%.1f s)%s  tempo %s  %d cambios' % (
            sid, prio, restart, ticks, ticks / S.TICK_HZ, ('  bucle desde el tick %d' % loop_at) if loop_at is not None else '',
            '-' if tempo_tick is None else 'tick %d' % tempo_tick, len(ev)))
        done += 1
    with open(os.path.join(outdir, 'SOUNDS.TXT'), 'w') as f:
        f.write('\n'.join(lines) + '\n')
    print('%d sonidos convertidos, %d sin convertir (de %d entradas del indice)' % (done, skipped, len(ix.res['sound'])))
    return 0


if __name__ == '__main__':
    sys.exit(main())

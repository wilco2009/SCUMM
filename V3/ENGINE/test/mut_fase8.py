#!/usr/bin/env python3
"""mut_fase8.py: mutaciones de la fase 8 (actores: ovd_act.asm; sonido: snd3.asm). Cada una cambia un trozo del Z80 en una copia del motor, lo monta y pasa la prueba que
le toca (actores: actscen.sh con escenas al azar contra sprites3.py; sonido: el arranque con sucesos de sonido contra el modelo) y mira si la detecta.
Uso: mut_fase8.py [filtro]      (salida: una linea por mutacion y el recuento; la copia vive en build/m8)"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENG = os.path.abspath(os.path.join(HERE, '..'))
B8 = os.path.join(HERE, 'build', 'm8')

# (descripcion, prueba, fichero, original, nuevo)    prueba: 'act' (actscen.sh) o 'snd' (arranque con sonidos)
M8 = [
    ('actores: el orden es de mayor a menor y', 'act', 'ovd_act.asm', '                cp d\n                jr c,ao_put\n                jr z,ao_put', '                cp d\n                jr nc,ao_put\n                jr z,ao_put'),
    ('actores: el empate pasa por delante', 'act', 'ovd_act.asm', '                cp d\n                jr c,ao_put\n                jr z,ao_put', '                cp d\n                jr c,ao_put'),
    ('actores: no mira la sala', 'act', 'ovd_act.asm', '                ld a,(CURROOM)\n                cp (ix+A_ROOM)\n                jr nz,ao_next', '                ld a,(CURROOM)\n                cp (ix+A_ROOM)'),
    ('actores: dibuja a los ocultos', 'act', 'ovd_act.asm', '                ld a,(ix+A_VIS)\n                or a\n                jr z,ao_next', '                ld a,(ix+A_VIS)\n                or a'),
    ('actores: dibuja a los que no tienen traje', 'act', 'ovd_act.asm', '                or (ix+A_COST+1)\n                jr z,ao_next', '                or (ix+A_COST+1)'),
    ('actores: no apaga los sprites sobrantes', 'act', 'ovd_act.asm', 'aq_off:         ld a,b\n                cp c\n                ret nc', 'ac_off:         ret'),
    ('actores: la direccion antigua 71 es izquierda', 'act', 'ovd_act.asm', '                cp 71\n                jr c,aod_up', '                cp 70\n                jr c,aod_up'),
    ('actores: la direccion 252 no es izquierda', 'act', 'ovd_act.asm', '                cp 252\n                jr c,aod_dn', '                cp 253\n                jr c,aod_dn'),
    ('actores: la direccion 256+ no es izquierda', 'act', 'ovd_act.asm', '                cp 34\n                jr c,aod_l', '                cp 33\n                jr c,aod_l'),
    ('actores: el fotograma de quieto no se usa', 'act', 'ovd_act.asm', '                ld a,(ix+A_STAND)       ; el fotograma pedido no esta en el traje: el de quieto', '                ld a,(ix+A_FRAME)       ; el fotograma pedido no esta en el traje: el de quieto'),
    ('actores: el contador no se reinicia', 'act', 'ovd_act.asm', '                ld (hl),a\n                inc hl\n                ld (hl),0\n                jr as_cnt', '                ld (hl),a\n                inc hl\n                jr as_cnt'),
    ('actores: la postura no usa los pasos', 'act', 'ovd_act.asm', '                srl h\n                rr l\n                srl h\n                rr l\n                srl h\n                rr l\n                ld a,l                  ; (el limite', '                srl h\n                rr l\n                srl h\n                rr l\n                ld a,l                  ; (el limite'),
    ('actores: no busca en el blob extra', 'act', 'ovd_act.asm', '                ret nc\n                ld hl,COLD_COSTDIR2\naq_cd:', '                ret\n                ld hl,COLD_COSTDIR2\naq_cd:'),
    ('actores: la animacion no suma la direccion', 'act', 'ovd_act.asm', '                ld a,(aq_dir)\n                ld e,a\n                ld d,0\n                add hl,de\n                ld (aq_anim),hl', '                ld e,0\n                ld d,0\n                add hl,de\n                ld (aq_anim),hl'),
    ('actores: x sin la camara', 'act', 'ovd_act.asm', '                ld de,(aq_cam)\n                or a\n                sbc hl,de\n                ld e,(iy+0)', '                ld de,0\n                or a\n                sbc hl,de\n                ld e,(iy+0)'),
    ('actores: y con la elevacion sumada', 'act', 'ovd_act.asm', '                ld e,(ix+A_ELEV)\n                ld d,(ix+A_ELEV+1)\n                or a\n                sbc hl,de', '                ld e,(ix+A_ELEV)\n                ld d,(ix+A_ELEV+1)\n                add hl,de'),
    ('actores: y sin HR_TOP', 'act', 'ovd_act.asm', '                ld de,HR_TOP+32\n                add hl,de', '                ld de,32\n                add hl,de'),
    ('actores: y sin ytop', 'act', 'ovd_act.asm', '                ld a,(hv_ytop)\n                ld e,a\n                ld d,0\n                or a\n                sbc hl,de\n                ld (aq_y32),hl', '                ld a,0\n                ld e,a\n                ld d,0\n                or a\n                sbc hl,de\n                ld (aq_y32),hl'),
    ('actores: dx sin signo', 'act', 'ovd_act.asm', '                ld e,(iy+0)\n                ld d,0\n                bit 7,e\n                jr z,acd_dx\n                dec d', '                ld e,(iy+0)\n                ld d,0\n                bit 7,e\n                jr z,acd_dx'),
    ('actores: el sprite 63 (cursor) se usa', 'act', 'ac_vars.inc', 'AC_MAXSPR       equ 63', 'AC_MAXSPR       equ 64'),
    ('actores: un actor que no cabe se dibuja a medias', 'act', 'ovd_act.asm', '                cp AC_MAXSPR+1\n                ret nc', '                cp AC_MAXSPR+9\n                ret nc'),
    ('actores: celda a la izquierda de la pantalla', 'act', 'ovd_act.asm', '                add hl,de\n                bit 7,h\n                jp nz,acd_skp2\n                ld (aq_cx),hl', '                add hl,de\n                ld (aq_cx),hl'),
    ('actores: celda a la derecha de la pantalla', 'act', 'ovd_act.asm', '                ld de,319\n                or a\n                sbc hl,de\n                jp nc,acd_skp2', '                ld de,400\n                or a\n                sbc hl,de\n                jp nc,acd_skp2'),
    ('actores: la mascara completa no es FF', 'act', 'ovd_act.asm', 'acd_ff:         ld a,$FF', 'acd_ff:         ld a,$7F'),
    ('actores: color uniforme solo en 7 filas', 'act', 'ovd_act.asm', '                call acd_fa\n                jr acd_skip', '                call acd_fa\n                ld (hl),0\n                jr acd_skip'),
    ('actores: sin recorte por arriba', 'act', 'ovd_act.asm', 'acl_neg:        neg', 'acl_neg:        ret\n                neg'),
    ('actores: sin recorte por abajo', 'act', 'ovd_act.asm', '                cp AC_YMAX-7\n                ret c', '                cp AC_YMAX-7\n                ret'),
    ('actores: el recorte de abajo deja una fila de mas', 'act', 'ovd_act.asm', '                sub AC_YMAX-8           ; A = 1..7: filas dentro = 8 - A', '                sub AC_YMAX-9           ; A = 1..7: filas dentro = 8 - A'),
    ('actores: el recorte de arriba deja una fila de mas', 'act', 'ovd_act.asm', 'acl_top:        ld b,a\n                ld a,AC_YMIN\n                sub b', 'acl_top:        ld b,a\n                ld a,AC_YMIN-1\n                sub b'),
    ('mascara: sin mascara de la sala', 'act', 'ovd_act.asm', '                ld a,(CURRD+15)\n                or a\n                ret z', '                ret'),
    ('mascara: ignora la mascara de la caja', 'act', 'ovd_act.asm', '                ld a,(hl)               ; mascara de la caja\n                or a\n                ret z', '                ld a,(hl)               ; mascara de la caja'),
    ('mascara: desplazamiento sin aplicar', 'act', 'ovd_act.asm', '                and 7                   ; antes se quitaba', '                and 0                   ; antes se quitaba'),
    ('mascara: la tira de la sala empieza una antes', 'act', 'ovd_act.asm', 'mk_s0:          ld (aq_s0),a', 'mk_s0:          dec a\n                ld (aq_s0),a'),
    ('mascara: la ventana no resta la fila del fotograma', 'act', 'ovd_act.asm', '                ld hl,(aq_ry)\n                ld a,h                  ; fila de la ventana por la que va el decodificador = -ry', '                ld hl,0\n                ld a,h                  ; fila de la ventana por la que va el decodificador = -ry'),
    ('mascara: un tramo de valor 0 se rellena', 'act', 'ovd_act.asm', '                ld a,c\n                or a\n                jr z,mk_run             ; valor 0: ya esta a ceros', '                ld a,c'),
    ('mascara: el fin del tramo no se acota a la ventana', 'act', 'ovd_act.asm', '                ld a,(aq_rh)\n                cp l\n                jr nc,mk_e1\nmk_cap:         ld a,(aq_rh)\n                ld l,a', '                jr mk_e1\nmk_cap:         ld a,(aq_rh)\n                ld l,a'),
    ('mascara: el inicio negativo no se acota', 'act', 'ovd_act.asm', '                bit 7,d\n                jr z,mk_s1\n                ld de,0                 ; inicio = max(inicio, 0)', '                bit 7,d\n                jr z,mk_s1'),
    ('mascara: la celda no usa la tira siguiente', 'act', 'ovd_act.asm', '                pop iy\n                ld bc,64\n                add iy,bc', '                pop iy\n                ld bc,0\n                add iy,bc'),
    ('mascara: la fila de la celda no cuenta', 'act', 'ovd_act.asm', '                add a,a                 ; fila de la celda en la ventana\n', ''),
    ('cache: la firma no incluye la camara', 'act', 'ovd_act.asm', 'aq_hash:        ld hl,(aq_cam)', 'aq_hash:        ld hl,0'),
    ('cache: la firma no incluye la x', 'act', 'ovd_act.asm', '                ld a,(ix+A_X)\n                call ach\n                ld a,(ix+A_X+1)\n                call ach', '                ld a,0\n                call ach\n                ld a,0\n                call ach'),
    ('cache: la firma no incluye el fotograma', 'act', 'ovd_act.asm', '                ld a,(aq_fr)\n                call ach\n                ld a,(aq_fr+1)\n                call ach', '                ld a,0\n                call ach\n                ld a,0\n                call ach'),
    ('cache: la marca de la entrada no se comprueba', 'act', 'ovd_act.asm', '                or a\n                sbc hl,de\n                pop hl\n                jr nz,acc_miss\n                ld e,(hl)', '                or a\n                sbc hl,de\n                pop hl\n                ld e,(hl)'),
    ('cache: no comprueba el primer sprite', 'act', 'ovd_act.asm', '                cp (hl)                 ; el mismo primer sprite\n                jr nz,acc_miss', '                cp (hl)                 ; el mismo primer sprite'),
    ('sonido: la prioridad igual no desplaza al actual', 'snd', 'snd3.asm', '                cp (hl)                 ; cprio <= prio: el nuevo pasa a sonar\n                jr z,ss_chain', '                cp (hl)                 ; cprio <= prio: el nuevo pasa a sonar'),
    ('sonido: el actual de mas prioridad no manda', 'snd', 'snd3.asm', '                jr z,ss_chain\n                jr nc,ss_cand\nss_chain:', '                jr z,ss_chain\nss_chain:'),
    ('sonido: el desplazado no pasa a la cola', 'snd', 'snd3.asm', 'ss_cand:        ld a,(sd_qn)            ; nr != _current_nr', 'ss_cand:        ret\n                ld a,(sd_qn)            ; nr != _current_nr'),
    ('sonido: el desplazado no reiniciable pasa a la cola', 'snd', 'snd3.asm', '                ld a,(sd_qr)\n                or a\n                ret z\n                ld a,(sd_next)', '                ld a,(sd_next)'),
    ('sonido: la cola no mira la prioridad', 'snd', 'snd3.asm', '                ld a,(sd_nprio)\n                ld hl,sd_qp\n                cp (hl)\n                jr z,ss_q\n                ret nc', '                jr ss_q'),
    ('sonido: stopSound no quita al de la cola', 'snd', 'snd3.asm', 'sp_c:           ld hl,sd_cur', 'sp_c:           jr sp_x\nsp_x:           ld hl,sd_cur'),
    ('sonido: stopSound del actual no encadena el siguiente', 'snd', 'snd3.asm', '                ld (sd_cur),a\n                ; sigue en sd_chain_next', '                ld (sd_cur),a\n                ret'),
    ('sonido: chainSound no pone a 0 el temporizador', 'snd', 'snd3.asm', '                ld hl,0\n                ld (snd_mt),hl          ; _music_timer = 0', '                ld hl,(snd_mt)\n                ld (snd_mt),hl          ; _music_timer = 0'),
    ('sonido: el tempo no se fija', 'snd', 'snd3.asm', '                ld hl,125\n                ld (snd_tpm),hl         ; el sonido fija el tempo', '                ld hl,65535\n                ld (snd_tpm),hl         ; el sonido fija el tempo'),
    ('sonido: el bucle se acaba', 'snd', 'snd3.asm', 'sc_dur:         ld (sd_left),hl', 'sc_dur:         ld hl,(sd_nd)\n                ld (sd_left),hl'),
    ('sonido: el fin de un sonido no encadena', 'snd', 'snd3.asm', 'st_end:         xor a\n                ld (sd_cur),a\n                call sd_chain_next', 'st_end:         xor a\n                ld (sd_cur),a'),
    ('sonido: el contador de ticks no se reinicia', 'snd', 'snd3.asm', '                ld hl,0\n                ld (snd_ctr),hl\n                ld hl,(snd_mt)\n                inc hl', '                ld hl,(snd_ctr)\n                ld (snd_ctr),hl\n                ld hl,(snd_mt)\n                inc hl'),
    ('sonido: 60 en lugar de 50 ticks por fotograma', 'snd', 'snd3.asm', '                ld de,50\n                or a\n                sbc hl,de\n                jr c,st_t', '                ld de,60\n                or a\n                sbc hl,de\n                jr c,st_t'),
    ('sonido: el factor de VAR_MUSIC_TIMER es 1', 'snd', 'snd3.asm', '                ld hl,(snd_mt)\n                or a\n                sbc hl,de\n                ld (VAR_MUSIC_TIMER),hl', '                ld hl,(snd_mt)\n                ld (VAR_MUSIC_TIMER),hl'),
    ('sonido: getSoundStatus no mira la cola', 'snd', 'snd3.asm', '                ld hl,sd_next\n                cp (hl)\n                ret nz\nsq_y:', '                ret\nsq_y:'),
    ('sonido: stopAllSounds no vacia la cola', 'snd', 'snd3.asm', '                ld (sd_cur),a\n                ld (sd_next),a\n                ret', '                ld (sd_cur),a\n                ret'),
    ('sonido: el bucle no se avisa al MCU', 'snd', 'snd3.asm', 'sc_l0:          call mcu_send\n                ld hl,(PF_SNDTPL)', 'sc_l0:          ld hl,(PF_SNDTPL)'),
]

# 10e: mutaciones equivalentes (no pueden cambiar nada que se vea): nombre -> motivo. No se pasan salvo con MUT_EQUIV=1.
EQUIV8 = {
    'actores: un actor que no cabe se dibuja a medias':
        'la pasada 1 ya reparte: los normales suman aq_tot <= 63 y la pasada 2 dibuja solo esos, asi que aq_n + celdas <= aq_tot <= 63 siempre (la comprobacion de aq_draw es de defensa)',
    'mascara: un tramo de valor 0 se rellena':
        'mk_strip ya deja a cero las aq_rh filas de cada tira y el relleno no sale de [inicio, min(fin, aq_rh)): rellenar con 0 no cambia nada',
    'actores: celda a la izquierda de la pantalla':
        'una x de celda negativa (bit 7 de H) es >= 319 sin signo y la salta igual la comprobacion siguiente (sbc hl,319 / jp nc,acd_skp2)',
}


def run(cmd, cwd, env=None):
    return subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True, env=env)


V3 = os.path.abspath(os.path.join(ENG, '..'))


def prepare(w):
    """La copia del motor de un trabajador: V3/ENGINE_m8_<w> (hermana de ENGINE: los scripts usan ../../TOOLS, ../../preview_hr...)."""
    d = os.path.join(V3, 'ENGINE_m8_%d' % w)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for f in os.listdir(ENG):
        p = os.path.join(ENG, f)
        if os.path.isfile(p):
            shutil.copy(p, d)
    os.makedirs(os.path.join(d, 'test'))
    for f in ('spr_run.sh', 'actscen.sh', 'spr_prep.inc', 'mk_actscen.py', 'check_spr.py', 'mk_events.py', 'compare_boot.py', 'mk_digest_boot.py', 'digest_boot.inc', 'test_scumm.cpp',
              'build_boot.sh', 'check_hr.py', 'ev_snd.txt'):
        shutil.copy(os.path.join(HERE, f), os.path.join(d, 'test', f))
    os.makedirs(os.path.join(d, 'test', 'build'))
    for f in ('z80.o', 'z80_ops.o', 'test_scumm.exe'):
        if os.path.exists(os.path.join(HERE, 'build', f)):
            shutil.copy(os.path.join(HERE, 'build', f), os.path.join(d, 'test', 'build', f))
    shutil.copytree(os.path.join(HERE, 'build', 'sdboot'), os.path.join(d, 'test', 'build', 'sdboot'))
    return d


def one(args):
    w, (desc, kind, fn, old, new) = args
    d = DIRS[w]
    src = open(os.path.join(ENG, fn), encoding='utf-8', newline='').read().replace(chr(13) + chr(10), chr(10))
    if old not in src:
        return desc, None
    open(os.path.join(d, fn), 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))
    try:
        if kind == 'act':
            caught = False
            for seed, room in ((3, 7), (4, 77), (5, 12), (6, 28)):               # salas con mascara de profundidad (28 %, 38 %), alta con mascara (192 lineas) y con cajas con mascara
                r = run('sh actscen.sh %d %d 8' % (seed, room), os.path.join(d, 'test'))
                out = r.stdout + r.stderr
                if r.returncode != 0 or 'con diferencias 0' not in out:
                    caught = True
                    break
        else:
            r = run('sh build_boot.sh 700 "../../Indy Last Crusade" ev_snd.txt', os.path.join(d, 'test'))
            out = r.stdout + r.stderr
            caught = 'DISTINT' in out or 'distintos: 0' not in out or 'iguales' not in out
    finally:
        open(os.path.join(d, fn), 'w', encoding='utf-8', newline='').write(src)
    return desc, caught


DIRS = {}


def main():
    import concurrent.futures as cf
    import queue
    filt = sys.argv[1] if len(sys.argv) > 1 else ''
    nw = int(os.environ.get('MUT_WORKERS', '4'))
    for w in range(nw):
        DIRS[w] = prepare(w)
    free = queue.Queue()
    for w in range(nw):
        free.put(w)
    todo = [m for m in M8 if not filt or any(x in m[0] for x in filt.split(','))]
    neq = 0
    if os.environ.get('MUT_EQUIV') != '1':                  # 10e: las equivalentes no se pasan (MUT_EQUIV=1 para pasarlas)
        for m in todo:
            if m[0] in EQUIV8:
                print('%-70s equivalente: %s' % (m[0], EQUIV8[m[0]]), flush=True)
                neq += 1
        todo = [m for m in todo if m[0] not in EQUIV8]
    kinds = sorted(set(m[1] for m in todo))
    todo = [('(sin mutar, %s: tiene que salir sin detectar)' % k, k, 'ovd_act.asm', '', '') for k in kinds] + todo   # 10e: control

    def job(m):
        w = free.get()
        try:
            return one((w, m))
        finally:
            free.put(w)
    det = tot = 0
    with cf.ThreadPoolExecutor(nw) as ex:
        for desc, caught in ex.map(job, todo):
            if caught is None:
                print('NO ENCUENTRO: %s' % desc, flush=True)
                continue
            if desc.startswith('(sin mutar'):
                print('%-70s %s' % (desc, 'BIEN' if not caught else '*** LA PRUEBA FALLA SIN MUTAR: las cifras no valen ***'), flush=True)
                continue
            tot += 1
            det += 1 if caught else 0
            print('%-70s %s' % (desc, 'detectada' if caught else '*** SIN DETECTAR ***'), flush=True)
    print('mutaciones de la fase 8: %d detectadas de %d (equivalentes, sin pasar: %d)' % (det, tot, neq))
    for w in DIRS:
        shutil.rmtree(DIRS[w], ignore_errors=True)


if __name__ == '__main__':
    main()

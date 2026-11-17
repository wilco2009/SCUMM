#!/usr/bin/env python3
"""mut_fase9.py (10e): mutaciones de ovc9.asm (guardar y cargar, fase 9; overlay C, solo en el programa: el nucleo de pruebas no guarda).
Cada mutacion cambia un trozo de ovc9.asm en una copia del motor, vuelve a montar SOLO el overlay C (scumm.sym no cambia, asi que lo que da el modelo y los
sucesos de entrada valen para todas) y pasa las pruebas de savetest.sh hasta que una la detecta: el resumen D de cada fotograma y las ordenes de sonido contra
el modelo (vmmodel3 boot-core con "OPT guardar 1") y, en las que cruzan salas o abren el dialogo, check_hr.py contra lo que daba sin mutar.
Antes de nada pasa las pruebas sin mutar (que tienen que dar todo igual) y guarda lo esperado en build/m9/.
Uso: python mut_fase9.py [filtro]   (filtro: palabras separadas por comas; MUT_WORKERS=4 copias en V3/ENGINE_m9_<n>, se borran al acabar; MUT_EQUIV=1 pasa tambien las equivalentes)"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ENG = os.path.abspath(os.path.join(HERE, '..'))
V3 = os.path.abspath(os.path.join(ENG, '..'))
B9 = os.path.join(HERE, 'build', 'm9')
GAME = '../../Indy Last Crusade'
L = '\n                '

# las pruebas de savetest.sh: (nombre, fotogramas, sucesos, entorno extra, check_hr)
CASES = [
    ('guardar300', 700, 'ev_save.txt', {}, False),
    ('cruzando', 900, 'ev_save2.txt', {}, True),
    ('sintetico', 400, 'ev_save3.txt', {'SCUMM_SYNTH': os.path.join(HERE, 'synth_save.hex')}, False),
    ('dialogoF5', 1500, 'ev_f5.txt', {}, True),
    ('matriz', 1350, 'ev_f5hw.txt', {'EVF_NOPOKE': '1', 'ZX81_MATRIX': '1300:SHIFT+S,1310:'}, False),
    ('cargarOK', 2600, 'ev_f5j.txt', {}, True),
    # 10e: guardar dentro del script sintetico y cargar desde el bucle principal (el script sigue justo detras del opcode de guardar: update_ptr)
    ('cargarfuera', 400, 'ev_save4.txt', {'SCUMM_SYNTH': os.path.join(HERE, 'synth_save.hex')}, False),
    # 10e: cargarOK y despues un guardado (DBG_SAVE) en la ranura 5, cuyo nombre esta vacio: el nombre que se leyo antes no puede quedar en el fichero
    ('nombrevacio', 2600, 'ev_save6.txt', {}, True),
    # 10e: el script sintetico con la SD que rechaza las escrituras (TS_WRFAIL, arnes y modelo): guardar da 2 y cargar despues, 5
    ('sdllena', 400, 'ev_save3.txt', {'SCUMM_SYNTH': os.path.join(HERE, 'synth_save.hex'), 'TS_WRFAIL': '1'}, False),
]

# (descripcion, original, nuevo); todas en ovc9.asm
M9 = [
    ('numero de ranuras 99', 'ld hl,100' + L + 'ret z                   ; 0: numero de ranuras', 'ld hl,99' + L + 'ret z                   ; 0: numero de ranuras'),
    ('unidad 4', 'ld l,3' + L + 'ret z                   ; 1: unidad', 'ld l,4' + L + 'ret z                   ; 1: unidad'),
    ('el nombre del fichero: unidades mal', "add a,10+'0'", "add a,9+'0'"),
    ('cabecera: sin la direccion de ev_handler', 'ld hl,ev_handler' + L + 'ld (SL_HDR+16),hl', 'ld hl,ev_handler' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('el nombre de la partida sale de la cadena siguiente', 'ld a,(sl_slot)' + L + 'add a,9' + L + 'cp NSTR', 'ld a,(sl_slot)' + L + 'add a,10' + L + 'cp NSTR'),
    ('el nombre de la partida no se borra antes', 'sl_getname:     ld hl,SL_NM' + L + 'ld de,SL_NM+1' + L + 'ld bc,31' + L + 'ld (hl),0' + L + 'ldir',
     'sl_getname:     ld hl,SL_NM' + L + 'ld de,SL_NM+1' + L + 'ld bc,31'),
    ('el nombre de la partida: 30 caracteres', 'ld b,31' + '\nsgn_l:', 'ld b,30' + '\nsgn_l:'),
    ('guardar sin update_ptr', 'sl_save:        call update_ptr', 'sl_save:        nop' + L + 'nop' + L + 'nop'),
    ('guardar: el error de escritura no cuenta', 'ld a,(wr_err)' + L + 'or a' + L + 'ret z' + L + 'ld hl,2', 'ld a,0' + L + 'or a' + L + 'ret z' + L + 'ld hl,2'),
    ('guardar: el bloque 7 sin su ultimo byte', 'sls_b7:         ld hl,$E000' + L + 'ld bc,$2000', 'sls_b7:         ld hl,$E000' + L + 'ld bc,$1FFF'),
    ('guardar: OBJCLS de la pagina que este', 'call cls_open' + L + 'ld hl,WINDOW' + L + 'ld bc,SL_CLS' + L + 'call sl_wr', 'nop' + L + 'nop' + L + 'nop' + L + 'ld hl,WINDOW' + L + 'ld bc,SL_CLS' + L + 'call sl_wr'),
    ('sin el monton de cadenas', 'defw STRHEAP, STRMAX', 'defw STRHEAP, 0'),
    ('sin el reproductor de sonido', 'defw snd_mt, SL_SNDV', 'defw snd_mt, 0'),
    ('sin MSGBUF', 'defw MSGBUF, MSG_MAX', 'defw MSGBUF, 0'),
    ('sl_live: RESV se restaura', 'defw RESV' + '\n                defb 2', 'defw RESV' + '\n                defb 0'),
    ('sl_live: DELTA se restaura', 'sl_live:        defw DELTA' + '\n                defb 1', 'sl_live:        defw DELTA' + '\n                defb 0'),
    ('sl_live: INEV se restaura', 'defw INEV' + '\n                defb 17', 'defw INEV' + '\n                defb 0'),
    ('sl_live: SC se restaura', 'defw SC' + '\n                defb 24', 'defw SC' + '\n                defb 0'),
    ('sl_live: TOPSP y DS_SP se restauran', 'defw TOPSP              ; TOPSP y DS_SP' + '\n                defb 4', 'defw TOPSP              ; TOPSP y DS_SP' + '\n                defb 0'),
    ('sl_live: RAI se restaura', 'defw RAI' + '\n                defb 1', 'defw RAI' + '\n                defb 0'),
    ('existe: 6 y 7 cruzados', 'ld hl,7' + L + 'ret z' + L + 'call f_close' + L + 'ld hl,6', 'ld hl,6' + L + 'ret z' + L + 'call f_close' + L + 'ld hl,7'),
    ('cargar: no existe da 3', 'ld hl,5' + L + 'ret z' + L + 'ld (sl_h),a' + L + 'ld a,CMD_FSTAT', 'ld hl,3' + L + 'ret z' + L + 'ld (sl_h),a' + L + 'ld a,CMD_FSTAT'),
    ('cargar: el tamano no se comprueba', 'sbc hl,de' + L + 'jp nz,sll_bad' + L + 'call sl_hdr', 'sbc hl,de' + L + 'nop' + L + 'nop' + L + 'nop' + L + 'call sl_hdr'),
    ('cargar: la cabecera no se comprueba', 'sll_c:          ld a,(de)' + L + 'cp (hl)' + L + 'jp nz,sll_bad', 'sll_c:          ld a,(de)' + L + 'cp (hl)' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('cargar: lo que no se restaura no vuelve a su sitio', 'ld hl,sl_live           ; lo que no se restaura vuelve a su sitio', 'jp sun_e' + L + 'ld hl,sl_live           ; lo que no se restaura vuelve a su sitio'),
    ('cargar: sin aq_init', 'sun_e:          call aq_init', 'sun_e:          nop' + L + 'nop' + L + 'nop'),
    ('cargar: sin gt_load', 'call gt_load            ; 10d', 'nop' + L + 'nop' + L + 'nop            ; 10d'),
    ('cargar: la sala no se vuelve a pintar', 'ld a,EV_ROOM_LOAD' + L + 'call ev_handler', 'ld a,EV_ROOM_LOAD' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('cargar: sin la paleta', 'ld a,EV_PALETTE' + L + 'call ev_handler', 'ld a,EV_PALETTE' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('cargar: el texto de arriba no se borra', 'ld a,EV_TEXT' + L + 'call ev_handler', 'ld a,EV_TEXT' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('cargar: los verbos no se recomponen', 'ld a,EV_VERB            ; verbos y objetos se vuelven a componer' + L + 'call ev_handler',
     'ld a,EV_VERB            ; verbos y objetos se vuelven a componer' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('cargar: los objetos no se recomponen', 'ld a,EV_OBJSTATE' + L + 'call ev_handler' + L + 'call sl_snd', 'ld a,EV_OBJSTATE' + L + 'nop' + L + 'nop' + L + 'nop' + L + 'call sl_snd'),
    ('cargar: el sonido no vuelve a empezar', 'call sl_snd' + L + 'ld a,(CUR)', 'nop' + L + 'nop' + L + 'nop' + L + 'ld a,(CUR)'),
    ('cargar: el sonido no para', 'sl_snd:         call sd_stopvgm', 'sl_snd:         nop' + L + 'nop' + L + 'nop'),
    ('cargar: el script sigue por el opcode de guardar', 'jr z,sll_ls             ; (script 9)', 'jr sll_ls               ; (script 9)'),
    ('cargar: sin load_slot', 'sll_ls:         ld a,(CUR)' + L + 'call load_slot', 'sll_ls:         ld a,(CUR)' + L + 'nop' + L + 'nop' + L + 'nop'),
    ('cargar: el resultado es 4', 'sll_done:       ld hl,3', 'sll_done:       ld hl,4'),
    ('nombres: ranura = id - a', 'sub c' + L + 'inc a                   ; ranura = id - a + 1', 'sub c' + L + 'nop                     ; ranura = id - a + 1'),
    ('nombres: la arroba no se cambia', 'cp 64' + L + 'jr nz,slp_ok', 'cp 65' + L + 'jr nz,slp_ok'),
    ('nombres: la z se cambia', 'cp 123' + L + 'jr nc,slp_sub', 'cp 122' + L + 'jr nc,slp_sub'),
    ('nombres: una partida que no existe deja la cadena', 'slp_none:        call sl_strp' + L + 'ret z' + L + 'ld (hl),0', 'slp_none:        call sl_strp' + L + 'ret z' + L + 'nop'),
    ('nombres: un caracter mas', 'ld a,c' + L + 'sub 2' + L + 'jr nc,slp_n', 'ld a,c' + L + 'sub 1' + L + 'jr nc,slp_n'),
    ('escribir: trozos de CHUNK + 1', 'fwn_full:       ld de,CHUNK', 'fwn_full:       ld de,CHUNK+1'),
]

# 10e: mutaciones equivalentes (con los datos de Indy3 y el MCU no pueden cambiar nada que se vea): nombre -> motivo. No se pasan salvo con MUT_EQUIV=1.
EQUIV9 = {
    'el nombre de la partida: 30 caracteres':
        'el dialogo de Indy3 corta el nombre a 22 letras (probado con 33: ev_dialogo2.txt guarda "ABCDEFGHIJKLMNOPQRSTUV"); nunca llega a 31',
    'numero de ranuras 99':
        'Indy3 nunca pide la orden $00: sus saveLoadGame usan $20 (constante, script local 203 de la sala 14) y $40/$80/$C0 + ranura (script 9 y local 205 de la sala 14)',
}


def run(cmd, cwd, env=None):
    e = dict(os.environ)
    if env:
        e.update(env)
    return subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True, env=e)


def baseline():
    """Pasa las 6 pruebas sin mutar con build_boot.sh (modelo incluido) y guarda en build/m9/<prueba>/ lo esperado, los sucesos y la salida de check_hr."""
    os.makedirs(B9, exist_ok=True)
    ok = True
    for name, n, evf, env, hr in CASES:
        d = os.path.join(B9, name)
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(os.path.join(HERE, 'build', 'sdboot')):
            if f.startswith('SAVE') and f.endswith('.SAV'):
                os.remove(os.path.join(HERE, 'build', 'sdboot', f))
        r = run('sh build_boot.sh %d "%s" %s' % (n, GAME, evf), HERE, env)
        out = r.stdout + r.stderr
        good = 'distintos: 0' in out and 'iguales' in out and 'DISTINT' not in out and r.returncode == 0
        hrl = ''
        if hr:
            h = run('python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx', HERE)
            hrl = (h.stdout.strip().splitlines() or [''])[-1]
        print('sin mutar %-12s %s %s' % (name, 'bien' if good else '*** NO DA LO MISMO QUE EL MODELO ***', hrl), flush=True)
        ok = ok and good
        for f in ('boot_expected.txt', 'boot_snd_expected.txt'):
            shutil.copy(os.path.join(HERE, 'build', f), os.path.join(d, f))
        shutil.copy(os.path.join(HERE, 'build', 'sdboot', 'DATA', 'DATA.BIN'), os.path.join(d, 'DATA.BIN'))
        poke = ''
        if not env.get('EVF_NOPOKE'):
            poke = run('python -I mk_events.py %s prog/scumm.sym' % evf, HERE).stdout.strip()
        open(os.path.join(d, 'poke.txt'), 'w').write(poke)
        open(os.path.join(d, 'hr.txt'), 'w').write(hrl)
        for f in os.listdir(d):                                 # 10e: los ficheros de partida que deja la prueba (nombres y bytes)
            if f.startswith('SAVE'):
                os.remove(os.path.join(d, f))
        sdb = os.path.join(HERE, 'build', 'sdboot')
        for f in os.listdir(sdb):
            if f.startswith('SAVE') and f.endswith('.SAV'):
                shutil.copy(os.path.join(sdb, f), os.path.join(d, f))
    return ok


def prepare(w):
    """La copia de un trabajador: V3/ENGINE_m9_<w> (hermana de ENGINE: check_hr usa ../../preview_hr)."""
    d = os.path.join(V3, 'ENGINE_m9_%d' % w)
    if os.path.exists(d):
        shutil.rmtree(d)
    os.makedirs(d)
    for f in os.listdir(ENG):
        p = os.path.join(ENG, f)
        if os.path.isfile(p):
            shutil.copy(p, d)
    t = os.path.join(d, 'test')
    os.makedirs(os.path.join(t, 'build'))
    shutil.copytree(os.path.join(HERE, 'prog'), os.path.join(t, 'prog'))
    for f in ('compare_boot.py', 'check_hr.py'):
        shutil.copy(os.path.join(HERE, f), t)
    shutil.copy(os.path.join(HERE, 'build', 'test_scumm.exe'), os.path.join(t, 'build'))
    shutil.copytree(os.path.join(HERE, 'build', 'sdboot'), os.path.join(t, 'build', 'sdboot'))
    return d


def one(w, m):
    desc, old, new = m
    d = DIRS[w]
    if not old:                                                 # control: sin mutar (old = new = '')
        old = new = ';'
    t = os.path.join(d, 'test')
    src = open(os.path.join(ENG, 'ovc9.asm'), encoding='utf-8', newline='').read().replace('\r\n', '\n')
    if old not in src:
        return desc, None, ''
    open(os.path.join(d, 'ovc9.asm'), 'w', encoding='utf-8', newline='').write(src.replace(old, new, 1))
    if os.path.exists(os.path.join(t, 'prog', 'ovlc.bin')):
        os.remove(os.path.join(t, 'prog', 'ovlc.bin'))
    r = run('pasmo -I test/prog ovlc.asm test/prog/ovlc.bin test/prog/ovlc.sym', d)
    if not os.path.exists(os.path.join(t, 'prog', 'ovlc.bin')) or r.returncode:
        open(os.path.join(d, 'ovc9.asm'), 'w', encoding='utf-8', newline='').write(src)
        return desc, None, 'no ensambla: ' + (r.stdout + r.stderr).strip()[-120:]
    sd = os.path.join(t, 'build', 'sdboot')
    shutil.copy(os.path.join(t, 'prog', 'ovlc.bin'), os.path.join(sd, 'DATA', 'OVLC.BIN'))
    try:
        for name, n, evf, env, hr in CASES:
            c = os.path.join(B9, name)
            for f in os.listdir(sd):
                if f.startswith('SAVE') and f.endswith('.SAV'):
                    os.remove(os.path.join(sd, f))
            shutil.copy(os.path.join(c, 'DATA.BIN'), os.path.join(sd, 'DATA', 'DATA.BIN'))
            e = {'TS_NOSTOP': '1', 'TS_MODELDELTA': '1', 'TS_DIGEST': 'build/boot_actual.txt'}
            e.update({k: v for k, v in env.items() if k != 'SCUMM_SYNTH'})
            poke = open(os.path.join(c, 'poke.txt')).read().strip()
            if poke:
                e['TS_POKE'] = poke
            for f in ('build/boot_actual.txt', 'build/boot_dump.bin'):
                if os.path.exists(os.path.join(t, f)):
                    os.remove(os.path.join(t, f))
            ee = dict(os.environ)
            ee.update(e)
            r = subprocess.run([os.path.join(t, 'build', 'test_scumm.exe'), 'prog/scumm.bin', 'prog/scumm.sym', 'build/sdboot', str(n), 'build/boot_dump.bin'],
                               cwd=t, capture_output=True, text=True, env=ee)
            if r.returncode or not os.path.exists(os.path.join(t, 'build', 'boot_actual.txt')):
                return desc, True, name + ' (el arnes falla)'
            cb = run('python -I compare_boot.py "%s" build/boot_actual.txt 0' % os.path.join(c, 'boot_expected.txt'), t)
            if cb.returncode:
                return desc, True, name + ': ' + cb.stdout.strip().splitlines()[0]
            snd_a = [ln for ln in r.stdout.replace('\r', '').splitlines() if ln.startswith('SND ')]
            snd_e = [ln for ln in open(os.path.join(c, 'boot_snd_expected.txt')).read().replace('\r', '').splitlines() if ln.strip()]
            if snd_a != snd_e:
                return desc, True, name + ': ordenes de sonido distintas'
            exp_sav = sorted(f for f in os.listdir(c) if f.startswith('SAVE'))
            got_sav = sorted(f for f in os.listdir(sd) if f.startswith('SAVE') and f.endswith('.SAV'))
            if exp_sav != got_sav:
                return desc, True, name + ': ficheros de partida %s (sin mutar %s)' % (got_sav, exp_sav)
            for f in exp_sav:
                if open(os.path.join(c, f), 'rb').read() != open(os.path.join(sd, f), 'rb').read():
                    return desc, True, name + ': el contenido de ' + f
            if hr:
                h = run('python -I check_hr.py build/boot_dump.bin prog/scumm.sym ../../preview_hr/gfx', t)
                hl = (h.stdout.strip().splitlines() or [''])[-1]
                if hl != open(os.path.join(c, 'hr.txt')).read().strip():
                    return desc, True, name + ': check_hr ' + hl
        return desc, False, ''
    finally:
        open(os.path.join(d, 'ovc9.asm'), 'w', encoding='utf-8', newline='').write(src)


DIRS = {}


def main():
    import concurrent.futures as cf
    import queue
    filt = sys.argv[1] if len(sys.argv) > 1 else ''
    todo = [m for m in M9 if not filt or any(x in m[0] for x in filt.split(','))]
    neq = 0
    if os.environ.get('MUT_EQUIV') != '1':
        for m in todo:
            if m[0] in EQUIV9:
                print('%-60s equivalente: %s' % (m[0], EQUIV9[m[0]]), flush=True)
                neq += 1
        todo = [m for m in todo if m[0] not in EQUIV9]
    if not os.environ.get('MUT9_NOBASE') or not os.path.exists(os.path.join(B9, CASES[-1][0], 'hr.txt')):
        if not baseline():
            print('LAS PRUEBAS SIN MUTAR NO DAN LO MISMO QUE EL MODELO: no vale la pena seguir')
            return 2
    nw = int(os.environ.get('MUT_WORKERS', '4'))
    for w in range(nw):
        DIRS[w] = prepare(w)
    desc, caught, why = one(0, ('(sin mutar: tiene que salir sin detectar)', '', ''))      # control en la copia: sin mutar no puede detectar nada
    print('%-60s %s' % (desc, 'BIEN' if not caught else '*** LA PRUEBA FALLA SIN MUTAR (%s): las cifras no valen ***' % why), flush=True)
    if caught or caught is None:
        for w in DIRS:
            shutil.rmtree(DIRS[w], ignore_errors=True)
        return 2
    free = queue.Queue()
    for w in range(nw):
        free.put(w)

    def job(m):
        w = free.get()
        try:
            return one(w, m)
        finally:
            free.put(w)
    det = tot = 0
    missed = []
    with cf.ThreadPoolExecutor(nw) as ex:
        for desc, caught, why in ex.map(job, todo):
            if caught is None:
                print('NO ENCUENTRO O NO ENSAMBLA: %s %s' % (desc, why), flush=True)
                missed.append(desc + ' (patron)')
                continue
            tot += 1
            det += 1 if caught else 0
            if not caught:
                missed.append(desc)
            print('%-60s %s' % (desc, ('detectada (%s)' % why) if caught else '*** SIN DETECTAR ***'), flush=True)
    print('mutaciones de ovc9.asm: %d detectadas de %d (equivalentes, sin pasar: %d)' % (det, tot, neq))
    for m in missed:
        print('  sin detectar:', m)
    for w in DIRS:
        shutil.rmtree(DIRS[w], ignore_errors=True)
    return 1 if missed else 0


if __name__ == '__main__':
    sys.exit(main())

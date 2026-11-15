#!/usr/bin/env python3
"""Genera digest_boot.inc (el resumen por fotograma D ... de CoreVM.digest, calculado desde la memoria del Z80) a partir de test_vm.cpp, para que test_scumm.cpp
(el programa completo, fase 5b) calcule EXACTAMENTE lo mismo que el arnes del nucleo. Se vuelve a generar si cambia digest() en test_vm.cpp:
    python mk_digest_boot.py"""
import os
import re

here = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(here, 'test_vm.cpp'), encoding='utf-8').read()


def cut(a, b):
    i = src.index(a)
    j = src.index(b, i)
    return src[i:j]


# 1. las direcciones (static int ...) y su asignacion en main
decl = cut('// direcciones (de vm.sym)', 'static const int TRAP')
decl = decl.replace('static int API_INIT, API_RUN_EXT, API_RUN_OBJECT, API_RUN_SCRIPT, API_FRAME, API_SET_ROOM, API_ABORT, API_LOAD_ROOM, API_SENTENCE;\n', '')
decl = decl.replace('static int ES_GO, ES_LOOP;\n', '')
m = src.index('  VARS = S("VARS");')
n = src.index('  API_INIT')
assign = src[m:n]
assign = assign.replace('  TK_IN', '  //')
# 2. crc16
crc = cut('static uint16_t crc16', '// ---------------------------------------------------------------- el anfitrion simulado')
# 3. del slot_base_off al final de digest()
body = cut('static int slot_base_off', 'static void flush_trace')
body = body.replace('ram[128 + tp]', 'pageptr(tp)').replace('ram[128 + page]', 'pageptr(page)')
body = body.replace('if (num == 10001) return ptr - d16(OFF_ROOMDIR + 32 * exit_room + 4);', 'if (num == 10001) return ptr - excd_start(page, ptr);')
# el digest de test_vm lee ram[CLS_PG] (OBJCLS en la pagina fria): en el programa tambien (la carga load_data)
out = '''// GENERADO por mk_digest_boot.py a partir de test_vm.cpp (no editar): el resumen por fotograma de CoreVM.digest, calculado desde la memoria del Z80, para el arnes del
// programa completo (test_scumm.cpp, TS_DIGEST). Las paginas de datos se leen de DATA.BIN (pageptr), no de la RAM (el programa las trae por demanda).
static std::vector<uint8_t> data;
static int d_first = 0, d_npages = 0, d_tables = 0;
static int OFF_SCRDIR = 16, OFF_OBJOWN = 616, OFF_OBJST = 1616, OFF_OBJCLS = 2616, OFF_OBJROOM = 5616, OFF_ROOMDIR = 6616,
           OFF_ODIR = 9816, OFF_COSTDIR = 12816, OFF_COSTDIR2 = 13203, OFF_BIGDIR = 13590;   // pack_data3.OFFSETS
static int d8(int o) { return data[o]; }
static int d16(int o) { return data[o] | (data[o + 1] << 8); }
static const uint8_t* pageptr(int v) { return &data[d_tables + (v - d_first) * 6144]; }
static int frame = 0;
static int cur_room = 0, entry_room = 0, exit_room = 0;
// el EXCD en ejecucion: el de la sala cuya direccion de salida es la mayor que no pasa del puntero (en la misma pagina)
static int excd_start(int page, int ptr) {
  int best = -1;
  for (int r = 0; r < 100; r++) {
    int e = OFF_ROOMDIR + 32 * r;
    if (d8(e + 3) == page && d16(e + 4) <= ptr && d16(e + 4) > best) best = d16(e + 4);
  }
  return best < 0 ? ptr : best;
}
''' + decl + crc + body + '''
static void init_digest_syms() {
''' + assign + '''}
'''
open(os.path.join(here, 'digest_boot.inc'), 'w', encoding='utf-8').write(out)
print('digest_boot.inc: %d lineas' % out.count('\n'))

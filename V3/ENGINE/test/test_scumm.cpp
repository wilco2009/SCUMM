// Arnes de PC del programa completo (SCUMM/V3/ENGINE/scumm.asm, fase 5b; copia del de v2): el Z80 de EightyOne con la memoria paginada de la
// placa, un MCU simulado que sirve DATA.BIN, los overlays (DATA/OVLB.BIN, OVLC.BIN y OVLD.BIN) y los ROOMnn.GFX de una carpeta, y los registros de sprites y la
// "sombra" de video (tabla de caracteres, color y pantalla) para poder dibujar lo que veria la FPGA.
//
// V3 (variables de entorno): TS_DIGEST=fichero escribe el resumen "D f=..." de CoreVM.digest tras el script de arranque (f=0) y tras cada fotograma (digest_boot.inc,
// generado de test_vm.cpp), para compararlo con el modelo (vmmodel3.py scenarios-boot); TS_MODELDELTA=1 pone en DELTA lo que usa el modelo (max(1, VAR_TIMER_NEXT)) en
// vez de los vsyncs del arnes, para que las trazas sean comparables. Termina al llegar a sc_quit (X, error de la VM o falta de ficheros): imprime el codigo.
//
// Uso: test_scumm scumm.bin scumm.sym carpeta_de_la_SD fotogramas salida.bin [guion]
//   Corre hasta que main_loop se ha ejecutado `fotogramas` veces y vuelca el estado en salida.bin:
//     0       65536 bytes: la sombra de video (sirve $3800-$3FFF, $C000-$CFFF)
//     65536   65536 bytes: la memoria logica tal como la ve el Z80 (bloques mapeados) al acabar
//     131072  64 sprites x 32 bytes: activo, x (2), y, color (8), forma (8), mascara (8) y 3 de relleno
//     +2048   scroll fino (2090), mapa de filas fijas (3), I, chroma
//   guion (opcional): pares "tecla:fotograma" separados por comas; teclas P (derecha) O (izquierda) ESPACIO
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
extern "C" {
#include "z80.h"
int tstates = 0;
int StackChange = 0, StepOutRequested = 0, RetExecuted = 0;
int z80_fetch_is_m1 = 0;
void z80_m1_backtrack(void) {}
void debug(int) {}
}

static uint8_t ram[64][8192];
static int blk[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static uint8_t shadow[65536];
static inline uint8_t rd(int a) { a &= 0xFFFF; return ram[blk[a >> 13]][a & 0x1FFF]; }
static inline uint16_t rd16(int a) { return rd(a) | (rd(a + 1) << 8); }
static std::map<std::string, int> sym;
static int S(const char* n) {
  auto it = sym.find(n);
  if (it == sym.end()) { printf("falta el simbolo %s%c", n, 10); exit(2); }
  return it->second;
}
#include "digest_boot.inc"

struct Spr { int on = 0, x = 0, y = 0; uint8_t col[8], pix[8], mask[8]; };
static Spr spr[64];
static int sel = 0, fine = 0, rows[3] = {255, 255, 255}, chroma = 0, sfast = 0, hfile = 0;

// ---- motor de scroll por hardware (puerto $3FEF; ver claude/planning/scroll_hardware.md): modelo en software, sobre la sombra.
// La orden se ejecuta al acabar el fotograma (main_loop) o, si el Z80 sondea el estado, tras 30000 instrucciones.
static int ridx = 0, wreg2 = 0, cmd_pend = 0, cmd_val = 0, motor_run = 0, moves = 0;
static bool wexp2 = false;
static long long cmd_at = 0, steps_g = 0;
static bool row_moves(int r) { int m = rows[r / 8]; return (m >> (r & 7)) & 1; }
static void move_chain(const int ch[34], int dir) {
  uint8_t tmp[34];
  for (int q = 0; q < 34; q++) tmp[q] = ch[q] >= 0 ? shadow[ch[q]] : 0;
  if (dir == 1) {
    for (int q = 1; q <= 32; q++) shadow[ch[q]] = tmp[q + 1];
    if (ch[0] >= 0) shadow[ch[0]] = tmp[1];
  } else {
    for (int q = 2; q <= 33; q++) shadow[ch[q]] = tmp[q - 1];
    if (ch[0] >= 0) shadow[ch[1]] = tmp[0];
    shadow[ch[33]] = tmp[32];
  }
}
static void do_move(int dir) {
  if (sfast != 171 || (dir != 1 && dir != 2)) return;
  int base = hfile, ch[34];
  for (int y = 0; y < 192; y++) {                                      // bitmap
    if (!row_moves(y >> 3)) continue;
    ch[0] = base + 0x1C00 + y; ch[33] = base + 0x1800 + y;
    for (int c = 0; c < 32; c++) ch[c + 1] = base + y * 32 + c;
    move_chain(ch, dir);
  }
  if ((chroma & 0x20) && !(chroma & 0x10))                             // atributos de HiRes modo 0 (8x1)
    for (int y = 0; y < 192; y++) {
      if (!row_moves(y >> 3)) continue;
      ch[0] = 0xDC00 + y; ch[33] = 0xD800 + y;
      for (int c = 0; c < 32; c++) ch[c + 1] = 0xC000 + y * 32 + c;
      move_chain(ch, dir);
    }
  moves++;
}
static void motor_tick(bool frame_end) {
  if (cmd_pend && (frame_end || steps_g - cmd_at > 30000)) { do_move(cmd_val); cmd_pend = 0; }
}

static int g_fr = 0, w_lo = -1, w_hi = -1, w_from = 0;   // TS_WATCH=lo-hi[,desde fotograma]: imprime las escrituras
static uint8_t x0[0x400]; static int x_base = 0, x_m = 0; static uint8_t p16[32]; static int p16_ptr = 0, p16_lo = 0, p16_on = 0;     // fase 8: sprites extra (POKE 2129, 2131) y su hoja en $0000-$03FF
static inline void wr(int a, uint8_t v) {
  a &= 0xFFFF;
  if (a >= w_lo && a <= w_hi && g_fr >= w_from) { printf("W f=%d pc=%04X b0=%d [%04X]=%02X%c", g_fr, z80.pc.w, blk[0], a, v, 10);
    if (getenv("TS_WATCHBRK")) { printf("  af=%04X bc=%04X de=%04X hl=%04X ix=%04X sp=%04X; pila: %02X%02X %02X%02X %02X%02X %02X%02X%c", z80.af.w, z80.bc.w, z80.de.w, z80.hl.w, z80.ix.w, z80.sp.w, rd(z80.sp.w + 1), rd(z80.sp.w), rd(z80.sp.w + 3), rd(z80.sp.w + 2), rd(z80.sp.w + 5), rd(z80.sp.w + 4), rd(z80.sp.w + 7), rd(z80.sp.w + 6), 10); exit(0); } }
  if (a < 0x2000) {                                  // bloque 0: ROM; los puertos mapeados en memoria de la FPGA
    if (a < 0x400) x0[a] = v;                        // fase 8: entradas de los sprites extra (hoja 0, 32 B por extra) escritas por el programa
    if (a == 2129) x_base = v; else if (a == 2131) x_m = v;
    else if (a == 2063) p16_ptr = v; else if (a == 2064) p16_lo = v; else if (a == 2067) p16_on = v & 1;
    else if (a == 2066) { p16[(p16_ptr & 15) * 2] = p16_lo; p16[(p16_ptr & 15) * 2 + 1] = v; p16_ptr++; }       // fase 8: paleta de 16
    if (a == 2100) sel = v & 63;
    else if (a == 2101) spr[sel].on = v & 1;
    else if (a == 2102) spr[sel].x = (spr[sel].x & 0x100) | v;
    else if (a == 2103) spr[sel].x = (spr[sel].x & 0xFF) | ((v & 1) << 8);
    else if (a == 2104) spr[sel].y = v;
    else if (a >= 2105 && a <= 2112) spr[sel].col[a - 2105] = v;
    else if (a >= 2113 && a <= 2120) spr[sel].pix[a - 2113] = v;
    else if (a >= 2121 && a <= 2128) spr[sel].mask[a - 2121] = v;
    else if (a == 2090) fine = v & 7;
    else if (a == 2091) rows[0] = v;
    else if (a == 2092) rows[1] = v;
    else if (a == 2093) rows[2] = v;
    else if (a == 2045) sfast = v;
    else if (a == 2044) hfile = v << 8;
    return;
  }
  ram[blk[a >> 13]][a & 0x1FFF] = v;
  shadow[a] = v;                                    // la sombra refleja toda la memoria logica
}
static inline void wr16(int a, uint16_t v) { wr(a, v & 255); wr(a + 1, v >> 8); }

// ---- MCU simulado
static std::string sd_dir;
static int mcu_clk = 0;
static std::vector<uint8_t> mcu_out;
static size_t mcu_outpos = 0;
static FILE* mcu_files[8];
static std::string mcu_name;
static int mcu_cmd = -1, mcu_cnt = 0, mcu_nlen = 0, mcu_h = 0, mcu_n = 0;
static void mcu_byte(uint8_t b) {
  if (mcu_cmd < 0) {
    mcu_cmd = b; mcu_cnt = 0; mcu_name.clear(); mcu_nlen = 0;
    if (b == 29 || b == 0x41 || b == 0x1C) mcu_cmd = -1;
    if (b == 35) { printf("SND f=%d STOP%c", g_fr, 10); mcu_cmd = -1; }             // STOP_VGM: sin parametros ni respuesta
    return;
  }
  if (mcu_cmd == 38) { printf("SND f=%d LOOP %d%c", g_fr, b, 10); mcu_cmd = -1; return; }     // LOOP_VGM: un byte, sin respuesta
  if (mcu_cmd == 34) {                                                                          // PLAY_VGM: longitud, nombre; responde el estado
    if (mcu_cnt == 0) { mcu_nlen = b; mcu_cnt = 1; }
    else {
      { static const char T[] = " ??????????\"&$:?()><=+-*/;,.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"; mcu_name += (b < 64) ? T[b] : '?'; }   // como el MCU: asc81_to_ascii
      if ((int)mcu_name.size() == mcu_nlen) { printf("SND f=%d PLAY %s%c", g_fr, mcu_name.c_str(), 10); mcu_out.push_back(0); mcu_cmd = -1; }
    }
    return;
  }
  if (mcu_cmd == 71) {                                                                          // FCREATE: como FOPEN pero crea el fichero (en la carpeta de datos)
    if (mcu_cnt == 0) { mcu_nlen = b; mcu_cnt = 1; }
    else {
      mcu_name += (char)b;
      if ((int)mcu_name.size() == mcu_nlen) {
        size_t k = mcu_name.rfind('/');
        std::string base = k == std::string::npos ? mcu_name : mcu_name.substr(k + 1);
        FILE* f = fopen((sd_dir + "/" + base).c_str(), "w+b");
        int h = 0xFF;
        if (f) for (int i = 0; i < 8; i++) if (!mcu_files[i]) { mcu_files[i] = f; h = i; break; }
        mcu_out.push_back((uint8_t)h);
        mcu_cmd = -1;
      }
    }
    return;
  }
  if (mcu_cmd == 56) {                                                                          // FWRITE: manejador, cuenta (2) y los bytes; responde el estado
    if (mcu_cnt == 0) { mcu_h = b & 7; mcu_cnt = 1; }
    else if (mcu_cnt == 1) { mcu_n = b; mcu_cnt = 2; }
    else if (mcu_cnt == 2) { mcu_n |= b << 8; mcu_cnt = 3; if (mcu_n == 0) { mcu_out.push_back(0); mcu_cmd = -1; } }
    else {
      FILE* f = mcu_files[mcu_h];
      static const bool wrfail = getenv("TS_WRFAIL") != nullptr;                              // 10e: TS_WRFAIL=1: la SD rechaza las escrituras (llena)
      if (f && !wrfail) fputc(b, f);
      if (++mcu_cnt - 3 == mcu_n) { if (f) fflush(f); mcu_out.push_back(f && !wrfail ? 0 : 255); mcu_cmd = -1; }
    }
    return;
  }
  if (mcu_cmd == 53) {
    if (mcu_cnt == 0) { mcu_nlen = b; mcu_cnt = 1; }
    else {
      mcu_name += (char)b;
      if ((int)mcu_name.size() == mcu_nlen) {
        size_t k = mcu_name.rfind('/');
        std::string base = k == std::string::npos ? mcu_name : mcu_name.substr(k + 1);
        std::string path = sd_dir + "/" + mcu_name;
        if (getenv("TS_FLOG")) printf("OPEN f=%d %s%c", g_fr, base.c_str(), 10);                // TS_FLOG=1: cada fichero que se abre
        FILE* f = fopen(path.c_str(), "rb");                                                  // la ruta relativa tal cual (AGI usa carpetas por tipo)
        if (!f) { path = sd_dir + "/" + base; f = fopen(path.c_str(), "rb"); }
        if (!f) { path = sd_dir + "/gfx/" + base; f = fopen(path.c_str(), "rb"); }
        int h = 0xFF;
        if (f) for (int i = 0; i < 8; i++) if (!mcu_files[i]) { mcu_files[i] = f; h = i; break; }
        mcu_out.push_back((uint8_t)h);
        mcu_cmd = -1;
      }
    }
  } else if (mcu_cmd == 59) {
    FILE* f = mcu_files[b & 7];
    long sz = 0;
    if (f) { long cur = ftell(f); fseek(f, 0, SEEK_END); sz = ftell(f); fseek(f, cur, SEEK_SET); }
    for (int i = 0; i < 4; i++) mcu_out.push_back((sz >> (8 * i)) & 255);
    for (int i = 0; i < 4; i++) mcu_out.push_back(0);
    mcu_out.push_back(0);
    mcu_cmd = -1;
  } else if (mcu_cmd == 55) {
    if (mcu_cnt == 0) { mcu_h = b & 7; mcu_cnt = 1; }
    else if (mcu_cnt == 1) { mcu_n = b; mcu_cnt = 2; }
    else {
      mcu_n |= b << 8;
      FILE* f = mcu_files[mcu_h];
      for (int i = 0; i < mcu_n; i++) { int c = f ? fgetc(f) : 0; mcu_out.push_back(c < 0 ? 0 : c); }
      mcu_out.push_back(0);
      mcu_cmd = -1;
    }
  } else if (mcu_cmd == 54) {                                                                   // F_SEEK: manejador y 4 bytes de desplazamiento; responde el estado
    if (mcu_cnt == 0) { mcu_h = b & 7; mcu_n = 0; mcu_cnt = 1; }
    else { mcu_n |= b << (8 * (mcu_cnt - 1)); if (++mcu_cnt == 5) { FILE* f = mcu_files[mcu_h]; if (f) fseek(f, (unsigned)mcu_n, SEEK_SET); mcu_out.push_back(f ? 0 : 255); mcu_cmd = -1; } }
  } else if (mcu_cmd == 57) {
    int h = b & 7;
    if (mcu_files[h]) { fclose(mcu_files[h]); mcu_files[h] = nullptr; }
    mcu_out.push_back(0);
    mcu_cmd = -1;
  } else { printf("orden del MCU desconocida: %d%c", mcu_cmd, 10); exit(3); }
}

// ---- teclado
struct Key { int frame; int keys; };
static std::vector<Key> script;
static int cur_keys = 0, frames_done = 0, frame_limit = 0;
// Matriz del teclado del ZX81 (ZX81_MATRIX="fotograma:TECLA+TECLA,fotograma:,..."): fila 0 SHIFT Z X C V, 1 A S D F G, 2 Q W E R T, 3 1-5, 4 0 9 8 7 6, 5 P O I U Y, 6 ENTER L K J H, 7 SPACE . M N B
struct MKey { int frame; uint8_t m[8]; };
static std::vector<MKey> mscript;
static uint8_t mat[8];
static bool mat_mode = false;
static bool mat_key(const std::string& k, int& row, int& bit) {
  static const char* rows[8] = {"#ZXCV", "ASDFG", "QWERT", "12345", "09876", "POIUY", "#LKJH", "_.MNB"};
  if (k == "SHIFT") { row = 0; bit = 0; return true; }
  if (k == "ENTER") { row = 6; bit = 0; return true; }
  if (k == "SPACE") { row = 7; bit = 0; return true; }
  if (k.size() != 1) return false;
  for (int r = 0; r < 8; r++) for (int b = 0; b < 5; b++) if (rows[r][b] == k[0] && k[0] != '#' && k[0] != '_') { row = r; bit = b; return true; }
  return false;
}
static bool finished = false;
static uint16_t main_loop_addr = 0, wait_frame_addr = 0;   // wait_frame: la espera de una trama de agivm (en una ventana de mensaje) cuenta como fotograma
// ---- TS_PROF=desde-hasta (fotogramas): cuenta T-estados por rutina (el simbolo anterior) y por vuelta del bucle principal
#include <map>
#include <algorithm>
static std::vector<std::pair<unsigned, std::string>> syms;
static std::map<std::string, long long> prof;
static long long prof_loop_start = 0, prof_total = 0, prof_work = 0;
static std::map<int, std::map<std::string, long long>> prof_by_loop;
static int prof_n = 0;
static std::vector<long long> prof_loops;
static int prof_lo = -1, prof_hi = -1;
// TS_VM=1 (con TS_PROF y TS_T=1): instrucciones de script ejecutadas y sus T-estados por opcode. Una instruccion de script va desde el paso por es_loop
// (vm_core.asm: el bucle de exec_script) hasta que el manejador vuelve a es_loop; las ejecuciones anidadas (startScript...) se restan de la instruccion que las lanza.
static unsigned a_es_loop = 0, a_es_noerr = 0, a_es_go = 0, a_disp = 0, a_sptr = 0;
static const bool ts_vm = getenv("TS_VM") != 0;
struct VmFrame { int op; long long t0, child, pro; unsigned sp; };
struct VmOp { long long n = 0, excl = 0, incl = 0; };
static std::vector<VmFrame> vm_stack;
static VmOp vm_ops[256];
static std::vector<long long> vm_samples;                 // T exclusivos (con el prologo) de cada instruccion de script
static long long vm_pro_acc = 0, vm_exit_oh = 0, vm_n = 0, vm_loop_n = 0;
static std::vector<long long> vm_n_loops;                 // instrucciones de script por vuelta del bucle principal
static bool vm_in_pro = false;
static std::map<int, std::vector<std::pair<unsigned, std::string>>> osyms;
static const char* sym_of(unsigned pc) {
  if (pc < 0x2000 && osyms.count(1000 + blk[0])) { auto& v = osyms[1000 + blk[0]]; std::pair<unsigned, std::string>* b = 0; for (auto& p : v) if (p.first <= pc && (!b || p.first >= b->first)) b = &p; if (b) return b->second.c_str(); }
  if (pc >= 0x2000 && pc < 0x4000) { auto& v = osyms[blk[1]]; std::pair<unsigned, std::string>* b = 0; for (auto& p : v) if (p.first <= pc && (!b || p.first >= b->first)) b = &p; if (b) return b->second.c_str(); }
  static std::string cur; const std::pair<unsigned, std::string>* best = nullptr;
  for (auto& p : syms) { if (p.first <= pc && (!best || p.first >= best->first)) best = &p; }
  cur = best ? best->second : "?"; return cur.c_str();
}
static void dump(const char* path) {
  FILE* f = fopen(path, "wb");
  fwrite(shadow, 1, 65536, f);
  uint8_t logical[65536];
  for (int a = 0; a < 65536; a++) logical[a] = rd(a);
  fwrite(logical, 1, 65536, f);
  for (int i = 0; i < 64; i++) {
    uint8_t b[32] = {0};
    b[0] = spr[i].on; b[1] = spr[i].x & 255; b[2] = spr[i].x >> 8; b[3] = spr[i].y;
    memcpy(b + 4, spr[i].col, 8); memcpy(b + 12, spr[i].pix, 8); memcpy(b + 20, spr[i].mask, 8);
    fwrite(b, 1, 32, f);
  }
  uint8_t t[8] = {(uint8_t)fine, (uint8_t)rows[0], (uint8_t)rows[1], (uint8_t)rows[2], z80.i, (uint8_t)chroma, (uint8_t)sfast, (uint8_t)(hfile >> 8)};
  fwrite(t, 1, 8, f);
  { uint8_t xt[2] = {(uint8_t)x_base, (uint8_t)x_m}; fwrite(xt, 1, 2, f); fwrite(x0, 1, 0x400, f); fputc(p16_on, f); fwrite(p16, 1, 32, f); }
  fclose(f);
}

extern "C" {
int z80_contend_wrapper(int, int, int t) { return t; }
int z80_contend_io_wrapper(int, int, int t) { return t; }
BYTE z80_readbyte_wrapper(int a) { return rd(a); }
BYTE z80_readoperandbyte_wrapper(int a) { return rd(a); }
BYTE z80_opcode_fetch_wrapper(int a) { z80_fetch_is_m1 = 0; return rd(a); }
void z80_writebyte_wrapper(int a, int d) { wr(a, (uint8_t)d); }
void z80_writeport_wrapper(int port, int d, int*) {
  int lo = port & 0xFF;
  if (lo == 0xE7) blk[d & 7] = (port >> 8) & 0x3F;           // mapeador (paginacion completa): B = pagina, dato = bloque
  else if (lo == 0xA7) { mcu_byte(d & 255); mcu_clk ^= 1; }
  else if (lo == 0xEF && (port >> 8) == 0x7F) chroma = d;
  else if (port == 0x3FEF) {                                  // puerto del depurador: orden del motor (registro 9 = OUT $41 + dato) y estado (OUT $20 + IN)
    if (wexp2) { wexp2 = false; if (wreg2 == 1 && (d & 7) != 0) { if (!cmd_pend) { cmd_pend = 1; cmd_val = d & 7; cmd_at = steps_g; } } }
    else if (d >= 0x20 && d <= 0x2F) ridx = 16 + (d & 15);
    else if (d >= 0x40 && d <= 0x4F) { wexp2 = true; wreg2 = d & 15; }
    else if (d <= 0x0F) ridx = d;
  }
}
BYTE z80_readport_wrapper(int port, int*) {
  int lo = port & 0xFF;
  if (port == 0x3FEF) return ridx == 16 ? (cmd_pend ? 0xC0 : 0) : 0;
  if (lo == 0xE7) return blk[(port >> 8) & 7];
  if (lo == 0xAF) return (mcu_clk << 7) | 0x02;
  if (lo == 0xA7) {
    uint8_t v = mcu_outpos < mcu_out.size() ? mcu_out[mcu_outpos++] : 0;
    if (mcu_outpos >= mcu_out.size()) { mcu_out.clear(); mcu_outpos = 0; }
    mcu_clk ^= 1;
    return v;
  }
  if (lo == 0xFE && mat_mode) {
    int sel = (port >> 8) & 255, v = 0xFF;
    for (int r = 0; r < 8; r++) if (!(sel & (1 << r))) v &= ~mat[r];
    return v;
  }
  if (lo == 0xFE) {
    int row = (port >> 8) & 255;
    int v = 0xFF;
    if (row == 0xDF) { if (cur_keys & 1) v &= ~2; if (cur_keys & 2) v &= ~1; }
    if (row == 0x7F) { if (cur_keys & 16) v &= ~1; if (cur_keys & 4) v &= ~8; if (cur_keys & 8) v &= ~16; }
    if (row == 0xFB) { if (cur_keys & 32) v &= ~16; if (cur_keys & 64) v &= ~1; }
    if (row == 0xFD && (cur_keys & 128)) v &= ~1;
    if (row == 0xF7 && (cur_keys & 256)) v &= ~8; if (row == 0xF7 && (cur_keys & 512)) v &= ~1; if (row == 0xF7 && (cur_keys & 1024)) v &= ~2; if (row == 0xF7 && (cur_keys & 2048)) v &= ~4; if (row == 0xEF && (cur_keys & 4096)) v &= ~2; if (row == 0xEF && (cur_keys & 8192)) v &= ~4;                   // tecla 4: salta la cutscene
    return v;
  }
  return 0xFF;
}
}

int main(int argc, char** argv) {
  if (argc < 6) { printf("uso: test_scumm scumm.bin scumm.sym carpeta_SD fotogramas salida.bin [guion]%c", 10); return 2; }
  FILE* f = fopen(argv[1], "rb");
  if (!f) { printf("no encuentro %s%c", argv[1], 10); return 2; }
  std::vector<uint8_t> code(32768);
  size_t sz = fread(code.data(), 1, code.size(), f); fclose(f);
  for (size_t i = 0; i < sz; i++) { int a = 0x4200 + (int)i; ram[a >> 13][a & 0x1FFF] = code[i]; }
  { FILE* s = fopen(argv[2], "r"); char line[256];
    while (s && fgets(line, sizeof line, s)) {
      char name[128]; unsigned v;
      if (sscanf(line, "%127s EQU %xH", name, &v) == 2) { sym[name] = (int)v; if (!strcmp(name, "main_loop")) main_loop_addr = v; if (!strcmp(name, "es_loop")) a_es_loop = v; if (!strcmp(name, "es_noerr")) a_es_noerr = v; if (!strcmp(name, "es_go")) a_es_go = v; if (!strcmp(name, "disp_table")) a_disp = v; if (!strcmp(name, "SPTR")) a_sptr = v; if (!strcmp(name, "wait_frame")) wait_frame_addr = v; if (v >= 0x4200 && v < 0x8000) syms.push_back({v, name}); }
    }
    if (s) fclose(s); }
  sd_dir = argv[3];
  frame_limit = atoi(argv[4]);
  if (argc > 6) {
    std::string sc = argv[6];
    size_t p = 0;
    while (p < sc.size()) {
      size_t q = sc.find(',', p);
      if (q == std::string::npos) q = sc.size();
      std::string it = sc.substr(p, q - p);
      size_t c = it.find(':');
      int keys = 0;
      for (char ch : it.substr(0, c)) { if (ch == 'O') keys |= 1; if (ch == 'P') keys |= 2; if (ch == 'S') keys |= 16; if (ch == 'N') keys |= 4; if (ch == 'B') keys |= 8; if (ch == 'T') keys |= 32; if (ch == 'Q') keys |= 64; if (ch == 'A') keys |= 128; if (ch == '4') keys |= 256; if (ch == '1') keys |= 512; if (ch == '2') keys |= 1024; if (ch == '3') keys |= 2048; if (ch == '9') keys |= 4096; if (ch == '8') keys |= 8192; }
      script.push_back({atoi(it.substr(c + 1).c_str()), keys});
      p = q + 1;
    }
  }
  if (const char* mx = getenv("ZX81_MATRIX")) {
    std::string sc = mx; size_t p = 0; mat_mode = true;
    while (p < sc.size()) {
      size_t q = sc.find(',', p); if (q == std::string::npos) q = sc.size();
      std::string it = sc.substr(p, q - p); size_t c = it.find(':');
      MKey mk; memset(mk.m, 0, 8); mk.frame = atoi(it.substr(0, c).c_str());
      std::string ks = it.substr(c + 1); size_t a = 0;
      while (a < ks.size()) {
        size_t b = ks.find('+', a); if (b == std::string::npos) b = ks.size();
        int r, bt; if (mat_key(ks.substr(a, b - a), r, bt)) mk.m[r] |= 1 << bt;
        a = b + 1;
      }
      mscript.push_back(mk); p = q + 1;
    }
  }
  const char* ts_dig = getenv("TS_DIGEST");
  FILE* dig = ts_dig ? fopen(ts_dig, "w") : nullptr;
  if (ts_dig) {
    init_digest_syms();
    std::string dp = sd_dir + "/DATA/DATA.BIN";
    FILE* df = fopen(dp.c_str(), "rb");
    if (!df) { printf("no puedo leer %s%c", dp.c_str(), 10); return 2; }
    fseek(df, 0, SEEK_END); long n = ftell(df); fseek(df, 0, SEEK_SET);
    data.resize(n);
    if (fread(data.data(), 1, n, df) != (size_t)n) return 2;
    fclose(df);
    d_npages = data[5]; d_first = data[6]; d_tables = d16(13);
  }
  const bool model_delta = getenv("TS_MODELDELTA") != 0;
  const unsigned a_boot_done = sym.count("boot_done") ? sym["boot_done"] : 0, a_frame_done = sym.count("frame_done") ? sym["frame_done"] : 0,
                 a_ml_dset = sym.count("ml_dset") ? sym["ml_dset"] : 0, a_quit = sym.count("quit_ret") ? sym["quit_ret"] : 0;
  ram[0][0x100] = 0x76;
  ram[0][0x2E7] = 0xC9; ram[0][0x207] = 0xC9;                // SET_FAST y SLOW_FAST de la ROM: RET
  for (int i = 8; i < 512; i++) ram[0][0x1E00 + i] = (uint8_t)(i * 37 + 11);   // juego de caracteres de la ROM (relleno)
  if (const char* rp = getenv("ZX81_ROM")) {           // la ROM del ZX81: solo hace falta el juego de caracteres de $1E00
    FILE* rf = fopen(rp, "rb");
    if (rf) { size_t n = fread(ram[0], 1, 8192, rf); (void)n; fclose(rf); }
    ram[0][0x2E7] = 0xC9; ram[0][0x207] = 0xC9;
  }
  z80_init(); z80_reset();
  z80.sp.w = 0xCFF8;
  wr(0xCFF8, 0xE0); wr(0xCFF9, 0xFF);
  z80.pc.w = 0x4215; z80.halted = 0; z80.iff1 = z80.iff2 = 0;        // ENTRY_POINT de vm_core.asm (+21)
  if (const char* os = getenv("TS_OSYM")) { FILE* q = fopen(os, "r"); char line[256];
    while (q && fgets(line, sizeof line, q)) { char name[128]; unsigned v; if (sscanf(line, "%127s EQU %xH", name, &v) == 2 && v < 0x4200) syms.push_back({v, std::string("ovl:") + name}); }
    if (q) fclose(q); }
  { static const struct { int pg; const char* nm; const char* f; } T[] = {{41, "A", "agia.sym"}, {42, "B", "agib.sym"}, {44, "C", "agic.sym"}, {46, "D", "agid.sym"}, {48, "E", "agie.sym"}, {49, "F", "agif.sym"}};
    static const struct { int pg; const char* nm; const char* f; } S[] = {{49, "B", "prog/ovlb.sym"}, {48, "C", "prog/ovlc.sym"}, {46, "D", "prog/ovld.sym"}};   // fase 10b: los overlays de SCUMM v3 corren en el bloque 0
    for (auto& t : S) { FILE* q = fopen(t.f, "r"); char line[256]; while (q && fgets(line, sizeof line, q)) { char name[128]; unsigned v; if (sscanf(line, "%127s EQU %xH", name, &v) == 2 && v < 0x2000) osyms[1000 + t.pg].push_back({v, std::string(t.nm) + ":" + name}); } if (q) fclose(q); }
    for (auto& t : T) { FILE* q = fopen(t.f, "r"); char line[256]; while (q && fgets(line, sizeof line, q)) { char name[128]; unsigned v; if (sscanf(line, "%127s EQU %xH", name, &v) == 2 && v >= 0x2000 && v < 0x4000) osyms[t.pg].push_back({v, std::string(t.nm) + ":" + name}); } if (q) fclose(q); } }
  if (const char* pf = getenv("TS_PROF")) sscanf(pf, "%d-%d", &prof_lo, &prof_hi);
  if (const char* w = getenv("TS_WATCH")) { unsigned lo = 0, hi = 0, fr = 0; sscanf(w, "%x-%x,%u", &lo, &hi, &fr); w_lo = lo; w_hi = hi; w_from = fr; }
  long long steps = 0;
  size_t ki = 0;
  static int hist[256]; static int hi = 0;           // ultimos PC, para ver como se escapa el programa
  while (!finished) {
    if (z80.pc.w == main_loop_addr || (wait_frame_addr && z80.pc.w == wait_frame_addr)) {
      motor_tick(true);
      { static const char* ts_dumps = getenv("TS_DUMPS"); static int last_dumped = -1;       // TS_DUMPS=f1,f2,...: ademas del volcado final, uno al empezar la vuelta que sigue a esos fotogramas (fase 8: los sprites de los actores); el fichero lleva el numero detras
        if (ts_dumps && frames_done != last_dumped) { const char* q = ts_dumps; while (*q) { char* e; long v = strtol(q, &e, 10); if (e == q) break; if (v == frames_done) { char nm[512]; snprintf(nm, sizeof nm, "%s.%ld", argv[5], v); dump(nm); last_dumped = frames_done; } q = *e ? e + 1 : e; } } }
      if (prof_lo >= 0 && frames_done > prof_lo && frames_done <= prof_hi) { prof_loops.push_back(prof_work); }
      if (ts_vm && prof_lo >= 0 && frames_done > prof_lo && frames_done <= prof_hi) vm_n_loops.push_back(vm_loop_n);
      vm_loop_n = 0; vm_stack.clear(); vm_pro_acc = 0;
      prof_work = 0; prof_n = frames_done;
      { static FILE* sl = getenv("TS_SPRLOG") ? fopen(getenv("TS_SPRLOG"), "w") : 0;
        if (sl) { unsigned h = 2166136261u; int n = 0; for (int i = 0; i < 64; i++) if (spr[i].on) { n++; const uint8_t q[3] = {(uint8_t)i, (uint8_t)spr[i].x, (uint8_t)((spr[i].x >> 8) ^ spr[i].y)}; for (int k = 0; k < 3; k++) h = (h ^ q[k]) * 16777619u; for (int k = 0; k < 8; k++) { h = (h ^ spr[i].col[k]) * 16777619u; h = (h ^ spr[i].pix[k]) * 16777619u; h = (h ^ spr[i].mask[k]) * 16777619u; } }
          unsigned h2 = 2166136261u, h3 = 2166136261u; for (int k = 0x6D00; k < 0x6F00; k++) h2 = (h2 ^ rd(k)) * 16777619u; for (int k = 0x7300; k < 0x7700; k++) h2 = (h2 ^ rd(k)) * 16777619u; for (int k = 0xA000; k < 0xA000 + 14440; k++) h3 = (h3 ^ rd(k)) * 16777619u;
          fprintf(sl, "%d %d %08x %08x %08x\n", frames_done, n, h, h2, h3); fflush(sl); } }
      frames_done++; g_fr = frames_done;
      if (const char* pk = getenv("TS_POKE")) {            // TS_POKE=fotograma:direccion:valor[,...]: escribe un byte (hex) en ese fotograma
        unsigned f, a, v; const char* p = pk;
        while (sscanf(p, "%u:%x:%x", &f, &a, &v) == 3) { if ((int)f == frames_done) wr(a, v); p = strchr(p, ','); if (!p) break; p++; }
      }
      if (const char* pc = getenv("TS_CALL")) {            // TS_CALL=fotograma:direccion[,...]: en ese fotograma llama a la rutina (hex) y vuelve a main_loop (para probar guardar / cargar)
        unsigned f, a; const char* p = pc;
        while (sscanf(p, "%u:%x", &f, &a) == 2) {
          if ((int)f == frames_done) { z80.sp.w -= 2; wr16(z80.sp.w, main_loop_addr); z80.pc.w = a; }
          p = strchr(p, ','); if (!p) break; p++;
        }
      }
      while (ki < script.size() && script[ki].frame <= frames_done) { cur_keys = script[ki].keys; ki++; }
      { static size_t mi = 0; while (mi < mscript.size() && mscript[mi].frame <= frames_done) { memcpy(mat, mscript[mi].m, 8); mi++; } }
      if (frames_done > frame_limit) { finished = true; break; }
    }
    if (z80.pc.w == 0xFFE0) { printf("el programa ha vuelto a BASIC; ultimos PC:%c", 10); for (int k = 60; k > 0; k--) printf("%04X ", hist[(hi - k) & 255]); printf("%c", 10); break; }
    if (frames_done > 0 && z80.pc.w >= 0x8000 && z80.pc.w < 0xFFF0) {         // la ULA del ZX81 mete NOPs al captar instrucciones por encima de $8000
      printf("CODIGO POR ENCIMA DE $8000: pc=%04X; ultimos PC:%c", z80.pc.w, 10);
      for (int k = 40; k > 0; k--) printf("%04X ", hist[(hi - k) & 255]);
      printf("%c", 10); break;
    }
    if (blk[0] == 0 && (z80.pc.w == 0x02E7 || z80.pc.w == 0x0207)) {           // SET_FAST y SLOW_FAST de la ROM: el arnes no tiene ROM, vuelve sin hacer nada
      z80.pc.w = rd16(z80.sp.w); z80.sp.w += 2; continue;
    }
    static const char* ts_bp = getenv("TS_BP"); if (ts_bp && z80.pc.w == (unsigned)strtol(ts_bp, 0, 16) && (!getenv("TS_BPA") || (z80.af.w >> 8) == (unsigned)strtol(getenv("TS_BPA"), 0, 16))) {   // TS_BP=direccion (hex): para ahi e imprime los ultimos PC, SP y la pila
      printf("TS_BP pc=%04X sp=%04X af=%04X bc=%04X de=%04X hl=%04X ix=%04X iy=%04X; pila:", z80.pc.w, z80.sp.w, z80.af.w, z80.bc.w, z80.de.w, z80.hl.w, z80.ix.w, z80.iy.w);
      for (int k = 0; k < 6; k++) printf(" %04X", rd16(z80.sp.w + 2 * k));
      { unsigned cs = rd16(S("CURSLOT")); printf("%cCUR=%d slot=%04X num=%d where=%d", 10, rd(S("CUR")), cs, rd16(cs + 2), rd(cs + 3)); printf(" RESMAP:"); for (int q = 0; q < 12; q++) printf(" %d", rd(S("RESMAP") + q)); printf("%c", 10); }
      printf("%cultimos PC:", 10);
      for (int k = 40; k > 0; k--) printf(" %04X", hist[(hi - k) & 255]);
      printf("%c", 10);
      if (!getenv("TS_TRACE")) break;
      for (int k = 0; k < atoi(getenv("TS_TRACE")); k++) { printf("%04X(%02X) ", z80.pc.w, rd(z80.pc.w)); z80_do_opcode(); }
      printf("%c", 10); break;
    }
    if (sym.count("sm_ok1") && z80.pc.w == (unsigned)sym["sm_ok1"] && getenv("TS_OVCHK")) {     // TS_OVCHK=1: las paginas de los overlays tras cargar (primeros bytes y suma)
      for (int pg : {46, 47, 48, 49, 15}) { unsigned sum = 0; for (int i = 0; i < 8192; i++) sum = sum * 31 + ram[pg][i]; printf("pagina %d: %02X %02X %02X %02X %02X %02X, suma %08X%c", pg, ram[pg][0], ram[pg][1], ram[pg][2], ram[pg][3], ram[pg][4], ram[pg][5], sum, 10); } }
    if (getenv("TS_P15") && a_frame_done && z80.pc.w == a_frame_done && frames_done == 1) { FILE* q = fopen("build/p15.bin", "wb"); fwrite(ram[15], 1, 8192, q); fclose(q); }
    if (getenv("TS_P15") && a_frame_done && z80.pc.w == a_frame_done) { static int lastv = -1; int v = ram[15][198] | (ram[15][199] << 8); if (v != lastv) { printf("f=%d: pagina 15, ancho de la sala 6 = %d%c", frames_done, v, 10); lastv = v; } }
    if (a_boot_done && z80.pc.w == a_boot_done && dig) { frame = 0; fprintf(dig, "%s\n", digest().c_str()); }
    if (a_frame_done && z80.pc.w == a_frame_done && dig) { frame++; fprintf(dig, "%s\n", digest().c_str()); }
    if (a_ml_dset && z80.pc.w == a_ml_dset && model_delta) { int t = (int16_t)rd16(S("VARS") + 2 * 19); if (t < 1) t = 1; if (t > 255) t = 255; wr(S("DELTA"), t); }
    if (a_quit && z80.pc.w == a_quit) { printf("el programa sale (sc_quit): sm_ov=%d ERR=%d sala=%d fotograma=%d%c", rd(S("sm_ov")), rd(S("ERR")), rd(S("CURROOM")), frames_done, 10); break; }
    hist[hi++ & 255] = z80.pc.w;
    int ts0 = tstates;
    unsigned vm_pc0 = z80.pc.w, vm_sp0 = z80.sp.w;
    const bool vm_on = ts_vm && (a_es_noerr || a_es_go) && prof_lo >= 0 && frames_done > prof_lo && frames_done <= prof_hi;
    if (vm_on) {
      if (vm_pc0 == a_es_loop) {                                   // vuelve el manejador: cierra la instruccion abierta en este nivel
        while (!vm_stack.empty() && vm_stack.back().sp < vm_sp0) vm_stack.pop_back();   // restos de un nivel que no volvio por es_loop
        if (!vm_stack.empty() && vm_stack.back().sp == vm_sp0) {
          VmFrame f = vm_stack.back(); vm_stack.pop_back();
          long long incl = prof_total - f.t0 + f.pro, ex = incl - f.child;
          vm_ops[f.op].n++; vm_ops[f.op].excl += ex; vm_ops[f.op].incl += incl; vm_samples.push_back(ex);
          if (!vm_stack.empty()) vm_stack.back().child += incl;
        }
      }
      if (vm_pc0 == (a_es_noerr ? a_es_noerr + 6 : a_es_go)) {      // (v3: es_go)
                              // ld hl,(SPTR): empieza una instruccion de script
        while (!vm_stack.empty() && vm_stack.back().sp < vm_sp0) vm_stack.pop_back();
        VmFrame f; f.op = rd(rd16(a_sptr)); f.t0 = prof_total; f.child = 0; f.pro = vm_pro_acc; f.sp = vm_sp0;
        vm_pro_acc = 0; vm_n++; vm_loop_n++;
        vm_stack.push_back(f);
      }
    }
    z80_do_opcode();
    if (prof_lo >= 0 && frames_done > prof_lo && frames_done <= prof_hi) { const char* sn = sym_of(hist[(hi - 1) & 255]); if (strcmp(sn, "hs_w")) { { static const bool ts_t = getenv("TS_T") != 0; int dt = ts_t ? tstates : 1; prof[sn] += dt; prof_by_loop[prof_n][sn] += dt; prof_total += dt; prof_work += dt; } } }
    if (vm_on && vm_pc0 >= a_es_loop && vm_pc0 < (a_es_noerr ? a_es_noerr + 6 : a_es_go)) {   // prologo del bucle (comprobar ERR y CUR): se carga a la instruccion que sigue o a la salida
      vm_pro_acc += tstates;
      if (z80.pc.w < a_es_loop || z80.pc.w > a_es_noerr + 6) { vm_exit_oh += vm_pro_acc; vm_pro_acc = 0; }
    }
    steps_g++;
    { static int w1 = -2, w2 = -2; if (w1 == -2) { w1 = getenv("TS_WATCH") && sym.count(getenv("TS_WATCH")) ? sym[getenv("TS_WATCH")] : -1; w2 = sym.count("hv_c0") ? sym["hv_c0"] : 0; }
      if (w1 >= 0 && z80.pc.w == w1) printf("W f=%d c0=%d c1=%d ch=%d dc0=%d dc1=%d A=%02X BC=%04X DE=%04X HL=%04X sp0=%04X%c", frames_done, rd(w2), rd(w2+1), rd(w2+2), rd(sym["ov_dc0"]), rd(sym["ov_dc0"]+1), z80.af.b.h, z80.bc.w, z80.de.w, z80.hl.w, rd(z80.sp.w) | rd(z80.sp.w+1) << 8, 10); }
    if (cmd_pend) motor_tick(false);
    static const char* ts_ns = getenv("TS_NOSTOP"); if (steps > 50000000LL && !ts_ns) { printf("atascado; ultimos PC:%c", 10); for (int k = 120; k > 0; k--) printf("%04X ", hist[(hi - k) & 255]); printf("%c", 10); break; }
    if (++steps > 2000000000LL) { printf("demasiadas instrucciones, pc=%04X%c", z80.pc.w, 10); break; }
  }
  if (prof_lo >= 0) {
    std::vector<std::pair<long long, std::string>> v; for (auto& kv : prof) v.push_back({kv.second, kv.first});
    std::sort(v.rbegin(), v.rend());
    printf("PERFIL de los fotogramas %d-%d: %lld T-estados (%zu vueltas)%c", prof_lo, prof_hi, prof_total, prof_loops.size(), 10);
    for (size_t i = 0; i < v.size() && i < (getenv("TS_TOP") ? (size_t)atoi(getenv("TS_TOP")) : 25); i++) printf("  %-18s %9lld  %5.1f%%%c", v[i].second.c_str(), v[i].first, 100.0 * v[i].first / prof_total, 10);
    { std::vector<std::pair<long long, int>> w; for (auto& kv : prof_by_loop) { long long t = 0; for (auto& q : kv.second) t += q.second; w.push_back({t, kv.first}); }
      std::sort(w.rbegin(), w.rend());
      if (getenv("TS_LOOPS")) { for (auto& kv : prof_by_loop) { long long t = 0; std::vector<std::pair<long long, std::string>> q; for (auto& x : kv.second) { t += x.second; q.push_back({x.second, x.first}); } std::sort(q.rbegin(), q.rend()); printf("V %d %lld", kv.first, t); for (size_t k = 0; k < (size_t)atoi(getenv("TS_LOOPS")) && k < q.size(); k++) printf(" %s=%lld", q[k].second.c_str(), q[k].first); printf("%c", 10); } }
      printf("las 8 vueltas mas pesadas (instrucciones):%c", 10);
      for (size_t i = 0; i < w.size() && i < 8; i++) {
        auto& m = prof_by_loop[w[i].second]; std::vector<std::pair<long long, std::string>> t; for (auto& q : m) t.push_back({q.second, q.first}); std::sort(t.rbegin(), t.rend());
        printf("  vuelta %d: %lld;", w[i].second, w[i].first); for (size_t k = 0; k < 3 && k < t.size(); k++) printf(" %s=%lld", t[k].second.c_str(), t[k].first); printf("%c", 10);
      } }
    std::sort(prof_loops.begin(), prof_loops.end());
    if (!prof_loops.empty()) { long long sm = 0; for (auto x : prof_loops) sm += x; printf("%s por vuelta: media %.0f, mediana %lld, p90 %lld, maxima %lld (un fotograma de 50 Hz son 65000 T a 3,25 MHz o unas 8000 instrucciones)%c", getenv("TS_T") ? "T-estados" : "instrucciones", (double)sm / prof_loops.size(), prof_loops[prof_loops.size() / 2], prof_loops[prof_loops.size() * 9 / 10], prof_loops.back(), 10); }
  }
  if (ts_vm && prof_lo >= 0) {
    std::sort(vm_samples.begin(), vm_samples.end());
    long long tot = 0; for (auto x : vm_samples) tot += x;
    printf("INSTRUCCIONES DE SCRIPT (fotogramas %d-%d): %lld ejecutadas (%lld cerradas), %lld T-estados en ellas + %lld de salidas de exec_script; %.0f%% del total medido%c", prof_lo, prof_hi, vm_n, (long long)vm_samples.size(), tot, vm_exit_oh, prof_total ? 100.0 * (tot + vm_exit_oh) / prof_total : 0.0, 10);
    if (!vm_samples.empty()) printf("  T por instruccion (decodificacion + manejador, sin anidadas, con el prologo del bucle): media %.1f, mediana %lld, p90 %lld, p99 %lld, maximo %lld%c", (double)tot / vm_samples.size(), vm_samples[vm_samples.size() / 2], vm_samples[vm_samples.size() * 9 / 10], vm_samples[vm_samples.size() * 99 / 100], vm_samples.back(), 10);
    std::sort(vm_n_loops.begin(), vm_n_loops.end());
    if (!vm_n_loops.empty()) { long long sm = 0; for (auto x : vm_n_loops) sm += x; printf("  instrucciones de script por vuelta: media %.1f, mediana %lld, p90 %lld, maxima %lld%c", (double)sm / vm_n_loops.size(), vm_n_loops[vm_n_loops.size() / 2], vm_n_loops[vm_n_loops.size() * 9 / 10], vm_n_loops.back(), 10); }
    std::vector<std::pair<long long, int>> o; for (int i = 0; i < 256; i++) if (vm_ops[i].n) o.push_back({vm_ops[i].excl, i});
    std::sort(o.rbegin(), o.rend());
    printf("  por opcode (ordenado por T exclusivos): opcode, manejador, n, T medio exclusivo, T medio con anidadas, T totales%c", 10);
    for (size_t i = 0; i < o.size() && i < (getenv("TS_TOP") ? (size_t)atoi(getenv("TS_TOP")) : 25); i++) {
      int op = o[i].second; unsigned h = a_disp ? (unsigned)(rd(a_disp + 4 * op + 2) | (rd(a_disp + 4 * op + 3) << 8)) : 0;
      printf("   %02X %-28s %8lld %8.1f %8.1f %10lld%c", op, sym_of(h), vm_ops[op].n, (double)vm_ops[op].excl / vm_ops[op].n, (double)vm_ops[op].incl / vm_ops[op].n, vm_ops[op].excl, 10);
    }
  }
  printf("fotogramas: %d, instrucciones: %lld, ERR=%d, sala=%d, gf_room=%d%c", frames_done, steps, rd(S("ERR")), rd(S("CURROOM")), rd(S("gf_room")), 10);
  if (dig) fclose(dig);
  dump(argv[5]);
  return 0;
}

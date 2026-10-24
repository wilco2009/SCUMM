// Arnes de PC del programa completo (SCUMM/ENGINE/scumm.asm): el Z80 de EightyOne con la memoria paginada de la
// placa, un MCU simulado que sirve DATA.BIN y los ROOMnn.GFX de una carpeta, y los registros de sprites y la
// "sombra" de video (tabla de caracteres, color y pantalla) para poder dibujar lo que veria la FPGA.
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

struct Spr { int on = 0, x = 0, y = 0; uint8_t col[8], pix[8], mask[8]; };
static Spr spr[64];
static int sel = 0, fine = 0, rows[3] = {255, 255, 255}, chroma = 0, sfast = 0;

static int g_fr = 0, w_lo = -1, w_hi = -1, w_from = 0;   // TS_WATCH=lo-hi[,desde fotograma]: imprime las escrituras
static inline void wr(int a, uint8_t v) {
  a &= 0xFFFF;
  if (a >= w_lo && a <= w_hi && g_fr >= w_from) printf("W f=%d pc=%04X [%04X]=%02X%c", g_fr, z80.pc.w, a, v, 10);
  if (a < 0x2000) {                                  // bloque 0: ROM; los puertos mapeados en memoria de la FPGA
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
    return;
  }
  ram[blk[a >> 13]][a & 0x1FFF] = v;
  if ((a >= 0x3800 && a < 0x4000) || (a >= 0xC000 && a < 0xD000)) shadow[a] = v;
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
  if (mcu_cmd == 53) {
    if (mcu_cnt == 0) { mcu_nlen = b; mcu_cnt = 1; }
    else {
      mcu_name += (char)b;
      if ((int)mcu_name.size() == mcu_nlen) {
        size_t k = mcu_name.rfind('/');
        std::string base = k == std::string::npos ? mcu_name : mcu_name.substr(k + 1);
        std::string path = sd_dir + "/" + base;
        FILE* f = fopen(path.c_str(), "rb");
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
static bool finished = false;
static uint16_t main_loop_addr = 0;
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
  uint8_t t[8] = {(uint8_t)fine, (uint8_t)rows[0], (uint8_t)rows[1], (uint8_t)rows[2], z80.i, (uint8_t)chroma, (uint8_t)sfast, 0};
  fwrite(t, 1, 8, f);
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
}
BYTE z80_readport_wrapper(int port, int*) {
  int lo = port & 0xFF;
  if (lo == 0xAF) return (mcu_clk << 7) | 0x02;
  if (lo == 0xA7) {
    uint8_t v = mcu_outpos < mcu_out.size() ? mcu_out[mcu_outpos++] : 0;
    if (mcu_outpos >= mcu_out.size()) { mcu_out.clear(); mcu_outpos = 0; }
    mcu_clk ^= 1;
    return v;
  }
  if (lo == 0xFE) {
    int row = (port >> 8) & 255;
    int v = 0xFF;
    if (row == 0xDF) { if (cur_keys & 1) v &= ~2; if (cur_keys & 2) v &= ~1; }
    if (row == 0x7F) { if (cur_keys & 16) v &= ~1; if (cur_keys & 4) v &= ~8; if (cur_keys & 8) v &= ~16; }
    if (row == 0xFB) { if (cur_keys & 32) v &= ~16; if (cur_keys & 64) v &= ~1; }
    if (row == 0xFD && (cur_keys & 128)) v &= ~1;
    if (row == 0xF7 && (cur_keys & 256)) v &= ~8; if (row == 0xF7 && (cur_keys & 512)) v &= ~1; if (row == 0xF7 && (cur_keys & 1024)) v &= ~2; if (row == 0xF7 && (cur_keys & 2048)) v &= ~4;                   // tecla 4: salta la cutscene
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
      if (sscanf(line, "%127s EQU %xH", name, &v) == 2 && !strcmp(name, "main_loop")) main_loop_addr = v;
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
      for (char ch : it.substr(0, c)) { if (ch == 'O') keys |= 1; if (ch == 'P') keys |= 2; if (ch == 'S') keys |= 16; if (ch == 'N') keys |= 4; if (ch == 'B') keys |= 8; if (ch == 'T') keys |= 32; if (ch == 'Q') keys |= 64; if (ch == 'A') keys |= 128; if (ch == '4') keys |= 256; if (ch == '1') keys |= 512; if (ch == '2') keys |= 1024; if (ch == '3') keys |= 2048; }
      script.push_back({atoi(it.substr(c + 1).c_str()), keys});
      p = q + 1;
    }
  }
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
  z80.pc.w = 0x4212; z80.halted = 0; z80.iff1 = z80.iff2 = 0;
  if (const char* w = getenv("TS_WATCH")) { unsigned lo = 0, hi = 0, fr = 0; sscanf(w, "%x-%x,%u", &lo, &hi, &fr); w_lo = lo; w_hi = hi; w_from = fr; }
  long long steps = 0;
  size_t ki = 0;
  static int hist[256]; static int hi = 0;           // ultimos PC, para ver como se escapa el programa
  while (!finished) {
    if (z80.pc.w == main_loop_addr) {
      frames_done++; g_fr = frames_done;
      if (const char* pk = getenv("TS_POKE")) {            // TS_POKE=fotograma:direccion:valor[,...]: escribe un byte (hex) en ese fotograma
        unsigned f, a, v; const char* p = pk;
        while (sscanf(p, "%u:%x:%x", &f, &a, &v) == 3) { if ((int)f == frames_done) wr(a, v); p = strchr(p, ','); if (!p) break; p++; }
      }
      while (ki < script.size() && script[ki].frame <= frames_done) { cur_keys = script[ki].keys; ki++; }
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
    if (getenv("TS_BP") && z80.pc.w == (unsigned)strtol(getenv("TS_BP"), 0, 16) && (!getenv("TS_BPA") || (z80.af.w >> 8) == (unsigned)strtol(getenv("TS_BPA"), 0, 16))) {   // TS_BP=direccion (hex): para ahi e imprime los ultimos PC, SP y la pila
      printf("TS_BP pc=%04X sp=%04X af=%04X bc=%04X de=%04X hl=%04X ix=%04X iy=%04X; pila:", z80.pc.w, z80.sp.w, z80.af.w, z80.bc.w, z80.de.w, z80.hl.w, z80.ix.w, z80.iy.w);
      for (int k = 0; k < 6; k++) printf(" %04X", rd16(z80.sp.w + 2 * k));
      printf("%cultimos PC:", 10);
      for (int k = 40; k > 0; k--) printf(" %04X", hist[(hi - k) & 255]);
      printf("%c", 10);
      if (!getenv("TS_TRACE")) break;
      for (int k = 0; k < atoi(getenv("TS_TRACE")); k++) { printf("%04X(%02X) ", z80.pc.w, rd(z80.pc.w)); z80_do_opcode(); }
      printf("%c", 10); break;
    }
    hist[hi++ & 255] = z80.pc.w;
    z80_do_opcode();
    if (steps > 50000000LL && !getenv("TS_NOSTOP")) { printf("atascado; ultimos PC:%c", 10); for (int k = 120; k > 0; k--) printf("%04X ", hist[(hi - k) & 255]); printf("%c", 10); break; }
    if (++steps > 2000000000LL) { printf("demasiadas instrucciones, pc=%04X%c", z80.pc.w, 10); break; }
  }
  printf("fotogramas: %d, instrucciones: %lld, ERR=%d, sala=%d%c", frames_done, steps, rd(0xEB0B), rd(0xEB40), 10);
  dump(argv[5]);
  return 0;
}

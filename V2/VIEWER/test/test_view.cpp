// Arnes de PC de ROOMVIEW (SCUMM/V2/VIEWER/roomview.asm): el Z80 de EightyOne con un MCU simulado que sirve los
// ROOMnn.GFX de una carpeta, un teclado con guion y la memoria plana. Al pulsar ESPACIO vuelca los 64 KB
// (memoria de pantalla, tablas de caracteres y de color, variables) para que check_view.py los compare con
// lo que debe verse.
//
// Uso: test_view roomview.bin gfx_dir salida.bin sala "guion"
//   guion = pares  tecla:fotogramas  separados por comas; teclas O P N B (una o mas letras juntas) o - (nada)
//           p. ej. "-:5,P:300,O:100"  (al acabar el guion se pulsa ESPACIO)
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

static uint8_t mem[65536];
static std::string gfx_dir;
static FILE* dump_file = nullptr;
static std::string dump_path;

// ---- MCU simulado
static int clk = 0;
static std::vector<uint8_t> inq, outq;
static size_t outpos = 0;
static FILE* files[8];
static std::string cmd_name;
static int cmd = -1, cmd_arg = 0, name_len = 0, cnt = 0, rd_h = 0, rd_n = 0;

static void mcu_byte(uint8_t b) {
  if (cmd < 0) {
    cmd = b; cmd_arg = 0; cmd_name.clear(); name_len = 0; cnt = 0; rd_h = rd_n = 0;
    if (cmd == 0x41 || cmd == 0x1C) cmd = -1;                      // 256C / 64C: sin respuesta
    return;
  }
  if (cmd == 53) {                                                  // fopen: longitud, nombre
    if (cnt == 0) { name_len = b; cnt = 1; }
    else {
      cmd_name += (char)b; cnt++;
      if ((int)cmd_name.size() == name_len) {
        std::string p = cmd_name;
        size_t k = p.rfind('/');
        std::string base = k == std::string::npos ? p : p.substr(k + 1);
        FILE* f = fopen((gfx_dir + "/" + base).c_str(), "rb");
        int h = 0xFF;
        if (f) { for (int i = 0; i < 8; i++) if (!files[i]) { files[i] = f; h = i; break; } }
        outq.push_back((uint8_t)h);
        cmd = -1;
      }
    }
  } else if (cmd == 59) {                                           // fstat
    FILE* f = files[b & 7];
    long sz = 0;
    if (f) { long cur = ftell(f); fseek(f, 0, SEEK_END); sz = ftell(f); fseek(f, cur, SEEK_SET); }
    for (int i = 0; i < 4; i++) outq.push_back((sz >> (8 * i)) & 255);
    for (int i = 0; i < 4; i++) outq.push_back(0);
    outq.push_back(0);
    cmd = -1;
  } else if (cmd == 55) {                                           // fread: handle, n lo, n hi
    if (cnt == 0) { rd_h = b & 7; cnt = 1; }
    else if (cnt == 1) { rd_n = b; cnt = 2; }
    else {
      rd_n |= b << 8;
      FILE* f = files[rd_h];
      for (int i = 0; i < rd_n; i++) { int c = f ? fgetc(f) : 0; outq.push_back(c < 0 ? 0 : c); }
      outq.push_back(0);
      cmd = -1;
    }
  } else if (cmd == 57) {                                           // fclose
    int h = b & 7;
    if (files[h]) { fclose(files[h]); files[h] = nullptr; }
    outq.push_back(0);
    cmd = -1;
  } else {
    printf("orden del MCU desconocida: %d\n", cmd);
    exit(3);
  }
}

// ---- teclado con guion
struct Step { int keys; int frames; };
static std::vector<Step> script;
static size_t sp_i = 0;
static int sp_left = 0;
static int cur_keys = 0;           // bits 0 O, 1 P, 2 N, 3 B, 4 ESPACIO
static bool finished = false;
static void next_step() {
  if (sp_i < script.size()) { cur_keys = script[sp_i].keys; sp_left = script[sp_i].frames; sp_i++; }
  else { cur_keys = 16; sp_left = 1000000; }
}
static void dump() {
  FILE* f = fopen(dump_path.c_str(), "wb");
  fwrite(mem, 1, 65536, f);
  fclose(f);
  finished = true;
}

extern "C" {
int z80_contend_wrapper(int, int, int t) { return t; }
int z80_contend_io_wrapper(int, int, int t) { return t; }
BYTE z80_readbyte_wrapper(int a) { return mem[a & 0xFFFF]; }
BYTE z80_readoperandbyte_wrapper(int a) { return mem[a & 0xFFFF]; }
BYTE z80_opcode_fetch_wrapper(int a) { z80_fetch_is_m1 = 0; return mem[a & 0xFFFF]; }
void z80_writebyte_wrapper(int a, int d) { mem[a & 0xFFFF] = (uint8_t)d; }
void z80_writeport_wrapper(int port, int d, int*) {

  if ((port & 0xFF) == 0xA7) { mcu_byte(d & 255); clk ^= 1; }
}
BYTE z80_readport_wrapper(int port, int*) {
  int lo = port & 0xFF;
    if (lo == 0xAF) return (clk << 7) | 0x02;                         // reloj del MCU y un VSYNC
  if (lo == 0xA7) {
    uint8_t v = outpos < outq.size() ? outq[outpos++] : 0;
    if (outpos >= outq.size()) { outq.clear(); outpos = 0; }
    clk ^= 1;
    return v;
  }
  if (lo == 0xFE) {
    int row = (port >> 8) & 255;
    if (row == 0xDF) {                                              // P O I U Y : esta es la que se lee una vez por fotograma
      if (sp_left > 0 && --sp_left == 0) next_step();
      if (cur_keys & 16) { dump(); }
      int v = 0xFF;
      if (cur_keys & 1) v &= ~2;                                    // O
      if (cur_keys & 2) v &= ~1;                                    // P
      return v;
    }
    if (row == 0x7F) {
      int v = 0xFF;
      if (cur_keys & 4) v &= ~8;                                    // N
      if (cur_keys & 8) v &= ~16;                                   // B
      if (cur_keys & 16) v &= ~1;                                   // ESPACIO
      return v;
    }
    return 0xFF;
  }
  return 0xFF;
}
}

int main(int argc, char** argv) {
  if (argc < 5) { printf("uso: test_view roomview.bin gfx_dir salida.bin sala [guion]\n"); return 2; }
  FILE* f = fopen(argv[1], "rb");
  if (!f) return 2;
  size_t n = fread(mem + 24576, 1, 8192, f);
  fclose(f);
  gfx_dir = argv[2];
  dump_path = argv[3];
  int room = atoi(argv[4]);
  std::string sc = argc > 5 ? argv[5] : "";
  size_t p = 0;
  while (p < sc.size()) {
    size_t q = sc.find(',', p);
    if (q == std::string::npos) q = sc.size();
    std::string item = sc.substr(p, q - p);
    size_t c = item.find(':');
    int keys = 0;
    for (char ch : item.substr(0, c)) {
      if (ch == 'O') keys |= 1;
      if (ch == 'P') keys |= 2;
      if (ch == 'N') keys |= 4;
      if (ch == 'B') keys |= 8;
    }
    script.push_back({keys, atoi(item.substr(c + 1).c_str())});
    p = q + 1;
  }
  next_step();
  mem[0x02E7] = 0xC9;                                               // SET_FAST y SLOW_FAST de la ROM: RET
  mem[0x0207] = 0xC9;
  for (int i = 0; i < 512; i++) mem[0x1E00 + i] = (uint8_t)(i * 37 + 11);
  for (int a = 24576; a < 24576 + 400; a++)                        // la sala de arranque: el LD A,1 / LD (room),A del principio
    if (mem[a] == 0x3E && mem[a + 1] == 0x01 && mem[a + 2] == 0x32 && mem[a + 3] == 0x00 && mem[a + 4] == 0x7F) { mem[a + 1] = (uint8_t)room; break; }
  z80_init(); z80_reset();
  z80.sp.w = 0x7FF0;
  mem[0x7FF0] = 0x00; mem[0x7FF1] = 0x01;
  mem[0x0100] = 0x76;
  z80.pc.w = 24576; z80.halted = 0; z80.iff1 = z80.iff2 = 0;
  long long steps = 0;
  while (!finished) {
    z80_do_opcode();
    if (++steps > 20000000LL) { printf("demasiadas instrucciones, pc=%04X sp=%04X hl=%04X de=%04X bc=%04X\n", z80.pc.w, z80.sp.w, z80.hl.w, z80.de.w, z80.bc.w); return 4; }
  }
  printf("ok: %lld instrucciones\n", steps);
  return 0;
}

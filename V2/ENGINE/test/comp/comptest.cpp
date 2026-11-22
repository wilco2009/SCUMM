// Corre compose.asm (comptest.bin en $8000) con el Z80 de EightyOne en 64 KB planos y cuenta los T-estados.
// Uso: comptest comptest.bin entrada.bin salida.bin   entrada = traje(@$C000) + emap(16 @$B000) + miembros(16 @$B010) + espejo(1)
#include <cstdio>
#include <cstdint>
#include <vector>
#include <map>
#include <string>
#include <cstring>
#include <algorithm>
extern "C" {
#include "z80.h"
int tstates = 0;
int StackChange = 0, StepOutRequested = 0, RetExecuted = 0;
int z80_fetch_is_m1 = 0;
void z80_m1_backtrack(void) {}
void debug(int) {}
}
static uint8_t m[65536];
extern "C" {
int z80_contend_wrapper(int, int, int t) { return t; }
int z80_contend_io_wrapper(int, int, int t) { return t; }
BYTE z80_readbyte_wrapper(int a) { return m[a & 0xFFFF]; }
BYTE z80_readoperandbyte_wrapper(int a) { return m[a & 0xFFFF]; }
BYTE z80_opcode_fetch_wrapper(int a) { return m[a & 0xFFFF]; }
void z80_writebyte_wrapper(int a, int d) { m[a & 0xFFFF] = d; }
void z80_writeport_wrapper(int, int, int*) {}
BYTE z80_readport_wrapper(int, int*) { return 0xFF; }
}
int main(int argc, char** argv) {
  FILE* f = fopen(argv[1], "rb"); fread(m + 0x8000, 1, 0x3000, f); fclose(f);
  f = fopen(argv[2], "rb"); std::vector<uint8_t> in(65536); size_t n = fread(in.data(), 1, in.size(), f); fclose(f);
  size_t cl = n - 33;
  for (size_t i = 0; i < cl; i++) m[0xC000 + i] = in[i];
  for (int i = 0; i < 16; i++) m[0xB000 + i] = in[cl + i];
  for (int i = 0; i < 16; i++) m[0xB010 + i] = in[cl + 16 + i];
  m[0x7F00] = 0x00; m[0x7F01] = 0xC0; m[0x7F02] = 0x00; m[0x7F03] = 0xB0; m[0x7F04] = 0x10; m[0x7F05] = 0xB0;
  m[0x7F06] = in[cl + 32]; m[0x7F08] = 0x00; m[0x7F09] = 0x90; m[0x7F0A] = 0x00; m[0x7F0B] = 0xA0;
  z80_init(); z80_reset();
  z80.sp.w = 0x7E00; m[0x7DFE] = 0x00; m[0x7DFF] = 0x00; z80.sp.w = 0x7DFE;   // RET a $0000: fin
  z80.pc.w = 0x8000;
  std::vector<std::pair<int,std::string>> syms;
  if (getenv("PROF")) { FILE* s = fopen(getenv("PROF"), "r"); char line[256]; char nm[128]; unsigned v;
    while (s && fgets(line, sizeof line, s)) if (sscanf(line, "%127s EQU %xH", nm, &v) == 2 && v >= 0x8000 && v < 0xB000) syms.push_back({(int)v, nm});
    if (s) fclose(s); std::sort(syms.begin(), syms.end()); }
  std::map<std::string,long long> prof;
  long long t = 0; int guard = 0;
  while (z80.pc.w != 0x0000 && guard < 20000000) { int pc = z80.pc.w; int dt = z80_do_opcode(); t += dt; guard++;
    if (!syms.empty()) { auto it = std::upper_bound(syms.begin(), syms.end(), std::make_pair(pc, std::string(""))); if (it != syms.begin()) { --it; prof[it->second] += dt; } } }
  if (!syms.empty()) { std::vector<std::pair<long long,std::string>> v; for (auto& kv : prof) v.push_back({kv.second, kv.first}); std::sort(v.rbegin(), v.rend()); for (size_t i = 0; i < v.size() && i < 25; i++) printf("  %-10s %8lld%c", v[i].second.c_str(), v[i].first, 10); }
  printf("T=%lld carry=%d%c", t, z80.af.b.l & 1, 10);
  f = fopen(argv[3], "wb"); fwrite(m + 0xA000, 1, 0x1000, f); fclose(f);
}

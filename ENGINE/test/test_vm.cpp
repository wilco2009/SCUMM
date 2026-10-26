// Arnes de PC del nucleo del interprete SCUMM (SCUMM/ENGINE/vm.asm).
//
// El Z80 de verdad (nucleo de EightyOne) ejecuta vm.bin con la memoria paginada del SD81 Booster
// (64 paginas de 8 KB, 8 bloques, puerto E7h) y los scripts de Maniac Mansion en las paginas de datos.
// Lo que el nucleo no hace (actores, texto, sonido...) sale por el puerto $F1: este arnes lo anota en la
// traza y devuelve un resultado simulado, exactamente igual que el modelo de referencia en Python
// (SCUMM/TOOLS/vmmodel.py). Escribe la traza de cada escenario en el mismo formato que el modelo.
//
// Uso: test_vm vm.bin vm.sym world.bin scenarios.txt actual.txt
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

// ---------------------------------------------------------------- memoria paginada
static uint8_t ram[64][8192];
static int blk[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static inline uint8_t rd(int a) { a &= 0xFFFF; return ram[blk[a >> 13]][a & 0x1FFF]; }
static inline void wr(int a, uint8_t v) { a &= 0xFFFF; if ((a >> 13) == 0) return; ram[blk[a >> 13]][a & 0x1FFF] = v; }
static inline uint16_t rd16(int a) { return rd(a) | (rd(a + 1) << 8); }
static inline void wr16(int a, uint16_t v) { wr(a, v & 255); wr(a + 1, v >> 8); }

// direcciones del nucleo (iguales que en vm.asm)
enum {
  VARS = 0xE000, OBJST = 0xE200, OBJOWN = 0xE520, SLOTS = 0xE900, NEST = 0xEA80, ARGS = 0xEAC0, CUR = 0xEB00,
  SPTR = 0xEB01, OPC = 0xEB03, NESTN = 0xEB04, ARGN = 0xEB05, HRES = 0xEB06, HFLAG = 0xEB08, ERR = 0xEB0B,
  DELTA = 0xEB0C, EVID = 0xEB4E, EVARGS = 0xEB50, ACTORS = 0xEF00, ROOMDIR = 0xF400, NACT = 25, ASZ = 48, APIW = 0xEB10, APIN = 0xEB11, APIP = 0xEB13, APIA = 0xEB14, APIVERB = 0xEB16, SCRDIR = 0xEC00,
  NSLOT = 24, NOBJ = 780
};
static uint16_t API_INIT = 0x4200, API_RUN_EXT = 0x4203, API_RUN_OBJECT = 0x4206, API_RUN_SCRIPT = 0x4209, API_FRAME = 0x420C, API_LOAD_ROOM = 0x420F;

// ---------------------------------------------------------------- el mundo
struct Dir { int page, addr, size; };
static std::map<int, Dir> sdir, odir;               // id de script / de objeto
static std::map<int, Dir> rdir[4];                  // [1] entrada, [2] salida, [3] cajas y objetos: por sala
static std::vector<uint8_t> w_owner, w_state;
static std::map<int, int> rwidth;

static bool load_world(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) return false;
  char magic[4];
  if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "VMW1", 4)) return false;
  uint16_t n;
  auto r8 = [&]() { int c = fgetc(f); return c; };
  auto r16 = [&]() { int a = fgetc(f); int b = fgetc(f); return a | (b << 8); };
  n = r16();
  for (int i = 0; i < n; i++) { int pg = r8(); if (fread(ram[pg], 1, 8192, f) != 8192) return false; }
  n = r16();
  for (int i = 0; i < n; i++) { int id = r16(); int pg = r8(); int ad = r16(); sdir[id] = {pg, ad, 0}; }
  n = r16();
  for (int i = 0; i < n; i++) { int id = r16(); r16(); int pg = r8(); int ad = r16(); int sz = r16(); odir[id] = {pg, ad, sz}; }
  n = r16();
  for (int i = 0; i < n; i++) { int rm = r8(); int kind = r8(); int pg = r8(); int ad = r16(); int sz = r16(); rdir[kind][rm] = {pg, ad, sz}; }
  n = r16();
  w_owner.resize(n); w_state.resize(n);
  if (fread(w_owner.data(), 1, n, f) != n) return false;
  if (fread(w_state.data(), 1, n, f) != n) return false;
  n = r16();
  for (int i = 0; i < n; i++) { int rm = r8(); int w = r16(); rwidth[rm] = w; }
  fclose(f);
  return true;
}

// ---------------------------------------------------------------- CRC-16/CCITT (como binascii.crc_hqx con 0xFFFF)
static uint16_t crc16(const uint8_t* d, size_t n) {
  uint16_t crc = 0xFFFF;
  for (size_t i = 0; i < n; i++) {
    crc ^= (uint16_t)d[i] << 8;
    for (int k = 0; k < 8; k++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
  }
  return crc;
}

// ---------------------------------------------------------------- el anfitrion simulado (igual que vmmodel.py)
static std::vector<std::string> trace;
static int frame = 0;
static uint32_t mock_hash(int op, const std::vector<uint16_t>& args) {
  uint32_t s = (op * 131 + frame * 17) & 0xFFFF;
  for (size_t i = 0; i < args.size(); i++) s = (s * 31 + args[i] + (uint32_t)i + 1) & 0xFFFF;
  return s;
}
// sucesos para el back-end (puerto $F2): el mismo formato y el mismo resultado simulado que vmgame.py
static int ev_argc(int id) { static const int n[] = {0, 1, 1, 0, 1, 3, 1, 3, 2}; return id >= 1 && id <= 8 ? n[id] : 0; }
static void event_trap(int id) {
  int n = ev_argc(id);
  std::vector<uint16_t> args;
  for (int i = 0; i < n; i++) args.push_back(rd16(EVARGS + 2 * i));
  std::string t = "E " + std::to_string(id) + " [";
  char b[16];
  for (int i = 0; i < n; i++) { snprintf(b, sizeof b, "%s%u", i ? "," : "", args[i]); t += b; }
  t += "]";
  trace.push_back(t);
  if (id == 4) wr16(HRES, mock_hash(0x100 + id, args) & 1);
}
static void host_trap(int op) {
  int n = rd(ARGN);
  std::vector<uint16_t> args;
  for (int i = 0; i < n; i++) args.push_back(rd16(ARGS + 2 * i));
  uint32_t s = mock_hash(op, args);
  wr16(HRES, s & 0xFF);
  wr(HFLAG, (s >> 8) & 1);
  std::string t;
  char b[16];
  snprintf(b, sizeof b, "H %02X [", op);
  t = b;
  for (int i = 0; i < n; i++) { snprintf(b, sizeof b, "%s%u", i ? "," : "", args[i]); t += b; }
  t += "]";
  trace.push_back(t);
}

// ---------------------------------------------------------------- MCU simulado (ficheros de la SD): solo para probar loader.asm
static std::string sd_dir;
static int mcu_clk = 0;
static std::vector<uint8_t> mcu_out;
static size_t mcu_outpos = 0;
static FILE* mcu_files[8];
static std::string mcu_name;
static int mcu_cmd = -1, mcu_cnt = 0, mcu_nlen = 0, mcu_h = 0, mcu_n = 0;
static void mcu_byte(uint8_t b) {
  if (mcu_cmd < 0) { mcu_cmd = b; mcu_cnt = 0; mcu_name.clear(); mcu_nlen = 0; if (b == 29) mcu_cmd = -1; return; }   // 29: FULLPAGING, sin respuesta
  if (mcu_cmd == 53) {                                            // fopen
    if (mcu_cnt == 0) { mcu_nlen = b; mcu_cnt = 1; }
    else {
      mcu_name += (char)b;
      if ((int)mcu_name.size() == mcu_nlen) {
        size_t k = mcu_name.rfind('/');
        std::string base = k == std::string::npos ? mcu_name : mcu_name.substr(k + 1);
        FILE* f = fopen((sd_dir + "/" + base).c_str(), "rb");
        int h = 0xFF;
        if (f) for (int i = 0; i < 8; i++) if (!mcu_files[i]) { mcu_files[i] = f; h = i; break; }
        mcu_out.push_back((uint8_t)h);
        mcu_cmd = -1;
      }
    }
  } else if (mcu_cmd == 55) {                                     // fread: manejador, n lo, n hi
    if (mcu_cnt == 0) { mcu_h = b & 7; mcu_cnt = 1; }
    else if (mcu_cnt == 1) { mcu_n = b; mcu_cnt = 2; }
    else {
      mcu_n |= b << 8;
      FILE* f = mcu_files[mcu_h];
      for (int i = 0; i < mcu_n; i++) { int c = f ? fgetc(f) : 0; mcu_out.push_back(c < 0 ? 0 : c); }
      mcu_out.push_back(0);
      mcu_cmd = -1;
    }
  } else if (mcu_cmd == 57) {                                     // fclose
    int h = b & 7;
    if (mcu_files[h]) { fclose(mcu_files[h]); mcu_files[h] = nullptr; }
    mcu_out.push_back(0);
    mcu_cmd = -1;
  } else { printf("orden del MCU desconocida: %d%c", mcu_cmd, 10); exit(3); }
}

// ---------------------------------------------------------------- el Z80
static long instr_total = 0, vm_insns = 0;
static long long ts_total = 0, ts_frames = 0, ts_vm = 0;   // T-states: total, solo bucles de fotograma, solo instrucciones de script
static int ts_mode = 0;
static uint16_t es_noerr_addr = 0;
extern "C" {
int z80_contend_wrapper(int, int, int t) { return t; }
int z80_contend_io_wrapper(int, int, int t) { return t; }
BYTE z80_readbyte_wrapper(int a) { return rd(a); }
BYTE z80_readoperandbyte_wrapper(int a) { return rd(a); }
BYTE z80_opcode_fetch_wrapper(int a) { z80_fetch_is_m1 = 0; return rd(a); }
void z80_writebyte_wrapper(int a, int d) { wr(a, (uint8_t)d); }
void z80_writeport_wrapper(int port, int d, int*) {
  if ((port & 0xFF) == 0xE7) blk[d & 7] = (port >> 8) & 0x3F;            // mapeador: B = pagina, dato = bloque
  else if ((port & 0xFF) == 0xF1) host_trap(d & 0xFF);                     // llamada al anfitrion
  else if ((port & 0xFF) == 0xF2) event_trap(d & 0xFF);                    // suceso para el back-end
  else if ((port & 0xFF) == 0xA7) { mcu_byte(d & 255); mcu_clk ^= 1; }
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
  return 0xFF;
}
}

static bool err_logged = false;
static int bp_addr = 0;
static long call_limit = 40000000L;
static bool z80_call(uint16_t addr) {
  z80.sp.w = 0x7FF0;
  wr(0x7FF0, 0x00); wr(0x7FF1, 0x01);
  ram[0][0x100] = 0x76;                    // trampa: HALT en $0100 (el bloque 0 es de solo lectura para el Z80)
  z80.pc.w = addr; z80.halted = 0; z80.iff1 = z80.iff2 = 0;
  long n = 0;
  long long tsum = 0;
  while (z80.pc.w != 0x0100) {
    if (z80.pc.w == es_noerr_addr) { vm_insns++; if (getenv("TV_TRACE")) fprintf(stderr, "  op %02X ptr %04X cur=%d%c", rd(0xEB03), rd16(0xEB01), rd(0xEB00), 10); }
    tstates = 0;
    int ppc = z80.pc.w;
    if (bp_addr && ppc == bp_addr) { fprintf(stderr, "BP %04X ARGS:", ppc); for (int k = 0; k < 8; k++) fprintf(stderr, " %04X", rd16(ARGS + 2 * k)); fprintf(stderr, "  HL=%04X A=%02X FO: X=%d Y=%d I=%d N=%d B=%d A=%d OBJSP=%04X NOBJS=%d%c", z80.hl.w, z80.af.b.h, rd16(0xF9F0), rd16(0xF9F2), rd(0xF9F6), rd(0xF9F7), rd(0xF9F8), rd(0xF9F9), rd16(0xF9C4), rd(0xF9C1), 10); { int base = rd16(0xF9C4) + 11 * rd(0xF9F6); fprintf(stderr, "   rec:"); for (int k = 0; k < 11; k++) fprintf(stderr, " %d", rd(base + k)); fprintf(stderr, "%c", 10); } }
    z80_do_opcode();
    if (getenv("TV_ERRPC") && rd(ERR) && !err_logged) { err_logged = true; fprintf(stderr, "ERR=%d tras la instruccion en %04X; pila: %04X %04X %04X %04X %04X%c", rd(ERR), ppc, rd16(z80.sp.w), rd16(z80.sp.w + 2), rd16(z80.sp.w + 4), rd16(z80.sp.w + 6), rd16(z80.sp.w + 8), 10); fprintf(stderr, "v8=%d v9=%d v10=%d v18=%d v26=%d v27=%d v28=%d%c", rd16(0xE010), rd16(0xE012), rd16(0xE014), rd16(0xE024), rd16(0xE034), rd16(0xE036), rd16(0xE038), 10); }
    tsum += tstates;
    instr_total++;
    if (++n > call_limit) return false;
  }
  ts_total += tsum;
  if (addr == API_FRAME) ts_frames += tsum;
  return true;
}

// ---------------------------------------------------------------- escenarios
static int cur_room = 0;
static long frames_run = 0, empty_frames = 0;
static long long ts_empty = 0, ts_busy = 0; static long busy_frames = 0, vm_busy = 0;
static std::string digest() {
  std::vector<uint8_t> v(512), o(NOBJ);
  for (int i = 0; i < 512; i++) v[i] = rd(VARS + i);
  for (int i = 0; i < NOBJ; i++) o[i] = rd(OBJST + i);
  char b[128];
  std::vector<uint8_t> ac(NACT * ASZ);
  for (int i = 0; i < NACT * ASZ; i++) ac[i] = rd(ACTORS + i);
  int td = rd16(0xEB44);
  int sn = rd(0xEB0D);
  std::vector<uint8_t> sq;
  for (int i = 0; i < sn; i++) { int a = 0xFE00 + 8 * i; for (int k = 0; k < 5; k++) sq.push_back(rd(a + k)); sq.push_back(rd(a + 5)); sq.push_back(0); sq.push_back(0); }
  // la cola en el formato del modelo: verbo, objeto A, objeto B, preposicion (B 2 + H 2 + H 2 + B + 2 de relleno): se rehace byte a byte
  std::vector<uint8_t> sq2;
  for (int i = 0; i < sn; i++) { int a = 0xFE00 + 8 * i; sq2.push_back(rd(a)); sq2.push_back(rd(a + 1)); sq2.push_back(rd(a + 2)); sq2.push_back(rd(a + 3)); sq2.push_back(rd(a + 4)); sq2.push_back(rd(a + 5)); sq2.push_back(0); sq2.push_back(0); }
  snprintf(b, sizeof b, "D f=%d V=%04X O=%04X A=%04X M=%d,%d,%d,%d,%d Q=%d,%04X S=", frame, crc16(v.data(), v.size()), crc16(o.data(), o.size()),
           crc16(ac.data(), ac.size()), rd(0xEB41), td, rd(0xEB42), rd(0xEB40), rd16(0xEB4A), sn, crc16(sq2.data(), sq2.size()));
  std::string s = b;
  bool first = true;
  for (int i = 0; i < NSLOT; i++) {
    int a = SLOTS + 16 * i;
    int st = rd(a);
    if (!st) continue;
    int wh = rd(a + 1), num = rd16(a + 2), ptr = rd16(a + 5);
    int base = 0;
    if (wh == 2) base = sdir.count(num) ? sdir[num].addr : 0;
    else if (num == 10002) base = rdir[1].count(rd(0xEB40)) ? rdir[1][rd(0xEB40)].addr : 0;
    else if (num == 10001) base = rdir[2].count(cur_room) ? rdir[2][cur_room].addr : 0;
    else if (num >= 9000 && num < 10000) base = sdir.count(num - 9000) ? sdir[num - 9000].addr : 0;
    else base = odir.count(num) ? odir[num].addr : 0;
    snprintf(b, sizeof b, "%s%d:%d:%d:%d:%d", first ? "" : " ", i, st, wh, num, ptr - base);
    s += b;
    first = false;
    if ((st & 0x7F) == 1) {
      uint32_t d = rd16(a + 7) | ((uint32_t)rd16(a + 9) << 16);
      snprintf(b, sizeof b, ":%u", d);
      s += b;
    }
  }
  return s;
}

static void flush_trace(FILE* out) { for (auto& t : trace) fprintf(out, "%s\n", t.c_str()); trace.clear(); }

static bool check_err(FILE* out) {
  int e = rd(ERR);
  if (!e) return false;
  trace.push_back("ERR " + std::to_string(e));
  flush_trace(out);
  return true;
}

static bool run_call(uint16_t addr, FILE* out) {
  if (!z80_call(addr)) { trace.push_back("ERR 9"); flush_trace(out); return false; }
  return !check_err(out);
}

static void load_roomdir() {
  for (int r = 0; r < 64; r++) {
    int a = ROOMDIR + 16 * r;
    for (int i = 0; i < 16; i++) wr(a + i, 0);
    if (!rwidth.count(r)) continue;
    if (rdir[1].count(r)) { wr(a, rdir[1][r].page); wr16(a + 1, rdir[1][r].addr); }
    if (rdir[2].count(r)) { wr(a + 3, rdir[2][r].page); wr16(a + 4, rdir[2][r].addr); }
    wr16(a + 6, rwidth[r]);
    if (rdir[3].count(r)) { wr(a + 8, rdir[3][r].page); wr16(a + 9, rdir[3][r].addr); wr16(a + 11, rdir[3][r].size); }
  }
}
static bool use_data = false;
static std::vector<uint8_t> sn_scr, sn_own, sn_st, sn_room;      // las tablas tal como las dejo el cargador
static void load_odir() {
  for (int i = 0; i < 780 * 3; i++) wr(0x8B00 + i, 0);
  for (auto& kv : odir) { wr(0x8B00 + 3 * kv.first, kv.second.page); wr16(0x8B00 + 3 * kv.first + 1, kv.second.addr); }
}
static void init_world() {
  if (use_data) {
    for (size_t i = 0; i < sn_scr.size(); i++) wr(SCRDIR + (int)i, sn_scr[i]);
    for (size_t i = 0; i < sn_own.size(); i++) wr(OBJOWN + (int)i, sn_own[i]);
    for (size_t i = 0; i < sn_st.size(); i++) wr(OBJST + (int)i, sn_st[i]);
    for (size_t i = 0; i < sn_room.size(); i++) wr(ROOMDIR + (int)i, sn_room[i]);
    return;
  }
  load_roomdir();
  load_odir();
  for (int i = 0; i < NOBJ; i++) { wr(OBJST + i, w_state[i]); wr(OBJOWN + i, w_owner[i]); }
  for (int i = 0; i < 256; i++) { wr(SCRDIR + 3 * i, 0); wr16(SCRDIR + 3 * i + 1, 0); }
  for (auto& kv : sdir) { wr(SCRDIR + 3 * kv.first, kv.second.page); wr16(SCRDIR + 3 * kv.first + 1, kv.second.addr); }
}

int main(int argc, char** argv) {
  if (argc < 6) { printf("uso: test_vm vm.bin vm.sym world.bin scenarios.txt actual.txt\n"); return 2; }
  FILE* f = fopen(argv[1], "rb");
  if (!f) { printf("no encuentro %s\n", argv[1]); return 2; }
  std::vector<uint8_t> code(16384);
  size_t sz = fread(code.data(), 1, code.size(), f); fclose(f);
  for (size_t i = 0; i < sz; i++) ram[2][0x200 + i] = code[i];        // $4200
  printf("vm.bin: %zu bytes en $4200\n", sz);
  { FILE* s = fopen(argv[2], "r"); char line[256];
    while (s && fgets(line, sizeof line, s)) {
      char name[128]; unsigned v;
      if (sscanf(line, "%127s EQU %xH", name, &v) == 2 && !strcmp(name, "es_noerr")) es_noerr_addr = v;
    }
    if (s) fclose(s); }
  if (const char* bn = getenv("TV_BP")) { FILE* s3 = fopen(argv[2], "r"); char l3[256]; while (s3 && fgets(l3, sizeof l3, s3)) { char nm[128]; unsigned v; if (sscanf(l3, "%127s EQU %xH", nm, &v) == 2 && !strcmp(nm, bn)) bp_addr = v; } if (s3) fclose(s3); }
  if (!es_noerr_addr) { printf("no encuentro es_noerr en %s\n", argv[2]); return 2; }
  if (!load_world(argv[3])) { printf("no puedo leer %s\n", argv[3]); return 2; }
  z80_init(); z80_reset();
  if (argc >= 8 && !strcmp(argv[6], "--data")) {      // el mundo lo carga el Z80 de DATA.BIN (loader.asm) en vez del arnes
    use_data = true;
    std::string dp = argv[7];
    size_t k = dp.find_last_of("/\\");
    sd_dir = k == std::string::npos ? "." : dp.substr(0, k);
    for (int p = 8; p < 64; p++) memset(ram[p], 0, sizeof ram[p]);
    unsigned lt = 0;
    { FILE* s2 = fopen(argv[2], "r"); char l2[256];
      while (s2 && fgets(l2, sizeof l2, s2)) { char nm[128]; unsigned v; if (sscanf(l2, "%127s EQU %xH", nm, &v) == 2 && !strcmp(nm, "lt_entry")) lt = v; }
      if (s2) fclose(s2); }
    if (!lt) { printf("no encuentro lt_entry%c", 10); return 2; }
    for (int i = 0; i < 8; i++) blk[i] = i;
    for (int i = 0; i < 0x1800 * 2; i++) wr(0x8000 + i, 0);
    if (!z80_call(lt)) { printf("el cargador no acaba%c", 10); return 2; }
    for (int i = 0; i < 8; i++) blk[i] = i;
    for (int i = 0; i < 768; i++) sn_scr.push_back(rd(SCRDIR + i));
    for (int i = 0; i < NOBJ; i++) { sn_own.push_back(rd(OBJOWN + i)); sn_st.push_back(rd(OBJST + i)); }
    for (int i = 0; i < 1024; i++) sn_room.push_back(rd(ROOMDIR + i));
    printf("datos cargados por el Z80 desde %s%c", argv[7], 10);
  }

  FILE* sc = fopen(argv[4], "r");
  FILE* out = fopen(argv[5], "w");
  if (!sc || !out) { printf("no puedo abrir los ficheros\n"); return 2; }
  char line[512];
  int nsc = 0;
  bool aborted = false;
  while (fgets(line, sizeof line, sc)) {
    line[strcspn(line, "\r\n")] = 0;
    if (!strncmp(line, "SCENARIO ", 9)) {
      fprintf(out, "%s\n", line);
      trace.clear(); frame = 0; cur_room = 0; aborted = false; nsc++;
      for (int i = 0; i < 8; i++) blk[i] = i;
      init_world();
      continue;
    }
    if (!strcmp(line, "END")) { if (!aborted) flush_trace(out); fprintf(out, "END\n"); continue; }
    if (aborted) continue;
    char cmd[16];
    int a = 0, b = 0;
    if (sscanf(line, "%15s %d %d", cmd, &a, &b) < 1) continue;
    if (!strcmp(cmd, "INIT")) {
      for (int i = 0; i < 8; i++) blk[i] = i;
      init_world();
      if (!run_call(API_INIT, out)) aborted = true;
      // el arnes recoge los sucesos y las llamadas al anfitrion con dos resquicios en RAM: OUT ($F2),A / OUT ($F1),A y RET
      wr(0x7B00, 0xD3); wr(0x7B01, 0xF2); wr(0x7B02, 0xC9); wr(0x7B04, 0xD3); wr(0x7B05, 0xF1); wr(0x7B06, 0xC9);
      wr16(0xEB6B, 0x7B00); wr16(0xEB6F, 0x7B04);
    } else if (!strcmp(cmd, "SETVAR")) {
      wr16(VARS + 2 * a, (uint16_t)b);
    } else if (!strcmp(cmd, "SCRIPT")) {
      wr16(APIN, a);
      if (!run_call(API_RUN_SCRIPT, out)) { aborted = true; continue; }
      flush_trace(out); fprintf(out, "%s\n", digest().c_str());
    } else if (!strcmp(cmd, "ROOMSCRIPT")) {
      Dir d = sdir[a];
      wr(APIW, 1); wr16(APIN, 9000 + a); wr(APIP, d.page); wr16(APIA, d.addr);
      if (!run_call(API_RUN_EXT, out)) { aborted = true; continue; }
      flush_trace(out); fprintf(out, "%s\n", digest().c_str());
    } else if (!strcmp(cmd, "LOADROOM")) {
      wr16(APIN, a);
      if (!run_call(API_LOAD_ROOM, out)) { aborted = true; continue; }
      flush_trace(out); fprintf(out, "%s\n", digest().c_str());
    } else if (!strcmp(cmd, "ENTRY") || !strcmp(cmd, "EXIT")) {
      int kind = !strcmp(cmd, "ENTRY") ? 1 : 2;
      cur_room = a;
      if (rdir[kind].count(a)) {
        Dir d = rdir[kind][a];
        wr(APIW, 1); wr16(APIN, kind == 1 ? 10002 : 10001); wr(APIP, d.page); wr16(APIA, d.addr);
        if (!run_call(API_RUN_EXT, out)) { aborted = true; continue; }
      }
      flush_trace(out); fprintf(out, "%s\n", digest().c_str());
    } else if (!strcmp(cmd, "OBJ")) {
      Dir d = odir[a];
      wr16(APIN, a); wr(APIP, d.page); wr16(APIA, d.addr); wr(APIVERB, b);
      if (!run_call(API_RUN_OBJECT, out)) { aborted = true; continue; }
      flush_trace(out); fprintf(out, "%s\n", digest().c_str());
    } else if (!strcmp(cmd, "INPUT")) {                // un clic o una tecla para el siguiente fotograma
      wr(0xEB72, 1); wr(0xEB73, (uint8_t)a); wr16(0xEB74, (uint16_t)b);
    } else if (!strcmp(cmd, "FRAMES")) {
      for (int i = 0; i < b; i++) {
        frame++; frames_run++;
        wr(DELTA, a);
        long vm0 = vm_insns; long long ts0 = ts_frames;
        if (!run_call(API_FRAME, out)) { aborted = true; break; }
        if (vm_insns == vm0) { empty_frames++; ts_empty += ts_frames - ts0; } else { busy_frames++; ts_busy += ts_frames - ts0; vm_busy += vm_insns - vm0; }
        trace.push_back(digest());
        flush_trace(out);
      }
    } else {
      printf("orden desconocida: %s\n", line);
    }
  }
  fclose(out); fclose(sc);
  printf("%d escenarios; instrucciones del Z80: %ld; instrucciones de script: %ld; Z80 por instruccion de script: %.0f\n",
         nsc, instr_total, vm_insns, vm_insns ? (double)instr_total / vm_insns : 0.0);
  printf("T-states: total %lld, en vm_frame %lld; fotogramas: %ld; T-states por fotograma %.0f\n", ts_total, ts_frames, frames_run, frames_run ? (double)ts_frames / frames_run : 0.0);
  printf("fotogramas sin ninguna instruccion de script: %ld, %.0f T-states cada uno (coste fijo de recorrer las ranuras)\n", empty_frames, empty_frames ? (double)ts_empty / empty_frames : 0.0);
  if (vm_busy && empty_frames) printf("fotogramas con script: %ld, %ld instrucciones de script; sin el coste fijo: %.0f T-states por instruccion de script\n", busy_frames, vm_busy, ((double)ts_busy - (double)busy_frames * ts_empty / empty_frames) / vm_busy);
  return 0;
}

// Arnes de PC del nucleo del interprete SCUMM v3 (SCUMM/V3/ENGINE/vm.asm + ovlb.asm). Fase 3 de SCUMM/V3/PLAN.md.
//
// El Z80 de EightyOne ejecuta vm.bin con la memoria paginada del SD81 Booster (bloques de 8 KB, puerto E7h). El mundo es
// DATA.BIN de V3/TOOLS/pack_data3.py (el mismo fichero que carga el programa de la placa): las tablas calientes van al bloque 7
// (SCRDIR, OBJOWN, OBJST, OBJCLS, BIGDIR), las frias a la pagina TABPG y la pagina de datos v a la pagina fisica 128 + v
// (vm.asm: map_page_x). El overlay B va a la pagina 49. Lo que no es nucleo sale por el puerto $F1: el arnes lo anota en la
// traza y devuelve el resultado simulado igual que el modelo (V3/TOOLS/vmmodel3.py, CoreVM).
//
// Uso: test_vm vm.bin vm.sym ovlb.bin DATA.BIN scenarios.txt actual.txt
// TS_VM=1: T-estados por instruccion de script (por opcode, con el despacho), como el TS_VM de V2/ENGINE/test/test_scumm.cpp.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include <algorithm>
extern "C" {
#include "z80.h"
int tstates = 0;
int StackChange = 0, StepOutRequested = 0, RetExecuted = 0;
int z80_fetch_is_m1 = 0;
void z80_m1_backtrack(void) {}
void debug(int) {}
}

// ---------------------------------------------------------------- memoria paginada (256 paginas en el arnes; la placa tiene 64)
static uint8_t ram[256][8192];
static int blk[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static inline uint8_t rd(int a) { a &= 0xFFFF; return ram[blk[a >> 13]][a & 0x1FFF]; }
static inline void wr(int a, uint8_t v) { a &= 0xFFFF; if ((a >> 13) == 0) return; ram[blk[a >> 13]][a & 0x1FFF] = v; }
static inline uint16_t rd16(int a) { return rd(a) | (rd(a + 1) << 8); }
static inline void wr16(int a, uint16_t v) { wr(a, v & 255); wr(a + 1, v >> 8); }

static std::map<std::string, int> sym;
static int S(const char* n) {
  auto it = sym.find(n);
  if (it == sym.end()) { printf("falta el simbolo %s%c", n, 10); exit(2); }
  return it->second;
}
static bool load_sym(const char* path) {
  FILE* s = fopen(path, "r");
  if (!s) return false;
  char line[256];
  while (fgets(line, sizeof line, s)) {
    char name[128]; unsigned v;
    if (sscanf(line, "%127s EQU %xH", name, &v) == 2) sym[name] = (int)v;
  }
  fclose(s);
  return true;
}

// direcciones (de vm.sym)
static int VARS, OBJST, OBJOWN, OBJCLS, SCRDIR, BIGDIR, SLOTS, LOCALS, CUTDATA, CUTSCR, CUTSP, ARGS, ARGN, HRES, HFLAG, ERR,
    DELTA, APIW, APIN, APIP, APIA, APIVERB, APIBIG, VACNT, VARARG, HOSTVEC, TOPOP, OPC, SPTR, CUR;
static int ACTORS, NEWNAMES, INVSL, EVARGS, EVVEC, CAMCUR, CAMDEST, CAMMODE, CAMFOL, CAMMOV, HAVEMSG, KEEPTXT, TALKDLY, LASTSND, CURROOM, ASIZE, NACT, NINV, NNAMES;
static int USERPUT, CURSTATE, MAINTOP, MAINH, STRLEN, STRPOS, STRHEAP, VERBS, VSZ, NVERB, NSTR, ACTNAMES;   // fase 4b-1
static int USETALK, STRSL, MSGPTR, MSGCNT, MSGEND, CHARCOL, MSGBUF;                                       // fase 4b-2
static int NSLOT, NLOCAL, TABPG, OVB_PAGE, COLD_ROOMDIR, COLD_ODIR, COLD_OBJROOM, COLD_COSTDIR, COLD_COSTDIR2;
static int API_INIT, API_RUN_EXT, API_RUN_OBJECT, API_RUN_SCRIPT, API_FRAME, API_SET_ROOM, API_ABORT;
static int ES_GO, ES_LOOP;
static const int TRAP = 0x7FFC, HOSTSTUB = 0x4100;   // (la pila del arnes baja desde $7FF0)

// ---------------------------------------------------------------- el mundo: DATA.BIN
static std::vector<uint8_t> data;
static int d_first = 0, d_npages = 0, d_tables = 0;
static int OFF_SCRDIR = 16, OFF_OBJOWN = 616, OFF_OBJST = 1616, OFF_OBJCLS = 2616, OFF_OBJROOM = 5616, OFF_ROOMDIR = 6616,
           OFF_ODIR = 9816, OFF_COSTDIR = 12816, OFF_COSTDIR2 = 13203, OFF_BIGDIR = 13590;   // pack_data3.OFFSETS
static int d8(int o) { return data[o]; }
static int d16(int o) { return data[o] | (data[o + 1] << 8); }
struct Loc { int page, addr; };
static std::map<int, std::map<int, Loc>> room_locals;   // sala -> id -> direccion
static bool load_data(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) return false;
  fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
  data.resize(n);
  if (fread(data.data(), 1, n, f) != (size_t)n) return false;
  fclose(f);
  if (memcmp(data.data(), "SDAT", 4) || data[4] != 3) { printf("%s no es un DATA.BIN de v3%c", path, 10); return false; }
  d_npages = data[5]; d_first = data[6]; d_tables = d16(13);
  int psz = d16(8);
  for (int i = 0; i < d_npages; i++) {
    int pg = 128 + d_first + i;
    if (pg > 255) { printf("demasiadas paginas%c", 10); return false; }
    memset(ram[pg], 0, 8192);
    memcpy(ram[pg], &data[d_tables + i * psz], psz);
  }
  for (int r = 0; r < 100; r++) {
    int e = OFF_ROOMDIR + 32 * r;
    int nl = d8(e + 9), tp = d8(e + 18), ta = d16(e + 19);
    for (int k = 0; k < nl; k++) {
      int a = ta - 0x2000 + 4 * k;
      uint8_t* p = ram[128 + tp];
      room_locals[r][p[a]] = {p[a + 1], p[a + 2] | (p[a + 3] << 8)};
    }
  }
  return true;
}
static void init_world() {
  for (int i = 0; i < 600; i++) wr(SCRDIR + i, data[OFF_SCRDIR + i]);
  for (int i = 0; i < 1000; i++) { wr(OBJOWN + i, data[OFF_OBJOWN + i]); wr(OBJST + i, data[OFF_OBJST + i]); }
  for (int i = 0; i < 3000; i++) wr(OBJCLS + i, data[OFF_OBJCLS + i]);
  for (int i = 0; i < 32; i++) wr(BIGDIR + i, data[OFF_BIGDIR + i]);
  uint8_t* c = ram[TABPG];
  memset(c, 0, 8192);
  memcpy(c + COLD_ROOMDIR, &data[OFF_ROOMDIR], 3200);
  memcpy(c + COLD_ODIR, &data[OFF_ODIR], 3000);
  memcpy(c + COLD_OBJROOM, &data[OFF_OBJROOM], 1000);
  memcpy(c + COLD_COSTDIR, &data[OFF_COSTDIR], 387);
  memcpy(c + COLD_COSTDIR2, &data[OFF_COSTDIR2], 387);
}

// ---------------------------------------------------------------- CRC-16/CCITT (binascii.crc_hqx con 0xFFFF)
static uint16_t crc16(const uint8_t* d, size_t n, uint16_t crc = 0xFFFF) {
  for (size_t i = 0; i < n; i++) {
    crc ^= (uint16_t)d[i] << 8;
    for (int k = 0; k < 8; k++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
  }
  return crc;
}

// ---------------------------------------------------------------- el anfitrion simulado (igual que vmmodel3.CoreVM)
static std::vector<std::string> trace;
static int frame = 0;
static uint32_t mock_hash(int op, const std::vector<uint16_t>& args) {
  uint32_t s = (op * 131 + frame * 17) & 0xFFFF;
  for (size_t i = 0; i < args.size(); i++) s = (s * 31 + args[i] + (uint32_t)i + 1) & 0xFFFF;
  return s;
}
// sucesos para el back-end (puerto $F2): el mismo formato y el mismo resultado simulado que vmgame3.py (GameMixin.ev)
static int ev_argc(int id) { static const int n[] = {0, 1, 1, 0, 1, 6, 1, 3, 2, 4, 1, 2, 3}; return id >= 1 && id <= 12 ? n[id] : 0; }
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
  char b[16];
  snprintf(b, sizeof b, "H %02X [", op);
  std::string t = b;
  for (int i = 0; i < n; i++) { snprintf(b, sizeof b, "%s%u", i ? "," : "", args[i]); t += b; }
  t += "]";
  trace.push_back(t);
}

// ---------------------------------------------------------------- el Z80 y la medida de T por instruccion
static long instr_total = 0, vm_insns = 0;
static long long tnow = 0;
static bool ts_vm = false;
struct Frame { long long t0; int sp; int op; long long nested; };
static std::vector<Frame> istk;
struct OpStat { long n = 0; long long excl = 0, incl = 0; };
static OpStat opst[256];
static std::vector<int> all_t;
struct FStat { long n = 0; long long sum = 0, mx = 0; };
static FStat fst[4];
static FStat tkst[4];
static long long tk_t0 = 0;
static int tk_k = 0, TK_IN = 0, TK_OUT = 0;       // T por fotograma (TS_VM=1): [0] sin mensaje ni espera, [1] sin mensaje con talk_delay, [2] con mensaje esperando, [3] con mensaje y displayDialog
extern "C" {
int z80_contend_wrapper(int, int, int t) { return t; }
int z80_contend_io_wrapper(int, int, int t) { return t; }
BYTE z80_readbyte_wrapper(int a) { return rd(a); }
BYTE z80_readoperandbyte_wrapper(int a) { return rd(a); }
BYTE z80_opcode_fetch_wrapper(int a) { z80_fetch_is_m1 = 0; return rd(a); }
void z80_writebyte_wrapper(int a, int d) { wr(a, (uint8_t)d); }
void z80_writeport_wrapper(int port, int d, int*) {
  if ((port & 0xFF) == 0xE7) blk[d & 7] = (port >> 8) & 0xFF;            // mapeador: B = pagina, dato = bloque
  else if ((port & 0xFF) == 0xF1) host_trap(d & 0xFF);
  else if ((port & 0xFF) == 0xF2) event_trap(d & 0xFF);
}
BYTE z80_readport_wrapper(int, int*) { return 0xFF; }
}

static long call_limit = 60000000L;
static bool tv_trace = false;
static long tv_pc = 0;
static bool tv_ring = false;
static int ring[40], VM_ERR = 0;
static long ringn = 0;
static bool z80_call(int addr) {
  z80.sp.w = 0x7FF0;
  wr16(0x7FF0, TRAP);
  ram[3][TRAP & 0x1FFF] = 0x76;
  z80.pc.w = addr; z80.halted = 0; z80.iff1 = z80.iff2 = 0;
  long n = 0;
  istk.clear();
  while (z80.pc.w != TRAP) {
    int pc = z80.pc.w;
    if (ts_vm) {
      if (pc == ES_GO) { if (istk.empty() || istk.back().sp != z80.sp.w) istk.push_back({tnow, z80.sp.w, rd(rd16(SPTR)), 0}); }   // (es_cross vuelve a es_go)
      else if (pc == ES_LOOP && !istk.empty() && istk.back().sp == z80.sp.w) {
        Frame f = istk.back(); istk.pop_back();
        long long incl = tnow - f.t0 + 22;          // + la comprobacion de CUR de es_loop (13 + 4 + 5)
        long long excl = incl - f.nested;
        opst[f.op].n++; opst[f.op].excl += excl; opst[f.op].incl += incl;
        all_t.push_back((int)excl);
        if (!istk.empty()) istk.back().nested += incl;
      }
    }
    if (ts_vm) {                                    // T de talk_frame (talk_delay y displayDialog, sin los scripts del fotograma) por estado de entrada
      if (pc == TK_IN) { tk_t0 = tnow; tk_k = rd(HAVEMSG) == 0 ? (rd16(TALKDLY) ? 1 : 0) : (rd16(TALKDLY) ? 2 : 3); }
      else if (pc == TK_OUT) { tkst[tk_k].n++; tkst[tk_k].sum += tnow - tk_t0; tkst[tk_k].mx = std::max(tkst[tk_k].mx, tnow - tk_t0); }
    }
    if (pc == ES_GO) { vm_insns++; if (tv_trace) fprintf(stderr, "  op %02X ptr %04X cur=%d pg=%d a1: room %d cost %d frame %d%c", rd(rd16(SPTR)), rd16(SPTR), rd(CUR), blk[1], rd(ACTORS+ASIZE), rd16(ACTORS+ASIZE+5), rd(ACTORS+ASIZE+11), 10); }
    if (tv_ring) {                                  // TV_RING=1: los ultimos 40 PC antes de cada vm_err
      ring[ringn++ % 40] = pc;
      if (pc == VM_ERR) { fprintf(stderr, "vm_err desde:"); for (int k = 0; k < 40; k++) fprintf(stderr, " %04X", ring[(ringn + k) % 40]); fprintf(stderr, "%c", 10); }
    }
    if (n < tv_pc) fprintf(stderr, "pc %04X sp %04X a=%02X de=%04X hl=%04X%c", pc, z80.sp.w, z80.af.b.h, z80.de.w, z80.hl.w, 10);
    tstates = 0;
    z80_do_opcode();
    tnow += tstates;
    instr_total++;
    if (++n > call_limit) return false;
  }
  return true;
}

// ---------------------------------------------------------------- escenarios
static int cur_room = 0, entry_room = 0, exit_room = 0;
static int slot_base_off(int st_where, int num, int page, int ptr) {
  if (st_where == 2) {
    if (num == 199) return ptr - 0x2000;                    // CODE: el bytecode empieza en el inicio de la ventana
    int pg = d8(OFF_SCRDIR + 3 * num), ad = d16(OFF_SCRDIR + 3 * num + 1);
    if (pg == 255) { int e = OFF_BIGDIR + 8 * ad; return (page - d8(e + 2)) * 4096 + ptr - 0x2000; }
    return ptr - ad;
  }
  if (st_where == 3) {
    auto it = room_locals[cur_room].find(num);
    return it == room_locals[cur_room].end() ? ptr : ptr - it->second.addr;
  }
  if (num == 10002) return ptr - d16(OFF_ROOMDIR + 32 * entry_room + 1);
  if (num == 10001) return ptr - d16(OFF_ROOMDIR + 32 * exit_room + 4);
  return ptr - d16(OFF_ODIR + 3 * num + 1);
}
// cadena en bruto del script (pagina de datos y direccion en la ventana), con su 0 final: la regla de read_raw_string del modelo
static std::vector<uint8_t> raw_string(int page, int addr) {
  std::vector<uint8_t> out;
  if (!page) return out;
  const uint8_t* p = ram[128 + page] + (addr - 0x2000);
  for (;;) {
    uint8_t c = *p++;
    out.push_back(c);
    if (c == 0) break;
    if (c == 0xFF) {
      c = *p++; out.push_back(c);
      if (c != 1 && c != 2 && c != 3 && c != 8) { out.push_back(*p++); out.push_back(*p++); }
    }
  }
  return out;
}
static void put16(std::vector<uint8_t>& v, int x) { v.push_back(x & 255); v.push_back((x >> 8) & 255); }
static uint16_t verbs_crc() {                    // vmmodel3.CoreVM.verbs_crc
  std::vector<uint8_t> b;
  for (int i = 0; i < NVERB; i++) {
    int a = VERBS + i * VSZ;
    for (int k = 0; k < 8; k++) b.push_back(rd(a + k));                 // verbid, color, hicolor, dimcolor, bkcolor, curmode, saveid, key
    b.push_back(rd(a + 8) & 1); b.push_back((rd(a + 8) >> 1) & 1);      // center, type
    put16(b, rd16(a + 9)); put16(b, rd16(a + 11)); put16(b, rd16(a + 13));
    std::vector<uint8_t> n = raw_string(rd(a + 15), rd16(a + 16));
    put16(b, (int)n.size());
    b.insert(b.end(), n.begin(), n.end());
  }
  return crc16(b.data(), b.size());
}
static uint16_t strings_crc() {                  // CoreVM.strings_crc
  std::vector<uint8_t> b;
  for (int s = 0; s < NSTR; s++) {
    int n = rd(STRLEN + s);
    if (!n) continue;
    b.push_back(s); put16(b, n);
    int p = rd16(STRPOS + 2 * s);
    for (int k = 0; k < n; k++) b.push_back(rd(STRHEAP + p + k));
  }
  return crc16(b.data(), b.size());
}
static uint16_t actor_names_crc() {              // CoreVM.actor_names_crc
  std::vector<uint8_t> b;
  for (int i = 0; i < NACT; i++) {
    std::vector<uint8_t> n = raw_string(rd(ACTNAMES + 3 * i), rd16(ACTNAMES + 3 * i + 1));
    put16(b, (int)n.size());
    b.insert(b.end(), n.begin(), n.end());
  }
  return crc16(b.data(), b.size());
}
static std::string digest() {
  std::vector<uint8_t> v(512), l(NSLOT * NLOCAL * 2), k;
  for (int i = 0; i < 512; i++) v[i] = rd(VARS + i);
  for (size_t i = 0; i < l.size(); i++) l[i] = rd(LOCALS + (int)i);
  for (int i = 0; i < 10; i++) k.push_back(rd(CUTDATA + i));
  for (int i = 0; i < 5; i++) k.push_back(rd(CUTSCR + i));
  std::vector<uint8_t> a(NACT * ASIZE), o, inv(NINV * 2), nn(NNAMES * 2);        // fase 4a: actores, objetos, inventario, nombres
  for (size_t i = 0; i < a.size(); i++) a[i] = rd(ACTORS + (int)i);
  for (int i = 0; i < 1000; i++) o.push_back(rd(OBJST + i));
  for (int i = 0; i < 1000; i++) o.push_back(rd(OBJOWN + i));
  for (int i = 0; i < 1000; i++) { o.push_back(rd(OBJCLS + 3 * i)); o.push_back(rd(OBJCLS + 3 * i + 1)); o.push_back(rd(OBJCLS + 3 * i + 2)); o.push_back(0); }
  for (size_t i = 0; i < inv.size(); i++) inv[i] = rd(INVSL + (int)i);
  for (size_t i = 0; i < nn.size(); i++) nn[i] = rd(NEWNAMES + (int)i);
  std::vector<uint8_t> mb, sl;                    // fase 4b-2: el bufer del mensaje (con su 0 final) y los valores por omision de las 4 ranuras de texto
  for (int p = MSGBUF; p <= rd16(MSGEND); p++) mb.push_back(rd(p));
  for (int i = 0; i < 44; i++) sl.push_back(rd(STRSL + i));
  char b[460];
  snprintf(b, sizeof b, "D f=%d V=%04X L=%04X K=%d,%04X A=%04X O=%04X I=%04X N=%04X M=%d,%d,%d,%d,%d X=%d,%d,%d,%d,%04X,%04X C=%d,%d,%d,%d,%d U=%d,%d,%d,%d W=%04X T=%04X P=%04X S=", frame,
           crc16(v.data(), v.size()), crc16(l.data(), l.size()), rd(CUTSP), crc16(k.data(), k.size()), crc16(a.data(), a.size()),
           crc16(o.data(), o.size()), crc16(inv.data(), inv.size()), crc16(nn.data(), nn.size()), rd(HAVEMSG), (int16_t)rd16(TALKDLY), rd(KEEPTXT),
           rd(CURROOM), (int16_t)rd16(LASTSND), rd(USETALK), rd16(MSGCNT), rd16(MSGPTR) - MSGBUF, rd(CHARCOL), crc16(mb.data(), mb.size()),
           crc16(sl.data(), sl.size()), (int16_t)rd16(CAMCUR), (int16_t)rd16(CAMDEST), rd(CAMMODE), rd(CAMFOL), rd(CAMMOV),
           (int16_t)rd16(USERPUT), (int16_t)rd16(CURSTATE), (int16_t)rd16(MAINTOP), (int16_t)rd16(MAINH), verbs_crc(), strings_crc(), actor_names_crc());
  std::string s = b;
  bool first = true;
  for (int i = 0; i < NSLOT; i++) {
    int a = SLOTS + 16 * i;
    int st = rd(a);
    if (!st) continue;
    int wh = rd(a + 1), num = rd16(a + 2), pg = rd(a + 4), ptr = rd16(a + 5);
    snprintf(b, sizeof b, "%s%d:%d:%d:%d:%d", first ? "" : " ", i, st, wh, num, slot_base_off(wh, num, pg, ptr));
    s += b;
    first = false;
    if ((st & 0x7F) == 1) { snprintf(b, sizeof b, ":%u", (unsigned)(rd16(a + 7) | ((uint32_t)rd16(a + 9) << 16))); s += b; }
    if (rd(a + 12)) { snprintf(b, sizeof b, ":f%d", rd(a + 12)); s += b; }
    if (rd(a + 13)) { snprintf(b, sizeof b, ":c%d", rd(a + 13)); s += b; }
  }
  return s;
}

static void flush_trace(FILE* out) { for (auto& t : trace) fprintf(out, "%s\n", t.c_str()); trace.clear(); }
static bool run_call(int addr, FILE* out) {
  wr(ERR, 0);
  if (!z80_call(addr)) { trace.push_back("ERR 9"); flush_trace(out); return false; }
  int e = rd(ERR);
  if (e) { trace.push_back("ERR " + std::to_string(e)); flush_trace(out); return false; }
  return true;
}

int main(int argc, char** argv) {
  if (argc < 7) { printf("uso: test_vm vm.bin vm.sym ovlb.bin DATA.BIN scenarios.txt actual.txt\n"); return 2; }
  ts_vm = getenv("TS_VM") && atoi(getenv("TS_VM"));
  tv_trace = getenv("TV_TRACE") != nullptr;
  tv_ring = getenv("TV_RING") != nullptr;
  tv_pc = getenv("TV_PC") ? atol(getenv("TV_PC")) : 0;
  if (!load_sym(argv[2])) { printf("no puedo leer %s\n", argv[2]); return 2; }
  VARS = S("VARS"); OBJST = S("OBJST"); OBJOWN = S("OBJOWN"); OBJCLS = S("OBJCLS"); SCRDIR = S("SCRDIR"); BIGDIR = S("BIGDIR");
  SLOTS = S("SLOTS"); LOCALS = S("LOCALS"); CUTDATA = S("CUTDATA"); CUTSCR = S("CUTSCR"); CUTSP = S("CUTSP"); ARGS = S("ARGS");
  ARGN = S("ARGN"); HRES = S("HRES"); HFLAG = S("HFLAG"); ERR = S("ERR"); DELTA = S("DELTA"); APIW = S("APIW"); APIN = S("APIN");
  APIP = S("APIP"); APIA = S("APIA"); APIVERB = S("APIVERB"); APIBIG = S("APIBIG"); VACNT = S("VACNT"); VARARG = S("VARARG");
  HOSTVEC = S("HOSTVEC"); TOPOP = S("TOPOP"); OPC = S("OPC"); SPTR = S("SPTR"); CUR = S("CUR");
  ACTORS = S("ACTORS"); NEWNAMES = S("NEWNAMES"); INVSL = S("INVSL"); EVARGS = S("EVARGS"); EVVEC = S("EVVEC"); CAMCUR = S("CAMCUR");
  CAMDEST = S("CAMDEST"); CAMMODE = S("CAMMODE"); CAMFOL = S("CAMFOL"); CAMMOV = S("CAMMOV"); HAVEMSG = S("HAVEMSG");
  KEEPTXT = S("KEEPTXT"); TALKDLY = S("TALKDLY"); LASTSND = S("LASTSND"); CURROOM = S("CURROOM"); ASIZE = S("ASIZE"); NACT = S("NACT");
  NINV = S("NINV"); NNAMES = S("NNAMES");
  USERPUT = S("USERPUT"); CURSTATE = S("CURSTATE"); MAINTOP = S("MAINTOP"); MAINH = S("MAINH"); STRLEN = S("STRLEN"); STRPOS = S("STRPOS");
  STRHEAP = S("STRHEAP"); VERBS = S("VERBS"); VSZ = S("VSZ"); NVERB = S("NVERB"); NSTR = S("NSTR"); ACTNAMES = S("ACTNAMES");
  USETALK = S("USETALK"); STRSL = S("STRSL"); MSGPTR = S("MSGPTR"); MSGCNT = S("MSGCNT"); MSGEND = S("MSGEND"); CHARCOL = S("CHARCOL");
  MSGBUF = S("MSGBUF");
  NSLOT = S("NSLOT"); NLOCAL = S("NLOCAL"); TABPG = S("TABPG"); OVB_PAGE = S("OVB_PAGE");
  COLD_ROOMDIR = S("COLD_ROOMDIR"); COLD_ODIR = S("COLD_ODIR"); COLD_OBJROOM = S("COLD_OBJROOM"); COLD_COSTDIR = S("COLD_COSTDIR");
  COLD_COSTDIR2 = S("COLD_COSTDIR2");
  API_INIT = 0x4200; API_RUN_EXT = 0x4203; API_RUN_OBJECT = 0x4206; API_RUN_SCRIPT = 0x4209; API_FRAME = 0x420C;
  API_SET_ROOM = 0x420F; API_ABORT = 0x4212;
  VM_ERR = S("vm_err");
  TK_IN = S("talk_frame"); TK_OUT = S("vf_tk");
  ES_GO = S("es_go"); ES_LOOP = S("es_loop");
  FILE* f = fopen(argv[1], "rb");
  if (!f) { printf("no encuentro %s\n", argv[1]); return 2; }
  std::vector<uint8_t> code(0xC000);
  size_t sz = fread(code.data(), 1, code.size(), f); fclose(f);
  for (size_t i = 0; i < sz; i++) { int a = 0x4200 + (int)i; ram[a >> 13][a & 0x1FFF] = code[i]; }
  f = fopen(argv[3], "rb");
  if (!f) { printf("no encuentro %s\n", argv[3]); return 2; }
  size_t szb = fread(ram[OVB_PAGE], 1, 8192, f); fclose(f);
  printf("vm.bin: %zu bytes en $4200 (codigo hasta $%04X, tablas hasta $%04X); ovlb.bin: %zu bytes en la pagina %d\n", sz,
         S("code_end"), S("tables_end"), szb, OVB_PAGE);
  if (!load_data(argv[4])) { printf("no puedo leer %s\n", argv[4]); return 2; }
  z80_init(); z80_reset();

  FILE* sc = fopen(argv[5], "r");
  FILE* out = fopen(argv[6], "w");
  if (!sc || !out) { printf("no puedo abrir los ficheros\n"); return 2; }
  static char line[16384];
  int nsc = 0;
  bool aborted = false;
  long frames_run = 0;
  int ncode = 0;
  while (fgets(line, sizeof line, sc)) {
    line[strcspn(line, "\r\n")] = 0;
    if (!strncmp(line, "SCENARIO ", 9)) {
      fprintf(out, "%s\n", line);
      trace.clear(); frame = 0; cur_room = entry_room = exit_room = 0; aborted = false; nsc++; ncode = 0;
      for (int i = 0; i < 8; i++) blk[i] = i;
      continue;
    }
    if (!strcmp(line, "END")) { if (!aborted) flush_trace(out); fprintf(out, "END\n"); continue; }
    if (aborted) continue;
    char cmd[16];
    int p[20] = {0};
    int np = sscanf(line, "%15s %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d %d", cmd, &p[0], &p[1], &p[2], &p[3], &p[4], &p[5],
                    &p[6], &p[7], &p[8], &p[9], &p[10], &p[11], &p[12], &p[13], &p[14], &p[15], &p[16]) - 1;
    if (np < 0) continue;
    bool dig = false;
    if (!strcmp(cmd, "INIT")) {
      for (int i = 0; i < 8; i++) blk[i] = i;
      init_world();
      if (!run_call(API_INIT, out)) { aborted = true; continue; }
      wr(HOSTSTUB, 0xD3); wr(HOSTSTUB + 1, 0xF1); wr(HOSTSTUB + 2, 0xC9);      // OUT ($F1),A / RET
      wr16(HOSTVEC, HOSTSTUB);
      wr(HOSTSTUB + 3, 0xD3); wr(HOSTSTUB + 4, 0xF2); wr(HOSTSTUB + 5, 0xC9);      // OUT ($F2),A / RET: sucesos del back-end
      wr16(EVVEC, HOSTSTUB + 3);
    } else if (!strcmp(cmd, "OPT")) {
    } else if (!strcmp(cmd, "SETVAR")) {
      wr16(VARS + 2 * p[0], (uint16_t)p[1]);
    } else if (!strcmp(cmd, "OWNER")) {
      wr(OBJOWN + p[0], p[1]);
    } else if (!strcmp(cmd, "STATE")) {
      wr(OBJST + p[0], p[1]);
    } else if (!strcmp(cmd, "INV")) {
      wr16(INVSL + 2 * p[0], (uint16_t)p[1]);
    } else if (!strcmp(cmd, "ACTORSET")) {                      // ACTORSET n sala x y traje visible: campos a mano, sin efectos
      int a = ACTORS + ASIZE * p[0];
      wr(a + 0, p[1]); wr16(a + 1, (uint16_t)p[2]); wr16(a + 3, (uint16_t)p[3]); wr16(a + 5, (uint16_t)p[4]); wr(a + 10, p[5] ? 1 : 0);
    } else if (!strcmp(cmd, "CLASS")) {
      unsigned c = 0; sscanf(line, "%*s %*d %x", &c);
      wr(OBJCLS + 3 * p[0], c & 255); wr(OBJCLS + 3 * p[0] + 1, (c >> 8) & 255); wr(OBJCLS + 3 * p[0] + 2, (c >> 16) & 255);
    } else if (!strcmp(cmd, "ROOM")) {
      cur_room = p[0];
      wr16(APIN, p[0]);
      if (!run_call(API_SET_ROOM, out)) { aborted = true; continue; }
    } else if (!strcmp(cmd, "SCRIPT")) {
      int na = np - 1;
      for (int i = 0; i < na && i < NLOCAL; i++) wr16(VARARG + 2 * i, (uint16_t)p[1 + i]);
      wr(VACNT, std::min(na, NLOCAL));
      wr16(APIN, p[0]);
      if (!run_call(API_RUN_SCRIPT, out)) { aborted = true; continue; }
      dig = true;
    } else if (!strcmp(cmd, "ENTRY") || !strcmp(cmd, "EXIT")) {
      bool en = !strcmp(cmd, "ENTRY");
      int e = OFF_ROOMDIR + 32 * p[0] + (en ? 0 : 3);
      if (en) entry_room = p[0]; else exit_room = p[0];
      if (d8(e)) {
        wr(APIW, 1); wr16(APIN, en ? 10002 : 10001); wr(APIP, d8(e)); wr16(APIA, d16(e + 1)); wr(APIBIG, 0);
        if (!run_call(API_RUN_EXT, out)) { aborted = true; continue; }
      }
      dig = true;
    } else if (!strcmp(cmd, "OBJ")) {
      int e = OFF_ODIR + 3 * p[0];
      wr16(APIN, p[0]); wr(APIP, p[0] < 1000 ? d8(e) : 0); wr16(APIA, p[0] < 1000 ? d16(e + 1) : 0); wr(APIVERB, p[1]);
      if (!run_call(API_RUN_OBJECT, out)) { aborted = true; continue; }
      dig = true;
    } else if (!strcmp(cmd, "CODE")) {                         // CODE <hex>: bytecode sintetico como un script global (vmsynth3.py)
      int pg = d_first + d_npages + ncode++;                    // una pagina de datos que no usa DATA.BIN (una por CODE: los nombres de verbos y actores apuntan al texto)
      if (128 + pg > 255) { printf("sin paginas para CODE%c", 10); return 2; }
      uint8_t* mem = ram[128 + pg];
      memset(mem, 0, 8192);
      int nb = 0;
      for (const char* h = line + 5; h[0] && h[1] && nb < 8192; h += 2) { unsigned v = 0; sscanf(h, "%2x", &v); mem[nb++] = (uint8_t)v; }
      wr(APIW, 2); wr16(APIN, 199); wr(APIP, pg); wr16(APIA, 0x2000); wr(APIBIG, 0);
      if (!run_call(API_RUN_EXT, out)) { aborted = true; continue; }
      dig = true;
    } else if (!strcmp(cmd, "ABORT")) {
      if (!run_call(API_ABORT, out)) { aborted = true; continue; }
      dig = true;
    } else if (!strcmp(cmd, "FRAMES")) {
      for (int i = 0; i < p[1]; i++) {
        frame++; frames_run++;
        wr(DELTA, p[0]);
        int hm0 = rd(HAVEMSG), td0 = rd16(TALKDLY);
        long long t0 = tnow;
        if (!run_call(API_FRAME, out)) { aborted = true; break; }
        if (ts_vm) { int k = hm0 == 0 ? (td0 ? 1 : 0) : (td0 ? 2 : 3); fst[k].n++; fst[k].sum += tnow - t0; fst[k].mx = std::max(fst[k].mx, tnow - t0); }
        trace.push_back(digest());
        flush_trace(out);
      }
    } else {
      printf("orden no soportada por el arnes del nucleo: %s\n", line);
      trace.push_back("ERR 98"); flush_trace(out); aborted = true;
    }
    if (dig) { flush_trace(out); fprintf(out, "%s\n", digest().c_str()); }
    if (dig && getenv("TV_ACT")) { int n = atoi(getenv("TV_ACT")); fprintf(stderr, "ACT%d:", n); for (int i = 0; i < ASIZE; i++) fprintf(stderr, "%02x", rd(ACTORS + ASIZE * n + i)); fputc(10, stderr); }
  }
  fclose(out); fclose(sc);
  printf("%d escenarios, %ld fotogramas; instrucciones del Z80: %ld; instrucciones de script: %ld (%.1f Z80 por instruccion)\n",
         nsc, frames_run, instr_total, vm_insns, vm_insns ? (double)instr_total / vm_insns : 0.0);
  if (ts_vm) {
    static const char* nm[4] = {"sin mensaje ni espera", "sin mensaje, con talk_delay", "con mensaje esperando", "con mensaje: displayDialog"};
    for (int k = 0; k < 4; k++) if (tkst[k].n) printf("talk_frame %-28s n %7ld  T medios %8.0f  max %lld%c", nm[k], tkst[k].n, (double)tkst[k].sum / tkst[k].n, tkst[k].mx, 10);
    for (int k = 0; k < 4; k++) if (fst[k].n) printf("fotograma %-28s n %7ld  T medios %8.0f  max %lld (incluye los scripts del fotograma)%c", nm[k], fst[k].n, (double)fst[k].sum / fst[k].n, fst[k].mx, 10);
  }
  if (ts_vm && !all_t.empty()) {
    std::vector<int> t = all_t;
    std::sort(t.begin(), t.end());
    long long sum = 0; for (int x : t) sum += x;
    auto pc = [&](double q) { return t[std::min(t.size() - 1, (size_t)(q * t.size()))]; };
    printf("T por instruccion de script (exclusivos, con es_loop y el despacho): n %zu, media %.0f, mediana %d, p90 %d, p99 %d, max %d\n",
           t.size(), (double)sum / t.size(), pc(0.5), pc(0.9), pc(0.99), t.back());
    std::vector<int> ops;
    for (int i = 0; i < 256; i++) if (opst[i].n) ops.push_back(i);
    std::sort(ops.begin(), ops.end(), [](int a, int b) { return opst[a].n > opst[b].n; });
    printf("  op        n   T medios (excl)   T medios (con anidadas)\n");
    for (int i : ops) printf("  %02X %8ld   %10.0f   %10.0f\n", i, opst[i].n, (double)opst[i].excl / opst[i].n, (double)opst[i].incl / opst[i].n);
  }
  return 0;
}

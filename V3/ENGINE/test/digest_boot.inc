// GENERADO por mk_digest_boot.py a partir de test_vm.cpp (no editar): el resumen por fotograma de CoreVM.digest, calculado desde la memoria del Z80, para el arnes del
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
// direcciones (de vm.sym)
static int VARS, OBJST, OBJOWN, OBJCLS, SCRDIR, BIGDIR, SLOTS, LOCALS, CUTDATA, CUTSCR, CUTSP, ARGS, ARGN, HRES, HFLAG, ERR,
    DELTA, APIW, APIN, APIP, APIA, APIVERB, APIBIG, VACNT, VARARG, HOSTVEC, TOPOP, OPC, SPTR, CUR;
static int ACTORS, NEWNAMES, INVSL, EVARGS, EVVEC, CAMCUR, CAMDEST, CAMMODE, CAMFOL, CAMMOV, HAVEMSG, KEEPTXT, TALKDLY, LASTSND, CURROOM, ASIZE, NACT, NINV, NNAMES;
static int API_INPUT, INEV;
static int USERPUT, CURSTATE, MAINTOP, MAINH, STRLEN, STRPOS, STRHEAP, VERBS, VSZ, NVERB, NSTR, ACTNAMES;   // fase 4b-1
static int USETALK, STRSL, MSGPTR, MSGCNT, MSGEND, CHARCOL, MSGBUF;                                       // fase 4b-2
static int OVC_PAGE;
static int APIFL, CLS_PG, RBLOB, SENTN, SENTQ, RESMAP, OBJP, NROBJ, NBOXES, CURRD;                               // fase 5
static int NSLOT, NLOCAL, TABPG, OVB_PAGE, COLD_ROOMDIR, COLD_ODIR, COLD_OBJROOM, COLD_COSTDIR, COLD_COSTDIR2;
static uint16_t crc16(const uint8_t* d, size_t n, uint16_t crc = 0xFFFF) {
  for (size_t i = 0; i < n; i++) {
    crc ^= (uint16_t)d[i] << 8;
    for (int k = 0; k < 8; k++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
  }
  return crc;
}

static int slot_base_off(int st_where, int num, int page, int ptr) {
  if (st_where == 2) {
    if (num == 199) return ptr - 0x2000;                    // CODE: el bytecode empieza en el inicio de la ventana
    int pg = d8(OFF_SCRDIR + 3 * num), ad = d16(OFF_SCRDIR + 3 * num + 1);
    if (pg == 255) { int e = OFF_BIGDIR + 8 * ad; return (page - d8(e + 2)) * 4096 + ptr - 0x2000; }
    return ptr - ad;
  }
  if (st_where == 3) {                                      // un script local de la sala en uso (CURRD: n x (id, pagina, direccion))
    int n = rd(CURRD + 9), tp = rd(CURRD + 18), ta = rd16(CURRD + 19);
    for (int k = 0; k < n; k++) {
      const uint8_t* e = pageptr(tp) + (ta - 0x2000) + 4 * k;
      if (e[0] == num) return ptr - (e[2] | (e[3] << 8));
    }
    return ptr;
  }
  if (num == 10002) return ptr - rd16(CURRD + 1);                  // el ENCD de la sala en uso (ROOM, ENTRY o startScene)
  if (num == 10001) return ptr - excd_start(page, ptr);
  return ptr - d16(OFF_ODIR + 3 * num + 1);
}
// cadena en bruto del script (pagina de datos y direccion en la ventana), con su 0 final: la regla de read_raw_string del modelo
static std::vector<uint8_t> raw_string(int page, int addr) {
  std::vector<uint8_t> out;
  if (!page) return out;
  const uint8_t* p = pageptr(page) + (addr - 0x2000);
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
    b.push_back(rd(a + 18));                                            // V_LEN (fase 7: columnas del ultimo dibujo)
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
static std::string walk_trace() {               // CoreVM.walk_trace (fase 6): n:x,y,caja,moving de cada actor de la sala en uso
  int room = rd(CURROOM);
  std::string t;
  if (room) for (int i = 1; i < NACT; i++) {
    int a = ACTORS + ASIZE * i;
    if (rd(a) != room) continue;
    char b[64];
    snprintf(b, sizeof b, "%s%d:%d,%d,%d,%d", t.empty() ? "" : ";", i, (int16_t)rd16(a + 1), (int16_t)rd16(a + 3), rd(a + 16), rd(a + 9));
    t += b;
  }
  return t.empty() ? "-" : t;
}
static std::string digest() {
  std::vector<uint8_t> pal(32);                         // fase 8: _roomPalette y _shadowPalette
  for (int i = 0; i < 32; i++) pal[i] = rd(S("ROOMPAL") + i);
  std::vector<uint8_t> v(512), l(NSLOT * NLOCAL * 2), k;
  for (int i = 0; i < 512; i++) v[i] = rd(VARS + i);
  for (size_t i = 0; i < l.size(); i++) l[i] = rd(LOCALS + (int)i);
  for (int i = 0; i < 10; i++) k.push_back(rd(CUTDATA + i));
  for (int i = 0; i < 5; i++) k.push_back(rd(CUTSCR + i));
  std::vector<uint8_t> a(NACT * ASIZE), o, inv(NINV * 2), nn(NNAMES * 2);        // fase 4a: actores, objetos, inventario, nombres
  for (size_t i = 0; i < a.size(); i++) a[i] = rd(ACTORS + (int)i);
  for (int i = 0; i < 1000; i++) o.push_back(rd(OBJST + i));
  for (int i = 0; i < 1000; i++) o.push_back(rd(OBJOWN + i));
  for (int i = 0; i < 1000; i++) { o.push_back(ram[CLS_PG][3 * i]); o.push_back(ram[CLS_PG][3 * i + 1]); o.push_back(ram[CLS_PG][3 * i + 2]); o.push_back(0); }
  for (size_t i = 0; i < inv.size(); i++) inv[i] = rd(INVSL + (int)i);
  for (size_t i = 0; i < nn.size(); i++) nn[i] = rd(NEWNAMES + (int)i);
  std::vector<uint8_t> mb, sl;                    // fase 4b-2: el bufer del mensaje (con su 0 final) y los valores por omision de las 4 ranuras de texto
  for (int p = MSGBUF; p <= rd16(MSGEND); p++) mb.push_back(rd(p));
  for (int i = 0; i < 44; i++) sl.push_back(rd(STRSL + i));
  std::vector<uint8_t> sq, rb;                    // fase 5: cola de frases (7 bytes cada una) y objetos (13 de los 14 bytes de cada registro) y cajas de la sala
  int ns = rd(SENTN), nb = rd(NBOXES), no = rd(NROBJ), op = rd16(OBJP);
  for (int i = 0; i < ns * 7; i++) sq.push_back(rd(SENTQ + i));
  for (int i = 0; i < no; i++) for (int k = 0; k < 13; k++) rb.push_back(rd(op + 14 * i + k));
  for (int i = 0; i < nb * 18; i++) rb.push_back(rd(RBLOB + 1 + i));
  std::vector<uint8_t> rm;
  for (int i = 0; i < 128; i++) rm.push_back(rd(RESMAP + i));
  char b[1000];
  snprintf(b, sizeof b, "D f=%d V=%04X L=%04X K=%d,%04X A=%04X O=%04X I=%04X N=%04X M=%d,%d,%d,%d,%d X=%d,%d,%d,%d,%04X,%04X C=%d,%d,%d,%d,%d U=%d,%d,%d,%d W=%04X T=%04X P=%04X Q=%d,%04X R=%d,%d,%04X,%d,%04X Y=%04X G=%s S=", frame,
           crc16(v.data(), v.size()), crc16(l.data(), l.size()), rd(CUTSP), crc16(k.data(), k.size()), crc16(a.data(), a.size()),
           crc16(o.data(), o.size()), crc16(inv.data(), inv.size()), crc16(nn.data(), nn.size()), rd(HAVEMSG), (int16_t)rd16(TALKDLY), rd(KEEPTXT),
           rd(CURROOM), (int16_t)rd16(LASTSND), rd(USETALK), rd16(MSGCNT), rd16(MSGPTR) - MSGBUF, rd(CHARCOL), crc16(mb.data(), mb.size()),
           crc16(sl.data(), sl.size()), (int16_t)rd16(CAMCUR), (int16_t)rd16(CAMDEST), rd(CAMMODE), rd(CAMFOL), rd(CAMMOV),
           (int16_t)rd16(USERPUT), (int16_t)rd16(CURSTATE), (int16_t)rd16(MAINTOP), (int16_t)rd16(MAINH), verbs_crc(), strings_crc(), actor_names_crc(),
           ns, crc16(sq.data(), sq.size()), nb, no, crc16(rb.data(), rb.size()), rd(S("EGOPOS")), crc16(rm.data(), rm.size()), crc16(pal.data(), pal.size()), walk_trace().c_str());
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


static void init_digest_syms() {
  VARS = S("VARS"); OBJST = S("OBJST"); OBJOWN = S("OBJOWN"); SCRDIR = S("SCRDIR"); BIGDIR = S("BIGDIR");
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
  MSGBUF = S("MSGBUF"); INEV = S("INEV");
  OVC_PAGE = S("OVC_PAGE");
  APIFL = S("APIFL"); CLS_PG = S("CLS_PG"); RBLOB = S("RBLOB"); SENTN = S("SENTN"); SENTQ = S("SENTQ"); RESMAP = S("RESMAP"); OBJP = S("OBJP"); NROBJ = S("NROBJ");
  NBOXES = S("NBOXES"); CURRD = S("CURRD");
  NSLOT = S("NSLOT"); NLOCAL = S("NLOCAL"); TABPG = S("TABPG"); OVB_PAGE = S("OVB_PAGE");
  COLD_ROOMDIR = S("COLD_ROOMDIR"); COLD_ODIR = S("COLD_ODIR"); COLD_OBJROOM = S("COLD_OBJROOM"); COLD_COSTDIR = S("COLD_COSTDIR");
  COLD_COSTDIR2 = S("COLD_COSTDIR2");
}

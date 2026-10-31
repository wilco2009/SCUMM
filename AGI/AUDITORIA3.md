# AUDITORIA3 — intérprete AGI v2 (Z80 + modelo) contra ScummVM `engines/agi`

Tercera auditoría. Parte de [AUDITORIA2.md](AUDITORIA2.md) (no se borra ni se edita) y rellena lo que esa dejó sin leer.
**Las secciones 1-7 son el informe original; la 8 recoge las correcciones posteriores, fila por fila.** No se ha ejecutado nada del clon de ScummVM.

- ScummVM: `C:\ClaudeCode\scummvm_src`, commit `f7403b6efaae` (el mismo de AUDITORIA2). Rutas `ScummVM fichero:línea` = `engines/agi/`.
- Nuestro lado: `V2/TOOLS/agi_vm.py` (modelo, `py:línea`) y `V2/ENGINE/*.asm` (Z80, `asm fichero:línea`).
- Regla de honestidad: solo afirmo haber comparado lo que he leído literalmente en esta sesión (§1 lo detalla con rangos). Donde pone "(AUD2)" el dato de ScummVM viene de lo que AUDITORIA2 dice haber leído y **no lo he releído**.
- Una copia de trabajo más larga (notas por lote) está en la carpeta de notas compartida de la sesión (`auditoria3_notas.md`).

Cambios de criterio respecto a AUDITORIA2:

1. **Se compara el Z80 directamente con ScummVM**, no "por suposición de que el modelo coincide". En §2 cada fila lleva `Z80` y `Modelo`; las discrepancias Z80≠modelo están marcadas `Z≠M`.
2. **Hay evidencia nueva sacada de los datos reales de los 6 juegos** (`agi_logic.py --stats` y listados de las 506 lógicas): decide si una diferencia importa o no. Se cita donde se usa.
3. Un "motivo" (H/O) solo se acepta si hay constancia: `AGI/PLAN.md`, comentario en el código o mensaje de commit (`git log`). Si no la hay, la fila queda **E** o **A CONFIRMAR** y lo digo. **`V2/PLAN.md` solo tiene 4 líneas; el plan real es `AGI/PLAN.md` (199 líneas)**.

---

## 1. Método y ficheros leídos

### 1.1 ScummVM (`engines/agi`)

| Fichero | Líneas | Leído por mí en esta sesión |
|---|---:|---|
| `agi.h` | 983 | **entero** (22-983; 1-21 licencia) |
| `saveload.cpp` | 1094 | **entero** (22-1094), incluido `saveGame` (70-343) |
| `menu.cpp` | 733 | **entero** (22-733) |
| `picture.cpp` | 864 | **entero** (22-864) |
| `sound.cpp` | 230 | **entero** (22-230) |
| `global.cpp` | 368 | **entero** (timer `inGameTimerUpdate`, `getVar`/`setVar`, heurística de segundos, GoldRush) |
| `checks.cpp` | 495 | **entero** (22-495) |
| `motion.cpp` | 320 | **entero** (24-320) |
| `opcodes.cpp` | 531 | 366-531 (`setupOpCodes`, variantes por versión) y las filas 275-276 (`put`/`put.v`). Las tablas v1/v2 (30-365) **no las he releído** (AUD2) |
| `cycle.cpp` | 604 | 36-215 (`newRoom`, `interpretCycle`) y 340-540 (`playGame`, `runGame`). 215-340 (`processAGIEvents`) **no releído** (AUD2) |
| `view.cpp` | 735 | 40-110 (`updateView`) y 600-735 (`clipViewCoordinates`, `updateScreenObjTable`). El resto (AUD2) |
| `text.cpp` | — | 425-520 (`messageBox`, `messageBox_KeyPress`, inicio de `drawMessageBox`) y 1296-1395 (`stringPrintf`) |
| `graphics.cpp` | 1570 | 22-545 y 1262-1403 y 1435-1450 (≈ 800 líneas: init, traducción de coordenadas, `getPriority`, `checkControlPixel`, `shakeScreen`, **tabla de prioridades**, `setAGIPal`). **No leído línea a línea**: 545-1262 (`render_Block*`, transiciones Amiga/AtariST, `drawBox`, caracteres, rectángulos) y 1404-1570 (paletas, cursores de ratón): es presentación, sin variables ni banderas |
| `systemui.cpp` | 1234 | 22-300 (textos de diálogos y `pauseDialog`/`restartDialog`/`quitDialog`/`askForCommand`) + índice de funciones (`grep` confirma que **no hay** `setVar`/`setFlag`/`getVar` en el fichero). **No leído**: 300-1234 (selector de ranuras, verificación, botones Amiga/AppleIIgs/AtariST) |
| `sound_*.cpp` | 230+2468 | Solo `grep`: lo único que tocan es `soundIsFinished()` (pone la bandera) y `getFlag(SOUND_ON)`; el audio **no** lo he leído (PCjr 589, 2GS 836, Sarien 372, MIDI 237, A2 204, CoCo3 130) |
| `op_cmd.cpp` | — | Funciones sueltas con `awk`: `cmdPut/PutF/Sound/Draw/AnimateObj/Position/Reposition/RepositionTo/Erase/SetView/Version/ForceUpdate/ConfigureScreen/SetUpperLeft/ObjStatusF/ShowPriScreen/ScriptSize/LoadLogic/InitDisk/OpenDialogue/Log/DiscardView/LoadSound`. El resto (AUD2) |
| `detection_tables.h` | — | `grep` de las versiones de interprete (2.272, 2.440, 2.917…) de los 6 juegos |

### 1.2 Nuestro lado

| Fichero | Líneas | Leído |
|---|---:|---|
| `agivm.asm` | 1924 | **entero** |
| `agiobj.asm` | 1170 | **entero** |
| `agic.asm` (overlay C) | 1299 | **entero** |
| `agiin.asm` | 1545 | **entero** |
| `agia.asm` (overlay A1: teclado) | 403 | **entero** |
| `agipic.asm` | 386 | **entero** |
| `agie.asm` | 68 | **entero** |
| `agid.asm` (guardar/cargar) | 334 | **entero** |
| `agispr.asm` (pace, call_x, plot) | 338 | **entero** |
| `agiview.asm` (visor de imágenes, no es el intérprete) | 231 | **entero** |
| `agicel.asm` | 161 | **entero** |
| `mcu.asm` | 136 | **entero** |
| `agi_vm.py` | 2041 | 205-420 (sprites por hardware, `sw_blit`, `render`) y 1995-2041 (`main`) + fragmentos con `sed` (`c_reposition`, `fix_position`, `scan`). El resto (71-215, 412-1999) lo leyó AUDITORIA2 y **no lo he releído** |
| `agi_text.py` | 179 | **entero** |
| `agib.asm` (overlay B: texto, menús) | 2294 | **parcial**: 436-470, 770-840 (`t_prt`, `t_status`, ventana), 1296-1315 (`t_menureset`), 1805-1840 (`t_menuopen`), 2141-2230 (`t_dlginv`, `t_dlgdone`, textos). **No leído**: ~2000 líneas de dibujo de texto, ventanas y lista de menús |
| `agihws.asm` | 1546 | solo 1-40 (cabecera/`t_sinit`) + `grep` (no contiene `VARS+`/`FLAGS+`) |
| `agisw.asm` | 1337 | solo 1-30 (cabecera) + `grep` (ídem) |
| `agires.inc`, `agitab.inc`, `font6.inc`, `sprtab.inc` | 997/225/97/19 | `agitab.inc`: leído por código para saber **qué comandos son `h_nop`** (generado por `gen_agitab.py`). El resto son tablas de datos/recursos de dibujo: **no leídos** |

### 1.3 Datos de los juegos

`python -I TOOLS/agi_logic.py ../<juego> [--stats]` sobre SQ1, KQ1, KQ2, PQ1, SQ2 y Larry1 (506 lógicas, 0 errores; el decodificador rechaza cualquier opcode > 0xA9, así que **ninguno usa `hold.key`, `release.key`, `set.pri.base`, `set.simple`, `push/pop.script`**). Salidas de la sesión en `/tmp/_l_<juego>.txt` (no están en el repositorio).

---

## 2. Diferencias en el orden de ejecución del ciclo

Leyenda: **E** error, **H** hardware, **O** velocidad/optimización, **AC** A CONFIRMAR. `Z≠M` = Z80 y modelo difieren entre sí.
Efecto y propuesta, siempre sobre lo que ve una lógica o el jugador.

### 2.0 Reloj y ritmo (`playGame`, `inGameTimerUpdate`)

| Id | ScummVM | Nuestro modelo / Z80 | Tipo | Efecto concreto | Propuesta |
|---|---|---|---|---|---|
| **A3-01** | `global.cpp:231-` `inGameTimerUpdate`: `curPlayTimeCycles = ms / 25` y los segundos salen de los **milisegundos reales**; se recalcula también al **leer** v11-v14 (`getVar`, global.cpp:90-96) y al **escribir** v11 (`setVarSecondsTrigger`, :215-228, ajusta el desfase de ms). Un ciclo dura `25 ms × 2 × v10` (`cycle.cpp:405-411`: `timeDelay*2`; 0→1 = 40 fps) | Modelo `py:1885-1900` y Z80 `agivm.asm:948-987` `tick_clock`: el reloj **cuenta ciclos**: `20 // max(1,v10)` ciclos = 1 s. Escribir v11 no toca `ticks`. **Los bucles modales (`pr_wait` agiin.asm:437-493, menú :556-615, `get.string` :748-784) no llaman a `tick_clock` ni a `snd_due`** | **E** (no hay constancia de la decisión: `PLAN.md:105` documenta el ritmo `pace`, no que el reloj dependa de los ciclos) | Con v10=2 y ciclos de 5 tramas (`pace`) coincide. **Con v10=1 un "segundo" son 20 ciclos × 3 tramas = 1,2 s; con v10=0 son 20 ciclos × 1 trama = 0,4 s** (ScummVM: 1 s). El reloj **se para** mientras hay una ventana de `print`, un menú o `get.string` (ScummVM sigue contando). Si los ciclos tardan más que el ritmo (lecturas de SD, sala pesada) el reloj va lento. **Lo usan SQ1 (9 lecturas de v11-14, p. ej. `equalv(v11,v149)` + `display(...%v13:%v12|2:%v11|2)` en la lógica del reloj), PQ1 (11), SQ2 (8), Larry1 (2)** | Contar el reloj con los **tramas reales** (`ClkPort`) en vez de ciclos, o al menos llamar a `tick_clock` en cada vuelta de los bucles modales y contar `(5*v10+1)/2` tramas por segundo-de-juego en lugar de `20//v10` ciclos. Documentarlo |
| **A3-02** | `cycle.cpp:405-411`: 25 ms × 2 × v10 | `agispr.asm:114-158` `pace`: ciclo = `(5·v10+1)/2` tramas (a 50 Hz: v10=2 → 100 ms ✓; v10=1 → 3 tramas = 60 ms ✗ 50 ms; v10=0 → 1 trama = 20 ms ✗ 25 ms). `PACE_V10 equ 1` (agispr.asm:11). El contador de tramas lo reinician las lecturas del MCU: "el tiempo del ciclo se subestima" (comentario de la línea 120 y `PLAN.md:105`) | **H** (documentado: `PLAN.md:105`, commit `14b32ae`) | Los ciclos con lectura de SD duran más que en ScummVM; v10=1 un 20 % más lentos. Sin efecto sobre variables salvo el reloj (A3-01) y la duración del sonido (A3-26) | — (aceptado). Si se corrige A3-01 con tramas reales, se corrige esto a la vez |

### 2.1 Teclado y entrada (`processAGIEvents`, `handleController`)

| Id | ScummVM | Modelo / Z80 | Tipo | Efecto | Propuesta |
|---|---|---|---|---|---|
| **A3-03** = D01 (**corregida**) | `cycle.cpp:250-258` (AUD2): `v19` solo si **no** hay controlador/dirección | Z80 `key_push` agiin.asm:110-111: `ld (VARS+19),a` siempre; modelo `py:1915-1920` igual. **Corrección a AUDITORIA2:** en el **teclado real** del ZX81 las direcciones (5-8) **no** son eventos de tecla: `kb_dir` agia.asm:270-304 emite eventos tipo 2 → `dirhold` (agia.asm:338-339), y `km_base` (agia.asm:351-358) deja a 0 esas teclas. Así que **las flechas no ponen v19** en la placa; solo en los guiones de prueba (`ev_dir` agiin.asm:103-105 tampoco toca v19: allí tampoco). Lo que sí ocurre: **las teclas con controlador** (ESC=27, F-keys→25-31, ENTER=13…) **ponen v19** | **E** | `have.key()` y `v19==N` ven ESC, ENTER y las F-keys que en ScummVM tienen controlador. **Larry1 compara v19 37 veces** (p. ej. `if (equaln(v19, 13))`) y PQ1/SQ1 usan `have.key` | Mirar `KEYMAP` antes de escribir v19 (en `key_push`): si la tecla tiene controlador, no tocar v19. Cuidado: ENTER sin controlador sí debe dejar 13 |
| **A3-04** = D02 | `cycle.cpp:253`: el ENTER de una línea deja `v19 = 13` | Z80 `ev_text` agiin.asm:90: `v19 = 0`; antes `kb_emit 13` (agia.asm:90-94) sí puso 13 en el evento de tecla, pero `ed_cr` (agia.asm:231-250) manda la línea a continuación y **`ev_text` lo pone a 0** | **E** | `have.key()` es falsa en el ciclo en que se envía una frase; en ScummVM es cierta | `ev_text`: no tocar v19 (dejar el 13 del evento de tecla). Atención a `28371f3` ("la lógica puede ponerla a 0, p. ej. tras el ENTER de una frase": el cambio se hizo para SQ1 sala 10, mirar que sigue funcionando) |
| **A3-05** = D03 | `keyboard.cpp:600-611` (AUD2): `v6` cambia en el **evento** con alternancia; sin `hold.key` el ego sigue andando tras soltar | Z80: `main_loop` agivm.asm:199-203 `v6 = dirhold` en **cada** ciclo con `pctl`; `dirhold` se pone a 0 al soltar (`kb_dir` emite también el cambio a 0). Modelo `py:1923` igual | **AC** (decisión de interfaz documentada en `PLAN.md:89` "al soltar, parar" y `:97`, **pero sin análisis de su efecto en v6/`stop.motion`**; el ZX81 sí detecta la suelta de tecla (`kb_dir` ya lo usa), así que no es una limitación de hardware) | Pulsar dos veces la misma dirección no para al ego; soltar sí lo para (ScummVM no). Los 6 juegos no usan `hold.key` (§1.3) | Dejar como está, pero documentarlo como decisión de jugabilidad. Si se quisiera igualar: modo alternancia en `kb_dir` |
| **A3-06** = D05 | `op_test.cpp:121-144` (AUD2): `have.key` sondea la cola si `v19==0` | Z80 `hc_have_key` agiin.asm:176-194: solo `v19!=0`, más espera solo en `txtm` (pantalla de texto); modelo `py:520-536` igual | **O** (`bbf6bf2`: "have.key solo bloquea en bucle apretado"; `28371f3`) | Un bucle `if (!have.key()) goto` en una lógica normal no ve la tecla hasta el ciclo siguiente | Aceptado |
| **A3-07** = D06 | `op_cmd.cpp:2111-2134` (AUD2): clave de 16 bits, 39 máx, `controllerOccurred[slot]=false` | Z80 `h_set_key` agiin.asm:140-163: tabla `KEYMAP[128]` por ASCII (7 bits); F4-F10 → 25-31 | **H** (teclado del ZX81; `PLAN.md:89`, `TECLAS.md`) | Sin efecto: los juegos hacen 34-44 `set.key` (todos en una lógica) | Aceptado |

### 2.2 Núcleo de la lógica (`interpretCycle`, `runLogic`, `testIfCode`)

| Id | ScummVM | Modelo / Z80 | Tipo | Efecto | Propuesta |
|---|---|---|---|---|---|
| **A3-08** = D13 | `op_test.cpp:442-462` (AUD2): cortocircuito | **Z80** `do_if` agivm.asm:743-850: evalúa **todas** las condiciones (`c_res`/`c_orres` acumulados; `di_nx` sigue). Modelo `py:568-609` igual | **E** | `if (isset(f40) && said(...))` ejecuta el `said` y pone f4; también `have.key` (con espera) y `controller` | Saltar al `0xFF` en la primera condición falsa (modo Y) y al `0xFC` en la primera cierta (modo O) |
| **A3-09** = D08 | `op_cmd.cpp:2434-2531`: `runLogic` devuelve 0 si la 0 acaba sin `return` y `interpretCycle` (`cycle.cpp:174`) la repite | Z80 `rl_next` agivm.asm:683-691 (`ret z`/`ret c`): acaba y sigue el ciclo | **E** (baja: patológico) | Una lógica 0 sin `return` final se repetiría en ScummVM | Aceptado salvo regla del usuario |
| **A3-10** (nuevo) | `agi.h:83-84`: `MAX_STRINGS 24` (+1 para `get.num`), 40 bytes | Z80: **12 cadenas** (`strptr` agiin.asm:269, `cp 12`/`ret nc` en `h_set_string` :287, `h_get_string` :733, `t_cmpstr` agic.asm:1139 y 1146, `t_parse` agic.asm:611, `h_word_to_string` :797). Modelo `strs = [''] * 12` | **E** (**grave: se usa**) | **PQ1 usa la cadena 12**: `set.string(s12, m14 " ")` (lógica ~2864 del listado) y `get.string(s12, m15 "Note: ", 23, 0, 30)`. **Larry1 usa la 12**: `set.string(s12, m185)`, `compare.strings(s11, s12)` y `compare.strings(s1, s12)` (lógicas con la contraseña/prueba de edad). En la placa el `get.string(s12…)` **vuelve sin esperar** y `compare.strings(.., s12)` da siempre falso | Ampliar a 13 cadenas (la 13ª para el índice 12; ScummVM tiene 25). `STRS` ocupa `$7710`-`$78FB` y `MSGBUF` está en `$7900`: hay que reubicar 41 bytes (el núcleo está al límite, `PLAN.md:170`: 10962 de 11008) y el formato de guardado cambia (`sf_tab` STRS,492) |
| **A3-11** = D39 | `op_cmd.cpp:2136-2141`: `set.string` copia el texto **sin formato**, 39 caracteres | Z80 `h_set_string` agiin.asm:286-296: `build_str` con **formato** y `c=40`. Modelo igual | **E** | `set.string(s, "…%v3…")` guarda ya el valor; en ScummVM se evalúa al imprimir. PQ1 hace 166 `set.string` | Guardar en bruto y formatear al usar (`%sN`) |
| **A3-12** = D41 | `text.cpp:1304-1383` (leído) | Z80 `build_str` agiin.asm:1294-1413: `%v` (lee y **ignora** `|W`, :1352-1366), `%m %s %w %g` **sin recursión** (:1379-1410). Falta `%0N` (nombre de objeto) y `\`. Un `%x` desconocido imprime `%` (ScummVM lo traga). Modelo `py:421-437` igual | **E** | `%vN|3` sin relleno de ceros; `%s`/`%m` con códigos dentro salen sin formatear; "You take the %o1"-like (`%0N`) sale mal. Ojo: `%sN` en ScummVM usa `getString(N)` (no N−1) y `%mN` solo si `numTexts > i` | Añadir ancho `|W`, `%0N` (nombre de INVNAMES) y recursión limitada |
| **A3-13** = D35/D36/D37/D49 | `words.cpp` (AUD2); `op_test.cpp:336` `if (f4 || !f2) return false` | Z80: `parse_text` agiin.asm:862-993 (quita `' ` - " .` sin separar, separa por todo lo no alfanumérico; MAXW 6; 16 palabras), sin regla `a`/`i`; `ev_text` :92 y `t_parse` agic.asm:623 ponen **f2=1 siempre**; `hc_said` agiin.asm:1140-1148 mira **`inwvalid` y `v9`**, **no `f2`**. `t_parse` no pone `v9=0`/`f4=0` antes (:610-624) | **E** | (a) frases solo de palabras "ignorar" → f2=1 y "I don't understand"; (b) palabra desconocida: `said(.., anyword/9999)` nunca es cierta; (c) `take.sword` es 1 palabra; (d) **nuevo**: `reset(f2)`/`set(f2)` desde la lógica no tiene efecto sobre `said` | f2=(palabras>0); `hc_said` mirar `FLAGS+2` y no `v9`; tratar `a`/`i`; igualar separadores de `words.cpp:181-245` |
| **A3-14** = D42 | `text.cpp:480-500`: solo ENTER/ESC cierran; ESC marca cancelado; `v21*20` ciclos de 25 ms = `v21` × 0,5 s | Z80 `pr_wait` agiin.asm:437-493: **cualquier tecla** cierra (`keyn` cambia); `pw_lim = 25·v21` vueltas (`t_prt` agib.asm:808-823) con `wait_frame` (50 Hz → 0,5 s ✓); pone `v21=0` ✓. Sin ESC | **E** (baja) / **H** parcial (ayuda dice "pulsa cualquier tecla", `s_pause` agib.asm) | Una tecla cualquiera cierra una ventana que en ScummVM solo cierran ENTER/ESC. Con `print` seguido de `restart.game` etc. la tecla "cancelar" no se distingue (se usa `pw_last`==13) | Aceptado si se documenta. Coste de igualar: 2 comprobaciones |
| **A3-15** = D43 | `op_cmd.cpp:1999-2097` (AUD2): `get.num` bloquea; `get.string` con ESC deja la cadena vacía | Z80 `t_getnum` agic.asm:577-607: **no espera** (saca de la cola o 0; solo cifras, mod 256). `h_get_string` agiin.asm:732-784: sin ESC (solo en la descripción de partida, `gs_cust`) | **E** | KQ1/KQ2/PQ1/SQ1/Larry1 usan `get.num` (11-21 veces): se obtiene 0 si el evento no estaba listo | Hacer `get.num` modal como `get.string` |
| **A3-16** = D45 | `inv.cpp` (AUD2): `f13` con inventario vacío: ENTER → `v25 = 0`; ESC → 255; empieza en `v25` | Z80 `h_status` agivm.asm:1518-1544 / `t_dlginv` agib.asm:2141-2190: con `f13` y vacío → `v25=255` sin esperar; lista de una columna, empieza en el primero | **E** (baja) | Lógica que usa `status` con f13 (`See Object`): vacío distinto, cursor inicial distinto | Aceptado salvo regla estricta |
| **A3-17** = D46 | `menu.cpp:308-403,494-593`: `menu.input` solo marca; ejecuta fuera de la lógica; **recuerda menú y elemento** (`_lastSelectedMenuNr`, `selectedItemNr`); navegación circular; requiere `submit.menu` y `_allowed` | Z80 `h_menu_input` agiin.asm:518-622: **inmediato**, controlador en el mismo ciclo; `h_submit_menu: ret` (nop, :512); `t_menuopen` agib.asm:1813-1826 empieza **siempre en menú 0 / elemento 0**; ENTER en desactivado se ignora ✓; ESC ✓. `OVB_MENURESET` (agib.asm:1302) está **definido y nunca llamado**: `restart.game` no reactiva los elementos (ScummVM `itemEnableAll`, `op_cmd.cpp:1908` (AUD2)) | **E** (parte **H**: teclado) | `if(controller(X))` tras `menu.input` en el mismo ciclo es cierto en el nuestro y falso en ScummVM; no se recuerda la selección; tras `restart.game` siguen desactivados los elementos desactivados (SQ1 lógica 0: `disable.item(c20)` y `set(f6)`) | Recordar menú/elemento (2 bytes); `itemEnableAll` en restart; el momento, aceptado |
| **A3-18** = D47 | `op_cmd.cpp:1894-1910` (AUD2): con f16 reinicia sin preguntar | Z80 `h_restart_game` agivm.asm:1487-1506: siempre pregunta (`pr_rawgo 2`). Modelo igual | **E** | **PQ1 y Larry1 hacen `set(f16)`** (lógica 0/9): su `restart.game` tras la muerte debería ser sin confirmación | Mirar `FLAGS+16` antes de `pr_rawgo` |
| **A3-19** = D48 + nuevos | `saveload.cpp:70-343` (`saveGame`) y 345-757 (`loadGame`), ambos **leídos** | Z80 `agid.asm:325-326` `sf_tab`: VARS, FLAGS, INV, KEYMAP, OBJ(1024), STRS(492), horizon, blk(5), pctl, lastpic(2), mg, st_on, tfg/tbg, accin, ticks, lista de add.to.pic. **No guarda**: `slot_sip` (el `sIP`/`cIP` de cada lógica, `saveload.cpp:222-226`), `exitAllLogics` (`:174`, y `doLoad` lo pone a true, :816), cadenas 12-24, `curchar`. **No pone `v8=180`** (`saveload.cpp:480`) y **restaura el block** que ScummVM **desactiva** al cargar (`saveload.cpp:532`). Sí: `h_stop_sound` ✓, `f12=1` ✓ (agid.asm:245), logica 0 repetida (`rs_rerun`) ✓, `exitall` ✓. `OVB_MENUON` (todos los elementos activos tras cargar) ✓ (agiin.asm:684) | **E** (sIP, block, v8) / **H** (12 ranuras, formato propio) | Tras cargar, una lógica de sala que usó `set.scan.start` empieza por el principio (si la sala se cargó en esta sesión conserva el `sIP` de **esta** sesión, que puede no corresponder a la partida). El block de la partida guardada reaparece (ScummVM: no). Sin efecto en juegos que no leen v8 (solo `log`, nop) | Guardar `slot_sip` por lógica (o rehacer: lógica 0 siempre desde 0); `blkf=0` al cargar; `v8=180` |

### 2.3 `new.room`, valores iniciales, objetos

| Id | ScummVM | Modelo / Z80 | Tipo | Efecto | Propuesta |
|---|---|---|---|---|---|
| **A3-20** = D11 (**efecto nulo comprobado**) | `cycle.cpp:465-522`+`agi.cpp`: v22=1 (PC), v24=38, v8=180, v10=0, v15=0, v26=3; f11,f5,f9=1 | Z80 `t_restart` agic.asm:36-135: v8=255, **v10=2, v15=3, v22=15, v24=41**, v26=3; f9,f5,f11,pctl=1. El Z80 y el modelo **coinciden entre sí**. `IL_MAX=39` fijo (agispr.asm:333) | **AC** (sin constancia, ni PLAN ni commit; `3ee1db3`/`5d97977` lo ponen sin motivo) | **Ninguna lógica de los 6 juegos lee v22, v24 ni v8** (v8 solo en `log(…%v8/4K memory left)`, nop); v15 solo en `assignn(v15,3)`; v10 siempre se asigna antes de leerse. Efecto: nulo en estos juegos | Poner los valores de ScummVM (3 líneas) para cumplir la regla |
| **A3-21** = D14a-d | `cycle.cpp:56-148`; no borra la imagen en `newRoom` | Z80 `do_new_room` agivm.asm:888-946 + `t_newroom` agic.asm:1197-1222: **IGUAL** en objetos, `v1=v0`, `v16`, reposición por v2, f5, horizonte, `pctl`, block, sIP≠0, Larry f36. Z80 conserva la imagen pero `st_n=0` y apaga los sprites hasta el final del ciclo; modelo borra `pic_ops` ('z') | **H/O** (sprites: `PLAN.md:194`: "los add.to.pic ya pintados se quedan en la imagen hasta el siguiente draw.pic") + **H** (`NOBJ=32`) | `NOBJ=32` **suficiente: el objeto máximo que usan los 6 juegos es el 19** (grep `\bo[0-9]+\b` de los listados; PQ1=19). Sin efecto sobre la prioridad de reposición (la imagen anterior sigue en `PG_PRI`) | `NOBJ`: documentar; `getobj` (agiobj.asm:35-52) hace `fatal 10` si ≥32 |
| **A3-22** = D16 | `op_cmd.cpp:1669,1697,1750` (AUD2): `follow.ego`/`move.obj`/`wander` ponen `fUpdate` | Z80 `h_move_obj` agiobj.asm:610, `h_follow_ego` :643, `h_wander` :648: solo `set 4,(ix+O_F1)` (bit "mon"); **sin `set 2` (upd)**. Modelo igual | **E** | Un objeto con `stop.update` al que se manda `wander`/`follow.ego`/`move.obj` sigue sin moverse | `set 2,(ix+O_F1)` en los tres |
| **A3-23** = D18 | `motion.cpp:110-138` `cyclerActivated` (leído): sobrescribe `wander_count`/`follow_stepSize`/`move_x` con la bandera del ciclador | Z80: solo `motact` (agiobj.asm:655-664: `ignoreLoopFlag`). `eol_set` (agiobj.asm:528-540) no llama a un equivalente de `cyclerActivated`. Modelo igual | **E** | Las brujas de BC y el águila de **KQ1 sala 22** y **KQ2** dependen de ello según el comentario de ScummVM (`motion.cpp:60-65`): el movimiento sigue con el contador sin pisar | Implementar: si el objeto tiene motion, sobrescribir `O_WANDER`/`O_MSTEP`/`O_TX` con `O_CFLAG` (3 ramas) |
| **A3-24** = D22 | `view.cpp:686-732` (leído): `updateView` siempre | Z80 `t_cycles` agic.asm:1061-1070 (+ modelo `py:1848`): con **v10 ≤ 1**, objeto ≠ ego, `ctype\|motion\|dir == 0` → **no** llama a `cycle_cel`, pero sí recarga el contador | **O, documentada** (`PLAN.md:197`, commit `40816d1`: "ScummVM no tiene esta regla (es una opción nuestra)… Un objeto cuya lógica lea su celda (`current.cel`) verá la celda congelada") | Visible: `current.cel`/`last.cel` de objetos estáticos con ciclo normal cuando el juego va en Fast/Fastest (v10 ≤ 1; PQ1 usa v10=1). Ningún `end.of.loop`/`reverse.loop` se pierde (ctype≠0 no se congela) | Aceptado. Test T-28 |
| **A3-25** = D24/D25 | `checks.cpp:95-100` (leído): cruce de línea base con `yPos_prev` de **ambos** objetos; `sprite.cpp:352-369` `fDidntMove` | Z80 `can_be_here` agiobj.asm:1136-1157: usa la `y` **actual** de ambos; `uo_mv` agiobj.asm:780-795: `dm` = "el paso no movió" respecto a antes del paso. **No hay `*_prev`** (ni `position` los fija: agiobj.asm:200-205). Modelo igual | **E** | Tras `reposition.to`/`position` (que en ScummVM sí tocan/no tocan `_prev` de forma distinta) el cruce de línea base y `fDidntMove` dan otra cosa; wander/follow.ego eligen otra dirección | Guardar `yprev` y `xprev` por objeto (2 bytes ×32 = 64) |
| **A3-26** = D27 | `view.cpp:475-608` (AUD2) | Z80 `obj_cell` agiobj.asm:70-151 con `vclamp=1`: bucle/celda fuera de rango → **último** (ScummVM: `setView` → bucle 0 / celda 0; `setLoop` → celda 0). **`sv_set` escribe v16** con la vista del ego (agiobj.asm:275-276); ScummVM solo en `newRoom` (`cycle.cpp:84`) y en el Z80 también `t_newroom` agic.asm:1220. Modelo igual | **E** (el commit `1cd38bb` documenta que **conservar** bucle/celda es lo correcto; lo que no se cubre es el caso fuera de rango) | Vistas con distinto nº de bucles/celdas: celda y tamaño distintos → `fixPosition`/colisión distintos; **v16 cambia con `set.view(ego)`** | Fuera de rango → 0 (no el último); no escribir v16 en `sv_set` |
| **A3-27** = D31 | `sprite.cpp:439-480`, `op_cmd.cpp:1477-1510` (AUD2) | Z80 `h_add_to_pic` agiobj.asm:399-476: límite `ST_MAX=48`, `MG_MAX=12`; caja de control solo con margen 0-2 (`cp 3`/`jr nc` :415-416) aunque el campo es de 2 bits y cabe el 3; **sin `fixPosition`**; prioridad 0 → `pri_y` de la `y` original | Límites **H/O documentados** (`PLAN.md:194`); margen 3 y `fixPosition` **E** | **Márgenes usados en los 6 juegos: 0, 1, 4-15; ninguno 2 ni 3** (conteo de `add.to.pic`). Máx. `add.to.pic` por lógica: PQ1 104 = 32 ≤ 48; cajas (margen 0-2): máx. 11 (PQ1 lógica 36) de 12 (`add.to.pic.v`: 8 usos en PQ1 no contados) | Margen 3 y `fixPosition`: trivial; sin efecto hoy. Subir `MG_MAX` si hay holgura |
| **A3-28** = D32 | `sprite.cpp:269-271` (AUD2): `f1 = isViewHidden` del ego | Ningún `FLAGS+1` en `ENGINE/*.asm` (grep) ni `flags[1]` en el modelo | **E/AC** | **KQ2/SQ2/SQ1/PQ1 hacen `isset(f1)`/`set(f1)`/`reset(f1)`**; ej. `if (!isset(f1) && equaln(v59, 0))` | Calcularla desde el plano de prioridad o dejarla siempre a 0 y documentarlo; mirar si esas lógicas dependen del valor del intérprete (también la *escriben* ellas) |
| **A3-29** = D53 | `op_test.cpp:305-326`: usa `xSize` aunque no esté dibujado | Z80 `cond_obj` agiobj.asm:681-685: `D=E=0` si no dibujado | **E** (baja) | `obj.in.box`/`right.posn` tras `erase` | Quitar el `ret z` |
| **A3-30** (nuevo, **Z≠M**) | `cmdReposition` (op_cmd): `xPos` es `int` | Z80 `rp_add` agiobj.asm:241-255 trabaja en **8 bits** (x+dx > 255 envuelve); modelo `py:913-921`: enteros sin límite. Mismo en `t_motion` bloque (`add a` de x nueva, agic.asm:1005-1009) | **E** (baja) | `reposition` con dx grande: Z80 coloca el objeto a la izquierda; modelo/ScummVM lo empujan con `fixPosition` | `cp 255` con saturación |
| **A3-31** (nuevo) | `checks.cpp:305-352` `fixPosition`: sin tope | Z80 `t_fixpos` agic.asm:676-713 y modelo: tope 171 vueltas ("se queda donde estaba") | **O** (seguridad; sin constancia documentada, pero ScummVM se colgaría) | Nunca con juegos reales | Aceptado |

### 2.4 Dibujo, sonido y limitaciones de hardware

| Id | ScummVM | Nuestro | Tipo | Efecto | Propuesta |
|---|---|---|---|---|---|
| **A3-32** | `sprite.cpp` (AUD2) pinta cada pixel del objeto si `prioridad objeto ≥ prioridad del fondo` (+ `checkControlPixel` graphics.cpp:519-542: busca hacia abajo el primer valor > 2) | Z80 `hg_okb` agicel.asm:94-124: igual regla (`<=`) sobre el plano `PROW`; 64 sprites, 12 por línea; rótulos > 6 mosaicos por fila al bitmap (`agisw.asm`); `FORCE_SW`/`FORCE_HW` por juego; objetos **x ≥ 160** y bucles **> 8190 bytes** no se dibujan (`py:248`, `py:259`) | **H**, documentado (`PLAN.md:91,103,162-165,170-171`) | Solo visual; **no cambia variables**. Salvo: `spr_big` (nunca dibujados) — `PLAN.md:91` lo da como pendiente en PQ1 vista 105 y no consta si se resolvió | Comprobar si algún bucle de los 6 juegos supera 8190 bytes |
| **A3-33** | `GfxMgr::priorityFromY`/`createDefaultPriorityTable` (graphics.cpp:1295-1303, **leído**): filas 0-47 → 4; luego +1 cada 12, máx. 14 | Z80 `pri_y` agiobj.asm:160-176: 4 si y<48, `5+(y-48)/12`, tope 15 (alcanzable solo con y>167: nunca) | **IGUAL** (comprobado ahora contra el código literal) | — | — |
| **A3-34** | `graphics.cpp:1305-1316` `setPriorityTable` (`set.pri.base`) | No existe | **AC → descartada**: ninguno de los 6 juegos emite el opcode (§1.3) | — | — |
| **A3-35** = D14b / `sound.cpp` (**leído**) | `stopSound()` (`sound.cpp:151-168`) **pone la bandera** del sonido en curso; `startSound` hace `stopSound()` y luego pone la nueva a 0 (:133,148); `soundIsFinished` pone la bandera al acabar el audio (:171-179). Si el sonido no está cargado, `startSound` **no toca nada** (:128-131) | Z80 `snd_stop` agivm.asm:1653-1667 pone todas las pendientes; `h_sound` :1565-1645 hace `snd_stop` y luego f=0, duración `(2t+3·v10)/(6·v10)` ciclos, mín. 2; `snd_due` :1111-1146 las pone **al empezar el ciclo** (no durante ventanas, A3-01). Hasta 8 pendientes. `do_new_room` ✓ (`h_stop_sound`). | **H** (el MCU reproduce VGM; la bandera se simula por duración — comentario `agivm.asm:1564`; `5d97977`) | La bandera de fin de sonido llega con la granularidad del ciclo y no durante una ventana/menú; el tiempo real depende de A3-02. `sound` con un nº de sonido inexistente: ScummVM no cambia la bandera, nosotros la ponemos a 0 y luego a 1 | Llamar `snd_due` también en los bucles modales |
| **A3-36** | `cmdPut`/`cmdPutF` (`op_cmd.cpp:615-630`, **leído**): `put(o,n)` hace `objectSetLocation(o, getVar(p1))`; `put.v(v,v)` ambos por variable. Su propia tabla (`opcodes.cpp:275-276`) dice `put "nn"`, `put.v "vv"` | Z80 `h_put`/`h_put_v` agivm.asm:1458-1471: `put(obj, sala literal)`; `put.v(obj literal, sala en variable)`. `agi_logic.py:43`: `('put','in'),('put.v','iv')` | **AC → a nuestro favor** | **Los datos reales lo confirman**: `PQ1: put(i4, 0)`, `put(i1, 0)`, `put(i10, 0)` (sala **literal** 0); `Larry1: put.v(i45, v46)` (objeto literal `i45`, sala en `v46`). La lectura de esta copia de ScummVM (`put(.., 0)` = sala `v0`; `put.v` con objeto variable) contradice su propia tabla: **parece un fallo de este snapshot, no un comportamiento a copiar** | No cambiar. Test T-30 |
| **A3-37** | `cmdVersion` muestra un messageBox; `cmdConfigureScreen` mueve filas; `cmdForceUpdate` redibuja; `cmdShowPriScreen` espera tecla | `h_nop` (agitab.inc): `load.logics(.v)`, `load.pic`, `discard.pic`, `show.pri.screen`, `load.view(.v)`, `discard.view(.v)`, `force.update`, `load.sound`, **`configure.screen`**, `init.disk`, `obj.status.v`, `init.joy`, `toggle.monitor`, **`version`**, `script.size`, `log`, `trace.on/info`, `set.upper.left`, `open/close.dialogue` | **H** (diseño fijo de pantalla 42×24 de 6 px; `load.*` inocuos: `PLAN.md:97`) / **AC** para los dos con efecto visible | `configure.screen`: KQ1 usa `(0,21,0)` y luego `(1,22,0)`; los otros `(1,22|23,0)`. `version()`: ScummVM abre una ventana. `force.update` no cambia estado (los sprites siempre están al día) | Documentar |
| **A3-38** | Opcodes que cambian de parámetros con la versión (`opcodes.cpp:405-421`: `quit` sin parámetros en 2.089, `print.at` con 3 en <2.089…) | `agi_logic.py` usa una sola tabla ('quit','n', 'print.at','mnnn'). La versión de cada juego no está en `GAMES` | **AC** | Los 506 listados decodifican sin error (el desfase de argumentos habría roto límites de bloque), así que en estos juegos la tabla es coherente. SQ1 hace 6 `quit` | Anotar versión por juego |
| **A3-39** | `cycle.cpp:296-298`+`agi.h:446-454` `nonBlockingText`, `artificialDelay_*` (retardos por juego en `new.room`/`draw.pic`), `getVarSecondsHeuristic` (espera 10 ms si la lógica espera segundos en bucle) | No existen | **H** (son apaños de ScummVM para ir rápido que no hacen falta en una máquina lenta) | Sin efecto sobre lógica | — |
| **A3-40** | `RandomSource::getRandomNumber` | LFSR `rand8` + `rem8` (agivm.asm:1189-1200,1428) | **H** | Distribución casi uniforme; no se puede igualar | — |

---

## 3. Fusión con AUDITORIA2 (D01…D55)

"Vigente" = sigue sin cambios porque desde AUDITORIA2 no se ha tocado código (`git log`: el último commit de código es `86f41bb`, anterior a AUDITORIA2).

| D | Resumen | Estado en AUDITORIA3 |
|---|---|---|
| D01 | v19 con teclas de controlador/dirección | **Vigente, corregido**: direcciones no afectan al teclado real (A3-03) |
| D02 | v19 tras ENTER | Vigente (A3-04) |
| D03 | dirección por evento/alternancia | Vigente, tipo AC (A3-05) |
| D04 | varias teclas por ciclo | Vigente, **H**: cola de 8 (`KEYQ`), v19 = última; sin efecto probado |
| D05 | have.key | Vigente, O (A3-06) |
| D06 | set.key | Vigente, H (A3-07) |
| D07 | orden dirección/checkAllMotions | **Comprobado en el Z80**: `t_pre` agic.asm:923-948 IGUAL |
| D08 | lógica 0 sin `return` | Vigente (A3-09) |
| D09 | limpieza en el bucle de `runLogic(0)` | **Comprobado en el Z80** (agivm.asm:209-231 + `do_new_room`): IGUAL |
| D10 | f5/f6/f12 al final del ciclo | Vigente, sin efecto; **`rs_keep` documentado (93aab87) y correcto**: `runGame` (`cycle.cpp:454-457`) pone f6 en el primer ciclo del juego reiniciado |
| D11 | valores iniciales | Vigente, efecto nulo en los 6 juegos (A3-20) |
| D12 | `newRoom` inmediato vs diferido | Vigente (resultado igual salvo D13) |
| D13 | cortocircuito | Vigente en Z80 y modelo (A3-08) |
| D14 | `newRoom` punto por punto | Z80 comprobado IGUAL (A3-21); `stopSound` pone la bandera ✓ (resuelve la duda 14b) |
| D15 | animate.obj | **Comprobado en el Z80** (`t_animate` agic.asm:564-575): IGUAL |
| D16 | follow/move/wander sin fUpdate | Vigente en Z80 (A3-22) |
| D17 | fMotion | Sin efecto (ScummVM no lo lee fuera de `changePos`) |
| D18 | cyclerActivated | Vigente (A3-23) |
| D19 | follow/move | IGUAL (Z80 `mo_go` agiobj.asm:592-617) salvo D16/D18 |
| D20 | wander/follow/moveObj | **Comprobado en el Z80** (`t_motion`/`t_follow`/`mv_od`): IGUAL; aleatorio H |
| D21 | checkMotion/bloques | **Comprobado en el Z80** (`bk_in` agiobj.asm:1041-1060): IGUAL |
| D22 | atajo Speed Fast | Vigente, **O documentada** (A3-24) |
| D23 | updatePosition | **Comprobado en el Z80** (`mv_pos` agiobj.asm:845-977 contra `checks.cpp:187-289`): IGUAL, incluidas rollback+`fixPosition` y borde→v2/v4/v5 |
| D24 | `yPos_prev` | Vigente (A3-25) |
| D25 | fDidntMove | Vigente (A3-25) |
| D26 | checkPriority/fixPosition | **Z80 comprobado IGUAL** (`pic_check` agipic.asm:320-386, `t_fixpos`); `set.pri.base` **no usada** (A3-34); tope 171 O (A3-31) |
| D27 | set.view/loop/cel, v16 | Vigente (A3-26) |
| D28 | clipViewCoordinates | **Z80 comprobado IGUAL** (`clip_view` agic.asm:1109-1135) |
| D29 | set.cel/fix.loop/end.of.loop… | IGUAL |
| D30 | reposition/position | Z80 IGUAL salvo 8 bits (A3-30) y `_prev` (A3-25) |
| D31 | add.to.pic | Vigente (A3-27) |
| D32 | f1 | Vigente (A3-28): **sí se lee en 4 juegos** |
| D33-D34 | stop/start.motion, set.dir… | IGUAL (Z80 agiobj.asm:554-584, 668-675) |
| D35 | parse | Vigente + nuevo (A3-13) |
| D36 | testSaid mira v9 | Vigente (A3-13) |
| D37 | normalización | Vigente (A3-13) |
| D38 | selección de palabra | Igual en el Z80: "la última coincidencia manda" (find_word agiin.asm:1069-1135) |
| D39 | set.string | Vigente + **grave 12 cadenas** (A3-10, A3-11) |
| D40 | comandos que faltan | **Reducido**: `hold.key`, `release.key`, `set.pri.base`, `set.simple`… no se usan en los 6 juegos (§1.3) |
| D41 | stringPrintf | Vigente (A3-12) |
| D42 | print | Vigente (A3-14) |
| D43 | get.num/get.string | Vigente en Z80 (A3-15) |
| D44 | status line | Sin cambio |
| D45 | status/inventario | Vigente (A3-16) |
| D46 | menús | Vigente en Z80 (A3-17); `OVB_MENURESET` sin uso |
| D47 | restart / f16 | Vigente; **f16 lo ponen PQ1 y Larry1** (A3-18) |
| D48 | save/restore | Vigente + nuevos (A3-19) |
| D49 | parse(s) | Vigente (Z80 `t_parse` agic.asm:609-624) |
| D50-D51 | resetControllers, random | IGUAL / H |
| D52 | put/put.v | **Cerrada a nuestro favor** (A3-36): no copiar la lectura de ScummVM |
| D53 | obj.in.box no dibujado | Vigente (A3-29) |
| D54 | show.obj | H, sin cambio |
| D55 | pictures | **Ya leído `picture.cpp` entero**: las imágenes se rasterizan fuera del Z80 (`agi2hr.py`); su equivalencia con `picture.cpp` **no está auditada** (fuera de la lista pedida). Reglas relevantes: pantalla inicial 15/4, `drawPicture` F0-FA, `draw_Fill` con `_scrColor != 15` etc. |

---

## 4. Desviaciones H/O bien documentadas (con constancia)

| Qué | Constancia | Efecto sobre la lógica |
|---|---|---|
| Pantalla HiRes 8×1, 160→256 px, 42×24 caracteres de 6 px, sprites HW (64, 12 por línea), rótulos anchos por software, `FORCE_SW/FORCE_HW` por juego | `PLAN.md:23, 91, 103, 162-165, 170-171`; commits `0e5b706`, `a6ccfe5`, `07e06c6` | Visual. Lógica en coordenadas AGI 160×168 |
| Congelar vistas (`FREEZE_VIEWS`, SQ1 vista 175: ciclo 127 al dibujarla) | `PLAN.md:163`; commit `bbf000e` ("de 106.700 a 31.000 instrucciones por ciclo"), `agi2spr.py:136` | `current.cel`/fin de ciclo de esa vista, solo cúpulas SQ1 sala 6 |
| Speed Fast/Fastest no cicla objetos estáticos | `PLAN.md:197`; `40816d1` | `current.cel` de objetos estáticos en Fast/Fastest (**documentado con su efecto**) |
| `PACE_V10` (ritmo de AGI) | `PLAN.md:105`; `14b32ae` | Solo el reloj (A3-01) |
| `NOBJ=32` | `PLAN.md:74` (tabla de 32 objetos); **verificado ahora**: máx. objeto usado = 19 | Ninguno |
| `add.to.pic`: 48 por imagen, 12 cajas, caja de control 0-2 | `PLAN.md:194` (con las cifras) | Verificado con los datos: ≤ 32 y ≤ 11 por lógica |
| Teclado ZX81: capas, F-keys→códigos de control, `ESC`=9 | `PLAN.md:89,97,111`; `TECLAS.md` | Ver A3-03 |
| Sonido por duración + MCU | comentario `agivm.asm:1564`; `5d97977` | Banderas con granularidad de ciclo (A3-35) |
| `save/restore` en 12 ranuras con overlay D | `a2d018e` | Formato propio |
| Overlays/paginas/memoria | `PLAN.md:170` (núcleo 10962/11008) | Ver A3-10: **la memoria es el motivo de que haya 12 cadenas, pero ese límite sí afecta a 2 juegos** |

---

## 5. Lo que de verdad no he podido leer

- **ScummVM**: `graphics.cpp` 545-1262 y 1404-1570; `systemui.cpp` 300-1234; todo el audio (`sound_*.cpp` salvo el `grep`); `opcodes.cpp` 30-365 (tablas); `cycle.cpp` 215-340 (`processAGIEvents`); `view.cpp`, `sprite.cpp`, `keyboard.cpp`, `text.cpp` (casi todo), `words.cpp`, `inv.cpp`, `op_cmd.cpp`/`op_test.cpp`/`logic.cpp`/`agi.cpp` (en AUDITORIA2, no releídos); `loader*.cpp`, `console.cpp`, `font.cpp`, `lzw.cpp`, `wagparser.cpp`, `metaengine.cpp`, `preagi` (fuera de la lista). **Motivo**: presentación o fuera de la lista pedida; el presupuesto de contexto de la sesión no daba para releer lo que AUDITORIA2 ya leyó entero. Los puntos de AUDITORIA2 que dependen de esos ficheros se dan "por AUD2".
- **Nuestro lado**: `agib.asm` (≈ 2000 de 2294 líneas: dibujo de texto/ventanas/lista de menús); `agihws.asm` y `agisw.asm` (sprites HW y rótulos SW: solo cabecera + `grep` de que no escriben variables ni banderas); `agires.inc`, `font6.inc`, `sprtab.inc` (datos); `agi_vm.py` 71-215 y 412-1999 (los leyó AUDITORIA2). No he comparado `agi_vm.py` con el Z80 línea a línea salvo en los puntos marcados `Z≠M` (A3-30) y los que cito como "Modelo … igual"; **no puedo afirmar que modelo y Z80 coincidan fuera de lo que he leído**.
- `agi2hr.py`/`agi_read.py` (rasterización de imágenes y vistas): no auditados contra `picture.cpp`.
- No se ha ejecutado nada: ni el clon de ScummVM, ni los tests, ni el emulador. Todos los efectos "en la placa" se deducen del código.

---

## 6. Casos de prueba para la batería

Formato: *lógica de prueba* → *resultado esperado según ScummVM* (T-nn ↔ A3-nn). Los que ya estaban en AUDITORIA2 §8 siguen válidos (D13, D01, D02, D27, D16, D18, D24, D25, D53, D41, D39, D42, D43, D45, D46, D47, D11, D14a, D32, D22, D08, D52→ ahora T-36).

| T | Caso | Esperado |
|---|---|---|
| T-01 | v10=2, 10 s de reloj: `v11` | pasa de 0 a 10 al cabo de 100 ciclos (ScummVM, tiempo real). Repetir con v10=1 (200 ciclos) y v10=0 (400 ciclos). Con una ventana `print` abierta 5 s: v11 avanza 5 |
| T-03 | Larry1: pulsar ESC (controlador) y mirar v19 | v19 sigue 0; `have.key` falso |
| T-10 | `set.string(s12,"abc")`, `compare.strings(s12,s12)`; `get.string(s12,…)` con ENTER | cierta; espera la línea (no vuelve antes) |
| T-13 | tras `parse("the")` (solo palabra id 0): `isset(f2)` | falso |
| T-13b | `reset(f2)` antes de `said(look)` con "look" tecleado | `said` falso |
| T-18 | `set(f16); restart.game` (PQ1/Larry1) | reinicia sin ventana |
| T-19 | `set.scan.start` en la lógica de sala, guardar, cargar en sesión nueva | la lógica retoma desde su `sIP` |
| T-19b | `block(..)`, guardar, cargar | `blkf` = 0 tras cargar; `v8` = 180 |
| T-22 | `stop.update(o2); wander(o2)` | `o2` se mueve |
| T-23 | `wander(o3); end.of.loop(o3,f60)` | `wander_count` = 60 |
| T-25 | `reposition.to(o1,x,y)` y objeto 2 que se mueve ese ciclo | cruce de línea base con `yprev` |
| T-26 | `set.view(ego,N)` con v16 | v16 no cambia |
| T-27 | `add.to.pic` con margen 3 | caja de control con prioridad 3 (agua) |
| T-30 | `put(i4,0)` y `put.v(i45,v46)` con v46=12 | objeto 4 en la sala 0; objeto 45 en la sala 12 (como el listado de PQ1/Larry1) |
| T-35 | `sound(s,f)` con `sound` no cargado | f no cambia |
| T-36 | `configure.screen(0,21,0)` | ventana de texto con otra geometría (anotar si se acepta) |
| T-40 | 200 ciclos con `ncyc` en modo real vs. emulador, comparar `display("%v13:%v12|2:%v11|2")` del reloj de SQ1 | Z80 ≈ ScummVM ±1 s |

---

## 7. Conteo

Filas de §2 (A3-01…A3-40): **E 22, H 8, O 3, AC 6, IGUAL 1** (A3-33, comprobada ahora contra el código literal). Las AC son: A3-05 (dirección por soltar tecla), A3-20 (valores iniciales, efecto nulo comprobado), A3-28 (f1), A3-34 (set.pri.base, descartada), A3-36 (put/put.v, a nuestro favor), A3-38 (versión por juego). Las filas mixtas (A3-14, A3-17, A3-21, A3-27, A3-37) se han contado por su componente de mayor peso.

Las tres que más pesan (para decidir qué corregir primero): **A3-10** (12 cadenas: rompe PQ1/Larry1), **A3-01** (reloj por ciclos, en 4 juegos) y **A3-18** (`f16`, PQ1/Larry1).

---

## 8. Estado de las correcciones (sesión de correcciones, rama main de SCUMM)

Regla: se copia la lógica de ScummVM (`engines/agi`, f7403b6) en el modelo (`TOOLS/agi_vm.py`, `agi_read.py`) y en el Z80 (`ENGINE/*.asm`) a la vez. Cada grupo se comprobó con la misma bateria que `dump/runall.sh`
(SQ1, KQ2, PQ1, SQ2, KQ1: Z80 == modelo, 5 OK, 0 DIFs; se ejecutó en una copia del árbol para poder seguir editando) y con la batería nueva `ENGINE/test_audit3.sh`
(los casos T-nn de §6 que se pueden automatizar; el código de prueba se inyecta con `AGI_BOOT`, que ahora admite `if=`, `all` y `cyc=`; `agi_vm.py --show` imprime variables y banderas).
Decisiones del usuario: **A3-01 y A3-19 no se corrigen.** Commits: **C1 = 871ba0f**, **C2 = 98bb7f9**, **C4 = e88c0de** (A3-25), **C5 = c9788fe** (A3-28), **C3 = 3e9de06**.

| Id | Estado | Detalle |
|---|---|---|
| A3-01 | SIN CAMBIO (decisión del usuario) | El reloj cuenta ciclos y se para en menús/ventanas: intencionado (velocidad; el tiempo real sería demasiado difícil) |
| A3-02 | SIN CAMBIO (H) | `pace`, documentado en `PLAN.md:105` |
| A3-03 | CORREGIDA (C2) | `key_push`/`kp_m`: una tecla con controlador no pone v19 (modelo igual). T-03, T-03b |
| A3-04 | CORREGIDA (C2) | `ev_text` deja v19 = 13 (si ENTER no tiene controlador). SQ1 sala 10 `look screen` sigue esperando la tecla: esa lógica hace `assignn(v19, 0)` antes de `text.screen` (comprobado en el listado), así que `have.key` espera igual. T-04 |
| A3-05 | SIN CAMBIO (AC) | La dirección sigue a la tecla mantenida (`dirhold`): decisión de jugabilidad documentada en `PLAN.md:89,97`; los 6 juegos no usan `hold.key` |
| A3-06, A3-07 | SIN CAMBIO (O / H) | Como estaban |
| A3-08 | CORREGIDA (C2) | `do_if` con cortocircuito (`skip_until` = `skipInstructionsUntil`); modelo igual. T-08a/b/c |
| A3-09 | SIN CAMBIO | Se comprobó que la lógica 0 de los 6 juegos acaba en `return`; el caso patológico no ocurre |
| A3-10 | CORREGIDA (C1) | 13 cadenas (`NSTR`); los búferes de $7930 a $7EA0 se desplazaron; el formato de guardado cambia (las partidas anteriores no se cargan). T-10 |
| A3-11 | CORREGIDA (C2) | `set.string` guarda el texto sin formato (39 caracteres). T-11 |
| A3-12 | CORREGIDA (C2) | `stringPrintf`: `%vN` con `\|W` (relleno de ceros), `%mN` y `%sN` recursivos, `%gN`, barra + carácter, otro `%x` se traga la letra. Límites propios (H): un mensaje anidado como máximo (búfer `SUBBUF`) y 6 fuentes anidadas. **`%0N`/`%oN` (nombre de objeto) no se implementa**: el clon de ScummVM usa `case '0'` (como su `put`, parece un fallo del snapshot) y los datos de los juegos solo usan `%o` en mensajes de depuración (`log`, nop). T-12 |
| A3-13 | CORREGIDA (C2) | `parse_text` (overlay C) = `cleanUpInput` + `findWordInDictionary`; f2 = hay palabras, f4 = 0; `said` = `testSaid` (overlay C). El vocabulario sigue normalizado (`agi_read.norm_word`, H del teclado). Palabras: tope 16. T-13a-i |
| A3-14 | CORREGIDA (C2) | La ventana de `print`/pause/restart solo se cierra con ENTER o ESC (`pw_ent`); `have.key` sigue con cualquier tecla. Sin caso automático (el modelo no distingue teclas en la espera de la ventana más allá de ENTER/ESC) |
| A3-15 | CORREGIDA (C2) | `get.num` modal como `get.string` (3 caracteres, atoi módulo 256). T-15 |
| A3-16 | CORREGIDA (C6) | `status` como `InventoryMgr::show`: pantalla de texto blanca (charAttrib 0,15), "You are carrying:" en (0,11), objetos en dos columnas desde la fila 2 (izquierda en la columna 1, derecha acabando en la 39), marcado el de v25 (si no es del ego, el primero), flechas ±2/±1 sin dar la vuelta, ENTER → v25 = objeto, ESC → 255, vacío: "nothing" (objeto 0); pie en la fila 24 (va a la 23 del HiRes); sin f13 acaba con cualquier tecla (antes: ventana de `print`). Al acabar `graphics`. Z80: overlay F (`t_dlginv`, `iv_open`, `iv_nav`) con el mismo bucle de `menu.input`. Diferencia de hardware: una flecha sola no cuenta como tecla en el modo sin elegir (en el ZX81 son SHIFT+5..8, una dirección). T-16a-k |
| A3-17 | CORREGIDA (C6) | Se recuerda el menú de la última vez **y el elemento de cada menú** (`selectedItemNr` de cada `GuiMenuEntry`); `restart.game` reactiva los elementos (`itemEnableAll`). Sin hacer (aceptado en el informe): ejecutar fuera de la lógica / exigir `submit.menu`. T-17a |
| A3-18 | CORREGIDA (C3) | `restart.game` con f16 no pregunta; hace `stopSound` antes. T-18 solo en el modelo: **el estado de los objetos tras reiniciar difiere entre Z80 y modelo desde antes** (suma de objetos 37 frente a 65 en el ciclo del reinicio, también con la confirmación por ENTER en HEAD~; no es de esta sesión): queda como pendiente aparte |
| A3-19 | SIN CAMBIO (decisión del usuario) | sIP, block y v8 al cargar partida |
| A3-20 | SIN CAMBIO (AC) | Efecto nulo comprobado en los 6 juegos |
| A3-21 | SIN CAMBIO (H/O) | |
| A3-22 | CORREGIDA (C3) | `move.obj`, `follow.ego` y `wander` ponen fUpdate. T-22 |
| A3-23 | CORREGIDA (C3) | `end.of.loop`/`reverse.loop` pisan wander_count / follow_stepSize / move_x con su bandera (`cyclerActivated`). T-22 (unidad en el modelo + Z80 == modelo) |
| A3-24 | SIN CAMBIO (O) | |
| A3-25 | CORREGIDA (C4) | `OBJP` ($7EA0, 64 bytes; `CLR_END` pasa a $7EE0 y la pila queda en 288 bytes; se guarda en las partidas y entra en la suma de objetos) = xPos_prev/yPos_prev. Las ponen `position(.v)` y `draw` (tras `fixPosition`), no `reposition.to`; `t_show` (overlay C) = `showSprites`: tras mover a todos los objetos, los que acaban de dar su paso (stepTimeCount == stepTime) ponen fDidntMove si no se movieron o actualizan la previa; `checkCollision` usa las y previas de los dos objetos (estricto, sin el empate del Z80 anterior). T-25a-d |
| A3-26 | CORREGIDA (C3) | `set.view`: bucle fuera de rango → 0; celda fuera de rango tras cambiar de bucle → 0; `set.loop` fuera de rango → último; `set.cel` fuera de rango → última; `set.view` ya no escribe v16 (solo `new.room`). Cuidado: `set.loop` recorta ya contra la vista que haya en ese momento (ScummVM), así que un `set.loop` anterior al `set.view` de una vista con más bucles pierde el bucle (si algún juego depende de ello, será visible en la sala). T-26 |
| A3-27 | CORREGIDA en parte (C3) | Margen 3 (caja de control con prioridad 3). Sin `fixPosition` en `add.to.pic` (con prioridad 15 solo recorta a la pantalla; sin efecto en los datos). T-27 |
| A3-28 | CORREGIDA (C5) | Bandera 1 = ningún píxel del ego se pinta: se acumula en `agihws.asm` (`hw_hid`) al armar los sprites del ego (mosaicos con máscara tras la prioridad del plano) y se reescribe `FLAGS+1 = ego_hid` en cada ciclo en que el ego pasa por `spr_obj` (aunque el sprite esté en caché), así lo que ponga o borre la lógica se pisa como en ScummVM. Límites: si el ego va por software (celda ancha), está fuera (x ≥ 160) o sin datos, conserva el último valor; se calcula al armar los sprites (fin de ciclo), no en el instante de `draw`. T-28a/b |
| A3-29 | CORREGIDA (C3) | `obj.in.box`/`center.posn`/`right.posn` usan el tamaño de la celda aunque el objeto no esté dibujado (si tiene vista). T-29 |
| A3-30 | CORREGIDA (C3) | `reposition` satura en 255 (Z80 y modelo; `fixPosition` lo devuelve a la pantalla). T-30 |
| A3-31..A3-33 | SIN CAMBIO (O / H / igual) | |
| A3-34, A3-36, A3-38 | SIN CAMBIO (AC) | `set.pri.base` no se usa; `put`/`put.v` a nuestro favor; versión de cada juego |
| A3-35, A3-37, A3-39, A3-40 | SIN CAMBIO (H) | |

Tamaños al terminar: núcleo `agivm.bin` 10943 de 11008 bytes; overlays (límite 8192, el A2 4096): A1 5921, B 8175, C 3335, D 854, A2 3454.
Para que el núcleo cupiera: el parser y `said` pasaron al overlay C (con `call_c`); `OVB_MENURESET` (nunca llamado) quedó vacío.
Los datos de los tests que usan el comando `restart.game` solo comparan el modelo (ver A3-18).

Notas de C4/C5: núcleo 10981, A1 5987, B 8175, C 3417, D 854, A2 3454. Hallazgo previo no corregido: en SQ1 sala 1 el Z80 y el modelo difieren en la máscara del borde derecho de los sprites a x = 253 (un píxel); `cmp_vm.py` admite `AGI_NOSPR=1` (no comparar sprites) y `AGI_VERBOSE=1` (máscaras) para esos casos.
Sin hacer de la tarea opcional: A3-16 (dos columnas desde v25) y A3-17 (memoria por menú): el overlay B está a 8175 de 8192 y hay que repartirlo.
Corrección posterior a C5: la reubicación de búferes de C1 dejó `MSGBUF` (= `PROW`, la fila de prioridad de las máscaras de los sprites) en $7930, sin alinear a página, y los sprites del borde derecho se veían sin recortar (SQ1 sala 1, el doctor moribundo). Ahora `MSGBUF` = $7A00 y los búferes pequeños (`STMP`, `STMP2`, `INW`, `KEYQ`, `SREC`, `TRREC`) ocupan $7930-$79DF; `CLR_END` = $7F00, pila de 256 bytes. Caso T-MASK.

Tarea C6 (2026-10-31): **overlay B partido**. Nuevo overlay F (`agif.asm`, página 49, `OVERF.OVL`, `call_f`): menús (`set.menu`..`menu.input`) y listas de guardar/cargar/inventario salen de B. El código de texto común (línea de texto, fondo, `fill_row`, `t_boxclose`, fuente) está en `agitx.inc`, incluido en B y en F. Tamaños: núcleo 10979 de 11008; A1 5984, B 4406, C 3393, D 858, A2 3454, F 5928 (todos bajo 8192; A2 bajo 4096). Cambios de reparto: `OVB_BOXCLOSE`/`GSDRAW`/`CLRRECT` pasan a $201B/$201E/$2021; tras `OVF_MENUCLOSE` el núcleo llama a `OVB_STATUS`. `t_invtxt` (overlay C) ya no se usa. Savegame y mapa de memoria sin cambios (solo se usa una página más, la 49; `OVERF.OVL` va con el resto en `DATA/`). Pruebas: runall 5 OK, `test_audit3.sh T-1[67]` todo OK. No probado en la placa ni en EightyOne.


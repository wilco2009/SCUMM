# SCUMM v3 en el Z80 del SD81 Booster (Indy3 EGA)

Plan y estado: `../PLAN.md`. Mapa de memoria y nucleo (fase 3): `../FASE3.md`. Esta carpeta empezo como copia de `V2/ENGINE` (decision D1 del plan): los ficheros de v2
que todavia no se han pasado a v3 siguen aqui tal cual.

| Fichero | Que es | Estado |
|---|---|---|
| `vm_core.asm` | Nucleo residente: despachador, operandos de 16 bits, variables, ranuras, locales, scripts, cutscenes, freeze, decodificador generico, anfitrion | v3 (fase 3) |
| `vm_ops.asm` | Manejadores nativos del nucleo | v3 (fase 3) |
| `arith32.asm` | Aritmetica de 32 bits | v3 (fase 3) |
| `ovlb.asm` | Overlay B (pagina 49): `expression`; las fases 4b y 5 le anaden los manejadores con subopcodes y la frase | v3 (fase 3) |
| `vm.asm` | Montaje de pruebas del nucleo (codigo desde `$4200`, tablas desde `$8000`) | v3 (fase 3) |
| `tables3.inc`, `vars_v3.inc` | **Generados** por `../TOOLS/gen_vmtables3.py`: no editar | v3 |
| `test/test_vm.cpp`, `test/build_test.sh` | Arnes del nucleo: el Z80 contra `../TOOLS/vmmodel3.py` (modo nucleo) por trazas | v3 (fase 3) |
| `ovld.asm`, `geom.asm`, `walk.asm` | Overlay D (pagina 46): geometria de las cajas y caminata de v3; los opcodes de caminata estan en `ovc6.asm` (overlay C) | v3 (fase 6) |
| `scumm.asm`, `hr.asm`, `loader.asm`, `dp_cache.inc`, `ovc7.asm`, `build_scumm.sh` | **Programa completo (fase 5b)**: arranque, bucle principal, cargador de `DATA.BIN` v3 y de los overlays, pantalla D3, camara, sonido simulado, `moveCamera` (overlay C). Sin texto, interfaz, actores ni sonido real (fases 7 y 8) | v3 (fase 5b) |
| `game.asm`, `input.asm`, `mcu.asm` | Capa de juego de v2 | `mcu.asm` vale; `game.asm` e `input.asm` son **copia de v2** y no se incluyen (fases 7-9) |
| `overlay.asm` (`ui`, `hrui`, `cam`, `actors`, `snd`, `dark`, `save`, `mouse`) | Overlay A (pagina 50) | copia de v2 (fases 7-9) |
| `vm_core.asm` de v2, `tables.inc`, `vars_v2.inc` | sustituidos por los de v3 | |

## Probar el nucleo

Necesita `pasmo`, `g++`/`gcc`, el nucleo Z80 de EightyOne (`Z80SRC`, por omision `/c/ClaudeCode/Eightyone2/src`) y los `.LFL` de Indy3 en `SCUMM/V3/Indy Last Crusade`.

```
sh test/build_test.sh                                    # todas las salas, 1 semilla: tablas, montaje, DATA.BIN, escenarios del modelo, Z80 y comparacion
sh test/build_test.sh "../../Indy Last Crusade" 2 1,15   # 2 semillas, solo las salas 1 y 15 (y los scripts globales)
TS_VM=1 test/build/test_vm.exe test/build/vm.bin test/build/vm.sym test/build/ovlb.bin test/build/DATA.BIN test/build/scenarios.txt test/build/actual.txt
```

`TS_VM=1` imprime los T-estados de cada instruccion de script (desde la comprobacion de `CUR` en `es_loop` hasta que el manejador vuelve; sin las instrucciones anidadas) y una
tabla por opcode. Depuracion: `TV_TRACE=1` (opcode y puntero de cada instruccion) y `TV_PC=n` (las n primeras instrucciones del Z80).

`build_test.sh` escribe en `test/build/` (ignorado por git: lleva datos derivados del juego).

## Probar el programa completo (fase 5b)

```
sh test/build_boot.sh [fotogramas]    # monta scumm.asm y los overlays, empaqueta DATA.BIN, corre el arranque de Indy3 en el arnes (test_scumm) y compara el resumen D de
                                      # cada fotograma con el del modelo (vmmodel3.py boot-core). Salida: test/build/boot_actual.txt, boot_expected.txt y el volcado boot_dump.bin
test/build/test_scumm.exe test/prog/scumm.bin test/prog/scumm.sym test/build/sdboot 760 volcado.bin   # (con TS_MODELDELTA=1) corre hasta el fotograma 760 (la sala 1 desde el 694)
python test/check_hr.py volcado.bin test/prog/scumm.sym test/build/sdboot                              # la pantalla (sombra de la FPGA) es la sala en su camara, D3
```
`sdboot` es la SD simulada (carpeta `DATA/` con `DATA.BIN`, `OVLB.BIN`, `OVLC.BIN`, `OVLD.BIN` y los `ROOMnn.GFX`). Variables de entorno de `test_scumm.exe` nuevas: `TS_DIGEST`, `TS_MODELDELTA`,
`TS_OVCHK`, `TS_P15` y `TS_WATCHBRK` (ver el comentario de cabecera de `test_scumm.cpp`).

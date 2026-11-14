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
| `scumm.asm`, `game.asm`, `geom.asm`, `walk.asm`, `input.asm`, `hr.asm`, `mcu.asm`, `loader.asm`, `dp_cache.inc` | Programa completo y capa de juego | **copia de v2**: no ensambla con el nucleo nuevo (fases 5-9) |
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

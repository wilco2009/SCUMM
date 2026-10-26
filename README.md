# SCUMM en el SD81 Booster

Interprete de SCUMM para el Z80 del ZX81 con el SD81 Booster, con un nivel por version del motor:

| Carpeta | Contenido |
|---|---|
| `V2/` | SCUMM v2 (Maniac Mansion y Zak McKracken, DOS): `ENGINE/` (el interprete en Z80 y su arnes de pruebas), `TOOLS/` (conversores y empaquetador de datos, modelo de referencia en Python), `VIEWER/` (visor de salas), `games/` (perfiles por juego) y, ignorados por git, los datos originales (`ManiacMansionDOS/`, `Zak McKracken/`) y lo derivado (`preview*/`) |
| `V3/` | (por empezar) |
| `V1/` | datos originales de Maniac Mansion NES (ignorados por git) |
| `AGI/` | Interprete de AGI (Sierra), como ScummVM: `AGI/V2/TOOLS` (lector, conversor y desensamblador en Python), `AGI/V2/ENGINE` (visor Z80) y `AGI/PLAN.md`; primer juego: Space Quest I |

Cada version lleva su propio `ENGINE`, `TOOLS` y `games`; si algo se comparte entre versiones se sacara a una carpeta comun. Documentacion de V2: `V2/ENGINE/README.md`,
`V2/TOOLS/LFL2HR.md` y, en `claude/planning/`, `scumm_hires16.md`.

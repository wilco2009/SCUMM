# Zak, solo para test/disfraz_capo.sh: empaqueta como pack_data.py (mismos argumentos: --debug-room 4) pero el script de arranque de depuracion pone a Var[0] = 7 y arranca el script 96
# (el cartel de la sala secreta: el caponiano se pone el sombrero y las gafas con "Mi sombrero" justo despues, que hace hablar al mismo actor).
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'TOOLS'))
import pack_data
orig = pack_data.debug_boot_script


def boot(world, spec):
    b = orig(world, spec)
    assert b[-1] == 0xA0
    return b[:-1] + bytes((0x80, 0x80, 0x80, 0x1A, 0, 7, 0, 0x42, 96, 0xA0))      # breakHere x3, move(Var[0], 7), startScript(96), stopObjectCode


pack_data.debug_boot_script = boot
sys.exit(pack_data.main())

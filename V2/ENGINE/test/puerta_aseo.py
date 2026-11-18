#!/usr/bin/env python3
"""Zak McKracken, sala 11 (avion): Abrir la puerta del aseo (objeto 246) con la luz verde (objeto 248 apagado) debe abrirla.
Abrir = doSentence(253, 246) desde el script del verbo 1: ScummVM no reutiliza la ranura del verbo para ese script especial
(las marcas freezeResistant/recursive de la ranura deben coincidir). Comprueba el modelo; build_test.sh compara el Z80 con el
modelo en los escenarios zak.puerta_aseoN. Uso: puerta_aseo.py "carpeta de los .LFL de Zak" """
import os
import sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'TOOLS'))
import vmmodel

w = vmmodel.World(sys.argv[1])
pre = ['INIT', 'LOADROOM 11', 'FRAMES 3 5']


def run(cmds):
    return vmmodel.run_scenario(w, pre + cmds + ['FRAMES 3 30'])[1]


ok = True
vm = run(['OBJ 246 1'])
print('Abrir con la luz verde: puerta 246 estado', vm.state[246], '(esperado 8)'); ok &= vm.state[246] == 8
vm = run(['OBJ 246 1', 'FRAMES 3 20', 'OBJ 246 2'])
print('Abrir y cerrar: puerta 246 estado', vm.state[246], '(esperado 0)'); ok &= vm.state[246] == 0
print('OK' if ok else 'FALLO')
sys.exit(0 if ok else 1)

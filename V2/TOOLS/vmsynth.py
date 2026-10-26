#!/usr/bin/env python3
"""Scripts sinteticos para probar el nucleo del interprete en los casos que los scripts reales casi no tocan:
variables 14-16 (punteros), la correccion de la variable 40, aritmetica y bits, comparaciones sin signo,
estados de objeto, retardos de 24 bits, esperas, scripts anidados que se matan o se encadenan, errores y
los decodificadores de operandos con subopcodes.

Cada script acaba en stopObjectCode (00) y anota los valores con startSound (que sale por el anfitrion y
queda en la traza), asi el modelo y el Z80 se comparan en lo que pasa DENTRO del script, no solo al final.
"""
import struct

OPS = {
    'stop': 0x00, 'break': 0x80, 'jump': 0x18,
    'isEqual': 0x48, 'isNotEqual': 0x08, 'isGreater': 0x78, 'isGreaterEqual': 0x04, 'isLess': 0x44,
    'isLessEqual': 0x38, 'equalZero': 0x28, 'notEqualZero': 0xA8,
}


class Asm:
    """Ensamblador minimo con etiquetas para los saltos relativos de 16 bits."""

    def __init__(self):
        self.b = bytearray()
        self.labels = {}
        self.fix = []

    def raw(self, *bs):
        self.b += bytes(bs)
        return self

    def label(self, name):
        self.labels[name] = len(self.b)
        return self

    def jump(self, op, name, *pre):
        """op (+ operandos previos) y el salto relativo hacia la etiqueta."""
        self.b += bytes([op, *pre])
        self.fix.append((len(self.b), name))
        self.b += b'\0\0'
        return self

    def done(self):
        for pos, name in self.fix:
            self.b[pos:pos + 2] = struct.pack('<h', self.labels[name] - (pos + 2))
        return bytes(self.b)

    # atajos
    def say(self, n):                       # startSound(n): marca en la traza
        return self.raw(0x1C, n)

    def say_var(self, v):                   # startSound(Var[v]): anota el valor de una variable
        return self.raw(0x9C, v)

    def move(self, r, w):                   # Var[r] = w (palabra inmediata)
        return self.raw(0x1A, r, w & 255, (w >> 8) & 255)

    def move_var(self, r, v):               # Var[r] = Var[v]
        return self.raw(0x9A, r, v)

    def stop(self):
        return self.raw(0x00)


def delay_bytes(d):
    v = 0xFFFFFF - d
    return v & 255, (v >> 8) & 255, (v >> 16) & 255


def s_indirect():                           # variables 14, 15 y 16: la lectura es indirecta
    a = Asm()
    for k, (p, t, val) in enumerate(((14, 50, 77), (15, 51, 88), (16, 52, 99))):
        a.move(p, t).move(t, val).move_var(100 + k, p).say_var(100 + k)
    a.raw(0x46, 14)                         # increment Var[14]: lee indirecto, escribe directo
    a.say_var(14).say_var(50).say_var(78)
    a.raw(0xC6, 15)                         # decrement
    a.say_var(15)
    a.raw(0x0A, 20, 3, 0)                   # assignVarWordIndirect: Var[Var[20]] = 3
    a.raw(0x2A, 20, 5, 0)                   # addIndirect
    a.raw(0x6A, 20, 1, 0)                   # subIndirect
    a.say_var(20).stop()
    return a.done()


def s_var40():                              # writeVar: en la variable 40 el 4, el 13 y el 64 pasan a 27
    a = Asm()
    for v in (4, 13, 64, 5, 27, 0x1004):
        a.move(40, v).say_var(40)
    a.raw(0x2C, 40, 64).say_var(40)         # assignVarByte tambien pasa por writeVar
    a.raw(0x26, 40, 2, 13, 4).say_var(40).say_var(41)    # setVarRange (byte) escribe 40 y 41
    a.raw(0x5A, 40, 0, 0).raw(0x2C, 40, 4).raw(0x5A, 40, 9, 0).say_var(40)   # add no pasa por writeVar
    a.stop()
    return a.done()


def s_arith():
    a = Asm()
    a.move(110, 1000).raw(0x5A, 110, 234, 0).raw(0x3A, 110, 100, 0).say_var(110)
    a.raw(0x2C, 111, 110).raw(0x2A, 111, 7, 0).say_var(110)            # addIndirect sobre Var[110]
    a.raw(0x6A, 111, 17, 0).say_var(110)
    a.raw(0x0A, 111, 0x39, 0x30).say_var(110)                          # Var[Var[111]] = 12345
    a.raw(0x2C, 112, 200).say_var(112)
    a.raw(0x26, 120, 3, 1, 2, 3).say_var(120).say_var(121).say_var(122)
    a.raw(0xA6, 125, 2, 0x34, 0x12, 0xFF, 0xFF).say_var(125).say_var(126)   # setVarRange con palabras (con signo)
    a.raw(0xDA, 110, 120).say_var(110)                                  # add con variable
    a.raw(0xBA, 110, 125).say_var(110)
    a.raw(0x46, 110).raw(0x46, 110).raw(0xC6, 110).say_var(110)
    a.move(130, 0xFFFF).raw(0x5A, 130, 1, 0).say_var(130)               # envuelve a 0
    a.move(131, 0).raw(0x3A, 131, 1, 0).say_var(131)                    # envuelve a 65535
    # bits
    a.raw(0x1B, 0x00, 0x03, 0, 1)                                       # setBitVar var 768+0, 1 -> Var[48] bit 0
    a.raw(0x1B, 0x00, 0x03, 7, 1).raw(0x1B, 0x00, 0x03, 15, 1)
    a.say_var(48)
    a.raw(0x31, 140, 0x00, 0x03, 7).say_var(140)                        # getBitVar
    a.raw(0x31, 141, 0x00, 0x03, 8).say_var(141)
    a.raw(0x1B, 0x00, 0x03, 7, 0).say_var(48)                           # borra el bit 7
    a.move(142, 15).raw(0xB1, 143, 0x00, 0x03, 142).say_var(143)        # B1 variable
    a.raw(0x9B, 0xF0, 0x03, 142, 1).say_var(63)                         # bit var 1008+15 -> Var[63]
    a.stop()
    return a.done()


def s_compare():
    a = Asm()
    vals = (0, 1, 0x7FFF, 0x8000, 0xFFFF)
    n = 0
    for op in ('isEqual', 'isNotEqual', 'isGreater', 'isGreaterEqual', 'isLess', 'isLessEqual'):
        for x in vals:
            a.move(150, x)
            for y in vals:
                n += 1
                a.jump(OPS[op], 'L%d' % n, 150, y & 255, (y >> 8) & 255)
                a.say(n & 0x7F)
                a.label('L%d' % n)
    for x in vals:                          # con una variable como segundo operando
        a.move(151, x).move(152, 1)
        a.jump(0xC8, 'Ve%d' % x, 151, 152).say(1).label('Ve%d' % x)
        a.jump(0xF8, 'Vg%d' % x, 151, 152).say(2).label('Vg%d' % x)
    for x in (0, 1, 0xFFFF):
        a.move(153, x)
        a.jump(0x28, 'Z%d' % x, 153).say(3).label('Z%d' % x)
        a.jump(0xA8, 'N%d' % x, 153).say(4).label('N%d' % x)
    a.stop()
    return a.done()


def s_states():
    a = Asm()
    n = 0
    for obj in (1, 182, 193, 438, 779):
        lo, hi = obj & 255, obj >> 8
        for k, (on, off, ifz, ifnz) in enumerate(((0x07, 0x47, 0x4F, 0x0F), (0x27, 0x67, 0x6F, 0x2F),
                                                  (0x57, 0x17, 0x1F, 0x5F), (0x37, 0x77, 0x7F, 0x3F))):
            for op in (on, off, on):
                a.raw(op, lo, hi)
                for iff in (ifz, ifnz):
                    n += 1
                    a.jump(iff, 'S%d' % n, lo, hi).say(n & 0x7F).label('S%d' % n)
    a.move(160, 5).raw(0x87, 160)           # setStateIntrinsicOn con una variable
    a.stop()
    return a.done()


def s_delays():
    a = Asm()
    a.say(1).raw(0x2E, *delay_bytes(0)).say(2).raw(0x2E, *delay_bytes(3)).say(3)
    a.raw(0x2E, *delay_bytes(65540)).say(4)
    a.move(170, 0xFFFF).raw(0x2B, 170).say(5)          # retardo negativo: se reanuda en el fotograma siguiente
    a.move(170, 0x7FFF).raw(0x2B, 170).say(6)
    a.move(170, 300).raw(0x2B, 170).say(7)
    a.stop()
    return a.done()


def s_waits():
    a = Asm()
    a.say(1).raw(0xAE).say(2).raw(0x4C).say(3).stop()  # waitForMessage y waitForSentence
    return a.done()


def s_nest_a():                                  # 187 -> 188 -> 189; 189 mata a 187
    return Asm().raw(0x42, 188).say(1).stop().done()


def s_nest_b():
    return Asm().say(2).raw(0x42, 189).say(3).raw(0x80).say(4).stop().done()


def s_nest_c():
    return Asm().say(5).raw(0x62, 187).say(6).stop().done()


def s_chain_a():                                 # 190 encadena a 191
    return Asm().say(10).raw(0x4A, 191).say(11).stop().done()


def s_chain_b():
    a = Asm().say(12).raw(0x68, 140, 190).say_var(140).raw(0x68, 141, 191).say_var(141)
    return a.raw(0x62, 0).say(13).stop().done()


def s_self():                                    # se arranca a si mismo
    return Asm().say(1).raw(0x42, 192).say(2).raw(0x80).say(3).stop().done()


def s_err_obj():                                 # objeto fuera de rango: error 5
    return Asm().say(1).raw(0x07, 0x0C, 0x03).say(2).stop().done()


def s_err_bit():                                 # variable de bit fuera de rango: error 3
    return Asm().say(1).raw(0x1B, 0x00, 0x10, 0, 1).say(2).stop().done()


def s_err_range():                               # setVarRange con cuenta 0: error 3
    return Asm().say(1).raw(0x26, 60, 0).say(2).stop().done()


def s_err_script():                              # script que no existe: error 4
    return Asm().say(1).raw(0x42, 6).say(2).stop().done()


def s_decode():                                  # decodificadores con subopcodes (van al anfitrion)
    a = Asm()
    a.move(150, 0xFB).raw(0x99, 150).say(1)                      # doSentence con FB en una variable: corta
    a.move(150, 0xFC).raw(0x99, 150).say(2)
    a.raw(0x19, 3, 5, 0, 6, 0, 1).say(3)                         # doSentence largo
    a.move(150, 0x1FB).raw(0x99, 150, 9, 0, 8, 0, 0).say(4)      # 0x1FB no es FB: largo
    a.raw(0x13, 1, 2, 2, 7).say(5)                               # actorOps sub 2 (paleta)
    a.raw(0x13, 1, 2, 3, ord('H'), ord('i'), 0).say(6)           # actorOps sub 3 (nombre)
    a.raw(0x13, 1, 2, 4).say(7)
    a.raw(0x7A, 0, 5).say(8)                                     # verbOps: borrar
    a.raw(0x7A, 0xFF, 3, 1).say(9)                               # verbOps: activar
    a.raw(0x7A, 7, 2, 3, 4, 1, ord('G'), ord('o'), 0).say(10)    # verbOps: nuevo
    a.raw(0x14, 5, ord('H'), ord('i'), 4, 99, 0x85, 3, ord('x'), 0).say(11)    # print con escapes
    a.raw(0xD8, 0x03, 0x04, 0x07, 0x77, ord('!'), 0).say(12)     # printEgo: 3 sin dato, 4 y 7 con un byte
    a.raw(0xCC, 7, 0x81, 0x82, 0).say(13)                        # pseudoRoom
    a.raw(0x54, 5, 0, ord('N'), 0).say(14)                       # setObjectName
    a.raw(0x14, 5, 4, 0, ord('A'), 0).say(17)                    # print: el byte extra de un escape puede ser 0
    a.raw(0x14, 5, 0x85, 0, 0x04, 0x00, 0).say(18)
    a.raw(0x3B, 5).say(15)                                       # waitForActor (anfitrion)
    a.move(152, 7).raw(0xD3, 150, 152, 4).say(16)                # actorOps con variables
    a.stop()
    return a.done()


def s_reuse_parent():                            # 198: el hijo mata al padre y arranca otra copia del padre
    a = Asm()
    a.jump(0xA8, 'first', 190)                   # si Var[190] == 0 -> primera copia
    a.say(20).raw(0x80).say(23).stop()           # segunda copia: cede el control y sigue otro dia
    a.label('first').move(190, 1).raw(0x42, 199).say(21).stop()
    return a.done()


def s_reuse_child():                             # 199
    return Asm().raw(0x62, 198).raw(0x42, 198).say(22).stop().done()


def s_start155():                                # startScript(155) pasa por la correccion de Maniac Mansion
    return Asm().say(1).raw(0x42, 155).say(2).stop().done()


def s_start87():                                 # startScript(87) no arranca si corren el 88 o el 89
    return Asm().raw(0x42, 88).raw(0x42, 89).raw(0x42, 87).say(1).stop().done()


def s_actors():
    """Actores: traje, sala, mostrar y ocultar, animaciones, hablar y cambiar de sala mientras se habla.
    Cada paso cede el control (breakHere) para que el resumen de cada fotograma muestre el estado."""
    a = Asm()

    def step(*bs):
        a.raw(*bs).raw(0x80)
    step(0x13, 5, 7, 4)                          # actorOps: traje 7 para el actor 5
    step(0x13, 5, 1, 1)                          # sonido 0
    step(0x13, 5, 9, 5)                          # color de habla
    step(0x2D, 5, 3)                             # putActorInRoom(5, 3)
    step(0x72, 3)                                # loadRoom(3): el actor 5 se muestra
    step(0x01, 5, 10, 20)                        # putActor
    step(0x11, 5, 0xF4)                          # animateActor: girar (chore 4)
    step(0x11, 5, 0xF9)                          # direccion inmediata (chore 3), dir 90
    step(0x11, 5, 0x28)                          # animacion normal (fotograma 10)
    step(0x11, 5, 224)                           # fotograma 56: se redirige al de inicio
    step(0x11, 5, 0xF4)
    step(0x11, 5, 0xF8)                          # inmediato: borra el giro pendiente
    step(0x11, 5, 0xFC)                          # parar
    step(0x11, 99, 0xFC)                         # actor no valido: no pasa nada
    step(0x14, 5, ord('H'), ord('i'), 0)         # habla el actor 5
    step(0x03, 140, 5)                           # getActorRoom
    a.say_var(140)
    step(0x2D, 5, 9)                             # cambia de sala mientras habla: se calla
    step(0x11, 5, 0xF4)                          # gira (moviendose) y luego se va a la sala 0
    step(0x2D, 5, 0)                             # sala 0
    step(0x03, 141, 5)
    a.say_var(141)
    step(0x03, 142, 77)                          # actor no valido: sala 0
    a.say_var(142)
    step(0x13, 5, 3, 4)                          # cambiar de traje con el actor oculto
    step(0x2D, 5, 3)
    step(0x01, 5, 11, 21)                        # putActor lo muestra (esta en la sala y no se ve)
    step(0x11, 5, 0x28)                          # fotograma 10, para ver como el traje lo reinicia
    step(0x13, 5, 8, 4)                          # con el actor visible: se oculta y se muestra
    step(0x13, 6, 2, 4)                          # otro actor
    step(0x2D, 6, 3)
    step(0x14, 255, ord('o'), ord('k'), 0)       # mensaje del sistema con actores en la sala
    step(0x72, 4)                                # otra sala: se ocultan todos
    a.stop()
    return a.done()


def s_msgs():
    """Mensajes: espera, mantener, salto de linea, variables, cadenas en variables, '@' y descarte."""
    a = Asm()
    a.move(200, 0xFFFF).move(201, 0).move(202, 32767).move(203, 32768).move(204, 12345)
    for v in (200, 201, 202, 203, 204):
        a.raw(0x94, 255, ord('V'), 0x04, v, ord('!'), 0)          # print(255, "V<var>!")
        a.raw(0xAE)                                                # waitForMessage
    a.move(150, ord('H')).move(151, ord('o')).move(152, ord('y')).move(153, 0x40).move(154, ord('!')).move(155, 0)
    a.raw(0x14, 255, 0x07, 150, 0)                                # cadena en variables (la arroba se salta)
    a.raw(0xAE)
    a.raw(0x14, 255, ord('a') | 0x80, ord('b'), 0x40, ord('c'), 0)   # espacio tras 'a', arroba descartada
    a.raw(0xAE)
    a.raw(0x14, 255, ord('A'), 0x01, ord('B'), 0x03, ord('C'), 0x01, ord('D'), 0)   # salto, espera, salto
    a.raw(0xAE)
    a.raw(0x14, 255, ord('K'), ord('e'), 0x02, 0)                 # mantener: no espera
    a.raw(0x14, 255, ord('+'), 0)                                 # se acumula
    a.raw(0xAE)
    a.raw(0x14, 255, ord('K'), 0x02, 0)                           # mantener y luego cambiar de sala
    a.raw(0x72, 5).raw(0x80)                                      # loadRoom(5): stopTalk con keepText
    a.raw(0x14, 255, 0x80, 0)                                     # codigo 0 con espacio
    a.raw(0x14, 255, 0)                                           # mensaje vacio
    a.raw(0x14, 7, ord('x'), 0)                                   # actor 7 fuera de sala: se pierde
    a.raw(0xD8, ord('E'), ord('g'), ord('o'), 0)                  # printEgo
    a.say(1).stop()
    return a.done()


def s_talk_bad():                                # el hablante pasa a ser un actor que no existe: error 3 al callar
    a = Asm()
    a.raw(0x14, 255, ord('T'), 0x03, ord('U'), 0)
    a.move(41, 30)
    a.raw(0xAE).say(1).stop()
    return a.done()


def s_room_script():                             # corre como script de sala y cede el control
    return Asm().say(1).raw(0x80).say(2).raw(0x80).say(3).stop().done()


def s_load_room():                               # un script global cambia de sala
    return Asm().say(1).raw(0x72, 3).say(2).stop().done()


def s_sounds():
    a = Asm()
    a.raw(0x1C, 5).raw(0x02, 6).raw(0x1C, 7).raw(0x3C, 5)             # startSound, startMusic, stopSound
    a.raw(0x7C, 130, 9).say_var(130).raw(0x7C, 131, 0).say_var(131)   # isSoundRunning (y con sonido 0)
    a.raw(0x20)                                                       # stopMusic
    a.move(160, 77).raw(0x9C, 160).raw(0x82, 160).raw(0xBC, 160)       # con variables
    a.raw(0xFC, 132, 160).say_var(132)
    a.stop()
    return a.done()


def s_walk():
    """Caminar con inmediatos: a un punto, a un objeto, hacia otro actor, y los consultores de actor."""
    a = Asm()
    a.raw(0x13, 5, 7, 4).raw(0x2D, 5, 3).raw(0x72, 3).raw(0x01, 5, 8, 60).say(1)
    a.raw(0x1E, 5, 70, 62).raw(0x3B, 5).say(2)                       # walkActorTo + waitForActor
    for op in (0x43, 0x23, 0x56, 0x63, 0x7B, 0x71, 0x06):              # X, Y, moving, facing, walkbox, costume, elevation
        a.raw(op, 130, 5).say_var(130)
    a.raw(0x3D, 5, 250).raw(0x06, 130, 5).say_var(130)                 # setActorElevation / getActorElevation
    a.raw(0x1E, 5, 10, 66).raw(0x3B, 5)
    a.raw(0x36, 5, 71, 0).raw(0x3B, 5)                                 # walkActorToObject
    a.raw(0x09, 5, 126, 0).raw(0x80).raw(0x80).raw(0x80)               # faceActor
    a.raw(0x13, 6, 2, 4).raw(0x2D, 6, 3).raw(0x01, 6, 40, 60).raw(0x80)
    a.raw(0x0D, 5, 6, 3).raw(0x3B, 5)                                  # walkActorToActor
    a.raw(0x0E, 5, 74, 0).raw(0x80)                                    # putActorAtObject
    a.raw(0x1E, 5, 41, 60).raw(0x80).raw(0x1E, 5, 41, 60).raw(0x3B, 5)  # al mismo sitio
    a.raw(0x43, 130, 77).say_var(130).raw(0x23, 130, 77).say_var(130)  # X e Y de un numero que no es actor
    a.raw(0x43, 130, 74).say_var(130).raw(0x23, 130, 74).say_var(130)  # ... de un objeto de la sala
    a.raw(0x43, 130, 200).say_var(130)                                 # ... de un objeto que no esta
    a.raw(0x43, 130, 0).say_var(130)
    a.raw(0x1E, 7, 20, 62).raw(0x80).raw(0x36, 7, 71, 0).raw(0x80)       # actor 7 fuera de la sala: se coloca sin caminar
    a.raw(0x43, 130, 7).say_var(130).raw(0x63, 130, 7).say_var(130)
    a.raw(0x13, 6, 2, 4).raw(0x2D, 6, 3)
    a.raw(0x01, 5, 30, 60).raw(0x80)                                    # faceActor hacia un actor a una distancia de 0, 1, 2 y 3 en x, y arriba y abajo
    for (px, py) in ((30, 60), (31, 60), (32, 60), (33, 60), (29, 60), (28, 60), (30, 58), (30, 62), (30, 59)):
        a.raw(0x01, 6, px, py).raw(0x80).raw(0x09, 5, 6, 0).raw(0x80).raw(0x80).raw(0x80)
        a.raw(0x63, 130, 5).say_var(130)
    a.stop()
    return a.done()


def s_randwalk():
    """Caminata con parametros en variables: sala (V100), salida (V101, V102), tres destinos (V103..V108),
    objeto (V109) y la posicion del segundo actor (V111, V112)."""
    a = Asm()
    a.raw(0x13, 5, 7, 4).raw(0x6D, 5, 100).raw(0xF2, 100).raw(0x13, 6, 2, 4).raw(0x6D, 6, 100)
    a.raw(0x61, 6, 111, 112).raw(0x61, 5, 101, 102).say(1)
    for k in range(3):
        a.raw(0x7E, 5, 103 + 2 * k, 104 + 2 * k).raw(0x3B, 5)
        a.raw(0x43, 130, 5).say_var(130).raw(0x23, 130, 5).say_var(130).raw(0x7B, 130, 5).say_var(130)
    a.raw(0x76, 5, 109).raw(0x3B, 5).raw(0x49, 5, 109).raw(0x80).raw(0x80).raw(0x80)
    a.raw(0x0D, 5, 6, 3).raw(0x3B, 5)
    a.raw(0x4E, 5, 109).raw(0x80).raw(0x63, 130, 5).say_var(130)
    a.raw(0x7E, 6, 103, 104).raw(0x3B, 6).say(2)
    a.stop()
    return a.done()


class SynthObj:
    def __init__(self, oid, walk_x, walk_y, actordir, x, y, width, height, parent, parentstate):
        self.id, self.walk_x, self.walk_y, self.actordir = oid, walk_x, walk_y, actordir
        self.x, self.y, self.width, self.height, self.parent, self.parentstate = x, y, width, height, parent, parentstate


class SynthRoom:
    """Sala inventada para probar las cajas de caminar con banderas que el juego casi no usa (cerradas, invisibles,
    solo para el jugador, trapecios) y una matriz de rutas con huecos. Solo tiene cajas y objetos."""
    encd_off = excd_off = 0
    width = 640

    def __init__(self, number, seed, object_ids):
        import random
        rng = random.Random(seed)
        self.number = number
        n = 3 if number == 63 else rng.randrange(3, 13)
        flags_pool = [0] * 6 + [1, 2, 3, 4, 5, 6, 7, 0x40, 0x60, 0x80, 0xA0, 0x20, 0xC1]
        self.boxes = []
        x = rng.randrange(0, 6)
        for _ in range(n):
            w = rng.randrange(3, 14)
            uy = 50 + rng.randrange(-3, 4)
            ly = uy + rng.randrange(2, 16)
            ulx, urx = x, x + w
            llx = max(0, x + rng.randrange(-8, 9))             # trapecios: aristas inclinadas, a veces mas anchas que altas
            lrx = urx + rng.randrange(-8, 9)
            flags = rng.choice(flags_pool)
            if number == 63:
                flags = [0x80, 0x80, 0xA0][len(self.boxes) % 3]  # sala sin cajas utilizables para casi todos
            self.boxes.append((uy, ly, ulx, urx, llx, lrx, rng.choice([0, 1, 3]), flags))
            x = urx + 1
        m = bytearray(i * n for i in range(n))
        for i in range(n):
            for j in range(n):
                hop = i if j == i else (i + 1 if j > i else i - 1)
                m.append(255 if rng.random() < 0.08 else hop)
        self.matrix = bytes(m)
        self.objects = [SynthObj(oid, rng.randrange(0, 80) * 8, rng.randrange(0, 32) * 8, rng.randrange(0, 8),
                                 rng.randrange(0, 80) * 8, rng.randrange(0, 14) * 8, rng.randrange(1, 8) * 8,
                                 rng.randrange(1, 8) * 8, rng.choice([0, 0, 0, 1, 2, 3, 9]), rng.choice([0, 0, 1]) * 8)
                        for oid in rng.sample(object_ids, 6)]

    def entry_script(self):
        return b''

    def exit_script(self):
        return b''


def synth_rooms(owner):
    """Salas 60..63; los objetos son numeros de objetos del juego que pertenecen a una sala (dueno $0F)."""
    ids = [i for i in range(1, len(owner)) if owner[i] == 0x0F]
    return {n: SynthRoom(n, 900 + n, ids) for n in range(60, 64)}


def s_sentence():
    """doSentence con variables: sala V100; verbo V120, objetos V121 y V122. Apila (subopcode 0), escribe la frase
    (2), ejecuta (1), y prueba $FB y $FC y el desbordamiento de la cola."""
    a = Asm()
    a.raw(0xF2, 100)                                                    # loadRoom(V100)
    a.raw(0xF9, 120, 121, 122, 0).raw(0xF9, 120, 122, 121, 0).raw(0x80)  # dos frases en la cola
    a.raw(0xF9, 120, 121, 122, 2).raw(0x80)                             # escribirla
    a.raw(0xF9, 120, 121, 122, 1).raw(0x80)                             # ejecutarla
    a.raw(0x19, 0xFB).raw(0x80)                                         # reiniciar la frase
    a.raw(0xF9, 120, 121, 122, 0).raw(0x19, 0xFC).raw(0x80)             # vaciar la cola y parar el script de frases
    a.raw(0xF9, 120, 121, 122, 1).raw(0x80)
    a.raw(0xF9, 120, 121, 121, 0).raw(0x80)                             # preposicion con A = B: se descarta
    a.raw(0x59, 254, 121, 0, 0, 1)                                   # verbo 254: stopObjectScript (inmediato en el verbo)
    for _ in range(7):                                                  # mas de 6: desborda la cola
        a.raw(0xF9, 120, 121, 122, 0)
    a.stop()
    return a.done()


def synth_scripts():
    return {
        180: s_indirect(), 181: s_var40(), 182: s_arith(), 183: s_compare(), 184: s_states(), 185: s_delays(),
        186: s_waits(), 187: s_nest_a(), 188: s_nest_b(), 189: s_nest_c(), 190: s_chain_a(), 191: s_chain_b(),
        192: s_self(), 193: s_err_obj(), 194: s_err_bit(), 195: s_err_range(), 196: s_err_script(),
        197: s_decode(), 198: s_reuse_parent(), 199: s_reuse_child(), 200: s_start155(), 201: s_start87(),
        202: s_actors(), 203: s_msgs(), 204: s_room_script(), 205: s_load_room(), 206: s_sounds(), 207: s_talk_bad(),
        208: s_walk(), 209: s_randwalk(), 210: s_sentence(),
    }


def synth_scenarios():
    """(nombre, ordenes): todos empiezan con INIT y una semilla fija de variables."""
    def sc(name, script, pre=(), frames='FRAMES 4 12', more=()):
        return ('synth%03d.%s' % (script, name), ['INIT', *pre, 'SCRIPT %d' % script, frames, *more])
    out = [
        sc('indirect', 180), sc('var40', 181), sc('arith', 182), sc('compare', 183), sc('states', 184),
        sc('delays', 185, frames='FRAMES 15 5000'), sc('delays2', 185, frames='FRAMES 1 40'),
        sc('waits', 186, pre=['SETVAR 3 1'], frames='FRAMES 1 5', more=['SETVAR 3 0', 'FRAMES 1 5']),
        sc('nest', 187), sc('chain', 190), sc('self', 192), sc('err_obj', 193), sc('err_bit', 194),
        sc('err_range', 195), sc('err_script', 196), sc('decode', 197),
        sc('reuse', 198, frames='FRAMES 4 4'),
        ('synth200.a', ['INIT', 'SETVAR 120 1', 'SCRIPT 200', 'FRAMES 4 6']),
        ('synth200.b', ['INIT', 'SETVAR 120 2', 'SCRIPT 200', 'FRAMES 4 6']),
    ]
    import random
    for k in range(12):                          # 88 y 89 en marcha o no, segun las variables
        rng = random.Random(77 + k)
        ln = ['INIT']
        for v in range(256):
            if rng.random() < 0.4:
                ln.append('SETVAR %d %d' % (v, rng.choice([0, 1, 2, 3, 4, 5, 11, 12, 26, 31])))
        out.append(('synth201.k%d' % k, ln + ['SCRIPT 201', 'FRAMES 4 8']))
    out += [
        sc('actors', 202, frames='FRAMES 4 80'), sc('msgs', 203, frames='FRAMES 4 300'),
        sc('sounds', 206, frames='FRAMES 4 3'), sc('talkbad', 207, frames='FRAMES 4 100'), sc('walk', 208, frames='FRAMES 4 500'),
        ('synth204.kill', ['INIT', 'LOADROOM 2', 'ROOMSCRIPT 204', 'FRAMES 4 1', 'SCRIPT 205', 'FRAMES 4 6']),
        ('synth204.alive', ['INIT', 'LOADROOM 3', 'ROOMSCRIPT 204', 'FRAMES 4 6']),
        ('synth185.clamp', ['INIT', 'SCRIPT 185', 'FRAMES 100 700']),
    ]
    # los punteros 14-16 con valores distintos
    for seed in (60, 120, 199):
        out.append(('synth180.ptr%d' % seed, ['INIT', 'SETVAR 14 %d' % seed, 'SETVAR 20 9', 'SCRIPT 180', 'FRAMES 4 3']))
    return out

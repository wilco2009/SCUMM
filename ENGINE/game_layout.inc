; DATOS DEL JUEGO (Maniac Mansion v2): disposicion de la interfaz. Para otro juego se sustituye este fichero y game_data.inc;
; el motor no contiene nada de esto.
INV_ROW0        equ 20                  ; filas 20-21: 4 objetos (2 columnas: 0 y 17) y las flechas (UP, DN) en la columna 15
VERB_ROW0       equ 17
SENT_ROW        equ 16
VERB_COLMUL     equ 13                  ; columna de un verbo = (x del juego * VERB_COLMUL + VERB_COLADD) >> VERB_COLSHIFT (320 -> 256 pixeles: 13/16)
VERB_COLADD     equ 4
VERB_COLSHIFT   equ 4
VERB_ROWSUB     equ 2                   ; fila de un verbo = y del juego - VERB_ROWSUB

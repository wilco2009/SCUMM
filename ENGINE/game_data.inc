; DATOS DEL JUEGO (Maniac Mansion v2): etiquetas cortas de los verbos, preposiciones, tablas de remapeo de trajes y plantilla de los
; ficheros de sala. Para otro juego se sustituye este fichero (y game_layout.inc); el motor solo usa los nombres.
REMAP1:         defb $04,$01,$02,$00,$01,$02,$03,$00,$06,$01,$03,$00,$01,$02,$03,$00
                defb $07,$00,$03,$00,$01,$02,$03,$00,$05,$00,$02,$00,$01,$02,$03,$00
REMAP2:         defb $00,$01,$03,$02,$03,$00,$02,$00,$00,$01,$03,$02,$01,$03,$01,$02
                defb $00,$01,$03,$02,$01,$00,$02,$02,$00,$01,$03,$02,$03,$03,$01,$01
REMAP3:         defb $00,$00,$02,$00,$01,$03,$02,$00,$01,$01,$02,$00,$01,$03,$02,$00
                defb $02,$01,$02,$00,$01,$03,$02,$00,$03,$00,$03,$00,$01,$03,$02,$00
gf_tpl:         defb "/SCUMM/ROOM00.GFX",0
ui_short:       defb 13,"WALK",0, 14,"PICK",0, 15,"WHAT",0, 7,"KID",0, 4,"ON",0, 5,"OFF",0
                defb $FF
us_preps:       defb " in",0," with",0," on",0," to",0

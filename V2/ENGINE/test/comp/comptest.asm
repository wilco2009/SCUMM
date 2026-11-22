; Prueba del compositor (compose.asm) fuera del programa: org $8000, parametros en $7F00 (los pone comptest.cpp)
CP_COST         equ $7F00
CP_EMAP         equ $7F02
CP_LIMB         equ $7F04
CP_MIR          equ $7F06
CP_CAN          equ $7F08
CP_OUT          equ $7F0A
                org $8000
                jp compose
                include "../../compose.asm"
cp_x0:          defw 0
cp_y0:          defw 0
cp_x1:          defw 0
cp_y1:          defw 0
cp_xm:          defw 0
cp_ym:          defw 0
cp_n:           defb 0
cp_i:           defb 0
cp_lp:          defw 0
cp_cw:          defb 0
cp_ch:          defb 0
cp_src:         defw 0
cp_run:         defb 0
cp_col:         defb 0
cp_bt:          defb 0
cp_hc:          defb 0
cp_cp:          defw 0
cp_cl:          defb 0
cp_op2:         defw 0
cp_cx:          defb 0
cp_cy:          defb 0
cp_k8:          defb 0
cp_cnt:         defw 0
cp_c8:          defw 0
cp_rowp:        defw 0
cp_sh:          defs 8
cp_list:        defs 16 * CP_LE

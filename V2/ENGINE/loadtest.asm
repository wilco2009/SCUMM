; loadtest.asm - el nucleo mas el cargador de datos, para comprobar load_data en el arnes de PC
                include "vm.asm"
                include "../../COMMON/mcu.asm"
                include "loader.asm"
ld_trace:       ret
lt_entry:       call load_data
                ret

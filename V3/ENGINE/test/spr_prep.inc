GAME="../../Indy Last Crusade"
Z80SRC="${Z80SRC:-/c/ClaudeCode/Eightyone2/src}"
B=build
SD=$B/sdboot
mkdir -p $SD/DATA
sh ../build_scumm.sh || exit 1
if [ ! -f $B/z80.o ]; then
  gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80.c" -o $B/z80.o || exit 1
  gcc -c -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" "$Z80SRC/z80/z80_ops.c" -o $B/z80_ops.o || exit 1
fi
[ $B/test_scumm.exe -nt test_scumm.cpp ] || g++ -std=gnu++17 -O2 -w -I"$Z80SRC/z80" -I"$Z80SRC" test_scumm.cpp $B/z80.o $B/z80_ops.o -o $B/test_scumm.exe || exit 1
[ $SD/DATA/DATA.BIN -nt ../../TOOLS/pack_data3.py ] && [ $SD/DATA/DATA.BIN -nt ../../preview_hr/cost/COST001.bin ] || python -I ../../TOOLS/pack_data3.py "$GAME" $SD/DATA/DATA.BIN --game ../../games/indy3.cfg --costumes ../../preview_hr --sounds ../../preview_hr/snd > /dev/null || exit 1
[ -f $SD/DATA/ROOM01.GFX ] || cp ../../preview_hr/gfx/*.GFX $SD/DATA/
cp prog/ovlb.bin $SD/DATA/OVLB.BIN; cp prog/ovlc.bin $SD/DATA/OVLC.BIN; cp prog/ovld.bin $SD/DATA/OVLD.BIN

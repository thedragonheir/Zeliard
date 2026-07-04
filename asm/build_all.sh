#!/bin/bash

# Make sure your dosbox-x.conf has the following, for max compilation speed:
# [cpu]
# core=dynamic
# cycles=max
# cputype=auto

cat << 'EOF' > build.bat
path D:\;%PATH%
tasm /m9 zeliard.asm >log.txt
link zeliard.obj, zeliard.exe /CPARMAXALLOC:513; >>log.txt
tasm /m9 mscadlib.asm >>log.txt
tlink mscadlib.obj >>log.txt
tasm /m9 sndadlib.asm >>log.txt
tlink sndadlib.obj >>log.txt
tasm /m9 stick.asm >>log.txt
tlink stick.obj >>log.txt
tasm /m9 game.asm >>log.txt
tlink game.obj >>log.txt
tasm /m9 mole.asm >>log.txt
tlink mole.obj >>log.txt
tasm /m9 gmmcga.asm >>log.txt
tlink gmmcga.obj >>log.txt
tasm /m9 gdmcga.asm >>log.txt
tlink gdmcga.obj >>log.txt
tasm /m9 gtmcga.asm >>log.txt
tlink gtmcga.obj >>log.txt
tasm /m9 gfmcga.asm >>log.txt
tlink gfmcga.obj >>log.txt
tasm /m9 ympd.asm >>log.txt
tlink ympd.obj >>log.txt
tasm /m9 ckpd.asm >>log.txt
tlink ckpd.obj >>log.txt
tasm /m9 opdemo.asm >>log.txt
tlink opdemo.obj >>log.txt
tasm /m9 town.asm >>log.txt
tlink town.obj >>log.txt
tasm /m9 rokademo.asm >>log.txt
tlink rokademo.obj >>log.txt
tasm /m9 kingpro.asm >>log.txt
tlink kingpro.obj >>log.txt
tasm /m9 kenjpro.asm >>log.txt
tlink kenjpro.obj >>log.txt
tasm /m9 armrpro.asm >>log.txt
tlink armrpro.obj >>log.txt
tasm /m9 drugpro.asm >>log.txt
tlink drugpro.obj >>log.txt
tasm /m9 bankpro.asm >>log.txt
tlink bankpro.obj >>log.txt
tasm /m9 churpro.asm >>log.txt
tlink churpro.obj >>log.txt
tasm /m9 innapro.asm >>log.txt
tlink innapro.obj >>log.txt
tasm /m9 fight.asm >>log.txt
tlink fight.obj >>log.txt
tasm /m9 select.asm >>log.txt
tlink select.obj >>log.txt
tasm /m9 eai1.asm >>log.txt
tlink eai1.obj >>log.txt
tasm /m9 crab.asm >>log.txt
tlink crab.obj >>log.txt
exit
EOF

rm *.bin

dosbox-x -c "mount c ." \
         -c "mount d ~/Projects/asm/TOOLS" \
         -c "c:" \
         -c "build.bat"

python3 exe2bin.py MSCADLIB.EXE mscadlib.drv 0x100
python3 exe2bin.py SNDADLIB.EXE sndadlib.drv 0x1100
python3 exe2bin.py STICK.EXE stick.bin 0x100
python3 exe2bin.py GAME.EXE game.bin 0xA000
python3 exe2bin.py MOLE.EXE mole.bin 0
python3 exe2bin.py GMMCGA.EXE gmmcga.bin 0x2000
python3 exe2bin.py GDMCGA.EXE gdmcga.bin 0x3000
python3 exe2bin.py GTMCGA.EXE gtmcga.bin 0x3000
python3 exe2bin.py GFMCGA.EXE gfmcga.bin 0x3000
python3 exe2bin.py YMPD.EXE ympd.bin 0x3300
python3 exe2bin.py CKPD.EXE ckpd.bin 0x3300
python3 exe2bin.py OPDEMO.EXE opdemo.bin 0x6000
python3 exe2bin.py TOWN.EXE town.bin 0x6000
python3 exe2bin.py ROKADEMO.EXE rokademo.bin 0xA000
python3 exe2bin.py KINGPRO.EXE kingpro.bin 0xA000
python3 exe2bin.py KENJPRO.EXE kenjpro.bin 0xA000
python3 exe2bin.py ARMRPRO.EXE armrpro.bin 0xA000
python3 exe2bin.py DRUGPRO.EXE drugpro.bin 0xA000
python3 exe2bin.py BANKPRO.EXE bankpro.bin 0xA000
python3 exe2bin.py CHURPRO.EXE churpro.bin 0xA000
python3 exe2bin.py INNAPRO.EXE innapro.bin 0xA000
python3 exe2bin.py FIGHT.EXE fight.bin 0x6000
python3 exe2bin.py SELECT.EXE select.bin 0xA000
python3 exe2bin.py EAI1.EXE eai1.bin 0xA000
python3 exe2bin.py CRAB.EXE crab.bin 0xA000

echo "ZELIARD.EXE diffs:" >diff.txt
{ cmp -l ../game/zeliard.exe ZELIARD.EXE | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "mscadlib.drv diffs:" >>diff.txt
{ cmp -l ../game/mscadlib.drv mscadlib.drv | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "sndadlib.drv diffs:" >>diff.txt
{ cmp -l ../game/sndadlib.drv sndadlib.drv | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "stick.bin diffs:" >>diff.txt
{ cmp -l ../game/stick.bin stick.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "game.bin diffs:" >>diff.txt
{ cmp -l ../game/game.bin game.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "mole.bin diffs:" >>diff.txt
{ cmp -l ../game/0/mole.bin mole.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "gmmcga.bin diffs:" >>diff.txt
{ cmp -l ../game/gmmcga.bin gmmcga.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "gdmcga.bin diffs:" >>diff.txt
{ cmp -l ../game/0/gdmcga.bin gdmcga.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "gtmcga.bin diffs:" >>diff.txt
{ cmp -l ../game/0/gtmcga.bin gtmcga.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "gfmcga.bin diffs:" >>diff.txt
{ cmp -l ../game/0/gfmcga.bin gfmcga.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "ympd.bin diffs:" >>diff.txt
{ cmp -l ../game/0/ympd.bin ympd.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "ckpd.bin diffs:" >>diff.txt
{ cmp -l ../game/0/ckpd.bin ckpd.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "opdemo.bin diffs:" >>diff.txt
{ cmp -l ../game/0/opdemo.bin opdemo.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "town.bin diffs:" >>diff.txt
{ cmp -l ../game/0/town.bin town.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "rokademo.bin diffs:" >>diff.txt
{ cmp -l ../game/0/rokademo.bin rokademo.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "kingpro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/kingpro.bin kingpro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "kenjpro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/kenjpro.bin kenjpro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "armrpro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/armrpro.bin armrpro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "drugpro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/drugpro.bin drugpro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "bankpro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/bankpro.bin bankpro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "churpro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/churpro.bin churpro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "innapro.bin diffs:" >>diff.txt
{ cmp -l ../game/0/innapro.bin innapro.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "fight.bin diffs:" >>diff.txt
{ cmp -l ../game/0/fight.bin fight.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "select.bin diffs:" >>diff.txt
{ cmp -l ../game/0/select.bin select.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "eai1.bin diffs:" >>diff.txt
{ cmp -l ../game/0/eai1.bin eai1.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
echo "crab.bin diffs:" >>diff.txt
{ cmp -l ../game/0/crab.bin crab.bin | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
rm *.EXE *.MAP *.OBJ build.bat

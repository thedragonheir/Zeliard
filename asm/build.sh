#!/bin/bash

# Make sure your dosbox-x.conf has the following, for max compilation speed:
# [cpu]
# core=dynamic
# cycles=max
# cputype=auto

cat << 'EOF' > build.bat
path D:\;%PATH%
tasm /m9 ckpd.asm >log.txt
tlink /t/x ckpd.obj >>log.txt
rem exit
EOF

dosbox-x -conf test.conf -c "mount c ." \
         -c "mount d ~/Projects/asm/TOOLS" \
         -c "c:" \
         -c "build.bat"

#python3 exe2bin.py MSCADLIB.EXE mscadlib.drv 0x100
#python3 exe2bin.py SNDADLIB.EXE sndadlib.drv 0x1100

#echo "mscadlib.drv diffs:" >diff.txt
#{ cmp -l ../game/mscadlib.drv mscadlib.drv | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1
#echo "sndadlib.drv diffs:" >>diff.txt
#{ cmp -l ../game/sndadlib.drv sndadlib.drv | gawk '{printf "0x%08X: %02X %02X\n", $1-1, strtonum(0$2), strtonum(0$3)}'; } >>diff.txt 2>&1

rm *.OBJ build.bat

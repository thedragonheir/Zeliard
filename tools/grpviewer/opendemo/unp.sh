#!/bin/bash
# Unpack all *.grp in current directory

for f in *.grp; do
    python3 unpack.py "$f"
done

#!/usr/bin/env python3
"""Determine correct writeReg argument order for pyopl."""
import pyopl, array

def test_order(reg_first):
    opl = pyopl.opl(44100, 2, 1)
    if reg_first:
        writer = lambda r, v: opl.writeReg(r, v)
    else:
        writer = lambda r, v: opl.writeReg(v, r)

    # OPL initialisation (wave‑select enable)
    writer(0x01, 0x20)
    writer(0xBD, 0x00)

    # Simple sine‑like instrument on channel 0
    writer(0x20, 0x01)      # op1 multiplier = 1
    writer(0x23, 0x01)      # op2 multiplier = 1
    writer(0x40, 0x00)      # op1 total level = 0 (max volume)
    writer(0x43, 0x00)      # op2 total level = 0
    writer(0x60, 0xF0)      # op1 attack=15 decay=0
    writer(0x63, 0xF0)      # op2 attack=15 decay=0
    writer(0x80, 0x0F)      # op1 sustain=0 release=15
    writer(0x83, 0x0F)      # op2 sustain=0 release=15
    writer(0xC0, 0x00)      # feedback=0, connection=0

    # Play A4 (440 Hz) – F‑number 0x156, block 4
    writer(0xA0, 0x56)      # freq low
    writer(0xB0, 0x31)      # block=4, fnum hi=1, key‑on

    # Collect 1 second of audio (44100 samples) in 512‑sample chunks
    full = bytearray()
    for _ in range(44100 // 512):
        buf = bytearray(1024)      # 512 samples × 2 bytes
        opl.getSamples(buf)
        full.extend(buf)
    samples = array.array('h', full)
    max_val = max(max(samples), -min(samples))
    return max_val

print("Testing writeReg(reg, val) ...", end=" ")
v1 = test_order(True)
print(f"max = {v1}")
print("Testing writeReg(val, reg) ...", end=" ")
v2 = test_order(False)
print(f"max = {v2}")

if v1 > 0 and v2 == 0:
    print("Correct order: writeReg(reg, val)")
elif v2 > 0 and v1 == 0:
    print("Correct order: writeReg(val, reg)")
else:
    print("Both orders gave same result – manual check needed.")
    
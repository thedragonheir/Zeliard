#!/usr/bin/env python3
"""Diagnose pyopl API"""
import pyopl

print(f"pyopl version: {pyopl.__version__ if hasattr(pyopl, '__version__') else 'unknown'}")
print(f"opl class: {pyopl.opl}")

# Create instance
try:
    opl = pyopl.opl(44100, 2, 1)
except Exception as e:
    print(f"Error creating opl: {e}")
    exit()

# Check methods
print("\nPublic methods:")
for m in dir(opl):
    if not m.startswith('_'):
        print(f"  {m}")

# Find a write-like method
write_m = None
for name in ['writeReg', 'writereg', 'write', 'write_register']:
    if hasattr(opl, name):
        write_m = getattr(opl, name)
        print(f"\nFound write method: {name}")
        break
if write_m is None:
    print("No write method found!")
    exit()

# Try calling with (reg, val) and (val, reg) - just catch errors
print("\nTrying write with (0x20, 0x01)...")
try:
    write_m(0x20, 0x01)
    print("  OK")
except Exception as e:
    print(f"  Error: {e}")
print("Trying write with (0x01, 0x20)...")
try:
    write_m(0x01, 0x20)
    print("  OK")
except Exception as e:
    print(f"  Error: {e}")

# Sample methods
sample_m = None
for name in ['getsamples', 'generate', 'getSamples']:
    if hasattr(opl, name):
        sample_m = getattr(opl, name)
        print(f"\nFound sample method: {name}")
        break
if sample_m is None:
    print("No sample method!")
    exit()

# Check signature
import inspect
try:
    sig = inspect.signature(sample_m)
    print(f"Signature: {sig}")
except:
    print("Signature not available (built-in)")

# Try calling with different arguments
print("\n--- Test sample(int) ---")
try:
    result = sample_m(100)
    print(f"Type: {type(result)}, len: {len(result) if hasattr(result, '__len__') else 'N/A'}")
    if isinstance(result, (bytes, bytearray)):
        print(f"First 10 bytes: {result[:10].hex()}")
except Exception as e:
    print(f"Error: {e}")

print("\n--- Test sample(bytearray) ---")
buf = bytearray(100 * 2)   # 16-bit mono
try:
    ret = sample_m(buf)
    print(f"Return value: {ret} (type {type(ret)})")
    print(f"First 10 bytes of buf: {buf[:10].hex()}")
except Exception as e:
    print(f"Error: {e}")

# Now actually try to play a tone using the first working write combo
print("\n--- Attempting to generate tone with write(reg, val) then write(val, reg) ---")
def test_tone(writer, sampler_uses_int, desc):
    opl2 = pyopl.opl(44100, 2, 1)
    # clear channels
    for ch in range(9):
        writer(0xA0 + ch, 0)
        writer(0xB0 + ch, 0)
    writer(0x01, 0x20)   # enable wave select
    writer(0xBD, 0x00)
    # setup channel 0
    writer(0x20, 0x01)
    writer(0x23, 0x01)
    writer(0x40, 0x00)
    writer(0x43, 0x00)
    writer(0x60, 0xF0)
    writer(0x63, 0xF0)
    writer(0x80, 0x0F)
    writer(0x83, 0x0F)
    writer(0xC0, 0x00)
    fnum = 0x156
    writer(0xA0, fnum & 0xFF)
    writer(0xB0, ((fnum >> 8) & 3) | (4 << 2) | 0x20)

    if sampler_uses_int:
        raw = sample_m(44100)
    else:
        buf2 = bytearray(44100 * 2)
        sample_m(buf2)
        raw = bytes(buf2)
    samp = array.array('h', raw) if raw else array.array('h', [])
    maxv = max(max(samp), -min(samp)) if samp else 0
    print(f"Max amplitude ({desc}): {maxv}")
    return maxv > 0

import array

# Write order combos
for write_style in ["reg,val", "val,reg"]:
    writer = lambda reg, val: write_m(reg, val) if write_style == "reg,val" else write_m(val, reg)
    for use_int in (True, False):
        desc = f"write({write_style}), sample({'int' if use_int else 'buf'})"
        try:
            if test_tone(writer, use_int, desc):
                print(f"SUCCESS with {desc}")
        except Exception as e:
            print(f"Failed with {desc}: {e}")

print("\nDiagnostic complete.")

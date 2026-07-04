#!/usr/bin/env python3
import os

def unpack(src: bytes, length_limit: int) -> bytes:
    """Decompression logic identical to GrpViewer."""
    if not src: return b""
    si = 0
    out = bytearray()
    dx = len(src)
    
    def lodsb(): nonlocal si; b = src[si]; si += 1; return b
    def lodsw(): nonlocal si; lo = src[si]; hi = src[si+1]; si += 2; return lo | (hi << 8)
    def stosb_rep(b, count): out.extend([b] * count)

    method = lodsb() & 0x07
    dx -= 1

    if method == 0:
        out.extend(src[si:si+dx])
    elif method == 1:
        bp = si
        while lodsb() != 0xFF: si += 1
        dx = len(src) - si
        while dx > 0:
            al = lodsb(); dx -= 1; ah = al & 0xF0; cx = 1; tbp = bp
            while True:
                entry_key = src[tbp]
                if (entry_key & 0x0F) != 0: break
                if ah == entry_key: cx = (al & 0x0F) + 2; al = src[tbp + 1]; break
                tbp += 2
            stosb_rep(al, cx)
    elif method == 2:
        marker = lodsb(); dx -= 1; ah = marker
        while dx > 0:
            al = lodsb(); dx -= 1; cx = 1
            if (al & 0xF0) == ah: cx = (al & 0x0F) + 3; al = lodsb(); dx -= 1
            stosb_rep(al, cx)
    elif method == 3:
        bp = si
        while lodsb() != 0xFF: si += 1
        dx = len(src) - si
        while dx > 0:
            al = lodsb(); dx -= 1; ah = al & 0x0F; cx = 1; tbp = bp
            while True:
                entry_key = src[tbp]
                if (entry_key & 0xF0) != 0: break
                if ah == entry_key: cx = (al >> 4) + 2; al = src[tbp + 1]; break
                tbp += 2
            stosb_rep(al, cx)
    elif method == 4:
        marker = lodsb(); dx -= 1; ah = marker
        while dx > 0:
            al = lodsb(); dx -= 1; cx = 1
            if (al & 0x0F) == ah: cx = (al >> 4) + 3; al = lodsb(); dx -= 1
            stosb_rep(al, cx)
    elif method == 5:
        while dx > 0:
            al = lodsb(); cx = 1
            if si < len(src) and src[si] == al:
                cx = src[si + 1] + 2; si += 2; dx -= 2
            stosb_rep(al, cx); dx -= 1
    elif method == 6:
        bp = si
        while lodsw() != 0xFFFF: pass
        dx = len(src) - si
        while dx > 0:
            al = lodsb(); dx -= 1; cx = 1; tbp = bp
            while True:
                tl = src[tbp]; th = src[tbp+1]
                if tl == 0xFF and th == 0xFF: break
                if tl == al: dx -= 1; cx = lodsb() + 2; al = th; break
                tbp += 2
            stosb_rep(al, cx)
    elif method == 7:
        ah = lodsb(); dx -= 1
        while dx > 0:
            al = lodsb(); cx = 1
            if al == ah: al = lodsb(); cx = lodsb() + 3; dx -= 2
            stosb_rep(al, cx); dx -= 1
            
    return bytes(out)

def process_sword_grp(filename="sword.grp"):
    if not os.path.exists(filename):
        print(f"Error: {filename} not found.")
        return

    # 1. Load and handle the Zeliard file header
    with open(filename, "rb") as f:
        raw = f.read()

    if raw[0] == 0:
        raw_data = raw[1:]
        length = len(raw) - 1
    else:
        skip = int.from_bytes(raw[1:3], "little")
        length = int.from_bytes(raw[3:5], "little")
        raw_data = raw[5 + skip:]

    # 2. Unpack the data
    unpacked = unpack(raw_data, length)
    print(f"Unpacked size: {len(unpacked)} bytes")

    # 3. Read the primary mega-group header (3 offsets, 2 bytes each)
    offsets = []
    for i in range(3):
        off = int.from_bytes(unpacked[i*2 : (i+1)*2], "little")
        offsets.append(off)
    
    print(f"Mega-group offsets: {offsets}")

    # 4. Save the mega-groups as separate binaries
    # Boundaries are: [off0:off1], [off1:off2], [off2:end]
    boundaries = offsets + [len(unpacked)]
    
    for i in range(3):
        start = boundaries[i]
        end = boundaries[i+1]
        chunk = unpacked[start:end]
        
        out_name = f"sword_mega_{i}.bin"
        with open(out_name, "wb") as f_out:
            f_out.write(chunk)
        print(f"Saved {out_name} ({len(chunk)} bytes)")

if __name__ == "__main__":
    process_sword_grp()

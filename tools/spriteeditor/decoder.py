"""
Zeliard MDT Viewer - MDT file decoders.

Dungeon MDT runtime memory layout (load address = 0xC000):
  +0x00  descriptor ptr
  +0x02  map width (WORD)
  +0x04  vertical platforms ptr     (3 bytes/entry, stop=FFFF)
  +0x06  collapsing platforms ptr   (3 bytes/entry, stop=FFFF)
  +0x08  horizontal platforms ptr   (7 bytes/entry, stop=FFFF)
  +0x0A  doors ptr                  (12 bytes/entry, stop=FFFF)
  +0x0C  accomplished items ptr     (stop=FFFF)
  +0x0E  cavern name renderer ptr
  +0x10  monsters ptr               (16 bytes/entry, stop=FFFF)
  +0x12  cavern level (BYTE)
  +0x13  tear X  (WORD — door-to-boss X tile coordinate)
  +0x15  tear Y  (BYTE)
  +0x17  signs ptr
  +0x19  packed_map_end ptr
  +0x1B  packed map data  ← RLE tile grid starts here (column-major)

Town MDT runtime memory layout (load address = 0xC000):
  +0x00  descriptor ptr
  +0x02  map width (WORD); height is always 8 tiles
  +0x04  offset to town name rendering info; skip 3 bytes, then pascal string
  +0x09  offset to town doors array (3 bytes/entry, stop=FFFF)
  +0x0D  offset to NPC texts pointer array
  +0x0F  offset to NPC array (8 bytes/entry, stop=FFFF)
  +0x17  unpacked map data  — map_width * 8 bytes, column-major
"""

import os
import struct
from typing import Tuple, Dict, List, Optional
from tkinter import messagebox

from .constants import MDT_LOAD_ADDR, DUNG_HEIGHT, TOWN_HEIGHT, is_town_mdt
from .models import (
    MdtData, TownMdtData, Door, TownDoor, Monster, Item, NPC
)

def unpack(src: bytes, length_limit: int) -> bytes:
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

def rol16(word, count=1):
    word &= 0xFFFF
    carry = 0
    for _ in range(count):
        carry = (word >> 15) & 1
        word = ((word << 1) | carry) & 0xFFFF
    return word, carry

def decode_4(p1, p2, p3):
    pxs = []
    for _ in range(4):
        ax = 0
        p3, cf = rol16(p3); ax = (ax << 1) | cf
        p2, cf = rol16(p2); ax = (ax << 1) | cf
        p1, cf = rol16(p1); ax = (ax << 1) | cf
        p3, cf = rol16(p3); ax = (ax << 1) | cf
        p2, cf = rol16(p2); ax = (ax << 1) | cf
        p1, cf = rol16(p1); ax = (ax << 1) | cf
        pxs.append(ax & 0x3F)
    return p1, p2, p3, pxs

def _parse_doors(data: bytes, doors_ptr: int, n: int) -> List[Door]:
    """Parse dungeon door entries (12 bytes each, 0xFFFF-terminated)."""
    doors = []
    off = _ptr_off_safe(doors_ptr, n)
    if off is None:
        return doors
    idx = 1
    while off + 2 <= n:
        if data[off] == 0xFF and data[off + 1] == 0xFF:
            break
        if off + 12 > n:
            break
        doors.append(Door.from_bytes(data, off, f'D{idx}'))
        idx += 1
        off += 12
    return doors


def _parse_town_doors(data: bytes, doors_ptr: int, n: int) -> List[TownDoor]:
    """Parse town door entries (3 bytes each, 0xFFFF-terminated)."""
    doors = []
    off = _ptr_off_safe(doors_ptr, n)
    if off is None:
        return doors
    idx = 1
    while off + 2 <= n:
        if data[off] == 0xFF and data[off + 1] == 0xFF:
            break
        if off + 3 > n:
            break
        doors.append(TownDoor.from_bytes(data, off, f'D{idx}'))
        idx += 1
        off += 3
    return doors


def _parse_monsters(data: bytes, monsters_ptr: int, n: int) -> Tuple[List[Monster], List[Item]]:
    """Parse monster/item entries (16 bytes each, 0xFFFF-terminated)."""
    monsters = []
    items = []
    off = _ptr_off_safe(monsters_ptr, n)
    if off is None:
        return monsters, items

    mid = iid = 1
    while off + 2 <= n:
        if data[off] == 0xFF and data[off + 1] == 0xFF:
            break
        if off + 16 > n:
            break

        stype = data[off + 14]
        if stype == 0:  # spawn type 0 = item
            items.append(Item.from_bytes(data, off, f'I{iid}'))
            iid += 1
        else:  # spawn type != 0 = monster
            monsters.append(Monster.from_bytes(data, off, f'M{mid}'))
            mid += 1
        off += 16
    return monsters, items


def _parse_town_npcs(data: bytes, npc_ptr: int, n: int) -> List[NPC]:
    """Parse town NPC entries (8 bytes each, 0xFFFF-terminated)."""
    npcs = []
    off = _ptr_off_safe(npc_ptr, n)
    if off is None:
        return npcs
    idx = 1
    while off + 2 <= n:
        if data[off] == 0xFF and data[off + 1] == 0xFF:
            break
        if off + 8 > n:
            break
        npcs.append(NPC.from_bytes(data, off, f'N{idx}'))
        idx += 1
        off += 8
    return npcs


def _parse_npc_texts(data: bytes, npc_texts_ptr: int, n: int) -> Dict[int, str]:
    """
    Read the NPC texts pointer array at npc_texts_ptr.

    The array holds one 2-byte LE runtime pointer per NPC id (0-based).
    The array has no explicit terminator — we stop when a pointer resolves
    outside the file. Each pointer points to a 0xFF-terminated string.
    Returns dict {npc_id (int): text (str)}.
    """
    texts: Dict[int, str] = {}
    base = _ptr_off_safe(npc_texts_ptr, n)
    if base is None:
        return texts

    idx = 0
    off = base
    while off + 2 <= n:
        ptr = struct.unpack_from('<H', data, off)[0]
        str_off = _ptr_off_safe(ptr, n)
        if str_off is None:
            break  # pointer out of range — end of array

        # Read 0xFF-terminated string
        end = str_off
        while end < n and data[end] != 0xFF:
            end += 1
        texts[idx] = data[str_off:end].decode('ascii', errors='replace')
        idx += 1
        off += 2
    return texts

def decode_patterns(unpacked_data):
    HEADER_SIZE = 256
    TILE_SIZE = 48
    # Modes for each tile are stored in the header after the first 6 bytes
    indices = unpacked_data[6:HEADER_SIZE]
    tile_bank = unpacked_data[HEADER_SIZE:]
    
    tiles = []
    total_tiles = len(tile_bank) // TILE_SIZE
    
    for idx in range(min(total_tiles, len(indices))):
        func_mode = indices[idx]
        if func_mode > 4: func_mode = 0 # Safety clamp per assembly
        
        tile_data = tile_bank[idx * TILE_SIZE : (idx + 1) * TILE_SIZE]
        pixels = [0] * 64 # 8x8 flat array
        
        for ry in range(8):
            row_bytes = tile_data[ry * 6 : (ry + 1) * 6]
            # lodsw + xchg logic results in Big Endian words
            w0 = (row_bytes[0] << 8) | row_bytes[1]
            w1 = (row_bytes[2] << 8) | row_bytes[3]
            w2 = (row_bytes[4] << 8) | row_bytes[5]
            
            p_r, p_g, p_b, p_mask = 0, 0, 0, 0
            
            # Map words to planes based on the function mode
            if func_mode == 0:   p_r, p_g, p_b, p_mask = w0, w1, w2, 0x0000 
            elif func_mode == 1: p_r, p_g, p_b, p_mask = w0, w1, 0, w2
            elif func_mode == 2: p_r, p_g, p_b, p_mask = w0, 0, w2, w1
            elif func_mode == 3: p_r, p_g, p_b, p_mask = 0, w1, w2, w0
            elif func_mode == 4: p_r, p_g, p_b, p_mask = w0, w1, w2, 0xFFFF

            # Decode pixels (must pass state p1, p2, p3 to the second call!)
            p1, p2, p3, px1 = decode_4(p_r, p_g, p_b)
            _,  _,  _,  px2 = decode_4(p1, p2, p3) # Continues with shifted bits
            row_pixels = px1 + px2
            
            for rx in range(8):
                # Check bit-mask for visibility (2 bits per pixel in p_mask)
                if func_mode == 0:
                    visible = True
                elif func_mode == 4:
                    visible = True
                else:
                    # Logic: "visible" if the 2-bit selector is 11b (0x03)
                    sel = (p_mask >> (14 - rx * 2)) & 0x03
                    visible = not (sel == 0x03)
                
                # Assign -1 to represent transparency for the viewer
                if visible:
                    pixels[ry * 8 + rx] = row_pixels[rx]
                else:
                    pixels[ry * 8 + rx] = -1 
        
        tiles.append(pixels)
    return tiles


# Add this decoding logic (adapted from grp_viewer.py)
def decode_pat_grp(filepath):
    """Decodes a .grp file of type 7 (8x8 tiles)."""
    if not os.path.exists(filepath):
        return None
        
    try:
        raw = open(filepath, "rb").read()
    except Exception as e:
        messagebox.showerror('Load Error', str(e))
        return

    # Simple Zeliard Header Handling
    if raw[0] == 0:
        skip, length, raw1 = 0, len(raw)-1, raw[1:]
    else:
        skip = int.from_bytes(raw[1:3], "little")
        length = int.from_bytes(raw[3:5], "little")
        raw1 = raw[5+skip:]

    unpacked = unpack(raw1, length)
    tiles = decode_patterns(unpacked)
    
    return tiles

def _parse_descriptor(data: bytes, desc_ptr: int, n: int):
    off = _ptr_off_safe(desc_ptr, n)
    if off is None or off + 4 >= n:
        return None

    t = data[off + 4]

    if t == 0x00:
        return decode_pat_grp("cpat.grp")
    elif t == 0x01:
        return decode_pat_grp("mpat.grp")
    elif t == 0x02:
        return decode_pat_grp("dpat.grp")
    else:
        return None

def _ptr_off_safe(ptr: int, file_size: int) -> Optional[int]:
    """Safe wrapper for pointer to offset conversion."""
    if ptr == 0 or ptr == 0xFFFF:
        return None
    if ptr >= MDT_LOAD_ADDR:
        off = ptr - MDT_LOAD_ADDR
    else:
        off = ptr
    return off if off < file_size else None


def _decode_tile_grid(data: bytes, start_offset: int, map_width: int,
                      map_height: int, packed: bool = True) -> List[List[int]]:
    """Decode tile grid from MDT data."""
    n = len(data)
    grid = [[0] * map_width for _ in range(map_height)]

    if not packed:
        # Unpacked tiles (town maps) — column-major
        for col in range(map_width):
            col_off = start_offset + col * map_height
            if col_off + map_height > n:
                break
            for row in range(map_height):
                grid[row][col] = data[col_off + row]
        return grid

    # Packed RLE tiles (dungeon maps) — column-major 2-bit opcode RLE
    si = start_offset
    for col in range(map_width):
        row = 0
        dl = 0
        guard = 0
        while dl < 0x40:
            guard += 1
            if guard > 0xFFFF or si >= n:
                break
            b = data[si]
            op = (b >> 6) & 3

            if op == 0:  # 00: long run
                rep = b + 1
                si += 1
                if si >= n:
                    break
                tile = data[si]
            elif op == 1:  # 01: packed nibbles
                rep = ((b >> 4) & 3) + 2
                tile = (b & 0x0F) + 1
            elif op == 2:  # 10: empty run (tile 0)
                rep = b & 0x3F
                tile = 0
                if rep == 0:
                    si += 1
                    continue
            else:  # 11: single tile
                tile = b & 0x3F
                rep = 1

            si += 1
            dl += rep
            for _ in range(rep):
                if row < map_height:
                    grid[row][col] = tile
                    row += 1

    return grid, si  # type: ignore


def decode_dung_mdt(data: bytes) -> MdtData:
    """
    Decode a Zeliard dungeon/outdoor MDT file.

    Returns MdtData with parsed grid, doors, monsters, items, and header info.
    """
    n = len(data)
    if n < 0x1D:
        raise ValueError(f'File too small: {n} bytes (need >= 29)')

    def word(o: int) -> int:
        return struct.unpack_from('<H', data, o)[0]

    def byte(o: int) -> int:
        return data[o] if o < n else 0

    mw = word(0x02)
    if not 1 <= mw <= 4096:
        raise ValueError(f'Invalid map width: {mw}')

    # Decode tile grid
    grid, consumed_si = _decode_tile_grid(data, 0x1B, mw, DUNG_HEIGHT, packed=True)

    return MdtData(
        map_width=mw,
        map_height=DUNG_HEIGHT,
        grid=grid,
        desc_ptr=word(0x00),
        vplat_ptr=word(0x04),
        cplat_ptr=word(0x06),
        hplat_ptr=word(0x08),
        doors_ptr=word(0x0A),
        achv_ptr=word(0x0C),
        name_ptr=word(0x0E),
        monsters_ptr=word(0x10),
        level=byte(0x12),
        tear_x=word(0x13) if n > 0x14 else 0,
        tear_y=byte(0x15),
        signs_ptr=word(0x17) if n > 0x18 else 0,
        map_end_ptr=word(0x19) if n > 0x1A else 0,
        consumed_si=consumed_si,
        doors=_parse_doors(data, word(0x0A), n),
        monsters=_parse_monsters(data, word(0x10), n)[0],
        items=_parse_monsters(data, word(0x10), n)[1],
    )


def decode_town_mdt(data: bytes) -> TownMdtData:
    """
    Decode a Zeliard town MDT file.

    Town memory layout (all offsets relative to file start / load address 0xC000):
      +0x00  descriptor ptr
      +0x02  map width WORD (little endian); height is fixed at 8
      +0x04  ptr to town name info: skip 3 bytes, then pascal string (1-byte length)
      +0x09  ptr to doors array (3 bytes/entry, 0xFFFF-terminated)
      +0x0F  ptr to NPC array (8 bytes/entry, 0xFFFF-terminated)
      +0x17  unpacked map — map_width * 8 bytes, column-major
    """
    n = len(data)
    if n < 0x17 + 8:
        raise ValueError(f'File too small for a town MDT: {n} bytes')

    def word(o: int) -> int:
        return struct.unpack_from('<H', data, o)[0]

    def byte(o: int) -> int:
        return data[o] if o < n else 0

    mw = word(0x02)
    if not 1 <= mw <= 4096:
        raise ValueError(f'Invalid town map width: {mw}')

    # Town name (pascal string at name_ptr + 3)
    name_ptr = word(0x04)
    town_name = ''
    name_off = _ptr_off_safe(name_ptr, n)
    if name_off is not None:
        str_off = name_off + 3  # skip 3 bytes before pascal string
        if str_off < n:
            slen = byte(str_off)
            raw = data[str_off + 1: str_off + 1 + slen]
            town_name = raw.decode('ascii', errors='replace')

    # Pointers
    doors_ptr = word(0x09)
    npc_texts_ptr = word(0x0D)
    npc_ptr = word(0x0F)

    # Parse entities
    town_doors = _parse_town_doors(data, doors_ptr, n)
    npc_texts = _parse_npc_texts(data, npc_texts_ptr, n)
    npcs = _parse_town_npcs(data, npc_ptr, n)

    # Decode tile grid (unpacked, column-major)
    grid = _decode_tile_grid(data, 0x17, mw, TOWN_HEIGHT, packed=False)
    desc_ptr = word(0x00)
    gfx = _parse_descriptor(data, word(0x00), n)

    return TownMdtData(
        map_width=mw,
        map_height=TOWN_HEIGHT,
        grid=grid,  # type: ignore
        town_name=town_name,
        name_ptr=name_ptr,
        doors_ptr=doors_ptr,
        npc_texts_ptr=npc_texts_ptr,
        npc_ptr=npc_ptr,
        town_doors=town_doors,
        npcs=npcs,
        npc_texts=npc_texts,
        desc_ptr=desc_ptr,
        gfx=gfx,
    )


def decode_mdt_file(filepath: str) -> MdtData:
    """
    Decode an MDT file, auto-detecting town vs dungeon format.

    Returns MdtData suitable for the viewer (town data is converted).
    """
    with open(filepath, 'rb') as f:
        data = f.read()

    if is_town_mdt(filepath):
        town_data = decode_town_mdt(data)
        return town_data.to_mdt_data()
    else:
        return decode_dung_mdt(data)

#!/usr/bin/env python3
import sys
import os
import copy
import tkinter as tk
from tkinter import filedialog, ttk

# ---------------------------------------------------------------------------
# Configuration & Data
# ---------------------------------------------------------------------------
import json
import re

def _load_json_with_comments(path):
    text = open(path, encoding="utf-8").read()
    text = re.sub(r'//[^\n]*', '', text)
    return json.loads(text)

_DATA = _load_json_with_comments("DATA.json")
_PALETTE = _load_json_with_comments("PALETTE.json")

GRP_DESCRIPTOR = _DATA["descriptors"]
# Fix magic.grp: JSON stores int keys as strings
for _desc in GRP_DESCRIPTOR:
    if len(_desc) > 2 and isinstance(_desc[2], dict):
        _fixed = {}
        for _k, _v in _desc[2].items():
            try:
                _fixed[int(_k)] = _v
            except ValueError:
                _fixed[_k] = _v
        _desc[2] = _fixed

MODE_CFG = {
    0: {"w": 20, "h": 18, "stride": 15, "bytes": 270, "type": "sprite"},
    1: {"w": 16, "h": 16, "stride": 12, "bytes": 192, "type": "sprite"},
    2: {"w": 8,  "h": 8,  "stride": 1,  "bytes": 8,   "type": "font"},
    3: {"w": 16, "h": 16, "stride": 8,  "bytes": 192, "type": "sprite"},
    4: {"w": 32, "h": 32, "stride": 0,  "bytes": 0,   "type": "sword"},
    5: {"w": 16, "h": 24, "stride": 0,  "bytes": 0,   "type": "npc"},
    6: {"w": 16, "h": 24, "stride": 0,  "bytes": 0,   "type": "npc"},
    7: {"w": 8,  "h": 8,  "stride": 6,  "bytes": 48,  "type": "pattern"},
    8: {"w": 16, "h": 8,  "stride": 4,  "bytes": 32,  "type": "fman"},
    9: {"w": 8,  "h": 8,  "stride": 6,  "bytes": 48,  "type": "roka"},
    10:{"w": 8,  "h": 8,  "stride": 6,  "bytes": 48,  "type": "dchr"},
    11:{"w": 16, "h": 8,  "stride": 4,  "bytes": 32,  "type": "enp"},
    12:{"w": 16, "h": 8,  "stride": 4,  "bytes": 32,  "type": "crab"},
    13:{"w": 16, "h": 8,  "stride": 4,  "bytes": 32,  "type": "dman"},
    14:{"w": 8,  "h": 8,  "stride": 4,  "bytes": 32,  "type": "ttl"},
    15:{"w": 8,  "h": 8,  "stride": 0,  "bytes": 0,   "type": "store"},
    16:{"w": 88, "h": 56, "stride": 0,  "bytes": 0,   "type": "ympd"},
    17:{"w": 16, "h": 24, "stride": 0,  "bytes": 0,   "type": "npc"},
}

SCALE = 4
CANVAS_BG = "#0f0f1a"
FG_COLOR = "#e0e0ff"
BG_COLOR = "#1a1a2e"

SWORD_COLORS = _PALETTE["sword_colors"]
HERO_INDICES = _DATA["hero_indices"]
ROKA_MAP = _PALETTE["roka_map"]

FRAMES_REGISTRY = _DATA["frames"]
ENP1_FRAMES = FRAMES_REGISTRY.get("enp1", {})
ENP2_FRAMES = FRAMES_REGISTRY.get("enp2", {})
ENP3_FRAMES = FRAMES_REGISTRY.get("enp3", {})
ENP4_FRAMES = FRAMES_REGISTRY.get("enp4", {})
ENP5_FRAMES = FRAMES_REGISTRY.get("enp5", {})
ENP6_FRAMES = FRAMES_REGISTRY.get("enp6", {})
ENP7_FRAMES = FRAMES_REGISTRY.get("enp7", {})
ENP8_FRAMES = FRAMES_REGISTRY.get("enp8", {})
CRAB_FRAMES = FRAMES_REGISTRY.get("crab", {})
DMAN_FRAMES = FRAMES_REGISTRY.get("dman", {})

PAL_DECODE_TABLES = [bytes(t) for t in _PALETTE["decode_tables"]]
PAL_DECODE_TABLES.append(PAL_DECODE_TABLES[3])

# ---------------------------------------------------------------------------
# Decompression logic
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Rendering Engines
# ---------------------------------------------------------------------------

PALETTE_STRS = _PALETTE["main_64"]

# ---------------------------------------------------------------------------
# Pixel decoding primitives
# ---------------------------------------------------------------------------

def rol16(word, count=1):
    """Rotate a 16-bit word left by `count` bits; return (new_word, last_carry)."""
    word &= 0xFFFF
    carry = 0
    for _ in range(count):
        carry = (word >> 15) & 1
        word = ((word << 1) | carry) & 0xFFFF
    return word, carry

def decode_4(p1, p2, p3):
    """Decode 4 pixels from three 16-bit plane words via rotating shifts.
    Returns updated (p1, p2, p3, [4 palette indices])."""
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

def decode_8(p1, p2, p3):
    """Decode 8 pixels from three 16-bit plane words (two consecutive decode_4 calls)."""
    p1, p2, p3, px1 = decode_4(p1, p2, p3)
    _,   _,   _,  px2 = decode_4(p1, p2, p3)
    return px1 + px2

def read_be_words(row_bytes, count=3):
    """Read `count` big-endian 16-bit words from row_bytes.
    Matches lodsw (little-endian load) + xchg ah,al (byte-swap) = big-endian word."""
    return [(row_bytes[i*2] << 8) | row_bytes[i*2 + 1] for i in range(count)]

_tile_counter = [0]

def draw_pixel(canvas, x, y, color_str, scale=None, tags=None):
    if scale is None:
        scale = SCALE
    if color_str == "-1":
        if not getattr(canvas, '_show_labels', False):
            return
        blink_tags = ("_blink_",)
        if tags:
            blink_tags = ("_blink_",) + tuple(tags) if isinstance(tags, (list, tuple)) else ("_blink_", tags)
        canvas.create_rectangle(x, y, x + scale, y + scale, fill="#00ff00", outline="", tags=blink_tags)
        if not getattr(canvas, '_blink_after_id', None):
            canvas._blink_visible = True
            canvas._blink_after_id = canvas.after(300, _blink_tick, canvas)
        return
    kwargs = {"fill": color_str, "outline": ""}
    if tags:
        kwargs["tags"] = tags
    canvas.create_rectangle(x, y, x + scale, y + scale, **kwargs)

def _blink_tick(canvas):
    try:
        visible = getattr(canvas, '_blink_visible', True)
        canvas._blink_visible = not visible
        canvas.itemconfigure("_blink_", state='normal' if visible else 'hidden')
        canvas._blink_after_id = canvas.after(300, _blink_tick, canvas)
    except tk.TclError:
        canvas._blink_after_id = None

def next_tile_tag():
    _tile_counter[0] += 1
    return f"tile_{_tile_counter[0]}"

def draw_tile_grouped(canvas, pixels, x0, y0, tile_w=8, scale=None, transparent_idx=None,
                      tile_idx=None, show_label=False, palette=None):
    if palette is None:
        palette = PALETTE_STRS
    if scale is None:
        scale = SCALE
    tag = next_tile_tag()
    tags = ("draggable", tag)
    if pixels is not None:
        for i, p_idx in enumerate(pixels):
            if p_idx is None or p_idx == transparent_idx:
                continue
            rx, ry = i % tile_w, i // tile_w
            draw_pixel(canvas, x0 + rx * scale, y0 + ry * scale, palette[p_idx], scale, tags=tags)
    if show_label and tile_idx is not None:
        font_size = max(7, int(scale * 2.5))
        label_h = font_size + 4
        label_w = max(16, len(str(tile_idx)) * (font_size - 1))
        canvas.create_rectangle(x0 + 1, y0 + 1, x0 + label_w, y0 + label_h,
                                fill="#111122", outline="", stipple="gray50",
                                tags=("tile_label", tag))
        canvas.create_text(x0 + 2, y0 + 2, text=str(tile_idx), anchor="nw",
                          fill="white", font=("Courier", font_size),
                          tags=("tile_label", tag))
    if not hasattr(canvas, '_frame_origins'):
        canvas._frame_origins = {}
    canvas._frame_origins[tag] = (x0, y0)
    return tag


# ---------------------------------------------------------------------------
# Sword rendering
# ---------------------------------------------------------------------------

def decode_sword_8x8(data, color_pair):
    """Decode a single 8x8 tile using 2-bit-per-pixel logic.
    Returns list of 64 palette indices (or None for transparent)."""
    c_high, c_low = color_pair
    pixels = []
    for row_idx in range(8):
        # Read 16-bit word, swap bytes (lodsw + xchg ah,al logic)
        word = (data[row_idx*2] << 8) | data[row_idx*2 + 1]
        for i in range(8):
            selector = (word >> ((7 - i) * 2)) & 0x03
            if selector == 0:
                pixels.append(None)     # Transparent
            elif selector == 3:
                pixels.append(c_high)
            else:
                pixels.append(c_low)
    return pixels

def render_sword_group(data, mega_idx, canvas, y_offset):
    """Render a sword mega-group including color variations and macro-tiles."""
    # Parse Mega-Group Header (15 LE Offsets = 30 bytes)
    header = [int.from_bytes(data[i*2:i*2+2], 'little') for i in range(15)]
    tile_bank = data[header[0]:]

    # Extract Macro-Tile Definitions (22 definitions, 16 bytes each)
    # Definitions start immediately after the 30-byte header (offset 0x1E)
    macro_defs = [data[0x1E + i*16 : 0x1E + (i+1)*16] for i in range(22)]

    current_y = y_offset
    scale = 3
    subgroups = [(0,6), (6,10), (10,11), (11,17), (17,21), (21,22)]
    show = getattr(canvas, '_show_labels', False)

    for c_pair in SWORD_COLORS[mega_idx]:
        x_cursor = 10
        for start, end in subgroups:
            for m_def in macro_defs[start:end]:
                for col in range(4):
                    for row in range(4):
                        t_idx = m_def[col * 4 + row]
                        if t_idx == 0xFF: continue
                        pixels = decode_sword_8x8(tile_bank[t_idx*16 : (t_idx+1)*16], c_pair)
                        tag = next_tile_tag()
                        tags = ("draggable", tag)
                        for i, p_idx in enumerate(pixels):
                            if p_idx is None: continue
                            rx, ry = i % 8, i // 8
                            draw_pixel(canvas,
                                       x_cursor + (col*8 + rx) * scale,
                                       current_y + (row*8 + ry) * scale,
                                       PALETTE_STRS[p_idx], scale, tags=tags)
                        if show:
                            font_size = max(7, int(scale * 2.5))
                            canvas.create_text(
                                x_cursor + col*8*scale + 2,
                                current_y + row*8*scale + 2,
                                text=f"0x{t_idx:02X}", anchor="nw",
                                fill="white", font=("Courier", font_size),
                                tags=("draggable", "tile_label", tag))
                        if not hasattr(canvas, '_frame_origins'):
                            canvas._frame_origins = {}
                        canvas._frame_origins[tag] = (
                            x_cursor + col*8*scale, current_y + row*8*scale)
                x_cursor += 32 * scale + 2
            x_cursor += 8
        current_y += 32 * scale + 16

    return current_y - y_offset

# ---------------------------------------------------------------------------
# NPC / Hero rendering
# ---------------------------------------------------------------------------

def decode_npc_tile(tile_data):
    """Decode one 8x8 NPC tile from 48 raw bytes (8 rows x 6 bytes).

    The game's apply_sprite_mask reads each row as 3 little-endian words
    (R, G, B planes), then:
      1. Masks out pure-white pixels: plane &= ~(B&G&R)  [so all-ones -> 0]
      2. Byte-swaps each plane word before storing to plane_buffer
      3. Derives blit_mask_bitplane = ~(B|G|R) after byte-swapping B|G|R
      4. Calls build_48_bits_packed_from_rgb_planes  -> 6 packed color bytes
      5. Calls extract_blit_byte_from_mask_plane     -> 1 mask byte
         mask bit = 1 (draw) when both bits of the 2-bit pixel slot in the
         16-bit mask word are 1, which happens iff the decoded palette
         index for that pixel is non-zero.

    Returns list of 64 entries (row-major): palette index (int) or None.
    """
    pixels = []
    for ry in range(8):
        p1, p2, p3 = read_be_words(tile_data[ry*6 : ry*6+6])
        # White-pixel masking: plane &= ~(B&G&R)
        white = p1 & p2 & p3
        p1 &= ~white & 0xFFFF
        p2 &= ~white & 0xFFFF
        p3 &= ~white & 0xFFFF
        pixels.extend(decode_8(p1, p2, p3))
    # Mask: draw only when index != 0
    return [idx if idx != 0 else None for idx in pixels]

def decode_npc_tile_nomask(tile_data):
    """Same as decode_npc_tile but without white-pixel masking.
    Used for mode 17 tiles (church, drug) where valid purple/magenta colours
    (e.g. index 7 = #7c007c, index 63 = #f800f8) would be incorrectly zeroed.
    """
    pixels = []
    for ry in range(8):
        p1, p2, p3 = read_be_words(tile_data[ry*6 : ry*6+6])
        pixels.extend(decode_8(p1, p2, p3))
    return [idx if idx != 0 else None for idx in pixels]

def render_grouped_tiles(data, canvas, y_offset, is_hero=False, overrides=None, row_major=False,
                         palette=None, decoder=decode_npc_tile):
    """Render tiles from planar data in grouped layouts (NPC sprites, hero, or tile_indices).

    For mman/cman: bytes 0-255 are a tile-index table (40 NPCs x 6 indices),
                   byte 256+ are 48-byte tile definitions.
    For tman: no index table; HERO_INDICES provides the tile layout.
    overrides dict may contain "tile_indices" list to replace HERO_INDICES.
    """
    if palette is None:
        palette = PALETTE_STRS
    INDEX_TABLE_SIZE = 0 if is_hero else 256
    NPC_COUNT        = 10 if is_hero else 40
    TILE_SIZE        = 48   # 48 raw bytes per tile
    TILES_PER_NPC    = 6    # 2 columns x 3 rows

    tile_bank      = data[INDEX_TABLE_SIZE:]
    if is_hero and isinstance(overrides, dict) and "tile_indices" in overrides:
        indices_source = overrides["tile_indices"]
    else:
        indices_source = HERO_INDICES if is_hero else data
    npc_per_row    = 5 if is_hero else 8
    GAP_X          = 16 * SCALE + 24
    GAP_Y          = 24 * SCALE + 16

    if row_major:
        TILES_PER_ROW = 7
        show = getattr(canvas, '_show_labels', False)
        y_pos = y_offset
        row_count = 0
        max_x = 0
        if isinstance(indices_source, dict):
            items = []
            for key, val in indices_source.items():
                items.append(key)
                if isinstance(val, (list, tuple)):
                    if val and isinstance(val[0], (list, tuple)) and val[0] and isinstance(val[0][0], (list, tuple)):
                        items.append(val)
                    else:
                        for row in val:
                            items.append(row)
                else:
                    items.append(val)
        else:
            items = indices_source

        def _render_row(row):
            nonlocal y_pos, row_count, max_x
            for ci, t_idx in enumerate(row):
                if not isinstance(t_idx, (int, float)):
                    continue
                t_idx = int(t_idx)
                if t_idx < 0:
                    x = 10 + ci * 8 * SCALE
                    max_x = max(max_x, x + 8 * SCALE)
                    draw_tile_grouped(canvas, None,
                                      x, y_pos,
                                      tile_idx=-1, show_label=show)
                    continue
                if not is_hero:
                    t_idx -= 1
                tile_offset = t_idx * TILE_SIZE
                if tile_offset + TILE_SIZE > len(tile_bank):
                    continue
                x = 10 + ci * 8 * SCALE
                max_x = max(max_x, x + 8 * SCALE)
                pixels = decoder(tile_bank[tile_offset : tile_offset + TILE_SIZE])
                draw_tile_grouped(canvas, pixels,
                                  x, y_pos,
                                  tile_idx=t_idx, show_label=show, palette=palette)
            y_pos += 8 * SCALE
            row_count += 1

        first_section = True
        for item in items:
            if isinstance(item, str):
                if not first_section:
                    y_pos += 18
                first_section = False
                text_y = y_pos
                y_pos += 14
                canvas.create_text(10, text_y, text=item, anchor="nw",
                                   fill="#ffcc44", font=("Courier", 10, "bold"),
                                   tags=("section_title", "draggable",))
                row_count += 1
            elif isinstance(item, (list, tuple)):
                # 3D: item is a list of frames, each frame is a list of rows
                if item and isinstance(item[0], (list, tuple)):
                    max_rows = max(len(frame) for frame in item)
                    max_cols = max(len(row) for frame in item for row in frame)
                    frame_w = max_cols * 8 * SCALE
                    frame_gap = 4 * SCALE
                    prev_tiles = {}
                    for fi, frame in enumerate(item):
                        for ri, row in enumerate(frame):
                            for ci, t_idx in enumerate(row):
                                if not isinstance(t_idx, (int, float)):
                                    continue
                                t_idx = int(t_idx)
                                if t_idx == 0:
                                    prev_tiles.pop((ri, ci), None)
                                    continue
                                was_neg = t_idx < 0
                                if was_neg:
                                    t_idx = prev_tiles.get((ri, ci), -1)
                                if t_idx < 0:
                                    x = 10 + fi * (frame_w + frame_gap) + ci * 8 * SCALE
                                    max_x = max(max_x, x + 8 * SCALE)
                                    draw_tile_grouped(canvas, None,
                                                      x, y_pos + ri * 8 * SCALE,
                                                      tile_idx=-1, show_label=show)
                                    continue
                                if not was_neg:
                                    prev_tiles[(ri, ci)] = t_idx
                                display_idx = -1 if was_neg else t_idx
                                if not is_hero:
                                    t_idx -= 1
                                tile_offset = t_idx * TILE_SIZE
                                if tile_offset + TILE_SIZE > len(tile_bank):
                                    continue
                                x = 10 + fi * (frame_w + frame_gap) + ci * 8 * SCALE
                                max_x = max(max_x, x + 8 * SCALE)
                                pixels = decoder(tile_bank[tile_offset : tile_offset + TILE_SIZE])
                                draw_tile_grouped(canvas, pixels,
                                                  x, y_pos + ri * 8 * SCALE,
                                                  tile_idx=display_idx, show_label=show, palette=palette)
                    y_pos += max_rows * 8 * SCALE
                    row_count += max_rows
                # 2D: item is a row (list of ints)
                else:
                    _render_row(item)
            elif isinstance(item, (int, float)):
                t_idx = int(item)
                if t_idx < 0:
                    x = 10 + row_count % TILES_PER_ROW * 8 * SCALE
                    max_x = max(max_x, x + 8 * SCALE)
                    draw_tile_grouped(canvas, None,
                                      x, y_offset + row_count // TILES_PER_ROW * 8 * SCALE,
                                      tile_idx=-1, show_label=show)
                    row_count += 1
                    continue
                if not is_hero:
                    t_idx -= 1
                tile_offset = t_idx * TILE_SIZE
                if tile_offset + TILE_SIZE > len(tile_bank):
                    continue
                x = 10 + row_count % TILES_PER_ROW * 8 * SCALE
                max_x = max(max_x, x + 8 * SCALE)
                pixels = decoder(tile_bank[tile_offset : tile_offset + TILE_SIZE])
                draw_tile_grouped(canvas, pixels,
                                  x, y_offset + row_count // TILES_PER_ROW * 8 * SCALE,
                                  tile_idx=t_idx, show_label=show, palette=palette)
                row_count += 1
        canvas.tag_raise("section_title")
        return max(row_count, 0) * 8 * SCALE + 20, max_x + 20

    # original NPC sprite rendering (mode 5, 6)
    for npc_idx in range(NPC_COUNT):
        base    = npc_idx * TILES_PER_NPC
        indices = indices_source[base : base + TILES_PER_NPC]
        x0 = 10 + (npc_idx % npc_per_row) * GAP_X
        y0 = y_offset + (npc_idx // npc_per_row) * GAP_Y
        for col in range(2):
            for row in range(3):
                t_idx = indices[col * 3 + row]
                if not is_hero:
                    t_idx -= 1
                tile_offset = t_idx * TILE_SIZE
                if tile_offset < 0 or tile_offset + TILE_SIZE > len(tile_bank):
                    continue
                pixels = decode_npc_tile(tile_bank[tile_offset : tile_offset + TILE_SIZE])
                show = getattr(canvas, '_show_labels', False)
                draw_tile_grouped(canvas, pixels, x0 + col*8*SCALE, y0 + row*8*SCALE,
                                  tile_idx=t_idx, show_label=show)
    num_rows = (NPC_COUNT + npc_per_row - 1) // npc_per_row
    return num_rows * GAP_Y



# ---------------------------------------------------------------------------
# Sprite / Font rendering (modes 0, 1, 3)
# ---------------------------------------------------------------------------

def decode_sprite_row(mode, row_bytes):
    """Decode one row of pixels for sprite modes 0, 1, and 3.

    All modes share the same decode_8() kernel; they differ only in how
    the 3 plane words are assembled from the raw stride bytes.

    Mode 0 (20px wide): two full 16-bit triplets + one 8-bit stub → 8+8+4 = 20px
    Mode 1 (16px wide): two full 16-bit triplets                   → 8+8    = 16px
    Mode 3 (16px wide): three consecutive BE words from 6 bytes    → 8+8    = 8px per call
                        (caller loops over 4 sub-tiles of 8 rows each)
    """
    if mode == 3:
        # Called once per 6-byte row of a single 8x8 sub-tile
        p1, p2, p3 = read_be_words(row_bytes)
        return decode_8(p1, p2, p3)

    if mode == 0:  # stride=15, 20px wide
        p1a, p2a, p3a = (row_bytes[0]<<8)|row_bytes[1],  (row_bytes[9]<<8)|row_bytes[8],  (row_bytes[10]<<8)|row_bytes[11]
        p1b, p2b, p3b = (row_bytes[2]<<8)|row_bytes[3],  (row_bytes[7]<<8)|row_bytes[6],  (row_bytes[12]<<8)|row_bytes[13]
        p1c, p2c, p3c = row_bytes[4]<<8,                 row_bytes[5]<<8,                 row_bytes[14]<<8
        return decode_8(p1a, p2a, p3a) + decode_8(p1b, p2b, p3b) + decode_4(p1c, p2c, p3c)[3]

    # mode == 1, stride=12, 16px wide
    p1a, p2a, p3a = (row_bytes[0]<<8)|row_bytes[1],  (row_bytes[7]<<8)|row_bytes[6],  (row_bytes[8]<<8)|row_bytes[9]
    p1b, p2b, p3b = (row_bytes[2]<<8)|row_bytes[3],  (row_bytes[5]<<8)|row_bytes[4],  (row_bytes[10]<<8)|row_bytes[11]
    return decode_8(p1a, p2a, p3a) + decode_8(p1b, p2b, p3b)

def render_sprite_group(data, mode, canvas, y_offset):
    cfg = MODE_CFG[mode]
    num_tiles = len(data) // cfg['bytes']
    if num_tiles == 0: return 0

    ti_per_row = 16
    num_rows = (num_tiles + ti_per_row - 1) // ti_per_row
    pad, gap = 4, 16
    show = getattr(canvas, '_show_labels', False)

    for idx in range(num_tiles):
        x0 = (idx % ti_per_row) * (cfg['w'] * SCALE + gap)
        y0 = y_offset + (idx // ti_per_row) * (cfg['h'] * SCALE + pad)
        tile_data = data[idx * cfg['bytes'] : (idx+1) * cfg['bytes']]

        if mode == 3:
            for sub_idx in range(4):
                quad_x, quad_y = (sub_idx % 2) * 8, (sub_idx // 2) * 8
                chunk = tile_data[sub_idx * 48 : (sub_idx+1) * 48]
                tag = next_tile_tag()
                tags = ("draggable", tag)
                for ry in range(8):
                    pixels = decode_sprite_row(3, chunk[ry*6 : (ry+1)*6])
                    for rx, p_idx in enumerate(pixels):
                        draw_pixel(canvas, x0 + (quad_x + rx) * SCALE,
                                   y0 + (quad_y + ry) * SCALE,
                                   PALETTE_STRS[p_idx], tags=tags)
                sub_tile_idx = idx * 4 + sub_idx
                if show:
                    font_size = max(7, int(SCALE * 2.5))
                    canvas.create_text(x0 + quad_x * SCALE + 2, y0 + quad_y * SCALE + 2,
                                      text=str(sub_tile_idx), anchor="nw",
                                      fill="white", font=("Courier", font_size),
                                      tags=("draggable", "tile_label", tag))
                if not hasattr(canvas, '_frame_origins'):
                    canvas._frame_origins = {}
                canvas._frame_origins[tag] = (x0 + quad_x * SCALE, y0 + quad_y * SCALE)
        else:
            all_pixels = []
            for ry in range(cfg['h']):
                all_pixels.extend(decode_sprite_row(mode, tile_data[ry*cfg['stride'] : (ry+1)*cfg['stride']]))
            tag = next_tile_tag()
            tags = ("draggable", tag)
            for i, p_idx in enumerate(all_pixels):
                rx, ry = i % cfg['w'], i // cfg['w']
                draw_pixel(canvas, x0 + rx * SCALE, y0 + ry * SCALE, PALETTE_STRS[p_idx], tags=tags)
            if show:
                font_size = max(7, int(SCALE * 2.5))
                canvas.create_text(x0 + 2, y0 + 2, text=str(idx), anchor="nw",
                                  fill="white", font=("Courier", font_size),
                                  tags=("draggable", "tile_label", tag))
            if not hasattr(canvas, '_frame_origins'):
                canvas._frame_origins = {}
            canvas._frame_origins[tag] = (x0, y0)

    return num_rows * (cfg['h'] * SCALE + pad)

def render_font_group(data, mode, canvas, y_offset):
    cfg = MODE_CFG[mode]
    num_tiles = len(data) // cfg['bytes']
    ti_per_row = 16
    num_rows = (num_tiles + ti_per_row - 1) // ti_per_row

    for idx in range(num_tiles):
        x0 = (idx % ti_per_row) * (8 * SCALE + 2)
        y0 = y_offset + (idx // ti_per_row) * (8 * SCALE + 2)
        tile_bytes = data[idx * 8 : (idx+1) * 8]
        tag = next_tile_tag()
        tags = ("draggable", tag)
        for ry, b in enumerate(tile_bytes):
            for rx in range(8):
                color = FG_COLOR if (b >> (7 - rx)) & 1 else BG_COLOR
                draw_pixel(canvas, x0 + rx * SCALE, y0 + ry * SCALE, color, tags=tags)
        show = getattr(canvas, '_show_labels', False)
        if show:
            font_size = max(7, int(SCALE * 2.5))
            canvas.create_text(x0 + 2, y0 + 2, text=str(idx), anchor="nw",
                              fill="white", font=("Courier", font_size),
                              tags=("draggable", "tile_label", tag))
        if not hasattr(canvas, '_frame_origins'):
            canvas._frame_origins = {}
        canvas._frame_origins[tag] = (x0, y0)

    return num_rows * (8 * SCALE + 2)

# ---------------------------------------------------------------------------
# Pattern rendering (mpat / dpat / cpat)
# ---------------------------------------------------------------------------

# Maps func_mode index to (p_r_src, p_g_src, p_b_src, p_mask_src)
# using symbolic slots: 'w0', 'w1', 'w2', or constants 0 / 0xFFFF
_PAT_PLANE_MAP = {
    0: ('w0', 'w1', 'w2', 0x0000),  # sprite_plane_decompressor_0
    1: ('w0', 'w1', 0,    'w2'  ),  # sprite_plane_decompressor_b
    2: ('w0', 0,    'w2', 'w1'  ),  # sprite_plane_decompressor_g
    3: (0,    'w1', 'w2', 'w0'  ),  # sprite_plane_decompressor_r
    4: ('w0', 'w1', 'w2', 0xFFFF),  # build_48_bytes_packed_tile
}

def render_pat_group(data, canvas, y_offset):
    """Implements decompress_patterns logic from assembly.
    - Bytes 0-5: Metadata/Pointers (ignored)
    - Bytes 6-255: Function indices (0-4) for each tile
    - Byte 256 onward: 48-byte tile data blocks
    """
    HEADER_SIZE = 256
    TILE_SIZE   = 48
    indices     = data[6:HEADER_SIZE]
    tile_bank   = data[HEADER_SIZE:]
    ti_per_row  = 16
    gap         = 8
    total_tiles = len(tile_bank) // TILE_SIZE

    show = getattr(canvas, '_show_labels', False)

    for idx in range(min(total_tiles, len(indices))):
        func_mode = min(indices[idx], 4)
        x0 = 10 + (idx % ti_per_row) * (8 * SCALE + gap)
        y0 = y_offset + (idx // ti_per_row) * (8 * SCALE + gap)

        tile_data = tile_bank[idx * TILE_SIZE : (idx+1) * TILE_SIZE]
        pr_slot, pg_slot, pb_slot, mask_slot = _PAT_PLANE_MAP[func_mode]
        tag = next_tile_tag()
        tags = ("draggable", tag)

        for ry in range(8):
            w0, w1, w2 = read_be_words(tile_data[ry*6 : (ry+1)*6])
            resolve = lambda s: (w0 if s=='w0' else w1 if s=='w1' else w2 if s=='w2' else s)
            p_r    = resolve(pr_slot)
            p_g    = resolve(pg_slot)
            p_b    = resolve(pb_slot)
            p_mask = resolve(mask_slot)
            pixels = decode_8(p_r, p_g, p_b)

            for rx in range(8):
                if func_mode in (0, 4):
                    visible = True
                else:
                    sel = (p_mask >> (14 - rx * 2)) & 0x03
                    visible = sel != 0x03
                color = PALETTE_STRS[pixels[rx]] if visible else "#00007d"
                draw_pixel(canvas, x0 + rx*SCALE, y0 + ry*SCALE, color, tags=tags)

        if show:
            font_size = max(7, int(SCALE * 2.5))
            canvas.create_text(x0 + 2, y0 + 2, text=str(idx), anchor="nw",
                              fill="white", font=("Courier", font_size),
                              tags=("draggable", "tile_label", tag))
        if not hasattr(canvas, '_frame_origins'):
            canvas._frame_origins = {}
        canvas._frame_origins[tag] = (x0, y0)

    return ((total_tiles // ti_per_row) + 1) * (8 * SCALE + gap)

# ---------------------------------------------------------------------------
# Fman rendering (fman.grp hero dungeon sprites)
# ---------------------------------------------------------------------------

def decode_fman_tile(t_data, lut):
    """Decode one 8x8 fman tile from 32 bytes (8 rows x 4 bytes, interleaved nibbles).
    see Decompress_Tile_Data in assembly.
    """
    pixels = []
    for ry in range(8):
        p0 = (t_data[ry*4]   << 8) | t_data[ry*4 + 1]
        p1 = (t_data[ry*4+2] << 8) | t_data[ry*4 + 3]
        combined = p0 | p1
        row_mask = ~(combined | (combined >> 1) | (combined << 2)) & 0xFFFF
        for rx in range(8):
            s1, s2 = 15 - rx*2, 14 - rx*2
            nib = (((p1>>s1)&1) << 3) | (((p0>>s1)&1) << 2) | (((p1>>s2)&1) << 1) | ((p0>>s2)&1)
            is_trans = (row_mask >> s2) & 3 == 3
            pixels.append(None if is_trans else lut[nib])
    return pixels

def render_fman_group(data, canvas, y_offset, frame_counts=None):
    """Decode fman.grp using frame counts in each group to determine group slices."""
    if not frame_counts:
        # Default fallback if no list is provided
        frame_counts = [len(data) // 9] # single group of len/9 frames

    # 1. Calculate slices and total header size
    fman_groups = []
    current_idx = 0
    for count in frame_counts:
        byte_count = count * 9  # Each frame is a 3x3 (9 bytes in the header) grid
        fman_groups.append(data[current_idx : current_idx + byte_count])
        current_idx += byte_count
    
    header_size = current_idx  # Where the tile definitions begin
    TILE_SIZE   = 32  
    scale       = SCALE

    # 2. Pre-decode all 8x8 tiles from the bank
    tiles_raw = data[header_size:] + b'\x00\x00\x00'
    lut = PAL_DECODE_TABLES[0]
    decoded_tiles = [
        decode_fman_tile(tiles_raw[t*TILE_SIZE : (t+1)*TILE_SIZE], lut)
        for t in range(len(tiles_raw) // TILE_SIZE)
    ]

    # 3. Render the groups
    current_y  = y_offset
    gap        = 12
    sprite_px  = 24  

    for group_indices in fman_groups:
        num_frames = len(group_indices) // 9
        frames_per_row = 18

        for f_idx in range(num_frames):
            x0 = 10 + (f_idx % frames_per_row) * (sprite_px * scale + gap)
            y0 = current_y + (f_idx // frames_per_row) * (sprite_px * scale + gap)
            
            # Draw frame border
            canvas.create_rectangle(x0-1, y0-1, x0 + sprite_px*scale, 
                                     y0 + sprite_px*scale, outline="gray")

            frame_map = group_indices[f_idx*9 : (f_idx+1)*9]
            for row in range(3):
                for col in range(3):
                    t_idx = frame_map[row * 3 + col]
                    if t_idx == 0 or t_idx >= len(decoded_tiles): continue
                    show = getattr(canvas, '_show_labels', False)
                    draw_tile_grouped(canvas, decoded_tiles[t_idx],
                                      x0 + col*8*scale, y0 + row*8*scale,
                                      scale=scale, tile_idx=t_idx, show_label=show)

        group_rows = (num_frames + frames_per_row - 1) // frames_per_row
        current_y += group_rows * (sprite_px * scale + gap) + 20

    return current_y - y_offset


def draw_composed_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale,
                        tile_meta=None, meta_pos=None, prev_tiles=None):
    """Draws a generic composed frame.
    frame_data = [pal, [row1_tiles...], [row2_tiles...], ...]
    Each inner list is a row of 8×8 tile indices.
    If tile_meta dict and meta_pos tuple are given, stores (meta_pos, ri, ci) per tag.
    prev_tiles: shared dict for cross-frame -1 resolution (keyed by (ri, ci)).
    If canvas is None, only updates prev_tiles (no drawing).
    """
    TILE_SIZE = 32
    pal_idx = frame_data[0]
    rows = frame_data[1:]
    lut = PAL_DECODE_TABLES[pal_idx]
    show = getattr(canvas, '_show_labels', False) if canvas else False

    for ri, row_tiles in enumerate(rows):
        for ci, t_idx in enumerate(row_tiles):
            if t_idx == 0 and prev_tiles is not None:
                prev_tiles.pop((ri, ci), None)
                continue
            if t_idx == 0:
                continue
            was_neg = t_idx < 0
            if was_neg:
                if prev_tiles is not None:
                    t_idx = prev_tiles.get((ri, ci), -1)
                else:
                    t_idx = -1
            if t_idx < 0:
                if canvas is not None:
                    tx = x_frame + ci * 8 * scale
                    ty = y_frame + ri * 8 * scale
                    draw_tile_grouped(canvas, None, tx, ty, tile_idx=-1, show_label=show, scale=scale)
                continue
            if prev_tiles is not None and not was_neg:
                prev_tiles[(ri, ci)] = t_idx
            if canvas is None:
                continue
            tile_data = tiles_raw[t_idx * TILE_SIZE : (t_idx + 1) * TILE_SIZE]
            pixels = decode_fman_tile(tile_data, lut)
            tx = x_frame + ci * 8 * scale
            ty = y_frame + ri * 8 * scale
            display_idx = -1 if was_neg else t_idx
            tag = draw_tile_grouped(canvas, pixels, tx, ty, tile_idx=display_idx, show_label=show, scale=scale)
            if tile_meta is not None and meta_pos is not None:
                tile_meta[tag] = (*meta_pos, ri, ci)

def draw_composed_16x16_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale,
                               prev_tiles=None):
    """Draws a 16x16 frame composed of four 8x8 tiles [tl, tr, bl, br].
    If canvas is None, only updates prev_tiles (no drawing).
    """
    TILE_SIZE = 32
    pal_idx = frame_data[0]
    tile_indices = frame_data[1:] # [tl, tr, bl, br]
    lut = PAL_DECODE_TABLES[pal_idx]
    show = getattr(canvas, '_show_labels', False) if canvas else False

    pos = [(0,0), (0,1), (1,0), (1,1)]
    for i, t_idx in enumerate(tile_indices):
        if t_idx == 0 and prev_tiles is not None:
            prev_tiles.pop(pos[i], None)
            continue
        if t_idx == 0:
            continue
        was_neg = t_idx < 0
        if was_neg:
            if prev_tiles is not None:
                t_idx = prev_tiles.get(pos[i], -1)
            else:
                t_idx = -1
        if t_idx < 0:
            if canvas is not None:
                col_offset = (i % 2) * 8 * scale
                row_offset = (i // 2) * 8 * scale
                draw_tile_grouped(canvas, None, x_frame + col_offset, y_frame + row_offset,
                                  tile_idx=-1, show_label=show, scale=scale)
            continue
        if prev_tiles is not None and not was_neg:
            prev_tiles[pos[i]] = t_idx
        if canvas is None:
            continue
        tile_data = tiles_raw[t_idx * TILE_SIZE : (t_idx + 1) * TILE_SIZE]
        pixels = decode_fman_tile(tile_data, lut)
        col_offset = (i % 2) * 8 * scale
        row_offset = (i // 2) * 8 * scale
        display_idx = -1 if was_neg else t_idx
        draw_tile_grouped(canvas, pixels, x_frame + col_offset, y_frame + row_offset,
                          tile_idx=display_idx, show_label=show, scale=scale)

def draw_composed_24x24_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale,
                               prev_tiles=None):
    """Draws a 24x24 frame composed of nine 8x8 tiles [by columns].
    If canvas is None, only updates prev_tiles (no drawing).
    """
    TILE_SIZE = 32
    tile_indices = frame_data
    lut = PAL_DECODE_TABLES[0]
    show = getattr(canvas, '_show_labels', False) if canvas else False

    pos = [(0,0), (1,0), (2,0), (0,1), (1,1), (2,1), (0,2), (1,2), (2,2)]
    for i, t_idx in enumerate(tile_indices):
        if t_idx == 0 and prev_tiles is not None:
            prev_tiles.pop(pos[i], None)
            continue
        if t_idx == 0:
            continue
        was_neg = t_idx < 0
        if was_neg:
            if prev_tiles is not None:
                t_idx = prev_tiles.get(pos[i], -1)
            else:
                t_idx = -1
        if t_idx < 0:
            if canvas is not None:
                col_offset = (i // 3) * 8 * scale
                row_offset = (i % 3) * 8 * scale
                draw_tile_grouped(canvas, None, x_frame + col_offset, y_frame + row_offset,
                                  tile_idx=-1, show_label=show, scale=scale)
            continue
        if prev_tiles is not None and not was_neg:
            prev_tiles[pos[i]] = t_idx
        if canvas is None:
            continue
        tile_data = tiles_raw[t_idx * TILE_SIZE : (t_idx + 1) * TILE_SIZE]
        pixels = decode_fman_tile(tile_data, lut)
        col_offset = (i // 3) * 8 * scale
        row_offset = (i % 3) * 8 * scale
        display_idx = -1 if was_neg else t_idx
        draw_tile_grouped(canvas, pixels, x_frame + col_offset, y_frame + row_offset,
                          tile_idx=display_idx, show_label=show, scale=scale)

def render_dman_group(data, canvas, y_offset):
    """
    Render dman.grp sprites.
    The first byte of each frame chooses the palette (lut).
    """
    TILE_SIZE = 32
    scale = SCALE
    current_y = y_offset
    gap_x = 16
    gap_y = 24
    sprite_px = 24  # Total width/height of the 3x3 tile assembly
    frames_per_row = 10

    # Ensure the data buffer is padded to prevent index-out-of-range errors 
    # for high tile indices (e.g., 0xF8)
    tiles_raw = data + b'\x00' * (256 * TILE_SIZE)

    for anim_name, frames in DMAN_FRAMES.items():
        for f_idx, frame_data in enumerate(frames):
            # Calculate base position for the 24x24 sprite
            x_frame = 10 + (f_idx % frames_per_row) * (sprite_px * scale + gap_x)
            y_frame = current_y + (f_idx // frames_per_row) * (sprite_px * scale + gap_y)

            # Draw frame border
            canvas.create_rectangle(x_frame-1, y_frame-1, x_frame + sprite_px*scale, 
                                     y_frame + sprite_px*scale, outline="gray")

            draw_composed_24x24_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale)

        # Advance Y cursor to the next animation block
        num_rows = (len(frames) + frames_per_row - 1) // frames_per_row
        current_y += num_rows * (sprite_px * scale + gap_y)

    return current_y - y_offset


def render_enp_group(data, canvas, y_offset, frames_key="auto", frames_override=None):
    """
    Render enpX.grp sprites.
    frames_key="enp1" : ENP1_FRAMES 레이아웃 사용 (enp1.grp, 16x16 고정)
    frames_key in FRAMES_REGISTRY : 해당 dict로 draw_composed_frame 렌더링
    otherwise         : 공유 프레임(Hit/Glow 등) + 0x19부터 순차 2x2 블록 배치 (enp2-8)
    """
    TILE_SIZE = 32
    scale     = SCALE
    sprite_px = 16
    gap_x     = 2 * scale
    gap_y     = 2 * scale
    frames_per_row = 12
    tiles_raw = data + b'\x00' * (256 * TILE_SIZE)
    current_y = y_offset

    # ── enp1: 하드코딩 프레임 맵 ─────────────────────────────────────────
    if frames_key == "enp1":
        for anim_name, frames in ENP1_FRAMES.items():
            # Animation 이름 레이블
            canvas.create_text(10, current_y, text=anim_name,
                                anchor="nw", fill="#ffcc44", font=("Courier", 10, "bold"),
                                tags=("draggable",))
            current_y += 16
            for f_idx, frame_data in enumerate(frames):
                x_frame = 10 + (f_idx % frames_per_row) * (sprite_px * scale + gap_x)
                y_frame = current_y + (f_idx // frames_per_row) * (sprite_px * scale + gap_y)
                draw_composed_16x16_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale)
            num_rows = (len(frames) + frames_per_row - 1) // frames_per_row
            current_y += num_rows * (sprite_px * scale + gap_y) + 4
        return current_y - y_offset

    # ── enp2/3/…: FRAMES_REGISTRY 맵 (draw_composed_frame 기반) ──────
    frames_dict = FRAMES_REGISTRY.get(frames_key, None)
    if frames_dict is not None:
        enp_data = frames_override if frames_override is not None else frames_dict
        if current_y == y_offset:
            current_y += 6
            canvas._tile_meta = {}
            prev_tiles = {}
            for anim_name, frames in enp_data.items():
                if anim_name.startswith("_"):
                    continue
                canvas.create_text(10, current_y, text=anim_name,
                                    anchor="nw", fill="#ffcc44", font=("Courier", 10, "bold"),
                                    tags=("draggable",))
                current_y += 17
                # Detect frame format: flat [pal, t1, t2, t3, t4] or nested [pal, [row1...], ...]
                first_fd = next((fd for fd in frames if len(fd) > 1), None)
                is_flat = first_fd is not None and isinstance(first_fd[1], int)
                if is_flat:
                    spr_w = 16
                    spr_h = 16
                else:
                    spr_w = max((max(len(r) for r in fd[1:]) if len(fd) > 1 else 0) * 8 for fd in frames)
                    spr_h = max(len(fd[1:]) * 8 for fd in frames)
                for f_idx, frame_data in enumerate(frames):
                    x_frame = 10 + (f_idx % frames_per_row) * (spr_w * scale + gap_x)
                    y_frame = current_y + (f_idx // frames_per_row) * (spr_h * scale + gap_y)
                    if is_flat:
                        draw_composed_16x16_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale,
                                                  prev_tiles=prev_tiles)
                    else:
                        draw_composed_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale,
                                            tile_meta=canvas._tile_meta, meta_pos=(anim_name, f_idx),
                                            prev_tiles=prev_tiles)
                num_rows = (len(frames) + frames_per_row - 1) // frames_per_row
                current_y += num_rows * (spr_h * scale + gap_y) + 6
        return current_y - y_offset

    # ── auto: 2x2 블록 배치 (enp2-8) ────────────────────────────────────
    # 공유 섹션: 타일 0x01~0x18 (Hit/Glow 이펙트)
    SHARED_FRAMES = [
        ("Hit",           [[1, 0x01,0x02,0x03,0x04],[1,0x05,0x06,0x07,0x08],[1,0x09,0x0A,0x0B,0x0C]]),
        ("Glow",          [[0, 0x0D,0x0E,0x0F,0x10],[0,0x11,0x12,0x13,0x14],[0,0x15,0x16,0x17,0x18]]),
        ("Chest",         [[0, 0xC9,0xCA,0xCB,0xCC]]),
        ("Key",           [[1, 0xCD,0xCE,0xCF,0xD0]]),
        ("Red Potion",    [[0, 0xD1,0xD2,0xD3,0xD4]]),
        ("Wall Destroy",  [[1,0xD5,0xD5,0xD5,0xD5],[1,0xD6,0xD7,0xD8,0xD9],
                           [1,0xDA,0xDB,0xDC,0xDD],[1,0x00,0x00,0xDE,0xDF]]),
    ]
    for anim_name, frames in SHARED_FRAMES:
        canvas.create_text(10, current_y, text=anim_name,
                            anchor="nw", fill="#ffcc44", font=("Courier", 10, "bold"),
                            tags=("draggable",))
        current_y += 16
        for f_idx, frame_data in enumerate(frames):
            x_frame = 10 + (f_idx % frames_per_row) * (sprite_px * scale + gap_x)
            y_frame = current_y + (f_idx // frames_per_row) * (sprite_px * scale + gap_y)
            draw_composed_16x16_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale)
        num_rows = (len(frames) + frames_per_row - 1) // frames_per_row
        current_y += num_rows * (sprite_px * scale + gap_y) + 4
    current_y += 8

    # 몬스터 전용 타일: 0x19 ~ (tile_count - 1), 4타일씩 2x2 조립
    n_tiles = len(data) // TILE_SIZE
    START = 0x19
    n_monster_tiles = max(0, n_tiles - START)
    n_frames = n_monster_tiles // 4

    for fi in range(n_frames):
        col = fi % frames_per_row
        row = fi // frames_per_row
        x_frame = 10 + col * (sprite_px * scale + gap_x)
        y_frame = current_y + row * (sprite_px * scale + gap_y)
        base = START + fi * 4
        frame_data = [0, base, base+1, base+2, base+3]
        draw_composed_16x16_frame(canvas, frame_data, tiles_raw, x_frame, y_frame, scale)

    n_rows = (n_frames + frames_per_row - 1) // frames_per_row
    current_y += n_rows * (sprite_px * scale + gap_y)
    return current_y - y_offset

def render_boss_group(data, canvas, y_offset):
    TILE_SIZE = 32
    scale = SCALE
    current_y = y_offset
    gap_x, gap_y = 25, 35
    
    # Header size in crab.grp is 0; tiles start immediately after the descriptors
    tiles_raw = data + b'\x00' * (256 * TILE_SIZE)

    # -----------------------------------------------------------------------
    # Part 1: Render Composite Crab Body (Phases 0-9)
    # -----------------------------------------------------------------------

    # Normal layout for phases 0-8: (part_name, grid_x, grid_y)
    body_layout08 = [
        ("Left Eye", 24, 0), ("Right Eye", 40, 0),
        ("Left Tibia", 0, 16), ("Left Femur", 16, 16), ("Mouth", 32, 16), ("Right Femur", 48, 16), ("Right Tibia", 64, 16),
        ("Left Bottom Legs", 0, 32), ("Left Claw", 16, 32), ("Maxilla", 32, 32), ("Right Claw", 48, 32), ("Right Bottom Legs", 64, 32)
    ]
    body_layout9 = [
        ("Left Eye", 32, 0),
        ("Left Tibia", 0, 16), ("Left Femur", 16, 8), ("Right Femur", 48, 8), ("Right Tibia", 64, 16),
        ("Left Bottom Legs", 8, 32), ("Left Claw", 16, 24), ("Right Claw", 48, 24), ("Right Bottom Legs", 56, 32)
    ]

    frames_per_row = 3
    for phase in range(10):
        x_base = 10 + (phase % frames_per_row) * (80 * scale + gap_x)
        y_base = current_y + (phase // frames_per_row) * (48 * scale + gap_y)
        
        canvas.create_rectangle(x_base-1, y_base-1, x_base + 80*scale, y_base + 48*scale, outline="gray")

        if phase < 9:
            # Standard rendering for phases 0-8
            for name, gx, gy in body_layout08:
                draw_composed_16x16_frame(canvas, CRAB_FRAMES[name][phase], tiles_raw, x_base + gx*scale, y_base + gy*scale, scale)
        else:
            # Phase 9: Special placement
            for name, gx, gy in body_layout9:
                draw_composed_16x16_frame(canvas, CRAB_FRAMES[name][phase], tiles_raw, x_base + gx*scale, y_base + gy*scale, scale)

    # Advance y_cursor past the 2 rows of body phases
    current_y += 3 * (48 * scale + gap_y) + 36
    
    # -----------------------------------------------------------------------
    # Part 2: Render Remaining 16x16 frames
    # -----------------------------------------------------------------------
    for anim_name in ["Mouth Acid Frames", "Acid Drops"]:
        frames = CRAB_FRAMES[anim_name]
        f_per_row = 10
        for f_idx, frame_data in enumerate(frames):
            x_f = 276 + (f_idx % f_per_row) * (16 * scale + 12)
            y_f = current_y + (f_idx // f_per_row) * (16 * scale)
            
            draw_composed_16x16_frame(canvas, frame_data, tiles_raw, x_f, y_f, scale)
            canvas.create_rectangle(x_f-1, y_f-1, x_f + 16*scale, y_f + 16*scale, outline="gray")
        
        num_rows = (len(frames) + f_per_row - 1) // f_per_row
        current_y += num_rows * (16 * scale + 12)
        
    return current_y - y_offset

# ---------------------------------------------------------------------------
# Roka rendering (roka.grp dungeon entrance decorations)
# ---------------------------------------------------------------------------

def roca_transform(val, frame):
    """Transform a 6-bit color value using the PaletteTransform logic from ASM.
    Both the high 3 bits and low 3 bits are transformed independently."""
    if val == 0:
        return None  # Transparent

    # Substitution tables per frame for 3-bit sub-values
    _SUBS = [
        {6: 3, 7: 5},          # frame 0
        {4: 2},                # frame 1
        {4: 5, 7: 4},          # frame 2
        {4: 3, 7: 5, 6: 7},    # frame 3
        {7: 5, 4: 7, 6: 4},    # frame 4
    ]
    sub = _SUBS[frame]
    high = (val >> 3) & 0x07
    low  =  val       & 0x07
    return (sub.get(high, high) << 3) | sub.get(low, low)

def decode_48b_tile_planar(planar_data):
    """Convert one 48-byte planar tile to 8 rows of 8 decoded 6-bit pixel values.

    Implements Reassemble_3_Planes_To_Packed_Bitmap then immediately decodes,
    skipping the intermediate packed byte representation.
    Each row: 3 LE words → byte-swap (xchg) → big-endian → extract bits per pixel.
    """
    rows = []
    for ry in range(8):
        p1, p2, p3 = read_be_words(planar_data[ry*6 : ry*6+6])
        row_pixels = []
        for i in range(8):
            b_high, b_low = 15 - 2*i, 14 - 2*i
            h3 = (((p3>>b_high)&1) << 2) | (((p2>>b_high)&1) << 1) | ((p1>>b_high)&1)
            l3 = (((p3>>b_low )&1) << 2) | (((p2>>b_low )&1) << 1) | ((p1>>b_low )&1)
            row_pixels.append((h3 << 3) | l3)
        rows.append(row_pixels)
    return rows  # list of 8 lists of 8 values

def render_roka_group(tile_bank_raw, canvas, y_offset):
    """Render the hardcoded 28x18 roka map 5 times with palette animation."""
    TILE_SIZE = 48
    COLS, ROWS = 28, 18

    num_tiles = len(tile_bank_raw) // TILE_SIZE
    tile_pixel_rows = [
        decode_48b_tile_planar(tile_bank_raw[i*TILE_SIZE : (i+1)*TILE_SIZE])
        for i in range(num_tiles)
    ]

    current_y = y_offset
    gap = 20
    show = getattr(canvas, '_show_labels', False)

    for frame in range(5):
        current_y += 25
        for row in range(ROWS):
            for col in range(COLS):
                tile_idx = ROKA_MAP[row * COLS + col]
                if tile_idx == 0 or tile_idx >= num_tiles:
                    continue
                x0 = 10 + col * (8 * SCALE)
                y0 = current_y + row * (8 * SCALE)
                tag = next_tile_tag()
                tags = ("draggable", tag)
                for ry, row_pixels in enumerate(tile_pixel_rows[tile_idx]):
                    for rx, val in enumerate(row_pixels):
                        final_idx = roca_transform(val, frame)
                        if final_idx is not None:
                            draw_pixel(canvas, x0 + rx*SCALE, y0 + ry*SCALE,
                                      PALETTE_STRS[final_idx], tags=tags)
                if show:
                    font_size = max(7, int(SCALE * 2.5))
                    canvas.create_text(x0 + 2, y0 + 2, text=f"{tile_idx}", anchor="nw",
                                      fill="white", font=("Courier", font_size),
                                      tags=("draggable", "tile_label", tag))
                if not hasattr(canvas, '_frame_origins'):
                    canvas._frame_origins = {}
                canvas._frame_origins[tag] = (x0, y0)
        current_y += ROWS * 8 * SCALE + gap

    return current_y - y_offset

def render_dchr_group(tile_bank_raw, canvas, y_offset, layout=None):
    TILE_SIZE = 48
    num_tiles = len(tile_bank_raw) // TILE_SIZE

    # Pre-decode all planar tiles into pixel rows
    tile_pixel_rows = [
        decode_48b_tile_planar(tile_bank_raw[i*TILE_SIZE : (i+1)*TILE_SIZE])
        for i in range(num_tiles)
    ]

    row_gap = 0
    tile_dim = 8 * SCALE
    section_gap = tile_dim // 2 + 4
    group_gap = tile_dim // 2
    show = getattr(canvas, '_show_labels', False)

    # --- Named sections: dict with string keys mapping to list-of-rows ---
    if isinstance(layout, dict) and not layout.get("indices"):
        current_y = y_offset
        for section_name, rows in layout.items():
            canvas.create_text(10, current_y, text=section_name, anchor="nw",
                              fill="#ffcc44", font=("Courier", 10, "bold"))
            current_y += 14
            for row in rows:
                x_cursor = 10
                for t_idx in row:
                    if 0 <= t_idx < num_tiles:
                        tag = next_tile_tag()
                        tags = ("draggable", tag)
                        for ry, row_pixels in enumerate(tile_pixel_rows[t_idx]):
                            for rx, val in enumerate(row_pixels):
                                if val != 0:
                                    draw_pixel(canvas, x_cursor + rx*SCALE, current_y + ry*SCALE,
                                              PALETTE_STRS[val], tags=tags)
                        if show:
                            font_size = max(7, int(SCALE * 2.5))
                            canvas.create_text(x_cursor + 2, current_y + 2, text=f"{t_idx}", anchor="nw",
                                              fill="white", font=("Courier", font_size),
                                              tags=("draggable", "tile_label", tag))
                        if not hasattr(canvas, '_frame_origins'):
                            canvas._frame_origins = {}
                        canvas._frame_origins[tag] = (x_cursor, current_y)
                    x_cursor += tile_dim + 1
                current_y += tile_dim + row_gap
            current_y += section_gap + 4
        return current_y - y_offset

    # --- Old format (list of rows of group sizes) ---
    if not layout or not isinstance(layout, list):
        num_rows = (num_tiles + 4) // 5
        layout = [list(range(i*5, min((i+1)*5, num_tiles))) for i in range(num_rows)]

    current_y = y_offset
    tile_idx = 0
    for row in layout:
        x_cursor = 10
        for group_size in row:
            for _ in range(group_size):
                if tile_idx >= num_tiles:
                    break
                tag = next_tile_tag()
                tags = ("draggable", tag)
                for ry, row_pixels in enumerate(tile_pixel_rows[tile_idx]):
                    for rx, val in enumerate(row_pixels):
                        if val != 0:
                            draw_pixel(canvas, x_cursor + rx*SCALE, current_y + ry*SCALE,
                                      PALETTE_STRS[val], tags=tags)
                if show:
                    font_size = max(7, int(SCALE * 2.5))
                    canvas.create_text(x_cursor + 2, current_y + 2, text=str(tile_idx), anchor="nw",
                                      fill="white", font=("Courier", font_size),
                                      tags=("draggable", "tile_label", tag))
                if not hasattr(canvas, '_frame_origins'):
                    canvas._frame_origins = {}
                canvas._frame_origins[tag] = (x_cursor, current_y)
                x_cursor += tile_dim
                tile_idx += 1
            x_cursor += group_gap
        current_y += tile_dim + row_gap

    return current_y - y_offset

# ---------------------------------------------------------------------------
# TTL Title Screen rendering (ttl1-3.grp)
# ---------------------------------------------------------------------------

def decode_ttl_tile(tile_data):
    """Decode one 8x8 TTL tile from 32 bytes (8 rows x 4 bytes).
    Each byte packs 2 pixels: hi nibble = left, lo nibble = right.
    Returns 64 palette indices (or None for transparent/black).
    """
    pixels = []
    for ry in range(8):
        for bx in range(4):
            byte_val = tile_data[ry * 4 + bx]
            left_nib = (byte_val >> 4) & 0xF
            right_nib = byte_val & 0xF
            pixels.append(left_nib)
            pixels.append(right_nib)
    return pixels

# ---------------------------------------------------------------------------
# 6DE1 image decode pipeline (for full-image .grp files like ttl3.grp)
# Ported from grp_view2.py which matches the 041F:6DE1 RLE + 4-plane blit
# ---------------------------------------------------------------------------

_KNOWN_DIMS = [
    (2,8),(4,8),(5,8),(7,8),(16,8),(3,16),(16,16),(11,16),(39,16),(4,16),(28,16),
    (17,16),(8,16),(52,16),(30,16),(2,20),(4,20),(6,24),(10,24),(7,24),(9,24),(2,24),
    (18,32),(9,32),(6,32),(1,32),(14,32),(3,32),(26,36),(37,36),(50,36),(28,36),
    (56,40),(16,40),(30,40),(34,48),(15,60),(80,60),(1,64),(16,64),(31,64),(66,64),
    (6,64),(56,72),(22,80),(24,88),(47,88),(22,88),(49,96),(127,96),(26,100),(28,100),
    (36,104),(44,104),(72,104),(65,112),(34,112),(84,112),(80,120),(4,128),(49,128),(62,128),
    (2,128),(80,136),(1,144),(134,160),(80,160),(63,176),(64,192),(15,192),(80,200),
    (31,216),(46,224),(3,232),
]

def _candidate_cls(decoded_size):
    """Return candidate CL values matching known ASM dims or divisor fallback."""
    primary = sorted({cl for (ch, cl) in _KNOWN_DIMS
                      if 0 <= decoded_size - ch * cl * 2 < 64})
    if primary:
        return primary
    half = decoded_size // 2
    return sorted({cl for cl in range(8, 257, 4)
                   if half % cl == 0 and 1 <= half // cl <= 256})

def decode_6de1(src):
    """041F:6DE1 RLE image decoder."""
    out = bytearray()
    i = 0
    while i < len(src):
        b = src[i]
        if b & 0x40:
            if i + 1 >= len(src): break
            word = (b << 8) | src[i + 1]; i += 2
            if word == 0xFFFF: break
            count = word & 0x3FFF
            if word & 0x8000:
                if i < len(src): out.extend([src[i]] * count); i += 1
            else:
                out.extend(src[i:i + count]); i += count
        else:
            count = b & 0x3F; i += 1
            if b & 0x80:
                if i < len(src): out.extend([src[i]] * count); i += 1
            else:
                out.extend(src[i:i + count]); i += count
    return bytes(out)

def interleave_4plane(src, rows, cl):
    """041F:30FC 4-plane interleaver: 2-plane 1bpp -> nibble-packed."""
    BP = rows * cl
    out = bytearray()
    si = 0
    for _ in range(BP // 2):
        bi = BP + si
        bx = (src[bi] << 8 | (src[bi+1] if bi+1 < len(src) else 0)) if bi < len(src) else 0
        ax = (src[si] << 8 | (src[si+1] if si+1 < len(src) else 0)) if si < len(src) else 0
        si += 2
        dx = (~(bx & ax)) & 0xFFFF
        cx = (bx | ax) & 0xFFFF
        ax = ax & dx
        bx = bx & dx
        planes = [cx, bx, ax, 0]
        for _ in range(4):
            pw = list(planes); acc = 0
            for _ in range(2):
                for _ in range(2):
                    for j in range(4):
                        msb = pw[j] >> 15
                        pw[j] = ((pw[j] << 1) & 0xFFFF) | msb
                        acc = ((acc << 1) | msb) & 0xFFFF
            planes = pw
            acc = ((acc & 0xFF) << 8) | ((acc >> 8) & 0xFF)
            out.extend([acc & 0xFF, (acc >> 8) & 0xFF])
    return bytes(out)

def _build_ttl3_palette():
    """256-entry VGA palette built from PALETTE.json file-level vga maps."""
    pal = ['#000000'] * 256
    colors = _PALETTE.get("colors", {})
    for grp_key, grp_val in _PALETTE.items():
        if isinstance(grp_val, dict) and "vga" in grp_val:
            for idx_str, color_name in grp_val["vga"].items():
                idx = int(idx_str, 0)
                if 0 <= idx < 256:
                    pal[idx] = colors.get(color_name, '#000000')
    return pal

def _render_6de1_image(data, canvas, y_offset, scale, palette=None, x_off=0):
    """Render a 6DE1-compressed full image on the canvas."""
    decoded = decode_6de1(data)
    if len(decoded) < 64:
        return None
    candidates = _candidate_cls(len(decoded))
    if not candidates:
        return None
    cl = candidates[0]
    rows = len(decoded) // (cl * 2)
    if rows < 1:
        return None
    trimmed = decoded[:rows * cl * 2]
    interleaved = interleave_4plane(trimmed, rows, cl)

    # VGA blit mask reconstruction (8-pass)
    mask1 = [0x80, 0x20, 0x08, 0x02, 0x40, 0x10, 0x04, 0x01]
    mask2 = [0x01, 0x04, 0x10, 0x40, 0x02, 0x08, 0x20, 0x80]
    def _wp(M):
        bl = M
        for s in range(8):
            cf = (bl >> 7) & 1; bl = ((bl << 1) & 0xFF) | cf
            if cf: return s
        return -1
    blit_calls = cl
    call_size = rows * 4
    m1p = [_wp(mask1[k]) for k in range(8)]
    m2p = [_wp(mask2[k]) for k in range(8)]
    vga = bytearray(call_size * blit_calls)
    for start_k in range(8):
        k = start_k
        for n in range(blit_calls):
            wp = m1p[k % 8] if n % 2 == 0 else m2p[k % 8]
            for i in range(call_size):
                if i % 8 == wp:
                    src_idx = n * call_size + i
                    if src_idx < len(interleaved):
                        vga[src_idx] |= interleaved[src_idx]
            k += 1

    pal = _build_ttl3_palette() if palette is None else palette

    # Render pixels onto canvas
    tag = next_tile_tag()
    tags = ("draggable", tag)
    for y in range(blit_calls):
        for x in range(call_size):
            val = vga[y * call_size + x]
            if val:
                color_str = pal[val] if val < len(pal) else '#000000'
                draw_pixel(canvas, x_off + x * scale, y_offset + y * scale, color_str, tags=tags)
    if not hasattr(canvas, '_frame_origins'):
        canvas._frame_origins = {}
    canvas._frame_origins[tag] = (x_off, y_offset)
    # Store for dev click lookup
    canvas._6de1_vga = vga
    canvas._6de1_w = call_size
    canvas._6de1_h = blit_calls
    canvas._6de1_y0 = y_offset
    canvas._6de1_scale = scale
    canvas._6de1_PALETTE = pal
    canvas._6de1_x0 = x_off
    # Clear stale nibble data
    canvas._nibble_tiles = None
    return blit_calls * scale  # total height

def render_ttl_group(data, canvas, y_offset, mode_override=None, grp_key="ttl3.grp"):
    """Render title screen tiles from ttl*.grp.
    mode_override: None=auto (6DE1 first), '6de1', 'nibble'.
    grp_key: filename key for per-file pipeline lookup."""
    scale = SCALE

    # If this file has a vga map in PALETTE.json, it's 6DE1-only
    has_vga = "vga" in _PALETTE.get(grp_key, {})
    mode = '6de1'
    if not has_vga:
        mode = mode_override if mode_override else '6de1'

    if mode == '6de1':
        # Try 6DE1 full-image pipeline
        pal = _build_ttl3_palette()
        # Center horizontally (roughly center of a 320-480px canvas window)
        height = _render_6de1_image(data, canvas, y_offset, scale, palette=pal)
        if height is not None:
            return height
        # If 6DE1 fails, fall through to nibble

    # Nibble tile rendering
    TILE_SIZE = 32
    n_tiles = len(data) // TILE_SIZE
    if n_tiles == 0:
        return 0

    # Build nibble color lookup from PALETTE.json
    nib_colors = {}
    nib_map = _PALETTE.get(grp_key, {}).get("nibble", {})
    pal_colors = _PALETTE.get("colors", {})
    for k, name in nib_map.items():
        nib_val = int(k, 0)
        nib_colors[nib_val] = pal_colors.get(name, "#000000")
    canvas._nibble_colors = nib_colors
    canvas._nibble_key = grp_key

    show = getattr(canvas, '_show_labels', False)

    # Auto-select columns: roughly square-ish grid
    for cols in range(27, 15, -1):
        if n_tiles % cols == 0:
            break
    else:
        cols = 22  # fallback
    ti_per_row = cols
    gap = 2

    for idx in range(n_tiles):
        x0 = (idx % ti_per_row) * (8 * scale + gap)
        y0 = y_offset + (idx // ti_per_row) * (8 * scale + gap)
        tile_data = data[idx * TILE_SIZE : (idx + 1) * TILE_SIZE]
        pixels = decode_ttl_tile(tile_data)
        tag = next_tile_tag()
        tags = ("draggable", tag)
        for i, nib in enumerate(pixels):
            color = nib_colors.get(nib, "#000000")
            rx, ry = i % 8, i // 8
            draw_pixel(canvas, x0 + rx * scale, y0 + ry * scale, color, tags=tags)
        if show:
            font_size = max(7, int(scale * 2.5))
            canvas.create_text(x0 + 2, y0 + 2, text=str(idx), anchor="nw",
                              fill="white", font=("Courier", font_size),
                              tags=("draggable", "tile_label", tag))
        if not hasattr(canvas, '_frame_origins'):
            canvas._frame_origins = {}
        canvas._frame_origins[tag] = (x0, y0)

    # Store for dev click lookup
    canvas._nibble_tiles = data
    canvas._nibble_w = ti_per_row * 8
    canvas._nibble_h = ((n_tiles + ti_per_row - 1) // ti_per_row) * 8
    canvas._nibble_y0 = y_offset
    canvas._nibble_scale = scale
    # Clear stale 6DE1 data
    canvas._6de1_vga = None

    n_rows = (n_tiles + ti_per_row - 1) // ti_per_row
    return n_rows * (8 * scale + gap)

# ---------------------------------------------------------------------------
# ympd.bin rendering (mode 16)
# ---------------------------------------------------------------------------

def _rle_decode_88x56(src, pos):
    """
    Port of RLE_decode_88_x_56_bytes from ympd.asm.
    Token 0x06 = repeat: read next word (low byte = pixel, high byte = count).
    Output: 4928 bytes (88*56).
    """
    out = bytearray()
    expected = 88 * 56
    while len(out) < expected and pos < len(src):
        b = src[pos]; pos += 1
        if b == 0x06:
            if pos + 2 > len(src): break
            val = src[pos]; cnt = src[pos + 1]; pos += 2
            block = bytes([val]) * min(cnt, expected - len(out))
            out.extend(block)
        else:
            out.append(b)
    return bytes(out), pos

def _rle_extract_28(src, pos):
    """
    Port of RLE_extract_28_bytes from ympd.asm.
    High nibble 6 = repeat zero (low nibble) times.
    Output: 28 bytes.
    """
    out = bytearray()
    while len(out) < 28 and pos < len(src):
        b = src[pos]; pos += 1
        hi = (b >> 4) & 0xF
        lo = b & 0xF
        if hi == 6:
            out.extend([0] * lo)
        else:
            out.append(b)
    return bytes(out), pos

def _mcga_mountains(plane0, plane1):
    """
    Port of sub_34F9 from ympd.asm.
    Interleave bits from two 4928-byte byte-planes into 4-bit pixel values.
    Each group of 8 pixels: 1 byte from each plane -> 2-bit index, scaled to 4-bit.
    """
    n = min(len(plane0), len(plane1))
    pixels = []
    for i in range(n):
        b0 = plane0[i]
        b1 = plane1[i]
        for bit in range(8):
            idx = ((b1 >> (7 - bit)) & 1) << 1 | ((b0 >> (7 - bit)) & 1)
            pixels.append(idx * 5)
    return pixels

def _mcga_ground_record(rec_a, rec_b):
    """
    Port of line_8px from ympd.asm.
    Interleave two 28-byte ground records into 4-bit pixel values.
    Each record is 28 bytes of bit-plane data for one ground strip.
    """
    pixels = []
    for i in range(min(len(rec_a), len(rec_b))):
        ba = rec_a[i]
        bb = rec_b[i]
        for bit in range(8):
            idx = ((bb >> (7 - bit)) & 1) << 1 | ((ba >> (7 - bit)) & 1)
            pixels.append(idx * 5)
    return pixels

def render_ympd_group(data, canvas, y_offset, grp_key="ympd.bin"):
    """
    Render ympd.bin: two 88x56 mountain images + two ground sets (16 records each).
    
    ympd.bin layout (from disassembly):
      [RLE stream for mountains0] [RLE stream for mountains1]
      [RLE stream for groundA]    [RLE stream for groundB]
    """
    scale = SCALE
    pos = 0
    current_y = y_offset

    # Build nibble color lookup from palette.json
    ym_nib = _PALETTE.get(grp_key, {}).get("nibble", {})
    ympd_colors = {}
    pal_colors = _PALETTE.get("colors", {})
    for k, name in ym_nib.items():
        ympd_colors[int(k, 0)] = pal_colors.get(name, "#000000")

    # --- Decode mountains ---
    mtn0_raw, pos = _rle_decode_88x56(data, pos)
    mtn1_raw, pos = _rle_decode_88x56(data, pos)

    # MCGA interleave
    mtn0_pixels = _mcga_mountains(mtn0_raw, mtn1_raw)  # 4928 4-bit values

    # Also decode second mountain image (same file, interleaved differently)
    # Parse the pair again as the second mountain image
    mtn0b_raw, pos = _rle_decode_88x56(data, pos)
    mtn1b_raw, pos = _rle_decode_88x56(data, pos)
    mtn1_pixels = _mcga_mountains(mtn0b_raw, mtn1b_raw)

    # --- Decode ground ---
    groundA = []
    for _ in range(16):
        rec, pos = _rle_extract_28(data, pos)
        groundA.append(rec)
    groundB = []
    for _ in range(16):
        rec, pos = _rle_extract_28(data, pos)
        groundB.append(rec)

    # MCGA interleave each ground record pair
    ground_pixels = []
    for i in range(16):
        gpx = _mcga_ground_record(groundA[i], groundB[i])
        ground_pixels.append(gpx)

    # --- Render mountain 0 ---
    canvas.create_text(10, current_y, text="Mountain Image 0", anchor="nw",
                       fill="#ffcc44", font=("Courier", 10, "bold"), tags=("draggable",))
    current_y += 14
    for py in range(56):
        for px in range(88):
            idx = py * 88 + px
            if idx < len(mtn0_pixels):
                val = mtn0_pixels[idx]
                color = ympd_colors.get(val, "#000000")
                draw_pixel(canvas, 10 + px * scale, current_y + py * scale, color, scale=scale)
    current_y += 56 * scale + 12

    # --- Render mountain 1 ---
    canvas.create_text(10, current_y, text="Mountain Image 1", anchor="nw",
                       fill="#ffcc44", font=("Courier", 10, "bold"), tags=("draggable",))
    current_y += 14
    for py in range(56):
        for px in range(88):
            idx = py * 88 + px
            if idx < len(mtn1_pixels):
                val = mtn1_pixels[idx]
                color = ympd_colors.get(val, "#000000")
                draw_pixel(canvas, 10 + px * scale, current_y + py * scale, color, scale=scale)
    current_y += 56 * scale + 20

    # --- Render ground strips ---
    canvas.create_text(10, current_y, text="Ground Strips (16 records)", anchor="nw",
                       fill="#ffcc44", font=("Courier", 10, "bold"), tags=("draggable",))
    current_y += 14
    # Each ground record: 28 bytes -> 224 pixels, displayed as 28x8
    ground_w = 28
    ground_h = 8
    records_per_row = 8
    for i, gpx in enumerate(ground_pixels):
        col = i % records_per_row
        row = i // records_per_row
        x0 = 10 + col * (ground_w * scale + 6)
        y0 = current_y + row * (ground_h * scale + 4)
        canvas.create_rectangle(x0 - 1, y0 - 1,
                                x0 + ground_w * scale, y0 + ground_h * scale,
                                outline="#445566", tags="tile_border")
        for pi, val in enumerate(gpx):
            if val:
                rx = pi % ground_w
                ry = pi // ground_w
                color = ympd_colors.get(val, "#000000")
                draw_pixel(canvas, x0 + rx * scale, y0 + ry * scale, color, scale=scale)

    n_ground_rows = (16 + records_per_row - 1) // records_per_row
    current_y += n_ground_rows * (ground_h * scale + 4)

    return current_y - y_offset


# ---------------------------------------------------------------------------
# Main Application
# ---------------------------------------------------------------------------

class GrpViewer:
    def __init__(self, root):
        self.root = root
        self.root.title("Zeliard GRP Viewer")
        self.root.configure(bg=CANVAS_BG)
        self._scale = SCALE
        self._show_labels = True
        self._current_file_path = None
        self._current_render_args = None
        self._filename = None
        self._tile_bank = None
        self._edit_frames = None
        self._palette_win = None
        self._palette_ts = SCALE
        # self._palette_use_nomask removed; mode-based dispatch in _redraw_palette
        self._palette_cols = 16
        self._palette_n_tiles = 0
        self._palette_cell_w = None
        self._palette_cell_h = None
        self._dev_mode = False
        self._mode_dialog = None
        self._selected_PALETTE_tile = None
        self._tile_palette_size = 32
        self._show_borders = False
        self._mod = sys.modules[__name__]
        self.setup_ui()

        if len(sys.argv) > 1:
            self.load_file(sys.argv[1])

    def _zoom_in(self):
        if self._scale < 10:
            self._scale += 1
            self._zoom_label.config(text=f"{self._scale}×")
            self._mod.SCALE = self._scale
            self.render(*self._current_render_args)

    def _zoom_out(self):
        if self._scale > 1:
            self._scale -= 1
            self._zoom_label.config(text=f"{self._scale}×")
            self._mod.SCALE = self._scale
            self.render(*self._current_render_args)

    def _toggle_labels(self):
        self._show_labels = not self._show_labels
        state = 'normal' if self._show_labels else 'hidden'
        self.canvas.itemconfigure('tile_label', state=state)
        self.canvas.itemconfigure('section_title', state=state)
        self._label_btn.config(text=f"Labels {'ON' if self._show_labels else 'OFF'}")
        self.render(*self._current_render_args)

    def _draw_borders(self):
        origins = getattr(self.canvas, '_frame_origins', {})
        s = 8 * SCALE
        for tag, (ox, oy) in origins.items():
            self.canvas.create_rectangle(ox, oy, ox + s, oy + s,
                                          outline="#445566", width=1, tags="tile_border")

    def _toggle_borders(self):
        self._show_borders = not self._show_borders
        self._borders_btn.config(text=f"Borders {'ON' if self._show_borders else 'OFF'}")
        self.render(*self._current_render_args)

    def _count_tile_usage(self):
        usage = {}
        if self._edit_frames is not None:
            for anim_name, frames in self._edit_frames.items():
                if anim_name.startswith("_"):
                    continue
                for frame in frames:
                    rows = frame[1:]
                    for row in rows:
                        for t_idx in row:
                            if t_idx > 0:
                                usage[t_idx] = usage.get(t_idx, 0) + 1
        elif self._current_render_args:
            _, _, _, overrides = self._current_render_args
            ti = overrides.get("tile_indices") if isinstance(overrides, dict) else None
            if isinstance(ti, dict):
                for frames in ti.values():
                    if not isinstance(frames, list):
                        continue
                    for frame in frames:
                        if not isinstance(frame, list):
                            continue
                        for row in frame:
                            if not isinstance(row, list):
                                continue
                            for t_idx in row:
                                if isinstance(t_idx, (int, float)) and t_idx > 0:
                                    usage[int(t_idx)] = usage.get(int(t_idx), 0) + 1
        return usage

    def _replace_tile_at(self, canvas_x, canvas_y, new_tile_idx):
        """Find the tile at (canvas_x, canvas_y) in main canvas and replace it."""
        meta = getattr(self.canvas, '_tile_meta', {})
        origins = getattr(self.canvas, '_frame_origins', {})
        best_tag = None
        best_dist = 64 * self._scale * self._scale
        for tag, (ox, oy) in origins.items():
            if tag not in meta:
                continue
            dx = canvas_x - ox
            dy = canvas_y - oy
            dist = dx * dx + dy * dy
            if dist < best_dist:
                best_dist = dist
                best_tag = tag
        if best_tag is None:
            return False
        anim_name, f_idx, ri, ci = meta[best_tag]
        self._edit_frames[anim_name][f_idx][ri + 1][ci] = new_tile_idx
        self.render(*self._current_render_args)
        return True

    def _palette_click(self, event):
        if self._palette_cell_w is None or not self._dev_mode:
            return
        ex = self._palette_canvas.canvasx(event.x)
        ey = self._palette_canvas.canvasy(event.y)
        col = int((ex - 2) // self._palette_cell_w)
        row = int((ey - 2) // self._palette_cell_h)
        idx = row * self._palette_cols + col
        if 0 <= idx < self._palette_n_tiles:
            self._selected_PALETTE_tile = idx
            self.info_label.config(text=f"Selected tile {idx} — click on canvas to place")

    def _canvas_click(self, event):
        if not self._dev_mode:
            return
        # Tile replacement from palette
        if self._selected_PALETTE_tile is not None:
            if self._edit_frames is None:
                self._selected_PALETTE_tile = None
                self.info_label.config(text="Replace not available for this file")
                return
            cvx = self.canvas.canvasx(event.x)
            cvy = self.canvas.canvasy(event.y)
            if self._replace_tile_at(cvx, cvy, self._selected_PALETTE_tile):
                self._selected_PALETTE_tile = None
                self.info_label.config(text="Tile replaced")
            return
        # Palette index lookup for 6DE1/nibble rendered images
        c = self.canvas
        cvx = c.canvasx(event.x)
        cvy = c.canvasy(event.y)
        if getattr(c, '_6de1_vga', None) is not None:
            s = c._6de1_scale
            y0 = c._6de1_y0
            x0 = getattr(c, '_6de1_x0', 0)
            px = int((cvx - x0) / s)
            py = int((cvy - y0) / s)
            if 0 <= px < c._6de1_w and 0 <= py < c._6de1_h:
                idx = c._6de1_vga[py * c._6de1_w + px]
                color_str = c._6de1_PALETTE[idx] if idx < len(c._6de1_PALETTE) else '#000000'
                self.info_label.config(
                    text=f"Pixel ({px},{py})  index=0x{idx:02X} ({idx})  color={color_str}")
            elif getattr(c, '_nibble_tiles', None) is not None:
                s = c._nibble_scale
                y0 = c._nibble_y0
                px = int(cvx / s)
                py = int((cvy - y0) / s)
                tw = c._nibble_w
                th = c._nibble_h
                if 0 <= px < tw and 0 <= py < th:
                    tile_idx = (py // 8) * (tw // 8) + (px // 8)
                    tile_x = px % 8
                    tile_y = py % 8
                    nibble_idx = tile_y * 8 + tile_x
                    tile_size = 32
                    if tile_idx < len(c._nibble_tiles) // tile_size:
                        off = tile_idx * tile_size
                        td = c._nibble_tiles[off:off + tile_size]
                        byte_idx = tile_y * 4 + tile_x // 2
                        if byte_idx < len(td):
                            byte_val = td[byte_idx]
                            nib = (byte_val >> 4) & 0xF if tile_x % 2 == 0 else byte_val & 0xF
                            nib_colors = getattr(c, '_nibble_colors', {})
                            color_str = nib_colors.get(nib, "#000000")
                            self.info_label.config(
                                text=f"Tile {tile_idx} pixel ({px},{py}) nib=0x{nib:X} color={color_str}")

    def _capture_png(self):
        from PIL import Image
        import os
        import tkinter as tk
        try:
            c = self.canvas

            # Try direct pixel rendering first (no Ghostscript needed)
            img = None
            if getattr(c, '_6de1_vga', None) is not None:
                w, h = c._6de1_w, c._6de1_h
                vga, pal = c._6de1_vga, c._6de1_PALETTE
                s = getattr(c, '_6de1_scale', 1)
                img = Image.new('RGB', (w * s, h * s), (0, 0, 0))
                px = img.load()
                for y in range(h):
                    for x in range(w):
                        val = vga[y * w + x]
                        if val:
                            cs = pal[val] if val < len(pal) else '#000000'
                            r, g, b = int(cs[1:3], 16), int(cs[3:5], 16), int(cs[5:7], 16)
                        else:
                            r = g = b = 0
                        for dy in range(s):
                            for dx in range(s):
                                 px[x * s + dx, y * s + dy] = (r, g, b)
            elif getattr(c, '_nibble_tiles', None) is not None:
                s = getattr(c, '_nibble_scale', 1)
                w, h = c._nibble_w, c._nibble_h
                nib_colors = getattr(c, '_nibble_colors', {})
                data = c._nibble_tiles
                TILE_SIZE = 32
                n_tiles = len(data) // TILE_SIZE
                ti_per_row = w // 8
                img = Image.new('RGB', (w * s, h * s), (0, 0, 0))
                px = img.load()
                for idx in range(min(n_tiles, (h // 8) * ti_per_row)):
                    tx = (idx % ti_per_row) * 8
                    ty = (idx // ti_per_row) * 8
                    td = data[idx * TILE_SIZE:(idx + 1) * TILE_SIZE]
                    pixels = decode_ttl_tile(td)
                    for i, nib in enumerate(pixels):
                        cs = nib_colors.get(nib, "#000000")
                        r, g, b = int(cs[1:3], 16), int(cs[3:5], 16), int(cs[5:7], 16)
                        rx, ry = i % 8, i // 8
                        for dy in range(s):
                            for dx in range(s):
                                px[(tx + rx) * s + dx, (ty + ry) * s + dy] = (r, g, b)

            if img is None:
                # Fallback: try canvas postscript (requires Ghostscript)
                import tempfile
                tmp = tempfile.mktemp(suffix='.eps')
                try:
                    self.canvas.postscript(file=tmp, colormode='color')
                    img = Image.open(tmp)
                finally:
                    try:
                        os.unlink(tmp)
                    except Exception:
                        pass

            if img is None:
                raise RuntimeError("No image data available for capture")

            base = os.path.splitext(self._filename or "capture")[0]
            fname = f"{base}.png"
            img.save(fname)
            full_path = os.path.abspath(fname)
            self.info_label.config(text=f"Saved {full_path}")

            # Show success dialog with "Open Folder" button
            d = tk.Toplevel(self.root)
            d.title("Capture Saved")
            d.configure(bg=CANVAS_BG)
            d.resizable(False, False)
            d.transient(self.root)
            d.grab_set()
            tk.Label(d, text=f"Saved:\n{full_path}", bg=CANVAS_BG, fg=FG_COLOR,
                     font=("Courier", 9), justify=tk.LEFT).pack(padx=16, pady=10)
            btn_frame = tk.Frame(d, bg=CANVAS_BG)
            btn_frame.pack(pady=(0, 10))
            tk.Button(btn_frame, text="Open Folder",
                      command=lambda: self._open_folder(full_path, d)).pack(side=tk.LEFT, padx=5)
            tk.Button(btn_frame, text="Close",
                      command=d.destroy).pack(side=tk.LEFT, padx=5)
        except Exception as e:
            msg = f"Capture failed: {e}"
            self.info_label.config(text=msg)
            # Show error in popup
            d = tk.Toplevel(self.root)
            d.title("Capture Error")
            d.configure(bg=CANVAS_BG)
            d.resizable(False, False)
            d.transient(self.root)
            d.grab_set()
            tk.Label(d, text=msg, bg=CANVAS_BG, fg="#ff6060",
                     font=("Courier", 9), justify=tk.LEFT).pack(padx=16, pady=16)
            tk.Button(d, text="OK", command=d.destroy, width=10).pack(pady=(0, 10))

    def _open_folder(self, path, dialog):
        import os, subprocess
        folder = os.path.dirname(path)
        try:
            if sys.platform == 'win32':
                os.startfile(folder)
            elif sys.platform == 'darwin':
                subprocess.Popen(['open', folder])
            else:
                subprocess.Popen(['xdg-open', folder])
        except Exception as e:
            self.info_label.config(text=f"Open folder failed: {e}")
        dialog.destroy()

    def _toggle_palette(self):
        if not self._dev_mode or self._tile_bank is None:
            return
        if self._palette_win and self._palette_win.winfo_exists():
            self._palette_win.destroy()
            self._palette_btn.config(text="Palette OFF")
        else:
            self._open_tile_palette()
            self._palette_btn.config(text="Palette ON")

    def _palette_zoom_in(self):
        if self._palette_ts < 10:
            self._palette_ts += 1
            self._redraw_palette()

    def _palette_zoom_out(self):
        if self._palette_ts > 1:
            self._palette_ts -= 1
            self._redraw_palette()

    def _redraw_palette(self):
        if not (self._palette_win and self._palette_win.winfo_exists()):
            return
        self._palette_canvas.delete("all")
        TILE_SIZE = self._tile_palette_size
        tiles_raw = self._tile_bank
        n_tiles = self._palette_n_tiles
        usage = self._count_tile_usage()
        ts = self._palette_ts
        cols = self._palette_cols
        cell_w = 8 * ts + 6
        cell_h = 8 * ts + 16
        self._palette_cell_w = cell_w
        self._palette_cell_h = cell_h
        pal_canvas_w = cols * cell_w + 4
        pal_canvas_h = ((n_tiles + cols - 1) // cols) * cell_h + 4
        self._palette_canvas.configure(scrollregion=(0, 0, pal_canvas_w, pal_canvas_h))
        self._palette_zoom_label.config(text=f"{ts}×")
        # Determine mode for decoder selection
        mode = None
        if self._current_render_args:
            modes_arg = self._current_render_args[1]
            if isinstance(modes_arg, int):
                mode = modes_arg
        for i in range(n_tiles):
            tile_data = tiles_raw[i * TILE_SIZE : (i + 1) * TILE_SIZE]
            if mode in (5, 6, 7, 9, 10):
                pixels = decode_npc_tile(tile_data)
            elif mode == 17:
                pixels = decode_npc_tile_nomask(tile_data)
            elif mode in (8, 11, 12, 13):
                pixels = decode_fman_tile(tile_data, PAL_DECODE_TABLES[0])
            else:
                pixels = decode_fman_tile(tile_data, PAL_DECODE_TABLES[0])
            cnt = usage.get(i, 0)
            if cnt == 0:
                bg = "#1a1a2e"
            elif cnt == 1:
                bg = "#444455"
            else:
                bg = "#663333"
            col = i % cols
            row = i // cols
            x = col * cell_w + 2
            y = row * cell_h + 2
            self._palette_canvas.create_rectangle(x, y, x + cell_w - 2, y + cell_h - 2,
                                                   fill=bg, outline="#555566")
            for pi, p_val in enumerate(pixels):
                if p_val is None or p_val == 0:
                    continue
                px = x + (pi % 8) * ts + 1
                py = y + (pi // 8) * ts + 1
                self._palette_canvas.create_rectangle(px, py, px + ts, py + ts,
                                                       fill=PALETTE_STRS[p_val], outline="")
            self._palette_canvas.create_text(x + cell_w // 2 - 1, y + 8 * ts + 4,
                                              text=str(i), fill="#aaaacc",
                                              font=("Courier", 9))

    def _open_tile_palette(self):
        if self._palette_win and self._palette_win.winfo_exists():
            self._palette_win.destroy()
        self._palette_win = tk.Toplevel(self.root)
        self._palette_win.title("Tile Palette")
        self._palette_win.configure(bg="#1a1a2e")
        self._palette_cols = 16
        TILE_SIZE = self._tile_palette_size
        self._palette_n_tiles = len(self._tile_bank) // TILE_SIZE
        # Toolbar
        ptoolbar = tk.Frame(self._palette_win, bg="#1a1a2e")
        ptoolbar.pack(side=tk.TOP, fill=tk.X, padx=4, pady=4)
        tk.Button(ptoolbar, text="－", command=self._palette_zoom_out, width=2).pack(side=tk.LEFT)
        self._palette_zoom_label = tk.Label(ptoolbar, text=f"{self._palette_ts}×",
                                             bg="#1a1a2e", fg="#e0e0ff", width=3)
        self._palette_zoom_label.pack(side=tk.LEFT)
        tk.Button(ptoolbar, text="＋", command=self._palette_zoom_in, width=2).pack(side=tk.LEFT)
        # Canvas + scroll
        body = tk.Frame(self._palette_win, bg="#1a1a2e")
        body.pack(fill=tk.BOTH, expand=True)
        self._palette_canvas = tk.Canvas(body, bg="#1a1a2e", highlightthickness=0)
        vbar = tk.Scrollbar(body, orient=tk.VERTICAL, command=self._palette_canvas.yview)
        self._palette_canvas.configure(yscrollcommand=vbar.set)
        self._palette_canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        vbar.pack(side=tk.RIGHT, fill=tk.Y)
        self._palette_canvas.bind("<Button-1>", self._palette_click)
        self._palette_canvas.bind("<MouseWheel>", lambda e: self._palette_canvas.yview_scroll(int(-1*(e.delta/120)), "units"))
        self._redraw_palette()

    def _open_sprite_test(self):
        if self._sprite_test_win and self._sprite_test_win.winfo_exists():
            self._sprite_test_win.destroy()
            self._sprite_test_win = None
            self._sprite_test_btn.config(text="Animation OFF")
            return
        frames = self._edit_frames
        tiles_raw = self._tile_bank
        is_npc = False
        use_nomask = False
        if frames is None and self._current_render_args:
            data, modes, filename, overrides = self._current_render_args
            if isinstance(modes, int) and modes == 17:
                use_nomask = True
            if isinstance(overrides, dict) and "tile_indices" in overrides:
                ti = overrides["tile_indices"]
                if isinstance(ti, dict):
                    frames = {}
                    tiles_raw = data
                    is_npc = True
                    for name, flist in ti.items():
                        if isinstance(flist, list) and flist:
                            cooked = []
                            for frame in flist:
                                if isinstance(frame, list) and frame:
                                    if isinstance(frame[0], list):
                                        cooked.append([0] + frame)
                            if cooked:
                                frames[name] = cooked
        if frames is None or tiles_raw is None:
            return

        section_names = [k for k in frames if not k.startswith("_")]
        if not section_names:
            return

        # Choose decoder based on mode
        tile_decoder = decode_npc_tile_nomask if use_nomask else decode_npc_tile
        win = tk.Toplevel(self.root)
        self._sprite_test_win = win
        self._sprite_test_btn.config(text="Animation ON")
        win.title("Animation Test")
        win.configure(bg="#1a1a2e")
        win.geometry("560x520")
        win.minsize(300, 300)

        state = {"playing": False, "frame": 0, "after_id": None}

        # Controls bar
        ctrl = tk.Frame(win, bg="#1a1a2e")
        ctrl.pack(fill=tk.X, padx=6, pady=6)

        tk.Label(ctrl, text="Sprite:", bg="#1a1a2e", fg="#f9e2af").pack(side=tk.LEFT)
        var_name = tk.StringVar()
        cb = ttk.Combobox(ctrl, textvariable=var_name, values=section_names,
                          state="readonly", width=26)
        cb.pack(side=tk.LEFT, padx=4)

        play_btn = tk.Button(ctrl, text="Play", width=5)
        play_btn.pack(side=tk.LEFT, padx=4)

        tk.Label(ctrl, text="FPS:", bg="#1a1a2e", fg="#aaaacc").pack(side=tk.LEFT)
        speed_lbl = tk.Label(ctrl, text="3", bg="#1a1a2e", fg="#e0e0ff", width=2)
        speed_lbl.pack(side=tk.LEFT)
        speed_var = tk.DoubleVar(value=3.0)
        tk.Scale(ctrl, from_=0, to=10, orient=tk.HORIZONTAL, variable=speed_var,
                 length=70, bg="#1a1a2e", highlightthickness=0, showvalue=False).pack(side=tk.LEFT)

        tk.Label(ctrl, text="Zoom:", bg="#1a1a2e", fg="#aaaacc").pack(side=tk.LEFT, padx=(10, 0))
        zoom_lbl = tk.Label(ctrl, text=f"{self._scale}\u00d7", bg="#1a1a2e", fg="#e0e0ff", width=3)
        zoom_lbl.pack(side=tk.LEFT)
        zoom_var = tk.IntVar(value=self._scale)
        tk.Scale(ctrl, from_=1, to=10, orient=tk.HORIZONTAL, variable=zoom_var,
                 length=80, bg="#1a1a2e", highlightthickness=0, showvalue=False).pack(side=tk.LEFT)

        # Frame bar
        frame_bar = tk.Scale(win, from_=0, to=0, orient=tk.HORIZONTAL,
                             bg="#1a1a2e", fg="#e0e0ff", highlightthickness=0,
                             length=300)
        frame_bar.pack(fill=tk.X, padx=8, pady=(0, 2))

        # Canvas
        canvas = tk.Canvas(win, bg="#1e1e2e", highlightthickness=1, highlightbackground="#444466")
        canvas.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)

        # Info label
        info_lbl = tk.Label(win, bg="#1a1a2e", fg="#aaaacc", font=("Courier", 9), anchor="w")
        info_lbl.pack(fill=tk.X, padx=8, pady=(0, 6))

        def render_frame(*_):
            canvas.delete("all")
            s = zoom_var.get()
            name = var_name.get()
            if not name or name not in frames:
                info_lbl.config(text="No sprite selected")
                return
            flist = frames[name]
            if not flist:
                info_lbl.config(text="Empty frame list")
                return
            fi = state["frame"] % len(flist)
            fd = flist[fi]
            # Sync frame bar
            frame_bar.config(to=len(flist) - 1)
            frame_bar.set(fi)
            if is_npc:
                rows = fd[1:]
                prev_tiles = {}
                for pf_idx in range(fi + 1):
                    pf = flist[pf_idx]
                    for ri, row in enumerate(pf[1:]):
                        for ci, t_idx in enumerate(row):
                            if t_idx == 0:
                                prev_tiles.pop((ri, ci), None)
                                continue
                            was_neg = t_idx < 0
                            if was_neg:
                                t_idx = prev_tiles.get((ri, ci), -1)
                            if t_idx < 0:
                                if pf_idx == fi:
                                    draw_tile_grouped(canvas, None,
                                                      4 + ci * 8 * s,
                                                      4 + ri * 8 * s,
                                                      tile_idx=-1, show_label=False, scale=s)
                                continue
                            if not was_neg:
                                prev_tiles[(ri, ci)] = t_idx
                            if pf_idx == fi:
                                display_idx = -1 if was_neg else t_idx
                                off = t_idx * 48
                                if off + 48 > len(tiles_raw):
                                    continue
                                pixels = tile_decoder(tiles_raw[off:off+48])
                                draw_tile_grouped(canvas, pixels,
                                                  4 + ci * 8 * s,
                                                  4 + ri * 8 * s,
                                            tile_idx=display_idx, show_label=False, scale=s)
                max_cols = max((len(r) for r in fd[1:]), default=0)
                max_rows = len(fd[1:])
            else:
                prev_tiles = {}
                for pf_idx in range(fi + 1):
                    pf = flist[pf_idx]
                    if pf_idx == fi:
                        draw_composed_frame(canvas, pf, tiles_raw, 4, 4, s, prev_tiles=prev_tiles)
                    else:
                        draw_composed_frame(None, pf, tiles_raw, 4, 4, s, prev_tiles=prev_tiles)
                max_cols = max((len(r) for r in fd[1:]), default=0)
                max_rows = len(fd[1:])
            cw = max_cols * 8 * s + 8
            ch = max_rows * 8 * s + 8
            canvas.config(scrollregion=(0, 0, cw, ch))
            info_lbl.config(text=f"Frame {fi+1}/{len(flist)}  {max_cols}\u00d7{max_rows} tiles")

        def play_next():
            if not state["playing"]:
                return
            speed = speed_var.get()
            name = var_name.get()
            if name in frames and frames[name] and speed > 0:
                state["frame"] = (state["frame"] + 1) % len(frames[name])
                render_frame()
            delay = int(1000.0 / speed) if speed > 0 else 100
            state["after_id"] = win.after(delay, play_next)

        def toggle_play():
            if state["playing"]:
                state["playing"] = False
                play_btn.config(text="Play")
                if state["after_id"]:
                    win.after_cancel(state["after_id"])
                    state["after_id"] = None
            else:
                state["playing"] = True
                play_btn.config(text="Stop")
                play_next()

        def on_select(*_):
            state["frame"] = 0
            if state["playing"]:
                if state["after_id"]:
                    win.after_cancel(state["after_id"])
                play_next()
            else:
                render_frame()

        def update_speed_label(*_):
            speed_lbl.config(text=str(int(speed_var.get())))
        def update_zoom_label(*_):
            zoom_lbl.config(text=f"{zoom_var.get()}\u00d7")
            render_frame()

        play_btn.config(command=toggle_play)
        cb.bind("<<ComboboxSelected>>", on_select)
        speed_var.trace_add("write", update_speed_label)
        zoom_var.trace_add("write", update_zoom_label)

        def on_frame_seek(e):
            if state["playing"]:
                if state["after_id"]:
                    win.after_cancel(state["after_id"])
                state["playing"] = False
                play_btn.config(text="Play")
            state["frame"] = int(frame_bar.get())
            render_frame()

        frame_bar.bind("<ButtonRelease-1>", on_frame_seek)

        def on_space(e):
            toggle_play()
            return "break"
        win.bind("<space>", on_space)
        win.focus_set()

        def on_close():
            if state["after_id"]:
                win.after_cancel(state["after_id"])
            win.destroy()
            self._sprite_test_win = None
            self._sprite_test_btn.config(text="Animation OFF")

        win.protocol("WM_DELETE_WINDOW", on_close)

        if section_names:
            var_name.set(section_names[0])
            render_frame()

    def _apply_json_descriptor(self):
        if self._current_render_args is None:
            return
        global _DATA, _PALETTE, GRP_DESCRIPTOR, FRAMES_REGISTRY
        try:
            new_data = _load_json_with_comments("DATA.json")
        except Exception as e:
            self.info_label.config(text=f"Failed to load DATA.json: {e}")
            return
        _DATA = new_data
        FRAMES_REGISTRY = _DATA["frames"]
        try:
            _PALETTE.clear()
            _PALETTE.update(_load_json_with_comments("PALETTE.json"))
        except Exception as e:
            self.info_label.config(text=f"Failed to load PALETTE.json: {e}")
            return
        GRP_DESCRIPTOR.clear()
        GRP_DESCRIPTOR.extend(new_data["descriptors"])
        for _desc in GRP_DESCRIPTOR:
            if len(_desc) > 2 and isinstance(_desc[2], dict):
                _fixed = {}
                for _k, _v in _desc[2].items():
                    try:
                        _fixed[int(_k)] = _v
                    except ValueError:
                        _fixed[_k] = _v
                _desc[2] = _fixed
        data, _modes, filename, _overrides = self._current_render_args
        desc = next((d for d in GRP_DESCRIPTOR if d[0] == filename), None)
        modes = desc[1] if desc else [1]
        overrides = desc[2] if desc and len(desc) > 2 else {}
        frames_key = overrides.get("frames", "auto") if isinstance(overrides, dict) else "auto"
        frames_dict = FRAMES_REGISTRY.get(frames_key, None)
        self._dev_mode = (isinstance(frames_dict, dict) and frames_dict.get("_DEV_MODE", False)) or (isinstance(overrides, dict) and overrides.get("_DEV_MODE", False)) or (desc is None)
        self._label_btn.config(text=f"Labels {'ON' if self._show_labels else 'OFF'}")
        self._borders_btn.config(text=f"Borders {'ON' if self._show_borders else 'OFF'}")
        self._edit_frames = None
        self.render(data, modes, filename, overrides)

    def _toggle_mode_dialog(self):
        if self._mode_dialog and self._mode_dialog.winfo_exists():
            self._mode_dialog.destroy()
            self._mode_dialog = None
            self._mode_btn.config(text="Mode OFF")
            return
        if self._current_render_args is None:
            return
        _, current_modes, _, _ = self._current_render_args
        default_mode = current_modes if isinstance(current_modes, int) else current_modes[0]
        MODE_DESC = {
            0: "0: Sprite 20x18 stride=15 270B (itemp.grp)",
            1: "1: Sprite 16x16 stride=12 192B (None Used)",
            2: "2: Font   8x8   stride=1   8B (font.grp)",
            3: "3: Sprite 16x16 stride=8  192B - BE (magic.grp)",
            4: "4: Sword  32x32 16B/tile (sword.grp)",
            5: "5: NPC 16x24 48B/tile index-table (mman.grp, cman.grp)",
            6: "6: Hero 16x24 48B/tile tile_indices (tman.grp, king.grp, kenjya.grp)",
            7: "7: Pattern 8x8  48B  - 3plane pattern (mpat.grp, dpat.grp, cpat.grp)",
            8: "8: fman   16x8  32B (fman.grp)",
            9: "9: roka   8x8   48B (roka.grp)",
            10:"10: dchr  8x8   48B (dchr.grp, mpp1~mppb.grp)",
            11:"11: enp   16x8  32B frames (enp1~enp8.grp)",
            12:"12: crab  16x8  32B (crab.grp)",
            13:"13: dman  16x8  32B (dman.grp)",
            14:"14: Title screen 3 6DE1 decode 32B/tile (ttl1.grp, ttl2.grp, ttl3.grp)",
            15:"15: Store image rowbytes layout (None Used)",
            16:"16: ympd  88x56 RLE MCGA (ympd.bin)",
            17:"17: Store 8x8 row-major 48B/tile tile_indices (omoya.grp, bank.grp, armor.grp, church.grp, drug.grp)",
        }
        d = tk.Toplevel(self.root)
        d.title("Rendering Mode")
        d.configure(bg=CANVAS_BG)
        d.resizable(False, False)
        self._mode_dialog = d
        self._mode_btn.config(text="Mode ON")
        def on_close():
            self._mode_dialog = None
            self._mode_btn.config(text="Mode OFF")
            d.destroy()
        d.protocol("WM_DELETE_WINDOW", on_close)
        tk.Label(d, text="Select mode:", bg=CANVAS_BG, fg=FG_COLOR).pack(padx=10, pady=5)
        var = tk.IntVar(value=default_mode)
        def on_select():
            if self._current_render_args:
                data, _, filename, _ = self._current_render_args
                desc = next((d for d in GRP_DESCRIPTOR if d[0] == filename), None)
                ov = desc[2] if desc and len(desc) > 2 else {}
                try:
                    self.render(data, var.get(), filename, ov)
                except Exception:
                    import traceback; traceback.print_exc()
                    self.info_label.config(text=f"Mode {var.get()} failed for {filename}")
        for k in sorted(MODE_DESC):
            tk.Radiobutton(d, text=MODE_DESC[k], variable=var, value=k, bg=CANVAS_BG, fg=FG_COLOR,
                           selectcolor="#222244", activebackground="#333355",
                           command=on_select, anchor="w", justify=tk.LEFT).pack(fill=tk.X, padx=10, pady=1)
        # focus + keep on top
        d.transient(self.root)
        d.grab_set()

    def _update_dev_toolbar(self):
        if hasattr(self, '_dev_toolbar'):
            if self._dev_mode:
                self._dev_toolbar.pack(side=tk.LEFT, before=self.info_label)
            else:
                self._dev_toolbar.pack_forget()

    def setup_ui(self):
        toolbar = tk.Frame(self.root, bg=CANVAS_BG)
        toolbar.pack(side=tk.TOP, fill=tk.X, padx=5, pady=5)

        tk.Button(toolbar, text="Open *.grp", command=self.on_open_click).pack(side=tk.LEFT)

        # Dev-only toolbar section
        self._dev_toolbar = tk.Frame(toolbar, bg=CANVAS_BG)

        # Zoom
        tk.Label(self._dev_toolbar, text=" Zoom:", bg=CANVAS_BG, fg="#aaaacc").pack(side=tk.LEFT, padx=(10, 2))
        tk.Button(self._dev_toolbar, text="－", command=self._zoom_out, width=2).pack(side=tk.LEFT)
        self._zoom_label = tk.Label(self._dev_toolbar, text=f"{self._scale}×", bg=CANVAS_BG, fg="#e0e0ff", width=3)
        self._zoom_label.pack(side=tk.LEFT)
        tk.Button(self._dev_toolbar, text="＋", command=self._zoom_in, width=2).pack(side=tk.LEFT)

        # Label toggle
        self._label_btn = tk.Button(self._dev_toolbar, text="Labels ON", command=self._toggle_labels)
        self._label_btn.pack(side=tk.LEFT, padx=(10, 2))

        # Border toggle
        self._borders_btn = tk.Button(self._dev_toolbar, text="Borders OFF", command=self._toggle_borders)
        self._borders_btn.pack(side=tk.LEFT, padx=(10, 2))

        # Palette toggle
        self._palette_btn = tk.Button(self._dev_toolbar, text="Palette OFF", command=self._toggle_palette)
        self._palette_btn.pack(side=tk.LEFT, padx=(10, 2))

        # Sprite Test
        self._sprite_test_btn = tk.Button(self._dev_toolbar, text="Animation OFF", command=self._open_sprite_test)
        self._sprite_test_btn.pack(side=tk.LEFT, padx=(10, 2))
        self._sprite_test_win = None

        # Apply JSON (F5)
        self._apply_json_btn = tk.Button(self._dev_toolbar, text="Apply JSON (F5)", command=self._apply_json_descriptor)
        self._apply_json_btn.pack(side=tk.LEFT, padx=(10, 2))
        self.root.bind("<F5>", lambda e: self._apply_json_descriptor())

        # Mode selector
        self._mode_btn = tk.Button(self._dev_toolbar, text="Mode OFF", command=self._toggle_mode_dialog)
        self._mode_btn.pack(side=tk.LEFT, padx=(10, 2))

        # Capture PNG
        tk.Button(self._dev_toolbar, text="Capture PNG", command=self._capture_png).pack(side=tk.LEFT, padx=(10, 2))

        self.info_label = tk.Label(toolbar, text="No file loaded", bg=CANVAS_BG, fg="#aaaacc", font=("Courier", 10))
        self.info_label.pack(side=tk.LEFT, padx=10)

        # Scrollable Canvas
        frame = tk.Frame(self.root, bg=CANVAS_BG)
        frame.pack(fill=tk.BOTH, expand=True)

        self.canvas = tk.Canvas(frame, bg=CANVAS_BG, highlightthickness=0)
        vbar = tk.Scrollbar(frame, orient=tk.VERTICAL, command=self.canvas.yview)
        hbar = tk.Scrollbar(self.root, orient=tk.HORIZONTAL, command=self.canvas.xview)

        self.canvas.configure(yscrollcommand=vbar.set, xscrollcommand=hbar.set)
        vbar.pack(side=tk.RIGHT, fill=tk.Y)
        hbar.pack(side=tk.BOTTOM, fill=tk.X)
        self.canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        self.canvas.bind("<MouseWheel>", lambda e: self.canvas.yview_scroll(int(-1*(e.delta/120)), "units"))
        self.canvas.bind("<Button-1>", self._canvas_click)

    def on_open_click(self):
        path = filedialog.askopenfilename(filetypes=[("Zeliard GRP", "*.grp"), ("All Files", "*.*")])
        if path:
            self.load_file(path)

    def load_file(self, path):
        try:
            raw = open(path, "rb").read()
        except Exception as e:
            self.info_label.config(text=f"Error: {e}")
            return

        # Simple Zeliard Header Handling
        if raw[0] == 0:
            skip, length, raw1 = 0, len(raw)-1, raw[1:]
        else:
            skip   = int.from_bytes(raw[1:3], "little")
            length = int.from_bytes(raw[3:5], "little")
            raw1   = raw[5+skip:]

        unpacked = unpack(raw1, length)
        filename = os.path.basename(path).lower()

        desc      = next((d for d in GRP_DESCRIPTOR if d[0] == filename), None)
        modes     = desc[1] if desc else [1]
        overrides = desc[2] if desc and len(desc) > 2 else {}
        no_desc  = desc is None

        self._filename = filename
        self._edit_frames = None
        self._tile_bank = None
        self._selected_PALETTE_tile = None
        # Determine dev mode + set label/border defaults
        frames_key = overrides.get("frames", "auto") if isinstance(overrides, dict) else "auto"
        frames_dict = FRAMES_REGISTRY.get(frames_key, None)
        self._dev_mode = (isinstance(frames_dict, dict) and frames_dict.get("_DEV_MODE", False)) or (isinstance(overrides, dict) and overrides.get("_DEV_MODE", False)) or no_desc
        self._show_labels = self._dev_mode
        self._show_borders = self._dev_mode
        self._label_btn.config(text=f"Labels {'ON' if self._dev_mode else 'OFF'}")
        self._borders_btn.config(text=f"Borders {'ON' if self._dev_mode else 'OFF'}")
        if self._palette_win and self._palette_win.winfo_exists():
            self._palette_win.destroy()
            self._palette_win = None
        self.render(unpacked, modes, filename, overrides)

    def render(self, data, modes, filename, overrides):
        self._current_render_args = (data, modes, filename, overrides)
        _tile_counter[0] = 0
        self.canvas.delete("all")
        self.canvas._frame_origins = {}
        self.canvas.delete("_blink_")
        self.canvas._blink_visible = True
        if getattr(self.canvas, '_blink_after_id', None):
            self.canvas.after_cancel(self.canvas._blink_after_id)
            self.canvas._blink_after_id = None
        self.canvas._show_labels = self._show_labels
        y_cursor = 10

        # Single-mode special cases
        if isinstance(modes, int):
            # Generic tile_indices override: any mode can use dict-based tile layout
            if isinstance(overrides, dict) and "tile_indices" in overrides:
                self._tile_palette_size = 48
                self._tile_bank = data + b'\x00' * (256 * 48)
                m17 = (modes == 17)
                consumed, max_w = render_grouped_tiles(data, self.canvas, y_cursor, is_hero=True, overrides=overrides, row_major=True,
                                                       decoder=decode_npc_tile_nomask if m17 else decode_npc_tile)
                self.canvas.config(scrollregion=(0, 0, max_w, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | Tile Layout")
                if self._show_borders:
                    self._draw_borders()
                self._update_dev_toolbar()
                self._redraw_palette()
                return
            if modes == 7:
                consumed = render_pat_group(data, self.canvas, y_cursor)
                self.canvas.config(scrollregion=(0, 0, 1000, y_cursor + consumed + 20))
                self.info_label.config(text=f"File: {filename} | Pattern Tiles")
            elif modes == 10:
                layout = overrides.get("_list", overrides) if isinstance(overrides, dict) else overrides
                consumed = render_dchr_group(data, self.canvas, y_cursor, layout=layout)
                self.canvas.config(scrollregion=(0, 0, 1000, y_cursor + consumed + 20))
                self.info_label.config(text=f"File: {filename} | Doors & Platforms")
            elif modes == 9:
                consumed = render_roka_group(data, self.canvas, y_cursor)
                self.canvas.config(scrollregion=(0, 0, 1200, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | 28x18 Map | 5 Palette Frames")
            elif modes == 8:
                frame_counts = overrides.get("_list", overrides) if isinstance(overrides, dict) else overrides
                consumed = render_fman_group(data, self.canvas, y_cursor, frame_counts)
                self.canvas.config(scrollregion=(0, 0, 1200, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | Hero in Dungeon Sprites")
            elif modes == 11:
                frames_key = overrides.get("frames", "auto") if isinstance(overrides, dict) else "auto"
                # Resolve frames dict for dev mode check
                frames_dict = FRAMES_REGISTRY.get(frames_key, None)
                dev = isinstance(frames_dict, dict) and frames_dict.get("_DEV_MODE", False)
                self._dev_mode = dev
                if dev:
                    if self._edit_frames is None:
                        self._edit_frames = copy.deepcopy(frames_dict)
                    TILE_SIZE = 32
                    self._tile_bank = data + b'\x00' * (256 * TILE_SIZE)
                consumed = render_enp_group(data, self.canvas, y_cursor, frames_key=frames_key,
                                             frames_override=self._edit_frames if dev else None)
                self.canvas.config(scrollregion=(0, 0, 1200, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | Monsters/Items Sprites")
            elif modes == 12:
                consumed = render_boss_group(data, self.canvas, y_cursor)
                self.canvas.config(scrollregion=(0, 0, 1200, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | Monsters/Items Sprites")
            elif modes == 13:
                consumed = render_dman_group(data, self.canvas, y_cursor)
                self.canvas.config(scrollregion=(0, 0, 1200, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | RokaDemo Sprites")
            elif modes == 14:
                consumed = render_ttl_group(data, self.canvas, y_cursor, grp_key=filename)
                self.canvas.config(scrollregion=(0, 0, 2000, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | Title Screen Image | 6DE1")
            elif modes == 16:
                consumed = render_ympd_group(data, self.canvas, y_cursor, grp_key=filename)
                self.canvas.config(scrollregion=(0, 0, 2000, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | ympd Mountains + Ground")
            elif modes == 17:
                consumed, max_w = render_grouped_tiles(data, self.canvas, y_cursor, is_hero=True,
                                                       overrides=overrides, row_major=True,
                                                       decoder=decode_npc_tile_nomask)
                self.canvas.config(scrollregion=(0, 0, max_w, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | Tile Layout")
            else:  # 5 or 6
                consumed = render_grouped_tiles(data, self.canvas, y_cursor, is_hero=(modes == 6), overrides=overrides)
                self.canvas.config(scrollregion=(0, 0, 1200, y_cursor + consumed + 40))
                self.info_label.config(text=f"File: {filename} | NPC Sprites")
            if self._show_borders:
                self._draw_borders()
            self._update_dev_toolbar()
            self._redraw_palette()
            return

        # Multi-group files: header holds one offset per group
        num_groups  = len(modes)
        offsets     = [int.from_bytes(data[i*2:(i+1)*2], "little") for i in range(num_groups)]
        unique_sorted = sorted(set(offsets))
        boundary_map  = {start: (unique_sorted[idx+1] if idx+1 < len(unique_sorted) else len(data))
                         for idx, start in enumerate(unique_sorted)}

        for i, mode in enumerate(modes):
            start_off  = offsets[i]
            group_data = data[start_off : boundary_map[start_off]]

            if MODE_CFG[mode]["type"] == "sword":
                consumed = render_sword_group(group_data, i, self.canvas, y_cursor)
            elif MODE_CFG[mode]["type"] == "sprite":
                tile_size = MODE_CFG[mode]["bytes"]
                if i in overrides:
                    s, c = overrides[i]
                    group_data = group_data[s*tile_size : (s+c)*tile_size]
                consumed = render_sprite_group(group_data, mode, self.canvas, y_cursor)
            else:
                consumed = render_font_group(group_data, mode, self.canvas, y_cursor)

            y_cursor += consumed + 20

        self.canvas.config(scrollregion=(0, 0, 1500, y_cursor))
        self.info_label.config(text=f"File: {filename} | Mega-Groups: {num_groups}")

        # Restore label visibility after re-render
        if not self._show_labels:
            self.canvas.itemconfigure('tile_label', state='hidden')

        # Draw tile borders if enabled
        if self._show_borders:
            self._draw_borders()
        self._update_dev_toolbar()
        self._redraw_palette()

if __name__ == "__main__":
    app = tk.Tk()
    app.geometry("1100x800")
    GrpViewer(app)
    app.mainloop()

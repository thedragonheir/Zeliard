"""
Map renderer module for MDTViewer.
This module extracts the map rendering logic from viewer.py into a
separate MapRenderer class. It holds no circular imports: it operates
on a passed-in viewer instance and uses viewer attributes (canvas,
mdt, block_size, etc.) to draw.
"""
from typing import Callable

from PIL import Image, ImageTk, ImageDraw

from ..core.constants import PALETTE
from ..core.decoder import decode_mdt_file_by_name
from .tile_graphics import get_tile_graphics
from ..core.constants import get_mdt_tileset


def _viewer_tileset_grp(viewer) -> str:
    fname = getattr(viewer, '_display_name', '') or ''
    if fname:
        grp_from_name = get_mdt_tileset(fname)
        # For MP*.MDT, force filename-world rule over descriptor.
        if grp_from_name.startswith('mpp'):
            return grp_from_name

    descriptor_grp = getattr(getattr(viewer, 'mdt', None), 'tileset_grp', '')
    if descriptor_grp:
        return descriptor_grp

    if fname:
        return grp_from_name
    return 'mpat.grp' if (viewer.mdt and viewer.mdt.is_town) else 'dpat.grp'


class MapRenderer:
    def __init__(self, viewer):
        self.viewer = viewer

    def get_tile_image(self, tile_idx):
        v = self.viewer
        grp_name = _viewer_tileset_grp(v)
        cache_key = (tile_idx, v.block_size, grp_name)
        if cache_key in v.tile_images:
            return v.tile_images[cache_key]

        # First, prefer GRP-based tile graphics if available
        try:
            if getattr(v, '_tile_gfx', None) and v._tile_gfx.loaded:
                photo = v._tile_gfx.get_tile_photo(tile_idx, v.block_size, grp_name)
                if photo:
                    v.tile_images[cache_key] = photo
                    return photo
        except Exception:
            pass

        # Fallback: use MDT-embedded gfx if present
        if not getattr(v.mdt, 'gfx', None) or tile_idx >= len(v.mdt.gfx):
            return None

        raw_pixels = v.mdt.gfx[tile_idx]
        img = Image.new('RGBA', (8, 8), (0, 0, 0, 0))
        for i, p_idx in enumerate(raw_pixels):
            if p_idx == -1:
                color_hex = v.PALETTE_STRS[5]
            else:
                color_hex = v.PALETTE_STRS[p_idx]
            x, y = i % 8, i // 8
            rgb = tuple(int(color_hex[i:i+2], 16) for i in (1, 3, 5))
            img.putpixel((x, y), rgb + (255,))
        img = img.resize((v.block_size, v.block_size), Image.NEAREST)
        photo = ImageTk.PhotoImage(img)
        v.tile_images[cache_key] = photo
        return photo

    def draw_map(self):
        v = self.viewer
        canvas = v.canvas
        canvas.delete('all')
        v.overlay_ids = []
        v._photo_refs = []
        if not v.mdt:
            return

        bs = v.block_size
        mw = v.mdt.map_width
        mh = v.mdt.map_height
        grid = v.mdt.grid
        wrap = v.wrap_var.get() and not v.mdt.is_town

        cx_count = 3 if wrap else 1
        cy_count = 3 if wrap else 1
        W = mw * bs * cx_count
        H = mh * bs * cy_count
        canvas.configure(scrollregion=(0, 0, W, H))

        ol = v.C_BG1 if (bs >= 6 and v.show_tile_border.get()) else ''
        ow = 1 if (bs >= 6 and v.show_tile_border.get()) else 0

        copies = [(0,0)] if not wrap else [
            (-1,-1),(0,-1),(1,-1),
            (-1, 0),(0, 0),(1, 0),
            (-1, 1),(0, 1),(1, 1),
        ]

        _pil_ok = False
        try:
            from PIL import Image as _PILImage, ImageTk as _PILImageTk
            _pil_ok = True
        except Exception:
            pass

        _hex_to_rgb_cache = {}
        def hex_rgb(h):
            if h not in _hex_to_rgb_cache:
                _hex_to_rgb_cache[h] = (int(h[1:3],16), int(h[3:5],16), int(h[5:7],16))
            return _hex_to_rgb_cache[h]

        def _render_copy_pil(ox, oy, palette_fn: Callable[[int], str], cache_key):
            if cache_key in v._map_cache:
                photo = v._map_cache[cache_key]
            else:
                from PIL import ImageDraw as _IDraw
                img  = _PILImage.new('RGB', (mw * bs, mh * bs))
                draw = _IDraw.Draw(img)
                for r in range(mh):
                    row_data = grid[r]
                    y0c = r * bs
                    for c in range(mw):
                        rgb = hex_rgb(palette_fn(row_data[c]))
                        x0c = c * bs
                        draw.rectangle([x0c, y0c, x0c+bs-1, y0c+bs-1], fill=rgb)
                photo = _PILImageTk.PhotoImage(img)
                v._map_cache[cache_key] = photo
            v._photo_refs.append(photo)
            canvas.create_image(ox, oy, image=photo, anchor='nw')

        for (gx, gy) in copies:
            is_center = (gx == 0 and gy == 0)
            ox = (gx + (1 if wrap else 0)) * mw * bs
            oy = (gy + (1 if wrap else 0)) * mh * bs

            if v.view_mode.get() == 'tiles' and is_center:
                for r in range(mh):
                    for c in range(mw):
                        tile_idx = grid[r][c]
                        x0 = ox + c * bs
                        y0 = oy + r * bs
                        town_surface = getattr(v.mdt, 'is_town', False) and not getattr(v.mdt, 'town_has_middle_layer', False)

                        # Tile index 0: surface town -> blue fill; dungeon/underground -> transparent
                        if tile_idx == 0:
                            if town_surface:
                                canvas.create_rectangle(x0, y0, x0+bs, y0+bs, fill=v.PALETTE_STRS[5])
                            continue

                        tile_img = self.get_tile_image(tile_idx)
                        if tile_img:
                            canvas.create_image(x0, y0, image=tile_img, anchor="nw")
                        else:
                            # Missing tile image: show blue for surface towns, otherwise leave transparent
                            if town_surface:
                                canvas.create_rectangle(x0, y0, x0+bs, y0+bs, fill=v.PALETTE_STRS[5])
                            else:
                                pass
            elif _pil_ok and bs >= 2:
                if is_center:
                    _render_copy_pil(ox, oy, lambda t: PALETTE[t % 64], ('c', bs))
                else:
                    _render_copy_pil(ox, oy, lambda t: v._gray(t), ('g', bs, gx, gy))
                if wrap and not is_center:
                    canvas.create_rectangle(
                        ox, oy, ox + mw*bs, oy + mh*bs,
                        fill='', outline='#334455', width=1)
            else:
                for r in range(mh):
                    for c in range(mw):
                        t  = grid[r][c]
                        x0 = ox + c * bs
                        y0 = oy + r * bs
                        color = PALETTE[t % 64] if is_center else v._gray(t)
                        canvas.create_rectangle(
                            x0, y0, x0+bs, y0+bs, fill=color, outline=ol, width=ow)
                if wrap and not is_center:
                    canvas.create_rectangle(
                        ox, oy, ox + mw*bs, oy + mh*bs,
                        fill='', outline='#334455', width=1)

        # Tile boundary grid (center copy only)
        if v.grid_var.get() and bs >= 3:
            ox = (1 if wrap else 0) * mw * bs
            oy = (1 if wrap else 0) * mh * bs
            x1 = ox + mw * bs
            y1 = oy + mh * bs
            for c in range(mw + 1):
                x = ox + c * bs
                canvas.create_line(x, oy, x, y1, fill='#202636', width=1)
            for r in range(mh + 1):
                y = oy + r * bs
                canvas.create_line(ox, y, x1, y, fill='#202636', width=1)

        if bs >= 4:
            ox = (1 if wrap else 0) * mw * bs
            oy = (1 if wrap else 0) * mh * bs
            for c in range(0, mw + 1, 16):
                canvas.create_line(ox+c*bs, oy, ox+c*bs, oy+mh*bs,
                    fill='#ffffff', stipple='gray25', width=1)
            for r in range(0, mh + 1, 16):
                canvas.create_line(ox, oy+r*bs, ox+mw*bs, oy+r*bs,
                    fill='#ffffff', stipple='gray25', width=1)

        if wrap:
            canvas.update_idletasks()
            cw = canvas.winfo_width()
            ch = canvas.winfo_height()
            cx = mw * bs
            cy = mh * bs
            canvas.xview_moveto(max(0, (cx - cw/2) / max(W-cw, 1)))
            canvas.yview_moveto(max(0, (cy - ch/2) / max(H-ch, 1)))

    def draw_overlays(self):
        v = self.viewer
        canvas = v.canvas
        for iid in v.overlay_ids:
            canvas.delete(iid)
        v.overlay_ids = []
        if not v.mdt or not v.show_overlay.get():
            return
        _show_vp_paths = v.show_vp_paths.get()
        _show_hp_paths = v.show_hp_paths.get()
        _show_cp_paths = v.show_cp_paths.get()
        _show_vp_label = v.show_vp_label.get()
        _show_hp_label = v.show_hp_label.get()
        _show_cp_label = v.show_cp_label.get()
        _show_labels   = v.show_labels.get()

        bs = v.block_size
        fs = max(6, min(10, bs - 1))
        font = ('Consolas', fs, 'bold')
        pad = max(1, bs // 6)

        wrap_on = v.wrap_var.get() and not v.mdt.is_town
        _ox = v.mdt.map_width  * bs if wrap_on else 0
        _oy = v.mdt.map_height * bs if wrap_on else 0

        def place(x, y, text, bg='#000000', fg='#000000'):
            """Place a labeled rectangle+text centered on tile (x,y).
            Defaults: black text on black bg for Color Blocks clarity.
            """
            cx = _ox + x * bs + bs // 2
            cy = _oy + y * bs + bs // 2
            tid = canvas.create_text(
                cx, cy, text=text, fill=fg, font=font, anchor='center')
            bb = canvas.bbox(tid)
            if bb:
                rid = canvas.create_rectangle(
                    bb[0] - pad, bb[1] - pad, bb[2] + pad, bb[3] + pad,
                    fill=bg, outline='#555555', width=1)
                canvas.tag_raise(tid)
                v.overlay_ids += [rid, tid]
            else:
                v.overlay_ids.append(tid)

        # Draw platform paths
        if _show_vp_paths or _show_cp_paths or _show_hp_paths:
            self.draw_platform_paths(_show_vp_paths, _show_cp_paths, _show_hp_paths,
                                    bs, _ox, _oy)

        # Now draw labels so they appear above the paths
        # Doors — town doors need y offset like NPCs
        if v.show_door_var.get():
            town_dy = 7 if v.mdt.is_town else 0
            for i, d in enumerate(v.mdt.doors if not v.mdt.is_town else v.mdt.town_doors):
                place(d.x, d.y + town_dy, f'D{i+1}', bg='#d8accf')

        # Monsters — respect monster toggle
        if v.show_monster_var.get():
            for i, m in enumerate(v.mdt.monsters):
                if v.view_mode.get() == 'tiles':
                    drawn = False
                    try:
                        if getattr(v, '_tile_gfx', None) and v._tile_gfx.loaded:
                            for npc_grp in ('enp1.grp', 'mman.grp', 'cman.grp', 'tman.grp'):
                                photo = v._tile_gfx.get_npc_photo(m.type, bs, grp_name=npc_grp)
                                if photo:
                                    out_w = bs * (16 // 8)
                                    out_h = bs * (24 // 8)
                                    px = _ox + m.x * bs - (out_w - bs) // 2
                                    py = _oy + m.y * bs - (out_h - bs)
                                    iid = canvas.create_image(px, py, image=photo, anchor='nw')
                                    v._photo_refs.append(photo)
                                    v.overlay_ids.append(iid)
                                    drawn = True
                                    break
                    except Exception:
                        drawn = False
                    if not drawn and _show_labels:
                        place(m.x, m.y, f'M{i+1}', bg='#DF819d')
                else:
                    if _show_labels:
                        place(m.x, m.y, f'M{i+1}', bg='#DF819d')

        # Items
        if v.show_item_var.get() and _show_labels:
            for i, it in enumerate(v.mdt.items):
                place(it.x, it.y, f'I{i+1}', bg='#6bc08c')

        # NPCs (town only)
        if v.mdt.is_town and v.show_npc_var.get():
            if v.view_mode.get() == 'tiles' and getattr(v, '_tile_gfx', None) and v._tile_gfx.loaded:
                for i, n in enumerate(v.mdt.npcs):
                    drawn = False
                    # Try loaded NPC GRP files (cman.grp, mman.grp, tman.grp)
                    for npc_grp in list(getattr(v._tile_gfx, '_npc', {}).keys()):
                        try:
                            sprite_id = getattr(v, '_npc_sprite_preview', {}).get(n.label, (n.npc_id & 0x0F) * 8 + (0 if (n.npc_id & 0x80) else 4))
                            photo = v._tile_gfx.get_npc_photo(sprite_id, bs, grp_name=npc_grp)
                            if photo:
                                out_w = bs * (16 // 8)
                                out_h = bs * (24 // 8)
                                px = _ox + n.x * bs - (out_w - bs) // 2
                                py = _oy + ((n.y or 0) + 7) * bs - (out_h - bs)
                                iid = canvas.create_image(px, py, image=photo, anchor='nw')
                                v._photo_refs.append(photo)
                                v.overlay_ids.append(iid)
                                drawn = True
                                break
                        except Exception:
                            pass
                    if not drawn and _show_labels:
                        place(n.x, (n.y or 0) + 7, f'N{i+1}', bg='#89dceb')
            else:
                # Color mode: just show labels with same y offset
                if _show_labels:
                    for i, n in enumerate(v.mdt.npcs):
                        place(n.x, (n.y or 0) + 7, f'N{i+1}', bg='#89dceb')

        # Platforms & signs — respect per-platform label toggles
        tiles_mode = (v.view_mode.get() == 'tiles')
        if not tiles_mode:
            if v.show_vp_label.get():
                for i, vp in enumerate(v.mdt.vplats):
                    x_tile = getattr(vp, 'x_init', getattr(vp, 'x', None))
                    y_init = getattr(vp, 'y_init', getattr(vp, 'y_fix', getattr(vp, 'y', 0)))
                    if x_tile is None:
                        continue
                    place(x_tile, y_init, f'VP{i+1}', bg=getattr(v, 'C_GREEN', '#a6e3a1'))
            if v.show_cp_label.get():
                for i, cp in enumerate(v.mdt.cplats):
                    x_tile = getattr(cp, 'x_init', getattr(cp, 'x', None))
                    y_init = getattr(cp, 'y_init', getattr(cp, 'y_fix', getattr(cp, 'y', 0)))
                    if x_tile is None:
                        continue
                    place(x_tile, y_init, f'CP{i+1}', bg=getattr(v, 'C_YELL', '#f9e2af'))
            if v.show_hp_label.get():
                for i, hp in enumerate(v.mdt.hplats):
                    x_init = getattr(hp, 'x_init', getattr(hp, 'x', 0))
                    if hasattr(hp, 'y') and hp.y is not None:
                        y_row = hp.y
                    else:
                        y_row = (getattr(hp, 'y_fix', 0) & 0x7F) if getattr(hp, 'y_fix', None) is not None else getattr(hp, 'y', 0)
                    place(x_init, y_row, f'HP{i+1}', bg=getattr(v, 'C_PINK', '#f5c2e7'))

        # Signs
        if v.show_sign_var.get() and _show_labels:
            for i, s in enumerate(v.mdt.signs):
                place(s.x, s.y, 'T', bg='#f9e2af')

        # Center name banner (if present)
        if getattr(v.mdt, 'name', ''):
            banner = v.mdt.name
            x = v.mdt.name_disp_x if hasattr(v.mdt, 'name_disp_x') else 0
            place(x, 0, banner, bg='#222222', fg=v.C_YELL)

    def draw_platform_paths(self, show_vp, show_cp, show_hp, bs, _ox, _oy):
        """Draw platform paths for VP, CP, and HP.
        
        Args:
            show_vp: whether to show VP paths
            show_cp: whether to show CP paths
            show_hp: whether to show HP paths
            bs: block size
            _ox: x offset for wrapping
            _oy: y offset for wrapping
        """
        v = self.viewer
        canvas = v.canvas
        
        # Common path drawing parameters
        line_w = max(2, bs // 3)
        # Reduced arrow size from (line_w, line_w*2, line_w)
        arrow_shape = (max(2, int(line_w*0.8)), max(3, int(line_w*1.5)), max(2, int(line_w*0.8)))
        
        if show_vp:
            self.draw_vp_paths(bs, _ox, _oy, line_w, arrow_shape)
        if show_cp:
            self.draw_cp_paths(bs, _ox, _oy, line_w, arrow_shape)
        if show_hp:
            self.draw_hp_paths(bs, _ox, _oy, line_w, arrow_shape)

    def draw_vp_paths(self, bs, _ox, _oy, line_w, arrow_shape):
        """Draw VP (Vertical Platform) paths."""
        v = self.viewer
        canvas = v.canvas
        
        for vp in v.mdt.vplats:
            col = getattr(vp, 'x_init', getattr(vp, 'x', None))
            row_init = getattr(vp, 'y_init', getattr(vp, 'y_fix', getattr(vp, 'y', 0)))
            if col is None:
                continue
            col = int(col) % v.mdt.map_width
            
            x = _ox + col * bs + bs // 2
            # Make the arrow end 2 tiles above the platform, with a length of 2 tiles
            # So it spans from row_init - 4 to row_init - 2
            y0 = _oy + (row_init - 4) * bs + bs // 2
            y1 = _oy + (row_init - 2) * bs + bs // 2
            
            lid = canvas.create_line(x, y0, x, y1, fill='#a6e3a1',
                                     width=line_w,
                                     arrow='both', arrowshape=arrow_shape, capstyle='round')
            v.overlay_ids.append(lid)

    def draw_cp_paths(self, bs, _ox, _oy, line_w, arrow_shape):
        """Draw CP (Collapsing Platform) paths."""
        v = self.viewer
        canvas = v.canvas
        
        for cp in v.mdt.cplats:
            col = getattr(cp, 'x_init', getattr(cp, 'x', None))
            row_init = getattr(cp, 'y_init', getattr(cp, 'y_fix', getattr(cp, 'y', 0)))
            if col is None:
                continue
            col = int(col) % v.mdt.map_width
            
            x = _ox + col * bs + bs // 2
            # Start the arrow 2 tiles below the platform, with a length of 2 tiles
            y0 = _oy + (row_init + 2) * bs + bs // 2
            y1 = _oy + (row_init + 4) * bs + bs // 2
            
            lid = canvas.create_line(x, y0, x, y1, fill='#f9e2af',
                                     width=line_w,
                                     arrow='last', arrowshape=arrow_shape, capstyle='round')
            v.overlay_ids.append(lid)

    def draw_hp_paths(self, bs, _ox, _oy, line_w, arrow_shape):
        """Draw HP (Horizontal Platform) paths."""
        v = self.viewer
        canvas = v.canvas
        
        for hp in v.mdt.hplats:
            x_init = getattr(hp, 'x_init', getattr(hp, 'x', 0))
            
            if hasattr(hp, 'y') and hp.y is not None:
                y_row = hp.y
            else:
                y_row = (getattr(hp, 'y_fix', 0) & 0x7F) if getattr(hp, 'y_fix', None) is not None else getattr(hp, 'y', 0)
            
            # Draw arrow 2 tiles above, centered at x_init
            x0 = _ox + (x_init - 1) * bs + bs // 2
            x1 = _ox + (x_init + 1) * bs + bs // 2
            y = _oy + (y_row - 2) * bs + bs // 2
            
            lid = canvas.create_line(x0, y, x1, y, fill='#f5c2e7',
                                     width=line_w,
                                     arrow='both', arrowshape=arrow_shape, capstyle='round')
            v.overlay_ids.append(lid)
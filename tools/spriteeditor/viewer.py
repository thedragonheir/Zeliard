"""
Zeliard Sprite Editor - Main application (v0.6.1 - multi-map tabbed support, merge source candidates).
"""

import os
import json
import tkinter as tk
from tkinter import filedialog, messagebox, simpledialog, ttk
from collections import Counter, defaultdict
from typing import Optional, List, Dict

from .mapctx import MapContext
from .constants import PALETTE, TOWN_HEIGHT, _MONSTER_TYPE_NAMES, get_map_type_info, _ptr_off_safe
from .models import MdtData
from .decoder import decode_mdt_file, is_town_mdt
from .widgets import Tooltip, InfoBox, ScrollFrame
from PIL import Image, ImageTk


class MDTViewer(tk.Tk):
    """Main Sprite Editor application window."""

    # Color scheme (Catppuccin-inspired)
    C_BG0 = '#0a0a10'
    C_BG1 = '#11111b'
    C_BG2 = '#181825'
    C_BG3 = '#1e1e2e'
    C_PANEL = '#24243a'
    C_SURF = '#313244'
    C_FG = '#cdd6f4'
    C_DIM = '#6c7086'
    C_BLUE = '#89b4fa'
    C_GREEN = '#a6e3a1'
    C_RED = '#f38ba8'
    C_YELL = '#f9e2af'
    C_CYAN = '#89dceb'
    C_PINK = '#f5c2e7'

    BLK_MIN = 2
    BLK_MAX = 72
    BLK_DEF = 8

    def build_palette():
        # Original Zeliard/MCGA Palette Fragment
        raw = [
            (0,0,0),(31,31,31),(31,0,0),(0,31,0),(0,31,31),(0,0,31),(31,31,0),(31,0,31),
            (31,31,31),(62,62,62),(62,31,31),(31,62,31),(31,62,62),(31,31,62),(62,62,31),(62,31,62),
            (31,0,0),(62,31,31),(62,0,0),(31,31,0),(31,31,31),(31,0,31),(62,31,0),(62,0,31),
            (0,31,0),(31,62,31),(31,31,0),(0,62,0),(0,62,31),(0,31,31),(31,62,0),(31,31,31),
            (0,31,31),(31,62,62),(31,31,31),(0,62,31),(0,62,62),(0,31,62),(31,62,31),(31,31,62),
            (0,0,31),(31,31,62),(31,0,31),(0,31,31),(0,31,62),(0,0,62),(31,31,31),(31,0,62),
            (31,31,0),(62,62,31),(62,31,0),(31,62,0),(31,62,31),(31,31,31),(62,62,0),(62,31,31),
            (31,0,31),(62,31,62),(62,0,31),(31,31,31),(31,31,62),(31,0,62),(62,31,31),(62,0,62),
        ]
        return [f"#{r*4:02x}{g*4:02x}{b*4:02x}" for r, g, b in raw]

    PALETTE_STRS = build_palette()

    def __init__(self):
        super().__init__()
        self.title('Zeliard Sprite Editor v0.6.1')
        self.geometry('1400x880')
        self.minsize(980, 660)
        self.configure(bg=self.C_BG2)

        self.block_size = self.BLK_DEF
        self.maps: Dict[int, MapContext] = {}
        self.active_map: Optional[MapContext] = None
        self.notebook = None

        # Global tile source / animation data (shared across all maps)
        self.show_overlay = tk.BooleanVar(value=False)
        self.show_tile_ids = tk.BooleanVar(value=False)
        self.hover_txt = tk.StringVar()
        self.tooltip: Optional[Tooltip] = None
        self.source_tile_candidates = None   # dict tile_id -> list of PIL Images
        self.source_tile_selections = {}     # tile_id -> chosen candidate index
        self.candidate_labels = {}           # dict (tile_id, idx) -> Label widget
        self.candidate_frames = {}           # dict (tile_id, idx) -> Frame widget (for border)
        self.show_checkerboard = tk.BooleanVar(value=True)
        self._checker_cache = {}           # size -> PIL Image
        self.CHECKER_LIGHT = '#aaaaaa'
        self.CHECKER_DARK  = '#666666'
        self.CHECKER_CELL  = 4

        # Persistence attributes (global, now less strict when merging)
        self.selections_dirty = False
        self.selections_file_path = None
        self.source_image_path = None
        self.source_tile_size = None

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ── UI Construction ───────────────────────────────────────────────────────
    def _build_ui(self):
        self._build_toolbar()
        self._build_body()

    def _build_toolbar(self):
        tb = tk.Frame(self, bg=self.C_BG0, height=46)
        tb.pack(fill='x')
        tb.pack_propagate(False)

        def btn(text, cmd, fg=None, px=10):
            b = tk.Button(
                tb, text=text, command=cmd,
                bg=self.C_SURF, fg=fg or self.C_FG,
                activebackground='#45475a', activeforeground=self.C_FG,
                relief='flat', bd=0, cursor='hand2',
                font=('Consolas', 9), padx=px, pady=7)
            b.pack(side='left', padx=2, pady=6)
            return b

        def sep():
            tk.Frame(tb, bg=self.C_SURF, width=1).pack(
                side='left', fill='y', pady=8, padx=5)

        btn('Add Map', self.add_map).pack(side='left', padx=(8, 2), pady=6)
        btn('Close Map', self.close_map, fg=self.C_RED)
        sep()
        btn('Save PNG', self.save_png, fg=self.C_GREEN)
        btn('Save TXT', self.save_txt, fg=self.C_BLUE)
        sep()

        btn('Add Source', self.load_source_image, fg=self.C_CYAN)
        btn('Load TileSheet', self.load_tilesheet, fg=self.C_CYAN)
        btn('Clear Source', self.clear_source_data, fg=self.C_RED)
        btn('Add Anim', self.load_animation, fg=self.C_YELL)
        sep()

        self.ov_btn = tk.Button(
            tb, text='Overlay  ON', command=self._toggle_overlay,
            bg='#2a2a45', fg=self.C_YELL,
            activebackground='#45475a', activeforeground=self.C_FG,
            relief='flat', bd=0, cursor='hand2',
            font=('Consolas', 9), padx=10, pady=7)
        self.ov_btn.pack(side='left', padx=2, pady=6)

        self.tid_btn = tk.Button(
            tb, text='Tile IDs  OFF', command=self._toggle_tile_ids,
            bg='#2a2a45', fg=self.C_YELL if self.show_tile_ids.get() else self.C_DIM,
            activebackground='#45475a', activeforeground=self.C_FG,
            relief='flat', bd=0, cursor='hand2',
            font=('Consolas', 9), padx=10, pady=7)
        self.tid_btn.pack(side='left', padx=2, pady=6)

        self.chk_btn = tk.Button(
            tb, text='Checker  ON', command=self._toggle_checkerboard,
            bg='#2a2a45', fg=self.C_YELL,
            activebackground='#45475a', activeforeground=self.C_FG,
            relief='flat', bd=0, cursor='hand2',
            font=('Consolas', 9), padx=10, pady=7)
        self.chk_btn.pack(side='left', padx=2, pady=6)
        sep()

        tk.Label(tb, text='Zoom', bg=self.C_BG0, fg=self.C_DIM,
                 font=('Consolas', 8)).pack(side='left', padx=(2, 0))
        btn('-', self.zoom_out, fg=self.C_RED, px=8)
        self.zoom_lbl = tk.Label(
            tb, text=f'{self.block_size}px',
            bg=self.C_BG0, fg=self.C_FG,
            font=('Consolas', 9), width=5)
        self.zoom_lbl.pack(side='left')
        btn('+', self.zoom_in, fg=self.C_GREEN, px=8)
        sep()

        btn('Save TileSheet', self.save_tilesheet, fg=self.C_PINK)
        sep()

        self.file_lbl = tk.Label(
            tb, text='',
            bg=self.C_BG0, fg=self.C_DIM, font=('Consolas', 9))
        self.file_lbl.pack(side='left', padx=8)

    # ── BODY: notebook for multiple maps ─────────────────────────────────
    def _build_body(self):
        pane = tk.PanedWindow(self, orient='horizontal',
                              bg=self.C_BG2, sashwidth=5, sashrelief='flat')
        pane.pack(fill='both', expand=True)

        left = tk.Frame(pane, bg=self.C_BG2)
        pane.add(left, minsize=650, stretch='always')

        self.placeholder = tk.Label(
            left,
            text='Add a map to begin\n\n'
                 'Level maps:  MP10.MDT  through  MPA0.MDT\n'
                 'Resources:   CMAP / STMP / BSMP / MRMP / ...',
            bg=self.C_BG1, fg=self.C_DIM,
            font=('Consolas', 12), justify='center')
        self.placeholder.pack(fill='both', expand=True)

        self.notebook = ttk.Notebook(left, style='TNotebook')
        style = ttk.Style()
        style.theme_use('default')
        style.configure('TNotebook', background=self.C_BG1, borderwidth=0)
        style.configure('TNotebook.Tab', background=self.C_SURF, foreground=self.C_FG,
                        font=('Consolas', 9), padding=[10, 2])
        style.map('TNotebook.Tab', background=[('selected', self.C_BLUE)])
        self.notebook.bind('<<NotebookTabChanged>>', self._on_tab_changed)

        status_frame = tk.Frame(left, bg=self.C_BG0)
        status_frame.pack(fill='x', side='bottom')

        self.file_lbl_status = tk.Label(
            status_frame,
            text='No map',
            bg=self.C_BG0, fg=self.C_YELL,
            font=('Consolas', 8), anchor='w', padx=10, pady=3)
        self.file_lbl_status.pack(side='left')

        sep_frame = tk.Frame(status_frame, bg=self.C_SURF, width=1)
        sep_frame.pack(side='left', fill='y', pady=2)

        self.status = tk.Label(
            status_frame, textvariable=self.hover_txt,
            bg=self.C_BG0, fg=self.C_DIM,
            font=('Consolas', 8), anchor='w', padx=10, pady=3)
        self.status.pack(side='left', fill='x', expand=True)

        right = tk.Frame(pane, bg=self.C_BG3)
        pane.add(right, minsize=315, stretch='never')
        self._build_info_panel(right)

    def _build_info_panel(self, parent: tk.Widget):
        top_frame = tk.Frame(parent, bg=self.C_BG3)
        top_frame.pack(side='top', fill='x')

        self.info_box1 = InfoBox(top_frame, 'MAP INFORMATION', self.C_SURF, self.C_BLUE)
        self.info_box1.pack(fill='x', padx=5, pady=3)

        self.info_box2 = InfoBox(top_frame, 'HEADER INFORMATION', self.C_SURF, self.C_BLUE)
        self.info_box2.pack(fill='x', padx=5, pady=3)

        self.info_box4 = InfoBox(top_frame, 'TILE INFORMATION', self.C_SURF, self.C_BLUE)
        self.info_box4.pack(fill='x', padx=5, pady=3)

        self.info_txt1 = tk.Text(self.info_box1._content, bg=self.C_PANEL, fg=self.C_FG,
                                font=('Consolas', 8), relief='flat', state='disabled',
                                width=40, wrap='none', selectbackground=self.C_SURF, height=5)
        self.info_box1.set_text_widget(self.info_txt1)

        self.info_txt2 = tk.Text(self.info_box2._content, bg=self.C_PANEL, fg=self.C_FG,
                                font=('Consolas', 8), relief='flat', state='disabled',
                                width=40, wrap='none', selectbackground=self.C_SURF, height=5)
        self.info_box2.set_text_widget(self.info_txt2)

        self.info_txt4 = tk.Text(self.info_box4._content, bg=self.C_PANEL, fg=self.C_FG,
                                font=('Consolas', 8), relief='flat', state='disabled',
                                width=40, wrap='none', selectbackground=self.C_SURF, height=5)
        self.info_box4.set_text_widget(self.info_txt4)

        tags = [
            ('k', self.C_BLUE), ('v', self.C_FG), ('d', self.C_DIM),
            ('g', self.C_GREEN), ('r', self.C_RED), ('y', self.C_YELL),
            ('c', self.C_CYAN), ('p', self.C_PINK), ('s', self.C_SURF),
        ]
        for txt in [self.info_txt1, self.info_txt2, self.info_txt4]:
            for tag, color in tags:
                txt.tag_config(tag, foreground=color)
            txt.tag_config('sec', foreground=self.C_FG, background=self.C_SURF)
            txt.tag_config('leg_d', foreground='#ffffff', background=self.C_BG0)
            txt.tag_config('leg_m', foreground='#ffffff', background=self.C_BG0)
            txt.tag_config('leg_i', foreground='#ffffff', background=self.C_BG0)

        candidate_frame = tk.Frame(parent, bg=self.C_BG3)
        candidate_frame.pack(side='bottom', fill='both', expand=True)

        self.info_box5 = InfoBox(candidate_frame, 'TILE CANDIDATES', self.C_SURF, self.C_BLUE)
        self.info_box5.pack(fill='both', expand=True, padx=5, pady=(3, 0))

    # ── Map management ────────────────────────────────────────────────────────
    def add_map(self):
        path = filedialog.askopenfilename(
            title='Open MDT File',
            filetypes=[('MDT map files', '*.mdt *.MDT'), ('All files', '*.*')])
        if not path:
            return
        try:
            raw_data = open(path, 'rb').read()
            mdt = decode_mdt_file(path)
            ctx = MapContext(path, mdt, raw_data)

            if self.placeholder and self.placeholder.winfo_ismapped():
                self.placeholder.pack_forget()
            if not self.notebook.winfo_ismapped():
                self.notebook.pack(fill='both', expand=True)

            tab_frame = tk.Frame(self.notebook, bg=self.C_BG1)
            self.notebook.add(tab_frame, text=os.path.basename(path))

            canvas = tk.Canvas(tab_frame, bg=self.C_BG1,
                               highlightthickness=0, cursor='crosshair')
            vsb = tk.Scrollbar(tab_frame, orient='vertical',
                               command=canvas.yview,
                               bg=self.C_SURF, troughcolor=self.C_BG2, width=10)
            hsb = tk.Scrollbar(tab_frame, orient='horizontal',
                               command=canvas.xview,
                               bg=self.C_SURF, troughcolor=self.C_BG2, width=10)
            canvas.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

            vsb.pack(side='right', fill='y')
            hsb.pack(side='bottom', fill='x')
            canvas.pack(fill='both', expand=True)

            canvas.bind('<Configure>', lambda e, c=ctx: self._update_canvas_scrollbars(c))
            canvas.bind('<Motion>', self._on_motion)
            canvas.bind('<Leave>', self._on_leave)
            canvas.bind('<MouseWheel>', self._on_wheel)
            canvas.bind('<Shift-MouseWheel>', self._on_shift_wheel)
            canvas.bind('<Button-4>', self._on_wheel)
            canvas.bind('<Button-5>', self._on_wheel)
            canvas.bind('<Shift-Button-4>', self._on_shift_wheel)
            canvas.bind('<Shift-Button-5>', self._on_shift_wheel)

            ctx.canvas = canvas
            ctx.vsb = vsb
            ctx.hsb = hsb

            tab_id = self.notebook.index('end') - 1
            self.maps[tab_id] = ctx

            self.notebook.select(tab_id)
        except Exception as e:
            messagebox.showerror('Load Error', str(e))

    def close_map(self):
        if not self.active_map or not self.notebook:
            return
        selected = self.notebook.select()
        if not selected:
            return
        tab_id = self.notebook.index(selected)
        if tab_id in self.maps:
            del self.maps[tab_id]
        self.notebook.forget(tab_id)

        # Rebuild map indices
        self.maps = {}
        for i in range(self.notebook.index('end')):
            tab_widget = self.notebook.nametowidget(self.notebook.tabs()[i])
            for child in tab_widget.winfo_children():
                if isinstance(child, tk.Canvas) and hasattr(child, 'ctx'):
                    self.maps[i] = child.ctx
                    break

        if not self.maps:
            self.notebook.pack_forget()
            self.placeholder.pack(fill='both', expand=True)
            self.active_map = None
            self._clear_info()
        else:
            self.notebook.select(0)

    def _on_tab_changed(self, event):
        selected = self.notebook.select()
        if not selected:
            self.active_map = None
            self._clear_info()
            return
        tab_id = self.notebook.index(selected)
        ctx = self.maps.get(tab_id)
        if ctx:
            self.active_map = ctx
            fname = os.path.basename(ctx.path)
            self.title(f'Zeliard Sprite Editor — {fname}')
            self.file_lbl.config(text=fname, fg=self.C_FG)
            self.file_lbl_status.config(text=fname)
            if self.tooltip is None:
                self.tooltip = Tooltip(self)
            self._draw_map(ctx)
            self._update_info(ctx)

    def _clear_info(self):
        for txt in [self.info_txt1, self.info_txt2, self.info_txt4]:
            txt.config(state='normal')
            txt.delete('1.0', 'end')
            txt.config(state='disabled')
        self.file_lbl.config(text='', fg=self.C_DIM)
        self.file_lbl_status.config(text='No map')
        self.title('Zeliard Sprite Editor v0.6.1')

    # ── Drawing helpers ────────────────────────────────────────────────────
    def get_tile_image(self, ctx: MapContext, tile_idx):
        use_checker = self.show_checkerboard.get()
        cache_key = (tile_idx, self.block_size, use_checker)
        if cache_key in ctx.tile_images:
            return ctx.tile_images[cache_key]

        if not ctx.mdt.gfx or tile_idx >= len(ctx.mdt.gfx):
            return None

        raw_pixels = ctx.mdt.gfx[tile_idx]
        img = Image.new('RGBA', (8, 8), (0, 0, 0, 0))
        for i, p_idx in enumerate(raw_pixels):
            if p_idx == -1:
                continue
            color_hex = self.PALETTE_STRS[p_idx]
            x, y = i % 8, i // 8
            rgb = tuple(int(color_hex[j:j+2], 16) for j in (1, 3, 5))
            img.putpixel((x, y), rgb + (255,))

        bw = self.block_size
        scaled = img.resize((bw, bw), Image.NEAREST)
        if use_checker:
            scaled = self._composite_over_checker(scaled, bw)

        photo = ImageTk.PhotoImage(scaled)
        ctx.tile_images[cache_key] = photo
        return photo

    def _draw_map(self, ctx: MapContext):
        ctx.canvas.delete("all")
        bw = self.block_size
        mw, mh = ctx.mdt.map_width, ctx.mdt.map_height
        use_checker = self.show_checkerboard.get()

        for y in range(mh):
            for x in range(mw):
                tile_idx = ctx.mdt.grid[y][x]
                x1, y1 = x * bw, y * bw

                if self.source_tile_candidates and tile_idx in self.source_tile_candidates:
                    sel_idx = self.source_tile_selections.get(tile_idx, 0)
                    if sel_idx < len(self.source_tile_candidates[tile_idx]):
                        src_img = self.source_tile_candidates[tile_idx][sel_idx]
                        cache_key = (tile_idx, bw, sel_idx, use_checker)
                        if cache_key not in ctx.source_tile_cache:
                            scaled = src_img.resize((bw, bw), Image.NEAREST)
                            if use_checker:
                                scaled = self._composite_over_checker(scaled, bw)
                            photo = ImageTk.PhotoImage(scaled)
                            ctx.source_tile_cache[cache_key] = photo
                        tile_img = ctx.source_tile_cache[cache_key]
                        ctx.canvas.create_image(x1, y1, image=tile_img, anchor='nw')
                        continue

                tile_img = self.get_tile_image(ctx, tile_idx)
                if tile_img:
                    ctx.canvas.create_image(x1, y1, image=tile_img, anchor='nw')
                else:
                    ctx.canvas.create_rectangle(x1, y1, x1+bw, y1+bw, fill='gray')

        ctx.canvas.config(scrollregion=(0, 0, mw * bw, mh * bw))
        self._draw_overlays(ctx)
        self._draw_tile_ids(ctx)
        self._update_canvas_scrollbars(ctx)

    def _draw_overlays(self, ctx: MapContext):
        for iid in ctx.overlay_ids:
            ctx.canvas.delete(iid)
        ctx.overlay_ids = []
        mdt = ctx.mdt
        if not mdt or not self.show_overlay.get():
            return
        bs = self.block_size
        fs = max(6, min(10, bs - 1))
        font = ('Consolas', fs, 'bold')
        pad = max(1, bs // 6)
        def place(x, y, text):
            cx = x * bs + bs // 2
            cy = y * bs + bs // 2
            tid = ctx.canvas.create_text(cx, cy, text=text, fill='#ffffff', font=font, anchor='center')
            bb = ctx.canvas.bbox(tid)
            if bb:
                rid = ctx.canvas.create_rectangle(bb[0]-pad, bb[1]-pad, bb[2]+pad, bb[3]+pad,
                                                  fill='#000000', outline='#555555', width=1)
                ctx.canvas.tag_raise(tid)
                ctx.overlay_ids += [rid, tid]
            else:
                ctx.overlay_ids.append(tid)
        for d in mdt.doors: place(d.x, d.y, d.label)
        for m in mdt.monsters: place(m.x, m.y, m.label)
        for i in mdt.items: place(i.x, i.y, i.label)
        if mdt.is_town:
            ground_row = TOWN_HEIGHT - 1
            for td in mdt.town_doors: place(td.x, ground_row, td.label)
            for npc in mdt.npcs: place(npc.x, ground_row, npc.label)

    def _draw_tile_ids(self, ctx: MapContext):
        for iid in ctx.tile_id_overlay_ids:
            ctx.canvas.delete(iid)
        ctx.tile_id_overlay_ids = []
        mdt = ctx.mdt
        if not mdt or not self.show_tile_ids.get():
            return
        bs = self.block_size
        fs = max(4, bs // 4)
        font = ('Consolas', fs, 'bold')
        mw, mh = mdt.map_width, mdt.map_height
        for y in range(mh):
            for x in range(mw):
                tile_idx = mdt.grid[y][x]
                tid = ctx.canvas.create_text(x*bs+2, y*bs+2, text=str(tile_idx),
                                             fill='white', font=font, anchor='nw')
                ctx.tile_id_overlay_ids.append(tid)

    def _update_canvas_scrollbars(self, ctx: MapContext, event=None):
        canvas = ctx.canvas
        canvas_width = canvas.winfo_width()
        canvas_height = canvas.winfo_height()
        map_full_w = ctx.mdt.map_width * self.block_size
        map_full_h = ctx.mdt.map_height * self.block_size

        if map_full_h <= canvas_height:
            ctx.vsb.pack_forget()
        else:
            ctx.vsb.pack(side='right', fill='y')

        if map_full_w <= canvas_width:
            ctx.hsb.pack_forget()
        else:
            ctx.hsb.pack(side='bottom', fill='x')

    # ── Event handlers ─────────────────────────────────────────────────────
    def _on_motion(self, event):
        ctx = self.active_map
        if not ctx:
            return
        canvas = ctx.canvas
        bs = self.block_size
        cx = canvas.canvasx(event.x)
        cy = canvas.canvasy(event.y)
        col = int(cx // bs)
        row = int(cy // bs)
        mdt = ctx.mdt
        mw, mh = mdt.map_width, mdt.map_height
        if 0 <= col < mw and 0 <= row < mh:
            tile = mdt.grid[row][col]
            self.hover_txt.set(f'  col:{col:4d}  row:{row:3d}  tile:{tile:2d}   {PALETTE[tile % 64]}')
        else:
            self.hover_txt.set('')
        entity = self._hit_entity(ctx, cx, cy)
        if entity and self.tooltip:
            rx = self.winfo_pointerx()
            ry = self.winfo_pointery()
            self.tooltip.show(rx, ry, self._make_tip(entity))
        elif self.tooltip:
            self.tooltip.hide()

    def _on_leave(self, event):
        self.hover_txt.set('')
        if self.tooltip:
            self.tooltip.hide()

    def _on_wheel(self, event):
        ctx = self.active_map
        if not ctx:
            return
        if event.state & 0x4:
            if event.delta > 0 or event.num == 4:
                self.zoom_in()
            else:
                self.zoom_out()
            return
        if event.num == 4:
            ctx.canvas.yview_scroll(-3, 'units')
        elif event.num == 5:
            ctx.canvas.yview_scroll(3, 'units')
        else:
            ctx.canvas.yview_scroll(-1 * (event.delta // 120), 'units')

    def _on_shift_wheel(self, event):
        ctx = self.active_map
        if not ctx:
            return
        if event.state & 0x4:
            return
        if event.num == 4:
            ctx.canvas.xview_scroll(-3, 'units')
        elif event.num == 5:
            ctx.canvas.xview_scroll(3, 'units')
        else:
            ctx.canvas.xview_scroll(-1 * (event.delta // 120), 'units')

    def _hit_entity(self, ctx: MapContext, cx, cy):
        mdt = ctx.mdt
        if not mdt or not self.show_overlay.get():
            return None
        bs = self.block_size
        thresh = (max(bs, 8) * 0.9) ** 2
        best = None
        best_d = thresh
        is_town = mdt.is_town
        ground_row = TOWN_HEIGHT - 1 if is_town else 0
        all_entities = list(mdt.doors) + list(mdt.monsters) + list(mdt.items)
        if is_town:
            all_entities.extend(mdt.town_doors)
            all_entities.extend(mdt.npcs)
        for e in all_entities:
            ex = e.x * bs + bs // 2
            ey = (ground_row if is_town else e.y) * bs + bs // 2
            d = (cx - ex) ** 2 + (cy - ey) ** 2
            if d < best_d:
                best_d = d
                best = e
        return best

    def _make_tip(self, e) -> str:
        lbl = e.label
        line = '-' * 30
        tip = [f'  {lbl}', f'  {line}']
        if lbl.startswith('D'):
            if hasattr(e, 'door_type'):
                tip += [f'  Type      {e.dtype}', f'  Column X  {e.x}', f'  Door type {e.door_type:#04x}']
            else:
                tip += [f'  Type      {e.dtype}', f'  From      ({e.x}, {e.y})',
                        f'  Dest map  {e.dest}', f'  To        ({e.x1}, {"town" if e.is_town else e.y1})',
                        f'  Lion Key  {"required" if e.needs_key else "not required"}',
                        f'  flags     {e.flags:#04x}   flags2  {e.flags2:#04x}',
                        f'  map_id    {e.map_id:#04x}   unk  {e.unk:#06x}']
        elif lbl.startswith('N'):
            tip += [f'  NPC id    {e.npc_id:#04x}  ({e.npc_id})', f'  Column X  {e.x}']
        elif lbl.startswith('M'):
            name = _MONSTER_TYPE_NAMES.get(e.type, '')
            name_str = f' ({name})' if name else ''
            tip += [f'  Type      {e.type:#04x}{name_str}', f'  Position  ({e.x}, {e.y})',
                    f'  Spawn     ({e.spwn_x}, {e.spwn_y})', f'  SType     {e.spwn_type:#04x}',
                    f'  Act       {e.act:#04x}', f'  Raw:  {e.raw}']
        elif lbl.startswith('I'):
            tip += [f'  Type      {e.type:#04x}  ({e.type})', f'  Position  ({e.x}, {e.y})',
                    f'  Spawn     ({e.spwn_x}, {e.spwn_y})', f'  Raw:  {e.raw}']
        else:
            tip.append('  Unknown entity')
        return '\n'.join(tip)

    # ── Zoom ────────────────────────────────────────────────────────────────
    def zoom_in(self):
        if self.block_size < self.BLK_MAX:
            self.block_size = min(self.block_size + 2, self.BLK_MAX)
            self.zoom_lbl.config(text=f'{self.block_size}px')
            if self.active_map:
                for ctx in self.maps.values():
                    ctx.tile_images.clear()
                    ctx.source_tile_cache.clear()
                self._draw_map(self.active_map)

    def zoom_out(self):
        if self.block_size > self.BLK_MIN:
            self.block_size = max(self.block_size - 2, self.BLK_MIN)
            self.zoom_lbl.config(text=f'{self.block_size}px')
            if self.active_map:
                for ctx in self.maps.values():
                    ctx.tile_images.clear()
                    ctx.source_tile_cache.clear()
                self._draw_map(self.active_map)

    # ── Toggle overlays/ids ────────────────────────────────────────────────
    def _toggle_overlay(self):
        self.show_overlay.set(not self.show_overlay.get())
        on = self.show_overlay.get()
        self.ov_btn.config(text=f'Overlay  {"ON " if on else "OFF"}',
                           fg=self.C_YELL if on else self.C_DIM)
        if self.active_map:
            self._draw_overlays(self.active_map)

    def _toggle_tile_ids(self):
        self.show_tile_ids.set(not self.show_tile_ids.get())
        on = self.show_tile_ids.get()
        self.tid_btn.config(text=f'Tile IDs  {"ON " if on else "OFF"}',
                            fg=self.C_YELL if on else self.C_DIM)
        if self.active_map:
            self._draw_tile_ids(self.active_map)

    # ── Info Panel Update ──────────────────────────────────────────────────
    def _update_info(self, ctx: MapContext):
        m = ctx.mdt
        d = ctx.raw_data
        if not m or not d:
            return
        mw, mh = m.map_width, m.map_height
        total = mw * mh
        flat = [m.grid[r][c] for r in range(mh) for c in range(mw)]
        cnt = Counter(flat)
        fname = os.path.basename(ctx.path) if ctx.path else ''
        mtype = get_map_type_info(ctx.path) if ctx.path else 'Unknown'

        for txt in [self.info_txt1, self.info_txt2, self.info_txt4]:
            txt.config(state='normal')
            txt.delete('1.0', 'end')

        T = self.info_txt1
        def kv(key, val, vt='v'):
            T.insert('end', f'  {key:<18}', 'k')
            T.insert('end', f'{val}\n', vt)
        def sep():
            T.insert('end', '  ' + '-' * 34 + '\n', 's')
        def sec(title):
            T.insert('end', f'\n  [ {title} ]\n', 'sec')

        sec('File Info')
        kv('Filename', fname)
        kv('File size', f'{len(d):,} bytes')
        kv('Map type', mtype)
        if m.is_town and m.town_name:
            kv('Town name', m.town_name, 'y')
        sep()

        sec('Map Structure')
        kv('Width', f'{mw} tiles')
        height_note = '(fixed — town)' if m.is_town else '(fixed)'
        kv('Height', f'{mh} tiles  {height_note}')
        kv('Total tiles', f'{total:,}')
        kv('Unique tiles', f'{len(cnt)} types')
        sep()

        if m.is_town:
            sec('Map Storage')
            kv('Format', 'Unpacked  (column-major)')
            kv('Map offset', '+0x17')
            kv('Map bytes', f'{mw * TOWN_HEIGHT}')
        else:
            cbytes = max(0, m.consumed_si - 0x1B)
            sec('Compression')
            kv('Packed bytes', f'{cbytes}')
            ratio = cbytes / total if total else 0
            kv('Bytes / tile', f'{ratio:.3f}')
            saving = (1 - ratio) * 100 if ratio < 1 else 0
            kv('Space saved', f'{saving:.1f}%', 'g' if saving > 50 else 'v')

        T = self.info_txt2
        def ptr_row(lbl, ptr):
            off = _ptr_off_safe(ptr, len(d))
            s = (f'{ptr:#06x}  ->  +{off:#06x}' if off is not None
                 else f'{ptr:#06x}  (invalid)')
            kv(lbl, s, 'c')

        if m.is_town:
            sec('Town Header Pointers  (runtime -> file offset)')
            ptr_row('Descriptor', m.desc_ptr)
            kv('Width (raw)', f'{m.map_width}  tiles', 'y')
            ptr_row('Name info', m.name_ptr)
            ptr_row('Doors', m.doors_ptr)
            ptr_row('NPC texts', m.npc_texts_ptr)
            ptr_row('NPCs', m.npc_ptr)
            kv('Map data', '+0x17  (unpacked tiles)', 'c')
        else:
            sec('Header Pointers  (runtime -> file offset)')
            ptr_row('Descriptor', m.desc_ptr)
            ptr_row('V-Platforms', m.vplat_ptr)
            ptr_row('C-Platforms', m.cplat_ptr)
            ptr_row('H-Platforms', m.hplat_ptr)
            ptr_row('Doors', m.doors_ptr)
            ptr_row('Achv-Items', m.achv_ptr)
            ptr_row('Name renderer', m.name_ptr)
            ptr_row('Monsters', m.monsters_ptr)
            ptr_row('Signs', m.signs_ptr)
            ptr_row('Map end', m.map_end_ptr)
            kv('Level', str(m.level), 'y')
            kv('Tear X', f'{m.tear_x:#06x}  ({m.tear_x})', 'y')
            kv('Tear Y', f'{m.tear_y:#04x}  ({m.tear_y})', 'y')

        sep()
        sec('Raw Header  +0x00..+0x1A')
        for o in range(0, min(0x1B, len(d)), 4):
            chunk = d[o:o + 4]
            hexs = ' '.join(f'{b:02X}' for b in chunk)
            ascs = ''.join(chr(b) if 0x20 <= b < 0x7F else '.' for b in chunk)
            T.insert('end', f'  +{o:02X}  {hexs:<11}  {ascs}\n', 'd')

        T = self.info_txt4
        sec('Tile Frequency  Top 15')
        for tile, count in cnt.most_common(15):
            pct = count / total * 100
            T.insert('end', f'  #{tile:2d}  {count:6d}  {pct:5.1f}%  {PALETTE[tile % 64]}\n', 'd')

        for txt in [self.info_txt1, self.info_txt2, self.info_txt4]:
            txt.config(state='disabled')

    # ── Source Loading (GLOBAL with MERGE) ─────────────────────────────────
    def load_source_image(self):
        if not self.active_map:
            messagebox.showwarning('Warning', 'Add a map first.')
            return
        path = filedialog.askopenfilename(
            title='Open Source Map Image',
            filetypes=[('PNG files', '*.png'), ('All files', '*')])
        if not path:
            return
        ts = simpledialog.askinteger(
            'Tile Size', 'Enter tile pixel size in the source image:',
            initialvalue=getattr(self, 'source_tile_size', 8), minvalue=1, parent=self)
        if ts is None:
            return
        try:
            src_img = Image.open(path)
            # Validate against active map dimensions
            mw, mh = self.active_map.mdt.map_width, self.active_map.mdt.map_height
            expected_w = mw * ts
            expected_h = mh * ts
            if src_img.size != (expected_w, expected_h):
                messagebox.showerror('Size Mismatch',
                                     f'Image must be exactly {expected_w}x{expected_h} pixels.\n'
                                     f'(map {mw}x{mh} × tile size {ts})')
                return

            # Build candidates from the active map's grid (only new entries)
            new_candidates = defaultdict(list)
            seen = defaultdict(set)
            for row in range(mh):
                for col in range(mw):
                    tid = self.active_map.mdt.grid[row][col]
                    box = (col * ts, row * ts, (col+1) * ts, (row+1) * ts)
                    tile_img = src_img.crop(box)
                    data = tile_img.tobytes()
                    if data not in seen[tid]:
                        seen[tid].add(data)
                        new_candidates[tid].append(tile_img)

            # MERGE with existing global candidates
            if self.source_tile_candidates is None:
                self.source_tile_candidates = dict(new_candidates)
                self.source_tile_selections = {}
                for tid in self.source_tile_candidates:
                    self.source_tile_selections[tid] = 0
            else:
                for tid, tiles in new_candidates.items():
                    if tid not in self.source_tile_candidates:
                        self.source_tile_candidates[tid] = []
                    for img in tiles:
                        # avoid exact duplicates
                        if not any(img.tobytes() == e.tobytes() for e in self.source_tile_candidates[tid]):
                            self.source_tile_candidates[tid].append(img)
                # Ensure selections are still valid
                for tid in list(self.source_tile_selections.keys()):
                    if tid in self.source_tile_candidates:
                        if self.source_tile_selections[tid] >= len(self.source_tile_candidates[tid]):
                            self.source_tile_selections[tid] = 0
                    else:
                        del self.source_tile_selections[tid]
                # Add missing selections for new tiles
                for tid in self.source_tile_candidates:
                    if tid not in self.source_tile_selections:
                        self.source_tile_selections[tid] = 0

            # Update global metadata (use the latest source for info only)
            self.source_image_path = path
            self.source_tile_size = ts
            self.selections_dirty = True
            # Disable persistence when multiple sources are mixed (path mismatch)
            self.selections_file_path = None

            # Clear per-map caches and redraw
            for ctx in self.maps.values():
                ctx.tile_images.clear()
                ctx.source_tile_cache.clear()
            self._build_tile_candidates_ui()
            if self.active_map:
                self._draw_map(self.active_map)

        except Exception as e:
            messagebox.showerror('Load Error', str(e))

    def load_tilesheet(self):
        if not self.active_map:
            messagebox.showwarning('Warning', 'Add a map first.')
            return
        path = filedialog.askopenfilename(
            title='Open Tilesheet Image',
            filetypes=[('PNG files', '*.png'), ('All files', '*')])
        if not path:
            return
        ts = simpledialog.askinteger(
            'Tile Size', 'Pixel size of each tile in the sheet:',
            initialvalue=getattr(self, 'source_tile_size', 8), minvalue=1, parent=self)
        if ts is None:
            return
        cols = simpledialog.askinteger(
            'Columns', 'Number of tile columns in the sheet:',
            initialvalue=16, minvalue=1, parent=self)
        if cols is None:
            return
        try:
            sheet_img = Image.open(path)
            w, h = sheet_img.size
            if w % ts != 0 or h % ts != 0:
                messagebox.showerror('Size Mismatch', f'Width/height must be multiples of tile size.')
                return
            tiles_across = w // ts
            if tiles_across != cols:
                cols = tiles_across
            tiles_down = h // ts
            tiles = []
            for row in range(tiles_down):
                for col in range(cols):
                    left = col * ts
                    upper = row * ts
                    tile_img = sheet_img.crop((left, upper, left + ts, upper + ts))
                    tiles.append(tile_img)

            # Replace global candidates with this tilesheet (full set)
            self.source_tile_candidates = {}
            self.source_tile_selections = {}
            all_tile_ids = set()
            for ctx in self.maps.values():
                for row in ctx.mdt.grid:
                    for tid in row:
                        all_tile_ids.add(tid)
            for tid in all_tile_ids:
                if tid < len(tiles):
                    self.source_tile_candidates[tid] = [tiles[tid]]
                    self.source_tile_selections[tid] = 0

            self.source_image_path = path
            self.source_tile_size = ts
            self.selections_dirty = True
            self._load_selections_if_match()  # try to load saved selections for this tilesheet

            for ctx in self.maps.values():
                ctx.tile_images.clear()
                ctx.source_tile_cache.clear()
            self._build_tile_candidates_ui()
            if self.active_map:
                self._draw_map(self.active_map)

        except Exception as e:
            messagebox.showerror('Load Error', str(e))

    def load_animation(self):
        if not self.active_map:
            messagebox.showwarning('Warning', 'Add a map first.')
            return
        path = filedialog.askopenfilename(
            title='Open Animation PNG (4 frames horizontally)',
            filetypes=[('PNG files', '*.png'), ('All files', '*')])
        if not path:
            return
        ts = simpledialog.askinteger(
            'Frame Size', 'Pixel size of each frame (width & height):',
            initialvalue=getattr(self, 'source_tile_size', 8), minvalue=1, parent=self)
        if ts is None:
            return
        start_id = simpledialog.askinteger(
            'Starting Tile ID', 'First tile ID to assign the animation:',
            initialvalue=0, minvalue=0, parent=self)
        if start_id is None:
            return
        try:
            anim_img = Image.open(path)
            w, h = anim_img.size
            expected_w = ts * 4
            if w != expected_w or h != ts:
                messagebox.showerror('Size Mismatch',
                                     f'Animation image must be exactly {expected_w}x{ts} pixels.')
                return
            frames = []
            for i in range(4):
                frame = anim_img.crop((i * ts, 0, (i + 1) * ts, ts))
                frames.append(frame)

            if self.source_tile_candidates is None:
                self.source_tile_candidates = {}
                self.source_tile_selections = {}
            for offset, tid in enumerate(range(start_id, start_id + 4)):
                if tid not in self.source_tile_candidates:
                    self.source_tile_candidates[tid] = []
                self.source_tile_candidates[tid].append(frames[offset])
                self.source_tile_selections[tid] = len(self.source_tile_candidates[tid]) - 1

            self.selections_dirty = True
            for ctx in self.maps.values():
                ctx.tile_images.clear()
                ctx.source_tile_cache.clear()
            self._build_tile_candidates_ui()
            if self.active_map:
                self._draw_map(self.active_map)

        except Exception as e:
            messagebox.showerror('Load Error', str(e))

    def clear_source_data(self):
        self._clear_source_data()
        for ctx in self.maps.values():
            ctx.tile_images.clear()
            ctx.source_tile_cache.clear()
        if self.active_map:
            self._draw_map(self.active_map)

    def _clear_source_data(self):
        self.source_tile_candidates = None
        self.source_tile_selections = {}
        self.candidate_labels = {}
        self.candidate_frames = {}
        self.source_image_path = None
        self.source_tile_size = None
        self.selections_dirty = False
        self.selections_file_path = None
        if hasattr(self, 'info_box5'):
            for w in self.info_box5._content.winfo_children():
                w.destroy()

    # ── Persistence (tied to tilesheet/source path; disabled on merge) ─────
    def _get_selections_file_path(self):
        if not self.source_image_path:
            return None
        base = os.path.splitext(self.source_image_path)[0]
        return base + '_tile_selections.json'

    def _load_selections_if_match(self):
        path = self._get_selections_file_path()
        self.selections_file_path = path
        if not path or not os.path.exists(path):
            return
        try:
            with open(path, 'r') as f:
                data = json.load(f)
            if data.get('source_file') != self.source_image_path or \
               data.get('tile_size') != self.source_tile_size:
                return
            saved = {int(k): v for k, v in data.get('selections', {}).items()}
            for tid in saved:
                if tid in self.source_tile_candidates and \
                   saved[tid] < len(self.source_tile_candidates[tid]):
                    self.source_tile_selections[tid] = saved[tid]
            self.selections_dirty = False
        except Exception:
            pass

    def _save_selections(self):
        path = self.selections_file_path
        if not path:
            return
        data = {
            'source_file': self.source_image_path,
            'tile_size': self.source_tile_size,
            'selections': {str(k): v for k, v in self.source_tile_selections.items()}
        }
        with open(path, 'w') as f:
            json.dump(data, f, indent=2)
        self.selections_dirty = False

    def _on_close(self):
        if self.selections_dirty:
            answer = messagebox.askyesnocancel(
                "Unsaved tile selections",
                "You have modified tile selections. Save before closing?")
            if answer:
                self._save_selections()
                self.destroy()
            elif answer is False:
                self.destroy()
        else:
            self.destroy()

    # ── Right panel: tile candidates (global) ──────────────────────────────
    def _build_tile_candidates_ui(self):
        content = self.info_box5._content
        for w in content.winfo_children():
            w.destroy()
        if not self.source_tile_candidates:
            return

        outer = tk.Frame(content, bg=self.C_BG2)
        outer.pack(fill='both', expand=True)

        v_canvas = tk.Canvas(outer, bg=self.C_BG2, highlightthickness=0)
        v_scroll = tk.Scrollbar(outer, orient='vertical', command=v_canvas.yview,
                                bg=self.C_SURF, troughcolor=self.C_BG2)
        h_scroll = tk.Scrollbar(outer, orient='horizontal', command=v_canvas.xview,
                                bg=self.C_SURF, troughcolor=self.C_BG2)
        v_canvas.configure(yscrollcommand=v_scroll.set, xscrollcommand=h_scroll.set)

        v_scroll.pack(side='right', fill='y')
        h_scroll.pack(side='bottom', fill='x')
        v_canvas.pack(side='left', fill='both', expand=True)

        inner = tk.Frame(v_canvas, bg=self.C_BG2)
        v_canvas.create_window((0, 0), window=inner, anchor='nw')

        def on_inner_configure(event):
            v_canvas.configure(scrollregion=v_canvas.bbox('all'))
        inner.bind('<Configure>', on_inner_configure)

        def _vert_wheel(event):
            if event.num == 4:
                v_canvas.yview_scroll(-3, 'units')
            elif event.num == 5:
                v_canvas.yview_scroll(3, 'units')
            else:
                v_canvas.yview_scroll(-1 * (event.delta // 120), 'units')

        def _horiz_wheel(event):
            if event.num == 4:
                v_canvas.xview_scroll(-3, 'units')
            elif event.num == 5:
                v_canvas.xview_scroll(3, 'units')
            else:
                v_canvas.xview_scroll(-1 * (event.delta // 120), 'units')

        def _bind_recursive(widget):
            widget.bind('<MouseWheel>', _vert_wheel)
            widget.bind('<Shift-MouseWheel>', _horiz_wheel)
            widget.bind('<Button-4>', _vert_wheel)
            widget.bind('<Button-5>', _vert_wheel)
            widget.bind('<Shift-Button-4>', _horiz_wheel)
            widget.bind('<Shift-Button-5>', _horiz_wheel)
            for child in widget.winfo_children():
                _bind_recursive(child)

        _bind_recursive(outer)
        _bind_recursive(v_canvas)

        self.candidate_labels = {}
        self.candidate_frames = {}

        for tile_id in sorted(self.source_tile_candidates.keys()):
            cands = self.source_tile_candidates[tile_id]
            section = tk.Frame(inner, bg=self.C_BG2)
            section.pack(fill='x', padx=5, pady=2)

            tk.Label(section, text=f'Tile {tile_id}',
                    fg=self.C_FG, bg=self.C_BG2,
                    font=('Consolas', 9)).pack(side='left', padx=5)

            row = tk.Frame(section, bg=self.C_BG2)
            row.pack(side='left', fill='x')

            for i, img in enumerate(cands):
                frame = tk.Frame(row, bg=self.C_BG2, highlightthickness=0,
                                highlightbackground='white', relief='flat')
                frame.pack(side='left', padx=2)
                thumb = img.copy()
                thumb.thumbnail((24, 24), Image.NEAREST)
                photo = ImageTk.PhotoImage(thumb)
                lbl = tk.Label(frame, image=photo, bg=self.C_BG2, borderwidth=0)
                lbl.image = photo
                lbl.pack()
                self.candidate_labels[(tile_id, i)] = lbl
                self.candidate_frames[(tile_id, i)] = frame

                lbl.bind('<Button-1>', lambda e, tid=tile_id, idx=i: self._select_candidate(tid, idx))
                frame.bind('<Button-1>', lambda e, tid=tile_id, idx=i: self._select_candidate(tid, idx))

                _bind_recursive(frame)
                _bind_recursive(lbl)

                if self.source_tile_selections.get(tile_id) == i:
                    frame.config(highlightthickness=1, relief='solid')

        inner.update_idletasks()
        v_canvas.configure(scrollregion=v_canvas.bbox('all'))

    def _select_candidate(self, tile_id, idx):
        if self.source_tile_selections.get(tile_id) == idx:
            return
        self.source_tile_selections[tile_id] = idx
        self.selections_dirty = True
        for (tid, i), frame in self.candidate_frames.items():
            if tid == tile_id:
                frame.config(highlightthickness=1 if i == idx else 0,
                             relief='solid' if i == idx else 'flat')
        if self.active_map:
            self.active_map.tile_images.clear()
            self.active_map.source_tile_cache.clear()
            self._draw_map(self.active_map)

    # ── Save Functions ──────────────────────────────────────────────────────
    def _get_tile_image_for_export(self, ctx: MapContext, tile_id, bs):
        if self.source_tile_candidates and tile_id in self.source_tile_candidates:
            sel = self.source_tile_selections.get(tile_id, 0)
            if sel < len(self.source_tile_candidates[tile_id]):
                img = self.source_tile_candidates[tile_id][sel]
                if img.mode != 'RGBA':
                    img = img.convert('RGBA')
                return img.resize((bs, bs), Image.NEAREST)

        if ctx.mdt.gfx and tile_id < len(ctx.mdt.gfx):
            raw_pixels = ctx.mdt.gfx[tile_id]
            tmp = Image.new('RGBA', (8, 8))
            for i, p_idx in enumerate(raw_pixels):
                if p_idx == -1:
                    pixel = (0, 0, 0, 0)
                else:
                    color_hex = self.PALETTE_STRS[p_idx]
                    rgb = tuple(int(color_hex[j:j+2], 16) for j in (1, 3, 5))
                    pixel = rgb + (255,)
                tmp.putpixel((i % 8, i // 8), pixel)
            return tmp.resize((bs, bs), Image.NEAREST)

        return Image.new('RGBA', (bs, bs), (0, 0, 0, 0))

    def save_png(self):
        ctx = self.active_map
        if not ctx:
            messagebox.showwarning('Warning', 'No map active.')
            return
        init = os.path.splitext(os.path.basename(ctx.path))[0] + '.png'
        path = filedialog.asksaveasfilename(defaultextension='.png',
                                            filetypes=[('PNG image', '*.png')],
                                            initialfile=init)
        if not path:
            return
        try:
            tile_size = self.source_tile_size if self.source_tile_candidates else 8
            mw, mh = ctx.mdt.map_width, ctx.mdt.map_height
            full_map = Image.new('RGBA', (mw * tile_size, mh * tile_size), (0, 0, 0, 0))
            for r in range(mh):
                for c in range(mw):
                    tid = ctx.mdt.grid[r][c]
                    tile_img = self._get_tile_image_for_export(ctx, tid, tile_size)
                    full_map.paste(tile_img, (c * tile_size, r * tile_size), tile_img)
            full_map.save(path)
            messagebox.showinfo('Saved', f'High-fidelity PNG saved:\n{path}')
        except Exception as e:
            messagebox.showerror('Save Error', str(e))

    def save_txt(self):
        ctx = self.active_map
        if not ctx:
            messagebox.showwarning('Warning', 'No map active.')
            return
        init = os.path.splitext(os.path.basename(ctx.path))[0] + '.txt'
        path = filedialog.asksaveasfilename(defaultextension='.txt',
                                            filetypes=[('Text file', '*.txt')],
                                            initialfile=init)
        if not path:
            return
        try:
            m = ctx.mdt
            with open(path, 'w', encoding='utf-8') as f:
                f.write(f'; Zeliard MDT:  {os.path.basename(ctx.path)}\n')
                f.write(f'; Width={m.map_width}  Height={m.map_height}\n')
                if m.is_town:
                    f.write(f'; Town name={m.town_name}  Doors={len(m.town_doors)}  NPCs={len(m.npcs)}\n;\n')
                else:
                    f.write(f'; Level={m.level}  Tear=({m.tear_x},{m.tear_y})\n'
                            f'; Doors={len(m.doors)}  Monsters={len(m.monsters)}  Items={len(m.items)}\n;\n')
                for row in m.grid:
                    f.write(''.join(chr(t + 0x20) for t in row) + '\n')
            messagebox.showinfo('Saved', f'TXT saved:\n{path}')
        except Exception as e:
            messagebox.showerror('Save Error', str(e))

    def save_tilesheet(self):
        if not self.source_tile_candidates:
            messagebox.showwarning('Warning', 'Load source image or tilesheet first.')
            return
        ts = getattr(self, 'source_tile_size', None)
        if ts is None:
            messagebox.showerror('Error', 'Source tile size unknown.')
            return
        tile_ids = sorted(self.source_tile_candidates.keys())
        if not tile_ids:
            return
        max_tid = max(tile_ids)
        total_tiles = max_tid + 1
        if 0 in self.source_tile_candidates:
            sel0 = self.source_tile_selections.get(0, 0)
            if sel0 < len(self.source_tile_candidates[0]):
                empty_tile = self.source_tile_candidates[0][sel0].convert('RGBA')
        else:
            empty_tile = Image.new('RGBA', (ts, ts), (0, 0, 0, 0))
        base = os.path.splitext(os.path.basename(self.active_map.path))[0] if self.active_map else 'tiles'
        default_name = f"{base}_x{ts}.png"
        path = filedialog.asksaveasfilename(defaultextension='.png',
                                            filetypes=[('PNG image', '*.png')],
                                            initialfile=default_name)
        if not path:
            return
        max_cols = 16
        cols = min(total_tiles, max_cols)
        rows = (total_tiles + cols - 1) // cols
        sheet_w = cols * ts
        sheet_h = rows * ts
        sheet = Image.new('RGBA', (sheet_w, sheet_h), (0, 0, 0, 0))
        existing_ids = set(tile_ids)
        for tid in range(total_tiles):
            if tid in existing_ids:
                sel = self.source_tile_selections.get(tid, 0)
                if sel < len(self.source_tile_candidates[tid]):
                    tile_img = self.source_tile_candidates[tid][sel]
                    if tile_img.mode != 'RGBA':
                        tile_img = tile_img.convert('RGBA')
                else:
                    tile_img = Image.new('RGBA', (ts, ts), (0, 0, 0, 0))
            else:
                tile_img = empty_tile
            row = tid // cols
            col = tid % cols
            sheet.paste(tile_img, (col * ts, row * ts), tile_img)
        sheet.save(path)
        messagebox.showinfo('Saved', f'Tile sheet saved as {default_name}\n at:\n{path}')

    # ── Checkerboard helpers ─────────────────────────────────────────────────
    def _make_checker_patch(self, size: int) -> Image.Image:
        if size in self._checker_cache:
            return self._checker_cache[size]
        img = Image.new('RGBA', (size, size))
        cell = max(1, self.CHECKER_CELL * size // 8)
        light = tuple(int(self.CHECKER_LIGHT[i:i+2], 16) for i in (1, 3, 5)) + (255,)
        dark  = tuple(int(self.CHECKER_DARK[i:i+2], 16)  for i in (1, 3, 5)) + (255,)
        for y in range(size):
            for x in range(size):
                img.putpixel((x, y), light if ((x // cell) + (y // cell)) % 2 == 0 else dark)
        self._checker_cache[size] = img
        return img

    def _composite_over_checker(self, tile_img: Image.Image, size: int) -> Image.Image:
        checker = self._make_checker_patch(size).copy()
        tile_rgba = tile_img.convert('RGBA') if tile_img.mode != 'RGBA' else tile_img
        checker.paste(tile_rgba, (0, 0), tile_rgba)
        return checker

    def _toggle_checkerboard(self):
        self.show_checkerboard.set(not self.show_checkerboard.get())
        on = self.show_checkerboard.get()
        self.chk_btn.config(
            text=f'Checker  {"ON " if on else "OFF"}',
            fg=self.C_YELL if on else self.C_DIM)
        self._checker_cache.clear()
        for ctx in self.maps.values():
            ctx.tile_images.clear()
            ctx.source_tile_cache.clear()
        if self.active_map:
            self._draw_map(self.active_map)

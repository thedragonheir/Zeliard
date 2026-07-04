"""
Zeliard MDT Viewer - Main application.
"""

import os
import tkinter as tk
from tkinter import filedialog, messagebox, ttk
from collections import Counter
# from typing import Optional, Dict, Any, List
from typing import Optional, List

from ..core.constants import PALETTE, TOWN_HEIGHT, _MONSTER_TYPE_NAMES, _ITEM_TYPE_NAMES, get_map_type_info, _ptr_off_safe, get_mdt_tileset, get_mdt_npc_grps, get_mdt_association
from ..core.models import MdtData
from ..core.decoder import decode_mdt_file_by_name
from ..common_ui.widgets import Tooltip, CollapsibleSection
from ..rendering.tile_graphics import get_tile_graphics
from ..rendering.map_renderer import MapRenderer
from ..archives.sar_reader import SarArchive
from ..viewer_ui.canvas_panel import attach_canvas_panel
from ..viewer_ui.sar_browser import SarBrowser
from ..viewer_ui.toolbar import attach_toolbar
from ..viewer_ui.view_settings_dialog import show_view_settings
from ..common_ui.sidebar import Sidebar


def _mdt_tileset_grp(mdt, fallback_name: str = '') -> str:
    if fallback_name:
        grp_from_name = get_mdt_tileset(fallback_name)
        # For MP*.MDT, force filename-world rule over descriptor.
        if grp_from_name.startswith('mpp'):
            return grp_from_name

    descriptor_grp = getattr(mdt, 'tileset_grp', '')
    if descriptor_grp:
        return descriptor_grp
    if fallback_name:
        return grp_from_name
    return 'mpat.grp' if getattr(mdt, 'is_town', False) else 'dpat.grp'


class _SarFileEntry:
    """Dummy entry representing a SAR archive file itself."""
    def __init__(self, path: str, size: int):
        self.name = os.path.basename(path)
        self.path = path
        self.size = size


class _MultiSarView:
    """
    Lightweight shim that merges entries from multiple SarArchive instances
    so the SarBrowser sees them as one archive.
    Optionally includes the SAR file paths themselves as entries.
    """
    def __init__(self, archives, include_sar_files=False):
        self._archives = archives
        self._index = {}   # name.upper() -> SarArchive
        self.entries = []
        # Add SAR file entries at the top (disabled by default)
        if include_sar_files:
            for sar in archives:
                self.entries.append(_SarFileEntry(sar.path, os.path.getsize(sar.path)))
        # Add archive entries
        for sar in archives:
            for entry in sar.entries:
                key = entry.name.upper()
                if key not in self._index:
                    self._index[key] = sar
                    self.entries.append(entry)
        self.name = ' + '.join(a.name for a in archives)
        # Use first archive path for tile loading compat
        self.path = archives[0].path if archives else ''

    def read(self, name: str) -> bytes:
        sar = self._index.get(name.upper())
        if sar is None:
            raise KeyError(f'{name!r} not in any loaded SAR')
        return sar.read(name)

    def contains(self, name: str) -> bool:
        return name.upper() in self._index

    def list_files(self, ext_filter=None):
        names = [e.name for e in self.entries]
        if ext_filter:
            ef = ext_filter.upper()
            names = [n for n in names if n.upper().endswith(ef)]
        return names


class MDTViewer(tk.Tk):
    """Main MDT Viewer application window."""

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

    VERSION = '3.5'

    BLK_MIN = 2
    BLK_MAX = 40
    BLK_DEF = 10

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
        self.title(f'Zeliard MDT Viewer  v{self.VERSION}')
        self.geometry('800x600')
        # Optionally constrain minimum size to 800x600 for consistency
        try:
            self.minsize(800, 600)
        except Exception:
            pass
        self.minsize(980, 660)
        self.configure(bg=self.C_BG2)

        self.block_size = self.BLK_DEF
        self.mdt: Optional[MdtData] = None
        self.current_file: Optional[str] = None
        self.file_data: Optional[bytes] = None
        self.show_overlay  = tk.BooleanVar(value=True)
        self.show_npc_var      = tk.BooleanVar(value=True)
        self.show_monster_var  = tk.BooleanVar(value=True)
        self.show_item_var     = tk.BooleanVar(value=True)
        self.show_door_var    = tk.BooleanVar(value=True)
        self.show_paths    = tk.BooleanVar(value=True)   # legacy alias = VP paths
        self.show_vp_paths    = tk.BooleanVar(value=True)
        self.show_hp_paths    = tk.BooleanVar(value=True)
        self.show_cp_paths    = tk.BooleanVar(value=True)
        self.show_vp_label   = tk.BooleanVar(value=True)
        self.show_hp_label   = tk.BooleanVar(value=True)
        self.show_cp_label   = tk.BooleanVar(value=True)
        self.show_labels      = tk.BooleanVar(value=True)
        self.show_sign_var    = tk.BooleanVar(value=True)
        self.show_tile_border = tk.BooleanVar(value=True)
        self.overlay_ids: List[int] = []
        self.hover_txt = tk.StringVar()
        self.tooltip: Optional[Tooltip] = None
        self._drag_start_x = 0
        self._drag_start_y = 0
        self.wrap_var    = tk.BooleanVar(value=False)  # init before _build_ui
        self.grid_var     = tk.BooleanVar(value=True)
        self.view_mode   = tk.StringVar(value='tiles')   # 'color' or 'tiles'
        self._tile_gfx   = get_tile_graphics()           # tile graphics instance
        self.tile_images = {}
        self._sar        = None                           # currently open SarArchive
        self._display_name      = ''
        self._display_name_prev = ''
        # Buffer for log messages created before the log panel exists
        self._log_buffer = []
        # Renderer instance (separates drawing logic into renderer.py)
        try:
            self.renderer = MapRenderer(self)
        except Exception:
            self.renderer = None

        # Sprite preview override: NPC label -> sprite index override for tooltip
        self._npc_sprite_preview: dict = {}
        self._hovered_npc_label: Optional[str] = None
        self._npc_locked = False
        self._locked_npc = None
        # NPC animation state
        self._npc_anim_timer: Optional[str] = None
        self._npc_anim_label: Optional[str] = None
        self._npc_anim_range: tuple = (0, 3)
        self._npc_anim_frame: int = 0
        self._npc_anim_interval: int = 500

        self._build_ui()

    # ── UI Construction ───────────────────────────────────────────────────────
    def _build_ui(self):
        """Build the complete UI."""
        self._toolbar = attach_toolbar(self)
        self._build_body()
        self._build_log_panel()

    def _build_body(self):
        """Build the main body using Sidebar panels for left/right collapse."""
        _body = tk.Frame(self, bg=self.C_BG2)
        _body.pack(fill='both', expand=True)

        # ── Left sidebar: SAR file browser ─────────────────────────────────
        self._sar_sidebar = Sidebar(
            _body, title='FILES', side='left',
            collapsed_width=28, expand_width=240,
            resizable=True,
            title_color=self.C_CYAN,
            bg=self.C_SURF, content_bg=self.C_BG0)
        self._sar_sidebar.pack(side='left', fill='y')
        # Compat aliases used elsewhere
        self.sar_panel  = self._sar_sidebar.content

        self._build_sar_panel(self.sar_panel)

        # ── Centre: map canvas (PanedWindow for resize handle) ──
        centre = tk.PanedWindow(_body, orient='horizontal',
                              bg=self.C_BG2, sashwidth=5, sashrelief='flat')
        centre.pack(side='left', fill='both', expand=True)
        self._centre_pane = centre

        # Left: map canvas
        left = tk.Frame(centre, bg=self.C_BG2)
        centre.add(left, minsize=650, stretch='always')

        # ── Right sidebar: info panel ──────────────────────────────────────
        self._info_sidebar = Sidebar(
            _body, title='INFO', side='right',
            collapsed_width=28, expand_width=330,
            resizable=True,
            title_color=self.C_CYAN,
            bg=self.C_SURF, content_bg=self.C_BG3)
        self._info_sidebar.pack(side='right', fill='y')
        self._build_info_panel(self._info_sidebar.content)
        # Compat aliases
        self._right_panel = self._info_sidebar
        self._info_sidebar_ref = self._info_sidebar

        self._canvas_panel = attach_canvas_panel(left, self)

        # NPC speech panel — hidden initially, shown for town maps

        # Status bar is in subbar (below toolbar)

        # Right: info panel (legacy - now handled by sidebar)
        # NOTE: info panel is now built inside _info_sidebar in _build_body()
        # This section is kept for compatibility only

    def _build_log_panel(self):
        """Build the collapsible log panel at the very bottom of the window using Sidebar."""
        log_container = tk.Frame(self, bg=self.C_BG1, bd=0)
        log_container.pack(fill='x', side='bottom')

        # Separator line (top border of log panel)
        tk.Frame(log_container, bg=self.C_SURF, height=1).pack(fill='x')

        # Create log sidebar
        self._log_sidebar = Sidebar(
            log_container, title='LOG', side='bottom',
            collapsed_width=22, expand_width=140,
            resizable=True,
            title_color=self.C_CYAN,
            bg=self.C_SURF, content_bg=self.C_BG1)
        self._log_sidebar.pack(fill='x')

        # Build log content inside the sidebar
        log_content_frame = self._log_sidebar.content
        log_content_frame.config(height=80)
        log_content_frame.pack_propagate(False)

        # Add Clear button to the log content area
        btn_frame = tk.Frame(log_content_frame, bg=self.C_BG1)
        btn_frame.pack(fill='x', padx=4, pady=2)
        tk.Button(
            btn_frame, text='Clear', command=self._log_clear,
            bg=self.C_SURF, fg=self.C_DIM,
            activebackground=self.C_BG2, activeforeground=self.C_FG,
            relief='flat', bd=0,
            font=('Consolas', 7), padx=4, pady=1,
            cursor='hand2').pack(side='right')

        # Text widget with scrollbar
        log_frame = tk.Frame(log_content_frame, bg=self.C_BG1)
        log_frame.pack(fill='both', expand=True, padx=4, pady=(0, 4))

        log_vsb = tk.Scrollbar(
            log_frame, orient='vertical',
            bg=self.C_SURF, troughcolor=self.C_BG1, width=8)
        self._log_txt = tk.Text(
            log_frame,
            bg=self.C_BG1, fg='#585870',
            font=('Consolas', 8), relief='flat', bd=0,
            state='disabled', wrap='none', height=4,
            selectbackground=self.C_SURF, selectforeground=self.C_FG,
            padx=8, pady=2,
            yscrollcommand=log_vsb.set)
        log_vsb.config(command=self._log_txt.yview)
        log_vsb.pack(side='right', fill='y')
        self._log_txt.pack(fill='both', expand=True)

        # Color tags — match sidebar info panel tag colors
        self._log_txt.tag_config('ts',     foreground='#313244',
                                  font=('Consolas', 7))
        self._log_txt.tag_config('load',   foreground='#a6e3a1',
                                  font=('Consolas', 8))
        self._log_txt.tag_config('unload', foreground='#f38ba8',
                                  font=('Consolas', 8))
        self._log_txt.tag_config('info',   foreground='#89b4fa',
                                  font=('Consolas', 8))
        self._log_txt.tag_config('warn',   foreground='#f9e2af',
                                  font=('Consolas', 8))
        self._log_txt.tag_config('dim',    foreground='#585870',
                                  font=('Consolas', 8))

    def _log(self, msg: str, tag: str = 'info'):
        """Append a timestamped line to the log panel.

        If the log panel hasn't been built yet, buffer the message and
        print it to the console so it's not silently lost. When the
        panel is available the buffer will be flushed.
        """
        import datetime
        ts = datetime.datetime.now().strftime('%H:%M:%S')
        # Prepare a simple record
        record = (msg, tag, ts)

        if not hasattr(self, '_log_txt') or self._log_txt is None:
            # Ensure buffer exists
            if not hasattr(self, '_log_buffer'):
                self._log_buffer = []
            self._log_buffer.append(record)
            # Also print to console so user sees errors when UI not ready
            try:
                print(f'[{ts}] {msg}')
            except Exception:
                pass
            return

        # Flush any buffered entries first
        if getattr(self, '_log_buffer', None):
            T = self._log_txt
            T.config(state='normal')
            for bmsg, btag, bts in self._log_buffer:
                T.insert('end', f'[{bts}] ', 'ts')
                T.insert('end', bmsg + '\n', btag)
            self._log_buffer.clear()
            T.see('end')
            T.config(state='disabled')

        # Now append the current message
        T = self._log_txt
        T.config(state='normal')
        T.insert('end', f'[{ts}] ', 'ts')
        T.insert('end', msg + '\n', tag)
        T.see('end')
        T.config(state='disabled')

    def _log_clear(self):
        if not hasattr(self, '_log_txt'):
            return
        self._log_txt.config(state='normal')
        self._log_txt.delete('1.0', 'end')
        self._log_txt.config(state='disabled')

    def _build_info_panel(self, parent: tk.Widget):
        """Build collapsible info sub-panels with drag-resize between them."""
        # Vertical PanedWindow: each CollapsibleSection is a pane
        # The sash between panes allows height adjustment
        vpane = tk.PanedWindow(parent, orient='vertical',
                               bg=self.C_BG2, sashwidth=5, sashrelief='flat',
                               opaqueresize=True)
        vpane.pack(fill='both', expand=True)
        self._info_vpane = vpane

        def make_sec(title, color=self.C_BLUE):
            # Container frame for pane
            pane_frame = tk.Frame(vpane, bg=self.C_BG3)
            sec = CollapsibleSection(pane_frame, title=title, color=color,
                                     bg_header=self.C_SURF, bg_content=self.C_BG3)
            sec.pack(fill='both', expand=True)
            vpane.add(pane_frame, stretch='always', minsize=28)
            return sec, sec.content

        sec1, cnt1 = make_sec('MAP INFORMATION')
        sec2, cnt2 = make_sec('HEADER INFORMATION')
        sec3, cnt3 = make_sec('OBJECT INFORMATION')
        self.info_box1 = type('IB', (), {'_content': cnt1})()
        self.info_box2 = type('IB', (), {'_content': cnt2})()
        self.info_box3 = type('IB', (), {'_content': cnt3})()
        # Legend — each button scrolls info_txt3 to first entity of that prefix
        self._legend_btns = {}  # prefix -> button for count updates
        def _mk_legend_btn(parent, text, fg, prefix):
            btn = tk.Button(parent, text=text + ' (0)', bg=self.C_BG0, fg=fg,
                          activebackground='#1e1e30', activeforeground=fg,
                          relief='flat', bd=0, cursor='hand2',
                          font=('Consolas', 8, 'bold'), padx=3, pady=1)
            btn.bind('<Button-1>', lambda e, p=prefix: self._scroll_info_to_prefix(p))
            btn.pack(side='left')
            self._legend_btns[prefix] = btn
            return btn

        inner = tk.Frame(self.info_box3._content, bg=self.C_BG0)
        inner.pack(fill='x', padx=5, pady=3)
        _mk_legend_btn(inner, 'Door',    '#d8accf', 'D')
        _mk_legend_btn(inner, 'Monster','#DF819d','M')
        _mk_legend_btn(inner, 'Item',  '#6bc08c', 'I')

        inner2 = tk.Frame(self.info_box3._content, bg=self.C_BG0)
        inner2.pack(fill='x', padx=5, pady=(0, 3))
        _mk_legend_btn(inner2, 'NPC',   '#89dceb', 'N')
        _mk_legend_btn(inner2, 'Tear',   '#f9e2af', 'T')
        _mk_legend_btn(inner2, 'VP=V-Platform', '#a6e3a1', 'VP')

        inner3 = tk.Frame(self.info_box3._content, bg=self.C_BG0)
        inner3.pack(fill='x', padx=5, pady=(0, 3))
        _mk_legend_btn(inner3, 'CP=C-Platform','#f9e2af','CP')
        _mk_legend_btn(inner3, 'HP=H-Platform','#f5c2e7','HP')
        _mk_legend_btn(inner3, 'S=Sign',  '#ccffcc', 'S')

        sec4, cnt4 = make_sec('TILE INFORMATION', color=self.C_CYAN)
        self.info_box4 = type('IB', (), {'_content': cnt4})()

        self.info_txt1 = tk.Text(self.info_box1._content, bg=self.C_PANEL, fg=self.C_FG,
                                 font=('Consolas', 8), relief='flat', state='disabled',
                                 width=40, wrap='none', selectbackground=self.C_SURF, height=5)
        self.info_txt1.pack(in_=cnt1, fill='both', expand=True)

        self.info_txt2 = tk.Text(self.info_box2._content, bg=self.C_PANEL, fg=self.C_FG,
                                 font=('Consolas', 8), relief='flat', state='disabled',
                                 width=40, wrap='none', selectbackground=self.C_SURF, height=5)
        self.info_txt2.pack(in_=cnt2, fill='both', expand=True)

        self.info_txt3 = None  # replaced by _tv3 Treeview below

        # ── Overlay Treeview (replaces info_txt3 Text widget) ──────────────
        ov_tv_frame = tk.Frame(cnt3, bg=self.C_BG3)
        ov_tv_frame.pack(fill='both', expand=True)

        try:
            _s = ttk.Style()
            _s.configure('OV.Treeview',
                          background=self.C_PANEL, foreground=self.C_FG,
                          fieldbackground=self.C_PANEL, rowheight=16,
                          font=('Consolas', 8))
            _s.configure('OV.Treeview.Heading',
                          background=self.C_SURF, foreground=self.C_DIM,
                          relief='flat', font=('Consolas', 7, 'bold'))
            _s.map('OV.Treeview',
                   background=[('selected', self.C_SURF)],
                   foreground=[('selected', '#ffffff')])
        except Exception:
            pass

        _tv3_cols = ('obj', 'attr', 'mask', 'hex_val', 'dec_val', 'name_val')
        self._tv3 = ttk.Treeview(
            ov_tv_frame, columns=_tv3_cols, show='headings',
            style='OV.Treeview', selectmode='extended')
        _tv3_cfg = {
            'obj':      (44,  'center', 'Obj'),
            'attr':     (62,  'w',      'Attr'),
            'mask':     (130, 'w',      'Mask'),
            'hex_val':  (70,  'w',      'Hex'),
            'dec_val':  (36,  'e',      'Dec'),
            'name_val': (90,  'w',      'Value'),
        }
        for col, (w, anch, hdr) in _tv3_cfg.items():
            self._tv3.column(col, width=w, anchor=anch, stretch=(col == 'name_val'))
            self._tv3.heading(col, text=hdr)

        _vsb3 = ttk.Scrollbar(ov_tv_frame, orient='vertical',   command=self._tv3.yview)
        _hsb3 = ttk.Scrollbar(ov_tv_frame, orient='horizontal', command=self._tv3.xview)
        self._tv3.configure(yscrollcommand=_vsb3.set, xscrollcommand=_hsb3.set)
        _vsb3.pack(side='right', fill='y')
        _hsb3.pack(side='bottom', fill='x')
        self._tv3.pack(fill='both', expand=True)

        self._tv3.tag_configure('sec',    foreground='#cdd6f4', background=self.C_SURF,
                                 font=('Consolas', 7, 'bold'))
        self._tv3.tag_configure('entity', foreground='#cba6f7',
                                 font=('Consolas', 8, 'bold'))
        self._tv3.tag_configure('dim',    foreground=self.C_DIM)
        self._tv3.tag_configure('raw',    foreground='#9399b2')
        self._tv3.tag_configure('note',   foreground='#9399b2',
                                 font=('Consolas', 7))
        self._tv3.tag_configure('hp_xi',  foreground='#f38ba8')
        self._tv3.tag_configure('hp_yf',  foreground='#89b4fa')
        self._tv3.tag_configure('hp_xl',  foreground='#f9e2af')
        self._tv3.tag_configure('hp_xr',  foreground='#a6e3a1')
        self._tv3.tag_configure('rb_type',foreground='#f38ba8')
        self._tv3.tag_configure('rb_id',  foreground='#cba6f7')
        self._tv3.tag_configure('rb_flag',foreground='#fab387')
        self._tv3.tag_configure('rb_act', foreground='#94e2d5')
        self._tv3.tag_configure('g',      foreground='#a6e3a1')
        self._tv3.tag_configure('p',      foreground='#f5c2e7')
        self._tv3.tag_configure('c',      foreground='#89dceb')
        self._tv3.tag_configure('y',      foreground='#f9e2af')

        self._tv3_entity_iids = {}   # label → first iid
        self._tv3.bind('<Double-Button-1>', self._on_tv3_click)
        self._tv3.bind('<Button-1>',        self._on_tv3_click)
        self._tv3.bind('<Control-a>',       self._tv3_select_all)
        self._tv3.bind('<Control-A>',       self._tv3_select_all)
        self._tv3.bind('<Control-c>',       self._tv3_copy)
        self._tv3.bind('<Control-C>',       self._tv3_copy)

        self.info_txt4 = tk.Text(self.info_box4._content, bg=self.C_PANEL, fg=self.C_FG,
                                 font=('Consolas', 8), relief='flat', state='disabled',
                                 width=40, wrap='none', selectbackground=self.C_SURF, height=5)
        self.info_txt4.pack(in_=cnt4, fill='both', expand=True)

        # Configure text tags
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
            txt.tag_config('entity_link', foreground='#cba6f7',
                           underline=True, font=('Consolas', 8, 'bold'))
            txt.tag_bind('entity_link', '<Button-1>', self._on_info_entity_click)
            txt.tag_bind('entity_link', '<Enter>',
                         lambda e: e.widget.config(cursor='hand2'))
            txt.tag_bind('entity_link', '<Leave>',
                         lambda e: e.widget.config(cursor=''))

        # (raw_colors configured directly on self._tv3 tags above)

    # ── File Operations ───────────────────────────────────────────────────────
    def _build_sar_panel(self, parent: tk.Widget):
        """Embed SarBrowser widget into the SAR panel frame."""
        self.sar_browser = SarBrowser(
            parent,
            on_select=self._on_sar_entry_selected,
        )
        self.sar_browser.pack(fill='both', expand=True)
        # Compat aliases used elsewhere
        self.sar_status_lbl = self.sar_browser.status_lbl
        self.sar_name_lbl   = self.sar_browser.name_lbl

    def open_sar(self):
        """Select a directory and load all zelres*.sar archives found there."""
        # Let user pick any *.sar file — we then load all zelresN.sar from that directory
        first = filedialog.askopenfilename(
            title='Select SAR file (zelres1/2/3.sar) in the Zeliard game folder',
            filetypes=[('Zeliard SAR archives', '*.sar *.SAR'),
                       ('All files', '*.*')])
        if not first:
            return
        directory = os.path.dirname(first)

        # Find all zelres*.sar files in the directory (case-insensitive)
        candidates = []
        for n in ['zelres1.sar','zelres2.sar','zelres3.sar',
                  'ZELRES1.SAR','ZELRES2.SAR','ZELRES3.SAR']:
            p = os.path.join(directory, n)
            if os.path.exists(p):
                candidates.append(p)
        # Deduplicate (case-insensitive OS)
        seen = set()
        paths = []
        for p in candidates:
            key = p.lower()
            if key not in seen:
                seen.add(key); paths.append(p)
        paths.sort()

        if not paths:
            messagebox.showwarning('No SAR Files',
                f'No SAR files found in:\n{directory}')
            return

        # Load the first (primary) SAR for browsing; pass all for tile graphics
        loaded = []
        last_sar = None
        for path in paths:
            try:
                sar = SarArchive(path)
                loaded.append(sar)
                last_sar = sar
            except Exception as e:
                pass  # skip missing / corrupt

        if not loaded:
            messagebox.showerror('SAR Error', 'Could not open any SAR archive.')
            return

        # Merge all entries into a combined browser view
        # Use a MultiSar shim that exposes combined entries
        self._sar = _MultiSarView(loaded)
        self._sar_dir = directory

        self._refresh_sar_list()

        # Tile graphics will be loaded on-demand when an MDT file is selected
        self._log(f'Loaded {len(loaded)} SAR archive(s). GRP files will load when MDT is selected.', 'info')

    def _refresh_sar_list(self):
        """Delegate list refresh to SarBrowser, then populate MDT place hints."""
        if not self._sar or not hasattr(self, 'sar_browser'):
            return
        self.sar_browser.load(self._sar)
        # Populate place_name hints for MDT entries (background quick-parse)
        self.after(50, self._populate_mdt_hints)

    def _populate_mdt_hints(self):
        """Parse each MDT in the SAR to extract place/dungeon name for the browser."""
        if not self._sar or not hasattr(self, 'sar_browser'):
            return
        #from ..core.decoder import decode_town_mdt
        from ..core.decoder import decode_town_mdt, decode_dung_mdt
        from ..core.constants import is_town_mdt
        for entry in self._sar.entries:
            name = entry.name.strip()
            if not name.upper().endswith('.MDT'):
                continue
            try:
                data = self._sar.read(name)
            except Exception:
                continue
            hint = ''
            try:
                if is_town_mdt(name):
                    town = decode_town_mdt(data)
                    hint = town.town_name or ''
                else:
                    mdt = decode_mdt(data)
                    mdt = decode_dung_mdt(data)
                    hint = mdt.name or ''
            except Exception:
                pass
            if hint:
                self.sar_browser.set_entry_hint(name, hint)
        # Re-render list with hints populated
        self.sar_browser._refresh()

    def _on_sar_entry_selected(self, name: str, entry=None):
        """Called by SarBrowser when a file is double-clicked."""
        if not self._sar:
            return
        if not name.upper().endswith('.MDT'):
            if hasattr(self, 'sar_browser'):
                self.sar_browser.set_status(f'{name}: not an MDT file')
            return
        try:
            data = self._sar.read(name)
        except Exception as e:
            messagebox.showerror('Read Error', f'Could not read {name}:\n{e}')
            return
        import tempfile
        suffix = '_' + name
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(data)
            tmp_path = tmp.name
        self._open_path(tmp_path, display_name=name)

        # Render map and load additional files depending on view mode
        if not getattr(self, '_sar', None) or not self.mdt:
            return

        if self.view_mode.get() == 'tiles':
            # Log render mode first (user action feedback)
            self._log('Render mode: Real Tiles  (loading GRP files...)', 'info')

            # Then load required GRP files
            fname = name
            tileset_grp = _mdt_tileset_grp(self.mdt, fname)
            required_groups = [tileset_grp]

            # For town maps: descriptor's town_npc_grp takes priority
            npc_grps = list(get_mdt_npc_grps(fname))
            if self.mdt.is_town and getattr(self.mdt, 'town_npc_grp', ''):
                desc_grp = self.mdt.town_npc_grp
                if desc_grp not in npc_grps:
                    npc_grps.insert(0, desc_grp)
            for ng in npc_grps:
                if ng not in required_groups:
                    required_groups.append(ng)

            for sar in getattr(self._sar, '_archives', []):
                for grp in required_groups:
                    is_loaded = (grp in getattr(self._tile_gfx, '_pat', {})) or (grp in getattr(self._tile_gfx, '_npc', {}))
                    if not is_loaded:
                        try:
                            missing = self._tile_gfx.load_groups_from_sar(sar.path, [grp])
                            if not missing:
                                name = grp.upper()
                                if 'PAT' in name:
                                    prefix = 'Tile: '
                                elif 'MAN' in name:
                                    prefix = 'NPC: '
                                else:
                                    prefix = ''
                                self._log(f'{prefix}{name} loaded from {os.path.basename(sar.path)}', 'info')
                        except Exception:
                            pass

            # Render after GRP files are loaded
            self.renderer.draw_map()
            self.renderer.draw_overlays()
        else:
            # Color block mode: just render without GRP loading
            self.renderer.draw_map()
            self.renderer.draw_overlays()

    def _close_sar_panel(self):
        """Collapse the SAR sidebar."""
        if hasattr(self, '_sar_sidebar') and not self._sar_sidebar.is_collapsed:
            self._sar_sidebar.collapse()

    def _open_sar_panel(self):
        """Expand the SAR sidebar."""
        if hasattr(self, '_sar_sidebar') and self._sar_sidebar.is_collapsed:
            self._sar_sidebar.expand()

    def open_file(self):
        """Open an MDT file via file dialog."""
        path = filedialog.askopenfilename(
            title='Open MDT File',
            filetypes=[('MDT map files', '*.mdt *.MDT'), ('All files', '*.*')])
        if not path:
            return
        self._open_path(path)

    def _open_path(self, path: str, display_name: str = ''):
        """Internal: load and display an MDT file (from disk or temp path)."""
        try:
            # Always clear previous data from memory before loading new file
            if self.tooltip:
                self.tooltip.hide()
            self._npc_locked = False
            self._locked_npc = None
            self.tile_images.clear()
            self._npc_sprite_preview.clear()
            self._npc_anim_stop()
            if hasattr(self, 'mdt') and self.mdt is not None:
                prev = getattr(self, '_display_name_prev', '')
                if prev:
                    self._log(f'Unloaded: {prev}  (all GRP data cleared)', 'unload')
                self._tile_gfx.reset()
                loaded_grps = list(self._tile_gfx._pat.keys()) + list(self._tile_gfx._npc.keys())
                if loaded_grps:
                    self._log(f'Cleared from memory: {", ".join(loaded_grps)}', 'dim')

            self.file_data = open(path, 'rb').read()
            self._display_name = display_name or os.path.basename(path)
            # For town detection, use display_name if opening from SAR temp file
            decode_name = self._display_name if display_name else path
            fname = self._display_name

            self.mdt = decode_mdt_file_by_name(decode_name, path)
            self._display_name_prev = fname
            self.current_file = path
            self.title(f'Zeliard MDT Viewer  —  {fname}')
            self.hint.pack_forget()
            self.cf.pack(fill='both', expand=True)

            if self.tooltip is None:
                self.tooltip = Tooltip(self)

            self._map_cache = {}
            if not getattr(self, '_sar', None):
                # No SAR available (file dialog open): render immediately
                self.renderer.draw_map()
                self.renderer.draw_overlays()
            # If SAR is available, rendering is handled by _on_sar_entry_selected
            self._update_info()
            self._update_place_banner()
            self._update_loop_btn_state()
            # Enable Save MDT button when display_name differs from path (SAR source)
            # Show NPC speech panel only for town maps
            if self.mdt.is_town:
                self.npc_panel.pack(fill='x', before=self.cf)
                self._set_npc_speech(None)
            else:
                self.npc_panel.pack_forget()

            # ── Log: MDT loaded ────────────────────────────────────────
            map_type = get_map_type_info(fname)
            n_monsters = len(self.mdt.monsters) if not self.mdt.is_town else 0
            n_doors    = len(self.mdt.doors) if not self.mdt.is_town else len(self.mdt.town_doors)
            self._log(f'Loaded: {fname}  [{map_type}]  '
                      f'{self.mdt.map_width}×{self.mdt.map_height} tiles  '
                      f'doors={n_doors}  monsters={n_monsters}', 'load')

            # ── Log: tileset assignment ────────────────────────────────
            tileset_grp = _mdt_tileset_grp(self.mdt, fname)
            tileset_source = 'descriptor' if getattr(self.mdt, 'tileset_grp', '') else 'filename'
            tileset_loaded = tileset_grp in getattr(self._tile_gfx, '_pat', {})
            if tileset_loaded:
                n_tiles = len(self._tile_gfx._pat[tileset_grp])
                self._log(f'Tileset: {tileset_grp}  ({n_tiles} tiles) — {tileset_source}, already in memory', 'info')
            elif self.view_mode.get() == 'tiles':
                self._log(f'Tileset: {tileset_grp}  — {tileset_source}, not found in SARs', 'warn')

        except Exception as e:
            messagebox.showerror('Load Error', str(e))

    # ── Map Rendering ─────────────────────────────────────────────────────────
    # Grayscale palette for ghost tiles (wrap copies)
    # Pre-computed gray palette for ghost tile copies (256 entries)
    _GRAY_CACHE: list = [
        f'#{min(30 + (i % 64) * 2, 140):02x}'
        f'{min(30 + (i % 64) * 2, 140):02x}'
        f'{min(30 + (i % 64) * 2, 140):02x}'
        for i in range(256)
    ]

    @classmethod
    def _gray(cls, tile: int) -> str:
        """Tile → grayscale hex (pre-computed lookup)."""
        return cls._GRAY_CACHE[tile & 0xFF]

    def get_tile_image(self, tile_idx):
        if getattr(self, 'renderer', None):
            try:
                return self.renderer.get_tile_image(tile_idx)
            except Exception:
                pass
        return None

    def _draw_map(self):
        """Draw the tile grid on the canvas (optionally with wrap-ghost copies)."""
        self.canvas.delete('all')
        self.overlay_ids = []
        self._photo_refs = []   # prevent PhotoImage garbage collection
        if not self.mdt:
            return

        bs  = self.block_size
        mw  = self.mdt.map_width
        mh  = self.mdt.map_height
        grid = self.mdt.grid
        wrap = self.wrap_var.get() and not self.mdt.is_town

        # Canvas region: 3×3 if wrap, else 1×1
        cx_count = 3 if wrap else 1
        cy_count = 3 if wrap else 1
        W = mw * bs * cx_count
        H = mh * bs * cy_count
        self.canvas.configure(scrollregion=(0, 0, W, H))

        ol = self.C_BG1 if (bs >= 6 and self.show_tile_border.get()) else ''
        ow = 1 if (bs >= 6 and self.show_tile_border.get()) else 0

        # Offsets for the 3×3 copies: (-1,-1),(0,-1),(1,-1)... center is (0,0)
        copies = [(0,0)] if not wrap else [
            (-1,-1),(0,-1),(1,-1),
            (-1, 0),(0, 0),(1, 0),
            (-1, 1),(0, 1),(1, 1),
        ]

        # Try PIL-based fast render (single image per map copy)
        _pil_ok = False
        try:
            from PIL import Image as _PILImage, ImageTk as _PILImageTk
            _pil_ok = True
        except ImportError:
            pass

        _hex_to_rgb_cache = {}   # '#rrggbb' -> (r,g,b)
        def hex_rgb(h):
            if h not in _hex_to_rgb_cache:
                _hex_to_rgb_cache[h] = (int(h[1:3],16), int(h[3:5],16), int(h[5:7],16))
            return _hex_to_rgb_cache[h]

        def _render_copy_pil(ox, oy, palette_fn, cache_key):
            """Render a full map copy as one PIL image → one canvas item.
            Uses _map_cache to avoid re-rendering identical frames.
            """
            if cache_key in self._map_cache:
                photo = self._map_cache[cache_key]
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
                self._map_cache[cache_key] = photo
            self._photo_refs.append(photo)
            self.canvas.create_image(ox, oy, image=photo, anchor='nw')

        for (gx, gy) in copies:
            is_center = (gx == 0 and gy == 0)
            ox = (gx + (1 if wrap else 0)) * mw * bs
            oy = (gy + (1 if wrap else 0)) * mh * bs

            if self.view_mode.get() == 'tiles' and is_center:
                # Tile graphics mode: per-tile PhotoImages
                _tile_set_grp = _mdt_tileset_grp(self.mdt, self._display_name or '')
                _tile_set = {'dpat.grp': 'dungeon', 'mpat.grp': 'town',
                             'cpat.grp': 'common'}.get(_tile_set_grp, 'dungeon')
                for r in range(mh):
                    for c in range(mw):
                        tile_idx = grid[r][c]
                        x0 = ox + c * bs
                        y0 = oy + r * bs
                        tile_img = self.get_tile_image(tile_idx)
                        if tile_img:
                            self.canvas.create_image(x0, y0, image=tile_img, anchor="nw")
                        else:
                            # Fallback if GRP is missing
                            self.canvas.create_rectangle(x0, y0, x0+bs, y0+bs, fill="gray")
            elif _pil_ok and bs >= 2:
                # Color mode + Pillow available → single image per copy (fast)
                if is_center:
                    _render_copy_pil(ox, oy, lambda t: PALETTE[t % 64], ('c', bs))
                else:
                    _render_copy_pil(ox, oy, lambda t: self._gray(t), ('g', bs, gx, gy))
                if wrap and not is_center:
                    # Border over the image
                    self.canvas.create_rectangle(
                        ox, oy, ox + mw*bs, oy + mh*bs,
                        fill='', outline='#334455', width=1)
            else:
                # Fallback: per-tile rectangles (no Pillow or very small bs)
                for r in range(mh):
                    for c in range(mw):
                        t  = grid[r][c]
                        x0 = ox + c * bs
                        y0 = oy + r * bs
                        color = PALETTE[t % 64] if is_center else self._gray(t)
                        self.canvas.create_rectangle(
                            x0, y0, x0+bs, y0+bs, fill=color, outline=ol, width=ow)
                if wrap and not is_center:
                    self.canvas.create_rectangle(
                        ox, oy, ox + mw*bs, oy + mh*bs,
                        fill='', outline='#334455', width=1)

        # 16-tile alignment guides (on center copy only)
        if bs >= 4:
            ox = (1 if wrap else 0) * mw * bs
            oy = (1 if wrap else 0) * mh * bs
            for c in range(0, mw + 1, 16):
                self.canvas.create_line(ox+c*bs, oy, ox+c*bs, oy+mh*bs,
                    fill='#ffffff', stipple='gray25', width=1)
            for r in range(0, mh + 1, 16):
                self.canvas.create_line(ox, oy+r*bs, ox+mw*bs, oy+r*bs,
                    fill='#ffffff', stipple='gray25', width=1)

        # Scroll to center copy when wrap is toggled on
        if wrap:
            self.canvas.update_idletasks()
            cw = self.canvas.winfo_width()
            ch = self.canvas.winfo_height()
            cx = mw * bs  # center copy left edge
            cy = mh * bs  # center copy top edge
            self.canvas.xview_moveto(max(0, (cx - cw/2) / max(W-cw, 1)))
            self.canvas.yview_moveto(max(0, (cy - ch/2) / max(H-ch, 1)))

    def _draw_overlays(self):
        if getattr(self, 'renderer', None):
            try:
                return self.renderer.draw_overlays()
            except Exception:
                pass
        return



    def _show_npc_ctrl_legend(self):
        """Show a popup with NPC text control byte reference as a sortable table."""
        popup = tk.Toplevel(self)
        popup.title('NPC Text — Control Byte Reference')
        popup.configure(bg='#1e1e2e')
        popup.resizable(True, True)
        popup.transient(self)
        popup.grab_set()

        tk.Label(popup, text='NPC TEXT CONTROL BYTES',
                 bg='#1e1e2e', fg='#89b4fa',
                 font=('Consolas', 10, 'bold'), padx=16, pady=8
                 ).pack(anchor='w')

        rows = [
            ('0x5C  (\\\\)',   "apostrophe  '",
             "Zeliard font maps 0x5C (backslash) to the apostrophe glyph"),
            ('0x81',           '[SPEECH PAUSE]',
             'Paragraph break; game pauses and starts new speech block'),
            ('0x00–0x1F',      '[0xNN]  (raw hex)',
             'Control codes — function unknown; shown raw so position is visible'),
            ('0x7F–0xFF',      '[0xNN]  (raw hex)',
             'High bytes — encoding or engine-specific; shown raw'),
            ('0x26  (&)',       'literal  &',
             'Regular ASCII ampersand — no special role detected'),
            ('0x20–0x7E',      'printable ASCII',
             'Normal text characters, displayed as-is'),
        ]

        frame = tk.Frame(popup, bg='#181825', padx=4, pady=4)
        frame.pack(fill='both', expand=True, padx=8, pady=(0, 6))

        try:
            _s = ttk.Style()
            _s.configure('NPC.Treeview',
                          background='#181825', foreground='#cdd6f4',
                          fieldbackground='#181825', rowheight=20,
                          font=('Consolas', 9))
            _s.configure('NPC.Treeview.Heading',
                          background='#313244', foreground='#6c7086',
                          relief='flat', font=('Consolas', 8, 'bold'))
            _s.map('NPC.Treeview',
                   background=[('selected', '#1a3a4a')],
                   foreground=[('selected', '#ffffff')])
        except Exception:
            pass

        tv = ttk.Treeview(frame,
                           columns=('byte', 'display', 'notes'),
                           show='headings', style='NPC.Treeview',
                           selectmode='extended', height=len(rows) + 1)
        tv.column('byte',    width=160, anchor='w', stretch=False)
        tv.column('display', width=180, anchor='w', stretch=False)
        tv.column('notes',   width=400, anchor='w', stretch=True)
        tv.heading('byte',    text='Byte / Range')
        tv.heading('display', text='Displayed as')
        tv.heading('notes',   text='Notes')
        tv.tag_configure('byte_row', foreground='#f9e2af')

        for byte_s, disp_s, note_s in rows:
            tv.insert('', 'end', values=(byte_s, disp_s, note_s), tags=('byte_row',))

        vsb = ttk.Scrollbar(frame, orient='vertical',   command=tv.yview)
        hsb = ttk.Scrollbar(frame, orient='horizontal', command=tv.xview)
        tv.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        vsb.pack(side='right', fill='y')
        hsb.pack(side='bottom', fill='x')
        tv.pack(fill='both', expand=True)

        # Ctrl+A / Ctrl+C
        def _sel_all(e=None):
            tv.selection_set(tv.get_children()); return 'break'
        def _copy(e=None):
            sel = tv.selection() or tv.get_children()
            txt = '\n'.join('\t'.join(str(v) for v in tv.item(i, 'values')) for i in sel)
            popup.clipboard_clear(); popup.clipboard_append(txt); return 'break'
        tv.bind('<Control-a>', _sel_all); tv.bind('<Control-A>', _sel_all)
        tv.bind('<Control-c>', _copy);    tv.bind('<Control-C>', _copy)

        tk.Button(popup, text='Close', command=popup.destroy,
                  bg='#313244', fg='#cdd6f4', relief='flat',
                  font=('Consolas', 9), padx=20, pady=4,
                  cursor='hand2').pack(pady=8)

        popup.update_idletasks()
        pw = popup.winfo_reqwidth() + 20
        ph = popup.winfo_reqheight() + 20
        px = self.winfo_rootx() + (self.winfo_width()  - pw) // 2
        py = self.winfo_rooty() + (self.winfo_height() - ph) // 2
        popup.geometry(f'{pw}x{ph}+{px}+{py}')



    def _update_place_banner(self):
        """Update the place-name label in the toolbar."""
        if not self.mdt:
            self.place_lbl_tb.config(text='')
            return
        if self.mdt.is_town and self.mdt.town_name:
            icon = '🏘'
            name = self.mdt.town_name
        elif not self.mdt.is_town and getattr(self.mdt, 'cavern_name', ''):
            icon = '⚔'
            name = self.mdt.cavern_name
        else:
            self.place_lbl_tb.config(text='')
            return
        self.place_lbl_tb.config(text=f'{icon}  {name.replace(chr(92), chr(39))}')

    def _update_view_btn(self):
        """View button — text stays static."""
        pass

    def _show_view_popup(self):
        """Open the View Settings dialog."""
        show_view_settings(self)

    def _show_open_popup(self):
        """Open file dropdown menu using tk.Menu widget."""
        menu = tk.Menu(self, tearoff=0, bg=self.C_BG2, fg=self.C_FG,
                       activebackground=self.C_SURF, activeforeground=self.C_FG)
        menu.add_command(label='SAR File', command=lambda: [menu.unpost(), self.open_sar()])
        menu.add_command(label='MDT File', command=lambda: [menu.unpost(), self.open_file()])

        btn = self._open_btn
        menu.post(btn.winfo_rootx(), btn.winfo_rooty() + btn.winfo_height())

    def _show_save_popup(self):
        """Save dropdown menu using tk.Menu widget.

        On the very first invocation, automatically copy the composed canvas
        image to the clipboard so the first Save also populates clipboard.
        Subsequent invocations behave normally.
        """
        # Auto-copy once on first open
        if not getattr(self, '_save_auto_copied', False):
            try:
                self.copy_png_to_clipboard()
            except Exception:
                # Ignore clipboard errors here; user can use menu item instead
                pass
            self._save_auto_copied = True

        menu = tk.Menu(self, tearoff=0, bg=self.C_BG2, fg=self.C_FG,
                       activebackground=self.C_SURF, activeforeground=self.C_FG)
        menu.add_command(label='PNG File', command=lambda s=self: [menu.unpost(), s.save_png()])
        menu.add_command(label='Copy Image to Clipboard', command=lambda s=self: [menu.unpost(), s.copy_png_to_clipboard()])
        menu.add_command(label='TXT File', command=lambda s=self: [menu.unpost(), s.save_txt()])
        menu.add_command(label='MDT File', command=lambda s=self: [menu.unpost(), s.save_mdt()])

        btn = self._save_btn
        menu.post(btn.winfo_rootx(), btn.winfo_rooty() + btn.winfo_height())

    def copy_png_to_clipboard(self):
        """Copy the canvas area as a DIB image to the Windows clipboard.

        Robust handling: declares ctypes prototypes for 64-bit, retries OpenClipboard,
        and uses a safe buffer copy to avoid GlobalLock failures where possible.
        """
        try:
            from PIL import ImageGrab
        except Exception:
            messagebox.showerror('Clipboard Error', 'Pillow is required for clipboard image support.')
            return

        import io, ctypes, time
        try:
            # Capture canvas area
            x = self.canvas.winfo_rootx()
            y = self.canvas.winfo_rooty()
            w = self.canvas.winfo_width()
            h = self.canvas.winfo_height()
            if w <= 0 or h <= 0:
                raise RuntimeError('Canvas has invalid size')
            bbox = (x, y, x + w, y + h)
            img = ImageGrab.grab(bbox)

            # Encode BMP and strip 14-byte file header to get DIB
            output = io.BytesIO()
            img.convert('RGB').save(output, 'BMP')
            bmp_data = output.getvalue()
            output.close()
            dib = bmp_data[14:]

            # Win32 API constants
            CF_DIB = 8
            GMEM_MOVEABLE = 0x0002

            user32 = ctypes.windll.user32
            kernel32 = ctypes.windll.kernel32
            # Ensure correct arg/return types for 64-bit safety
            try:
                from ctypes import wintypes
                user32.OpenClipboard.argtypes = [wintypes.HWND]
                user32.OpenClipboard.restype = wintypes.BOOL
                user32.EmptyClipboard.restype = wintypes.BOOL
                user32.SetClipboardData.argtypes = [wintypes.UINT, wintypes.HANDLE]
                user32.SetClipboardData.restype = wintypes.HANDLE
                user32.CloseClipboard.restype = wintypes.BOOL

                kernel32.GlobalAlloc.argtypes = [wintypes.UINT, ctypes.c_size_t]
                kernel32.GlobalAlloc.restype = wintypes.HGLOBAL
                kernel32.GlobalLock.argtypes = [wintypes.HGLOBAL]
                kernel32.GlobalLock.restype = ctypes.c_void_p
                kernel32.GlobalUnlock.argtypes = [wintypes.HGLOBAL]
                kernel32.GlobalUnlock.restype = wintypes.BOOL
                kernel32.GlobalFree.argtypes = [wintypes.HGLOBAL]
                kernel32.GlobalFree.restype = wintypes.HGLOBAL
            except Exception:
                # If wintypes isn't available for some reason, continue without strict prototypes
                pass

            # Retry opening clipboard a few times (another app may be holding it)
            opened = False
            for _ in range(6):
                if user32.OpenClipboard(None):
                    opened = True
                    break
                time.sleep(0.05)
            if not opened:
                raise RuntimeError('OpenClipboard failed')

            try:
                user32.EmptyClipboard()
                hGlobal = kernel32.GlobalAlloc(GMEM_MOVEABLE, len(dib))
                if not hGlobal:
                    raise MemoryError('GlobalAlloc failed')
                pGlobal = kernel32.GlobalLock(hGlobal)
                if not pGlobal:
                    # GlobalLock failed — free and bail out
                    kernel32.GlobalFree(hGlobal)
                    raise MemoryError('GlobalLock failed')

                # Create a temporary ctypes buffer from dib and copy into global memory
                src = (ctypes.c_char * len(dib)).from_buffer_copy(dib)
                ctypes.memmove(pGlobal, ctypes.addressof(src), len(dib))

                kernel32.GlobalUnlock(hGlobal)
                # SetClipboardData takes ownership of hGlobal on success
                if not user32.SetClipboardData(CF_DIB, hGlobal):
                    # If SetClipboardData failed, free allocation
                    kernel32.GlobalFree(hGlobal)
                    raise RuntimeError('SetClipboardData failed')
            finally:
                user32.CloseClipboard()
        except Exception as e:
            messagebox.showerror('Clipboard Error', str(e))

    def _set_view_mode(self, mode: str):
        """Switch between 'color' block view and 'tiles' real-graphics view.

        Ensure the map and overlays are redrawn immediately so the UI reflects
        the mode change (labels/overlays depend on the mode).
        """
        prev_mode = self.view_mode.get()
        self.view_mode.set(mode)
        self._update_view_btn()

        is_tiles = mode == 'tiles'
        has_sar = getattr(self, '_sar', None) is not None
        has_mdt = getattr(self, 'mdt', None) is not None

        # Log the mode change first (user action feedback)
        if is_tiles:
            fname = getattr(self, '_display_name', '')
            tileset_grp = _mdt_tileset_grp(self.mdt, fname) if has_mdt else ''
            if tileset_grp in getattr(self._tile_gfx, '_pat', {}):
                n = len(self._tile_gfx._pat[tileset_grp])
                self._log(f'Render mode: Color Blocks → Real Tiles  ({tileset_grp}, {n} tiles)', 'info')
            else:
                self._log(f'Render mode: Color Blocks → Real Tiles  (loading...)', 'info')
        else:
            self._log('Render mode: Real Tiles → Color Blocks', 'dim')

        # Then load required GRP files
        if is_tiles and has_sar and has_mdt:
            fname = getattr(self, '_display_name', '')
            tileset_grp = _mdt_tileset_grp(self.mdt, fname)
            required_groups = [tileset_grp]

            npc_grps = get_mdt_npc_grps(fname)
            for ng in npc_grps:
                if ng not in required_groups:
                    required_groups.append(ng)

            for sar in getattr(self._sar, '_archives', []):
                for grp in required_groups:
                    is_loaded = (grp in getattr(self._tile_gfx, '_pat', {})) or (grp in getattr(self._tile_gfx, '_npc', {}))
                    if not is_loaded:
                        try:
                            missing = self._tile_gfx.load_groups_from_sar(sar.path, [grp])
                            if not missing:
                                name = grp.upper()
                                if 'PAT' in name:
                                    prefix = 'Tile: '
                                elif 'MAN' in name:
                                    prefix = 'NPC: '
                                else:
                                    prefix = ''
                                self._log(f'{prefix}{name} loaded from {os.path.basename(sar.path)}', 'info')
                        except Exception:
                            pass

            # Render after GRP files are loaded
            if getattr(self, 'renderer', None):
                self.renderer.draw_map()
                self.renderer.draw_overlays()
        else:
            # Clear tile cache when switching to color mode
            if getattr(self, '_tile_gfx', None):
                self._tile_gfx.clear_cache()
            if getattr(self, 'renderer', None):
                self.renderer.draw_map()
                self.renderer.draw_overlays()

    def _try_load_tiles_auto(self):
        """Try to load tile graphics from zelres2.sar automatically."""
        search_paths = [os.getcwd()]
        if hasattr(self, '_sar_dir') and self._sar_dir:
            search_paths.insert(0, self._sar_dir)
        if self.current_file:
            search_paths.insert(0, os.path.dirname(self.current_file))
        if self._sar:
            sar_path = getattr(self._sar, 'path', '')
            if sar_path:
                search_paths.insert(0, os.path.dirname(sar_path))

        seen = set()
        any_loaded = False
        for directory in search_paths:
            if directory in seen:
                continue
            seen.add(directory)
            for sar_name in ['zelres2.sar', 'ZELRES2.SAR', 'zelres1.sar', 'ZELRES1.SAR']:
                sar_path = os.path.join(directory, sar_name)
                if os.path.exists(sar_path):
                    self._log(f'Trying to load tile GFX from {sar_path}', 'dim')
                    missing = self._tile_gfx.load_from_sar(sar_path)
                    if self._tile_gfx.loaded:
                        any_loaded = True
                        msg = f'Tile GFX loaded from {sar_name}: ' + \
                              ', '.join(self._tile_gfx._pat.keys()) + \
                              '  NPC: ' + ', '.join(self._tile_gfx._npc.keys())
                        self.hover_txt.set(f'  {msg}')
                        self._log(msg, 'load')
                    else:
                        self._log(f'Failed to load tile GFX from {sar_path}: {", ".join(missing)}', 'warn')

        if any_loaded:
            return

        # Report what's missing
        status = self._tile_gfx.get_status()
        self.hover_txt.set(f'  {status}')
        self._log(f'Tile GFX not found: {status}', 'warn')
        from tkinter import messagebox
        messagebox.showinfo(
            'Tile Graphics — Files Not Found',
            'Real tile graphics require zelres2.sar\n'
            '(dpat.grp, mpat.grp, cpat.grp, mman.grp, cman.grp, tman.grp).\n\n'
            'Place zelres2.sar in the same folder as your MDT files.\n\n'
            f'Status: {self._tile_gfx.get_status()}\n\n'
            'Falling back to color-block view.'
        )
        self.view_mode.set('color')
        self._update_view_btn()

    def load_tile_graphics_from(self, path: str):
        """Public: load tile graphics from a SAR file or directory."""
        self._log(f'Trying to load tile GFX from {path}', 'info')
        if path.lower().endswith('.sar'):
            missing = self._tile_gfx.load_from_sar(path)
        else:
            missing = self._tile_gfx.load_from_dir(path)
        if self._tile_gfx.loaded:
            pats = ', '.join(self._tile_gfx._pat.keys())
            npcs = ', '.join(self._tile_gfx._npc.keys())
            self._log(f'Successfully loaded tile GFX from {path}: {pats}', 'load')
            self._log(f'NPC sprites: {npcs}', 'info')
        else:
            self._log(f'Failed to load tile GFX from {path}: {", ".join(missing)}', 'warn')
        self._tile_gfx.clear_cache()
        if self.mdt:
            self.renderer.draw_map()
        return missing

    @staticmethod
    def _is_loop_map(filename: str) -> bool:
        """Return True if this MDT file is a wrap-around (loop) map.
        Non-loop maps: mp?d.mdt (dungeons), mp84, mp80-83, mp90, mpa0.
        """
        if not filename:
            return False
        stem = os.path.splitext(os.path.basename(filename))[0].upper()
        # Town/common resource MDT files — no loop map
        _TOWN_STEMS = {'CMAP','MRMP','STMP','BSMP','HLMP','TMMP','DRMP',
                       'LLMP','PRMP','ESMP'}
        if stem in _TOWN_STEMS:
            return False
        # Dungeon maps: mpXd
        if len(stem) == 4 and stem[:2] == 'MP' and stem[3] == 'D':
            return False
        # Special non-loop outdoor maps
        if stem in {'MP84','MP90','MPA0'}:
            return False
        # mp80-mp83: these are world-8 multi-screens, still wrap
        # (only mp84 and mp8d are excluded above)
        return True

    def _update_loop_btn_state(self):
        """Enable/disable the Loop Map button depending on current map."""
        pass  # Now handled in View dialog


    def save_mdt(self):
        """Save the currently open MDT file (from SAR temp) to disk."""
        if not self.current_file or not self.file_data:
            return
        name = self._display_name or os.path.basename(self.current_file)
        path = filedialog.asksaveasfilename(
            title='Save MDT File',
            initialfile=name,
            defaultextension='.mdt',
            filetypes=[('MDT map files', '*.mdt'), ('All files', '*.*')])
        if not path:
            return
        with open(path, 'wb') as f:
            f.write(self.file_data)
        self.sar_browser.set_status(f'Saved: {os.path.basename(path)}',
                                    '#a6e3a1') if hasattr(self, 'sar_browser') else None


    def _toggle_sar_panel(self):
        """Toggle left SAR sidebar."""
        if hasattr(self, '_sar_sidebar'):
            self._sar_sidebar.toggle()

    def _toggle_info_collapse(self):
        """Toggle info sidebar (arrow button)."""
        if hasattr(self, '_info_sidebar'):
            self._info_sidebar.toggle()
            if hasattr(self, 'canvas'):
                self.canvas.update_idletasks()

    def _collapse_info_panel(self):
        """Collapse the info sidebar."""
        if hasattr(self, '_info_sidebar') and not self._info_sidebar.is_collapsed:
            self._info_sidebar.collapse()

    def _restore_info_panel(self):
        """Expand the info sidebar."""
        if hasattr(self, '_info_sidebar') and self._info_sidebar.is_collapsed:
            self._info_sidebar.expand()

    def _toggle_info_panel(self):
        """Toggle info sidebar (toolbar)."""
        self._toggle_info_collapse()

    def _refresh_overlays(self):
        """Redraw overlays using current path/label visibility settings."""
        if self.mdt:
            self.renderer.draw_map()
            self.renderer.draw_overlays()

    def _toggle_overlay(self):
        """Toggle overlay visibility."""
        self.show_overlay.set(not self.show_overlay.get())
        self.renderer.draw_overlays()

    def _toggle_wrap(self):
        """Toggle wrap-around ghost map display."""
        self.wrap_var.set(not self.wrap_var.get())
        if self.mdt:
            self.renderer.draw_map()
            self.renderer.draw_overlays()

    def _toggle_show(self, which):
        """Toggle NPC / Monster / Item visibility."""
        if which == 'npc':
            self.show_npc_var.set(not self.show_npc_var.get())
        elif which == 'monster':
            self.show_monster_var.set(not self.show_monster_var.get())
        elif which == 'item':
            self.show_item_var.set(not self.show_item_var.get())
        if self.mdt:
            self.renderer.draw_overlays()

    # ── Paths popup ───────────────────────────────────────────────────────────
    # ── Overlay Treeview helpers ──────────────────────────────────────────────
    def _on_tv3_click(self, event=None):
        """Click on overlay Treeview row — focus canvas on that entity."""
        sel = self._tv3.selection()
        if not sel:
            return
        iid = sel[0]
        vals = self._tv3.item(iid, 'values')
        obj_label = vals[0].strip() if vals else ''
        if obj_label:
            self._focus_entity_by_label(obj_label)

    def _tv3_select_all(self, event=None):
        children = self._tv3.get_children()
        if children:
            self._tv3.selection_set(children)
        return 'break'

    def _tv3_copy(self, event=None):
        sel = self._tv3.selection() or self._tv3.get_children()
        lines = []
        for iid in sel:
            vals = self._tv3.item(iid, 'values')
            lines.append('\t'.join(str(v) for v in vals))
        self.clipboard_clear()
        self.clipboard_append('\n'.join(lines))
        return 'break'

    # ── NPC Speech ────────────────────────────────────────────────────────────
    def _set_npc_speech(self, npc, force_index=None):
        """Update the NPC speech panel with colored control sequences.
        force_index: NPC list index to use for text lookup (bypasses label parsing).
        The panel always shows hovered NPC dialogue (no lock); locking is handled
        via the tooltip.
        """
        txt = self.npc_speech_txt
        txt.config(state='normal')
        txt.delete('1.0', 'end')
        if npc is None:
            self._hovered_npc_label = None
            if not (self.tooltip and self.tooltip.is_pinned()):
                self._npc_anim_stop()
            self.npc_speech_lbl.config(
                text='  hover over an NPC to read their dialogue', fg=self.C_DIM)
        else:
            # Stop animation if switching to a different NPC (only when not pinned)
            if self._npc_anim_label and self._npc_anim_label != npc.label:
                if not (self.tooltip and self.tooltip.is_pinned()):
                    self._npc_anim_stop()
            self._hovered_npc_label = npc.label
            # NPC texts dict is keyed by index (0,1,2...) not by npc_id byte value
            if force_index is not None:
                npc_idx = force_index
            elif npc.label.startswith('N'):
                npc_idx = int(npc.label[1:]) - 1
            else:
                npc_idx = 0
            texts = self.mdt.npc_texts if self.mdt else {}
            raw_speech = texts.get(npc_idx, '') if texts else ''
            # Skip header update during animation (animation tick handles it)
            if not self._npc_anim_timer or self._npc_anim_label != npc.label:
                self.npc_speech_lbl.config(
                    text=f'  {npc.label}  npc_id={npc.npc_id & 0x0F:#04x}  idx={npc_idx}', fg=self.C_YELL)
            if raw_speech:
                import re
                parts = re.split(r'(\[SPEECH PAUSE\]|\[0x[0-9A-Fa-f]+\])', raw_speech)
                for part in parts:
                    if part == '[SPEECH PAUSE]':
                        txt.insert('end', '[SPEECH PAUSE]\n', 'ctrl')
                    elif part.startswith('[0x') and part.endswith(']'):
                        txt.insert('end', part, 'raw')
                    else:
                        txt.insert('end', part.replace("\\", "'"))
            else:
                txt.insert('end', '(no dialogue found)')
        # Keep widget editable for selection (don't disable)

    # ── Info Panel Update ─────────────────────────────────────────────────────
    def _update_info(self):
        """Update all info boxes with current map data."""
        m = self.mdt
        d = self.file_data
        if not m or not d:
            return

        mw, mh = m.map_width, m.map_height
        total = mw * mh
        flat = [m.grid[r][c] for r in range(mh) for c in range(mw)]
        cnt = Counter(flat)
        fname = os.path.basename(self.current_file) if self.current_file else ''

        _name_for_type = self._display_name or self.current_file or ''
        mtype = get_map_type_info(_name_for_type) if _name_for_type else 'Unknown'

        for txt in [self.info_txt1, self.info_txt2, self.info_txt4]:
            txt.config(state='normal')
            txt.delete('1.0', 'end')
        # Clear overlay treeview
        self._tv3.delete(*self._tv3.get_children())
        self._tv3_entity_iids.clear()

        T = self.info_txt1

        def kv(key, val, vt='v'):
            T.insert('end', f'  {key:<18}', 'k')
            T.insert('end', f'{val}\n', vt)

        def sep():
            T.insert('end', '  ' + '-' * 34 + '\n', 's')

        def sec(title):
            T.insert('end', f'\n  [ {title} ]\n', 'sec')

        # Box 1: File Info, Map Structure, Compression / Map data
        sec('File Info')
        # For SAR-loaded files, fname is the original name; current_file is the temp path
        _from_sar = (self._display_name and
                     self._display_name != os.path.basename(self.current_file))
        if _from_sar:
            _sar_path = getattr(self._sar, 'path', '') if self._sar else ''
            _sar_name = os.path.basename(_sar_path) if _sar_path else 'SAR'
            kv('Filename', self._display_name)
            kv('Source', f'{_sar_name}  (SAR archive)', 'd')
        else:
            kv('Filename', fname)
        kv('File size', f'{len(d):,} bytes')
        kv('Map type', mtype)
        
        # Show map/place name from parsed name_ptr structure
        if m.is_town and m.town_name:
            kv('Place name', m.town_name.replace(chr(92), chr(39)), 'y')
        elif not m.is_town and getattr(m, 'cavern_name', ''):
            kv('Place name', m.cavern_name.replace(chr(92), chr(39)), 'y')
            kv('Name color', f'0x{m.name_color:2X}', 'd')
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

        # Box 2: Header Pointers, Raw Header
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

        sep()
        sec('Raw Header  +0x00..+0x1A')
        for o in range(0, min(0x1B, len(d)), 4):
            chunk = d[o:o + 4]
            hexs = ' '.join(f'{b:02X}' for b in chunk)
            ascs = ''.join(chr(b) if 0x20 <= b < 0x7F else '.' for b in chunk)
            T.insert('end', f'  +{o:02X}  {hexs:<11}  {ascs}\n', 'd')

        # Box 3: Overlay Treeview — entities
        TV = self._tv3

        def tv_sec(title):
            TV.insert('', 'end', values=(title, '', '', '', '', ''), tags=('sec',))

        def tv_entity(lbl, tag='entity'):
            iid = TV.insert('', 'end', values=(lbl, '', '', '', '', ''), tags=(tag,))
            self._tv3_entity_iids[lbl.strip()] = iid
            return iid

        _ATTR_TAG = {
            'x': 'hp_xi', 'x_init': 'hp_xi', 'x1': 'hp_xi', 'spwn_x': 'hp_xi',
            'y': 'hp_yf', 'y_fix': 'hp_yf', 'y_init': 'hp_yf', 'spawn': 'hp_yf', 'spwn_y': 'hp_yf',
            'x_left': 'hp_xl', 'left': 'hp_xl',
            'x_right': 'hp_xr', 'right': 'hp_xr', 'y1': 'hp_xr', 'y_end': 'hp_xr',
            'type': 'rb_type', 'spwn_type': 'rb_type', 'door_type': 'rb_type',
            'id': 'rb_id', 'map_id': 'rb_id', 'npc_id': 'rb_id', 'init_dir': 'rb_id',
            'flags': 'rb_flag', 'flags2': 'rb_flag', 'y_flag': 'rb_flag',
            'act': 'rb_act',
            'size': 'hp_xl', 'unk': 'dim', 'dest': 'dim', 'tile': 'c',
        }

        def tv_row(attr, mask_str, hex_str, dec_str, name_str=''):
            tag = _ATTR_TAG.get(attr, 'dim')
            TV.insert('', 'end',
                      values=('', attr, mask_str, hex_str, dec_str, name_str),
                      tags=(tag,))

        def tv_raw(raw_str):
            TV.insert('', 'end',
                      values=('', 'raw', '', raw_str, '', ''),
                      tags=('raw',))

        def parse_fmtW(raw_val, mask=0xFFFF):
            v = raw_val & mask
            mask_str = f'0x{raw_val:04X} & 0x{mask:04X}'
            hex_str  = f'0x{v:04X}'
            dec_str  = str(v)
            return mask_str, hex_str, dec_str

        def parse_fmtB(raw_val, mask=0xFF):
            v = raw_val & mask
            mask_str = f'0x{raw_val:02X} & 0x{mask:02X}'
            hex_str  = f'0x{v:02X}'
            dec_str  = str(v)
            return mask_str, hex_str, dec_str

        if m.is_town:
            tv_sec(f'Town Doors  ({len(m.town_doors)})')
            for td in m.town_doors:
                tv_entity(td.label)
                tv_row('x',         *parse_fmtW(td.x))
                tv_row('door_type', *parse_fmtB(td.door_type))
                tv_raw(td.raw)

            tv_sec(f'NPCs  ({len(m.npcs)})')
            for npc in m.npcs:
                tv_entity(npc.label)
                tv_row('x',         *parse_fmtW(npc.x))
                tv_row('npc_id',    *parse_fmtB(npc.npc_id, 0x0F))
                dir_label = 'left' if (npc.npc_id & 0x80) else 'right'
                tv_row('init_dir',  *parse_fmtB(npc.npc_id, 0xF0), dir_label)
                tv_row('head_tile', *parse_fmtB(npc.head_tile))
                tv_row('anim_phase',*parse_fmtB(npc.anim_phase))
                tv_row('ai_type',   *parse_fmtB(npc.ai_type))
                tv_row('flags',     *parse_fmtB(npc.flags))
                tv_row('facing',    *parse_fmtB(npc.facing))
                tv_raw(npc.raw)

            npc_texts = m.npc_texts if hasattr(m, 'npc_texts') else {}
            tv_sec(f'NPC Strings  ({len(npc_texts)})')
            for i, (npc_id, text) in enumerate(sorted(npc_texts.items()), 1):
                TV.insert('', 'end',
                          values=(f'[{i}]', f'id={npc_id}', '', '', '', text[:60]),
                          tags=('dim',))
        else:
            tv_sec(f'Doors  ({len(m.doors)})')
            for dr in m.doors:
                icon = '[KEY]' if dr.needs_key else ('[TWN]' if dr.is_town else '[   ]')
                tv_entity(dr.label, tag='p')
                TV.insert('', 'end', values=('', 'dtype', '', icon, '', dr.dtype), tags=('p',))
                tv_row('x',      *parse_fmtW(dr.x))
                tv_row('y',      *parse_fmtB(dr.y))
                tv_row('flags',  *parse_fmtB(dr.flags))
                tv_row('map_id', *parse_fmtB(dr.map_id))
                tv_row('x1',     *parse_fmtW(dr.x1))
                dest_y_hex = 'town' if dr.is_town else f'0x{dr.y1 & 0xFFFF:04X}'
                dest_y_dec = 'town' if dr.is_town else str(dr.y1 & 0xFFFF)
                TV.insert('', 'end',
                          values=('', 'y1', f'0x{dr.y1:04X} & 0xFFFF' if not dr.is_town else '',
                                  dest_y_hex, dest_y_dec, dr.dest),
                          tags=('hp_xr',))
                tv_row('unk',    *parse_fmtW(dr.unk))
                tv_row('flags2', *parse_fmtB(dr.flags2))
                tv_raw(dr.raw)

            tv_sec(f'Monsters  ({len(m.monsters)})')
            for mo in m.monsters:
                name_str = _MONSTER_TYPE_NAMES.get(mo.type, '')
                tv_entity(mo.label)
                tv_row('x',         *parse_fmtW(mo.x))
                tv_row('y',         *parse_fmtB(mo.y))
                tv_row('type',      *parse_fmtB(mo.type), name_str)
                tv_row('spwn_x',    *parse_fmtW(mo.spwn_x))
                tv_row('spwn_y',    *parse_fmtB(mo.spwn_y))
                tv_row('spwn_type', *parse_fmtB(mo.spwn_type), _MONSTER_TYPE_NAMES.get(mo.spwn_type,''))
                tv_row('act',       *parse_fmtB(mo.act))
                tv_raw(mo.raw)

            tv_sec(f'Items  ({len(m.items)})')
            for it in m.items:
                name_str = _ITEM_TYPE_NAMES.get(it.type, '')
                tv_entity(it.label)
                tv_row('x',      *parse_fmtW(it.x))
                tv_row('y',      *parse_fmtB(it.y))
                tv_row('type',   *parse_fmtB(it.type), name_str)
                tv_row('spwn_x', *parse_fmtW(it.spwn_x))
                tv_row('spwn_y', *parse_fmtB(it.spwn_y))
                tv_raw(it.raw)

            tv_sec(f'V-Platforms  ({len(m.vplats)})')
            for vp in m.vplats:
                y_i = getattr(vp, 'y_init', getattr(vp, 'y_end', vp.size))
                tv_entity(vp.label)
                tv_row('Manual', '', '', '')
                tv_row('x_init', '', f'0x{vp.x:02X}', str(vp.x))
                tv_row('spawn',  '', f'0x{vp.y:02X}', str(vp.y), 'always 0')
                tv_row('y_init', '', f'0x{y_i:02X}', str(y_i))
                tv_raw(vp.raw)

            tv_sec(f'C-Platforms  ({len(m.cplats)})')
            for cp in m.cplats:
                y_i = getattr(cp, 'y_init', getattr(cp, 'y_end', cp.size))
                tv_entity(cp.label)
                tv_row('Auto', '', '', '')
                tv_row('x_init', '', f'0x{cp.x:02X}', str(cp.x))
                tv_row('spawn',  '', f'0x{cp.y:02X}', str(cp.y), 'always 0')
                tv_row('y_init', '', f'0x{y_i:02X}', str(y_i))
                tv_raw(cp.raw)

            tv_sec(f'H-Platforms  ({len(m.hplats)})')
            for hp in m.hplats:
                parts = hp.raw.split()
                x_init_raw  = (int(parts[1], 16) << 8) | int(parts[0], 16)
                y_fix_raw   = int(parts[2], 16)
                x_left_raw  = (int(parts[4], 16) << 8) | int(parts[3], 16)
                x_right_raw = (int(parts[6], 16) << 8) | int(parts[5], 16)
                tv_entity(hp.label)
                tv_row('Auto', '', '', '')
                tv_row('x_init',  *parse_fmtW(x_init_raw,  0x0FFF))
                tv_row('y_fix',   *parse_fmtB(y_fix_raw,   0x7F))
                tv_row('x_left',  *parse_fmtW(x_left_raw,  0x0FFF))
                tv_row('x_right', *parse_fmtW(x_right_raw, 0x0FFF))
                tv_raw(hp.raw)

            tv_sec('Tear (Boss Door)')
            if m.tear_x or m.tear_y:
                _tx = m.tear_x; _ty = m.tear_y
                tv_entity('T', tag='y')
                tv_row('x', *parse_fmtW(_tx))
                tv_row('y', *parse_fmtB(_ty))
                tv_raw(f'{_tx & 0xFF:02X} {(_tx >> 8) & 0xFF:02X} {_ty:02X}')

            signs = getattr(m, 'signs', [])
            tv_sec(f'Signs / Notice Boards  ({len(signs)})')
            for sg in signs:
                tv_entity(sg.label, tag='g')
                raw_b = sg.raw if isinstance(sg.raw, (bytes, bytearray)) else b''
                if len(raw_b) >= 4:
                    tv_row('x_screen', '', f'0x{raw_b[0]:02X}', str(raw_b[0]),
                           f'pixel={raw_b[0]*8}px')
                    tv_row('y_screen', '', f'0x{raw_b[1]:02X}', str(raw_b[1]),
                           f'pixel={raw_b[1]*8}px')
                    tv_row('x_tile', '', str(raw_b[2]), str(raw_b[2]), 'tile col')
                    tv_row('y_tile', '', str(raw_b[3]), str(raw_b[3]), 'tile row')
                for line in sg.text.split('\n'):
                    pfx = '[C] ' if line.startswith(',') else '    '
                    body = line[1:] if line.startswith(',') else line
                    TV.insert('', 'end',
                              values=('', 'text', '', '', '', pfx + body),
                              tags=('g',))
                raw_hex = ' '.join(f'{b:02X}' for b in raw_b)
                tv_raw(raw_hex)

            achv = getattr(m, 'achv_items', [])
            tv_sec(f'Achv-Items Check Table  ({len(achv)} entries)')
            for ai in achv:
                tv_entity(ai.label, tag='dim')
                tv_raw(ai.raw)


        # Box 4: Tile Frequency
        T = self.info_txt4
        sec('Tile Frequency  Top 20')
        for tile, count in cnt.most_common(20):
            pct = count / total * 100
            T.insert('end',
                     f'  #{tile:2d}  {count:6d}  {pct:5.1f}%  {PALETTE[tile % 64]}\n', 'd')

        for txt in [self.info_txt1, self.info_txt2, self.info_txt4]:
            txt.config(state='disabled')

        # Update legend button counts
        if hasattr(self, '_legend_btns'):
            self._update_legend_counts()

    def _update_legend_counts(self):
        """Update legend buttons with entity counts."""
        m = self.mdt
        if not m:
            return
        counts = {
            'D': len(m.doors),
            'M': len(m.monsters),
            'I': len(m.items),
            'N': len(m.npcs),
            'VP': len(m.vplats),
            'CP': len(m.cplats),
            'HP': len(m.hplats),
            'S': len(m.signs),
            'T': 1 if m.tear_x is not None else 0,
        }
        prefixes = ['D', 'M', 'I', 'N', 'VP', 'CP', 'HP', 'S', 'T']
        btn_map = {
            'D': 'D=Door',
            'M': 'M=Monster',
            'I': 'I=Item',
            'N': 'N=NPC',
            'VP': 'VP=V-Platform',
            'CP': 'CP=C-Platform',
            'HP': 'HP=H-Platform',
            'S': 'S=Sign',
            'T': 'T=Tear(Boss)',
        }
        for p in prefixes:
            if p in self._legend_btns:
                c = counts.get(p, 0)
                base = btn_map.get(p, p)
                self._legend_btns[p].config(text=f'{base} ({c})')

    # ── Mouse Events ──────────────────────────────────────────────────────────

    def _draw_ghost_overlays(self, bs: int, font, pad: int):
        """Draw entity overlay labels on the 8 ghost copies (Loop Map mode)."""
        if not self.mdt:
            return
        mw = self.mdt.map_width
        mh = self.mdt.map_height
        ox  = mw * bs   # center copy origin
        oy  = mh * bs

        def ghost_label(e_x, e_y, text, bg='#000000', fg='#ffffff'):
            """Place a dimmed label at each of the 8 ghost copy positions."""
            for (dgx, dgy) in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]:
                cx_ = ox + dgx * mw * bs + e_x * bs + bs // 2
                cy_ = oy + dgy * mh * bs + e_y * bs + bs // 2
                # Dim the colors for ghost copies
                dim_bg = '#1a1a1a'
                dim_fg = '#888888'
                tid = self.canvas.create_text(cx_, cy_, text=text,
                    fill=dim_fg, font=font, anchor='center')
                bb  = self.canvas.bbox(tid)
                if bb:
                    rid = self.canvas.create_rectangle(
                        bb[0]-pad, bb[1]-pad, bb[2]+pad, bb[3]+pad,
                        fill=dim_bg, outline='#444444', width=1)
                    self.canvas.tag_raise(tid)
                    self.overlay_ids += [rid, tid]
                else:
                    self.overlay_ids.append(tid)

        m = self.mdt
        for d in m.doors:       ghost_label(d.x, d.y, d.label)
        for mo in m.monsters:   ghost_label(mo.x, mo.y, mo.label)
        for it in m.items:      ghost_label(it.x, it.y, it.label)
        for sg in getattr(m, 'signs', []):
            ghost_label(sg.x, sg.y, sg.label)
        if m.tear_x or m.tear_y:
            ghost_label(m.tear_x, m.tear_y, 'T')
        # VP/CP: only draw ghost label if platform wraps across a map edge.
        # Closed VPs (case 0) stay within bounds — skip ghost copies for them.
        grid_data = m.grid
        mh_ = m.map_height
        for vp in m.vplats:
            col_idx = vp.x % m.map_width
            y_dest  = getattr(vp, 'y_init', getattr(vp, 'y_end', vp.size))
            dest_cl = min(max(y_dest, 0), mh_ - 1)
            # Scan for top wall
            open_top = all(grid_data[r][col_idx] == 0 for r in range(dest_cl))
            # Scan for bottom wall
            open_bot = all(grid_data[r][col_idx] == 0 for r in range(dest_cl + 1, mh_))
            if open_top or open_bot:
                ghost_label(vp.x, vp.y, vp.label)
        for cp in m.cplats:
            col_idx = cp.x % m.map_width
            y_dest  = getattr(cp, 'y_init', getattr(cp, 'y_end', cp.size))
            dest_cl = min(max(y_dest, 0), mh_ - 1)
            open_bot = all(grid_data[r][col_idx] == 0 for r in range(dest_cl + 1, mh_))
            if open_bot:
                ghost_label(cp.x, cp.y, cp.label)
        for hp in m.hplats:     ghost_label(hp.x, hp.y, hp.label)

    def _canvas_to_tile(self, cx: float, cy: float):
        """Convert canvas pixel coords to (col, row) accounting for wrap offset."""
        bs  = self.block_size
        mw  = self.mdt.map_width
        mh  = self.mdt.map_height
        wrap = self.wrap_var.get() and not self.mdt.is_town
        ox  = (mw * bs) if wrap else 0
        oy  = (mh * bs) if wrap else 0
        # Translate to center-copy coords then tile index (with wrap modulo)
        col = int((cx - ox) // bs) % mw
        row = int((cy - oy) // bs) % mh
        return col, row

    def _on_motion(self, event):
        """Handle mouse motion over the canvas."""
        if not self.mdt:
            return
        bs = self.block_size
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        mw, mh = self.mdt.map_width, self.mdt.map_height
        wrap = self.wrap_var.get() and not self.mdt.is_town
        bs_  = self.block_size
        ox_  = (mw * bs_) if wrap else 0
        oy_  = (mh * bs_) if wrap else 0
        # Relative tile coords (negative on left/top ghost copies)
        rel_col = int((cx - ox_) // bs_)
        rel_row = int((cy - oy_) // bs_)
        # Wrapped tile index for grid lookup
        col = rel_col % mw
        row = rel_row % mh
        if 0 <= col < mw and 0 <= row < mh:
            tile = self.mdt.grid[row][col]
            self.hover_txt.set(
                f'  x:{rel_col:4d} ({rel_col:#06x})   y:{rel_row:3d} ({rel_row:#06x})   tile: {tile}')
        else:
            self.hover_txt.set('')

        entity = self._hit_entity(cx, cy)
        if self.tooltip and self.tooltip.is_pinned():
            pass  # don't overwrite pinned tooltip
        elif entity and self.tooltip:
            rx = self.winfo_pointerx()
            ry = self.winfo_pointery()
            self.tooltip.show(rx, ry, self._make_tip(entity))
        elif self.tooltip:
            self.tooltip.hide()

        # Update NPC speech panel when hovering an NPC on a town map
        if self.mdt and self.mdt.is_town:
            npc = entity if (entity and hasattr(entity, 'label') and entity.label.startswith('N')) else None
            self._set_npc_speech(npc)

    def _npc_anim_stop(self):
        """Stop any running NPC animation."""
        if self._npc_anim_timer:
            self.after_cancel(self._npc_anim_timer)
            self._npc_anim_timer = None
        self._npc_anim_label = None
        self._npc_anim_frame = 0
        if self.tooltip and self.tooltip.is_pinned():
            self.tooltip._update_btn_states(self)

    def _npc_anim_toggle(self, direction: str):
        """Toggle NPC animation on/off for the given direction ('left' or 'right')."""
        # Use locked NPC label when tooltip is pinned, otherwise hovered label
        if self.tooltip and self.tooltip.is_pinned() and self._locked_npc:
            label = self._locked_npc.label
        else:
            label = getattr(self, '_hovered_npc_label', None)
        if not label or not self.mdt or not self.mdt.is_town:
            return
        # If same direction is already animating, stop it
        if self._npc_anim_label == label and self._npc_anim_timer and self._npc_anim_frame is not None:
            self._npc_anim_stop()
            return
        # Stop any prior animation
        self._npc_anim_stop()
        self._npc_anim_label = label
        self._npc_anim_frame = 0
        self._npc_anim_range = (0, 3) if direction == 'left' else (4, 7)
        if self.tooltip and self.tooltip.is_pinned():
            self.tooltip._update_btn_states(self)
        self._npc_anim_tick()

    def _npc_anim_tick(self):
        """Animation tick — advance one frame and schedule next."""
        label = self._npc_anim_label
        if not label or not self.mdt or not self.mdt.is_town:
            self._npc_anim_stop()
            return
        # Cycle through frame range
        lo, hi = self._npc_anim_range
        offset = lo + self._npc_anim_frame
        # Set preview sprite: base npc_id + offset
        for n in self.mdt.npcs:
            if n.label == label:
                # Use override NPC ID from pinned tooltip scale if available
                if self.tooltip and self.tooltip.is_pinned():
                    try:
                        override_id = int(self.tooltip._npc_id_var.get()) & 0x0F
                    except (ValueError, AttributeError):
                        override_id = n.npc_id & 0x0F
                else:
                    override_id = n.npc_id & 0x0F
                base = override_id * 8
                sprite = base + offset
                self._npc_sprite_preview[label] = sprite
                self.renderer.draw_overlays()
                # Update pinned tooltip content if tooltip is pinned
                if self.tooltip and self.tooltip.is_pinned():
                    self.tooltip.update_pinned(self._make_tip(n), self)
                break
        self._npc_anim_frame = (self._npc_anim_frame + 1) % (hi - lo + 1)
        self._npc_anim_timer = self.after(self._npc_anim_interval, self._npc_anim_tick)

    def _on_leave(self, event):
        """Handle mouse leaving the canvas."""
        self.hover_txt.set('')
        if self.tooltip and not self.tooltip.is_pinned():
            self.tooltip.hide()
        if self.mdt and self.mdt.is_town:
            self._set_npc_speech(None)

    def _on_wheel(self, event):
        """Mouse wheel: zoom in/out at cursor position (Google Maps style).
        Ctrl+wheel: scroll vertically (legacy). Shift+wheel: scroll horizontally.
        """
        # Determine scroll direction
        if event.num == 4 or event.delta > 0:
            direction = 1   # up / zoom in
        else:
            direction = -1  # down / zoom out

        if event.state & 0x4:
            # Ctrl held — vertical scroll
            self.canvas.yview_scroll(-direction * 3, 'units')
            return
        if event.state & 0x1:
            # Shift held — horizontal scroll
            self.canvas.xview_scroll(-direction * 3, 'units')
            return

        # Default: zoom centered on mouse cursor
        if not self.mdt:
            if direction > 0:
                self.zoom_in()
            else:
                self.zoom_out()
            return

        # Get canvas position of mouse before zoom
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        old_bs = self.block_size

        if direction > 0:
            self.zoom_in()
        else:
            self.zoom_out()

        new_bs = self.block_size
        if new_bs == old_bs:
            return  # already at limit

        # Adjust scroll so the tile under the cursor stays in place
        scale = new_bs / old_bs
        new_cx = cx * scale
        new_cy = cy * scale

        mw = self.mdt.map_width
        mh = self.mdt.map_height
        wrap = self.wrap_var.get() and not self.mdt.is_town
        W = mw * new_bs * (3 if wrap else 1)
        H = mh * new_bs * (3 if wrap else 1)
        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()

        xfrac = max(0.0, min(1.0, (new_cx - event.x) / max(W - cw, 1)))
        yfrac = max(0.0, min(1.0, (new_cy - event.y) / max(H - ch, 1)))
        self.canvas.xview_moveto(xfrac)
        self.canvas.yview_moveto(yfrac)

    def _on_info_entity_click(self, event):
        """Click on entity label in info panel - focus canvas on that entity."""
        widget = event.widget
        idx = widget.index(f'@{event.x},{event.y}')
        tags = widget.tag_names(idx)
        for tag in tags:
            if tag.startswith('ent:'):
                label = tag[4:]
                self._focus_entity_by_label(label)
                return

    def _scroll_info_to_prefix(self, prefix: str):
        """Scroll overlay Treeview to first entity matching prefix."""
        target = None
        for lbl in self._tv3_entity_iids:
            if lbl == prefix or (lbl.startswith(prefix) and
                                  len(lbl) > len(prefix) and lbl[len(prefix)].isdigit()):
                target = lbl
                break
        if target:
            iid = self._tv3_entity_iids[target]
            self._tv3.see(iid)
            self._tv3.selection_set(iid)

    def _scroll_info_to_label(self, label: str):
        """Scroll overlay Treeview to the entity row with given label."""
        iid = self._tv3_entity_iids.get(label.strip())
        if iid:
            self._tv3.see(iid)
            self._tv3.selection_set(iid)

    def _focus_entity_by_label(self, label: str):
        """Find entity by label string and scroll canvas to it."""
        if not self.mdt:
            return
        all_ents = (list(self.mdt.doors) + list(self.mdt.monsters) +
                    list(self.mdt.items) + list(getattr(self.mdt, 'signs', [])))
        if not self.mdt.is_town:
            if self.mdt.tear_x or self.mdt.tear_y:
                import types
                tear = types.SimpleNamespace(label='T', x=self.mdt.tear_x, y=self.mdt.tear_y)
                all_ents.append(tear)
            all_ents += list(self.mdt.vplats) + list(self.mdt.cplats) + list(self.mdt.hplats)
        else:
            all_ents += list(self.mdt.town_doors) + list(self.mdt.npcs)
        for e in all_ents:
            if getattr(e, 'label', '') == label:
                self._focus_entity(e)
                return

    def _on_canvas_click(self, event):
        """Left-click: unpin tooltip if clicking same NPC or empty space."""
        if not self.mdt or not self.show_overlay.get():
            return
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        entity = self._hit_entity(cx, cy)
        # Unpin when clicking the same NPC or empty space
        if self.tooltip and self.tooltip.is_pinned():
            if entity and getattr(entity, 'label', '') == self._locked_npc.label:
                self.tooltip.hide()
                self._npc_locked = False
                self._locked_npc = None
                self._npc_anim_stop()
            elif not entity or not entity.label.startswith('N'):
                self.tooltip.hide()
                self._npc_locked = False
                self._locked_npc = None
                self._npc_anim_stop()
        if entity:
            self._focus_entity(entity)
            lbl = getattr(entity, 'label', '')
            if lbl:
                self._scroll_info_to_label(lbl)

    def _on_canvas_double_click(self, event):
        """Double-click: pin tooltip on that NPC with play buttons."""
        if not self.mdt or not self.show_overlay.get():
            return
        cx = self.canvas.canvasx(event.x)
        cy = self.canvas.canvasy(event.y)
        entity = self._hit_entity(cx, cy)
        if entity and hasattr(entity, 'label') and entity.label.startswith('N'):
            self._npc_locked = True
            self._locked_npc = entity
            rx = self.winfo_pointerx()
            ry = self.winfo_pointery()
            self.tooltip.show_pinned(rx, ry, self._make_tip(entity), self)
            self._set_npc_speech(entity)

    def _focus_entity(self, entity):
        """Scroll canvas so the entity is centered in the viewport."""
        bs  = self.block_size
        mw  = self.mdt.map_width
        mh  = self.mdt.map_height
        wrap = self.wrap_var.get() and not self.mdt.is_town
        cx_count = 3 if wrap else 1
        cy_count = 3 if wrap else 1
        W = mw * bs * cx_count
        H = mh * bs * cy_count
        # Wrap adds 1 copy offset to the center
        ox = (mw * bs) if wrap else 0
        oy = (mh * bs) if wrap else 0
        ex = ox + entity.x * bs + bs // 2
        if self.mdt.is_town:
            from ..core.constants import TOWN_HEIGHT
            ey = oy + (TOWN_HEIGHT - 2) * bs + bs // 2
        else:
            ey = oy + entity.y * bs + bs // 2
        cw = self.canvas.winfo_width()
        ch = self.canvas.winfo_height()
        xfrac = max(0.0, min(1.0, (ex - cw / 2) / max(W - cw, 1)))
        yfrac = max(0.0, min(1.0, (ey - ch / 2) / max(H - ch, 1)))
        self.canvas.xview_moveto(xfrac)
        self.canvas.yview_moveto(yfrac)

    def _on_right_click(self, event):
        """Start right mouse button drag."""
        self.canvas.scan_mark(event.x, event.y)

    def _on_right_drag(self, event):
        """Pan canvas with right mouse button drag."""
        self.canvas.scan_dragto(event.x, event.y, gain=1)

    def _on_right_release(self, event):
        """End right mouse button drag."""
        pass

    def _hit_entity(self, cx, cy):
        """Find entity at canvas coordinates (works in both normal and loop-map mode)."""
        if not self.mdt or not self.show_overlay.get():
            return None
        bs   = self.block_size
        mw_h = self.mdt.map_width
        mh_h = self.mdt.map_height
        wrap = self.wrap_var.get() and not self.mdt.is_town
        ox   = (mw_h * bs) if wrap else 0
        oy   = (mh_h * bs) if wrap else 0
        # Translate canvas coords to center-copy pixel coords (wrap-aware)
        lx   = cx - ox
        ly   = cy - oy
        thresh = (max(bs, 8) * 0.9) ** 2
        best = None
        best_d = thresh
        is_town = self.mdt.is_town
        ground_row = (TOWN_HEIGHT - 2) if is_town else 0

        all_entities = (list(self.mdt.doors) + list(self.mdt.monsters) +
                        list(self.mdt.items) + list(getattr(self.mdt, 'signs', [])))

        # Add platforms — store actual Platform objects so _make_tip can access .raw/.size/.ptype
        for vp in self.mdt.vplats:
            all_entities.append(vp)          # use platform's own (x,y) as hit target
        for cp in self.mdt.cplats:
            all_entities.append(cp)
        for hp in self.mdt.hplats:
            all_entities.append(hp)

        # Tear pseudo-entity
        if not is_town and (self.mdt.tear_x or self.mdt.tear_y):
            all_entities.append(type('Tear', (), {
                'label': 'T', 'x': self.mdt.tear_x, 'y': self.mdt.tear_y, '_is_tear': True
            })())

        if is_town:
            all_entities.extend(self.mdt.town_doors)
            all_entities.extend(self.mdt.npcs)

        for e in all_entities:
            ex = e.x * bs + bs // 2
            ey = (ground_row if is_town else e.y) * bs + bs // 2
            # Distance in center-copy coordinates; wrap: check all 9 copies
            if wrap:
                # Find minimum distance across ghost copies
                min_d = float('inf')
                for dgx in (-1, 0, 1):
                    for dgy in (-1, 0, 1):
                        d = (lx - (ex + dgx * mw_h * bs)) ** 2 +                             (ly - (ey + dgy * mh_h * bs)) ** 2
                        if d < min_d:
                            min_d = d
                d = min_d
            else:
                # For doors with 2x4 box, check entire area
                if e.label and e.label.startswith('D'):
                    dx = e.x * bs
                    dy = e.y * bs
                    # Town doors use ground_row - 4, dungeon doors use e.y
                    if is_town:
                        dy = (TOWN_HEIGHT - 2) * bs
                    dw, dh = 2 * bs, 4 * bs
                    if dx <= lx < dx + dw and dy <= ly < dy + dh:
                        best = e
                        break
                    continue
                d = (lx - ex) ** 2 + (ly - ey) ** 2
            if d < best_d:
                best_d = d
                best = e
            # For platforms, also check destination point (where label is displayed)
            if e.label and e.label.startswith(('VP', 'CP', 'HP')):
                if e.label.startswith(('VP', 'CP')):
                    dest_y = getattr(e, 'y_init', getattr(e, 'y_end', e.size))
                else:  # HP
                    dest_y = e.y
                dex = e.x * bs + bs // 2
                dey = dest_y * bs + bs // 2
                if wrap:
                    min_d = float('inf')
                    for dgx in (-1, 0, 1):
                        for dgy in (-1, 0, 1):
                            d = (lx - (dex + dgx * mw_h * bs)) ** 2 + (ly - (dey + dgy * mh_h * bs)) ** 2
                            if d < min_d:
                                min_d = d
                    d = min_d
                else:
                    d = (lx - dex) ** 2 + (ly - dey) ** 2
                if d < best_d:
                    best_d = d
                    best = e
        return best

    # Color-tag map for raw bytes (mirrors info-panel rb_ tags)
    _RAW_COLORS = {
        # primary position → hp_xi (red)
        'x':      'hp_xi', 'x_init': 'hp_xi',
        # secondary position → hp_xl (yellow)
        'x1':     'hp_xl', 'spwn_x': 'hp_xl', 'x_left': 'hp_xl', 'left': 'hp_xl',
        # x_right → hp_xr (green)
        'x_right':'hp_xr', 'right':  'hp_xr',
        # primary y → hp_yf (blue)
        'y':      'hp_yf', 'spawn':  'hp_yf', 'y_init': 'hp_yf', 'y_fix': 'hp_yf',
        # secondary y → hp_xr (green)
        'y1':     'hp_xr', 'spwn_y': 'hp_xr', 'y_end':  'hp_xr',
        # flags
        'y_flag': 'rb_flag', 'flags': 'rb_flag', 'flags2': 'rb_flag',
        # size/misc
        'size':   'rb_w', 'unk': 'rb_w',
        # type
        'type':   'rb_type', 'spwn_type': 'rb_type', 'door_type': 'rb_type',
        # id
        'map_id': 'rb_id', 'npc_id': 'rb_id', 'id': 'rb_id',
        # action
        'act':    'rb_act',
        # NPC-specific
        'head_tile': 'rb_y', 'anim_phase': 'rb_act', 'ai_type': 'rb_type', 'facing': 'rb_flag',
        # misc
        'dest':   'd', 'tile': 'c',
    }

    def _make_tip(self, e) -> list:
        """Return List[(text,tag)] for the colored tooltip (mirrors info-panel format)."""
        lbl  = e.label
        segs = []   # (text, tag)

        def add(text, tag='v'):
            segs.append((text, tag))

        # HP-style format helpers
        def fmtW(raw, mask=0xFFFF):
            val = raw & mask
            return f'0x{raw:04X} & 0x{mask:04X} = 0x{val:04X} ({val})'
        def fmtB(raw, mask=0xFF):
            val = raw & mask
            return f'0x{raw:02X} & 0x{mask:02X} = 0x{val:02X} ({val})'

        def krow(key, val, vtag=None):
            """  key           val\n  (no = sign)"""
            vt = vtag or self._RAW_COLORS.get(key, 'v')
            add(f'  {key:<12}  ', 'k')
            add(f'{val}\n', vt)

        def raw_row(raw_str, byte_colors):
            """Colored raw bytes line."""
            add('  raw  ', 'k')
            parts = raw_str.split()
            for i, b in enumerate(parts):
                add(b, byte_colors.get(i, 'd'))
                if i < len(parts) - 1:
                    add(' ', 'd')
            add('\n')
            add('\n')   # blank line after raw

        # Header: entity label
        add(f'  {lbl}\n', 'p')
        add('  ' + '-' * 28 + '\n', 's')

        if getattr(e, '_is_tear', False) or (lbl == 'T'):
            krow('type', 'Boss Door (Tear)', 'y')
            krow('x', fmtW(e.x))
            krow('y', fmtB(e.y))
            tx = e.x; ty = e.y
            _raw = f'{tx & 0xFF:02X} {(tx >> 8) & 0xFF:02X} {ty:02X}'
            raw_row(_raw, {0:'rb_x',1:'rb_x',2:'rb_y'})

        elif lbl.startswith('D'):
            if hasattr(e, 'door_type'):      # Town door 3-byte
                krow('type',      e.dtype, 'y')
                krow('x',        fmtW(e.x))
                krow('door_type',f'0x{e.door_type:02X}')
                raw_row(getattr(e, 'raw', ''), {0:'rb_x',1:'rb_x',2:'rb_type'})
            else:                            # Dungeon door 12-byte
                icon = '[KEY]' if e.needs_key else ('[TWN]' if e.is_town else '[   ]')
                krow('type',   f'{icon} {e.dtype}', 'y')
                krow('x',      fmtW(e.x))
                krow('y',      fmtB(e.y))
                krow('flags',  fmtB(e.flags))
                krow('map_id', fmtB(e.map_id))
                krow('x1',     fmtW(e.x1))
                dest_y = 'town' if e.is_town else f'0x{e.y1:02X} ({e.y1})'
                krow('y1',     dest_y)
                krow('unk',    fmtW(e.unk))
                krow('flags2', fmtB(e.flags2))
                krow('dest',   e.dest, 'd')
                raw_row(e.raw, {0:'rb_x',1:'rb_x',2:'rb_y',3:'rb_flag',
                                4:'rb_id',5:'rb_x',6:'rb_x',7:'rb_y',8:'rb_y',
                                9:'rb_act',10:'rb_act',11:'rb_flag'})

        elif lbl.startswith('N'):
            krow('x',         fmtW(e.x))
            krow('npc_id',    fmtB(e.npc_id, 0x0F), 'rb_id')
            dir_label = 'left' if (e.npc_id & 0x80) else 'right'
            krow('init_dir', f'{fmtB(e.npc_id, 0xF0)}  ({dir_label})', 'rb_id')
            krow('head_tile', fmtB(e.head_tile))
            krow('anim_phase',fmtB(e.anim_phase))
            krow('ai_type',   fmtB(e.ai_type))
            krow('flags',     fmtB(e.flags))
            krow('facing',    fmtB(e.facing))
            raw_row(getattr(e,'raw',''), {0:'rb_x',1:'rb_x',
                                           2:'rb_id',3:'rb_y',
                                           4:'rb_act',5:'rb_type',
                                           6:'rb_flag',7:'rb_flag'})
            add('\n')
            add('Double-click to pin, ◀▶ to animate\n', 'd')

        elif lbl.startswith('M'):
            name = _MONSTER_TYPE_NAMES.get(e.type, '')
            krow('x',         fmtW(e.x))
            krow('y',         fmtB(e.y))
            krow('type',      f'0x{e.type:2X}' + (f' ({name})' if name else ''))
            krow('spwn_x',    fmtW(e.spwn_x))
            krow('spwn_y',    fmtB(e.spwn_y))
            krow('spwn_type', f'0x{e.spwn_type:2X}', 'rb_type')
            krow('act',       f'0x{e.act:2X}', 'rb_act')
            raw_row(e.raw, {0:'rb_x',1:'rb_x',2:'rb_y',4:'rb_type',
                            11:'rb_x',12:'rb_x',13:'rb_y',14:'rb_id',15:'rb_act'})

        elif lbl.startswith('I'):
            name = _ITEM_TYPE_NAMES.get(e.type, '')
            krow('x',         fmtW(e.x))
            krow('y',         fmtB(e.y))
            krow('type',    f'0x{e.type:2X}' + (f' ({name})' if name else ''))
            krow('spwn_x',    fmtW(e.spwn_x))
            krow('spwn_y',    fmtB(e.spwn_y))
            raw_row(e.raw, {0:'rb_x',1:'rb_x',2:'rb_y',4:'rb_type',
                            11:'rb_x',12:'rb_x',13:'rb_y'})

        elif lbl.startswith('S'):
            krow('tile',    f'({e.x}, {e.y})', 'c')
            add('  text\n', 'k')
            for tline in e.text.split('\n'):
                add(f'    {tline}\n', 'g')
            raw_row(getattr(e,'raw',''), {0:'rb_x',1:'rb_y',2:'rb_x',3:'rb_y'})

        elif lbl.startswith(('VP','CP','HP')):
            ptype = getattr(e, 'ptype', lbl[:2]+'-Platform')
            krow('type',  ptype, 'c')
            if lbl.startswith(('VP','CP')):
                krow('attr', 'Manual' if lbl.startswith('VP') else 'Auto', 'c')
                # raw: x_init[1] spawn[1] y_init[1]
                krow('x_init', fmtB(e.x))
                krow('spawn',  fmtB(e.y) + '  (always 0)')
                y_i = getattr(e, 'y_init', getattr(e, 'y_end', e.size))
                krow('y_init', fmtB(y_i))
                raw_row(getattr(e,'raw',''), {0:'rb_x', 1:'rb_y', 2:'rb_y'})
            else:
                krow('attr', 'Auto', 'c')
                # raw: "23 40 97 1E 00 2A 00 3B"
                # 리틀엔디언: [1][0], [4][3], [6][5]
                raw_parts = getattr(e, 'raw', '').split()
                x_init_raw = (int(raw_parts[1], 16) << 8) | int(raw_parts[0], 16)  # little-endian
                y_fix_raw = int(raw_parts[2], 16)
                x_left_raw = (int(raw_parts[4], 16) << 8) | int(raw_parts[3], 16)
                x_right_raw = (int(raw_parts[6], 16) << 8) | int(raw_parts[5], 16)
                # 표시: 0x002A & 0x0FFF = 0x002A (42)
                krow('x_init',  f'0x{x_init_raw:04X} & 0x0FFF = 0x{x_init_raw & 0x0FFF:04X} ({x_init_raw & 0x0FFF})')
                krow('y_fix',   f'0x{y_fix_raw:02X} & 0x7F = 0x{y_fix_raw & 0x7F:02X} ({y_fix_raw & 0x7F})')
                krow('x_left',  f'0x{x_left_raw:04X} & 0x0FFF = 0x{x_left_raw & 0x0FFF:04X} ({x_left_raw & 0x0FFF})')
                krow('x_right', f'0x{x_right_raw:04X} & 0x0FFF = 0x{x_right_raw & 0x0FFF:04X} ({x_right_raw & 0x0FFF})')
                raw_row(getattr(e,'raw',''),
                        {0:'rb_x', 1:'rb_x', 2:'rb_y',
                         3:'rb_x', 4:'rb_x', 5:'rb_x', 6:'rb_x'})

        else:
            add('  Unknown entity\n', 'd')

        return segs

    # ── Zoom ──────────────────────────────────────────────────────────────────
    def zoom_in(self):
        """Zoom in the map view."""
        if self.block_size < self.BLK_MAX:
            prev = self.block_size
            self.block_size = min(self.block_size + 2, self.BLK_MAX)
            if self.block_size != prev:
                self.zoom_lbl.config(text=f'{self.block_size}px')
                self._schedule_redraw()

    def zoom_out(self):
        """Zoom out the map view."""
        if self.block_size > self.BLK_MIN:
            prev = self.block_size
            self.block_size = max(self.block_size - 2, self.BLK_MIN)
            if self.block_size != prev:
                self.zoom_lbl.config(text=f'{self.block_size}px')
                self._schedule_redraw()

    def _schedule_redraw(self):
        """Debounced redraw: coalesce rapid zoom events into one draw call."""
        self._map_cache = {}   # invalidate on zoom change
        if hasattr(self, '_redraw_id') and self._redraw_id:
            self.after_cancel(self._redraw_id)
        self._redraw_id = self.after(16, self._do_redraw)

    def _do_redraw(self):
        self._redraw_id = None
        if self.mdt:
            self._tile_gfx.clear_cache()   # once per debounced batch
            self.renderer.draw_map()
            self.renderer.draw_overlays()

    # ── Save Functions ────────────────────────────────────────────────────────
    def save_png(self):
        """Export current canvas view as PNG image."""
        if not self.mdt:
            messagebox.showwarning('Warning', 'Open a file first.')
            return
        try:
            from PIL import Image, ImageGrab
        except ImportError:
            try:
                from PIL import Image
                ImageGrab = None
            except ImportError:
                messagebox.showerror('Pillow Required',
                             'PNG export requires Pillow:\n\n  pip install Pillow')
                return

        init = os.path.splitext(os.path.basename(self.current_file))[0] + '.png'
        path = filedialog.asksaveasfilename(
            defaultextension='png',
            filetypes=[('PNG image', '*.png')], initialfile=init)
        if not path:
            return
        try:
            if ImageGrab:
                x = self.winfo_rootx() + self.canvas.winfo_x()
                y = self.winfo_rooty() + self.canvas.winfo_y()
                w = self.canvas.winfo_width()
                h = self.canvas.winfo_height()
                img = ImageGrab.grab(bbox=(x, y, x+w, y+h))
            else:
                ps = self.canvas.postscript(colormode='color')
                from io import BytesIO
                img = Image.open(BytesIO(ps.encode('utf-8')))
            img.save(path)
            messagebox.showinfo('Saved', f'PNG saved:\n{path}')
        except Exception as e:
            messagebox.showerror('Save Error', str(e))

    def save_txt(self):
        """Export map as text file."""
        if not self.mdt:
            messagebox.showwarning('Warning', 'Open a file first.')
            return
        init = os.path.splitext(os.path.basename(self.current_file))[0] + '.txt'
        path = filedialog.asksaveasfilename(
            defaultextension='.txt',
            filetypes=[('Text file', '*.txt')], initialfile=init)
        if not path:
            return
        try:
            m = self.mdt
            with open(path, 'w', encoding='utf-8') as f:
                f.write(f'; Zeliard MDT:  {os.path.basename(self.current_file)}\n')
                f.write(f'; Width={m.map_width}  Height={m.map_height}\n')
                if m.is_town:
                    f.write(f'; Town name={m.town_name}  '
                            f'Doors={len(m.town_doors)}  '
                            f'NPCs={len(m.npcs)}\n;\n')
                else:
                    f.write(f'; Level={m.level}  Tear=({m.tear_x},{m.tear_y})\n')
                    f.write(f'; Doors={len(m.doors)}  '
                            f'Monsters={len(m.monsters)}  '
                            f'Items={len(m.items)}\n;\n')
                for row in m.grid:
                    f.write(''.join(chr(t + 0x20) for t in row) + '\n')
            messagebox.showinfo('Saved', f'TXT saved:\n{path}')
        except Exception as e:
            messagebox.showerror('Save Error', str(e))

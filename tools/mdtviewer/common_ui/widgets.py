"""
Zeliard MDT Viewer - Reusable UI widgets.
"""

import tkinter as tk
from typing import Optional, List, Tuple, Union


# Color tags shared between Tooltip and the info-panel Text widgets
# These must match the tag names configured in _build_info_panel.
TOOLTIP_COLORS = {
    'k':       '#89b4fa',   # key label   (blue)
    'v':       '#cdd6f4',   # plain value (fg)
    'd':       '#6c7086',   # dim
    'g':       '#a6e3a1',   # green
    'r':       '#f38ba8',   # red / monster
    'y':       '#f9e2af',   # yellow
    'c':       '#89dceb',   # cyan
    'p':       '#cba6f7',   # pink / entity label
    's':       '#313244',   # surface / sep
    'rb_x':    '#89b4fa',   # x coord (blue)
    'rb_y':    '#a6e3a1',   # y coord (green)
    'rb_w':    '#f9e2af',   # width/size (yellow)
    'rb_type': '#f38ba8',   # type (red)
    'rb_id':   '#cba6f7',   # id/map_id (purple)
    'rb_flag': '#fab387',   # flags (orange)
    'rb_act':  '#94e2d5',   # act (teal)
    # HP/VP/CP per-field colors
    'hp_xi':   '#f38ba8',   # x_init  (red)
    'hp_yf':   '#89b4fa',   # y_fix   (blue)
    'hp_xl':   '#f9e2af',   # x_left  (yellow)
    'hp_xr':   '#a6e3a1',   # x_right (green)
    'vp_xi':   '#f38ba8',
    'vp_yi':   '#89b4fa',
    'vp_yd':   '#a6e3a1',
}


class Tooltip:
    """Colored hover-tooltip using a Text widget (matches info-panel style).
    Supports pinned mode with control panel (NPC ID input, speed input, ◀▶ buttons).
    """

    BG = '#12121e'
    BD = '#313244'

    def __init__(self, root: tk.Tk):
        self._root = root
        self._win:  Optional[tk.Toplevel] = None
        self._txt:  Optional[tk.Text]     = None
        self._pinned = False
        self._pinned_viewer = None
        # Control widgets (created in _ensure_window)
        self._ctrl_frame: Optional[tk.Frame] = None
        self._title_lbl: Optional[tk.Label] = None
        self._banner_ctrl: Optional[tk.Label] = None
        self._banner_anim: Optional[tk.Label] = None
        self._npc_id_var: Optional[tk.StringVar] = None
        self._npc_id_scale: Optional[tk.Scale] = None
        self._speed_var: Optional[tk.StringVar] = None
        self._speed_scale: Optional[tk.Scale] = None
        self._play_left: Optional[tk.Button] = None
        self._play_right: Optional[tk.Button] = None
        self._anim_info_lbl: Optional[tk.Label] = None
        self._npc_id_trace_id = ''

    def _ensure_window(self):
        if self._win:
            return
        self._win = tk.Toplevel(self._root)
        self._win.wm_overrideredirect(True)
        self._win.attributes('-topmost', True)

        outer = tk.Frame(self._win, bg=self.BD, bd=1, relief='solid')
        outer.pack()
        self._txt = tk.Text(
            outer,
            bg=self.BG, fg='#cdd6f4',
            font=('Consolas', 8),
            relief='flat', bd=0,
            padx=10, pady=7,
            state='disabled',
            wrap='none',
            width=48, height=1,
            cursor='arrow',
            exportselection=False,
        )
        self._txt.pack()
        for tag, color in TOOLTIP_COLORS.items():
            self._txt.tag_config(tag, foreground=color)
        self._txt.tag_config('sep', foreground='#313244')

        # Control panel (hidden by default)
        self._ctrl_frame = tk.Frame(outer, bg=self.BG)

        # -- Title --
        self._title_lbl = tk.Label(
            self._ctrl_frame, text='── Sprite Test ──',
            bg=self.BG, fg='#f9e2af', font=('Consolas', 8, 'bold'))
        self._title_lbl.pack(fill='x', pady=(4, 2))

        # ── Banner: Controls ──
        self._banner_ctrl = tk.Label(
            self._ctrl_frame, text='─── Controls ───',
            bg=self.BG, fg='#6c7086', font=('Consolas', 7))
        self._banner_ctrl.pack(fill='x', pady=(2, 2))

        # -- NPC ID Scale (0-3) --
        id_f = tk.Frame(self._ctrl_frame, bg=self.BG)
        tk.Label(id_f, text='NPC ID:', bg=self.BG, fg='#cdd6f4',
                 font=('Consolas', 8)).pack(side='left', padx=(8, 0))
        self._npc_id_var = tk.DoubleVar(value=0)
        self._npc_id_scale = tk.Scale(
            id_f, from_=0, to=3, orient='horizontal',
            variable=self._npc_id_var, showvalue=True,
            tickinterval=1, digits=0, resolution=1,
            bg=self.BG, fg='#89dceb', troughcolor='#1e1e2e',
            sliderrelief='flat', relief='flat', bd=0,
            font=('Consolas', 7), highlightthickness=0,
            length=120)
        self._npc_id_scale.pack(side='left', padx=(6, 8))
        id_f.pack(fill='x', pady=1)

        # -- Speed Scale (0.01-1.0) --
        sp_f = tk.Frame(self._ctrl_frame, bg=self.BG)
        tk.Label(sp_f, text='Speed(s):', bg=self.BG, fg='#cdd6f4',
                 font=('Consolas', 8)).pack(side='left', padx=(8, 0))
        self._speed_var = tk.DoubleVar(value=0.5)
        self._speed_scale = tk.Scale(
            sp_f, from_=0.01, to=1.0, orient='horizontal',
            variable=self._speed_var, showvalue=True,
            tickinterval=0.2, digits=2, resolution=0.01,
            bg=self.BG, fg='#a6e3a1', troughcolor='#1e1e2e',
            sliderrelief='flat', relief='flat', bd=0,
            font=('Consolas', 7), highlightthickness=0,
            length=120)
        self._speed_scale.pack(side='left', padx=(6, 8))
        sp_f.pack(fill='x', pady=1)

        # ── Banner: Animation ──
        self._banner_anim = tk.Label(
            self._ctrl_frame, text='─── Animation ───',
            bg=self.BG, fg='#6c7086', font=('Consolas', 7))
        self._banner_anim.pack(fill='x', pady=(4, 2))

        # -- Play buttons --
        btn_f = tk.Frame(self._ctrl_frame, bg=self.BG)
        self._play_left = tk.Button(
            btn_f, text='◀', state='disabled',
            bg=self.BG, fg='#89dceb',
            relief='flat', bd=0, font=('Consolas', 9, 'bold'),
            cursor='hand2', padx=8, pady=1)
        self._play_left.pack(side='left', padx=(8, 2))
        self._play_right = tk.Button(
            btn_f, text='▶', state='disabled',
            bg=self.BG, fg='#89dceb',
            relief='flat', bd=0, font=('Consolas', 9, 'bold'),
            cursor='hand2', padx=8, pady=1)
        self._play_right.pack(side='left', padx=(2, 8))
        btn_f.pack(fill='x', pady=(2, 2))

        # -- Anim info label (below play buttons) --
        self._anim_info_lbl = tk.Label(
            self._ctrl_frame, text='',
            bg=self.BG, fg='#89dceb', font=('Consolas', 8))
        self._anim_info_lbl.pack(fill='x', pady=(0, 4))

    # ── Public API ────────────────────────────────────────────────────────

    def show(self, rx: int, ry: int,
             segments: Union[str, List[Tuple[str, str]]]):
        self._ensure_window()
        self._pinned = False
        self._pinned_viewer = None
        self._ctrl_frame.pack_forget()
        self._update_content(segments)
        self._win.wm_geometry(f'+{rx + 20}+{ry + 20}')
        self._win.deiconify()
        self._win.lift()

    def show_pinned(self, rx: int, ry: int,
                    segments: Union[str, List[Tuple[str, str]]],
                    viewer):
        self._ensure_window()
        self._pinned = True
        self._pinned_viewer = viewer
        self._update_content(segments)

        # Populate entries from current NPC state
        label = viewer._locked_npc.label if viewer._locked_npc else ''
        npc = None
        for n in getattr(viewer, 'mdt', None).npcs:
            if n.label == label:
                npc = n
                break
        current_npc_id = (npc.npc_id & 0x0F) if npc else 0
        self._npc_id_var.set(current_npc_id)
        self._speed_var.set(viewer._npc_anim_interval / 1000)
        self._update_anim_info(viewer)

        # Wire callbacks
        self._play_left.config(command=lambda: viewer._npc_anim_toggle('left'))
        self._play_right.config(command=lambda: viewer._npc_anim_toggle('right'))
        if self._npc_id_trace_id:
            self._npc_id_var.trace_remove('write', self._npc_id_trace_id)
        self._npc_id_trace_id = self._npc_id_var.trace_add('write', self._on_npc_id_change)
        self._speed_var.trace_add('write', self._on_speed_change)

        self._ctrl_frame.pack(fill='x')
        self._update_btn_states(viewer)
        self._win.wm_geometry(f'+{rx + 20}+{ry + 20}')
        self._win.deiconify()
        self._win.lift()

    def update_pinned(self,
                      segments: Union[str, List[Tuple[str, str]]],
                      viewer):
        if not self._pinned or not self._win:
            return
        self._update_content(segments)
        self._update_btn_states(viewer)
        self._update_anim_info(viewer)

    def hide(self):
        self._pinned = False
        self._pinned_viewer = None
        if self._npc_id_trace_id:
            try:
                self._npc_id_var.trace_remove('write', self._npc_id_trace_id)
            except Exception:
                pass
            self._npc_id_trace_id = ''
        if self._ctrl_frame:
            self._ctrl_frame.pack_forget()
        if self._win:
            self._win.withdraw()

    def is_pinned(self) -> bool:
        return self._pinned

    # ── Internal ──────────────────────────────────────────────────────────

    def _update_content(self, segments):
        T = self._txt
        T.config(state='normal')
        T.delete('1.0', 'end')
        if isinstance(segments, str):
            T.insert('end', segments)
        else:
            for text, tag in segments:
                T.insert('end', text, tag)
        content = T.get('1.0', 'end-1c')
        lines   = content.split('\n')
        h = min(len(lines), 30)
        w = min(max((len(l) for l in lines), default=20) + 2, 60)
        T.config(height=h, width=w, state='disabled')

    def _update_btn_states(self, viewer):
        self._play_left.config(state='normal')
        self._play_right.config(state='normal')
        anim_label = getattr(viewer, '_npc_anim_label', None)
        playing = anim_label is not None
        if playing:
            is_left = getattr(viewer, '_npc_anim_range', (4, 7)) == (0, 3)
        else:
            is_left = False
        self._play_left.config(
            text='■' if (playing and is_left) else '◀',
            fg='#f38ba8' if (playing and is_left) else '#89dceb')
        self._play_right.config(
            text='■' if (playing and not is_left) else '▶',
            fg='#f38ba8' if (playing and not is_left) else '#89dceb')

    def _update_anim_info(self, viewer):
        """Update the anim info label below play buttons."""
        label = getattr(viewer, '_npc_anim_label', None)
        ani = getattr(viewer, '_npc_anim_timer', None)
        if label and ani:
            lo, hi = viewer._npc_anim_range
            frame = viewer._npc_anim_frame
            offset = lo + frame
            sprite = (int(self._npc_id_var.get()) & 0x0F) * 8 + offset
            self._anim_info_lbl.config(
                text=f'  anim: frame={offset}  sprite={sprite}')
        else:
            self._anim_info_lbl.config(text='')

    def _on_npc_id_change(self, *_args):
        viewer = self._pinned_viewer
        if not viewer or not viewer._locked_npc:
            return
        new_id = int(self._npc_id_var.get()) & 0x0F
        label = viewer._locked_npc.label
        npc_dir_right = not (viewer._locked_npc.npc_id & 0x80)
        if viewer._npc_anim_timer and viewer._npc_anim_label == label:
            lo, hi = viewer._npc_anim_range
            offset = lo + viewer._npc_anim_frame
            sprite = new_id * 8 + offset
        else:
            sprite = new_id * 8 + (4 if npc_dir_right else 0)
        viewer._npc_sprite_preview[label] = sprite
        viewer.renderer.draw_overlays()
        # Refresh tooltip content
        self.update_pinned(viewer._make_tip(viewer._locked_npc), viewer)

    def _on_speed_change(self, *_args):
        viewer = self._pinned_viewer
        if not viewer:
            return
        new_speed = max(0.01, min(1.0, self._speed_var.get()))
        viewer._npc_anim_interval = int(new_speed * 1000)
        # Restart timer with new interval if animating
        if viewer._npc_anim_timer:
            viewer.after_cancel(viewer._npc_anim_timer)
            viewer._npc_anim_timer = viewer.after(
                viewer._npc_anim_interval, viewer._npc_anim_tick)


class InfoBox(tk.Frame):
    """Collapsible info panel with header and text content area."""

    def __init__(self, parent: tk.Widget, title: str,
                 bg_header: str, fg_header: str, **kwargs):
        super().__init__(parent, bg=parent.cget('bg'), **kwargs)
        self._bg_header = bg_header
        self._fg_header = fg_header
        self._txt: Optional[tk.Text] = None
        self._build_box(title)

    def _build_box(self, title: str):
        self._header = tk.Frame(self, bg=self._bg_header, relief='solid', bd=1)
        self._header.pack(fill='x')
        tk.Label(self._header, text=title, bg=self._bg_header,
                 fg=self._fg_header, font=('Consolas', 10, 'bold')
                 ).pack(side='left', padx=5, pady=3)
        self._content = tk.Frame(self, bg=self._bg_header)
        self._content.pack(fill='both', expand=True)

    def set_text_widget(self, txt: tk.Text):
        self._txt = txt
        self._txt.pack(in_=self._content, fill='both', expand=True)

    def hide(self): pass


class ScrollFrame(tk.Frame):
    """Scrollable container frame."""

    def __init__(self, parent: tk.Widget, *args, **kwargs):
        tk.Frame.__init__(self, parent, *args, **kwargs)
        self.canvas = tk.Canvas(self, bg=self.cget('bg'), highlightthickness=0)
        self.scrollbar = tk.Scrollbar(
            self, orient='vertical', command=self.canvas.yview,
            bg=self.master.cget('bg'))
        self.canvas.configure(yscrollcommand=self.scrollbar.set)
        self.scrollbar.pack(side='right', fill='y')
        self.canvas.pack(side='left', fill='both', expand=True)

        self.interior = tk.Frame(self.canvas, bg=self.cget('bg'))
        self.canvas_window = self.canvas.create_window(
            (0, 0), window=self.interior, anchor='nw')

        self.interior.bind('<Configure>', self._on_configure)
        self.canvas.bind('<Configure>', self._on_canvas_configure)

    def _on_configure(self, event=None):
        self.canvas.configure(scrollregion=self.canvas.bbox('all'))

    def _on_canvas_configure(self, event):
        self.canvas.itemconfig(self.canvas_window, width=event.width)


class CollapsibleSection(tk.Frame):
    """
    A self-contained collapsible box for use in info panels.

    Header bar is always visible. Clicking the title or the ▼/▶ button
    collapses/expands the content area. The box never disappears and never
    overlaps siblings — it simply shows/hides its content frame.

    Usage:
        sec = CollapsibleSection(parent, title='MAP INFO', color='#89b4fa')
        sec.pack(fill='x')
        # Add content:
        lbl = tk.Label(sec.content, text='hello')
        lbl.pack()
    """

    def __init__(self, parent, title: str = '', color: str = '#89b4fa',
                 bg_header: str = '#313244', bg_content: str = '#1e1e2e',
                 start_expanded: bool = True, **kwargs):
        super().__init__(parent, bg=bg_content, **kwargs)
        self._expanded = start_expanded
        self._bg_hdr   = bg_header
        self._bg_cnt   = bg_content

        # ── Header ──
        hdr = tk.Frame(self, bg=bg_header, relief='solid', bd=1)
        hdr.pack(fill='x')

        self._toggle_btn = tk.Button(
            hdr, text=('▼' if start_expanded else '▶'),
            command=self.toggle,
            bg=bg_header, fg=color, relief='flat', bd=0,
            cursor='hand2', font=('Consolas', 10), padx=4, pady=2,
            activebackground=bg_header, activeforeground=color)
        self._toggle_btn.pack(side='right', padx=2)

        title_lbl = tk.Label(hdr, text=title, bg=bg_header, fg=color,
                             font=('Consolas', 10, 'bold'), cursor='hand2',
                             padx=5, pady=3)
        title_lbl.pack(side='left')
        # Clicking the title label also toggles
        title_lbl.bind('<Button-1>', lambda e: self.toggle())

        # ── Content ──
        self.content = tk.Frame(self, bg=bg_content)
        if start_expanded:
            self.content.pack(fill='both', expand=True)

    # ── API ────────────────────────────────────────────────────────────────
    def toggle(self):
        if self._expanded:
            self.collapse()
        else:
            self.expand()

    def collapse(self):
        self.content.pack_forget()
        self._toggle_btn.config(text='▶')
        self._expanded = False

    def expand(self):
        self.content.pack(fill='both', expand=True)
        self._toggle_btn.config(text='▼')
        self._expanded = True

    @property
    def is_expanded(self) -> bool:
        return self._expanded

"""
sidebar.py — Reusable collapsible sidebar with drag-resize.

Public API
----------
Sidebar(parent, title, side, collapsed_width, expand_width,
        resizable, min_width, title_color, bg, content_bg, on_toggle)

    .content         — tk.Frame  — place child widgets here
    .toggle()        — collapse or expand
    .collapse()
    .expand()
    .is_collapsed    — bool property
    .set_width(w)    — programmatic resize

Usage in another app
---------------------
    from .sidebar import Sidebar
    sb = Sidebar(root, title='Files', side='left', expand_width=240, resizable=True)
    sb.pack(side='left', fill='y')
    MyWidget(sb.content).pack(fill='both', expand=True)
    
    # For bottom panel
    sb = Sidebar(root, title='Log', side='bottom', expand_width=100, resizable=True)
    sb.pack(side='bottom', fill='x')
"""

import tkinter as tk
from typing import Callable, Optional


class Sidebar(tk.Frame):
    """
    Collapsible, drag-resizable sidebar panel supporting left, right, and bottom sides.

    Layout (side='left'):
        ┌──────────────────────┬───┐
        │  TITLE          ◀   │ ↔ │  ← header + grip strip
        ├──────────────────────┤   │
        │                      │   │
        │   content            │   │  ← content fills the rest
        │                      │   │
        └──────────────────────┴───┘

    Layout (side='bottom'):
        ┌──────────────────────┐
        │  TITLE          ▲   │  ← header
        ├──────────────────────┤
        │   content            │  ← content
        ├──────────────────────┤
        │          ↕           │  ← grip strip
        └──────────────────────┘

    The sidebar never leaves the layout — it just shrinks to
    `collapsed_width` when collapsed, so sibling widgets are not
    forced to redraw.
    """

    _ARROW = {
        ('left',  True):  '◀',
        ('left',  False): '▶',
        ('right', True):  '▶',
        ('right', False): '◀',
        ('bottom', True):  '▼',
        ('bottom', False): '▲',
    }
    _GRIP_W  = 8    # px width of the drag handle strip (increased hit target)
    _GRIP_BG = '#45475a'
    _GRIP_HI = '#89b4fa'

    def __init__(self,
                 parent,
                 title:           str                 = '',
                 side:            str                 = 'left',
                 collapsed_width: int                 = 28,
                 expand_width:    int                 = 240,
                 resizable:       bool                = True,
                 min_width:       int                 = 80,
                 title_color:     str                 = '#89dceb',
                 bg:              str                 = '#313244',
                 content_bg:      str                 = '#1e1e2e',
                 on_toggle:       Optional[Callable]  = None,
                 **kwargs):
        super().__init__(parent, bg=bg, **kwargs)
        self._side      = side
        self._col_w     = collapsed_width
        self._exp_w     = expand_width
        self._cur_w     = expand_width
        self._min_w     = min_width
        self._collapsed = False
        self._cb        = on_toggle
        self._bg        = bg
        self._fg        = title_color
        self._resizable = resizable

        self.pack_propagate(False)
        if self._side == 'bottom':
            self.config(height=expand_width)
        else:
            self.config(width=expand_width)
        self._build(title, bg, content_bg, title_color, resizable)

    # ── Construction ───────────────────────────────────────────────────────
    def _build(self, title, bg, content_bg, fg, resizable):
        """
        Pack order matters for tkinter pack geometry manager.
        For left/right: two-column layout (grip + main)
        For bottom: two-row layout (main + grip)
        """
        # Determine grip and main packing for left/right/bottom sides
        if self._side == 'bottom':
            # For bottom sidebar, place the grip on the top edge so the user drags
            # the top border of the log panel (matches expected UX).
            grip_side  = 'top'
            other_side = 'bottom'
            grip_orient = 'horizontal'
            grip_fill = 'x'
            main_fill = 'both'
            grip_cursor = 'sb_v_double_arrow'
        else:
            grip_side  = 'right' if self._side == 'left' else 'left'
            other_side = 'left'  if self._side == 'left' else 'right'
            grip_orient = 'vertical'
            grip_fill = 'y'
            main_fill = 'both'
            grip_cursor = 'sb_h_double_arrow'

        # ── Grip strip (pack FIRST so it gets space before content) ────────
        if resizable:
            grip_width = self._GRIP_W if self._side != 'bottom' else None
            grip_height = self._GRIP_W if self._side == 'bottom' else None
            self._grip = tk.Frame(
                self, bg=self._GRIP_BG,
                width=grip_width, height=grip_height,
                cursor=grip_cursor)
            self._grip.pack(side=grip_side, fill=grip_fill)
            self._grip.pack_propagate(False)
            # Bind drag handlers (press/move/release) for robust resizing
            self._grip.bind('<Button-1>', self._on_grip_press)
            self._grip.bind('<B1-Motion>', self._on_grip_move)
            self._grip.bind('<ButtonRelease-1>', self._on_grip_release)
            self._grip.bind('<Enter>', lambda e: self._grip.config(bg=self._GRIP_HI))
            self._grip.bind('<Leave>', lambda e: self._grip.config(bg=self._GRIP_BG))
            # Ensure grip is above neighbors so it receives mouse events
            try:
                self._grip.lift()
            except Exception:
                pass
        else:
            self._grip = None

        # ── Main area (header + content) ────────────────────────────────────
        self._main = tk.Frame(self, bg=bg)
        self._main.pack(side=other_side, fill=main_fill, expand=True)

        # Header
        self._hdr = tk.Frame(self._main, bg=bg, height=28)
        self._hdr.pack(fill='x', side='top')
        self._hdr.pack_propagate(False)

        # Keep title variants for collapsed display
        self._title = title
        if self._side in ('left', 'right'):
            # Vertical label for narrow collapsed sidebar
            self._vertical_title = "\n".join(list(title)) if title else ''
        else:
            self._vertical_title = title

        self._lbl = tk.Label(
            self._hdr, text=title, bg=bg, fg=fg,
            font=('Consolas', 9, 'bold'), padx=6, pady=4)
        self._btn = tk.Button(
            self._hdr, text=self._arrow(expanded=True),
            command=self.toggle,
            bg=bg, fg=fg, relief='flat', bd=0, cursor='hand2',
            font=('Consolas', 11), padx=4, pady=2,
            activebackground=bg, activeforeground=fg)
        self._pack_header_widgets(expanded=True)

        # Content
        self.content = tk.Frame(self._main, bg=content_bg)
        self.content.pack(fill='both', expand=True, side='top')

    def _pack_header_widgets(self, expanded: bool):
        # Remove current header widgets before re-packing
        self._lbl.pack_forget()
        self._btn.pack_forget()
        if expanded:
            # Normal header: title and arrow
            if self._side == 'left':
                self._lbl.config(text=self._title)
                self._lbl.pack(side='left')
                self._btn.pack(side='right')
            else:
                self._lbl.config(text=self._title)
                self._btn.pack(side='left')
                self._lbl.pack(side='left')
        else:
            # Collapsed header:
            # - For left/right: show arrow above and a vertical title beneath it (centered).
            # - For bottom: show arrow to the left of the title.
            if self._side in ('left', 'right'):
                # Vertical stack: arrow on top, verticalized title below
                self._lbl.config(text=self._vertical_title, justify='center', anchor='center')
                self._btn.pack(side='top', pady=(2, 0))
                self._lbl.pack(side='top', pady=(0, 2))
            else:
                # Bottom collapsed: arrow on the left, title to the right
                self._lbl.config(text=self._title)
                self._btn.pack(side='left', padx=2, pady=2)
                self._lbl.pack(side='left', padx=2, pady=2)

    # ── Public API ─────────────────────────────────────────────────────────
    def toggle(self):
        self.expand() if self._collapsed else self.collapse()

    def collapse(self):
        if self._collapsed:
            return
        if self._side == 'bottom':
            self._cur_w = self.winfo_height() or self._exp_w
        else:
            self._cur_w = self.winfo_width() or self._exp_w
        self._collapsed = True
        # Hide content and label, show only arrow button
        self.content.pack_forget()
        # For left/right collapsed state, expand header height so vertical title can be visible
        if self._side in ('left', 'right'):
            # Try to set header height to sidebar height; use after to ensure geometry is updated
            def _set_hdr_height():
                h = self.winfo_height() or (self.master.winfo_height() if self.master else 120)
                # keep a reasonable minimum
                self._hdr.config(height=max(h, 80))
            try:
                _set_hdr_height()
            except Exception:
                # schedule for later if immediate call fails
                self.after(10, _set_hdr_height)

        self._pack_header_widgets(expanded=False)
        # Hide grip while collapsed
        if self._grip:
            self._grip.pack_forget()
        if self._side == 'bottom':
            self.config(height=self._col_w)
        else:
            self.config(width=self._col_w)
        self._btn.config(text=self._arrow(expanded=False))
        if self._cb:
            self._cb(False)

    def expand(self):
        if not self._collapsed:
            return
        self._collapsed = False
        # Restore grip first so it keeps its space
        if self._grip:
            if self._side == 'bottom':
                grip_side = 'top'
            else:
                grip_side = 'right' if self._side == 'left' else 'left'
            self._grip.pack(side=grip_side, fill=('x' if self._side == 'bottom' else 'y'))
            try:
                self._grip.lift()
            except Exception:
                pass
        # Restore header height to default before repacking content so it doesn't shift down
        try:
            self._hdr.config(height=28)
        except Exception:
            pass
        self._pack_header_widgets(expanded=True)
        # Pack content after header size is restored
        self.content.pack(fill='both', expand=True, side='top')
        if self._side == 'bottom':
            self.config(height=self._cur_w)
        else:
            self.config(width=self._cur_w)
        self._btn.config(text=self._arrow(expanded=True))
        if self._cb:
            self._cb(True)

    def set_width(self, w: int):
        """Resize programmatically (only when expanded)."""
        self._cur_w = max(w, self._min_w)
        if not self._collapsed:
            if self._side == 'bottom':
                self.config(height=self._cur_w)
            else:
                self.config(width=self._cur_w)

    @property
    def is_collapsed(self) -> bool:
        return self._collapsed

    # ── Drag resize ────────────────────────────────────────────────────────
    def _on_grip_press(self, event):
        """Record starting mouse position and current size for a drag operation."""
        if self._collapsed:
            return
        if self._side == 'bottom':
            self._drag_start_y = event.y_root
            self._drag_start_h = self.winfo_height() or self._exp_w
        else:
            self._drag_start_x = event.x_root
            self._drag_start_w = self.winfo_width() or self._exp_w

    def _on_grip_move(self, event):
        """Handle pointer motion while dragging the grip."""
        if self._collapsed:
            return
        try:
            if self._side == 'bottom':
                dy = self._drag_start_y - event.y_root
                new_h = int(self._drag_start_h + dy)
                new_h = max(new_h, self._min_w)
                self._cur_w = new_h
                self.config(height=new_h)
            else:
                if self._side == 'left':
                    dx = event.x_root - self._drag_start_x
                    new_w = int(self._drag_start_w + dx)
                else:  # right
                    dx = self._drag_start_x - event.x_root
                    new_w = int(self._drag_start_w + dx)
                self.set_width(new_w)
        except AttributeError:
            # If drag start wasn't recorded, ignore
            return

    def _on_grip_release(self, event):
        """End of drag — clear temporary state."""
        for a in ('_drag_start_x', '_drag_start_w', '_drag_start_y', '_drag_start_h'):
            if hasattr(self, a):
                try:
                    delattr(self, a)
                except Exception:
                    try:
                        self.__dict__.pop(a, None)
                    except Exception:
                        pass

    # ── Arrow ───────────────────────────────────────────────────────────────
    def _arrow(self, expanded: bool) -> str:
        return self._ARROW[(self._side, expanded)]

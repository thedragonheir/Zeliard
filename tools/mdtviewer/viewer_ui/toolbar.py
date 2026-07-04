import tkinter as tk


class Toolbar:
    """Top toolbar and status subbar."""

    def __init__(self, viewer):
        self.viewer = viewer
        self._build_toolbar()
        self._build_subbar()

    def _build_toolbar(self):
        v = self.viewer
        tb = tk.Frame(v, bg=v.C_BG0, height=46)
        tb.pack(fill='x')
        tb.pack_propagate(False)

        v._open_btn = self._button(tb, 'Open ▾', v._show_open_popup, padx=(8, 2))
        v._save_btn = self._button(tb, 'Save ▾', v._show_save_popup, fg=v.C_GREEN)
        self._separator(tb)

        tk.Label(
            tb,
            text='Zoom',
            bg=v.C_BG0,
            fg=v.C_DIM,
            font=('Consolas', 8),
        ).pack(side='left', padx=(2, 0))
        self._button(tb, '-', v.zoom_out, fg=v.C_RED, px=8)
        v.zoom_lbl = tk.Label(
            tb,
            text=f'{v.block_size}px',
            bg=v.C_BG0,
            fg=v.C_FG,
            font=('Consolas', 9),
            width=5,
        )
        v.zoom_lbl.pack(side='left')
        self._button(tb, '+', v.zoom_in, fg=v.C_GREEN, px=8)
        self._separator(tb)

        self._separator(tb)
        v._view_btn = tk.Button(
            tb,
            text='View ▾',
            command=v._show_view_popup,
            bg='#2a3a2a',
            fg=v.C_GREEN,
            activebackground='#45475a',
            activeforeground=v.C_FG,
            relief='flat',
            bd=0,
            cursor='hand2',
            font=('Consolas', 9),
            padx=10,
            pady=7,
        )
        v._view_btn.pack(side='left', padx=2, pady=6)
        self._separator(tb)

    def _build_subbar(self):
        v = self.viewer
        sb = tk.Frame(v, bg='#0a0a14', height=28)
        sb.pack(fill='x')
        sb.pack_propagate(False)

        v.place_lbl_tb = tk.Label(
            sb,
            text='',
            bg='#0a0a14',
            fg='#f9e2af',
            font=('Consolas', 11, 'bold'),
            anchor='w',
            padx=14,
            pady=2,
        )
        v.place_lbl_tb.pack(side='left')

        self._subbar_separator(sb)

        v.status = tk.Label(
            sb,
            textvariable=v.hover_txt,
            bg='#0a0a14',
            fg=v.C_FG,
            font=('Consolas', 11, 'bold'),
            anchor='w',
            padx=14,
            pady=2,
        )
        v.status.pack(side='left', fill='x', expand=True)

        self._subbar_separator(sb)

        v.place_banner = tk.Label(
            sb,
            text='',
            bg='#0a0a14',
            fg='#f9e2af',
            font=('Consolas', 8),
            anchor='w',
        )
        v.place_banner.pack(side='right')

    def _button(self, parent, text, command, fg=None, px=10, padx=2, state='normal'):
        v = self.viewer
        button = tk.Button(
            parent,
            text=text,
            command=command,
            bg=v.C_SURF,
            fg=fg or v.C_FG,
            activebackground='#45475a',
            activeforeground=v.C_FG,
            relief='flat',
            bd=0,
            cursor='hand2',
            font=('Consolas', 9),
            padx=px,
            pady=7,
            state=state,
        )
        button.pack(side='left', padx=padx, pady=6)
        return button

    def _separator(self, parent):
        tk.Frame(parent, bg=self.viewer.C_SURF, width=1).pack(
            side='left',
            fill='y',
            pady=8,
            padx=5,
        )

    def _subbar_separator(self, parent):
        tk.Frame(parent, bg='#313244', width=1).pack(
            side='left',
            fill='y',
            pady=4,
            padx=6,
        )


def attach_toolbar(viewer):
    """Build the top toolbar and subbar."""
    return Toolbar(viewer)

import tkinter as tk


class CanvasPanel:
    """Center map canvas panel and related rendering widgets."""

    def __init__(self, parent, viewer):
        self.parent = parent
        self.viewer = viewer
        self._build()

    def _build(self):
        self._build_hint()
        self._build_canvas()
        self._bind_canvas_events()
        self._build_npc_panel()

    def _build_hint(self):
        v = self.viewer
        v.hint = tk.Label(
            self.parent,
            text='Open an MDT file\n\n'
                 'Level maps:  MP10.MDT  through  MPA0.MDT\n'
                 'Resources:   CMAP / STMP / BSMP / MRMP / ...',
            bg=v.C_BG1,
            fg=v.C_DIM,
            font=('Consolas', 12),
            justify='center',
        )
        v.hint.pack(fill='both', expand=True)

    def _build_canvas(self):
        v = self.viewer
        v.cf = tk.Frame(self.parent, bg=v.C_BG1)
        v.canvas = tk.Canvas(
            v.cf,
            bg=v.C_BG1,
            highlightthickness=0,
            cursor='crosshair',
            xscrollincrement=1,
            yscrollincrement=1,
        )
        vsb = tk.Scrollbar(
            v.cf,
            orient='vertical',
            command=v.canvas.yview,
            bg=v.C_SURF,
            troughcolor=v.C_BG2,
            width=10,
        )
        hsb = tk.Scrollbar(
            v.cf,
            orient='horizontal',
            command=v.canvas.xview,
            bg=v.C_SURF,
            troughcolor=v.C_BG2,
            width=10,
        )
        v.canvas.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)
        vsb.pack(side='right', fill='y')
        hsb.pack(side='bottom', fill='x')
        v.canvas.pack(fill='both', expand=True)

    def _bind_canvas_events(self):
        v = self.viewer
        v.canvas.bind('<Motion>', v._on_motion)
        v.canvas.bind('<Leave>', v._on_leave)
        v.canvas.bind('<Button-1>', v._on_canvas_click)
        v.canvas.bind('<Double-Button-1>', v._on_canvas_double_click)
        v.canvas.bind('<MouseWheel>', v._on_wheel)
        v.canvas.bind('<Button-4>', v._on_wheel)
        v.canvas.bind('<Button-5>', v._on_wheel)
        v.canvas.bind('<Button-3>', v._on_right_click)
        v.canvas.bind('<B3-Motion>', v._on_right_drag)
        v.canvas.bind('<ButtonRelease-3>', v._on_right_release)

    def _build_npc_panel(self):
        v = self.viewer
        v.npc_panel = tk.Frame(self.parent, bg=v.C_BG0)
        npc_hdr = tk.Frame(v.npc_panel, bg=v.C_SURF)
        npc_hdr.pack(fill='x')
        tk.Label(
            npc_hdr,
            text='NPC DIALOGUE',
            bg=v.C_SURF,
            fg=v.C_BLUE,
            font=('Consolas', 9, 'bold'),
            anchor='w',
            padx=6,
            pady=3,
        ).pack(side='left')
        v.npc_speech_lbl = tk.Label(
            npc_hdr,
            text='',
            bg=v.C_SURF,
            fg=v.C_DIM,
            font=('Consolas', 8),
            anchor='w',
            padx=6,
        )
        v.npc_speech_lbl.pack(side='left')
        tk.Button(
            npc_hdr,
            text='?',
            command=v._show_npc_ctrl_legend,
            bg=v.C_SURF,
            fg='#f9e2af',
            relief='flat',
            bd=0,
            font=('Consolas', 8, 'bold'),
            cursor='hand2',
            padx=4,
            pady=1,
        ).pack(side='right', padx=4)

        v.npc_speech_txt = tk.Text(
            v.npc_panel,
            bg=v.C_PANEL,
            fg=v.C_FG,
            font=('Consolas', 9),
            relief='flat',
            wrap='word',
            height=4,
            selectbackground='#2a3a4a',
            selectforeground='#ffffff',
            exportselection=True,
            padx=8,
            pady=4,
        )
        v.npc_speech_txt.bind('<Key>', self._npc_readonly)
        v.npc_speech_txt.tag_config(
            'ctrl',
            foreground='#f9e2af',
            font=('Consolas', 8, 'bold'),
        )
        v.npc_speech_txt.tag_config(
            'raw',
            foreground='#f38ba8',
            font=('Consolas', 8),
        )
        v.npc_speech_txt.pack(fill='x')

    def _npc_readonly(self, event):
        nav = {
            'Left', 'Right', 'Up', 'Down', 'Home', 'End', 'Prior', 'Next',
            'Shift_L', 'Shift_R', 'Control_L', 'Control_R',
        }
        if event.state & 0x4:
            return None
        if event.keysym in nav:
            return None
        return 'break'


def attach_canvas_panel(parent, viewer):
    """Build the center canvas panel and attach compatibility attributes."""
    return CanvasPanel(parent, viewer)

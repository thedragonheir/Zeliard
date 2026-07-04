import tkinter as tk


class ViewSettingsDialog:
    """Dialog for render and overlay visibility settings."""

    def __init__(self, viewer):
        self.viewer = viewer
        self.dialog = tk.Toplevel(viewer)
        self._render_vars = {}
        self._build()

    def _build(self):
        v = self.viewer
        dlg = self.dialog

        dlg.title('View Settings')
        dlg.transient(v)
        # Modeless dialog: do not call grab_set() so the main window remains usable.
        cw, ch = 320, 560
        sw, sh = v.winfo_screenwidth(), v.winfo_screenheight()
        dlg.geometry(f'{cw}x{ch}+{(sw - cw) // 2}+{(sh - ch) // 2}')
        dlg.configure(bg=v.C_BG2)

        self._section('RENDER MODE')
        self._render_check('Color Blocks', 'color')
        self._render_check('Real Tiles', 'tiles')

        self._section('COMMON')
        self._check('Loop Map', v.wrap_var)
        self._check('Tile Grid', v.grid_var)

        self._section('OBJECTS')
        overlay_cmd = self._draw_overlays
        self._check('All', v.show_overlay, overlay_cmd)
        self._check('V-Platform', v.show_vp_label, overlay_cmd)
        self._check('H-Platform', v.show_hp_label, overlay_cmd)
        self._check('C-Platform', v.show_cp_label, overlay_cmd)
        self._check('Sign', v.show_sign_var, overlay_cmd)
        self._check('NPC', v.show_npc_var, overlay_cmd)
        self._check('Monster', v.show_monster_var, overlay_cmd)
        self._check('Item', v.show_item_var, overlay_cmd)
        self._check('Door', v.show_door_var, overlay_cmd)

        self._section('PATH')
        self._check('V-Platform Path', v.show_vp_paths)
        self._check('H-Platform Path', v.show_hp_paths)
        self._check('C-Platform Path', v.show_cp_paths)

        dlg.bind('<Escape>', lambda e: dlg.destroy())
        dlg.focus()

    def _section(self, text):
        v = self.viewer
        frame = tk.Frame(self.dialog, bg=v.C_BG1)
        frame.pack(fill='x', padx=10, pady=(10, 2))
        tk.Label(
            frame,
            text=text,
            bg=v.C_BG1,
            fg=v.C_DIM,
            font=('Consolas', 8, 'bold'),
        ).pack(anchor='w')

    def _check(self, text, var, cmd=None):
        v = self.viewer
        frame = tk.Frame(self.dialog, bg=v.C_BG2)
        frame.pack(fill='x', padx=10, pady=1)
        cb = tk.Checkbutton(
            frame,
            text=text,
            variable=var,
            command=cmd or v._refresh_overlays,
            bg=v.C_BG2,
            fg=v.C_FG,
            activebackground=v.C_BG2,
            selectcolor=v.C_BG2,
            font=('Consolas', 9),
            anchor='w',
        )
        cb.pack(side='left')

    def _render_check(self, text, mode):
        v = self.viewer
        frame = tk.Frame(self.dialog, bg=v.C_BG2)
        frame.pack(fill='x', padx=10, pady=1)
        checked = tk.BooleanVar(value=(v.view_mode.get() == mode))
        self._render_vars[mode] = checked
        cb = tk.Checkbutton(
            frame,
            text=text,
            variable=checked,
            command=lambda: self._set_render_mode(mode),
            bg=v.C_BG2,
            fg=v.C_FG,
            activebackground=v.C_BG2,
            selectcolor=v.C_BG2,
            font=('Consolas', 9),
            anchor='w',
        )
        cb.pack(side='left')

    def _set_render_mode(self, mode):
        for render_mode, var in self._render_vars.items():
            var.set(render_mode == mode)
        self.viewer._set_view_mode(mode)

    def _draw_overlays(self):
        self.viewer.renderer.draw_overlays()


def show_view_settings(viewer):
    """Open the View Settings dialog."""
    return ViewSettingsDialog(viewer)

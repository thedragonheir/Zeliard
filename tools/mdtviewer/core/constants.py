"""
Zeliard MDT Viewer - Constants and lookup tables.
"""

import os

# ─── Runtime constants ────────────────────────────────────────────────────────
MDT_LOAD_ADDR   = 0xC000   # MDT runtime segment base address
DUNG_HEIGHT = 64       # All Zeliard dungeons are exactly 64 tiles tall
TOWN_HEIGHT = 8       # All Zeliard town maps are exactly 8 tiles tall

# ─── Tile color palette (golden-ratio HSV across 64 entries) ──────────────────
def _hsv(h, s, v):
    i = int(h*6) % 6; f = h*6 - int(h*6)
    p = v*(1-s); q = v*(1-f*s); t = v*(1-(1-f)*s)
    r, g, b = [(v,t,p),(q,v,p),(p,v,t),(p,q,v),(t,p,v),(v,p,q)][i]
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

PALETTE = {0: '#0c0c14'}
_h = 0.08
for _i in range(1, 64):
    _h = (_h + 0.618033988749895) % 1.0
    PALETTE[_i] = _hsv(_h, 0.55 + 0.30*((_i%4)/3.0), 0.50 + 0.40*(_i%2))

# ─── Map ID lookup tables ─────────────────────────────────────────────────────
# Dungeon/outdoor maps — map_id is 0-based from MP10.MDT (STICK.BIN index 0x15)
_DUNG_MAPS = [
    'MP10.MDT','MP1D.MDT','MP20.MDT','MP21.MDT','MP2D.MDT',
    'MP30.MDT','MP31.MDT','MP3D.MDT','MP40.MDT','MP41.MDT',
    'MP4D.MDT','MP50.MDT','MP51.MDT','MP5D.MDT','MP60.MDT',
    'MP60.MDT','MP61.MDT','MP62.MDT','MP6D.MDT','MP70.MDT',
    'MP71.MDT','MP72.MDT','MP73.MDT','MP7D.MDT','MP80.MDT',
    'MP81.MDT','MP82.MDT','MP83.MDT','MP84.MDT','MP8D.MDT',
    'MP90.MDT','MPA0.MDT',
]

# Town maps — destination y == 0x00FF means town warp (linear, no Y)
_TOWN_MAPS = {
    0x01: 'MRMP.MDT  (1. Muralla Town)',
    0x02: 'STMP.MDT  (2. Satono Town)',
    0x03: 'BSMP.MDT  (3. Bosque Village)',
    0x04: 'CMAP.MDT  (0. Felishika Castle)',
    0x05: 'HLMP.MDT  (4. Helada Town)',
    0x06: 'DRMP.MDT  (6. Dorado Town)',
    0x07: 'LLMP.MDT  (7. Llama Town)',
    0x08: 'PRMP.MDT  (8-1. Pureza Town)',
    0x09: 'ESMP.MDT  (8-2. Esco Village)',
    0x0A: 'TMMP.MDT  (5. Tumba Town)',
}

# Derive town stems for filename detection
_TOWN_STEMS = {v.split('.')[0] for v in _TOWN_MAPS.values()}

# ─── Monster type names (type field) ─────────────────────────────────────────
_MONSTER_TYPE_NAMES = {
    0x00: 'Bat',
    0x01: 'Snail/Slug',
    0x02: 'Frog',
    0x03: 'Rat/Lizard',
    0x04: 'Flying Eye',
    0x05: 'Skeleton',
    0x06: 'Ghost',
    0x07: 'Golem',
    0x08: 'Dragon',
    0x09: 'Witch',
    0x0A: 'Wizard',
    0x0B: 'Knight',
    0x0C: 'Demon',
}

# ─── Item type names (type field) ────────────────────────────────────────────
_ITEM_TYPE_NAMES = {
    0x00: 'Coin/Gold',
    0x25: '[HALT]',
    0x45: '[HALT]',
    0x65: '[HALT]',
    0x66: '[HALT]',
    0x67: '[FORCE QUIT]',
    0x68: '[Sprite: Explode]',
    0x69: '[Sprite: Explode -> Almas]',
    0x6A: '[Sprite: Explode]',
    0x6B: '[Sprite: Explode + Almas chest loop]',
    0x6C: '[Sprite: Explode]',
    0x6D: '[Sprite: Explode]',
    0x6E: '[Sprite: Explode]',
    0x6F: '[Sprite: Explode / Breakable wall (hero only)]',
    0x70: 'Passthrough Wall (hero only)',
    0x71: 'Block',
    0x72: '(none)',
    0x73: 'Chest',
    0x74: '1 Almas',
    0x75: '10 Almas',
    0x76: 'Key',
    0x77: 'Lion Key  (no sprite)',
    0x78: 'Red Potion (HP)',
    0x79: 'Blue Potion (MP)',
    0x7A: 'Ruzeria Shoes  (duplicate — may conflict)',  # 7a = Ruzeria Shoes
    0x7B: '100 Almas  (broken sprite)',
    0x7C: 'Empty Dialog Box',
    0x7D: "Hero's Helmet  (no sprite)",
    0x7E: 'Pureza Boots  (no sprite)',
    0x7F: '[HALT — corrupted sprite]',
    0x80: 'Bat',
    0x81: 'Snail',
    0xC0: '[Crash on entry]',
    0xCF: '[Sprite: Explode]',
    0xD0: 'Breakable Wall (hit only, floor-safe)',
    0xD1: 'Breakable Wall (hit + jump breaks)',
    0xD2: '[Crash on entry]',
    0xD3: '[Crash on entry]',
    0xFF: '[BROKEN — corrupted sprite]',
}

# ─── Helper functions ─────────────────────────────────────────────────────────
def _dung_name(mid):
    """Get dungeon map name from map_id."""
    return _DUNG_MAPS[mid] if 0 <= mid < len(_DUNG_MAPS) else f'?[{mid:#04x}]'


def _town_name(mid):
    """Get town map name from map_id."""
    return _TOWN_MAPS.get(mid, f'?[{mid:#04x}]')


def _ptr_off(ptr, file_size):
    """Convert runtime pointer to file offset."""
    if ptr == 0 or ptr == 0xFFFF:
        return None
    if ptr >= MDT_LOAD_ADDR:
        off = ptr - MDT_LOAD_ADDR
    else:
        off = ptr
    return off if off < file_size else None


# Alias for compatibility
_ptr_off_safe = _ptr_off


def _normalize_mdt_name(filename: str) -> str:
    """
    Normalize a possibly-qualified MDT name to plain upper filename.
    Examples:
      - 'C:/x/mp10.mdt' -> 'MP10.MDT'
      - 'zelres2.sar:mp10.mdt' -> 'MP10.MDT'
      - 'mp10.mdt  [Outdoor map]' -> 'MP10.MDT'
    """
    raw = str(filename or '').strip().replace('\\', '/')
    base = raw.split('/')[-1]
    if ':' in base:
        base = base.split(':')[-1]
    up = base.upper()
    idx = up.find('.MDT')
    if idx >= 0:
        up = up[:idx + 4]
    return up


def is_town_mdt(filename: str) -> bool:
    """Return True if the filename matches a known Zeliard town MDT."""
    stem = os.path.splitext(_normalize_mdt_name(filename))[0]
    return stem in _TOWN_STEMS


def get_map_type_info(filename: str) -> str:
    """Get human-readable map type description from filename."""
    fn = os.path.splitext(os.path.basename(filename))[0].upper().replace('.MDT', '')
    if fn.startswith('MP') and len(fn) >= 3:
        rest = fn[2:]
        if rest.endswith('D'):
            return f'Dungeon (world {rest[:-1]})'
        else:
            return f'Outdoor map (world {rest})'
    else:
        return {
            'CMAP':'0. Felishika Castle',
            'MRMP':'1. Muralla Town',
            'STMP':'2. Satono Town',
            'BSMP':'3. Bosque Village',
            'HLMP':'4. Helada Town',
            'TMMP':'5. Tumba Town',
            'DRMP':'6. Dorado Town',
            'LLMP':'7. Llama Town',
            'PRMP':'8-1. Pureza Town',
            'ESMP':'8-2. Esco Village',
        }.get(fn, 'Unknown / Resource')


# ─── MDT File Associations ────────────────────────────────────────────────────
# Central registry: when opening an MDT file, which GRP files should be loaded?
#
# Structure:
#   'MDT_FILE.MDT': {
#       'tileset': 'xxx.grp',      # Main tile pattern file
#       'extra_grps': [...],       # Additional GRP files (sprites, NPCs, etc.)
#   }
#
# Rules for auto-derived entries (not in this table):
#   - MP + world-char + *.MDT → mpp{world}.grp tileset, plus dchr.grp + enp{world}.grp
#   - name ends with 'D.MDT'  → dpat.grp tileset
#   - is_town_mdt()           → mpat.grp tileset
#   - otherwise               → cpat.grp tileset
#
# Source evidence:
#   cmap.mdt = Felishika Castle  → cpat.grp + cman.grp
#   MP* MDTs use world-indexed mpp*.grp (e.g. MP10 -> mpp1, MP2D -> mpp2, MPA0 -> mppa)
#   Town MDTs split by area type: underground towns -> dpat, surface towns -> mpat
_MDT_FILE_ASSOCIATIONS: dict = {
    # ── Felishika Castle ─────────────────────────
    'CMAP.MDT': {
        'tileset': 'cpat.grp',           # 0. Felishika's Castle (user-confirmed)
        'npc_grp': 'mman.grp',           # Castle hero sprites
    },

    # ── Town maps ─────────────────────────────────
    # Surface towns (mpat.grp) → mman.grp (town NPCs)
    'MRMP.MDT': {'tileset': 'mpat.grp', 'npc_grp': 'mman.grp'},   # 1. Muralla Town
    'BSMP.MDT': {'tileset': 'mpat.grp', 'npc_grp': 'mman.grp'},   # 3. Bosque Village
    'LLMP.MDT': {'tileset': 'mpat.grp', 'npc_grp': 'mman.grp'},   # 7. Llama Town
    'ESMP.MDT': {'tileset': 'mpat.grp', 'npc_grp': 'mman.grp'},   # 8-2. Esco Village

    # Underground towns (dpat.grp) → tman.grp (underground town NPCs)
    'STMP.MDT': {'tileset': 'dpat.grp', 'npc_grp': 'tman.grp'},   # 2. Satono Town
    'HLMP.MDT': {'tileset': 'dpat.grp', 'npc_grp': 'tman.grp'},   # 4. Helada Town
    'TMMP.MDT': {'tileset': 'dpat.grp', 'npc_grp': 'tman.grp'},   # 5. Tumba Town
    'DRMP.MDT': {'tileset': 'dpat.grp', 'npc_grp': 'tman.grp'},   # 6. Dorado Town
    'PRMP.MDT': {'tileset': 'dpat.grp', 'npc_grp': 'tman.grp'},   # 8-1. Pureza Town

    # ── World dungeon maps (mp?d suffix) ─────────
    'MP1D.MDT': {'tileset': 'mpp1.grp', 'extra_grps': []},
    'MP2D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP3D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP4D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP5D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP6D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP7D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP8D.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},
    'MP90.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},   # World 9
    'MPA0.MDT': {'tileset': 'dpat.grp', 'extra_grps': []},   # World A (final boss)

    # ── Outdoor / field maps (mp?0-3) ────────────
    'MP10.MDT': {'tileset': 'mpp1.grp', 'extra_grps': []},
    'MP20.MDT': {'tileset': 'mpp2.grp', 'extra_grps': []},
    'MP21.MDT': {'tileset': 'mpp2.grp', 'extra_grps': []},
    'MP30.MDT': {'tileset': 'mpp3.grp', 'extra_grps': []},
    'MP31.MDT': {'tileset': 'mpp3.grp', 'extra_grps': []},
    'MP40.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP41.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP50.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP51.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP60.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP61.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP62.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP70.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP71.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP72.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP73.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP80.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP81.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP82.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP83.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
    'MP84.MDT': {'tileset': 'mpat.grp', 'extra_grps': []},
}


def get_mdt_association(filename: str) -> dict:
    """
    Return the association dict for the given MDT file, or None if not explicitly registered.
    """
    base = _normalize_mdt_name(filename)
    stem_upper = os.path.splitext(base)[0] + '.MDT'
    return _MDT_FILE_ASSOCIATIONS.get(stem_upper)


def get_mdt_tileset(filename: str) -> str:
    """
    Return the GRP pattern file name for the given MDT filename.
    Rule priority:
      - MP + world-char + *.MDT → mpp{world}.grp (world: 1-9/A/B)
      - explicit table override  → _MDT_FILE_ASSOCIATIONS
      - name ends with 'D.MDT'  → dpat.grp  (fallback dungeon)
      - is_town_mdt()           → mpat.grp  (surface-town fallback)
      - otherwise               → cpat.grp  (common/castle)
    """
    base = _normalize_mdt_name(filename)
    stem_upper = os.path.splitext(base)[0] + '.MDT'

    # Check explicit association first
    assoc = _MDT_FILE_ASSOCIATIONS.get(stem_upper)
    if assoc:
        return assoc['tileset']

    # MP rule (highest priority for MP* files):
    # Any MDT starting with MP uses the 3rd character as world key.
    # ex) MP10/MP1D -> mpp1, MP90/MP9D -> mpp9, MPA0 -> mppa
    if len(base) >= 4 and base.startswith('MP') and base.endswith('.MDT'):
        world = base[2]
        if world.isdigit() and world != '0':
            return f'mpp{world}.grp'
        if world in {'A', 'B'}:
            return f'mpp{world.lower()}.grp'

    # Fallback rules
    if base.endswith('D.MDT'):
        return 'dpat.grp'
    if is_town_mdt(filename):
        return 'mpat.grp'
    return 'cpat.grp'


def get_mdt_npc_grps(filename: str) -> list:
    """
    Return a list of NPC GRP files to load when opening the given MDT file.
    For MP* files not in the table, auto-derive dchr.grp and enp*.grp.
    """
    base = _normalize_mdt_name(filename)
    stem_upper = os.path.splitext(base)[0] + '.MDT'

    # Check explicit association first
    assoc = _MDT_FILE_ASSOCIATIONS.get(stem_upper)
    if assoc and 'npc_grp' in assoc:
        return [assoc['npc_grp']]

    # Auto-derive for MP* files: dchr.grp + enp{world}.grp
    import re
    m = re.match(r'(?i)^mp([1-9a-b])', base)
    if m:
        world = m.group(1).lower()
        return ['dchr.grp', f'enp{world}.grp']

    return []

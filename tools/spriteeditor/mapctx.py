from .models import MdtData


class MapContext:
    """Holds all data and canvas references for a single opened MDT map."""
    def __init__(self, path: str, mdt: MdtData, raw_data: bytes):
        self.path = path
        self.mdt = mdt
        self.raw_data = raw_data
        # Per-map image caches (key = (tile_id, block_size, use_checker) or source variant)
        self.tile_images = {}
        self.source_tile_cache = {}
        # Canvas overlay IDs for this map
        self.overlay_ids = []
        self.tile_id_overlay_ids = []
        # Canvas widget and scrollbars (filled after creation)
        self.canvas = None
        self.vsb = None
        self.hsb = None

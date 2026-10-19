"""Create the drag-to-Applications Finder layout for Sofa's disk image."""
import sys

from ds_store import DSStore

with DSStore.open(sys.argv[1], "w+") as layout:
    layout["."]["bwsp"] = {
        "ShowStatusBar": False,
        "ShowToolbar": False,
        "ShowSidebar": False,
        "ShowPathbar": False,
        "ShowTabView": False,
        "WindowBounds": "{{200, 200}, {600, 400}}",
    }
    layout["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "iconSize": 96.0,
        "textSize": 13.0,
        "gridSpacing": 100.0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "backgroundType": 0,
    }
    layout["."]["vstl"] = ("type", b"icnv")
    layout["Sofa.app"]["Iloc"] = (150, 130)
    layout["Applications"]["Iloc"] = (450, 130)
    layout["Install Sofa.txt"]["Iloc"] = (300, 285)

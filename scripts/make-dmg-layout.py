#!/usr/bin/env python3
"""Regenerate the checked-in Finder template (requires ds_store==1.3.1).

The regular DMG build only copies the template and needs no Python packages.
"""
from pathlib import Path

from ds_store import DSStore


target = Path(__file__).resolve().parent.parent / "Resources/DMGLayout.bin"
with DSStore.open(str(target), "w+") as store:
    store["."]["bwsp"] = {
        "WindowBounds": "{{220, 160}, {640, 360}}",
        "ShowStatusBar": False,
        "ShowToolbar": False,
        "ShowPathbar": False,
        "ShowSidebar": False,
        "ContainerShowSidebar": False,
        "ShowTabView": False,
        "PreviewPaneVisibility": False,
        "SidebarWidth": 0,
    }
    store["."]["icvp"] = {
        "viewOptionsVersion": 1,
        "backgroundType": 0,
        "gridOffsetX": 0.0,
        "gridOffsetY": 0.0,
        "gridSpacing": 100.0,
        "arrangeBy": "none",
        "showIconPreview": True,
        "showItemInfo": False,
        "labelOnBottom": True,
        "textSize": 14.0,
        "iconSize": 96.0,
        "scrollPositionX": 0.0,
        "scrollPositionY": 0.0,
    }
    store["."]["icvl"] = ("type", b"icnv")
    store["."]["vSrn"] = ("long", 1)
    store["Tunerfenster.app"]["Iloc"] = (180, 160)
    store["Applications"]["Iloc"] = (460, 160)
print(target)

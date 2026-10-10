# dmgbuild settings for Suniye.dmg: the volume contents and the Finder window
# that opens when the DMG is mounted. scripts/create_dmg.sh passes `app` and
# `background` with -D. Positions are in points from the top left of the window
# content; scripts/render_dmg_background.swift draws the art around them.
#
# Do not set hide_extensions: it writes a com.apple.FinderInfo attribute onto
# the signed app, and `codesign --verify --strict` then rejects the app.
import os.path
import plistlib

app = defines["app"]
app_name = os.path.basename(app)
with open(os.path.join(app, "Contents", "Info.plist"), "rb") as info:
    icon_name = plistlib.load(info)["CFBundleIconFile"]

format = "ULMO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", os.path.splitext(icon_name)[0] + ".icns")
background = defines["background"]

# Finder's window bounds include the title bar: 432 pt is the 400 pt design
# under a 32 pt title bar (macOS 27). The background is 432 pt tall, so a
# shorter title bar shows more of the hills, never a tiled copy of the image.
window_rect = ((400, 300), (660, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
arrange_by = None
icon_size = 112
text_size = 12
label_pos = "bottom"
icon_locations = {
    app_name: (180, 170),
    "Applications": (480, 170),
}

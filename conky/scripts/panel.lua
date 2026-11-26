-- Draws the panel's translucent, rounded background behind the conky text, and tells the live
-- wallpaper where the panel is (it draws frosted glass under it: KWin can't blur conky's window).
require 'cairo'

local RADIUS = 16
local R, G, B = 0x1c / 255, 0x12 / 255, 0x0c / 255
local ALPHA = 105 / 255   -- lighter than the old 150: the wallpaper frosts what's behind

local last = ""
-- glass.qml: a QtObject the wallpaper loads (it can't read JSON files, see weather.qml)
local function tell_wallpaper(w, h, head, gx, gy)
    local key = table.concat({w, h, head, gx, gy}, ",")
    if key == last then return end
    last = key
    local dir = (os.getenv("XDG_CACHE_HOME") or (os.getenv("HOME") .. "/.cache")) .. "/sepia-summit"
    os.execute("mkdir -p '" .. dir .. "'")
    local f = io.open(dir .. "/glass.qml", "w")
    if not f then return end
    f:write(string.format('import QtQml\nQtObject { readonly property var panels: [{"head": %d, "anchor": "top_right", ' ..
        '"gap_x": %d, "gap_y": %d, "w": %d, "h": %d, "r": %d}] }\n', head, gx, gy, w, h, RADIUS))
    f:close()
end

function conky_sepia_bg(head, gx, gy)
    if conky_window == nil then return end
    local w, h = conky_window.width, conky_window.height
    if w == 0 or h == 0 then return end
    tell_wallpaper(w, h, tonumber(head) or 0, tonumber(gx) or 36, tonumber(gy) or 36)

    local surface = conky_surface()
    if not surface then return end

    local cr = cairo_create(surface)
    local deg = math.pi / 180
    cairo_new_sub_path(cr)
    cairo_arc(cr, w - RADIUS, RADIUS, RADIUS, -90 * deg, 0)
    cairo_arc(cr, w - RADIUS, h - RADIUS, RADIUS, 0, 90 * deg)
    cairo_arc(cr, RADIUS, h - RADIUS, RADIUS, 90 * deg, 180 * deg)
    cairo_arc(cr, RADIUS, RADIUS, RADIUS, 180 * deg, 270 * deg)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, R, G, B, ALPHA)
    cairo_fill_preserve(cr)
    cairo_set_source_rgba(cr, 0xf5 / 255, 0xe8 / 255, 0xca / 255, 0.10)   -- faint glass edge
    cairo_set_line_width(cr, 1.5)
    cairo_stroke(cr)
    cairo_destroy(cr)
end

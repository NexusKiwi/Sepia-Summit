-- Draws the panel's translucent, rounded background behind the conky text.
require 'cairo'

local RADIUS = 16
local R, G, B = 0x1c / 255, 0x12 / 255, 0x0c / 255
local ALPHA = 150 / 255

function conky_sepia_bg()
    if conky_window == nil then return end
    local w, h = conky_window.width, conky_window.height
    if w == 0 or h == 0 then return end

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
    cairo_fill(cr)
    cairo_destroy(cr)
end

-- Draws the panel background: the slice of wallpaper behind the panel, then a
-- rounded translucent tint. KWin backs desktop-type windows with white, so real
-- transparency isn't possible there, and only that type both survives Show
-- Desktop and stays under normal windows.
require 'cairo'
require 'cairo_xlib'

local RADIUS = 16
local R, G, B = 0x1c / 255, 0x12 / 255, 0x0c / 255
local ALPHA = 150 / 255
local RECHECK_EVERY = 40   -- updates between checks for a moved panel or changed monitors
local WPDIR = os.getenv('HOME') .. '/Pictures/Wallpapers/sepia-mountains/'

local backdrop, backdrop_key, backdrop_w, backdrop_h
local ticks = 0

local function read_cmd(cmd)
    local f = io.popen(cmd .. ' 2>/dev/null')
    if not f then return '' end
    local out = f:read('*a') or ''
    f:close()
    return out
end

local function monitors()
    local list = {}
    for w, h, x, y in read_cmd('xrandr --listmonitors'):gmatch('(%d+)/%d+x(%d+)/%d+%+(%-?%d+)%+(%-?%d+)') do
        list[#list + 1] = { w = tonumber(w), h = tonumber(h), x = tonumber(x), y = tonumber(y) }
    end
    return list
end

local function panel_position()
    for line in read_cmd('xwininfo -root -tree'):gmatch('[^\n]+') do
        if line:find('"Conky"', 1, true) then
            local x, y = line:match('%d+x%d+[%+%-]%-?%d+[%+%-]%-?%d+%s+%+(%-?%d+)%+(%-?%d+)')
            if x then return tonumber(x), tonumber(y) end
        end
    end
end

-- Same choice of image as plasma/set-wallpaper.js
local function wallpaper_for(mon, list)
    local tall = mon.h > 1150
    if #list == 2 then
        local leftmost = math.min(list[1].x, list[2].x)
        local side = mon.x == leftmost and 'LEFT' or 'RIGHT'
        return (tall and 'sepia-mountains_dual-1440p_5120x1440_' or 'sepia-mountains_dual-1080p_3840x1080_') .. side .. '.png'
    elseif mon.w / mon.h >= 2.2 then
        return tall and 'sepia-mountains_ultrawide_3440x1440.png' or 'sepia-mountains_ultrawide_2560x1080.png'
    end
    return tall and 'sepia-mountains_single_2560x1440.png' or 'sepia-mountains_single_1920x1080.png'
end

local function rounded_tint(cr, w, h)
    local deg = math.pi / 180
    cairo_new_sub_path(cr)
    cairo_arc(cr, w - RADIUS, RADIUS, RADIUS, -90 * deg, 0)
    cairo_arc(cr, w - RADIUS, h - RADIUS, RADIUS, 0, 90 * deg)
    cairo_arc(cr, RADIUS, h - RADIUS, RADIUS, 90 * deg, 180 * deg)
    cairo_arc(cr, RADIUS, RADIUS, RADIUS, 180 * deg, 270 * deg)
    cairo_close_path(cr)
    cairo_set_source_rgba(cr, R, G, B, ALPHA)
    cairo_fill(cr)
end

local function refresh_backdrop(w, h)
    local px, py = panel_position()
    if not px then return end
    local list, mon = monitors(), nil
    for _, m in ipairs(list) do
        if px >= m.x and px < m.x + m.w and py >= m.y and py < m.y + m.h then mon = m end
    end
    if not mon then return end

    local file = wallpaper_for(mon, list)
    local key = table.concat({ file, px, py, w, h, mon.x, mon.y, mon.w, mon.h }, ':')
    if key == backdrop_key then return end

    local img = cairo_image_surface_create_from_png(WPDIR .. file)
    if cairo_surface_status(img) ~= CAIRO_STATUS_SUCCESS then
        cairo_surface_destroy(img)
        return
    end

    -- Scaled and centre-cropped, like the wallpaper plugin
    local iw, ih = cairo_image_surface_get_width(img), cairo_image_surface_get_height(img)
    local scale = math.max(mon.w / iw, mon.h / ih)
    local ox = (mon.w - iw * scale) / 2 + mon.x - px
    local oy = (mon.h - ih * scale) / 2 + mon.y - py

    local slice = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h)
    local cr = cairo_create(slice)
    cairo_save(cr)
    cairo_translate(cr, ox, oy)
    cairo_scale(cr, scale, scale)
    cairo_set_source_surface(cr, img, 0, 0)
    cairo_paint(cr)
    cairo_restore(cr)
    rounded_tint(cr, w, h)
    cairo_destroy(cr)
    cairo_surface_destroy(img)

    if backdrop then cairo_surface_destroy(backdrop) end
    backdrop, backdrop_key, backdrop_w, backdrop_h = slice, key, w, h
end

function conky_sepia_bg()
    if conky_window == nil then return end
    local w, h = conky_window.width, conky_window.height
    if w == 0 or h == 0 then return end

    -- conky reports a small height on its first frames, so rebuild on any resize
    if not backdrop or w ~= backdrop_w or h ~= backdrop_h or ticks % RECHECK_EVERY == 0 then
        refresh_backdrop(w, h)
    end
    ticks = ticks + 1

    local surface = cairo_xlib_surface_create(conky_window.display, conky_window.drawable,
                                              conky_window.visual, w, h)
    local cr = cairo_create(surface)
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE)
    if backdrop and w == backdrop_w and h == backdrop_h then
        cairo_set_source_surface(cr, backdrop, 0, 0)
    else
        cairo_set_source_rgb(cr, R, G, B)
    end
    cairo_paint(cr)
    cairo_destroy(cr)
    cairo_surface_destroy(surface)
end

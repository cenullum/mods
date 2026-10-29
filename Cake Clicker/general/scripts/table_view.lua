singleton_name = "table_view"

-- =============================================================================
-- Cake Clicker - the table itself, on every screen (all peers).
--
-- Draws the table and the plate, the slices (the top layer's colour, sized by
-- what is left), each seat's colour on the rim, the arrow of a push in
-- progress, the message in the middle ("No slice, turn the plate"), the
-- crumbs of my bites and the two A / D keys under the table.
--
-- Each peer turns the table so that its own seat is at the bottom; the rest of
-- the screen (market, panels, board) is the same for everyone, so everyone's
-- mouse cursor points at the same thing on every screen.
--
-- Input: the left/right stick (A / D, the arrow keys, a gamepad stick). A press
-- gives instant feedback here (a sound, crumbs) and goes to game.lua, which
-- decides: a bite while there is cake in front, otherwise a push.
--
-- The seats and the bots' cursors are seats_view.lua; news, sounds of what
-- happens and the floating "+grams" are news_view.lua.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local TAU = math.pi * 2
local TABLE = CATALOG.table_layout
local CENTER_X, CENTER_Y = TABLE.center_x, TABLE.center_y
local INNER_RADIUS = TABLE.cake * 0.14       -- the bare middle of the plate

local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end

local function hex_color(hex, alpha)
    return Color(tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255, alpha or 1)
end
local function faded(color, alpha) return Color(color.r, color.g, color.b, alpha) end

local COLORS = {
    surface = hex_color("#fffdf9"), surface_dim = hex_color("#f4f0e7"), ink = hex_color("#2e1a12"),
    soft = hex_color("#6f5547"), line = hex_color("#ddd5c6"), accent = hex_color("#e23d6d"),
    good = hex_color("#2d8a3e"), bad = hex_color("#cf3434"), warn = hex_color("#c77700"),
    table = hex_color("#d6a676"), table_rings = hex_color("#c18f5e"), plate = hex_color("#ffffff"),
    plate_rim = hex_color("#e4ddd2"), white = Color(1, 1, 1, 1), clear = Color(0, 0, 0, 0),
    slice_edge = Color(0.24, 0.12, 0.06, 0.42), slice_shine = Color(1, 1, 1, 0.55), cherry_glow = Color(1, 0.84, 0.29, 0.9),
}

add_tag(name, "cc_view")
add_tag(name, "cc_pockets")     -- also gets my upgrades and pocket (pockets_ALL)

-- =============================================================================
-- Text (every word comes from general/language/cake_clicker_<code>.json)
-- =============================================================================
local translations = {}
local language = ""

local function words(key)
    local text = translations[key]
    if text == nil then
        text = translate("{" .. key .. "}")
        translations[key] = text
    end
    return text
end

local function words_with(key, ...)
    local ok, text = pcall(string.format, words(key), ...)
    return ok and text or words(key)
end

-- =============================================================================
-- Drawing helpers. Every *_view.lua carries the ones it uses (the same code in
-- each: a script runs in its own Lua state and cannot share functions). They
-- are retained: the engine is only called when something about an element
-- changed, and whatever a frame did not draw is hidden at its end.
-- =============================================================================
local drawn = {}
local frame_number = 0

local function record(element_name, kind)
    local entry = drawn[element_name]
    if not entry then
        entry = { kind = kind }
        drawn[element_name] = entry
    end
    entry.frame = frame_number
    return entry
end

local function color_changed(entry, field, color)
    local old = entry[field]
    if old and old.r == color.r and old.g == color.g and old.b == color.b and old.a == color.a then return false end
    entry[field] = Color(color.r, color.g, color.b, color.a)
    return true
end

local function image(element_name, path, x, y, width, height, options)
    local entry = record(element_name, "image")
    local config = nil
    local function change() config = config or { name = element_name } return config end
    if entry.path ~= path then
        change().image_path = path
        entry.path, entry.width = path, nil
    end
    if not entry.visible then change().visible = true entry.visible = true end
    if entry.x ~= x or entry.y ~= y then change().position = Vector2(x, y) entry.x, entry.y = x, y end
    if entry.width ~= width or entry.height ~= height then
        change().scale = Vector2(width, height)
        entry.width, entry.height = width, height
    end
    if color_changed(entry, "tint", options and options.tint or COLORS.white) then change().modulate = entry.tint end
    local z = options and options.z or 0
    if entry.z ~= z then change().z_index = z entry.z = z end
    local rotation = options and options.rotation or 0
    if entry.rotation ~= rotation then change().rotation = rotation entry.rotation = rotation end
    local flip_h, flip_v = (options and options.flip_h) == true, (options and options.flip_v) == true
    if entry.flip_h ~= flip_h or entry.flip_v ~= flip_v then
        change().flip_h = flip_h
        config.flip_v = flip_v
        entry.flip_h, entry.flip_v = flip_h, flip_v
    end
    if config then set_image(config) end
end

local function icon(element_name, icon_name, x, y, size, options)
    image(element_name, "icons/" .. icon_name, x, y, size, size, options)
end

local function label(element_name, text, x, y, width, height, size, color, options)
    local entry = record(element_name, "label")
    local align = options and options.align or 1
    local valign = options and options.valign or 1
    local left = align == 0 and x or (align == 1 and x - width / 2 or x - width)
    local top = valign == 0 and y or (valign == 1 and y - height / 2 or y - height)
    local config = nil
    local function change() config = config or { name = element_name } return config end
    if not entry.created then
        change().scale = 0.5
        entry.created = true
    end
    if not entry.visible then change().visible = true entry.visible = true end
    if entry.text ~= text then change().text = text entry.text = text end
    if entry.left ~= left or entry.top ~= top then change().position = Vector2(left, top) entry.left, entry.top = left, top end
    if entry.width ~= width or entry.height ~= height then
        change().size = Vector2(width * 2, height * 2)
        entry.width, entry.height = width, height
    end
    if entry.size ~= size then change().font_size = math.floor(size * 2) entry.size = size end
    if color_changed(entry, "color", color) then change().font_color = entry.color end
    local outline = options and options.outline or 0
    if color_changed(entry, "outline_color", options and options.outline_color or COLORS.white) or entry.outline ~= outline then
        change().outline_size = math.floor(outline * 2)
        config.outline_color = entry.outline_color
        entry.outline = outline
    end
    if entry.align ~= align or entry.valign ~= valign then
        change().horizontal_alignment = align
        config.vertical_alignment = valign
        entry.align, entry.valign = align, valign
    end
    local z = options and options.z or 0
    if entry.z ~= z then change().z_index = z entry.z = z end
    if config then
        set_label(config)
        -- set_label sets the size before the font, and a Label never shrinks
        -- below what its previous text needed: send the size once more
        if config.text or config.font_size then set_label({ name = element_name, size = Vector2(width * 2, height * 2) }) end
    end
end

local function circle(element_name, x, y, radius, fill, line_color, line_width, z)
    local entry = record(element_name, "circle")
    local config = nil
    local function change() config = config or { name = element_name } return config end
    if not entry.visible then change().visible = true entry.visible = true end
    if entry.x ~= x or entry.y ~= y then change().position = Vector2(x, y) entry.x, entry.y = x, y end
    if entry.radius ~= radius then
        change().radius = radius
        config.segments = math.min(128, math.max(24, math.floor(radius)))
        entry.radius = radius
    end
    if color_changed(entry, "line", line_color) then change().color = entry.line end
    if color_changed(entry, "fill", fill) then change().fill_color = entry.fill end
    if entry.line_width ~= line_width then change().width = line_width entry.line_width = line_width end
    if entry.z ~= z then change().z_index = z entry.z = z end
    if config then set_circle(config) end
end

local function polyline(element_name, signature, build_points, color, width, z)
    local entry = record(element_name, "line")
    if entry.signature == signature and entry.visible then return end
    entry.signature, entry.visible = signature, true
    set_line({ name = element_name, points = build_points(), color = color, width = width, z_index = z })
end

local function arc_points(x, y, radius, from_angle, to_angle)
    local count = math.max(4, math.ceil(math.abs(to_angle - from_angle) / 0.07))
    local points = {}
    for index = 0, count do
        local angle = from_angle + (to_angle - from_angle) * index / count
        points[#points + 1] = Vector2(x + math.cos(angle) * radius, y + math.sin(angle) * radius)
    end
    return points
end

local function panel(element_name, x, y, width, height, color, z, outline)
    local corner = math.min(12, width / 2, height / 2)
    local left, top, right, bottom = x - width / 2, y - height / 2, x + width / 2, y + height / 2
    local inner_width, inner_height = width - 2 * corner, height - 2 * corner
    local half = corner / 2
    local function pieces(prefix, corner_path, top_path, side_path, tint, layer)
        image(element_name .. prefix .. "1", corner_path, left + half, top + half, corner, corner, { tint = tint, z = layer })
        image(element_name .. prefix .. "2", corner_path, right - half, top + half, corner, corner, { tint = tint, z = layer, flip_h = true })
        image(element_name .. prefix .. "3", corner_path, left + half, bottom - half, corner, corner, { tint = tint, z = layer, flip_v = true })
        image(element_name .. prefix .. "4", corner_path, right - half, bottom - half, corner, corner, { tint = tint, z = layer, flip_h = true, flip_v = true })
        if inner_width > 0 then
            image(element_name .. prefix .. "5", top_path, x, top + half, inner_width + 1, corner, { tint = tint, z = layer })
            image(element_name .. prefix .. "6", top_path, x, bottom - half, inner_width + 1, corner, { tint = tint, z = layer, flip_v = true })
        end
        if inner_height > 0 then
            image(element_name .. prefix .. "7", side_path, left + half, y, corner, inner_height + 1, { tint = tint, z = layer })
            image(element_name .. prefix .. "8", side_path, right - half, y, corner, inner_height + 1, { tint = tint, z = layer, flip_h = true })
        end
    end
    pieces("__box", "ui/bc", "ui/beh", "ui/bev", color, z)
    if inner_width > 0 and inner_height > 0 then
        image(element_name .. "__box9", "ui/px", x, y, inner_width + 1, inner_height + 1, { tint = color, z = z })
    end
    if outline then pieces("__rim", "ui/rc", "ui/reh", "ui/rev", outline, z + 1) end
end

local function text_width(text, size)
    local width, index, length = 0, 1, #text
    while index <= length do
        local byte = text:byte(index)
        if byte < 0x80 then
            width = width + (byte == 32 and size * 0.3 or size * 0.56)
            index = index + 1
        elseif byte >= 0xF0 then
            width, index = width + size, index + 4
        elseif byte >= 0xE0 then
            local code = (byte % 16) * 4096 + ((text:byte(index + 1) or 0) % 64) * 64 + ((text:byte(index + 2) or 0) % 64)
            width, index = width + (code >= 0x2E80 and size or size * 0.6), index + 3
        else
            width, index = width + size * 0.58, index + 2
        end
    end
    return width
end

local function begin_frame()
    frame_number = frame_number + 1
end

local function finish_frame()
    for element_name, entry in pairs(drawn) do
        if entry.frame ~= frame_number and entry.visible then
            entry.visible = false
            if entry.kind == "image" then set_image({ name = element_name, visible = false })
            elseif entry.kind == "label" then set_label({ name = element_name, visible = false })
            elseif entry.kind == "circle" then set_circle({ name = element_name, visible = false })
            elseif entry.kind == "line" then
                destroy_line(element_name)
                drawn[element_name] = nil
            end
        end
    end
end

-- =============================================================================
-- What this screen knows (from game.lua's messages)
-- =============================================================================
local state = {
    phase = "lobby", sequence = -1, seats = {}, players = 0, me = 0, countdown = 0, cake = "", slices = {},
    bodies = {}, rotation = 0, tension = 0, turning = false, lock = 0, pushers = { 0, 0 },
    my_upgrades = {}, my_pocket = {},
}
-- local animation and input
local show = { rotation = 0, tension = 0, crumbs = {}, shake = 0, pill_flash = { 0, 0 }, failed_at = 0, time = 0,
    last_direction = 0 }

local function sound(path, volume, pitch_spread)
    set_audio({ stream_path = path, bus = "Effect", volume = volume or 0, random_pitch = pitch_spread or 0, is_2d = false })
end

-- =============================================================================
-- Table geometry (this peer's seat at the bottom)
-- =============================================================================

local function slice_count() return state.players * 2 end

local function view_turn()
    if state.me == 0 or state.players == 0 then return 0 end
    return -(state.me - 1) * TAU / state.players
end

local function seat_angle(seat_number) return math.pi / 2 + (seat_number - 1) * TAU / math.max(1, state.players) + view_turn() end

local function front_number(seat_number) return (2 * (seat_number - 1) - state.rotation) % slice_count() end

local function slice_at(number) return state.slices[(number % slice_count()) + 1] end

local function my_slice() return state.me > 0 and slice_count() > 0 and slice_at(front_number(state.me)) or nil end

local function best_direction(seat_number)
    if slice_count() == 0 or #state.slices == 0 then return 0 end
    local mine = front_number(seat_number)
    for distance = 1, slice_count() // 2 do
        local left, right = slice_at(mine - distance), slice_at(mine + distance)
        local left_value = (left and left.left or 0) + ((left and left.cherry) and 0.5 or 0)
        local right_value = (right and right.left or 0) + ((right and right.cherry) and 0.5 or 0)
        if left_value > 0 or right_value > 0 then return left_value >= right_value and 1 or -1 end
    end
    return 0
end

local function layer_color(cake_id, layer_index)
    if layer_index == 0 then return hex_color(CATALOG.layers.honey.color) end
    local cake = CAKES[cake_id]
    local layer = cake and cake.layers[layer_index]
    if not layer then return COLORS.plate_rim end
    return hex_color(layer[3] or CATALOG.layers[layer[1]].color)
end

local function seat_name(seat_number)
    local seat = state.seats[seat_number]
    return seat and seat.short or "?"
end

-- =============================================================================
-- My bites
-- =============================================================================

local function spawn_crumbs()
    local slice = my_slice()
    local color = layer_color(state.cake, slice and slice.top or -1)
    for _ = 1, 5 do
        local angle, speed = math.random() * TAU, (0.3 + 0.7 * math.random()) * 140
        table.insert(show.crumbs, { x = CENTER_X, y = CENTER_Y + TABLE.cake * 0.62, speed_x = math.cos(angle) * speed,
            speed_y = math.sin(angle) * speed - 42, life = 0.4 + 0.4 * math.random(), color = color, radius = 1.5 + 2 * math.random() })
    end
    while #show.crumbs > 40 do table.remove(show.crumbs, 1) end
end

local function failed_press()
    if show.time - show.failed_at < 0.35 then return end
    show.failed_at = show.time
    show.shake = 0.26
    sound("bad")
end

-- =============================================================================
-- Receiving the state
-- =============================================================================

local function read_roster(roster)
    state.seats = {}
    for _, entry in ipairs(roster.seats or {}) do
        table.insert(state.seats, { id = tostring(entry.id), short = tostring(entry.s), hex = tostring(entry.c),
            color = hex_color(tostring(entry.c)) })
    end
    state.players = #state.seats
    state.me = 0
    for number, seat in ipairs(state.seats) do
        if seat.id == LOCAL_STEAM_ID then state.me = number end
    end
end

local function read_table(part)
    state.slices = {}
    local numbers = part.slices or {}
    for index = 1, #numbers // 3 do
        local flags = math.floor(numbers[index * 3] or 0)
        state.slices[index] = { left = (numbers[index * 3 - 2] or 0) / 1000, top = math.floor(numbers[index * 3 - 1] or -1),
            cherry = flags % 2 == 1, salted = (flags // 2) % 2 == 1 }
    end
    state.bodies = {}
    local body = part.seats or {}
    for number = 1, #body // 6 do
        local base = (number - 1) * 6
        local flags = math.floor(body[base + 1] or 0)
        state.bodies[number] = { stuffed = flags % 2 == 1, disarmed = (flags // 2) % 2 == 1, pushing = (flags // 4) % 2 == 1,
            coffee = (flags // 8) % 2 == 1, empty = (flags // 16) % 2 == 1, fullness = body[base + 2] or 0,
            stamina = (body[base + 3] or 0) / 10, max_stamina = body[base + 4] or 12, wait = (body[base + 5] or 0) / 10,
            auto_bites = math.floor(body[base + 6] or 0) }
    end
    state.rotation = math.floor(part.rotation or 0)
    state.tension = part.tension or 0
    state.turning = part.turning == true
    state.lock = (part.lock or 0) / 10
    state.pushers = { math.floor((part.pushers or {})[1] or 0), math.floor((part.pushers or {})[2] or 0) }
end

function pockets_ALL(sender_id, changed)
    for _, entry in ipairs(changed or {}) do
        if math.floor(entry.seat) == state.me then
            state.my_upgrades = {}
            for index, key in ipairs(CATALOG.upgrade_order) do state.my_upgrades[key] = math.floor((entry.levels or {})[index] or 0) end
            state.my_pocket = {}
            for _, item in ipairs(entry.pocket or {}) do table.insert(state.my_pocket, tostring(item)) end
        end
    end
end

function state_ALL(sender_id, message)
    local sequence = math.floor(tonumber(message.q) or 0)
    if sequence <= state.sequence and sequence > 1 then return end
    state.sequence = sequence
    state.phase = tostring(message.phase or "lobby")
    if state.phase == "lobby" then
        state.seats, state.players, state.me, state.slices, state.cake = {}, 0, 0, {}, ""
        return
    end
    if message.roster then read_roster(message.roster) end
    state.countdown = (tonumber(message.countdown) or 0) / 10
    state.cake = tostring(message.cake or "")
    if type(message.table) == "table" then read_table(message.table) end
end

-- =============================================================================
-- Input: a press of left or right
-- =============================================================================

local function press(direction)
    if state.phase ~= "eating" or state.me == 0 then return end
    local body = state.bodies[state.me]
    if not body then return end
    local slice = my_slice()
    if slice and slice.left > 0 then
        if body.stuffed or body.disarmed then
            failed_press()
        else
            sound("bite", -2, 0.1)
            spawn_crumbs()
        end
    elseif state.lock > 0 or state.turning or body.stamina < 1 then
        failed_press()
    else
        sound("push", -3, 0.08)
        show.pill_flash[direction > 0 and 1 or 2] = 0.12
    end
    run_network_function("-game", "press_HOST", { direction })
end

local function read_input(inputs)
    local stick = inputs and inputs.stick_1
    local x = stick and stick.x or 0
    local direction = 0
    if x <= -0.5 then direction = 1 elseif x >= 0.5 then direction = -1 end
    if direction ~= 0 and direction ~= show.last_direction then press(direction) end
    show.last_direction = direction
end

-- =============================================================================
-- Animation
-- =============================================================================

local function animate(delta)
    show.time = show.time + delta
    show.rotation = show.rotation + (state.rotation - show.rotation) * math.min(1, delta * 9)
    local rotation_gap = math.abs(state.rotation - show.rotation)
    -- snap the last bit (and big jumps), so the slices stop being rebuilt
    if rotation_gap > 3 or rotation_gap < 0.002 then show.rotation = state.rotation end
    show.tension = show.tension + (state.tension - show.tension) * math.min(1, delta * 12)
    if math.abs(state.tension - show.tension) < 0.5 then show.tension = state.tension end
    local kept = {}
    for _, crumb in ipairs(show.crumbs) do
        crumb.speed_y = crumb.speed_y + 420 * delta
        crumb.x, crumb.y = crumb.x + crumb.speed_x * delta, crumb.y + crumb.speed_y * delta
        crumb.life = crumb.life - delta
        if crumb.life > 0 then table.insert(kept, crumb) end
    end
    show.crumbs = kept
    show.shake = math.max(0, show.shake - delta)
    show.pill_flash[1] = math.max(0, show.pill_flash[1] - delta)
    show.pill_flash[2] = math.max(0, show.pill_flash[2] - delta)
end

-- =============================================================================
-- Drawing
-- =============================================================================

local function wedge_outline(x, y, inner, outer, from_angle, to_angle)
    local points = arc_points(x, y, outer, from_angle, to_angle)
    for _, point in ipairs(arc_points(x, y, inner, to_angle, from_angle)) do points[#points + 1] = point end
    points[#points + 1] = points[1]
    return points
end

local function draw_plate_marks(slice_angle)
    -- each seat's colour along the plate's rim
    for number, seat in ipairs(state.seats) do
        local angle = seat_angle(number)
        local from_angle, to_angle = angle - slice_angle / 2 + 0.05, angle + slice_angle / 2 - 0.05
        polyline("seat_arc" .. number, string.format("%.3f%s", angle, seat.hex), function()
            return arc_points(CENTER_X, CENTER_Y, TABLE.plate * 0.965, from_angle, to_angle)
        end, seat.color, number == state.me and 6 or 4, -36)
    end
    -- the table lock, or an arrow showing which way the plate is being pushed
    local ring = TABLE.plate * 1.07
    if state.lock > 0 then
        circle("lock_ring", CENTER_X, CENTER_Y, ring, COLORS.clear, COLORS.soft, 3, -35)
        icon("lock_icon", "lock", CENTER_X, CENTER_Y + ring, 24, { z = -34 })
        label("lock_seconds", tostring(math.ceil(state.lock)), CENTER_X + 22, CENTER_Y + ring, 30, 20, 14, COLORS.ink,
            { align = 0, z = -34, outline = 3, outline_color = COLORS.surface })
    elseif math.abs(show.tension) > 2 then
        local share = math.min(1, math.abs(show.tension) / 100)
        local sweep = share * math.pi * 0.9 * (show.tension > 0 and 1 or -1)
        local start_angle = math.pi / 2
        local color = faded(COLORS.accent, 0.35 + 0.55 * share)
        polyline("tension_arc", string.format("%.3f", sweep), function()
            return arc_points(CENTER_X, CENTER_Y, ring, start_angle, start_angle + sweep)
        end, color, 4.4, -35)
        local tip = start_angle + sweep
        image("tension_head", "ui/tri", CENTER_X + math.cos(tip) * ring, CENTER_Y + math.sin(tip) * ring, 18, 18,
            { tint = color, z = -34, rotation = tip + (show.tension > 0 and 1 or -1) * math.pi / 2 })
    end
end

local function draw_slice(number, slice, slice_angle, highlight)
    local angle = math.pi / 2 + (number - 1 + show.rotation) * slice_angle + view_turn()
    local from_angle, to_angle = angle - slice_angle / 2 + 0.035, angle + slice_angle / 2 - 0.035
    local x, y = CENTER_X + math.cos(angle) * 3, CENTER_Y + math.sin(angle) * 3
    local element = "slice" .. number
    if slice.left <= 0 then
        for crumb = 0, 3 do
            local distance = INNER_RADIUS + (TABLE.cake - INNER_RADIUS) * (((number * 7 + crumb * 13) % 10) / 11)
            local spread = angle + (((number + crumb) % 3) - 1) * slice_angle * 0.2
            image(element .. "_crumb" .. crumb, "ui/disc", x + math.cos(spread) * distance, y + math.sin(spread) * distance, 4, 4,
                { tint = COLORS.plate_rim, z = -30 })
        end
        if highlight == "mine" then
            polyline(element .. "_outline", string.format("e%.3f", angle), function()
                return wedge_outline(x, y, INNER_RADIUS, TABLE.cake, from_angle, to_angle)
            end, COLORS.accent, 2, -29)
        end
        return
    end
    local outer = math.sqrt(INNER_RADIUS ^ 2 + (TABLE.cake ^ 2 - INNER_RADIUS ^ 2) * math.min(1.15, slice.left))
    local signature = string.format("%.3f|%.1f|%d", angle, outer, slice.top)
    polyline(element .. "_fill", signature, function()
        return arc_points(x, y, (INNER_RADIUS + outer) / 2, from_angle, to_angle)
    end, layer_color(state.cake, slice.top), outer - INNER_RADIUS, -32)
    polyline(element .. "_edge", signature, function()
        return wedge_outline(x, y, INNER_RADIUS, outer, from_angle, to_angle)
    end, COLORS.slice_edge, 1.5, -31)
    polyline(element .. "_shine", signature, function()
        return arc_points(x, y, math.max(INNER_RADIUS, outer - 2), from_angle + 0.03, to_angle - 0.03)
    end, COLORS.slice_shine, 2, -31)
    if highlight then
        polyline(element .. "_outline", signature .. highlight, function()
            return wedge_outline(x, y, INNER_RADIUS, outer + 1, from_angle, to_angle)
        end, COLORS.accent, highlight == "mine" and 3.5 or 2.5, -29)
    end
    if slice.salted then
        for grain = 0, 5 do
            local distance = INNER_RADIUS + (outer - INNER_RADIUS) * (((grain * 37 + number * 11) % 17) / 17)
            local spread = from_angle + (to_angle - from_angle) * (((grain * 53 + number * 7) % 19) / 19)
            image(element .. "_salt" .. grain, "ui/disc", x + math.cos(spread) * distance, y + math.sin(spread) * distance, 4, 4, { z = -28 })
        end
    end
    if slice.cherry then
        local cherry_x, cherry_y = x + math.cos(angle) * (outer - 18), y + math.sin(angle) * (outer - 18)
        local glow = 40 + 6 * math.sin(show.time * 6)
        image(element .. "_glow", "ui/glow", cherry_x, cherry_y, glow, glow, { tint = COLORS.cherry_glow, z = -27 })
        icon(element .. "_cherry", "cherry", cherry_x, cherry_y, 24, { z = -26 })
    end
end

local function draw_table()
    circle("table", CENTER_X, CENTER_Y, TABLE.table, COLORS.table, COLORS.table_rings, 2, -40)
    for ring = 1, 4 do
        circle("table_ring" .. ring, CENTER_X, CENTER_Y, TABLE.table * 0.93 - (ring - 1) * 13, COLORS.clear,
            faded(COLORS.table_rings, 0.5), 1, -39)
    end
    circle("plate_shadow", CENTER_X, CENTER_Y + 6, TABLE.plate + 3, Color(0.2, 0.12, 0.06, 0.22), COLORS.clear, 1, -38)
    circle("plate", CENTER_X, CENTER_Y, TABLE.plate, COLORS.plate, COLORS.plate_rim, 2, -37)
    if state.players == 0 then return end
    local slice_angle = TAU / slice_count()
    draw_plate_marks(slice_angle)
    if state.cake == "" or #state.slices == 0 then return end
    local mine = state.me > 0 and front_number(state.me) or -1
    -- my slice is empty: outline the nearest full slice in the way to turn
    local target = -1
    local my_slice_now = my_slice()
    if mine >= 0 and state.phase == "eating" and my_slice_now and my_slice_now.left <= 0 then
        local direction = best_direction(state.me)
        for distance = 1, slice_count() do
            local candidate = (mine - direction * distance) % slice_count()
            if direction ~= 0 and state.slices[candidate + 1].left > 0 then
                target = candidate
                break
            end
        end
    end
    for number, slice in ipairs(state.slices) do
        local highlight = nil
        if number - 1 == mine then highlight = "mine" elseif number - 1 == target then highlight = "next" end
        draw_slice(number, slice, slice_angle, highlight)
    end
    circle("hub", CENTER_X, CENTER_Y, INNER_RADIUS * 0.92, COLORS.plate, COLORS.plate_rim, 1, -25)
end

local function draw_centre_message()
    if state.phase == "countdown" and state.countdown > 0 then
        panel("centre", CENTER_X, CENTER_Y, 120, 96, faded(COLORS.surface, 0.94), 60, COLORS.good)
        label("centre_title", tostring(math.ceil(state.countdown)), CENTER_X, CENTER_Y - 10, 110, 60, 52, COLORS.good, { z = 62 })
        label("centre_text", words("get_ready"), CENTER_X, CENTER_Y + 32, 110, 20, 12, COLORS.soft, { z = 62 })
        return
    end
    if state.phase ~= "eating" or state.me == 0 then return end
    local body = state.bodies[state.me]
    local slice = my_slice()
    if not body or not slice then return end
    local title, subtitle, color = nil, "", COLORS.ink
    if body.disarmed then
        title, subtitle, color = words("state_disarmed"), words_with("state_disarmed_sub", math.ceil(body.wait)), COLORS.bad
    elseif body.stuffed then
        local has_ayran = false
        for _, item in ipairs(state.my_pocket) do if item == "ayran" then has_ayran = true end end
        title, color = words("state_stuffed"), COLORS.bad
        subtitle = words_with(has_ayran and "state_stuffed_ayran" or "state_stuffed_sub", math.ceil(body.wait))
    elseif slice.left <= 0 then
        local direction = best_direction(state.me)
        title, color = words("state_empty"), COLORS.accent
        if body.stamina < 1 then subtitle = words("state_empty_tired")
        elseif direction > 0 then subtitle = words("state_empty_left")
        elseif direction < 0 then subtitle = words("state_empty_right")
        else subtitle = words("state_empty_done") end
    else
        -- someone is turning a smaller slice in front of me
        local toward = state.tension > 30 and 1 or (state.tension < -30 and -1 or 0)
        local pusher = toward == 1 and state.pushers[1] or (toward == -1 and state.pushers[2] or 0)
        if toward ~= 0 and pusher > 0 and pusher ~= state.me and state.lock <= 0 then
            local coming = slice_at(front_number(state.me) - toward)
            if coming and coming.left < slice.left then
                title, color = words_with("state_threat", seat_name(pusher)), COLORS.warn
                subtitle = (state.my_upgrades.guard_dog or 0) > 0 and words("state_threat_dog") or words("state_threat_eat")
            end
        end
    end
    if not title then return end
    local width = math.max(text_width(title, 17), text_width(subtitle, 12)) + 36
    local x = CENTER_X + (show.shake > 0 and math.sin(show.shake * 60) * 5 or 0)
    panel("centre", x, CENTER_Y, width, 56, faded(COLORS.surface, 0.94), 60, color)
    label("centre_title", title, x, CENTER_Y - 10, width, 24, 17, color, { z = 62 })
    label("centre_text", subtitle, x, CENTER_Y + 13, width, 18, 12, COLORS.soft, { z = 62 })
end

local function draw_crumbs()
    for index, crumb in ipairs(show.crumbs) do
        image("crumb" .. index, "ui/disc", crumb.x, crumb.y, crumb.radius * 2, crumb.radius * 2,
            { tint = faded(crumb.color, math.max(0, math.min(1, crumb.life * 2))), z = 79 })
    end
end

local function draw_turn_pills()
    if state.me == 0 then return end
    local suggest = 0
    local slice = my_slice()
    if state.phase == "eating" and slice and slice.left <= 0 then suggest = best_direction(state.me) end
    local pills = { { 1, -95, "◀  A", math.max(0, show.tension) }, { -1, 95, "D  ▶", math.max(0, -show.tension) } }
    for index, pill_info in ipairs(pills) do
        local direction, x, caption, push_share = pill_info[1], pill_info[2], pill_info[3], pill_info[4]
        local element = "turn_pill" .. index
        local outline = suggest == direction and faded(COLORS.accent, 0.55 + 0.45 * math.sin(show.time * 6)) or nil
        panel(element, x, 288, 170, 38, show.pill_flash[index] > 0 and COLORS.line or COLORS.surface_dim, 10, outline)
        local fill = math.max(0, math.min(1, push_share / 100))
        if fill > 0.01 then
            local fill_width = 166 * fill
            local fill_x = direction > 0 and (x - 83 + fill_width / 2) or (x + 83 - fill_width / 2)
            image(element .. "_fill", "ui/px", fill_x, 288, fill_width, 32, { tint = faded(COLORS.accent, 0.32), z = 12 })
        end
        label(element .. "_text", caption, x, 288, 160, 30, 16, COLORS.ink, { z = 13 })
    end
end

-- =============================================================================
-- Every frame
-- =============================================================================

function _process(delta, inputs)
    local current = get_current_language()
    if current ~= language then
        language = current
        translations = {}
    end
    read_input(inputs)
    animate(delta)
    begin_frame()
    if state.phase ~= "lobby" then
        draw_table()
        draw_centre_message()
        draw_crumbs()
        draw_turn_pills()
    end
    finish_frame()
end

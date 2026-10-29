singleton_name = "seats_view"

-- =============================================================================
-- Cake Clicker - the people at the table, on every screen (all peers).
--
-- Draws every seat around the table: avatar (Steam picture or the bot's
-- animal), name, score, a status icon (stuffed, spoon dropped, pushing,
-- coffee) and the bots' speech bubbles; and the bots' mouse cursors, drawn to
-- look like the engine's own player cursors (a glove and a name in the seat
-- colour). The players' own cursors ARE the engine's: set_cursor(true) in
-- world.lua, tinted here with each player's seat colour.
--
-- Like table_view.lua, each peer sees its own seat at the bottom.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local TAU = math.pi * 2
local TABLE = CATALOG.table_layout
local CENTER_X, CENTER_Y = TABLE.center_x, TABLE.center_y

local function hex_color(hex, alpha)
    return Color(tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255, alpha or 1)
end
local function faded(color, alpha) return Color(color.r, color.g, color.b, alpha) end

local COLORS = {
    surface = hex_color("#fffdf9"), ink = hex_color("#2e1a12"), soft = hex_color("#6f5547"),
    clear = Color(0, 0, 0, 0), white = Color(1, 1, 1, 1),
}

add_tag(name, "cc_view")

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

local function grouped(number)
    local digits = tostring(math.floor(math.abs(number)))
    local separator = words("num_group")
    local out = digits:reverse():gsub("(%d%d%d)", "%1" .. separator:reverse()):reverse()
    if out:sub(1, #separator) == separator then out = out:sub(#separator + 1) end
    return out
end

local function one_decimal(number) return (string.format("%.1f", number):gsub("%.", words("num_dec"))) end

local function grams(amount)
    amount = math.max(0, amount)
    if amount < 10 then return words_with("unit_g", one_decimal(amount)) end
    if amount < 1000 then return words_with("unit_g", grouped(amount)) end
    if amount < 1e6 then return words_with("unit_kg", one_decimal(amount / 1e3)) end
    return words_with("unit_t", one_decimal(amount / 1e6))
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

local function pill(element_name, x, y, width, height, color, z, outline)
    width = math.max(width, height)
    local middle = width - height
    local cap = height / 2
    local function pieces(prefix, cap_path, middle_path, tint, layer)
        image(element_name .. prefix .. "1", cap_path, x - middle / 2 - cap / 2, y, cap, height, { tint = tint, z = layer })
        image(element_name .. prefix .. "2", cap_path, x + middle / 2 + cap / 2, y, cap, height, { tint = tint, z = layer, flip_h = true })
        if middle > 0 then image(element_name .. prefix .. "3", middle_path, x, y, middle + 1, height, { tint = tint, z = layer }) end
    end
    pieces("__pill", "ui/pc", "ui/pm", color, z)
    if outline then pieces("__ring", "ui/qc", "ui/qm", outline, z + 1) end
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
local state = { phase = "lobby", sequence = -1, seats = {}, players = 0, me = 0, bodies = {}, scores = {}, cursors = {} }
local show = { bubbles = {}, cursors = {}, avatars = {}, cursor_colors = "", time = 0 }

-- =============================================================================
-- Seats (this peer's seat at the bottom)
-- =============================================================================

local function view_turn()
    if state.me == 0 or state.players == 0 then return 0 end
    return -(state.me - 1) * TAU / state.players
end

local function seat_angle(seat_number) return math.pi / 2 + (seat_number - 1) * TAU / math.max(1, state.players) + view_turn() end

local function to_view(x, y)
    local turn = view_turn()
    if turn == 0 then return x, y end
    local dx, dy = x - CENTER_X, y - CENTER_Y
    return CENTER_X + dx * math.cos(turn) - dy * math.sin(turn), CENTER_Y + dx * math.sin(turn) + dy * math.cos(turn)
end

-- =============================================================================
-- Receiving the state
-- =============================================================================

local function apply_cursor_colors()
    local signature = ""
    for _, seat in ipairs(state.seats) do signature = signature .. seat.id .. seat.hex end
    if signature == show.cursor_colors then return end
    show.cursor_colors = signature
    -- everyone's own mouse cursor (drawn by the engine) takes their seat colour
    for _, seat in ipairs(state.seats) do
        if not seat.bot then set_cursor(true, nil, seat.color, nil, seat.id) end
    end
end

local function read_roster(roster)
    state.seats = {}
    for _, entry in ipairs(roster.seats or {}) do
        table.insert(state.seats, { id = tostring(entry.id), short = tostring(entry.s), hex = tostring(entry.c),
            color = hex_color(tostring(entry.c)), icon = tostring(entry.ic or ""), bot = entry.bot == true })
    end
    state.players = #state.seats
    state.me = 0
    for number, seat in ipairs(state.seats) do
        if seat.id == LOCAL_STEAM_ID then state.me = number end
    end
    apply_cursor_colors()
end

-- Only the status flags of each seat's body (see cake_table.snapshot).
local function read_bodies(part)
    state.bodies = {}
    local body = part.seats or {}
    for number = 1, #body // 6 do
        local flags = math.floor(body[(number - 1) * 6 + 1] or 0)
        state.bodies[number] = { stuffed = flags % 2 == 1, disarmed = (flags // 2) % 2 == 1,
            pushing = (flags // 4) % 2 == 1, coffee = (flags // 8) % 2 == 1 }
    end
end

function state_ALL(sender_id, message)
    local sequence = math.floor(tonumber(message.q) or 0)
    if sequence <= state.sequence and sequence > 1 then return end
    state.sequence = sequence
    state.phase = tostring(message.phase or "lobby")
    if state.phase == "lobby" then
        state.seats, state.players, state.me = {}, 0, 0
        show.cursors, show.bubbles = {}, {}
        return
    end
    if message.roster then read_roster(message.roster) end
    if type(message.table) == "table" then read_bodies(message.table) end
    state.scores = {}
    local books = message.books or {}
    for number = 1, #books // 3 do state.scores[number] = (books[number * 3 - 2] or 0) / 10 end
    state.cursors = {}
    local cursors = message.cursors or {}
    for number = 1, #cursors // 3 do
        state.cursors[number] = { x = cursors[number * 3 - 2] or 0, y = cursors[number * 3 - 1] or 0,
            presses = math.floor(cursors[number * 3] or -1) }
    end
    -- a bot's remark becomes a speech bubble over its seat
    for _, event in ipairs(message.events or {}) do
        if event.k == "say" then
            show.bubbles[math.floor(tonumber(event.p) or 0)] = {
                text = words("line_" .. tostring(event.w) .. "_" .. math.floor(tonumber(event.n) or 1)), life = 2.3 }
        end
    end
end

function _on_loaded_avatar(player_id) show.avatars[tostring(player_id)] = true end

-- =============================================================================
-- Animation
-- =============================================================================

local function animate(delta)
    show.time = show.time + delta
    for seat_number, bubble in pairs(show.bubbles) do
        bubble.life = bubble.life - delta
        if bubble.life <= 0 then show.bubbles[seat_number] = nil end
    end
    -- the bots' cursors glide to where the host says they are; while there is a
    -- cake they are in table space and turn with this peer's view of the table
    local table_space = state.phase == "eating" or state.phase == "countdown"
    for seat_number, target in ipairs(state.cursors) do
        local seat = state.seats[seat_number]
        if seat and seat.bot and target.presses >= 0 then
            local x, y = target.x, target.y
            if table_space then x, y = to_view(x, y) end
            local cursor = show.cursors[seat_number]
            if not cursor then
                cursor = { x = x, y = y, presses = target.presses, pressed = 0, ripple = 0 }
                show.cursors[seat_number] = cursor
            end
            local follow = 1 - math.exp(-14 * delta)
            if math.abs(cursor.x - x) > 500 or math.abs(cursor.y - y) > 500 then follow = 1 end
            cursor.x, cursor.y = cursor.x + (x - cursor.x) * follow, cursor.y + (y - cursor.y) * follow
            if target.presses > cursor.presses then
                cursor.presses, cursor.pressed, cursor.ripple = target.presses, 0.1, 0.35
            end
            cursor.pressed = math.max(0, cursor.pressed - delta)
            cursor.ripple = math.max(0, cursor.ripple - delta)
        else
            show.cursors[seat_number] = nil
        end
    end
end

-- =============================================================================
-- Drawing
-- =============================================================================

local function draw_avatar(element, seat, x, y, radius, z)
    image(element .. "_ring", "ui/disc", x, y, radius * 2 + 7, radius * 2 + 7, { tint = seat.color, z = z })
    image(element .. "_disc", "ui/disc", x, y, radius * 2, radius * 2, { tint = COLORS.surface, z = z + 1 })
    if not seat.bot and show.avatars[seat.id] then
        image(element .. "_photo", seat.id, x, y, radius * 2, radius * 2, { z = z + 2 })
        local entry = drawn[element .. "_photo"]
        if not entry.shaded then
            entry.shaded = true
            set_shader({ parent_name = "", image_name = element .. "_photo", shader_name = "circle", outline_color = seat.color })
        end
    else
        icon(element .. "_icon", seat.icon ~= "" and seat.icon or "yum", x, y, 32, { z = z + 2 })
    end
end

local STATUS_ICONS = { { "stuffed", "dizzy" }, { "disarmed", "noentry" }, { "pushing", "rotate" }, { "coffee", "coffee" } }

local function draw_seats()
    for number, seat in ipairs(state.seats) do
        local angle = seat_angle(number)
        local x, y = CENTER_X + math.cos(angle) * TABLE.seats, CENTER_Y + math.sin(angle) * TABLE.seats
        local element = "seat" .. number
        local radius = TABLE.avatar
        local body = state.bodies[number] or {}
        if number == state.me then
            image(element .. "_glow", "ui/glow", x, y, 76, 76, { tint = faded(seat.color, 0.8), z = 1 })
        end
        draw_avatar(element, seat, x, y, radius, 2)
        for _, status in ipairs(STATUS_ICONS) do
            if body[status[1]] then
                image(element .. "_status_disc", "ui/disc", x + radius + 4, y - radius - 2, 30, 30, { tint = COLORS.surface, z = 6 })
                icon(element .. "_status", status[2], x + radius + 4, y - radius - 2, 24, { z = 7 })
                break
            end
        end
        local name_text = number == state.me and words("you") or seat.short
        local score_text = grams(state.scores[number] or 0)
        local width = math.max(text_width(name_text, 13), text_width(score_text, 12)) + 8
        local label_style = { z = 8, outline = 3, outline_color = COLORS.surface }
        if math.abs(math.sin(angle)) > 0.7 then
            -- top and bottom seats: the name to the side
            local label_x, align = x + radius + 9, 0
            if label_x + width > TABLE.table + 160 then label_x, align = x - radius - 9, 2 end
            label_style.align = align
            label(element .. "_name", name_text, label_x, y - 8, width, 18, 13, COLORS.ink, label_style)
            label(element .. "_score", score_text, label_x, y + 9, width, 16, 12, COLORS.soft, label_style)
        else
            label(element .. "_name", name_text, x, y + radius + 14, width + 20, 18, 13, COLORS.ink, label_style)
            label(element .. "_score", score_text, x, y + radius + 30, width + 20, 16, 12, COLORS.soft, label_style)
        end
        local bubble = show.bubbles[number]
        if bubble then
            local bubble_width = text_width(bubble.text, 12) + 24
            local above = math.sin(angle) > -0.3
            local bubble_y = above and (y - radius - 23) or (y + radius + 23 + (math.abs(math.sin(angle)) > 0.7 and 0 or 34))
            local bubble_x = math.max(-540 + bubble_width / 2, math.min(540 - bubble_width / 2, x))
            local alpha = math.min(1, bubble.life * 2)
            pill(element .. "_bubble", bubble_x, bubble_y, bubble_width, 26, faded(COLORS.surface, alpha), 40, faded(seat.color, alpha))
            label(element .. "_bubble_text", bubble.text, bubble_x, bubble_y, bubble_width, 26, 12, faded(COLORS.ink, alpha), { z = 42 })
        end
    end
end

local function draw_bot_cursors()
    if state.phase == "over" then return end
    for number, cursor in pairs(show.cursors) do
        local seat = state.seats[number]
        if seat then
            local size = cursor.pressed > 0 and 26 or 32
            image("cursor" .. number, "cursor", cursor.x + size / 2 - 6 * size / 32, cursor.y + size / 2 - 5 * size / 32,
                size, size, { tint = seat.color, z = 500 })
            label("cursor" .. number .. "_name", seat.short, cursor.x + 19, cursor.y + 24, 120, 18, 14, seat.color,
                { align = 0, valign = 0, z = 500, outline = 4, outline_color = Color(0, 0, 0, 0.85) })
            if cursor.ripple > 0 then
                local grown = 1 - cursor.ripple / 0.35
                circle("cursor" .. number .. "_ripple", cursor.x, cursor.y, 4 + 14 * grown, COLORS.clear,
                    faded(seat.color, 0.9 * (1 - grown)), 2, 499)
            end
        end
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
    animate(delta)
    begin_frame()
    if state.phase ~= "lobby" then
        draw_seats()
        draw_bot_cursors()
    end
    finish_frame()
end

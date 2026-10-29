singleton_name = "hud_view"

-- =============================================================================
-- Cake Clicker - the bar on top and my own panels (all peers).
--
-- Top: the clock (time left, the cake count or the crown race), everyone's
-- standing (rank, avatar, name, crowns, cake eaten), my wallet and the name
-- of the cake on the table with how much of it is left.
-- Left: my pocket (one-shot items; click one to use it) and my stomach - or
-- my arm strength while I have no slice and have to push.
-- Right: my upgrades; click one to read what it does. With a butler, a switch
-- turns it on and off.
--
-- A spectator (someone who joined during a game) only gets the top bar.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local ITEMS = {}
for _, item in ipairs(CATALOG.items) do ITEMS[item.id] = item end
local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end

local POCKET_X, POCKET_Y = -446, -150
local METER_X, METER_Y = -446, -26
local UPGRADES_X, UPGRADES_Y = 446, -10
local WALLET_X, WALLET_Y = 420, -212      -- clear of the engine's menu button (top right)
local DESCRIPTION_SECONDS = 6

local function hex_color(hex, alpha)
    return Color(tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255, alpha or 1)
end
local function faded(color, alpha) return Color(color.r, color.g, color.b, alpha) end
local COLORS = {
    surface = hex_color("#fffdf9"), surface_dim = hex_color("#f4f0e7"), ink = hex_color("#2e1a12"),
    soft = hex_color("#6f5547"), line = hex_color("#ddd5c6"), accent = hex_color("#e23d6d"),
    pista = hex_color("#5e8c27"), gold = hex_color("#b98309"), bad = hex_color("#cf3434"),
    arm = hex_color("#2f6fd6"), white = Color(1, 1, 1, 1), clear = Color(0, 0, 0, 0),
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

local function coins(amount) return grouped(math.max(0, amount)) end

local function clock_text(seconds)
    seconds = math.max(0, math.ceil(seconds))
    return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- =============================================================================
-- Drawing helpers. Every *_view.lua carries the ones it uses (the same code in
-- each: a script runs in its own Lua state and cannot share functions). They
-- are retained: the engine is only called when something about an element
-- changed, and whatever a frame did not draw is hidden at its end.
-- =============================================================================
local drawn = {}
local frame_number = 0
local clickables = {}
local mouse = Vector2(0, 0)
local mouse_was_down = false

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

local function begin_frame()
    frame_number = frame_number + 1
    clickables = {}
end

-- A screen rectangle that does something when clicked (checked next frame).
local function clickable(left, top, right, bottom, on_click, argument)
    table.insert(clickables, { left, top, right, bottom, on_click, argument })
end

local function hovered(left, top, right, bottom)
    return mouse.x >= left and mouse.x <= right and mouse.y >= top and mouse.y <= bottom
end

local function read_mouse(inputs)
    if not inputs then return end
    if inputs.stick_2 then mouse = inputs.stick_2 end
    local down = inputs.key_12 == true
    if down and not mouse_was_down then
        for index = #clickables, 1, -1 do
            local area = clickables[index]
            if mouse.x >= area[1] and mouse.x <= area[3] and mouse.y >= area[2] and mouse.y <= area[4] then
                area[5](area[6])
                break
            end
        end
    end
    mouse_was_down = down
end

-- =============================================================================
-- What this screen knows (from game.lua's messages)
-- =============================================================================
local state = {
    phase = "lobby", sequence = -1, seats = {}, players = 0, me = 0, settings = {}, clock = 0, final = false,
    cakes_done = 0, cake = "", cake_left = 0, books = {}, my_body = nil,
    my_upgrades = {}, my_pocket = {}, my_butler = true,
}
local show = { description = nil, description_life = 0, time = 0, avatars = {} }
for _, key in ipairs(CATALOG.upgrade_order) do state.my_upgrades[key] = 0 end

local function read_roster(roster)
    state.seats = {}
    for _, entry in ipairs(roster.seats or {}) do
        table.insert(state.seats, { id = tostring(entry.id), short = tostring(entry.s), color = hex_color(tostring(entry.c)),
            icon = tostring(entry.ic or ""), bot = entry.bot == true })
    end
    state.players = #state.seats
    state.me = 0
    for number, seat in ipairs(state.seats) do
        if seat.id == LOCAL_STEAM_ID then state.me = number end
    end
end

-- My own body from the table part (see cake_table.snapshot).
local function read_my_body(part)
    state.my_body = nil
    local numbers = part.seats or {}
    if state.me == 0 or #numbers < state.me * 6 then return end
    local base = (state.me - 1) * 6
    local flags = math.floor(numbers[base + 1] or 0)
    state.my_body = { stuffed = flags % 2 == 1, empty = (flags // 16) % 2 == 1, fullness = numbers[base + 2] or 0,
        stamina = (numbers[base + 3] or 0) / 10, max_stamina = numbers[base + 4] or 12 }
end

function pockets_ALL(sender_id, changed)
    for _, entry in ipairs(changed or {}) do
        if math.floor(entry.seat) == state.me then
            for index, key in ipairs(CATALOG.upgrade_order) do
                state.my_upgrades[key] = math.floor((entry.levels or {})[index] or 0)
            end
            state.my_pocket = {}
            for _, item in ipairs(entry.pocket or {}) do table.insert(state.my_pocket, tostring(item)) end
            state.my_butler = entry.butler == true
        end
    end
end

function state_ALL(sender_id, message)
    local sequence = math.floor(tonumber(message.q) or 0)
    if sequence <= state.sequence and sequence > 1 then return end
    state.sequence = sequence
    state.phase = tostring(message.phase or "lobby")
    if state.phase == "lobby" then
        state.seats, state.players, state.me, state.my_pocket = {}, 0, 0, {}
        for _, key in ipairs(CATALOG.upgrade_order) do state.my_upgrades[key] = 0 end
        return
    end
    if message.roster then read_roster(message.roster) end
    local settings = message.settings or {}
    state.settings = { end_mode = tostring(settings.end_mode or "time"), end_value = math.floor(settings.end_value or 5) }
    state.clock = (tonumber(message.clock) or 0) / 10
    state.final = message.final == true
    state.cakes_done = math.floor(message.cakes_done or 0)
    state.cake = tostring(message.cake or "")
    state.books = {}
    local books = message.books or {}
    for number = 1, #books // 3 do
        state.books[number] = { score = (books[number * 3 - 2] or 0) / 10, crowns = math.floor(books[number * 3 - 1] or 0),
            coins = math.floor(books[number * 3] or 0) }
    end
    if type(message.table) == "table" then
        state.cake_left = math.floor(message.table.left or 0)
        read_my_body(message.table)
    end
end

function _on_loaded_avatar(player_id) show.avatars[tostring(player_id)] = true end

-- =============================================================================
-- Drawing: the top bar
-- =============================================================================
local function draw_clock()
    local settings = state.settings
    local big, small, highlight = "", "", false
    if settings.end_mode == "time" then
        local total = settings.end_value * 60
        big = clock_text(total - state.clock)
        highlight = state.final
        small = state.final and words("clock_final") or words_with("clock_final_at", clock_text(math.max(30, total * 0.12)))
    elseif settings.end_mode == "cakes" then
        big = string.format("%d/%d", math.min(state.cakes_done + 1, settings.end_value), settings.end_value)
        small = words("clock_cakes")
        highlight = state.cake == CATALOG.final_cake.id
    else
        local most = 0
        for _, book in ipairs(state.books) do most = math.max(most, book.crowns) end
        big = string.format("%d/%d", most, settings.end_value)
        small = words("clock_crowns")
    end
    panel("clock", -496, -258, 148, 58, COLORS.surface, 20)
    label("clock_big", big, -496, -268, 140, 34, 28, highlight and COLORS.accent or COLORS.ink, { z = 22 })
    label("clock_small", small, -496, -239, 140, 16, 11, COLORS.soft, { z = 22 })
end

local function draw_avatar(element, seat, x, y, radius, z)
    image(element .. "_ring", "ui/disc", x, y, radius * 2 + 6, radius * 2 + 6, { tint = seat.color, z = z })
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

-- Everyone's standing, best first.
local function draw_standings()
    local order = {}
    for number = 1, state.players do order[number] = number end
    local crowns_first = state.settings.end_mode == "crowns"
    table.sort(order, function(first, second)
        local first_book, second_book = state.books[first], state.books[second]
        if not first_book or not second_book then return first < second end
        if crowns_first and first_book.crowns ~= second_book.crowns then return first_book.crowns > second_book.crowns end
        if first_book.score ~= second_book.score then return first_book.score > second_book.score end
        return first < second
    end)
    local count = #order
    local width = math.min(150, (820 - (count - 1) * 6) / math.max(1, count))
    local total = count * width + (count - 1) * 6
    for rank, number in ipairs(order) do
        local seat, book = state.seats[number], state.books[number]
        if seat and book then
            local x = -total / 2 + width / 2 + (rank - 1) * (width + 6)
            local left = x - width / 2
            local element = "standing" .. rank
            panel(element, x, -258, width, 48, COLORS.surface, 20, number == state.me and COLORS.accent or nil)
            label(element .. "_rank", tostring(rank), left + 12, -258, 14, 20, 13, COLORS.soft, { z = 23 })
            draw_avatar(element .. "_avatar", seat, left + 39, -258, 16, 22)
            local text_room = width - 66
            label(element .. "_name", number == state.me and words("you") or seat.short, left + 60, -266, text_room, 18, 13,
                COLORS.ink, { align = 0, z = 23 })
            if book.crowns > 0 then
                icon(element .. "_crown", "crown", left + 68, -248, 16, { z = 23 })
                label(element .. "_score", book.crowns .. "  " .. grams(book.score), left + 78, -248, text_room - 18, 16, 11,
                    COLORS.soft, { align = 0, z = 23 })
            else
                label(element .. "_score", grams(book.score), left + 60, -248, text_room, 16, 11, COLORS.soft, { align = 0, z = 23 })
            end
        end
    end
end

local function draw_wallet()
    local book = state.books[state.me]
    if not book then return end
    pill("wallet", WALLET_X, WALLET_Y, 150, 42, COLORS.surface, 20)
    icon("wallet_coin", "coin", WALLET_X - 52, WALLET_Y, 32, { z = 22 })
    label("wallet_amount", coins(book.coins), WALLET_X + 12, WALLET_Y, 110, 30, 22, COLORS.ink, { z = 22 })
end

-- The cake on the table, how much is left, and "double points" in the final.
local function draw_cake_name()
    local cake = CAKES[state.cake]
    if not cake or state.phase == "market" then return end
    local name_text = words("cake_" .. cake.id)
    local left_text = words_with("cake_left", state.cake_left)
    local double = cake.final or state.final
    local name_width = text_width(name_text, 16)
    local left_width = text_width(left_text, 12) + 20
    local double_width = double and text_width(words("double_points"), 12) + 22 or 0
    local width = 44 + name_width + 10 + left_width + (double and double_width + 8 or 0) + 12
    local start = -width / 2
    pill("cake_name", 0, -207, width, 36, COLORS.surface, 20)
    icon("cake_name_icon", cake.icon, start + 24, -207, 32, { z = 22 })
    label("cake_name_text", name_text, start + 44, -207, name_width + 20, 24, 16, COLORS.ink, { align = 0, z = 22 })
    local left_x = start + 44 + name_width + 10 + left_width / 2
    pill("cake_left", left_x, -207, left_width, 24, COLORS.surface_dim, 21)
    label("cake_left_text", left_text, left_x, -207, left_width, 20, 12, COLORS.soft, { z = 23 })
    if double then
        local double_x = left_x + left_width / 2 + 8 + double_width / 2
        pill("cake_double", double_x, -207, double_width, 24, COLORS.accent, 21)
        label("cake_double_text", words("double_points"), double_x, -207, double_width, 20, 12, COLORS.white, { z = 23 })
    end
end

-- =============================================================================
-- Drawing: my panels
-- =============================================================================
local function draw_pocket()
    panel("pocket", POCKET_X, POCKET_Y, 236, 128, COLORS.surface, 20)
    label("pocket_title", words("pocket"), POCKET_X - 106, POCKET_Y - 46, 200, 24, 17, COLORS.ink, { align = 0, z = 22 })
    for slot = 1, CATALOG.limits.pocket_size do
        local x, y = POCKET_X - 74 + (slot - 1) * 74, POCKET_Y + 14
        local element = "pocket_slot" .. slot
        local item_id = state.my_pocket[slot]
        if item_id and ITEMS[item_id] then
            local over = hovered(x - 33, y - 33, x + 33, y + 33)
            panel(element, x, y, 66, 66, over and COLORS.line or COLORS.surface_dim, 21, over and COLORS.accent or nil)
            icon(element .. "_icon", ITEMS[item_id].icon, x, y - 8, 32, { z = 23 })
            label(element .. "_name", words("it_" .. item_id), x, y + 20, 64, 24, 9, COLORS.ink, { z = 23 })
            if state.phase == "eating" then
                clickable(x - 33, y - 33, x + 33, y + 33, function(index)
                    run_network_function("-game", "use_HOST", { index })
                end, slot)
            end
        else
            panel(element, x, y, 66, 66, COLORS.surface, 21, COLORS.line)
            label(element .. "_name", words("empty"), x, y, 60, 20, 11, COLORS.soft, { z = 23 })
        end
    end
end

-- The stomach, or the arm while I have no slice and have to push.
local function draw_meter()
    local body = state.my_body
    if not body then return end
    panel("meter", METER_X, METER_Y, 236, 92, COLORS.surface, 20)
    local pushing = state.phase == "eating" and body.empty
    local icon_name, title, status, share, color, alarm
    if pushing then
        icon_name = body.stamina < 1 and "exhale" or "rollpin"
        title = words("arm")
        status = body.stamina < 1 and words("arm_tired") or string.format("%d/%d", math.floor(body.stamina), body.max_stamina)
        share, color, alarm = body.stamina / body.max_stamina, COLORS.arm, body.stamina < 1
    else
        title, share = words("stomach"), body.fullness / 100
        if body.stuffed then icon_name, status, color, alarm = "dizzy", words("stomach_stuffed"), COLORS.bad, true
        elseif body.fullness > 85 then icon_name, status, color, alarm = "persevere", words("stomach_almost"), COLORS.bad, true
        elseif body.fullness > 60 then icon_name, status, color = "smile", words("stomach_filling"), COLORS.gold
        else icon_name, status, color = "yum", words("stomach_hungry"), COLORS.pista end
    end
    if alarm then
        panel("meter_alarm", METER_X, METER_Y, 236, 92, COLORS.clear, 21, faded(COLORS.bad, 0.55 + 0.45 * math.sin(show.time * 6)))
    end
    icon("meter_icon", icon_name, METER_X - 94, METER_Y - 18, 32, { z = 22 })
    label("meter_title", title, METER_X - 72, METER_Y - 29, 178, 20, 15, COLORS.ink, { align = 0, z = 22 })
    label("meter_status", status, METER_X - 72, METER_Y - 9, 178, 18, 11, COLORS.soft, { align = 0, z = 22 })
    panel("meter_bar", METER_X, METER_Y + 20, 208, 18, COLORS.surface_dim, 21)
    local bar_width = 204 * math.max(0, math.min(1, share))
    if bar_width > 1 then image("meter_fill", "ui/px", METER_X - 102 + bar_width / 2, METER_Y + 20, bar_width, 14, { tint = color, z = 23 }) end
    if not pushing then
        -- the line past which my stomach calms down again
        image("meter_mark", "ui/px", METER_X - 102 + 204 * 0.6, METER_Y + 20, 2, 16, { tint = faded(COLORS.soft, 0.5), z = 24 })
    end
end

local function draw_upgrades()
    local x0, y0 = UPGRADES_X, UPGRADES_Y
    panel("upgrades", x0, y0, 236, 336, COLORS.surface, 20)
    label("upgrades_title", words("upgrades"), x0 - 106, y0 - 150, 130, 24, 17, COLORS.ink, { align = 0, z = 22 })
    local clicks_work = state.phase == "eating" or state.phase == "countdown"
    if state.my_upgrades.butler > 0 then
        local switch_text = state.my_butler and words("butler_on") or words("butler_off")
        local width = text_width(switch_text, 11) + 22
        local switch_x = x0 + 106 - width / 2
        pill("butler_switch", switch_x, y0 - 150, width, 24, state.my_butler and COLORS.pista or COLORS.surface_dim, 22)
        label("butler_switch_text", switch_text, switch_x, y0 - 150, width, 20, 11, state.my_butler and COLORS.white or COLORS.ink, { z = 24 })
        if clicks_work then
            clickable(switch_x - width / 2, y0 - 162, switch_x + width / 2, y0 - 138, function()
                run_network_function("-game", "butler_HOST", {})
            end)
        end
    end
    for index, key in ipairs(CATALOG.upgrade_order) do
        local x = x0 - 84 + ((index - 1) % 4) * 56
        local y = y0 - 110 + ((index - 1) // 4) * 48
        local level = state.my_upgrades[key] or 0
        local element = "upgrade" .. index
        local chosen = show.description == key
        panel(element, x, y, 52, 44, level > 0 and COLORS.surface or COLORS.surface_dim, 21,
            chosen and COLORS.accent or (level > 0 and COLORS.line or nil))
        icon(element .. "_icon", ITEMS[key].icon, x, y - 6, 24, { z = 23, tint = level > 0 and COLORS.white or Color(1, 1, 1, 0.3) })
        label(element .. "_level", level > 0 and tostring(level) or "–", x, y + 13, 50, 14, 10, level > 0 and COLORS.ink or COLORS.soft, { z = 23 })
        if clicks_work then
            clickable(x - 26, y - 22, x + 26, y + 22, function(upgrade)
                show.description, show.description_life = upgrade, DESCRIPTION_SECONDS
            end, key)
        end
    end
    -- what the upgrade I clicked does
    local key = show.description
    if key then
        local level = state.my_upgrades[key] or 0
        panel("description", x0, y0 + 214, 236, 92, COLORS.ink, 30)
        icon("description_icon", ITEMS[key].icon, x0 - 96, y0 + 186, 24, { z = 32 })
        label("description_name", words("it_" .. key), x0 - 80, y0 + 186, 150, 20, 13, COLORS.surface, { align = 0, z = 32 })
        label("description_level", level > 0 and words_with("level_n", level) or words("not_bought"), x0 + 106, y0 + 186, 60, 20, 10,
            faded(COLORS.surface, 0.7), { align = 2, z = 32 })
        label("description_text", words("it_" .. key .. "_d"), x0, y0 + 224, 220, 52, 11, faded(COLORS.surface, 0.9), { z = 32 })
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
    read_mouse(inputs)
    show.time = show.time + delta
    if show.description then
        show.description_life = show.description_life - delta
        if show.description_life <= 0 then show.description = nil end
    end
    begin_frame()
    if state.phase ~= "lobby" then
        draw_clock()
        draw_standings()
        draw_cake_name()
        if state.me > 0 then
            draw_wallet()
            draw_pocket()
            draw_meter()
            draw_upgrades()
        end
    end
    finish_frame()
end

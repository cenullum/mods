singleton_name = "market_view"

-- =============================================================================
-- Cake Clicker - the market on every screen (all peers).
--
-- Between two cakes the game freezes: a dark veil over the table, the next
-- cake's name, the market's countdown, and a row of cards. A card shows what
-- it is (kind, picture, name, what it does), my level of it and its price for
-- ME (prices grow with the level I already have). Click a card to buy it.
--
-- A card that just replaced a bought one can already be read but is locked
-- for a few seconds: it is drawn greyed out with a padlock and the seconds
-- left, and the market's countdown waits (with a padlock too) until it opens.
-- Above it, for a moment: who bought the card that was there before.
--
-- Card positions come from catalog.json "market_layout", the same numbers the
-- bots use to move their cursors to the cards.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local LAYOUT = CATALOG.market_layout
local CARD_WIDTH, CARD_HEIGHT = LAYOUT.card_width, LAYOUT.card_height
local ITEMS = {}
for _, item in ipairs(CATALOG.items) do ITEMS[item.id] = item end
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
    pista = hex_color("#5e8c27"), pista_light = hex_color("#6fa52f"), gold = hex_color("#b98309"),
    locked = hex_color("#cfc8bd"), locked_text = hex_color("#9a8f84"), veil = Color(0.18, 0.1, 0.07, 0.62),
    white = Color(1, 1, 1, 1),
}
local KIND_COLORS = { tool = hex_color("#2f6fd6"), power = hex_color("#2d8a3e"), auto = hex_color("#8e5bd8"), use = hex_color("#d06d0a") }

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
    phase = "lobby", sequence = -1, seats = {}, me = 0, unit = 50, cards = {}, countdown = 0, next_cake = "",
    my_coins = 0, my_upgrades = {}, my_pocket = {},
}
for _, key in ipairs(CATALOG.upgrade_order) do state.my_upgrades[key] = 0 end
local received_at = 0       -- the lock timers count down locally between two messages
local clock = 0

local function sound(path, volume)
    set_audio({ stream_path = path, bus = "Effect", volume = volume or 0, random_pitch = 0.08, is_2d = false })
end

local function card_center(slot, count)
    local total = count * CARD_WIDTH + (count - 1) * LAYOUT.gap
    return -total / 2 + CARD_WIDTH / 2 + (slot - 1) * (CARD_WIDTH + LAYOUT.gap), LAYOUT.y
end

local function price_for_me(item)
    local level = item.kind == "use" and 0 or (state.my_upgrades[item.id] or 0)
    return math.max(1, math.floor(item.price * state.unit * (item.growth or 1) ^ level + 0.5))
end

function pockets_ALL(sender_id, changed)
    for _, entry in ipairs(changed or {}) do
        if math.floor(entry.seat) == state.me then
            for index, key in ipairs(CATALOG.upgrade_order) do
                state.my_upgrades[key] = math.floor((entry.levels or {})[index] or 0)
            end
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
    if message.roster then
        state.seats, state.me = {}, 0
        for number, entry in ipairs(message.roster.seats or {}) do
            state.seats[number] = { short = tostring(entry.s) }
            if tostring(entry.id) == LOCAL_STEAM_ID then state.me = number end
        end
    end
    if state.phase == "lobby" then
        state.me, state.cards = 0, {}
        for _, key in ipairs(CATALOG.upgrade_order) do state.my_upgrades[key] = 0 end
        state.my_pocket = {}
        return
    end
    state.unit = tonumber(message.unit) or state.unit
    local books = message.books or {}
    state.my_coins = state.me > 0 and math.floor(books[state.me * 3] or 0) or 0
    local market = message.market
    if type(market) == "table" then
        state.cards = {}
        for slot, card in ipairs(market.cards or {}) do
            state.cards[slot] = { item = tostring(card[1]), lock = (card[2] or 0) / 10, buyer = math.floor(card[3] or 0),
                bought = tostring(card[4] or "") }
        end
        state.countdown = (market.countdown or 0) / 10
        state.next_cake = tostring(market.next_cake or "")
        received_at = clock
    end
    for _, event in ipairs(message.events or {}) do
        if event.k == "buy" then
            sound("buy", math.floor(tonumber(event.p) or 0) == state.me and 0 or -10)
        elseif event.k == "unlocked" then
            sound("flip", -4)
        end
    end
end

-- =============================================================================
-- Drawing
-- =============================================================================
local function draw_header(any_locked)
    local next_cake = CAKES[state.next_cake]
    if next_cake then
        local heading = words_with("next_cake", words("cake_" .. next_cake.id))
        local width = text_width(heading, 16) + 70
        pill("market_next", 0, -196, width, 40, COLORS.surface, 110)
        icon("market_next_icon", next_cake.icon, -width / 2 + 28, -196, 32, { z = 112 })
        label("market_next_text", heading, 16, -196, width - 40, 30, 16, COLORS.ink, { z = 112 })
    end
    -- the market's countdown; it waits (padlock) while a new card is locked
    local seconds_left = math.max(0, state.countdown - (any_locked and 0 or (clock - received_at)))
    image("market_clock", "ui/disc", 0, -132, 64, 64, { tint = any_locked and COLORS.surface_dim or COLORS.surface, z = 110 })
    image("market_clock_ring", "ui/ring", 0, -132, 64, 64, { tint = any_locked and COLORS.soft or COLORS.accent, z = 111 })
    label("market_clock_text", tostring(math.ceil(seconds_left)), 0, -133, 60, 40, 28, any_locked and COLORS.soft or COLORS.ink, { z = 112 })
    if any_locked then icon("market_clock_lock", "lock", 26, -110, 20, { z = 113 }) end
end

-- The bottom bar of a card: the price and "Buy", or why I cannot.
local function draw_buy_bar(element, card, item, x, bar_y, over, lock_left)
    local level = item.kind ~= "use" and (state.my_upgrades[item.id] or 0) or 0
    local price = price_for_me(item)
    local reason = nil
    if item.kind == "use" and #state.my_pocket >= CATALOG.limits.pocket_size then reason = words("pocket_full")
    elseif item.max and level >= item.max then reason = words("maxed") end
    local affordable = not reason and lock_left <= 0 and state.my_coins >= price and state.me > 0
    local bar_color = affordable and (over and COLORS.pista_light or COLORS.pista) or (lock_left > 0 and COLORS.locked or COLORS.surface_dim)
    panel(element .. "_bar", x, bar_y, 148, 32, bar_color, 121)
    if lock_left > 0 then
        icon(element .. "_bar_lock", "lock", x - 18, bar_y, 20, { z = 123 })
        label(element .. "_bar_text", tostring(math.ceil(lock_left)), x + 12, bar_y, 40, 24, 14, COLORS.ink, { z = 123 })
        return
    end
    if reason then
        label(element .. "_bar_text", reason, x, bar_y, 140, 24, 12, COLORS.soft, { z = 123 })
        return
    end
    if not affordable and state.my_coins > 0 then
        -- how close I am to affording it
        local filled = 144 * math.max(0, math.min(1, state.my_coins / price))
        image(element .. "_bar_progress", "ui/px", x - 72 + filled / 2, bar_y, filled, 26, { tint = faded(COLORS.pista, 0.25), z = 122 })
    end
    label(element .. "_bar_text", affordable and words("buy") or words("save_up"), x - 66, bar_y, 70, 24, 12,
        affordable and COLORS.white or COLORS.soft, { align = 0, z = 123 })
    icon(element .. "_bar_coin", "coin", x + 18, bar_y, 20, { z = 123 })
    label(element .. "_bar_price", coins(price), x + 70, bar_y, 60, 24, 13, affordable and COLORS.white or COLORS.ink, { align = 2, z = 123 })
end

local function draw_card(slot, card, count)
    local item = ITEMS[card.item]
    if not item then return end
    local x, y = card_center(slot, count)
    local left, top = x - CARD_WIDTH / 2, y - CARD_HEIGHT / 2
    local element = "card" .. slot
    local lock_left = math.max(0, card.lock - (clock - received_at))
    local locked = lock_left > 0
    local over = not locked and hovered(left, top, left + CARD_WIDTH, top + CARD_HEIGHT)
    local kind_color = locked and COLORS.locked_text or KIND_COLORS[item.kind]
    local text_color = locked and COLORS.locked_text or COLORS.ink
    local outline = locked and COLORS.locked or (item.rarity == 2 and COLORS.gold or (over and COLORS.accent or nil))
    panel(element, x, y, CARD_WIDTH, CARD_HEIGHT, locked and COLORS.surface_dim or COLORS.surface, 120, outline)
    label(element .. "_kind", words("kind_" .. item.kind), left + 12, top + 16, 140, 16, 11, kind_color, { align = 0, z = 122 })
    for star = 1, math.floor(item.rarity) do
        icon(element .. "_star" .. star, "sparkle", left + CARD_WIDTH - 4 - star * 18, top + 16, 16,
            { z = 122, tint = locked and Color(1, 1, 1, 0.4) or COLORS.white })
    end
    image(element .. "_icon_disc", "ui/disc", x, top + 62, 66, 66, { tint = faded(kind_color, 0.14), z = 121 })
    icon(element .. "_icon", item.icon, x, top + 62, 48, { z = 122, tint = locked and Color(0.75, 0.75, 0.75, 0.55) or COLORS.white })
    if locked then
        -- the padlock over the picture, and the seconds until it opens
        image(element .. "_lock_disc", "ui/disc", x + 30, top + 84, 34, 34, { tint = COLORS.surface, z = 123 })
        icon(element .. "_lock", "lock", x + 30, top + 84, 24, { z = 124 })
    end
    label(element .. "_name", words("it_" .. item.id), x, top + 112, 156, 22, 15, text_color, { z = 122 })
    local level = item.kind ~= "use" and (state.my_upgrades[item.id] or 0) or -1
    if level >= 0 then
        local level_text = level == 0 and words("card_new") or words_with("card_level", level, level + 1)
        label(element .. "_level", level_text, x, top + 132, 156, 16, 11, locked and COLORS.locked_text or COLORS.soft, { z = 122 })
    end
    label(element .. "_text", words("it_" .. item.id .. "_d"), x, top + 168, 150, 56, 11, locked and COLORS.locked_text or COLORS.soft, { z = 122 })
    draw_buy_bar(element, card, item, x, top + CARD_HEIGHT - 24, over, lock_left)
    -- who bought the card that was here a moment ago
    if card.buyer > 0 and card.bought ~= "" then
        local note
        if card.buyer == state.me then note = words_with("card_yours", words("it_" .. card.bought))
        else note = words_with("card_bought_by", state.seats[card.buyer] and state.seats[card.buyer].short or "?", words("it_" .. card.bought)) end
        local note_width = math.min(CARD_WIDTH + 40, text_width(note, 12) + 24)
        pill(element .. "_note", x, top - 18, note_width, 26, COLORS.ink, 125)
        label(element .. "_note_text", note, x, top - 18, note_width, 24, 12, COLORS.white, { z = 127 })
    end
    if not locked and state.me > 0 then
        clickable(left, top, left + CARD_WIDTH, top + CARD_HEIGHT, function(choice)
            run_network_function("-game", "buy_HOST", { choice[1], choice[2] })
        end, { slot, card.item })
    end
end

local function draw_market()
    image("market_veil", "ui/px", 0, 1400, 6000, 3270, { tint = COLORS.veil, z = 100 })
    local any_locked = false
    for _, card in ipairs(state.cards) do
        if card.lock - (clock - received_at) > 0 then any_locked = true end
    end
    draw_header(any_locked)
    for slot, card in ipairs(state.cards) do draw_card(slot, card, #state.cards) end
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
    clock = clock + delta
    read_mouse(inputs)
    begin_frame()
    if state.phase == "market" then draw_market() end
    finish_frame()
end

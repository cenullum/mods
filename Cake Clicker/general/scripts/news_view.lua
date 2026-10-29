singleton_name = "news_view"

-- =============================================================================
-- Cake Clicker - what just happened, on every screen (all peers).
--
-- Turns the events in game.lua's state message into what a player notices: a
-- banner ("Chocolate Cake is here!", "Osman took your slice!"), the sound that
-- goes with it, a "+grams" floating up from my seat whenever my score grows,
-- and one soft click for every bite I take automatically.
--
-- The banner sits over the cake while there is one and under the cards while
-- the market is open. My seat is always at the bottom of the table, so the
-- floats start from the same place on every screen.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local TABLE = CATALOG.table_layout
local CENTER_X, CENTER_Y = TABLE.center_x, TABLE.center_y
local SNAPSHOT_EVERY = CATALOG.timing.snapshot

local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end

local function hex_color(hex, alpha)
    return Color(tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255, alpha or 1)
end
local function faded(color, alpha) return Color(color.r, color.g, color.b, alpha) end

local COLORS = {
    surface = hex_color("#fffdf9"), ink = hex_color("#2e1a12"), accent = hex_color("#e23d6d"),
    gold = hex_color("#b98309"), good = hex_color("#2d8a3e"), bad = hex_color("#cf3434"),
    white = Color(1, 1, 1, 1),
}

local BANNER_COLORS = { info = COLORS.ink, bad = COLORS.bad, gold = COLORS.gold, go = COLORS.good, hot = COLORS.accent }

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

local function coins(amount) return grouped(math.max(0, amount)) end

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
local state = { phase = "lobby", sequence = -1, seats = {}, players = 0, me = 0, rotation = 0, scores = {}, my_auto_bites = nil }
local show = { banner = nil, floats = {}, my_score = nil, auto_bites_seen = nil, clicks_due = 0, click_gap = 0, click_timer = 0 }

local function sound(path, volume, pitch_spread)
    set_audio({ stream_path = path, bus = "Effect", volume = volume or 0, random_pitch = pitch_spread or 0, is_2d = false })
end

-- =============================================================================
-- Banners and floats
-- =============================================================================

local function show_banner(title, subtitle, kind)
    show.banner = { title = title, subtitle = subtitle or "", kind = kind or "info", age = 0 }
end

local function float_grams(amount, special_text)
    local x, y = CENTER_X, CENTER_Y + TABLE.cake * 0.62
    local last = show.floats[#show.floats]
    if not special_text and last and not last.special and last.age < 0.45 then
        last.amount = last.amount + amount
        last.text = "+" .. grams(last.amount)
        return
    end
    table.insert(show.floats, { amount = amount, x = x + math.random(-20, 20), y = y, age = 0, special = special_text ~= nil,
        text = special_text or ("+" .. grams(amount)), color = special_text and COLORS.gold or COLORS.accent,
        size = special_text and 20 or 15 })
    if #show.floats > 6 then table.remove(show.floats, 1) end
end

-- =============================================================================
-- Receiving the state
-- =============================================================================

local function read_roster(roster)
    state.seats = {}
    for _, entry in ipairs(roster.seats or {}) do
        table.insert(state.seats, { id = tostring(entry.id), short = tostring(entry.s) })
    end
    state.players = #state.seats
    local me = 0
    for number, seat in ipairs(state.seats) do
        if seat.id == LOCAL_STEAM_ID then me = number end
    end
    if me ~= state.me then show.my_score, show.auto_bites_seen = nil, nil end
    state.me = me
end

local function front_number(seat_number) return (2 * (seat_number - 1) - state.rotation) % math.max(1, state.players * 2) end

local function seat_name(seat_number)
    local seat = state.seats[seat_number]
    return seat and seat.short or "?"
end

local function after_update()
    if state.me == 0 then return end
    local score = state.scores[state.me]
    if score and show.my_score and score > show.my_score + 0.001 and state.phase == "eating" then
        float_grams(score - show.my_score)
    end
    show.my_score = score
    local auto_bites = state.my_auto_bites
    if auto_bites and show.auto_bites_seen and auto_bites > show.auto_bites_seen and state.phase == "eating" then
        local count = math.min(auto_bites - show.auto_bites_seen, 6)
        show.clicks_due = show.clicks_due + count
        show.click_gap = SNAPSHOT_EVERY / count
    end
    show.auto_bites_seen = auto_bites
end

-- What one event means for this screen: a banner and a sound.

local function handle_event(event)
    local kind = tostring(event.k or "")
    local seat_number = math.floor(tonumber(event.p) or 0)
    local mine = seat_number == state.me and state.me > 0
    local target = math.floor(tonumber(event.tg) or 0)
    if kind == "cake" then
        local cake = CAKES[tostring(event.c)]
        if cake then show_banner(words_with("arrived", words("cake_" .. cake.id)), "", cake.final and "hot" or "go") end
        sound("cake")
    elseif kind == "crown" then
        local amount = words_with("ate_amount", grams(tonumber(event.g) or 0))
        if mine then show_banner(words("crown_you"), amount, "gold") sound("crown")
        else show_banner(words_with("crown_other", seat_name(seat_number)), amount, "gold") sound("cake") end
    elseif kind == "final" then
        show_banner(words("final_started"), words("final_sub"), "hot")
        sound("final")
    elseif kind == "cherry" then
        local on_mine = state.me > 0 and front_number(state.me) == math.floor(tonumber(event.s) or -1)
        if on_mine then show_banner(words("cherry_yours"), words("cherry_yours_sub"), "gold")
        else show_banner(words("cherry_spawn"), words("cherry_spawn_sub"), "gold") end
        sound("cherry")
    elseif kind == "cherry_got" then
        if mine then show_banner(words("cherry_got_you"), words_with("coins_plus", coins(tonumber(event.c) or 0)), "gold") sound("cherry")
        else show_banner(words_with("cherry_got_other", seat_name(seat_number)), "", "gold") end
    elseif kind == "waiter_turn" then
        show_banner(words("waiter_turned"), words("waiter_turned_sub"), "info")
    elseif kind == "waiter_crumbs" then
        show_banner(words("waiter_crumbs"), "", "info")
    elseif kind == "robbed" and math.floor(tonumber(event.v) or 0) == state.me then
        local by = math.floor(tonumber(event.by) or 0)
        show_banner(by > 0 and words_with("robbed_by", seat_name(by)) or words("robbed"),
            event.e and words("robbed_sub_smaller") or words("robbed_sub_turn_back"), "bad")
        sound("bad")
    elseif kind == "gift" and math.floor(tonumber(event.v) or 0) == state.me then
        show_banner(words("gift"), words("gift_sub"), "go")
    elseif kind == "rot" then
        sound("rot")
    elseif kind == "stuffed" and mine then
        sound("bad")
    elseif kind == "crit" and mine then
        float_grams(0, words("crit"))
        sound("crit")
    elseif kind == "butler" and mine then
        show_banner(words_with("butler_bought", words("it_" .. tostring(event.id))), "", "go")
    elseif kind == "market" then
        sound("cake")
    elseif kind == "tick" then
        sound("tick")
    elseif kind == "start" then
        show_banner(words("go"), "", "go")
        sound("cake")
    elseif kind == "useless" and mine then
        show_banner(words("item_useless"), "", "bad")
        sound("bad")
    elseif kind == "over" then
        sound("crown")
    elseif kind == "item" then
        local item = tostring(event.id)
        local aimed_at_me = target == state.me and state.me > 0
        if item == "table_lock" then
            if mine then show_banner(words("use_lock_you"), words("use_lock_sub"), "info")
            else show_banner(words_with("use_lock_other", seat_name(seat_number)), words("use_lock_sub"), "info") end
        elseif aimed_at_me then
            local titles = { spoon_throw = "throw_hit_you", hot_pepper = "pepper_hit_you", salt_shaker = "salt_hit_you", raccoon_fork = "raccoon_hit_you" }
            local subtitles = { spoon_throw = "throw_hit_you_sub", hot_pepper = "pepper_hit_you_sub", salt_shaker = "salt_hit_you_sub" }
            if titles[item] then
                show_banner(words_with(titles[item], seat_name(seat_number)), subtitles[item] and words(subtitles[item]) or "", "bad")
                sound("hit")
            end
        elseif mine then
            local own = { coffee = { "use_coffee", "use_coffee_sub" }, ayran = { "use_ayran", "use_ayran_sub" },
                turnip_juice = { "use_turnip" }, honey_sauce = { "use_honey", "use_honey_sub" }, quick_spin = { "use_spin" } }
            local aimed = { spoon_throw = "throw_hit_other", hot_pepper = "pepper_hit_other", salt_shaker = "salt_hit_other" }
            if own[item] then show_banner(words(own[item][1]), own[item][2] and words(own[item][2]) or "", "go")
            elseif aimed[item] then show_banner(words_with(aimed[item], seat_name(target)), "", "go")
            elseif item == "raccoon_fork" then show_banner(words_with("raccoon_you", grams(tonumber(event.g) or 0)), "", "go") end
            sound("buy")
        end
    end
end

function state_ALL(sender_id, message)
    local sequence = math.floor(tonumber(message.q) or 0)
    if sequence <= state.sequence and sequence > 1 then return end
    state.sequence = sequence
    state.phase = tostring(message.phase or "lobby")
    if state.phase == "lobby" then
        state.seats, state.players, state.me = {}, 0, 0
        show.my_score, show.auto_bites_seen = nil, nil
    else
        if message.roster then read_roster(message.roster) end
        local table_part = type(message.table) == "table" and message.table or {}
        state.rotation = math.floor(table_part.rotation or 0)
        local body = table_part.seats or {}
        state.my_auto_bites = state.me > 0 and math.floor(body[(state.me - 1) * 6 + 6] or 0) or nil
        state.scores = {}
        local books = message.books or {}
        for number = 1, #books // 3 do state.scores[number] = (books[number * 3 - 2] or 0) / 10 end
        after_update()
    end
    for _, event in ipairs(message.events or {}) do handle_event(event) end
end

-- =============================================================================
-- Animation
-- =============================================================================

local function animate(delta)
    if show.banner then
        show.banner.age = show.banner.age + delta
        if show.banner.age > 2.4 then show.banner = nil end
    end
    local kept = {}
    for _, float in ipairs(show.floats) do
        float.age = float.age + delta
        float.y = float.y - 60 * delta
        if float.age < 0.9 then table.insert(kept, float) end
    end
    show.floats = kept
    -- my automatic bites: one soft click each, spread over the snapshot interval
    if show.clicks_due > 0 then
        show.click_timer = show.click_timer - delta
        if show.click_timer <= 0 then
            show.clicks_due = show.clicks_due - 1
            show.click_timer = show.click_gap
            sound("click", -6, 0.15)
        end
    end
end

-- =============================================================================
-- Drawing
-- =============================================================================

local function draw_banner()
    local banner = show.banner
    if not banner then return end
    local alpha, rise = 1, 0
    if banner.age < 0.2 then
        alpha = banner.age / 0.2
        rise = (1 - alpha) * 12
    elseif banner.age > 2.0 then
        alpha = math.max(0, (2.4 - banner.age) / 0.4)
        rise = -(1 - alpha) * 18
    end
    local background = BANNER_COLORS[banner.kind] or COLORS.ink
    local foreground = banner.kind == "info" and COLORS.surface or COLORS.white
    local width = math.max(text_width(banner.title, 18), text_width(banner.subtitle, 12)) + 40
    local height = banner.subtitle ~= "" and 52 or 36
    local in_market = state.phase == "market"
    local y = (in_market and 214 or -40) + rise
    local z = in_market and 140 or 70
    panel("banner", 0, y, width, height, faded(background, alpha), z)
    if banner.subtitle ~= "" then
        label("banner_title", banner.title, 0, y - 9, width, 24, 18, faded(foreground, alpha), { z = z + 2 })
        label("banner_text", banner.subtitle, 0, y + 13, width, 18, 12, faded(foreground, alpha * 0.88), { z = z + 2 })
    else
        label("banner_title", banner.title, 0, y, width, 24, 18, faded(foreground, alpha), { z = z + 2 })
    end
end

local function draw_floats()
    for index, float in ipairs(show.floats) do
        local alpha = math.max(0, math.min(1, (0.9 - float.age) * 2))
        label("float" .. index, float.text, float.x, float.y, 160, 28, float.size, faded(float.color, alpha),
            { z = 80, outline = 4, outline_color = faded(COLORS.surface, alpha) })
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
        draw_banner()
        draw_floats()
    end
    finish_frame()
end

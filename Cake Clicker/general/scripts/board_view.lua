singleton_name = "board_view"

-- =============================================================================
-- Cake Clicker - the settings board before a game and the results after it
-- (all peers).
--
-- The settings board is the same for everyone (world space, so everyone's
-- mouse cursor points at the same buttons). Only the host - or anyone, when no
-- admin is in the room - changes a setting or starts the game; everyone else
-- can still click an option to read what it means. The description under the
-- options always explains the last thing this player clicked.
--
-- The results board lists every seat: cake eaten, crowns, turns of the plate,
-- money spent and upgrade levels; the host can send the room back to the
-- settings board for another game.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local MAX_SEATS, MAX_BOTS = CATALOG.limits.max_seats, CATALOG.limits.max_bots
local LABEL_X, OPTIONS_X = -340, -120

local function hex_color(hex, alpha)
    return Color(tonumber(hex:sub(2, 3), 16) / 255, tonumber(hex:sub(4, 5), 16) / 255,
        tonumber(hex:sub(6, 7), 16) / 255, alpha or 1)
end
local function faded(color, alpha) return Color(color.r, color.g, color.b, alpha) end
local COLORS = {
    surface = hex_color("#fffdf9"), surface_dim = hex_color("#f4f0e7"), ink = hex_color("#2e1a12"),
    soft = hex_color("#6f5547"), line = hex_color("#ddd5c6"), accent = hex_color("#e23d6d"),
    accent_dark = hex_color("#c92e5c"), veil = Color(0.18, 0.1, 0.07, 0.62), white = Color(1, 1, 1, 1),
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
    phase = "lobby", sequence = -1,
    settings = { bots = 3, difficulty = "normal", end_mode = "time", end_value = 5 }, players = {}, admin_in_room = true,
    seats = {}, me = 0, results = nil,
}
local show = { explained = nil, avatars = {} }      -- the option this player clicked last: { key, value }

function state_ALL(sender_id, message)
    local sequence = math.floor(tonumber(message.q) or 0)
    if sequence <= state.sequence and sequence > 1 then return end
    state.sequence = sequence
    state.phase = tostring(message.phase or "lobby")
    if type(message.lobby) == "table" then
        local settings = message.lobby.settings or {}
        state.settings = { bots = math.floor(settings.bots or 3), difficulty = tostring(settings.difficulty or "normal"),
            end_mode = tostring(settings.end_mode or "time"), end_value = math.floor(settings.end_value or 5) }
        state.players = {}
        for _, player in ipairs(message.lobby.players or {}) do
            table.insert(state.players, { id = tostring(player.id), name = tostring(player.n) })
        end
        state.admin_in_room = message.lobby.admin == true
        state.results = nil
    end
    if message.roster then
        state.seats, state.me = {}, 0
        for number, entry in ipairs(message.roster.seats or {}) do
            state.seats[number] = { id = tostring(entry.id), name = tostring(entry.n), color = hex_color(tostring(entry.c)),
                icon = tostring(entry.ic or ""), bot = entry.bot == true }
            if state.seats[number].id == LOCAL_STEAM_ID then state.me = number end
        end
    end
    if message.settings then state.settings.end_mode = tostring(message.settings.end_mode or state.settings.end_mode) end
    if type(message.results) == "table" then state.results = message.results end
end

function _on_loaded_avatar(player_id) show.avatars[tostring(player_id)] = true end

local function i_may_manage()
    return is_admin(LOCAL_STEAM_ID) or not state.admin_in_room
end

-- The two big buttons (globals, so a test or another script can press them too).
function start_click() run_network_function("-game", "start_HOST", {}) end
function again_click() run_network_function("-game", "again_HOST", {}) end

-- =============================================================================
-- The settings board
-- =============================================================================
-- One row: the question on the left, the options as buttons on the right.
local function option_row(row_name, y, question, options, current, setting_key, button_width)
    label("row_" .. row_name, words(question), LABEL_X, y, 205, 40, 15, COLORS.ink, { align = 0, z = 22 })
    for index, option in ipairs(options) do
        local x = OPTIONS_X + button_width / 2 + (index - 1) * (button_width + 8)
        local chosen = tostring(option.value) == tostring(current)
        local over = hovered(x - button_width / 2, y - 20, x + button_width / 2, y + 20)
        local element = "option_" .. row_name .. index
        panel(element, x, y, button_width, 40, chosen and COLORS.surface or (over and COLORS.line or COLORS.surface_dim), 21,
            chosen and COLORS.accent or nil)
        label(element .. "_text", option.text, x, y, button_width - 8, 36, option.size or 14, chosen and COLORS.ink or COLORS.soft, { z = 23 })
        clickable(x - button_width / 2, y - 20, x + button_width / 2, y + 20, function(value)
            show.explained = { key = setting_key, value = value }
            if i_may_manage() then run_network_function("-game", "settings_HOST", { setting_key, value }) end
        end, option.value)
    end
end

-- The text under the options: what the option this player clicked last means.
local function explanation(humans, fewest_bots)
    local settings = state.settings
    local clicked = show.explained
    local function pace_note(mode, value)
        local pace = CATALOG.end_values[mode].pace[string.format("%d", value)] or 1
        if pace <= 1 then return "" end
        return " " .. words_with("desc_pace", (string.format("%.1f", pace):gsub("%.", words("num_dec"))))
    end
    if clicked and clicked.key == "bots" then
        local bots = math.max(fewest_bots, math.floor(tonumber(clicked.value) or 0))
        return words_with("desc_bots", bots, (humans + bots) * 2)
    elseif clicked and clicked.key == "difficulty" then
        return words("desc_diff_" .. tostring(clicked.value))
    elseif clicked and clicked.key == "end_value" then
        return words("desc_mode_" .. settings.end_mode) .. pace_note(settings.end_mode, math.floor(tonumber(clicked.value) or 0))
    end
    local mode = (clicked and clicked.key == "end_mode") and tostring(clicked.value) or settings.end_mode
    local text = words("desc_mode_" .. mode)
    if mode == settings.end_mode then text = text .. pace_note(mode, settings.end_value) end
    return text
end

local function draw_settings_board()
    local settings = state.settings
    local humans = math.max(1, #state.players)
    local fewest_bots = humans == 1 and 1 or 0
    local most_bots = math.min(MAX_BOTS, MAX_SEATS - humans)
    local bots = math.max(fewest_bots, math.min(settings.bots, most_bots))
    icon("title_icon", "birthday", -150, -262, 64, { z = 22 })
    label("title", words("title"), 30, -262, 320, 60, 40, COLORS.accent, { z = 22, outline = 5, outline_color = COLORS.surface })
    panel("board", 0, 40, 720, 500, COLORS.surface, 20)
    local bot_options = {}
    for count = fewest_bots, most_bots do table.insert(bot_options, { value = count, text = tostring(count) }) end
    option_row("bots", -165, "set_bots", bot_options, bots, "bots", 54)
    local difficulty_options = {}
    for _, difficulty in ipairs(CATALOG.difficulties) do
        table.insert(difficulty_options, { value = difficulty, text = words("diff_" .. difficulty) })
    end
    option_row("difficulty", -110, "set_diff", difficulty_options, settings.difficulty, "difficulty", 140)
    local mode_options = {}
    for _, mode in ipairs(CATALOG.end_modes) do
        table.insert(mode_options, { value = mode, text = words("mode_" .. mode), size = 12 })
    end
    option_row("mode", -55, "set_mode", mode_options, settings.end_mode, "end_mode", 150)
    local value_options = {}
    for _, option in ipairs(CATALOG.end_values[settings.end_mode].options) do
        local value = math.floor(option)      -- JSON numbers arrive as floats ("5.0")
        local text = settings.end_mode == "time" and words_with("minutes_n", value) or tostring(value)
        table.insert(value_options, { value = value, text = text })
    end
    option_row("value", 0, "set_val_" .. settings.end_mode, value_options, settings.end_value, "end_value", 90)
    panel("explanation", 0, 72, 660, 70, COLORS.surface_dim, 21)
    label("explanation_text", explanation(humans, fewest_bots), 0, 72, 640, 64, 13, COLORS.soft, { z = 23 })
    local names = {}
    for _, player in ipairs(state.players) do table.insert(names, player.name) end
    label("who_sits", words_with("table_line", table.concat(names, ", "), bots, (humans + bots) * 2), 0, 136, 660, 40, 13,
        COLORS.ink, { z = 22 })
    if i_may_manage() then
        local over = hovered(-140, 194, 140, 246)
        pill("start", 0, 220, 280, 52, over and COLORS.accent_dark or COLORS.accent, 22)
        label("start_text", words("start"), 0, 220, 260, 40, 20, COLORS.white, { z = 24 })
        clickable(-140, 194, 140, 246, start_click)
    else
        pill("start", 0, 220, 380, 52, COLORS.surface_dim, 22)
        label("start_text", words("waiting_host"), 0, 220, 360, 40, 15, COLORS.soft, { z = 24 })
    end
end

-- =============================================================================
-- The results board
-- =============================================================================
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
        icon(element .. "_icon", seat.icon ~= "" and seat.icon or "yum", x, y, 24, { z = z + 2 })
    end
end

local COLUMNS = { { -370, "#", 0 }, { -330, "col_player", 0 }, { -40, "col_eaten", 2 }, { 50, "col_crowns", 2 },
    { 150, "col_turns", 2 }, { 260, "col_spent", 2 }, { 370, "col_upgrades", 2 } }

local function draw_results_board()
    local results = state.results
    if not results then return end
    image("results_veil", "ui/px", 0, 1400, 6000, 3270, { tint = COLORS.veil, z = 100 })
    local rows = results.rows or {}
    local winner = rows[1] and math.floor(rows[1][1] or 0) or 0
    local my_rank, my_score = 0, 0
    for rank, row in ipairs(rows) do
        if math.floor(row[1] or 0) == state.me then my_rank, my_score = rank, (row[2] or 0) / 10 end
    end
    local cakes_eaten, game_time = math.floor(results.cakes or 0), clock_text(results.time or 0)
    panel("results", 0, 30, 820, 520, COLORS.surface, 110)
    icon("results_icon", winner == state.me and "trophy" or "slice", 0, -190, 48, { z = 112 })
    local winner_seat = state.seats[winner]
    local title = winner == state.me and words("winner_you") or words_with("winner_other", winner_seat and winner_seat.name or "?")
    label("results_title", title, 0, -146, 760, 40, 26, COLORS.accent, { z = 112 })
    local summary = my_rank > 0 and words_with("over_sub", my_rank, grams(my_score), cakes_eaten, game_time)
        or words_with("over_sub_watch", cakes_eaten, game_time)
    if state.settings.end_mode == "crowns" then summary = summary .. " " .. words("over_by_crowns") end
    label("results_summary", summary, 0, -114, 760, 24, 13, COLORS.soft, { z = 112 })
    for index, column in ipairs(COLUMNS) do
        local heading = column[2] == "#" and "#" or words(column[2])
        label("results_heading" .. index, heading, column[1], -80, 120, 20, 12, COLORS.soft, { align = column[3], z = 112 })
    end
    image("results_rule", "ui/px", 0, -66, 760, 1, { tint = COLORS.line, z = 112 })
    for rank, row in ipairs(rows) do
        local seat_number = math.floor(row[1] or 0)
        local seat = state.seats[seat_number]
        local y = -44 + (rank - 1) * 36
        local element = "results_row" .. rank
        if seat_number == state.me then image(element .. "_mine", "ui/px", 0, y, 770, 34, { tint = faded(COLORS.accent, 0.09), z = 111 }) end
        label(element .. "_rank", tostring(rank), -370, y, 30, 24, 14, COLORS.ink, { align = 0, z = 112 })
        if seat then draw_avatar(element .. "_avatar", seat, -316, y, 13, 112) end
        label(element .. "_name", seat and seat.name or "?", -296, y, 230, 24, 14, COLORS.ink, { align = 0, z = 112 })
        local cells = { grams((row[2] or 0) / 10), tostring(math.floor(row[3] or 0)), tostring(math.floor(row[4] or 0)),
            coins(row[5] or 0), tostring(math.floor(row[6] or 0)) }
        for cell, text in ipairs(cells) do
            local column = COLUMNS[cell + 2]
            label(element .. "_cell" .. cell, text, column[1], y, 110, 24, 14, COLORS.ink, { align = 2, z = 112 })
        end
    end
    if i_may_manage() then
        local over = hovered(-130, 224, 130, 272)
        pill("again", 0, 248, 260, 48, over and COLORS.accent_dark or COLORS.accent, 112)
        label("again_text", words("play_again"), 0, 248, 240, 36, 18, COLORS.white, { z = 114 })
        clickable(-130, 224, 130, 272, again_click)
    else
        pill("again", 0, 248, 380, 48, COLORS.surface_dim, 112)
        label("again_text", words("waiting_host"), 0, 248, 360, 36, 15, COLORS.soft, { z = 114 })
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
    begin_frame()
    if state.phase == "lobby" then draw_settings_board()
    elseif state.phase == "over" then draw_results_board() end
    finish_frame()
end

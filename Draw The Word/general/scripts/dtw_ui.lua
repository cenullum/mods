network_mode = 1
singleton_name = "dtw_ui"

-- =============================================================================
-- Draw The Word - all client-side UI. Every function here runs locally; the
-- manager drives them through run_function / run_network_function. Nothing here
-- is authoritative: it only renders state the host already decided.
-- =============================================================================

local MANAGER = "-dtw_manager"

-- Panel handles
local HUD = "dtw_hud"
local SCORE = "dtw_score"
local CHOICE = "dtw_choice"
local REPORT = "dtw_report"
local PODIUM = "dtw_podium"
local paint_panel = ""

-- View element names (defined in views/drawing.json).
-- Buttons shown only while the local player is the current drawer.
local BTN_GIVE_UP     = "_NUIKKDtjGLzdy0rQ1782862171"
local BTN_REVEAL_HINT = "_xuQLH3n3H3ARkcvj1782862174"
-- Labels updated every round / every hint.
local LBL_HINT_MASK   = "_HS3wK4fxnuHeArzz1782862323"
local LBL_TIME        = "_T0ymDUIzwocvC7FK1782862419"

-- Local view of the current round
local hud_phase = "idle"
local am_drawer = false
local drawer_name = ""
local my_word = ""       -- only set for the drawer
local mask = ""
local time_left = 0
local hint_max = 0

-- Camera zoom controlled by the Zoom In / Zoom Out buttons in the view.
local zoom_level = 1.0
local ZOOM_STEP = 0.2
local ZOOM_MIN = 0.3
local ZOOM_MAX = 3.0

-- =============================================================================
-- HUD (top center) - status + timer + masked word
-- =============================================================================
local function set_hud(text)
    if is_panel_exists(HUD) then
        update_panel_settings(HUD, { text = text })
    else
        HUD = create_panel({
            title = "Draw The Word",
            text = text,
            close = false,
            set_time = false,
            resizable = false,
            no_multiple_tag = "dtw_hud",
            minimum_size = Vector2(320, 80),
            offset_ratio = Vector2(1, 0),
        })
    end
end

local function refresh_hud()
    local txt
    if hud_phase == "choosing" then
        if am_drawer then
            txt = "[center][b]Your turn![/b]\nPick a word to draw.[/center]"
        else
            txt = "[center][b]" .. drawer_name .. "[/b] is picking a word...[/center]"
        end
    elseif hud_phase == "drawing" then
        if am_drawer then
            -- Drawer sees their word inline: one line, yellow, slightly larger.
            txt = "[center]You are drawing [color=#ffff66][font_size=22]" ..
                string.upper(my_word) .. "[/font_size][/color][/center]"
        else
            -- Guessers see who is drawing. Mask goes to the view label; time to the
            -- time label. Keep the panel minimal.
            txt = "[center][b]" .. drawer_name .. "[/b] is drawing[/center]"
        end
    elseif hud_phase == "intermission" then
        txt = "[center]Get ready for the next round...[/center]"
    else
        txt = "[center][b]Draw The Word[/b]\nWaiting for players...[/center]"
    end
    set_hud(txt)
end

-- =============================================================================
-- Per-round panel cleanup
-- =============================================================================
local function close_choice() if is_panel_exists(CHOICE) then close_panel(CHOICE) end end
local function close_report() if is_panel_exists(REPORT) then close_panel(REPORT) end end
local function close_drawer()
    -- Hide the drawer-only view buttons and clear the shared hint/mask label.
    set_button({ name = BTN_GIVE_UP,     visible = false })
    set_button({ name = BTN_REVEAL_HINT, visible = false })
    set_label({  name = LBL_HINT_MASK,   text = "" })
end
local function close_paint()
    if paint_panel ~= "" and is_panel_exists(paint_panel) then close_panel(paint_panel) end
    paint_panel = ""
end
local function close_podium() if is_panel_exists(PODIUM) then close_panel(PODIUM) end end

local function clear_round_ui()
    close_choice()
    close_report()
    close_drawer()
    close_paint()
end

-- =============================================================================
-- Report button (top-right) - visible to non-drawers during a turn
-- =============================================================================
local function show_report_panel()
    if am_drawer then return end
    if is_panel_exists(REPORT) then return end
    REPORT = create_panel({
        title = "Report",
        text = "Drawer not playing fairly?",
        close = false,
        set_time = false,
        resizable = false,
        no_multiple_tag = "dtw_report",
        minimum_size = Vector2(200, 160),
        offset_ratio = Vector2(2, 0),
    })
    add_button_to_panel(REPORT, {
        text = "Report drawer",
        entity_name = "-dtw_ui",
        function_name = "report_click",
        color = Color(0.85, 0.3, 0.3, 1),
        is_vertical = true,
    })
end

function report_click(args)
    run_network_function(MANAGER, "report_drawer_HOST", {})
end

function on_report_update(report_count, threshold)
    if is_panel_exists(REPORT) then
        update_panel_settings(REPORT, {
            text = "Reports: [color=#ff8866]" .. report_count .. "[/color] / " .. threshold .. " to skip",
        })
    end
end

-- =============================================================================
-- Word choice (drawer only, during "choosing")
-- =============================================================================
function show_word_choice_CLIENT(sender_id, choices, choose_time)
    close_choice()
    CHOICE = create_panel({
        title = "Choose a word",
        text = "[center]Pick the word you want to draw:[/center]",
        close = false,
        set_time = false,
        resizable = false,
        no_multiple_tag = "dtw_choice",
        countdown = choose_time,
        minimum_size = Vector2(320, 250),
        offset_ratio = Vector2(1, 1),
    })
    for _, word in ipairs(choices) do
        add_button_to_panel(CHOICE, {
            text = word,
            entity_name = "-dtw_ui",
            function_name = "choose_word_click",
            extra_args = { word = word },
            color = Color(0.3, 0.5, 0.8, 1),
            is_vertical = true,
        })
    end
    add_button_to_panel(CHOICE, {
        text = "Pass / Skip my turn",
        entity_name = "-dtw_ui",
        function_name = "pass_turn_click",
        color = Color(0.6, 0.6, 0.6, 1),
        is_vertical = true,
    })
end

function choose_word_click(args)
    run_network_function(MANAGER, "choose_word_HOST", { args.extra_args.word })
    close_choice()
end

function pass_turn_click(args)
    run_network_function(MANAGER, "pass_turn_HOST", {})
    close_choice()
    close_drawer()
end

-- =============================================================================
-- Drawer controls (the painting panel + hint / pass buttons)
-- =============================================================================
function start_drawing_CLIENT(sender_id, word, image_name, max_reveal)
    am_drawer = true
    my_word = word
    hint_max = max_reveal

    close_choice()
    close_report()

    -- Open the ready-made painting toolbox (brush / colours / undo / etc.).
    -- offset_ratio y=0.9 shifts the panel slightly above screen-centre (y=1.0)
    -- so it sits higher on screen while still clearing the time label in the
    -- top-left of the view (label bottom ≈ 18 % of screen height).
    close_paint()
    paint_panel = create_painting_panel({
        name = image_name,
        title = "Draw: " .. string.upper(word),
        close = false,
        offset_ratio = Vector2(0, 0.9),
    })

    -- Show the drawer-only action buttons defined in views/drawing.json.
    set_button({ name = BTN_GIVE_UP,     visible = true })
    set_button({ name = BTN_REVEAL_HINT, visible = true })
end

function reveal_hint_click(args)
    run_network_function(MANAGER, "reveal_hint_HOST", {})
end

-- =============================================================================
-- Zoom controls (local: each player has their own view zoom)
-- =============================================================================
function zoom_in_click(args)
    zoom_level = math.min(zoom_level + ZOOM_STEP, ZOOM_MAX)
    set_camera_zoom(Vector2(zoom_level, zoom_level))
end

function zoom_out_click(args)
    zoom_level = math.max(zoom_level - ZOOM_STEP, ZOOM_MIN)
    set_camera_zoom(Vector2(zoom_level, zoom_level))
end

-- =============================================================================
-- Manager-driven state updates
-- =============================================================================
function on_turn_announce(p_drawer_id, p_drawer_name)
    hud_phase = "choosing"
    drawer_name = p_drawer_name
    am_drawer = (LOCAL_STEAM_ID == p_drawer_id)
    mask = ""
    clear_round_ui()
    close_podium()
    set_label({ name = LBL_TIME, text = "" })
    if not am_drawer then show_report_panel() end
    refresh_hud()
end

function on_round_start(p_drawer_id, p_drawer_name, p_mask, p_total_letters, p_time)
    hud_phase = "drawing"
    drawer_name = p_drawer_name
    am_drawer = (LOCAL_STEAM_ID == p_drawer_id)
    mask = p_mask    -- "" until the drawer presses Reveal Hint
    time_left = p_time
    -- Clear hint mask label at the start of each round.
    set_label({ name = LBL_HINT_MASK, text = "" })
    set_label({ name = LBL_TIME, text = tostring(p_time) .. "s" })
    if not am_drawer then
        my_word = ""
        show_report_panel()
        add_to_chat("[color=#88ccff]" .. p_drawer_name .. " is now drawing. Type your guesses in chat![/color]", false)
    end
    refresh_hud()
end

function on_timer(p_time_left)
    time_left = p_time_left
    set_label({ name = LBL_TIME, text = tostring(p_time_left) .. "s" })
end

function on_hint(p_mask, used, maxr)
    mask = p_mask
    hint_max = maxr
    -- Push the mask (underscores / revealed letters) to the view label.
    set_label({ name = LBL_HINT_MASK, text = mask })
    -- Hide the Reveal Hint button once the full letter-reveal budget is used.
    -- used=0 means structure was shown (free); actual letters start at used=1.
    if used >= maxr and maxr > 0 then
        set_button({ name = BTN_REVEAL_HINT, visible = false })
    end
    refresh_hud()
end

function on_correct_guess(guesser_id, guesser_name, pts)
    if guesser_id == LOCAL_STEAM_ID then
        add_to_chat("[color=#66ff99][b]You guessed it! +" .. pts .. " points[/b][/color]", false)
    else
        add_to_chat("[color=#66ff99][b]" .. guesser_name .. "[/b] guessed correctly! (+" .. pts .. ")[/color]", false)
    end
end

function notify_close_CLIENT(sender_id)
    add_to_chat("[color=#ffcc44]You guessed close![/color]", false)
end

function on_relayed_chat(chat_name, chat_text)
    add_to_chat("[color=#6699ff]" .. chat_name .. "[/color]: " .. chat_text, false)
end

function on_turn_skipped(skipped_name, reason)
    hud_phase = "intermission"
    am_drawer = false
    clear_round_ui()
    set_label({ name = LBL_TIME, text = "" })
    add_to_chat("[color=#ffaa66]" .. skipped_name .. " " .. reason .. ".[/color]", false)
    refresh_hud()
end

function on_round_end(word, p_drawer_name, bonus, lines)
    hud_phase = "intermission"
    clear_round_ui()
    set_label({ name = LBL_TIME, text = "" })

    local summary = "[color=#ffff66]The word was: [b]" .. string.upper(word) .. "[/b][/color]"
    if #lines == 0 then
        summary = summary .. "\n[color=#ff8888]Nobody guessed it.[/color]"
    else
        for _, l in ipairs(lines) do
            summary = summary .. "\n[color=#66ff99]" .. l.name .. "[/color] +" .. l.points
        end
        summary = summary .. "\n[color=#88ccff]" .. p_drawer_name .. " (drawer) +" .. bonus .. "[/color]"
    end
    add_to_chat(summary, false)
    am_drawer = false
    refresh_hud()
end

-- =============================================================================
-- Scoreboard (right side) - rebuilt on every update
-- =============================================================================
function on_scoreboard(scoreboard)
    if is_panel_exists(SCORE) then close_panel(SCORE) end
    SCORE = create_panel({
        title = "Scores",
        text = "",
        close = false,
        set_time = false,
        resizable = true,
        is_scrollable = true,
        no_multiple_tag = "dtw_score",
        minimum_size = Vector2(240, 320),
        offset_ratio = Vector2(2, 0.8),
    })
    for _, p in ipairs(scoreboard) do
        local label = p.name .. " - " .. p.score
        local col = Color(0.45, 0.5, 0.55, 1)
        if p.is_drawer then
            label = "[pencil] " .. label
            col = Color(0.3, 0.55, 0.8, 1)
        end
        if p.steam_id == LOCAL_STEAM_ID then
            label = label .. " (you)"
            col = Color(0.3, 0.7, 0.4, 1)
        end
        add_button_to_panel(SCORE, {
            text = label,
            color = col,
            is_vertical = true,
        })
    end
end

-- =============================================================================
-- Podium (game over) - top 3 with medals, clickable to open Steam profile
-- =============================================================================
function on_game_over(scoreboard)
    hud_phase = "gameover"
    am_drawer = false
    clear_round_ui()
    close_report()
    set_label({ name = LBL_TIME, text = "" })
    refresh_hud()

    close_podium()
    PODIUM = create_panel({
        title = "Final Results",
        text = "[center][b][font_size=22]Game Over![/font_size][/b][/center]",
        close = true,
        set_time = false,
        resizable = true,
        is_scrollable = true,
        no_multiple_tag = "dtw_podium",
        countdown = 14,
        minimum_size = Vector2(360, 380),
        offset_ratio = Vector2(1, 1),
    })

    local medals = { "[1st]", "[2nd]", "[3rd]" }
    local colors = { Color(0.95, 0.78, 0.2, 1), Color(0.75, 0.75, 0.8, 1), Color(0.8, 0.5, 0.3, 1) }

    for i = 1, math.min(3, #scoreboard) do
        local p = scoreboard[i]
        add_button_to_panel(PODIUM, {
            text = medals[i] .. "  " .. p.name .. "  -  " .. p.score .. " pts",
            entity_name = "-dtw_ui",
            function_name = "open_player_profile",
            extra_args = { steam_id = p.steam_id },
            color = colors[i],
            is_vertical = true,
        })
    end

    -- Remaining players as plain rows.
    for i = 4, #scoreboard do
        local p = scoreboard[i]
        add_button_to_panel(PODIUM, {
            text = i .. ". " .. p.name .. "  -  " .. p.score .. " pts",
            color = Color(0.4, 0.45, 0.5, 1),
            is_vertical = true,
        })
    end
end

function open_player_profile(args)
    open_profile(args.extra_args.steam_id)
end

function on_reset()
    hud_phase = "idle"
    am_drawer = false
    drawer_name = ""
    my_word = ""
    mask = ""
    clear_round_ui()
    close_podium()
    set_label({ name = LBL_TIME, text = "" })
    refresh_hud()
end

-- =============================================================================
-- Late-joiner sync
-- =============================================================================
function sync_state_CLIENT(sender_id, phase, p_drawer_name, p_drawer_id, p_mask, p_total_letters, p_time)
    hud_phase = phase
    drawer_name = p_drawer_name
    am_drawer = (p_drawer_id ~= "" and LOCAL_STEAM_ID == p_drawer_id)
    mask = p_mask or ""
    time_left = p_time or 0
    -- Populate the view labels to match the current round state.
    if phase == "drawing" then
        set_label({ name = LBL_HINT_MASK, text = mask })
        set_label({ name = LBL_TIME, text = tostring(time_left) .. "s" })
        if not am_drawer then show_report_panel() end
    else
        set_label({ name = LBL_HINT_MASK, text = "" })
        set_label({ name = LBL_TIME, text = "" })
    end
    refresh_hud()
end






singleton_name = "hs_ui"
network_mode = 0

-- =============================================================================
-- Hide and Seek - local HUD (runs on every peer). Drives the view labels and
-- buttons defined in views/gameplay.json, plus transient banners and the final
-- score table. All state comes from the manager's _ALL fan-out calls.
-- =============================================================================

-- View node names (from views/gameplay.json).
local LBL_HIDERS  = "_2KqOFQ8pLW2EjPX21782993139"
local LBL_SEEKERS = "_b8ISiKsKz8XrfQYg1782993191"
local LBL_SCORE   = "_txdN9vgoxXQaBk5R1782993216"
local LBL_TIME    = "_8DAdEhsV2JWB08Qp1783148038"
local BTN_FREEZE  = "_KC7nJTwMfvNKEsGX1782994308"
local BTN_NEXT    = "_rEQJw0yTVwVq9WLb1782994307"
local BTN_PREV    = "_AGBFmi2oREVo22Nc1782994418"
local BTN_SELF    = "_Nq25tndCoVpsdfAx1782994473"
local BTN_ZOOM_OUT = "_zRV9tgab0CeCaVGd1783044615"
local BTN_ZOOM_IN  = "_EvAMzUFal4MGA2b11783044632"

local MANAGER = "-hs_manager"
local VOTE = "hs_vote"    -- player map vote panel

local_role = 0
hiders = {}
nav_index = 0

-- Host seed-panel state
typed_seed = ""
last_seed = 0
pcount = 0
minp = 2

-- The panel gets a FRESH, unique name every time it is genuinely rebuilt.
-- close_panel()'s underlying node removal is deferred (queue_free), so closing
-- and immediately create_panel()-ing under the SAME name races the still-alive
-- old node: Godot silently renames the new one to dodge the collision, so the
-- add_input_to_panel/add_button_to_panel calls that follow land on the wrong
-- (or about-to-vanish) panel and the one you actually see ends up with no
-- buttons on it. Using a new name every rebuild sidesteps the race entirely.
-- IMPORTANT: these must be declared here, BEFORE on_roles/anything that uses
-- them - Lua resolves "local" scope by TEXTUAL position, not call order, so a
-- declaration placed later in the file would leave earlier functions silently
-- reading an unrelated (always-nil) global of the same name.
local setup_panel_name = ""
local setup_counter = 0
local had_seed_before = false -- tracks whether the LAST build included "Same Map"

-- =============================================================================
-- Fan-out from the manager
-- =============================================================================
function on_roles(lr, hlist, round)
    local_role = lr or 0
    hiders = hlist or {}
    nav_index = 0
    -- A real round started: clear the setup / vote / podium menus.
    if (round or 0) >= 1 then
        if setup_panel_name ~= "" and is_panel_exists(setup_panel_name) then
            close_panel(setup_panel_name)
            setup_panel_name = ""
        end
        if is_panel_exists(VOTE) then close_panel(VOTE) end
        if is_panel_exists("hs_podium") then close_panel("hs_podium") end
    end
    -- Paint Mode is for everyone (seekers and hiders); the hider-camera buttons
    -- only make sense for hiders. Zoom in/out is a hider-only camera perk (works
    -- in both Movement and Paint Mode) - seekers must never see or use it, so
    -- their view stays fixed/fair.
    local is_active = (local_role == 1 or local_role == 2)
    local is_hider = (local_role == 2)
    set_button({ name = BTN_FREEZE, visible = is_active, text = "Paint Mode" })
    set_button({ name = BTN_NEXT, visible = is_hider })
    set_button({ name = BTN_PREV, visible = is_hider })
    set_button({ name = BTN_SELF, visible = is_hider })
    set_button({ name = BTN_ZOOM_OUT, visible = is_hider })
    set_button({ name = BTN_ZOOM_IN, visible = is_hider })
end

-- =============================================================================
-- Host seed panel (start of game + after every match). Lets the host pick the
-- map: type a seed, roll a random one, or keep the same map. Deterministic, so
-- only the seed is shared with everyone else.
-- =============================================================================
-- Values cross the run_function boundary as floats ("1.0"); force whole numbers.
local function n_int(x)
    return math.floor(tonumber(x) or 0)
end

local function build_setup_text(vote_same, vote_new)
    local ready = pcount >= minp
    local lines = { "[b]Host: pick the map[/b]" }
    if ready then
        table.insert(lines, "Players: " .. n_int(pcount))
    else
        table.insert(lines, "Players: " .. n_int(pcount) .. "  (need " .. n_int(minp - pcount) .. " more)")
    end
    if last_seed > 0 then table.insert(lines, "Current seed: [b]" .. n_int(last_seed) .. "[/b]") end
    if n_int(vote_same) + n_int(vote_new) > 0 then
        table.insert(lines, "Votes -> Same: " .. n_int(vote_same) .. "   |   New: " .. n_int(vote_new))
    end
    if not ready then table.insert(lines, "You can still generate a map to explore it.") end
    return table.concat(lines, "\n")
end

local function rebuild_setup_panel(body_text, ready, has_seed)
    local old_name = setup_panel_name
    setup_counter = setup_counter + 1
    setup_panel_name = "hs_setup_" .. setup_counter
    if old_name ~= "" and is_panel_exists(old_name) then close_panel(old_name) end
    had_seed_before = has_seed

    create_panel({
        -- No close button: the host must act (pick/generate a seed) rather than
        -- being able to dismiss this and lose access to starting the match.
        name = setup_panel_name, title = "Hide & Seek - Host", text = body_text,
        set_time = false, close = false, resizable = false, minimum_size = Vector2(380, 340),
    })
    add_input_to_panel(setup_panel_name, {
        entity_name = name, function_name = "on_seed_input", text = "Seed",
        default_value = typed_seed,
    })
    add_button_to_panel(setup_panel_name, { entity_name = name, function_name = "on_use_seed",
        text = ready and "Start With This Seed" or "Generate This Seed", color = Color(0.3, 0.55, 0.35) })
    add_button_to_panel(setup_panel_name, { entity_name = name, function_name = "on_random_seed",
        text = ready and "Random Seed & Start" or "Random Seed", color = Color(0.35, 0.45, 0.6) })
    if has_seed then
        add_button_to_panel(setup_panel_name, { entity_name = name, function_name = "on_same_map",
            text = "Same Map (seed " .. last_seed .. ")", color = Color(0.5, 0.45, 0.3) })
    end
end

-- Only ever called from deliberate host actions (bootstrap, pressing a seed
-- button, casting a vote) - never from a passive player join/leave, so the
-- panel never flickers or rebuilds just because someone connected.
function show_host_setup(seed, phase, players_count, min_players, vote_same, vote_new)
    last_seed = n_int(seed)
    pcount = n_int(players_count)
    minp = n_int(min_players)
    if minp < 1 then minp = 2 end

    local ready = pcount >= minp
    local has_seed = last_seed > 0
    local body_text = build_setup_text(vote_same, vote_new)

    -- Only rebuild the button set the first time, or when a seed is picked for
    -- the very first time (that is what adds the "Same Map" button). Every
    -- other call (vote tally updates) just refreshes the text in place.
    if setup_panel_name == "" or not is_panel_exists(setup_panel_name) or (has_seed and not had_seed_before) then
        rebuild_setup_panel(body_text, ready, has_seed)
    else
        update_panel_settings(setup_panel_name, { text = body_text })
    end
end

function on_vote_update(same, new)
    if setup_panel_name ~= "" and is_panel_exists(setup_panel_name) then
        show_host_setup(last_seed, "gameover", pcount, minp, same, new)
    elseif is_panel_exists(VOTE) then
        update_panel_settings(VOTE, { text = "Vote for the next map.\nSame: " .. same .. "   |   New: " .. new })
    end
end

-- Called directly (same-peer, no network round-trip) the instant the host
-- presses any seed button, so the panel is guaranteed gone immediately rather
-- than waiting on the set_roles_ALL broadcast to round-trip back.
function close_host_setup()
    if setup_panel_name ~= "" and is_panel_exists(setup_panel_name) then
        close_panel(setup_panel_name)
        setup_panel_name = ""
    end
end

function on_seed_input(args)
    -- The input's value is delivered keyed by its label ("Seed").
    typed_seed = tostring(args["Seed"] or "")
end

function on_use_seed(args)
    local s = tonumber(typed_seed) or 0
    run_function(MANAGER, "host_begin", { s })
end

function on_random_seed(args)
    run_function(MANAGER, "host_begin", { -1 }) -- <=0 tells the host to roll one
end

function on_same_map(args)
    run_function(MANAGER, "host_begin", { last_seed })
end

-- =============================================================================
-- Player map vote (non-host, after a match).
-- =============================================================================
function show_vote(match_seed)
    if is_panel_exists(VOTE) then close_panel(VOTE) end
    create_panel({
        name = VOTE, title = "Next Map?", set_time = false, close = true,
        text = "The match is over (seed " .. (match_seed or 0) .. ").\nVote for the next map:",
        minimum_size = Vector2(320, 150),
    })
    add_button_to_panel(VOTE, { entity_name = name, function_name = "on_vote_same",
        text = "Same Map", color = Color(0.5, 0.45, 0.3) })
    add_button_to_panel(VOTE, { entity_name = name, function_name = "on_vote_new",
        text = "New Map", color = Color(0.35, 0.45, 0.6) })
end

function on_vote_same(args)
    run_network_function(MANAGER, "cast_vote_HOST", { "same" })
end

function on_vote_new(args)
    run_network_function(MANAGER, "cast_vote_HOST", { "new" })
end

function on_stats(hider_alive, hider_total, seekers, my_score)
    set_label({ name = LBL_HIDERS, text = "Hiders: " .. hider_alive .. "/" .. hider_total })
    set_label({ name = LBL_SEEKERS, text = "Seekers: " .. seekers })
    set_label({ name = LBL_SCORE, text = "Score: " .. my_score })
end

-- Round/phase countdown ("m:ss", or "" outside hiding/seeking) - see hs_manager's
-- time_tick, which reads however much time the active phase timer has left.
function on_time_display(text)
    set_label({ name = LBL_TIME, text = text or "" })
end

function on_banner(text, secs)
    create_panel({
        title = "Hide & Seek", text = text, countdown = secs or 4,
        no_multiple_tag = "hs_banner", set_time = false, close = true,
        minimum_size = Vector2(360, 120),
    })
end

function on_paint_mode(active)
    set_button({ name = BTN_FREEZE, text = active and "Movement Mode" or "Paint Mode" })
end

function on_caught(hider_name, seeker_name, is_me)
    local msg
    if is_me then
        msg = "You were caught by " .. seeker_name .. "!"
    else
        msg = seeker_name .. " caught " .. hider_name .. "!"
    end
    create_panel({
        title = "Caught!", text = msg, countdown = 3,
        no_multiple_tag = "hs_caught", set_time = false, minimum_size = Vector2(340, 110),
    })
end

function on_game_over(board, match_seed)
    if is_panel_exists("hs_podium") then close_panel("hs_podium") end
    create_panel({
        name = "hs_podium", title = "Final Scores (seed " .. (match_seed or 0) .. ")", set_time = false,
        minimum_size = Vector2(360, 320), is_scrollable = true,
    })
    for i, row in ipairs(board) do
        local color = Color(0.3, 0.35, 0.4)
        if i == 1 then color = Color(0.9, 0.75, 0.2) end
        if i == 2 then color = Color(0.7, 0.72, 0.75) end
        if i == 3 then color = Color(0.7, 0.45, 0.25) end
        add_button_to_panel("hs_podium", {
            entity_name = name, function_name = "noop",
            text = i .. ".  " .. row.name .. "   -   " .. row.score,
            color = color,
        })
    end
end

function noop(args) end

-- =============================================================================
-- View button callbacks (wired via en/fn in views/gameplay.json)
-- =============================================================================
function on_freeze_click(args)
    run_function(LOCAL_STEAM_ID, "toggle_paint_mode", {})
end

function on_next_click(args)
    if #hiders == 0 then return end
    nav_index = (nav_index % #hiders) + 1
    run_function(LOCAL_STEAM_ID, "move_camera_to", { hiders[nav_index] })
end

function on_prev_click(args)
    if #hiders == 0 then return end
    nav_index = ((nav_index - 2) % #hiders) + 1
    run_function(LOCAL_STEAM_ID, "move_camera_to", { hiders[nav_index] })
end

function on_self_click(args)
    nav_index = 0
    run_function(LOCAL_STEAM_ID, "move_camera_to", { LOCAL_STEAM_ID })
end

function on_zoom_in_click(args)
    run_function(LOCAL_STEAM_ID, "zoom_in", {})
end

function on_zoom_out_click(args)
    run_function(LOCAL_STEAM_ID, "zoom_out", {})
end

singleton_name = "gm"
network_mode = 1

-- =============================================================================
-- Beyaz Canavar - game manager. The HOST is the single authority: it owns the
-- phase, every player's role, catches, screams, escapes and the end of a round.
-- Clients only send intents (start vote, scream) and mirror what the host
-- broadcasts. Task logic lives in task_manager.lua, the school in school_gen.lua.
--
-- Round flow:
--   lobby     everybody waits in the sealed detention room next to the sleeping
--             monster; the host picks a seed in the host menu (or /start votes)
--   cutscene  the monster wakes up (it does not eat anyone yet), white flash,
--             humans are teleported into the school, the monster far away
--   playing   tasks; a caught human is eaten (3x), leaves a corpse and comes
--             back as a monster as far as possible from the remaining humans
--   escape    all five tasks done: five exits open, reaching one = escaped
--   ended     no human left in the school; results, then back to the lobby
-- =============================================================================

local LOBBY, CUTSCENE, PLAYING, ESCAPE, ENDED = "lobby", "cutscene", "playing", "escape", "ended"

local VOTE_SECONDS = 20
local CATCH_RADIUS = 26
local SCREAM_RADIUS = 96       -- 3 tiles
local SCREAM_COOLDOWN = 30
local ANIM_FPS = 8.4           -- monster_anim.lua's FPS (12 * 0.7)
local SCREAM_WINDUP = 3 / ANIM_FPS    -- the scream itself is frames 4-11: stun + shake start at frame 4
local SCREAM_ACTIVE = 8 / ANIM_FPS    -- frames 4-11 (12-14 are the way back)
local STUN_SECONDS = 3
local EAT_LOOPS = 3
local EXIT_RADIUS = 40
local RESULT_SECONDS = 15
local VOICE_RANGE = 512        -- 16 tiles
local WAKE_SECONDS = 23 / ANIM_FPS
local SCREAM_SECONDS = 14 / ANIM_FPS
local EAT_SECONDS = 17 * EAT_LOOPS / ANIM_FPS
local EAT_SOUND_RANGE = 14 * 32
local HORROR_MIN, HORROR_MAX = 90, 150 -- seconds between horror stings (average 2 minutes)

-- Mirrored on every peer.
phase = LOBBY
round = 0
seed_value = 0
roles = {}           -- steam id -> "human" | "monster" | "escaped"
npc_name = ""
exits_open = false

-- Host only.
local now = 0
local booted = false
local votes_allowed = true
local typed_seed = ""
local panel_count = 0
local panel_name = ""
local vote = nil
local busy_until = {}      -- monster -> time it may move/catch again
local cooldown_until = {}  -- monster -> time it may scream again
local dying = {}           -- victim steam id -> true while being eaten
local corpses = {}
local escaped_list = {}
local test_boss = ""       -- /testboss: the host playing the monster; the round never ends by itself

-- Local (every peer).
local vote_panel = ""
local result_panel = ""
local exit_markers = {}
exit_serial = 0
local bell_on = false

-- The school bell rings from the moment the exits open until the NEXT round
-- starts (through the results and the lobby). It is a child of this entity so
-- it can be found again and stopped; a SoundManager-parented player cannot.
local function set_bell(on)
    if on == bell_on then return end
    bell_on = on
    if on then
        set_audio({ stream_path = "bell", name = "bc_bell", parent_name = name, is_loop = true })
    else
        destroy(name, "bc_bell", false)
    end
end

-- Phase to this peer's players AND straight to the HUD: a late joiner's own
-- player entity may not exist yet when the state arrives.
function set_local_phase(args)
    run_function_by_tag("user", "set_phase", args)
    run_function("-hud", "set_phase", args)
end

local function is_user(id)
    return id ~= nil and id ~= "" and id ~= npc_name and entity_exists(id) and has_tag(id, "user")
end

local function users()
    return get_entity_names_by_tag("user")
end

local function nick_of(id)
    local n = get_value("", id, "nickname")
    return n and tostring(n) or "?"
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- =============================================================================
-- Boot
-- =============================================================================

function host_boot()
    if not IS_HOST or booted then return end
    booted = true
    set_minimap(true)
    local pos = run_function("-gen", "get_lobby_monster_pos")
    npc_name = spawn_entity_host({ t = "monster", p = pos }) or ""
    for _, id in ipairs(users()) do
        if not roles[id] then roles[id] = "human" end
    end
    typed_seed = tostring(get_os_time_unix() % 1000000007)
    show_host_panel()
end

start_timer({ timer_id = "bc_gm_boot", entity_name = name, function_name = "host_boot",
    wait_time = 0.5, duration = 0.5 })
start_timer({ timer_id = "bc_gm_tick", entity_name = name, function_name = "tick", wait_time = 0.1 })

-- The horror sting: the host rolls a random moment about every two minutes and
-- everybody hears it together. run_function's delay, not a timer: a timer
-- re-armed from inside its own callback is removed right after it returns.
local function next_horror()
    run_function(name, "horror_tick", {}, HORROR_MIN + math.random() * (HORROR_MAX - HORROR_MIN))
end

function horror_tick()
    if not IS_HOST then return end
    if phase == PLAYING or phase == ESCAPE then run_network_function(name, "horror_ALL", {}) end
    next_horror()
end

function horror_ALL(sender_id)
    set_audio({ stream_path = "horror", bus = "Ambient" })
end

if IS_HOST then next_horror() end

function _process(delta, inputs)
    now = now + delta
    return nil
end

-- monster.lua registers itself on every peer as it spawns.
function register_npc(entity_name)
    npc_name = entity_name
end

-- =============================================================================
-- Host menu (seed + start + vote switch)
-- =============================================================================

function show_host_panel()
    if not IS_HOST or phase ~= LOBBY then return end
    close_host_panel()
    panel_count = panel_count + 1
    panel_name = "_bc_host_menu_" .. panel_count
    create_panel({ name = panel_name, title = "{host_menu_title}", text = "{host_menu_text}",
        set_time = false, close = false, resizable = false, minimum_size = Vector2(440, 320) })
    add_input_to_panel(panel_name, { entity_name = name, function_name = "on_seed_typed",
        text = "{seed}", default_value = typed_seed })
    add_checkbox_to_panel(panel_name, { entity_name = name, function_name = "on_votes_toggled",
        text = "{allow_start_votes}", default_value = votes_allowed })
    add_button_to_panel(panel_name, { entity_name = name, function_name = "on_random_seed",
        text = "{random_seed}", color = Color(0.35, 0.45, 0.6) })
    add_button_to_panel(panel_name, { entity_name = name, function_name = "on_start_pressed",
        text = "{start_game}", color = Color(0.55, 0.2, 0.2) })
end

function close_host_panel()
    if panel_name ~= "" and is_panel_exists(panel_name) then close_panel(panel_name) end
    panel_name = ""
end

function on_seed_typed(args)
    -- Values arrive keyed by the control's RAW label, i.e. the token.
    typed_seed = tostring(args["{seed}"] or "")
end

function on_votes_toggled(args)
    votes_allowed = args["{allow_start_votes}"] == true
end

function on_random_seed(args)
    if args and args["{allow_start_votes}"] ~= nil then votes_allowed = args["{allow_start_votes}"] == true end
    typed_seed = tostring(get_os_time_unix() % 1000000007)
    show_host_panel()
end

function on_start_pressed(args)
    if args then
        if args["{seed}"] ~= nil then typed_seed = tostring(args["{seed}"]) end
        if args["{allow_start_votes}"] ~= nil then votes_allowed = args["{allow_start_votes}"] == true end
    end
    start_round()
end

local function chosen_seed()
    local s = tonumber(typed_seed)
    if not s or math.floor(s) == 0 then s = get_os_time_unix() % 1000000007 end
    -- The seed shown in chat must rebuild the same school when typed back in.
    s = math.floor(math.abs(s)) % 2147483646
    if s == 0 then s = 1 end
    return s
end

-- =============================================================================
-- /start vote (Finding Liar style) - commands.lua forwards here
-- =============================================================================

local function tell(steam_id, token)
    if steam_id == HOST_STEAM_ID then
        run_function("-hud", "banner", { token, 3 })
    else
        run_network_function(name, "tell_CLIENT", { token }, steam_id)
    end
end

function tell_CLIENT(sender_id, token)
    run_function("-hud", "banner", { token, 3 })
end

function request_start_HOST(sender_id)
    if not IS_HOST then return end
    if phase ~= LOBBY then tell(sender_id, "{game_already_running}") return end
    if sender_id == HOST_STEAM_ID then start_round() return end
    if not votes_allowed then tell(sender_id, "{start_votes_disabled}") return end
    if vote then tell(sender_id, "{vote_already_running}") return end
    vote = { yes = { [sender_id] = true }, no = {} }
    run_network_function(name, "vote_ALL", { nick_of(sender_id), VOTE_SECONDS, sender_id })
    start_timer({ timer_id = "bc_vote", entity_name = name, function_name = "vote_timeout",
        wait_time = VOTE_SECONDS, duration = VOTE_SECONDS })
    check_vote()
end

function vote_HOST(sender_id, yes)
    if not IS_HOST or not vote or phase ~= LOBBY then return end
    if vote.yes[sender_id] or vote.no[sender_id] then return end
    if yes then vote.yes[sender_id] = true else vote.no[sender_id] = true end
    check_vote()
end

function check_vote()
    if not vote then return end
    local voters = math.max(1, #users())
    local needed = voters // 2 + 1
    local yes, no = count(vote.yes), count(vote.no)
    run_network_function(name, "vote_progress_ALL", { yes, no, needed })
    if yes >= needed then
        vote = nil
        stop_timer("bc_vote")
        run_network_function(name, "vote_result_ALL", { true })
        start_round()
    elseif no > voters - needed or yes + no >= voters then
        vote = nil
        stop_timer("bc_vote")
        run_network_function(name, "vote_result_ALL", { false })
    end
end

function vote_timeout(args)
    if not vote then return end
    vote = nil
    run_network_function(name, "vote_result_ALL", { false })
end

function vote_ALL(sender_id, initiator_nick, seconds, initiator_id)
    if vote_panel ~= "" and is_panel_exists(vote_panel) then close_panel(vote_panel) end
    vote_panel = "_bc_vote_" .. math.floor(get_os_time_unix() % 100000) .. "_" .. math.floor(seconds)
    create_panel({ name = vote_panel, title = "{vote_title}",
        text = string.format(translate("{vote_text}"), tostring(initiator_nick)),
        set_time = false, close = true, countdown = seconds, minimum_size = Vector2(380, 180) })
    if initiator_id ~= LOCAL_STEAM_ID then
        add_button_to_panel(vote_panel, { entity_name = name, function_name = "on_vote_yes",
            text = "{vote_yes}", color = Color(0.25, 0.55, 0.3), is_vertical = false })
        add_button_to_panel(vote_panel, { entity_name = name, function_name = "on_vote_no",
            text = "{vote_no}", color = Color(0.6, 0.25, 0.25), is_vertical = false })
    end
end

function on_vote_yes(args)
    run_network_function(name, "vote_HOST", { true })
    if vote_panel ~= "" and is_panel_exists(vote_panel) then close_panel(vote_panel) end
end

function on_vote_no(args)
    run_network_function(name, "vote_HOST", { false })
    if vote_panel ~= "" and is_panel_exists(vote_panel) then close_panel(vote_panel) end
end

function vote_progress_ALL(sender_id, yes, no, needed)
    if vote_panel ~= "" and is_panel_exists(vote_panel) then
        update_panel_settings(vote_panel, { text = string.format(translate("{vote_progress}"),
            math.floor(yes), math.floor(needed), math.floor(no)) })
    end
end

function vote_result_ALL(sender_id, passed)
    if vote_panel ~= "" and is_panel_exists(vote_panel) then close_panel(vote_panel) end
    vote_panel = ""
    run_function("-hud", "banner", { passed and "{vote_passed}" or "{vote_failed}", 3 })
end

-- =============================================================================
-- Round start: wake-up cutscene, flash, teleport
-- =============================================================================

function start_round()
    if not IS_HOST or phase ~= LOBBY then return end
    close_host_panel()
    if vote then
        vote = nil
        stop_timer("bc_vote")
    end
    seed_value = chosen_seed()
    round = round + 1
    phase = CUTSCENE
    escaped_list = {}
    dying = {}
    busy_until = {}
    cooldown_until = {}
    for _, id in ipairs(users()) do roles[id] = "human" end
    run_network_function(name, "start_ALL", { seed_value, round, roles })
    cutscene_waited = 0
    -- run_function's delay, not a timer: a timer re-armed from inside its own
    -- callback is removed right after the callback returns (TimerManager stops
    -- a finished one after calling it), which used to strand a slow round 2 in
    -- the detention room forever.
    run_function(name, "cutscene_done", { round }, WAKE_SECONDS + 0.4)
end

cutscene_waited = 0

function start_ALL(sender_id, new_seed, new_round, new_roles)
    seed_value = math.floor(new_seed)
    round = math.floor(new_round)
    phase = CUTSCENE
    set_bell(false)
    apply_roles(new_roles)
    run_function("-gen", "set_seed", { seed_value, true })
    if npc_name ~= "" and entity_exists(npc_name) then
        run_function("-anim", "play", { npc_name, "wake_up", 1 })
    end
    set_local_phase({ CUTSCENE })
    run_function("-hud", "banner", { "{it_wakes_up}", WAKE_SECONDS + 0.5 })
    run_function("-anim", "shake", { WAKE_SECONDS, 8 })
end

function cutscene_done(for_round)
    if phase ~= CUTSCENE or math.floor(tonumber(for_round) or 0) ~= round then return end
    -- Wait for this peer's school to be painted (at most a few seconds).
    if not run_function("-gen", "is_ready") and cutscene_waited < 6 then
        cutscene_waited = cutscene_waited + 0.3
        run_function(name, "cutscene_done", { round }, 0.3)
        return
    end
    run_network_function(name, "flash_ALL", {})
    -- Humans into the start room, spread out; the monster as far away as it gets.
    local spawns = run_function("-gen", "get_human_spawns") or {}
    local i = 0
    for _, id in ipairs(users()) do
        if roles[id] == "human" and #spawns > 0 then
            i = i + 1
            local p = spawns[1 + ((i - 1) * 7) % #spawns]
            teleport(id, p)
        end
    end
    if npc_name ~= "" and entity_exists(npc_name) then
        run_function(npc_name, "host_begin_hunt", { run_function("-gen", "get_monster_spawn") })
    end
    phase = PLAYING
    exits_open = false
    run_function("-tasks", "host_new_round", {})
    run_network_function(name, "phase_ALL", { PLAYING, seed_value })
    if test_boss ~= "" then spawn_as_monster(test_boss) end
end

function flash_ALL(sender_id)
    flash_vignette({ color = Color(1, 1, 1, 1), radius = -1, smoothness = 0.01, duration = 1.4 })
end

function phase_ALL(sender_id, new_phase, s)
    phase = new_phase
    set_local_phase({ phase })
    if phase == PLAYING then
        add_to_chat(string.format(translate("{seed_announce}"), math.floor(s)))
        run_function("-hud", "banner", { "{find_tasks_banner}", 5 })
    end
end

function teleport(id, p)
    unfreeze_entity(id)
    change_instantly({ entity_name = id, position = p, linear_velocity = Vector2(0, 0) })
end

-- =============================================================================
-- Roles
-- =============================================================================

function apply_roles(new_roles)
    roles = {}
    for id, role in pairs(new_roles or {}) do roles[tostring(id)] = role end
    for id, role in pairs(roles) do
        if entity_exists(id) then run_function(id, "apply_role", { role }) end
    end
end

function role_ALL(sender_id, id, role)
    roles[id] = role
    if entity_exists(id) then run_function(id, "apply_role", { role }) end
    if id == LOCAL_STEAM_ID and role ~= "human" then run_function("-tasks", "clear_local", {}) end
end

local function set_role(id, role)
    roles[id] = role
    run_network_function(name, "role_ALL", { id, role })
end

function get_role(id)
    return roles[id] or "human"
end

-- Humans that can be chased / caught right now (host).
function get_humans()
    local out = {}
    for _, id in ipairs(users()) do
        if roles[id] == "human" and not dying[id] then out[#out + 1] = id end
    end
    return out
end

function is_busy(m)
    return (busy_until[m] or 0) > now
end

function can_scream(m)
    return not is_busy(m) and (cooldown_until[m] or 0) <= now
end

-- =============================================================================
-- Join / leave
-- =============================================================================

function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end
    set_voice_channel({ steam_id = steam_id, channel_name = "school", parent_name = steam_id,
        proximity_length = VOICE_RANGE, icon_offset = Vector2(0, -30) })
    if phase == PLAYING or phase == ESCAPE then
        roles[steam_id] = "monster"
    elseif not roles[steam_id] then
        roles[steam_id] = "human"
    end
    if steam_id ~= HOST_STEAM_ID then
        run_network_function(name, "state_CLIENT", { phase, round, seed_value, roles, exits_open, npc_name }, steam_id)
        run_function("-tasks", "host_sync_to", { steam_id })
    end
    run_network_function(name, "role_ALL", { steam_id, roles[steam_id] })
    if roles[steam_id] == "monster" then
        -- Late joiner during a round: wakes up as a monster far from the humans.
        run_function(name, "spawn_as_monster", { steam_id }, 0.6)
    end
end

function state_CLIENT(sender_id, new_phase, new_round, new_seed, new_roles, exits, npc)
    phase = new_phase
    round = math.floor(new_round)
    seed_value = math.floor(new_seed)
    if npc and npc ~= "" then npc_name = npc end
    apply_roles(new_roles)
    set_local_phase({ phase })
    if seed_value > 0 then run_function("-gen", "set_seed", { seed_value }) end
    exits_open = exits
    if exits_open then pending_exits = true end
    set_bell(exits_open == true)
end

-- Exits of a late joiner can only be drawn once its school is painted.
pending_exits = false
function on_school_ready(s)
    if pending_exits then
        pending_exits = false
        show_exits_local()
    end
    run_function("-tasks", "on_school_ready", {})
end

function _on_user_disconnected(steam_id, nickname)
    roles[steam_id] = nil
    if not IS_HOST then return end
    dying[steam_id] = nil
    run_function("-tasks", "host_player_left", { steam_id })
    check_end()
end

-- =============================================================================
-- Host tick: catches, escapes, end of round
-- =============================================================================

local function monsters()
    local out = {}
    if npc_name ~= "" and entity_exists(npc_name) then out[#out + 1] = npc_name end
    for _, id in ipairs(users()) do
        if roles[id] == "monster" then out[#out + 1] = id end
    end
    return out
end

function tick(args)
    if not IS_HOST then return end
    if phase ~= PLAYING and phase ~= ESCAPE then return end
    local humans = get_humans()
    for _, m in ipairs(monsters()) do
        if not is_busy(m) then
            local mp = get_value("", m, "position")
            if mp then
                for _, h in ipairs(humans) do
                    local hp = get_value("", h, "position")
                    if hp and not dying[h] and dist(mp, hp) <= CATCH_RADIUS then
                        catch(m, h, hp)
                        break
                    end
                end
            end
        end
    end
    if phase == ESCAPE then check_escapes() end
    check_end()
end

function catch(m, victim, pos)
    dying[victim] = true
    busy_until[m] = now + EAT_SECONDS
    run_function("-tasks", "host_drop_items", { victim, pos.x, pos.y })
    corpses[#corpses + 1] = spawn_entity_host({ t = "corpse", p = pos, owner = victim, nick = nick_of(victim) })
    freeze_entity(victim)
    run_network_function(name, "caught_ALL", { victim, m, EAT_SECONDS })
    if m == npc_name then run_function(npc_name, "host_eat", { EAT_SECONDS }) end
    start_timer({ timer_id = "bc_convert_" .. victim, entity_name = name, function_name = "convert_victim",
        wait_time = EAT_SECONDS, duration = EAT_SECONDS, extra_args = { victim = victim } })
end

function caught_ALL(sender_id, victim, m, seconds)
    if entity_exists(victim) then run_function(victim, "set_eaten", {}) end
    if entity_exists(m) then
        set_audio({ stream_path = "eating", parent_name = m, is_2d = true, max_distance = EAT_SOUND_RANGE })
        run_function("-anim", "play", { m, "eating", EAT_LOOPS })
        if has_tag(m, "user") then run_function(m, "set_busy", { seconds }) end
    end
    if victim == LOCAL_STEAM_ID then
        run_function("-hud", "banner", { "{you_were_caught}", seconds })
        run_function("-anim", "shake", { 1.2, 16 })
        flash_vignette({ color = Color(0.8, 0.0, 0.0, 1), duration = 1.2 })
        run_function("-tasks", "clear_local", {})
    end
end

function convert_victim(args)
    local victim = args.extra_args and args.extra_args.victim or ""
    dying[victim] = nil
    if not is_user(victim) or phase == ENDED or phase == LOBBY then return end
    spawn_as_monster(victim)
    check_end()
end

-- Puts a player into the school as a monster, as far as possible from every
-- remaining human, playing the wake-up in place.
function spawn_as_monster(id)
    if not IS_HOST or not is_user(id) then return end
    if phase ~= PLAYING and phase ~= ESCAPE then return end
    local points = run_function("-gen", "get_room_points") or {}
    local humans = get_humans()
    local best, best_d = nil, -1
    for _, p in ipairs(points) do
        local d = math.huge
        for _, h in ipairs(humans) do
            local hp = get_value("", h, "position")
            if hp then d = math.min(d, dist(p, hp)) end
        end
        if d > best_d then best, best_d = p, d end
    end
    best = best or run_function("-gen", "get_monster_spawn")
    teleport(id, best)
    roles[id] = "monster"
    busy_until[id] = now + WAKE_SECONDS
    cooldown_until[id] = now + SCREAM_COOLDOWN * 0.5
    run_network_function(name, "became_monster_ALL", { id, WAKE_SECONDS })
end

function became_monster_ALL(sender_id, id, seconds)
    roles[id] = "monster"
    if entity_exists(id) then
        run_function(id, "apply_role", { "monster" })
        run_function("-anim", "play", { id, "wake_up", 1 })
        run_function(id, "set_busy", { seconds })
    end
    if id == LOCAL_STEAM_ID then
        run_function("-hud", "banner", { "{you_are_monster}", 5 })
        run_function("-tasks", "clear_local", {})
    end
end

function check_escapes()
    local exits = run_function("-tasks", "get_exit_points") or {}
    for _, h in ipairs(get_humans()) do
        local hp = get_value("", h, "position")
        if hp then
            for _, e in ipairs(exits) do
                if dist(hp, e) <= EXIT_RADIUS then
                    escape(h, hp)
                    break
                end
            end
        end
    end
end

function escape(id, pos)
    run_function("-tasks", "host_drop_items", { id, pos.x, pos.y })
    roles[id] = "escaped"
    escaped_list[#escaped_list + 1] = id
    local lobby = run_function("-gen", "get_lobby_spawns") or {}
    if #lobby > 0 then teleport(id, lobby[1 + (#escaped_list * 5) % #lobby]) end
    run_network_function(name, "role_ALL", { id, "escaped" })
    run_network_function(name, "escaped_ALL", { id, nick_of(id) })
end

function escaped_ALL(sender_id, id, nick)
    run_function("-hud", "banner", { string.format(translate("{player_escaped}"), tostring(nick)), 4 })
    if id == LOCAL_STEAM_ID then
        run_function("-hud", "banner", { "{you_escaped}", 5 })
        clear_exits_local()
    end
end

function check_end()
    if not IS_HOST then return end
    if phase ~= PLAYING and phase ~= ESCAPE then return end
    if test_boss ~= "" then return end
    if count(dying) > 0 then return end
    if #get_humans() > 0 then return end
    phase = ENDED
    local winners = {}
    for _, id in ipairs(escaped_list) do winners[#winners + 1] = nick_of(id) end
    run_network_function(name, "end_ALL", { winners })
    start_timer({ timer_id = "bc_back_to_lobby", entity_name = name, function_name = "back_to_lobby",
        wait_time = RESULT_SECONDS, duration = RESULT_SECONDS })
end

function end_ALL(sender_id, winners)
    phase = ENDED
    set_local_phase({ ENDED })
    if result_panel ~= "" and is_panel_exists(result_panel) then close_panel(result_panel) end
    result_panel = "_bc_result_" .. round
    local text
    if winners and #winners > 0 then
        text = "{survivors_win}\n\n" .. table.concat(winners, "\n")
    else
        text = "{monsters_win}"
    end
    create_panel({ name = result_panel, title = "{round_over}", text = text, set_time = false,
        countdown = RESULT_SECONDS, minimum_size = Vector2(360, 220) })
    clear_exits_local()
end

-- =============================================================================
-- Back to the lobby
-- =============================================================================

function back_to_lobby(args)
    if not IS_HOST then return end
    for _, c in ipairs(corpses) do
        if c and c ~= "" then destroy("", c) end
    end
    corpses = {}
    test_boss = ""
    run_function("-tasks", "host_end_round", {})
    phase = LOBBY
    exits_open = false
    dying = {}
    busy_until = {}
    cooldown_until = {}
    local lobby = run_function("-gen", "get_lobby_spawns") or {}
    local i = 0
    for _, id in ipairs(users()) do
        roles[id] = "human"
        i = i + 1
        if #lobby > 0 then teleport(id, lobby[1 + (i * 5) % #lobby]) end
    end
    if npc_name ~= "" and entity_exists(npc_name) then
        run_function(npc_name, "host_sleep", { run_function("-gen", "get_lobby_monster_pos") })
    end
    run_network_function(name, "lobby_ALL", { roles })
    typed_seed = tostring(get_os_time_unix() % 1000000007)
    show_host_panel()
end

function lobby_ALL(sender_id, new_roles)
    phase = LOBBY
    exits_open = false
    apply_roles(new_roles)
    set_local_phase({ LOBBY })
    if result_panel ~= "" and is_panel_exists(result_panel) then close_panel(result_panel) end
    clear_exits_local()
    run_function("-tasks", "clear_local", {})
    run_function("-hud", "banner", { "{back_in_detention}", 4 })
end

-- =============================================================================
-- /testboss (host only): become the monster right away to test it. With nobody
-- left to hunt the round would end and restart at once, so check_end is off
-- until the same command is typed again (or the round goes back to the lobby).
-- =============================================================================

function request_testboss_HOST(sender_id)
    if not IS_HOST then return end
    if sender_id ~= HOST_STEAM_ID then tell(sender_id, "{testboss_host_only}") return end
    if test_boss ~= "" and (phase == PLAYING or phase == ESCAPE) then
        tell(sender_id, "{testboss_off}")
        back_to_lobby()
        return
    end
    if phase == ENDED then tell(sender_id, "{testboss_wait}") return end
    test_boss = sender_id
    tell(sender_id, "{testboss_on}")
    if phase == LOBBY then
        start_round()
    elseif phase == PLAYING or phase == ESCAPE then
        if roles[sender_id] ~= "monster" and not dying[sender_id] then
            local p = get_value("", sender_id, "position")
            if p then run_function("-tasks", "host_drop_items", { sender_id, p.x, p.y }) end
            spawn_as_monster(sender_id)
        end
    end
    -- CUTSCENE: cutscene_done turns the host into the monster once the round starts.
end

-- =============================================================================
-- Screams (NPC from monster.lua, players via scream_HOST)
-- =============================================================================

function scream_HOST(sender_id)
    if not IS_HOST then return end
    if roles[sender_id] ~= "monster" or (phase ~= PLAYING and phase ~= ESCAPE) then return end
    if not can_scream(sender_id) then return end
    do_scream(sender_id)
end

function do_scream(m)
    if not can_scream(m) then return false end
    cooldown_until[m] = now + SCREAM_COOLDOWN
    busy_until[m] = now + SCREAM_SECONDS
    run_network_function(name, "scream_ALL", { m, SCREAM_SECONDS, SCREAM_COOLDOWN })
    start_timer({ timer_id = "bc_scream_" .. m, entity_name = name, function_name = "scream_hit",
        wait_time = SCREAM_WINDUP, duration = SCREAM_WINDUP, extra_args = { m = m } })
    return true
end

function scream_hit(args)
    local m = args.extra_args and args.extra_args.m or ""
    if not entity_exists(m) then return end
    local mp = get_value("", m, "position")
    if not mp then return end
    local nearest, nearest_d = nil, math.huge
    for _, h in ipairs(get_humans()) do
        local hp = get_value("", h, "position")
        if hp then
            local d = dist(mp, hp)
            if d <= SCREAM_RADIUS then
                run_network_function(name, "stun_ALL", { h, STUN_SECONDS })
            end
            if d < nearest_d then nearest, nearest_d = hp, d end
        end
    end
    -- A screaming PLAYER monster hears where the closest human is (2 seconds).
    if nearest and has_tag(m, "user") then
        if m == HOST_STEAM_ID then
            reveal_prey(nearest)
        else
            run_network_function(name, "reveal_CLIENT", { nearest }, m)
        end
    end
end

local reveal_serial = 0
local REVEAL_SECONDS = 2

function reveal_CLIENT(sender_id, pos)
    reveal_prey(pos)
end

function reveal_prey(pos)
    reveal_fog(pos, 2.5, REVEAL_SECONDS)
    reveal_serial = reveal_serial + 1
    local target = "bc_prey_" .. reveal_serial
    set_image({ name = target, image_path = "tiles/blood_floor", position = pos, visible = false })
    local icon = set_navigation_icon({ name = "nav_bc_prey_" .. reveal_serial, target_name = target,
        text = "{prey_here}", color = Color(1, 0.25, 0.25, 1), is_show_distance = true, show_on_screen = true,
        outline_color = Color(0, 0, 0, 1), outline_size = 8 })
    run_function("-hud", "banner", { "{prey_heard}", REVEAL_SECONDS })
    run_function(name, "clear_reveal", { target, icon or "" }, REVEAL_SECONDS)
end

function clear_reveal(target, icon)
    if icon and icon ~= "" then destroy("", icon) end
    destroy("", target, false)
end

function scream_ALL(sender_id, m, seconds, cooldown)
    if entity_exists(m) then
        run_function("-anim", "play", { m, "scream", 1 })
        if has_tag(m, "user") then run_function(m, "set_busy", { seconds }) end
    end
    if m == LOCAL_STEAM_ID then run_function("-hud", "scream_used", { cooldown }) end
    -- The shake starts with the scream itself (frame 4), like the stun.
    run_function(name, "scream_feel", { m }, SCREAM_WINDUP)
end

-- Everybody close enough feels it - monsters and the screamer too. Humans in
-- stun range are skipped: they get the stronger stun_ALL shake, and this one
-- would replace it if it arrived second.
function scream_feel(m)
    local me = get_value("", LOCAL_STEAM_ID, "position")
    local mp = entity_exists(m) and get_value("", m, "position") or nil
    if not me or not mp then return end
    local d = dist(me, mp)
    if d > SCREAM_RADIUS * 4 then return end
    if roles[LOCAL_STEAM_ID] == "human" and d <= SCREAM_RADIUS then return end
    run_function("-anim", "shake", { SCREAM_ACTIVE, 13 })
end

function stun_ALL(sender_id, id, seconds)
    if entity_exists(id) then run_function(id, "set_stunned", { seconds }) end
    if id == LOCAL_STEAM_ID then
        run_function("-anim", "shake", { math.min(seconds, 2.0), 30 })
        flash_vignette({ color = Color(0.5, 0.0, 0.0, 1), duration = seconds * 0.6 })
        run_function("-hud", "banner", { "{you_are_stunned}", seconds })
    end
end

-- =============================================================================
-- Exits (task_manager calls host_all_tasks_done)
-- =============================================================================

function host_all_tasks_done()
    if not IS_HOST or phase ~= PLAYING then return end
    phase = ESCAPE
    exits_open = true
    run_network_function(name, "exits_ALL", {})
end

function exits_ALL(sender_id)
    phase = ESCAPE
    exits_open = true
    set_local_phase({ ESCAPE })
    set_bell(true)
    show_exits_local()
    if roles[LOCAL_STEAM_ID] == "human" then
        run_function("-hud", "banner", { "{all_tasks_done_escape}", 6 })
        add_to_chat("{all_tasks_done_escape}")
    elseif roles[LOCAL_STEAM_ID] == "monster" then
        run_function("-hud", "banner", { "{they_are_escaping}", 5 })
    end
end

function show_exits_local()
    run_function("-gen", "open_exits", {})
    clear_exits_local()
    if roles[LOCAL_STEAM_ID] ~= "human" then return end
    local points = run_function("-tasks", "get_exit_points") or {}
    exit_serial = exit_serial + 1
    for i, p in ipairs(points) do
        local target = "bc_exit_target_" .. exit_serial .. "_" .. i
        set_image({ name = target, image_path = "tiles/door_exit", position = p, visible = false })
        local icon = set_navigation_icon({ name = "nav_bc_exit_" .. exit_serial .. "_" .. i, target_name = target, text = "{exit}",
            color = Color(0.45, 1.0, 0.5, 1), is_show_distance = true, show_on_screen = true, outline_color = Color(0, 0, 0, 1),
            outline_size = 8 })
        exit_markers[#exit_markers + 1] = { target = target, icon = icon }
    end
end

function clear_exits_local()
    for _, m in ipairs(exit_markers) do
        if m.icon and m.icon ~= "" then destroy("", m.icon) end
        destroy("", m.target, false)
    end
    exit_markers = {}
end

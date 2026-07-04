network_mode = 1
singleton_name = "hs_manager"

-- =============================================================================
-- Hide and Seek - host-authoritative game manager. Runs on every peer, but all
-- decisions (roles, catches, scoring, world seed, timing) are made ONLY on the
-- host; clients send intents that the host validates (anti-cheat). _ALL handlers
-- run everywhere and keep a light client mirror + fan out UI updates.
--
-- Game shape: two rounds. Players are split into group A and group B. Round 1 A
-- seeks / B hides; round 2 the sides swap. During the hiding phase seekers are
-- free to roam the whole map (so they can memorise item layout/terrain), but
-- each side is made invisible to the other (client-side, per-viewer) so nobody
-- can actually spot the opposing team while hiding/scouting. PRE_LOCK_WARN
-- seconds before the hunt, seekers are teleported back into their room and the
-- door reseals; when the hunt starts the door opens and everyone becomes
-- visible to everyone. Scores accumulate across both rounds, then a final score
-- table is shown.
-- =============================================================================

local GEN = "-hs_gen"
local UI = "-hs_ui"

-- Tunables ------------------------------------------------------------------
local MIN_PLAYERS = 2
local ROUNDS = 2
local HIDE_LOCK = 60          -- total prep-phase length (roam, memorise, hide, paint)
local PRE_LOCK_WARN = 10      -- seconds before the hunt: seekers get pulled back in
local SEEK_TIME = 120         -- seconds of hunting after the room opens
local ROUND_GAP = 6           -- pause between rounds
local PODIUM_TIME = 14        -- how long the final score table stays up
local SEEKER_FRACTION = 0.34  -- share of players that seek in round 1
local SHOOT_COOLDOWN = 2.0    -- seconds between a seeker's shots
local SHOOT_RANGE = 96        -- ray length in px (6 tiles at the current 16px tile size)
local WHISTLE_MIN = 8         -- random whistle interval bounds (seconds)
local WHISTLE_MAX = 16
-- Scoring
local CATCH_BASE = 50         -- seeker points per catch (+ time bonus)
local CATCH_MAX = 150         -- extra seeker points for an instant catch
local SURVIVE_MAX = 200       -- hider points for surviving the full hunt
local SURVIVE_BONUS = 100     -- extra for never being caught at all

-- Host-authoritative state --------------------------------------------------
players = {}      -- steam_id -> { name, group, role, score, alive, in_game }
connected = {}    -- ordered steam_ids
phase = "lobby"   -- lobby | preview | hiding | seeking | round_end | gameover
round_no = 0
seed = 0          -- current match seed (0 = none chosen yet)
map_w = 40
map_h = 40
seek_started = 0
last_shot = {}    -- steam_id -> time of last shot
votes = {}        -- steam_id -> "same" | "new" (post-match map vote)

-- Client mirror (every peer) -------------------------------------------------
cl_phase = "lobby"

-- Deterministic RNG for group splits / seeds / whistle target ---------------
local rng_state = 1
local function rng_seed(s) rng_state = s % 2147483647; if rng_state <= 0 then rng_state = rng_state + 2147483646 end end
local function rng_int() rng_state = (rng_state * 16807) % 2147483647; return rng_state end
local function rng_range(a, b) if b < a then return a end; return a + (rng_int() % (b - a + 1)) end

-- Whole-second wall clock (unix seconds).
local function now()
    return get_os_time_unix()
end

local function count(pred)
    local n = 0
    for _, p in pairs(players) do if pred(p) then n = n + 1 end end
    return n
end

local function list_remove(list, value)
    for i, v in ipairs(list) do if v == value then table.remove(list, i); return end end
end

-- =============================================================================
-- HOST: role assignment + world sizing
-- =============================================================================

-- Split the roster into group A (round-1 seekers) and group B (round-1 hiders),
-- seeded so it is reproducible. A is the minority so hide and seek feels classic.
local function assign_groups()
    local ids = {}
    for _, id in ipairs(connected) do
        if players[id] then table.insert(ids, id) end
    end
    -- Fisher-Yates shuffle with the deterministic RNG.
    for i = #ids, 2, -1 do
        local j = rng_range(1, i)
        ids[i], ids[j] = ids[j], ids[i]
    end
    local total = #ids
    local seekers = math.max(1, math.min(total - 1, math.floor(total * SEEKER_FRACTION + 0.5)))
    for i, id in ipairs(ids) do
        players[id].group = (i <= seekers) and 1 or 2
        players[id].in_game = true
    end
end

-- Roles for a round: group 1 seeks in round 1 and hides in round 2 (and v.v.).
local function role_of(group, r)
    local seeker_group = (r == 1) and 1 or 2
    return (group == seeker_group) and 1 or 2 -- 1 = seeker, 2 = hider
end

-- Main-cave size (in 16px tiles) from the round's seeker/hider counts: bigger with
-- more players, wider when seekers outnumber hiders, tighter when hiders dominate.
-- (The generator adds a fixed seeker-room annex on top of this.)
local function compute_map_size(n_hiders, n_seekers)
    local ratio = n_seekers / math.max(1, n_hiders)
    local factor = math.max(0.75, math.min(1.8, 0.7 + 0.5 * ratio))
    local dim = math.floor((34 + 5 * n_hiders + 3 * n_seekers) * factor + 0.5)
    dim = math.max(38, math.min(84, dim))
    return dim, dim
end

-- =============================================================================
-- HOST: round orchestration
-- =============================================================================
local function role_map()
    local m = {}
    for id, p in pairs(players) do
        m[id] = p.in_game and p.role or 0
    end
    return m
end

local function hider_list()
    local list = {}
    for _, id in ipairs(connected) do
        local p = players[id]
        if p and p.in_game and p.role == 2 then table.insert(list, id) end
    end
    return list
end

local function scoreboard()
    local arr = {}
    for _, id in ipairs(connected) do
        local p = players[id]
        if p then table.insert(arr, { steam_id = id, name = p.name, score = p.score }) end
    end
    table.sort(arr, function(a, b) return a.score > b.score end)
    return arr
end

local function score_map()
    local m = {}
    for id, p in pairs(players) do m[id] = p.score end
    return m
end

local function broadcast_stats()
    local alive = count(function(p) return p.in_game and p.role == 2 and p.alive end)
    local total_h = count(function(p) return p.in_game and p.role == 2 end)
    local seekers = count(function(p) return p.in_game and p.role == 1 end)
    run_network_function(name, "stats_ALL", { alive, total_h, seekers, score_map() })
end

local function place_players()
    local seeker_spawn = run_function(GEN, "get_seeker_spawn", {})
    local spawns = run_function(GEN, "get_hider_spawns", {})
    local hi = 0
    local si = 0
    for _, id in ipairs(connected) do
        local p = players[id]
        if p and p.in_game then
            local pos
            if p.role == 1 then
                pos = string_to_vector2(seeker_spawn) + Vector2((si % 3) * 20 - 20, math.floor(si / 3) * 20 - 20)
                si = si + 1
            else
                local base = spawns[(hi % #spawns) + 1]
                pos = string_to_vector2(base) + Vector2((hi % 2) * 24 - 12, 0)
                hi = hi + 1
            end
            change_instantly({ entity_name = id, position = pos, linear_velocity = Vector2(0, 0), rotation = 0 })
        end
    end
end

function start_round(r)
    if not IS_HOST then return end
    round_no = r

    -- Resolve this round's roles + counts.
    for _, id in ipairs(connected) do
        local p = players[id]
        if p and p.in_game then
            p.role = role_of(p.group, r)
            p.alive = (p.role == 2) -- only hiders can be "caught"; seekers stay active
        end
    end
    local n_h = count(function(p) return p.in_game and p.role == 2 end)
    local n_s = count(function(p) return p.in_game and p.role == 1 end)
    map_w, map_h = compute_map_size(n_h, n_s)
    -- `seed` is the host-chosen match seed (set in host_begin). Both rounds of a
    -- match share it, so the map is the same for round 1 and the swapped round 2.

    -- Build the world: host locally, clients over the network (deterministic).
    local cfg = { seed = seed, w = map_w, h = map_h, hiders = n_h }
    run_function(GEN, "generate", { cfg })
    run_network_function(name, "world_gen_CLIENT", { seed, map_w, map_h, n_h })

    place_players()

    -- Apply role visuals + refresh HUD everywhere (including host).
    run_network_function(name, "set_roles_ALL", { role_map(), r, hider_list() })

    -- Seekers are free to roam the whole map from the start (to learn the layout),
    -- so open the door immediately - but hide each side from the other so nobody
    -- can actually be spotted during this phase.
    run_function(GEN, "open_room", {})
    run_network_function(name, "open_room_CLIENT", {})
    run_network_function(name, "set_hidden_phase_ALL", { true, connected })

    run_network_function(name, "banner_ALL", {
        "Round " .. r .. "/" .. ROUNDS .. " (seed " .. seed .. ") - roam, hide & paint! "
        .. "Hunt begins in " .. HIDE_LOCK .. "s", 5 })
    broadcast_stats()

    phase = "hiding"
    start_timer({ timer_id = "hs_hidelock", entity_name = name, function_name = "hide_lock_done",
        wait_time = HIDE_LOCK, duration = HIDE_LOCK })
    local pre_wait = math.max(1, HIDE_LOCK - PRE_LOCK_WARN)
    start_timer({ timer_id = "hs_prelock", entity_name = name, function_name = "pre_lock_seekers",
        wait_time = pre_wait, duration = pre_wait })
    start_time_display()
end

-- =============================================================================
-- HOST: on-screen round/phase countdown (the _8DAdEh... label everyone sees)
-- =============================================================================

-- Repeats every second for as long as hiding/seeking is active, reading however
-- much time the ACTIVE phase timer (hs_hidelock or hs_seek) has left rather than
-- tracking a second, separate countdown - one source of truth for "time left".
function start_time_display()
    if not IS_HOST then return end
    start_timer({ timer_id = "hs_time_tick", entity_name = name, function_name = "time_tick",
        wait_time = 1.0 }) -- no duration: repeats until stop_timer'd (see time_tick's else)
end

function time_tick(args)
    if not IS_HOST then return end
    local timer_id = nil
    if phase == "hiding" then
        timer_id = "hs_hidelock"
    elseif phase == "seeking" then
        timer_id = "hs_seek"
    else
        stop_timer("hs_time_tick")
        run_network_function(name, "time_display_ALL", { "" })
        return
    end
    local data = get_timer_data(timer_id)
    local secs = math.max(0, math.ceil(tonumber(data.time_left) or 0))
    local mm = math.floor(secs / 60)
    local ss = secs % 60
    run_network_function(name, "time_display_ALL", { string.format("%d:%02d", mm, ss) })
end

function time_display_ALL(sender_id, text)
    run_function(UI, "on_time_display", { text })
end

-- Called PRE_LOCK_WARN seconds before the hunt: pull every seeker back into their
-- room and reseal the door, so the hunt always starts from a fresh, fair position
-- (and hiders never get to see where seekers scattered to while roaming).
function pre_lock_seekers()
    if not IS_HOST or phase ~= "hiding" then return end
    local spawn = run_function(GEN, "get_seeker_spawn", {})
    local si = 0
    for _, id in ipairs(connected) do
        local p = players[id]
        if p and p.in_game and p.role == 1 then
            local pos = string_to_vector2(spawn) + Vector2((si % 3) * 20 - 20, math.floor(si / 3) * 20 - 20)
            change_instantly({ entity_name = id, position = pos, linear_velocity = Vector2(0, 0), rotation = 0 })
            si = si + 1
        end
    end
    run_function(GEN, "seal_room", {})
    run_network_function(name, "reseal_room_CLIENT", {})
    run_network_function(name, "lock_seekers_ALL", {})
    run_network_function(name, "banner_ALL", { "Seekers return to the room - hunt begins in " .. PRE_LOCK_WARN .. "s!", 4 })
end

function hide_lock_done(args)
    if not IS_HOST or phase ~= "hiding" then return end
    stop_timer("hs_prelock")
    phase = "seeking"
    seek_started = now()
    run_function(GEN, "open_room", {})
    run_network_function(name, "open_room_CLIENT", {})
    run_network_function(name, "release_seekers_ALL", {})
    run_network_function(name, "set_hidden_phase_ALL", { false, connected })
    run_network_function(name, "banner_ALL", { "Seekers released! Hunt begins!", 4 })

    start_timer({ timer_id = "hs_seek", entity_name = name, function_name = "seek_done",
        wait_time = SEEK_TIME, duration = SEEK_TIME })
    schedule_whistle()
end

function seek_done(args)
    if not IS_HOST or phase ~= "seeking" then return end
    end_round("time")
end

-- Randomised taunt: a random living hider whistles so seekers get a rough bearing.
function schedule_whistle()
    if not IS_HOST or phase ~= "seeking" then return end
    local wait = rng_range(WHISTLE_MIN, WHISTLE_MAX)
    start_timer({ timer_id = "hs_whistle", entity_name = name, function_name = "do_whistle",
        wait_time = wait, duration = wait })
end

function do_whistle(args)
    if not IS_HOST or phase ~= "seeking" then return end
    local alive = {}
    for _, id in ipairs(connected) do
        local p = players[id]
        if p and p.in_game and p.role == 2 and p.alive then table.insert(alive, id) end
    end
    if #alive > 0 then
        local target = alive[rng_range(1, #alive)]
        local pos = get_value("", target, "position")
        if pos then run_network_function(name, "whistle_ALL", { pos }) end
    end
    schedule_whistle()
end

-- =============================================================================
-- HOST: shooting (server-authoritative raycast + cooldown)
-- =============================================================================
function shoot_HOST(sender_id, aim_x, aim_y)
    if not IS_HOST or phase ~= "seeking" then return end
    local shooter = players[sender_id]
    if not shooter or not shooter.in_game or shooter.role ~= 1 then return end

    local t = now()
    if last_shot[sender_id] and (t - last_shot[sender_id]) < SHOOT_COOLDOWN then return end
    last_shot[sender_id] = t

    local from = get_value("", sender_id, "position")
    if not from then return end
    local aim = Vector2(aim_x, aim_y)
    local dir = aim - from
    if dir.x == 0 and dir.y == 0 then dir = Vector2(1, 0) end

    -- Hit walls (layer 1) and player bodies (layer 2); ignore the shooter itself.
    local hit = raycast({
        from = from,
        direction = dir,
        length = SHOOT_RANGE,
        collision_mask = { 1, 2 },
        exclude = { sender_id },
    })

    run_network_function(name, "shot_ALL", { from, hit.position })

    if hit.hit then
        local victim = players[hit.collider]
        if victim and victim.in_game and victim.role == 2 and victim.alive then
            victim.alive = false
            -- Seeker: earlier catch = more; hider: later catch = more.
            local elapsed = math.max(0, t - seek_started)
            local frac = math.max(0, math.min(1, 1 - elapsed / SEEK_TIME))
            shooter.score = shooter.score + CATCH_BASE + math.floor(CATCH_MAX * frac)
            victim.score = victim.score + math.floor(SURVIVE_MAX * (elapsed / SEEK_TIME))

            run_network_function(name, "caught_ALL", { hit.collider, sender_id, shooter.name, victim.name })
            broadcast_stats()

            if count(function(p) return p.in_game and p.role == 2 and p.alive end) == 0 then
                end_round("all_caught")
            end
        end
    end
end

-- =============================================================================
-- HOST: end of round / game
-- =============================================================================
function end_round(reason)
    if not IS_HOST then return end
    phase = "round_end"
    stop_timer("hs_seek")
    stop_timer("hs_whistle")

    -- Everyone who was never caught gets the full survival reward.
    for _, id in ipairs(connected) do
        local p = players[id]
        if p and p.in_game and p.role == 2 and p.alive then
            p.score = p.score + SURVIVE_MAX + SURVIVE_BONUS
        end
    end
    broadcast_stats()
    run_network_function(name, "banner_ALL", { "Round " .. round_no .. " over!", 4 })

    start_timer({ timer_id = "hs_gap", entity_name = name, function_name = "after_round",
        wait_time = ROUND_GAP, duration = ROUND_GAP })
end

function after_round(args)
    if not IS_HOST then return end
    if round_no < ROUNDS then
        start_round(round_no + 1)
    else
        end_game()
    end
end

-- Match over: show the podium + open the map vote for players and the seed panel
-- for the host. Nothing auto-restarts; the host chooses the next map/seed.
function end_game()
    if not IS_HOST then return end
    phase = "gameover"
    votes = {}
    for _, id in ipairs(connected) do
        local p = players[id]
        if p then p.role = 0 end
    end
    run_network_function(name, "set_roles_ALL", { role_map(), 0, {} })
    run_network_function(name, "game_over_ALL", { scoreboard(), seed })
    broadcast_stats()
    refresh_host_setup()
end

-- =============================================================================
-- HOST: seed panel + map vote
-- =============================================================================

-- A random, shareable seed in the valid range.
local function random_seed()
    rng_seed(now() + #connected + rng_int())
    return rng_int()
end

-- (Re)show the host-only seed panel. Same panel at first start and after a match;
-- post-match it also carries the map vote tally so the host can honour it.
function refresh_host_setup()
    if not IS_HOST then return end
    if phase ~= "lobby" and phase ~= "gameover" and phase ~= "preview" then return end
    local same, new = 0, 0
    for _, v in pairs(votes) do
        if v == "same" then same = same + 1 elseif v == "new" then new = new + 1 end
    end
    run_function(UI, "show_host_setup", { seed, phase, #connected, MIN_PLAYERS, same, new })
end

-- This manager is a STATIC network singleton, so it comes online AFTER the host's
-- own _on_user_initialized has already fired - meaning it never hears about the
-- host that way. Bootstrap on startup by enumerating the users that already exist
-- (they are tagged "user"). Future joiners still arrive via _on_user_initialized.
bootstrapped = false
function host_bootstrap()
    if not IS_HOST or bootstrapped then return end
    bootstrapped = true
    for _, uid in ipairs(get_entity_names_by_tag("user")) do
        if not players[uid] then
            local nick = get_value("", uid, "nickname")
            if type(nick) ~= "string" or nick == "" then nick = uid end
            players[uid] = { name = nick, group = 0, role = 0, score = 0, alive = false, in_game = false }
            table.insert(connected, uid)
        end
    end
    run_network_function(name, "set_roles_ALL", { role_map(), round_no, hider_list() })
    broadcast_stats()
    refresh_host_setup()
end

-- Called by the host's own UI. seed_arg <= 0 means "pick a fresh random seed".
function host_begin(seed_arg)
    if not IS_HOST then return end
    -- Close the setup panel immediately (a direct same-peer call, no network
    -- round-trip) the instant the host acts - it must never linger on screen
    -- once a seed/round has actually been chosen.
    run_function(UI, "close_host_setup", {})
    stop_all_timers()
    local s = math.floor(tonumber(seed_arg) or 0)
    if s <= 0 then s = random_seed() end
    seed = s
    votes = {}
    round_no = 0
    for _, id in ipairs(connected) do
        local p = players[id]
        if p then p.score = 0; p.in_game = true; p.role = 0; p.alive = false end
    end

    if #connected >= MIN_PLAYERS then
        rng_seed(seed) -- tie the team split to the seed too (reproducible)
        assign_groups()
        start_round(1)
    else
        -- Not enough players for a match: still build the world so the host can
        -- roam/preview it (everyone becomes a free hider, no hunt, no scoring).
        map_w, map_h = compute_map_size(math.max(1, #connected), 1)
        run_function(GEN, "generate", { { seed = seed, w = map_w, h = map_h, hiders = #connected } })
        run_network_function(name, "world_gen_CLIENT", { seed, map_w, map_h, #connected })
        run_function(GEN, "open_room", {})
        run_network_function(name, "open_room_CLIENT", {})
        phase = "preview"
        for _, id in ipairs(connected) do
            if players[id] then players[id].role = 2; players[id].alive = true end
        end
        place_players()
        run_network_function(name, "set_roles_ALL", { role_map(), 0, hider_list() })
        run_network_function(name, "banner_ALL", { "Preview (seed " .. seed .. ") - waiting for "
            .. (MIN_PLAYERS - #connected) .. " more to start the hunt.", 5 })
        broadcast_stats()
        -- The panel was already closed above; preview is a "gameplay" state (the
        -- host is exploring), so it stays hidden. It reopens naturally once the
        -- match ends (end_game) or is force-stopped by a disconnect.
    end
end

-- Any player casts a map vote after a match; the host tallies + rebroadcasts.
function cast_vote_HOST(sender_id, choice)
    if not IS_HOST or phase ~= "gameover" then return end
    if choice ~= "same" and choice ~= "new" then return end
    votes[sender_id] = choice
    local same, new = 0, 0
    for _, v in pairs(votes) do
        if v == "same" then same = same + 1 elseif v == "new" then new = new + 1 end
    end
    run_network_function(name, "vote_update_ALL", { same, new })
    refresh_host_setup()
end

function vote_update_ALL(sender_id, same, new)
    run_function(UI, "on_vote_update", { same, new })
end

-- =============================================================================
-- ALL-peer mirror + UI fan-out (runs on host and clients)
-- =============================================================================
function world_gen_CLIENT(sender_id, s, w, h, hiders)
    run_function(GEN, "generate", { { seed = s, w = w, h = h, hiders = hiders } })
end

function open_room_CLIENT(sender_id)
    run_function(GEN, "open_room", {})
end

function reseal_room_CLIENT(sender_id)
    run_function(GEN, "seal_room", {})
end

function lock_seekers_ALL(sender_id)
    run_function(LOCAL_STEAM_ID, "on_lock_view", {})
end

function release_seekers_ALL(sender_id)
    run_function(LOCAL_STEAM_ID, "on_release_view", {})
end

-- Cross-team invisibility during the roam/hide phase. roster is the full
-- connected-players array (passed explicitly since only the HOST's "connected"
-- list is populated - clients need it as data to iterate the same set).
function set_hidden_phase_ALL(sender_id, hidden, roster)
    for _, uid in ipairs(roster) do
        run_function(uid, "on_phase_hidden", { hidden })
    end
end

function set_roles_ALL(sender_id, roles, r, hiders)
    cl_phase = "roles"
    local local_role = roles[LOCAL_STEAM_ID] or 0
    for id, role in pairs(roles) do
        run_function(id, "apply_role", { { role = role, round = r } })
    end
    run_function(UI, "on_roles", { local_role, hiders, r })
end

function stats_ALL(sender_id, hider_alive, hider_total, seekers, scores)
    run_function(UI, "on_stats", { hider_alive, hider_total, seekers, scores[LOCAL_STEAM_ID] or 0 })
end

function banner_ALL(sender_id, text, secs)
    run_function(UI, "on_banner", { text, secs })
end

function caught_ALL(sender_id, hider_id, seeker_id, seeker_name, hider_name)
    run_function(hider_id, "on_caught", {})
    run_function(UI, "on_caught", { hider_name, seeker_name, hider_id == LOCAL_STEAM_ID })
end

function shot_ALL(sender_id, from_pos, to_pos)
    local lname = "tracer_" .. tostring(sender_id)
    set_line({ name = lname, start_position = from_pos, end_position = to_pos,
        color = Color(1, 0.25, 0.2, 0.9), width = 2, z_index = 50 })
    run_function(name, "clear_tracer", { lname }, 0.15)
end

function clear_tracer(lname)
    if line_exists(lname) then destroy_line(lname) end
end

function whistle_ALL(sender_id, pos)
    -- is_2d=true -> AudioStreamPlayer2D: Godot attenuates automatically based on
    -- distance from the camera (the implicit 2D listener), out to max_distance.
    -- Reduced further per request (16 tiles = 256px at the current 16px grid).
    set_audio({ stream_path = "whistle", is_2d = true, position = pos, max_distance = 256, volume = 2 })
end

function game_over_ALL(sender_id, board, match_seed)
    cl_phase = "gameover"
    run_function(UI, "on_game_over", { board, match_seed })
    -- Non-host players get the map vote; the host uses its seed panel instead.
    if not IS_HOST then
        run_function(UI, "show_vote", { match_seed })
    end
end

-- =============================================================================
-- Player bookkeeping (HOST authoritative)
-- =============================================================================
function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end
    if not players[steam_id] then
        players[steam_id] = { name = nickname, group = 0, role = 0, score = 0, alive = false, in_game = false }
    else
        players[steam_id].name = nickname
    end
    local found = false
    for _, id in ipairs(connected) do if id == steam_id then found = true end end
    if not found then table.insert(connected, steam_id) end

    if phase == "preview" then
        -- A late joiner during a solo preview: if we now have enough players,
        -- promote it straight into a real match with the SAME seed - no need
        -- for the host to press Start again.
        if #connected >= MIN_PLAYERS then
            rng_seed(seed)
            assign_groups()
            start_round(1)
            return
        end
        -- Still short-handed: fold them into the preview as another free hider
        -- (without disturbing anyone already exploring - place only this one).
        players[steam_id].in_game = true
        players[steam_id].role = 2
        players[steam_id].alive = true
        run_network_function(name, "world_gen_CLIENT", { seed, map_w, map_h,
            count(function(p) return p.in_game and p.role == 2 end) }, steam_id)
        run_network_function(name, "open_room_CLIENT", {}, steam_id)
        local spawns = run_function(GEN, "get_hider_spawns", {})
        if spawns and #spawns > 0 then
            local hi = count(function(p) return p.in_game and p.role == 2 end) - 1
            local base = spawns[(hi % #spawns) + 1]
            change_instantly({ entity_name = steam_id, position = string_to_vector2(base),
                linear_velocity = Vector2(0, 0), rotation = 0 })
        end
        run_network_function(name, "set_roles_ALL", { role_map(), 0, hider_list() })
    elseif phase == "hiding" or phase == "seeking" then
        -- Deterministic: a late joiner only needs the seed to rebuild the live world.
        run_network_function(name, "world_gen_CLIENT", { seed, map_w, map_h,
            count(function(p) return p.in_game and p.role == 2 end) }, steam_id)
        if phase == "seeking" then
            run_network_function(name, "open_room_CLIENT", {}, steam_id)
        end
        run_network_function(name, "set_roles_ALL", { role_map(), round_no, hider_list() }, steam_id)
    else
        -- Lobby / game-over: refresh everyone so the hider-only buttons hide.
        run_network_function(name, "set_roles_ALL", { role_map(), round_no, hider_list() })
    end
    broadcast_stats()
    -- No panel refresh here on purpose: the host's setup panel is only shown/
    -- updated by deliberate actions (bootstrap, pressing a button, voting), not
    -- by passive join/leave events.
end

function _on_user_disconnected(steam_id, nickname)
    if not IS_HOST then return end
    players[steam_id] = nil
    list_remove(connected, steam_id)
    last_shot[steam_id] = nil

    votes[steam_id] = nil
    if (phase == "hiding" or phase == "seeking" or phase == "round_end") and #connected < MIN_PLAYERS then
        stop_all_timers()
        phase = "gameover"
        round_no = 0
        for _, p in pairs(players) do p.role = 0 end
        run_network_function(name, "banner_ALL", { "Not enough players - match stopped.", 4 })
        run_network_function(name, "set_roles_ALL", { role_map(), 0, {} })
        -- A deliberate state change (the match was just interrupted), unlike a
        -- plain join/leave - show the host a fresh seed panel to start over.
        refresh_host_setup()
    elseif phase == "seeking" then
        if count(function(p) return p.in_game and p.role == 2 and p.alive end) == 0 then
            end_round("all_caught")
        end
    end
    broadcast_stats()
end

-- Runs once when this singleton comes online (on every peer). The host registers
-- the already-connected players and opens the seed panel a moment later, once the
-- initial user entities are guaranteed to be spawned.
if IS_HOST then
    start_timer({ timer_id = "hs_boot", entity_name = name, function_name = "host_bootstrap",
        wait_time = 0.4, duration = 0.4 })
end

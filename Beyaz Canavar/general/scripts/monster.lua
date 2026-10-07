network_mode = 2
lock_rotation = true
linear_damp = 0
friction = 0
speed = 62

-- =============================================================================
-- Beyaz Canavar - the NPC monster (DYNAMIC: the host simulates it, everyone
-- sees it). One exists from the start, lying asleep in the detention room.
--
-- Host AI, re-evaluated every 0.2 s:
--   patrol  walk (navigate_to, A*) to a random room / corridor point, pause, repeat
--   chase   a human it can SEE (has_line_of_sight, within SIGHT tiles) - with the
--           scream ready it screams once the human is within 3 tiles (stuns
--           humans within 3 tiles), then follows the player around corners; LOST_SECONDS without sight or
--           LOSE_DISTANCE away and it goes back to patrolling
--   busy    sleeping, waking up, screaming or eating: it stands still
-- The catch itself is checked by game_manager for every monster alike.
-- Animation runs locally on every peer through monster_anim.lua; the current
-- one-shot animation is mirrored in `anim_state` so a late joiner sees it too.
-- =============================================================================

local TILE = 32
local SIGHT = 7 * TILE
local LOSE_DISTANCE = 16 * TILE
local LOST_SECONDS = 5
local SCREAM_REACH = 3 * TILE
local ANIM_FPS = 8.4       -- monster_anim.lua's FPS
local AI_STEP = 0.2

add_tag(name, "monster")
add_tag(name, "fog_hide")
set_collision({ parent_name = name, name = "col", shape = "circle", size = 8,
    collision_layer = { 3 }, collision_mask = { 1 } })

run_function("-gm", "register_npc", { name })
run_function("-anim", "setup", { name })

-- What the monster looks like right now, for peers that join later.
local function apply_anim_state()
    local state = get_value("", name, "anim_state") or "sleep"
    if state == "sleep" then
        run_function("-anim", "hold", { name, "wake_up", 1 })
    else
        run_function("-anim", "walk", { name })
    end
end
apply_anim_state()

-- Host state.
local mode = "sleep"      -- sleep | idle | patrol | chase | busy
local target = ""
local last_seen = 0
local clock = 0
local idle_until = 0
local busy_until = 0
local points = {}

local function set_anim_state(state)
    set_value("", name, "anim_state", state)
end

function sleep_ALL(sender_id)
    run_function("-anim", "hold", { name, "wake_up", 1 })
end

function walk_ALL(sender_id)
    run_function("-anim", "walk", { name })
end

-- Lobby: lying on the floor, frozen, harmless.
function host_sleep(pos)
    if not IS_HOST then return end
    navigate_to(name, "")
    mode = "sleep"
    target = ""
    unfreeze_entity(name)
    change_instantly({ entity_name = name, position = pos, linear_velocity = Vector2(0, 0) })
    freeze_entity(name)
    set_anim_state("sleep")
    run_network_function(name, "sleep_ALL", {})
end

-- After the wake-up cutscene: teleported into the school, the hunt begins.
function host_begin_hunt(pos)
    if not IS_HOST then return end
    unfreeze_entity(name)
    change_instantly({ entity_name = name, position = pos, linear_velocity = Vector2(0, 0) })
    set_value("", name, "speed", speed)
    set_anim_state("walk")
    run_network_function(name, "walk_ALL", {})
    points = run_function("-gen", "get_patrol_points") or {}
    mode = "idle"
    idle_until = clock + 1.5
end

-- game_manager: we caught someone - stand still while eating.
function host_eat(seconds)
    if not IS_HOST then return end
    navigate_to(name, "")
    mode = "busy"
    busy_until = clock + seconds
    target = ""
end

local function my_pos()
    return get_value("", name, "position")
end

local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- Closest human we can actually see.
local function spot()
    local me = my_pos()
    if not me then return "", math.huge end
    local best, best_d = "", math.huge
    for _, h in ipairs(run_function("-gm", "get_humans") or {}) do
        local hp = get_value("", h, "position")
        if hp then
            local d = dist(me, hp)
            if d <= SIGHT and d < best_d and has_line_of_sight(me, hp) then
                best, best_d = h, d
            end
        end
    end
    return best, best_d
end

local function patrol()
    if #points == 0 then points = run_function("-gen", "get_patrol_points") or {} end
    if #points == 0 then return end
    local me = my_pos()
    -- A random point that is not right next to us.
    for _ = 1, 6 do
        local p = points[math.random(1, #points)]
        if not me or dist(me, p) > 6 * TILE then
            if navigate_to(name, p, { stop_distance = 12 }) then
                mode = "patrol"
                return
            end
        end
    end
    mode = "idle"
    idle_until = clock + 1
end

local function try_scream()
    if run_function("-gm", "can_scream", { name }) then
        if run_function("-gm", "do_scream", { name }) then
            navigate_to(name, "")
            mode = "busy"
            busy_until = clock + 14 / ANIM_FPS
            return true
        end
    end
    return false
end

local function chase(h)
    target = h
    last_seen = clock
    mode = "chase"
    navigate_to(name, h, { stop_distance = 4 })
end

function ai_step(args)
    if not IS_HOST then return end
    clock = clock + AI_STEP
    local phase = get_value("", "-gm", "phase")
    if phase ~= "playing" and phase ~= "escape" then return end
    if mode == "sleep" then return end
    if mode == "busy" then
        if clock < busy_until then return end
        if target ~= "" and entity_exists(target) then chase(target) else mode = "idle" end
        return
    end
    if run_function("-gm", "is_busy", { name }) then return end

    local seen, d = spot()
    if mode == "chase" then
        local alive = false
        for _, h in ipairs(run_function("-gm", "get_humans") or {}) do
            if h == target then alive = true end
        end
        local tp = alive and get_value("", target, "position") or nil
        local me = my_pos()
        if not tp or not me then
            navigate_to(name, "")
            mode = "idle"
            idle_until = clock + 1
            return
        end
        local td = dist(me, tp)
        if has_line_of_sight(me, tp) and td <= LOSE_DISTANCE then last_seen = clock end
        if clock - last_seen > LOST_SECONDS or td > LOSE_DISTANCE then
            navigate_to(name, "")
            target = ""
            mode = "idle"
            idle_until = clock + 2
            return
        end
        if td <= SCREAM_REACH and clock - last_seen < 0.3 and try_scream() then return end
        -- A closer visible human steals the chase.
        if seen ~= "" and seen ~= target and d < td * 0.6 then chase(seen) end
        return
    end

    if seen ~= "" then
        target = seen
        last_seen = clock
        if d <= SCREAM_REACH and try_scream() then return end
        chase(seen)
        return
    end
    if mode == "idle" and clock >= idle_until then patrol() end
end

function _on_navigation_finished(reached)
    if not IS_HOST then return end
    if mode == "patrol" then
        mode = "idle"
        idle_until = clock + 1 + math.random() * 2
    elseif mode == "chase" then
        -- Lost the path to the target: look around, the AI step decides again.
        mode = "idle"
        idle_until = clock + 0.5
    end
end

if IS_HOST then
    math.randomseed(math.floor(get_os_time_unix()))
    start_timer({ timer_id = "bc_ai_" .. name, entity_name = name, function_name = "ai_step", wait_time = AI_STEP })
    set_anim_state("sleep")
    freeze_entity(name)
end

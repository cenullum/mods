network_mode = 2 -- the host walks it around, so every peer needs its position streamed
lock_rotation = true
linear_damp = 0
friction = 0 -- slide along walls instead of sticking

-- =============================================================================
-- MineBlockLand - the Guardian of the Isle (day-7 boss).
--
-- Bullet-hell patterns: expanding rings, a rotating spiral and aimed volleys,
-- plus a huge 3-second telegraphed slam you must walk out of and a meteor
-- shower of small telegraphed impacts scattered around it. All simulation
-- is host-side; bullets are fire-and-forget entities (one spawn message each,
-- no per-frame sync). Below 30% HP it gets angry and everything speeds up.
-- =============================================================================

add_tag(name, "npc")

local SPEED = 6
local SIZE = 64
local BULLET_DMG = 12
local BULLET_SPEED = 65
local BULLET_LIFE = 5.0
local RING_BULLETS = 14
local VOLLEY_BULLETS = 5
local VOLLEY_SPREAD = 0.5           -- radians across the whole fan
local PATTERN_SECONDS = 2.6
local SPIRAL_STEP_SECONDS = 0.12
local SPIRAL_SHOTS = 20
local SLAM_SECONDS = 9.0
local SLAM_RADIUS = 90
local SLAM_WINDUP = 3.0
local SLAM_DMG = 45
local METEOR_SECONDS = 7.0          -- how often a shower starts
local METEOR_COUNT = 6              -- impacts per shower
local METEOR_RADIUS = 26            -- much smaller than the slam
local METEOR_WINDUP = 1.1           -- shorter warning than the slam too
local METEOR_DMG = 18
local METEOR_MIN_RANGE = 40         -- ring around the boss the impacts land in
local METEOR_MAX_RANGE = 170
local METEOR_STAGGER = 0.18         -- seconds between one impact and the next
local ENRAGE_FRACTION = 0.3
local ENRAGE_EXTRA_BULLETS = 6
local HP_BAR_WIDTH = 56

local max_hp = hp
local pattern_index = 0
local spiral_angle = 0
local spiral_left = 0
local target = ""

set_value("", name, "speed", SPEED)

set_image({ parent_name = name, name = "body", image_path = "items/15x15_octopus",
    scale = Vector2(SIZE, SIZE), z_index = 2 })
set_collision({ parent_name = name, name = "col", shape = "circle", size = SIZE / 2,
    collision_layer = { 3 }, collision_mask = { 1 } })
set_progress_bar({ parent_name = name, name = "hpbar", position = Vector2(-HP_BAR_WIDTH / 2, -SIZE / 2 - 10),
    size = Vector2(HP_BAR_WIDTH, 5), min_value = 0, max_value = max_hp, value = hp,
    show_percentage = false, modulate = Color(228 / 255, 59 / 255, 68 / 255, 1), z_index = 10 })

local function enraged()
    return hp <= max_hp * ENRAGE_FRACTION
end

local function fire(angle, speed_override)
    local my_pos = get_value("", name, "position")
    if not my_pos then return end
    spawn_entity_host({ t = "bullet", p = my_pos, r = angle, dmg = BULLET_DMG,
        speed = speed_override or BULLET_SPEED, life = BULLET_LIFE })
end

-- =============================================================================
-- Host AI.
-- =============================================================================

function retarget()
    if not IS_HOST then return end
    local nearest = get_nearest_entity_by_tag(name, "alive")
    target = (nearest and nearest.name) and nearest.name or ""
    go_to_target(name, target, false)
end

function run_pattern()
    if not IS_HOST then return end
    pattern_index = pattern_index + 1
    local which = pattern_index % 3
    if which == 0 then
        -- Ring: bullets in every direction (more when enraged).
        local count = RING_BULLETS + (enraged() and ENRAGE_EXTRA_BULLETS or 0)
        for i = 1, count do
            fire(2 * math.pi * i / count)
        end
    elseif which == 1 then
        -- Spiral: a rotating emitter driven by its own little timer.
        spiral_left = SPIRAL_SHOTS + (enraged() and ENRAGE_EXTRA_BULLETS or 0)
        start_timer({ timer_id = "spiral" .. name, entity_name = name,
            function_name = "spiral_step", wait_time = SPIRAL_STEP_SECONDS,
            duration = SPIRAL_STEP_SECONDS * spiral_left })
    else
        -- Volley: a tight fan aimed at the current target.
        local my_pos = get_value("", name, "position")
        local target_pos = target ~= "" and get_value("", target, "position") or nil
        if my_pos and target_pos then
            local aim = math.atan(target_pos.y - my_pos.y, target_pos.x - my_pos.x)
            for i = 1, VOLLEY_BULLETS do
                local offset = VOLLEY_SPREAD * ((i - 1) / (VOLLEY_BULLETS - 1) - 0.5)
                fire(aim + offset, BULLET_SPEED * 1.3)
            end
        end
    end
end

function spiral_step()
    if not IS_HOST or spiral_left <= 0 then return end
    spiral_left = spiral_left - 1
    spiral_angle = spiral_angle + 0.5
    fire(spiral_angle)
    fire(spiral_angle + math.pi)
end

function slam()
    if not IS_HOST then return end
    local my_pos = get_value("", name, "position")
    if not my_pos then return end
    run_function("-combat", "start_telegraph", { {
        x = my_pos.x, y = my_pos.y, shape = "circle", r = SLAM_RADIUS,
        windup = SLAM_WINDUP, dmg = SLAM_DMG, targets = "players", attacker = name } })
end

-- Meteor shower: a handful of small telegraphs rain down on random spots
-- around the boss, one every METEOR_STAGGER seconds, so the whole arena
-- becomes unsafe for a moment instead of one big circle under the boss.
-- Each drop is its own delayed call - if the boss dies mid-shower the
-- pending calls simply never fire.
function meteor_shower()
    if not IS_HOST then return end
    local my_pos = get_value("", name, "position")
    if not my_pos then return end
    local count = METEOR_COUNT + (enraged() and 3 or 0)
    for i = 1, count do
        local angle = math.random() * 2 * math.pi
        local range = METEOR_MIN_RANGE + math.random() * (METEOR_MAX_RANGE - METEOR_MIN_RANGE)
        run_function(name, "meteor_drop",
            { my_pos.x + math.cos(angle) * range, my_pos.y + math.sin(angle) * range },
            (i - 1) * METEOR_STAGGER)
    end
end

function meteor_drop(x, y)
    if not IS_HOST then return end
    run_function("-combat", "start_telegraph", { {
        x = x, y = y, shape = "circle", r = METEOR_RADIUS,
        windup = METEOR_WINDUP, dmg = METEOR_DMG, targets = "players", attacker = name } })
end

if IS_HOST then
    retarget()
    start_timer({ timer_id = "brt" .. name, entity_name = name,
        function_name = "retarget", wait_time = 3.0 })
    start_timer({ timer_id = "bpat" .. name, entity_name = name,
        function_name = "run_pattern", wait_time = PATTERN_SECONDS })
    start_timer({ timer_id = "bslam" .. name, entity_name = name,
        function_name = "slam", wait_time = SLAM_SECONDS })
    start_timer({ timer_id = "bmet" .. name, entity_name = name,
        function_name = "meteor_shower", wait_time = METEOR_SECONDS })
end

-- =============================================================================
-- Damage / defeat.
-- =============================================================================

function npc_take_damage(dmg_in, attacker, kb, angle)
    if not IS_HOST then return end
    hp = hp - dmg_in
    local my_pos = get_value("", name, "position")
    if my_pos then
        run_function("-combat", "show_damage", { my_pos.x, my_pos.y, dmg_in, "npc" })
    end
    if attacker and attacker ~= "" and has_tag(attacker, "user") then
        run_function("-gm", "add_stat", { attacker, "dmg_dealt", dmg_in })
    end
    run_network_function(name, "hp_bar_ALL", { hp })
    if hp <= 0 then
        if attacker and attacker ~= "" and has_tag(attacker, "user") then
            run_function("-gm", "add_stat", { attacker, "kills", 1 })
        end
        run_function("-gm", "on_boss_defeated", { { x = my_pos and my_pos.x, y = my_pos and my_pos.y } })
        destroy("", name)
    end
end

-- Everyone keeps the floating HP bar in sync (only sent when the boss is hit).
function hp_bar_ALL(sender_id, new_hp)
    hp = new_hp
    set_progress_bar({ parent_name = name, name = "hpbar", value = math.max(new_hp, 0) })
end

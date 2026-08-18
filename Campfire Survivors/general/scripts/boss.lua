lock_rotation = true
linear_damp = 0
friction = 0
network_mode = 2

-- =============================================================================
-- Campfire Survivors - the Guardian (30-minute boss).
--
-- Same fight as MineBlockLand's Guardian: expanding rings, a rotating spiral,
-- aimed volleys, one huge telegraphed slam you have to walk out of, and a
-- meteor shower of small telegraphed impacts scattered around it. All of the
-- simulation is host-side; the bullets are ordinary bandit_bullet entities
-- (one spawn message each, no per-frame sync). Below 30% HP it enrages and
-- every pattern gets extra projectiles.
--
-- Spawned by "-bm" with: h = total hp, wl = wave level index (damage scale).
-- =============================================================================

add_tag(name, "monster")  -- so player bullets and contact damage find it
add_tag(name, "boss")     -- ...and so the wave reset can spare it

local SPEED = 25
local SIZE = 64
local BULLET_SPEED = 65
local BULLET_FACTOR = 1.5
local RING_BULLETS = 14
local VOLLEY_BULLETS = 5
local VOLLEY_SPREAD = 0.5           -- radians across the whole fan
local PATTERN_SECONDS = 2.6
local SPIRAL_STEP_SECONDS = 0.12
local SPIRAL_SHOTS = 20
local SLAM_SECONDS = 9.0
local SLAM_RADIUS = 90
local SLAM_WINDUP = 3.0
local METEOR_SECONDS = 7.0
local METEOR_COUNT = 6
local METEOR_RADIUS = 26
local METEOR_WINDUP = 1.1
local METEOR_MIN_RANGE = 40
local METEOR_MAX_RANGE = 170
local METEOR_STAGGER = 0.18
local ENRAGE_FRACTION = 0.3
local ENRAGE_EXTRA_BULLETS = 6
local HP_BAR_WIDTH = 56

-- Base damage values, all scaled by the wave level the run reached.
local BASE_CONTACT_DMG = 6          -- applied per user damage tick (every 0.2s)
local BASE_BULLET_DMG = 12
local BASE_SLAM_DMG = 45
local BASE_METEOR_DMG = 18

wave_level = wl or 1
health = h
max_health = h
damage = BASE_CONTACT_DMG * wave_level  -- read by user.lua's check_monster_damage

local bullet_damage = BASE_BULLET_DMG * wave_level
local slam_damage = BASE_SLAM_DMG * wave_level
local meteor_damage = BASE_METEOR_DMG * wave_level

local pattern_index = 0
local spiral_angle = 0
local spiral_left = 0
local target = ""

set_value("", name, "speed", SPEED)

image_name = set_image({ parent_name = name, name = "body", image_path = "boss",
    scale = Vector2(SIZE, SIZE), z_index = 2 })
set_shader({ parent_name = name, image_name = image_name, shader_name = "circle",
    outline_color = Color(0.89, 0.23, 0.27, 1) })

set_collision({ parent_name = name, name = "col", shape = "circle", size = SIZE / 2,
    collision_layer = { 3 },   -- monster layer: player bullets and damage areas see it
    collision_mask = { 1, 3 } })

set_progress_bar({ parent_name = name, name = "hpbar",
    position = Vector2(-HP_BAR_WIDTH / 2, -SIZE / 2 - 10),
    size = Vector2(HP_BAR_WIDTH, 5), min_value = 0, max_value = max_health, value = health,
    show_percentage = false, modulate = Color(0.89, 0.23, 0.27, 1), z_index = 10 })

local function enraged()
    return health <= max_health * ENRAGE_FRACTION
end

local function fire(angle, speed_override)
    spawn_entity_host({
        t = "bandit_bullet",
        p = get_value("", name, "position"),
        r = angle,
        monster_id = name,
        damage = bullet_damage,
        speed = speed_override or BULLET_SPEED,
        factor = BULLET_FACTOR,
    })
end

-- =============================================================================
-- Host AI.
-- =============================================================================

function retarget()
    if not IS_HOST then return end
    local nearest = get_nearest_entity_by_tag(name, "alive")
    target = (nearest and nearest.name) and nearest.name or ""
    if target ~= "" then
        go_to_target(name, target, false)
    end
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
    run_function("-bm", "start_telegraph", { {
        x = my_pos.x, y = my_pos.y, shape = "circle", r = SLAM_RADIUS,
        windup = SLAM_WINDUP, dmg = slam_damage, attacker = name } })
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
    run_function("-bm", "start_telegraph", { {
        x = x, y = y, shape = "circle", r = METEOR_RADIUS,
        windup = METEOR_WINDUP, dmg = meteor_damage, attacker = name } })
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
--
-- Same signature as monster.lua's take_damage so bullet.lua needs no special
-- case, but the boss is far too heavy to be knocked around and it drops no XP.
-- =============================================================================

function take_damage(incoming_damage, knockback_amount, angle, player_id)
    if not IS_HOST then return end

    local actual_damage = math.min(incoming_damage, health)
    health = health - incoming_damage

    run_network_function(name, "show_damage_label_ALL", { actual_damage })
    if player_id and actual_damage > 0 then
        run_function("-stats", "add_player_stat", { player_id, "damage_dealt", actual_damage })
    end
    run_network_function(name, "hp_bar_ALL", { health })

    if health <= 0 then
        if player_id then
            run_function("-stats", "add_player_stat", { player_id, "enemies_killed", 1 })
        end
        run_function("-bm", "on_boss_defeated", { player_id or "" })
        destroy("", name)
    end
end

-- Everyone keeps the floating HP bar in sync (only sent when the boss is hit).
function hp_bar_ALL(sender_id, new_health)
    health = new_health
    set_progress_bar({ parent_name = name, name = "hpbar", value = math.max(new_health, 0) })
end

function show_damage_label_ALL(sender_id, damage_amount)
    local label_name = set_label({
        text = "-" .. tostring(math.floor(damage_amount)),
        outline_color = Color(0, 0, 0, 1),
        outline_size = 2,
        font_color = Color(1, 0.85, 0.3, 1),
        font_size = 12,
        position = position,
        size = Vector2(64, 16),
    })
    -- The timer lives on "-mg" because the boss can be destroyed before it fires.
    start_timer({
        entity_name = "-mg",
        function_name = "destroy_damage_label",
        extra_args = { label_name = label_name },
        wait_time = 2.0,
        duration = 2.0,
        timer_id = label_name .. "_timer"
    })
end

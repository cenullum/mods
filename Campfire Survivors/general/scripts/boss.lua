lock_rotation = true
linear_damp = 0
friction = 0
network_mode = 2

-- =============================================================================
-- Campfire Survivors - the Guardian (30-minute boss), fought in THREE PHASES.
--
-- You have to empty its health bar three times. Each phase is faster, hits
-- harder and unlocks another attack, so the fight teaches itself:
--
--   1. EASY    only the shotgun blast (one wide burst of projectiles).
--   2. MEDIUM  + omnidirectional rings and aimed volleys, + meteor showers.
--   3. HARD    + the rotating spiral and the huge telegraphed slam, and it
--              still enrages below 30% of this phase's health.
--
-- The health pool the director hands over is SPLIT across the phases (20/30/40
-- percent), so all three together are a bit cheaper than the old single bar -
-- the fight gets its length back from the phase breaks and the harder patterns
-- instead of from a longer grind.
--
-- All of the simulation is host-side; the bullets are ordinary bandit_bullet
-- entities (one spawn message each, no per-frame sync).
--
-- Spawned by "-bm" with: h = total hp across all phases, wl = wave level index.
-- =============================================================================

add_tag(name, "monster")  -- so player bullets and contact damage find it
add_tag(name, "boss")     -- ...and so the wave reset can spare it

local SIZE = 64
local BULLET_SPEED = 130
local BULLET_FACTOR = 1.5
local RING_BULLETS = 14
local VOLLEY_BULLETS = 5
local VOLLEY_SPREAD = 0.5           -- radians across the whole fan
local SHOTGUN_SPREAD = 1.15         -- much wider than a volley: it is a blast
local SPIRAL_STEP_SECONDS = 0.12
local SPIRAL_SHOTS = 20
local SLAM_RADIUS = 90
local SLAM_WINDUP = 3.0
local METEOR_RADIUS = 26
local METEOR_WINDUP = 1.1
-- Both scaled by sqrt(2) from the old 40/170 so the drop-zone annulus keeps
-- its shape but covers double the area.
local METEOR_MIN_RANGE = 57
local METEOR_MAX_RANGE = 240
local METEOR_STAGGER = 0.18
local ENRAGE_FRACTION = 0.3
local ENRAGE_EXTRA_BULLETS = 6
local HP_BAR_WIDTH = 56

-- =============================================================================
-- Per-phase tuning. Every table is indexed by the phase number (1..PHASE_COUNT),
-- so adding a fourth phase means adding one entry to each of these.
-- =============================================================================

local PHASE_COUNT = 3
local PHASE_HP_SHARE = { 0.20, 0.30, 0.40 }     -- fractions of the total pool
local PHASE_HP_MULTIPLIER = 1.5                 -- +50% health on top of that pool, every phase
local PHASE_SPEED = { 30, 42, 57 }              -- it chases harder every phase (+50% over base 20/28/38)
local PHASE_PATTERN_SECONDS = { 3.2, 2.5, 1.9 } -- ...and shoots more often
local PHASE_DAMAGE_SCALE = { 0.7, 1.0, 1.35 }
local PHASE_SHOTGUN_BULLETS = { 9, 12, 16 }
local PHASE_METEOR_COUNT = { 0, 8, 11 }  -- +50% over the old 0/5/7
-- 0 seconds = the phase does not have that attack at all.
local PHASE_METEOR_SECONDS = { 0, 8.0, 5.5 }
local PHASE_SLAM_SECONDS = { 0, 0, 8.0 }
-- The cycle each phase walks through, one entry per pattern timer tick.
local PHASE_PATTERNS = {
    { "shotgun" },
    { "shotgun", "ring", "volley" },
    { "shotgun", "ring", "spiral", "volley" },
}
-- Amber -> orange -> red, so you can read the phase off the outline alone.
local PHASE_COLOR = {
    Color(0.99, 0.76, 0.31, 1),
    Color(0.93, 0.49, 0.19, 1),
    Color(0.89, 0.23, 0.27, 1),
}
local PHASE_BREAK_SECONDS = 2.0     -- stunned pause between phases

-- Base damage values, all scaled by the wave level the run reached AND by the
-- phase (see refresh_damage).
local BASE_CONTACT_DMG = 6          -- applied per user damage tick (every 0.2s)
local BASE_BULLET_DMG = 12
local BASE_SLAM_DMG = 45
local BASE_METEOR_DMG = 18

wave_level = wl or 1
phase = 1
local total_health = h
local function phase_pool(index)
    return math.max(math.floor(total_health * PHASE_HP_SHARE[index] * PHASE_HP_MULTIPLIER), 1)
end

health = phase_pool(1)
max_health = health
damage = BASE_CONTACT_DMG * wave_level  -- read by user.lua's check_monster_damage

local bullet_damage = BASE_BULLET_DMG * wave_level
local slam_damage = BASE_SLAM_DMG * wave_level
local meteor_damage = BASE_METEOR_DMG * wave_level

local pattern_index = 0
local spiral_angle = 0
local spiral_left = 0
local target = ""
local phase_locked = false          -- true during the between-phase pause

image_name = set_image({ parent_name = name, name = "body", image_path = "boss",
    scale = Vector2(SIZE, SIZE), z_index = 2 })
set_shader({ parent_name = name, image_name = image_name, shader_name = "circle",
    outline_color = PHASE_COLOR[1] })

set_collision({ parent_name = name, name = "col", shape = "circle", size = SIZE / 2,
    collision_layer = { 3 },   -- monster layer: player bullets and damage areas see it
    collision_mask = { 1, 3 } })

set_progress_bar({ parent_name = name, name = "hpbar",
    position = Vector2(-HP_BAR_WIDTH / 2, -SIZE / 2 - 10),
    size = Vector2(HP_BAR_WIDTH, 5), min_value = 0, max_value = max_health, value = health,
    show_percentage = false, modulate = PHASE_COLOR[1], z_index = 10 })

-- Shows the current FIGHT PHASE (1..PHASE_COUNT), not the wave level - kept in
-- sync with the bar in phase_ALL below. Translated locally on each peer, same
-- as the phase banner: never sent over the network as resolved text.
set_label({ parent_name = name, name = "levellabel",
    text = string.format(translate("{boss_level_label}"), phase),
    outline_color = Color(0, 0, 0, 1), outline_size = 2,
    font_color = Color(1, 1, 1, 1), font_size = 14,
    position = Vector2(-HP_BAR_WIDTH / 2, -SIZE / 2 - 26),
    size = Vector2(HP_BAR_WIDTH, 14), horizontal_alignment = 1, z_index = 10 })

-- Only the final phase enrages - phases 1 and 2 end at 0 anyway, so an
-- "almost dead" bonus there would just be a second difficulty spike per phase.
local function enraged()
    return phase >= PHASE_COUNT and health <= max_health * ENRAGE_FRACTION
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

-- Angle toward the current target, or nil when there is nobody to aim at
-- (right after a spawn, or once everyone is down).
local function aim_angle()
    local my_pos = get_value("", name, "position")
    local target_pos = target ~= "" and get_value("", target, "position") or nil
    if not my_pos or not target_pos then return nil end
    return math.atan(target_pos.y - my_pos.y, target_pos.x - my_pos.x)
end

local function refresh_damage()
    local scale = PHASE_DAMAGE_SCALE[phase]
    damage = BASE_CONTACT_DMG * wave_level * scale
    bullet_damage = BASE_BULLET_DMG * wave_level * scale
    slam_damage = BASE_SLAM_DMG * wave_level * scale
    meteor_damage = BASE_METEOR_DMG * wave_level * scale
end

-- =============================================================================
-- Host AI.
-- =============================================================================

function retarget()
    if not IS_HOST then return end
    local nearest = get_nearest_entity_by_tag(name, "alive")
    target = (nearest and nearest.name) and nearest.name or ""
    if target ~= "" and not phase_locked then
        go_to_target(name, target, false)
    end
end

function run_pattern()
    if not IS_HOST or phase_locked then return end
    local cycle = PHASE_PATTERNS[phase]
    pattern_index = pattern_index + 1
    local which = cycle[((pattern_index - 1) % #cycle) + 1]

    if which == "shotgun" then
        -- Shotgun: one wide blast of projectiles at the target, all at once.
        -- This is the only thing phase 1 does, so it has to read clearly.
        local aim = aim_angle() or (math.random() * 2 * math.pi)
        local count = PHASE_SHOTGUN_BULLETS[phase] + (enraged() and ENRAGE_EXTRA_BULLETS or 0)
        for i = 1, count do
            local offset = SHOTGUN_SPREAD * ((i - 1) / (count - 1) - 0.5)
            -- Slightly uneven speeds so the wall of pellets spreads out as it
            -- travels instead of staying a single dodgeable arc.
            fire(aim + offset, BULLET_SPEED * (0.85 + math.random() * 0.4))
        end
    elseif which == "ring" then
        -- Ring: bullets in every direction (more when enraged).
        local count = RING_BULLETS + (enraged() and ENRAGE_EXTRA_BULLETS or 0)
        for i = 1, count do
            fire(2 * math.pi * i / count)
        end
    elseif which == "spiral" then
        -- Spiral: a rotating emitter driven by its own little timer.
        spiral_left = SPIRAL_SHOTS + (enraged() and ENRAGE_EXTRA_BULLETS or 0)
        start_timer({ timer_id = "spiral" .. name, entity_name = name,
            function_name = "spiral_step", wait_time = SPIRAL_STEP_SECONDS,
            duration = SPIRAL_STEP_SECONDS * spiral_left })
    else
        -- Volley: a tight fan aimed at the current target.
        local aim = aim_angle()
        if aim then
            for i = 1, VOLLEY_BULLETS do
                local offset = VOLLEY_SPREAD * ((i - 1) / (VOLLEY_BULLETS - 1) - 0.5)
                fire(aim + offset, BULLET_SPEED * 1.3)
            end
        end
    end
end

function spiral_step()
    if not IS_HOST or spiral_left <= 0 or phase_locked then return end
    spiral_left = spiral_left - 1
    spiral_angle = spiral_angle + 0.5
    fire(spiral_angle)
    fire(spiral_angle + math.pi)
end

function slam()
    if not IS_HOST or phase_locked or PHASE_SLAM_SECONDS[phase] <= 0 then return end
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
    if not IS_HOST or phase_locked or PHASE_METEOR_COUNT[phase] <= 0 then return end
    local my_pos = get_value("", name, "position")
    if not my_pos then return end
    local count = PHASE_METEOR_COUNT[phase] + (enraged() and 3 or 0)
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

-- =============================================================================
-- Phases.
--
-- apply_phase re-arms the host timers for the phase we are now in; the slam and
-- meteor timers are stopped outright in the phases that do not have those
-- attacks so no work is queued for them at all.
-- =============================================================================

local function apply_phase()
    if not IS_HOST then return end
    refresh_damage()
    set_value("", name, "speed", PHASE_SPEED[phase])

    start_timer({ timer_id = "bpat" .. name, entity_name = name,
        function_name = "run_pattern", wait_time = PHASE_PATTERN_SECONDS[phase] })

    if PHASE_SLAM_SECONDS[phase] > 0 then
        start_timer({ timer_id = "bslam" .. name, entity_name = name,
            function_name = "slam", wait_time = PHASE_SLAM_SECONDS[phase] })
    else
        stop_timer("bslam" .. name)
    end

    if PHASE_METEOR_SECONDS[phase] > 0 then
        start_timer({ timer_id = "bmet" .. name, entity_name = name,
            function_name = "meteor_shower", wait_time = PHASE_METEOR_SECONDS[phase] })
    else
        stop_timer("bmet" .. name)
    end
end

-- HOST: the bar hit zero but there is another phase left. Refill it, freeze the
-- boss for a beat so the players get a breather (and can see what happened),
-- then come back angrier.
local function advance_phase()
    phase = phase + 1
    max_health = phase_pool(phase)
    health = max_health
    phase_locked = true
    pattern_index = 0
    spiral_left = 0

    -- Stop dead in its tracks: go_to_target only rewrites the velocity once a
    -- second, so clear the current one too or it would keep sliding.
    go_to_target(name, "")
    set_value("", name, "linear_velocity", Vector2(0, 0))

    apply_phase()
    run_network_function(name, "phase_ALL", { phase, max_health })
    start_timer({ timer_id = "bphase" .. name, entity_name = name,
        function_name = "end_phase_break", wait_time = PHASE_BREAK_SECONDS,
        duration = PHASE_BREAK_SECONDS })
end

-- HOST: the breather is over. It wakes up with a full ring so standing on top
-- of it during the pause is not free.
function end_phase_break()
    if not IS_HOST then return end
    phase_locked = false
    for i = 1, RING_BULLETS do
        fire(2 * math.pi * i / RING_BULLETS)
    end
    retarget()
end

-- Every peer: new bar size, new outline colour, banner + growl.
function phase_ALL(sender_id, new_phase, new_max)
    phase = math.floor(new_phase)
    max_health = new_max
    health = new_max
    set_progress_bar({ parent_name = name, name = "hpbar",
        max_value = new_max, value = new_max, modulate = PHASE_COLOR[phase] })
    set_shader({ parent_name = name, image_name = image_name, shader_name = "circle",
        outline_color = PHASE_COLOR[phase] })
    set_label({ parent_name = name, name = "levellabel",
        text = string.format(translate("{boss_level_label}"), phase) })

    -- Translated locally on each peer (never send translated text over the
    -- network): the token carries a %d, so it cannot be handed to the
    -- auto-translating label as a bare token.
    local text = string.format(translate("{the_guardian_grows_stronger}"), phase, PHASE_COUNT)
    add_to_chat("[color=#e43b44]" .. text .. "[/color]", false)
    set_label({ name = "_center_information", text = text,
        font_color = PHASE_COLOR[phase] })
    -- Reuses "-bm"'s own banner timer/clearer, so a phase banner and the
    -- arrival banner can never fight over "_center_information".
    start_timer({ entity_name = "-bm", timer_id = "boss_banner", wait_time = 4.0,
        duration = 4.0, function_name = "clear_boss_banner" })
    set_audio({ stream_path = "monster-growl", volume = -4, random_pitch = 0.1 })
end

if IS_HOST then
    retarget()
    apply_phase()
    start_timer({ timer_id = "brt" .. name, entity_name = name,
        function_name = "retarget", wait_time = 3.0 })
end

-- =============================================================================
-- Damage / defeat.
--
-- Same signature as monster.lua's take_damage so bullet.lua needs no special
-- case, but the boss is far too heavy to be knocked around and it drops no XP.
-- =============================================================================

function take_damage(incoming_damage, knockback_amount, angle, player_id)
    if not IS_HOST then return end
    -- Between phases it is untouchable, otherwise burst damage in the pause
    -- would eat straight through the phase that just started.
    if phase_locked then return end

    local actual_damage = math.min(incoming_damage, health)
    health = health - incoming_damage

    local is_final_blow = health <= 0 and phase >= PHASE_COUNT
    -- 'health' is already decremented, so this doubles as "was that the killing
    -- blow?" and carries the death sound on the same message (see monster.lua).
    run_network_function(name, "show_damage_label_ALL", { actual_damage, is_final_blow })
    if player_id and actual_damage > 0 then
        run_function("-stats", "add_player_stat", { player_id, "damage_dealt", actual_damage })
    end
    run_network_function(name, "hp_bar_ALL", { health })

    if health <= 0 then
        if phase < PHASE_COUNT then
            advance_phase()
            return
        end
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

function show_damage_label_ALL(sender_id, damage_amount, died)
    -- Same hit/death pair every monster plays, just louder - this is the boss.
    set_audio({
        no_multiple_tag = "imp" .. name,
        stream_path = "bullet_impact",
        position = position,
        is_2d = true,
        max_distance = 520,
        volume = -6,
        random_pitch = 0.15
    })
    run_function("-mg", "spawn_damage_particle", {position})
    if died then
        set_audio({
            stream_path = "npc_died",
            position = position,
            is_2d = true,
            max_distance = 640,
            volume = -2,
            random_pitch = 0.06
        })
    end
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

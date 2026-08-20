network_mode = 2
lock_rotation = true
linear_damp = 0
friction = 0 -- slide along walls instead of sticking when a wander/flee/charge line runs into one

-- =============================================================================
-- MineBlockLand - one generic script for EVERY animal on the island.
--
-- The entity carries no stats of its own: -wild hands it a species key at spawn
-- time and everything (looks, speed, herd reactions, loot) is read out of
-- wildlife.lua's SPECIES table. Adding a new animal never touches this file.
--
-- Behaviours:
--   "flee" - harmless. Wanders around its group's anchor; being hit sends it
--            running away from whoever hit it for a few seconds.
--   "herd" - harmless until provoked. Hitting ONE member alerts the whole herd
--            through its shared tag, and every member hunts the attacker down
--            until the target gets far enough away, at which point the herd
--            calms back down and goes back to grazing.
--
-- Cost control: there is deliberately NO _process here. All AI runs on a single
-- ~0.4s host-side timer, and only the host runs it at all - clients just render
-- the synced body. Combined with -wild only keeping nearby chunks populated,
-- a full island of wildlife costs a few dozen timer ticks per second.
--
-- Spawn config: species, start_hp, herd, anchor_x, anchor_y, wkey, wgroup,
-- wmember. (wgroup/wmember are STRINGS: numbers crossing the Lua<->GDScript
-- boundary come back as floats, and "2.0" is not a usable table index.)
--
-- Note the deliberate start_hp -> hp copy below: get_value() answers out of the
-- entity's spawn-config variables BEFORE it looks at the Lua state, so a live
-- value that -wild has to read back (the HP it stores when the chunk empties)
-- must live under a name the spawn config never used.
-- =============================================================================

add_tag(name, "npc")
add_tag(name, "critter")
add_tag(name, herd)

hp = start_hp

local def = run_function("-wild", "get_species", { species })

local AI_SECONDS = 0.4
local WANDER_RADIUS = 88        -- pixels from the group's anchor
local WANDER_ARRIVE = 12
local WANDER_TRIES = 5
local IDLE_CHANCE = 0.35        -- chance a finished wander leg is spent standing still
local IDLE_SECONDS = 1.6
local STUCK_RETRY_MIN = 5       -- boxed in (no walkable spot found): back off longer than a
local STUCK_RETRY_MAX = 10      -- normal grazing pause before trying again, terrain may change
local STUCK_CHECK_SECONDS = 3   -- if a wander leg hasn't moved at least STUCK_MOVE_MIN pixels
local STUCK_MOVE_MIN = 6        -- in this many seconds, its straight-line path ran into a wall
local FLEE_SECONDS = 4.5
local FLEE_SPEED_MULT = 1.7
local FLEE_STEP = 20            -- pixels looked ahead when steering around walls
local CALM_DISTANCE = 300       -- an enraged herd gives up past this
local RETARGET_SECONDS = 1.6

local clock = 0
local state = "wander"
local wander_x, wander_y = anchor_x, anchor_y
local idle_until = -1
local flee_until = -1
local flee_angle = 0
local target = ""
local last_retarget = -10
local attack_ready = true
local progress_x, progress_y = anchor_x, anchor_y
local progress_time = 0

local SIZE = def.size
local CHARGE_SPEED = def.charge_speed or def.speed

set_value("", name, "speed", def.speed)
set_image({ parent_name = name, name = "body", image_path = def.image,
    scale = Vector2(SIZE, SIZE), z_index = 2 })
-- Flying animals have an EMPTY collision mask, so trees, rock and water are
-- nothing to them; they still sit on layer 3 so arrows and melee hit normally.
set_collision({ parent_name = name, name = "col", shape = "circle", size = SIZE / 2,
    collision_layer = { 3 }, collision_mask = def.flying and {} or { 1 } })
-- Read by -combat's melee hit test, so a swing that clips the body counts.
set_value("", name, "hit_radius", SIZE / 2)
-- ...and by -steps: a bird or a butterfly never touches the ground, so it must
-- not drag a trail of footsteps across the island behind it.
if def.flying then set_value("", name, "silent_steps", true) end

-- =============================================================================
-- Movement helpers (host only - clients just receive the synced position).
-- =============================================================================

local function stop_moving()
    set_value("", name, "linear_velocity", Vector2(0, 0))
end

local function move_along(angle, speed)
    set_value("", name, "linear_velocity",
        Vector2(math.cos(angle) * speed, math.sin(angle) * speed))
end

local function walkable_at(world_x, world_y)
    if def.flying then return true end
    local tile = local_to_map(Vector2(world_x, world_y))
    return run_function("-gen", "is_walkable", { math.floor(tile.x), math.floor(tile.y) })
end

-- Picks the next grazing spot inside the group's home range. Falls back to
-- standing still rather than walking into a wall.
local function pick_wander_spot()
    for _ = 1, WANDER_TRIES do
        local angle = math.random() * 2 * math.pi
        local dist = math.random() * WANDER_RADIUS
        local wx = anchor_x + math.cos(angle) * dist
        local wy = anchor_y + math.sin(angle) * dist
        if walkable_at(wx, wy) then
            wander_x, wander_y = wx, wy
            return true
        end
    end
    -- Boxed in (a herd anchored next to a cliff): wait it out instead of
    -- grinding against the wall, and back off longer than a normal grazing
    -- pause so a permanently blocked spot doesn't spend every tick retrying.
    idle_until = clock + STUCK_RETRY_MIN + math.random() * (STUCK_RETRY_MAX - STUCK_RETRY_MIN)
    return false
end

-- =============================================================================
-- Host AI tick.
-- =============================================================================

local function tick_wander(pos)
    if clock < idle_until then
        stop_moving()
        return
    end
    local dx, dy = wander_x - pos.x, wander_y - pos.y
    if dx * dx + dy * dy <= WANDER_ARRIVE * WANDER_ARRIVE then
        progress_x, progress_y, progress_time = pos.x, pos.y, clock
        if math.random() < IDLE_CHANCE then
            idle_until = clock + IDLE_SECONDS
            stop_moving()
            return
        end
        pick_wander_spot()
        dx, dy = wander_x - pos.x, wander_y - pos.y
    elseif clock - progress_time >= STUCK_CHECK_SECONDS then
        -- Hasn't gotten meaningfully closer in a while: the straight-line path
        -- to this leg's spot runs into terrain the sliding physics can't get
        -- around on its own. Give up on it and pick a fresh one instead of
        -- grinding along the same wall forever.
        if distance_to(pos, Vector2(progress_x, progress_y)) < STUCK_MOVE_MIN then
            pick_wander_spot()
            dx, dy = wander_x - pos.x, wander_y - pos.y
        end
        progress_x, progress_y, progress_time = pos.x, pos.y, clock
    end
    move_along(math.atan(dy, dx), def.speed)
end

local function tick_flee(pos)
    if clock >= flee_until then
        state = "wander"
        pick_wander_spot()
        return
    end
    -- Keep the panic heading, but veer around anything solid in the way.
    if not walkable_at(pos.x + math.cos(flee_angle) * FLEE_STEP,
            pos.y + math.sin(flee_angle) * FLEE_STEP) then
        flee_angle = flee_angle + (math.random() * 1.4 - 0.7)
    end
    move_along(flee_angle, def.speed * FLEE_SPEED_MULT)
end

local function tick_aggro(pos)
    -- Re-pick the nearest living player now and then: a stampede chases
    -- whoever is closest, and this is also what quietly drops a target that
    -- died or disconnected.
    if clock - last_retarget >= RETARGET_SECONDS then
        last_retarget = clock
        local nearest = get_nearest_entity_by_tag(name, "alive")
        target = (nearest and nearest.name) and nearest.name or ""
    end
    local target_pos = target ~= "" and get_value("", target, "position") or nil
    if not target_pos then
        calm_down()
        return
    end
    local dist = distance_to(pos, target_pos)
    if dist > CALM_DISTANCE then
        run_function_by_tag(herd, "host_calm")
        return
    end
    local angle = math.atan(target_pos.y - pos.y, target_pos.x - pos.x)
    if dist <= def.reach and attack_ready then
        attack_ready = false
        stop_moving()
        run_function("-combat", "start_telegraph", { {
            x = pos.x + math.cos(angle) * (def.reach * 0.6),
            y = pos.y + math.sin(angle) * (def.reach * 0.6),
            shape = "circle", r = 10 + SIZE / 2, windup = def.windup,
            dmg = def.dmg, targets = "players", attacker = name } })
        start_timer({ timer_id = "cc" .. name, entity_name = name,
            function_name = "reset_attack", wait_time = def.cooldown,
            duration = def.cooldown })
        return
    end
    move_along(angle, CHARGE_SPEED)
end

function wild_tick()
    if not IS_HOST then return end
    clock = clock + AI_SECONDS
    local pos = get_value("", name, "position")
    if not pos then return end
    if state == "flee" then
        tick_flee(pos)
    elseif state == "aggro" then
        tick_aggro(pos)
    else
        tick_wander(pos)
    end
end

function reset_attack()
    attack_ready = true
end

-- =============================================================================
-- Herd reactions (called on every member through the shared herd tag).
-- =============================================================================

function host_provoke(attacker)
    if not IS_HOST or attacker == "" or def.behavior ~= "herd" then return end
    if clock - last_retarget < RETARGET_SECONDS and state == "aggro" then return end
    last_retarget = clock
    state = "aggro"
    target = attacker
    idle_until = -1
end

function calm_down()
    state = "wander"
    target = ""
    progress_time = clock
    pick_wander_spot()
end

function host_calm()
    if not IS_HOST or state ~= "aggro" then return end
    calm_down()
end

-- =============================================================================
-- Damage / death (same entry point every damageable NPC in the mod exposes).
-- =============================================================================

function npc_take_damage(dmg_in, attacker, kb, angle)
    if not IS_HOST then return end
    hp = hp - dmg_in
    local pos = get_value("", name, "position")
    if pos then
        run_function("-combat", "show_damage", { pos.x, pos.y, dmg_in, "npc" })
    end
    if attacker and attacker ~= "" and has_tag(attacker, "user") then
        run_function("-gm", "add_stat", { attacker, "dmg_dealt", dmg_in })
    end
    if kb and kb > 0 and angle then
        add_linear_velocity(name, Vector2(math.cos(angle) * kb, math.sin(angle) * kb))
    end
    if hp <= 0 then
        host_die(attacker, pos)
        return
    end
    if def.behavior == "herd" and attacker and attacker ~= "" then
        -- One shove and the entire herd comes for you.
        run_function_by_tag(herd, "host_provoke", { attacker })
        return
    end
    -- Harmless species just bolt: away from the attacker, or in any direction
    -- at all when the hit came from something without a position (a bolt).
    state = "flee"
    flee_until = clock + FLEE_SECONDS
    local from = (attacker and attacker ~= "") and get_value("", attacker, "position") or nil
    if from and pos then
        flee_angle = math.atan(pos.y - from.y, pos.x - from.x)
    else
        flee_angle = math.random() * 2 * math.pi
    end
end

function host_die(attacker, pos)
    if pos then
        for _, drop in ipairs(run_function("-items", "get_wildlife_drops", { def.loot })) do
            if math.random() < drop.chance then
                spawn_entity_host({ t = "ground_item", p = pos,
                    item_id = drop.id, count = math.random(drop.min, drop.max) })
            end
        end
    end
    run_function("-gm", "on_enemy_killed",
        { { killer = attacker, dungeon_id = "", x = pos and pos.x, y = pos and pos.y } })
    run_function("-wild", "on_critter_died", { wkey, wgroup, wmember })
    destroy("", name)
end

-- HOST: a player threw a saddle over this animal. As far as the world is
-- concerned it leaves exactly the way a death does - the -wild ledger has to
-- forget it, or walking back into the chunk would resurrect a mount that is
-- already under somebody - but there is no loot and nobody is credited a kill,
-- and the slot is NOT pencilled in to regrow (no_respawn): nothing died here,
-- the animal simply changed owner.
-- Returns the species key so the rider knows what it is now sitting on.
function host_tame()
    if not IS_HOST then return "" end
    run_function("-wild", "on_critter_died", { wkey, wgroup, wmember, true })
    destroy("", name)
    return species
end

if IS_HOST then
    pick_wander_spot()
    start_timer({ timer_id = "wt" .. name, entity_name = name,
        function_name = "wild_tick", wait_time = AI_SECONDS })
end

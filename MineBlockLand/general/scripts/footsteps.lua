singleton_name = "steps"
network_mode = 0

-- =============================================================================
-- MineBlockLand - footsteps for everything that walks (players, zombies,
-- dungeon guards, wildlife).
--
-- ZERO network traffic. Every peer watches the entities NEAR ITSELF and plays
-- their steps from the tile they happen to be standing on, because both halves
-- of that are already local: positions are streamed anyway (users and npcs are
-- DYNAMIC entities) and kind_at is a pure function of the seed plus the
-- mutation ledger every peer already holds. So the same step lands on every
-- screen without a single packet - see worldgen.lua's header for why the world
-- is derivable rather than transmitted.
--
-- Cost control - the whole reason this is ONE singleton instead of a bit of
-- _process bolted onto user/enemy/critter:
--   * one timer for the entire island, no _process anywhere;
--   * a squared-distance cull against the local player runs FIRST, so anything
--     you could not hear anyway costs a single position read and nothing else
--     (and drops its tracking entry, so it cannot go stale either);
--   * kind_at is only asked the moment a step actually fires, never per tick -
--     the same trick user.lua's water_ripple uses;
--   * steps go out through a round-robin of SLOTS no_multiple_tag names, which
--     caps how many can ever be playing at the same instant: a horde chasing
--     you cannot stack forty simultaneous AudioStreamPlayer2D nodes, the 13th
--     step simply retriggers the oldest slot. (The tag does NOT pool nodes
--     across plays - SoundManager frees a player when it finishes either way -
--     it only collapses overlap, which is exactly the runaway case here.)
-- =============================================================================

-- Tile kind ids (each entity has its own Lua env; must match worldgen.lua).
local K_GRASS, K_SAND, K_TREE, K_FARM, K_FARM_SEEDED, K_FARM_GROWN = 1, 2, 3, 4, 5, 6
local K_SEA, K_DEEP, K_STONE, K_FLOOR, K_SAPLING = 7, 8, 9, 10, 11
local K_CACTUS, K_PALM, K_FLOWER, K_WOOD_BLOCK = 12, 13, 14, 15

-- Which footstep set a tile plays. Sand is deliberately "dirt": there is no
-- sand set, and dirt is what loose ground sounds like. Nothing walkable is
-- stone right now except the dungeon floor - that is what the stone set is for.
-- The blocking kinds (tree/rock/cactus/palm/placed block) are listed anyway,
-- because a flying critter or a phasing ghost can be standing over one.
local MATERIAL = {
    [K_GRASS] = "grass", [K_FLOWER] = "grass", [K_TREE] = "grass",
    [K_SAND] = "dirt", [K_FARM] = "dirt", [K_FARM_SEEDED] = "dirt",
    [K_FARM_GROWN] = "dirt", [K_SAPLING] = "dirt", [K_CACTUS] = "dirt",
    [K_PALM] = "dirt",
    [K_SEA] = "water", [K_DEEP] = "water",
    [K_STONE] = "stone", [K_FLOOR] = "stone", [K_WOOD_BLOCK] = "stone",
}

-- general/sounds/footsteps/<material>_footsteps1..10.ogg
local VARIANTS = 10

local TICK = 0.12             -- how often every walker is looked at
local HEAR_RANGE = 420        -- past this nothing is computed at all...
local MAX_DISTANCE = 420      -- ...which is exactly where the 2D falloff ends
local MOVE_MIN = 1.5          -- px moved within one TICK to count as "walking"
local STEP_PERIOD = 0.34      -- seconds between steps while moving
local STEP_JITTER = 0.12      -- +/- fraction of it, so a horde never marches in lockstep
local VOLUME = -7
local PITCH_RANDOM = 0.12     -- on top of picking a random one of the 10 files
local SLOTS = 12              -- ceiling on footsteps playing at the same time
local PRUNE_TICKS = 40        -- drop entries for entities that stopped existing

local HEAR_RANGE_SQ = HEAR_RANGE * HEAR_RANGE
local MOVE_MIN_SQ = MOVE_MIN * MOVE_MIN

local tracks = {}   -- entity name -> { x, y, t, period, seen, silent }
local slot = 0
local ticks = 0

local function next_period()
    return STEP_PERIOD * (1 - STEP_JITTER + math.random() * 2 * STEP_JITTER)
end

local function play_step(material, x, y)
    slot = (slot % SLOTS) + 1
    set_audio({
        stream_path = "footsteps/" .. material .. "_footsteps" .. math.random(VARIANTS),
        is_2d = true, position = Vector2(x, y), max_distance = MAX_DISTANCE,
        volume = VOLUME, random_pitch = PITCH_RANDOM,
        -- Round-robin slot: a step lands on a tag that is still playing only
        -- once SLOTS others fired inside one sample's length, and then it
        -- retriggers that player rather than adding an extra one. Position,
        -- volume, pitch and stream are all re-applied on reuse, so a
        -- retriggered player is indistinguishable from a fresh one.
        no_multiple_tag = "mbl_step" .. slot,
    })
end

-- One walker, one tick. 'me' is the local player's position (the listener).
local function watch(entity, me)
    local pos = get_value("", entity, "position")
    if not pos then return end
    local dx, dy = pos.x - me.x, pos.y - me.y
    if dx * dx + dy * dy > HEAR_RANGE_SQ then
        -- Out of earshot: forget it entirely, so walking back into range starts
        -- a fresh stride instead of firing one step for the whole trip.
        tracks[entity] = nil
        return
    end

    local track = tracks[entity]
    if not track then
        tracks[entity] = { x = pos.x, y = pos.y, t = 0, period = next_period(),
            seen = ticks,
            -- Read once, at track creation: a bird has nothing to step on and a
            -- ghost has no feet (see critter.lua / enemy.lua).
            silent = get_value("", entity, "silent_steps") == true }
        return
    end
    track.seen = ticks

    local mx, my = pos.x - track.x, pos.y - track.y
    track.x, track.y = pos.x, pos.y
    if track.silent or mx * mx + my * my < MOVE_MIN_SQ then
        track.t = 0 -- standing still: the next stride starts from scratch
        return
    end
    track.t = track.t + TICK
    if track.t < track.period then return end
    track.t = 0
    track.period = next_period()

    local tile = local_to_map(pos)
    -- Floored on the way in AND on the way out: tile coords and the kind id
    -- both crossed the Lua<->GDScript boundary, so they arrive as floats.
    local kind = run_function("-gen", "kind_at",
        { math.floor(tile.x), math.floor(tile.y) })
    local material = MATERIAL[math.floor(kind)]
    if material then play_step(material, pos.x, pos.y) end
end

function step_tick()
    -- The listener is the local player: before it exists there is nobody to
    -- hear anything, and no centre to cull against. Its presence is checked
    -- through the tag list rather than by reading the position straight away,
    -- because get_value on an entity that is not there yet logs an error - and
    -- this runs several times a second from the moment the map loads.
    local users = get_entity_names_by_tag("user")
    local me = nil
    for _, user_name in ipairs(users) do
        if user_name == LOCAL_STEAM_ID then
            me = get_value("", LOCAL_STEAM_ID, "position")
            break
        end
    end
    if not me then return end
    ticks = ticks + 1
    for _, entity in ipairs(users) do
        watch(entity, me)
    end
    for _, entity in ipairs(get_entity_names_by_tag("npc")) do
        watch(entity, me)
    end
    -- Entities destroyed while still in earshot (a zombie killed at your feet)
    -- never hit the out-of-range branch above, so sweep the leftovers now and
    -- then rather than walking the whole table every tick.
    if ticks % PRUNE_TICKS == 0 then
        for entity, track in pairs(tracks) do
            if ticks - track.seen >= PRUNE_TICKS then tracks[entity] = nil end
        end
    end
end

start_timer({ timer_id = "mbl_steps", entity_name = name,
    function_name = "step_tick", wait_time = TICK })

singleton_name = "wild"
network_mode = 0

-- =============================================================================
-- MineBlockLand - wildlife registry + chunk-based population manager.
--
-- TWO jobs, one file:
--
-- 1. SPECIES is the single data table describing every animal in the game
--    (looks, stats, which biome it belongs to, how big its herd is and how it
--    reacts to being hit). critter.lua is a completely generic entity that
--    reads its definition from here at spawn time - adding a new animal, or a
--    whole new behaviour family, means editing this table, not writing code.
--
-- 2. The HOST keeps a LEDGER of animal groups per world chunk and only keeps
--    the ones near a player actually spawned. Walk away and the group's
--    entities are destroyed after their live position/HP is written back into
--    the ledger; walk back and they respawn exactly where and how they were.
--    So the world feels populated everywhere while only a couple of dozen
--    entities exist at any moment. The active window (ACTIVE_CHUNK_RADIUS)
--    matches worldgen.lua's VIEW_CHUNK_RADIUS, so animals only ever live in
--    chunks whose tiles are actually generated.
--
-- Nothing here is persisted to the save file: at each dawn the ledger for
-- unattended chunks is dropped, so the island naturally restocks and the
-- bookkeeping can never grow without bound. That's safe because a dropped
-- chunk isn't actually forgotten - which species, how many and exactly where
-- they stand is re-derived deterministically from (world seed, chunk coords)
-- via whash01() below, the same trick -gen uses for terrain. So the animal
-- population for a given chunk on a given seed is always the same, on any
-- day, on any peer, whether it was just rolled for the first time or rolled
-- again after being dropped.
-- =============================================================================

-- Behaviours (see critter.lua for the implementation):
--   "flee" - harmless. Wanders; runs away from whoever hits it.
--   "herd" - harmless until provoked. Hitting one member enrages the WHOLE
--            group, which then hunts the attacker down; they calm back down
--            once the target gets far enough away.
SPECIES = {
    -- Beach ------------------------------------------------------------------
    crab = { label ="{crab}", image = "items/10x10_crab", size = 11, hp = 16,
        speed = 8, biomes = { beach = true }, group = { 2, 4 }, weight = 16,
        behavior = "flee", loot = "small" },
    turtle = { label ="{turtle}", image = "items/10x10_turtle", size = 13, hp = 34,
        speed = 4, biomes = { beach = true }, group = { 2, 3 }, weight = 10,
        behavior = "flee", loot = "medium" },
    frog = { label ="{frog}", image = "items/10x10_frog", size = 10, hp = 12,
        speed = 9, biomes = { beach = true }, group = { 1, 1 }, weight = 9,
        behavior = "flee", loot = "small" },

    -- Grassland --------------------------------------------------------------
    bunny = { label ="{bunny}", image = "items/5x5_bunny", size = 10, hp = 10,
        speed = 16, biomes = { grass = true }, group = { 3, 5 }, weight = 18,
        behavior = "flee", loot = "small" },
    fox = { label ="{fox}", image = "items/5x5_fox", size = 12, hp = 24,
        speed = 15, biomes = { grass = true }, group = { 2, 4 }, weight = 12,
        behavior = "flee", loot = "medium" },
    monkey = { label ="{monkey}", image = "items/10x10_monkey", size = 13, hp = 26,
        speed = 13, biomes = { grass = true }, group = { 2, 4 }, weight = 10,
        behavior = "flee", loot = "medium" },
    bird = { label ="{bird}", image = "items/10x10_bird", size = 10, hp = 8,
        speed = 17, biomes = { grass = true }, group = { 1, 1 }, weight = 12,
        behavior = "flee", loot = "small", flying = true },
    butterfly = { label ="{butterfly}", image = "items/10x10_butterfly", size = 8, hp = 6,
        speed = 11, biomes = { grass = true }, group = { 1, 1 }, weight = 10,
        behavior = "flee", loot = "small", flying = true },
    bug = { label ="{bug}", image = "items/10x10_bug", size = 8, hp = 6,
        speed = 7, biomes = { grass = true }, group = { 1, 1 }, weight = 8,
        behavior = "flee", loot = "small" },
    unicorn = { label ="{unicorn}", image = "items/10x10_unicorn", size = 16, hp = 70,
        speed = 20, biomes = { grass = true }, group = { 1, 1 }, weight = 2,
        behavior = "flee", loot = "large" },

    -- Desert -----------------------------------------------------------------
    ostrich = { label ="{ostrich}", image = "items/15x15_ostrich", size = 17, hp = 42,
        speed = 18, biomes = { desert = true }, group = { 2, 4 }, weight = 12,
        behavior = "flee", loot = "medium" },
    eagle = { label ="{eagle}", image = "items/10x10_eagle", size = 13, hp = 28,
        speed = 17, biomes = { desert = true, beach = true }, group = { 2, 3 }, weight = 8,
        behavior = "flee", loot = "medium", flying = true },

    -- The provokable herds ---------------------------------------------------
    rhino = { label ="{rhino}", image = "items/15x15_rhino", size = 20, hp = 95,
        speed = 10, biomes = { grass = true, desert = true }, group = { 3, 5 }, weight = 7,
        behavior = "herd", loot = "large",
        dmg = 20, windup = 0.5, cooldown = 1.8, reach = 28, charge_speed = 21 },
    elephant = { label ="{elephant}", image = "items/10x10_elephant", size = 22, hp = 130,
        speed = 8, biomes = { grass = true }, group = { 2, 3 }, weight = 5,
        behavior = "herd", loot = "large",
        dmg = 26, windup = 0.7, cooldown = 2.2, reach = 30, charge_speed = 15 },
}

-- Chunk lifecycle -------------------------------------------------------------
local CHUNK_TILES = 32
local ACTIVE_CHUNK_RADIUS = 2   -- keep in step with worldgen.lua's VIEW_CHUNK_RADIUS
local SCAN_SECONDS = 1.5
local MAX_ACTIVE_CRITTERS = 44  -- hard ceiling across the whole server
-- A slain animal's slot in the ledger is not lost, only emptied: this many
-- seconds later the group grows the member back near its anchor, so camping
-- one meadow does not permanently strip it (before, a chunk you never left
-- stayed dead until dawn, since host_restock only ever drops INACTIVE chunks).
local RESPAWN_SECONDS = 90

-- Population density ----------------------------------------------------------
local GROUP_CHANCE = 0.55        -- chance a chunk holds any wildlife at all
local SECOND_GROUP_CHANCE = 0.30 -- ...and a chance it holds a second group
local ANCHOR_TRIES = 8           -- random tiles probed for a spawnable anchor
local MEMBER_TRIES = 6
local GROUP_SPREAD = 5           -- tiles a herd member may start from the anchor

-- Host-only state.
local ledger = {}         -- "cx,cy" -> { groups = { group, ... } }
local active_chunks = {}  -- "cx,cy" -> true
local active_count = 0
local world_seed = nil    -- cached from -gen; see ensure_world_seed()
-- Seconds of wall clock, counted one scan at a time (there is no need for a
-- real clock here: every deadline is set and read from this same counter).
local clock = 0

-- Species keys grouped by biome, sorted so the weighted pick is stable
-- regardless of pairs() iteration order.
local by_biome = {}

local function build_biome_index()
    by_biome = {}
    local keys = {}
    for key in pairs(SPECIES) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        for biome in pairs(SPECIES[key].biomes) do
            by_biome[biome] = by_biome[biome] or {}
            table.insert(by_biome[biome], key)
        end
    end
end

build_biome_index()

-- =============================================================================
-- Registry accessors (critter.lua reads its whole definition through these).
-- =============================================================================

function get_species(species_key)
    return SPECIES[species_key]
end

-- The little ones a Pet Charm can conjure up, in a stable order (pairs() has
-- none, and the charm cycles through this list one Interact at a time - the
-- order must be the same on every peer and every session).
function get_pet_species()
    local keys = {}
    for species_key, def in pairs(SPECIES) do
        if def.loot == "small" then table.insert(keys, species_key) end
    end
    table.sort(keys)
    return keys
end

-- =============================================================================
-- Rolling a fresh population for a chunk.
-- =============================================================================

local function key_of(cx, cy)
    return math.floor(cx) .. "," .. math.floor(cy)
end

-- Deterministic replacement for math.random(): a pure function of the world
-- seed, the chunk coords and a salt, so the SAME chunk on the SAME seed always
-- rolls the same animals in the same spots - walk away and back, log out and
-- back in, or have a friend visit the same chunk on their own machine, and the
-- herd is exactly where it was. Formula mirrors -gen's own hash01 (see
-- worldgen.lua) so it inherits the same well-mixed distribution.
local function whash01(x, y, salt)
    local h = (world_seed or 0) + salt * 668265263
    h = (h ~ (x * 374761393)) % 0x100000000
    h = (h * 3266489917 + 374761393) % 0x100000000
    h = (h ~ (y * 668265263)) % 0x100000000
    h = (h * 2654435761) % 0x100000000
    h = h ~ (h >> 16)
    return (h % 0x100000000) / 0x100000000
end

local function ensure_world_seed()
    if world_seed == nil then
        world_seed = run_function("-gen", "get_seed") or 0
    end
end

-- Returns a fresh 0..1 "draw" function scoped to one chunk: every call moves
-- to the next salt, so a whole chunk's worth of rolls (does it have wildlife,
-- which species, how many, exactly where) is a deterministic sequence purely
-- driven by (world_seed, cx, cy) - the actual branching only depends on
-- world state (terrain) that is itself a pure function of the same seed, so
-- the sequence of draws taken is reproducible too.
local function make_drawer(cx, cy)
    local draw_index = 0
    return function()
        draw_index = draw_index + 1
        return whash01(cx, cy, draw_index)
    end
end

local function pick_species(biome, draw)
    local candidates = by_biome[biome]
    if not candidates then return nil end
    local total = 0
    for _, key in ipairs(candidates) do total = total + SPECIES[key].weight end
    local pick = draw() * total
    for _, key in ipairs(candidates) do
        pick = pick - SPECIES[key].weight
        if pick <= 0 then return key end
    end
    return candidates[1]
end

-- Flying animals ignore terrain entirely; everything else needs solid footing.
local function can_stand(def, tx, ty)
    if def.flying then
        local biome = run_function("-gen", "biome_at", { tx, ty })
        return biome ~= "deep" and biome ~= "dungeon"
    end
    return run_function("-gen", "is_walkable", { tx, ty })
end

local function roll_group(cx, cy, group_id, draw)
    for _ = 1, ANCHOR_TRIES do
        local tx = cx * CHUNK_TILES + math.floor(draw() * CHUNK_TILES)
        local ty = cy * CHUNK_TILES + math.floor(draw() * CHUNK_TILES)
        local biome = run_function("-gen", "biome_at", { tx, ty })
        local species_key = pick_species(biome, draw)
        if species_key then
            local def = SPECIES[species_key]
            if can_stand(def, tx, ty) then
                local span = def.group[2] - def.group[1]
                local count = def.group[1] + math.floor(draw() * (span + 1))
                local members = {}
                for index = 1, count do
                    local mx, my = tx, ty
                    for _ = 1, MEMBER_TRIES do
                        local ox = tx + math.floor(draw() * (GROUP_SPREAD * 2 + 1)) - GROUP_SPREAD
                        local oy = ty + math.floor(draw() * (GROUP_SPREAD * 2 + 1)) - GROUP_SPREAD
                        if can_stand(def, ox, oy) then
                            mx, my = ox, oy
                            break
                        end
                    end
                    local world = map_to_local(Vector2(mx, my))
                    members[index] = { x = world.x, y = world.y, hp = def.hp }
                end
                local anchor = map_to_local(Vector2(tx, ty))
                -- 'dead' is member_index -> the clock value at which that slot
                -- grows an animal back (see respawn_due).
                return { species = species_key, members = members, entities = {},
                    dead = {}, herd = "mblherd_" .. group_id,
                    anchor_x = anchor.x, anchor_y = anchor.y }
            end
        end
    end
    return nil
end

local function roll_chunk(ck, cx, cy)
    -- The herd tag doubles as an entity group name, so keep it to plain
    -- identifier characters ("3,-2" -> "3n2").
    local tag_base = ck:gsub(",", "_"):gsub("-", "n")
    local draw = make_drawer(cx, cy)
    local groups = {}
    if draw() < GROUP_CHANCE then
        local first = roll_group(cx, cy, tag_base .. "_1", draw)
        if first then table.insert(groups, first) end
        if draw() < SECOND_GROUP_CHANCE then
            local second = roll_group(cx, cy, tag_base .. "_2", draw)
            if second then table.insert(groups, second) end
        end
    end
    return { groups = groups }
end

-- =============================================================================
-- Spawning / despawning ("freezing" a group is really destroy + remember).
-- =============================================================================

local function member_count(group)
    local total = 0
    for _ in pairs(group.members) do total = total + 1 end
    return total
end

-- Turns ONE ledger member into a live entity. Returns false when the ceiling
-- is in the way, so the caller can leave the slot for the next scan.
local function spawn_member(ck, group, group_index, member_index)
    local member = group.members[member_index]
    if not member or group.entities[member_index] then return false end
    if active_count >= MAX_ACTIVE_CRITTERS then return false end
    -- Ids cross the Lua<->GDScript boundary as spawn config and would come back
    -- as floats ("2.0"), so they travel as strings and are turned back into
    -- numbers on arrival. 'start_hp', not 'hp': get_value() answers out of the
    -- spawn config before it reads the Lua state, so the live HP read back in
    -- deactivate() needs a name the config never used.
    local entity = spawn_entity_host({ t = "critter",
        p = Vector2(member.x, member.y),
        species = group.species, start_hp = member.hp,
        herd = group.herd, anchor_x = group.anchor_x,
        anchor_y = group.anchor_y, wkey = ck,
        wgroup = tostring(group_index),
        wmember = tostring(member_index) })
    if not entity then return false end
    group.entities[member_index] = entity
    active_count = active_count + 1
    return true
end

local function activate(ck, cx, cy)
    if not ledger[ck] then
        ensure_world_seed()
        ledger[ck] = roll_chunk(ck, cx, cy)
    end
    active_chunks[ck] = true
    for group_index, group in ipairs(ledger[ck].groups) do
        -- Whole-group check, not per-member: half a herd is worse than none.
        if SPECIES[group.species]
                and active_count + member_count(group) <= MAX_ACTIVE_CRITTERS then
            for member_index in pairs(group.members) do
                spawn_member(ck, group, group_index, member_index)
            end
        end
    end
end

-- A spot near the group's anchor for a regrown member. The anchor itself was
-- can_stand-checked when the group was rolled, so it is always a valid last
-- resort - the tries above it only exist so a whole herd does not respawn
-- stacked on the exact same pixel.
local function respawn_position(def, group)
    local tile = local_to_map(Vector2(group.anchor_x, group.anchor_y))
    local tx, ty = math.floor(tile.x), math.floor(tile.y)
    for _ = 1, MEMBER_TRIES do
        local ox = tx + math.random(-GROUP_SPREAD, GROUP_SPREAD)
        local oy = ty + math.random(-GROUP_SPREAD, GROUP_SPREAD)
        if can_stand(def, ox, oy) then
            local world = map_to_local(Vector2(ox, oy))
            return world.x, world.y
        end
    end
    return group.anchor_x, group.anchor_y
end

-- Every slain member of an ACTIVE chunk whose timer has run out comes back at
-- full HP. Chunks nobody is standing in are left alone: their whole ledger is
-- thrown away at dawn anyway (host_restock), and animals do not need to be
-- simulated where no one can see them.
local function respawn_due(ck)
    local chunk = ledger[ck]
    if not chunk then return end
    for group_index, group in ipairs(chunk.groups) do
        local def = SPECIES[group.species]
        if def then
            for member_index, due_at in pairs(group.dead) do
                if clock >= due_at then
                    local x, y = respawn_position(def, group)
                    group.members[member_index] = { x = x, y = y, hp = def.hp }
                    if spawn_member(ck, group, group_index, member_index) then
                        group.dead[member_index] = nil
                    else
                        -- At the ceiling: put the slot back and retry next scan.
                        group.members[member_index] = nil
                    end
                end
            end
        end
    end
end

local function deactivate(ck)
    active_chunks[ck] = nil
    local chunk = ledger[ck]
    if not chunk then return end
    for _, group in ipairs(chunk.groups) do
        for member_index, entity in pairs(group.entities) do
            local member = group.members[member_index]
            if member then
                local pos = get_value("", entity, "position")
                local live_hp = get_value("", entity, "hp")
                if pos then member.x, member.y = pos.x, pos.y end
                if live_hp then member.hp = live_hp end
            end
            destroy("", entity)
            active_count = active_count - 1
        end
        group.entities = {}
    end
end

-- =============================================================================
-- The scan: which chunks should be populated right now.
-- =============================================================================

function wild_scan()
    if not IS_HOST then return end
    if not run_function("-gen", "is_seed_ready") then return end
    clock = clock + SCAN_SECONDS
    local wanted = {}
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        local pos = get_value("", user_name, "position")
        if pos then
            local tile = local_to_map(pos)
            local ccx = math.floor(tile.x) // CHUNK_TILES
            local ccy = math.floor(tile.y) // CHUNK_TILES
            for dy = -ACTIVE_CHUNK_RADIUS, ACTIVE_CHUNK_RADIUS do
                for dx = -ACTIVE_CHUNK_RADIUS, ACTIVE_CHUNK_RADIUS do
                    wanted[key_of(ccx + dx, ccy + dy)] = { ccx + dx, ccy + dy }
                end
            end
        end
    end
    for ck in pairs(active_chunks) do
        if not wanted[ck] then deactivate(ck) end
    end
    for ck, coords in pairs(wanted) do
        if not active_chunks[ck] then activate(ck, coords[1], coords[2]) end
        respawn_due(ck)
    end
end

-- =============================================================================
-- Callbacks from critter.lua / -gm.
-- =============================================================================

-- A member left the world: empty its slot, so returning to the chunk does not
-- resurrect it on the spot. Unless 'no_respawn' is set (a saddled mount, which
-- is still very much alive and walking around under its rider), the slot is
-- pencilled in to grow the animal back RESPAWN_SECONDS later - see respawn_due.
function on_critter_died(wkey, wgroup, wmember, no_respawn)
    if not IS_HOST then return end
    local chunk = ledger[wkey]
    if not chunk then return end
    local group = chunk.groups[tonumber(wgroup)]
    if not group then return end
    local member_index = tonumber(wmember)
    if group.entities[member_index] then
        group.entities[member_index] = nil
        active_count = active_count - 1
    end
    group.members[member_index] = nil
    group.dead = group.dead or {}
    if no_respawn then
        group.dead[member_index] = nil
    else
        group.dead[member_index] = clock + RESPAWN_SECONDS
    end
end

-- HOST: a rider climbed down - the animal rejoins the world right where they
-- left it, the reverse of host_tame in critter.lua. It comes back as an
-- ownerless critter, not a ledger member (nobody's group budget pays for it,
-- same as taming never gives that budget back - see on_critter_died's
-- no_respawn branch), so it can wander, fight back, or be saddled again just
-- like any other animal instead of vanishing for good.
function release_mount(species_key, x, y)
    if not IS_HOST or not species_key or species_key == "" then return end
    local def = SPECIES[species_key]
    if not def then return end
    spawn_entity_host({ t = "critter", p = Vector2(x, y),
        species = species_key, start_hp = def.hp,
        herd = "loose" .. tostring(math.random(1, 999999999)),
        anchor_x = x, anchor_y = y,
        wkey = "", wgroup = "0", wmember = "0" })
end

-- Dawn: throw away the ledger of every chunk nobody is standing in, so the
-- island quietly restocks with fresh animals instead of slowly emptying out.
function host_restock()
    if not IS_HOST then return end
    for ck in pairs(ledger) do
        if not active_chunks[ck] then ledger[ck] = nil end
    end
end

-- New world / boss wipe: the caller already destroyed the entities by tag, so
-- only the bookkeeping needs clearing.
function host_reset()
    if not IS_HOST then return end
    ledger = {}
    active_chunks = {}
    active_count = 0
    clock = 0
    world_seed = nil -- re-fetched from -gen on the next roll (a new world means a new seed)
end

-- -gen only exists a moment after the singletons are created, and the seed
-- lands a little later still; the scan checks for both every time it runs.
start_timer({ timer_id = "wild_scan", entity_name = name,
    function_name = "wild_scan", wait_time = SCAN_SECONDS })

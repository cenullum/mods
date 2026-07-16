singleton_name = "gen"
network_mode = 0

-- =============================================================================
-- MineBlockLand - deterministic procedural world (runs on EVERY peer).
--
-- The host picks one integer seed and broadcasts it; every peer then computes
-- the exact same island from pure functions of (seed, tile x, tile y), so no
-- tile data ever travels over the network. Chunks are generated LAZILY as
-- players approach them (the host also generates around remote players, since
-- it simulates the enemies there).
--
-- World layout: a 16x16-chunk island (tiles -256..255). Land in the middle,
-- then a ring of shallow sea (walk-through but slow), then deep sea with solid
-- collision - the hard edge of the world. A 64x64-tile stone dungeon full of
-- rooms sits east of spawn.
--
-- Terrain changes (chopped trees, mined rock, farmland...) are host-ordered
-- MUTATIONS: a {tile -> new kind} ledger that overrides the pure terrain
-- function. The ledger is tiny, syncs to late joiners in one message and is
-- what the save file persists - same seed + same ledger = same world.
-- =============================================================================

-- Tile kinds (the mod's own vocabulary; ATLAS below maps them to tiles).
K_GRASS = 1
K_SAND = 2
K_TREE = 3
K_FARM = 4
K_FARM_SEEDED = 5
K_FARM_GROWN = 6
K_SEA = 7
K_DEEP = 8
K_STONE = 9
K_FLOOR = 10 -- dungeon floor

local TILESET_STONE = 0 -- 47-blob autotile source (stone_47_blob_texture.png)
local TILESET_MAIN = 1  -- tiles.png

-- kind -> atlas coords in tiles.png
local ATLAS = {
    [K_GRASS] = { 1, 0 }, [K_SAND] = { 0, 0 }, [K_TREE] = { 2, 0 },
    [K_FARM] = { 3, 0 }, [K_FARM_SEEDED] = { 4, 0 }, [K_FARM_GROWN] = { 5, 0 },
    [K_SEA] = { 6, 0 }, [K_DEEP] = { 7, 0 }, [K_FLOOR] = { 0, 1 },
}

-- World dimensions (1 chunk = 32x32 tiles, fixed by the engine).
local CHUNK_TILES = 32
local WORLD_CHUNK_MIN, WORLD_CHUNK_MAX = -8, 7
local LAND_RADIUS = 210     -- coast starts beyond this many tiles from spawn
local DEEP_RADIUS = 235     -- deep sea (solid) beyond this
local COAST_WOBBLE = 18     -- +/- tiles of coastline noise
local SPAWN_CLEAR_R = 7     -- feature-free grass circle around spawn

-- Boss arena: a clearing kept free of trees/stone so the fight has room.
BOSS_ARENA_X, BOSS_ARENA_Y = 0, -26
local BOSS_ARENA_R = 7

-- Starter farmland patch just east of spawn.
local FARM_X0, FARM_X1, FARM_Y0, FARM_Y1 = 5, 8, -1, 2

-- Dungeon rect (64x64 tiles = 2x2 chunks of area), east of spawn, entrance west.
DUNGEON_X0, DUNGEON_Y0 = 120, -32
DUNGEON_SIZE = 64

-- Noise salts (any distinct constants).
local SALT_COAST, SALT_STONE, SALT_SAND, SALT_TREE, SALT_TREE2 = 11, 22, 33, 44, 55

-- Chunk generation pacing.
local VIEW_CHUNK_RADIUS = 2      -- generate chunks this far around each player
local GEN_SCAN_INTERVAL = 0.3    -- how often player positions are checked
local GEN_STEP_INTERVAL = 0.05   -- one queued chunk is built per step

seed = nil                       -- set by -gm (host rolls it / save restores it)
local muts = {}                  -- "x,y" -> kind (host-ordered terrain changes)
local generated = {}             -- "cx,cy" -> true
local gen_queue = {}             -- array of {cx, cy}
local queued = {}                -- "cx,cy" -> true (dedupe)
local dungeon_grid = nil         -- [local_y*64+local_x] -> K_FLOOR / K_STONE
local dungeon_pois = {}          -- {{type="chest"/"witch"/"brute", x, y, id}, ...}

-- =============================================================================
-- Deterministic hashing / noise (pure Lua 5.4 integer math).
-- =============================================================================

local function hash01(x, y, salt)
    local h = (seed or 0) + salt * 668265263
    h = (h ~ (x * 374761393)) % 0x100000000
    h = (h * 3266489917 + 374761393) % 0x100000000
    h = (h ~ (y * 668265263)) % 0x100000000
    h = (h * 2654435761) % 0x100000000
    h = h ~ (h >> 16)
    return (h % 0x100000000) / 0x100000000
end

-- Smooth value noise in [0,1] on a lattice of 'scale' tiles.
local function value_noise(x, y, scale, salt)
    local gx, gy = x / scale, y / scale
    local x0, y0 = math.floor(gx), math.floor(gy)
    local fx, fy = gx - x0, gy - y0
    local sx = fx * fx * (3.0 - 2.0 * fx)
    local sy = fy * fy * (3.0 - 2.0 * fy)
    local v00 = hash01(x0, y0, salt)
    local v10 = hash01(x0 + 1, y0, salt)
    local v01 = hash01(x0, y0 + 1, salt)
    local v11 = hash01(x0 + 1, y0 + 1, salt)
    local a = v00 + (v10 - v00) * sx
    local b = v01 + (v11 - v01) * sx
    return a + (b - a) * sy
end

-- Seeded Park-Miller RNG for the dungeon builder (independent of hash01).
local rng_state = 1
local function rng_seed(s)
    rng_state = s % 2147483647
    if rng_state <= 0 then rng_state = rng_state + 2147483646 end
end
local function rng_range(a, b)
    rng_state = (rng_state * 16807) % 2147483647
    return a + (rng_state % (b - a + 1))
end

local function key_of(x, y)
    return x .. "," .. y
end

-- =============================================================================
-- Dungeon: rooms + corridors carved into a solid 64x64 stone block.
-- =============================================================================

local function din(lx, ly)
    return ly * DUNGEON_SIZE + lx
end

local function carve_rect(x0, y0, x1, y1)
    for ly = math.max(1, y0), math.min(DUNGEON_SIZE - 2, y1) do
        for lx = math.max(1, x0), math.min(DUNGEON_SIZE - 2, x1) do
            dungeon_grid[din(lx, ly)] = K_FLOOR
        end
    end
end

local function build_dungeon()
    dungeon_grid = {}
    dungeon_pois = {}
    for i = 0, DUNGEON_SIZE * DUNGEON_SIZE - 1 do
        dungeon_grid[i] = K_STONE
    end
    rng_seed(seed + 777)

    -- Rooms on a rough 3x3 grid; the middle-west cell stays the entrance hall.
    local rooms = {}
    for gy = 0, 2 do
        for gx = 0, 2 do
            local cx = 8 + gx * 20 + rng_range(-2, 2)
            local cy = 8 + gy * 20 + rng_range(-2, 2)
            local w = rng_range(8, 13)
            local h = rng_range(8, 13)
            local room = { x0 = cx, y0 = cy, x1 = math.min(cx + w, DUNGEON_SIZE - 3),
                y1 = math.min(cy + h, DUNGEON_SIZE - 3) }
            room.cx = (room.x0 + room.x1) // 2
            room.cy = (room.y0 + room.y1) // 2
            carve_rect(room.x0, room.y0, room.x1, room.y1)
            table.insert(rooms, room)
        end
    end
    -- Corridors: connect each room to the next (walk the grid row by row).
    for i = 2, #rooms do
        local a, b = rooms[i - 1], rooms[i]
        carve_rect(math.min(a.cx, b.cx), a.cy - 1, math.max(a.cx, b.cx), a.cy + 1)
        carve_rect(b.cx - 1, math.min(a.cy, b.cy), b.cx + 1, math.max(a.cy, b.cy))
    end
    -- Entrance: a west-side corridor into the middle-left room (index 4's row
    -- start = room 4 in reading order is the centre; use the middle-west: 4th).
    local entry = rooms[4]
    carve_rect(0, entry.cy - 1, entry.cx, entry.cy + 1)
    dungeon_grid[din(0, entry.cy - 1)] = K_FLOOR
    dungeon_grid[din(0, entry.cy)] = K_FLOOR
    dungeon_grid[din(0, entry.cy + 1)] = K_FLOOR

    -- Loot + guards: every room except the entrance gets a chest and guards.
    local guard_id = 0
    for i, room in ipairs(rooms) do
        if i ~= 4 then
            guard_id = guard_id + 1
            table.insert(dungeon_pois, { type = "chest", id = "dc" .. guard_id,
                x = DUNGEON_X0 + room.cx, y = DUNGEON_Y0 + room.cy })
            local kinds = { "brute", "witch" }
            for g = 1, 2 do
                table.insert(dungeon_pois, { type = kinds[g], id = "dg" .. guard_id .. "_" .. g,
                    x = DUNGEON_X0 + room.cx + rng_range(-3, 3),
                    y = DUNGEON_Y0 + room.cy + rng_range(-3, 3) })
            end
        end
    end
end

local function in_dungeon(x, y)
    return x >= DUNGEON_X0 and x < DUNGEON_X0 + DUNGEON_SIZE
        and y >= DUNGEON_Y0 and y < DUNGEON_Y0 + DUNGEON_SIZE
end

-- =============================================================================
-- Pure terrain function: kind of a tile before any mutations.
-- =============================================================================

local function coast_at(x, y)
    local r = math.sqrt(x * x + y * y)
    return r + COAST_WOBBLE * (value_noise(x, y, 24, SALT_COAST) * 2.0 - 1.0)
end

local function near(x, y, cx, cy, r)
    local dx, dy = x - cx, y - cy
    return dx * dx + dy * dy < r * r
end

-- Ground with no features on it (what mining/chopping reveals).
function ground_kind(x, y)
    if in_dungeon(x, y) then return K_FLOOR end
    local coast = coast_at(x, y)
    if coast > LAND_RADIUS - 5 then return K_SAND end -- beaches
    if value_noise(x, y, 26, SALT_SAND) > 0.62 then return K_SAND end
    return K_GRASS
end

function base_kind(x, y)
    if in_dungeon(x, y) then
        return dungeon_grid[din(x - DUNGEON_X0, y - DUNGEON_Y0)]
    end
    local coast = coast_at(x, y)
    if coast > DEEP_RADIUS then return K_DEEP end
    if coast > LAND_RADIUS then return K_SEA end
    if x >= FARM_X0 and x <= FARM_X1 and y >= FARM_Y0 and y <= FARM_Y1 then
        return K_FARM
    end
    local ground = ground_kind(x, y)
    -- Keep spawn and the boss arena free of blocking features.
    if near(x, y, 0, 0, SPAWN_CLEAR_R) or near(x, y, BOSS_ARENA_X, BOSS_ARENA_Y, BOSS_ARENA_R) then
        return ground
    end
    if coast < LAND_RADIUS - 6 and value_noise(x, y, 18, SALT_STONE) > 0.68 then
        return K_STONE
    end
    if ground == K_GRASS and value_noise(x, y, 10, SALT_TREE) > 0.60
            and hash01(x, y, SALT_TREE2) < 0.45 then
        return K_TREE
    end
    return ground
end

-- Effective kind: mutations override the pure terrain.
function kind_at(x, y)
    local m = muts[key_of(x, y)]
    if m then return m end
    return base_kind(x, y)
end

function is_walkable(x, y)
    local k = kind_at(x, y)
    return k ~= K_DEEP and k ~= K_SEA and k ~= K_STONE and k ~= K_TREE
end

-- =============================================================================
-- Painting tiles.
-- =============================================================================

local function paint(x, y, kind, was_stone)
    if kind == K_STONE then
        set_tile(x, y, Vector2(0, 0), TILESET_STONE) -- autotile picks the blob
        return
    end
    if was_stone then
        -- Erase through the autotile source first so neighbouring stone blobs
        -- re-fit around the new hole (see the Hide and Seek generator notes).
        set_tile(x, y, Vector2(-1, -1), TILESET_STONE)
    end
    local atlas = ATLAS[kind]
    set_tile(x, y, Vector2(atlas[1], atlas[2]), TILESET_MAIN)
end

-- =============================================================================
-- Mutations (host-ordered; -gm broadcasts and persists them).
-- =============================================================================

function apply_mut(x, y, kind)
    local was = kind_at(x, y)
    muts[key_of(x, y)] = kind
    local cx, cy = x // CHUNK_TILES, y // CHUNK_TILES
    if generated[key_of(cx, cy)] then
        paint(x, y, kind, was == K_STONE)
    end
end

function get_all_muts()
    return muts
end

function set_all_muts(new_muts)
    for k, v in pairs(new_muts) do
        local x, y = string.match(k, "(-?%d+),(-?%d+)")
        apply_mut(tonumber(x), tonumber(y), math.floor(v))
    end
end

function clear_all_muts()
    muts = {}
end

-- =============================================================================
-- Lazy chunk generation.
-- =============================================================================

local function generate_chunk(cx, cy)
    local ck = key_of(cx, cy)
    if generated[ck] then return end
    generated[ck] = true
    local tx0, ty0 = cx * CHUNK_TILES, cy * CHUNK_TILES
    for y = ty0, ty0 + CHUNK_TILES - 1 do
        for x = tx0, tx0 + CHUNK_TILES - 1 do
            local k = muts[key_of(x, y)] or base_kind(x, y)
            paint(x, y, k, false)
        end
    end
end

local function enqueue_chunk(cx, cy)
    if cx < WORLD_CHUNK_MIN or cx > WORLD_CHUNK_MAX
            or cy < WORLD_CHUNK_MIN or cy > WORLD_CHUNK_MAX then
        return
    end
    local ck = key_of(cx, cy)
    if generated[ck] or queued[ck] then return end
    queued[ck] = true
    table.insert(gen_queue, { cx, cy })
end

local function enqueue_around(world_pos)
    local tile = local_to_map(world_pos)
    local ccx = math.floor(tile.x) // CHUNK_TILES
    local ccy = math.floor(tile.y) // CHUNK_TILES
    for dy = -VIEW_CHUNK_RADIUS, VIEW_CHUNK_RADIUS do
        for dx = -VIEW_CHUNK_RADIUS, VIEW_CHUNK_RADIUS do
            enqueue_chunk(ccx + dx, ccy + dy)
        end
    end
end

function gen_scan()
    if seed == nil then return end
    if IS_HOST then
        -- The host simulates enemies near every player, so it needs their tiles.
        for _, user_name in ipairs(get_entity_names_by_tag("user")) do
            local pos = get_value("", user_name, "position")
            if pos then enqueue_around(pos) end
        end
    else
        local pos = get_value("", LOCAL_STEAM_ID, "position")
        if pos then enqueue_around(pos) end
    end
end

function gen_step()
    if #gen_queue == 0 then return end
    local entry = table.remove(gen_queue, 1)
    queued[key_of(entry[1], entry[2])] = nil
    generate_chunk(entry[1], entry[2])
end

-- =============================================================================
-- Lifecycle.
-- =============================================================================

-- Called by -gm on every peer once the seed is known (host start / join sync
-- / new world reset).
function set_seed(new_seed)
    if seed == new_seed then return end
    seed = math.floor(new_seed)
    -- A reset with tiles already placed: erase everything we generated.
    for ck in pairs(generated) do
        local cx, cy = string.match(ck, "(-?%d+),(-?%d+)")
        local tx0, ty0 = tonumber(cx) * CHUNK_TILES, tonumber(cy) * CHUNK_TILES
        for y = ty0, ty0 + CHUNK_TILES - 1 do
            for x = tx0, tx0 + CHUNK_TILES - 1 do
                set_tile(x, y, Vector2(-1, -1), TILESET_STONE)
                set_tile(x, y, Vector2(-1, -1), TILESET_MAIN)
            end
        end
    end
    generated = {}
    gen_queue = {}
    queued = {}
    muts = {}
    build_dungeon()
    -- Solid ground under everyone's feet immediately; the rest streams in.
    for cy = -1, 0 do
        for cx = -1, 0 do
            generate_chunk(cx, cy)
        end
    end
end

function get_dungeon_pois()
    return dungeon_pois
end

function is_seed_ready()
    return seed ~= nil
end

start_timer({ timer_id = "gen_scan", entity_name = name, function_name = "gen_scan",
    wait_time = GEN_SCAN_INTERVAL })
start_timer({ timer_id = "gen_step", entity_name = name, function_name = "gen_step",
    wait_time = GEN_STEP_INTERVAL })

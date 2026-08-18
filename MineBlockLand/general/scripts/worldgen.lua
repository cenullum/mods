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
K_SAPLING = 11 -- planted tree seed, grows into K_TREE (appended, don't renumber the above)
K_CACTUS = 12  -- desert-sand equivalent of a tree (blocks, choppable)
K_PALM = 13    -- beach-sand equivalent of a tree (blocks, choppable)
K_FLOWER = 14  -- purely decorative grass detail (walkable, not actionable)
K_WOOD_BLOCK = 15 -- player-placed wood block (mined/gathered material, not a tree)

local TILESET_STONE = 0 -- 47-blob autotile source (stone_47_blob_texture.png)
local TILESET_MAIN = 1  -- tiles.png
local TILESET_WOOD = 2  -- 47-blob autotile source (wood_atlas.png)

-- kind -> atlas coords in tiles.png
local ATLAS = {
    [K_GRASS] = { 1, 0 }, [K_SAND] = { 0, 0 }, [K_TREE] = { 2, 0 },
    [K_FARM] = { 3, 0 }, [K_FARM_SEEDED] = { 4, 0 }, [K_FARM_GROWN] = { 5, 0 },
    [K_SEA] = { 6, 0 }, [K_DEEP] = { 7, 0 }, [K_FLOOR] = { 0, 1 },
    [K_SAPLING] = { 1, 1 }, [K_CACTUS] = { 2, 1 }, [K_PALM] = { 3, 1 },
    [K_FLOWER] = { 4, 1 },
}

-- Kinds painted from an autotile source instead of a fixed ATLAS coord.
local AUTOTILE_SOURCES = { [K_STONE] = TILESET_STONE, [K_WOOD_BLOCK] = TILESET_WOOD }

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

-- Dungeon rect (64x64 tiles = 2x2 chunks of area), east of spawn, entrance west.
DUNGEON_X0, DUNGEON_Y0 = 120, -32
DUNGEON_SIZE = 64
local JUG_CORNER_CHANCE = 65 -- percent, rolled per room corner

-- Noise salts (any distinct constants).
local SALT_COAST, SALT_STONE, SALT_SAND, SALT_TREE, SALT_TREE2 = 11, 22, 33, 44, 55
local SALT_SPAWN_TREE = 66
local SALT_CACTUS, SALT_CACTUS2 = 77, 88
local SALT_PALM, SALT_PALM2 = 99, 110
local SALT_FLOWER = 121

-- Desert/beach flora is deliberately rarer than the grassland's trees: the
-- noise gate is tighter AND a per-tile hash thins out whatever survives it.
local CACTUS_NOISE, CACTUS_CHANCE = 0.66, 0.04
local PALM_NOISE, PALM_CHANCE = 0.62, 0.22
local FLOWER_CHANCE = 0.035 -- scattered single tiles, no clustering

local SPAWN_TREE_COUNT = 10 -- trees ringed near the edge of the spawn clearing

-- Chunk generation pacing. A whole 32x32 chunk in one frame is a visible
-- hitch, so queued chunks are painted a few ROWS per step instead.
local VIEW_CHUNK_RADIUS = 2      -- generate chunks this far around each player
local GEN_SCAN_INTERVAL = 0.3    -- how often player positions are checked
local GEN_STEP_INTERVAL = 0.05   -- one slice of the queued chunk per step
local GEN_ROWS_PER_STEP = 8      -- rows painted per step (8 x 32 tiles)
-- /openallmap's background queue paints twice as fast: it is a one-off request
-- with 256 chunks to get through, and it only ever runs while nothing a player
-- is actually walking into is waiting (see gen_step).
local REVEAL_ROWS_PER_STEP = 16

seed = nil                       -- set by -gm (host rolls it / save restores it)
local muts = {}                  -- "x,y" -> kind (host-ordered terrain changes)
local generated = {}             -- "cx,cy" -> true (fully painted)
local gen_queue = {}             -- array of {cx, cy, next_row}
local queued = {}                -- "cx,cy" -> true (queued or being painted)
local reveal_queue = {}          -- /openallmap: same shape, strictly lower priority
local dungeon_grid = nil         -- [local_y*64+local_x] -> K_FLOOR / K_STONE
local dungeon_pois = {}          -- {{type="chest"/"witch"/"brute", x, y, id}, ...}
local dungeon_entrance = nil     -- {x, y} tile of the west-side corridor mouth
local spawn_trees = {}           -- "x,y" -> true (ring of trees near the spawn clearing's edge)

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

-- Ring of SPAWN_TREE_COUNT trees near the edge of the spawn clearing (not on
-- top of the player, who spawns at the centre). Positions are pure functions
-- of 'seed' via hash01, so every peer computes the exact same ring.
local function build_spawn_trees()
    spawn_trees = {}
    local edge_r = SPAWN_CLEAR_R - 1
    for i = 1, SPAWN_TREE_COUNT do
        local angle = hash01(i, 0, SALT_SPAWN_TREE) * math.pi * 2.0
        local radius = edge_r * (0.7 + 0.3 * hash01(i, 1, SALT_SPAWN_TREE))
        local tx = math.floor(math.cos(angle) * radius + 0.5)
        local ty = math.floor(math.sin(angle) * radius + 0.5)
        spawn_trees[key_of(tx, ty)] = true
    end
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
    -- The door, in world tiles: what the map marker points at (the middle of a
    -- 64x64 stone block would just say "somewhere in there").
    dungeon_entrance = { x = DUNGEON_X0, y = DUNGEON_Y0 + entry.cy }

    -- Loot + guards: every room except the entrance gets a chest and guards.
    -- Every room (the entrance hall included) also gets clay jugs tucked into
    -- its corners - smash them for a chance at loot, or for nothing at all.
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
    -- Jugs are rolled in their own pass so they never shift the guard/chest
    -- placement of a seed that existed before jugs did.
    for i, room in ipairs(rooms) do
        local corners = {
            { room.x0 + 1, room.y0 + 1 }, { room.x1 - 1, room.y0 + 1 },
            { room.x0 + 1, room.y1 - 1 }, { room.x1 - 1, room.y1 - 1 },
        }
        for c, corner in ipairs(corners) do
            if rng_range(1, 100) <= JUG_CORNER_CHANCE then
                table.insert(dungeon_pois, { type = "jug", id = "dj" .. i .. "_" .. c,
                    x = DUNGEON_X0 + corner[1], y = DUNGEON_Y0 + corner[2] })
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

-- Which biome a tile belongs to, independent of whatever feature (tree, rock,
-- cactus...) happens to sit on it: "dungeon" | "deep" | "sea" | "beach" |
-- "desert" | "grass". Both sandy biomes read as K_SAND on the ground, but they
-- grow different things and host different wildlife, so the distinction lives
-- here once instead of being re-derived by every caller.
-- NOTE: every public entry point floors its coords - numbers that crossed the
-- Lua<->GDScript boundary come back as floats and "3.0" keys/hashes would
-- silently mismatch the integer ones used during generation.
function biome_at(x, y)
    x, y = math.floor(x), math.floor(y)
    if in_dungeon(x, y) then return "dungeon" end
    local coast = coast_at(x, y)
    if coast > DEEP_RADIUS then return "deep" end
    if coast > LAND_RADIUS then return "sea" end
    if coast > LAND_RADIUS - 5 then return "beach" end
    if value_noise(x, y, 26, SALT_SAND) > 0.62 then return "desert" end
    return "grass"
end

-- Ground with no features on it (what mining/chopping reveals).
function ground_kind(x, y)
    local biome = biome_at(x, y)
    if biome == "dungeon" then return K_FLOOR end
    if biome == "grass" then return K_GRASS end
    return K_SAND -- beach and desert share the sand tile
end

function base_kind(x, y)
    x, y = math.floor(x), math.floor(y)
    if in_dungeon(x, y) then
        return dungeon_grid[din(x - DUNGEON_X0, y - DUNGEON_Y0)]
    end
    local coast = coast_at(x, y)
    if coast > DEEP_RADIUS then return K_DEEP end
    if coast > LAND_RADIUS then return K_SEA end
    local ground = ground_kind(x, y)
    -- Keep spawn and the boss arena free of blocking features, except for a
    -- ring of trees near the edge of the spawn clearing (see spawn_trees).
    if near(x, y, 0, 0, SPAWN_CLEAR_R) then
        if ground == K_GRASS and spawn_trees[key_of(x, y)] then
            return K_TREE
        end
        return ground
    end
    if near(x, y, BOSS_ARENA_X, BOSS_ARENA_Y, BOSS_ARENA_R) then
        return ground
    end
    if coast < LAND_RADIUS - 6 and value_noise(x, y, 18, SALT_STONE) > 0.68 then
        return K_STONE
    end
    if ground == K_GRASS and value_noise(x, y, 10, SALT_TREE) > 0.60
            and hash01(x, y, SALT_TREE2) < 0.45 then
        return K_TREE
    end
    -- Sand grows its own (much sparser) flora: cacti inland, palms on the coast.
    if ground == K_SAND then
        local biome = biome_at(x, y)
        if biome == "desert" and value_noise(x, y, 12, SALT_CACTUS) > CACTUS_NOISE
                and hash01(x, y, SALT_CACTUS2) < CACTUS_CHANCE then
            return K_CACTUS
        end
        if biome == "beach" and value_noise(x, y, 9, SALT_PALM) > PALM_NOISE
                and hash01(x, y, SALT_PALM2) < PALM_CHANCE then
            return K_PALM
        end
        return ground
    end
    -- Grass that stayed bare gets the occasional flower (decoration only).
    if ground == K_GRASS and hash01(x, y, SALT_FLOWER) < FLOWER_CHANCE then
        return K_FLOWER
    end
    return ground
end

-- Effective kind: mutations override the pure terrain.
function kind_at(x, y)
    x, y = math.floor(x), math.floor(y)
    local m = muts[key_of(x, y)]
    if m then return m end
    return base_kind(x, y)
end

function is_walkable(x, y)
    local k = kind_at(math.floor(x), math.floor(y))
    return k ~= K_DEEP and k ~= K_SEA and k ~= K_STONE and k ~= K_TREE
        and k ~= K_CACTUS and k ~= K_PALM and k ~= K_WOOD_BLOCK
end

-- =============================================================================
-- Painting tiles.
-- =============================================================================

local function paint(x, y, kind, was_kind)
    local src = AUTOTILE_SOURCES[kind]
    if src then
        set_tile(x, y, Vector2(0, 0), src) -- autotile picks the blob
        return
    end
    local was_src = was_kind and AUTOTILE_SOURCES[was_kind]
    if was_src then
        -- Erase through the autotile source first so neighbouring blobs
        -- re-fit around the new hole (see the Hide and Seek generator notes).
        set_tile(x, y, Vector2(-1, -1), was_src)
    end
    local atlas = ATLAS[kind]
    set_tile(x, y, Vector2(atlas[1], atlas[2]), TILESET_MAIN)
end

-- =============================================================================
-- Mutations (host-ordered; -gm broadcasts and persists them).
-- =============================================================================

function apply_mut(x, y, kind)
    x, y, kind = math.floor(x), math.floor(y), math.floor(kind)
    local was = kind_at(x, y)
    muts[key_of(x, y)] = kind
    local cx, cy = x // CHUNK_TILES, y // CHUNK_TILES
    local ck = key_of(cx, cy)
    -- Paint if the chunk is on screen (fully painted OR currently streaming
    -- in row by row - an already-painted row would otherwise stay stale).
    if generated[ck] or queued[ck] then
        paint(x, y, kind, was)
    end
end

function get_all_muts()
    return muts
end

function set_all_muts(new_muts)
    for k, v in pairs(new_muts) do
        -- Tolerate float-form keys ("3.0,5.0") left behind by older saves.
        local x, y = string.match(k, "^(-?[%d%.]+),(-?[%d%.]+)$")
        if x and tonumber(x) and tonumber(y) then
            apply_mut(tonumber(x), tonumber(y), math.floor(v))
        end
    end
end

function clear_all_muts()
    muts = {}
end

-- =============================================================================
-- Lazy chunk generation.
-- =============================================================================

local function paint_chunk_rows(cx, cy, row0, row1)
    local tx0, ty0 = cx * CHUNK_TILES, cy * CHUNK_TILES
    for y = ty0 + row0, ty0 + row1 do
        for x = tx0, tx0 + CHUNK_TILES - 1 do
            local k = muts[key_of(x, y)] or base_kind(x, y)
            paint(x, y, k, nil)
        end
    end
end

-- Immediate, whole-chunk build (only for the spawn area at set_seed time).
local function generate_chunk(cx, cy)
    local ck = key_of(cx, cy)
    if generated[ck] then return end
    generated[ck] = true
    paint_chunk_rows(cx, cy, 0, CHUNK_TILES - 1)
end

local function enqueue_chunk(cx, cy)
    if cx < WORLD_CHUNK_MIN or cx > WORLD_CHUNK_MAX
            or cy < WORLD_CHUNK_MIN or cy > WORLD_CHUNK_MAX then
        return
    end
    local ck = key_of(cx, cy)
    if generated[ck] or queued[ck] then return end
    queued[ck] = true
    table.insert(gen_queue, { cx, cy, 0 })
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

-- =============================================================================
-- /openallmap: paint EVERY chunk of the island, so the G map (which is built
-- purely from the tiles this peer has actually placed - the engine's minimap is
-- a picture of the TileMapLayer, there is no separate overlay to draw on) shows
-- the whole thing instead of just where you have been.
--
-- Strictly background work: the reveal queue is only touched when gen_queue is
-- empty, so land a player is walking into is always painted first, and a chunk
-- that the normal generator claims in the meantime is simply dropped from it.
-- =============================================================================

local function reveal_step()
    local entry = reveal_queue[1]
    if not entry then return end
    local cx, cy, row = entry[1], entry[2], entry[3]
    local ck = key_of(cx, cy)
    if generated[ck] or queued[ck] then -- the player got there first
        table.remove(reveal_queue, 1)
        return
    end
    local last_row = math.min(row + REVEAL_ROWS_PER_STEP - 1, CHUNK_TILES - 1)
    paint_chunk_rows(cx, cy, row, last_row)
    if last_row >= CHUNK_TILES - 1 then
        table.remove(reveal_queue, 1)
        generated[ck] = true
        if #reveal_queue == 0 then
            run_function("-gm", "announce_local", { "{whole_island_on_map}" })
        end
    else
        entry[3] = last_row + 1
    end
end

-- Queues every not-yet-painted chunk in the world. Returns how many are left to
-- go, so the command that called it can say something useful.
function reveal_all()
    if seed == nil then return 0 end
    reveal_queue = {}
    for cy = WORLD_CHUNK_MIN, WORLD_CHUNK_MAX do
        for cx = WORLD_CHUNK_MIN, WORLD_CHUNK_MAX do
            local ck = key_of(cx, cy)
            if not generated[ck] and not queued[ck] then
                table.insert(reveal_queue, { cx, cy, 0 })
            end
        end
    end
    return #reveal_queue
end

function is_revealing()
    return #reveal_queue > 0
end

-- Paints GEN_ROWS_PER_STEP rows of the front chunk, spreading the work over
-- several frames so walking into new land never hitches. With nothing urgent
-- left, the same budget goes to an /openallmap reveal instead.
function gen_step()
    local entry = gen_queue[1]
    if not entry then
        reveal_step()
        return
    end
    local cx, cy, row = entry[1], entry[2], entry[3]
    local ck = key_of(cx, cy)
    if generated[ck] then -- built synchronously in the meantime (set_seed)
        table.remove(gen_queue, 1)
        queued[ck] = nil
        return
    end
    local last_row = math.min(row + GEN_ROWS_PER_STEP - 1, CHUNK_TILES - 1)
    paint_chunk_rows(cx, cy, row, last_row)
    if last_row >= CHUNK_TILES - 1 then
        table.remove(gen_queue, 1)
        queued[ck] = nil
        generated[ck] = true
    else
        entry[3] = last_row + 1
    end
end

-- =============================================================================
-- Lifecycle.
-- =============================================================================

-- Called by -gm on every peer once the seed is known (host start / join sync
-- / new world reset).
function set_seed(new_seed)
    if seed == new_seed then return end
    seed = math.floor(new_seed)
    -- A reset with tiles already placed: erase everything we generated,
    -- including chunks that were only partially streamed in.
    for ck in pairs(queued) do
        generated[ck] = true
    end
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
    reveal_queue = {}
    muts = {}
    build_spawn_trees()
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

-- Tile of the dungeon's west door (nil until a seed has been set).
function get_dungeon_entrance()
    return dungeon_entrance
end

-- Has this peer actually painted the chunk this tile sits in? That is what
-- "explored" means here: -gm uses it to decide when the dungeon has been found
-- and may go on the map.
function is_tile_generated(x, y)
    local cx = math.floor(x) // CHUNK_TILES
    local cy = math.floor(y) // CHUNK_TILES
    return generated[key_of(cx, cy)] == true
end

function is_seed_ready()
    return seed ~= nil
end

-- Forces the next set_seed call to run its full wipe even if the seed the
-- host ends up picking matches the one already loaded here. Called on every
-- peer when a boss-wiped run resets (game_manager.lua's boss_wipe_ALL):
-- set_seed's "if seed == new_seed then return" guard is there to skip
-- redundant repaints on ordinary re-syncs, but it also means picking the
-- SAME seed after a wipe left old mutations (chopped trees, mined stone,
-- placed blocks) sitting on the map untouched.
function force_wipe()
    seed = nil
end

-- Lets -wild derive its own deterministic hash from the same world seed
-- (see wildlife.lua's whash01) without duplicating -gen's seed bookkeeping.
function get_seed()
    return seed
end

start_timer({ timer_id = "gen_scan", entity_name = name, function_name = "gen_scan",
    wait_time = GEN_SCAN_INTERVAL })
start_timer({ timer_id = "gen_step", entity_name = name, function_name = "gen_step",
    wait_time = GEN_STEP_INTERVAL })

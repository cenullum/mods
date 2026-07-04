singleton_name = "hs_gen"
network_mode = 0

-- =============================================================================
-- Hide and Seek - deterministic procedural world generator (runs on EVERY peer).
--
-- The host chooses a single integer seed and the map dimensions and broadcasts
-- them; every peer then builds the *identical* cave locally from that seed, so no
-- tiles or item positions ever have to travel over the network. Same seed ->
-- same cave, same corridors, same item layout (fully deterministic).
--
-- Layout: a closed rectangle (solid outer wall, nobody escapes) filled with
-- rough-edged rectangular rooms joined by corridors. One room is the sealed
-- "seeker room" the seekers start locked inside. Items decorate the rooms only
-- (never corridors), thinning out toward room centres, with same-image clusters.
-- =============================================================================

-- Tunables ------------------------------------------------------------------
local ITEM_DENSITY = 0.9        -- base chance a room floor cell spawns an item (dense)
local CLUSTER_CHANCE = 0.4      -- chance an item copies a nearby item's image
local ITEM_SCALE = 1            -- item pixel size = native size * this (5/10/15 px)
local ITEM_JITTER = 8           -- max +/- px an item is nudged from its tile centre
local CORRIDOR_W = 3            -- corridor width in tiles
local ANNEX_ROWS = 28           -- rows reserved at the top for the sealed seeker room:
                                -- the main cave starts below this, so locked seekers
                                -- can't see the hiders (they arrive down a long corridor)
local ITEM_Z = 0                -- item render order (players sit above)
local TILESET_ID = 0
-- The deep filler ring beyond the actual map uses the SAME autotile source as
-- everything else. A second (non-autotile) source was tried here for speed, but
-- autotile only counts same-SOURCE neighbours (compute_autotile_coords checks
-- get_cell_source_id(neighbour) == source_id) - so cells right at the boundary
-- between two different sources compute an "edge" blob shape (as if that side
-- were open) even though a solid margin block visually sits there. That is a
-- real hole: the edge blob's collision polygon is missing a chunk exactly where
-- the two sources meet, letting players and raycasts pass straight through. One
-- shared autotile source keeps the whole solid mass - and its collision - seamless.
-- Extra solid tiles surrounding the map. Every cell here goes through the same
-- autotile neighbour-recompute cascade as the interior (see the note above), so
-- this is O(margin_area) EXTRA set_tile calls on top of the interior every
-- single generate() - and generate() runs on EVERY round, first erasing the
-- previous round's tiles then rebuilding, i.e. roughly DOUBLE this cost each
-- transition. At the original 32 (one chunk) a large map could add ~16,000
-- extra autotile placements; kept small since players can never actually reach
-- this ring (build_walls already seals the real cave/annex boundary).
local OUTER_MARGIN = 8

-- Generated state (queried by the host for spawn placement) -----------------
W = 0
H = 0
seeker_spawn = "(0, 0)"         -- world position string for seeker start
door_cells = {}                 -- {"x,y"} cells to seal/open the seeker room
hider_spawns = {}               -- array of world-position strings
_wall_cells = {}                -- every tile we placed this round (for cleanup)
_item_names = {}                -- every decoration image node placed this round
_item_counter = 0

-- Working grids (numeric index y*W+x) ---------------------------------------
local solid = {}                -- true = wall
local room_id = {}              -- >0 room index, 0 = corridor/none
local rooms = {}                -- { {x,y,w,h,cx,cy} , ... }

-- Deterministic RNG (Park-Miller minimal standard, 64-bit-int exact in Lua 5.4)
local rng_state = 1
local function rng_seed(s)
    rng_state = s % 2147483647
    if rng_state <= 0 then rng_state = rng_state + 2147483646 end
end
local function rng_int()
    rng_state = (rng_state * 16807) % 2147483647
    return rng_state
end
local function rng_range(a, b) -- inclusive integer range
    if b < a then return a end
    return a + (rng_int() % (b - a + 1))
end
local function rng_float() return (rng_int() - 1) / 2147483646 end

local function idx(x, y) return y * W + x end
local function in_bounds(x, y) return x >= 0 and y >= 0 and x < W and y < H end

-- Carve one floor cell (optionally tagging it as belonging to room r).
local function carve(x, y, r)
    if not in_bounds(x, y) then return end
    -- Never carve the 1-tile outer border: the map must stay closed.
    if x <= 0 or y <= 0 or x >= W - 1 or y >= H - 1 then return end
    solid[idx(x, y)] = false
    if r ~= nil then room_id[idx(x, y)] = r end
end

-- =============================================================================
-- Cleanup of the previous round's tiles/items before building a new cave.
-- =============================================================================
local function clear_world()
    for _, c in ipairs(_wall_cells) do
        set_tile(c[1], c[2], Vector2(-1, -1), c[3]) -- c[3] = the tileset id it was placed with
    end
    -- Seal tiles live on door cells that were floor (never tracked in _wall_cells),
    -- so erase them explicitly or they'd leave a phantom wall next round.
    for _, key in ipairs(door_cells) do
        local cx, cy = string.match(key, "(%-?%d+),(%-?%d+)")
        if cx then set_tile(tonumber(cx), tonumber(cy), Vector2(-1, -1), TILESET_ID) end
    end
    for _, iname in ipairs(_item_names) do
        destroy("-hs_gen", iname)
    end
    _wall_cells = {}
    _item_names = {}
    solid = {}
    room_id = {}
    rooms = {}
    door_cells = {}
    hider_spawns = {}
end

-- =============================================================================
-- Room + corridor carving.
-- =============================================================================
local function carve_room_rough(rx, ry, rw, rh, r)
    -- Solid rectangle interior...
    for y = ry, ry + rh - 1 do
        for x = rx, rx + rw - 1 do
            carve(x, y, r)
        end
    end
    -- ...then rough, cave-like bumps pushed outward from the rectangle edge
    -- (only ever ADD floor, so rooms can never get disconnected by roughening).
    for y = ry, ry + rh - 1 do
        if rng_float() < 0.5 then carve(rx - 1, y, r) end
        if rng_float() < 0.5 then carve(rx + rw, y, r) end
    end
    for x = rx, rx + rw - 1 do
        if rng_float() < 0.5 then carve(x, ry - 1, r) end
        if rng_float() < 0.5 then carve(x, ry + rh, r) end
    end
end

-- L-shaped corridor (horizontal then vertical) of width CORRIDOR_W. Corridor
-- cells are room_id 0 so no items ever spawn on the roads.
local function carve_corridor(x1, y1, x2, y2)
    local x = x1
    while x ~= x2 do
        for w = 0, CORRIDOR_W - 1 do carve(x, y1 + w, 0) end
        x = x + (x2 > x1 and 1 or -1)
    end
    local y = y1
    while y ~= y2 do
        for w = 0, CORRIDOR_W - 1 do carve(x2 + w, y, 0) end
        y = y + (y2 > y1 and 1 or -1)
    end
    for w1 = 0, CORRIDOR_W - 1 do
        for w2 = 0, CORRIDOR_W - 1 do carve(x2 + w1, y2 + w2, 0) end
    end
end

-- Vertical-then-horizontal corridor. Used for the seeker-room exit so it always
-- heads straight down into the map before turning, never back into the room.
local function carve_corridor_v_first(x1, y1, x2, y2)
    local y = y1
    while y ~= y2 do
        for w = 0, CORRIDOR_W - 1 do carve(x1 + w, y, 0) end
        y = y + (y2 > y1 and 1 or -1)
    end
    local x = x1
    while x ~= x2 do
        for w = 0, CORRIDOR_W - 1 do carve(x, y2 + w, 0) end
        x = x + (x2 > x1 and 1 or -1)
    end
    for w1 = 0, CORRIDOR_W - 1 do
        for w2 = 0, CORRIDOR_W - 1 do carve(x2 + w1, y2 + w2, 0) end
    end
end

-- Does a candidate room rectangle (padded) overlap the seeker room region?
local function overlaps_seeker(rx, ry, rw, rh)
    local s = rooms[1]
    if not s then return false end
    return not (rx + rw + 1 < s.x - 1 or rx - 1 > s.x + s.w + 1
        or ry + rh + 1 < s.y - 1 or ry - 1 > s.y + s.h + 1)
end

-- Re-solidify the seeker room's perimeter ring (except the door) so nothing that
-- was carved nearby can leave a second way out. Guarantees a single exit.
local function seal_perimeter()
    local s = rooms[1]
    local x0, y0, x1, y1 = s.x - 1, s.y - 1, s.x + s.w, s.y + s.h
    for x = x0, x1 do solid[idx(x, y0)] = true; solid[idx(x, y1)] = true end
    for y = y0, y1 do solid[idx(x0, y)] = true; solid[idx(x1, y)] = true end
    for _, key in ipairs(door_cells) do
        local cx, cy = string.match(key, "(%-?%d+),(%-?%d+)")
        solid[idx(tonumber(cx), tonumber(cy))] = false
    end
end

-- =============================================================================
-- Item placement (rooms only, thinner toward centres, mild same-image clusters).
-- =============================================================================
local function place_items()
    local files = get_file_names("general/images/items", "png")
    local by_size = { ["5x5"] = {}, ["10x10"] = {}, ["15x15"] = {} }
    for _, f in ipairs(files) do
        for key, list in pairs(by_size) do
            if string.sub(f, 1, #key + 1) == key .. "_" then
                table.insert(list, f)
            end
        end
    end
    -- Smaller items are denser, bigger items rarer (weighted picker).
    local weighted = {}
    local function add_weight(key, n)
        if #by_size[key] == 0 then return end
        for _ = 1, n do table.insert(weighted, key) end
    end
    add_weight("5x5", 6); add_weight("10x10", 3); add_weight("15x15", 1)
    if #weighted == 0 then return end

    local last_file = nil
    for y = 1, H - 2 do
        for x = 1, W - 2 do
            local r = room_id[idx(x, y)]
            -- Rooms only (r>1 skips corridors r==0 and the seeker room r==1).
            if (not solid[idx(x, y)]) and r and r > 1 then
                local room = rooms[r]
                -- Distance from room centre normalised to [0,1]: edges get more.
                local dx = (x - room.cx) / math.max(1, room.w * 0.5)
                local dy = (y - room.cy) / math.max(1, room.h * 0.5)
                local edge = math.min(1, math.sqrt(dx * dx + dy * dy))
                local chance = ITEM_DENSITY * (0.55 + 0.45 * edge)
                if rng_float() < chance then
                    local file
                    if last_file and rng_float() < CLUSTER_CHANCE then
                        file = last_file
                    else
                        local key = weighted[rng_range(1, #weighted)]
                        file = by_size[key][rng_range(1, #by_size[key])]
                    end
                    last_file = file
                    local native = tonumber(string.match(file, "^(%d+)x")) or 8
                    local px = native * ITEM_SCALE
                    local base = map_to_local(Vector2(x, y))
                    local jx = (rng_float() * 2 - 1) * ITEM_JITTER
                    local jy = (rng_float() * 2 - 1) * ITEM_JITTER
                    _item_counter = _item_counter + 1
                    local iname = "it" .. tostring(_item_counter)
                    set_image({
                        parent_name = "-hs_gen",
                        name = iname,
                        image_path = "items/" .. string.gsub(file, "%.png$", ""),
                        position = base + Vector2(jx, jy),
                        scale = Vector2(px, px),
                        z_index = ITEM_Z,
                    })
                    table.insert(_item_names, iname)
                end
            end
        end
    end
end

-- =============================================================================
-- Rasterise: fill EVERY solid (non-walkable) cell with a wall tile, so the
-- unwalkable areas read as solid rock rather than see-through background. The
-- walkable floor keeps no tile, so the map's repeating floor texture shows there.
-- =============================================================================
local function build_walls()
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            if solid[idx(x, y)] ~= false then -- nil (untouched) or true = wall
                set_tile(x, y, Vector2(0, 0), TILESET_ID) -- autotile ignores coords
                table.insert(_wall_cells, { x, y, TILESET_ID })
            end
        end
    end
end

-- =============================================================================
-- Deep filler ring: OUTER_MARGIN tiles of solid rock surrounding the whole map
-- (the actual cave/annex box already built by build_walls), same autotile source
-- as everything else so there is no seam (visual or collision) at the boundary.
-- =============================================================================
local function build_margin()
    local x0, y0 = -OUTER_MARGIN, -OUTER_MARGIN
    local x1, y1 = W + OUTER_MARGIN - 1, H + OUTER_MARGIN - 1
    for y = y0, y1 do
        local inside_rows = (y >= 0 and y < H)
        for x = x0, x1 do
            if not (inside_rows and x >= 0 and x < W) then
                set_tile(x, y, Vector2(0, 0), TILESET_ID) -- autotile ignores coords
                table.insert(_wall_cells, { x, y, TILESET_ID })
            end
        end
    end
end

-- =============================================================================
-- PUBLIC: build the whole world from a seed. Called on every peer.
-- =============================================================================
function generate(cfg)
    clear_world()
    rng_seed(math.floor(tonumber(cfg.seed) or 1))
    W = math.floor(tonumber(cfg.w) or 40)
    local main_h = math.floor(tonumber(cfg.h) or 40)
    local main_top = ANNEX_ROWS      -- first row of the main cave
    H = ANNEX_ROWS + main_h          -- annex on top, main cave below

    -- Everything starts solid; carving opens it up.
    for i = 0, W * H - 1 do solid[i] = true end

    -- The sealed seeker room sits alone in the top annex, far above the cave, so
    -- locked seekers cannot watch the hiders. Clean rectangle with a single 2-wide
    -- door on its bottom that opens onto a long corridor down into the main cave.
    local sw, sh = 8, 8
    local sx, sy = 3, 3
    rooms[1] = { x = sx, y = sy, w = sw, h = sh, cx = sx + math.floor(sw / 2), cy = sy + math.floor(sh / 2) }
    for y = sy, sy + sh - 1 do
        for x = sx, sx + sw - 1 do carve(x, y, 1) end
    end
    local door_x = sx + math.floor(sw / 2) - 1
    local door_y = sy + sh -- bottom ring row
    door_cells = { door_x .. "," .. door_y, (door_x + 1) .. "," .. door_y }
    seeker_spawn = vector2_to_string(map_to_local(Vector2(rooms[1].cx, rooms[1].cy)))

    -- Room 2 sits low in the main cave so the seeker corridor can run straight down.
    local r2w, r2h = rng_range(7, 12), rng_range(7, 12)
    local r2x = rng_range(4, W - r2w - 3)
    local r2y = rng_range(main_top + math.floor(main_h / 2), H - r2h - 3)
    rooms[2] = { x = r2x, y = r2y, w = r2w, h = r2h, cx = r2x + math.floor(r2w / 2), cy = r2y + math.floor(r2h / 2) }
    carve_room_rough(r2x, r2y, r2w, r2h, 2)

    -- Every other room is scattered through the MAIN cave only (never the annex).
    local target_rooms = math.max(5, math.floor((W * main_h) / 140))
    local next_r = 3
    local tries = 0
    while next_r <= target_rooms + 1 and tries < target_rooms * 12 do
        tries = tries + 1
        local rw = rng_range(6, 11)
        local rh = rng_range(6, 11)
        local rx = rng_range(2, W - rw - 3)
        local ry = rng_range(main_top, H - rh - 3)
        rooms[next_r] = { x = rx, y = ry, w = rw, h = rh, cx = rx + math.floor(rw / 2), cy = ry + math.floor(rh / 2) }
        carve_room_rough(rx, ry, rw, rh, next_r)
        next_r = next_r + 1
    end

    -- Chain the main-cave rooms together so it is one connected space.
    for r = 3, next_r - 1 do
        carve_corridor(rooms[r - 1].cx, rooms[r - 1].cy, rooms[r].cx, rooms[r].cy)
    end

    -- Seeker exit: open the door, drop a stub down, then a long vertical-first
    -- corridor all the way down through the annex gap to room 2 in the cave.
    for _, key in ipairs(door_cells) do
        local cx, cy = string.match(key, "(%-?%d+),(%-?%d+)")
        carve(tonumber(cx), tonumber(cy), 0)
    end
    for y = door_y, door_y + 2 do
        carve(door_x, y, 0); carve(door_x + 1, y, 0)
    end
    carve_corridor_v_first(door_x, door_y + 2, rooms[2].cx, rooms[2].cy)

    seal_perimeter()

    -- Hider spawn tiles: main-cave room centres only (never the seeker room).
    for r = 2, next_r - 1 do
        table.insert(hider_spawns, vector2_to_string(map_to_local(Vector2(rooms[r].cx, rooms[r].cy))))
    end
    if #hider_spawns == 0 then
        table.insert(hider_spawns,
            vector2_to_string(map_to_local(Vector2(math.floor(W / 2), main_top + math.floor(main_h / 2)))))
    end

    place_items()
    build_walls()
    build_margin()
    seal_room() -- start with the seeker room sealed
end

-- Seal the seeker room by dropping wall tiles onto its door cells.
function seal_room()
    for _, key in ipairs(door_cells) do
        local cx, cy = string.match(key, "(%-?%d+),(%-?%d+)")
        set_tile(tonumber(cx), tonumber(cy), Vector2(0, 0), TILESET_ID)
    end
end

-- Open the seeker room by erasing those door tiles again (autotile re-fits).
function open_room()
    for _, key in ipairs(door_cells) do
        local cx, cy = string.match(key, "(%-?%d+),(%-?%d+)")
        set_tile(tonumber(cx), tonumber(cy), Vector2(-1, -1), TILESET_ID)
    end
end

-- Host helpers ---------------------------------------------------------------
function get_seeker_spawn() return seeker_spawn end
function get_hider_spawns() return hider_spawns end

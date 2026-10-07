singleton_name = "gen"
network_mode = 0

-- =============================================================================
-- Beyaz Canavar - deterministic school generator (runs on EVERY peer).
--
-- The host picks one integer seed and broadcasts it; every peer then builds the
-- identical school from it, so no tile ever travels over the network. Same
-- seed -> same corridors, rooms, furniture, vents, exits and task objects.
-- Randomness is a Park-Miller generator (exact in Lua 5.4 integers) consumed in
-- a fixed order, plus a per-cell hash for cosmetic variants; never math.random
-- and never pairs() over a hash table (its order is not guaranteed).
--
-- Tiles (see general/maps/school/info.json):
--   id 0      opaque dual layer "Floor": lower terrain = wall (BASE), upper = wood
--   id 1..10  transparent dual layers, GROUP 1: the wall colours. Every wall cell
--             gets BASE plus one colour layer; the group makes neighbouring
--             colours join without drawing an edge between them.
--   11..      plain decoration tiles, looked up by file name (TILE["desk_..."])
--
-- The detention room (the lobby) is fixed and sealed, around the origin where
-- the engine spawns every player. The school is generated east of it.
-- =============================================================================

local V0 = Vector2(0, 0)
local ERASE = Vector2(-1, -1)

local T_FLOOR = 0
local WALL_COLOR = { corridor = 7, classroom = 4, library = 1, teachers = 2, principal = 6,
    office = 9, cafeteria = 8, toilet_girls = 5, toilet_boys = 5, lab = 3, storage = 10,
    detention = 6 }
local ROOM_TOKEN = { corridor = "{room_corridor}", classroom = "{room_classroom}",
    library = "{room_library}", teachers = "{room_teachers}", principal = "{room_principal}",
    office = "{room_office}", cafeteria = "{room_cafeteria}", toilet_girls = "{room_toilet_girls}",
    toilet_boys = "{room_toilet_boys}", lab = "{room_lab}", storage = "{room_storage}",
    detention = "{room_detention}" }

-- Geometry, in cells. The school rectangle includes its 2-thick outer wall.
local SX, SY, SW, SH = 40, -34, 96, 68
local OUTER = 2
-- Detention room interior (sealed, walls 2 thick around it).
local LX, LY, LW, LH = -7, -6, 14, 10

local MIN_ROOM = 5
local MAX_VENTS = 12
local CELLS_PER_FRAME = 500
local KIND_WALL, KIND_FLOOR = 1, 2

-- Plain tiles that collide (must match info.json "collision"); used to keep
-- every room walkable from its doors after furnishing it.
local SOLID_PREFIX = { "bin", "bookshelf", "cafeteria_table", "desk", "door", "double_chair",
    "food_display", "fridge", "locker", "park_bench", "sink", "student_desk", "tablet_chair" }

TILE = {}

seed = 0
ready = false
generation = 0

local kind = {}       -- cell key -> KIND_WALL / KIND_FLOOR
local room_of = {}    -- floor cell key -> room index (0 = doorway)
local color_of = {}   -- wall cell key -> wall colour layer
local deco = {}       -- cell key -> plain tile name
local clear = {}      -- cell key -> true: keep free (in front of doors, spawn spots)
local rooms = {}      -- [1] corridors, [2] detention, [3..] school rooms
local objects = {}    -- interactables, index = object id
local school_keys = {}  -- painted school cells, in paint order (cleared on a new seed)
local jobs = {}       -- paint queue: { op = "clear"|"paint", key = k }
local job_head = 1
local lobby_done = false
local minimap_names = {}
local vent_images = {}
local exit_images = {}

-- =============================================================================
-- Helpers
-- =============================================================================

local function K(x, y) return (y + 4096) * 8192 + (x + 4096) end
local function KX(k) return k % 8192 - 4096 end
local function KY(k) return k // 8192 - 4096 end

local rng_state = 1
local function rng_seed(s)
    rng_state = s % 2147483647
    if rng_state <= 0 then rng_state = rng_state + 2147483646 end
end
local function rng_next()
    rng_state = (rng_state * 16807) % 2147483647
    return rng_state
end
local function rng_int(a, b)
    if b <= a then return a end
    return a + rng_next() % (b - a + 1)
end
local function rng_float() return rng_next() / 2147483647 end
local function rng_pick(list) return list[rng_int(1, #list)] end

-- Per-cell hash (MineBlockLand's), for cosmetic variants that must not shift
-- the sequential RNG.
local function hash01(x, y, salt)
    local h = (seed or 0) + salt * 668265263
    h = (h ~ (x * 374761393)) % 0x100000000
    h = (h * 3266489917 + 374761393) % 0x100000000
    h = (h ~ (y * 668265263)) % 0x100000000
    h = (h * 2654435761) % 0x100000000
    h = h ~ (h >> 16)
    return (h % 0x100000000) / 0x100000000
end

local function is_floor(x, y) return kind[K(x, y)] == KIND_FLOOR end
local function is_wall(x, y) return kind[K(x, y)] == KIND_WALL end

local function set_floor(x, y, room)
    local k = K(x, y)
    kind[k] = KIND_FLOOR
    room_of[k] = room
end

local function set_wall(x, y)
    local k = K(x, y)
    kind[k] = KIND_WALL
    room_of[k] = nil
end

local function is_solid_tile(name)
    if not name then return false end
    for _, p in ipairs(SOLID_PREFIX) do
        if name:sub(1, #p) == p then return true end
    end
    return false
end

local function load_tile_ids()
    local info = load_json("general/maps/school/info.json")
    for _, ts in ipairs(info.tilesets or {}) do
        local path = tostring(ts.path or "")
        local base = path:match("([^/]+)%.png$")
        if base and ts.mode == "plain" then TILE[base] = math.floor(ts.id) end
    end
end

-- =============================================================================
-- Objects (interactables)
-- =============================================================================

local function add_object(obj_kind, x, y, room, extra)
    local obj = { id = #objects + 1, kind = obj_kind, x = x, y = y, room = room,
        rk = rooms[room] and rooms[room].kind or "corridor" }
    if extra then
        for _, field in ipairs({ "tile", "opened", "pair", "r", "g", "b", "exit_tile", "dy" }) do
            if extra[field] ~= nil then obj[field] = extra[field] end
        end
    end
    objects[obj.id] = obj
    return obj
end

local function can_place(x, y)
    local k = K(x, y)
    return kind[k] == KIND_FLOOR and room_of[k] ~= 0 and not clear[k] and not deco[k]
end

local function wall_free(x, y)
    local k = K(x, y)
    return kind[k] == KIND_WALL and not deco[k]
end

-- =============================================================================
-- Rooms: contacts across 1-thick wall lines, doors
-- =============================================================================

local parent = {}
local function uf_find(a)
    while parent[a] ~= a do
        parent[a] = parent[parent[a]]
        a = parent[a]
    end
    return a
end
local function uf_union(a, b)
    local ra, rb = uf_find(a), uf_find(b)
    if ra ~= rb then parent[ra] = rb end
end

-- Spans of a room side where the wall line has another room's floor behind it.
-- side: "n" | "s" | "w" | "e". Returns { {side, other, a, b}, ... } (a..b along the side).
local function side_contacts(r, side)
    local out = {}
    local cur = nil
    local len = (side == "n" or side == "s") and r.w or r.h
    for i = 0, len - 1 do
        local wx, wy, bx, by
        if side == "n" then wx, wy, bx, by = r.x + i, r.y - 1, r.x + i, r.y - 2
        elseif side == "s" then wx, wy, bx, by = r.x + i, r.y + r.h, r.x + i, r.y + r.h + 1
        elseif side == "w" then wx, wy, bx, by = r.x - 1, r.y + i, r.x - 2, r.y + i
        else wx, wy, bx, by = r.x + r.w, r.y + i, r.x + r.w + 1, r.y + i end
        local other = nil
        if is_wall(wx, wy) and is_floor(bx, by) then
            local o = room_of[K(bx, by)]
            if o and o > 0 then other = o end
        end
        if other and cur and cur.other == other and cur.b == i - 1 then
            cur.b = i
        else
            if cur then out[#out + 1] = cur end
            cur = other and { side = side, other = other, a = i, b = i } or nil
        end
    end
    if cur then out[#out + 1] = cur end
    return out
end

local function door_cell(r, side, i)
    if side == "n" then return r.x + i, r.y - 1 end
    if side == "s" then return r.x + i, r.y + r.h end
    if side == "w" then return r.x - 1, r.y + i end
    return r.x + r.w, r.y + i
end

-- Inward step (into room r) from a door cell on `side`.
local function inward(side)
    if side == "n" then return 0, 1 end
    if side == "s" then return 0, -1 end
    if side == "w" then return 1, 0 end
    return -1, 0
end

local function place_door(r, span, width)
    local a, b = span.a, span.b
    local lo, hi = a + 1, b - width
    if hi < lo then lo, hi = a, b - width + 1 end
    if hi < lo then return nil end
    local p = rng_int(lo, hi)
    local cells = {}
    local dx, dy = inward(span.side)
    for i = 0, width - 1 do
        local x, y = door_cell(r, span.side, p + i)
        set_floor(x, y, 0)
        cells[#cells + 1] = { x = x, y = y }
        -- Keep two cells free on both sides of the doorway.
        for d = 1, 2 do
            clear[K(x + dx * d, y + dy * d)] = true
            clear[K(x - dx * d, y - dy * d)] = true
        end
    end
    local door = { side = span.side, other = span.other, cells = cells }
    r.doors[#r.doors + 1] = door
    if rooms[span.other] and rooms[span.other].doors then
        rooms[span.other].doors[#rooms[span.other].doors + 1] = door
    end
    uf_union(r.id, span.other)
    return door
end

-- =============================================================================
-- Layout
-- =============================================================================

local function carve_rect(x0, y0, x1, y1, room)
    for y = y0, y1 do
        for x = x0, x1 do set_floor(x, y, room) end
    end
end

local function bsp(r, out)
    local can_x = r.w >= MIN_ROOM * 2 + 1
    local can_y = r.h >= MIN_ROOM * 2 + 1
    local area = r.w * r.h
    local want = r.w > 13 or r.h > 11 or area > 120
    if (not can_x and not can_y) or not want or (area <= 260 and rng_float() < 0.12) then
        out[#out + 1] = r
        return
    end
    local vertical
    if can_x and can_y then
        vertical = (r.w > r.h) or (r.w == r.h and rng_float() < 0.5)
    else
        vertical = can_x
    end
    if vertical then
        local p = rng_int(r.x + MIN_ROOM, r.x + r.w - 1 - MIN_ROOM)
        bsp({ x = r.x, y = r.y, w = p - r.x, h = r.h }, out)
        bsp({ x = p + 1, y = r.y, w = r.x + r.w - 1 - p, h = r.h }, out)
    else
        local p = rng_int(r.y + MIN_ROOM, r.y + r.h - 1 - MIN_ROOM)
        bsp({ x = r.x, y = r.y, w = r.w, h = p - r.y }, out)
        bsp({ x = r.x, y = p + 1, w = r.w, h = r.y + r.h - 1 - p }, out)
    end
end

local function build_corridors(ix0, iy0, ix1, iy1)
    local hcor, vcor = {}, {}
    local ih = iy1 - iy0 + 1
    local hcount = (rng_float() < 0.45) and 2 or 1
    for i = 1, hcount do
        local center = iy0 + (ih * i) // (hcount + 1) + rng_int(-3, 3)
        hcor[#hcor + 1] = { y0 = center - 1, y1 = center + 1 }
    end
    local iw = ix1 - ix0 + 1
    local vcount = rng_int(2, 3)
    local last_x1 = ix0 + 6
    for i = 1, vcount do
        local center = ix0 + (iw * i) // (vcount + 1) + rng_int(-4, 4)
        local width = (rng_float() < 0.35) and 3 or 2
        local x0 = math.max(center, last_x1 + 9)
        if x0 + width - 1 <= ix1 - 9 then
            local v = { x0 = x0, x1 = x0 + width - 1, y0 = iy0, y1 = iy1 }
            -- Some vertical corridors only run from a main corridor to one edge.
            if rng_float() < 0.35 then
                local h = hcor[rng_int(1, #hcor)]
                if rng_float() < 0.5 then v.y1 = h.y1 else v.y0 = h.y0 end
            end
            vcor[#vcor + 1] = v
            last_x1 = v.x1
        end
    end
    for _, h in ipairs(hcor) do carve_rect(ix0, h.y0, ix1, h.y1, 1) end
    for _, v in ipairs(vcor) do carve_rect(v.x0, v.y0, v.x1, v.y1, 1) end
    return hcor, vcor
end

-- Rectangles of non-corridor interior: bands between main corridors, split by
-- the vertical corridors crossing each band.
local function blocks_of(ix0, iy0, ix1, iy1, hcor, vcor)
    local bands = {}
    local y = iy0
    local sorted = {}
    for _, h in ipairs(hcor) do sorted[#sorted + 1] = h end
    table.sort(sorted, function(a, b) return a.y0 < b.y0 end)
    for _, h in ipairs(sorted) do
        if h.y0 - 1 >= y then bands[#bands + 1] = { y0 = y, y1 = h.y0 - 1 } end
        y = h.y1 + 1
    end
    if y <= iy1 then bands[#bands + 1] = { y0 = y, y1 = iy1 } end
    local out = {}
    for _, band in ipairs(bands) do
        local cuts = {}
        for _, v in ipairs(vcor) do
            if v.y0 <= band.y0 and v.y1 >= band.y1 then cuts[#cuts + 1] = v end
        end
        table.sort(cuts, function(a, b) return a.x0 < b.x0 end)
        local x = ix0
        for _, v in ipairs(cuts) do
            if v.x0 - 1 >= x then out[#out + 1] = { x0 = x, y0 = band.y0, x1 = v.x0 - 1, y1 = band.y1 } end
            x = v.x1 + 1
        end
        if x <= ix1 then out[#out + 1] = { x0 = x, y0 = band.y0, x1 = ix1, y1 = band.y1 } end
    end
    return out
end

local function room_center(r)
    return r.x + (r.w - 1) // 2, r.y + (r.h - 1) // 2
end

local function assign_types(school_rooms)
    -- Principal's office first: a medium room with a corridor behind its
    -- north or south wall, so its single (locked) door is a front-facing tile.
    local cands = {}
    for _, r in ipairs(school_rooms) do
        local area = r.w * r.h
        if area >= 25 and area <= 90 then
            for _, side in ipairs({ "n", "s" }) do
                for _, c in ipairs(side_contacts(r, side)) do
                    if c.other == 1 and c.b - c.a >= 2 then
                        cands[#cands + 1] = { room = r, span = c }
                        break
                    end
                end
            end
        end
    end
    local principal = nil
    if #cands > 0 then
        principal = rng_pick(cands)
        principal.room.kind = "principal"
        principal.room.principal_span = principal.span
    end
    local rest = {}
    for _, r in ipairs(school_rooms) do
        if r.kind == nil then rest[#rest + 1] = r end
    end
    table.sort(rest, function(a, b)
        if a.w * a.h ~= b.w * b.h then return a.w * a.h > b.w * b.h end
        return a.id < b.id
    end)
    local function take_largest(t)
        if #rest > 0 then
            local r = table.remove(rest, 1)
            r.kind = t
        end
    end
    local function take_smallest(t)
        if #rest > 0 then
            local r = table.remove(rest, #rest)
            r.kind = t
        end
    end
    take_largest("cafeteria")
    take_largest("library")
    take_smallest("toilet_girls")
    take_smallest("toilet_boys")
    take_smallest("storage")
    take_smallest("office")
    -- Medium rooms for the staff room and the computer lab.
    if #rest > 0 then
        local r = table.remove(rest, (#rest + 1) // 2)
        r.kind = "teachers"
    end
    if #rest > 2 then
        local r = table.remove(rest, (#rest + 1) // 2)
        r.kind = "lab"
    end
    for _, r in ipairs(rest) do r.kind = "classroom" end
end

local function connect_rooms(school_rooms)
    parent = {}
    for i = 1, #rooms do parent[i] = i end
    -- Principal: exactly one 1-wide door to the corridor (the locked one).
    for _, r in ipairs(school_rooms) do
        if r.kind == "principal" and r.principal_span then
            local door = place_door(r, r.principal_span, 1)
            if door then
                local c = door.cells[1]
                deco[K(c.x, c.y)] = "door3"
                r.locked_door = add_object("pdoor", c.x, c.y, r.id, { tile = "door3" })
            end
        end
    end
    -- Everyone with a corridor behind a wall gets a 2-wide door to it (big rooms two).
    for _, r in ipairs(school_rooms) do
        if r.kind ~= "principal" then
            local spans = {}
            for _, side in ipairs({ "n", "s", "w", "e" }) do
                for _, c in ipairs(side_contacts(r, side)) do
                    if c.other == 1 and c.b - c.a >= 1 then spans[#spans + 1] = c end
                end
            end
            table.sort(spans, function(a, b)
                if a.b - a.a ~= b.b - b.a then return a.b - a.a > b.b - b.a end
                return a.side < b.side
            end)
            if #spans > 0 then
                place_door(r, spans[1], 2)
                local big = r.kind == "cafeteria" or r.kind == "library"
                if #spans > 1 and (big or rng_float() < 0.25) then place_door(r, spans[2], 2) end
            end
        end
    end
    -- Rooms with no corridor: join a connected neighbour until everything is one.
    local changed = true
    while changed do
        changed = false
        for _, r in ipairs(school_rooms) do
            if r.kind ~= "principal" and uf_find(r.id) ~= uf_find(1) then
                local best = nil
                for _, side in ipairs({ "n", "s", "w", "e" }) do
                    for _, c in ipairs(side_contacts(r, side)) do
                        local o = rooms[c.other]
                        if c.b - c.a >= 1 and o and o.kind ~= "principal" and uf_find(c.other) == uf_find(1) then
                            best = best or c
                        end
                    end
                end
                if best then
                    place_door(r, best, 2)
                    changed = true
                end
            end
        end
    end
    -- Still isolated (only isolated neighbours): link to any neighbour and retry.
    for _, r in ipairs(school_rooms) do
        if r.kind ~= "principal" and uf_find(r.id) ~= uf_find(1) then
            for _, side in ipairs({ "n", "s", "w", "e" }) do
                for _, c in ipairs(side_contacts(r, side)) do
                    local o = rooms[c.other]
                    if c.b - c.a >= 1 and o and o.kind ~= "principal" and uf_find(c.other) ~= uf_find(r.id) then
                        place_door(r, c, 2)
                    end
                end
            end
        end
    end
    -- Extra doors between neighbouring rooms: loops, "rooms lead into rooms".
    for _, r in ipairs(school_rooms) do
        if r.kind ~= "principal" then
            for _, side in ipairs({ "e", "s" }) do
                for _, c in ipairs(side_contacts(r, side)) do
                    local o = rooms[c.other]
                    if c.other > 2 and o and o.kind ~= "principal" and c.b - c.a >= 2 and rng_float() < 0.3 then
                        place_door(r, c, 2)
                    end
                end
            end
        end
    end
end

-- =============================================================================
-- Furnishing
-- =============================================================================

local placed = {}   -- this room's furniture keys, for rollback
local pending = {}  -- floor interactables waiting for the walkability check

-- Floor furniture. Its interactable is only registered by commit_room(), after
-- ensure_walkable() decided whether the piece stays.
local function put(x, y, name, obj_kind, room, extra)
    if not can_place(x, y) then return false end
    local k = K(x, y)
    deco[k] = name
    placed[#placed + 1] = k
    if obj_kind then
        extra = extra or {}
        extra.tile = name
        pending[#pending + 1] = { kind = obj_kind, x = x, y = y, room = room, extra = extra, key = k, name = name }
    end
    return true
end

local function begin_room()
    placed = {}
    pending = {}
end

local function commit_room()
    for _, p in ipairs(pending) do
        if deco[p.key] == p.name then add_object(p.kind, p.x, p.y, p.room, p.extra) end
    end
    placed = {}
    pending = {}
end

local function put_wall(x, y, name, obj_kind, room, extra)
    if not wall_free(x, y) then return nil end
    deco[K(x, y)] = name
    if obj_kind then
        clear[K(x, y + 1)] = true  -- someone has to be able to stand in front of it
        extra = extra or {}
        extra.tile = name
        return add_object(obj_kind, x, y, room, extra)
    end
    return nil
end

-- Every free floor cell of the room must be reachable from a door (or from the
-- room's first free cell for the sealed lobby); undo furniture until it is.
local function ensure_walkable(r)
    local function free(x, y)
        local k = K(x, y)
        return kind[k] == KIND_FLOOR and not is_solid_tile(deco[k])
    end
    local function check()
        local start = nil
        for _, door in ipairs(r.doors) do
            local c = door.cells[1]
            if free(c.x, c.y) then start = c break end
        end
        if not start then
            for y = r.y, r.y + r.h - 1 do
                for x = r.x, r.x + r.w - 1 do
                    if not start and free(x, y) then start = { x = x, y = y } end
                end
            end
        end
        if not start then return true end
        local seen = { [K(start.x, start.y)] = true }
        local queue = { start }
        local head = 1
        while head <= #queue do
            local c = queue[head]
            head = head + 1
            for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                local nx, ny = c.x + d[1], c.y + d[2]
                local inside = nx >= r.x - 1 and nx <= r.x + r.w and ny >= r.y - 1 and ny <= r.y + r.h
                local nk = K(nx, ny)
                if inside and not seen[nk] and free(nx, ny) then
                    seen[nk] = true
                    queue[#queue + 1] = { x = nx, y = ny }
                end
            end
        end
        for y = r.y, r.y + r.h - 1 do
            for x = r.x, r.x + r.w - 1 do
                if free(x, y) and not seen[K(x, y)] then return false end
            end
        end
        return true
    end
    while not check() and #placed > 0 do
        deco[table.remove(placed)] = nil
    end
end

local function north_wall_cells(r)
    local out = {}
    for x = r.x, r.x + r.w - 1 do
        if is_wall(x, r.y - 1) then out[#out + 1] = x end
    end
    return out
end

local function is_exterior_north(y)
    return y == SY + OUTER - 1 or y == LY - 1
end

local DESK_VARIANTS = { "student_desk_with_apple", "student_desk_with_book", "double_chair_student_desk",
    "tablet_chair", "tablet_chair_double" }
local CHAIRS = { "chair1", "chair2", "chair3" }
local BINS = { "bin1", "bin2", "bin3" }
local BOARDS = { "blackboard", "blackboard1", "blackboard2" }

local function wall_decor(r, salt, allow_windows)
    for _, x in ipairs(north_wall_cells(r)) do
        local y = r.y - 1
        local h = hash01(x, y, salt)
        if allow_windows and is_exterior_north(y) and (x - r.x) % 3 == 1 then
            put_wall(x, y, (h < 0.6) and "window" or ((h < 0.8) and "window2" or "window3"))
        elseif h < 0.05 then
            put_wall(x, y, (h < 0.025) and "blood_wall1" or "blood_wall3")
        end
    end
end

local function scatter_blood(r, salt)
    for y = r.y, r.y + r.h - 1 do
        for x = r.x, r.x + r.w - 1 do
            local h = hash01(x, y, salt)
            if h < 0.025 and can_place(x, y) then
                deco[K(x, y)] = (h < 0.008) and "blood_floor" or ((h < 0.016) and "blood_floor2" or "blood_floor4")
            end
        end
    end
end

local function corner_bin(r, salt)
    local spots = { { r.x, r.y + r.h - 1 }, { r.x + r.w - 1, r.y + r.h - 1 }, { r.x + r.w - 1, r.y } }
    local s = spots[1 + math.floor(hash01(r.x, r.y, salt) * #spots) % #spots]
    put(s[1], s[2], BINS[1 + math.floor(hash01(s[1], s[2], salt + 1) * 3) % 3], "bin", r.id)
end

local function furnish_classroom(r, salt)
    local cx = r.x + (r.w - 1) // 2
    local walls = north_wall_cells(r)
    put_wall(cx, r.y - 1, BOARDS[1 + math.floor(hash01(cx, r.y, salt) * 3) % 3])
    if r.w >= 9 then put_wall(cx - 2, r.y - 1, "blackboard_with_map") end
    if #walls > 0 then put_wall(walls[#walls], r.y - 1, (hash01(r.x, r.y, salt) < 0.5) and "clock" or "clock2") end
    wall_decor(r, salt, true)
    put(cx, r.y + 1, (hash01(cx, r.y, salt + 3) < 0.5) and "desk_with_desktop_globe" or "desk_with_computer2")
    for y = r.y + 3, r.y + r.h - 2, 2 do
        for x = r.x + 1, r.x + r.w - 2, 2 do
            local h = hash01(x, y, salt + 5)
            if h < 0.9 then
                local name = DESK_VARIANTS[1 + math.floor(h * 100) % #DESK_VARIANTS]
                if h < 0.04 then name = "desk_with_blood" end
                put(x, y, name)
            end
        end
    end
    corner_bin(r, salt)
end

local function furnish_detention(r, salt)
    local cx = r.x + (r.w - 1) // 2
    put_wall(cx, r.y - 1, "blackboard2")
    put_wall(cx + 2, r.y - 1, "clock")
    put_wall(cx - 3, r.y - 1, "bulletin_board2")
    wall_decor(r, salt, true)
    for _, row in ipairs({ r.y + 1, r.y + r.h - 2 }) do
        for x = r.x + 1, r.x + r.w - 2, 2 do
            if x < -2 or x > 2 then put(x, row, DESK_VARIANTS[1 + (x + 50) % #DESK_VARIANTS]) end
        end
    end
    put(r.x, r.y + r.h - 1, "bin2")
    put(r.x + r.w - 1, r.y + r.h - 1, "desk_with_blood")
    deco[K(r.x + 2, r.y + 4)] = "blood_floor"
    deco[K(r.x + r.w - 3, r.y + 3)] = "blood_floor2"
end

local function furnish_library(r, salt)
    wall_decor(r, salt, true)
    for y = r.y, r.y + r.h - 2, 3 do
        for x = r.x + 1, r.x + r.w - 2 do
            if (x - r.x) % 5 ~= 0 then
                local h = hash01(x, y, salt)
                if h < 0.85 then
                    put(x, y, (h < 0.45) and "bookshelf1" or "bookshelf2", "shelf", r.id, { opened = "bookshelf_empty" })
                else
                    put(x, y, "bookshelf_empty")
                end
            end
        end
    end
    corner_bin(r, salt)
end

local function furnish_cafeteria(r, salt)
    wall_decor(r, salt, true)
    local cx = r.x + (r.w - 1) // 2
    for x = r.x + 1, r.x + r.w - 2 do
        if math.abs(x - cx) > 1 then
            put(x, r.y, ((x % 2) == 0) and "food_display_counter1" or "food_display _counter2")
        end
    end
    put(r.x, r.y, "fridge_closed")
    put(r.x + r.w - 1, r.y, (hash01(r.x, r.y, salt) < 0.5) and "fridge_opened" or "fridge_closed")
    for y = r.y + 3, r.y + r.h - 2, 3 do
        for x = r.x + 1, r.x + r.w - 3, 4 do
            put(x, y, "cafeteria_table")
            put(x + 1, y, "cafeteria_table")
            put(x, y - 1, CHAIRS[1 + (x + y) % 3])
            put(x + 1, y + 1, CHAIRS[1 + (x * 3 + y) % 3])
        end
    end
    put(r.x, r.y + r.h - 1, "bin1", "bin", r.id)
    put(r.x + r.w - 1, r.y + r.h - 1, "bin2", "bin", r.id)
end

local function furnish_teachers(r, salt)
    local walls = north_wall_cells(r)
    local cx = r.x + (r.w - 1) // 2
    local board_x = nil
    for _, x in ipairs(walls) do
        if not board_x and math.abs(x - cx) <= 2 then board_x = x end
    end
    board_x = board_x or walls[1]
    if board_x then
        put_wall(board_x, r.y - 1, "bulletin_board1", "board", r.id)
    end
    if #walls > 1 then put_wall(walls[#walls], r.y - 1, "clock2") end
    wall_decor(r, salt, true)
    put(r.x + 1, r.y, "desk_metal_with_many_papers", "desk", r.id)
    put(r.x + r.w - 1, r.y, "fridge_closed")
    local cy = r.y + (r.h - 1) // 2 + 1
    for x = cx - 1, cx + 1 do
        put(x, cy, "cafeteria_table")
        put(x, cy - 1, CHAIRS[1 + x % 3])
        put(x, cy + 1, CHAIRS[1 + (x + 1) % 3])
    end
    for x = r.x + 1, r.x + r.w - 2, 3 do
        put(x, r.y + r.h - 1, (x % 2 == 0) and "desk_with_computer" or "desk_with_computer2")
    end
    corner_bin(r, salt)
end

local function furnish_principal(r, salt)
    local cx = r.x + (r.w - 1) // 2
    put_wall(cx, r.y - 1, "blackboard_with_map")
    put_wall(r.x, r.y - 1, "clock")
    wall_decor(r, salt, true)
    local cy = r.y + 1
    if r.locked_door and r.locked_door.y == r.y - 1 then cy = r.y + r.h - 2 end
    put(cx, cy, "desk_with_computer", "computer", r.id)
    put(cx, cy + ((cy == r.y + 1) and 1 or -1), "chair2")
    put(r.x, r.y, "bookshelf1")
    put(r.x + r.w - 1, r.y, "bookshelf2")
    put(r.x + r.w - 1, r.y + r.h - 1, "desk_metal_with_many_papers")
    put(r.x, r.y + r.h - 1, "bin3", "bin", r.id)
    scatter_blood(r, salt + 7)
end

local function furnish_office(r, salt)
    local walls = north_wall_cells(r)
    if #walls > 0 then put_wall(walls[1], r.y - 1, "bulletin_board2") end
    if #walls > 2 then put_wall(walls[#walls], r.y - 1, "fire_extinguisher2") end
    wall_decor(r, salt, true)
    for x = r.x + 1, r.x + r.w - 2, 2 do
        put(x, r.y + 1, (x % 4 == 1) and "desk_with_computer" or "desk_metal_with_many_papers")
        put(x, r.y + 2, CHAIRS[1 + x % 3])
    end
    put(r.x + r.w - 1, r.y + r.h - 1, "bookshelf_empty")
    corner_bin(r, salt)
end

local function furnish_toilet(r, salt)
    for x = r.x, r.x + r.w - 1, 2 do
        if is_wall(x, r.y - 1) then put_wall(x, r.y - 1, "sink", "sink", r.id) end
    end
    wall_decor(r, salt, false)
    put(r.x, r.y + r.h - 1, "bin3", "bin", r.id)
    scatter_blood(r, salt + 9)
end

local function furnish_storage(r, salt)
    for x = r.x + 1, r.x + r.w - 2 do
        local h = hash01(x, r.y, salt)
        put(x, r.y, (h < 0.5) and "locker_grey_closed" or ((h < 0.75) and "locker_grey_opened" or "locker_green_closed"))
    end
    for y = r.y + 1, r.y + r.h - 2, 2 do put(r.x, y, "bookshelf_empty") end
    put(r.x + r.w - 1, r.y + r.h - 1, "desk_metal_with_many_papers")
    put(r.x + r.w - 1, r.y, "bin1", "bin", r.id)
    scatter_blood(r, salt + 11)
end

local function furnish_lab(r, salt)
    wall_decor(r, salt, true)
    local cx = r.x + (r.w - 1) // 2
    put_wall(cx, r.y - 1, "blackboard1")
    for y = r.y + 1, r.y + r.h - 2, 3 do
        for x = r.x + 1, r.x + r.w - 2, 2 do
            put(x, y, (hash01(x, y, salt) < 0.5) and "desk_with_computer" or "desk_with_computer2")
            put(x, y + 1, CHAIRS[1 + (x + y) % 3])
        end
    end
    corner_bin(r, salt)
end

local FURNISH = { classroom = furnish_classroom, library = furnish_library, cafeteria = furnish_cafeteria,
    teachers = furnish_teachers, principal = furnish_principal, office = furnish_office,
    toilet_girls = furnish_toilet, toilet_boys = furnish_toilet, storage = furnish_storage, lab = furnish_lab,
    detention = furnish_detention }

-- Corridors: lockers, windows (exterior only), boards, clocks, extinguishers on
-- the walls above them; a few bins and benches along their south walls.
-- Wall decorations keep their distance: no two clocks / extinguishers / boards
-- side by side. last_any[row] / last_of[kind][row] remember the previous x.
local last_any, last_of = {}, {}
local WALL_GAP = { clock = 14, fire_extinguisher = 10, bulletin_board = 6, window = 3, blood_wall = 8 }

local function wall_spaced(x, y, family)
    if last_any[y] and x - last_any[y] < 2 then return false end
    local per = last_of[family]
    if per and per[y] and x - per[y] < (WALL_GAP[family] or 3) then return false end
    return true
end

local function put_wall_spaced(x, y, name, family)
    if not wall_spaced(x, y, family) then return false end
    if not wall_free(x, y) then return false end
    put_wall(x, y, name)
    last_any[y] = x
    last_of[family] = last_of[family] or {}
    last_of[family][y] = x
    return true
end

local LOCKERS = {
    { "locker_closed_red", "locker_opened_red" },
    { "locker_grey_closed", "locker_grey_opened" },
}

-- Corridors: a row of lockers standing on the floor along the north wall of the
-- 3-wide main corridors; windows (exterior only), notice boards, clocks and
-- extinguishers spaced out on the walls; a few bins and benches by the south wall.
local function furnish_corridors(salt)
    last_any, last_of = {}, {}
    local run_left = 0
    for y = SY + 1, SY + SH - 2 do
        run_left = 0
        for x = SX + 1, SX + SW - 2 do
            local k = K(x, y)
            local below = K(x, y + 1)
            local above = K(x, y - 1)
            -- Wall decoration above a corridor.
            if kind[k] == KIND_WALL and not deco[k] and kind[below] == KIND_FLOOR and room_of[below] == 1 then
                local h = hash01(x, y, salt)
                if is_exterior_north(y) and h < 0.45 then
                    put_wall_spaced(x, y, (h < 0.3) and "window" or "window3", "window")
                elseif h < 0.52 then
                    put_wall_spaced(x, y, (h < 0.49) and "bulletin_board1" or "bulletin_board2", "bulletin_board")
                elseif h < 0.56 then
                    put_wall_spaced(x, y, (h < 0.54) and "clock" or "clock2", "clock")
                elseif h < 0.6 then
                    put_wall_spaced(x, y, (h < 0.58) and "fire_extinguisher1" or "fire_extinguisher2", "fire_extinguisher")
                elseif h < 0.62 then
                    put_wall_spaced(x, y, "blood_wall2", "blood_wall")
                end
            end
            -- Lockers: top row of a 3-wide corridor (wall above, corridor below twice).
            local top_row = kind[k] == KIND_FLOOR and room_of[k] == 1 and kind[above] == KIND_WALL
                and room_of[below] == 1 and room_of[K(x, y + 2)] == 1
            if top_row then
                if run_left > 0 then
                    run_left = run_left - 1
                    local hv = hash01(x, y, salt + 1)
                    local placed_it
                    if hv < 0.7 then
                        local pair = LOCKERS[1 + math.floor(hv * 10) % 2]
                        placed_it = put(x, y, pair[1], "locker", 1, { opened = pair[2] })
                    else
                        placed_it = put(x, y, (hv < 0.85) and "locker_blue_closed" or "locker_green_closed")
                    end
                    if not placed_it then run_left = 0 end
                elseif hash01(x, y, salt + 4) < 0.1 then
                    local pair = LOCKERS[2]
                    if put(x, y, pair[1], "locker", 1, { opened = pair[2] }) then
                        run_left = 2 + math.floor(hash01(x, y, salt + 2) * 4)
                    end
                end
            else
                run_left = 0
            end
            -- Floor props against a south wall, only in 3-wide corridors.
            local above2 = K(x, y - 2)
            if kind[k] == KIND_FLOOR and room_of[k] == 1 and kind[below] == KIND_WALL
                and kind[above2] == KIND_FLOOR and room_of[above2] == 1 and room_of[above] == 1 then
                local hf = hash01(x, y, salt + 3)
                if hf < 0.03 then
                    put(x, y, BINS[1 + math.floor(hf * 300) % 3], "bin", 1)
                elseif hf < 0.05 then
                    put(x, y, "park_bench")
                elseif hf < 0.07 then
                    deco[k] = deco[k] or "blood_floor4"
                end
            end
        end
    end
end

-- =============================================================================
-- Exits, vents, wall colours, spawn data
-- =============================================================================

local function pick_exits()
    local cands = {}
    local function consider(x, y, dy)
        local inner = K(x, y + dy)
        local k = K(x, y)
        if kind[k] == KIND_WALL and not deco[k] and kind[inner] == KIND_FLOOR then
            local ro = room_of[inner]
            if ro and ro > 0 and rooms[ro].kind ~= "principal" and not clear[inner] then
                cands[#cands + 1] = { x = x, y = y, dy = dy }
            end
        end
    end
    for x = SX + OUTER + 1, SX + SW - OUTER - 2 do
        consider(x, SY + OUTER - 1, 1)
        consider(x, SY + SH - OUTER, -1)
    end
    if #cands == 0 then return end
    local chosen = {}
    local first = cands[1 + math.floor(hash01(seed % 9973, 7, 41) * #cands) % #cands]
    chosen[1] = first
    while #chosen < 5 and #chosen < #cands do
        local best, best_d = nil, -1
        for _, c in ipairs(cands) do
            local d = math.huge
            for _, o in ipairs(chosen) do
                local dd = (c.x - o.x) ^ 2 + (c.y - o.y) ^ 2
                if dd < d then d = dd end
            end
            if d > best_d then best, best_d = c, d end
        end
        chosen[#chosen + 1] = best
    end
    for i, c in ipairs(chosen) do
        deco[K(c.x, c.y)] = "__exit"  -- reserved; drawn only once the exits open
        clear[K(c.x, c.y + c.dy)] = true
        add_object("exit", c.x, c.y, room_of[K(c.x, c.y + c.dy)],
            { exit_tile = (i % 2 == 1) and "door_exit" or "door_Exit2", dy = c.dy })
    end
end

local VENT_COLORS = { { 1.0, 0.35, 0.35 }, { 0.35, 1.0, 0.45 }, { 0.4, 0.6, 1.0 }, { 1.0, 0.9, 0.3 },
    { 1.0, 0.45, 1.0 }, { 0.35, 1.0, 1.0 }, { 1.0, 0.65, 0.25 }, { 0.85, 0.85, 0.85 } }

local function pick_vents(school_rooms)
    local list = {}
    for _, r in ipairs(school_rooms) do
        if r.kind ~= "principal" and rng_float() < 0.4 then
            local spots = {}
            for _, x in ipairs(north_wall_cells(r)) do
                if wall_free(x, r.y - 1) and not clear[K(x, r.y)] then spots[#spots + 1] = x end
            end
            if #spots > 0 then
                list[#list + 1] = { room = r, x = rng_pick(spots), y = r.y - 1 }
            end
        end
    end
    while #list > MAX_VENTS do table.remove(list, rng_int(1, #list)) end
    if #list % 2 == 1 then table.remove(list) end
    table.sort(list, function(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    local half = #list // 2
    for i = 1, half do
        local a, b = list[i], list[i + half]
        local col = VENT_COLORS[1 + (i - 1) % #VENT_COLORS]
        deco[K(a.x, a.y)] = "__vent"
        deco[K(b.x, b.y)] = "__vent"
        clear[K(a.x, a.y + 1)] = true
        clear[K(b.x, b.y + 1)] = true
        local oa = add_object("vent", a.x, a.y, a.room.id, { r = col[1], g = col[2], b = col[3] })
        local ob = add_object("vent", b.x, b.y, b.room.id, { r = col[1], g = col[2], b = col[3] })
        oa.pair = ob.id
        ob.pair = oa.id
    end
end

local function colour_walls(x0, y0, x1, y1)
    for y = y0, y1 do
        for x = x0, x1 do
            local k = K(x, y)
            if kind[k] == KIND_WALL then
                local best, best_corridor = nil, false
                for dy = -1, 1 do
                    for dx = -1, 1 do
                        local nk = K(x + dx, y + dy)
                        if kind[nk] == KIND_FLOOR then
                            local ro = room_of[nk]
                            if ro and ro > 1 then
                                if not best or ro < best then best = ro end
                            else
                                best_corridor = true
                            end
                        end
                    end
                end
                local t = "corridor"
                if best then t = rooms[best].kind end
                color_of[k] = WALL_COLOR[t] or WALL_COLOR.corridor
            end
        end
    end
end

-- The free floor cell nearest a room's centre (patrol points, room labels).
local function free_center(r)
    local cx, cy = room_center(r)
    local best, best_d = nil, math.huge
    for y = r.y, r.y + r.h - 1 do
        for x = r.x, r.x + r.w - 1 do
            if kind[K(x, y)] == KIND_FLOOR and not is_solid_tile(deco[K(x, y)]) then
                local d = (x - cx) ^ 2 + (y - cy) ^ 2
                if d < best_d then best, best_d = { x = x, y = y }, d end
            end
        end
    end
    return best or { x = cx, y = cy }
end

local human_room = nil
local monster_room = nil
local patrol = {}

local function pick_spawns(school_rooms)
    local mx, my = SX + SW // 2, SY + SH // 2
    local best_d = math.huge
    for _, r in ipairs(school_rooms) do
        if r.kind == "classroom" then
            local cx, cy = room_center(r)
            local d = (cx - mx) ^ 2 + (cy - my) ^ 2
            if d < best_d then human_room, best_d = r, d end
        end
    end
    human_room = human_room or school_rooms[1]
    local hx, hy = room_center(human_room)
    local far_d = -1
    for _, r in ipairs(school_rooms) do
        if r.kind ~= "principal" then
            local cx, cy = room_center(r)
            local d = (cx - hx) ^ 2 + (cy - hy) ^ 2
            if d > far_d then monster_room, far_d = r, d end
        end
    end
    patrol = {}
    for _, r in ipairs(school_rooms) do
        local c = free_center(r)
        r.center = c
        if r.kind ~= "principal" then patrol[#patrol + 1] = { x = c.x, y = c.y, room = r.id } end
    end
    -- Corridor points too, so the monster also roams the halls.
    for y = SY + OUTER, SY + SH - OUTER - 1, 6 do
        for x = SX + OUTER, SX + SW - OUTER - 1, 6 do
            if room_of[K(x, y)] == 1 and not is_solid_tile(deco[K(x, y)]) then
                patrol[#patrol + 1] = { x = x, y = y, room = 1 }
            end
        end
    end
end

-- =============================================================================
-- Building the school / the lobby
-- =============================================================================

local function reset_state()
    kind, room_of, color_of, deco, clear = {}, {}, {}, {}, {}
    rooms, objects = {}, {}
    rooms[1] = { id = 1, kind = "corridor", doors = {} }
    rooms[2] = { id = 2, kind = "detention", x = LX, y = LY, w = LW, h = LH, doors = {} }
end

local function build_lobby()
    for y = LY - 2, LY + LH + 1 do
        for x = LX - 2, LX + LW + 1 do set_wall(x, y) end
    end
    carve_rect(LX, LY, LX + LW - 1, LY + LH - 1, 2)
    for y = -1, 2 do
        for x = -3, 3 do clear[K(x, y)] = true end
    end
    -- Seed-independent: the lobby is painted once, before any seed exists.
    local saved_seed = seed
    seed = 0
    begin_room()
    furnish_detention(rooms[2], 9001)
    ensure_walkable(rooms[2])
    commit_room()
    seed = saved_seed
    colour_walls(LX - 2, LY - 2, LX + LW + 1, LY + LH + 1)
end

local function build_school()
    -- Everything starts as wall; corridors and rooms are carved out of it.
    for y = SY, SY + SH - 1 do
        for x = SX, SX + SW - 1 do set_wall(x, y) end
    end
    local ix0, iy0 = SX + OUTER, SY + OUTER
    local ix1, iy1 = SX + SW - 1 - OUTER, SY + SH - 1 - OUTER
    local hcor, vcor = build_corridors(ix0, iy0, ix1, iy1)
    local school_rooms = {}
    for _, b in ipairs(blocks_of(ix0, iy0, ix1, iy1, hcor, vcor)) do
        local x0, y0, x1, y1 = b.x0, b.y0, b.x1, b.y1
        if x0 > ix0 then x0 = x0 + 1 end
        if x1 < ix1 then x1 = x1 - 1 end
        if y0 > iy0 then y0 = y0 + 1 end
        if y1 < iy1 then y1 = y1 - 1 end
        if x1 - x0 + 1 >= 3 and y1 - y0 + 1 >= 3 then
            local leaves = {}
            bsp({ x = x0, y = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }, leaves)
            for _, r in ipairs(leaves) do
                r.id = #rooms + 1
                r.doors = {}
                rooms[r.id] = r
                school_rooms[#school_rooms + 1] = r
                carve_rect(r.x, r.y, r.x + r.w - 1, r.y + r.h - 1, r.id)
            end
        end
    end
    assign_types(school_rooms)
    connect_rooms(school_rooms)
    pick_exits()
    pick_vents(school_rooms)
    for i, r in ipairs(school_rooms) do
        begin_room()
        local f = FURNISH[r.kind]
        if f then f(r, 100 + i * 17) end
        if r.kind ~= "principal" and r.kind ~= "toilet_girls" and r.kind ~= "toilet_boys" and r.kind ~= "storage" then
            scatter_blood(r, 500 + i)
        end
        ensure_walkable(r)
        commit_room()
    end
    begin_room()
    furnish_corridors(77)
    commit_room()
    colour_walls(SX, SY, SX + SW - 1, SY + SH - 1)
    pick_spawns(school_rooms)
    return school_rooms
end

-- Every task needs its objects; a layout that lacks one is rebuilt from a
-- derived RNG state (the same on every peer, so the seed still means one map).
local function layout_ok(school_rooms)
    local count = {}
    for _, obj in ipairs(objects) do count[obj.kind] = (count[obj.kind] or 0) + 1 end
    local kinds = {}
    for _, r in ipairs(school_rooms) do kinds[r.kind] = true end
    for _, r in ipairs(school_rooms) do
        if r.kind ~= "principal" and uf_find(r.id) ~= uf_find(1) then return false end
    end
    return kinds.principal and kinds.teachers and kinds.library and human_room ~= nil
        and (count.pdoor or 0) == 1 and (count.computer or 0) == 1 and (count.board or 0) >= 1
        and (count.desk or 0) >= 1 and (count.shelf or 0) >= 3 and (count.sink or 0) >= 1
        and (count.locker or 0) >= 6 and (count.bin or 0) >= 8 and (count.exit or 0) == 5
end

-- =============================================================================
-- Painting (progressive, a few hundred cells per frame)
-- =============================================================================

local function paint_cell(k)
    local x, y = KX(k), KY(k)
    local kd = kind[k]
    if kd == KIND_FLOOR then
        set_tile(x, y, V0, T_FLOOR)
    elseif kd == KIND_WALL then
        set_dual_tile(x, y, T_FLOOR, true)
        set_tile(x, y, V0, color_of[k] or WALL_COLOR.corridor)
    end
    local d = deco[k]
    if d and d:sub(1, 2) ~= "__" and TILE[d] then
        set_tile(x, y, V0, TILE[d])
    end
end

local function queue_area(x0, y0, x1, y1, keys)
    for y = y0, y1 do
        for x = x0, x1 do
            local k = K(x, y)
            if kind[k] then
                jobs[#jobs + 1] = { op = "paint", key = k }
                if keys then keys[#keys + 1] = k end
            end
        end
    end
end

function _process(delta, inputs)
    if job_head > #jobs then return nil end
    local budget = CELLS_PER_FRAME
    while budget > 0 and job_head <= #jobs do
        local job = jobs[job_head]
        job_head = job_head + 1
        if job.op == "clear" then
            clear_tile(KX(job.key), KY(job.key))
        else
            paint_cell(job.key)
        end
        budget = budget - 1
    end
    if job_head > #jobs then
        jobs = {}
        job_head = 1
        ready = true
        on_painted()
    end
    return nil
end

local function world_pos(x, y)
    return map_to_local(Vector2(x, y))
end

function on_painted()
    -- Room names on the map (local markers; humans open it, monsters never can).
    for _, n in ipairs(minimap_names) do delete_minimap_target(n) end
    minimap_names = {}
    for i = 2, #rooms do
        local r = rooms[i]
        if r.x and r.kind ~= "classroom" then
            local c = r.center or free_center(r)
            local n = "bc_room_" .. i
            set_minimap_target({ name = n, world_position = world_pos(c.x, c.y), text = ROOM_TOKEN[r.kind] or "",
                icon_size = Vector2(3, 3), color = Color(0.85, 0.85, 0.9, 0.85) })
            minimap_names[#minimap_names + 1] = n
        end
    end
    -- Vents: one world sprite each, tinted with its pair's colour.
    for _, n in ipairs(vent_images) do destroy("", n, false) end
    vent_images = {}
    generation = generation + 1
    for _, obj in ipairs(objects) do
        if obj.kind == "vent" then
            local n = "bc_vent_" .. generation .. "_" .. obj.id
            set_image({ name = n, image_path = "tiles/vent", position = world_pos(obj.x, obj.y),
                modulate = Color(obj.r, obj.g, obj.b, 1), z_index = 0 })
            vent_images[#vent_images + 1] = n
        end
    end
    run_function("-gm", "on_school_ready", { seed })
end

-- =============================================================================
-- API (run_function("-gen", ...)) - every peer has the same data
-- =============================================================================

-- force = true repaints even for the same seed (a new round must undo the
-- previous round's opened lockers, removed door and visible exits).
function set_seed(new_seed, force)
    new_seed = math.floor(tonumber(new_seed) or 0)
    if new_seed == seed and not force and (ready or #jobs > 0) then return end
    -- Wipe the previous school (the lobby stays).
    for _, k in ipairs(school_keys) do jobs[#jobs + 1] = { op = "clear", key = k } end
    school_keys = {}
    for _, n in ipairs(exit_images) do destroy("", n, false) end
    exit_images = {}
    seed = new_seed
    ready = false
    for attempt = 0, 11 do
        reset_state()
        human_room, monster_room = nil, nil
        build_lobby()
        rng_seed(seed + 1 + attempt * 7919)
        local school_rooms = build_school()
        if layout_ok(school_rooms) then break end
    end
    if not lobby_done then
        queue_area(LX - 2, LY - 2, LX + LW + 1, LY + LH + 1, nil)
        lobby_done = true
    end
    queue_area(SX, SY, SX + SW - 1, SY + SH - 1, school_keys)
end

-- Boot: tile ids + the lobby only, before any seed is chosen.
function build_lobby_only()
    if lobby_done then return end
    reset_state()
    build_lobby()
    queue_area(LX - 2, LY - 2, LX + LW + 1, LY + LH + 1, nil)
    lobby_done = true
end

function is_ready() return ready end
function get_seed() return seed end

-- Room name token at a world position ("" in doorways / outside).
function room_at(wx, wy)
    local cell = local_to_map(Vector2(wx, wy))
    local k = K(math.floor(cell.x), math.floor(cell.y))
    local ro = room_of[k]
    if not ro or ro == 0 then return "" end
    local r = rooms[ro]
    return r and (ROOM_TOKEN[r.kind] or "") or ""
end

-- Every interactable: { id, kind, x, y, room, tile, opened, pair, r, g, b, exit_tile }.
function get_objects() return objects end

function get_object(id) return objects[math.floor(id)] end

-- World positions where the humans start (spread over the start room).
function get_human_spawns()
    local out = {}
    local r = human_room
    if not r then return out end
    for y = r.y, r.y + r.h - 1 do
        for x = r.x, r.x + r.w - 1 do
            if kind[K(x, y)] == KIND_FLOOR and not is_solid_tile(deco[K(x, y)]) then
                out[#out + 1] = world_pos(x, y)
            end
        end
    end
    return out
end

function get_monster_spawn()
    local c = monster_room and (monster_room.center or free_center(monster_room)) or { x = SX + 4, y = SY + 4 }
    return world_pos(c.x, c.y)
end

-- Patrol points (room centres + corridor samples) as world positions.
function get_patrol_points()
    local out = {}
    for _, p in ipairs(patrol) do out[#out + 1] = world_pos(p.x, p.y) end
    return out
end

-- Room centres only (far-away spawn candidates for new monsters).
function get_room_points()
    local out = {}
    for _, p in ipairs(patrol) do
        if p.room > 1 then out[#out + 1] = world_pos(p.x, p.y) end
    end
    return out
end

function get_lobby_spawns()
    local out = {}
    for y = 0, 2 do
        for x = -4, 4 do out[#out + 1] = world_pos(x, y) end
    end
    return out
end

function get_lobby_monster_pos()
    return world_pos(0, LY + 3)
end

-- Runtime tile change (an opened locker, an emptied shelf, the unlocked door).
-- name "" erases the plain tile; old_name tells which tileset to erase from.
function set_deco(x, y, name, old_name)
    x, y = math.floor(x), math.floor(y)
    if name == "" then
        local old = old_name and TILE[old_name]
        if old then set_tile(x, y, ERASE, old) end
        deco[K(x, y)] = nil
    elseif TILE[name] then
        set_tile(x, y, V0, TILE[name])
        deco[K(x, y)] = name
    end
end

-- Exits appear: draw their doors (all peers; also late joiners).
function open_exits()
    for _, obj in ipairs(objects) do
        if obj.kind == "exit" then set_deco(obj.x, obj.y, obj.exit_tile) end
    end
end

load_tile_ids()
build_lobby_only()

lock_rotation = true
linear_damp = 6 -- thrown, then it skids to a stop and sits there ticking

-- =============================================================================
-- MineBlockLand - a thrown bomb.
-- Spawn config: dmg, radius (pixels), thrower (entity name, excluded from the
-- blast and credited for the kills).
--
-- Two stages on purpose, so a bomb is a THREAT and not a trap: it sits and
-- blinks for FUSE_SECONDS, then the blast itself is a normal -combat telegraph
-- (red zone fills white for BLAST_WINDUP before it lands). Everyone - including
-- the zombie horde you lured onto it - gets a fair chance to walk out of the
-- circle, and friendly fire is handled for us because tg_resolve already
-- respects -gm's friendly_fire flag.
--
-- Tiles are broken at blast time, not at throw time, so the hole always matches
-- the circle everybody just saw.
--
-- Like bullet.lua this entity is NOT synced (one spawn message, then every peer
-- simulates the same throw locally); the host stays the only authority for the
-- blast position, the damage and the crater.
-- =============================================================================

add_tag(name, "bomb")

local FUSE_SECONDS = 1.6
local BLAST_WINDUP = 0.4
local BLINK_SECONDS = 0.16
local KNOCKBACK = 150
local TILE_DAMAGE = 6      -- stone has 6 hp: one bomb clears rock outright

-- Tile size in pixels, read from the tilemap instead of hardcoded (same trick
-- bullet.lua uses).
local TILE = map_to_local(Vector2(1, 0)).x - map_to_local(Vector2(0, 0)).x

local blink_on = false

set_image({ parent_name = name, name = "body", image_path = "items/10x10_bomb",
    scale = Vector2(11, 11), z_index = 2 })
-- Collides with tiles only, like every other projectile here: it should bounce
-- off walls but never shove a player or a zombie around.
set_collision({ parent_name = name, name = "col", shape = "circle", size = 5,
    collision_layer = { 4 }, collision_mask = { 1 } })

-- Every peer blinks it locally - no traffic, and it reads as "about to go off".
start_timer({ timer_id = "blink" .. name, entity_name = name,
    function_name = "blink", wait_time = BLINK_SECONDS })

if IS_HOST then
    run_function(name, "host_fuse_end", {}, FUSE_SECONDS)
end

function blink()
    blink_on = not blink_on
    set_image({ parent_name = name, name = "body",
        modulate = blink_on and Color(1, 0.45, 0.35, 1) or Color(1, 1, 1, 1) })
end

-- HOST: the fuse ran out. Show the blast circle, then resolve it a beat later.
function host_fuse_end()
    if not IS_HOST then return end
    local pos = get_value("", name, "position")
    if not pos then
        run_network_function(name, "destroy_self_ALL", {})
        return
    end
    run_function("-combat", "start_telegraph", { {
        x = pos.x, y = pos.y, shape = "circle", r = radius,
        windup = BLAST_WINDUP, dmg = dmg, targets = "all",
        attacker = thrower, kb = KNOCKBACK } })
    -- The telegraph lives on -combat from here on, so the bomb only has to
    -- stick around long enough to carve the crater at the same moment.
    start_timer({ timer_id = "blast" .. name, entity_name = name,
        function_name = "host_blast", wait_time = BLAST_WINDUP,
        duration = BLAST_WINDUP })
end

-- HOST: carve the crater and tell everyone to play the boom.
function host_blast()
    if not IS_HOST then return end
    local pos = get_value("", name, "position")
    if pos then
        break_tiles(pos)
        -- The puff + shake are broadcast through -gm, which already owns the
        -- mod's build-once particle cache (see ensure_chip_fx there).
        run_network_function("-gm", "boom_fx_ALL", { pos.x, pos.y })
    end
    -- The bomb isn't network-synced (see the file header), so every peer -
    -- including the host itself - has its own local copy of this entity that
    -- nothing but this message ever tells to go away. Without it the client
    -- copy just sits there blinking forever after the blast already happened.
    run_network_function(name, "destroy_self_ALL", {})
end

function destroy_self_ALL(sender_id)
    destroy("", name)
end

-- Every breakable cell whose CENTRE is inside the blast circle takes a full
-- stone's worth of damage. Coordinates are floored at this entry point: tile
-- maths that crossed the Lua<->GDScript boundary comes back as floats.
function break_tiles(pos)
    local reach = math.floor(radius / TILE)
    local centre = local_to_map(pos)
    local cx, cy = math.floor(centre.x), math.floor(centre.y)
    for ty = cy - reach, cy + reach do
        for tx = cx - reach, cx + reach do
            local world = map_to_local(Vector2(tx, ty))
            if distance_to(pos, world) <= radius then
                -- quiet: a blast clears dozens of cells in one frame, and the
                -- boom itself (host_blast's boom_fx_ALL) is the sound of it -
                -- not thirty tile thuds stacked on the same millisecond.
                run_function("-gm", "host_damage_tile",
                    { x = tx, y = ty, dmg = TILE_DAMAGE, quiet = true })
            end
        end
    end
end


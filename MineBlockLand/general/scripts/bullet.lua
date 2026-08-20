lock_rotation = true
linear_damp = 0

-- =============================================================================
-- MineBlockLand - hostile projectile (witch bolts + all boss bullets).
-- Spawn config: dmg, speed, life (rotation comes in as the spawn 'r'), and an
-- optional 'bolt_color' - a fully transparent one (or none at all) means "use
-- the default orange", which is what the boss and every other shooter send.
-- One spawn message, then every peer simulates the straight flight locally;
-- only the HOST applies damage (players are hit through host_take_damage).
-- =============================================================================

add_tag(name, "bullet")

local hit_something = false
local TILE_DAMAGE = 1 -- a tree (4 hp) takes 4 bolts, a rock (6 hp) takes 6
local K_TREE, K_STONE, K_WOOD_BLOCK = 3, 9, 15

-- Flight direction (matches the linear_velocity set below; lock_rotation keeps
-- 'rotation' constant for the whole flight).
local DIR = Vector2(math.cos(rotation), math.sin(rotation))
-- Tile size in pixels, read from the tilemap instead of hardcoded.
local TILE = map_to_local(Vector2(1, 0)).x - map_to_local(Vector2(0, 0)).x

local BOLT_COLOR = Color(247 / 255, 118 / 255, 34 / 255, 1)
if bolt_color ~= nil and bolt_color.a > 0 then BOLT_COLOR = bolt_color end

set_image({ parent_name = name, name = "body", image_path = "white",
    scale = Vector2(7, 7), modulate = BOLT_COLOR, z_index = 3 })
set_shader({ parent_name = name, image_name = "body", shader_name = "circle" })
set_area({ parent_name = name, name = "area", shape = "circle", size = 4,
    collision_mask = { 1, 2 } }) -- tiles and player bodies

set_value("", name, "linear_velocity",
    Vector2(math.cos(rotation) * speed, math.sin(rotation) * speed))

run_function(name, "destroy_self", {}, life)

-- The cast, heard the instant the bolt appears - no broadcast needed for this
-- either: spawn_entity_host already sent the ONE message that created this
-- entity on every peer, so each peer's own local copy plays it the moment its
-- own top-level script (this file) runs, same as bomb.lua's blink starting
-- itself on every peer with no host guard.
local spawn_pos = get_value("", name, "position")
if spawn_pos then
    set_audio({ stream_path = "spell", is_2d = true, position = spawn_pos,
        max_distance = 420, volume = -3, random_pitch = 0.1 })
end

-- The area reports the TileMap hit while the bullet's *centre* is often still in
-- the empty cell in front of the wall (the area has a radius, and a fast bullet
-- moves a good chunk of a tile per physics step). Mapping the raw position then
-- lands on air and the hit is silently dropped - that was the "sometimes it does
-- no damage" bug. Probe a short way along the flight direction and take the
-- first breakable cell we find.
function solid_tile_ahead(pos)
    local steps = { 0, 0.35, 0.7, 1.0 }
    for i = 1, #steps do
        local probe = Vector2(pos.x + DIR.x * TILE * steps[i],
            pos.y + DIR.y * TILE * steps[i])
        local tile = local_to_map(probe)
        local tx, ty = math.floor(tile.x), math.floor(tile.y)
        local kind = run_function("-gen", "kind_at", { tx, ty })
        if kind == K_TREE or kind == K_STONE or kind == K_WOOD_BLOCK then return tx, ty end
    end
    return nil
end

-- Every peer simulates this bolt's flight itself (see the file header), so the
-- impact is heard everywhere without a single message: whoever is close enough
-- ran the very same collision a frame ago. bullet_impact is a DAMAGE sound,
-- not a generic "stopped somewhere" sound, so a bolt burying itself in a wall
-- or a tree - no host_take_damage call, just a tile hit - stays silent here;
-- only actually hurting the player gets it.
local IMPACT_DISTANCE = 420

function on_area_body_entered(body_name)
    if hit_something then return end
    if body_name == "TileMap" then
        hit_something = true
        if IS_HOST then
            local pos = get_value("", name, "position")
            if pos then
                local tx, ty = solid_tile_ahead(pos)
                if tx then
                    run_function("-gm", "host_damage_tile",
                        { x = tx, y = ty, dmg = TILE_DAMAGE })
                end
            end
        end
        destroy_self()
        return
    end
    if has_tag(body_name, "alive") then
        hit_something = true
        local pos = get_value("", name, "position")
        if pos then
            set_audio({ stream_path = "bullet_impact", is_2d = true, position = pos,
                max_distance = IMPACT_DISTANCE, volume = -4, random_pitch = 0.12 })
        end
        if IS_HOST then
            run_function(body_name, "host_take_damage", { dmg, "" })
        end
        destroy_self()
    end
end

function destroy_self()
    destroy("", name)
end

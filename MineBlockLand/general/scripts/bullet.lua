lock_rotation = true
linear_damp = 0

-- =============================================================================
-- MineBlockLand - hostile projectile (witch bolts + all boss bullets).
-- Spawn config: dmg, speed, life (rotation comes in as the spawn 'r').
-- One spawn message, then every peer simulates the straight flight locally;
-- only the HOST applies damage (players are hit through host_take_damage).
-- =============================================================================

add_tag(name, "bullet")

local hit_something = false

set_image({ parent_name = name, name = "body", image_path = "white",
    scale = Vector2(7, 7), modulate = Color(247 / 255, 118 / 255, 34 / 255, 1), z_index = 3 })
set_shader({ parent_name = name, image_name = "body", shader_name = "circle" })
set_area({ parent_name = name, name = "area", shape = "circle", size = 4,
    collision_mask = { 1, 2 } }) -- tiles and player bodies

set_value("", name, "linear_velocity",
    Vector2(math.cos(rotation) * speed, math.sin(rotation) * speed))

run_function(name, "destroy_self", {}, life)

function on_area_body_entered(body_name)
    if hit_something then return end
    if body_name == "TileMap" then
        hit_something = true
        destroy_self()
        return
    end
    if has_tag(body_name, "alive") then
        hit_something = true
        if IS_HOST then
            run_function(body_name, "host_take_damage", { dmg, "" })
        end
        destroy_self()
    end
end

function destroy_self()
    destroy("", name)
end

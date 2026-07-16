network_mode = 1
lock_rotation = true
linear_damp = 8

-- =============================================================================
-- MineBlockLand - an item lying on the ground (drops, death piles, chests).
-- Spawn config: item_id, count, dungeon_id (chests placed in the dungeon).
-- Walk over it and the HOST drops it into your inventory (chests open into
-- loot on the spot). Loose drops despawn after a while; dungeon chests never.
-- =============================================================================

add_tag(name, "ground_item")

local DESPAWN_SECONDS = 180
local picked = false

local item = run_function("-items", "get_item", { item_id })
set_image({ parent_name = name, name = "icon", image_path = item.image,
    scale = Vector2(12, 12), z_index = 1 })
if count and count > 1 then
    set_label({ parent_name = name, name = "cnt", text = "x" .. math.floor(count),
        position = Vector2(-16, 8), size = Vector2(32, 8), font_size = 5,
        outline_size = 2, outline_color = Color(0, 0, 0, 1), z_index = 1 })
end
set_area({ parent_name = name, name = "area", shape = "circle", size = 10,
    collision_mask = { 2 } }) -- player bodies

if dungeon_id == nil then dungeon_id = "" end
if IS_HOST and dungeon_id == "" then
    run_function(name, "despawn", {}, DESPAWN_SECONDS)
end

function on_area_body_entered(body_name)
    if not IS_HOST or picked then return end
    if not has_tag(body_name, "alive") then return end
    picked = true
    run_function("-inv", "host_pickup", { { picker = body_name, item_id = item_id, count = count } })
    if dungeon_id ~= "" then
        run_function("-gm", "mark_dungeon_done", { dungeon_id })
    end
    destroy("", name)
end

function despawn()
    if IS_HOST and not picked then
        destroy("", name)
    end
end

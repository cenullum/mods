network_mode = 1
freeze = true

-- =============================================================================
-- Beyaz Canavar - a caught player's body. Spawned by the host with
-- { owner = steam id, nick = nickname }; STATIC (network_mode 1), so the engine
-- re-sends it to everyone who joins later and it stays for the whole round.
-- Drawn locally on every peer: a blood pool, the owner's Steam avatar turned
-- 90 degrees and tinted red.
-- =============================================================================

local AVATAR_PX = 26
local POOLS = { "tiles/blood_floor", "tiles/blood_floor2", "tiles/blood_floor4" }

local owner_id = tostring(owner or "")
local pool = POOLS[1 + (#owner_id + math.floor(position.x)) % #POOLS]

set_image({ parent_name = name, name = "pool", image_path = pool, scale = Vector2(40, 40),
    position = Vector2(0, 6), z_index = -1, modulate = Color(1, 1, 1, 0.95) })

local function draw()
    -- Avatar if this peer has it, the default icon otherwise (offline, left the game).
    local shown = ""
    if owner_id ~= "" and entity_exists(owner_id) then
        shown = set_image({ parent_name = name, name = "body", image_path = owner_id, rotation = math.pi / 2,
            modulate = Color(1, 0.3, 0.3, 1), z_index = 0 })
    end
    if not shown or shown == "" then
        set_image({ parent_name = name, name = "body", rotation = math.pi / 2,
            modulate = Color(1, 0.3, 0.3, 1), z_index = 0 })
    end
    set_image_pixel(name, "body", Vector2(AVATAR_PX, AVATAR_PX))
    set_shader({ parent_name = name, image_name = "body", shader_name = "circle",
        outline_color = Color(0.5, 0.05, 0.05, 1) })
end
draw()

add_tag(name, "corpse")

function _on_loaded_avatar(steam_id)
    if steam_id == owner_id then draw() end
end

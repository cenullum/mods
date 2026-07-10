network_mode = 1
gravity_scale = 0.0
lock_rotation = true
freeze = true

-- =============================================================================
-- Crazy Eights - player entity.
--
-- There are no walking avatars: everyone sits around one table (the camera is
-- rotated per seat by ce_manager). The only per-player world presence is the
-- MOUSE CURSOR, mirrored to everyone (same pattern as the Hook Up mod):
-- the local player positions their own cursor every frame, the HOST (who owns
-- every user's inputs) broadcasts each cursor to the other peers.
-- =============================================================================

add_tag(name, "user")

local cursor_name = "ce_cur_" .. name
local last_sent = Vector2(-999999, -999999)

-- Per-player color. The MANAGER assigns one distinct color per player (by join
-- order, so nobody shares) and syncs it as a steam_id->hex map; the nicknames use
-- the same map, so each cursor matches its owner's name color exactly. `name` is
-- this entity's steam_id. A local hash palette is only a fallback until the map
-- arrives.
local PALETTE = {
    Color(0.95, 0.35, 0.35, 1), Color(0.35, 0.75, 0.95, 1),
    Color(0.95, 0.8, 0.3, 1),  Color(0.5, 0.9, 0.4, 1),
    Color(0.85, 0.45, 0.9, 1), Color(0.98, 0.6, 0.2, 1),
    Color(0.4, 0.95, 0.8, 1),  Color(0.8, 0.8, 0.85, 1),
}
local function hex_to_color(hex)
    local r = tonumber(hex:sub(2, 3), 16) / 255
    local g = tonumber(hex:sub(4, 5), 16) / 255
    local b = tonumber(hex:sub(6, 7), 16) / 255
    return Color(r, g, b, 1)
end
local function my_color()
    local colors = get_value("", "-ce_manager", "cl_colors")
    if type(colors) == "table" and colors[name] then
        return hex_to_color(colors[name])
    end
    local sum = 0
    for i = 1, #name do sum = sum + string.byte(name, i) end
    return PALETTE[(sum % #PALETTE) + 1]
end

local function apply_cursor(pos)
    set_image({
        name = cursor_name,
        image_path = "cursor",
        position = pos,
        scale = Vector2(18, 18),
        modulate = my_color(),
        z_index = 900,
        visible = not IS_LOCAL, -- you don't need a world-space dot under your own OS cursor
    })
end

function _process(delta, inputs)
    local mouse_position = inputs["stick_2"] or Vector2(-999999, -999999)

    if IS_LOCAL then
        apply_cursor(mouse_position)
    end

    -- The host owns every player's inputs: it relays each cursor to the others
    -- (skipping tiny movements to save bandwidth).
    if IS_HOST then
        local dx = mouse_position.x - last_sent.x
        local dy = mouse_position.y - last_sent.y
        if dx * dx + dy * dy > 4 then
            last_sent = mouse_position
            run_network_function(name, "cursor_pos_ALL", { mouse_position })
        end
    end

    return inputs
end

function cursor_pos_ALL(sender_id, pos)
    if IS_LOCAL then return end -- we place our own cursor with zero latency
    apply_cursor(pos)
end

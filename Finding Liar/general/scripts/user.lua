network_mode = 1
gravity_scale = 1.0
speed = 40.0
linear_damp = 0.005
bounce = 0
friction = 0.7 -- For staying on wall
rough = 0.00
lock_rotation = true


add_tag(name, "user")

is_avatar_loaded = false
collision_name = ""
image_name = "player_image"
nickname_label_name = "nickname"

local outline_color = nil

function create_user_ALL(sender_id, player_color)
    outline_color = player_color

    -- Create collision
    collision_config = {
        parent_name = name,
        shape = "circle",
        size = 16
    }
    collision_name = set_collision(collision_config)

    -- Create nickname
    nickname_config = {
        parent_name = name,
        name = nickname_label_name,
        text = nickname,
        outline_color = player_color,
        outline_size = 4,
        font_size = 8,
        position = Vector2(-256, -48),
        size = Vector2(512, 16),
        horizontal_alignment = 1,
        vertical_alignment = 1,
        z_index = 5
    }
    nickname_label_name = set_label(nickname_config)

    -- Create avatar
    if is_avatar_loaded then
        image_name = set_image({
            parent_name = name,
            name = image_name,
            image_path = name,
            scale = Vector2(32, 32)
        })
    else
        image_name = set_image({
            parent_name = name,
            name = image_name,
            scale = Vector2(32, 32),
        })
    end

    set_shader({
        parent_name = name,
        image_name = image_name,
        shader_name = "circle",
        inner_circle = 0.45,
        outer_circle = 0.49,
        smoothness = 0.01,
        outline_color = player_color
    })

    if IS_LOCAL then
        set_camera_target(name)
    end
end

function create_user_CLIENT(sender_id, player_color)
    create_user_ALL(sender_id, player_color)
end

local function generate_random_color()
    local hue = math.random() * 360
    local saturation = 0.7 + (math.random() * 0.3)
    local value = 0.8 + (math.random() * 0.2)
    local c = value * saturation
    local x = c * (1 - math.abs((hue / 60) % 2 - 1))
    local m = value - c
    local r, g, b
    if hue < 60 then
        r, g, b = c, x, 0
    elseif hue < 120 then
        r, g, b = x, c, 0
    elseif hue < 180 then
        r, g, b = 0, c, x
    elseif hue < 240 then
        r, g, b = 0, x, c
    elseif hue < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    return Color(r + m, g + m, b + m, 1)
end

function _on_user_initialized(steam_id, nickname)
    if IS_HOST then
        if steam_id == name then
            local player_color = generate_random_color()
            run_network_function(name, "create_user_ALL", { player_color })
        else
            run_network_function(name, "create_user_CLIENT", { outline_color }, steam_id)
        end
    end
end

function _on_loaded_avatar(steam_id)
    if name == steam_id then
        is_avatar_loaded = true
        image_name = set_image({
            parent_name = name,
            name = image_name,
            image_path = steam_id,
            scale = Vector2(32, 32)
        })
        set_shader({
            parent_name = name,
            image_name = image_name,
            shader_name = "circle",
            inner_circle = 0.45,
            outer_circle = 0.49,
            smoothness = 0.01,
            outline_color = outline_color
        })
    end
end

function _on_user_disconnected(steam_id, nickname)
    if steam_id == name then
        add_to_chat(nickname .. " disconnected", false)
    end
end

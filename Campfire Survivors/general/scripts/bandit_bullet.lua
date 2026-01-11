linear_damp = 0

--bandit_bullet lua

-- monster_id            who fired this bullet
-- damage         Damage amount
-- factor             Scale factor for bullet size

-- Add bullet tag for identification
add_tag(name, "bullet")

lifetime = 4.0  -- How long bullet exists before auto-destroying

-- Set the image with rotation
image_name=set_image({
    parent_name=name,
    image_path="red_bullet",
    scale = Vector2(16 * factor, 16 * factor),
    rotation = rotation -- Add rotation to match movement direction
})

-- Play shoot sound
set_audio({
no_multiple_tag=monster_id,
stream_path = "9mm",
position = position,
random_pitch=0.15
})

-- Set up collision area for both host and clients
set_area({
parent_name=name,
size=8*factor,
shape="circle",
collision_layer = {4}, -- Bandit bullet is on layer 4
collision_mask = {1, 2} -- Collides with tilemap (1) and players (2)
})

-- Calculate velocity based on rotation and speed
local velocity = Vector2(math.cos(rotation) * speed, math.sin(rotation) * speed)
set_value("", name, "linear_velocity", velocity)
run_function(name,"destroy_self",{},lifetime)

-- Handle collision with entities
function on_area_body_entered(body_name)
    if body_name == "TileMap" then -- tilemap does not have has_tag function
        destroy_self()
        return
    end

    if has_tag(body_name, "user") then
        -- Only host handles damage
        if IS_HOST then
            -- Deal damage to the user
            run_function(body_name, "take_damage", {damage})
        end
        
        -- Both host and clients destroy the bullet after hitting a user
        destroy_self()
    end
end

function destroy_self()
    destroy("", name)
end 



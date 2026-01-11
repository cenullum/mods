linear_damp = 0

--bullet lua

-- you should not set those values here it will override values that comes from spawn_entity_host in user script
-- steam_id            who fired this bullet
-- damage         Damage amount
-- penetration  How many enemies the bullet can pass through
-- factor             Scale factor for bullet size
-- knockback    Knockback force

-- Add bullet tag for identification
add_tag(name, "bullet")

enemies_hit = 0 -- Track how many enemies have been hit (for penetration)
lifetime = 1.0  -- How long bullet exists before auto-destroying

image_name=set_image({parent_name=name,image_path="blue_bullet",scale = Vector2(16 * factor, 16 * factor) })
-- Play shoot sound
set_audio({
no_multiple_tag=steam_id,--one user have one audio so it avoids weird sound because of too many bullets
stream_path = "9mm",
position = position,
random_pitch=0.15
})
 
-- Set up collision area for both host and clients
set_area({
parent_name=name,
size=8*factor,
shape="circle",
collision_mask={1,3}-- 1 is tilemap and standart layer, 3 is monster layer
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

    if has_tag(body_name, "monster") then
        -- Track penetration for both host and clients
        enemies_hit = enemies_hit + 1

        -- Only host handles damage and lifesteal
        if IS_HOST then
            -- Deal damage to the monster
            run_function(body_name, "take_damage", {damage, knockback, rotation, steam_id})

            -- Apply lifesteal to player if configured
            if steam_id and steam_id ~= "" then
                run_function(steam_id, "apply_lifesteal", {damage})
            end
        end

        -- Both host and clients check penetration limit
        if enemies_hit > penetration then
            destroy_self()
        end
    end
end

function destroy_self()
    destroy("", name)
end













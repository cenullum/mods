linear_damp = 0
lock_rotation = true
network_mode = 2

--monster lua
add_tag(name,"monster")

-- Set monster properties from the data
health=h
size = i
is_bandit = false
damage = d
speed = s
outline_color = oc
wave_level = wl or 1  -- Store the wave level for scaling bandit bullet damage

-- Function to handle synced monster type from host to clients
function set_monster_type(synced_monster_id)
    -- Update the monster data with the synced ID
    monster_data = run_function("-mg", "get_monster_data", {synced_monster_id})
    monster_type = monster_data.type
   
    size = monster_data.size

    set_value("",name,"speed",monster_data.speed) -- 'speed' is a built-in variable and must be updated using set_value.
   
    -- Check if monster is a bandit
    if monster_type == "bandit" then
        is_bandit = true
    end

    -- Update visual appearance based on synced data
    image_name = set_image({parent_name=name, image_path=monster_type, scale=Vector2(size, size), image_name=image_name})

    set_shader({parent_name= name, image_name= image_name, shader_name= "circle", outline_color= outline_color})

    -- Configure collision based on size
    collision_config = {
    parent_name = name,
    name = collision_name,
    shape = "circle",
    size = size/2, -- Collision size is half of the visual size
    collision_layer = {3}, -- Enemy is only on layer 3
    collision_mask = {1, 3} -- Collides with tilemap (1) and other enemies (3)
    }

    collision_name = set_collision(collision_config)

    return true
end

-- We'll get monster id from the monster generator with in monster_generation.lua:
--local entity_data = {
--      p = spawn_pos,
--     t = "monster",
--     id = monster_id
--  }
set_monster_type(id)

run_function("-mg", "monster_count_change", {1})



function follow_random_user()
    if IS_HOST == false then
        return -- Only the host can decide this action for server authority
    end
    -- Get all entities with the "user" and "alive" tags instead of just "user"
    local users = get_entity_names_by_tag("alive")

    -- Check if there are any alive users
    if #users == 0 then
        return
    end

    -- Select a random alive user from the list
    local random_index = math.random(1, #users)
    local target_name = users[random_index]

    go_to_target(name, target_name, false)
end

-- Only call follow_random_user for non-bandit monsters
if not is_bandit then
    follow_random_user()
end

-- Set up timers
if IS_HOST then
    -- Only set up target timer for non-bandit monsters
    if not is_bandit then
        start_timer({
        entity_name = name,
        function_name = "follow_random_user",
        wait_time = 10.0,  -- Change target every 10 seconds
        timer_id = name .. "_target_timer"  -- Use unique timer ID
        })
    end
    
    -- Set up shooting timer for bandits
    if is_bandit then
        start_timer({
            entity_name = name,
            function_name = "bandit_shoot",
            wait_time = 4.0,  -- Shoot every 2 seconds
            timer_id = name .. "_shoot_timer"
        })
    end
end

-- Function for bandits to shoot at nearest user
function bandit_shoot()
    if not IS_HOST or not is_bandit then
        return
    end
    
    -- Find the nearest alive user to shoot at instead of any user
    local nearest_data = get_nearest_entity_by_tag(name, "alive")
    
    -- Check if an alive user was found 
    if nearest_data and nearest_data.name ~= nil then
        -- Calculate bullet damage based on wave level (base damage 10, scaled by wave level)
        local bullet_damage = 10 * wave_level
        
        -- Create the bullet
        local bullet_data = {
            t = "bandit_bullet",  -- Script name 
            p = position,         -- Starting position
            r = nearest_data.angle,  -- Rotation toward user
            monster_id = name,    -- Who fired this bullet
            damage = bullet_damage,  -- Damage amount scaled by wave level
            speed = 60,          -- Bullet speed
            factor = 1            -- Bullet size factor
        }
        
        spawn_entity_host(bullet_data)
    end
end

-- Client-side function to show damage label
function show_damage_label_ALL(sender_id, damage_amount)
    -- Set up the damage label
    local damage_label_config = {
        text = "-" .. tostring(math.floor(damage_amount)),
        outline_color = Color(0,0,0,1),
        outline_size = 2,
        font_color = Color(1, 0, 0, 1),
        font_size = 10,
        position = position,
        size = Vector2(64, 16),
    }
    
    label_name = set_label(damage_label_config)
    -- Start timer to destroy the label after 2 seconds
    start_timer({
        entity_name = "-mg",--This function is not on monster lua because monster can be destroyed so timer can not run this function
        function_name = "destroy_damage_label",
        extra_args = {label_name = label_name},
        wait_time = 2.0,
		duration=2.0,-- duration and wait_time is same so it will just work once then be finished automatically
        timer_id = label_name .. "_timer"
    })
end

-- Modified take_damage to track which player killed the monster
function take_damage(damage, knockback_amount, angle, player_id)
    -- Calculate actual damage dealt (cannot exceed current health)
    local actual_damage = math.min(damage, health)
    
    -- Apply damage
    health = health - damage


    -- Show damage label to all clients with the actual damage taken
    if IS_HOST then
        run_network_function(name, "show_damage_label_ALL", {actual_damage})
        if player_id and actual_damage > 0 then
            run_function("-stats", "add_player_stat", {player_id, "damage_dealt", actual_damage})
        end
    end

    -- Apply knockback if specified
    if knockback_amount > 0 then
        local knockback_direction = Vector2(math.cos(angle), math.sin(angle))
        local knockback_velocity = knockback_direction * knockback_amount

        -- Apply knockback force
        add_linear_velocity(name, knockback_velocity)
    end

    -- Check for death
    if health <= 0 then
        -- Record kill if player_id is provided
        if IS_HOST and player_id then
            run_function("-stats", "add_player_stat", {player_id, "enemies_killed", 1})
        end
        
        destroy_self()
    end
end

function destroy_self()
    run_function("-mg", "monster_count_change", {-1})
    -- Spawn the monster
    local entity_data = {
    p = position,
    t = "xp"
    }

    local entity_name = spawn_entity_host(entity_data)
    destroy("", name)
end













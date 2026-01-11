lock_rotation = true
linear_damp = 5

--user lua
add_tag(name,"user")
add_tag(name,"alive")
collision_name=""

-- visuals
image_name="image"
nickname_label_name=""
hit_progres_bar_name=""
interact_label_name=""
revive_progress_bar_name="revive_progress_bar"..name
revive_progress=0



is_avatar_loaded=false
is_dead = false

collected_xp=0
current_level = 0
base_xp_requirement = 100
required_xp = base_xp_requirement

-- Default stats (used for resetting)
default_player_stats = {
movement_speed = 40,
max_health = 100,
current_health = 100,
armor = 0,
pickup_range = 32,
experience_gain = 7,
regeneration = 0,
dodge_chance = 0,
attack_speed = 1.0,
projectile_factor = 1,
projectile_count = 1,
projectile_speed = 150,
projectile_penetration = 0,
lifesteal = 0,
knockback = 50,
damage = 30--30
}
-- Global stats for direct access
movement_speed = default_player_stats.movement_speed
max_health = default_player_stats.max_health
current_health = default_player_stats.current_health
armor = default_player_stats.armor
pickup_range = default_player_stats.pickup_range
experience_gain = default_player_stats.experience_gain
regeneration = default_player_stats.regeneration
dodge_chance = default_player_stats.dodge_chance
attack_speed = default_player_stats.attack_speed
projectile_factor = default_player_stats.projectile_factor
projectile_count = default_player_stats.projectile_count
projectile_speed = default_player_stats.projectile_speed
projectile_penetration = default_player_stats.projectile_penetration
lifesteal = default_player_stats.lifesteal
knockback = default_player_stats.knockback
damage = default_player_stats.damage
set_value("", name, "speed", movement_speed)

-- Configurable parameters
local fire_interval = 1.0  -- Time between shots in seconds

if IS_LOCAL then
    set_camera_target(name)
end

-- Pickup range
area_config={
parent_name=name,
shape="circle",
size=pickup_range,
collision_layer = {2},
collision_mask = {2}
}
area_name=set_area(area_config)

-- taking damage  range
taking_damage_area_config={
    parent_name=name,
    shape="circle",
    size=16,
    collision_layer = {6},
    collision_mask = {3}
    }
taking_damage_area_name=set_area(taking_damage_area_config)


revive_duration=3-- 3 seconds

function calculate_step_increment(total_duration_seconds , interval_seconds)
    local steps = total_duration_seconds / interval_seconds
    return 100 / steps
end
revive_increment=calculate_step_increment(revive_duration,0.1)

-- Called when upgrade system sends updated stats
function update_stats(stats)
    -- Update globals with the new stats
    movement_speed = stats.movement_speed
    max_health = stats.max_health
    current_health = stats.current_health
    armor = stats.armor
    pickup_range = stats.pickup_range
    experience_gain = stats.experience_gain
    regeneration = stats.regeneration
    dodge_chance = stats.dodge_chance
    attack_speed = stats.attack_speed
    projectile_factor = stats.projectile_factor
    projectile_count = stats.projectile_count
    projectile_speed = stats.projectile_speed
    projectile_penetration = stats.projectile_penetration
    lifesteal = stats.lifesteal
    knockback = stats.knockback
    damage = stats.damage

    -- Update UI elements
    if IS_LOCAL then
        set_progress_bar({
        name = "_health_progress_bar",
        max_value = max_health,
        value = current_health
        })
        
        -- Update health label
        set_label({
        name = "_health_label",
        text = string.format("Health: %d/%d", math.floor(current_health), math.floor(max_health))
        })
    end

    -- Update movement speed
    set_value("", name, "speed", movement_speed)
end


function create_user_ALL(sender_id)
    collision_config={
    parent_name=name,
    name=collision_name,
    shape="circle",
    size=16,
    collision_layer = {2, 4}, -- Player is on layer 2 and 4 (for bandit bullets)
    collision_mask = {1, 4} -- Collides with tilemap (layer 1) and bandit bullets (layer 4)
    }
    collision_name=set_collision(collision_config)

    nickname_config={
    parent_name=name,
    name=nickname_label_name,
    text=nickname,
    outline_color=Color(0,0,0,1),
    outline_size=4,
    font_size=8,
    position=Vector2(-256,-48),
    size=Vector2(512,16),
    horizontal_alignment=1,
    vertical_alignment=1}

    nickname_label_name=set_label(nickname_config)

    if is_avatar_loaded then
        image_name= set_image({parent_name=name,name=image_name,image_path=name,scale=Vector2(32,32)})-- name in user entity is steam_id and path of avatar image
    else
        image_name= set_image({parent_name=name,name=image_name,scale=Vector2(32,32)})--just temporary image until avatar is loaded
    end

    set_shader({parent_name= name,image_name= image_name, shader_name= "circle"})--default values inner_circle=0.45 outer_circle=0.49 smoothness=0.01
    
    -- Create hidden revive progress bar
    revive_progress_bar_config = {
        parent_name = name,
        name = revive_progress_bar_name,
        position = Vector2(-10, -20),
        size = Vector2(32, 4),
        value = 0,
        max_value = 100,
        color = Color(0, 1, 0, 1),
        visible = false
    }
    revive_progress_bar_name = set_progress_bar(revive_progress_bar_config)

end

-- Reset stats to default values
function reset_stats()
    update_stats(default_player_stats)
    -- Remove dead tag
    remove_tag(name, "dead")
    -- Add alive tag back so monsters can target again
    add_tag(name, "alive")
    -- Sync to clients
    sync_player_state(max_health, false)
end

function _on_loaded_avatar(steam_id)
    if name==steam_id then -- if it is this user entity
        is_avatar_loaded=true
        image_config={parent_name=name,image_name= image_name,image_path=steam_id,scale=Vector2(32,32)}
        image_name= set_image(image_config)
        set_shader({parent_name= name,image_name= image_name, shader_name= "circle"})
    end
end





function _on_user_initialized(steam_id,nickname)
    -- This will be called when a client has fully downloaded and initialized
    -- Safe to call network functions now for this client

    if IS_HOST then
        run_network_function(name, "create_user_ALL")
        
        -- Sync current health and dead status to new clients
        sync_player_state(max_health, false)
    end
end

function shoot_at_nearest_monster(args)
    -- Don't shoot if player is dead
    if is_dead then
        return
    end
    
    -- Find the nearest monster, excluding self or any other entities you want
    local nearest_data = get_nearest_entity_by_tag(name, "monster")

    -- Check if a monster was found and is within range
    if nearest_data and nearest_data.name ~= nil then
        -- Create multiple bullets if projectile count > 1
        for i = 1, projectile_count do
            -- Calculate angle spread for projectiles evenly distributed in 360 degrees
            local angle_offset = 0
            if projectile_count > 1 then
                -- Divide 360 degrees by projectile_count for even distribution
                -- Subtract 1 from i so first bullet (i=1) targets the enemy directly
                angle_offset = (i - 1) * (2 * math.pi / projectile_count)
            end

            -- Create the bullet with properties from player stats
            local bullet_data = {
            t = "bullet",                -- Script name
            p = position,             -- Starting position
            r = nearest_data.angle + angle_offset,  -- Rotation with 360 degree spread
            steam_id = name,               --  Those variables should be few chars for network optimization but I'm lazy
            damage = damage,
            speed = projectile_speed,
            factor = projectile_factor,
            penetration = projectile_penetration,
            knockback = knockback
            }

            spawn_entity_host(bullet_data)
        end
    end
end

if IS_HOST  then
    start_timer({
    entity_name=name,
    timer_id = "shoot_timer"..name,--we add name to end to each user will have it own timer
    wait_time = fire_interval,

    function_name = "shoot_at_nearest_monster"
    })

    -- Add damage check timer
    start_timer({
        entity_name = name,
        timer_id = "damage_check_timer"..name,
        wait_time = 0.2, 
        function_name = "check_monster_damage"
    })
end



function on_area_area_entered(body_name)
    if IS_HOST==false then
        return
    end

    if has_tag(body_name,"xp") then
        destroy("", body_name)
        -- Apply experience gain multiplier
        collected_xp = collected_xp + (1 * experience_gain)
        
        -- Track crystal collected
        run_function("-stats", "add_player_stat", {name, "crystals_collected", 1})

        -- Check for level up
        while collected_xp >= required_xp do
            collected_xp = 0  -- Reset XP when leveling up
            current_level = current_level + 1
            -- Calculate required XP for the new level (10% more than base)
            required_xp = math.floor(base_xp_requirement * (1.1 ^ (current_level)))
            
            -- Trigger upgrade system
            run_function("-stats", "update_player_level", {name, current_level})
            run_function("-sm", "add_right", {name, 1})
        end

        -- Send all calculated values to client
        run_network_function(name, "update_collected_xp_CLIENT", {collected_xp, current_level, required_xp}, name)
    end
    
    -- Check if a living player entered a dead player's area
    if has_tag(body_name, "user") and not has_tag(body_name, "dead") and is_dead then
        -- Start revive process
        start_revive(body_name)
    end
end

function on_area_area_exited(body_name)
    if IS_HOST==false then
        return
    end
    
    -- Check if a living player exited a dead player's area
    if has_tag(body_name, "user") and not has_tag(body_name, "dead") and is_dead then
        -- Stop revive process
        stop_revive()
    end
end

-- Update collected XP on the client side
function update_collected_xp_CLIENT(sender_id, _collected_xp, _current_level, _required_xp)
    -- Just take the values calculated by the host
    collected_xp = _collected_xp
    required_xp = _required_xp

    -- Update level UI
    if IS_LOCAL then
        current_level = _current_level
        -- Update level display with XP progress
        set_label({
            name = "_level_label",
            text = string.format("Level %d: XP %d/%d", current_level, math.floor(collected_xp), required_xp)
        })
        -- Update progress bar with the collected_xp from host
        set_progress_bar({
            name = "_level_progress_bar",
            value = collected_xp,
            max_value = required_xp
        })
        set_audio({
            stream_path = "crystal",
            random_pitch = 0.15,
        })
    end
end







-- Add a new function to handle incoming healing
function add_health(amount)
    if is_dead then return 0 end
    
    local old_health = current_health
    _current_health = math.min(current_health + amount, max_health)
    
    -- Calculate actual healing applied
    local actual_healing = _current_health - old_health
    
    -- Update health bar if this is local player
    if IS_LOCAL then
        set_progress_bar({
            name = "_health_progress_bar",
            value = _current_health
        })
        -- Update health label
        set_label({
            name = "_health_label",
            text = string.format("Health: %d/%d", math.floor(_current_health), math.floor(max_health))
            })
    end
    
    -- Sync player state
    if IS_HOST then
        sync_player_state(_current_health, is_dead)
    end
    
    return actual_healing
end

-- Helper function for taking damage that includes dodge chance
-- check_monster_damage and bullet collision only run on host so we don't need to check if IS_HOST
function take_damage(incoming_damage)
    -- Don't take damage if already dead
    if is_dead  then
        return 0
    end
    
    -- Check for dodge
    if math.random() < dodge_chance then
        -- Track dodged attack
        run_function("-stats", "add_player_stat", {name, "bullets_dodged", 1})
        return 0
    end
    
    -- Calculate damage reduction from armor
    local damage_prevented = incoming_damage * armor
    
    -- Apply armor reduction
    local reduced_damage = incoming_damage - damage_prevented
    
    -- Store old health for damage calculation
    local old_health = current_health
    
    -- Update health
    _current_health = math.max(0, current_health - reduced_damage)
    
    -- Track damage taken stats
    if reduced_damage > 0 then
        run_function("-stats", "add_player_stat", {name, "damage_taken", reduced_damage})
    end

    if damage_prevented > 0 then
        run_function("-stats", "add_player_stat", {name, "damage_prevented", damage_prevented})
    end
    
    -- Check if player died
    if _current_health <= 0 then
        -- Handle death
        handle_death()
    end
    
    -- Sync player state
    sync_player_state(_current_health, is_dead)
    
    return reduced_damage
end

-- Handle player death
function handle_death()
    if IS_HOST and not is_dead then
        -- Set dead state
        
        -- Track player downed
        run_function("-stats", "add_player_stat", {name, "times_downed", 1})
        
        -- Add dead tag for identification
        add_tag(name, "dead")
        
        -- Remove alive tag so monsters won't target dead players
        remove_tag(name, "alive")
        
        -- Sync to clients
        sync_player_state(current_health, true)
        
        -- Announce death
        add_to_chat("[color=#aa4499]"..nickname.."[/color]".."[color=#883377] has been downed! Go to revive![/color]",true)

        -- Check if all players are dead
        run_function("-wm", "check_game_over")
    end
end

-- Function to check for overlapping monsters and apply damage
function check_monster_damage()
    if is_dead then
        return
    end
    -- Get all overlapping monsters
    overlapping_monsters = get_overlapping_entities("", name, taking_damage_area_name, "monster")
    -- Calculate total damage from all overlapping monsters
    local total_damage = 0
    for _, monster_name in ipairs(overlapping_monsters) do
        -- Get monster's damage value
        local monster_damage = get_value("", monster_name, "damage") or 0
        total_damage = total_damage + monster_damage
    end
    
    -- Apply damage if any monsters are overlapping
    if total_damage > 0 then
        take_damage(total_damage)
    end
end

-- Reset player UI elements
function reset_player_ui_ALL(sender_id)
    if IS_LOCAL then
        -- Reset level and XP
        current_level = 0
        collected_xp = 0
        required_xp = base_xp_requirement
        
        -- Update level display
        set_label({
            name = "_level_label",
            text = string.format("Level %d: %d/%d", current_level, 0, required_xp)
        })
        
        -- Reset level progress bar
        set_progress_bar({
            name = "_level_progress_bar",
            value = 0,
            max_value = required_xp
        })
        
        -- Reset health bar and label
        set_progress_bar({
            name = "_health_progress_bar",
            max_value = max_health,
            value = max_health
        })
        set_label({
            name = "_health_label",
            text = string.format("Health: %d/%d", math.floor(max_health), math.floor(max_health))
        })
        
        -- Reset time display
        set_label({
            name = "_time_label",
            text = "Time: 00:00"
        })
        
        -- Clear center information
        set_label({
            name = "_center_information",
            text = "",
            font_color = Color(1, 1, 1, 1)
        })
        

    end
end

-- Function to refill health to max
function refill_health_ALL()
    -- Set current health to max
    current_health = max_health
    -- Update health bar if this is the local player
    if IS_LOCAL then
        set_progress_bar({
            name = "_health_progress_bar",
            value = current_health
        })
        -- Update health label
        set_label({
            name = "_health_label",
            text = string.format("Health: %d/%d", math.floor(current_health), math.floor(max_health))
            })
    end
end

-- Start revive process for a downed player
function start_revive(revivor_id)
    if IS_HOST==false or not is_dead then
        return
    end
    
    -- Reset revive progress
    revive_progress = 0
    
    -- Show revive progress bar to all clients
    run_network_function(name, "show_revive_progress_bar_ALL", {true})
    
    -- Start the revive timer
    start_timer({
        entity_name = name,
        timer_id = "revive_timer_" .. name,
        wait_time = 0.1,

        function_name = "update_revive_progress",
        extra_args = {revivor_id = revivor_id}
    })
end

-- Stop the revive process
function stop_revive()
    if IS_HOST then
        -- Hide revive progress bar for all clients
        run_network_function(name, "show_revive_progress_bar_ALL", {false})
        
        -- Stop the timer
        stop_timer("revive_timer_" .. name)
    end
end

-- Update revive progress
function update_revive_progress(args)
    if not is_dead or not args.extra_args or not args.extra_args.revivor_id then
        stop_revive()
        return
    end
    
    -- Add to progress
    revive_progress = revive_progress + revive_increment
    
    -- Update progress bar on all clients
    run_network_function(name, "update_revive_progress_ALL", {revive_progress})
    
    -- Check if revive is complete
    if revive_progress >= 100 then
        -- Complete revive
        revive_player()
        
        -- Track revive performed by revivor
        run_function("-stats", "add_player_stat", {args.extra_args.revivor_id, "revives_performed", 1})
        
        -- Announce revive
        add_to_chat("[color=#117733]"..nickname.."[/color][color=#0f6622] has been revived by [/color][color=#117733]"..get_value("", args.extra_args.revivor_id, "nickname").."[/color]", true)
        
        -- Stop timer
        stop_timer("revive_timer_" .. name)
    end
end

-- Show or hide the revive progress bar
function show_revive_progress_bar_ALL(sender_id, visible)
    set_progress_bar({
        parent_name = name,
        name = revive_progress_bar_name,
        visible = visible,
    })
end

-- Update the revive progress bar
function update_revive_progress_ALL(sender_id, progress)
    revive_progress = progress
    set_progress_bar({
        parent_name = name,
        name = revive_progress_bar_name,
        value = progress
    })
end

-- Revive the player
function revive_player()
    if not is_dead then
        return false
    end
    
    -- Add alive tag back
    add_tag(name, "alive")
    
    -- Remove dead tag
    remove_tag(name, "dead")
    
    -- Hide revive progress bar
    run_network_function(name, "show_revive_progress_bar_ALL", {false})
    
    -- Sync to clients with half health
    if IS_HOST then
        sync_player_state(max_health / 2, false)
    end
    
    return true
end

-- Character upgrade functions
function update_movement_speed(increase_percentage)
    -- Increase movement_speed by percentage
    movement_speed = movement_speed * (1 + increase_percentage)
    
    -- Update RigidBody2D speed property
    set_value("", name, "speed", movement_speed)

end

function update_max_health(increase_percentage)
    -- Calculate new max health
    local old_max_health = max_health
    max_health = max_health * (1 + increase_percentage)
    
    -- Also increase current health proportionally
    current_health = current_health * (max_health / old_max_health)
    
    -- Update UI if this is the local player
    if IS_LOCAL then
        set_progress_bar({
            name = "_health_progress_bar",
            max_value = max_health,
            value = current_health
        })
        -- Update health label
        set_label({
            name = "_health_label",
            text = string.format("Health: %d/%d", math.floor(current_health), math.floor(max_health))
            })
    end

end

function update_armor(increase_percentage)
    -- Increase armor by percentage
    armor = armor + increase_percentage

end

function update_pickup_range(increase_percentage)
    -- Increase pickup range by percentage
    pickup_range = pickup_range * (1 + increase_percentage)
    
    -- Update pickup range
    area_config = {
        parent_name = name,
        name = area_name,
        shape = "circle",
        size = pickup_range,
        collision_layer = {2},
        collision_mask = {2}
    }
    set_area(area_config)
    
end

function update_experience_gain(increase_percentage)
    -- Increase experience gain by percentage
    experience_gain = experience_gain * (1 + increase_percentage)
    

end

function update_regeneration(increase_percentage)
    -- Set regeneration value (regenerates this percentage of max health per second)
    regeneration = regeneration + increase_percentage
    
    -- If this is the first time adding regeneration, start the regeneration timer
    if regeneration > 0 and not get_value("", name, "regen_timer_active") then
        start_timer({
            entity_name = name,
            timer_id = "regeneration_timer",
            wait_time = 1.0, -- Regenerate every second

            function_name = "apply_regeneration"
        })
        set_value("", name, "regen_timer_active", true)
    end

end

-- Function called by the regeneration timer
function apply_regeneration()
    if regeneration > 0 and not is_dead then
        local healing = max_health * regeneration
        local actual_healing = add_health(healing)
        
        -- Track regeneration healing separately
        if IS_HOST and actual_healing > 0 then
            run_function("-stats", "add_player_stat", {name, "damage_regenerated", actual_healing})
        end
    end
end

function update_dodge_chance(increase_percentage)
    -- Increase dodge chance
    dodge_chance = dodge_chance + increase_percentage

end

-- Weapon upgrade functions
function update_attack_speed(increase_percentage)
    -- Decrease fire interval (increase attack speed)
    attack_speed = attack_speed * (1 + increase_percentage)
    local new_fire_interval = 1.0 / attack_speed
    
    -- Update the shooting timer if on host
    if IS_HOST then
        stop_timer("shoot_timer"..name)
        start_timer({
            entity_name = name,
            timer_id = "shoot_timer"..name,
            wait_time = new_fire_interval,

            function_name = "shoot_at_nearest_monster"
        })
    end
    

end

function update_projectile_size(increase_percentage)
    -- Increase projectile factor by percentage
    projectile_factor = projectile_factor * (1 + increase_percentage)
end

function update_projectile_count(increase_value)
    -- Increase projectile count by value (usually 1)
    projectile_count = projectile_count + increase_value
end

function update_projectile_speed(increase_percentage)
    -- Increase projectile speed by percentage
    projectile_speed = projectile_speed * (1 + increase_percentage)

end

function update_projectile_penetration(increase_value)
    -- Increase penetration by value (usually 1)
    projectile_penetration = projectile_penetration + increase_value

end

function update_lifesteal(increase_percentage)
    -- Increase lifesteal by percentage
    lifesteal = lifesteal + increase_percentage

end

function update_knockback(increase_percentage)
    -- Increase knockback by percentage
    knockback = knockback * (1 + increase_percentage)

end

function update_damage(increase_percentage)
    -- Increase damage by percentage
    damage = damage * (1 + increase_percentage)
end

-- Apply lifesteal when dealing damage
function apply_lifesteal(damage_dealt)
    if lifesteal > 0 then
        local healing = damage_dealt * lifesteal
        local actual_healing = add_health(healing)
        
        if IS_HOST and actual_healing > 0 then
            run_function("-stats", "add_player_stat", {name, "lifesteal_amount", actual_healing})
        end
    end
end

-- Sync player health and dead status to all clients
function sync_player_state(_current_health, _is_dead)
    if IS_HOST then
        run_network_function(name, "update_player_state_ALL", {_current_health, _is_dead})
    end
end

-- Client-side function to update player state
function update_player_state_ALL(sender_id, health, dead_status)
    local was_alive = not is_dead
    
    -- Calculate health difference for screen shake
    local health_difference = current_health - health
    
    -- Update health and death status
    current_health = health
    is_dead = dead_status
    
    -- Update visual appearance based on dead status
    if is_dead then
        set_death_appearance()
        set_value("",name,"speed",0 )
       
        -- Play death sound if this is the local player and they just died
        if was_alive then
            show_teammate_down_message(nickname)

            set_audio({
                stream_path = "dead",
                random_pitch = 0.15
            })

        end
    else
       

        set_alive_appearance()
        set_value("", name, "speed", movement_speed)
    end
    
    if IS_LOCAL then

        -- Apply screen shake based on damage taken
        if health_difference > 0 then
            -- Calculate screen shake intensity based on damage (capped at 5)
            local shake_intensity = math.min(5, health_difference)
            screenshake(1, shake_intensity)
            
            -- Play hurt sound for local player when taking damage and still alive
            if not is_dead then
                set_audio({
                    stream_path = "hurt",
                    random_pitch = 0.15,
                    volume = -10-- must be between -80 and 24
                })
            end
        end
        
        -- Update health bar
        set_progress_bar({
            name = "_health_progress_bar",
            value = current_health
        })
        -- Update health label
        set_label({
            name = "_health_label",
            text = string.format("Health: %d/%d", math.floor(current_health), math.floor(max_health))
            })
        
        -- Show death message if player died
        if is_dead then
            -- Display message that teammates can revive you
            set_label({
                name = "_center_information",
                text = "You died! Your teammates can revive you.",
                font_color = Color(1, 0.3, 0.3, 1)  -- Light red color
            })
        else
            set_label({
                name = "_center_information",
                text = "",
                font_color = Color(1, 1, 1, 1)
            })
        end
    end
end

-- Set the visual appearance for dead player
function set_death_appearance()

    -- Close upgrade panel if it exists
    if is_panel_exists("upgrade_panel") then
        close_panel("upgrade_panel")
    end

    -- Make nickname purple
    set_label({
        name = nickname_label_name,
        color = Color(0.5, 0, 0.5, 1) -- Purple
    })
    
    -- Make image dark grey
    set_shader({
        parent_name = name,
        image_name = image_name,
        shader_name = "circle",
        inner_circle = 0.45,
        outer_circle = 0.49,
        smoothness = 0.01,
        outline_color = Color(0.5, 0, 0.5, 1),
    })

    if is_avatar_loaded then
        image_name= set_image({parent_name=name,name=image_name,image_path=name,scale=Vector2(32,32),modulate=Color(0.5, 0, 0.5, 1)})-- name in user entity is steam_id and path of avatar image
    else
        image_name= set_image({parent_name=name,name=image_name,scale=Vector2(32,32),modulate=Color(0.5, 0, 0.5, 1)})--just temporary image until avatar is loaded
    end
    
    -- Disable collision for dead player
    set_collision({
	parent_name=name,
        name = collision_name,
        disabled = true 
    })
end

-- Set the visual appearance for alive player
function set_alive_appearance()
    -- Reset nickname color
    set_label({
        name = nickname_label_name,
        color = Color(1, 1, 1, 1) -- White
    })
    
    set_shader({
        parent_name = name,
        image_name = image_name,
        shader_name = "circle",
        inner_circle = 0.45,
        outer_circle = 0.49,
        smoothness = 0.01,
        outline_color = Color(1, 1, 1, 1),

    })

    set_progress_bar({
        parent_name = name,
        name = revive_progress_bar_name,
        visible = false
    })
    
    if is_avatar_loaded then
        image_name= set_image({parent_name=name,name=image_name,image_path=name,scale=Vector2(32,32),modulate=Color(1, 1, 1, 1)})-- name in user entity is steam_id and path of avatar image
    else
        image_name= set_image({parent_name=name,name=image_name,scale=Vector2(32,32),modulate=Color(1, 1, 1, 1)})--just temporary image until avatar is loaded
    end
    
    -- Enable collision
    set_collision({
	parent_name=name,
        name = collision_name,
        disabled = false
    })
end


-- Function to show teammate down message
function show_teammate_down_message(downed_nickname)
    if IS_LOCAL ==false then-- Show only other players
        -- Show the message in purple
        label_text=downed_nickname .. " is down!"
        set_label({
            name = "_center_information",
            text = label_text,
            font_color = Color(0.5, 0, 0.5, 1)  -- Purple color
        })
        
        -- Start timer to clear the message after 2 seconds
        start_timer({
            entity_name = name,
            timer_id = "clear_down_message"..name,
            wait_time = 2.0,
            duration = 2.0,--it will be single shot because duration and wait_time are the same
            function_name = "clear_center_information",
            extra_args = {label_text=label_text}
        })
    end
end

-- Function to clear center information
function clear_center_information(args)
    current_label_text=get_value("","_center_information","text")
    if current_label_text==args.label_text then -- If the text is the same as the one we set, we clear it
        set_label({
            name = "_center_information",
            text = "",
            font_color = Color(1, 1, 1, 1)
        })  
    end
end












































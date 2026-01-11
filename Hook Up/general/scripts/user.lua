gravity_scale = 0.3
linear_damp = 0.001
bounce = 0.5             
friction = 200.0           
rough = 200.0   




-- User tags
add_tag(name, "user")

-- Avatar loading system
is_avatar_loaded = false

-- Collision
collision_name = ""

-- Visual elements
image_name = "player_image"
nickname_label_name = "nickname"
hook_power_bar_name = "_hook_power_bar"
hook_line_name = "hook_line"..name
cursor_name = "player_cursor"..name





-- Store the outline color that will be set by host
local outline_color = nil

-- Hook system variables
hook_state = "READY" -- READY, FIRING, ATTACHED, SEARCHING, WARNING, FISHING

hook_entity_name = "*hook_" .. name
hook_power = 30 -- Default hook power
hook_power_min = 100
hook_power_max = 600
hook_charging = false
hook_charge_time_accumulated = 0.0 -- Use accumulated time instead of start time
hook_charge_duration = 2.0 -- seconds
hook_firing_start_time = 0.0 -- Track when hook started firing
hook_firing_timeout = 5.0 -- 5 seconds timeout for firing state

-- Pong effect for hook power
hook_power_direction = 1 -- 1 for increasing, -1 for decreasing

-- New variable for fishing cooldown
hook_fishing_cooldown = 0.0
hook_fishing_cooldown_duration = 0.5 -- Half second cooldown

-- Warning visual elements
warning_emoji_name = "warning_emoji_" .. name

-- Cursor system variables
cursor_nickname_name = "cursor_nickname_" .. name
mouse_position = Vector2(0, 0)


function set_hook_state_ALL(sender_id, new_state)
    local old_state = hook_state
    

    hook_state = new_state

    -- If leaving fishing mode, stop fishing and start cooldown
    if old_state == "FISHING" and new_state ~= "FISHING" then
        if IS_LOCAL then
            run_function("-fishing_game_ui", "disable_fishing_ui", {})--2 second delay to show death message
        end
        
        -- Stop fishing on host (this will clean up the game state)
        if IS_HOST then
            run_function("-fishing_game", "stop_fishing_for_player", {name})
        end
        
        -- Start cooldown only when going from FISHING to READY and only for local player
        if new_state == "READY" and IS_LOCAL then
            hook_fishing_cooldown = hook_fishing_cooldown_duration
        end
    end
    

    
    -- State-specific logic consolidated into this network function
    if new_state == "FIRING" then
        -- Activate the reusable hook projectile
        run_function(hook_entity_name, "activate_hook", {})

        if IS_LOCAL then
        set_camera_target(hook_entity_name)
        end


    elseif new_state == "ATTACHED" then
        -- Update UI for attached state
        if IS_LOCAL then
            set_camera_target(name)
            set_label({
                name = "_hook_status_label",
                text = "HOOKED! Hold @key_7@/@key_12@ to launch to hook, press during firing to cancel",
                visible = true
            })
        end
    elseif new_state == "SEARCHING" then

        if IS_LOCAL then
            set_label({
                name = "_hook_status_label",
                text = "Searching for fish... Press @key_7@/@key_12@ to cancel",
                visible = true
            })
            -- Set camera to follow hook
            set_camera_target(hook_entity_name)
        end
        local hook_pos = get_value("", hook_entity_name, "position")
        start_particle({
            particle_id = "bubble_effect",
            position = hook_pos,
        })
        set_audio({
            stream_path = "water_splash",
            position = hook_pos,
            is_2d = true,
            random_pitch = 0.2,
            max_distance = 400.0
        })
    elseif new_state == "WARNING" then
        if IS_LOCAL then
            -- Keep camera on hook during warning
            set_camera_target(hook_entity_name)
            set_label({
                name = "_hook_status_label",
                text = "🐟 FISH FOUND! Press @key_7@/@key_12@ to catch! 🐟",
                visible = true
            })
        end
        
        -- Show warning emoji above hook
        local hook_pos = get_value("", hook_entity_name, "position")
        set_label({
            name = warning_emoji_name,
            text = "⚠️",
            font_size = 32,
            position = Vector2(hook_pos.x - 16, hook_pos.y - 50),
            size = Vector2(32, 32),
            horizontal_alignment = 1,
            vertical_alignment = 1,
            modulate = Color(1, 1, 0, 1), -- Yellow color for warning
            z_index = 15,
            visible = true
        })
        start_particle({
            particle_id = "bubble_effect",
            position = hook_pos,
        })
        set_audio({
            stream_path = "water_splash",
            position = hook_pos,
            is_2d = true,
            random_pitch = 0.2,
            max_distance = 400.0
        })
        
    elseif new_state == "FISHING" then
        -- Hide warning emoji when entering fishing
        set_label({
            name = warning_emoji_name,
            visible = false
        })
        
        if IS_LOCAL then
            -- Set camera to follow hook during fishing
            set_camera_target(hook_entity_name)
        end
        local hook_pos = get_value("", hook_entity_name, "position")
        start_particle({
            particle_id = "bubble_effect",
            position = hook_pos,
            })
        set_audio({
            stream_path = "water_splash",
            position = hook_pos,
            is_2d = true,
            random_pitch = 0.2,
            max_distance = 400.0
        })
    elseif new_state == "READY" then
        -- Hide warning emoji when going to ready
        set_label({
            name = warning_emoji_name,
            visible = false
        })
        run_function(hook_entity_name, "deactivate_hook", {})
        if IS_LOCAL then
            -- Return camera to player
            set_camera_target(name)
        end
    end

end


-- Helper: teleport a user to a target position
function teleport_user( target_pos)

    if not target_pos then return end
    change_instantly({
        entity_name = name,
        angular_velocity = 0.0,
        position = target_pos,
        linear_velocity = Vector2(0, 0),
        rotation = 0.0
    })
end

-- If the player's body enters an Area tagged "magma", reset self (host-only)
function on_body_body_entered(data)
    if not IS_HOST then return end

    entity_name=data["body_name"]

    if has_tag(entity_name, "magma") then
        local nearest = get_nearest_entity_by_tag(name, "checkpoint")
        if nearest and nearest.name and nearest.name ~= "" then
            local checkpoint_pos = get_value("", nearest.name, "position")
            if checkpoint_pos then
                teleport_user(checkpoint_pos )
            end
        end

    end
end

function create_user(sender_id, player_color,pos)
    -- Initialize voice chat for this player when they join
    if IS_HOST then
         -- Set global voice chat (proximity = 0 means global)

        set_voice_channel({
            steam_id = name,
            channel_name= "global",
            proximity_length=0,
        })

    end
    -- Set the outline color from host
    outline_color = player_color

    
    -- Create collision first (like Campfire)
    collision_config = {
        parent_name = name,
        shape = "circle",
        size = 16,
        collision_layer = {2},
        collision_mask = {1,4}
    }
    collision_name = set_collision(collision_config)
    
    -- Create nickname with synced outline color
    nickname_config = {
        parent_name = name,
        name = nickname_label_name,
        text = nickname,
        outline_color = outline_color,
        outline_size = 4,
        font_size = 8,
        position = Vector2(-256, -48),
        size = Vector2(512, 16),
        horizontal_alignment = 1,
        vertical_alignment = 1,
        z_index = 5
    }
    nickname_label_name = set_label(nickname_config)
    
    -- Create player visual with avatar system
    if is_avatar_loaded then
        image_name = set_image({
            parent_name = name,
            name = image_name,
            image_path = name, -- name is steam_id for avatar path
            scale = Vector2(32, 32)
        })
    else
        image_name = set_image({
            parent_name = name,
            name = image_name,
            scale = Vector2(32, 32),
        })
    end
    
    -- Apply circle shader with synced outline color
    set_shader({
        parent_name = name,
        image_name = image_name,
        shader_name = "circle",
        inner_circle = 0.45,
        outer_circle = 0.49,
        smoothness = 0.01,
        outline_color = outline_color
    })
    
    -- Create cursor with player's outline color (invisible for local player)
    set_image({
        name = cursor_name,
        image_path = "cursor",
        scale = Vector2(16, 16),
        modulate = outline_color,
        position = Vector2(0, 0),
        z_index = 10,
        visible = not IS_LOCAL  -- Local player doesn't see their own cursor
    })
    
    -- Create cursor nickname label (invisible for local player)
    set_label({
        parent_name = cursor_name, -- Child of cursor, will move automatically
        name = cursor_nickname_name,
        text = nickname,
        font_size = 12,
        position = Vector2(-100, 20), -- Relative to cursor position
        size = Vector2(200, 20),
        horizontal_alignment = 1, -- Center
        vertical_alignment = 1, -- Center
        --modulate = outline_color, --its already set in set_image
        outline_color = Color(0, 0, 0, 1), -- Black outline
        outline_size = 8,
        z_index = 10,
        --visible = not IS_LOCAL  --its already set in set_image Local player doesn't see their own cursor nickname
    })
    
    -- Create reusable hook projectile
    local hook_data = {
        t = "hook_projectile",
        p = Vector2(0, 0), -- Will be positioned when activated
        n = "hook_" .. name,
        modulate = outline_color,
        owner_name = name
    }
    if IS_HOST then
    hook_entity_name = spawn_entity_host(hook_data)
    end


    if IS_LOCAL then
        set_camera_target(name)
        create_hook_ui()
    end
	
    change_instantly({
        entity_name = name,
        angular_velocity = 0.0,
        position = pos,
        linear_velocity = Vector2(0, 0),
        rotation = 0.0
    })

end

function create_user_CLIENT(sender_id, player_color,pos)
    create_user(sender_id, player_color,pos)
end

function create_user_ALL(sender_id, player_color,pos)
    create_user(sender_id, player_color,pos)
end



-- Generate random outline color for each player
local function generate_random_color()
    -- Generate bright, vibrant colors
    local hue = math.random() * 360
    local saturation = 0.7 + (math.random() * 0.3) -- 0.7 to 1.0
    local value = 0.8 + (math.random() * 0.2) -- 0.8 to 1.0
    
    -- Convert HSV to RGB
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


-- Warning If you type this function in the user.lua file, it will be called on each user entity on each user
-- For example if room have 9 users already and someone is joined, this function 
-- will be called 1 times on each user entity, total 10 times on each client/host
-- so you need to check steam_id == name to avoid or type this function in singleton/unique entity 

function _on_user_initialized(steam_id, nickname)
    -- This will be called when a client has fully downloaded and initialized
    -- Safe to call network functions now for this client

    if IS_HOST then 
        if steam_id == name then
            
            -- Generate color on host side and pass it all clients
            local player_color = generate_random_color()
            local spawn_position=get_value("","-spawn_point","position")
            run_network_function(name, "create_user_ALL", {player_color,spawn_position})
        else
            -- Pass older clients to new client
            -- outline_color is already set when older client joined
            -- Position could be different so we need to get recent position
          
            run_network_function(name, "create_user_CLIENT", {outline_color,position},steam_id)
        end
    end
end 

function _on_user_disconnected(steam_id,nickname)
    if steam_id == name then
        add_to_chat(nickname.. " disconnected")
        destroy("", hook_entity_name)
        destroy("",cursor_name)
        destroy("",cursor_nickname_name)
        destroy_line(hook_line_name)
    end
end



function create_hook_ui()
    -- Hook power progress bar
    hook_power_bar_config = {
        name = hook_power_bar_name,

        value = hook_power,
        max_value = hook_power_max,

        visible = true
    }
    hook_power_bar_name = set_progress_bar(hook_power_bar_config)
end

-- Input tracking variables
last_x_input = false
last_x2_input = false  -- For key_13
last_b_input = false

function _process(delta, inputs)
    -- Update mouse position and cursor
    update_cursor(inputs)

    if IS_LOCAL then
        handle_inventory_input(inputs)
        -- Update fishing cooldown timer
        if hook_fishing_cooldown > 0 then
            hook_fishing_cooldown = hook_fishing_cooldown - delta
            if hook_fishing_cooldown < 0 then
                hook_fishing_cooldown = 0
            end
        end
        
        handle_hook_input(delta, inputs)
        update_hook_power_ui()
        
        -- Handle firing timeout
        if hook_state == "FIRING" then
            hook_firing_start_time = hook_firing_start_time + delta
            if hook_firing_start_time >= hook_firing_timeout then
                -- Timeout reached, reset hook system
                if IS_HOST then
                    run_network_function(name, "reset_hook_system_ALL", {})
                end
                if IS_LOCAL then
                    set_label({
                        name = "_hook_timeout_label",
                        text = "Hook timed out! You can fire again.",
                        position = Vector2(20, 60),
                        size = Vector2(400, 20),
                        modulate = Color(1, 0.8, 0, 1),
                        visible = true
                    })
                    
                end
            end
        end
        


    end
    update_hook_line()

    
    return inputs
end

function update_cursor(inputs)
    mouse_position = inputs["stick_2"] or Vector2(-999999,-999999)

    if IS_LOCAL then
        set_image({
            name = cursor_name,
            --image_path = "cursor", we dont need this already set in set_image in create_user_ALL
            position = mouse_position,
        })
        -- Nickname automatically follows cursor since it's a child
    end
    
    -- Sync cursor position to all other players
    if IS_HOST then
        run_network_function(name, "update_cursor_position_ALL", {mouse_position})
    end
end

function update_cursor_position_ALL(sender_id,cursor_pos)
    -- If this is the local player, don't update (they control their own cursor)
    if IS_LOCAL then
        return
    end
    
    -- Update cursor position for non-local players
    set_image({
        name = cursor_name,
        position = cursor_pos,
    })
    -- Nickname automatically follows cursor since it's a child
end



function handle_hook_input(delta, inputs)

    local x_input = inputs["key_7"] or false  -- Use 'key_8' for hook charging
    local x2_input = inputs["key_12"] or false  -- Use 'key_13' for hook charging
    
    -- Combine both inputs - hook activates if either key is pressed
    local hook_input = x_input or x2_input
    local last_hook_input = last_x_input or last_x2_input
    
    -- Check for just pressed hook (was false, now true)
    local hook_just_pressed = hook_input and not last_hook_input
    -- Check for just released hook (was true, now false)
    local hook_just_released = not hook_input and last_hook_input
    
    -- Phase 1: Hook firing to mouse position
    if hook_state == "READY" then

        if hook_just_pressed and not hook_charging and hook_fishing_cooldown <= 0 then
            -- Start charging hook (only if not in cooldown)
            hook_charging = true
            hook_charge_time_accumulated = 0.0
        end
        
        if hook_charging and hook_input then
            -- Update hook power with pong effect
            hook_charge_time_accumulated = hook_charge_time_accumulated + delta
            
            -- Pong effect calculation (2x faster)
            local progress_speed = 2.0 / hook_charge_duration -- 2x faster pong effect
            local current_progress = (hook_charge_time_accumulated * progress_speed) % 2.0 -- 0-2 cycle
            
            local normalized_progress
            if current_progress <= 1.0 then
                normalized_progress = current_progress -- 0 to 1
            else
                normalized_progress = 2.0 - current_progress -- 1 to 0
            end
            
            -- Apply to hook power
            hook_power = hook_power_min + (hook_power_max - hook_power_min) * normalized_progress

        end
        
        if hook_just_released and hook_charging then
            -- Release hook to mouse position
            hook_charging = false
            fire_hook_to_mouse()
        end
    
    -- Phase 2: User firing to hook position
    elseif hook_state == "ATTACHED" then

        
        if hook_just_pressed and not hook_charging then
            -- Start charging for user launch
            hook_charging = true
            hook_charge_time_accumulated = 0.0
        end
        
        if hook_charging and hook_input then
            -- Update hook power with pong effect
            hook_charge_time_accumulated = hook_charge_time_accumulated + delta
            
            -- Pong effect calculation (2x faster)
            local progress_speed = 2.0 / hook_charge_duration -- 2x faster pong effect
            local current_progress = (hook_charge_time_accumulated * progress_speed) % 2.0 -- 0-2 cycle
            
            local normalized_progress
            if current_progress <= 1.0 then
                normalized_progress = current_progress -- 0 to 1
            else
                normalized_progress = 2.0 - current_progress -- 1 to 0
            end
            
            -- Apply to hook power
            hook_power = hook_power_min + (hook_power_max - hook_power_min) * normalized_progress
        end
        
        if hook_just_released and hook_charging then
            -- Launch user to hook position
            hook_charging = false
            fire_user_to_hook()
        end
    
    -- Phase 3: Firing state
    elseif hook_state == "FIRING" then

        
        -- During firing, hook key can be used to cancel/detach
        if hook_just_pressed then
            -- Send detach request to host
            if IS_LOCAL then
                run_network_function(name, "request_detach_hook_HOST", {})
            end
        end
        
    -- Phase 4: Searching state
    elseif hook_state == "SEARCHING" then
        -- During searching, hook key cancels and returns to ready
        if hook_just_pressed then
            if IS_LOCAL then
                run_network_function(name, "request_cancel_searching_HOST", {})
            end
        end
    
    -- Phase 5: Warning state
    elseif hook_state == "WARNING" then
        -- During warning, hook key catches the fish and transitions to fishing
        if hook_just_pressed then
            if IS_LOCAL then
                run_network_function("-fishing_game", "handle_warning_catch_HOST", {})
            end
        end
    
    -- Phase 6: Fishing state
    elseif hook_state == "FISHING" then
        -- During fishing, hook key is used for fishing actions
        if hook_just_pressed then
            -- Send fishing click to game
            if IS_LOCAL then
                run_network_function("-fishing_game", "handle_fishing_click_HOST", {})
            end
        end
    end
    

    
    -- Update last input states
    last_x_input = x_input
    last_x2_input = x2_input
end

-- Inventory toggle input handling
function handle_inventory_input(inputs)
    local b_input = inputs["key_6"] or false  -- 'key_7' for inventory toggle ( default E key )

    -- Detect just released
    local b_just_released = (not b_input) and last_b_input

    if b_just_released then
        if is_panel_exists("_inventory_panel") then
            -- Panel open, simply close locally
            close_panel("_inventory_panel")
        else
            run_function("-inventory_manager", "create_loading_panel", {})

            -- Request inventory data from host
            run_network_function("-inventory_manager", "request_inventory_data_HOST", {})
        end
    end

    -- Update last state
    last_b_input = b_input
end

function fire_hook_to_mouse()
    if hook_state == "FIRING" or not hook_entity_name or hook_entity_name == "" then
        return
    end
    hook_firing_start_time = 0.0 -- Reset firing timer
    
    -- Send hook fire request to host with only hook power (host calculates everything else)
    if IS_LOCAL then
        run_network_function(name, "request_fire_hook_HOST", {hook_power})
    end
end

function fire_user_to_hook()
    if hook_state ~= "ATTACHED" then
        return
    end
    
    -- Send user launch request to host with only hook power
    if IS_LOCAL then
        run_network_function(name, "request_launch_user_HOST", {hook_power})
    end
end

-- HOST function: Validate and process hook fire request
function request_fire_hook_HOST(sender_id, requested_power)
    if sender_id ~= name then-- each user can only fire to their own hook
        return
    end

    -- Only allow firing if in READY state
    if hook_state ~= "READY" then
        print("Fire hook denied: player not in READY state (current: " .. hook_state .. ")")
        return
    end

    -- Clamp power to prevent cheating
    local clamped_power = math.max(hook_power_min, math.min(requested_power, hook_power_max))
    
    -- Calculate direction from player position to mouse
    local direction = mouse_position - position
    direction = direction.normalized()
    
    
    -- Calculate velocity with clamped power
    local _velocity = direction * clamped_power

    unfreeze_entity(hook_entity_name,true)
    change_instantly({
        entity_name = hook_entity_name,
        linear_velocity = _velocity,
        position = position
    })
 
    -- Send fire command to all clients including the sender
    run_network_function(sender_id, "set_hook_state_ALL", {"FIRING"})
end



function update_hook_power_ui()
    -- Update status based on hook state
    if IS_LOCAL then
        -- Only show power bar and label during READY and ATTACHED states
        local should_show_power_bar = (hook_state == "READY" or hook_state == "ATTACHED")
        
        if hook_power_bar_name then
            -- Different colors based on hook state
            local hook_color
            if hook_state == "READY" then
                -- Hook Power: Blue to Cyan gradient
                local power_ratio = hook_power / hook_power_max
                hook_color = Color(0.2, 0.5 + power_ratio * 0.5, 1.0, 1.0) -- Blue to Light Blue
            elseif hook_state == "ATTACHED" then
                -- Jump Power: Orange to Red gradient
                local power_ratio = hook_power / hook_power_max
                hook_color = Color(1.0, 0.5 + power_ratio * 0.5, 0.2, 1.0) -- Orange to Red
            else
                -- Default color (shouldn't be reached due to visibility logic)
                local power_ratio = hook_power / hook_power_max
                hook_color = Color(power_ratio, 1.0 - power_ratio, 0.0, 1.0)
            end
            
            set_progress_bar({
                name = hook_power_bar_name,
                value = hook_power,
                max_value = hook_power_max,
                visible = should_show_power_bar,
                modulate = hook_color
            })
        end
        
        -- Set power label text and color based on hook state
        local power_label_text = ""
        local label_color = Color(1, 1, 1, 1) -- Default white
        
        if hook_state == "READY" then
            power_label_text = "Hook Power"
            label_color = Color(0.5, 0.8, 1.0, 1.0) -- Light blue for hook power
        elseif hook_state == "ATTACHED" then
            power_label_text = "Jump Power"
            label_color = Color(1.0, 0.7, 0.3, 1.0) -- Orange for jump power
        end
        
        set_label({
            parent_name = "",
            name = "_hook_power_label",
            text = power_label_text,
            modulate = label_color,
            visible = should_show_power_bar
        })

        local status_text = ""
        if hook_state == "READY" then
            if hook_fishing_cooldown > 0 then
                status_text = string.format("Cooldown: %.1fs", hook_fishing_cooldown)
            elseif hook_charging then
                status_text = "Charging hook... Release @key_7@/@key_12@ to fire!"
            else
                status_text = "Ready to fire hook - Hold @key_7@/@key_12@"
            end
        elseif hook_state == "FIRING" then
            status_text = "FIRING"
        elseif hook_state == "ATTACHED" then
            if hook_charging then
                status_text = "Charging launch... Release @key_7@/@key_12@ to launch!"
            else
                status_text = "HOOKED! Hold @key_7@/@key_12@ to launch, press during firing to cancel"
            end
        elseif hook_state == "SEARCHING" then
            status_text = "SEARCHING for fish... Press @key_7@/@key_12@ to cancel"
        elseif hook_state == "WARNING" then
            status_text = "WARNING FOUND FISH! Use @key_7@/@key_12@ to catch! 🐟"
        elseif hook_state == "FISHING" then
            status_text = "FISHING - Use @key_7@/@key_12@ to fish on green light and yellow light to catch!"
        end
        
        set_label({
            name = "_hook_status_label",
            text = status_text,
            visible = status_text ~= ""
        })
    end
end









-- Avatar loading system (like Campfire)
function _on_loaded_avatar(steam_id)
    if name == steam_id then -- if it is this user entity
        is_avatar_loaded = true
        image_config = {
            parent_name = name,
            image_name = image_name,
            image_path = steam_id,
            scale = Vector2(32, 32)
        }
        image_name = set_image(image_config)
        -- Reapply shader with random outline color
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

-- HOST function: Process detach request
function request_detach_hook_HOST(sender_id)
    if sender_id ~= name then
        return
    end
    
    -- Only allow detaching if in FIRING state
    if hook_state ~= "FIRING" then
        print("Detach hook denied: player not in FIRING state (current: " .. hook_state .. ")")
        return
    end
    
    -- Send reset command to all clients
    run_network_function(sender_id, "reset_hook_system_ALL", {})
end

-- HOST function: Process cancel searching request
function request_cancel_searching_HOST(sender_id)
    if sender_id ~= name then
        return
    end
    
    -- Only allow canceling if actually in SEARCHING state
    if hook_state ~= "SEARCHING" then
        print("Cancel searching denied: player not in SEARCHING state (current: " .. hook_state .. ")")
        return
    end
    
    -- Show cancellation bubble effect before stopping fishing
    run_function("-fishing_game", "show_world_space_result", {name, "", "🚫 Fishing cancelled"})
    
    -- Stop searching timer if active
    run_function("-fishing_game", "stop_searching_for_player", {name})
    
    -- Send reset command to all clients
    run_network_function(sender_id, "reset_hook_system_ALL", {})
end

-- HOST function: Validate and process user launch to hook
function request_launch_user_HOST(sender_id, requested_power)
    if sender_id ~= name then
        return
    end

    -- Only allow launching if in ATTACHED state
    if hook_state ~= "ATTACHED" then
        print("Launch user denied: player not in ATTACHED state (current: " .. hook_state .. ")")
        return
    end

    -- Get current player position from host data
    local player_pos = get_value("", sender_id, "position")
    
    -- Get hook target position from the user's hook system
    local hook_pos = get_value("", hook_entity_name , "position")
    
    -- Clamp power to prevent cheating
    local clamped_power = math.max(hook_power_min, math.min(requested_power, hook_power_max))
    
    -- Calculate direction from player position to hook
    local direction = hook_pos - player_pos
    direction = direction.normalized()
    
    -- Calculate velocity with clamped power
    local _velocity = direction * clamped_power
        -- Apply velocity to user using set_value
    set_value("", name, "linear_velocity", _velocity)
    -- Send launch command to all clients
    run_network_function(sender_id, "reset_hook_system_ALL", { })
end


-- ALL function: Network-synchronized hook system reset
function reset_hook_system_ALL(sender_id)
    
    -- set_hook_state_ALL is a network function but we do not need to send again from host to client for optimization
    -- first parameter is dummy sender_id as "sender_id" for running function on this entity locally
    run_function(name, "set_hook_state_ALL", {"sender_id","READY"})


    hook_charging = false
    hook_charge_time_accumulated = 0.0
    hook_firing_start_time = 0.0
    hook_power_direction = 1 -- Reset pong direction


    
    -- Hook line will be hidden automatically by update_hook_line() since state is READY
    
    if IS_LOCAL then
        
        set_label({
            name = "_hook_status_label",
            text = "",
            visible = false
        })
        
        -- Hide timeout message if it exists
        set_label({
            name = "_hook_timeout_label",
            visible = false
        })
    end

end


function update_hook_line()
    local should_show_line = false
    local line_start = Vector2(0, 0)
    local line_end = Vector2(0, 0)
    
    if hook_state ~= "READY" then
        should_show_line = true
        line_start = position

        if hook_entity_name and hook_entity_name ~= "" then
            line_end = get_value("", hook_entity_name, "position")
        end
    end
    
    if should_show_line then
        -- Create or update hook line
        set_line({
            name = hook_line_name,
            start_position = line_start,
            end_position = line_end,
            color = outline_color or Color(1, 1, 1, 1),
            width = 2,
            visible = true
        })
    else  

        
        set_line({
            name = hook_line_name,
            visible = false,
            width = 0
        })
    end
end









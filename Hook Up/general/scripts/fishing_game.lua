network_mode = 1
singleton_name = "fishing_game"

-- Fish types based on fish_types.txt (22 fish total)
fish_types = {
    -- Common fish (7)
    {name = "Salmon", min_weight = 0.5, max_weight = 1.2, base_health = 40, heal_amount = 6, image = "fish/fish1", rarity = "common", water_source = "sea"},
    {name = "Mackerel", min_weight = 0.3, max_weight = 0.8, base_health = 35, heal_amount = 5, image = "fish/fish3", rarity = "common", water_source = "sea"},
    {name = "Mullet", min_weight = 0.4, max_weight = 1.0, base_health = 38, heal_amount = 5, image = "fish/fish5", rarity = "common", water_source = "lake"},

    {name = "Shrimp", min_weight = 0.1, max_weight = 0.3, base_health = 25, heal_amount = 3, image = "fish/fish21", rarity = "common", water_source = "swamp_water"},
    {name = "Scallop", min_weight = 0.2, max_weight = 0.5, base_health = 28, heal_amount = 4, image = "fish/fish15", rarity = "common", water_source = "sea"},
    {name = "Sea Urchin", min_weight = 0.1, max_weight = 0.4, base_health = 32, heal_amount = 4, image = "fish/fish19", rarity = "common", water_source = "cave_water"},
    
    -- Rare fish (7)
    {name = "Vermillon Snapper", min_weight = 0.8, max_weight = 1.8, base_health = 55, heal_amount = 8, image = "fish/fish2", rarity = "rare", water_source = "sea"},
    {name = "Angelfish", min_weight = 0.3, max_weight = 0.7, base_health = 45, heal_amount = 7, image = "fish/fish4", rarity = "rare", water_source = "lake"},
    {name = "Mediterranean Trout", min_weight = 1.0, max_weight = 2.2, base_health = 60, heal_amount = 9, image = "fish/fish6", rarity = "rare", water_source = "lake"},
    {name = "Sheepshead", min_weight = 1.2, max_weight = 2.5, base_health = 65, heal_amount = 10, image = "fish/fish8", rarity = "rare", water_source = "sea"},
    {name = "Squid", min_weight = 0.8, max_weight = 1.6, base_health = 50, heal_amount = 8, image = "fish/fish12", rarity = "rare", water_source = "cave_water"},
    {name = "Seahorse", min_weight = 0.1, max_weight = 0.3, base_health = 40, heal_amount = 6, image = "fish/fish13", rarity = "rare", water_source = "swamp_water"},

    
    -- Epic fish (5)
    {name = "Tuna", min_weight = 3.0, max_weight = 6.0, base_health = 100, heal_amount = 15, image = "fish/fish7", rarity = "epic", water_source = "sea"},
    {name = "Octopus", min_weight = 2.0, max_weight = 4.5, base_health = 90, heal_amount = 13, image = "fish/fish11", rarity = "epic", water_source = "cave_water"},
    {name = "Eel", min_weight = 1.5, max_weight = 3.0, base_health = 85, heal_amount = 12, image = "fish/fish16", rarity = "epic", water_source = "swamp_water"},
    {name = "Jellyfish", min_weight = 0.8, max_weight = 2.0, base_health = 75, heal_amount = 11, image = "fish/fish17", rarity = "epic", water_source = "sea"},
    {name = "Discus Fish", min_weight = 0.4, max_weight = 0.9, base_health = 48, heal_amount = 7, image = "fish/fish20", rarity = "epic", water_source = "lake"},
    {name = "Sea Turtle", min_weight = 15.0, max_weight = 35.0, base_health = 250, heal_amount = 30, image = "fish/fish14", rarity = "epic", water_source = "sea"},
    
    -- Legendary fish (3)
    {name = "Shark", min_weight = 8.0, max_weight = 20.0, base_health = 200, heal_amount = 25, image = "fish/fish9", rarity = "legendary", water_source = "sea"},
    {name = "Crab", min_weight = 0.2, max_weight = 0.6, base_health = 30, heal_amount = 4, image = "fish/fish10", rarity = "legendary", water_source = "swamp_water"},
    {name = "Yellow Pufferfish", min_weight = 0.6, max_weight = 1.4, base_health = 80, heal_amount = 12, image = "fish/fish18", rarity = "legendary", water_source = "lake"},
    {name = "Lobster", min_weight = 1.0, max_weight = 3.5, base_health = 150, heal_amount = 20, image = "fish/fish22", rarity = "legendary", water_source = "cave_water"}
}

-- Healing system
healing_interval = 0.2 -- Heal every 200ms

-- Active fishing players with improved timer system
active_fishing_players = {}

-- Active searching players with timers
active_searching_players = {}

-- Create bubble particle based on main.tscn bubble_particle
create_particle({
    particle_id = "bubble_effect",
    lifetime = 3.0,
    explosiveness = 1.0,
    randomness = 0.26,
    direction = {x = 0, y = -1},
    gravity = {x = 0, y = 100},
    initial_velocity_max = 119.72,
    angle_max = 207.8,
    scale_amount_max = 1,
    scale_amount_min = 0.5,
    amount = 50,
    spread =45,
    color=Color(1,1,1,1),
    one_shot=true,
    texture_path = "bubble"
})

function generate_random_fish(water_source)
    print("DEBUG: generate_random_fish called with water_source: " .. tostring(water_source))
    -- Filter fish by water source
    local available_fish = {}
    for i, fish_type in ipairs(fish_types) do
        if fish_type.water_source == water_source then
            table.insert(available_fish, fish_type)
        end
    end
    
    print("DEBUG: Found " .. #available_fish .. " fish types for water_source: " .. tostring(water_source))
    
    -- If no fish available for this water source, return garbage
    if #available_fish == 0 then
        print("DEBUG: No fish found for water_source, returning garbage")
        return generate_garbage()
    end
    
    -- Rarity weights for catch probability
    local rarity_weights = {
        common = 50,     -- 50% base chance
        rare = 25,       -- 25% base chance  
        epic = 15,       -- 15% base chance
        legendary = 10   -- 10% base chance
    }
    
    -- Create weighted list
    local weighted_fish = {}
    for i, fish_type in ipairs(available_fish) do
        local weight = rarity_weights[fish_type.rarity] or 1
        for j = 1, weight do
            table.insert(weighted_fish, fish_type)
        end
    end
    
    -- Random chance to get garbage instead of fish (varies by water source)
    local garbage_chance = 0.2 -- 20% base garbage chance
    if water_source == "swamp_water" then
        garbage_chance = 0.35 -- 35% in swamp
    elseif water_source == "cave_water" then
        garbage_chance = 0.25 -- 25% in caves
    end
    
    if math.random() < garbage_chance then
        return generate_garbage()
    end
    
    local fish_type = weighted_fish[math.random(#weighted_fish)]
    local weight = math.random() * (fish_type.max_weight - fish_type.min_weight) + fish_type.min_weight
    local weight_multiplier = weight ^ 0.7  -- Use ^ operator instead of math.pow
    
    return {
        name = fish_type.name,
        weight = math.floor(weight * 10) / 10, -- Round to 1 decimal
        health = math.floor(fish_type.base_health * weight_multiplier),
        heal_amount = math.floor(fish_type.heal_amount * weight_multiplier),
        image = fish_type.image,
        rarity = fish_type.rarity,
        water_source = fish_type.water_source,
        is_garbage = false
    }
end

function generate_garbage()
    local garbage_image = "garbage/garbage" .. math.random(1, 6) -- Random garbage1-6
    
    return {
        name = "Garbage",
        weight = 0,
        health = 0,
        heal_amount = 0,
        image = garbage_image,
        rarity = "garbage",
        water_source = "any",
        is_garbage = true
    }
end

-- Add at the top, after other state variables
local fishing_blocked = false

-- Prevent new fishing/searching if blocked
function start_searching_for_player(steam_id, water_source)
    if not IS_HOST or fishing_blocked then
        return
    end
    print("start_searching_for_player: " .. steam_id .. " in " .. tostring(water_source))
    print("DEBUG: Received water_source type: " .. type(water_source))
    
    -- Handle case where water_source might be passed as table/array
    local actual_water_source = water_source
    if type(water_source) == "table" and #water_source > 0 then
        actual_water_source = water_source[1]
        print("DEBUG: Extracted water_source from table: " .. tostring(actual_water_source))
    end
    
    -- Add player to searching list with water source
    active_searching_players[steam_id] = {
        timer_name = "search_timer_" .. steam_id,
        water_source = actual_water_source or "sea" -- Default to sea if not specified
    }
    
    print("DEBUG: Stored water_source for " .. steam_id .. ": " .. tostring(active_searching_players[steam_id].water_source))
    
    -- Generate random search time between 3-8 seconds
    local search_time = math.random() * 5 + 3 -- 3-8 seconds
    print("Setting search timer for " .. steam_id .. ": " .. search_time .. " seconds")
    
    -- Set timer to transition to fishing after search time
    start_timer({
        timer_id = active_searching_players[steam_id].timer_name,
        entity_name = name,
        function_name = "on_search_completed",
        wait_time = search_time,
        duration = search_time,
        extra_args = {steam_id = steam_id}
    })
    
end

function stop_searching_for_player(steam_id)
    if not IS_HOST then
        return
    end
    
    if active_searching_players[steam_id] then
        -- Cancel the timer
        local timer_name = active_searching_players[steam_id].timer_name
        stop_timer(timer_name)
        
        -- Remove from searching list
        active_searching_players[steam_id] = nil
        print("Stopped searching for: " .. steam_id)
    end
end

function on_search_completed(args)
    if not IS_HOST then
        return
    end
    print("on_search_completed: ")
    local steam_id = args.extra_args.steam_id
    print("Search completed for: " .. steam_id)
    
    -- Check if player is still in searching state
    local player_hook_state = get_value("", steam_id, "hook_state")
    if player_hook_state == "SEARCHING" then
        -- DON'T remove from searching list here - keep it for warning catch
        print("DEBUG: Keeping player " .. steam_id .. " in active_searching_players for warning catch")
        
        -- Transition to warning state instead of fishing
        run_network_function(steam_id, "set_hook_state_ALL", {"WARNING"})
        
        -- Start warning timer (1 second)
        start_timer({
            timer_id = "warning_timer_" .. steam_id,
            entity_name = name,
            function_name = "on_warning_timeout",
            wait_time = 1.0,
            duration = 1.0,
            extra_args = {steam_id = steam_id}
        })
        
        print("Warning phase started for: " .. steam_id)
    end
end

function on_warning_timeout(args)
    if not IS_HOST then
        return
    end
    
    local steam_id = args.extra_args.steam_id
    print("Warning timeout for: " .. steam_id)
    
    -- Check if player is still in warning state
    local player_hook_state = get_value("", steam_id, "hook_state")
    if player_hook_state == "WARNING" then
        -- Player missed the warning, show failure bubble and reset to ready
        show_world_space_result(steam_id, "", "😞 Missed")
        run_network_function(steam_id, "set_hook_state_ALL", {"READY"})
    end
end

function handle_warning_catch_HOST(sender_id)
    if not IS_HOST then
        return
    end
    
    print("Warning catch attempt by: " .. sender_id)
    
    -- Debug: Print all active searching players
    print("DEBUG: All active searching players:")
    for steam_id, data in pairs(active_searching_players) do
        print("  - " .. steam_id .. " -> " .. tostring(data.water_source))
    end
    
    -- Check if player is in warning state
    local player_hook_state = get_value("", sender_id, "hook_state")
    if player_hook_state == "WARNING" then
        -- Cancel warning timer
        stop_timer("warning_timer_" .. sender_id)
        
        -- Get water source from searching player data
        local water_source = "sea" -- Default fallback
        if active_searching_players[sender_id] then
            water_source = active_searching_players[sender_id].water_source
            print("DEBUG: Retrieved water_source for " .. sender_id .. ": " .. tostring(water_source))
        else
            print("DEBUG: No active searching data for " .. sender_id .. ", using default: " .. water_source)
            print("DEBUG: sender_id type: " .. type(sender_id) .. ", value: " .. tostring(sender_id))
        end
        
        -- Generate catch (fish or garbage)
        local catch = generate_random_fish(water_source)
        
        if catch.is_garbage then
            -- Direct garbage catch - no fishing game needed
            print("Garbage caught by: " .. sender_id)
            show_world_space_result(sender_id, catch.image, "😞 Garbage")
            run_network_function(sender_id, "set_hook_state_ALL", {"READY"})
        else
            -- Normal fish - start fishing game
            run_network_function(sender_id, "set_hook_state_ALL", {"FISHING"})
            
            -- Start fishing game with pre-generated fish
            start_fishing_for_player_with_fish(sender_id, catch)
            
            -- Notify fishing UI to start
            run_network_function("-fishing_game_ui", "start_fishing_CLIENT", {}, sender_id)
        end
        
        -- Remove from searching list after processing
        if active_searching_players[sender_id] then
            print("DEBUG: Removing " .. sender_id .. " from active_searching_players")
            active_searching_players[sender_id] = nil
        end
        
        print("Successfully caught warning for: " .. sender_id)
    else
        print("Warning catch denied: player not in WARNING state (current: " .. tostring(player_hook_state) .. ")")
    end
end



function start_fishing_for_player_with_fish(steam_id, pre_generated_fish)
    if not IS_HOST then
        return
    end
    print("start_fishing_for_player_with_fish: " .. steam_id)
    
    -- Get water source from searching player data
    local water_source = "sea" -- Default fallback
    if active_searching_players[steam_id] then
        water_source = active_searching_players[steam_id].water_source
    end
    
    -- Initialize or reset fishing state for this player
    active_fishing_players[steam_id] = {
        player_health = 100,
        fish_health = 0,
        max_fish_health = 0,
        current_fish = pre_generated_fish,
        water_source = water_source,
        -- New improved timer system
        current_light = "none",
        phase_timer = 0.0,
        max_phase_timer = 0.0,
        next_phase = "green",
        green_duration = 0.0,
        yellow_duration = 1.0, -- Always 1 second
        red_duration = 0.0,
        healing_timer = 0.0,
        healing_active = false
    }
    
    -- Use pre-generated fish and adjust health
    local fish = pre_generated_fish
    fish.health = math.floor(fish.health / 2) -- Start with half health
    
    active_fishing_players[steam_id].current_fish = fish
    active_fishing_players[steam_id].fish_health = fish.health
    active_fishing_players[steam_id].max_fish_health = fish.health * 2
    
    -- Send fish data to UI
    run_network_function("-fishing_game_ui", "start_fishing_game_CLIENT", {
        fish.name, fish.weight, fish.health, fish.health * 2, fish.image, fish.rarity, fish.water_source
    }, steam_id)
    
    -- Start green phase
    start_green_phase_for_player(steam_id)
end

--Only host should stop fishing
function stop_fishing_for_player(steam_id)
    if active_fishing_players[steam_id] then
        -- Remove player from active fishing
        active_fishing_players[steam_id] = nil
    end
    
    -- Also stop searching if player was searching
    stop_searching_for_player(steam_id)
end

function start_green_phase_for_player(steam_id)
    if not IS_HOST then
        return
    end
    
    local player_data = active_fishing_players[steam_id]
    if not player_data then
        return
    end
    
    print("Starting green phase for: " .. steam_id)
    
    player_data.current_light = "green"
    player_data.healing_active = false
    player_data.next_phase = "yellow"
    
    -- Generate random durations
    player_data.green_duration = math.random() * 2.5 + 2.0 -- 2s - 4.5s
    player_data.red_duration = math.random() * 2.5 + 2.0 -- 2s - 4.5s
    
    -- Set timer for green phase
    player_data.phase_timer = player_data.green_duration
    player_data.max_phase_timer = player_data.green_duration
    
    -- Send green phase to UI with correct total timer (green + yellow)
    local total_timer = player_data.green_duration + player_data.yellow_duration
    run_network_function("-fishing_game_ui", "update_fishing_phase_CLIENT", {
        "green", "ŞİMDİ ÇEK!", total_timer
    }, steam_id)
end

function start_yellow_phase_for_player(steam_id)
    if not IS_HOST then
        return
    end
    
    local player_data = active_fishing_players[steam_id]
    if not player_data then
        return
    end
    
    print("Starting yellow phase for: " .. steam_id)
    
    player_data.current_light = "yellow"
    player_data.next_phase = "red"
    
    -- Set timer for yellow phase (always 1 second)
    player_data.phase_timer = player_data.yellow_duration
    player_data.max_phase_timer = player_data.yellow_duration
    
    -- Send yellow phase to UI
    run_network_function("-fishing_game_ui", "update_fishing_phase_CLIENT", {
        "yellow", "DURMAK ÜZERE...", player_data.yellow_duration
    }, steam_id)
end

function start_red_phase_for_player(steam_id)
    if not IS_HOST then
        return
    end
    
    local player_data = active_fishing_players[steam_id]
    if not player_data then
        return
    end
    
    print("Starting red phase for: " .. steam_id)
    
    player_data.current_light = "red"
    player_data.healing_active = true
    player_data.healing_timer = 0.0
    player_data.next_phase = "green"
    
    -- Set timer for red phase
    player_data.phase_timer = player_data.red_duration
    player_data.max_phase_timer = player_data.red_duration
    
    -- Send red phase to UI
    run_network_function("-fishing_game_ui", "update_fishing_phase_CLIENT", {
        "red", "SAKIN ÇEKME!", player_data.red_duration
    }, steam_id)
end

function handle_fishing_click_HOST(sender_id)
    local player_data = active_fishing_players[sender_id]
    if not player_data then
        print("Fishing click denied: player not in active fishing state")
        return
    end
    
    -- Additional check: verify player is actually in FISHING state
    local player_hook_state = get_value("", sender_id, "hook_state")
    if player_hook_state ~= "FISHING" then
        print("Fishing click denied: player not in FISHING state (current: " .. tostring(player_hook_state) .. ")")
        return
    end

    local is_correct_click = (player_data.current_light == "green") or (player_data.current_light == "yellow")
    local is_incorrect_click = (player_data.current_light == "red")
    
    if is_correct_click then
        -- Deal damage to fish
        local damage = math.random(15) + 20 -- 20-35 damage
        player_data.fish_health = player_data.fish_health - damage
        if player_data.fish_health < 0 then
            player_data.fish_health = 0
        end
        

        -- Send update to UI
        run_network_function("-fishing_game_ui", "update_fishing_health_CLIENT", {
            player_data.player_health, player_data.fish_health, player_data.max_fish_health
        }, sender_id)
        
        -- Check if fish is caught
        if player_data.fish_health <= 0 then
            handle_fish_caught(sender_id)
        end
        
    elseif is_incorrect_click then
        -- Deal damage to player
        local damage = math.random(10) + 15 -- 15-25 damage
        player_data.player_health = player_data.player_health - damage
        

        -- Send damage feedback to UI
        run_network_function("-fishing_game_ui", "fishing_player_damage_CLIENT", {
            player_data.player_health, player_data.fish_health, player_data.max_fish_health
        }, sender_id)
        
        -- Check if player died
        if player_data.player_health <= 0 then
            handle_player_death(sender_id)
        end
    end
end

function handle_fish_caught(steam_id)
    local player_data = active_fishing_players[steam_id]
    if not player_data then
        return
    end
    
    print("Fish caught by: " .. steam_id)
    
    -- Get fish data
    local fish = player_data.current_fish
    
    -- Try to add fish to inventory first
    run_function("-inventory_manager", "add_fish_to_inventory", {steam_id, fish})

    -- Always show bubble effect with fish info regardless of inventory result
    local rarity_colors = {
        common = Color(0.7,0.7,0.7,1),
        rare = Color(0.2,0.6,1,1),
        epic = Color(0.8,0.2,0.8,1),
        legendary = Color(1.0,0.8,0,1),
        garbage = Color(0.5,0.5,0.5,1)
    }
    local fish_weight_pounds = math.floor(fish.weight * 2.20462 * 100) / 100
    local fish_text = fish.name .. "\n" .. fish.weight .. " kg / " .. fish_weight_pounds .. " lbs\nRarity: " .. fish.rarity
    show_world_space_result(steam_id, fish.image, fish_text, fish.weight, rarity_colors[fish.rarity])

    -- Reset player's hook system to READY state after success
    run_network_function(steam_id, "set_hook_state_ALL", {"READY"})
    
    -- Remove player from active fishing
    active_fishing_players[steam_id] = nil
end


function handle_player_death(steam_id)
    local player_data = active_fishing_players[steam_id]
    if not player_data then
        return
    end
    
    print("Player died: " .. steam_id)
    
    -- Show failure bubble effect
    show_world_space_result(steam_id, "", "😞 Escaped")

    -- Reset player's hook system to READY state
    run_network_function(steam_id, "set_hook_state_ALL", {"READY"})
    
    -- Remove player from active fishing
    active_fishing_players[steam_id] = nil
end

function show_world_space_result(steam_id, image_path, text, fish_weight, text_color)
    local player_position = get_value("", steam_id, "position")
    
    -- Create world space bubble entity
    local bubble_data = {
        t = "bubble_effect",
        p = Vector2(player_position.x, player_position.y - 50), -- Above player
        n = "bubble_" .. steam_id .. "_" .. math.random(1000, 9999),
        image_path = image_path or "",
        text = text or "",
        text_color = text_color,
        fish_weight = fish_weight or 1.0,
    }
    spawn_entity_host(bubble_data)
end

function _process(delta, inputs)
    if not IS_HOST then
        return inputs
    end
    
    -- Handle timers for all active fishing players
    for steam_id, player_data in pairs(active_fishing_players) do
        -- Update phase timer
        player_data.phase_timer = player_data.phase_timer - delta
        
        -- Send timer updates to UI every frame for smooth countdown
        run_network_function("-fishing_game_ui", "update_timer_CLIENT", {
            math.max(0, player_data.phase_timer)
        }, steam_id)
        
        -- Check if phase should change
        if player_data.phase_timer <= 0 then
            if player_data.next_phase == "yellow" then
                start_yellow_phase_for_player(steam_id)
            elseif player_data.next_phase == "red" then
                start_red_phase_for_player(steam_id)
            elseif player_data.next_phase == "green" then
                start_green_phase_for_player(steam_id)
            end
        end
        
        -- Handle healing during red phase
        if player_data.healing_active and player_data.current_light == "red" then
            player_data.healing_timer = player_data.healing_timer + delta
            
            if player_data.healing_timer >= healing_interval then
                player_data.healing_timer = 0.0
                
                -- Heal fish
                local heal_amount = (math.random() * 4 + 1) / 100 -- 1-5% heal
                player_data.fish_health = player_data.fish_health + (player_data.max_fish_health * heal_amount)
                
                if player_data.fish_health > player_data.max_fish_health then
                    player_data.fish_health = player_data.max_fish_health
                end
                
                -- If fish is at full health, damage player
                if player_data.fish_health >= player_data.max_fish_health then
                    local player_damage = math.random(4) + 1 -- 1-5 damage from max health (100)
                    player_data.player_health = player_data.player_health - player_damage
                    
                    if player_data.player_health < 0 then
                        player_data.player_health = 0
                    end
                    
                    -- Check if player died
                    if player_data.player_health <= 0 then
                        handle_player_death(steam_id)
                        -- Player is removed from table in handle_player_death, so continue to next iteration

                    end
                end
                
                -- Send health update to UI
                run_network_function("-fishing_game_ui", "update_fishing_health_CLIENT", {
                    player_data.player_health, player_data.fish_health, player_data.max_fish_health
                }, steam_id)
            end
        end
    end
    
    return inputs
end

function block_minigames(block)
    if not IS_HOST then return end
    fishing_blocked = block and true or false
end

function force_escape_all()
    if not IS_HOST then return end
    for steam_id, _ in pairs(active_fishing_players) do
        handle_player_death(steam_id)
    end
end
singleton_name = "wm"

-- wave_manager.lua
--
-- Global variables for wave management
current_wave = 0                  -- Current wave number (global for network)
base_wave_duration = 60           -- Base duration of a wave in seconds (1 minute)
wave_duration_increment = 5       -- Seconds to add to wave duration per wave
max_wave_duration = 120           -- Maximum wave duration (2 minutes)
wave_cooldown = 30                -- Seconds between waves
remaining_time = 0                -- Remaining time in current wave/cooldown (global for network)
wave_state = "inactive"           -- Current state: "inactive", "active", "cooldown"

-- Base monster spawn parameters (for our scaling calculations)
base_min_monsters = 2             -- Base minimum monsters per spawn
base_max_monsters = 5             -- Base maximum monsters per spawn
base_min_interval = 1             -- Base minimum spawn interval
base_max_interval = 3             -- Base maximum spawn interval

-- Count active players using entity tag system
function count_players()
    local player_entities = get_entity_names_by_tag("user")
    local count = #player_entities
    
    -- Ensure at least 1 player for calculations
    return math.max(1, count)
end

-- Update spawn parameters based on wave and player count
function update_spawn_parameters(wave_num, player_count)
    -- Scale parameters based on wave and player count
    local wave_scale = 1 + (wave_num - 1) * 0.1  -- 10% increase per wave
    local player_scale = math.sqrt(player_count)  -- Square root scaling for players
    local difficulty = wave_scale * player_scale
    
    -- Calculate new monster counts
    local new_min_monsters = math.max(2, math.floor(base_min_monsters * difficulty))
    local new_max_monsters = math.max(5, math.floor(base_max_monsters * difficulty))
    
    -- Calculate new spawn intervals (faster as waves progress)
    local interval_scale = math.max(0.2, 1 - (wave_num - 1) * 0.03)  -- 3% faster per wave, min 20%
    local new_min_interval = base_min_interval * interval_scale
    local new_max_interval = base_max_interval * interval_scale
    
    -- Update monster_generation parameters - updated to use "-mg"
    set_value("", "-mg", "min_monsters", new_min_monsters)
    set_value("", "-mg", "max_monsters", new_max_monsters)
    set_value("", "-mg", "min_interval", new_min_interval)
    set_value("", "-mg", "max_interval", new_max_interval)
    
    -- Play sound effect for wave start
    set_audio({
        stream_path = "monster-growl",
    })
    
    return {
        min_monsters = new_min_monsters,
        max_monsters = new_max_monsters,
        min_interval = new_min_interval,
        max_interval = new_max_interval
    }
end

-- Start a new wave
function start_wave()
    -- Increment wave counter
    current_wave = current_wave + 1
    set_wave_state("active")
    

    
    -- Update monster generation's current wave
    set_value("","-mg", "current_wave", current_wave)
    
    -- If this is the first wave, start stats tracking
    if current_wave == 1 and IS_HOST then
        run_function("-stats", "start_tracking", {})
    end
    
    -- Update wave number in stats tracker
    if IS_HOST then
        run_function("-stats", "update_wave_reached", {current_wave})
    end
    
    wave_duration = math.min(
        max_wave_duration, 
        base_wave_duration + (current_wave - 1) * wave_duration_increment
    )
    
    -- Set remaining time for the wave
    remaining_time = wave_duration
    
    -- Count players and update monster parameters
    local player_count = count_players()
    local params = update_spawn_parameters(current_wave, player_count)
    
    -- Check if we're entering a new level
    if current_wave % 7 == 1 then
        local level_data = run_function("-mg", "get_level_data", {current_wave})
        local color_hex = string.format("#%02x%02x%02x", 
            math.floor(level_data.color.r * 255),
            math.floor(level_data.color.g * 255),
            math.floor(level_data.color.b * 255)
        )
        add_to_chat(string.format("[color=%s]Monsters have evolved to %s level![/color]", color_hex, level_data.name), true)
    end
    
    -- Refill all players' health
    refill_all_players_health()
    
    set_value("","-mg","spawning_enabled",true)
    run_function("-mg","schedule_next_spawn")
    
    run_network_function(name, "sync_wave_state_CLIENT", {
        current_wave,
        wave_state,
        remaining_time,
        wave_duration
    })
    
    -- Update the _center_information label
    update_information_label()
    
    -- Schedule timer updates every second
    start_timer({
        entity_name = name,
        timer_id = "wave_timer_update",
        function_name = "update_wave_timer",
        wait_time = 1.0,
        duration = wave_duration
    })
    
    -- Announce wave start
    announce_wave_start(current_wave, wave_duration, params)
end

-- Update the wave timer every second
function update_wave_timer(args)
    if not wave_state == "active" then
        return
    end
    
    remaining_time = remaining_time - 1
    update_information_label()
    
    if args.is_last_iteration then
        end_wave()

        return
    end
end

-- Update the _center_information label with current wave and time info
function update_information_label()
    local label_text = "Game is not started yet"
    
    if wave_state == "active" then
        label_text = string.format("WAVE %d - %s remaining", current_wave, format_time(remaining_time))
    elseif wave_state == "cooldown" then
        label_text = string.format("Next Wave in %s", format_time(remaining_time))
    end
    
    set_label({
        parent_name = "",
        name = "_bottom_information",
        text = label_text,
		visible=true
    })
end

-- End the current wave
function end_wave()
    set_wave_state("cooldown")
    remaining_time = wave_cooldown
    
    -- Disable monster spawning - updated to use "-mg"
    set_value("", "-mg", "spawning_enabled", false)
    
    destroy_entities_by_tag("monster")
    -- Destroy all bullets
    destroy_entities_by_tag("bullet")
    run_function("-mg","monster_count_reset")
    -- Stop wave timer update
    stop_timer("wave_timer_update")
    
    -- Stop any pending monster spawn timers
    stop_timer("monster_spawn")
    
    -- Revive all dead players when wave ends
    revive_all_dead_players()
    


    run_network_function(name, "sync_wave_state_CLIENT", {
        current_wave,
        wave_state,
        remaining_time,
        wave_cooldown
    })

    
    -- Schedule cooldown timer updates
    start_timer({
        entity_name = name,
        timer_id = "cooldown_timer_update",
        function_name = "update_cooldown_timer",
        wait_time = 1.0,
        duration = wave_cooldown
    })
    
    -- Update information label
    update_information_label()
    
    -- Announce wave end and cooldown
    announce_wave_end(current_wave)
    announce_wave_cooldown(wave_cooldown)
    run_function("-sm","send_upgrade_panels")
end

-- Revive all dead players
function revive_all_dead_players()
    if IS_HOST then
        -- Get all user entities
        run_function_by_tag("dead","revive_player",{})
        
        add_to_chat("[color=#117733]All users have been automatically revived as the wave ended![/color]", true)

    end
end

-- Update the cooldown timer every second
function update_cooldown_timer(args)
    if wave_state == "active" then
        return
    end
    
    remaining_time = remaining_time - 1
    update_information_label()
    
    if args.is_last_iteration then
		start_wave()
        return
    end
end

function set_wave_state(state)
    wave_state = state

    -- Notify all clients about the wave state change
    run_network_function("-campfire", "set_wave_state_ALL", {state})
    
    
end

-- Function for the host to manually trigger the next wave
function wave_trigger()
    if wave_state == "inactive" then
        -- If no wave has started yet or we're waiting after cooldown
        start_wave()
    elseif wave_state == "cooldown" then
        -- If we're in the cooldown period, stop the cooldown and start the next wave
        stop_timer("cooldown_timer_update")
        start_wave()
    end
    -- If wave is active, do nothing
end

-- Player join/leave handlers - update parameters immediately when player count changes
function _on_user_connected(user_id, nickname)

    
    -- If a wave is active, update parameters based on new player count
    if wave_state == "active" then
        update_spawn_parameters(current_wave, count_players())
    end
end

function _on_user_disconnected(user_id, nickname)
    print("Player left: " .. nickname .. " (" .. user_id .. ")")
    
    -- If a wave is active, update parameters based on new player count
    if wave_state == "active" then
        update_spawn_parameters(current_wave, count_players())
    end
end

-- Announcement functions
function announce_wave_start(wave_num, duration, params)
    -- Get level data for this wave
    local level_data = run_function("-mg", "get_level_data", {wave_num})
    
    local msg = string.format(
        "WAVE %d HAS BEGUN! (%s Level) Duration: %d seconds\nMonsters: %d-%d, Spawn rate: %.1f-%.1f sec",
        wave_num,
        level_data.name,
        math.floor(duration),
        params.min_monsters,
        params.max_monsters,
        params.min_interval,
        params.max_interval
    )
    
    -- Convert color to hex for chat
    local color = level_data.color
    
    local hex_color = string.format("#%02x%02x%02x", 
        math.floor(color.r * 255), 
        math.floor(color.g * 255), 
        math.floor(color.b * 255))
    
    add_to_chat("[color="..hex_color.."]"..msg.."[/color]",true)
end

function announce_wave_end(wave_num)
    -- Get level data for this wave
    local level_data = run_function("-mg", "get_level_data", {wave_num})
    
    local msg = string.format("WAVE %d (%s Level) COMPLETE! Get ready for the next wave...", wave_num, level_data.name)
    
    -- Convert color to hex for chat
    local color = level_data.color
    local hex_color = string.format("#%02x%02x%02x", 
        math.floor(color.r * 255), 
        math.floor(color.g * 255), 
        math.floor(color.b * 255))
    
    add_to_chat("[color="..hex_color.."]"..msg.."[/color]",true)
    
    -- Play sound effect for wave end
    set_audio({
        stream_path = "monster-growl2",
        volume = -10
    })
end

function announce_wave_cooldown(cooldown)
    local msg = string.format("Next wave begins in %d seconds", math.floor(cooldown))
    add_to_chat("[color=#ddcc77]"..msg.."[/color]",true)
end

-- Calculate estimated difficulty percentage (30-minute target)
function get_difficulty_percentage()
    -- Based on a 30-minute target (approximately 20-24 waves)
    local max_expected_waves = 24
    return math.min(100, math.floor((current_wave / max_expected_waves) * 100))
end

-- Function to format time as MM:SS
function format_time(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining_seconds = seconds % 60
    return string.format("%02d:%02d", minutes, remaining_seconds)
end

-- Check if all players are dead and handle game over
function check_game_over()
    if not IS_HOST then
        return
    end
   

    local player_entities = get_entity_names_by_tag("user")
    local alive_players = get_entity_names_by_tag("alive")

    -- If there are players but none are alive, reset the game
    if #player_entities > 0 and #alive_players == 0 then
        -- Game over - reset everything
        game_over()
    end
end

-- Reset game state
function game_over()
    -- Reset player UI elements
    if IS_HOST == false then
        return
    end

    run_function("-sm", "reset_player_upgrade_rights")
    -- Stop stats tracking and show game over stats
    run_function("-stats", "stop_tracking", {})
    run_function("-stats", "show_game_over_stats", {})

    current_wave = 0
    remaining_time = 0
    set_wave_state("inactive")

    stop_timer("wave_timer_update")
    stop_timer("cooldown_timer_update")
    stop_timer("monster_spawn")-- starts in monster_generation 

    -- Destroy all entities
    destroy_entities_by_tag("monster")
    destroy_entities_by_tag("bullet")
    destroy_entities_by_tag("xp")

    -- Reset monster generation
    run_function("-mg", "monster_count_reset")
    set_value("", "-mg", "spawning_enabled", false)

    -- Reset all players
    local player_entities = get_entity_names_by_tag("user")
    for _, player_id in ipairs(player_entities) do
        -- Reset player stats and revive
        run_function(player_id, "reset_stats")
        run_network_function(player_id, "reset_player_ui_ALL", {})
    end

    -- Reset campfire state
    run_function("-campfire", "reset_campfire_state")

    -- Update UI
    update_information_label()
    add_to_chat("[color=#ddcc77]Game Over! All players have been revived and the game has been reset.[/color]", true)

    -- Sync game over state to all clients using existing sync function
    run_network_function(name, "sync_wave_state_CLIENT", {
        current_wave,
        wave_state,
        remaining_time,
        0  -- duration is 0 since game is over
    })
end

-- Function to handle client initialization
function _on_user_initialized(steam_id, nickname)
    if IS_HOST and steam_id ~= LOCAL_STEAM_ID then 
        -- Sync current wave state to the new client if its not the host
        run_network_function(name, "sync_wave_state_CLIENT", {
            current_wave,
            wave_state,
            remaining_time,
            wave_state == "active" and (base_wave_duration + (current_wave - 1) * wave_duration_increment) or wave_cooldown
        }, steam_id)
    end
end

-- Function to refill all players' health to max
function refill_all_players_health()
    if IS_HOST then
        -- Use the special "user" entity_name to run on all user entities
        run_network_function_by_tag("user", "refill_health_ALL", {})
    end
end

-- Network function to sync wave state to all clients
function sync_wave_state_CLIENT(sender_id, _current_wave, _wave_state, _remaining_time, _duration)
    print("sync_wave_state_CLIENT")
    current_wave = _current_wave
    wave_state = _wave_state
    remaining_time = _remaining_time
    
    -- Stop any existing timers
    stop_timer("wave_timer_update")
    stop_timer("cooldown_timer_update")
    
    -- Start appropriate timer based on state
    if _wave_state == "active" then
        start_timer({
            entity_name = name,
            timer_id = "wave_timer_update",
            function_name = "update_wave_timer",
            wait_time = 1.0,
            duration = _duration
        })
    elseif _wave_state == "cooldown" then
        start_timer({
            entity_name = name,
            timer_id = "cooldown_timer_update",
            function_name = "update_cooldown_timer",
            wait_time = 1.0,
            duration = _duration
        })
    end
    
    update_information_label()

end


update_information_label()
singleton_name = "cmd"

-- Register commands to the centralized system
add_command("-cmd", "handle_restart", "restart", "Restarts the game (Host only)", true)
add_command("-cmd", "handle_kill", "kill", "Kills your character", true)
add_command("-cmd", "show_monsters_info", "monsters", "Shows monster stats and mathematical formulas", true)
add_command("-cmd", "skip_music", "next", "Skips to the next music track", true)



-- Function to handle restart command
function handle_restart(sender_id)
    if not IS_HOST then
        -- If not host, show error message
        local message_config = {
            title = "Error",
            text = "Only the host can restart the game!",
            resizable = false,
        }
        create_panel(message_config)
        return
    end

    -- Reset game state
    run_function("-stats", "stop_tracking")
    run_function("-stats", "start_tracking")
    run_function("-sm", "reset_player_upgrade_rights")

    -- Reset wave system
    run_function("-wm", "reset_wave_system")

    -- Announce restart
    add_to_chat("[color=#117733]Game has been restarted by the host![/color]", true)
end

-- Function to handle kill command

function handle_kill(sender_id)
    if IS_HOST then
        -- If host, directly kill the player
        run_function(sender_id, "take_damage", { 1000000 })
    else
        -- If client, send kill request to host
        run_network_function("-cmd", "request_kill_HOST", {})
    end
end

-- Host function to handle kill requests from clients
function request_kill_HOST(sender_id)
    -- Kill the requesting player
    run_function(sender_id, "take_damage", { 1000000 })
end

-- Function to show monster stats and formulas
function show_monsters_info(sender_id)
    local monsters_text = "MONSTER STATS & FORMULAS:\n\n"


    -- Level names
    monsters_text = monsters_text .. "LEVEL NAMES:\n"
    monsters_text = monsters_text .. "1: Normal, 2: Enhanced, 3: Superior\n"
    monsters_text = monsters_text .. "4: Elite, 5: Legendary, 6: Mythic, 7+: Unstoppable\n\n"

    -- Wave level system
    monsters_text = monsters_text .. "WAVE LEVEL SYSTEM:\n"
    monsters_text = monsters_text .. "• Level increases every 7 waves by 1\n"
    monsters_text = monsters_text .. "• Level Index = (wave - 1) / 7 + 1\n\n"

    -- Base monster stats
    monsters_text = monsters_text .. "BASE MONSTER STATS:\n"
    monsters_text = monsters_text .. "• Ghost: 30 HP, 1.5 DMG, 50 Speed, 32 Size\n"
    monsters_text = monsters_text .. "• Wolf: 45 HP, 2.5 DMG, 70 Speed, 36 Size\n"
    monsters_text = monsters_text .. "• Bandit: 60 HP, 0.5 DMG, 0 Speed, 40 Size\n"
    monsters_text = monsters_text .. "• Zombie: 75 HP, 3.0 DMG, 30 Speed, 44 Size\n"
    monsters_text = monsters_text .. "• Cactus: 90 HP, 4.5 DMG, 25 Speed, 48 Size\n"
    monsters_text = monsters_text .. "• Snake: 35 HP, 2.0 DMG, 60 Speed, 34 Size\n\n"

    -- Enhanced stats formula
    monsters_text = monsters_text .. "STATS FORMULA OF MONSTERS:\n"
    monsters_text = monsters_text .. "• Health = Base Health × Level Index\n"
    monsters_text = monsters_text .. "• Damage = Base Damage × Level Index\n\n"

    -- Bandit bullet formula
    monsters_text = monsters_text .. "BANDIT BULLET DAMAGE:\n"
    monsters_text = monsters_text .. "• Bullet Damage = 10 × Level Index\n"

    -- Examples
    monsters_text = monsters_text .. "EXAMPLES:\n"
    monsters_text = monsters_text .. "Wave 2 (Level 1 Normal): Bandit has 60 HP, 0.5 DMG\n"
    monsters_text = monsters_text .. "• Bullet Damage = 10 × 1 = 10\n\n"
    monsters_text = monsters_text .. "Wave 8 (Level 2 Enhanced): Bandit has 120 HP, 1.0 DMG\n"
    monsters_text = monsters_text .. "• Bullet Damage = 10 × 2 = 20\n\n"
    monsters_text = monsters_text .. "Wave 15 (Level 3 Superior): Bandit has 180 HP, 1.5 DMG\n"
    monsters_text = monsters_text .. "• Bullet Damage = 10 × 3 = 30\n\n"


    -- Create a message panel
    local message_config = {
        title = "Monster Information",
        text = monsters_text,
        resizable = true,
    }
    create_panel(message_config)
end

-- Function to skip to next music track
function skip_music(sender_id)
    -- Call the world singleton's music skip function
    run_function("-w", "skip_to_next_music", {})
end

function _on_chat_message_received(sender_id, nickname, message)
    if message == "" then return "" end

    -- Handle *DEAD* prefix for pre-formatted message
    local is_dead = get_value("", sender_id, "is_dead")
    if is_dead then
        return "[color=#aa4499]*DEAD*[/color]" .. message
    end

    return nil -- No change, use the pre-formatted message
end

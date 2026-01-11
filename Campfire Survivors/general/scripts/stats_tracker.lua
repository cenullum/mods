singleton_name = "stats"

-- Global stats (shared by all players)
global_stats = {
    survival_time = 0,        -- In seconds
    wave_reached = 0,         -- Maximum wave reached
    total_enemies_killed = 0, -- Total enemy count killed across all players
    game_running = false      -- Whether the game is currently running
}

-- Player-specific stats (indexed by player ID)
player_stats = {}

-- Default stats for new players
default_player_stats = {
    enemies_killed = 0,     -- Number of enemies killed by player
    damage_taken = 0,       -- Total damage taken
    damage_regenerated = 0, -- Total HP regenerated
    damage_dealt = 0,       -- Total damage dealt to enemies
    bullets_dodged = 0,     -- Number of bullets dodged
    damage_prevented = 0,   -- Damage reduced by armor
    revives_performed = 0,  -- Number of revives performed
    times_downed = 0,       -- Number of times player was downed
    crystals_collected = 0, -- XP crystals collected
    lifesteal_amount = 0,   -- Amount of life stolen through lifesteal
    level_reached = 0,      -- Maximum level reached
    upgrade_levels = {}     -- Table of upgrade levels (populated later)
}





-- Called every second to update time-based stats
function update_stats_timer()
    if not global_stats.game_running then
        return
    end

    -- Increment survival time
    global_stats.survival_time = global_stats.survival_time + 1
end

if IS_HOST then
    -- Start the tracking timer that updates every second
    start_timer({
        entity_name = name,
        timer_id = "stats_tracker_timer",
        function_name = "update_stats_timer",
        wait_time = 1.0,
    })
end


-- Called by wave_manager when a new wave starts
function update_wave_reached(wave_number)
    if wave_number > global_stats.wave_reached then
        global_stats.wave_reached = wave_number
    end
end

-- Start tracking game stats when the game begins
function start_tracking()
    if IS_HOST then
        -- Reset global stats for new game
        global_stats.survival_time = 0
        global_stats.wave_reached = 0
        global_stats.total_enemies_killed = 0
        global_stats.game_running = true

        -- Reset player stats
        reset_all_player_stats()
    end
end

-- Stop tracking when game ends
function stop_tracking()
    if IS_HOST then
        global_stats.game_running = false
    end
end

-- Reset all player stats for a new game
function reset_all_player_stats()
    if not IS_HOST then return end

    player_stats = {}

    -- Initialize stats for all connected players
    local player_entities = get_entity_names_by_tag("user")
    for _, player_id in ipairs(player_entities) do
        initialize_player_stats(player_id)
    end
end

-- Initialize stats for a new player
function initialize_player_stats(player_id)
    if not player_stats[player_id] then
        player_stats[player_id] = table.deepcopy(default_player_stats)
    end
end

-- Deep copy helper function
function table.deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = table.deepcopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

-- Add to a player's stat
function add_player_stat(player_id, stat_name, amount)
    if not IS_HOST then return end

    -- Initialize player stats if needed
    if not player_stats[player_id] then
        initialize_player_stats(player_id)
    end

    -- Add to the stat if it exists
    if player_stats[player_id][stat_name] ~= nil then
        player_stats[player_id][stat_name] = player_stats[player_id][stat_name] + amount
    end

    -- Track total kills if this is an enemy kill
    if stat_name == "enemies_killed" then
        global_stats.total_enemies_killed = global_stats.total_enemies_killed + amount
    end
end

-- Set a player's stat to a specific value
function set_player_stat(player_id, stat_name, value)
    if not IS_HOST then return end

    -- Initialize player stats if needed
    if not player_stats[player_id] then
        initialize_player_stats(player_id)
    end

    -- Set the stat if it exists
    if player_stats[player_id][stat_name] ~= nil then
        player_stats[player_id][stat_name] = value
    end
end

-- Update player level reached
function update_player_level(player_id, level)
    local current_level = player_stats[player_id] and player_stats[player_id].level_reached or 0
    if level > current_level then
        set_player_stat(player_id, "level_reached", level)
    end
end

-- Update player upgrade levels
function update_player_upgrades(player_id, upgrade_id, level, is_weapon_upgrade)
    -- Initialize player stats if needed
    if not player_stats[player_id] then
        initialize_player_stats(player_id)
    end

    -- Initialize upgrade_levels if needed
    if not player_stats[player_id].upgrade_levels then
        player_stats[player_id].upgrade_levels = {}
    end

    -- Convert upgrade_id to integer
    local upgrade_id_int = math.floor(tonumber(upgrade_id))

    -- Create unique identifier for this upgrade type
    local prefix = is_weapon_upgrade and "weapon_" or "character_"
    local upgrade_key = prefix .. upgrade_id_int

    -- Update the level
    player_stats[player_id].upgrade_levels[upgrade_key] = level
end

-- Track upgrade level for a player
function track_upgrade_level(player_id, upgrade_id, is_weapon_upgrade)
    if not IS_HOST then return end

    -- Initialize player stats if needed
    if not player_stats[player_id] then
        initialize_player_stats(player_id)
    end

    -- Initialize upgrade_levels if needed
    if not player_stats[player_id].upgrade_levels then
        player_stats[player_id].upgrade_levels = {}
    end

    -- Convert upgrade_id to integer
    local upgrade_id_int = math.floor(tonumber(upgrade_id))

    -- Create unique identifier for this upgrade type
    local prefix = is_weapon_upgrade and "weapon_" or "character_"
    local upgrade_key = prefix .. upgrade_id_int

    -- Get current level
    local current_level = 1
    if player_stats[player_id].upgrade_levels[upgrade_key] then
        current_level = player_stats[player_id].upgrade_levels[upgrade_key] + 1
    end

    -- Update the level
    player_stats[player_id].upgrade_levels[upgrade_key] = current_level
end

-- Get all game stats to display to players
function get_all_stats()
    if not IS_HOST then return nil end

    local all_stats = {
        global = global_stats,
        players = {}
    }

    -- Collect player stats including nicknames
    for player_id, stats in pairs(player_stats) do
        local nickname = get_value("", player_id, "nickname") or player_id
        all_stats.players[player_id] = {
            nickname = nickname,
            stats = stats
        }
    end

    return all_stats
end

-- Format survival time as MM:SS
function format_time(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining_seconds = seconds % 60
    return string.format("%02d:%02d", minutes, remaining_seconds)
end

-- Function called when game over to show stats panel
function show_game_over_stats()
    if not IS_HOST then return end

    -- Get all stats
    local all_stats = get_all_stats()

    -- Send stats to all players to display
    run_network_function(name, "show_game_over_stats_ALL", { all_stats })
end

-- Client function to display stats panel
function show_game_over_stats_ALL(sender_id, all_stats)
    -- Create panel with global stats
    local global = all_stats.global
    local survival_time_formatted = format_time(global.survival_time)

    local panel_text = string.format(
        "GAME OVER\n\nSurvival Time: %s\nWave Reached: %d\nTotal Enemies Killed: %d",
        survival_time_formatted, global.wave_reached, global.total_enemies_killed
    )

    local panel_settings = {
        title = "Campfire Survivors - Game Statistics",
        text = panel_text,
        resizable = true,
        close = true,
        is_scrollable = true,
        minimum_size = Vector2(600, 500)
    }

    local panel_name = create_panel(panel_settings)

    -- Create table of player stats
    create_player_stats_table(panel_name, all_stats)
end

-- Create a table showing player stats
function create_player_stats_table(panel_name, all_stats)
    local table_data1 = {}
    local table_data2 = {}
    local row = 0

    -- Table 1 Header (Blue Theme)
    local header_color1 = Color(0.2, 0.2, 0.5, 0.9)
    table_data1[vector2_to_string(Vector2(0, row))] = { text = "Nickname", color = header_color1 }
    table_data1[vector2_to_string(Vector2(1, row))] = { text = "Level", color = header_color1 }
    table_data1[vector2_to_string(Vector2(2, row))] = { text = "Kills", color = header_color1 }
    table_data1[vector2_to_string(Vector2(3, row))] = { text = "Revives", color = header_color1 }
    table_data1[vector2_to_string(Vector2(4, row))] = { text = "Downed", color = header_color1 }
    table_data1[vector2_to_string(Vector2(5, row))] = { text = "Crystals", color = header_color1 }
    table_data1[vector2_to_string(Vector2(6, row))] = { text = "Dodges", color = header_color1 }

    -- Table 2 Header (Green Theme)
    local header_color2 = Color(0.2, 0.5, 0.2, 0.9)
    table_data2[vector2_to_string(Vector2(0, row))] = { text = "Nickname", color = header_color2 }
    table_data2[vector2_to_string(Vector2(1, row))] = { text = "DMG Dealt", color = header_color2 }
    table_data2[vector2_to_string(Vector2(2, row))] = { text = "DMG Taken", color = header_color2 }
    table_data2[vector2_to_string(Vector2(3, row))] = { text = "Regeneration", color = header_color2 }
    table_data2[vector2_to_string(Vector2(4, row))] = { text = "Lifesteal", color = header_color2 }
    table_data2[vector2_to_string(Vector2(5, row))] = { text = "Blocked DMG", color = header_color2 }

    row = row + 1

    -- Player rows
    for player_id, player_data in pairs(all_stats.players) do
        local nickname = player_data.nickname
        local stats = player_data.stats

        local cell_color1 = Color(0.3, 0.3, 0.6, 0.8)
        local cell_color2 = Color(0.3, 0.6, 0.3, 0.8)

        -- Table 1 Cells
        table_data1[vector2_to_string(Vector2(0, row))] = { text = nickname, color = cell_color1 }
        table_data1[vector2_to_string(Vector2(1, row))] = { text = tostring(math.floor(stats.level_reached)), color =
        cell_color1 }
        table_data1[vector2_to_string(Vector2(2, row))] = { text = tostring(math.floor(stats.enemies_killed)), color =
        cell_color1 }
        table_data1[vector2_to_string(Vector2(3, row))] = { text = tostring(math.floor(stats.revives_performed)), color =
        cell_color1 }
        table_data1[vector2_to_string(Vector2(4, row))] = { text = tostring(math.floor(stats.times_downed)), color =
        cell_color1 }
        table_data1[vector2_to_string(Vector2(5, row))] = { text = tostring(math.floor(stats.crystals_collected)), color =
        cell_color1 }
        table_data1[vector2_to_string(Vector2(6, row))] = { text = tostring(math.floor(stats.bullets_dodged)), color =
        cell_color1 }

        -- Table 2 Cells
        table_data2[vector2_to_string(Vector2(0, row))] = { text = nickname, color = cell_color2 }
        table_data2[vector2_to_string(Vector2(1, row))] = { text = tostring(math.floor(stats.damage_dealt)), color =
        cell_color2 }
        table_data2[vector2_to_string(Vector2(2, row))] = { text = tostring(math.floor(stats.damage_taken)), color =
        cell_color2 }
        table_data2[vector2_to_string(Vector2(3, row))] = { text = tostring(math.floor(stats.damage_regenerated)), color =
        cell_color2 }
        table_data2[vector2_to_string(Vector2(4, row))] = { text = tostring(math.floor(stats.lifesteal_amount)), color =
        cell_color2 }
        table_data2[vector2_to_string(Vector2(5, row))] = { text = tostring(math.floor(stats.damage_prevented)), color =
        cell_color2 }

        row = row + 1
    end

    -- Create a separate table for upgrade levels
    local table_data3 = {}
    row = 0

    -- Header row
    table_data3[vector2_to_string(Vector2(0, row))] = { text = "Player", color = Color(0.5, 0.2, 0.5, 0.9) }
    table_data3[vector2_to_string(Vector2(1, row))] = { text = "Upgrades", color = Color(0.5, 0.2, 0.5, 0.9) }
    row = row + 1

    -- Player rows with concatenated upgrade information
    for player_id, player_data in pairs(all_stats.players) do
        local nickname = player_data.nickname
        local stats = player_data.stats

        -- Collect upgrade information
        local upgrade_text = ""
        if stats.upgrade_levels then
            -- Map for character upgrade names
            local character_upgrade_names = {
                [1] = "Speed",
                [2] = "Health",
                [3] = "Armor",
                [4] = "Pickup Range",
                [5] = "XP Gain",
                [6] = "Regeneration",
                [7] = "Dodge"
            }

            -- Map for weapon upgrade names
            local weapon_upgrade_names = {
                [1] = "Atk Speed",
                [2] = "Proj Size",
                [3] = "Proj Count",
                [4] = "Proj Speed",
                [5] = "Penetration",
                [6] = "Lifesteal",
                [7] = "Knockback",
                [8] = "Damage"
            }

            -- Character upgrades
            for id, name in pairs(character_upgrade_names) do
                local key = "character_" .. id
                local level = math.floor(stats.upgrade_levels[key] or 0)

                if level > 0 then
                    upgrade_text = upgrade_text .. name .. " Lv" .. level .. ", "
                end
            end

            -- Weapon upgrades
            for id, name in pairs(weapon_upgrade_names) do
                local key = "weapon_" .. id
                local level = math.floor(stats.upgrade_levels[key] or 0)

                if level > 0 then
                    upgrade_text = upgrade_text .. name .. " Lv" .. level .. ", "
                end
            end

            -- Remove trailing comma and space if there are upgrades
            if #upgrade_text > 0 then
                upgrade_text = upgrade_text:sub(1, -3)
            end
        end

        -- If no upgrades were found, show "No upgrades"
        if #upgrade_text == 0 then
            upgrade_text = "No upgrades"
        end

        -- Player name cell
        table_data3[vector2_to_string(Vector2(0, row))] = { text = nickname, color = Color(0.6, 0.3, 0.6, 0.8) }

        -- Upgrades cell
        table_data3[vector2_to_string(Vector2(1, row))] = { text = upgrade_text, color = Color(0.6, 0.3, 0.6, 0.8) }

        row = row + 1
    end

    -- Set the tables in the panel
    set_table(panel_name, {
        name = "stats_table1",
        table_data = table_data1
    })

    set_table(panel_name, {
        name = "stats_table2",
        table_data = table_data2
    })

    -- Add the upgrades table
    set_table(panel_name, {
        name = "stats_table3",
        table_data = table_data3
    })
end

-- Player connection/disconnection handlers
function _on_user_connected(user_id, nickname)
    add_to_chat("[color=#117733]" .. nickname .. "[/color][color=#0f6622] connected[/color]")
    if IS_HOST then
        initialize_player_stats(user_id)
    end
end

function _on_user_disconnected(user_id, nickname)
    add_to_chat("[color=#cc6677]" .. nickname .. "[/color][color=#aa5566] disconnected[/color]")
    if IS_HOST then
        -- Player stats remain in memory until game reset
    end
end

-- Get player stats
function get_player_stats(player_id)
    if not IS_HOST then return nil end

    -- Initialize player stats if needed
    if not player_stats[player_id] then
        initialize_player_stats(player_id)
    end

    return player_stats[player_id]
end

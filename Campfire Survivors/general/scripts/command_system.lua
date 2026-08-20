singleton_name = "cmd"

-- Register commands to the centralized system
add_command("-cmd", "handle_restart", "restart", "{restarts_the_game_host_only}", true)
add_command("-cmd", "handle_kill", "kill", "{kills_your_character}", true)
add_command("-cmd", "show_monsters_info", "monsters", "{shows_monster_stats_and_mathematical_for}", true)
add_command("-cmd", "skip_music", "next", "{skips_to_the_next_music_track}", true)
add_command("-cmd", "handle_testboss", "testboss", "{cmd_testboss_desc}", true)



-- Function to handle restart command
function handle_restart(sender_id)
    if not IS_HOST then
        -- If not host, show error message
        local message_config = {
            title ="{error}",
            text ="{only_the_host_can_restart_the_game}",
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
    add_to_chat("{game_has_been_restarted_by_the_host}", true)
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
    local monsters_text ="{monster_stats_formulas}"


    -- Level names
    monsters_text = monsters_text .. "{level_names}"
    monsters_text = monsters_text .. "{level_names_1_3}"
    monsters_text = monsters_text .. "{level_names_4_7}"

    -- Wave level system
    monsters_text = monsters_text .. "{wave_level_system}"
    monsters_text = monsters_text .. "{level_increases_every_7_waves_by_1}"
    monsters_text = monsters_text .. "{level_index_wave_1_7_1}"

    -- Base monster stats
    monsters_text = monsters_text .. "{base_monster_stats}"
    monsters_text = monsters_text .. "{ghost_30_hp_1_5_dmg_50_speed_32_size}"
    monsters_text = monsters_text .. "{wolf_45_hp_2_5_dmg_70_speed_36_size}"
    monsters_text = monsters_text .. "{bandit_60_hp_0_5_dmg_0_speed_40_size}"
    monsters_text = monsters_text .. "{zombie_75_hp_3_0_dmg_30_speed_44_size}"
    monsters_text = monsters_text .. "{cactus_90_hp_4_5_dmg_25_speed_48_size}"
    monsters_text = monsters_text .. "{snake_35_hp_2_0_dmg_60_speed_34_size}"

    -- Enhanced stats formula
    monsters_text = monsters_text .. "{stats_formula_of_monsters}"
    monsters_text = monsters_text .. "{health_base_health_level_index}"
    monsters_text = monsters_text .. "{damage_base_damage_level_index}"

    -- Bandit bullet formula
    monsters_text = monsters_text .. "{bandit_bullet_damage}"
    monsters_text = monsters_text .. "{bullet_damage_10_level_index}"

    -- Examples
    monsters_text = monsters_text .. "EXAMPLES:\n"
    monsters_text = monsters_text .. "{wave_2_level_1_normal_bandit_has_60_hp_0}"
    monsters_text = monsters_text .. "{bullet_damage_10_1_10}"
    monsters_text = monsters_text .. "{wave_8_level_2_enhanced_bandit_has_120_h}"
    monsters_text = monsters_text .. "{bullet_damage_10_2_20}"
    monsters_text = monsters_text .. "{wave_15_level_3_superior_bandit_has_180}"
    monsters_text = monsters_text .. "{bullet_damage_10_3_30}"


    -- Create a message panel
    local message_config = {
        title ="{monster_information}",
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

-- Testing shortcut: spawn the boss immediately instead of waiting BOSS_TIME
-- out. Host only, same as restart/kill validation.
function handle_testboss(sender_id)
    if not IS_HOST then
        add_to_chat("{only_the_host_can_test_the_boss}", false)
        return
    end
    run_function("-bm", "force_spawn_boss")
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

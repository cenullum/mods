singleton_name = "cmd"

-- Register commands to the centralized system
add_command("-cmd", "show_fishing_help", "fishing", "{shows_fishing_game_controls_and_tips}", true)
add_command("-cmd", "teleport_to_spawn_point", "spawn_point", "{teleport_to_spawn_point_and_reset_positi}",
    true)
add_command("-cmd", "change_spawn_point", "change_spawn_point",
    "{cmd_change_spawn_point_desc}", true)



-- Function to show fishing game help
function show_fishing_help()
    local fishing_text ="{fishing_game_controls}"

    fishing_text = fishing_text .. "{hook_controls}"
    fishing_text = fishing_text .. "{hold_to_charge_hook_power}"
    fishing_text = fishing_text .. "{release_to_fire_hook}"
    fishing_text = fishing_text .. "{press_while_hooked_to_launch_yourself}"
    fishing_text = fishing_text .. "{press_during_firing_to_cancel}"

    fishing_text = fishing_text .. "{fishing_mechanics}"
    fishing_text = fishing_text .. "{hook_onto_fish_to_start_fishing_minigame}"
    fishing_text = fishing_text .. "{follow_the_traffic_light_signals}"
    fishing_text = fishing_text .. "{green_reel_in_red_stop}"
    fishing_text = fishing_text .. "{manage_your_health_vs_fish_health}"

    fishing_text = fishing_text .. "TIPS:\n"
    fishing_text = fishing_text .. "{different_fish_have_different_difficulti}"
    fishing_text = fishing_text .. "{watch_your_hook_power_higher_power_furth}"
    fishing_text = fishing_text .. "{use_platforms_to_get_better_fishing_posi}"
    fishing_text = fishing_text .. "{some_areas_have_better_fish_than_others}"

    local message_config = {
        title ="{fishing_game_help}",
        text = fishing_text,
        resizable = true,

    }
    create_panel(message_config)
end



-- Command Wrapper functions
-- These are called locally by add_command and they trigger network functions

function teleport_to_spawn_point()
    run_network_function("-cmd", "teleport_to_spawn_point_HOST", {})
end

function change_spawn_point(x, y)
    run_network_function("-cmd", "change_spawn_point_ALL", { x, y })
end



-- HOST function: Handle teleport to spawn point request
function teleport_to_spawn_point_HOST(sender_id)
    local spawn_position = get_value("", "-spawn_point", "position")

    change_instantly({
        entity_name = sender_id,
        angular_velocity = 0.0,
        position = spawn_position,
        linear_velocity = Vector2(0, 0),
        rotation = 0.0
    })
end

function change_spawn_point_ALL(sender_id, x, y)
    -- Validate parameters
    if not x or not y then
        add_to_chat("{error_missing_parameters_usage_change_sp}", false)
        return
    end

    -- Convert to numbers and validate
    local pos_x = tonumber(x)
    local pos_y = tonumber(y)

    if not pos_x or not pos_y then
        add_to_chat("{error_invalid_parameters_x_and_y_must_be}", false)
        return
    end

    -- Check for reasonable bounds (optional safety check)
    if pos_x < -10000 or pos_x > 10000 or pos_y < -10000 or pos_y > 10000 then
        add_to_chat("{error_position_values_too_extreme_use_va}",
            false)
        return
    end

    -- Update spawn point position
    local new_position = Vector2(pos_x, pos_y)
    set_value("", "-spawn_point", "position", new_position)

    -- Confirm the change
    add_to_chat("{spawn_point_updated_to_position}" .. pos_x .. ", " .. pos_y .. ")[/b][/color]", true)
end

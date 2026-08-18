singleton_name = "user_action_panel"

function view_steam_profile(args)
    open_profile(args.extra_args.steam_id)
end

function move_to_red_team(args)
    _steam_id = args.extra_args.steam_id
    run_function("-ui_manager", "move_team", { _steam_id, 1 })
    run_network_function(_steam_id, "change_team_ALL", { 1 }) -- Character itself
    set_voice_channel({
        steam_id = _steam_id,
        channel_name = "team_red",
        parent_name = _steam_id,
        icon_offset = Vector2(0, -30)
    })
end

function move_to_blue_team(args)
    _steam_id = args.extra_args.steam_id
    run_function("-ui_manager", "move_team", { _steam_id, 2 })
    run_network_function(_steam_id, "change_team_ALL", { 2 }) -- Character itself
    set_voice_channel({
        steam_id = _steam_id,
        channel_name = "team_blue",
        parent_name = _steam_id,
        icon_offset = Vector2(0, -30)
    })
end

function move_to_spectator(args)
    _steam_id = args.extra_args.steam_id
    run_function("-ui_manager", "move_team", { _steam_id, 0 })
    run_network_function(_steam_id, "change_team_ALL", { 0 }) -- Character itself
    set_voice_channel({
        steam_id = _steam_id,
        channel_name = "spectators"
    })
end

-- Bot rows in the score table open this panel instead: a bot has no Steam
-- profile, and its team/removal go through -bot_manager (which owns the roster).
function move_bot_to_red_team(args)
    run_function("-bot_manager", "set_bot_team", { args.extra_args.steam_id, 1 })
end

function move_bot_to_blue_team(args)
    run_function("-bot_manager", "set_bot_team", { args.extra_args.steam_id, 2 })
end

function set_bot_type_both(args)
    run_function("-bot_manager", "set_bot_type", { args.extra_args.steam_id, 0 })
end

function set_bot_type_keeper(args)
    run_function("-bot_manager", "set_bot_type", { args.extra_args.steam_id, 1 })
end

function set_bot_type_field(args)
    run_function("-bot_manager", "set_bot_type", { args.extra_args.steam_id, 2 })
end

function kick_bot(args)
    run_function("-bot_manager", "remove_bot", { args.extra_args.steam_id })
    close_panel(args.panel_name)
end

function show_bot_actions(bot_name, bot_label)
    if not IS_HOST then return end
    local panel_name = create_panel({
        text = "{user_actions}" .. bot_label,
        title = "{bot_management}",
        resizable = false,
        name = "football_player_action_id",
        no_multiple_tag = "football_player_action",
        minimum_size = Vector2(450, 420)
    })

    local buttons = {
        { "{move_to_red_team}", "#CC0000", "move_bot_to_red_team" },
        { "{move_to_blue_team}", "#0066CC", "move_bot_to_blue_team" },
        { "{bot_type_both}", "#4B8BF4", "set_bot_type_both" },
        { "{bot_type_gk}", "#4B8BF4", "set_bot_type_keeper" },
        { "{bot_type_field}", "#4B8BF4", "set_bot_type_field" },
        { "{remove_bot}", "#AA2222", "kick_bot" },
    }
    for i = 1, #buttons do
        add_button_to_panel(panel_name, {
            text = buttons[i][1],
            is_vertical = true,
            color = buttons[i][2],
            entity_name = name,
            function_name = buttons[i][3],
            extra_args = { steam_id = bot_name }
        })
    end
end

function show_user_actions(steam_id, user_name, is_bot)
    if is_bot == true then
        show_bot_actions(steam_id, user_name)
        return
    end

    local settings = {
        text ="{user_actions}" .. user_name,
        title ="{user_actions_2}",
        resizable = false,
        name = "football_player_action_id",
        no_multiple_tag = "football_player_action"
    }

    local panel_name = create_panel(settings)

    -- View Steam Profile button for all users
    add_button_to_panel(panel_name, {
        text ="{view_steam_profile}",
        is_vertical = true,
        color = "#4B8BF4",
        entity_name = name,
        function_name = "view_steam_profile",
        extra_args = { steam_id = steam_id }
    })

    -- Host-only controls
    if IS_HOST then
        -- Move to Red Team
        add_button_to_panel(panel_name, {
            text ="{move_to_red_team}",
            is_vertical = true,
            color = "#CC0000",
            entity_name = name,
            function_name = "move_to_red_team",
            extra_args = { steam_id = steam_id }
        })

        -- Move to Blue Team
        add_button_to_panel(panel_name, {
            text ="{move_to_blue_team}",
            is_vertical = true,
            color = "#0066CC",
            entity_name = name,
            function_name = "move_to_blue_team",
            extra_args = { steam_id = steam_id }
        })

        add_button_to_panel(panel_name, {
            text ="{move_to_spectator}",
            is_vertical = true,
            color = "#FFFFFF",
            entity_name = name,
            function_name = "move_to_spectator",
            extra_args = { steam_id = steam_id }
        })
    end
end


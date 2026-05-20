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

function show_user_actions(steam_id, user_name)
    local settings = {
        text = "User Actions - " .. user_name,
        title = "User Actions",
        resizable = false,
        name = "football_player_action_id",
        no_multiple_tag = "football_player_action"
    }

    local panel_name = create_panel(settings)

    -- View Steam Profile button for all users
    add_button_to_panel(panel_name, {
        text = "View Steam Profile",
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
            text = "Move to Red Team",
            is_vertical = true,
            color = "#CC0000",
            entity_name = name,
            function_name = "move_to_red_team",
            extra_args = { steam_id = steam_id }
        })

        -- Move to Blue Team
        add_button_to_panel(panel_name, {
            text = "Move to Blue Team",
            is_vertical = true,
            color = "#0066CC",
            entity_name = name,
            function_name = "move_to_blue_team",
            extra_args = { steam_id = steam_id }
        })

        add_button_to_panel(panel_name, {
            text = "Move to Spectator",
            is_vertical = true,
            color = "#FFFFFF",
            entity_name = name,
            function_name = "move_to_spectator",
            extra_args = { steam_id = steam_id }
        })
    end
end


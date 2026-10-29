singleton_name = "user_action_panel"

function view_steam_profile(args)
    open_profile(args.extra_args.steam_id)
end

-- Admin moves go through the host (-team_balancer checks is_admin), so a
-- dedicated server's owner can use them from their own machine. The voice
-- channel follows in user.lua's change_team_ALL on the host.
function move_to_red_team(args)
    run_network_function("-team_balancer", "admin_set_team_HOST", { args.extra_args.steam_id, 1 })
    close_panel(args.panel_name)
end

function move_to_blue_team(args)
    run_network_function("-team_balancer", "admin_set_team_HOST", { args.extra_args.steam_id, 2 })
    close_panel(args.panel_name)
end

function move_to_spectator(args)
    run_network_function("-team_balancer", "admin_set_team_HOST", { args.extra_args.steam_id, 0 })
    close_panel(args.panel_name)
end

-- A player's own row: switch team or watch. The host decides whether the switch
-- is fair (see team_balancer.lua).
function join_red_team(args)
    run_network_function("-team_balancer", "request_team_HOST", { 1, false })
    close_panel(args.panel_name)
end

function join_blue_team(args)
    run_network_function("-team_balancer", "request_team_HOST", { 2, false })
    close_panel(args.panel_name)
end

function join_spectators(args)
    run_network_function("-team_balancer", "request_team_HOST", { 0, false })
    close_panel(args.panel_name)
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
        { "{move_to_red_team}", "#E07010", "move_bot_to_red_team" },
        { "{move_to_blue_team}", "#7A3FE0", "move_bot_to_blue_team" },
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

    -- An admin's own row uses the admin moves below (no fairness check, the
    -- admin decides); everyone else asks the host.
    if steam_id == LOCAL_STEAM_ID and not is_admin(LOCAL_STEAM_ID) then
        local own = {
            { "{join_red_team}", "#E07010", "join_red_team" },
            { "{join_blue_team}", "#7A3FE0", "join_blue_team" },
            { "{watch_as_spectator}", "#FFFFFF", "join_spectators" },
        }
        for i = 1, #own do
            add_button_to_panel(panel_name, {
                text = own[i][1],
                is_vertical = true,
                color = own[i][2],
                entity_name = name,
                function_name = own[i][3],
            })
        end
    end

    -- Admin controls (the host, or a dedicated server's owner)
    if is_admin(LOCAL_STEAM_ID) then
        -- Move to Red Team
        add_button_to_panel(panel_name, {
            text ="{move_to_red_team}",
            is_vertical = true,
            color = "#E07010",
            entity_name = name,
            function_name = "move_to_red_team",
            extra_args = { steam_id = steam_id }
        })

        -- Move to Blue Team
        add_button_to_panel(panel_name, {
            text ="{move_to_blue_team}",
            is_vertical = true,
            color = "#7A3FE0",
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


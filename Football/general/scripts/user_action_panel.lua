singleton_name = "user_action_panel"

-- Store temporary kick/ban data
local temp_data = {}

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
        proximity_length = 256.0,
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
        proximity_length = 256.0,
        icon_offset = Vector2(0, -30)
    })
end

function move_to_spectator(args)
    run_function("-ui_manager", "move_team", { _steam_id, 0 })
    run_network_function(_steam_id, "change_team_ALL", { 0 }) -- Character itself
    remove_voice_channel(_steam_id)
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

        -- Kick and Ban buttons only for non-host users
        if steam_id ~= HOST_STEAM_ID then
            add_button_to_panel(panel_name, {
                text = "Kick User",
                is_vertical = true,
                color = "#FF6B6B",
                entity_name = name,
                function_name = "show_kick_panel",
                extra_args = { steam_id = steam_id, nickname = user_name }
            })

            add_button_to_panel(panel_name, {
                text = "Ban User",
                is_vertical = true,
                color = "#FF0000",
                entity_name = name,
                function_name = "show_ban_panel",
                extra_args = { steam_id = steam_id, nickname = user_name }
            })
        end
    end
end

-- Convert duration string to seconds
function get_duration_seconds(duration_str)
    if duration_str == "1 Hour" then
        return 3600
    elseif duration_str == "6 Hours" then
        return 3600 * 6
    elseif duration_str == "12 Hours" then
        return 3600 * 12
    elseif duration_str == "1 Day" then
        return 3600 * 24
    elseif duration_str == "1 Week" then
        return 3600 * 24 * 7
    elseif duration_str == "1 Month" then
        return 3600 * 24 * 30
    elseif duration_str == "Permanent" then
        return 3600 * 24 * 365 * 100                                     -- 100 years
    else
        return 3600                                                      -- default 1 hour
    end
end

-- Show kick confirmation panel
function show_kick_panel(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname

    temp_data[steam_id] = temp_data[steam_id] or {}
    temp_data[steam_id].kick_reason = "No reason provided"
    close_panel(args.panel_name)

    local settings = {
        text = "Kick " .. nickname,
        title = "Kick User",
        resizable = false,
        name = "football_kick_panel_id",
        no_multiple_tag = "football_kick_panel"
    }

    local panel_name = create_panel(settings)

    -- Reason input
    add_input_to_panel(panel_name, {
        text = "Reason",
        default_value = "",
        entity_name = name,
        function_name = "on_kick_reason_changed",
        extra_args = { steam_id = steam_id }
    })

    -- Kick button
    add_button_to_panel(panel_name, {
        text = "Kick User",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = "execute_kick",
        extra_args = { steam_id = steam_id, nickname = nickname }
    })
end

function on_kick_reason_changed(args)
    local steam_id = args.extra_args.steam_id
    temp_data[steam_id].kick_reason = args.Reason
end

function execute_kick(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname
    local reason = "No reason provided"
    if temp_data[steam_id] and temp_data[steam_id].kick_reason then
        reason = temp_data[steam_id].kick_reason
    end
    create_sure_panel(
        "Are you sure you want to kick " .. nickname .. "?\nReason: " .. reason,
        "confirm_kick",
        "cancel_moderation"
    )

    -- Store data for confirmation
    temp_data[steam_id].pending_action = {
        type = "kick",
        reason = reason
    }

    close_panel(args.panel_name)
end

function confirm_kick(args)
    for steam_id, data in pairs(temp_data) do
        if data.pending_action and data.pending_action.type == "kick" then
            kick_user(steam_id, data.pending_action.reason)
            temp_data[steam_id] = nil
            break
        end
    end
    close_panel(args.panel_name)
end

-- Show ban panel with duration options
function show_ban_panel(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname


    temp_data[steam_id] = temp_data[steam_id] or {}
    temp_data[steam_id].ban_reason = "No reason provided"
    temp_data[steam_id].ban_duration = "1 Hour" -- Default duration

    close_panel(args.panel_name)

    local settings = {
        text = "Ban " .. nickname,
        title = "Ban User",
        resizable = false,
        name = "football_ban_panel_id",
        no_multiple_tag = "football_ban_panel"
    }

    local panel_name = create_panel(settings)

    -- Duration options
    add_optionbox_to_panel(panel_name, {
        text = "Duration",
        options = { "1 Hour", "6 Hours", "12 Hours", "1 Day", "1 Week", "1 Month", "Permanent" },
        entity_name = name,
        function_name = "on_ban_duration_changed",
        extra_args = { steam_id = steam_id }
    })

    -- Reason input
    add_input_to_panel(panel_name, {
        text = "Reason",
        default_value = "",
        entity_name = name,
        function_name = "on_ban_reason_changed",
        extra_args = { steam_id = steam_id }
    })

    -- Ban button
    add_button_to_panel(panel_name, {
        text = "Ban User",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = "execute_ban",
        extra_args = { steam_id = steam_id, nickname = nickname }
    })
end

function on_ban_reason_changed(args)
    local steam_id = args.extra_args.steam_id
    temp_data[steam_id].ban_reason = args.Reason
end

function on_ban_duration_changed(args)
    local steam_id = args.extra_args.steam_id
    temp_data[steam_id].ban_duration = args.Duration
end

function execute_ban(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname

    if not temp_data[steam_id] then return end

    local duration_text = temp_data[steam_id].ban_duration or "1 Hour"
    local reason = temp_data[steam_id].ban_reason or "No reason provided"

    -- Convert duration text to seconds
    local duration_seconds = get_duration_seconds(duration_text)
    create_sure_panel(
        "Are you sure you want to ban " .. nickname .. "?\nDuration: " .. duration_text .. "\nReason: " .. reason,
        "confirm_ban",
        "cancel_moderation"
    )

    -- Store data for confirmation
    temp_data[steam_id].pending_action = {
        type = "ban",
        duration = duration_seconds, -- Store the duration in seconds
        reason = reason
    }

    close_panel(args.panel_name)
end

function confirm_ban(args)
    for steam_id, data in pairs(temp_data) do
        if data.pending_action and data.pending_action.type == "ban" then
            local duration = data.pending_action.duration
            local reason = data.pending_action.reason

            if not duration then
                duration = get_duration_seconds("1 Hour")
            end
            if not reason then reason = "No reason provided" end

            ban_user(steam_id, duration, reason)

            temp_data[steam_id] = nil
            break
        end
    end
    close_panel(args.panel_name)
end

function cancel_moderation(args)
    for steam_id, data in pairs(temp_data) do
        if data.pending_action then
            temp_data[steam_id] = nil
            break
        end
    end
    close_panel(args.panel_name)
end

-- Helper function to create a confirmation panel in Lua
-- message: Text to show in panel
-- ok_function: Function name to call when OK is pressed
-- cancel_function: Function name to call when Cancel is pressed
function create_sure_panel(message, ok_function, cancel_function)
    local settings = {
        text = message,
        title = "Are you sure?",
        resizable = false,
        name = "football_moderation_you_sure_id",
        no_multiple_tag = "football_moderation_you_sure"
    }

    -- Create main panel
    local panel_name = create_panel(settings)

    -- Add OK button
    add_button_to_panel(panel_name, {
        text = "OK",
        is_vertical = false,
        color = "#00FF00",
        entity_name = name,
        function_name = ok_function
    })

    -- Add Cancel button
    add_button_to_panel(panel_name, {
        text = "Cancel",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = cancel_function
    })

    return panel_name
end

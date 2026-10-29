singleton_name = "moderation_panel"

-- ============================================================================
-- MODERATION PANEL MOD
-- General-purpose moderation panel for server hosts
-- Accessible via /moderation command in chat
-- ============================================================================



-- Connected users dictionary: {steam_id = {nickname = string}}
local connected_users = {}

-- Temporary data for kick/ban operations: {steam_id = {kick_reason, ban_reason, ban_duration, pending_action}}
local temp_data = {}

-- Panel names
local MAIN_PANEL_NAME = "moderation_main_panel_id"
local BANNED_USERS_PANEL_NAME = "moderation_banned_users_panel_id"

-- Search input storage
local history_search_steam_id = ""

-- Who may use the panel: the host, a dedicated server's owners and its
-- moderators (see get_role). Every action is carried out on the host, which
-- checks the rank again: a moderator can never act on another moderator, an
-- owner or the host (the engine enforces that in kick_user/ban_user too).
local function is_staff(steam_id)
    local role = get_role(steam_id)
    return role == "host" or role == "owner" or role == "moderator"
end

local function role_suffix(steam_id)
    local role = get_role(steam_id)
    if role == "host" then return "{host}" end
    if role == "owner" then return "{owner_role}" end
    if role == "moderator" then return "{moderator_role}" end
    return ""
end

-- Print initial message when mod loads (for whoever may use the panel)
if is_staff(LOCAL_STEAM_ID) then
    add_to_chat("{you_can_type_moderation_to_open_moderati}", false)
end

-- Register moderation command to the centralized system
add_command(name, "show_moderation_panel", "moderation", "{host_only_open_the_moderation_panel}", true)




function _on_user_connected(steam_id, nickname)
    -- Store user info (but don't update UI yet - not safe for network calls)
    connected_users[steam_id] = { nickname = nickname }
end

function _on_user_initialized(steam_id, nickname)
    -- User is fully initialized, safe to update UI
    connected_users[steam_id] = { nickname = nickname }
    refresh_main_panel()
end

function _on_user_disconnected(steam_id, nickname)
    -- Remove user from tracking
    connected_users[steam_id] = nil
    refresh_main_panel()
end

function _on_user_kicked(steam_id, nickname, reason)
    local message = "[color=#FF6B6B]" .. nickname .. "{has_been_kicked}"
    if reason ~= "" then
        message = message .. "{reason_3}" .. reason .. ")"
    end
    message = message .. "[/color]"
    add_to_chat(message, false)

    -- Refresh panel to remove kicked user
    refresh_main_panel()
end

function _on_user_banned(steam_id, nickname, duration, reason)
    local duration_text = format_duration(duration)
    local message = "[color=#FF0000]" .. nickname .. "{has_been_banned_for}" .. duration_text
    if reason ~= "" then
        message = message .. "{reason_3}" .. reason .. ")"
    end
    message = message .. "[/color]"
    add_to_chat(message, false)

    -- Refresh panel to update banned users list
    refresh_main_panel()
end

function show_moderation_panel()
    if not is_staff(LOCAL_STEAM_ID) then
        add_to_chat("{only_the_host_can_access_moderation_pane}", false)
        return
    end

    -- Close panel if it already exists, then recreate
    if is_panel_exists(MAIN_PANEL_NAME) then
        close_panel(MAIN_PANEL_NAME)
    end

    local settings = {
        title ="{moderation_panel}",
        resizable = true,
        is_scrollable = true,
        name = MAIN_PANEL_NAME,
        no_multiple_tag = "moderation_moderation_panel",

    }

    MAIN_PANEL_NAME = create_panel(settings)

    -- Add button to open Banned Users Panel
    add_button_to_panel(MAIN_PANEL_NAME, {
        text ="{banned_users}",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = "show_banned_users_panel"
    })

    -- Create connected users table
    create_connected_users_table()
end

function show_banned_users_panel()
    if not is_staff(LOCAL_STEAM_ID) then return end

    -- Close main panel if open
    if is_panel_exists(MAIN_PANEL_NAME) then
        close_panel(MAIN_PANEL_NAME)
    end

    -- Close if already exists (shouldn't happen but for safety)
    if is_panel_exists(BANNED_USERS_PANEL_NAME) then
        close_panel(BANNED_USERS_PANEL_NAME)
    end

    local settings = {
        title ="{banned_users}",
        resizable = true,
        is_scrollable = true,
        name = BANNED_USERS_PANEL_NAME,
        no_multiple_tag = "moderation_banned_users_panel",

    }

    BANNED_USERS_PANEL_NAME = create_panel(settings)

    -- Create banned users table first (so it's at the top of the scroll)
    request_banned_users()

    -- Add search section for history (under the table)
    add_input_to_panel(BANNED_USERS_PANEL_NAME, {
        text ="{search_steam_id}",
        default_value = "",
        entity_name = name,
        function_name = "on_history_search_input_changed"
    })

    -- View History button (at the bottom, in the same row as Back)
    add_button_to_panel(BANNED_USERS_PANEL_NAME, {
        text ="{view_history}",
        is_vertical = false,
        color = "#4B8BF4",
        entity_name = name,
        function_name = "search_user_history"
    })

    -- Back button (at the bottom)
    add_button_to_panel(BANNED_USERS_PANEL_NAME, {
        text ="{back}",
        is_vertical = false,
        color = "#808080",
        entity_name = name,
        function_name = "back_to_main_panel"
    })
end

function back_to_main_panel(args)
    if is_panel_exists(BANNED_USERS_PANEL_NAME) then
        close_panel(BANNED_USERS_PANEL_NAME)
    end
    show_moderation_panel()
end

function refresh_main_panel()
    -- Refresh connected users table if main panel exists
    if is_panel_exists(MAIN_PANEL_NAME) then
        create_connected_users_table()
    end

    -- Refresh banned users table if banned users panel exists
    if is_panel_exists(BANNED_USERS_PANEL_NAME) then
        request_banned_users()
    end
end

function create_connected_users_table()
    local table_data = {}

    -- Header row
    table_data[vector2_to_string(Vector2(0, 0))] = { text ="{connected_users}", color = "#4B8BF4" }
    table_data[vector2_to_string(Vector2(1, 0))] = { text ="{steam_id}", color = "#4B8BF4" }

    -- Sort users by nickname
    local sorted_users = {}
    for steam_id, user_data in pairs(connected_users) do
        table.insert(sorted_users, { steam_id = steam_id, nickname = user_data.nickname })
    end

    table.sort(sorted_users, function(a, b)
        return a.nickname < b.nickname
    end)

    -- Fill data rows
    for i, user in ipairs(sorted_users) do
        local row = i
        local steam_id = user.steam_id
        local nickname = user.nickname

        -- Highlight the host / owners / moderators
        local color = "#FFFFFF"
        local suffix = role_suffix(steam_id)
        if suffix ~= "" then
            color = (suffix == "{moderator_role}") and "#7FD4FF" or "#00FF00"
            nickname = nickname .. suffix
        end

        table_data[vector2_to_string(Vector2(0, row))] = {
            text = nickname,
            color = color,
            steam_id = steam_id
        }

        table_data[vector2_to_string(Vector2(1, row))] = {
            text = steam_id,
            color = color,
            steam_id = steam_id
        }
    end

    -- Update table
    set_table(MAIN_PANEL_NAME, {
        name = "moderation_connected_users_table",
        table_data = table_data,
        entity_name = name,
        function_name = "on_connected_user_clicked"
    })
end

-- The ban list lives on the host; another machine asks for it.
function request_banned_users()
    if IS_HOST then
        create_banned_users_table(BANNED_USERS_PANEL_NAME, get_banned_users_list())
    else
        run_network_function(name, "banned_users_HOST", {})
    end
end

function banned_users_HOST(sender_id)
    if not IS_HOST or not is_staff(sender_id) then return end
    run_network_function(name, "banned_users_CLIENT", { get_banned_users_list() }, sender_id)
end

function banned_users_CLIENT(sender_id, banned_users)
    if is_panel_exists(BANNED_USERS_PANEL_NAME) then
        create_banned_users_table(BANNED_USERS_PANEL_NAME, banned_users)
    end
end

function create_banned_users_table(panel_name, banned_users)
    local table_data = {}

    -- Header row
    table_data[vector2_to_string(Vector2(0, 0))] = { text ="{banned_users}", color = "#FF0000" }
    table_data[vector2_to_string(Vector2(1, 0))] = { text ="{time_remaining}", color = "#FF0000" }
    table_data[vector2_to_string(Vector2(2, 0))] = { text ="{reason}", color = "#FF0000" }

    -- Fill data rows
    for i, ban_info in ipairs(banned_users) do
        local row = i
        local steam_id = ban_info.steam_id
        local nickname = ban_info.nickname
        local remaining = format_duration(ban_info.remaining_seconds)
        local reason = ban_info.reason

        if reason == "" then
            reason = "{no_reason_provided}"
        end

        table_data[vector2_to_string(Vector2(0, row))] = {
            text = nickname,
            color = "#FF8888",
            steam_id = steam_id,
            nickname = nickname,
            reason = reason
        }

        table_data[vector2_to_string(Vector2(1, row))] = {
            text = remaining,
            color = "#FF8888",
            steam_id = steam_id,
            nickname = nickname
        }

        table_data[vector2_to_string(Vector2(2, row))] = {
            text = reason,
            color = "#FF8888",
            steam_id = steam_id,
            nickname = nickname
        }
    end

    -- Update table
    set_table(panel_name, {
        name = "moderation_banned_users_table",
        table_data = table_data,
        entity_name = name,
        function_name = "on_banned_user_clicked"
    })
end

function on_connected_user_clicked(args)
    local cell_data = args.cell_data
    if not cell_data or not cell_data.steam_id then
        return
    end

    local steam_id = cell_data.steam_id
    local nickname = connected_users[steam_id] and connected_users[steam_id].nickname or "Unknown"

    show_user_action_panel(steam_id, nickname)
end

function on_banned_user_clicked(args)
    local cell_data = args.cell_data
    if not cell_data or not cell_data.steam_id then
        return
    end

    local steam_id = cell_data.steam_id
    local nickname = cell_data.nickname or "{unknown_user}"
    -- The row already carries what the panel shows (works off the host too).
    show_unban_panel(steam_id, { reason = cell_data.reason }, nickname)
end

function show_user_action_panel(steam_id, nickname)
    local settings = {
        text ="{user_actions}" .. nickname .. " (" .. steam_id .. ")",
        title ="{user_actions_2}",
        resizable = false,
        name = "moderation_user_action_panel_id",
        no_multiple_tag = "moderation_user_action_panel"
    }

    local panel_name = create_panel(settings)

    -- View Steam Profile button
    add_button_to_panel(panel_name, {
        text ="{view_steam_profile}",
        is_vertical = true,
        color = "#4B8BF4",
        entity_name = name,
        function_name = "view_steam_profile",
        extra_args = { steam_id = steam_id }
    })

    -- An owner (or the host) appoints moderators.
    if is_admin(LOCAL_STEAM_ID) and (get_role(steam_id) == "player" or get_role(steam_id) == "moderator") then
        local is_mod = get_role(steam_id) == "moderator"
        add_button_to_panel(panel_name, {
            text = is_mod and "{remove_moderator}" or "{make_moderator}",
            is_vertical = true,
            color = "#7FD4FF",
            entity_name = name,
            function_name = "toggle_moderator",
            extra_args = { steam_id = steam_id, make = not is_mod }
        })
    end

    -- Kick/ban only for players ranked below the one looking at the panel
    if can_moderate(LOCAL_STEAM_ID, steam_id) then
        -- Kick button
        add_button_to_panel(panel_name, {
            text ="{kick_user}",
            is_vertical = true,
            color = "#FF6B6B",
            entity_name = name,
            function_name = "show_kick_panel",
            extra_args = { steam_id = steam_id, nickname = nickname }
        })

        -- Ban button
        add_button_to_panel(panel_name, {
            text ="{ban_user}",
            is_vertical = true,
            color = "#FF0000",
            entity_name = name,
            function_name = "show_ban_panel",
            extra_args = { steam_id = steam_id, nickname = nickname }
        })
    end
end

function toggle_moderator(args)
    run_network_function(name, "set_moderator_HOST", { args.extra_args.steam_id, args.extra_args.make == true })
    close_panel(args.panel_name)
end

function set_moderator_HOST(sender_id, target_id, make)
    if not IS_HOST or not is_admin(sender_id) then return end
    local changed
    if make then changed = add_moderator(target_id) else changed = remove_moderator(target_id) end
    if changed then
        local nickname = connected_users[target_id] and connected_users[target_id].nickname or target_id
        add_to_chat(nickname .. (make and "{is_now_a_moderator}" or "{is_no_longer_a_moderator}"), true)
    end
end

function view_steam_profile(args)
    open_profile(args.extra_args.steam_id)
end

function show_kick_panel(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname

    temp_data[steam_id] = temp_data[steam_id] or {}
    temp_data[steam_id].kick_reason = ""

    close_panel(args.panel_name)

    local settings = {
        text ="{kick}" .. nickname,
        title ="{kick_user}",
        resizable = false,
        name = "moderation_kick_panel_id",
        no_multiple_tag = "moderation_kick_panel"
    }

    local panel_name = create_panel(settings)

    -- Reason input
    add_input_to_panel(panel_name, {
        text ="{reason}",
        default_value = "",
        entity_name = name,
        extra_args = { steam_id = steam_id }
    })

    -- Kick button
    add_button_to_panel(panel_name, {
        text ="{kick_user}",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = "execute_kick",
        extra_args = { steam_id = steam_id, nickname = nickname }
    })
end

function execute_kick(args)
    local steam_id = args.extra_args and args.extra_args.steam_id
    local nickname = args.extra_args and args.extra_args.nickname or "Unknown"
    
    local reason = args.Reason or ""
    if reason == "" then
        reason = "{no_reason_provided}"
    end

    create_confirmation_panel(
        "{are_you_sure_you_want_to_kick}" .. nickname .. "{reason_4}" .. reason,
        "confirm_kick",
        "cancel_action"
    )

    if not temp_data[steam_id] then
        temp_data[steam_id] = {}
    end

    temp_data[steam_id].pending_action = {
        type = "kick",
        reason = reason
    }

    close_panel(args.panel_name)
end

function confirm_kick(args)
    for steam_id, data in pairs(temp_data) do
        if data.pending_action and data.pending_action.type == "kick" then
            run_network_function(name, "kick_HOST", { steam_id, data.pending_action.reason })
            temp_data[steam_id] = nil
            break
        end
    end
    close_panel(args.panel_name)
end

function show_ban_panel(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname

    temp_data[steam_id] = temp_data[steam_id] or {}
    temp_data[steam_id].ban_reason = ""
    temp_data[steam_id].ban_duration = "1 Hour"

    close_panel(args.panel_name)

    local settings = {
        text ="{ban}" .. nickname,
        title ="{ban_user}",
        resizable = false,
        name = "moderation_ban_panel_id",
        no_multiple_tag = "moderation_ban_panel"
    }

    local panel_name = create_panel(settings)

    -- Duration option box
    add_optionbox_to_panel(panel_name, {
        text ="{duration}",
        options = { "1 Hour", "6 Hours", "12 Hours", "1 Day", "1 Week", "1 Month", "{permanent}" },
        entity_name = name,
        extra_args = { steam_id = steam_id }
    })

    -- Reason input
    add_input_to_panel(panel_name, {
        text ="{reason}",
        default_value = "",
        entity_name = name,
        extra_args = { steam_id = steam_id }
    })

    -- Ban button
    add_button_to_panel(panel_name, {
        text ="{ban_user}",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = "execute_ban",
        extra_args = { steam_id = steam_id, nickname = nickname }
    })
end

function execute_ban(args)
    if not args then 
        return 
    end
    
    local steam_id = args.extra_args and args.extra_args.steam_id
    local nickname = args.extra_args and args.extra_args.nickname or "Unknown"

    if not steam_id then 
        return 
    end

    local duration_text = args.Duration or "1 Hour"
    local reason = args.Reason or ""

    if reason == "" then
        reason = "{no_reason_provided}"
    end
    
    if not temp_data[steam_id] then
        temp_data[steam_id] = {}
    end

    local duration_seconds = get_duration_seconds(duration_text)

    create_confirmation_panel(
        "{are_you_sure_you_want_to_ban}" .. nickname .. "{duration_2}" .. duration_text .. "{reason_5}" .. reason,
        "confirm_ban",
        "cancel_action"
    )

    temp_data[steam_id].pending_action = {
        type = "ban",
        duration = duration_seconds,
        reason = reason
    }
    
    close_panel(args.panel_name)
end

function confirm_ban(args)
    for steam_id, data in pairs(temp_data) do
        if data.pending_action and data.pending_action.type == "ban" then
            local duration = data.pending_action.duration or get_duration_seconds("1 Hour")
            local reason = data.pending_action.reason or "{no_reason_provided}"

            run_network_function(name, "ban_HOST", { steam_id, duration, reason })
            temp_data[steam_id] = nil
            break
        end
    end
    close_panel(args.panel_name)
end

function show_unban_panel(steam_id, ban_info, nickname)
    local nickname = nickname or (ban_info and ban_info.nickname) or "{unknown_user}"

    local settings = {
        text ="{unban}" .. nickname .. "?",
        title ="{unban_user}",
        resizable = false,
        name = "moderation_unban_panel_id",
        no_multiple_tag = "moderation_unban_panel"
    }

    local panel_name = create_panel(settings)

    -- Show ban info text
    local info_text ="{reason_2}" .. (ban_info.reason or "{no_reason_provided}")

    -- Unban button
    add_button_to_panel(panel_name, {
        text ="{unban_user}",
        is_vertical = false,
        color = "#00FF00",
        entity_name = name,
        function_name = "execute_unban",
        extra_args = { steam_id = steam_id, nickname = nickname }
    })

    -- Cancel button
    add_button_to_panel(panel_name, {
        text ="{cancel}",
        is_vertical = false,
        color = "#808080",
        entity_name = name,
        function_name = "cancel_unban"
    })
end

function execute_unban(args)
    local steam_id = args.extra_args.steam_id
    local nickname = args.extra_args.nickname

    run_network_function(name, "unban_HOST", { steam_id, nickname })

    close_panel(args.panel_name)
end

-- The actions themselves, on the host. The sender is passed to kick_user /
-- ban_user as the actor, so the engine refuses a moderator acting on someone of
-- equal or higher rank even if a modified client asks.
function kick_HOST(sender_id, target_id, reason)
    if not IS_HOST or not is_staff(sender_id) then return end
    kick_user(target_id, reason, sender_id)
end

function ban_HOST(sender_id, target_id, duration, reason)
    if not IS_HOST or not is_staff(sender_id) then return end
    ban_user(target_id, math.floor(tonumber(duration) or 3600), reason, sender_id)
end

function unban_HOST(sender_id, target_id, nickname)
    if not IS_HOST or not is_staff(sender_id) then return end
    unban_user(target_id)
    -- Targeted at the sender; on a listen host that is the host itself, and a
    -- targeted call to the host runs locally.
    run_network_function(name, "unbanned_CLIENT", { nickname }, sender_id)
end

function unbanned_CLIENT(sender_id, nickname)
    add_to_chat("[color=#00FF00]" .. nickname .. "{has_been_unbanned}", false)
    refresh_main_panel()
end

function cancel_unban(args)
    close_panel(args.panel_name)
end

function create_confirmation_panel(message, ok_function, cancel_function)
    local settings = {
        text = message,
        title ="{are_you_sure}",
        resizable = false,
        name = "moderation_confirmation_id",
        no_multiple_tag = "moderation_confirmation_panel"
    }

    local panel_name = create_panel(settings)

    -- OK button
    add_button_to_panel(panel_name, {
        text ="{ok}",
        is_vertical = false,
        color = "#00FF00",
        entity_name = name,
        function_name = ok_function
    })

    -- Cancel button
    add_button_to_panel(panel_name, {
        text ="{cancel}",
        is_vertical = false,
        color = "#FF0000",
        entity_name = name,
        function_name = cancel_function
    })

    return panel_name
end

function cancel_action(args)
    -- Clear pending actions
    for steam_id, data in pairs(temp_data) do
        if data.pending_action then
            temp_data[steam_id].pending_action = nil
        end
    end
    close_panel(args.panel_name)
end

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
    elseif duration_str == "{permanent}" then
        return 3600 * 24 * 365 * 100
    else
        return 3600
    end
end

function format_duration(seconds)
    if seconds >= 3600 * 24 * 365 then
        return "{permanent}"
    elseif seconds >= 3600 * 24 * 30 then
        return math.floor(seconds / (3600 * 24 * 30)) .. "{month_s}"
    elseif seconds >= 3600 * 24 * 7 then
        return math.floor(seconds / (3600 * 24 * 7)) .. "{week_s}"
    elseif seconds >= 3600 * 24 then
        return math.floor(seconds / (3600 * 24)) .. "{day_s}"
    elseif seconds >= 3600 then
        return math.floor(seconds / 3600) .. "{hour_s}"
    elseif seconds >= 60 then
        return math.floor(seconds / 60) .. "{minute_s}"
    else
        return seconds .. "{second_s}"
    end
end

function on_history_search_input_changed(args)
    history_search_steam_id = args["{search_steam_id}"] or ""
end

function search_user_history(args)
    if history_search_steam_id == "" then
        add_to_chat("{please_enter_a_steam_id_to_search}", false)
        return
    end

    if IS_HOST then
        show_history(history_search_steam_id, get_user_history(history_search_steam_id))
    else
        run_network_function(name, "history_HOST", { history_search_steam_id })
    end
end

function history_HOST(sender_id, steam_id)
    if not IS_HOST or not is_staff(sender_id) then return end
    run_network_function(name, "history_CLIENT", { steam_id, get_user_history(steam_id) }, sender_id)
end

function history_CLIENT(sender_id, steam_id, history)
    show_history(steam_id, history)
end

function show_history(steam_id, history)
    if #history == 0 then
        show_no_history_panel(steam_id)
    else
        show_history_panel(steam_id, history)
    end
end

function show_no_history_panel(steam_id)
    local settings = {
        text ="{no_moderation_records_found_for_steam_id}" .. steam_id,
        title ="{no_history_found}",
        resizable = false,
        name = "moderation_history_panel_id",
        no_multiple_tag = "moderation_history_panel"
    }

    local panel_name = create_panel(settings)

    add_button_to_panel(panel_name, {
        text ="{close}",
        is_vertical = false,
        color = "#808080",
        entity_name = name,
        function_name = "close_history_panel"
    })
end

function show_history_panel(steam_id, history)
    local settings = {
        title ="{moderation_history}" .. get_nickname_from_history(history),
        resizable = true,
        is_scrollable = true,
        name = "moderation_history_panel_id",
        no_multiple_tag = "moderation_history_panel",

    }

    local panel_name = create_panel(settings)

    create_history_table(panel_name, history)

    add_button_to_panel(panel_name, {
        text ="{close}",
        is_vertical = false,
        color = "#808080",
        entity_name = name,
        function_name = "close_history_panel"
    })
end

function create_history_table(panel_name, history)
    local table_data = {}

    -- Header row
    table_data[vector2_to_string(Vector2(0, 0))] = { text ="{date_time}", color = "#4B8BF4" }
    table_data[vector2_to_string(Vector2(1, 0))] = { text ="{action}", color = "#4B8BF4" }
    table_data[vector2_to_string(Vector2(2, 0))] = { text ="{duration}", color = "#4B8BF4" }
    table_data[vector2_to_string(Vector2(3, 0))] = { text ="{reason}", color = "#4B8BF4" }

    -- Fill data rows (history sorted newest-first from GDScript)
    for i, entry in ipairs(history) do
        local row = i
        local action = entry.action
        local color = get_action_color(action)

        local formatted_time = format_timestamp(entry.timestamp)

        local duration_text = ""
        if action == "BAN" then
            duration_text = format_duration(entry.duration)
        else
            duration_text = "N/A"
        end

        local reason = entry.reason
        if reason == "" then
            reason = "{no_reason_provided}"
        end

        table_data[vector2_to_string(Vector2(0, row))] = {
            text = formatted_time,
            color = color
        }

        table_data[vector2_to_string(Vector2(1, row))] = {
            text = action,
            color = color
        }

        table_data[vector2_to_string(Vector2(2, row))] = {
            text = duration_text,
            color = color
        }

        table_data[vector2_to_string(Vector2(3, row))] = {
            text = reason,
            color = color
        }
    end

    set_table(panel_name, {
        name = "moderation_history_table",
        table_data = table_data,
        entity_name = name
    })
end

function close_history_panel(args)
    close_panel(args.panel_name)
end

-- Helper functions
function get_action_color(action)
    if action == "KICK" then
        return "#FF6B6B" -- Light red
    elseif action == "BAN" then
        return "#FF0000" -- Red
    elseif action == "UNBAN" then
        return "#00FF00" -- Green
    else
        return "#FFFFFF"
    end
end

function get_nickname_from_history(history)
    if #history > 0 then
        return history[1].nickname
    end
    return "{unknown_user}"
end

singleton_name = "ui_manager"

--for managing scoreboard, goal, and starting match


users = {} -- Format: {steam_id = {goals=0, assists=0, team=0}}
SCORE_PANEL_NAME = "football_scoreboard_panel_id"

is_score_table_input_last = false

change_view("gameplay")

set_value("", "_USQKTEW3zusL1CNU1737417431", "text", "@key_6@ Hit Ball\n@key_11@ Scoreboard\n@stick_1@ Movement") -- right bottom  inputs label


blue_score = 0
red_score = 0


function _process(delta, inputs)
    local is_score_table_input_new = inputs["key_11"]
    if is_score_table_input_last == true and is_score_table_input_new == false then
        if is_panel_exists(SCORE_PANEL_NAME) then
            close_panel(SCORE_PANEL_NAME)
        else
            refresh_scoreboard(true)
        end
    end
    is_score_table_input_last = is_score_table_input_new
end

function update_team_score(scoring_team)
    if not IS_HOST then return end

    if scoring_team == 1 then     -- RED
        red_score = red_score + 1
    elseif scoring_team == 2 then --BLUE
        blue_score = blue_score + 1
    end

    run_network_function(name, "update_match_score_ALL", { red_score, blue_score })
end

function update_match_score_ALL(sender_id, _red_score, _blue_score)
    label_config = {
        text = "RED TEAM " .. math.floor(_red_score),
        name = "_L1O0Bnkl5f5W4PXI1737915307"
    }
    set_label(label_config)

    label_config2 = {
        text = "BLUE TEAM " .. math.floor(_blue_score),
        name = "_nht0GjrXZngWZM5b1737915305"
    }
    set_label(label_config2)

    set_audio({
        stream_path = "goal",
        bus = "Effect",
        random_pitch = 0.2,
        is_2d = false,
    })
end

function _on_user_disconnected(steam_id, nickname)
    add_to_chat(nickname .. " disconnected")
    remove_user_from_scoreboard(steam_id)
end

function _on_user_connected(steam_id, nickname)
    --Not safe to call network functions
    add_to_chat(nickname .. " connected")
end

function _on_user_initialized(steam_id, nickname)
    -- This will be called when a client has fully downloaded and initialized
    -- Safe to call network functions now for this client
    if IS_HOST then
        --  Update this client with current game state
        run_network_function(name, "update_match_score_ALL", { red_score, blue_score }, steam_id)
        add_user_to_scoreboard(steam_id, nickname)
    end
end

function update_users_score_ALL(sender_id, users_data)
    users = users_data
    check_and_create_user_visuals()
    if is_panel_exists(SCORE_PANEL_NAME) then
        refresh_scoreboard(false) -- false because panel already exists
    end
end

function check_and_create_user_visuals()
    -- Check each user's visuals if they're not spectators
    for steam_id, user_data in pairs(users) do -- get_entity_names_by_tag("user") can also be used but we already store users
        if user_data.team ~= 0 then            -- Not a spectator
            local image_name = get_value("", steam_id, "image_name")
            if image_name == "" then           -- Visuals not initialized
                -- Call change_team_ALL with their current team
                -- change_team_ALL is network function but we can call it locally on client to create visuals
                -- first parameter(LOCAL_STEAM_ID) can be any random value we don't use it actually
                -- but we need to pass it to the network function as sender_id
                run_function(steam_id, "change_team_ALL", { LOCAL_STEAM_ID, user_data.team })
            end
        end
    end
end

-- Add new user to scoreboard
function add_user_to_scoreboard(steam_id, nickname)
    if IS_HOST then
        users[steam_id] = {
            goals = 0,
            nickname = nickname,
            assists = 0,
            team = 0 -- users start without team
        }
        run_network_function(name, "update_users_score_ALL", { users })
    end
end

-- Remove user from scoreboard
function remove_user_from_scoreboard(steam_id)
    if IS_HOST then
        users[steam_id] = nil
        run_network_function(name, "update_users_score_ALL", { users })
    end
end

function own_goal_scores(scorer_id)
    if IS_HOST then
        if scorer_id and users[scorer_id] then
            if not users[scorer_id].goals then
                users[scorer_id].goals = 0
            end
            users[scorer_id].goals = users[scorer_id].goals - 1
        end
        run_network_function(name, "update_users_score_ALL", { users })
    end
end

function addition_scores(scorer_id, assister_id)
    if not IS_HOST then return end
    -- Increment goal for scorer if valid
    if scorer_id and users[scorer_id] then
        if not users[scorer_id].goals then
            users[scorer_id].goals = 0
        end
        users[scorer_id].goals = users[scorer_id].goals + 1
    end

    -- Increment assist for assister if valid
    if assister_id and users[assister_id] then
        if not users[assister_id].assists then
            users[assister_id].assists = 0
        end
        users[assister_id].assists = users[assister_id].assists + 1
    end
    run_network_function(name, "update_users_score_ALL", { users })
end

function handle_goal_ui_ALL(sender_id, last_touching_steam_id, previous_touching_steam_id, scoring_team)
    -- Validate required parameters
    if last_touching_steam_id == nil then
        print("Error: last_touching_steam_id is nil")
        return
    end
    if scoring_team == nil or (scoring_team ~= 1 and scoring_team ~= 2) then
        return
    end
    -- Validate user exists
    if users[last_touching_steam_id] == nil then -- if there is not data of scorer dont run the function
        return
    end
    -- Validate user has required data
    local user = users[last_touching_steam_id]
    if user.team == nil or user.nickname == nil then
        return
    end

    if user.team == 0 then -- Don't allow spectators (team 0) to score
        return
    end

    local user_team = users[last_touching_steam_id].team
    local is_own_goal = false
    local display_color = Color(0, 0, 1) --BLUE

    if scoring_team == 1 then
        display_color = Color(1, 0, 0) --RED
    end

    if (user_team == 1 and scoring_team == 2) or
        (user_team == 2 and scoring_team == 1) then
        is_own_goal = true
    end

    local goal_text = ""

    local scoring_team_str = "Red"
    if scoring_team == 2 then
        scoring_team_str = "Blue"
    end

    if is_own_goal then
        goal_text = "Ops! " ..
            users[last_touching_steam_id].nickname .. " OWN GOAL!!! 🥲\n" .. scoring_team_str .. " team scored"
        own_goal_scores(last_touching_steam_id)
    else
        local assist_id = nil
        if previous_touching_steam_id and users[previous_touching_steam_id] and users[last_touching_steam_id] then
            if previous_touching_steam_id ~= last_touching_steam_id then
                if users[previous_touching_steam_id].team == users[last_touching_steam_id].team then
                    assist_id = previous_touching_steam_id
                end
            end
        end

        goal_text = users[last_touching_steam_id].nickname .. " SCORED A GOAL!!!\n" .. scoring_team_str .. " team scored"

        if assist_id then
            goal_text = goal_text .. "\nAssist by " .. users[assist_id].nickname
        end

        addition_scores(last_touching_steam_id, assist_id)
    end
    -- Update team score
    if IS_HOST then
        update_team_score(scoring_team)
    end

    local label_config = {
        text = goal_text,
        visible = true,
        font_color = display_color,
        name = "_center_label"
    }
    set_label(label_config)

    run_function(name, "hide_goal_message", {}, 3.0) -- with 3 seconds delay
end

function hide_goal_message() -- Function to hide the goal message
    set_value("", "_center_label", "visible", false)
end

-- Change user team
function move_team(steam_id, team)
    if not IS_HOST then return end
    if users[steam_id] then
        users[steam_id].team = team
        run_network_function(name, "update_users_score_ALL", { users })
    end
end

function refresh_scoreboard(is_create_if_not_exist)
    local panel_exists = is_panel_exists(SCORE_PANEL_NAME)

    -- Create panel if it doesn't exist
    if not panel_exists then
        if not is_create_if_not_exist then
            return
        end
        local settings = {
            title = "Scoreboard",
            resizable = true,
            is_scrollable = true,
            name = SCORE_PANEL_NAME,
            no_multiple_tag = "football_scoreboard",
            minimum_size = Vector2(300, 200) --default is Vector2(300,150)
        }
        SCORE_PANEL_NAME = create_panel(settings)
    end

    if IS_HOST and panel_exists == false then
        add_button_to_panel(SCORE_PANEL_NAME, {
            text = "Start Match",
            entity_name = name,
            function_name = "show_match_settings_panel",
            is_vertical = true,
            icon_path = "forward",
            color = Color(0, 1, 0) -- Green color
        })
    end


    -- Create table data
    local table_data = create_scoreboard_data()
    -- Update or create table
    set_table(SCORE_PANEL_NAME, {
        name = "football_scoreboard_table", -- Consistent table name for updates
        table_data = table_data,
        entity_name = name,
        function_name = "on_user_clicked"
    })
end

function show_match_settings_panel()
    close_panel(SCORE_PANEL_NAME)
    local panel_config = {
        text = "",
        title = "Match Settings",
        name = "football_match_settings_panel_id",
        no_multiple_tag = "football_match_settings", -- Prevent multiple panels
        resizable = false
    }

    local panel_name = create_panel(panel_config)

    add_button_to_panel(panel_name, {
        text = "Start Match",
        entity_name = name,
        function_name = "match_countdown",
        is_vertical = true,
        color = Color(0, 1, 0) -- Green color
    })

    add_optionbox_to_panel(panel_name, {
        text = "Time Limit",
        options = { 1, 2, 5, 10, 15, 20, 30, 60, 90, "∞" }, --"∞" means infinite
        entity_name = name,
    })
end

function match_countdown(args)
    run_network_function(name, "start_match_countdown_ALL", { args["Time Limit"] })
    close_panel(args.panel_name)
end

function start_match_countdown_ALL(sender_id, time_limit)
    set_label({
        name = "_center_label",
        text = 3,
        font_color = Color(1, 1, 1),
        visible = true
    })


    start_timer({
        timer_id = "match_countdown",
        entity_name = name,
        function_name = "count_down",
        wait_time = 1.0,
        duration = 3.0,
        extra_args = { time_limit = time_limit }
    })
    stop_timer("match_time") --stop if there is a previous match timer
end

function count_down(args)
    countdown = 3 - args.iteration_count
    if args.is_last_iteration then
        set_label({
            name = "_center_label",
            visible = false
        })
        if IS_HOST then
            start_match(args)
        end
        return
    end
    set_label({
        name = "_center_label",
        text = countdown,
        font_color = Color(1, 1, 1),
        visible = true
    })
end

function start_match(args)
    blue_score = 0
    red_score = 0
    run_network_function(name, "update_match_score_ALL", { red_score, blue_score })
    run_network_function("-time_manager", "start_time_ALL", { args.extra_args["time_limit"] })
    reset_users_position()
    run_function("*ball", "reset")

    set_label({
        name = "_center_label",
        visible = false
    })
end

function reset_users_position()
    for steam_id, user_data in pairs(users) do -- get_entity_names_by_tag("user") can also be used but we already store users
        if user_data.team ~= 0 then            -- Not a spectator
            run_function(steam_id, "reset_position")
        end
    end
end

function determine_winner()
    local winner = 0 -- 0: draw, 1:red won, 2: blue won
    local score_diff = red_score - blue_score

    if score_diff > 0 then
        winner = 1
    elseif score_diff < 0 then
        winner = 2
    end

    run_network_function(name, "handle_game_over_ALL", { winner })
end

function handle_game_over_ALL(sender_id, winner)
    set_audio({
        stream_path = "whistle",
        bus = "Effect",
        is_2d = false,
    })

    local message, color

    if winner == 2 then
        message = "BLUE TEAM WON"
        color = Color(0, 0, 1)
    elseif winner == 1 then
        message = "RED TEAM WON"
        color = Color(1, 0, 0)
    else
        message = "DRAW"
        color = Color(1, 1, 1)
    end

    set_label({
        name = "_center_label",
        text = message,
        visible = true,
        font_color = color
    })
end

function create_scoreboard_data()
    local table_data = {}

    -- Header row
    table_data[vector2_to_string(Vector2(0, 0))] = { text = "User", color = "#808080" }
    table_data[vector2_to_string(Vector2(1, 0))] = { text = "Team", color = "#808080" }
    table_data[vector2_to_string(Vector2(2, 0))] = { text = "Goals", color = "#808080" }
    table_data[vector2_to_string(Vector2(3, 0))] = { text = "Assists", color = "#808080" }

    -- Sort users
    local sorted_users = {}
    for steam_id, data in pairs(users) do
        table.insert(sorted_users, { steam_id = steam_id, data = data })
    end

    table.sort(sorted_users, function(a, b)
        if a.data.team ~= b.data.team then
            return a.data.team > b.data.team
        end
        return a.data.goals > b.data.goals
    end)

    -- Fill data for each user
    for i, user in ipairs(sorted_users) do
        local steam_id = user.steam_id
        local data = user.data
        local row = i

        local color = "#FFFFFF"
        if data.team == 2 then     --blue
            color = "#0066CC"
        elseif data.team == 1 then --red
            color = "#CC0000"
        end

        table_data[vector2_to_string(Vector2(0, row))] = {
            text = data.nickname,
            color = color,
            steam_id = steam_id
        }

        local team_name = "Spectator"
        if data.team == 1 then
            team_name = "Red"
        elseif data.team == 2 then
            team_name = "Blue"
        end

        table_data[vector2_to_string(Vector2(1, row))] = {
            text = team_name,
            color = color
        }

        table_data[vector2_to_string(Vector2(2, row))] = {
            text = math.floor(data.goals),
            color = color
        }

        table_data[vector2_to_string(Vector2(3, row))] = {
            text = math.floor(data.assists),
            color = color
        }
    end

    return table_data
end

function on_user_clicked(args) --custom function on cell of the table clicked
    local cell_data = args.cell_data
    if cell_data and cell_data.steam_id then
        run_function("-user_action_panel", "show_user_actions", { cell_data.steam_id, cell_data.text })
    end
end

function dump(o)
    if type(o) == 'table' then
        local s = '{\n'
        for k, v in pairs(o) do
            local key = k
            if type(k) == 'userdata' and k.x and k.y then
                key = string.format("(%d,%d)", k.x, k.y)
            elseif type(k) ~= 'number' then
                key = '"' .. tostring(k) .. '"'
            end

            local value = v
            if type(v) == 'userdata' and v.x and v.y then
                value = string.format("(%d,%d)", v.x, v.y)
            else
                value = dump(v)
            end

            s = s .. '  [' .. key .. '] = ' .. value .. ',\n'
        end
        return s .. '}'
    else
        return tostring(o)
    end
end

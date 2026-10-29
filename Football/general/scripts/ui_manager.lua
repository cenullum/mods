singleton_name = "ui_manager"

--for managing scoreboard, goal, and starting match


users = {} -- Format: {steam_id = {goals=0, assists=0, team=0}}
SCORE_PANEL_NAME = "football_scoreboard_panel_id"

is_score_table_input_last = false

-- Team colours: team 1 is orange, team 2 purple (they were plain red and blue). The ids keep the
-- old words - red_goalpost, "{red_team}", red_score - but every team colour on screen comes from
-- here; user.lua, bot.lua and user_action_panel.lua carry the same values (each script has its
-- own environment). TEAM_HEX = the darker shade for panel buttons (white text on them).
TEAM_COLORS = { [1] = Color(1.0, 0.55, 0.12, 1), [2] = Color(0.62, 0.38, 1.0, 1) }
TEAM_HEX = { [1] = "#E07010", [2] = "#7A3FE0" }
TEXT_OUTLINE = Color(0.08, 0.06, 0.16, 1)      -- dark ink outline for every big HUD text

-- The goal banner: a big title in the scoring team's colour that pops in, the scorer under it and
-- the assist under that. Its own three labels; _center_label is left to the match result.
GOAL_TITLE = "_goal_title"
GOAL_SCORER = "_goal_scorer"
GOAL_ASSIST = "_goal_assist"
GOAL_POP = { 1.9, 1.45, 1.12, 0.94, 1.04, 1.0 } -- the title's scale, one step every GOAL_POP_STEP s
GOAL_POP_STEP = 0.035
GOAL_SHOW_SECONDS = 3.0

change_view("gameplay")

set_value("", "_USQKTEW3zusL1CNU1737417431", "text", "@key_8@ {hit_ball}\n@key_11@ {scoreboard}\n@stick_1@ {movement}") -- right bottom  inputs label


blue_score = 0
red_score = 0
local my_match_goals = 0 -- this peer's goals in the current match (Steam achievement: hat-trick)

-- Who starts a match. An admin (the host, or a dedicated server's owner) uses the
-- match settings as always. With no admin among the players - a dedicated server
-- nobody owns at the moment - the players vote, and a match also starts by
-- itself once both teams have someone on them. On a listen host the host is
-- always present, so nothing starts without them, exactly as before.
match_state = "idle"     -- host: "idle" | "countdown" | "running"
votes = {}               -- host: steam_id -> true
DEFAULT_TIME_LIMIT = 5   -- minutes, for voted and automatic matches
AUTO_START_DELAY = 20.0  -- seconds of warning before an automatic start

add_command(name, "cmd_start", "start", "{cmd_start_desc}", true)


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
        text ="{red_team}" .. math.floor(_red_score),
        name = "_L1O0Bnkl5f5W4PXI1737915307",
        font_color = TEAM_COLORS[1], outline_color = TEXT_OUTLINE, outline_size = 8
    }
    set_label(label_config)

    label_config2 = {
        text ="{blue_team}" .. math.floor(_blue_score),
        name = "_nht0GjrXZngWZM5b1737915305",
        font_color = TEAM_COLORS[2], outline_color = TEXT_OUTLINE, outline_size = 8
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
    add_to_chat(nickname .. "{disconnected}")
    remove_user_from_scoreboard(steam_id)
    if IS_HOST then
        votes[steam_id] = nil
        run_function("-team_balancer", "on_player_left", { steam_id })
        check_auto_start()
    end
end

function _on_user_connected(steam_id, nickname)
    --Not safe to call network functions
    add_to_chat(nickname .. "{connected}")
end

function _on_user_initialized(steam_id, nickname)
    -- This will be called when a client has fully downloaded and initialized
    -- Safe to call network functions now for this client
    if IS_HOST then
        --  Update this client with current game state
        run_network_function(name, "update_match_score_ALL", { red_score, blue_score }, steam_id)
        add_user_to_scoreboard(steam_id, nickname)
        run_function("-team_balancer", "on_player_joined", { steam_id })
    end
end

function get_users_table()
    return users
end

-- Bots hold team slots too: when one comes, goes or switches, a player waiting
-- in the queue may now fit.
local function bot_slots_changed()
    run_function("-team_balancer", "serve_queue")
    check_auto_start()
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
        -- Bots build their own visuals in bot.lua on every peer, and their
        -- entity may not have spawned here yet: never poke them.
        if user_data.is_bot then
            -- nothing to do
        elseif user_data.team ~= 0 then        -- Not a spectator
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

-- Add a bot to the scoreboard (-bot_manager calls this when one is spawned).
-- Bots live in the same table as players on purpose: that is what lets them
-- score, pick up assists and be clicked in the score table like anyone else.
function add_bot_to_scoreboard(bot_name, bot_label, team)
    if IS_HOST then
        users[bot_name] = {
            goals = 0,
            nickname = bot_label,
            assists = 0,
            team = math.floor(team),
            is_bot = true
        }
        run_network_function(name, "update_users_score_ALL", { users })
    end
    if IS_HOST then bot_slots_changed() end
end

-- Remove user from scoreboard
function remove_user_from_scoreboard(steam_id)
    if IS_HOST then
        local was_bot = users[steam_id] ~= nil and users[steam_id].is_bot
        users[steam_id] = nil
        if was_bot then bot_slots_changed() end
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
    local scorer_nick = users[last_touching_steam_id].nickname

    if (user_team == 1 and scoring_team == 2) or
        (user_team == 2 and scoring_team == 1) then
        is_own_goal = true
    end

    if is_own_goal then
        show_goal_banner("{own_goal_title}", string.format(translate("{own_goal_by}"), scorer_nick), "",
            TEAM_COLORS[scoring_team])
        own_goal_scores(last_touching_steam_id)
        if last_touching_steam_id == LOCAL_STEAM_ID then unlock_achievement("FB_OWN_GOAL") end
    else
        local assist_id = nil
        if previous_touching_steam_id and users[previous_touching_steam_id] and users[last_touching_steam_id] then
            if previous_touching_steam_id ~= last_touching_steam_id then
                if users[previous_touching_steam_id].team == users[last_touching_steam_id].team then
                    assist_id = previous_touching_steam_id
                end
            end
        end

        local assist_line = ""
        if assist_id then
            assist_line = string.format(translate("{goal_assist}"), users[assist_id].nickname)
        end
        show_goal_banner("{goal_title}", scorer_nick, assist_line, TEAM_COLORS[scoring_team])

        addition_scores(last_touching_steam_id, assist_id)
        if last_touching_steam_id == LOCAL_STEAM_ID then
            add_achievement_progress("fb_goals", 1)
            my_match_goals = my_match_goals + 1
            if my_match_goals == 3 then unlock_achievement("FB_HAT_TRICK") end
        end
        if assist_id == LOCAL_STEAM_ID then add_achievement_progress("fb_assists", 1) end
    end
    -- Update team score
    if IS_HOST then
        update_team_score(scoring_team)
    end

    run_function(name, "hide_goal_message", {}, GOAL_SHOW_SECONDS)
end

-- Local on every peer (handle_goal_ui_ALL runs everywhere), so each player's language is used.
function show_goal_banner(title, scorer_line, assist_line, color)
    set_label({ name = GOAL_TITLE, text = title, visible = true,
        anchor_left = 0.05, anchor_right = 0.95, anchor_top = 0.16, anchor_bottom = 0.34,
        horizontal_alignment = 1, vertical_alignment = 1,
        font_size = 96, font_color = color, outline_size = 22, outline_color = TEXT_OUTLINE,
        rotation = -0.05, scale = GOAL_POP[1] })
    set_label({ name = GOAL_SCORER, text = scorer_line, visible = true,
        anchor_left = 0.1, anchor_right = 0.9, anchor_top = 0.33, anchor_bottom = 0.41,
        horizontal_alignment = 1, vertical_alignment = 1,
        font_size = 40, font_color = Color(1, 1, 1, 1), outline_size = 12, outline_color = TEXT_OUTLINE })
    set_label({ name = GOAL_ASSIST, text = assist_line, visible = assist_line ~= "",
        anchor_left = 0.1, anchor_right = 0.9, anchor_top = 0.405, anchor_bottom = 0.455,
        horizontal_alignment = 1, vertical_alignment = 1,
        font_size = 24, font_color = Color(0.9, 0.88, 1, 1), outline_size = 8, outline_color = TEXT_OUTLINE })
    for i = 2, #GOAL_POP do
        run_function(name, "goal_pop_step", { i }, (i - 1) * GOAL_POP_STEP)
    end
end

function goal_pop_step(i)
    set_label({ name = GOAL_TITLE, scale = GOAL_POP[math.floor(i)] })
end

function hide_goal_message()
    for _, label in ipairs({ GOAL_TITLE, GOAL_SCORER, GOAL_ASSIST }) do
        set_value("", label, "visible", false)
    end
end

-- Change user team
function move_team(steam_id, team)
    if not IS_HOST then return end
    if users[steam_id] then
        users[steam_id].team = team
        run_network_function(name, "update_users_score_ALL", { users })
        if users[steam_id].is_bot then bot_slots_changed() end
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
            title ="{scoreboard}",
            resizable = true,
            is_scrollable = true,
            name = SCORE_PANEL_NAME,
            no_multiple_tag = "football_scoreboard",
            minimum_size = Vector2(300, 400) --default is Vector2(300,150)
        }
        SCORE_PANEL_NAME = create_panel(settings)
    end

    if panel_exists == false then
        if is_admin(LOCAL_STEAM_ID) then
            add_button_to_panel(SCORE_PANEL_NAME, {
                text ="{start_match}",
                entity_name = name,
                function_name = "show_match_settings_panel",
                is_vertical = true,
                icon_path = "forward",
                color = Color(0, 1, 0) -- Green color
            })
        else
            add_button_to_panel(SCORE_PANEL_NAME, {
                text ="{vote_start_match}",
                entity_name = name,
                function_name = "vote_start",
                is_vertical = true,
                icon_path = "forward",
                color = Color(0, 1, 0)
            })
        end
        if IS_HOST then
            add_button_to_panel(SCORE_PANEL_NAME, {
                text ="{bot_management}",
                entity_name = "-bot_manager",
                function_name = "show_bot_panel",
                is_vertical = true,
                color = Color(0.2, 0.55, 0.9)
            })
        end
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
        title ="{match_settings}",
        name = "football_match_settings_panel_id",
        no_multiple_tag = "football_match_settings", -- Prevent multiple panels
        resizable = false
    }

    local panel_name = create_panel(panel_config)

    add_button_to_panel(panel_name, {
        text ="{start_match}",
        entity_name = name,
        function_name = "match_countdown",
        is_vertical = true,
        color = Color(0, 1, 0) -- Green color
    })

    add_optionbox_to_panel(panel_name, {
        text ="{time_limit}",
        options = { 1, 2, 5, 10, 15, 20, 30, 60, 90, "∞" }, --"∞" means infinite
        entity_name = name,
    })
end

function match_countdown(args)
    -- Panel values are keyed by the widget's RAW text, which is the token itself.
    -- Through the host, so an admin who is not the host (a server owner) can use it.
    run_network_function(name, "request_match_start_HOST", { args["{time_limit}"] })
    close_panel(args.panel_name)
end

function request_match_start_HOST(sender_id, time_limit)
    if not IS_HOST or not is_admin(sender_id) then return end
    begin_match(time_limit)
end

function begin_match(time_limit)
    stop_timer("football_auto_start")
    votes = {}
    match_state = "countdown"
    run_network_function(name, "start_match_countdown_ALL", { time_limit })
end

-- Players without an admin around: a vote, or a match that starts by itself.
function vote_start(args)
    run_network_function(name, "vote_start_HOST", {})
    if args ~= nil and args.panel_name ~= nil then
        close_panel(args.panel_name)
    end
end

function cmd_start(sender_id)
    vote_start(nil)
end

local function admin_present()
    for id, data in pairs(users) do
        if not data.is_bot and is_admin(id) then return true end
    end
    return false
end

local function humans_on_teams()
    local n = 0
    for _, data in pairs(users) do
        local t = math.floor(tonumber(data.team) or 0)
        if not data.is_bot and (t == 1 or t == 2) then n = n + 1 end
    end
    return n
end

function vote_start_HOST(sender_id)
    if not IS_HOST or match_state ~= "idle" or users[sender_id] == nil then return end
    if is_admin(sender_id) then
        begin_match(DEFAULT_TIME_LIMIT)
        return
    end
    votes[sender_id] = true
    local voters, have = 0, 0
    for id, data in pairs(users) do
        if not data.is_bot then
            voters = voters + 1
            if votes[id] then have = have + 1 end
        end
    end
    local needed = math.floor(voters / 2) + 1
    add_to_chat((users[sender_id].nickname or "") .. "{voted_to_start}" .. have .. "/" .. needed, true)
    if have >= needed then
        begin_match(DEFAULT_TIME_LIMIT)
    end
end

-- Called whenever the teams change or a match ends. Starts (or cancels) the
-- warning timer; cheap enough to call on every such event.
function check_auto_start()
    if not IS_HOST then return end
    local ready = match_state == "idle" and not admin_present() and humans_on_teams() >= 2
    local data = get_timer_data("football_auto_start")
    local running = data ~= nil and data.is_running == true
    if ready and not running then
        add_to_chat("{match_auto_start_soon}", true)
        start_timer({
            timer_id = "football_auto_start",
            entity_name = name,
            function_name = "auto_start_fired",
            wait_time = AUTO_START_DELAY,
            duration = AUTO_START_DELAY,
        })
    elseif not ready and running then
        stop_timer("football_auto_start")
    end
end

function auto_start_fired(args)
    if args ~= nil and args.is_last_iteration == false then return end
    if match_state == "idle" and not admin_present() and humans_on_teams() >= 2 then
        begin_match(DEFAULT_TIME_LIMIT)
    end
end

function start_match_countdown_ALL(sender_id, time_limit)
    my_match_goals = 0
    set_label({
        name = "_center_label",
        text = "3",
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
    -- timer args cross from GDScript as floats, and so does any number sent back to a label:
    -- floor it and send it as text, or the label reads "2.0", "1.0"
    countdown = math.floor(3 - args.iteration_count)
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
        text = tostring(countdown),
        font_color = Color(1, 1, 1),
        visible = true
    })
end

function start_match(args)
    match_state = "running"
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
    match_state = "idle"
    -- The next match, when nobody is around to start it.
    check_auto_start()
end

function handle_game_over_ALL(sender_id, winner)
    set_audio({
        stream_path = "whistle",
        bus = "Effect",
        is_2d = false,
    })

    local message, color

    if winner == 2 then
        message = "{blue_team_won}"
        color = TEAM_COLORS[2]
    elseif winner == 1 then
        message = "{red_team_won}"
        color = TEAM_COLORS[1]
    else
        message = "{draw_result}"
        color = Color(1, 1, 1)
    end
    local me = users[LOCAL_STEAM_ID]
    if winner ~= 0 and me and me.team == winner then add_achievement_progress("fb_wins", 1) end
    my_match_goals = 0

    set_label({
        name = "_center_label",
        text = message,
        visible = true,
        font_color = color,
        outline_color = TEXT_OUTLINE,
        outline_size = 16
    })
end

function create_scoreboard_data()
    local table_data = {}

    -- Header row
    table_data[vector2_to_string(Vector2(0, 0))] = { text ="{user_2}", color = "#808080" }
    table_data[vector2_to_string(Vector2(1, 0))] = { text ="{team}", color = "#808080" }
    table_data[vector2_to_string(Vector2(2, 0))] = { text ="{goals}", color = "#808080" }
    table_data[vector2_to_string(Vector2(3, 0))] = { text ="{assists}", color = "#808080" }

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
        if data.team == 1 or data.team == 2 then
            color = TEAM_HEX[data.team]
        end

        table_data[vector2_to_string(Vector2(0, row))] = {
            text = data.nickname,
            color = color,
            steam_id = steam_id,
            is_bot = data.is_bot == true -- cell metadata: comes back on click
        }

        local team_name = "{spectator}"
        if data.team == 1 then
            team_name = "{bot_team_red}"
        elseif data.team == 2 then
            team_name = "{bot_team_blue}"
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
        run_function("-user_action_panel", "show_user_actions",
            { cell_data.steam_id, cell_data.text, cell_data.is_bot == true })
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



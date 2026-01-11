network_mode = 1
singleton_name = "finding_liar_manager"


-- Utility: convert table to string for debug
function table_to_string(t)
    if type(t) ~= "table" then return tostring(t) end
    local items = {}
    for i, v in ipairs(t) do
        table.insert(items, tostring(v))
    end
    return "[" .. table.concat(items, ", ") .. "]"
end


-- Game state variables
game_active = false
game_timer_duration = 300 -- 5 minutes in seconds
game_timer_remaining = 0
next_game_countdown = 0
countdown_active = false
initial_countdown = 0
initial_countdown_active = false
liar_blocked = false

-- User data (server-side only)
users = {} -- {steam_id = {name="", role="innocent/liar", is_alive=true}}
connected_users = {} -- List of connected user steam_ids

-- Game data
selected_word = ""
word_options = {} -- All words from all categories for display

-- Voting system
active_vote = nil -- {target_id="", initiator_id="", votes_yes=0, votes_no=0, voted_players={}}
vote_threshold = 0

-- Game settings
min_users = 3
game_time_limit = 300 -- 5 minutes

-- Auto-vote settings
auto_vote_timer_active = false
auto_vote_force_mode = nil -- nil = normal, true = force join, false = force skip
auto_vote_delay = 10.0 -- 10 seconds after player joins

-- Calculate number of liars based on user count
function calculate_liar_count(user_count)
    if user_count < 3 then
        return 0
    elseif user_count <= 6 then
        return 1
    elseif user_count <= 9 then
        return 2
    elseif user_count <= 12 then
        return 3
    else
        return math.floor(user_count / 3)
    end
end

-- Initialize game when enough users join
function initialize_game()
    
    if not IS_HOST or liar_blocked then 
        return 
    end
    
    local user_count = #connected_users
    
    if user_count < min_users then
        -- Stop initial countdown if active
        if initial_countdown_active then
            stop_initial_countdown()
        end
        return
    end
    
    -- If initial countdown is active, don't start game yet
    if initial_countdown_active then
        return
    end
    
    -- Reset game state
    game_active = true
    game_timer_remaining = game_time_limit
    users = {}
    active_vote = nil
    
    -- Stop auto-vote timer if active
    if auto_vote_timer_active then
        auto_vote_timer_active = false
        stop_timer("auto_vote_timer")
    end
    
    -- Update status display
    run_network_function(name, "update_finding_liar_status_ALL", {})
    
    -- Get all categories and collect all words
    local all_categories = run_function("-finding_liar_data", "get_all_categories", {})
    local all_words = {}
    
    -- Collect all words from all categories
    for _, category in ipairs(all_categories) do
        for _, word in ipairs(category.words) do
            table.insert(all_words, word)
        end
    end
    
    -- Shuffle all words randomly
    local shuffled_words = shuffle_table(all_words)
    
    -- Select 15 random words for display
    local display_words = {}
    for i = 1, math.min(15, #shuffled_words) do
        table.insert(display_words, shuffled_words[i])
    end
    
    -- Select random word from the display words
    local random_word_index = math.random(1, #display_words)
    selected_word = display_words[random_word_index]
    word_options = display_words -- Show only the 15 selected words as options
    
    -- Assign roles
    local liar_count = calculate_liar_count(user_count)
    local shuffled_users = shuffle_table(connected_users)
    
    for i, steam_id in ipairs(shuffled_users) do
        local nickname = get_value("", steam_id, "nickname") or "Unknown"
        users[steam_id] = {
            name = nickname,
            role = (i <= liar_count) and "liar" or "innocent",
            is_alive = true
        }
    end
    
    -- Calculate vote threshold (50% + 1) - integer
    vote_threshold = math.floor(user_count / 2) + 1
    
    -- Store data only in manager (server-side)
    -- word_options and selected_word are already stored in manager variables
    
    -- Get liar count based on user count
    local innocent_count = user_count - liar_count

    -- Send role-specific data to each client individually (secure)
    for steam_id, user_data in pairs(users) do
        if user_data.role == "innocent" then
            -- Send innocent info only to innocent users
            run_network_function(name, "start_game_CLIENT", {
                game_time_limit,
                "innocent",
                selected_word,
                word_options,
                liar_count,
                innocent_count
            }, steam_id)
        elseif user_data.role == "liar" then
            -- Send liar info only to liar users
            run_network_function(name, "start_game_CLIENT", {
                game_time_limit,
                "liar",
                "",  -- No correct word for liar
                word_options,
                liar_count,
                innocent_count
            }, steam_id)
        end
    end
    
    -- Start game timer
    start_timer({
        timer_id = "finding_liar_game_timer",
        entity_name = name,
        function_name = "update_game_timer",
        wait_time = 1.0,
        duration = game_time_limit
    })
end

-- Shuffle function for randomizing player roles
function shuffle_table(t)
    local shuffled = {}
    for i, v in ipairs(t) do
        shuffled[i] = v
    end
    
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    return shuffled
end

-- Network function to start game for specific client (secure - role-specific data)
function start_game_CLIENT(sender_id, time_limit, user_role, correct_word, word_options, liar_count, innocent_count)
    
    game_active = true
    game_timer_remaining = time_limit
    
    -- Show game UI with role info and counts
    run_function("-finding_liar_ui", "show_game_interface", {user_role, liar_count, innocent_count})
    
    -- Display role-specific information using received parameters
    if user_role == "innocent" then
        run_function("-finding_liar_ui", "show_innocent_info", {correct_word, word_options})
    elseif user_role == "liar" then
        run_function("-finding_liar_ui", "show_liar_info", {word_options})
    end
    
    add_to_chat("[color=#ff8066][b]Finding Liar game started![/b][/color]", false)
end

-- Handle liar word selection
function liar_select_word_HOST(sender_id, selected_word_guess)
    if not game_active then return end
    
    -- Verify sender is a liar
    if not users[sender_id] or users[sender_id].role ~= "liar" then
        return
    end
    
    -- Check if guess is correct
    local is_correct = (selected_word_guess == selected_word)
    
    if is_correct then
        -- Liar wins - send to all clients
        run_network_function(name, "end_game_ALL", {"liar", "The liar correctly guessed the word: " .. selected_word})
    else
        -- Liar loses - send to all clients
        run_network_function(name, "end_game_ALL", {"innocent", "The liar guessed wrong! The word was: " .. selected_word})
    end
end

-- Handle voting initiation
function initiate_vote_HOST(sender_id, target_steam_id)
    if not game_active or active_vote then return end
    
    -- Verify sender and target are valid users
    if not users[sender_id] or not users[target_steam_id] then return end
    if not users[sender_id].is_alive or not users[target_steam_id].is_alive then return end
    if sender_id == target_steam_id then return end
    
    -- Initialize vote
    active_vote = {
        target_id = target_steam_id,
        initiator_id = sender_id,
        votes_yes = 1, -- Initiator automatically votes yes
        votes_no = 0,
        voted_users = {[sender_id] = true, [target_steam_id] = true} -- Target can't vote
    }
    
    local initiator_name = users[sender_id].name
    local target_name = users[target_steam_id].name
    
    -- Start vote timer (30 seconds)
    start_timer({
        timer_id = "finding_liar_vote_timer",
        entity_name = name,
        function_name = "end_vote_timeout",
        wait_time = 30.0,
        duration = 30.0
    })
    
    -- Send vote to all clients with different panels for target vs others
    for steam_id, _ in pairs(users) do
        if steam_id == target_steam_id then 
            -- Special panel for voted person (no voting buttons)
            run_network_function(name, "show_vote_target_CLIENT", {
                initiator_name,
                target_name,
                target_steam_id,
                vote_threshold,
                30 -- vote duration
            }, steam_id)
        else 
            -- Normal voting panel for others
            run_network_function(name, "show_vote_CLIENT", {
                initiator_name,
                target_name,
                target_steam_id,
                vote_threshold,
                30, -- vote duration
                sender_id -- initiator's Steam ID
            }, steam_id)
        end
    end
end

-- Network function to show voting interface
function show_vote_CLIENT(sender_id, initiator_name, target_name, target_id, votes_needed, vote_duration, initiator_steam_id)
    if not game_active then return end
    
    run_function("-finding_liar_ui", "show_vote_panel", {
        initiator_name,
        target_name,
        target_id,
        votes_needed,
        vote_duration,
        initiator_steam_id
    })
end

-- Network function to show voting interface for voted person (no buttons)
function show_vote_target_CLIENT(sender_id, initiator_name, target_name, target_id, votes_needed, vote_duration)
    if not game_active then return end
    
    run_function("-finding_liar_ui", "show_vote_target_panel", {
        initiator_name,
        target_name,
        target_id,
        votes_needed,
        vote_duration
    })
end

-- Handle vote submission
function submit_vote_HOST(sender_id, target_id, vote_yes)
    if not game_active or not active_vote then return end
    if active_vote.target_id ~= target_id then return end
    
    -- Check if sender is the target (voted person cannot vote)
    if sender_id == active_vote.target_id then return end
    
    -- Check if user already voted
    if active_vote.voted_users[sender_id] then return end
    
    -- Record vote
    active_vote.voted_users[sender_id] = true
    if vote_yes then
        active_vote.votes_yes = active_vote.votes_yes + 1
    else
        active_vote.votes_no = active_vote.votes_no + 1
    end
    
    -- Update vote progress on all clients
    for steam_id, _ in pairs(users) do
        if steam_id == active_vote.target_id then 
            -- Special update for voted person
            run_network_function("-finding_liar_ui", "update_vote_target_progress_CLIENT", {
                active_vote.votes_yes,
                active_vote.votes_no,
                vote_threshold
            }, steam_id)
        else 
            -- Normal update for others
            run_network_function("-finding_liar_ui", "update_vote_progress_CLIENT", {
                active_vote.votes_yes,
                active_vote.votes_no,
                vote_threshold
            }, steam_id)
        end
    end
    
    -- Check if vote is complete
    local total_votes = active_vote.votes_yes + active_vote.votes_no
    local eligible_voters = count_alive_users() - 1 -- Exclude target
    
    if total_votes >= eligible_voters or active_vote.votes_yes >= vote_threshold then
        stop_timer("finding_liar_vote_timer")
        resolve_vote()
    end
end

-- End vote due to timeout
function end_vote_timeout(args)
    if not active_vote then return end
    
    add_to_chat("[color=#ffaa44][b]Vote timed out! No elimination.[/b][/color]", true)
    
    -- Close vote panels on all clients
    run_network_function(name, "close_vote_panel_ALL", {})
    
    active_vote = nil
end

-- Resolve voting results
function resolve_vote()
    if not active_vote then return end
    
    local target_id = active_vote.target_id
    local target_name = users[target_id].name
    local passed = active_vote.votes_yes >= vote_threshold
    
    -- Close vote panels on all clients first
    run_network_function(name, "close_vote_panel_ALL", {})
    
    if passed then
        -- Vote passed - eliminate user
        users[target_id].is_alive = false
        
        local target_role = users[target_id].role
        if target_role == "liar" then
            -- Check if all liars are eliminated
            if count_alive_liars() == 0 then
                -- Send to all clients
                run_network_function(name, "end_game_ALL", {"innocent", "All liars have been eliminated!"})
            else
                run_network_function(name, "player_eliminated_ALL", {target_name, "liar", false})
            end
        else
            -- Innocent was eliminated - liars win
            run_network_function(name, "end_game_ALL", {"liar", "An innocent player was eliminated!"})
        end
    else
        -- Vote failed
        add_to_chat("[color=#ffaa44][b]Vote against " .. target_name .. " failed![/b][/color]", true)
    end
    
    active_vote = nil
end

-- Count alive users
function count_alive_users()
    local count = 0
    for _, user_data in pairs(users) do
        if user_data.is_alive then
            count = count + 1
        end
    end
    return count
end

-- Count alive liars
function count_alive_liars()
    local count = 0
    for _, user_data in pairs(users) do
        if user_data.is_alive and user_data.role == "liar" then
            count = count + 1
        end
    end
    return count
end

-- Timer update function
function update_game_timer(args)
    if not game_active then return end
    
    if args.is_last_iteration then
        -- Time's up - liars win
        run_network_function(name, "end_game_ALL", {"liar", "Time is up! The liars win!"})
        return
    end
    
    game_timer_remaining = args.duration - args.iteration_count
    run_network_function(name, "update_timer_ALL", {game_timer_remaining})
end

-- Network function to update timer on client
function update_timer_ALL(sender_id, time_remaining)
    game_timer_remaining = time_remaining
    run_function("-finding_liar_ui", "update_timer_display", {time_remaining})
end

-- Network function to handle user elimination
function player_eliminated_ALL(sender_id, user_name, role, game_over)
    add_to_chat("[color=#ff4444][b]" .. user_name .. " has been eliminated![/b][/color]", false)
    if not game_over then
        run_function("-finding_liar_ui", "refresh_user_list", {})
    end
end

-- End game
function end_game_ALL(sender_id, winner, reason)
    game_active = false
    
    if IS_HOST then
        stop_timer("finding_liar_game_timer")
    end
    
    add_to_chat("[color=#66ff66][b]Game Over! " .. winner .. " wins![/b][/color]", false)
    add_to_chat("[color=#aaaaaa]" .. reason .. "[/color]", false)
    
    run_function("-finding_liar_ui", "show_game_over", {winner, reason})
    
    -- Close game after a delay
    if IS_HOST then
    start_timer({
        timer_id = "close_game_delay",
        entity_name = name,
        function_name = "close_game_delayed",
            wait_time = 11.0,
            duration = 11.0
    })
    end
    
    -- Update status display
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- Close game with delay
function close_game_delayed()
    run_network_function(name, "close_game_ALL", {})
end

-- Network function to close game
function close_game_ALL(sender_id)
    game_active = false
    run_function("-finding_liar_ui", "close_game_interface", {})
    
    -- Start next game countdown
    if IS_HOST then
        start_next_game_countdown()
    end
    
    -- Update status display
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- Network function to close vote panel on client
function close_vote_panel_ALL(sender_id)
    run_function("-finding_liar_ui", "close_vote_panel", {})
end

-- Start next game countdown
function start_next_game_countdown()
    if not IS_HOST then return end
    
    -- Check if there are enough users before starting countdown
    if #connected_users < min_users then
        return
    end
    
    countdown_active = true
    next_game_countdown = 10
    
    -- Show countdown UI to all clients
    run_network_function(name, "show_next_game_countdown_ALL", {next_game_countdown})
    
    -- Start countdown timer
    start_timer({
        timer_id = "next_game_countdown_timer",
        entity_name = name,
        function_name = "update_next_game_countdown",
        wait_time = 1.0,
        duration = 10.0
    })
    
    -- Update status display
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- Update next game countdown
function update_next_game_countdown()
    if not IS_HOST or not countdown_active then return end
    
    next_game_countdown = next_game_countdown - 1
    
    -- Check if still enough users during countdown
    if #connected_users < min_users then
        countdown_active = false
        -- Status will be updated by hide_next_game_countdown_ALL
        return
    end
    
    if next_game_countdown > 0 then
        -- Update countdown display for all clients
        run_network_function(name, "update_next_game_countdown_ALL", {next_game_countdown})
    else
        -- Countdown finished, start new game
        countdown_active = false
        -- Status will be updated by hide_next_game_countdown_ALL
        
        -- Small delay before starting new game
        start_timer({
            timer_id = "start_new_game_delay",
            entity_name = name,
            function_name = "initialize_game",
            wait_time = 1.0,
            duration = 1.0
        })
    end
end

-- Network function to show next game countdown
function show_next_game_countdown_ALL(sender_id, countdown_time)
    countdown_active = true
    next_game_countdown = countdown_time
    
    run_function("-finding_liar_ui", "show_next_game_countdown", {countdown_time})
end

-- Network function to update next game countdown
function update_next_game_countdown_ALL(sender_id, countdown_time)
    next_game_countdown = countdown_time
    
    run_function("-finding_liar_ui", "update_next_game_countdown", {countdown_time})
end

-- Network function to hide next game countdown
function hide_next_game_countdown_ALL(sender_id)
    countdown_active = false
    next_game_countdown = 0
    
    -- Update status display after hiding countdown
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- Start initial countdown when enough users join
function start_initial_countdown()
    if not IS_HOST then return end
    
    initial_countdown_active = true
    initial_countdown = 10
    
    -- Stop auto-vote timer if active
    if auto_vote_timer_active then
        auto_vote_timer_active = false
        stop_timer("auto_vote_timer")
    end
    
    -- Show countdown UI to all clients
    run_network_function(name, "show_initial_countdown_ALL", {initial_countdown})
    
    -- Start countdown timer
    start_timer({
        timer_id = "initial_countdown_timer",
        entity_name = name,
        function_name = "update_initial_countdown",
        wait_time = 1.0,
        duration = 10.0
    })
    
    -- Update status display
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- Update initial countdown
function update_initial_countdown()
    if not IS_HOST or not initial_countdown_active then return end
    
    initial_countdown = initial_countdown - 1
    
    -- Check if still enough users
    if #connected_users < min_users then
        stop_initial_countdown()
        return
    end
    
    if initial_countdown > 0 then
        -- Update countdown display for all clients
        run_network_function(name, "update_initial_countdown_ALL", {initial_countdown})
    else
        -- Countdown finished, start game
        initial_countdown_active = false
        -- Status will be updated by hide_initial_countdown_ALL
        
        -- Start game immediately
        initialize_game()
    end
end

-- Stop initial countdown
function stop_initial_countdown()
    if not IS_HOST then return end
    
    initial_countdown_active = false
    initial_countdown = 0
    
    -- Stop timer
    stop_timer("initial_countdown_timer")
    
    -- Status will be updated by hide_initial_countdown_ALL
end

-- Network function to show initial countdown
function show_initial_countdown_ALL(sender_id, countdown_time)
    initial_countdown_active = true
    initial_countdown = countdown_time
    
    run_function("-finding_liar_ui", "show_initial_countdown", {countdown_time})
end

-- Network function to update initial countdown
function update_initial_countdown_ALL(sender_id, countdown_time)
    initial_countdown = countdown_time
    
    run_function("-finding_liar_ui", "update_initial_countdown", {countdown_time})
end

-- Network function to hide initial countdown
function hide_initial_countdown_ALL(sender_id)
    initial_countdown_active = false
    initial_countdown = 0
    
    -- Update status display after hiding countdown
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- HOST function to provide user data for UI updates
function get_user_data_for_ui_HOST(sender_id)
    
    -- Get requester's role from users table
    local requester_role = "spectator"
    if users[sender_id] then
        requester_role = users[sender_id].role
    end
    
    -- Separate game participants from spectators
    local game_participants = {}
    local spectators = {}
    local alive_count = 0
    
    -- Use cached users instead of get_entity_names_by_tag to avoid mixing with late joiners
    for steam_id, user_data in pairs(users) do
        local nickname = user_data.name
        
        -- User is in the game
        table.insert(game_participants, {
            steam_id = steam_id, 
            nickname = nickname, 
            is_alive = user_data.is_alive
        })
        if user_data.is_alive then
            alive_count = alive_count + 1
        end
    end
    
    -- Get spectators (users not in the game)
    local all_connected_users = get_entity_names_by_tag("user")
    
    for _, user_entity_name in ipairs(all_connected_users) do
        local steam_id = user_entity_name
        local nickname = get_value("", steam_id, "nickname") or "Unknown"
        
        if not users[steam_id] then
            -- User is spectating
            table.insert(spectators, {steam_id = steam_id, nickname = nickname})
        end
    end
    
    -- Send data back to requesting client
    run_network_function("-finding_liar_ui", "update_user_list_CLIENT", {
        game_participants,
        spectators,
        requester_role,
        alive_count,
        #game_participants
    }, sender_id)
end

-- HOST function to check user role and allow/deny actions
function check_user_role_for_action_HOST(sender_id, action_type, args)
    
    -- Get sender's role from users table
    local sender_role = "spectator"
    if users[sender_id] then
        sender_role = users[sender_id].role
    end
    
    if action_type == "word_click" then
        -- Only liars can click words
        if sender_role == "liar" then
            run_network_function("-finding_liar_ui", "process_word_click_CLIENT", {args}, sender_id)
        end
    elseif action_type == "vote_click" then
        -- Only innocent users can vote
        if sender_role == "innocent" then
            run_network_function("-finding_liar_ui", "process_vote_click_CLIENT", {args}, sender_id)
        end
    end
end



function _on_user_disconnected(steam_id, nickname)
    add_to_chat(nickname.. " disconnected.", false)
    -- Remove from connected users
    for i, id in ipairs(connected_users) do
        if id == steam_id then
            table.remove(connected_users, i)
            break
        end
    end
    
    -- If game is active and too few users remain
    if game_active and #connected_users < min_users then
        if IS_HOST then
            run_network_function(name, "end_game_ALL", {"none", "Not enough users remaining!"})
        end
    end
    
    -- If initial countdown is active and not enough users remain
    if initial_countdown_active and #connected_users < min_users then
        if IS_HOST then
            stop_initial_countdown()
        end
    end
    
    -- If next game countdown is active and not enough users remain
    if countdown_active and #connected_users < min_users then
        if IS_HOST then
            countdown_active = false
            stop_timer("next_game_countdown_timer")
            -- Status will be updated by hide_next_game_countdown_ALL
        end
    end
    
    -- Update status display for all clients
    if IS_HOST then
        run_network_function(name, "update_finding_liar_status_ALL", {})
    end
end

-- Utility function to check if table contains value
function table_contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

function _on_user_connected(steam_id, nickname)
    add_to_chat(nickname.. " connected.", false)
    
    -- Update status display for all clients
    if IS_HOST then
        run_network_function(name, "update_finding_liar_status_ALL", {})
    end
end

-- Initialize connected users on script load
function _on_user_initialized(steam_id, nickname)
    -- Ensure user is in connected_users list
    add_to_chat(nickname.. " joined.", false)
    if not table_contains(connected_users, steam_id) then
        table.insert(connected_users, steam_id)
    end
    
    -- Check position-based game start logic
    
    if IS_HOST and #connected_users >= min_users and not game_active and not initial_countdown_active and not countdown_active then
        check_position_based_game_start()
    end
    
    -- Start auto-vote timer if more than 3 players and no game active
    if IS_HOST and #connected_users > 3 and not game_active and not initial_countdown_active and not countdown_active then
        start_auto_vote_timer()
    end
    
    -- Update status display for all clients
    if IS_HOST then
        run_network_function(name, "update_finding_liar_status_ALL", {})
    end
end

-- Check if we should start game based on positions
function check_position_based_game_start()
    -- Ensure caches are up-to-date, get table result
    local pos = run_function("-liar_position_detector", "refresh_cached_positions", {})
    local players_above = (pos and pos.players_above) or {}
    local players_below = (pos and pos.players_below) or {}


    -- Handle nil values (safety check)
    if not players_above then players_above = {} end
    if not players_below then players_below = {} end


    local total_above = #players_above
    local total_below = #players_below
    local total_players = total_above + total_below
    -- If less than 3 total players, can't start
    if total_players < 3 then

        return
    end
    
    -- If 3+ players above line, start with only those players
    if total_above >= 3 and total_below == 0 then
        add_to_chat("[color=#66ff66][b]Position Detector:[/b] Auto-starting Finding Liar with " .. total_above .. " players above the line.[/color]", false)
        start_game_with_specific_users(players_above)
        return
    end


    run_function("-liar_position_detector", "start_voting_for_below_players", {players_below})
    
    -- Update status to show voting in progress
    run_network_function(name, "update_finding_liar_status_ALL", {})
end

-- Utility function to get table size
function table_size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end 

function block_minigames(block)
    if not IS_HOST then return end
    liar_blocked = block and true or false
end

function interrupt_game()
    if not IS_HOST then return end
    if game_active then
        run_network_function(name, "end_game_ALL", {"none", "Golden Flag was touched! Minigame interrupted."})
        game_active = false
    end
end

-- Function to check if game is active (for position detector)
function is_game_active()
    return game_active or initial_countdown_active or countdown_active or liar_blocked
end

-- Function to start game with specific users (called by position detector)
function start_game_with_specific_users(user_steam_ids)
    if liar_blocked then return end
    
    -- Validate minimum users
    if #user_steam_ids < min_users then
        return
    end
    
    -- Don't start if game is already active
    if game_active or initial_countdown_active or countdown_active then
        return
    end
    
    -- Override connected_users with specific list for this game
    local original_connected_users = connected_users
    connected_users = {}
    
    -- Copy specific users to connected_users and validate they exist
    for _, steam_id in ipairs(user_steam_ids) do
        local nickname = get_value("", steam_id, "nickname")
        if nickname then -- User exists and is valid
            table.insert(connected_users, steam_id)
        end
    end
    
    -- Final validation - make sure we still have enough users
    if #connected_users >= min_users then
        add_to_chat("[color=#66ff66][b]Finding Liar:[/b] Starting game with " .. #connected_users .. " selected players.[/color]", false)
        initialize_game()
        
        -- Update status to show game started
        run_network_function(name, "update_finding_liar_status_ALL", {})
    else
        -- Restore original connected users if validation failed
        connected_users = original_connected_users
        add_to_chat("[color=#ff4444][b]Finding Liar:[/b] Not enough valid players for game.[/color]", false)
    end
end

-- Update Finding Liar status display for all clients
function update_finding_liar_status_ALL(sender_id)
    local status_text = "Minigame: Finding Liar\n"
    
    if game_active then
        status_text = status_text .. "Game in progress..."
    elseif initial_countdown_active then
        status_text = status_text .. "Starting in " .. initial_countdown .. "s"
    elseif countdown_active then
        status_text = status_text .. "Next game in " .. next_game_countdown .. "s"
    else
        -- Check if voting is active in position detector
        local voting_active = run_function("-liar_position_detector", "is_voting_active", {})
        
        if voting_active then
            status_text = status_text .. "Voting for below players...\n"
        elseif auto_vote_timer_active then
            -- Show auto-vote countdown
            local timer_data = get_timer_data("auto_vote_timer")
            local remaining_time = 0
            if timer_data and timer_data.duration and timer_data.iteration_count then
                remaining_time = math.max(0, timer_data.duration - timer_data.iteration_count)
            end
            
            local mode_text = ""
            if auto_vote_force_mode == true then
                mode_text = " (FORCED JOIN)"
            elseif auto_vote_force_mode == false then
                mode_text = " (FORCED SKIP)"
            end
            
            status_text = status_text .. "Auto-vote starting in " .. math.floor(remaining_time) .. "s" .. mode_text .. "\n"
            status_text = status_text .. "Connected: " .. #connected_users .. "/3"
        else
            -- Show current player counts and requirements
            local pos = run_function("-liar_position_detector", "refresh_cached_positions", {})
            local players_above = (pos and pos.players_above) or {}
            local players_below = (pos and pos.players_below) or {}
            
            status_text = status_text .. "Connected: " .. #connected_users .. "/3\n"
            status_text = status_text .. "Above line: " .. #players_above .. " | Below line: " .. #players_below
            
            if #connected_users >= 3 then
                if #players_above >= 3 and #players_below == 0 then
                    status_text = status_text .. "\nAuto-starting with above players..."
                elseif #players_above > 0 and #players_below > 0 then
                    if auto_vote_force_mode == true then
                        status_text = status_text .. "\nAuto-vote: FORCED JOIN (next game)"
                    elseif auto_vote_force_mode == false then
                        status_text = status_text .. "\nAuto-vote: FORCED SKIP (next game)"
                    else
                        status_text = status_text .. "\nAuto-vote will start in 10s after new player"
                    end
                end
            else
                status_text = status_text .. "\nWaiting for more players..."
            end
        end
    end
    

    run_function("-finding_liar_ui", "update_status_display", {status_text})
end

-- Start auto-vote timer for next voting session
function start_auto_vote_timer()
    if auto_vote_timer_active then return end
    
    auto_vote_timer_active = true
    local mode_text = ""
    if auto_vote_force_mode == true then
        mode_text = " (FORCED JOIN)"
    elseif auto_vote_force_mode == false then
        mode_text = " (FORCED SKIP)"
    end
    add_to_chat("[color=#ffaa44][b]Auto-vote:[/b] Starting in 10 seconds for players below the line..." .. mode_text .. "[/color]", false)
    
    start_timer({
        timer_id = "auto_vote_timer",
        entity_name = name,
        function_name = "execute_auto_vote",
        wait_time = auto_vote_delay,
        duration = auto_vote_delay
    })
end

-- Execute auto-vote after timer expires
function execute_auto_vote()
    if not auto_vote_timer_active then return end
    
    auto_vote_timer_active = false
    
    -- Check if conditions are still met
    if #connected_users > 3 and not game_active and not initial_countdown_active and not countdown_active then
        -- Get current positions and start voting
        local pos = run_function("-liar_position_detector", "refresh_cached_positions", {})
        local players_above = (pos and pos.players_above) or {}
        local players_below = (pos and pos.players_below) or {}
        
        if #players_above > 0 and #players_below > 0 then
            add_to_chat("[color=#66ff66][b]Auto-vote:[/b] Starting voting for below players...[/color]", false)
            run_function("-liar_position_detector", "start_voting_for_below_players", {players_below})
        end
    end
end

-- Test command function to control auto-voting
function set_auto_vote_force_mode(force_mode)
    if not IS_HOST then return end
    
    auto_vote_force_mode = force_mode
    local status_text = ""
    if force_mode == true then
        status_text = "FORCED JOIN - Below players will be forced to join next game"
    elseif force_mode == false then
        status_text = "FORCED SKIP - Below players will be forced to skip next game"
    else
        status_text = "NORMAL - Below players will vote normally"
    end
    add_to_chat("[color=#ff8066][b]Auto-vote:[/b] " .. status_text .. "[/color]", false)
    
    -- Update status display
    run_network_function(name, "update_finding_liar_status_ALL", {})
end


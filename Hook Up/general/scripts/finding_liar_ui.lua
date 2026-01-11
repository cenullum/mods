network_mode = 1
singleton_name = "finding_liar_ui"

-- Panel names
local MAIN_PANEL_NAME = "finding_liar_main"
local USERS_PANEL_NAME = "finding_liar_users"
local WORDS_PANEL_NAME = "finding_liar_words"
local VOTE_PANEL_NAME = "finding_liar_vote"
local GAME_OVER_PANEL_NAME = "finding_liar_game_over"

-- UI state (minimal - get data from manager via network calls)
local local_user_role = "spectator" -- Store user's role for timer display
local current_correct_word = "" -- Store correct word for innocent players

-- Vote panel state
local current_vote_info = {
    initiator_name = "",
    target_name = "",
    user_voted = false,
    user_vote_choice = "" -- "YES" or "NO"
}

-- Show main game interface
function show_game_interface(user_role, liar_count, innocent_count)
    
    -- Store user role for timer display
    local_user_role = user_role or "spectator"
    
    -- Update command system state to reflect UI is open
    run_function("-cmd", "set_liar_ui_state", {true})
    
    -- Don't create separate main panel - everything will be in users panel
    -- Just show combined users panel and words panel
    show_users_panel()
    show_words_panel()
end

-- Show users panel section
function show_users_panel()
    -- Users will be loaded when update_user_list_CLIENT is called
    -- No need to create panel here - it will be created when data arrives
    refresh_user_list()
end

-- Show words panel section
function show_words_panel()
    -- Close existing words panel if it exists
    if is_panel_exists(WORDS_PANEL_NAME) then
        close_panel(WORDS_PANEL_NAME)
    end
    
    -- Create separate words panel at center-right (slightly above players)
    local words_panel_config = {
        title = "Word Options",
        text = "Waiting for role assignment...",
        resizable = true,
        is_scrollable = true,
        minimum_size = Vector2(250, 450), -- Increased height for better visibility
        close = false,
        no_multiple_tag = "finding_liar_words",
        offset_ratio = Vector2(1.5, 0.6) -- Center-right, slightly above center
    }
    
    WORDS_PANEL_NAME = create_panel(words_panel_config)
    
    -- Words will be added based on player role
end

-- Display role-specific information for innocent users
function show_innocent_info(correct_word, all_words)
    
    -- Store role info and correct word for display
    local_user_role = "innocent"
    current_correct_word = correct_word
    
    -- Show all words with the correct word highlighted
    show_word_options_for_innocent(all_words, correct_word)
    
    -- No need to refresh - manager will call update_user_list_CLIENT
end

-- Display role-specific information for liar users  
function show_liar_info(word_options)
    
    -- Store role info for display
    local_user_role = "liar"
    
    -- Show clickable words for liar
    show_word_options_for_liar(word_options)
    
    -- No need to refresh - manager will call update_user_list_CLIENT
end

-- Refresh user list (gets data from manager via network function)
function refresh_user_list()
    -- Request user data from manager
    run_network_function("-finding_liar_manager", "get_user_data_for_ui_HOST", {})
end

-- Network function to receive user data from manager and update UI
function update_user_list_CLIENT(sender_id, game_participants, spectators, local_user_role, alive_count, game_count)
    
    -- Store the local user role globally
    local_user_role = local_user_role
    
    -- Determine if user can vote (only innocent players)
    local can_vote = (local_user_role == "innocent")
    local vote_instruction = ""
    if can_vote then
        vote_instruction = "\n\nClick to vote:"
    end
    
    -- Create role-specific header text
    local role_info = ""
    if local_user_role == "innocent" then
        local word_info = ""
        if current_correct_word ~= "" then
            word_info = "The selected word is: [b][color=#66ff66]" .. current_correct_word .. "[/color][/b]\n"
        end
        role_info = "You are innocent.\n" .. word_info .. "Find the liar by asking questions and voting!\nType !rules to see the rules.\n\n"
    elseif local_user_role == "liar" then
        role_info = "You are the liar.\nAsk questions to others.\nType !rules to see the rules.\n\n"
    elseif local_user_role == "spectator" then
        role_info = "You are spectating.\nType !rules to see the rules.\n\n"
    end
    
    local header_text = role_info .. "Game: " .. alive_count .. "/" .. game_count .. " alive | Spectators: " .. #spectators .. vote_instruction
    
    -- Always recreate the panel to avoid duplicate buttons
    if is_panel_exists(USERS_PANEL_NAME) then
        close_panel(USERS_PANEL_NAME)
    end
    
    -- Create new users panel
    local users_panel_config = {
        title = "Finding Liar - Game Info & Users",
        text = header_text,
        resizable = true,
        is_scrollable = true,
        minimum_size = Vector2(300, 400),
        close = false,
        no_multiple_tag = "finding_liar_users",
        offset_ratio = Vector2(1.5, 1) -- Center-right
    }
    
    USERS_PANEL_NAME = create_panel(users_panel_config)
    -- Add game participants first
    for _, participant in ipairs(game_participants) do
        local steam_id = participant.steam_id
        local nickname = participant.nickname  
        local is_alive = participant.is_alive
        
        local button_color = Color(0.7, 0.7, 0.7, 1) -- Light gray for active users
        local user_name = nickname
        local can_vote = true
        
        if LOCAL_STEAM_ID == steam_id then
            button_color = Color(0, 1, 0, 1) -- Green for local user
            user_name = user_name .. " (YOU)"
            can_vote = false -- Can't vote for yourself
        end
        
        -- Check if user is eliminated
        if not is_alive then
            button_color = Color(1, 0.3, 0.3, 1) -- Red for eliminated
            user_name = "✗ " .. user_name .. " (ELIMINATED)"
            can_vote = false
        end
        
        -- Add user button (only innocent users can vote, liars can see but not vote)
        if can_vote and local_user_role == "innocent" then
            add_button_to_panel(USERS_PANEL_NAME, {
                text = user_name,
                entity_name = "-finding_liar_ui",
                function_name = "on_user_clicked",
                extra_args = {target_steam_id = steam_id, target_name = nickname},
                color = button_color,
                is_vertical = true
            })
        else
            -- Show as non-clickable button (for liars, spectators, self, eliminated)
            add_button_to_panel(USERS_PANEL_NAME, {
                text = user_name,
                color = button_color,
                is_vertical = true
                -- No function handlers - makes it display-only
            })
        end
    end
    
    -- Add separator if there are both participants and spectators
    if #game_participants > 0 and #spectators > 0 then
        add_button_to_panel(USERS_PANEL_NAME, {
            text = "--- SPECTATORS ---",
            color = Color(0.5, 0.5, 0.5, 1),
            is_vertical = true
        })
    end
    
    -- Add spectators
    for _, spectator in ipairs(spectators) do
        local steam_id = spectator.steam_id
        local nickname = spectator.nickname
        
        local button_color = Color(0.4, 0.4, 0.4, 1) -- Dark gray for spectators
        local user_name = nickname .. " (SPECTATOR)"
        
        if LOCAL_STEAM_ID == steam_id then
            button_color = Color(0.6, 0.6, 0.6, 1) -- Slightly lighter gray for local spectator
            user_name = user_name .. " (YOU)"
        end
        
        -- Spectators are always non-clickable
        add_button_to_panel(USERS_PANEL_NAME, {
            text = user_name,
            color = button_color,
            is_vertical = true
        })
    end
end

-- Show word options for innocent players (with correct word highlighted)
function show_word_options_for_innocent(words, correct_word)
    if not is_panel_exists(WORDS_PANEL_NAME) then
        return -- Panel doesn't exist yet
    end
    
    -- Limit to 15 words for display
    local display_words = {}
    for i = 1, math.min(15, #words) do
        table.insert(display_words, words[i])
    end
    
    update_panel_settings(WORDS_PANEL_NAME, {
        text = "Word options from all categories:\n[color=#66ff66]The correct word: " .. correct_word .. "[/color]"
    })
    
    for i, word in ipairs(display_words) do
        local button_color = Color(0.9, 0.9, 0.9, 1) -- Light gray default
        local button_text = "• " .. word
        
        -- Highlight the correct word
        if word == correct_word then
            button_color = Color(0.4, 1, 0.4, 1) -- Light green for correct word
            button_text = "✓ " .. word .. " (CORRECT)"
        end
        
        add_button_to_panel(WORDS_PANEL_NAME, {
            text = button_text,
            color = button_color,
            is_vertical = true
            -- No function handlers - innocent players can see but not interact
        })
    end
end

-- Show word options for liar (clickable)
function show_word_options_for_liar(words)
    if not is_panel_exists(WORDS_PANEL_NAME) then
        return -- Panel doesn't exist yet
    end
    
    -- Limit to 15 words for display
    local display_words = {}
    for i = 1, math.min(15, #words) do
        table.insert(display_words, words[i])
    end
    
    update_panel_settings(WORDS_PANEL_NAME, {
        text = "Guess the correct word to win:\nClick to select"
    })
    
    for i, word in ipairs(display_words) do
        add_button_to_panel(WORDS_PANEL_NAME, {
            text = word,
            entity_name = "-finding_liar_ui",
            function_name = "on_word_clicked",
            extra_args = {word = word},
            color = Color(0.3, 0.5, 0.8, 1), -- Blue color
            is_vertical = true
        })
    end
end

-- Handle word click by liar
function on_word_clicked(args)
    -- Check role via manager before proceeding
    run_network_function("-finding_liar_manager", "check_user_role_for_action_HOST", {"word_click", args})
end
    
-- Called from manager if user is liar and can click words
function process_word_click_CLIENT(sender_id, args)
    local word = args.extra_args.word
    
    -- Show confirmation dialog
    local confirm_config = {
        title = "Confirm Word Selection",
        text = "You are about to choose this word: [b]" .. word .. "[/b]\n\nIf it's wrong, you'll lose. If it's correct, you'll win.\n\nAre you sure?",
        resizable = false,
        no_multiple_tag = "word_confirm"
    }
    
    local confirm_panel = create_panel(confirm_config)
    
    -- Add Continue button
    add_button_to_panel(confirm_panel, {
        text = "Continue",
        entity_name = "-finding_liar_ui",
        function_name = "confirm_word_selection",
        extra_args = {word = word},
        color = Color(0, 1, 0, 1), -- Green
        is_vertical = false
    })
    
    -- Add Cancel button
    add_button_to_panel(confirm_panel, {
        text = "Cancel",
        entity_name = "-finding_liar_ui", 
        function_name = "cancel_word_selection",
        color = Color(1, 0, 0, 1), -- Red
        is_vertical = false
    })
end

-- Confirm word selection
function confirm_word_selection(args)
    local word = args.extra_args.word
    local panel_name = args.panel_name
    
    close_panel(panel_name)
    
    -- Send word selection to host
    run_network_function("-finding_liar_manager", "liar_select_word_HOST", {word})
end

-- Cancel word selection
function cancel_word_selection(args)
    local panel_name = args.panel_name
    close_panel(panel_name)
end

-- Handle user click (for voting)
function on_user_clicked(args)
    local target_steam_id = args.extra_args.target_steam_id
    local target_name = args.extra_args.target_name
    
    -- Don't allow voting on self
    if target_steam_id == LOCAL_STEAM_ID then return end
    
    -- Check role via manager before proceeding
    run_network_function("-finding_liar_manager", "check_user_role_for_action_HOST", {"vote_click", args})
end

-- Called from manager if user is innocent and can vote
function process_vote_click_CLIENT(sender_id, args)
    local target_steam_id = args.extra_args.target_steam_id
    local target_name = args.extra_args.target_name
    
    -- Show voting confirmation with warning
    local vote_config = {
        title = "Confirm Vote",
        text = "Are you sure [b]" .. target_name .. "[/b] is the liar?\n\n[color=#ff6666][b]WARNING:[/b][/color] If you vote out an innocent player, the liars win!\n\nDo you want to start a vote?",
        resizable = false,
        no_multiple_tag = "vote_confirm"
    }
    
    local vote_panel = create_panel(vote_config)
    
    -- Add Confirm button
    add_button_to_panel(vote_panel, {
        text = "Confirm - Start Vote",
        entity_name = "-finding_liar_ui",
        function_name = "confirm_vote_initiation",
        extra_args = {target_steam_id = target_steam_id, target_name = target_name},
        color = Color(1, 0.5, 0, 1), -- Orange
        is_vertical = false
    })
    
    -- Add Cancel button
    add_button_to_panel(vote_panel, {
        text = "Cancel",
        entity_name = "-finding_liar_ui",
        function_name = "cancel_vote_initiation",
        color = Color(0.5, 0.5, 0.5, 1), -- Gray
        is_vertical = false
    })
end

-- Confirm vote initiation
function confirm_vote_initiation(args)
    local target_steam_id = args.extra_args.target_steam_id
    local target_name = args.extra_args.target_name
    local panel_name = args.panel_name
    
    close_panel(panel_name)
    
    -- Send vote initiation to host
    run_network_function("-finding_liar_manager", "initiate_vote_HOST", {target_steam_id})
end

-- Cancel vote initiation
function cancel_vote_initiation(args)
    local panel_name = args.panel_name
    close_panel(panel_name)
end

-- Show voting panel when a vote is active
function show_vote_panel(initiator_name, target_name, target_id, votes_needed, vote_duration, initiator_steam_id)
    -- Store vote info for updates and reset vote status
    current_vote_info.initiator_name = initiator_name
    current_vote_info.target_name = target_name
    current_vote_info.user_voted = false
    current_vote_info.user_vote_choice = ""
    
    -- Check if current user is the initiator
    local is_initiator = false
    if LOCAL_STEAM_ID == initiator_steam_id then
        is_initiator = true
        current_vote_info.user_voted = true
        current_vote_info.user_vote_choice = "YES"
    end
    
    -- Close any existing vote panel first
    if is_panel_exists(VOTE_PANEL_NAME) then
        close_panel(VOTE_PANEL_NAME)
    end
    
    -- Create vote panel with countdown at center screen
    local vote_status_text = ""
    if is_initiator then
        vote_status_text = "[b]Your vote:[/b] YES (initiator)"
    else
        vote_status_text = "[b]Your vote:[/b] You haven't voted yet"
    end
    
    local vote_config = {
        title = "VOTE IN PROGRESS",
        text = "[b]VOTING:[/b] " .. initiator_name .. " → " .. target_name .. "\n\n" ..
               "[b]Votes needed:[/b] " .. math.floor(votes_needed or 0) .. "\n" ..
               "[b]Current votes:[/b]\n" ..
               "[color=#66ff66]✅ YES: 1 (initiator)[/color]\n" ..
               "[color=#ff4444]❌ NO: 0[/color]\n\n" ..
               vote_status_text .. "\n\n" ..
               "[b]Question:[/b] Is " .. target_name .. " the liar?\n\n" ..
               "Vote YES to eliminate, NO to keep.",
        resizable = false,
        close = false, -- Disable close button during vote
        no_multiple_tag = "active_vote",
        countdown = vote_duration or 30, -- Default 30 seconds if not specified
        offset_ratio = Vector2(1, 1) -- Center screen
    }
    
    VOTE_PANEL_NAME = create_panel(vote_config)
    
    -- Only add voting buttons if user is not the initiator
    if not is_initiator then
    -- Add Yes button
    add_button_to_panel(VOTE_PANEL_NAME, {
        text = "YES - Eliminate " .. target_name,
        entity_name = "-finding_liar_ui",
        function_name = "submit_vote",
        extra_args = {target_id = target_id, vote_yes = true},
        color = Color(1, 0, 0, 1), -- Red
        is_vertical = false
    })
    
    -- Add No button
    add_button_to_panel(VOTE_PANEL_NAME, {
        text = "NO - Keep " .. target_name,
        entity_name = "-finding_liar_ui",
        function_name = "submit_vote",
        extra_args = {target_id = target_id, vote_yes = false},
        color = Color(0, 1, 0, 1), -- Green
        is_vertical = false
    })
    end
end

-- Submit vote
function submit_vote(args)
    -- Check if vote panel still exists (vote might have timed out)
    if not is_panel_exists(VOTE_PANEL_NAME) then
        -- Vote has ended, show message and return
        local message_config = {
            title = "Vote Ended",
            text = "The vote has already ended or timed out.",
            resizable = false,
            countdown = 3
        }
        create_panel(message_config)
        return
    end
    
    local target_id = args.extra_args.target_id
    local vote_yes = args.extra_args.vote_yes
    
    -- Send vote to host
    run_network_function("-finding_liar_manager", "submit_vote_HOST", {target_id, vote_yes})
    
    -- Track user's vote
    current_vote_info.user_voted = true
    current_vote_info.user_vote_choice = vote_yes and "YES" or "NO"
    
    -- Update panel immediately to show vote status
    update_vote_panel_with_user_status()
end

-- Close vote panel
function close_vote_panel()
    if is_panel_exists(VOTE_PANEL_NAME) then
        close_panel(VOTE_PANEL_NAME)
    end
    
    -- Clear vote info
    current_vote_info.initiator_name = ""
    current_vote_info.target_name = ""
    current_vote_info.user_voted = false
    current_vote_info.user_vote_choice = ""
end

-- Update vote progress in real-time
function update_vote_progress_CLIENT(sender_id, votes_yes, votes_no, votes_needed)
    if not is_panel_exists(VOTE_PANEL_NAME) then
        return -- Panel doesn't exist
    end
    
    -- Generate user vote status text
    local vote_status_text = ""
    if current_vote_info.user_voted then
        vote_status_text = "[b]Your vote:[/b] " .. current_vote_info.user_vote_choice
    else
        vote_status_text = "[b]Your vote:[/b] You haven't voted yet"
    end
    
    -- Use stored vote info for complete update
    local updated_text = string.format(
        "[b]VOTING:[/b] %s → %s\n\n" ..
        "[b]Votes needed:[/b] %d\n" ..
        "[b]Current votes:[/b]\n" ..
        "[color=#66ff66]✅ YES: %d[/color]\n" ..
        "[color=#ff4444]❌ NO: %d[/color]\n\n" ..
        "%s\n\n" ..
        "[b]Question:[/b] Is %s the liar?\n\n" ..
        "Vote YES to eliminate, NO to keep.",
        current_vote_info.initiator_name,
        current_vote_info.target_name,
        votes_needed,
        votes_yes,
        votes_no,
        vote_status_text,
        current_vote_info.target_name
    )
    
    -- Update panel text to show current vote progress
    update_panel_settings(VOTE_PANEL_NAME, {
        text = updated_text
    })
    
    -- Remove buttons if user has voted
    if current_vote_info.user_voted then
        update_vote_panel_without_buttons()
    end
end

-- Update panel to show user vote status immediately
function update_vote_panel_with_user_status()
    if not is_panel_exists(VOTE_PANEL_NAME) then
        return -- Panel doesn't exist
    end
    
    -- Generate user vote status text
    local vote_status_text = "[b]Your vote:[/b] " .. current_vote_info.user_vote_choice
    
    -- Basic update without vote counts (will be updated by server)
    local updated_text = string.format(
        "[b]VOTING:[/b] %s → %s\n\n" ..
        "[b]Votes needed:[/b] ?\n" ..
        "[b]Current votes:[/b]\n" ..
        "[color=#66ff66]✅ YES: ?[/color]\n" ..
        "[color=#ff4444]❌ NO: ?[/color]\n\n" ..
        "%s\n\n" ..
        "[b]Question:[/b] Is %s the liar?\n\n" ..
        "Waiting for vote update...",
        current_vote_info.initiator_name,
        current_vote_info.target_name,
        vote_status_text,
        current_vote_info.target_name
    )
    
    -- Update panel text
    update_panel_settings(VOTE_PANEL_NAME, {
        text = updated_text
    })
    
    -- Remove voting buttons since user has voted
    update_vote_panel_without_buttons()
end

-- Recreate vote panel without voting buttons
function update_vote_panel_without_buttons()
    if not is_panel_exists(VOTE_PANEL_NAME) then
        return
    end
    
    -- Panel text is already updated, just remove the buttons by recreating panel
    -- This is simpler than trying to remove specific buttons
    local current_text = "" -- Will be updated by next update_vote_progress_CLIENT call
    
    -- Just keep the panel as is - the buttons will become non-functional
    -- since user can't vote twice anyway due to server-side checking
end

-- Show voting panel for voted person (no voting buttons, just info)
function show_vote_target_panel(initiator_name, target_name, target_id, votes_needed, vote_duration)
    -- Store vote info for updates
    current_vote_info.initiator_name = initiator_name
    current_vote_info.target_name = target_name
    current_vote_info.user_voted = false -- Target doesn't vote
    current_vote_info.user_vote_choice = ""
    
    -- Close any existing vote panel first
    if is_panel_exists(VOTE_PANEL_NAME) then
        close_panel(VOTE_PANEL_NAME)
    end
    
    -- Create vote panel for target with warning message
    local vote_config = {
        title = "⚠️ YOU ARE BEING VOTED",
        text = "[b]WARNING:[/b] Players suspect you are the liar!\n\n" ..
               "[b]VOTING:[/b] " .. initiator_name .. " → " .. target_name .. "\n\n" ..
               "[b]Votes needed:[/b] " .. math.floor(votes_needed or 0) .. "\n" ..
               "[b]Current votes:[/b]\n" ..
               "[color=#66ff66]✅ YES: 1 (initiator)[/color]\n" ..
               "[color=#ff4444]❌ NO: 0[/color]\n\n" ..
               "[b]Your status:[/b] You cannot vote (you are the target)\n\n" ..
               "[b]Question:[/b] Is " .. target_name .. " the liar?\n\n" ..
               "Defend yourself in chat!",
        resizable = false,
        close = false, -- Disable close button during vote
        no_multiple_tag = "active_vote_target",
        countdown = vote_duration or 30, -- Default 30 seconds if not specified
        offset_ratio = Vector2(1, 1) -- Center screen
    }
    
    VOTE_PANEL_NAME = create_panel(vote_config)
    
    -- No voting buttons for target - they can only observe
end

-- Update vote progress for voted person (no voting options)
function update_vote_target_progress_CLIENT(sender_id, votes_yes, votes_no, votes_needed)
    if not is_panel_exists(VOTE_PANEL_NAME) then
        return -- Panel doesn't exist
    end
    
    -- Update with target-specific text
    local updated_text = string.format(
        "[b]WARNING:[/b] Players suspect you are the liar!\n\n" ..
        "[b]VOTING:[/b] %s → %s\n\n" ..
        "[b]Votes needed:[/b] %d\n" ..
        "[b]Current votes:[/b]\n" ..
        "[color=#66ff66]✅ YES: %d[/color]\n" ..
        "[color=#ff4444]❌ NO: %d[/color]\n\n" ..
        "[b]Your status:[/b] You cannot vote (you are the target)\n\n" ..
        "[b]Question:[/b] Is %s the liar?\n\n" ..
        "Defend yourself in chat!",
        current_vote_info.initiator_name,
        current_vote_info.target_name,
        votes_needed,
        votes_yes,
        votes_no,
        current_vote_info.target_name
    )
    
    -- Update panel text to show current vote progress
    update_panel_settings(VOTE_PANEL_NAME, {
        text = updated_text
    })
end

-- Update timer display
function update_timer_display(time_remaining)
    local minutes = math.floor(time_remaining / 60)
    local seconds = time_remaining % 60
    local time_text = string.format("%d:%02d", minutes, seconds)
    
    -- Add objective text based on user role
    local objective_text = ""
    if local_user_role == "liar" then
        objective_text = " - Find the word"
    elseif local_user_role == "innocent" then
        objective_text = " - Find the liar"
    else
        objective_text = " - Spectating"
    end
    
    local full_text = time_text .. objective_text
    
    -- Update timer label color based on remaining time
    local timer_color = Color(1, 0.8, 0, 1) -- Yellow default
    if time_remaining <= 60 then
        timer_color = Color(1, 0.3, 0.3, 1) -- Red for last minute
    elseif time_remaining <= 180 then
        timer_color = Color(1, 0.6, 0, 1) -- Orange for last 3 minutes
    end
    
    -- Update timer label
    set_label({
        name = "_finding_liar_timer",
        text = full_text,
        font_color = timer_color
    })
end

-- Show game over screen
function show_game_over(winner, reason)
    if is_panel_exists(GAME_OVER_PANEL_NAME) then
        close_panel(GAME_OVER_PANEL_NAME)
    end
    
    local winner_color = Color(0.5, 0.5, 0.5, 1) -- Gray default
    if winner == "innocent" then
        winner_color = Color(0, 1, 0, 1) -- Green for innocent win
    elseif winner == "liar" then
        winner_color = Color(1, 0, 0, 1) -- Red for liar win
    end
    

    local hex_color = string.format("#%02x%02x%02x", 
    math.floor(winner_color.r * 255), 
    math.floor(winner_color.g * 255), 
    math.floor(winner_color.b * 255))

    
    local game_over_config = {
        title = "GAME OVER",
        text = "[b][color=" .. hex_color .. "]" .. winner:upper() .. " WINS![/color][/b]\n\n" .. reason,
        resizable = false,
        countdown = 10, -- Auto-close after 10 seconds
        no_multiple_tag = "game_over"
    }
    
    GAME_OVER_PANEL_NAME = create_panel(game_over_config)
end

-- Close game interface
function close_game_interface()
    -- Hide view elements (only timer remains)

    
    -- Update command system state to reflect UI is closed
    run_function("-cmd", "set_liar_ui_state", {false})
    
    -- Close all finding liar related panels
    if is_panel_exists(USERS_PANEL_NAME) then
        close_panel(USERS_PANEL_NAME)
    end
    if is_panel_exists(WORDS_PANEL_NAME) then
        close_panel(WORDS_PANEL_NAME)
    end
    if is_panel_exists(VOTE_PANEL_NAME) then
        close_panel(VOTE_PANEL_NAME)
    end
    if is_panel_exists(GAME_OVER_PANEL_NAME) then
        close_panel(GAME_OVER_PANEL_NAME)
    end
    
    -- Clear vote info and state
    current_vote_info.initiator_name = ""
    current_vote_info.target_name = ""
    current_correct_word = ""
    local_user_role = "spectator"
end

-- Show next game countdown
function show_next_game_countdown(countdown_time)
    set_label({
        name = "_finding_liar_timer", 
        text = string.format("%d - Next mini game", countdown_time),
        font_color = Color(0, 0.8, 1, 1) -- Blue color for countdown
    })
end

-- Update next game countdown
function update_next_game_countdown(countdown_time)
    set_label({
        name = "_finding_liar_timer",
        text = string.format("%d - Next mini game", countdown_time),
        font_color = Color(0, 0.8, 1, 1) -- Blue color for countdown
    })
end

-- Hide next game countdown
function hide_next_game_countdown()
    -- Status will be updated by manager
end

-- Show initial countdown
function show_initial_countdown(countdown_time)
    set_label({
        name = "_finding_liar_timer",
        text = string.format("%d - Game starting", countdown_time),
        font_color = Color(0, 1, 0, 1) -- Green color for initial countdown
    })
end

-- Update initial countdown
function update_initial_countdown(countdown_time)
    set_label({
        name = "_finding_liar_timer",
        text = string.format("%d - Game starting", countdown_time),
        font_color = Color(0, 1, 0, 1) -- Green color for initial countdown
    })
end

-- Hide initial countdown
function hide_initial_countdown()
    -- Status will be updated by manager
end

-- Show participation vote to specific players (network function)
function show_participation_vote_to_players_CLIENT(sender_id, vote_duration)
    local vote_config = {
        title = "🎯 Join Finding Liar Game?",
        text = "[b]Do you want to join the Finding Liar game?[/b]\n\n" ..
               "[color=#ffaa44]Since you are below the red line, joining is optional.[/color]\n" ..
               "Each player decides for themselves!\n\n" ..
               "[color=#aaaaaa]Minimum 3 total players needed to start.[/color]",
        resizable = false,
        close = false,
        no_multiple_tag = "liar_participation_vote",
        countdown = vote_duration,
        offset_ratio = Vector2(1, 1) -- Center screen
    }
    
    local vote_panel = create_panel(vote_config)
    
    -- Add YES button
    add_button_to_panel(vote_panel, {
        text = "YES - Join Game",
        entity_name = "-finding_liar_ui",
        function_name = "submit_participation_vote",
        extra_args = {vote_yes = true},
        color = Color(0, 1, 0, 1), -- Green
        is_vertical = false
    })
    
    -- Add NO button
    add_button_to_panel(vote_panel, {
        text = "NO - Skip Game",
        entity_name = "-finding_liar_ui", 
        function_name = "submit_participation_vote",
        extra_args = {vote_yes = false},
        color = Color(1, 0, 0, 1), -- Red
        is_vertical = false
    })
end

-- Handle participation vote submission
function submit_participation_vote(args)
    local vote_yes = args.extra_args.vote_yes
    local panel_name = args.panel_name
    
    -- Close the voting panel
    close_panel(panel_name)
    
    -- Send vote to position detector via network function
    run_network_function("-liar_position_detector", "handle_participation_vote_HOST", {vote_yes})
end

-- Update status display (called by manager)
function update_status_display(status_text)
    set_label({
        name = "_finding_liar_timer",
        text = status_text,
    })
end

-- Network function to update status display on client
function update_status_display_CLIENT(sender_id, status_text)
    update_status_display(status_text)
end


-- Show voting info for above players (network function)
function show_voting_info_for_above_CLIENT(sender_id, vote_duration)
    local info_config = {
        title = "📊 Finding Liar - Voting in Progress",
        text = "[b]Players below the red line are voting to join the game.[/b]\n\n" ..
               "[color=#66ff66]You are above the line and will automatically join.[/color]\n\n" ..
               "[color=#ffaa44]Waiting for below players to decide...[/color]\n\n",
        resizable = false,
        close = true,
        no_multiple_tag = "voting_info_above",
        countdown = vote_duration,
        offset_ratio = Vector2(1, 0.5) -- Top center
    }
    
    create_panel(info_config)
end


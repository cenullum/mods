network_mode = 1
singleton_name = "liar_position_detector"
freeze = true

-- Visual setup - horizontal line indicator
image_name = set_image({
    parent_name = name, 
    image_path = "white_32",
    scale = Vector2(50000, 8),  -- Very wide horizontal, very thin vertical
    modulate = Color(1, 0, 0, 0.3),  -- Transparent red color
    z_index = 15
})

-- Game state variables
players_who_want_to_join = {}  -- Players who voted to join
voting_active = false
vote_timer_duration = 10.0

-- Cached player positions
cached_players_above = {}
cached_players_below = {}

-- Check player positions and return categorized lists (called by manager)
function refresh_cached_positions()
    local all_users = get_entity_names_by_tag("user")
    local players_above = {}
    local players_below = {}
    
    local detector_y = position.y
    
    -- Categorize players based on position
    for _, steam_id in ipairs(all_users) do
        local player_pos = get_value("", steam_id, "position")
        
        if player_pos.y < detector_y then
            -- Player is above the line
            table.insert(players_above, steam_id)
        else
            -- Player is below the line  
            table.insert(players_below, steam_id)
        end
    end
    cached_players_above = players_above
    cached_players_below = players_below
    
    return { players_above = cached_players_above, players_below = cached_players_below }
end


-- Start voting for below players (called by manager)
function start_voting_for_below_players(players_below)
    if voting_active then return end
    

    
    voting_active = true
    players_who_want_to_join = {}
    
    add_to_chat("[color=#ffaa44][b]Position Detector:[/b] Starting vote for players below the line to join Finding Liar game.[/color]", false)
    
    -- Send vote invitation to players below the line via UI manager using network function
    for _, steam_id in ipairs(cached_players_below) do
        run_network_function("-finding_liar_ui", "show_participation_vote_to_players_CLIENT", {
            vote_timer_duration
        }, steam_id)
    end
    
    -- Show message for above players about the voting process
    for _, steam_id in ipairs(cached_players_above) do
        run_network_function("-finding_liar_ui", "show_voting_info_for_above_CLIENT", {
            vote_timer_duration
        }, steam_id)
    end
    
    -- Start vote timer
    start_timer({
        timer_id = "participation_vote_timer",
        entity_name = name,
        function_name = "end_participation_vote",
        wait_time = vote_timer_duration,
        duration = vote_timer_duration
    })

end

-- Network function to handle participation vote from UI
function handle_participation_vote_HOST(sender_id, vote_yes)
    if not voting_active then return end
    
    -- Check if sender is actually below the line using cached data
    local is_below = false
    for _, steam_id in ipairs(cached_players_below) do
        if steam_id == sender_id then
            is_below = true
            break
        end
    end
    
    if not is_below then return end
    
    -- If player wants to join, add them to the list
    if vote_yes then
        -- Check if already added
        local already_added = false
        for _, steam_id in ipairs(players_who_want_to_join) do
            if steam_id == sender_id then
                already_added = true
                break
            end
        end
        
        if not already_added then
            table.insert(players_who_want_to_join, sender_id)
            local nickname = get_value("", sender_id, "nickname") or sender_id
            add_to_chat("[color=#66ff66]" .. nickname .. " wants to join the game![/color]", false)
        end
    end
end

-- End participation vote and determine result
function end_participation_vote()
    if not voting_active then return end
    
    voting_active = false
    
    -- Check if force mode is active
    local force_mode = get_value("", "-finding_liar_manager", "auto_vote_force_mode")
    
    -- Combine above players (mandatory) with below players who want to join
    local all_participants = {}
    
    -- Add all above players (mandatory) using cached data
    for _, steam_id in ipairs(cached_players_above) do
        table.insert(all_participants, steam_id)
    end
    
    -- Handle below players based on force mode
    local total_below_wanting = #players_who_want_to_join
    local total_below = #cached_players_below
    
    if force_mode == true then
        -- Force all below players to join
        for _, steam_id in ipairs(cached_players_below) do
            table.insert(all_participants, steam_id)
        end
        total_below_wanting = total_below
        add_to_chat("[color=#ffaa44][b]Position Detector:[/b] FORCED JOIN mode - All below players will join![/color]", false)
    elseif force_mode == false then
        -- Force all below players to skip
        total_below_wanting = 0
        add_to_chat("[color=#ffaa44][b]Position Detector:[/b] FORCED SKIP mode - All below players will skip![/color]", false)
    else
        -- Normal mode - add only below players who voted yes
        for _, steam_id in ipairs(players_who_want_to_join) do
            table.insert(all_participants, steam_id)
        end
    end
    
    -- Calculate total players correctly
    local total_players = #all_participants
    
    add_to_chat("[color=#ffaa44][b]Position Detector:[/b] Vote results - Above: " .. #cached_players_above .. ", Below wanting: " .. total_below_wanting .. "[/color]", false)
    

    
    if total_players >= 3 then
        add_to_chat("[color=#66ff66][b]Position Detector:[/b] Starting Finding Liar with " .. total_players .. " players.[/color]", false)
        run_function("-finding_liar_manager", "start_game_with_specific_users", {all_participants})
    else
        add_to_chat("[color=#ff4444][b]Position Detector:[/b] Not enough players to start (need 3, have " .. total_players .. ").[/color]", false)
    end
    
    -- Reset force mode after use (only affects one voting session)
    if force_mode ~= nil then
        run_function("-finding_liar_manager", "set_auto_vote_force_mode", {nil})
    end
    
    -- Reset vote state
    players_who_want_to_join = {}
end


-- Check if voting is currently active
function is_voting_active()
    return voting_active
end

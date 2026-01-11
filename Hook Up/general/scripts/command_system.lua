singleton_name = "cmd"

-- Register commands to the centralized system
add_command("-cmd", "show_finding_liar_rules", "rules", "Shows Finding Liar game rules and how to play", true)
add_command("-cmd", "toggle_liar_interface", "liar", "Toggle Finding Liar mini-game interface", true)
add_command("-cmd", "show_fishing_help", "fishing", "Shows fishing game controls and tips", true)
add_command("-cmd", "teleport_to_spawn_point", "spawn_point", "Teleport to spawn point and reset position/velocity",
    true)
add_command("-cmd", "change_spawn_point", "change_spawn_point",
    "[x:number] [y:number] (Host only) Change spawn point position ", true)
add_command("-cmd", "set_auto_vote_force_mode", "autovote",
    "[mode:boolean] (Host only) Force join/skip next game ", true)


-- Function to show Finding Liar game rules
function show_finding_liar_rules()
    local rules_text = "FINDING LIAR GAME RULES:\n\n"

    -- Basic objective
    rules_text = rules_text .. "OBJECTIVE:\n"
    rules_text = rules_text .. "• Innocent players: Find and eliminate all liars\n"
    rules_text = rules_text .. "• Liars: Survive or guess the correct word\n\n"

    -- How to play
    rules_text = rules_text .. "HOW TO PLAY:\n"
    rules_text = rules_text .. "• Everyone gets a category (e.g., 'Beach')\n"
    rules_text = rules_text .. "• Innocent players see the secret word\n"
    rules_text = rules_text .. "• Liars don't know the word - they must figure it out\n"
    rules_text = rules_text .. "• Ask questions to find suspicious behavior\n\n"

    -- Voting system
    rules_text = rules_text .. "VOTING SYSTEM:\n"
    rules_text = rules_text .. "• Click on a player to start a vote against them\n"
    rules_text = rules_text .. "• Everyone except the accused can vote\n"
    rules_text = rules_text .. "• Need 50% + 1 votes to eliminate someone\n"
    rules_text = rules_text .. "• If an innocent is eliminated, liars win!\n\n"

    -- Liar actions
    rules_text = rules_text .. "LIAR STRATEGY:\n"
    rules_text = rules_text .. "• Ask general questions about the category\n"
    rules_text = rules_text .. "• Try to blend in with innocent players\n"
    rules_text = rules_text .. "• When ready, click a word to guess\n"
    rules_text = rules_text .. "• Correct guess = Liar wins, Wrong guess = Innocent wins\n\n"

    -- Player counts
    rules_text = rules_text .. "LIAR COUNT BY PLAYERS:\n"
    rules_text = rules_text .. "• 3-6 players: 1 liar\n"
    rules_text = rules_text .. "• 7-9 players: 2 liars\n"
    rules_text = rules_text .. "• 10-12 players: 3 liars\n"
    rules_text = rules_text .. "• Every 3 additional players: +1 liar\n\n"

    -- Timer info
    rules_text = rules_text .. "TIME LIMIT:\n"
    rules_text = rules_text .. "• Games last 5 minutes\n"
    rules_text = rules_text .. "• If time runs out, liars win automatically\n\n"

    -- Tips
    rules_text = rules_text .. "TIPS:\n"
    rules_text = rules_text .. "• Good questions: 'What color is it?' 'How big is it?'\n"
    rules_text = rules_text .. "• Bad questions: 'Is it a beach ball?' (too specific)\n"
    rules_text = rules_text .. "• Watch for players who ask but never answer!\n"

    -- Create a message panel
    local message_config = {
        title = "Finding Liar - Game Rules",
        text = rules_text,
        resizable = true,
    }
    create_panel(message_config)
end

-- Function to show fishing game help
function show_fishing_help()
    local fishing_text = "FISHING GAME CONTROLS:\n\n"

    fishing_text = fishing_text .. "HOOK CONTROLS:\n"
    fishing_text = fishing_text .. "• Hold @key_7@ to charge hook power\n"
    fishing_text = fishing_text .. "• Release @key_7@ to fire hook\n"
    fishing_text = fishing_text .. "• Press @key_7@ while hooked to launch yourself\n"
    fishing_text = fishing_text .. "• Press @key_7@ during firing to cancel\n\n"

    fishing_text = fishing_text .. "FISHING MECHANICS:\n"
    fishing_text = fishing_text .. "• Hook onto fish to start fishing minigame\n"
    fishing_text = fishing_text .. "• Follow the traffic light signals\n"
    fishing_text = fishing_text .. "• Green = Reel in, Red = Stop\n"
    fishing_text = fishing_text .. "• Manage your health vs fish health\n\n"

    fishing_text = fishing_text .. "TIPS:\n"
    fishing_text = fishing_text .. "• Different fish have different difficulties\n"
    fishing_text = fishing_text .. "• Watch your hook power - higher power = further range\n"
    fishing_text = fishing_text .. "• Use platforms to get better fishing positions\n"
    fishing_text = fishing_text .. "• Some areas have better fish than others\n"

    local message_config = {
        title = "Fishing Game Help",
        text = fishing_text,
        resizable = true,

    }
    create_panel(message_config)
end

-- Global variable to track Finding Liar UI state
liar_ui_visible = false

-- Function to toggle Finding Liar interface
function toggle_liar_interface()
    liar_ui_visible = not liar_ui_visible

    -- Toggle visibility of Finding Liar timer (only remaining UI element)
    set_label({ name = "_finding_liar_timer", visible = liar_ui_visible })

    -- Show status message
    local status_text = ""
    if liar_ui_visible then
        status_text = "Finding Liar timer enabled"

        -- Update with default timer value when enabling
        set_label({ name = "_finding_liar_timer", text = "5:00" })
    else
        status_text = "Finding Liar timer disabled"
    end

    add_to_chat("[color=#ff8066][b]" .. status_text .. "[/b][/color]", false)
end

-- Function to set liar UI state (called from finding_liar_ui.lua)
function set_liar_ui_state(state)
    liar_ui_visible = state -- First argument is the boolean state
end

-- Command Wrapper functions
-- These are called locally by add_command and they trigger network functions

function teleport_to_spawn_point()
    run_network_function("-cmd", "teleport_to_spawn_point_HOST", {})
end

function change_spawn_point(x, y)
    run_network_function("-cmd", "change_spawn_point_ALL", { x, y })
end

function set_auto_vote_force_mode(mode)
    local force_mode = nil
    if mode == "true" then
        force_mode = true
    elseif mode == "false" then
        force_mode = false
    end
    run_function("-finding_liar_manager", "set_auto_vote_force_mode", { mode })
end

-- HOST function: Handle teleport to spawn point request
function teleport_to_spawn_point_HOST(sender_id)
    local spawn_position = get_value("", "-spawn_point", "position")

    change_instantly({
        entity_name = sender_id,
        angular_velocity = 0.0,
        position = spawn_position,
        linear_velocity = Vector2(0, 0),
        rotation = 0.0
    })
end

function change_spawn_point_ALL(sender_id, x, y)
    -- Validate parameters
    if not x or not y then
        add_to_chat("[color=#ff8066][b]Error: Missing parameters! Usage: /change_spawn_point x y[/b][/color]", false)
        return
    end

    -- Convert to numbers and validate
    local pos_x = tonumber(x)
    local pos_y = tonumber(y)

    if not pos_x or not pos_y then
        add_to_chat("[color=#ff8066][b]Error: Invalid parameters! x and y must be numbers[/b][/color]", false)
        return
    end

    -- Check for reasonable bounds (optional safety check)
    if pos_x < -10000 or pos_x > 10000 or pos_y < -10000 or pos_y > 10000 then
        add_to_chat(
            "[color=#ff8066][b]Error: Position values too extreme! Use values between -10000 and 10000[/b][/color]",
            false)
        return
    end

    -- Update spawn point position
    local new_position = Vector2(pos_x, pos_y)
    set_value("", "-spawn_point", "position", new_position)

    -- Confirm the change
    add_to_chat("[color=#66FF99][b]Spawn point updated to position (" .. pos_x .. ", " .. pos_y .. ")[/b][/color]", true)
end

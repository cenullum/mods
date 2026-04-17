singleton_name = "cmd"

add_command("-cmd", "show_finding_liar_rules", "rules", "Shows Finding Liar game rules and how to play", true)
add_command("-cmd", "toggle_liar_interface", "liar", "Toggle Finding Liar mini-game interface", true)


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


-- Global variable to track Finding Liar UI state
liar_ui_visible = false

-- Function to toggle Finding Liar interface
function toggle_liar_interface()
    liar_ui_visible = not liar_ui_visible

    -- Toggle visibility of Finding Liar timer
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



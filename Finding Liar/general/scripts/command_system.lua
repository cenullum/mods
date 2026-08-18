singleton_name = "cmd"

add_command("-cmd", "show_finding_liar_rules", "rules", "{shows_finding_liar_game_rules_and_how_to}", true)
add_command("-cmd", "toggle_liar_interface", "liar", "{toggle_finding_liar_mini_game_interface}", true)


-- Function to show Finding Liar game rules
function show_finding_liar_rules()
    local rules_text ="{finding_liar_game_rules}"

    -- Basic objective
    rules_text = rules_text .. "OBJECTIVE:\n"
    rules_text = rules_text .. "{innocent_players_find_and_eliminate_all}"
    rules_text = rules_text .. "{liars_survive_or_guess_the_correct_word}"

    -- How to play
    rules_text = rules_text .. "{how_to_play}"
    rules_text = rules_text .. "{everyone_gets_a_category_e_g_beach}"
    rules_text = rules_text .. "{innocent_players_see_the_secret_word}"
    rules_text = rules_text .. "{liars_don_t_know_the_word_they_must_figu}"
    rules_text = rules_text .. "{ask_questions_to_find_suspicious_behavio}"

    -- Voting system
    rules_text = rules_text .. "{voting_system}"
    rules_text = rules_text .. "{click_on_a_player_to_start_a_vote_agains}"
    rules_text = rules_text .. "{everyone_except_the_accused_can_vote}"
    rules_text = rules_text .. "{need_50_1_votes_to_eliminate_someone}"
    rules_text = rules_text .. "{if_an_innocent_is_eliminated_liars_win}"

    -- Liar actions
    rules_text = rules_text .. "{liar_strategy}"
    rules_text = rules_text .. "{ask_general_questions_about_the_category}"
    rules_text = rules_text .. "{try_to_blend_in_with_innocent_players}"
    rules_text = rules_text .. "{when_ready_click_a_word_to_guess}"
    rules_text = rules_text .. "{correct_guess_liar_wins_wrong_guess_inno}"

    -- Player counts
    rules_text = rules_text .. "{liar_count_by_players}"
    rules_text = rules_text .. "{3_6_players_1_liar}"
    rules_text = rules_text .. "{7_9_players_2_liars}"
    rules_text = rules_text .. "{10_12_players_3_liars}"
    rules_text = rules_text .. "{every_3_additional_players_1_liar}"

    -- Timer info
    rules_text = rules_text .. "{time_limit}"
    rules_text = rules_text .. "{games_last_5_minutes}"
    rules_text = rules_text .. "{if_time_runs_out_liars_win_automatically}"

    -- Tips
    rules_text = rules_text .. "TIPS:\n"
    rules_text = rules_text .. "{good_questions_what_color_is_it_how_big}"
    rules_text = rules_text .. "{bad_questions_is_it_a_beach_ball_too_spe}"
    rules_text = rules_text .. "{watch_for_players_who_ask_but_never_answ}"

    -- Create a message panel
    local message_config = {
        title ="{finding_liar_game_rules_2}",
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
        status_text ="{finding_liar_timer_enabled}"

        -- Update with default timer value when enabling
        set_label({ name = "_finding_liar_timer", text = "5:00" })
    else
        status_text ="{finding_liar_timer_disabled}"
    end

    add_to_chat("[color=#ff8066][b]" .. status_text .. "[/b][/color]", false)
end

-- Function to set liar UI state (called from finding_liar_ui.lua)
function set_liar_ui_state(state)
    liar_ui_visible = state -- First argument is the boolean state
end

-- Command Wrapper functions
-- These are called locally by add_command and they trigger network functions



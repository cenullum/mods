singleton_name = "dtw_cmd"

-- =============================================================================
-- Draw The Word - chat commands. Purely local UI; no game state lives here.
-- The rules text is one keyword per paragraph rather than one giant blob, so a
-- translator can work through it in readable chunks (and so a missing paragraph
-- falls back to English on its own instead of dropping the whole page).
-- =============================================================================

add_command("-dtw_cmd", "show_dtw_rules", "rules", "{cmd_rules_desc}", true)

function show_dtw_rules()
    local t = "[b]{rules_heading}[/b]\n\n"

    t = t .. "[b]{rules_goal_title}[/b]\n"
    t = t .. "{rules_goal}\n\n"

    t = t .. "[b]{rules_draw_title}[/b]\n"
    t = t .. "{rules_draw}\n\n"

    t = t .. "[b]{rules_guess_title}[/b]\n"
    t = t .. "{rules_guess}\n\n"

    t = t .. "[b]{rules_score_title}[/b]\n"
    t = t .. "{rules_score}\n\n"

    t = t .. "[b]{rules_report_title}[/b]\n"
    t = t .. "{rules_report}\n\n"

    t = t .. "[b]{rules_end_title}[/b]\n"
    t = t .. "{rules_end}\n"

    create_panel({
        title = "{rules_title}",
        text = t,
        resizable = true,
        is_scrollable = true,
        minimum_size = Vector2(420, 460),
    })
end

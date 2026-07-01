singleton_name = "dtw_cmd"

-- =============================================================================
-- Draw The Word - chat commands. Purely local UI; no game state lives here.
-- =============================================================================

add_command("-dtw_cmd", "show_dtw_rules", "rules", "Show how to play Draw The Word", true)

function show_dtw_rules()
    local t = "[b]DRAW THE WORD - HOW TO PLAY[/b]\n\n"

    t = t .. "[b]GOAL[/b]\n"
    t = t .. "Take turns drawing a secret word while everyone else races to guess it in chat.\n\n"

    t = t .. "[b]YOUR TURN TO DRAW[/b]\n"
    t = t .. "- You are offered two words; pick one within the time limit.\n"
    t = t .. "- You then have ~80 seconds to draw it on the shared board.\n"
    t = t .. "- You cannot type in chat while drawing.\n"
    t = t .. "- Optional: reveal hint letters - but each hint lowers the points\n"
    t = t .. "  everyone (including you) can earn that round.\n\n"

    t = t .. "[b]GUESSING[/b]\n"
    t = t .. "- Type your guess in chat. A correct guess is never shown as text:\n"
    t = t .. "  everyone just sees \"[name] guessed correctly\", so the word stays\n"
    t = t .. "  secret. A near-miss is whispered only to YOU (\"you guessed close\").\n"
    t = t .. "- Other messages still appear in chat, so you can talk and team up.\n"
    t = t .. "- Guess faster for more points. Once you are right, you sit out the\n"
    t = t .. "  rest of the round.\n\n"

    t = t .. "[b]SCORING[/b]\n"
    t = t .. "- Earlier correct guesses score higher; the drawer earns a bonus for\n"
    t = t .. "  every player who guesses the word.\n\n"

    t = t .. "[b]REPORTING[/b]\n"
    t = t .. "- Drawer not playing fair? Use the Report button (top-right). If more\n"
    t = t .. "  than half of the guessers report, that turn is skipped.\n\n"

    t = t .. "[b]END[/b]\n"
    t = t .. "- A round ends when time runs out or everyone has guessed. When every\n"
    t = t .. "  player has had a turn, the top 3 are shown on a podium.\n"

    create_panel({
        title = "Draw The Word - Rules",
        text = t,
        resizable = true,
        is_scrollable = true,
        minimum_size = Vector2(420, 460),
    })
end

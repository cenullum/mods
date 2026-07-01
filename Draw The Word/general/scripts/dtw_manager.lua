network_mode = 1
singleton_name = "dtw_manager"

-- =============================================================================
-- Draw The Word - host-authoritative game manager.
--
-- Flow per turn:
--   idle -> choosing (drawer picks 1 of 2 words) -> drawing (80s) ->
--   intermission (reveal word + scores) -> next turn ... -> gameover (podium).
--
-- This script instance runs on every peer. HOST-suffixed functions execute on
-- the host (clients route their intents there); ALL-suffixed functions execute
-- on every peer and keep the lightweight client mirror (cl_*) in sync so the
-- chat handler and HUD can react locally without leaking the secret word.
-- =============================================================================

-- The shared paintable board (a world-space Sprite2D created in world.lua).
-- Drawing on it is gated server-side via set_painter; only the drawer is allowed.
local IMAGE_NAME = "dtw_board"
local UI = "-dtw_ui"
local DATA = "-dtw_data"

-- Tunables
local MIN_PLAYERS = 2
local CHOOSE_TIME = 15
local DRAW_TIME = 80
local INTERMISSION_TIME = 6
local PODIUM_TIME = 14
local MAX_POINTS = 100
local MIN_POINTS = 25
local MAX_REVEAL_RATIO = 0.8
local DRAWER_BONUS_RATIO = 0.25

-- ---------- HOST authoritative state ----------
players = {}    -- steam_id -> { name, score, has_drawn }
order = {}      -- steam_ids in join order (used to rebuild the queue)
connected = {}  -- steam_ids currently in the lobby (ordered)
queue = {}      -- steam_ids still waiting to draw this game

phase = "idle"  -- idle | choosing | drawing | intermission | gameover
drawer_id = ""
secret_word = ""
word_choices = {}
participants = {}    -- steam_id -> true : eligible guessers this round (snapshot)
correct = {}         -- steam_id -> points awarded this round
correct_order = {}   -- steam_ids in order they guessed correctly
reports = {}         -- steam_id -> true : reporters of the current drawer
revealed = {}             -- glyph index -> true : letters revealed via hints
hint_structure_shown = false  -- true after first hint press (structure reveal)
revealed_count = 0
total_letters = 0
max_reveal = 0
drawer_round_bonus = 0
draw_time_left = DRAW_TIME

-- ---------- CLIENT mirror (every peer) ----------
cl_phase = "idle"
cl_drawer_id = ""
cl_correct = {}      -- steam_id -> true : who already guessed correctly

-- =============================================================================
-- Small helpers
-- =============================================================================
local function count_map(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function list_remove_value(list, value)
    for i, v in ipairs(list) do
        if v == value then
            table.remove(list, i)
            return true
        end
    end
    return false
end

local function list_contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- Sorted [{ steam_id, name, score, is_drawer, has_drawn }] for the scoreboard.
local function build_scoreboard()
    local arr = {}
    for steam_id, p in pairs(players) do
        table.insert(arr, {
            steam_id = steam_id,
            name = p.name,
            score = p.score,
            is_drawer = (steam_id == drawer_id),
            has_drawn = p.has_drawn,
        })
    end
    table.sort(arr, function(a, b) return a.score > b.score end)
    return arr
end

local function broadcast_scoreboard()
    run_network_function(name, "scoreboard_ALL", { build_scoreboard() })
end

-- =============================================================================
-- HOST: turn / round orchestration
-- =============================================================================

-- Rebuild the draw queue from everyone who has not drawn yet this game.
local function rebuild_queue()
    queue = {}
    for _, steam_id in ipairs(connected) do
        local p = players[steam_id]
        if p and not p.has_drawn then
            table.insert(queue, steam_id)
        end
    end
end

-- Try to begin the game when idle and enough players are present.
function maybe_start()
    if not IS_HOST then return end
    if phase ~= "idle" then return end
    if #connected < MIN_PLAYERS then
        set_painter(IMAGE_NAME, 0) -- keep the board locked while waiting
        return
    end
    rebuild_queue()
    start_next_turn()
end

-- Pop the next valid drawer and enter the word-choosing phase.
function start_next_turn()
    if not IS_HOST then return end
    if phase == "gameover" then return end

    -- Drop anyone who left while queued.
    while #queue > 0 and not players[queue[1]] do
        table.remove(queue, 1)
    end

    if #queue == 0 or #connected < MIN_PLAYERS then
        end_game()
        return
    end

    drawer_id = table.remove(queue, 1)
    phase = "choosing"
    secret_word = ""
    word_choices = run_function(DATA, "dtw_get_two_words", {})

    -- Lock the board and wipe it for the new round.
    clear_canvas(IMAGE_NAME)
    set_painter(IMAGE_NAME, 0)

    local drawer_name = players[drawer_id].name

    -- Announce the turn FIRST: turn_announce_ALL runs clear_round_ui() on every
    -- peer (wiping any leftover round panels). Only then offer the words, so the
    -- choice panel is not immediately closed by that cleanup on the drawer.
    run_network_function(name, "turn_announce_ALL", { drawer_id, drawer_name }, "")
    broadcast_scoreboard()
    -- Offer the two words to the drawer only.
    run_network_function(UI, "show_word_choice_CLIENT", { word_choices, CHOOSE_TIME }, drawer_id)

    -- Auto-skip if the drawer does not pick in time.
    start_timer({
        timer_id = "dtw_choose_timer",
        entity_name = name,
        function_name = "choose_timeout",
        wait_time = CHOOSE_TIME,
        duration = CHOOSE_TIME,
    })
end

function choose_timeout(args)
    if not IS_HOST then return end
    if phase ~= "choosing" then return end
    -- Drawer never chose: they forfeit this turn.
    local skipped_name = players[drawer_id] and players[drawer_id].name or "Player"
    if players[drawer_id] then players[drawer_id].has_drawn = true end
    run_network_function(name, "turn_skipped_ALL", { skipped_name, "did not pick a word" }, "")
    phase = "intermission"
    set_painter(IMAGE_NAME, 0)
    start_timer({
        timer_id = "dtw_intermission",
        entity_name = name,
        function_name = "after_intermission",
        wait_time = 2.0,
        duration = 2.0,
    })
end

-- HOST: the drawer picked one of the two offered words.
function choose_word_HOST(sender_id, word)
    if not IS_HOST then return end
    if phase ~= "choosing" or sender_id ~= drawer_id then return end
    if word ~= word_choices[1] and word ~= word_choices[2] then return end
    stop_timer("dtw_choose_timer")
    begin_round(word)
end

-- HOST: enter the drawing phase with the chosen word.
function begin_round(word)
    if not IS_HOST then return end

    phase = "drawing"
    secret_word = word
    correct = {}
    correct_order = {}
    reports = {}
    revealed = {}
    hint_structure_shown = false
    revealed_count = 0
    drawer_round_bonus = 0
    draw_time_left = DRAW_TIME
    total_letters = run_function(DATA, "dtw_letter_count", { word })
    max_reveal = math.floor(total_letters * MAX_REVEAL_RATIO)

    -- Snapshot the guessers (everyone connected except the drawer).
    participants = {}
    for _, steam_id in ipairs(connected) do
        if steam_id ~= drawer_id then participants[steam_id] = true end
    end

    -- Fresh board, only the drawer may paint it.
    clear_canvas(IMAGE_NAME)
    set_painter(IMAGE_NAME, drawer_id)

    local drawer_name = players[drawer_id].name

    -- Drawer gets the painting panel + the secret word; all peers get the round HUD.
    -- The mask starts empty: guessers see nothing until the drawer presses "Reveal Hint".
    run_network_function(UI, "start_drawing_CLIENT", { word, IMAGE_NAME, max_reveal }, drawer_id)
    run_network_function(name, "round_start_ALL", { drawer_id, drawer_name, "", 0, DRAW_TIME }, "")
    broadcast_scoreboard()

    start_timer({
        timer_id = "dtw_draw_timer",
        entity_name = name,
        function_name = "draw_tick",
        wait_time = 1.0,
        duration = DRAW_TIME,
    })
end

function draw_tick(args)
    if not IS_HOST then return end
    if phase ~= "drawing" then return end
    if args.is_last_iteration then
        end_round("time")
        return
    end
    draw_time_left = args.duration - args.iteration_count
    run_network_function(name, "timer_ALL", { draw_time_left }, "")
end

-- Effective points for a correct guess: more time left = more points, and every
-- revealed hint letter shrinks the round's distributable cap.
local function compute_points()
    local frac = draw_time_left / DRAW_TIME
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    local base = MIN_POINTS + (MAX_POINTS - MIN_POINTS) * frac

    local reveal_ratio = 0
    if total_letters > 0 then reveal_ratio = revealed_count / total_letters end
    local cap_factor = 1 - reveal_ratio
    if cap_factor < 0.2 then cap_factor = 0.2 end -- never zero out the round

    local pts = math.floor(base * cap_factor)
    if pts < 1 then pts = 1 end
    return pts
end

-- HOST: a guesser submitted a chat message during the drawing phase.
function submit_guess_HOST(sender_id, raw_text)
    if not IS_HOST then return end
    if phase ~= "drawing" then return end
    if sender_id == drawer_id then return end
    if correct[sender_id] then return end

    local p = players[sender_id]
    local sender_name = p and p.name or "Player"

    -- Spectators (joined mid-round) are not guessing; just relay their chatter.
    if not participants[sender_id] then
        run_network_function(name, "broadcast_chat_ALL", { sender_name, raw_text }, "")
        return
    end

    local guess = run_function(DATA, "dtw_normalize", { raw_text })
    local answer = run_function(DATA, "dtw_normalize", { secret_word })

    if guess == answer and guess ~= "" then
        -- Correct guess.
        local pts = compute_points()
        correct[sender_id] = pts
        table.insert(correct_order, sender_id)
        if p then p.score = p.score + pts end

        -- Drawer earns a bonus for every correct guesser.
        local bonus = math.floor(pts * DRAWER_BONUS_RATIO)
        if bonus < 5 then bonus = 5 end
        drawer_round_bonus = drawer_round_bonus + bonus
        if players[drawer_id] then players[drawer_id].score = players[drawer_id].score + bonus end

        run_network_function(name, "correct_guess_ALL", { sender_id, sender_name, pts }, "")
        broadcast_scoreboard()

        -- Round ends early once everyone has guessed.
        if count_map(correct) >= count_map(participants) then
            end_round("all_guessed")
        end
    elseif run_function(DATA, "dtw_is_close", { guess, answer }) then
        -- Close: tell only this guesser, never reveal to the room.
        run_network_function(UI, "notify_close_CLIENT", {}, sender_id)
    else
        -- Wrong guess / normal chatter: relay to everyone.
        run_network_function(name, "broadcast_chat_ALL", { sender_name, raw_text }, "")
    end
end

-- HOST: the drawer reveals a hint. First press shows the word structure
-- (underscore mask, free of charge). Every subsequent press reveals one random
-- letter, up to max_reveal. No hints are allowed once someone guessed correctly.
function reveal_hint_HOST(sender_id)
    if not IS_HOST then return end
    if phase ~= "drawing" or sender_id ~= drawer_id then return end
    if #correct_order > 0 then return end          -- no hints once someone is right

    if not hint_structure_shown then
        -- First press: reveal word shape (underscores only, no letter exposed).
        -- This does not consume a letter-reveal slot; used=0 keeps the counter clean.
        hint_structure_shown = true
        local structure_mask = run_function(DATA, "dtw_build_mask", { secret_word, {} })
        run_network_function(name, "hint_ALL", { structure_mask, 0, max_reveal }, "")
        return
    end

    -- Second press and beyond: reveal one random unrevealed letter.
    if revealed_count >= max_reveal then return end
    local eligible = {}
    for i = 1, #secret_word do
        local ch = string.sub(secret_word, i, i)
        if string.match(ch, "%a") and not revealed[i] then
            table.insert(eligible, i)
        end
    end
    if #eligible == 0 then return end

    local idx = eligible[math.random(1, #eligible)]
    revealed[idx] = true
    revealed_count = revealed_count + 1

    local mask = run_function(DATA, "dtw_build_mask", { secret_word, revealed })
    run_network_function(name, "hint_ALL", { mask, revealed_count, max_reveal }, "")
end

-- HOST: anyone may report the current drawer; over half skips them.
function report_drawer_HOST(sender_id)
    if not IS_HOST then return end
    if phase ~= "choosing" and phase ~= "drawing" then return end
    if sender_id == drawer_id then return end
    if not players[sender_id] then return end
    if reports[sender_id] then return end

    reports[sender_id] = true
    local report_count = count_map(reports)
    local eligible = #connected - 1
    if eligible < 1 then eligible = 1 end
    local threshold = math.floor(eligible / 2) + 1

    run_network_function(name, "report_update_ALL", { report_count, threshold }, "")

    if report_count >= threshold then
        local skipped_name = players[drawer_id] and players[drawer_id].name or "Player"
        if players[drawer_id] then players[drawer_id].has_drawn = true end
        if phase == "choosing" then stop_timer("dtw_choose_timer") end
        if phase == "drawing" then stop_timer("dtw_draw_timer") end
        run_network_function(name, "turn_skipped_ALL", { skipped_name, "was reported by most players" }, "")
        phase = "intermission"
        set_painter(IMAGE_NAME, 0)
        start_timer({
            timer_id = "dtw_intermission",
            entity_name = name,
            function_name = "after_intermission",
            wait_time = 2.0,
            duration = 2.0,
        })
    end
end

-- HOST: the drawer passes their turn.
function pass_turn_HOST(sender_id)
    if not IS_HOST then return end
    if sender_id ~= drawer_id then return end
    if phase ~= "choosing" and phase ~= "drawing" then return end

    if players[drawer_id] then players[drawer_id].has_drawn = true end
    if phase == "choosing" then stop_timer("dtw_choose_timer") end
    if phase == "drawing" then stop_timer("dtw_draw_timer") end

    run_network_function(name, "turn_skipped_ALL", { players[drawer_id] and players[drawer_id].name or "Player", "passed their turn" }, "")
    phase = "intermission"
    set_painter(IMAGE_NAME, 0)
    start_timer({
        timer_id = "dtw_intermission",
        entity_name = name,
        function_name = "after_intermission",
        wait_time = 2.0,
        duration = 2.0,
    })
end

-- HOST: finish the drawing round and show the summary.
function end_round(reason)
    if not IS_HOST then return end
    if phase ~= "drawing" then return end

    phase = "intermission"
    stop_timer("dtw_draw_timer")
    set_painter(IMAGE_NAME, 0)
    if players[drawer_id] then players[drawer_id].has_drawn = true end

    -- Build the "who guessed it" summary.
    local lines = {}
    for _, steam_id in ipairs(correct_order) do
        local nm = players[steam_id] and players[steam_id].name or "Player"
        table.insert(lines, { name = nm, points = correct[steam_id] })
    end

    run_network_function(name, "round_end_ALL", {
        secret_word,
        players[drawer_id] and players[drawer_id].name or "Player",
        drawer_round_bonus,
        lines,
    }, "")
    broadcast_scoreboard()

    start_timer({
        timer_id = "dtw_intermission",
        entity_name = name,
        function_name = "after_intermission",
        wait_time = INTERMISSION_TIME,
        duration = INTERMISSION_TIME,
    })
end

function after_intermission(args)
    if not IS_HOST then return end
    if phase == "gameover" then return end
    start_next_turn()
end

-- HOST: no one left to draw this game -> show the podium, then restart.
function end_game()
    if not IS_HOST then return end
    phase = "gameover"
    drawer_id = ""
    set_painter(IMAGE_NAME, 0)

    run_network_function(name, "game_over_ALL", { build_scoreboard() }, "")

    start_timer({
        timer_id = "dtw_podium",
        entity_name = name,
        function_name = "after_podium",
        wait_time = PODIUM_TIME,
        duration = PODIUM_TIME,
    })
end

function after_podium(args)
    if not IS_HOST then return end
    -- Reset scores and start a fresh game.
    for _, p in pairs(players) do
        p.score = 0
        p.has_drawn = false
    end
    phase = "idle"
    drawer_id = ""
    -- Fresh word pool so no words repeat from the previous game.
    run_function(DATA, "dtw_reset_pool", {})
    run_network_function(name, "reset_ALL", {}, "")
    broadcast_scoreboard()
    maybe_start()
end

-- =============================================================================
-- ALL-peer mirror updates + UI fan-out (run on host and clients)
-- =============================================================================
function turn_announce_ALL(sender_id, p_drawer_id, p_drawer_name)
    cl_phase = "choosing"
    cl_drawer_id = p_drawer_id
    cl_correct = {}
    run_function(UI, "on_turn_announce", { p_drawer_id, p_drawer_name })
end

function round_start_ALL(sender_id, p_drawer_id, p_drawer_name, mask, p_total_letters, p_time)
    cl_phase = "drawing"
    cl_drawer_id = p_drawer_id
    cl_correct = {}
    run_function(UI, "on_round_start", { p_drawer_id, p_drawer_name, mask, p_total_letters, p_time })
end

function timer_ALL(sender_id, time_left)
    run_function(UI, "on_timer", { time_left })
end

function hint_ALL(sender_id, mask, used, maxr)
    run_function(UI, "on_hint", { mask, used, maxr })
end

function correct_guess_ALL(sender_id, guesser_id, guesser_name, pts)
    cl_correct[guesser_id] = true
    run_function(UI, "on_correct_guess", { guesser_id, guesser_name, pts })
end

function broadcast_chat_ALL(sender_id, chat_name, chat_text)
    run_function(UI, "on_relayed_chat", { chat_name, chat_text })
end

function report_update_ALL(sender_id, report_count, threshold)
    run_function(UI, "on_report_update", { report_count, threshold })
end

function turn_skipped_ALL(sender_id, skipped_name, reason)
    cl_phase = "intermission"
    run_function(UI, "on_turn_skipped", { skipped_name, reason })
end

function round_end_ALL(sender_id, word, p_drawer_name, bonus, lines)
    cl_phase = "intermission"
    run_function(UI, "on_round_end", { word, p_drawer_name, bonus, lines })
end

function game_over_ALL(sender_id, scoreboard)
    cl_phase = "gameover"
    cl_drawer_id = ""
    run_function(UI, "on_game_over", { scoreboard })
end

function reset_ALL(sender_id)
    cl_phase = "idle"
    cl_drawer_id = ""
    cl_correct = {}
    run_function(UI, "on_reset", {})
end

function scoreboard_ALL(sender_id, scoreboard)
    run_function(UI, "on_scoreboard", { scoreboard })
end

-- =============================================================================
-- Chat interception (runs on EVERY peer as a display hook)
-- =============================================================================

-- Pull the raw text out of the pre-formatted message
-- "[color=#xxxxxx]name[/color]: actual text".
local function extract_text(formatted)
    local marker = "[/color]: "
    local idx = string.find(formatted, marker, 1, true)
    if idx then
        return string.sub(formatted, idx + #marker)
    end
    local i2 = string.find(formatted, ": ", 1, true)
    if i2 then return string.sub(formatted, i2 + 2) end
    return formatted
end

function _on_chat_message_received(sender_id, nickname, message)
    -- Outside an active drawing round, chat behaves normally.
    if cl_phase ~= "drawing" then return nil end

    -- The drawer must not type (could reveal the word).
    if sender_id == cl_drawer_id then return "" end
    -- Players who already guessed correctly cannot send more this round.
    if cl_correct[sender_id] then return "" end

    -- Treat as a guess: hide the raw text on every client, and from the sender's
    -- own machine route it to the host for validation. The host decides whether
    -- it is correct (announce), close (private hint), or normal chatter (relay).
    if sender_id == LOCAL_STEAM_ID then
        run_network_function(name, "submit_guess_HOST", { extract_text(message) }, "")
    end
    return ""
end

-- =============================================================================
-- Player tracking (HOST authoritative)
-- =============================================================================
function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end

    if not players[steam_id] then
        players[steam_id] = { name = nickname, score = 0, has_drawn = false }
        table.insert(order, steam_id)
    else
        players[steam_id].name = nickname
    end
    if not list_contains(connected, steam_id) then
        table.insert(connected, steam_id)
    end

    -- If a game is running, the newcomer waits at the back of the queue.
    if phase ~= "idle" and phase ~= "gameover" then
        if not players[steam_id].has_drawn and not list_contains(queue, steam_id) and steam_id ~= drawer_id then
            table.insert(queue, steam_id)
        end
    end

    -- Sync current state to the late joiner. If a round is being drawn, mirror
    -- whatever hint state has been revealed so far: if the structure was shown,
    -- send the current mask (underscores + any revealed letters); if the drawer
    -- has not pressed hint yet, send an empty mask so the late joiner also sees
    -- nothing (consistent with what everyone else is seeing).
    local sync_mask = ""
    local sync_total = 0
    local sync_time = 0
    if phase == "drawing" then
        if hint_structure_shown then
            sync_mask = run_function(DATA, "dtw_build_mask", { secret_word, revealed })
        end
        sync_total = total_letters
        sync_time = draw_time_left
    end
    run_network_function(UI, "sync_state_CLIENT", {
        phase,
        (drawer_id ~= "" and players[drawer_id]) and players[drawer_id].name or "",
        drawer_id,
        sync_mask,
        sync_total,
        sync_time,
    }, steam_id)

    broadcast_scoreboard()
    maybe_start()
end

function _on_user_disconnected(steam_id, nickname)
    if not IS_HOST then return end

    local was_drawer = (steam_id == drawer_id)
    players[steam_id] = nil
    list_remove_value(connected, steam_id)
    list_remove_value(queue, steam_id)
    list_remove_value(order, steam_id)
    participants[steam_id] = nil
    correct[steam_id] = nil
    reports[steam_id] = nil

    broadcast_scoreboard()

    -- Not enough players: stop the game and wait.
    if #connected < MIN_PLAYERS then
        if phase == "choosing" then stop_timer("dtw_choose_timer") end
        if phase == "drawing" then stop_timer("dtw_draw_timer") end
        if phase ~= "idle" and phase ~= "gameover" then
            phase = "idle"
            drawer_id = ""
            set_painter(IMAGE_NAME, 0)
            run_network_function(name, "reset_ALL", {}, "")
        end
        return
    end

    if was_drawer and (phase == "choosing" or phase == "drawing") then
        -- The drawer left: drop the round and move on.
        if phase == "choosing" then stop_timer("dtw_choose_timer") end
        if phase == "drawing" then stop_timer("dtw_draw_timer") end
        run_network_function(name, "turn_skipped_ALL", { nickname, "left the game" }, "")
        phase = "intermission"
        set_painter(IMAGE_NAME, 0)
        start_timer({
            timer_id = "dtw_intermission",
            entity_name = name,
            function_name = "after_intermission",
            wait_time = 2.0,
            duration = 2.0,
        })
    elseif phase == "drawing" then
        -- A guesser left: the round may now be complete.
        if count_map(correct) >= count_map(participants) and count_map(participants) > 0 then
            end_round("all_guessed")
        end
    end
end

function _on_user_connected(steam_id, nickname)
    add_to_chat("[color=#88ccff]" .. nickname .. "[/color] joined the room.", false)
end

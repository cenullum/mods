network_mode = 1
singleton_name = "ce_manager"

-- =============================================================================
-- Crazy Eights - host-authoritative game manager + all client UI.
--
-- Rules (classic Crazy Eights):
--   * Match the top discard by COLOR or VALUE; an 8 is wild (pick a color).
--   * skip = next player skipped, reverse = direction flips (acts like skip
--     with 2 players), draw2 = next player draws two and is skipped.
--   * On your turn you may instead click the deck to draw ONE card: if it is
--     playable you may play it, clicking the deck again passes.
--   * First player with an empty hand wins the round.
--
-- Anti-cheat: the deck order lives only on the host (engine-enforced), every
-- intent below is validated on the host, and hand identities are only sent to
-- their owner - other players (and spectators) see card BACKS only.
-- Late joiners spectate; the "Sit at table" button queues them for the next
-- round while a round is running.
-- =============================================================================

local MIN_PLAYERS = 2
local HAND_SIZE = 7
local TURN_TIME = 30
local START_DELAY = 6
local ROUND_END_TIME = 8
local PENALTY_TIME = 5    -- seconds a +2 victim has to stack another +2 or eat the pile
local DEAL_PAUSE = 1.0    -- a beat before the penalty cards actually enter the hand

local DECK = "ce_draw"
local DRAW_POS = Vector2(-75, 0)
local DISCARD_POS = Vector2(75, 0)
local CARD_SIZE = Vector2(96, 134)
local SEAT_RADIUS = 300
local COLOR_KEYS = { "purple", "teal", "orange", "green" }
local COLOR_HEX = { purple = "#a558ff", teal = "#19d3c5", orange = "#ff9a2e", green = "#61d13f" }

-- Distinct per-player colors (assigned by join order so nobody shares one) used
-- for BOTH the world-space mouse cursors (user.lua reads this same map) and the
-- nicknames in the panels + at the seats. Stored/sent as hex so both sides need
-- only hex_to_color (already here) - no Color field access on the Lua bridge.
local PLAYER_HEX = {
    "#f25a5a", "#59bffa", "#fad047", "#85e56b", "#d972ea",
    "#fa9933", "#66f2d1", "#fa8cbf", "#99a6fa", "#c0d24d",
}

-- ---------- HOST state ----------
players = {}          -- steam_id -> { name, wins }
connected = {}        -- ordered steam_ids in the lobby
seated = {}           -- ordered steam_ids playing THIS round (seat order)
waiting = {}          -- steam_ids who sat down mid-round (join next round)
phase = "lobby"       -- lobby | starting | playing | roundend
turn_idx = 1
direction = 1
active_color = ""
active_value = ""
top_uid = ""
drawn_this_turn = false
-- Stacking +2 penalty (UNO-style): a played draw2 puts the NEXT player on a short
-- clock; they may only answer with their own draw2 (passing a growing +N on) or,
-- when the clock runs out, they draw the whole accumulated pile and are skipped.
pen_active = false    -- a +2 penalty is currently on the clock
pen_total = 0         -- cards the victim draws if they don't stack
pen_victim = ""       -- steam_id who must stack a +2 or eat the pile
pen_dealing = false   -- brief lock while the pile is dealt out (no plays accepted)
pen_deal_left = 0     -- cards still to deal out one-by-one during the pause
pen_deal_victim = ""  -- who the dealt-out pile is going to

-- ---------- CLIENT mirror ----------
cl_phase = "lobby"
cl_seated = {}
cl_turn = ""
cl_color = ""
cl_names = {}
cl_wins = {}
cl_colors = {}        -- steam_id -> hex; per-player color shared with user.lua cursors
cl_pending_wild = ""  -- uid of the 8 we are choosing a color for
cl_zoom = 0.6         -- local camera zoom; starts fully zoomed out (see world.lua)
cl_local_rot = 0.0     -- LOCAL counter-rotation (radians); never networked
cl_pen = nil          -- { victim, total } mirror of the +2 stacking window
cl_pen_time_left = 0.0 -- local cosmetic countdown for that window
cl_pen_shown = -1
cl_pen_last = -1       -- detects a new/re-opened window (accumulated total changes)

local MAX_SEATS = 8
local DROP_RADIUS = 170

local function hex_to_color(hex)
    local r = tonumber(hex:sub(2, 3), 16) / 255
    local g = tonumber(hex:sub(4, 5), 16) / 255
    local b = tonumber(hex:sub(6, 7), 16) / 255
    return Color(r, g, b, 1)
end

-- What each special/action card does (shown bottom-right when one is played).
local ACTION_NOTES = {
    skip    = "[center][b]Skip[/b]\nThe next player is skipped.[/center]",
    reverse = "[center][b]Reverse[/b]\nTurn order flips (a Skip with 2 players).[/center]",
    draw2   = "[center][b]Draw Two (+2)[/b]\nNext player must stack their own +2 within 5s or draw the pile (+2, +4, +6...) and be skipped.[/center]",
    ["8"]   = "[center][b]Wild 8[/b]\nPlay it on anything, then choose the next color.[/center]",
}
local NOTE = ""

-- panel names
local HUD = ""
local SEATP = ""
local SCORE = ""
local WILD = ""

-- =============================================================================
-- Helpers
-- =============================================================================
local function list_remove(list, value)
    for i, v in ipairs(list) do
        if v == value then table.remove(list, i) return true end
    end
    return false
end

local function list_contains(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function seat_position(index, count)
    local angle = math.pi / 2 + (index - 1) * (2 * math.pi / math.max(count, 1))
    return Vector2(math.cos(angle) * SEAT_RADIUS, math.sin(angle) * SEAT_RADIUS)
end

local function is_playable(card_id)
    if get_card_keyword(card_id, "wild") then return true end
    return get_card_keyword(card_id, "color") == active_color
        or get_card_keyword(card_id, "value") == active_value
end

local function current_turn_id()
    return seated[turn_idx] or ""
end

-- One distinct color per connected player, by stable join order (host-side).
local function assign_colors()
    local out = {}
    for i, id in ipairs(connected) do
        out[id] = PLAYER_HEX[((i - 1) % #PLAYER_HEX) + 1]
    end
    return out
end

-- Play a sound on EVERY peer. set_audio is otherwise purely local, so the host
-- broadcasts it through the manager singleton (which exists on all machines).
function play_sound(sound)
    if not IS_HOST then return end
    run_network_function(name, "sound_ALL", { sound })
end

function sound_ALL(sender_id, sound)
    set_audio({ stream_path = sound, bus = "Effect", random_pitch = 0.12, is_2d = false })
end

-- Ticks the local (cosmetic, unsynced) +2 countdown shown in the HUD; only
-- touches the panel when the displayed whole second actually changes.
function _process(delta, inputs)
    if cl_pen and cl_pen_time_left > 0 then
        cl_pen_time_left = math.max(0, cl_pen_time_left - delta)
        local shown = math.ceil(cl_pen_time_left)
        if shown ~= cl_pen_shown then
            cl_pen_shown = shown
            refresh_hud()
        end
    end
    return inputs
end

-- =============================================================================
-- HOST: state broadcast (everything clients may know - no hand identities)
-- =============================================================================
function broadcast_state(target)
    if not IS_HOST then return end
    local wins = {}
    local names = {}
    for id, p in pairs(players) do
        wins[id] = p.wins
        names[id] = p.name
    end
    run_network_function(name, "sync_ALL", { {
        phase = phase,
        seated = seated,
        turn = current_turn_id(),
        color = active_color,
        names = names,
        wins = wins,
        colors = assign_colors(),
        pen = pen_active and { victim = pen_victim, total = pen_total } or nil,
    } }, target or "")
end

-- =============================================================================
-- HOST: seating & round flow
-- =============================================================================
function sit_HOST(sender_id)
    if not IS_HOST then return end
    if not players[sender_id] then return end
    if list_contains(seated, sender_id) or list_contains(waiting, sender_id) then return end
    if phase == "lobby" or phase == "starting" then
        table.insert(seated, sender_id)
        try_start()
    else
        table.insert(waiting, sender_id) -- joins when the round ends
    end
    broadcast_state()
end

function stand_HOST(sender_id)
    if not IS_HOST then return end
    list_remove(waiting, sender_id)
    if phase == "lobby" or phase == "starting" then
        list_remove(seated, sender_id)
        if phase == "starting" and #seated < MIN_PLAYERS then
            phase = "lobby"
            stop_timer("ce_start")
        end
    end
    broadcast_state()
end

function try_start()
    if not IS_HOST then return end
    if phase ~= "lobby" or #seated < MIN_PLAYERS then return end
    phase = "starting"
    start_timer({
        timer_id = "ce_start",
        entity_name = name,
        function_name = "start_round",
        wait_time = START_DELAY,
        duration = START_DELAY,
    })
    broadcast_state()
end

function start_round(args)
    if not IS_HOST then return end
    if #seated < MIN_PLAYERS then
        phase = "lobby"
        broadcast_state()
        return
    end
    card_destroy_all()

    -- Full 100-card pool: per color one 0, two of 1-9, two of each action.
    local pool = {}
    for _, color in ipairs(COLOR_KEYS) do
        table.insert(pool, "ce_" .. color .. "_0")
        for n = 1, 9 do
            table.insert(pool, "ce_" .. color .. "_" .. n)
            table.insert(pool, "ce_" .. color .. "_" .. n)
        end
        for _, action in ipairs({ "skip", "reverse", "draw2" }) do
            table.insert(pool, "ce_" .. color .. "_" .. action)
            table.insert(pool, "ce_" .. color .. "_" .. action)
        end
    end

    card_create_deck({
        name = DECK,
        position = DRAW_POS,
        cards = pool,
        size = CARD_SIZE,
        visibility = "owner", -- only the drawer learns their card
        show_count = true,
    })
    card_shuffle(DECK) -- no seed: random every round
    play_sound("card_shuffle") -- everyone hears the deck being shuffled + dealt

    for _, id in ipairs(seated) do
        for _ = 1, HAND_SIZE do
            card_draw(DECK, id)
        end
    end

    -- Flip the starter card (redraw eights back into the deck: a wild cannot
    -- open the round).
    local starter_uid = ""
    local starter_id = ""
    repeat
        if starter_uid ~= "" then
            card_return_to_deck(starter_uid, DECK, -1)
        end
        starter_uid = card_draw(DECK, LOCAL_STEAM_ID)
        starter_id = card_uid_info(starter_uid).card_id or ""
    until starter_id ~= "" and not get_card_keyword(starter_id, "wild")
    card_play(starter_uid, DISCARD_POS, true)
    top_uid = starter_uid
    active_color = get_card_keyword(starter_id, "color") or COLOR_KEYS[1]
    active_value = get_card_keyword(starter_id, "value") or ""

    phase = "playing"
    turn_idx = 1
    direction = 1
    drawn_this_turn = false
    pen_active = false
    pen_total = 0
    pen_victim = ""
    pen_dealing = false
    pen_deal_left = 0
    pen_deal_victim = ""
    restart_turn_timer()
    broadcast_state()
end

function restart_turn_timer()
    if not IS_HOST then return end
    stop_timer("ce_turn")
    start_timer({
        timer_id = "ce_turn",
        entity_name = name,
        function_name = "turn_timeout",
        wait_time = TURN_TIME,
        duration = TURN_TIME,
    })
end

function turn_timeout(args)
    if not IS_HOST or phase ~= "playing" then return end
    -- Too slow: draw a card (if they had not) and pass.
    local id = current_turn_id()
    if id ~= "" and not drawn_this_turn and card_deck_count(DECK) > 0 then
        card_draw(DECK, id)
        play_sound("card_taking_from_deck")
    end
    advance_turn(1)
    broadcast_state()
end

function advance_turn(steps)
    if #seated == 0 then return end
    turn_idx = ((turn_idx - 1 + direction * steps) % #seated) + 1
    drawn_this_turn = false
    restart_turn_timer()
end

-- Refill the draw pile from the discard stack (all table cards but the top).
function refill_deck()
    if not IS_HOST then return end
    for _, uid in ipairs(card_table_cards()) do
        if uid ~= top_uid then
            card_return_to_deck(uid, DECK, 0)
        end
    end
    card_shuffle(DECK)
    play_sound("card_shuffle")
end

-- =============================================================================
-- HOST: player intents
-- =============================================================================
function play_card_HOST(sender_id, data)
    if not IS_HOST or phase ~= "playing" then return end
    if pen_dealing then return end -- pile is being handed out; ignore everything
    if sender_id ~= current_turn_id() then return end
    local uid = data and data.uid or ""
    -- The uid must really be in the sender's hand; the host sees identities.
    local card_id = ""
    for _, entry in ipairs(card_get_hand(sender_id)) do
        if entry.uid == uid then card_id = entry.card_id break end
    end
    if card_id == "" or not is_playable(card_id) then return end

    -- While a +2 is on the clock the victim may ONLY answer with another draw2.
    if pen_active and tostring(get_card_keyword(card_id, "value") or "") ~= "draw2" then
        return
    end

    card_play(uid, Vector2(DISCARD_POS.x + math.random(-10, 10), DISCARD_POS.y + math.random(-8, 8)), true)
    top_uid = uid
    active_value = tostring(get_card_keyword(card_id, "value") or "")
    play_sound("card_flip")

    if get_card_keyword(card_id, "wild") then
        local pick = data and data.color or ""
        if not list_contains(COLOR_KEYS, pick) then
            pick = COLOR_KEYS[math.random(1, #COLOR_KEYS)]
        end
        active_color = pick
    else
        active_color = tostring(get_card_keyword(card_id, "color") or active_color)
    end

    -- Win before effects: an empty hand ends the round immediately.
    if card_hand_count(sender_id) == 0 then
        end_round(sender_id)
        return
    end

    if active_value == "skip" then
        advance_turn(2)
    elseif active_value == "reverse" then
        direction = -direction
        if #seated == 2 then
            advance_turn(2) -- with two players a reverse behaves like a skip
        else
            advance_turn(1)
        end
    elseif active_value == "draw2" then
        -- Grow the stacking penalty and put the NEXT player on the clock.
        advance_turn(1)
        stop_timer("ce_turn")       -- the victim is on the penalty clock, not a normal turn
        pen_active = true
        pen_total = pen_total + 2
        pen_victim = current_turn_id()
        -- Fan the played +2s out in a neat centred row so the pile reads clearly.
        local slot = pen_total / 2  -- 1st, 2nd, 3rd... +2 in the chain
        card_move(uid, Vector2(DISCARD_POS.x + (slot - 1) * 34 - 34, DISCARD_POS.y - 6), 0.25)
        stop_timer("ce_penalty")
        start_timer({
            timer_id = "ce_penalty",
            entity_name = name,
            function_name = "penalty_timeout",
            wait_time = PENALTY_TIME,
            duration = PENALTY_TIME,
        })
    else
        advance_turn(1)
    end
    broadcast_state()
end

-- The +2 window ran out: after a short beat the victim eats the pile, dealt out
-- ONE card at a time (0.2s apart, each with its own draw sound) so the count is
-- obvious. pen_dealing stays true the whole time, so nobody can play meanwhile.
--
-- IMPORTANT: this uses TWO timers, not one reused id. start_timer's engine timer
-- always fires its Lua callback FIRST and only decides afterwards (based on the
-- iteration count captured before that call) whether to auto stop_timer() the
-- SAME id - so calling start_timer again on that identical id FROM WITHIN its own
-- callback just gets torn down a moment later by the very call that invoked us
-- (that was the earlier bug: the 2nd card's timer got created, then immediately
-- freed, and the deal silently stalled forever with pen_dealing stuck true).
-- The fix is the idiom used elsewhere in this codebase (see wave_manager.lua):
-- ONE repeating timer for ALL the deal steps, sized by duration/wait_time so the
-- engine itself iterates it exactly pen_total times and auto-stops on the last one.
function penalty_timeout(args)
    if not IS_HOST or not pen_active then return end
    if phase ~= "playing" then
        pen_active = false pen_dealing = false pen_victim = "" pen_total = 0
        return
    end
    pen_active = false
    pen_dealing = true -- lock out plays while we deal
    pen_deal_victim = pen_victim
    pen_deal_left = pen_total
    broadcast_state()
    start_timer({
        timer_id = "ce_pdeal_wait",
        entity_name = name,
        function_name = "start_penalty_deal",
        wait_time = DEAL_PAUSE,
        duration = DEAL_PAUSE,
    })
end

-- After the beat: one repeating timer handles ALL the cards (0.2s apart, engine
-- auto-stops after pen_total iterations) - no per-step start_timer calls needed.
function start_penalty_deal(args)
    if not IS_HOST or pen_deal_victim == "" then return end
    start_timer({
        timer_id = "ce_pdeal",
        entity_name = name,
        function_name = "deal_penalty_step",
        wait_time = 0.2,
        duration = 0.2 * math.max(pen_deal_left, 1),
    })
end

-- Deals exactly ONE penalty card per tick; on the last tick, finishes up.
function deal_penalty_step(args)
    if not IS_HOST then return end
    if phase ~= "playing" or pen_deal_victim == "" or pen_deal_left <= 0 then
        finish_penalty_deal()
        return
    end
    if card_deck_count(DECK) == 0 then refill_deck() end
    if card_deck_count(DECK) > 0 then
        card_draw(DECK, pen_deal_victim)
        play_sound("card_taking_from_deck")
    end
    pen_deal_left = pen_deal_left - 1
    broadcast_state()
    if args and args.is_last_iteration or pen_deal_left <= 0 then
        finish_penalty_deal()
    end
end

function finish_penalty_deal()
    if not IS_HOST then return end
    pen_deal_left = 0
    pen_deal_victim = ""
    pen_victim = ""
    pen_total = 0
    pen_dealing = false
    if phase == "playing" then
        advance_turn(1) -- draw2 also skips the victim's own turn
    end
    broadcast_state()
end

function draw_card_HOST(sender_id)
    if not IS_HOST or phase ~= "playing" then return end
    if pen_active or pen_dealing then return end -- must answer a +2 with a +2, not a draw
    if sender_id ~= current_turn_id() then return end
    if drawn_this_turn then
        -- Second deck click = pass.
        advance_turn(1)
        broadcast_state()
        return
    end
    if card_deck_count(DECK) == 0 then refill_deck() end
    if card_deck_count(DECK) == 0 then
        advance_turn(1) -- nothing left anywhere: just pass
        broadcast_state()
        return
    end
    local uid = card_draw(DECK, sender_id)
    play_sound("card_taking_from_deck")
    drawn_this_turn = true
    local card_id = card_uid_info(uid).card_id or ""
    if card_id == "" or not is_playable(card_id) then
        advance_turn(1) -- not playable: the turn ends right away
    end
    broadcast_state()
end

function end_round(winner_id)
    if not IS_HOST then return end
    stop_timer("ce_turn")
    -- Clear any in-flight +2 penalty so its timers can't fire after the round ends
    -- (e.g. someone won by playing their last card as a +2).
    stop_timer("ce_penalty")
    stop_timer("ce_pdeal_wait")
    stop_timer("ce_pdeal")
    pen_active = false
    pen_dealing = false
    pen_victim = ""
    pen_total = 0
    pen_deal_left = 0
    pen_deal_victim = ""
    phase = "roundend"
    if players[winner_id] then
        players[winner_id].wins = players[winner_id].wins + 1
    end
    local winner_name = players[winner_id] and players[winner_id].name or "?"
    run_network_function(name, "round_over_ALL", { winner_name })
    start_timer({
        timer_id = "ce_next",
        entity_name = name,
        function_name = "after_round",
        wait_time = ROUND_END_TIME,
        duration = ROUND_END_TIME,
    })
    broadcast_state()
end

function after_round(args)
    if not IS_HOST then return end
    -- Everyone who sat down during the round joins now.
    for _, id in ipairs(waiting) do
        if players[id] and not list_contains(seated, id) then
            table.insert(seated, id)
        end
    end
    waiting = {}
    card_destroy_all()
    phase = "lobby"
    broadcast_state()
    try_start()
end

-- =============================================================================
-- Player tracking
-- =============================================================================
function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end
    if not players[steam_id] then
        players[steam_id] = { name = nickname, wins = 0 }
    else
        players[steam_id].name = nickname
    end
    if not list_contains(connected, steam_id) then
        table.insert(connected, steam_id)
    end
    -- The engine already synced decks/hand counts to the late joiner;
    -- this mirrors the mod-level state (phase, seats, turn).
    broadcast_state(steam_id)
    broadcast_state()
end

function _on_user_disconnected(steam_id, nickname)
    if not IS_HOST then return end
    -- If the player on the +2 clock leaves, cancel the pending penalty cleanly so
    -- its timers never fire against a seat that no longer exists.
    if steam_id == pen_victim or steam_id == pen_deal_victim then
        stop_timer("ce_penalty")
        stop_timer("ce_pdeal_wait")
        stop_timer("ce_pdeal")
        pen_active = false
        pen_dealing = false
        pen_victim = ""
        pen_total = 0
        pen_deal_left = 0
        pen_deal_victim = ""
    end
    players[steam_id] = nil
    list_remove(connected, steam_id)
    list_remove(waiting, steam_id)
    local was_turn = (steam_id == current_turn_id())
    local seat = 0
    for i, v in ipairs(seated) do
        if v == steam_id then seat = i end
    end
    if seat > 0 then
        table.remove(seated, seat)
        if phase == "playing" then
            if #seated < MIN_PLAYERS then
                if #seated == 1 then
                    end_round(seated[1]) -- last one standing wins
                else
                    phase = "lobby"
                    card_destroy_all()
                end
            else
                if seat < turn_idx then
                    turn_idx = turn_idx - 1
                end
                if was_turn then
                    turn_idx = ((turn_idx - 1) % #seated) + 1
                    drawn_this_turn = false
                    restart_turn_timer()
                else
                    turn_idx = ((turn_idx - 1) % #seated) + 1
                end
            end
        end
    end
    broadcast_state()
end

-- =============================================================================
-- CLIENT: state mirror + UI
-- =============================================================================
function sync_ALL(sender_id, state)
    cl_phase = state.phase or "lobby"
    cl_seated = state.seated or {}
    cl_turn = state.turn or ""
    cl_color = state.color or ""
    cl_names = state.names or {}
    cl_wins = state.wins or {}
    cl_colors = state.colors or {}

    -- Mirror the +2 stacking window and (re)start the local cosmetic countdown
    -- whenever the accumulated total changes (a fresh window, or a stacked +2).
    cl_pen = state.pen
    if cl_pen then
        if cl_pen.total ~= cl_pen_last then
            cl_pen_last = cl_pen.total
            cl_pen_time_left = PENALTY_TIME
            cl_pen_shown = -1
        end
    else
        cl_pen_last = -1
    end

    -- Seat anchors: where everyone's cards fly from/to.
    local count = #cl_seated
    local my_seat = 0
    for i, id in ipairs(cl_seated) do
        local angle = math.pi / 2 + (i - 1) * (2 * math.pi / math.max(count, 1))
        card_set_player_anchor(id, Vector2(math.cos(angle) * SEAT_RADIUS, math.sin(angle) * SEAT_RADIUS))
        if id == LOCAL_STEAM_ID then my_seat = i end
    end

    -- Tabletop feel: rotate MY camera so my seat is at the bottom of my screen.
    -- The camera rotation is purely local presentation (never networked - only
    -- positions travel the wire), so every peer computes their OWN angle here
    -- and then counter-rotates their own world-space visuals (cards, seat
    -- avatars/names, turn marker) by the SAME amount so those stay upright.
    if my_seat > 0 and (cl_phase == "playing" or cl_phase == "roundend") then
        local angle = math.pi / 2 + (my_seat - 1) * (2 * math.pi / math.max(count, 1))
        cl_local_rot = angle - math.pi / 2
    else
        cl_local_rot = 0.0
    end
    set_camera_rotation(cl_local_rot)
    card_set_world_rotation(cl_local_rot)

    -- Turn marker: a small dot at the active seat.
    local marker_visible = cl_phase == "playing" and cl_turn ~= ""
    local marker_pos = Vector2(0, 0)
    for i, id in ipairs(cl_seated) do
        if id == cl_turn then
            local angle = math.pi / 2 + (i - 1) * (2 * math.pi / math.max(count, 1))
            marker_pos = Vector2(math.cos(angle) * (SEAT_RADIUS - 60), math.sin(angle) * (SEAT_RADIUS - 60))
        end
    end
    set_image({
        name = "ce_turn_marker",
        image_path = "cursor",
        position = marker_pos,
        rotation = cl_local_rot,
        scale = Vector2(34, 34),
        modulate = Color(1, 0.85, 0.2, 1),
        visible = marker_visible,
        z_index = 50,
    })

    refresh_hud()
    update_table_buttons()
    refresh_scoreboard()
    refresh_seat_avatars()
    -- Dropping a dragged card near the discard pile plays it (else it snaps back).
    card_set_drop_zone(DISCARD_POS, DROP_RADIUS)
end

-- Steam avatar + name for each seated player, on the outer ring of their seat.
-- Uses fixed slots (no create/destroy churn): unused slots are just hidden.
function refresh_seat_avatars()
    local count = #cl_seated
    for i = 1, MAX_SEATS do
        local av = "seat_av_" .. i
        local nm = "seat_nm_" .. i
        if i <= count then
            local id = cl_seated[i]
            local angle = math.pi / 2 + (i - 1) * (2 * math.pi / math.max(count, 1))
            local outer = Vector2(math.cos(angle) * (SEAT_RADIUS + 74), math.sin(angle) * (SEAT_RADIUS + 74))
            set_image({ name = av, image_path = id, position = outer, rotation = cl_local_rot,
                scale = Vector2(58, 58), z_index = 45, visible = true })
            set_label({ name = nm, text = cl_names[id] or "", position = outer + Vector2(-48, 34),
                size = Vector2(96, 20), font_size = 14, rotation = cl_local_rot,
                modulate = hex_to_color(cl_colors[id] or "#ffffff"), visible = true })
        else
            set_image({ name = av, visible = false })
            set_label({ name = nm, visible = false })
        end
    end
end

-- Avatars arrive asynchronously; refresh the seats when one finishes loading.
function _on_loaded_avatar(steam_id)
    refresh_seat_avatars()
end

function show_action_note(card_id)
    local value = get_card_keyword(card_id, "value")
    local note = ACTION_NOTES[value]
    if not note then return end  -- only the special/action cards get an explainer
    if is_panel_exists(NOTE) then
        update_panel_settings(NOTE, { text = note })
    else
        NOTE = create_panel({
            title = "Card effect",
            text = note,
            close = false,
            set_time = false,
            resizable = false,
            no_multiple_tag = "ce_note",
            minimum_size = Vector2(250, 120),
            -- Lower down the left edge, well below the "Crazy Eights" HUD but
            -- still above the bottom-left chat. (offset_ratio: 0,0=top-left ..
            -- 2,2=bottom-right)
            offset_ratio = Vector2(0, 0.62),
        })
    end
end

function round_over_ALL(sender_id, winner_name)
    create_panel({
        title = "Round over!",
        text = "[center][b]" .. winner_name .. "[/b] wins the round![/center]",
        countdown = ROUND_END_TIME - 1,
        close = false,
        set_time = false,
        resizable = false,
        no_multiple_tag = "ce_round_over",
        minimum_size = Vector2(320, 140),
    })
end

function refresh_hud()
    local txt
    if cl_phase == "playing" and cl_pen then
        -- A +2 is on the clock: warn the victim (or spectators) with a countdown.
        local secs = math.max(0, math.ceil(cl_pen_time_left))
        if cl_pen.victim == LOCAL_STEAM_ID then
            txt = "[center][b]+" .. cl_pen.total .. " STACKING![/b]\nPlay a [b]+2[/b] within " ..
                secs .. "s to pass it on, or draw " .. cl_pen.total .. " cards![/center]"
        else
            local vic = cl_names[cl_pen.victim] or "?"
            txt = "[center][b]" .. vic .. " is under +" .. cl_pen.total .. "[/b]\n" ..
                secs .. "s to stack a +2 or draw " .. cl_pen.total .. "...[/center]"
        end
    elseif cl_phase == "playing" then
        local who = cl_names[cl_turn] or "?"
        local hex = COLOR_HEX[cl_color] or "#ffffff"
        if cl_turn == LOCAL_STEAM_ID then
            who = "YOUR TURN - play a matching card or click the deck"
        else
            who = who .. "'s turn"
        end
        txt = "[center][b]" .. who .. "[/b]\nActive color: [color=" .. hex .. "]" ..
            string.upper(cl_color) .. "[/color][/center]"
    elseif cl_phase == "starting" then
        txt = "[center]Round starting... sit down now to join![/center]"
    elseif cl_phase == "roundend" then
        txt = "[center]Round finished - next one soon.[/center]"
    else
        txt = "[center][b]Crazy Eights[/b]\nSit at the table (" .. #cl_seated .. "/" ..
            MIN_PLAYERS .. " needed)[/center]"
    end
    if is_panel_exists(HUD) then
        update_panel_settings(HUD, { text = txt })
    else
        HUD = create_panel({
            title = "Crazy Eights",
            text = txt,
            close = false,
            set_time = false,
            resizable = false,
            no_multiple_tag = "ce_hud",
            minimum_size = Vector2(360, 96),
            offset_ratio = Vector2(0, 0),
        })
    end
end

-- The Sit/Stand buttons live in the "table" view (general/views/table.json);
-- here we just toggle which one is shown and what the Sit button says.
function update_table_buttons()
    local am_seated = list_contains(cl_seated, LOCAL_STEAM_ID)
    local round_running = (cl_phase == "playing" or cl_phase == "roundend")
    set_button({
        name = "_sit_btn",
        visible = not am_seated,
        text = round_running and "Sit next round" or "Sit at table",
    })
    set_button({
        name = "_stand_btn",
        visible = am_seated and (cl_phase == "lobby" or cl_phase == "starting"),
    })
end

function sit_click(args)
    run_network_function(name, "sit_HOST", {})
end

function stand_click(args)
    run_network_function(name, "stand_HOST", {})
end

-- Local camera zoom perk (magnification factor: bigger = more zoomed in).
function zoom_in_click(args)
    cl_zoom = math.min(cl_zoom + 0.2, 3.6)  -- new higher ceiling (start is 2.4)
    set_camera_zoom(Vector2(cl_zoom, cl_zoom))
end

function zoom_out_click(args)
    cl_zoom = math.max(cl_zoom - 0.2, 0.6)
    set_camera_zoom(Vector2(cl_zoom, cl_zoom))
end

function refresh_scoreboard()
    local counts = card_hand_counts()
    local lines = ""
    for i, id in ipairs(cl_seated) do
        local marker = (id == cl_turn and cl_phase == "playing") and "> " or "   "
        local hex = cl_colors[id] or "#ffffff"
        lines = lines .. marker .. "[color=" .. hex .. "]" .. (cl_names[id] or id) .. "[/color]" ..
            "  -  " .. tostring(counts[id] or 0) .. " cards, " ..
            tostring(cl_wins[id] or 0) .. " wins\n"
    end
    if lines == "" then lines = "(nobody is seated yet)" end
    if is_panel_exists(SCORE) then
        update_panel_settings(SCORE, { text = lines })
    else
        SCORE = create_panel({
            title = "Players",
            text = lines,
            close = false,
            set_time = false,
            resizable = false,
            no_multiple_tag = "ce_score",
            minimum_size = Vector2(260, 170),
            offset_ratio = Vector2(2, 0),
        })
    end
end

-- =============================================================================
-- CLIENT: card interaction callbacks (from the engine CardManager)
-- =============================================================================
function _on_hand_card_clicked(uid, card_id)
    if cl_phase ~= "playing" or cl_turn ~= LOCAL_STEAM_ID then return end
    if card_id == "" then return end
    -- Under a +2 penalty the only legal answer is another +2 (a stack).
    if cl_pen and cl_pen.victim == LOCAL_STEAM_ID
        and tostring(get_card_keyword(card_id, "value") or "") ~= "draw2" then
        return
    end
    if get_card_keyword(card_id, "wild") then
        cl_pending_wild = uid
        show_wild_panel()
        return
    end
    run_network_function(name, "play_card_HOST", { uid = uid, color = "" })
end

function _on_deck_clicked(deck_name)
    if deck_name ~= DECK then return end
    if cl_phase ~= "playing" or cl_turn ~= LOCAL_STEAM_ID then return end
    run_network_function(name, "draw_card_HOST", {})
end

function show_wild_panel()
    if is_panel_exists(WILD) then close_panel(WILD) end
    WILD = create_panel({
        title = "Wild 8!",
        text = "[center]Choose the new color:[/center]",
        close = true,
        set_time = false,
        resizable = false,
        no_multiple_tag = "ce_wild",
        minimum_size = Vector2(240, 260),
    })
    for _, key in ipairs(COLOR_KEYS) do
        local hex = COLOR_HEX[key] or "#ffffff"
        add_button_to_panel(WILD, {
            text = string.upper(key),
            entity_name = name,
            function_name = "wild_color_click",
            extra_args = { color = key },
            color = hex_to_color(hex),
            is_vertical = true,
        })
    end
end

function wild_color_click(args)
    if cl_pending_wild == "" then return end
    run_network_function(name, "play_card_HOST", {
        uid = cl_pending_wild,
        color = args.extra_args.color,
    })
    cl_pending_wild = ""
    if is_panel_exists(WILD) then close_panel(WILD) end
end

-- Refresh counters whenever cards move anywhere.
function _on_card_drawn(owner_id, deck_name, uid)
    refresh_scoreboard()
end

function _on_card_played(owner_id, uid, card_id)
    refresh_scoreboard()
    if card_id and card_id ~= "" then
        show_action_note(card_id)
    end
end

-- Dragging a hand card onto the table plays it, exactly like tapping it.
function _on_hand_card_dropped(uid, card_id)
    _on_hand_card_clicked(uid, card_id)
end

function _on_card_removed(uid)
    refresh_scoreboard()
end

function _on_card_transferred(from_id, to_id, uid)
    refresh_scoreboard()
end

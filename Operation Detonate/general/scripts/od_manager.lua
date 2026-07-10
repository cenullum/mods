network_mode = 1
singleton_name = "od_manager"

-- =============================================================================
-- Operation: Detonate - host-authoritative rules + all client UI.
--
-- Story: covert agents pull equipment from a shared supply deck, sabotage each
-- other, and pray they never draw a TIME BOMB. Bomb without a Disarm Kit = out
-- of the mission. Last agent standing wins.
--
-- Mechanics implemented:
--   Time Bomb / Disarm Kit  - defuse and hide the bomb anywhere in the deck
--   Ambush (attack)         - next agent takes 2 turns
--   Retreat (skip)          - end a turn without drawing
--   Supply Request (favor)  - target CHOOSES which card to hand over
--   Mission Shuffle         - shuffle the deck
--   Recon Drone (future)    - privately see the top 3 cards
--   Signal Jammer (nope)    - reactive: a 3.5s "jam window" opens after every
--                             action; jammers can jam jammers (parity decides)
--   Weapons (5 kinds)       - 2 identical: steal random / 3: name a card
--
-- Anti-cheat: deck order is host-only (engine), all intents validated on the
-- host against REAL hand contents, hands are back-side-only for everyone else.
-- Late joiners spectate and can queue for the next round.
-- =============================================================================

local MIN_PLAYERS = 2
local MAX_SEATS = 5
local HAND_SIZE = 5           -- + 1 guaranteed Disarm Kit each
local TURN_TIME = 45
local JAM_TIME = 7.0  -- doubled: give people a fair chance to notice + react with a Jammer
local FAVOR_TIME = 15
local BOMB_TIME = 20
local START_DELAY = 6
local ROUND_END_TIME = 9

local DECK = "od_draw"
local DRAW_POS = Vector2(-80, 0)
local DISCARD_POS = Vector2(80, 0)
local PLAYED_POS = Vector2(0, -120)   -- cards sit here during the jam window
local CARD_SIZE = Vector2(100, 140)
local SEAT_RADIUS = 310

local WEAPONS = { "pistol_9mm", "heavy_revolver", "machine_pistol", "compact_smg", "tactical_handgun" }

-- Distinct per-player colors (by join order, so nobody shares one) shared with
-- user.lua for the world-space cursors and used for the nicknames in the panels
-- and at the seats. Stored/sent as hex.
local PLAYER_HEX = {
    "#f25a5a", "#59bffa", "#fad047", "#85e56b", "#d972ea",
    "#fa9933", "#66f2d1", "#fa8cbf", "#99a6fa", "#c0d24d",
}
local function hex_to_color(hex)
    local r = tonumber(hex:sub(2, 3), 16) / 255
    local g = tonumber(hex:sub(4, 5), 16) / 255
    local b = tonumber(hex:sub(6, 7), 16) / 255
    return Color(r, g, b, 1)
end

-- (MAX_SEATS is declared once, near MIN_PLAYERS above - this used to redeclare
-- it as 8 here, silently shadowing the real 5-seat cap for every avatar-slot
-- loop and HUD text below it; that's why removing it fixes both, not just one.)
local DROP_RADIUS = 220

cl_local_rot = 0.0  -- LOCAL counter-rotation (radians); never networked
local NAMEABLE = { "disarm_kit", "ambush", "retreat", "supply_request", "mission_shuffle",
    "recon_drone", "signal_jammer", "pistol_9mm", "heavy_revolver", "machine_pistol",
    "compact_smg", "tactical_handgun" }

-- ---------- HOST state ----------
players = {}         -- steam_id -> { name, wins }
connected = {}
seated = {}          -- seat order (fixed for the round)
waiting = {}
alive = {}           -- steam_id -> true
phase = "lobby"      -- lobby | starting | playing | roundend
turn_idx = 1
turns_owed = 1
pending = nil        -- { kind, by, data, jams, uids } during a jam window
awaiting_favor = nil -- { giver, receiver }
awaiting_bomb = nil  -- { id, bomb, disarm }

-- ---------- CLIENT mirror ----------
cl_phase = "lobby"
cl_seated = {}
cl_alive = {}
cl_turn = ""
cl_owed = 1
cl_names = {}
cl_colors = {}       -- steam_id -> hex; per-player color shared with user.lua cursors
cl_wins = {}
cl_pending = nil     -- { kind, by, jams }
cl_favor = nil       -- { giver, receiver }
cl_bomb_holder = ""
cl_zoom = 0.6        -- local camera zoom; starts fully zoomed out (see world.lua)

-- Local (unsynced, cosmetic) countdown for the jam window, so players can see
-- exactly how long they still have to react with a Signal Jammer.
cl_jam_time_left = 0.0
cl_jam_shown_sec = -1
cl_jam_last_jams = -1

local HUD = ""
local SEATP = ""
local SCORE = ""
local PICKER = ""
local PEEK = ""
local BOMBP = ""

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

-- Ticks the local (cosmetic, unsynced) jam-window countdown shown in the HUD.
-- Only touches the panel when the displayed whole second actually changes.
function _process(delta, inputs)
    if cl_pending and cl_jam_time_left > 0 then
        cl_jam_time_left = math.max(0, cl_jam_time_left - delta)
        local shown = math.ceil(cl_jam_time_left)
        if shown ~= cl_jam_shown_sec then
            cl_jam_shown_sec = shown
            refresh_hud()
        end
    end
    return inputs
end

local function lua_shuffle(list)
    for i = #list, 2, -1 do
        local j = math.random(1, i)
        list[i], list[j] = list[j], list[i]
    end
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

local function alive_count()
    local n = 0
    for _, id in ipairs(seated) do
        if alive[id] then n = n + 1 end
    end
    return n
end

local function discard_jitter()
    return Vector2(DISCARD_POS.x + math.random(-12, 12), DISCARD_POS.y + math.random(-9, 9))
end

-- Find `count` uids of a card id inside a player's hand (host sees identities).
local function find_in_hand(steam_id, card_id, count)
    local found = {}
    for _, entry in ipairs(card_get_hand(steam_id)) do
        if entry.card_id == card_id then
            table.insert(found, entry.uid)
            if #found >= count then break end
        end
    end
    return found
end

local function card_type(card_id)
    return tostring(get_card_keyword(card_id, "type") or "")
end

function announce(text)
    run_network_function(name, "announce_ALL", { text })
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

-- =============================================================================
-- HOST: state broadcast
-- =============================================================================
function broadcast_state(target)
    if not IS_HOST then return end
    local wins = {}
    local names = {}
    for id, p in pairs(players) do
        wins[id] = p.wins
        names[id] = p.name
    end
    local pending_info = nil
    if pending then
        pending_info = { kind = pending.kind, by = pending.by, jams = pending.jams }
    end
    local favor_info = nil
    if awaiting_favor then
        favor_info = { giver = awaiting_favor.giver, receiver = awaiting_favor.receiver }
    end
    run_network_function(name, "sync_ALL", { {
        phase = phase,
        seated = seated,
        alive = alive,
        turn = current_turn_id(),
        owed = turns_owed,
        names = names,
        wins = wins,
        colors = assign_colors(),
        pending = pending_info,
        favor = favor_info,
        bomb_holder = awaiting_bomb and awaiting_bomb.id or "",
    } }, target or "")
end

-- =============================================================================
-- HOST: seating & round flow
-- =============================================================================
function sit_HOST(sender_id)
    if not IS_HOST or not players[sender_id] then return end
    if list_contains(seated, sender_id) or list_contains(waiting, sender_id) then return end
    if (phase == "lobby" or phase == "starting") and #seated < MAX_SEATS then
        table.insert(seated, sender_id)
        try_start()
    else
        table.insert(waiting, sender_id)
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
            stop_timer("od_start")
        end
    end
    broadcast_state()
end

function try_start()
    if not IS_HOST or phase ~= "lobby" or #seated < MIN_PLAYERS then return end
    phase = "starting"
    start_timer({
        timer_id = "od_start",
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
    alive = {}
    for _, id in ipairs(seated) do alive[id] = true end

    -- Action/weapon pool (no bombs, no disarms yet).
    local pool = {}
    local function add(id, n) for _ = 1, n do table.insert(pool, id) end end
    add("ambush", 4); add("retreat", 4); add("supply_request", 4)
    add("mission_shuffle", 4); add("recon_drone", 5); add("signal_jammer", 5)
    for _, w in ipairs(WEAPONS) do add(w, 4) end
    lua_shuffle(pool)

    -- Deck order is built ENTIRELY here on the host (it never leaves the host):
    -- first every player's opening 6 (5 random + 1 guaranteed Disarm Kit), then
    -- the rest with the Time Bombs and spare Disarm Kits shuffled in.
    local order = {}
    for _ = 1, #seated do
        for _ = 1, HAND_SIZE do
            table.insert(order, table.remove(pool))
        end
        table.insert(order, "disarm_kit")
    end
    local rest = {}
    for _, id in ipairs(pool) do table.insert(rest, id) end
    for _ = 1, #seated - 1 do table.insert(rest, "time_bomb") end
    for _ = 1, math.max(math.min(2, 6 - #seated), 0) do table.insert(rest, "disarm_kit") end
    lua_shuffle(rest)
    for _, id in ipairs(rest) do table.insert(order, id) end

    card_create_deck({
        name = DECK,
        position = DRAW_POS,
        cards = order,
        size = CARD_SIZE,
        visibility = "owner",
        show_count = true,
    })
    play_sound("card_shuffle") -- everyone hears the supply deck being prepped + dealt
    for _, id in ipairs(seated) do
        for _ = 1, HAND_SIZE + 1 do
            card_draw(DECK, id)
        end
    end

    phase = "playing"
    turn_idx = 1
    turns_owed = 1
    pending = nil
    awaiting_favor = nil
    awaiting_bomb = nil
    restart_turn_timer()
    announce("Mission start! " .. tostring(#seated - 1) .. " Time Bomb(s) are hidden in the deck.")
    broadcast_state()
end

function restart_turn_timer()
    if not IS_HOST then return end
    stop_timer("od_turn")
    start_timer({
        timer_id = "od_turn",
        entity_name = name,
        function_name = "turn_timeout",
        wait_time = TURN_TIME,
        duration = TURN_TIME,
    })
end

function turn_timeout(args)
    if not IS_HOST or phase ~= "playing" then return end
    if pending or awaiting_favor or awaiting_bomb then return end -- their own timers run
    draw_card_HOST(current_turn_id())
end

-- Move to the next living agent (owing one normal turn).
function advance_turn()
    if alive_count() == 0 then return end
    repeat
        turn_idx = (turn_idx % #seated) + 1
    until alive[seated[turn_idx]]
    turns_owed = 1
    restart_turn_timer()
end

-- One owed turn was consumed without an explosion.
function finish_turn_step()
    turns_owed = turns_owed - 1
    if turns_owed > 0 then
        restart_turn_timer() -- same player keeps playing (Ambush debt)
    else
        advance_turn()
    end
end

-- =============================================================================
-- HOST: intents
-- =============================================================================
function play_action_HOST(sender_id, data)
    if not IS_HOST or phase ~= "playing" then return end
    if pending or awaiting_favor or awaiting_bomb then return end
    if sender_id ~= current_turn_id() or not alive[sender_id] then return end
    local uid = data and data.uid or ""
    local card_id = tostring(card_uid_info(uid).card_id or "")
    local owner = tostring(card_uid_info(uid).owner or "")
    if owner ~= sender_id or card_id == "" then return end
    local kind = card_type(card_id)
    if kind ~= "attack" and kind ~= "skip" and kind ~= "favor"
        and kind ~= "shuffle" and kind ~= "future" then return end
    local target = data and tostring(data.target or "") or ""
    if kind == "favor" then
        if target == sender_id or not alive[target] then return end
    end
    card_play(uid, PLAYED_POS, true)
    play_sound("card_flip")
    open_jam_window({ kind = kind, by = sender_id, data = { target = target }, jams = 0, uids = { uid } })
end

-- Every rejection below tells the clicking player WHY, via combo_rejected_ALL
-- (targeted, so only they see it) - a silent `return` here is exactly what
-- makes "I click Pair(2)/Triple(3) and nothing happens" impossible to debug.
function combo_HOST(sender_id, data)
    if not IS_HOST then return end
    local function reject(reason)
        run_network_function(name, "combo_rejected_ALL", { reason }, sender_id)
    end
    if phase ~= "playing" then reject("The mission isn't in play right now.") return end
    if pending then reject("Wait for the current jam window to resolve first.") return end
    if awaiting_favor then reject("Wait for the pending Supply Request to resolve first.") return end
    if awaiting_bomb then reject("Wait for the pending Time Bomb to resolve first.") return end
    if sender_id ~= current_turn_id() then reject("It's not your turn.") return end
    if not alive[sender_id] then reject("You're out of the mission.") return end
    local weapon = tostring(data and data.weapon or "")
    local count = tonumber(data and data.count or 0) or 0
    local target = tostring(data and data.target or "")
    local named = tostring(data and data.named or "")
    if not list_contains(WEAPONS, weapon) then reject("That's not a weapon card.") return end
    if count ~= 2 and count ~= 3 then reject("Invalid combo size.") return end
    if target == "" or target == sender_id or not alive[target] then
        reject("Pick a valid, living target.") return
    end
    if count == 3 and not list_contains(NAMEABLE, named) then reject("Pick a valid card to name.") return end
    local uids = find_in_hand(sender_id, weapon, count)
    if #uids < count then
        reject("You no longer have " .. count .. " identical " ..
            (get_card_info(weapon).name or "weapons") .. " - someone may have taken one.")
        return
    end
    for i, uid in ipairs(uids) do
        card_play(uid, Vector2(PLAYED_POS.x + (i - (count + 1) / 2) * 34, PLAYED_POS.y), true)
    end
    play_sound("card_flip")
    -- Build the kind explicitly: `count` arrives over the network as a FLOAT (2.0),
    -- so "combo" .. count would be "combo2.0" and never match apply_action's
    -- "combo2"/"combo3" - that's exactly why the steal silently did nothing.
    open_jam_window({ kind = (count == 3) and "combo3" or "combo2", by = sender_id,
        data = { target = target, named = named, weapon = weapon }, jams = 0, uids = uids })
end

function combo_rejected_ALL(sender_id, reason)
    announce_local(tostring(reason or "That combo can't be played right now."))
end

function open_jam_window(new_pending)
    pending = new_pending
    stop_timer("od_jam")
    start_timer({
        timer_id = "od_jam",
        entity_name = name,
        function_name = "jam_timeout",
        wait_time = JAM_TIME,
        duration = JAM_TIME,
    })
    broadcast_state()
end

function jam_HOST(sender_id, data)
    if not IS_HOST or phase ~= "playing" or not pending then return end
    if not alive[sender_id] then return end
    local uid = data and data.uid or ""
    local info = card_uid_info(uid)
    if tostring(info.owner or "") ~= sender_id then return end
    if card_type(tostring(info.card_id or "")) ~= "nope" then return end
    card_play(uid, Vector2(PLAYED_POS.x, PLAYED_POS.y - 40 - pending.jams * 16), true)
    play_sound("card_flip")
    table.insert(pending.uids, uid)
    pending.jams = pending.jams + 1
    local jammer = players[sender_id] and players[sender_id].name or "?"
    announce(jammer .. " played a SIGNAL JAMMER!" ..
        (pending.jams % 2 == 1 and " Action canceled..." or " Jam neutralized - action is back on!"))
    open_jam_window(pending) -- restart the window: jammers can jam jammers
end

function jam_timeout(args)
    if not IS_HOST or not pending then return end
    local p = pending
    pending = nil
    stop_timer("od_jam")
    -- The window closed: slide everything played into the discard pile.
    for _, uid in ipairs(p.uids) do
        card_move(uid, discard_jitter(), 0.3)
    end
    if p.jams % 2 == 1 then
        announce("The action was JAMMED - no effect.")
        broadcast_state()
        return
    end
    apply_action(p)
    broadcast_state()
end

function apply_action(p)
    local by_name = players[p.by] and players[p.by].name or "?"
    if p.kind == "attack" then
        announce(by_name .. " sets an AMBUSH - next agent owes two turns!")
        advance_turn()
        turns_owed = 2
    elseif p.kind == "skip" then
        announce(by_name .. " retreats.")
        finish_turn_step()
    elseif p.kind == "shuffle" then
        card_shuffle(DECK)
        play_sound("card_shuffle")
        announce(by_name .. " shuffled the mission deck.")
    elseif p.kind == "future" then
        card_peek(DECK, 3, p.by)
        announce(by_name .. " launches a recon drone...")
    elseif p.kind == "favor" then
        local giver = p.data.target
        if alive[giver] then
            awaiting_favor = { giver = giver, receiver = p.by }
            stop_timer("od_favor")
            start_timer({
                timer_id = "od_favor",
                entity_name = name,
                function_name = "favor_timeout",
                wait_time = FAVOR_TIME,
                duration = FAVOR_TIME,
            })
            announce(by_name .. " demands supplies from " ..
                (players[giver] and players[giver].name or "?") .. "!")
        end
    elseif p.kind == "combo2" then
        local stolen = card_transfer("", p.data.target, p.by)
        if stolen ~= "" then
            announce(by_name .. " steals a random card with a pair of " ..
                (get_card_info(p.data.weapon).name or "weapons") .. "!")
        end
    elseif p.kind == "combo3" then
        local uids = find_in_hand(p.data.target, p.data.named, 1)
        if #uids > 0 then
            card_transfer(uids[1], p.data.target, p.by)
            announce(by_name .. " names \"" .. (get_card_info(p.data.named).name or p.data.named) ..
                "\" - and takes it!")
        else
            announce(by_name .. " names \"" .. (get_card_info(p.data.named).name or p.data.named) ..
                "\" - but " .. (players[p.data.target] and players[p.data.target].name or "?") ..
                " has none. Wasted!")
        end
    end
end

function give_card_HOST(sender_id, data)
    if not IS_HOST or not awaiting_favor then return end
    if sender_id ~= awaiting_favor.giver then return end
    local uid = data and data.uid or ""
    if tostring(card_uid_info(uid).owner or "") ~= sender_id then return end
    local receiver = awaiting_favor.receiver
    awaiting_favor = nil
    stop_timer("od_favor")
    card_transfer(uid, sender_id, receiver)
    broadcast_state()
end

function favor_timeout(args)
    if not IS_HOST or not awaiting_favor then return end
    local giver = awaiting_favor.giver
    local receiver = awaiting_favor.receiver
    awaiting_favor = nil
    card_transfer("", giver, receiver) -- too slow: random card
    broadcast_state()
end

function draw_card_HOST(sender_id)
    if not IS_HOST or phase ~= "playing" then return end
    if pending or awaiting_favor or awaiting_bomb then return end
    if sender_id ~= current_turn_id() or not alive[sender_id] then return end
    local uid = card_draw(DECK, sender_id)
    if uid == "" then
        finish_turn_step()
        broadcast_state()
        return
    end
    play_sound("card_taking_from_deck")
    local card_id = tostring(card_uid_info(uid).card_id or "")
    if card_type(card_id) == "bomb" then
        local drawer = players[sender_id] and players[sender_id].name or "?"
        local disarms = find_in_hand(sender_id, "disarm_kit", 1)
        -- Show the bomb to everyone: it leaves the hand and lands on the table.
        card_play(uid, Vector2(0, 0), true)
        play_sound("card_flip")
        if #disarms == 0 then
            explode(sender_id, uid)
        else
            awaiting_bomb = { id = sender_id, bomb = uid, disarm = disarms[1] }
            announce(drawer .. " drew a TIME BOMB - disarming it...")
            stop_timer("od_bomb")
            start_timer({
                timer_id = "od_bomb",
                entity_name = name,
                function_name = "bomb_timeout",
                wait_time = BOMB_TIME,
                duration = BOMB_TIME,
            })
        end
    else
        finish_turn_step()
    end
    broadcast_state()
end

function place_bomb_HOST(sender_id, data)
    if not IS_HOST or not awaiting_bomb then return end
    if sender_id ~= awaiting_bomb.id then return end
    local slot = tostring(data and data.slot or "random")
    local index = -1
    if slot == "top" then index = 0
    elseif slot == "second" then index = 1
    elseif slot == "middle" then index = math.floor(card_deck_count(DECK) / 2)
    elseif slot == "bottom" then index = 999999 end
    resolve_bomb(index)
end

function bomb_timeout(args)
    if not IS_HOST or not awaiting_bomb then return end
    resolve_bomb(-1) -- too slow: hidden somewhere random
end

function resolve_bomb(index)
    local holder = awaiting_bomb.id
    local bomb = awaiting_bomb.bomb
    local disarm = awaiting_bomb.disarm
    awaiting_bomb = nil
    stop_timer("od_bomb")
    -- The kit is spent openly; the bomb vanishes back into the deck.
    card_play(disarm, discard_jitter(), true)
    play_sound("card_flip")
    card_move(disarm, discard_jitter(), 0.25)
    card_return_to_deck(bomb, DECK, index)
    announce((players[holder] and players[holder].name or "?") ..
        " DEFUSED the bomb and hid it back in the deck!")
    finish_turn_step()
    broadcast_state()
end

function explode(victim, bomb_uid)
    alive[victim] = nil
    stop_timer("od_turn")
    announce("*** " .. (players[victim] and players[victim].name or "?") ..
        " had no Disarm Kit. BOOM - out of the mission! ***")
    -- Their equipment is lost with them.
    card_discard(bomb_uid)
    for _, entry in ipairs(card_get_hand(victim)) do
        card_discard(entry.uid)
    end
    if alive_count() <= 1 then
        local winner = ""
        for _, id in ipairs(seated) do
            if alive[id] then winner = id end
        end
        end_round(winner)
        return
    end
    -- If it was the victim's turn, the mission moves on.
    if current_turn_id() == victim then
        advance_turn()
    end
end

function end_round(winner_id)
    if not IS_HOST then return end
    stop_timer("od_turn")
    stop_timer("od_jam")
    stop_timer("od_favor")
    stop_timer("od_bomb")
    pending = nil
    awaiting_favor = nil
    awaiting_bomb = nil
    phase = "roundend"
    if players[winner_id] then
        players[winner_id].wins = players[winner_id].wins + 1
    end
    run_network_function(name, "round_over_ALL",
        { players[winner_id] and players[winner_id].name or "Nobody" })
    start_timer({
        timer_id = "od_next",
        entity_name = name,
        function_name = "after_round",
        wait_time = ROUND_END_TIME,
        duration = ROUND_END_TIME,
    })
    broadcast_state()
end

function after_round(args)
    if not IS_HOST then return end
    for _, id in ipairs(waiting) do
        if players[id] and not list_contains(seated, id) and #seated < MAX_SEATS then
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
    broadcast_state(steam_id)
    broadcast_state()
end

function _on_user_disconnected(steam_id, nickname)
    if not IS_HOST then return end
    players[steam_id] = nil
    list_remove(connected, steam_id)
    list_remove(waiting, steam_id)
    if awaiting_favor and (awaiting_favor.giver == steam_id or awaiting_favor.receiver == steam_id) then
        awaiting_favor = nil
        stop_timer("od_favor")
    end
    if awaiting_bomb and awaiting_bomb.id == steam_id then
        awaiting_bomb = nil
        stop_timer("od_bomb")
    end
    local seat = 0
    for i, v in ipairs(seated) do
        if v == steam_id then seat = i end
    end
    if seat > 0 then
        local was_turn = (steam_id == current_turn_id())
        local was_alive = alive[steam_id]
        alive[steam_id] = nil
        table.remove(seated, seat)
        if seat <= turn_idx and turn_idx > 1 then
            turn_idx = turn_idx - 1
        end
        if phase == "playing" and was_alive then
            if alive_count() <= 1 then
                local winner = ""
                for _, id in ipairs(seated) do
                    if alive[id] then winner = id end
                end
                if winner ~= "" then
                    end_round(winner)
                else
                    phase = "lobby"
                    card_destroy_all()
                end
            elseif was_turn then
                turn_idx = math.max(turn_idx, 1)
                if not alive[seated[turn_idx]] then
                    advance_turn()
                else
                    turns_owed = 1
                    restart_turn_timer()
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
    cl_alive = state.alive or {}
    cl_turn = state.turn or ""
    cl_owed = state.owed or 1
    cl_names = state.names or {}
    cl_wins = state.wins or {}
    cl_colors = state.colors or {}
    cl_pending = state.pending
    cl_favor = state.favor
    cl_bomb_holder = state.bomb_holder or ""

    -- A new jam window (or a jam that reopened it) resets the local countdown.
    if cl_pending then
        local jams = cl_pending.jams or 0
        if jams ~= cl_jam_last_jams then
            cl_jam_last_jams = jams
            cl_jam_time_left = JAM_TIME
            cl_jam_shown_sec = -1
        end
    else
        cl_jam_last_jams = -1
    end

    local count = #cl_seated
    local my_seat = 0
    for i, id in ipairs(cl_seated) do
        local angle = math.pi / 2 + (i - 1) * (2 * math.pi / math.max(count, 1))
        card_set_player_anchor(id, Vector2(math.cos(angle) * SEAT_RADIUS, math.sin(angle) * SEAT_RADIUS))
        if id == LOCAL_STEAM_ID then my_seat = i end
    end
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

    -- Turn marker dot in front of the active seat.
    local marker_visible = cl_phase == "playing" and cl_turn ~= ""
    local marker_pos = Vector2(0, 0)
    for i, id in ipairs(cl_seated) do
        if id == cl_turn then
            local angle = math.pi / 2 + (i - 1) * (2 * math.pi / math.max(count, 1))
            marker_pos = Vector2(math.cos(angle) * (SEAT_RADIUS - 62), math.sin(angle) * (SEAT_RADIUS - 62))
        end
    end
    set_image({
        name = "od_turn_marker",
        image_path = "cursor",
        position = marker_pos,
        rotation = cl_local_rot,
        scale = Vector2(34, 34),
        modulate = Color(1, 0.55, 0.15, 1),
        visible = marker_visible,
        z_index = 50,
    })

    refresh_hud()
    update_table_buttons()
    refresh_scoreboard()
    refresh_bomb_panel()
    refresh_seat_avatars()
    -- Dropping a dragged card near the middle of the table plays it.
    card_set_drop_zone(Vector2(0, -40), DROP_RADIUS)
end

-- Steam avatar + name for each seated agent, on the outer ring of their seat.
-- Fixed slots (no create/destroy churn): unused slots are hidden.
function refresh_seat_avatars()
    local count = #cl_seated
    for i = 1, MAX_SEATS do
        local av = "seat_av_" .. i
        local nm = "seat_nm_" .. i
        if i <= count then
            local id = cl_seated[i]
            local angle = math.pi / 2 + (i - 1) * (2 * math.pi / math.max(count, 1))
            local outer = Vector2(math.cos(angle) * (SEAT_RADIUS + 76), math.sin(angle) * (SEAT_RADIUS + 76))
            local dead = (cl_phase == "playing" and not cl_alive[id])
            set_image({ name = av, image_path = id, position = outer, rotation = cl_local_rot,
                scale = Vector2(58, 58), z_index = 45,
                modulate = dead and Color(0.5, 0.5, 0.5, 1) or Color(1, 1, 1, 1), visible = true })
            set_label({ name = nm, text = cl_names[id] or "", position = outer + Vector2(-48, 34),
                size = Vector2(96, 20), font_size = 14, rotation = cl_local_rot,
                modulate = hex_to_color(cl_colors[id] or "#ffffff"), visible = true })
        else
            set_image({ name = av, visible = false })
            set_label({ name = nm, visible = false })
        end
    end
end

function _on_loaded_avatar(steam_id)
    refresh_seat_avatars()
end

-- Dragging a hand card onto the table plays it, exactly like tapping it.
function _on_hand_card_dropped(uid, card_id)
    _on_hand_card_clicked(uid, card_id)
end

function announce_ALL(sender_id, text)
    create_panel({
        title = "Operation: Detonate",
        text = "[center]" .. text .. "[/center]",
        countdown = 4,
        close = false,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_announce",
        minimum_size = Vector2(380, 110),
        offset_ratio = Vector2(1, 2),
    })
end

function round_over_ALL(sender_id, winner_name)
    create_panel({
        title = "Mission complete",
        text = "[center][b]" .. winner_name .. "[/b] is the last agent standing![/center]",
        countdown = ROUND_END_TIME - 1,
        close = false,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_round_over",
        minimum_size = Vector2(340, 140),
    })
end

function refresh_hud()
    local txt
    if cl_phase == "playing" then
        if cl_pending then
            local by = cl_names[cl_pending.by] or "?"
            local secs = math.max(0, math.ceil(cl_jam_time_left))
            txt = "[center][b]JAM WINDOW - " .. secs .. "s[/b]\n" .. by .. "'s action resolves when it runs out.\n" ..
                "Click a Signal Jammer in your hand to cancel it! (jams: " ..
                tostring(cl_pending.jams) .. ")[/center]"
        elseif cl_favor then
            txt = "[center][b]" .. (cl_names[cl_favor.giver] or "?") ..
                "[/b] must hand a card to [b]" .. (cl_names[cl_favor.receiver] or "?") .. "[/b][/center]"
        elseif cl_bomb_holder ~= "" then
            txt = "[center][b]" .. (cl_names[cl_bomb_holder] or "?") ..
                "[/b] is disarming a TIME BOMB...[/center]"
        elseif cl_turn == LOCAL_STEAM_ID then
            txt = "[center][b]YOUR TURN[/b] - play action cards, then click the deck to draw" ..
                (cl_owed > 1 and (" (" .. cl_owed .. " turns owed!)") or "") .. "[/center]"
        else
            txt = "[center][b]" .. (cl_names[cl_turn] or "?") .. "[/b]'s turn" ..
                (cl_owed > 1 and (" (owes " .. cl_owed .. " turns)") or "") .. "[/center]"
        end
    elseif cl_phase == "starting" then
        txt = "[center]Mission starting... sit down now to join![/center]"
    elseif cl_phase == "roundend" then
        txt = "[center]Mission finished - debriefing.[/center]"
    else
        txt = "[center][b]Operation: Detonate[/b]\nSit at the table (" .. #cl_seated .. "/" ..
            MIN_PLAYERS .. "+ needed, max " .. MAX_SEATS .. ")[/center]"
    end
    if is_panel_exists(HUD) then
        update_panel_settings(HUD, { text = txt })
    else
        HUD = create_panel({
            title = "Operation: Detonate",
            text = txt,
            close = false,
            set_time = false,
            resizable = false,
            no_multiple_tag = "od_hud",
            minimum_size = Vector2(430, 100),
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
        text = round_running and "Sit next mission" or "Sit at table",
    })
    set_button({
        name = "_stand_btn",
        visible = am_seated and (cl_phase == "lobby" or cl_phase == "starting"),
    })
end

function sit_click(args) run_network_function(name, "sit_HOST", {}) end
function stand_click(args) run_network_function(name, "stand_HOST", {}) end

-- Local camera zoom perk (magnification factor: bigger = more zoomed in).
function zoom_in_click(args)
    cl_zoom = math.min(cl_zoom + 0.2, 3.6)  -- ceiling; start is fully zoomed out (0.6)
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
        local status = cl_alive[id] and (tostring(counts[id] or 0) .. " cards") or "EXPLODED"
        local hex = cl_colors[id] or "#ffffff"
        lines = lines .. marker .. "[color=" .. hex .. "]" .. (cl_names[id] or id) .. "[/color]" ..
            "  -  " .. status .. ", " .. tostring(cl_wins[id] or 0) .. " wins\n"
    end
    if lines == "" then lines = "(nobody is seated yet)" end
    if is_panel_exists(SCORE) then
        update_panel_settings(SCORE, { text = lines })
    else
        SCORE = create_panel({
            title = "Agents",
            text = lines,
            close = false,
            set_time = false,
            resizable = false,
            no_multiple_tag = "od_score",
            minimum_size = Vector2(270, 170),
            offset_ratio = Vector2(2, 0),
        })
    end
end

-- Bomb placement panel: only for the agent who is defusing right now.
function refresh_bomb_panel()
    local mine = cl_bomb_holder == LOCAL_STEAM_ID
    if not mine then
        if is_panel_exists(BOMBP) then close_panel(BOMBP) end
        return
    end
    if is_panel_exists(BOMBP) then return end
    BOMBP = create_panel({
        title = "Bomb defused!",
        text = "[center]Where do you hide the Time Bomb?[/center]",
        close = false,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_bomb",
        countdown = BOMB_TIME,
        minimum_size = Vector2(260, 300),
    })
    for _, slot in ipairs({ "top", "second", "middle", "bottom", "random" }) do
        add_button_to_panel(BOMBP, {
            text = string.upper(slot),
            entity_name = name,
            function_name = "bomb_slot_click",
            extra_args = { slot = slot },
            color = Color(0.75, 0.4, 0.2, 1),
            is_vertical = true,
        })
    end
end

function bomb_slot_click(args)
    run_network_function(name, "place_bomb_HOST", { slot = args.extra_args.slot })
    if is_panel_exists(BOMBP) then close_panel(BOMBP) end
end

-- =============================================================================
-- CLIENT: hand & deck interaction
-- =============================================================================
local pending_weapon = ""   -- combo flow scratch (local only)
local pending_count = 2
local pending_target = ""

function _on_hand_card_clicked(uid, card_id)
    if card_id == "" then return end
    -- 1) Someone demanded supplies from ME: clicking a card gives THAT card.
    if cl_favor and cl_favor.giver == LOCAL_STEAM_ID then
        run_network_function(name, "give_card_HOST", { uid = uid })
        return
    end
    -- 2) Jam window: clicking my Signal Jammer cancels the pending action.
    if cl_pending then
        if get_card_keyword(card_id, "type") == "nope" then
            run_network_function(name, "jam_HOST", { uid = uid })
        end
        return
    end
    -- 3) Normal turn actions.
    if cl_phase ~= "playing" or cl_turn ~= LOCAL_STEAM_ID then return end
    local kind = tostring(get_card_keyword(card_id, "type") or "")
    if kind == "attack" or kind == "skip" or kind == "shuffle" or kind == "future" then
        run_network_function(name, "play_action_HOST", { uid = uid, target = "" })
    elseif kind == "favor" then
        show_target_picker("supply_target_click", { uid = uid },
            "Who must hand you a card?")
    elseif kind == "weapon" then
        show_combo_panel(card_id)
    elseif kind == "nope" then
        announce_local("Signal Jammers are reactive - use one while someone else's action is resolving.")
    elseif kind == "disarm" then
        announce_local("Disarm Kits trigger automatically when you draw a Time Bomb.")
    end
end

function _on_deck_clicked(deck_name)
    if deck_name ~= DECK then return end
    if cl_phase ~= "playing" or cl_turn ~= LOCAL_STEAM_ID then return end
    if cl_pending or cl_favor or cl_bomb_holder ~= "" then return end
    run_network_function(name, "draw_card_HOST", {})
end

function announce_local(text)
    create_panel({
        title = "Hint",
        text = "[center]" .. text .. "[/center]",
        countdown = 4,
        close = true,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_hint",
        minimum_size = Vector2(340, 110),
    })
end

-- Generic "pick an agent" popup.
function show_target_picker(callback_name, extra, title_text)
    -- Nobody eligible: say so instead of opening an empty, seemingly-broken panel.
    local any_target = false
    for _, id in ipairs(cl_seated) do
        if id ~= LOCAL_STEAM_ID and cl_alive[id] then any_target = true break end
    end
    if not any_target then
        announce_local("No valid target right now (everyone else is out or not seated).")
        return
    end
    if is_panel_exists(PICKER) then close_panel(PICKER) end
    PICKER = create_panel({
        title = "Choose target",
        text = "[center]" .. title_text .. "[/center]",
        close = true,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_picker",
        minimum_size = Vector2(260, 240),
    })
    for _, id in ipairs(cl_seated) do
        if id ~= LOCAL_STEAM_ID and cl_alive[id] then
            local merged = { target = id }
            for k, v in pairs(extra) do merged[k] = v end
            add_button_to_panel(PICKER, {
                text = cl_names[id] or id,
                entity_name = name,
                function_name = callback_name,
                extra_args = merged,
                color = Color(0.35, 0.5, 0.75, 1),
                is_vertical = true,
            })
        end
    end
end

function supply_target_click(args)
    run_network_function(name, "play_action_HOST", {
        uid = args.extra_args.uid,
        target = args.extra_args.target,
    })
    if is_panel_exists(PICKER) then close_panel(PICKER) end
end

-- Weapon combo flow: pick pair/triple, then target, then (for 3) a card name.
function show_combo_panel(weapon_id)
    local mine = 0
    for _, entry in ipairs(card_get_hand(LOCAL_STEAM_ID)) do
        if entry.card_id == weapon_id then mine = mine + 1 end
    end
    if mine < 2 then
        announce_local("Weapons have no power alone - collect 2 or 3 identical ones.")
        return
    end
    pending_weapon = weapon_id
    if is_panel_exists(PICKER) then close_panel(PICKER) end
    PICKER = create_panel({
        title = get_card_info(weapon_id).name or "Weapon combo",
        text = "[center]Play a set of identical weapons:[/center]",
        close = true,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_picker",
        minimum_size = Vector2(280, 200),
    })
    add_button_to_panel(PICKER, {
        text = "Pair (2) - steal a RANDOM card",
        entity_name = name,
        function_name = "combo_count_click",
        extra_args = { count = 2 },
        color = Color(0.5, 0.5, 0.6, 1),
        is_vertical = true,
    })
    if mine >= 3 then
        add_button_to_panel(PICKER, {
            text = "Triple (3) - NAME a card to take",
            entity_name = name,
            function_name = "combo_count_click",
            extra_args = { count = 3 },
            color = Color(0.65, 0.55, 0.3, 1),
            is_vertical = true,
        })
    end
end

function combo_count_click(args)
    pending_count = args.extra_args.count
    show_target_picker("combo_target_click", {},
        pending_count == 2 and "Steal a random card from..." or "Demand a named card from...")
end

function combo_target_click(args)
    pending_target = args.extra_args.target
    if pending_count == 2 then
        run_network_function(name, "combo_HOST", {
            weapon = pending_weapon, count = 2, target = pending_target, named = "",
        })
        if is_panel_exists(PICKER) then close_panel(PICKER) end
    else
        show_named_picker()
    end
end

function show_named_picker()
    if is_panel_exists(PICKER) then close_panel(PICKER) end
    PICKER = create_panel({
        title = "Name a card",
        text = "[center]If they have it, they must hand it over:[/center]",
        close = true,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_picker",
        minimum_size = Vector2(300, 420),
    })
    for _, id in ipairs(NAMEABLE) do
        add_button_to_panel(PICKER, {
            text = get_card_info(id).name or id,
            entity_name = name,
            function_name = "named_card_click",
            extra_args = { named = id },
            color = Color(0.4, 0.45, 0.55, 1),
            is_vertical = true,
        })
    end
end

function named_card_click(args)
    run_network_function(name, "combo_HOST", {
        weapon = pending_weapon, count = 3, target = pending_target,
        named = args.extra_args.named,
    })
    if is_panel_exists(PICKER) then close_panel(PICKER) end
end

-- Recon Drone result (arrives only on the peeking peer).
function _on_card_peek(deck_name, ids)
    if is_panel_exists(PEEK) then close_panel(PEEK) end
    local lines = ""
    for i, id in ipairs(ids) do
        lines = lines .. tostring(i) .. ". " .. (get_card_info(id).name or id) .. "\n"
    end
    if lines == "" then lines = "(the deck is empty)" end
    PEEK = create_panel({
        title = "Recon Drone - top of the deck",
        text = lines,
        countdown = 8,
        close = true,
        set_time = false,
        resizable = false,
        no_multiple_tag = "od_peek",
        minimum_size = Vector2(300, 180),
    })
end

-- Keep the scoreboard counters fresh on every card movement.
function _on_card_drawn(owner_id, deck_name, uid) refresh_scoreboard() end
function _on_card_played(owner_id, uid, card_id) refresh_scoreboard() end
function _on_card_removed(uid) refresh_scoreboard() end
function _on_card_transferred(from_id, to_id, uid) refresh_scoreboard() end

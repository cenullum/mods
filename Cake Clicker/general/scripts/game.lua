network_mode = 1
singleton_name = "game"

-- =============================================================================
-- Cake Clicker - the referee. Runs on the HOST; every other peer only draws.
--
-- What it owns:
--   * the settings board (how many bots, how good, how the game ends),
--   * who is in the room and who sits where,
--   * the phases of a match: countdown -> eating -> market -> eating ... -> over,
--   * every player's books: score, crowns, coins, upgrades, pocket items,
--   * every request a client sends (press, buy, use, settings, start, again).
--
-- What it asks the other host scripts to do (each is its own entity, so they
-- talk through run_function and plain tables):
--   -cake_table  the cake on the table: slices, bites, turning, item effects
--   -market      the cards between two cakes
--   -bots        the bots' brains; they only DECIDE, this script carries out their
--                actions through the same checks a player's request goes through
--
-- Ten times a second it sends one state message to every peer, tagged
-- "cc_view": every *_view script takes the part it draws. Upgrades and pocket
-- items go out only when they change, tagged "cc_pockets".
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local STEP = CATALOG.timing.step
local SNAPSHOT_EVERY = CATALOG.timing.snapshot
local START_COUNTDOWN = CATALOG.timing.start_countdown
local PRESSES_PER_SECOND = CATALOG.timing.presses_per_second
local MAX_SEATS = CATALOG.limits.max_seats
local MAX_BOTS = CATALOG.limits.max_bots
local POCKET_SIZE = CATALOG.limits.pocket_size
local ROSTER_RESEND_EVERY = 20       -- snapshots between two full copies of the roster

local ITEMS = {}
for _, item in ipairs(CATALOG.items) do ITEMS[item.id] = item end
local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end

-- the settings board; kept between games
local settings = { bots = 3, difficulty = "normal", end_mode = "time", end_value = 5 }
-- players in the room, in the order they arrived: { id = "7656...", name = "nick" }
local room = {}
-- the game being played, or nil while the room is on the settings board
local match = nil
-- what goes out with the next state message
local outbox = { events = {}, timer = 0, sequence = 0, roster_version = 0, roster_sent = -1,
    since_roster = 0, send_now = false }
local step_clock = 0

-- =============================================================================
-- Small helpers
-- =============================================================================
local function emit(kind, fields)
    local event = fields or {}
    event.k = kind
    table.insert(outbox.events, event)
end

local function whole(number) return math.floor((tonumber(number) or 0) + 0.5) end

local function pace_for(mode, value)
    local entry = CATALOG.end_values[mode]
    return entry and entry.pace[string.format("%d", value)] or 1
end

local function admin_in_room()
    for _, player in ipairs(room) do
        if is_admin(player.id) then return true end
    end
    return false
end

-- Settings and starting are the admin's call; with no admin in the room (a
-- dedicated server nobody owns right now) anyone may do it.
local function may_manage(player_id)
    return is_admin(player_id) or not admin_in_room()
end

local function seat_of_player(player_id)
    if not match then return nil end
    for _, seat in ipairs(match.seats) do
        if seat.id == player_id then return seat end
    end
    return nil
end

-- A request from a client counts only when it comes from a human who sits at the table.
local function seat_of_sender(sender_id)
    if not IS_HOST then return nil end
    local seat = seat_of_player(sender_id)
    if seat and not seat.is_bot then return seat end
    return nil
end

local function empty_upgrades()
    local levels = {}
    for _, key in ipairs(CATALOG.upgrade_order) do levels[key] = 0 end
    return levels
end

local function price_of(seat, item)
    local level = item.kind == "use" and 0 or seat.upgrades[item.id]
    return math.max(1, whole(item.price * match.unit * (item.growth or 1) ^ level))
end

local function can_hold(seat, item)
    if item.kind == "use" then return #seat.pocket < POCKET_SIZE end
    return not (item.max and seat.upgrades[item.id] >= item.max)
end

-- Ranking: by crowns first in a crown race, then by cake eaten.
local function ranking()
    local order = {}
    for _, seat in ipairs(match.seats) do table.insert(order, seat) end
    local crowns_first = match.settings.end_mode == "crowns"
    table.sort(order, function(first, second)
        if crowns_first and first.crowns ~= second.crowns then return first.crowns > second.crowns end
        if first.score ~= second.score then return first.score > second.score end
        return first.number < second.number
    end)
    return order
end

local function leader_except(seat)
    for _, other in ipairs(ranking()) do
        if other ~= seat then return other end
    end
    return nil
end

-- How far the match is, 0..1 (bots value long-term upgrades less near the end).
local function progress()
    local mode, value = match.settings.end_mode, match.settings.end_value
    if mode == "time" then return match.clock / (value * 60) end
    if mode == "cakes" then return match.cakes_done / value end
    local most = 0
    for _, seat in ipairs(match.seats) do most = math.max(most, seat.crowns) end
    return most / value
end

-- =============================================================================
-- Cakes
-- =============================================================================
-- Which cake comes next: the vanilla one first, the wedding cake as the final,
-- otherwise any other than the last one.
local function choose_next_cake()
    local mode, value = match.settings.end_mode, match.settings.end_value
    if (mode == "time" and match.final_started and not match.final_served)
        or (mode == "cakes" and match.cake_number == value - 1) then
        match.final_served = true
        return CATALOG.final_cake
    end
    if match.cake_number == 0 then return CATALOG.cakes[1] end
    local pick
    for _ = 1, 12 do
        pick = CATALOG.cakes[math.random(1, #CATALOG.cakes)]
        if pick.id ~= match.last_cake_id then break end
    end
    return pick
end

-- Puts match.next_cake on the table. The table script sizes it from how fast
-- everyone eats (their upgrades and click rate), so a cake lasts about as long
-- at any point of the game.
local function begin_cake()
    local cake = match.next_cake or choose_next_cake()
    match.next_cake = nil
    match.cake = cake
    match.last_cake_id = cake.id
    match.cake_number = match.cake_number + 1
    local eaters = {}
    for _, seat in ipairs(match.seats) do
        local clicks = 0
        if not seat.is_bot then clicks = seat.measured_clicks or 4 end
        table.insert(eaters, { seat = seat.number, upgrades = seat.upgrades, clicks = clicks, bot = seat.is_bot })
    end
    local unit = run_function("-cake_table", "start_cake", { {
        cake = cake.id, number = match.cake_number, pace = match.pace, clock = match.clock,
        difficulty = match.settings.difficulty, eaters = eaters,
    } })
    match.unit = tonumber(unit) or match.unit
    if match.cake_number > 1 then emit("cake", { c = cake.id }) end
end

-- Steam achievements for whoever won the match (bots and players who left are
-- skipped by the engine itself).
local function award_match_winner()
    local winner = ranking()[1]
    if not winner or winner.is_bot or #match.seats < 2 then return end
    add_achievement_progress("cc_wins", 1, winner.id)
    if match.settings.difficulty ~= "hard" then return end
    for _, seat in ipairs(match.seats) do
        if seat.is_bot then
            unlock_achievement("CC_WIN_HARD", winner.id)
            return
        end
    end
end

local function end_match()
    match.phase = "over"
    run_function("-market", "close", {})
    run_function("-bots", "stop", {})
    award_match_winner()
    local rows = {}
    for _, seat in ipairs(ranking()) do
        local levels = 0
        for _, key in ipairs(CATALOG.upgrade_order) do levels = levels + seat.upgrades[key] end
        table.insert(rows, { seat.number, whole(seat.score * 10), seat.crowns, seat.turns, whole(seat.spent), levels })
    end
    match.results = { rows = rows, cakes = match.cakes_done, time = whole(match.clock) }
    emit("over", {})
end

local function open_market()
    match.phase = "market"
    match.next_cake = choose_next_cake()
    local cards = 3 + math.max(0, math.floor((#match.seats - 3) / 2))
    run_function("-market", "open", { { next_cake = match.next_cake.id, cards = cards } })
    emit("market", {})
end

-- The table reports a finished cake with how much each seat ate of it.
local function finish_cake(eaten)
    match.cakes_done = match.cakes_done + 1
    local best_amount, king = -1, match.seats[1]
    for _, seat in ipairs(match.seats) do
        local amount = tonumber(eaten[seat.number]) or 0
        if amount > best_amount then best_amount, king = amount, seat end
    end
    king.crowns = king.crowns + 1
    emit("crown", { p = king.number, g = best_amount })
    if not king.is_bot then add_achievement_progress("cc_crowns", 1, king.id) end
    local settings_now = match.settings
    if settings_now.end_mode == "crowns" and king.crowns >= settings_now.end_value then return end_match() end
    if settings_now.end_mode == "cakes" and match.cakes_done >= settings_now.end_value then return end_match() end
    open_market()
end

-- =============================================================================
-- Starting a match
-- =============================================================================
local function new_seat(number, player, bot)
    return {
        number = number, id = player and player.id or ("bot" .. number),
        name = player and player.name or bot.name, short = player and player.name or bot.short,
        is_bot = bot ~= nil, bot_key = bot and bot.key or "", icon = bot and bot.icon or "",
        color = bot and bot.color or "#e23d6d", persona = bot and bot.persona or "balanced",
        score = 0, crowns = 0, coins = 0, spent = 0, turns = 0, upgrades = empty_upgrades(), pocket = {},
        butler_on = true, press_times = {}, press_budget = PRESSES_PER_SECOND, gone = false,
    }
end

local function shuffled(list)
    local copy = {}
    for index, value in ipairs(list) do copy[index] = value end
    for index = #copy, 2, -1 do
        local other = math.random(1, index)
        copy[index], copy[other] = copy[other], copy[index]
    end
    return copy
end

local function start_match()
    local humans = {}
    for _, player in ipairs(room) do
        if #humans < MAX_SEATS then table.insert(humans, player) end
    end
    if #humans == 0 then return end
    local fewest_bots = (#humans == 1) and 1 or 0
    local bot_count = math.max(fewest_bots, math.min(settings.bots, MAX_BOTS, MAX_SEATS - #humans))
    -- everyone sits in a random order; the bots are a random pick of the five
    local sitters = {}
    for _, player in ipairs(humans) do table.insert(sitters, { player = player }) end
    local bot_pool = shuffled(CATALOG.bots)
    for index = 1, bot_count do table.insert(sitters, { bot = bot_pool[index] }) end
    sitters = shuffled(sitters)
    match = {
        settings = { bots = bot_count, difficulty = settings.difficulty, end_mode = settings.end_mode,
            end_value = settings.end_value },
        phase = "countdown", countdown = START_COUNTDOWN, clock = 0, final_started = false,
        cakes_done = 0, cake_number = 0, cake = nil, next_cake = nil, last_cake_id = "", unit = 50,
        pace = pace_for(settings.end_mode, settings.end_value), seats = {}, dirty_pockets = {}, results = nil,
    }
    match.final_window = settings.end_mode == "time" and math.max(30, settings.end_value * 60 * 0.12) or 0
    local next_color = 1
    for number, sitter in ipairs(sitters) do
        local seat = new_seat(number, sitter.player, sitter.bot)
        if not sitter.bot then
            seat.color = CATALOG.human_colors[next_color]
            next_color = next_color + 1
        end
        match.seats[number] = seat
        match.dirty_pockets[number] = true
    end
    outbox.roster_version = outbox.roster_version + 1
    outbox.events = {}
    local bot_seats = {}
    for _, seat in ipairs(match.seats) do
        if seat.is_bot then table.insert(bot_seats, { seat = seat.number, persona = seat.persona }) end
    end
    run_function("-cake_table", "start_match", { { seats = #match.seats } })
    run_function("-bots", "start_match", { { difficulty = settings.difficulty, players = #match.seats, bots = bot_seats } })
    -- the first cake is on the table during the countdown
    begin_cake()
end

-- =============================================================================
-- Buying and using
-- =============================================================================
-- One card bought by a seat (a click, a bot or the butler): the card must be the
-- one the buyer saw and already unlocked, the buyer must afford it and have
-- room for it.
local function purchase(seat, slot, item_id, by_butler)
    if not match or match.phase ~= "market" then return false end
    local card = run_function("-market", "peek", { slot })
    if type(card) ~= "table" or card.item ~= item_id or not card.open then return false end
    local item = ITEMS[item_id]
    if not item or not can_hold(seat, item) then return false end
    local price = price_of(seat, item)
    if seat.coins < price then return false end
    seat.coins = seat.coins - price
    seat.spent = seat.spent + price
    if item.kind == "use" then
        table.insert(seat.pocket, item.id)
    else
        seat.upgrades[item.id] = seat.upgrades[item.id] + 1
    end
    match.dirty_pockets[seat.number] = true
    run_function("-market", "replace", { { slot = slot, buyer = seat.number } })
    emit("buy", { p = seat.number, id = item.id, s = slot })
    if by_butler then emit("butler", { p = seat.number, id = item.id }) end
    return true
end

-- A pocket item used during eating; the table carries out its effect.
local function use_pocket_item(seat, index)
    if not match or match.phase ~= "eating" then return false end
    local item_id = seat.pocket[index]
    if not item_id then return false end
    local leader = leader_except(seat)
    local worked = run_function("-cake_table", "use_item", { {
        seat = seat.number, item = item_id, leader = leader and leader.number or 0,
    } })
    if worked ~= true then
        emit("useless", { p = seat.number })
        return false
    end
    table.remove(seat.pocket, index)
    match.dirty_pockets[seat.number] = true
    return true
end

-- The bots script returns what its brains want to do; it goes through the
-- same checks as a player's request.
local function carry_out(actions)
    if type(actions) ~= "table" then return end
    for _, action in ipairs(actions) do
        local seat = match and match.seats[whole(action.seat)]
        if seat then
            if action.kind == "bite" or action.kind == "push" then
                run_function("-cake_table", action.kind, { { seat = seat.number, direction = whole(action.direction) } })
            elseif action.kind == "buy" then
                purchase(seat, whole(action.slot), tostring(action.item), not seat.is_bot)
            elseif action.kind == "use" then
                use_pocket_item(seat, whole(action.index))
            end
        end
    end
end

-- =============================================================================
-- The fixed step
-- =============================================================================
local function step_match(delta)
    if match.phase == "countdown" then
        local shown_before = math.ceil(match.countdown)
        match.countdown = match.countdown - delta
        if match.countdown <= 0 then
            match.countdown = 0
            match.phase = "eating"
            emit("start", {})
        elseif math.ceil(match.countdown) ~= shown_before then
            emit("tick", {})
        end
    elseif match.phase == "eating" then
        match.clock = match.clock + delta
        local settings_now = match.settings
        if settings_now.end_mode == "time" then
            local left = settings_now.end_value * 60 - match.clock
            if not match.final_started and left <= match.final_window then
                match.final_started = true
                run_function("-cake_table", "set_double_points", { true })
                emit("final", {})
            end
            if left <= 0 then return end_match() end
        end
        local result = run_function("-cake_table", "step", { { delta = delta } })
        if type(result) == "table" then
            for number, seat in ipairs(match.seats) do
                seat.score = seat.score + (tonumber(result.score[number]) or 0)
                seat.coins = seat.coins + (tonumber(result.coins[number]) or 0)
                seat.turns = seat.turns + (tonumber(result.turns[number]) or 0)
            end
            if result.done then return finish_cake(result.eaten) end
        end
    elseif match.phase == "market" then
        local result = run_function("-market", "step", { { delta = delta } })
        if type(result) == "table" and result.closed then
            match.phase = "eating"
            begin_cake()
        end
    end
    if match.phase ~= "over" then carry_out(run_function("-bots", "step", { { delta = delta } })) end
end

-- How fast every human presses (last 8 seconds), for the size of the next cake.
local function measure_click_rates()
    for _, seat in ipairs(match.seats) do
        if not seat.is_bot then
            local recent = {}
            for _, moment in ipairs(seat.press_times) do
                if moment > match.clock - 8 then table.insert(recent, moment) end
            end
            seat.press_times = recent
            if match.clock > 8 then seat.measured_clicks = math.min(9, #recent / 8) end
        end
    end
end

-- =============================================================================
-- Requests from the players
-- =============================================================================
function press_HOST(sender_id, direction)
    local seat = seat_of_sender(sender_id)
    if not seat or match.phase ~= "eating" or seat.press_budget < 1 then return end
    seat.press_budget = seat.press_budget - 1
    table.insert(seat.press_times, match.clock)
    run_function("-cake_table", "press", { { seat = seat.number, direction = (tonumber(direction) or 0) >= 0 and 1 or -1 } })
end

function buy_HOST(sender_id, slot, item_id)
    local seat = seat_of_sender(sender_id)
    if seat then purchase(seat, whole(slot), tostring(item_id or ""), false) end
end

function use_HOST(sender_id, index)
    local seat = seat_of_sender(sender_id)
    if seat then use_pocket_item(seat, whole(index)) end
end

function butler_HOST(sender_id)
    local seat = seat_of_sender(sender_id)
    if not seat or seat.upgrades.butler <= 0 then return end
    seat.butler_on = not seat.butler_on
    match.dirty_pockets[seat.number] = true
end

function settings_HOST(sender_id, key, value)
    if not IS_HOST or match or not may_manage(sender_id) then return end
    if key == "bots" then
        settings.bots = math.max(0, math.min(MAX_BOTS, whole(value)))
    elseif key == "difficulty" and CATALOG.bot_levels[value] then
        settings.difficulty = value
    elseif key == "end_mode" and CATALOG.end_values[value] and settings.end_mode ~= value then
        settings.end_mode = value
        settings.end_value = CATALOG.end_values[value].default
    elseif key == "end_value" then
        for _, option in ipairs(CATALOG.end_values[settings.end_mode].options) do
            if option == whole(value) then settings.end_value = whole(value) end
        end
    end
    outbox.send_now = true
end

function start_HOST(sender_id)
    if not IS_HOST or match or not may_manage(sender_id) then return end
    start_match()
    outbox.send_now = true
end

function again_HOST(sender_id)
    if not IS_HOST or not match or match.phase ~= "over" or not may_manage(sender_id) then return end
    match = nil
    outbox.roster_version = outbox.roster_version + 1
    outbox.send_now = true
end

function _on_user_initialized(player_id, nickname)
    if not IS_HOST then return end
    local known = false
    for _, player in ipairs(room) do
        if player.id == player_id then
            player.name = nickname
            known = true
        end
    end
    if not known then table.insert(room, { id = player_id, name = nickname }) end
    if match then
        -- a player who dropped out gets their seat back from the bot that kept it warm
        local seat = seat_of_player(player_id)
        if seat and seat.gone then
            seat.gone, seat.is_bot, seat.name, seat.short = false, false, nickname, nickname
            run_function("-bots", "remove_brain", { seat.number })
        end
        for _, other in ipairs(match.seats) do match.dirty_pockets[other.number] = true end
        outbox.roster_version = outbox.roster_version + 1
    end
    outbox.send_now = true
end

function _on_user_disconnected(player_id, nickname)
    if not IS_HOST then return end
    for index, player in ipairs(room) do
        if player.id == player_id then
            table.remove(room, index)
            break
        end
    end
    if match then
        local seat = seat_of_player(player_id)
        if seat and not seat.is_bot then
            -- the seat plays on as a bot, so the table keeps its slices
            seat.gone, seat.is_bot = true, true
            run_function("-bots", "add_brain", { { seat = seat.number, persona = "balanced" } })
            outbox.roster_version = outbox.roster_version + 1
        end
        local anyone_left = false
        for _, other in ipairs(match.seats) do
            if not other.is_bot then anyone_left = true end
        end
        if not anyone_left then
            run_function("-bots", "stop", {})
            run_function("-market", "close", {})
            match = nil
            outbox.roster_version = outbox.roster_version + 1
        end
    end
    outbox.send_now = true
end

-- =============================================================================
-- The state message
-- =============================================================================
local function roster_message()
    local seats = {}
    for _, seat in ipairs(match.seats) do
        table.insert(seats, { id = seat.id, n = seat.name, s = seat.short, c = seat.color, ic = seat.icon, bot = seat.is_bot })
    end
    return { version = outbox.roster_version, seats = seats }
end

local function lobby_message()
    local players = {}
    for _, player in ipairs(room) do table.insert(players, { id = player.id, n = player.name }) end
    return { settings = settings, players = players, admin = admin_in_room() }
end

-- Upgrades and pockets go out only when they change (with the full set to a
-- player who just joined).
local function send_pockets(everyone)
    local changed = {}
    for _, seat in ipairs(match.seats) do
        if everyone or match.dirty_pockets[seat.number] then
            local levels = {}
            for _, key in ipairs(CATALOG.upgrade_order) do table.insert(levels, seat.upgrades[key]) end
            table.insert(changed, { seat = seat.number, levels = levels, pocket = seat.pocket, butler = seat.butler_on })
            match.dirty_pockets[seat.number] = nil
        end
    end
    if #changed > 0 then run_network_function_by_tag("cc_pockets", "pockets_ALL", { changed }) end
end

-- What the bots need to decide: the same picture the players see, plus their books.
local function observation(table_state, market_state)
    local books = {}
    for _, seat in ipairs(match.seats) do
        table.insert(books, { coins = seat.coins, upgrades = seat.upgrades, pocket = seat.pocket,
            butler = seat.butler_on and seat.upgrades.butler > 0 and not seat.is_bot, score = seat.score })
    end
    local leaders = {}
    for _, seat in ipairs(match.seats) do
        local leader = leader_except(seat)
        leaders[seat.number] = leader and leader.number or 0
    end
    return { phase = match.phase, clock = match.clock, progress = progress(), unit = match.unit,
        table = table_state, market = market_state, books = books, leaders = leaders, events = outbox.events }
end

local function state_message(everything)
    outbox.sequence = outbox.sequence + 1
    local message = { q = outbox.sequence, phase = match and match.phase or "lobby" }
    if not match then
        message.lobby = lobby_message()
    else
        if everything or outbox.roster_sent ~= outbox.roster_version or outbox.since_roster >= ROSTER_RESEND_EVERY then
            message.roster = roster_message()
            outbox.roster_sent = outbox.roster_version
            outbox.since_roster = 0
        else
            outbox.since_roster = outbox.since_roster + 1
        end
        message.settings = match.settings
        message.countdown = whole(match.countdown * 10)
        message.clock = whole(match.clock * 10)
        message.final = match.final_started
        message.cakes_done = match.cakes_done
        message.cake = (match.phase ~= "market" and match.cake) and match.cake.id or ""
        message.unit = match.unit
        local books = {}
        for _, seat in ipairs(match.seats) do
            table.insert(books, whole(seat.score * 10))
            table.insert(books, seat.crowns)
            table.insert(books, math.floor(seat.coins))
        end
        message.books = books
        local table_state = run_function("-cake_table", "snapshot", {})
        message.table = table_state
        if match.phase == "market" then message.market = run_function("-market", "snapshot", {}) end
        local bot_state = run_function("-bots", "snapshot", {})
        if type(bot_state) == "table" then
            message.cursors = bot_state.cursors
            for _, event in ipairs(bot_state.events or {}) do table.insert(outbox.events, event) end
        end
        if type(table_state) == "table" then
            for _, event in ipairs(table_state.events or {}) do table.insert(outbox.events, event) end
        end
        if type(message.market) == "table" then
            for _, event in ipairs(message.market.events or {}) do table.insert(outbox.events, event) end
        end
        if match.phase ~= "over" then
            run_function("-bots", "observe", { observation(table_state, message.market) })
        end
        if match.phase == "over" then message.results = match.results end
    end
    message.events = outbox.events
    outbox.events = {}
    return message
end

function _process(delta, inputs)
    if not IS_HOST then return end
    if match then
        for _, seat in ipairs(match.seats) do
            seat.press_budget = math.min(PRESSES_PER_SECOND, seat.press_budget + PRESSES_PER_SECOND * delta)
        end
        step_clock = step_clock + math.min(delta, 0.25)
        local steps = 0
        while match and step_clock >= STEP and steps < 10 do
            step_clock = step_clock - STEP
            steps = steps + 1
            step_match(STEP)
            if match and match.phase == "eating" then measure_click_rates() end
        end
    end
    outbox.timer = outbox.timer + delta
    local every = match and SNAPSHOT_EVERY or 0.5
    if outbox.timer >= every or outbox.send_now then
        local everything = outbox.send_now
        outbox.timer = 0
        outbox.send_now = false
        if match then send_pockets(everything) end
        run_network_function_by_tag("cc_view", "state_ALL", { state_message(everything) })
    end
end

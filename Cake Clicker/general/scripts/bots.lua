singleton_name = "bots"

-- =============================================================================
-- Cake Clicker - the bots' brains (and the butler). HOST only.
--
-- A bot sits at the table like a player and only DECIDES: step() returns a list
-- of actions (bite, push, buy, use) and game.lua carries them out through the
-- same checks a player's request goes through, so a bot can never do what a
-- player could not. What a bot knows is what a player sees: game.lua hands it
-- the state message ten times a second (observe), plus its own books.
--
-- Each bot also has a mouse cursor that moves like a hand (a damped spring
-- toward where it is looking): over its own slice while it eats, to the table
-- edge when it pushes, over the cards while it shops. The positions go out in
-- the state message and table_view draws them.
--
-- Personalities (catalog.json "personas") change how often a bot defends its
-- slice, steals a neighbour's and which cards it likes. The difficulty sets its
-- clicking speed, how many cards it buys per market and how quickly it reacts.
--
-- The butler (an item) is a brain without a cursor: in the market it buys
-- permanent upgrades for the human who owns it.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local TAU = math.pi * 2
local TABLE = CATALOG.table_layout
local CARDS = CATALOG.market_layout
local SPRING = 55                        -- cursor stiffness
local DAMPING = 2 * math.sqrt(SPRING) * 0.8
local SHOPPING_WINDOW = 9                -- bots only start buying while the market countdown is above this

local ITEMS = {}
for _, item in ipairs(CATALOG.items) do ITEMS[item.id] = item end
local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end

local brains = {}             -- seat number -> bot brain
local level = CATALOG.bot_levels.normal
local players = 0
local view = nil              -- the latest observation from game.lua
local actions = {}            -- what the brains decided this step
local events = {}             -- remarks ("say") for the speech bubbles
local butler_timers = {}      -- human seat -> seconds to the butler's next look
local running = false

local function random_between(low, high) return low + math.random() * (high - low) end

local function decide(kind, fields)
    fields.kind = kind
    table.insert(actions, fields)
end

local function say(seat_number, kind, chance)
    if math.random() > chance or not brains[seat_number] then return end
    events[#events + 1] = { k = "say", p = seat_number, w = kind, n = math.random(1, CATALOG.remark_counts[kind]) }
end

-- =============================================================================
-- Reading the observation
-- =============================================================================
-- A seat's body from the table part of the state (see cake_table.snapshot).
local function body_of(seat_number)
    local numbers = view.table.seats
    local base = (seat_number - 1) * 6
    local flags = math.floor(numbers[base + 1] or 0)
    return {
        stuffed = flags % 2 == 1, disarmed = (flags // 2) % 2 == 1, coffee = (flags // 8) % 2 == 1,
        empty = (flags // 16) % 2 == 1, fullness = numbers[base + 2] or 0,
        stamina = (numbers[base + 3] or 0) / 10, max_stamina = numbers[base + 4] or 12,
    }
end

local function slice_count() return players * 2 end
local function front_number(seat_number)
    return (2 * (seat_number - 1) - math.floor(view.table.rotation or 0)) % slice_count()
end
-- share of a slice left (0..1.15) and whether a golden cherry sits on it
local function slice_info(number)
    local numbers = view.table.slices
    local base = (number % slice_count()) * 3
    local left = (numbers[base + 1] or 0) / 1000
    local cherry = math.floor(numbers[base + 3] or 0) % 2 == 1
    return left, cherry
end
local function slice_value(number, cherry_bonus)
    local left, cherry = slice_info(number)
    return left + (cherry and cherry_bonus or 0)
end

local function best_direction(seat_number)
    local mine = front_number(seat_number)
    for distance = 1, slice_count() // 2 do
        local left_value = slice_value(mine - distance, 0.5)
        local right_value = slice_value(mine + distance, 0.5)
        if left_value > 0 or right_value > 0 then return left_value >= right_value and 1 or -1 end
    end
    return 0
end

local function books_of(seat_number) return view.books[seat_number] end

local function price_of(seat_number, item)
    local level_now = item.kind == "use" and 0 or (books_of(seat_number).upgrades[item.id] or 0)
    return math.max(1, math.floor(item.price * view.unit * (item.growth or 1) ^ level_now + 0.5))
end

local function can_hold(seat_number, item)
    local books = books_of(seat_number)
    if item.kind == "use" then return #books.pocket < CATALOG.limits.pocket_size end
    return not (item.max and (books.upgrades[item.id] or 0) >= item.max)
end

-- =============================================================================
-- The cursor
-- =============================================================================
local function seat_angle(seat_number) return math.pi / 2 + (seat_number - 1) * TAU / players end

-- A point in front of a seat: rf = distance as a share of the cake's radius.
local function table_point(seat_number, rf, turn)
    local angle = seat_angle(seat_number) + (turn or 0)
    return TABLE.center_x + math.cos(angle) * TABLE.cake * rf, TABLE.center_y + math.sin(angle) * TABLE.cake * rf
end

local function card_center(slot, count)
    local total = count * CARDS.card_width + (count - 1) * CARDS.gap
    return -total / 2 + CARDS.card_width / 2 + (slot - 1) * (CARDS.card_width + CARDS.gap), CARDS.y
end

local function aim(brain, x, y)
    brain.cursor.target_x, brain.cursor.target_y = x, y
end

local function click(brain)
    brain.cursor.presses = brain.cursor.presses + 1
end

local function move_cursor(brain, delta)
    local cursor = brain.cursor
    local substep = delta / 3
    for _ = 1, 3 do
        cursor.wobble = cursor.wobble + substep
        local goal_x = cursor.target_x + math.sin(cursor.wobble * 2.1) * 3
        local goal_y = cursor.target_y + math.cos(cursor.wobble * 1.7) * 3
        cursor.speed_x = cursor.speed_x + (SPRING * (goal_x - cursor.x) - DAMPING * cursor.speed_x) * substep
        cursor.speed_y = cursor.speed_y + (SPRING * (goal_y - cursor.y) - DAMPING * cursor.speed_y) * substep
        cursor.x = cursor.x + cursor.speed_x * substep
        cursor.y = cursor.y + cursor.speed_y * substep
    end
end

-- =============================================================================
-- Brains
-- =============================================================================
local function new_brain(seat_number, persona)
    local x, y = table_point(seat_number, 1.25, 0)
    return {
        seat = seat_number, persona = CATALOG.personas[persona] or CATALOG.personas.balanced,
        clicks = level.clicks * random_between(0.9, 1.1), act_progress = math.random(),
        shop_timer = random_between(0.6, 2.2), use_timer = random_between(2, 4), browse_timer = 0,
        steal_timer = 0, steal_direction = 0, drag_side = false, intent = nil, bought = 0,
        cursor = { x = x, y = y, speed_x = 0, speed_y = 0, target_x = x, target_y = y, wobble = random_between(0, 10), presses = 0 },
    }
end

function start_match(request)
    level = CATALOG.bot_levels[request.difficulty] or CATALOG.bot_levels.normal
    players = math.floor(request.players)
    brains = {}
    butler_timers = {}
    view = nil
    events = {}
    for _, entry in ipairs(request.bots or {}) do
        local seat_number = math.floor(entry.seat)
        brains[seat_number] = new_brain(seat_number, entry.persona)
    end
    running = true
end

-- A player left: their seat plays on as a bot.
function add_brain(request)
    local seat_number = math.floor(request.seat)
    brains[seat_number] = new_brain(seat_number, request.persona)
end

-- ...and gets it back when they return.
function remove_brain(seat_number)
    brains[math.floor(seat_number)] = nil
end

function stop()
    running = false
    brains = {}
end

-- One decision at the table (the prototype's botAct): eat, push toward a full
-- slice when there is none, defend against a neighbour turning the plate away,
-- or now and then try to steal a bigger slice.
local function act_at_table(brain)
    local seat = brain.seat
    local body = body_of(seat)
    local mine = front_number(seat)
    local mine_left = slice_info(mine)
    local tension = view.table.tension or 0
    local locked = view.table.turning or (view.table.lock or 0) > 0
    local function push(direction)
        brain.drag_side = not brain.drag_side
        aim(brain, table_point(seat, 1.12, direction * (brain.drag_side and -0.28 or 0.12)))
        click(brain)
        decide("push", { seat = seat, direction = direction })
    end
    if mine_left <= 0 then
        if locked or body.stamina < 1 then return end
        local direction = best_direction(seat)
        if math.abs(tension) >= 10 and math.random() < 0.85 then direction = tension > 0 and 1 or -1 end
        if direction ~= 0 then push(direction) end
        if body.stamina < 2 then say(seat, "tired", 0.3) end
        return
    end
    if brain.steal_timer > 0 and not locked and body.stamina >= 1 then return push(brain.steal_direction) end
    if not locked and math.abs(tension) > 50 and body.stamina > 3 then
        local toward = tension > 0 and 1 or -1
        if slice_value(mine - toward, 1) < mine_left * 0.85 and math.random() < brain.persona.defend then
            return push(-toward)
        end
    end
    if not locked and body.stamina > body.max_stamina * 0.6 and math.random() < brain.persona.steal * 0.03 then
        local right, left = slice_value(mine - 1, 1), slice_value(mine + 1, 1)
        local direction, value = 1, right
        if left > right then direction, value = -1, left end
        if value > mine_left * 1.6 then
            brain.steal_direction = direction
            brain.steal_timer = random_between(2, 3.5)
            say(seat, "plot", 0.5)
            return push(direction)
        end
    end
    if body.stuffed or body.disarmed then return end
    aim(brain, table_point(seat, random_between(0.35, 0.8), random_between(-0.2, 0.2)))
    click(brain)
    decide("bite", { seat = seat, direction = 1 })
end

-- When to use a pocket item (the prototype's botUse).
local function use_items(brain)
    local seat = brain.seat
    local pocket = books_of(seat).pocket
    if #pocket == 0 then return end
    local body = body_of(seat)
    local mine_left = slice_info(front_number(seat))
    local free = not view.table.turning and (view.table.lock or 0) <= 0
    local leader = math.floor(view.leaders[seat] or 0)
    local leader_body = leader > 0 and body_of(leader) or nil
    local leader_left = leader > 0 and slice_info(front_number(leader)) or 0
    for index, item in ipairs(pocket) do
        local go = false
        if item == "coffee" then go = mine_left > 0.45 and not body.stuffed and not body.coffee
        elseif item == "ayran" then go = body.fullness > 75
        elseif item == "turnip_juice" then go = mine_left <= 0 and body.stamina < 3
        elseif item == "honey_sauce" then go = mine_left < 0.25
        elseif item == "quick_spin" then go = free and mine_left <= 0
        elseif item == "spoon_throw" then go = leader_body and not leader_body.disarmed and leader_left > 0 and math.random() < 0.6
        elseif item == "hot_pepper" then go = leader_body and not leader_body.stuffed and leader_body.fullness < 60 and math.random() < 0.5
        elseif item == "table_lock" then go = mine_left > 0.5 and math.abs(view.table.tension or 0) > 45 and free
        elseif item == "salt_shaker" then go = leader_left > 0.4 and math.random() < 0.5
        elseif item == "raccoon_fork" then go = math.random() < 0.6 end
        if go then return decide("use", { seat = seat, index = index }) end
    end
end

-- How much a bot (or the butler) wants an item.
local function wish(seat_number, item, persona)
    local next_cake = CAKES[view.market and view.market.next_cake or ""]
    local remaining_game = 1 - (view.progress or 0)
    local fullness = body_of(seat_number).fullness
    local value
    if item.kind == "tool" then
        local useful = false
        for _, layer in ipairs(next_cake and next_cake.layers or {}) do
            for _, kind in ipairs(CATALOG.tools[item.id] or {}) do
                if layer[1] == kind then useful = true end
            end
        end
        value = (item.id == "gold_spoon" and 1.5 or (useful and 1.4 or 0.7)) * (persona.tool_love or 1)
    else
        local base = { big_spoon = 1.2, master_hand = 0.8, strong_arm = 0.45, stamina = 0.45, cherry_magnet = 0.5,
            apprentice = 1.3, robo_jaw = 1.1, conveyor = 1.4, motor = 0.7, guard_dog = 0.6, turnip_juice = 0.45 }
        value = base[item.id] or 0.5
        if item.id == "big_belly" or item.id == "fast_digest" then value = fullness > 40 and 1 or 0.55 end
        if item.id == "tip_jar" then value = 0.95 * remaining_game end
        if item.id == "bakery" then value = 1.1 * remaining_game end
        if item.id == "smart_jaw" then value = fullness > 50 and 0.9 or 0.5 end
        if item.id == "ayran" then value = fullness > 60 and 1.3 or 0.35 end
        if item.id == "butler" then value = 0 end
    end
    return value * (persona.likes[item.id] or 1)
end

-- Picks a card to buy and walks the cursor to its buy bar.
local function shop(brain, delta)
    local cards = view.market and view.market.cards or {}
    local count = #cards
    if brain.intent then
        local card = cards[brain.intent.slot]
        brain.intent.age = brain.intent.age + delta
        if not card or card[1] ~= brain.intent.item or brain.intent.age > 4 then
            brain.intent = nil
            return
        end
        aim(brain, brain.intent.x, brain.intent.y)
        local cursor = brain.cursor
        if math.abs(cursor.x - brain.intent.x) < 16 and math.abs(cursor.y - brain.intent.y) < 16 then
            click(brain)
            decide("buy", { seat = brain.seat, slot = brain.intent.slot, item = brain.intent.item })
            brain.bought = brain.bought + 1
            say(brain.seat, "buy", 0.2)
            brain.intent = nil
        end
        return
    end
    brain.shop_timer = brain.shop_timer - delta
    local countdown = (view.market and view.market.countdown or 0) / 10
    if brain.shop_timer <= 0 and countdown > SHOPPING_WINDOW and brain.bought < level.buys then
        brain.shop_timer = random_between(0.8, 2.4) * level.shopping_gap
        local coins = books_of(brain.seat).coins
        local best_slot, best_value = 0, 0
        for slot, card in ipairs(cards) do
            local item = ITEMS[card[1]]
            local readable_for = (card[5] or 0) / 10
            if item and card[2] <= 0 and readable_for >= level.reaction and can_hold(brain.seat, item)
                and price_of(brain.seat, item) <= coins then
                local value = wish(brain.seat, item, brain.persona) * random_between(0.75, 1.25)
                if value > best_value then best_slot, best_value = slot, value end
            end
        end
        if best_slot > 0 and best_value > 0.7 then
            local x, y = card_center(best_slot, count)
            brain.intent = { slot = best_slot, item = cards[best_slot][1], age = 0,
                x = x + random_between(-40, 40), y = y + CARDS.card_height / 2 - 30 + random_between(-6, 6) }
            return
        end
    end
    -- nothing to buy right now: the cursor drifts over the cards
    brain.browse_timer = brain.browse_timer - delta
    if brain.browse_timer <= 0 and count > 0 then
        brain.browse_timer = random_between(0.9, 2.2)
        local x, y = card_center(math.random(1, count), count)
        aim(brain, x + random_between(-60, 60), y + random_between(-90, 120))
    end
end

-- The butler buys the best permanent upgrade its owner can afford.
local function butler(seat_number, delta)
    butler_timers[seat_number] = (butler_timers[seat_number] or 1) - delta
    if butler_timers[seat_number] > 0 then return end
    butler_timers[seat_number] = 1.2
    local coins = books_of(seat_number).coins
    local best_slot, best_value, best_item = 0, 0, nil
    for slot, card in ipairs(view.market.cards or {}) do
        local item = ITEMS[card[1]]
        if item and card[2] <= 0 and item.kind ~= "use" and item.id ~= "butler" and can_hold(seat_number, item) then
            local price = price_of(seat_number, item)
            if price <= coins then
                local value = wish(seat_number, item, CATALOG.personas.balanced) / math.sqrt(price / view.unit + 0.5)
                if value > best_value then best_slot, best_value, best_item = slot, value, item.id end
            end
        end
    end
    if best_slot > 0 then decide("buy", { seat = seat_number, slot = best_slot, item = best_item }) end
end

-- Remarks: bots react to what just happened to them.
local REACTIONS = {
    robbed = { "v", "robbed", 0.6 }, turned = { "p", "steal", 0.5 }, stuffed = { "p", "stuffed", 0.7 },
    cherry_got = { "p", "cherry", 0.8 }, crown = { "p", "crown", 0.9 },
}
local ITEM_REACTIONS = { spoon_throw = { "hit", 0.8 }, hot_pepper = { "spicy", 0.9 }, raccoon_fork = { "robbed", 0.8 } }

local function react(event_list)
    for _, event in ipairs(event_list or {}) do
        local reaction = REACTIONS[event.k]
        if reaction then
            say(math.floor(tonumber(event[reaction[1]]) or 0), reaction[2], reaction[3])
        elseif event.k == "item" and ITEM_REACTIONS[event.id] then
            local item_reaction = ITEM_REACTIONS[event.id]
            say(math.floor(tonumber(event.tg) or 0), item_reaction[1], item_reaction[2])
        end
    end
end

-- =============================================================================
-- Called by game.lua
-- =============================================================================
function observe(observation)
    view = observation
    players = math.max(players, #(observation.books or {}))
    react(observation.events)
end

function step(request)
    actions = {}
    if not running or not view then return actions end
    local delta = tonumber(request.delta) or 0.05
    local phase = view.phase
    for _, brain in pairs(brains) do
        if phase == "eating" then
            if brain.steal_timer > 0 then brain.steal_timer = brain.steal_timer - delta end
            local slow_down = 0.35 + 0.65 * math.exp(-(view.clock or 0) / 120)
            brain.act_progress = brain.act_progress + brain.clicks * slow_down * delta * random_between(0.7, 1.3)
            while brain.act_progress >= 1 do
                brain.act_progress = brain.act_progress - 1
                act_at_table(brain)
            end
            brain.use_timer = brain.use_timer - delta
            if brain.use_timer <= 0 then
                brain.use_timer = random_between(1.2, 3)
                use_items(brain)
            end
            brain.bought = 0
            brain.intent = nil
        elseif phase == "market" then
            shop(brain, delta)
        end
        move_cursor(brain, delta)
    end
    if phase == "market" then
        for seat_number, books in ipairs(view.books) do
            if books.butler and not brains[seat_number] then butler(seat_number, delta) end
        end
    end
    return actions
end

-- cursors: per seat three numbers (x, y, clicks so far), or 0, 0, -1 for a seat
-- that is not a bot.
function snapshot()
    local cursors = {}
    for seat_number = 1, players do
        local brain = brains[seat_number]
        if brain then
            table.insert(cursors, math.floor(brain.cursor.x))
            table.insert(cursors, math.floor(brain.cursor.y))
            table.insert(cursors, brain.cursor.presses)
        else
            table.insert(cursors, 0)
            table.insert(cursors, 0)
            table.insert(cursors, -1)
        end
    end
    local message = { cursors = cursors, events = events }
    events = {}
    return message
end

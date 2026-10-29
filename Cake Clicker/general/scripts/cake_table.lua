singleton_name = "cake_table"

-- =============================================================================
-- Cake Clicker - the cake on the table. HOST only; game.lua drives it.
--
-- The cake is cut into two slices per seat. A seat can only eat the slice in
-- front of it (slice number 2 * (seat - 1) - rotation, wrapped). Every slice is
-- a stack of layers (cream, sponge, biscuit...) and harder layers take more
-- bites. Everyone also eats by themselves, slowly; upgrades bought in the
-- market make bites bigger, faster or automatic.
--
-- Turning the plate: a push adds to a shared "tension"; at +100 or -100 the
-- plate turns one slice and every seat faces a different slice.
--
-- This script also keeps each seat's body: how full the stomach is (stuffed =
-- no eating for a while), how much arm strength is left for pushing, and the
-- timers items set (coffee, a dropped spoon). Pocket items have their effect
-- here; game.lua keeps the pockets themselves.
--
-- Called by game.lua (run_function "-cake_table"):
--   start_match, start_cake, step, press, bite, push, use_item,
--   set_double_points, snapshot
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local TAU = math.pi * 2
local NO_EATING_FOR = 7          -- seconds nobody ate before the waiter turns the plate
local CRUMB_SHARE = 0.02         -- a slice this small is finished in one bite
local STUFFED_AT, CALM_AT = 100, 60
local TAIL_SHARE, TAIL_SECONDS = 0.12, 12   -- a cake this nearly eaten for this long is cleared

local LAYERS = CATALOG.layers
local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end
-- layer -> the tool that speeds it up
local TOOL_FOR_LAYER = {}
for tool, layers in pairs(CATALOG.tools) do
    for _, layer in ipairs(layers) do TOOL_FOR_LAYER[layer] = tool end
end

local seats = {}        -- per seat: upgrades, stomach, arm, timers, earnings
local cake = nil        -- { kind, slices, unit, eaten_by }
local plate = { rotation = 0, tension = 0, turning_lock = 0, table_lock = 0, pushers = {} }
local clock = 0
local double_points = false
local pace = 1
local events = {}

local function emit(kind, fields)
    local event = fields or {}
    event.k = kind
    table.insert(events, event)
end

local function random_between(low, high) return low + math.random() * (high - low) end

-- =============================================================================
-- What the upgrades do (the only place these formulas live)
-- =============================================================================
local function max_stamina(seat) return 12 + 4 * seat.upgrades.stamina end
local function stamina_regen(seat) return 2.5 * (1 + 0.4 * seat.upgrades.stamina) end
local function digestion(seat) return 6 * (1 + 0.35 * seat.upgrades.fast_digest) end
local function bite_power(seat) return 1 + 0.4 * seat.upgrades.big_spoon end
local function auto_bites_per_second(seat) return 2 + 1.5 * seat.upgrades.apprentice + 3 * seat.upgrades.conveyor end
local function auto_bite_power(seat) return bite_power(seat) * 0.7 * (1 + 0.4 * seat.upgrades.robo_jaw) end
local function auto_pushes_per_second(seat) return 1.2 + 1.2 * seat.upgrades.motor end

-- How fast a seat gets through a layer: soft layers are easy, tools help.
local function layer_speed(seat, layer_kind)
    local speed = LAYERS[layer_kind].softness
    local tool = TOOL_FOR_LAYER[layer_kind]
    if tool then speed = speed * (1 + 0.6 * seat.upgrades[tool]) end
    return speed * (1 + 0.25 * seat.upgrades.gold_spoon)
end

-- =============================================================================
-- Slices
-- =============================================================================
local function slice_count() return #seats * 2 end
local function slice_at(number) return cake.slices[(number % slice_count()) + 1] end
local function front_number(seat) return (2 * (seat.number - 1) - plate.rotation) % slice_count() end
local function front_slice(seat)
    if not cake then return nil end
    return slice_at(front_number(seat))
end
local function remaining(slice)
    if not slice then return 0 end
    local total = 0
    for _, layer in ipairs(slice.layers) do total = total + layer.amount end
    return total
end
local function top_layer(slice)
    for _, layer in ipairs(slice.layers) do
        if layer.amount > 0 then return layer end
    end
    return nil
end
local function finish_crumbs(slice)
    local leftover = 0
    if remaining(slice) <= slice.size * CRUMB_SHARE then
        for _, layer in ipairs(slice.layers) do
            leftover = leftover + layer.amount
            layer.amount = 0
        end
    end
    return leftover
end

-- Which way to turn for the nearest full slice (a golden cherry counts extra).
local function best_direction(seat)
    local mine = front_number(seat)
    for distance = 1, slice_count() // 2 do
        local left, right = slice_at(mine - distance), slice_at(mine + distance)
        local left_value = remaining(left) + (left.cherry and cake.unit * 0.5 or 0)
        local right_value = remaining(right) + (right.cherry and cake.unit * 0.5 or 0)
        if left_value > 0 or right_value > 0 then return left_value >= right_value and 1 or -1 end
    end
    return 0
end

-- Someone else is turning a smaller slice in front of this seat: the way the
-- tension points, or 0.
local function threat_to(seat)
    if math.abs(plate.tension) <= 30 or plate.turning_lock > 0 or plate.table_lock > 0 then return 0 end
    local direction = plate.tension > 0 and 1 or -1
    local pusher = plate.pushers[direction]
    local mine = remaining(front_slice(seat))
    if not pusher or pusher == seat.number or mine <= 0 then return 0 end
    if remaining(slice_at(front_number(seat) - direction)) < mine then return direction end
    return 0
end

-- =============================================================================
-- Setting up
-- =============================================================================
function start_match(info)
    seats = {}
    for number = 1, math.floor(tonumber(info.seats) or 0) do
        seats[number] = {
            number = number, upgrades = {}, fullness = 0, stuffed = false, stamina = 12,
            disarmed = 0, coffee = 0, pushing = 0, auto_progress = math.random(), push_progress = 0, guard_progress = 0,
            auto_bites = 0, score = 0, coins = 0, turns = 0,
        }
        for _, key in ipairs(CATALOG.upgrade_order) do seats[number].upgrades[key] = 0 end
    end
    cake = nil
    plate = { rotation = 0, tension = 0, turning_lock = 0, table_lock = 0, pushers = {} }
    clock = 0
    double_points = false
    events = {}
end

function set_double_points(on) double_points = on == true end

-- How much a seat eats per second right now (for sizing the next cake).
local function eating_speed(seat, clicks)
    local upgrades = seat.upgrades
    local tools = upgrades.fork + upgrades.ladle + upgrades.knife + upgrades.hammer
    local boost = (1 + 0.25 * upgrades.gold_spoon) * (1 + 0.15 * tools) * 0.85
    return boost * (clicks * 0.8 * bite_power(seat) + auto_bites_per_second(seat) * auto_bite_power(seat))
end

-- Puts a new cake on the table and returns its "unit" (one slice's size), which
-- is also the price scale of the market. A cake is sized so that it lasts
-- about ten seconds of everyone's average eating speed, whatever the upgrades.
function start_cake(info)
    pace = tonumber(info.pace) or 1
    clock = tonumber(info.clock) or clock
    local bot_clicks = CATALOG.bot_levels[info.difficulty].clicks * (0.35 + 0.65 * math.exp(-clock / 120))
    local total_speed = 0
    for _, eater in ipairs(info.eaters) do
        local seat = seats[math.floor(eater.seat)]
        for key, level in pairs(eater.upgrades) do seat.upgrades[key] = math.floor(level) end
        seat.stamina = math.min(seat.stamina, max_stamina(seat))
        local clicks = eater.bot and bot_clicks or (tonumber(eater.clicks) or 4)
        total_speed = total_speed + eating_speed(seat, clicks)
    end
    local number = math.floor(tonumber(info.number) or 1)
    local unit = math.max(12, total_speed / #seats * (10 + math.min(4, (number - 1) * 0.2)) / math.sqrt(pace))
    local kind = CAKES[info.cake]
    local weights = 0
    for _, layer in ipairs(kind.layers) do weights = weights + layer[2] end
    local slices = {}
    for index = 1, slice_count() do
        local size_now = unit * kind.size * random_between(0.88, 1.12)
        local layers = {}
        for layer_index, layer in ipairs(kind.layers) do
            local amount = size_now * layer[2] / weights
            layers[layer_index] = { kind = layer[1], index = layer_index, amount = amount }
        end
        slices[index] = { layers = layers, size = size_now, salted = 0, cherry = false }
    end
    local eaten_by = {}
    for number_of_seat = 1, #seats do eaten_by[number_of_seat] = 0 end
    cake = { kind = kind, slices = slices, unit = unit, eaten_by = eaten_by, last_bite = clock, tail = 0,
        cherry_in = random_between(25, 40) }
    for _, seat in ipairs(seats) do
        seat.stuffed = false
        seat.disarmed = 0
    end
    return unit
end

-- =============================================================================
-- Eating
-- =============================================================================
-- Score and coins for grams eaten off a slice (salt halves both).
local function credit(seat, grams, slice)
    local salt = (slice and slice.salted > 0) and 0.5 or 1
    local points = grams * salt * ((double_points or cake.kind.final) and 2 or 1)
    if grams > 0 then cake.last_bite = clock end
    seat.score = seat.score + points
    cake.eaten_by[seat.number] = cake.eaten_by[seat.number] + points
    seat.coins = seat.coins + grams * cake.kind.coin * salt * (1 + 0.2 * seat.upgrades.tip_jar)
        * (1 + 0.15 * seat.upgrades.gold_spoon) * pace
    return points
end

local function eat_from_slice(seat, power)
    local slice = front_slice(seat)
    local grams = 0
    for _, layer in ipairs(slice.layers) do
        if layer.amount > 0 then
            local speed = layer_speed(seat, layer.kind)
            local taken = math.min(power * speed, layer.amount)
            layer.amount = layer.amount - taken
            if layer.amount < 1e-6 then layer.amount = 0 end
            grams = grams + taken
            power = power - taken / speed
            if power <= 1e-9 then break end
        end
    end
    return grams + finish_crumbs(slice), slice
end

-- One bite: by hand (a press) or automatic. Returns the points it scored.
local function take_bite(seat, automatic)
    if not cake or seat.stuffed or seat.disarmed > 0 or remaining(front_slice(seat)) <= 0 then return 0 end
    local power = (automatic and auto_bite_power(seat) or bite_power(seat)) * (seat.coffee > 0 and 2 or 1)
    local critical = math.random() < 0.04 + 0.06 * seat.upgrades.master_hand
    if critical then power = power * 3 end
    local grams, slice = eat_from_slice(seat, power)
    local points = credit(seat, grams, slice)
    if automatic then seat.auto_bites = seat.auto_bites + 1 end
    seat.fullness = seat.fullness + (automatic and 0.45 or 1.6) / (1 + 0.33 * seat.upgrades.big_belly)
    if seat.fullness >= STUFFED_AT then
        seat.fullness = STUFFED_AT
        if not seat.stuffed then
            seat.stuffed = true
            emit("stuffed", { p = seat.number })
        end
    end
    if slice.cherry then
        slice.cherry = false
        local bonus = cake.unit * 1.5 * (1 + 0.5 * seat.upgrades.cherry_magnet) * pace
        seat.coins = seat.coins + bonus
        emit("cherry_got", { p = seat.number, c = math.floor(bonus) })
    end
    if critical then emit("crit", { p = seat.number, g = points }) end
    return points
end

-- =============================================================================
-- Turning the plate
-- =============================================================================
local function turn_plate(direction, pusher)
    local before = {}
    for _, seat in ipairs(seats) do before[seat.number] = remaining(front_slice(seat)) end
    plate.rotation = plate.rotation + direction
    plate.tension = 0
    plate.turning_lock = 1.1
    if pusher then pusher.turns = pusher.turns + 1 end
    for _, seat in ipairs(seats) do
        if seat ~= pusher then
            local now = front_slice(seat)
            local now_left, was_left = remaining(now), before[seat.number]
            if was_left > now.size * 0.2 and was_left > now_left * 1.5 then
                emit("robbed", { v = seat.number, by = pusher and pusher.number or 0, e = now_left > 0 })
            elseif was_left <= 0 and now_left > 0 then
                emit("gift", { v = seat.number })
            end
        end
    end
    if pusher then emit("turned", { p = pusher.number }) end
    emit("rot", { d = direction })
end

-- One push in a direction; "lock" while the plate cannot turn, "tired" without
-- arm strength.
local function push_plate(seat, direction)
    if not cake or plate.turning_lock > 0 or plate.table_lock > 0 then return "lock" end
    if seat.stamina < 1 then return "tired" end
    seat.stamina = seat.stamina - 1
    plate.tension = plate.tension + direction * 14 * (1 + 0.3 * seat.upgrades.strong_arm)
    plate.pushers[direction] = seat.number
    seat.pushing = 0.45
    if plate.tension >= 100 then turn_plate(1, seat) elseif plate.tension <= -100 then turn_plate(-1, seat) end
    return "ok"
end

-- A player's press: a bite while there is cake in front, otherwise a push.
function press(request)
    local seat = seats[math.floor(request.seat)]
    if not seat or not cake then return end
    if remaining(front_slice(seat)) > 0 then take_bite(seat, false) else push_plate(seat, request.direction) end
end

function bite(request)
    local seat = seats[math.floor(request.seat)]
    if seat and cake then take_bite(seat, false) end
end

function push(request)
    local seat = seats[math.floor(request.seat)]
    if seat and cake then push_plate(seat, request.direction >= 0 and 1 or -1) end
end

-- =============================================================================
-- Pocket items (game.lua checks the pocket; this carries out the effect)
-- =============================================================================
local ITEM_EFFECTS = {}

function ITEM_EFFECTS.coffee(seat) seat.coffee = 10 return true end

function ITEM_EFFECTS.ayran(seat)
    seat.fullness = math.max(0, seat.fullness - 50)
    if seat.fullness < CALM_AT then seat.stuffed = false end
    return true
end

function ITEM_EFFECTS.turnip_juice(seat) seat.stamina = max_stamina(seat) return true end

function ITEM_EFFECTS.honey_sauce(seat)
    local slice = front_slice(seat)
    local amount = slice.size * 0.4
    table.insert(slice.layers, 1, { kind = "honey", index = 0, amount = amount })
    return true
end

function ITEM_EFFECTS.quick_spin(seat)
    if plate.table_lock > 0 then return false end
    local mine = front_number(seat)
    local direction = remaining(slice_at(mine - 1)) >= remaining(slice_at(mine + 1)) and 1 or -1
    turn_plate(direction, seat)
    return true
end

function ITEM_EFFECTS.table_lock()
    plate.table_lock = 10
    plate.tension = 0
    return true
end

function ITEM_EFFECTS.spoon_throw(_, target)
    if not target then return false end
    target.disarmed = 4
    return true
end

function ITEM_EFFECTS.hot_pepper(_, target)
    if not target then return false end
    target.fullness = math.min(STUFFED_AT, target.fullness + 60)
    if target.fullness >= STUFFED_AT then target.stuffed = true end
    return true
end

function ITEM_EFFECTS.salt_shaker(_, target)
    local slice = target and front_slice(target)
    if not slice or remaining(slice) <= 0 then return false end
    slice.salted = 12
    return true
end

-- A big bite off the fullest slice that is not the user's own.
function ITEM_EFFECTS.raccoon_fork(seat)
    local mine = front_number(seat)
    local best_number, best_left = -1, 0
    for index, slice in ipairs(cake.slices) do
        local left = remaining(slice)
        if index - 1 ~= mine and left > best_left then best_number, best_left = index - 1, left end
    end
    if best_number < 0 then return false end
    local slice = cake.slices[best_number + 1]
    local wanted, grams = best_left * 0.2, 0
    for _, layer in ipairs(slice.layers) do
        if wanted <= 0 then break end
        local taken = math.min(layer.amount, wanted)
        layer.amount = layer.amount - taken
        wanted = wanted - taken
        grams = grams + taken
    end
    grams = grams + finish_crumbs(slice)
    local points = credit(seat, grams, slice)
    seat.fullness = math.min(STUFFED_AT - 1, seat.fullness + 8)
    local victim = 0
    for _, other in ipairs(seats) do
        if other ~= seat and front_number(other) == best_number then victim = other.number end
    end
    emit("item", { p = seat.number, id = "raccoon_fork", tg = victim, g = points })
    return true
end

-- Items aimed at the leader name their target in the event; the rest do not.
local AIMED = { spoon_throw = true, hot_pepper = true, salt_shaker = true }

function use_item(request)
    local seat = seats[math.floor(request.seat)]
    local effect = ITEM_EFFECTS[tostring(request.item)]
    if not seat or not effect or not cake then return false end
    local target = seats[math.floor(tonumber(request.leader) or 0)]
    if not effect(seat, target) then return false end
    if AIMED[request.item] then
        emit("item", { p = seat.number, id = request.item, tg = target.number })
    elseif request.item ~= "raccoon_fork" then
        emit("item", { p = seat.number, id = request.item, tg = 0 })
    end
    return true
end

-- =============================================================================
-- The step
-- =============================================================================
local function update_slices(delta)
    for _, slice in ipairs(cake.slices) do
        if slice.salted > 0 then slice.salted = slice.salted - delta end
        if cake.kind.melts then
            for _, layer in ipairs(slice.layers) do
                if layer.kind == "icecream" and layer.amount > 0 then
                    layer.amount = math.max(0, layer.amount - slice.size * 0.012 * delta)
                end
            end
            if remaining(slice) > 0 and remaining(slice) <= slice.size * CRUMB_SHARE then finish_crumbs(slice) end
        end
    end
end

-- Now and then a golden cherry lands on a full slice (a magnet pulls it closer).
local function drop_cherry(delta)
    cake.cherry_in = cake.cherry_in - delta
    if cake.cherry_in > 0 then return end
    cake.cherry_in = random_between(30, 55)
    local candidates, weights, total = {}, {}, 0
    for index, slice in ipairs(cake.slices) do
        if not slice.cherry and remaining(slice) > slice.size * 0.4 then
            local weight = 1
            for _, seat in ipairs(seats) do
                if front_number(seat) == index - 1 then weight = weight + seat.upgrades.cherry_magnet * 1.5 end
            end
            table.insert(candidates, index)
            table.insert(weights, weight)
            total = total + weight
        end
    end
    if #candidates == 0 then return end
    local roll, chosen = math.random() * total, candidates[1]
    for index = 1, #candidates do
        roll = roll - weights[index]
        if roll <= 0 then
            chosen = candidates[index]
            break
        end
    end
    cake.slices[chosen].cherry = true
    emit("cherry", { s = chosen - 1 })
end

-- The waiter: turns the plate when nobody could eat for a while, and clears a
-- cake whose last crumbs take too long.
local function waiter(delta)
    if clock - cake.last_bite > NO_EATING_FOR and plate.turning_lock <= 0 and plate.table_lock <= 0 then
        cake.last_bite = clock
        emit("waiter_turn", {})
        turn_plate(math.random() < 0.5 and 1 or -1, nil)
    end
    local left, total = 0, 0
    for _, slice in ipairs(cake.slices) do
        left = left + remaining(slice)
        total = total + slice.size
    end
    cake.tail = (left < total * TAIL_SHARE) and (cake.tail + delta) or 0
    if cake.tail > TAIL_SECONDS then
        cake.tail = 0
        for _, slice in ipairs(cake.slices) do
            for _, layer in ipairs(slice.layers) do layer.amount = 0 end
        end
        emit("waiter_crumbs", {})
    end
end

local function cake_is_finished()
    for _, slice in ipairs(cake.slices) do
        if remaining(slice) > 0 then return false end
    end
    return true
end

-- A seat's body over time, and everything it does without being asked.
local function update_seat(seat, delta)
    if seat.disarmed > 0 then seat.disarmed = seat.disarmed - delta end
    if seat.coffee > 0 then seat.coffee = seat.coffee - delta end
    if seat.pushing > 0 then seat.pushing = seat.pushing - delta end
    seat.stamina = math.min(max_stamina(seat), seat.stamina + stamina_regen(seat) * delta)
    if seat.fullness > 0 then seat.fullness = math.max(0, seat.fullness - digestion(seat) * delta) end
    if seat.stuffed and seat.fullness <= CALM_AT then seat.stuffed = false end
    if seat.upgrades.bakery > 0 then
        seat.coins = seat.coins + 0.04 * cake.unit * seat.upgrades.bakery * pace * delta
    end
    seat.auto_progress = seat.auto_progress + auto_bites_per_second(seat) * delta
    while seat.auto_progress >= 1 do
        seat.auto_progress = seat.auto_progress - 1
        local careful = seat.upgrades.smart_jaw > 0 and seat.fullness > 88
        if not careful then take_bite(seat, true) end
    end
    -- an empty slice turns the plate by itself, slowly (faster with a motor)
    if remaining(front_slice(seat)) <= 0 then
        seat.push_progress = seat.push_progress + auto_pushes_per_second(seat) * delta
        while seat.push_progress >= 1 do
            seat.push_progress = seat.push_progress - 1
            local direction = best_direction(seat)
            if math.abs(plate.tension) >= 10 then direction = plate.tension > 0 and 1 or -1 end
            if direction ~= 0 then push_plate(seat, direction) end
        end
    else
        seat.push_progress = 0
    end
    -- the guard dog pushes back when someone turns a smaller slice in front of you
    local threat = seat.upgrades.guard_dog > 0 and threat_to(seat) or 0
    if threat ~= 0 then
        seat.guard_progress = seat.guard_progress + 1.5 * seat.upgrades.guard_dog * delta
        while seat.guard_progress >= 1 do
            seat.guard_progress = seat.guard_progress - 1
            push_plate(seat, -threat)
        end
    else
        seat.guard_progress = 0
    end
end

-- Earnings since the last step, then reset (game.lua adds them to the books).
local function collect_earnings()
    local score, coins, turns = {}, {}, {}
    for number, seat in ipairs(seats) do
        score[number], coins[number], turns[number] = seat.score, seat.coins, seat.turns
        seat.score, seat.coins, seat.turns = 0, 0, 0
    end
    return score, coins, turns
end

function step(request)
    local delta = tonumber(request.delta) or 0.05
    if not cake then return nil end
    clock = clock + delta
    if plate.turning_lock > 0 then plate.turning_lock = plate.turning_lock - delta end
    if plate.table_lock > 0 then
        plate.table_lock = plate.table_lock - delta
        plate.tension = 0
    end
    if plate.tension ~= 0 then
        local relax = 12 * delta
        if math.abs(plate.tension) <= relax then plate.tension = 0
        else plate.tension = plate.tension - (plate.tension > 0 and relax or -relax) end
    end
    update_slices(delta)
    drop_cherry(delta)
    waiter(delta)
    for _, seat in ipairs(seats) do
        if cake_is_finished() then break end
        update_seat(seat, delta)
    end
    local score, coins, turns = collect_earnings()
    local result = { done = cake_is_finished(), score = score, coins = coins, turns = turns }
    if result.done then
        result.eaten = cake.eaten_by
        cake = nil
    end
    return result
end

-- =============================================================================
-- What the players see (sent ten times a second by game.lua)
-- =============================================================================
-- slices: per slice three numbers - share left x1000, the top layer (its
--   index in the cake's layer list, 0 = honey, -1 = none) and flags (1 a
--   golden cherry, 2 salted);
-- seats: per seat six numbers - flags (1 stuffed, 2 spoon dropped, 4 pushing,
--   8 coffee, 16 nothing in front), fullness, arm strength x10, its maximum,
--   seconds until eating again x10, automatic bites so far.
function snapshot()
    local slices, body, left, total = {}, {}, 0, 0
    if cake then
        for _, slice in ipairs(cake.slices) do
            local amount = remaining(slice)
            local top = top_layer(slice)
            table.insert(slices, math.floor(amount / slice.size * 1000 + 0.5))
            table.insert(slices, top and top.index or -1)
            table.insert(slices, (slice.cherry and 1 or 0) + (slice.salted > 0 and 2 or 0))
            left = left + math.min(amount, slice.size)
            total = total + slice.size
        end
    end
    for _, seat in ipairs(seats) do
        local empty = not cake or remaining(front_slice(seat)) <= 0
        local flags = (seat.stuffed and 1 or 0) + (seat.disarmed > 0 and 2 or 0) + (seat.pushing > 0 and 4 or 0)
            + (seat.coffee > 0 and 8 or 0) + (empty and 16 or 0)
        local wait = 0
        if seat.disarmed > 0 then wait = seat.disarmed
        elseif seat.stuffed then wait = math.max(0, (seat.fullness - CALM_AT) / digestion(seat)) end
        table.insert(body, flags)
        table.insert(body, math.floor(seat.fullness))
        table.insert(body, math.floor(seat.stamina * 10))
        table.insert(body, max_stamina(seat))
        table.insert(body, math.floor(wait * 10))
        table.insert(body, seat.auto_bites)
    end
    local message = {
        slices = slices, seats = body, rotation = plate.rotation, tension = math.floor(plate.tension),
        turning = plate.turning_lock > 0, lock = math.floor(math.max(0, plate.table_lock) * 10),
        pushers = { plate.pushers[1] or 0, plate.pushers[-1] or 0 },
        left = total > 0 and math.floor(left / total * 100 + 0.5) or 0, events = events,
    }
    events = {}
    return message
end

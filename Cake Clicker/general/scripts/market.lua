singleton_name = "market"

-- =============================================================================
-- Cake Clicker - the market between two cakes. HOST only; game.lua drives it.
--
-- When a cake is finished the game freezes and the market opens with a row of
-- cards (3, one more for every two players past four), all of them buyable at
-- once. The market has a 20-second countdown; when it reaches zero the next
-- cake arrives.
--
-- A bought card is replaced at once by a new one, which everyone can already
-- read but nobody can buy for 5 seconds. While any card is locked like that
-- the 20-second countdown waits.
--
-- Called by game.lua (run_function "-market"):
--   open, step, peek, replace, close, snapshot
-- game.lua checks the buyer's money and room; this script only knows cards.
-- =============================================================================

local CATALOG = load_json("general/data/catalog.json")
local CARD_LOCK = CATALOG.timing.card_lock
local COUNTDOWN = CATALOG.timing.market_countdown
local BUYER_NOTE = CATALOG.timing.buyer_note
local TOOL_CHANCE = 0.3          -- how often a card is a tool the next cake needs

local CAKES = { [CATALOG.final_cake.id] = CATALOG.final_cake }
for _, cake in ipairs(CATALOG.cakes) do CAKES[cake.id] = cake end

local cards = {}                 -- { item, lock, buyer, note, opened_at }
local countdown = 0
local is_open = false
local next_cake = nil
local clock = 0
local events = {}

local function emit(kind, fields)
    local event = fields or {}
    event.k = kind
    table.insert(events, event)
end

-- Is this tool good against one of the next cake's layers?
local function cake_needs(tool, cake)
    local layers = CATALOG.tools[tool]
    if not layers or not cake then return false end
    for _, layer in ipairs(cake.layers) do
        for _, kind in ipairs(layers) do
            if layer[1] == kind then return true end
        end
    end
    return false
end

-- A random card that is not already on the table: sometimes a tool the next
-- cake calls for, otherwise any item, rarer ones less often.
local function draw_card(already_shown)
    local pool = {}
    for _, item in ipairs(CATALOG.items) do
        local shown = false
        for _, other in ipairs(already_shown) do
            if other == item.id then shown = true end
        end
        if not shown then table.insert(pool, item) end
    end
    if math.random() < TOOL_CHANCE then
        local wanted = {}
        for _, item in ipairs(pool) do
            if item.kind == "tool" and cake_needs(item.id, next_cake) then table.insert(wanted, item) end
        end
        if #wanted > 0 then return wanted[math.random(1, #wanted)].id end
    end
    local total = 0
    for _, item in ipairs(pool) do total = total + CATALOG.rarity_weights[item.rarity + 1] end
    local roll = math.random() * total
    for _, item in ipairs(pool) do
        roll = roll - CATALOG.rarity_weights[item.rarity + 1]
        if roll <= 0 then return item.id end
    end
    return pool[#pool].id
end

local function shown_items(except_slot)
    local list = {}
    for slot, card in ipairs(cards) do
        if slot ~= except_slot then table.insert(list, card.item) end
    end
    return list
end

-- The market opens: every card face up and buyable right away.
function open(request)
    next_cake = CAKES[tostring(request.next_cake)]
    cards = {}
    for slot = 1, math.floor(tonumber(request.cards) or 3) do
        cards[slot] = { item = draw_card(shown_items(0)), lock = 0, buyer = 0, note = 0, opened_at = -99 }
    end
    countdown = COUNTDOWN
    is_open = true
end

function close()
    is_open = false
    cards = {}
end

-- The card in a slot and whether it can be bought now (for game.lua's checks).
function peek(slot)
    local card = cards[math.floor(tonumber(slot) or 0)]
    if not is_open or not card then return { item = "", open = false } end
    return { item = card.item, open = card.lock <= 0 }
end

-- A card was bought: a new one takes its place, readable but locked.
function replace(request)
    local slot = math.floor(request.slot)
    if not cards[slot] then return end
    local bought = cards[slot].item
    cards[slot] = { item = draw_card(shown_items(slot)), lock = CARD_LOCK, buyer = math.floor(request.buyer),
        note = BUYER_NOTE, bought = bought, opened_at = -99 }
end

function step(request)
    local delta = tonumber(request.delta) or 0.05
    if not is_open then return { closed = false } end
    clock = clock + delta
    local any_locked = false
    for slot, card in ipairs(cards) do
        if card.lock > 0 then
            card.lock = card.lock - delta
            if card.lock <= 0 then
                card.lock = 0
                card.opened_at = clock
                emit("unlocked", { s = slot })
            else
                any_locked = true
            end
        end
        if card.note > 0 then
            card.note = card.note - delta
            if card.note <= 0 then card.buyer = 0 end
        end
    end
    -- the countdown waits while a new card is still locked
    if not any_locked then countdown = countdown - delta end
    if countdown <= 0 then
        close()
        return { closed = true }
    end
    return { closed = false }
end

-- cards: per card { item, lock left x10, who just bought the card it
-- replaced (seat number, 0 = nobody), what they bought, seconds since it
-- unlocked x10 (bots wait a moment before buying a card that just opened) }
function snapshot()
    local list = {}
    for _, card in ipairs(cards) do
        local since = card.opened_at > 0 and (clock - card.opened_at) or 99
        table.insert(list, { card.item, math.floor(card.lock * 10 + 0.5), card.buyer, card.bought or "",
            math.floor(math.min(99, since) * 10) })
    end
    local message = { cards = list, countdown = math.floor(math.max(0, countdown) * 10 + 0.5),
        next_cake = next_cake and next_cake.id or "", events = events }
    events = {}
    return message
end

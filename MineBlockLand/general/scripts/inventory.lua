singleton_name = "inv"
network_mode = 0

-- =============================================================================
-- MineBlockLand - inventories, held items and the craft panel.
--
-- HOST-AUTHORITATIVE: the host owns every player's item counts. Clients only
-- send intents (craft, equip); walking over a ground item is detected host-side
-- by the item entity itself. After any change the host sends that ONE player
-- their updated inventory (event-based - nothing is synced per frame).
--
-- The UI is Terraria-style: every recipe is always listed and its colour says
-- how close you are - gray (own nothing), orange (own some), green (craftable).
-- Clicking any entry shows its description; clicking an equippable item equips
-- it (shown in everyone's world on top of your body).
-- =============================================================================

local COLOR_HEADER = Color(38 / 255, 43 / 255, 68 / 255, 1)     -- Shade
local COLOR_ITEM = Color(58 / 255, 68 / 255, 102 / 255, 1)      -- Steel
local COLOR_HELD = Color(24 / 255, 60 / 255, 62 / 255, 1)       -- Mold (equipped)
local COLOR_NONE = Color(90 / 255, 105 / 255, 136 / 255, 0.6)   -- Iron, dimmed
local COLOR_SOME = Color(247 / 255, 118 / 255, 34 / 255, 1)     -- Amber
local COLOR_READY = Color(99 / 255, 199 / 255, 77 / 255, 1)     -- Glade
local COLOR_DROP = Color(110 / 255, 32 / 255, 32 / 255, 1)      -- Muted red
-- Inventory and crafting are two separate side-by-side panels (left / right)
-- that always open and close together on E - see toggle_panel().
local INV_PANEL = "_mbl_inventory"
local CRAFT_LIST_PANEL = "_mbl_crafting"
local CRAFT_PANEL = "_mbl_craft_qty" -- the "how many?" popup opened from a recipe row
local INV_TABLE = "mbl_inv_table"
local CRAFT_TABLE = "mbl_craft_table"
local ITEM_CELL_SIZE = Vector2(340, 40) -- item cell (grid column 0)
local DROP_CELL_SIZE = Vector2(80, 40)  -- drop cell right next to it (column 1)
local CRAFT_CELL_SIZE = Vector2(420, 40)

-- Host state.
inv = {}   -- steam_id -> { item_id -> count }
held = {}  -- steam_id -> item_id ("" = fists)

-- Local (per-peer) state.
my_inv = {}
my_held = ""

-- =============================================================================
-- Host-side inventory primitives.
-- =============================================================================

function host_get(steam_id)
    if not inv[steam_id] then inv[steam_id] = {} end
    return inv[steam_id]
end

function host_count(steam_id, item_id)
    return host_get(steam_id)[item_id] or 0
end

function host_add(steam_id, item_id, count)
    local bag = host_get(steam_id)
    bag[item_id] = (bag[item_id] or 0) + count
end

-- Returns true and removes the items only when the player really has them.
function host_consume(args)
    local steam_id, item_id, count = args.steam_id, args.item_id, args.count
    local bag = host_get(steam_id)
    if (bag[item_id] or 0) < count then return false end
    bag[item_id] = bag[item_id] - count
    if bag[item_id] <= 0 then
        bag[item_id] = nil
        if held[steam_id] == item_id then
            set_held(steam_id, "")
        end
    end
    host_sync(steam_id)
    return true
end

-- Send ONE player their own inventory (also runs on the host peer, so the
-- handler filters by the target id).
function host_sync(steam_id)
    run_network_function(name, "inv_sync_ALL", { steam_id, host_get(steam_id) }, steam_id)
end

function inv_sync_ALL(sender_id, target_id, bag)
    if LOCAL_STEAM_ID ~= target_id then return end
    my_inv = bag or {}
    set_label({ name = "_mbl_arrows", text = "Arrows: " .. math.floor(my_inv.arrow or 0) })
    -- Owned counts affect both panels (backpack contents and recipe colors).
    if is_panel_exists(INV_PANEL) then rebuild_inventory_panel() end
    if is_panel_exists(CRAFT_LIST_PANEL) then rebuild_crafting_panel() end
end

-- Ground items call this from the host when a player body touches them.
function host_pickup(args)
    local picker, item_id, count = args.picker, args.item_id, args.count
    if item_id == "chest" then
        local chest = run_function("-items", "get_chest_loot")
        local rolls = math.random(chest.rolls_min, chest.rolls_max)
        local got = {}
        for _ = 1, rolls do
            local total = 0
            for _, entry in ipairs(chest.loot) do total = total + entry.weight end
            local pick = math.random(total)
            for _, entry in ipairs(chest.loot) do
                pick = pick - entry.weight
                if pick <= 0 then
                    local n = math.random(entry.min, entry.max)
                    host_add(picker, entry.id, n)
                    local item = run_function("-items", "get_item", { entry.id })
                    table.insert(got, n .. " " .. item.name)
                    break
                end
            end
        end
        run_function("-gm", "announce", { get_value("", picker, "nickname")
            .. " opened a chest: " .. table.concat(got, ", ") })
    else
        host_add(picker, item_id, count)
    end
    host_sync(picker)
end

-- Death: fling the whole inventory onto the ground around the body.
function host_scatter(steam_id)
    local pos = get_value("", steam_id, "position")
    if pos then
        for item_id, count in pairs(host_get(steam_id)) do
            -- Big stacks scatter as a few piles, not one entity per unit.
            local piles = math.min(count, 3)
            local per = count // piles
            local extra = count - per * piles
            for p = 1, piles do
                local angle = math.random() * 2 * math.pi
                local dist = 14 + math.random() * 22
                spawn_entity_host({ t = "ground_item",
                    p = Vector2(pos.x + math.cos(angle) * dist, pos.y + math.sin(angle) * dist),
                    item_id = item_id, count = per + (p == 1 and extra or 0) })
            end
        end
    end
    inv[steam_id] = {}
    set_held(steam_id, "")
    host_sync(steam_id)
end

-- Drop 'count' of 'item_id' on the ground near the player (key press or the
-- inventory panel's Drop button both funnel through here).
function drop_HOST(sender_id, item_id, count)
    if not item_id or item_id == "" then return end
    count = math.floor(count or 1)
    if count <= 0 then return end
    local owned = host_count(sender_id, item_id)
    if owned <= 0 then return end
    count = math.min(count, owned)
    local pos = get_value("", sender_id, "position")
    if not pos then return end
    local bag = host_get(sender_id)
    bag[item_id] = bag[item_id] - count
    if bag[item_id] <= 0 then
        bag[item_id] = nil
        if held[sender_id] == item_id then set_held(sender_id, "") end
    end
    -- Nudge it off the player's own body so it does not get instantly
    -- re-picked-up by the same collision that dropped it.
    local angle = math.random() * 2 * math.pi
    local dist = 20 + math.random() * 10
    spawn_entity_host({ t = "ground_item",
        p = Vector2(pos.x + math.cos(angle) * dist, pos.y + math.sin(angle) * dist),
        item_id = item_id, count = count })
    host_sync(sender_id)
end

-- =============================================================================
-- Held item (host validates, everyone renders).
-- =============================================================================

function set_held(steam_id, item_id)
    held[steam_id] = item_id
    run_network_function(name, "held_ALL", { steam_id, item_id })
end

function equip_HOST(sender_id, item_id)
    if item_id ~= "" then
        if host_count(sender_id, item_id) <= 0 then return end
        if not run_function("-items", "is_equippable", { item_id }) then return end
    end
    set_held(sender_id, item_id)
end

function held_ALL(sender_id, steam_id, item_id)
    if steam_id == LOCAL_STEAM_ID then
        my_held = item_id
        if is_panel_exists(INV_PANEL) then rebuild_inventory_panel() end
    end
    if get_value("", steam_id, "name") ~= nil then -- entity may not exist yet on a joining peer
        run_function(steam_id, "set_held_visual", { item_id })
    end
end

function get_held(steam_id)
    return held[steam_id] or ""
end

-- =============================================================================
-- Crafting.
-- =============================================================================

-- How many times 'recipe' can be crafted with what 'sender_id' currently owns.
function host_max_crafts(sender_id, recipe)
    local max_times = 999999
    for item_id, needed in pairs(recipe.needs) do
        max_times = math.min(max_times, host_count(sender_id, item_id) // needed)
    end
    return math.max(max_times, 0)
end

-- 'requested' is clamped to what the player can actually afford and to a
-- sane upper bound (the "Max" button sends a huge sentinel; the host alone
-- decides the real number - never trust the client's count).
function craft_HOST(sender_id, recipe_index, requested)
    local recipe = run_function("-items", "get_recipe", { math.floor(recipe_index) })
    if not recipe then return end
    requested = math.floor(requested or 1)
    local times = math.max(math.min(requested, host_max_crafts(sender_id, recipe), 999), 0)
    if times <= 0 then return end
    local bag = host_get(sender_id)
    for item_id, needed in pairs(recipe.needs) do
        bag[item_id] = bag[item_id] - needed * times
        if bag[item_id] <= 0 then bag[item_id] = nil end
    end
    host_add(sender_id, recipe.id, recipe.count * times)
    run_function("-gm", "add_stat", { sender_id, "crafts", times })
    host_sync(sender_id)
end

-- =============================================================================
-- Save / load (called by -gm).
-- =============================================================================

function get_save_data()
    return { inv = inv, held = held }
end

function load_save_data(data)
    -- JSON round-trips numbers as floats; keep item counts integral.
    inv = {}
    for steam_id, bag in pairs(data.inv or {}) do
        inv[steam_id] = {}
        for item_id, count in pairs(bag) do
            inv[steam_id][item_id] = math.floor(count)
        end
    end
    held = data.held or {}
end

function host_sync_all_to(steam_id)
    host_sync(steam_id)
    -- Late joiner also needs to see what everyone currently holds.
    for other_id, item_id in pairs(held) do
        run_network_function(name, "held_ALL", { other_id, item_id }, steam_id)
    end
end

-- =============================================================================
-- Panel UI (local only; built from my_inv).
-- =============================================================================

-- E always opens/closes both panels together.
function toggle_panel()
    if is_panel_exists(INV_PANEL) then
        close_panel(INV_PANEL)
        if is_panel_exists(CRAFT_LIST_PANEL) then close_panel(CRAFT_LIST_PANEL) end
        if is_panel_exists(CRAFT_PANEL) then close_panel(CRAFT_PANEL) end
        return
    end
    rebuild_inventory_panel()
    rebuild_crafting_panel()
end

-- Sorted list of owned item ids for a stable panel layout.
local function sorted_items()
    local ids = {}
    for item_id in pairs(my_inv) do table.insert(ids, item_id) end
    table.sort(ids, function(a, b)
        local ia = run_function("-items", "get_item", { a })
        local ib = run_function("-items", "get_item", { b })
        return ia.name < ib.name
    end)
    return ids
end

-- "0/8 Stone" (nothing owned) or "100/8 Stone" (already more than enough) -
-- always shows what you HAVE against what you NEED, never just the need.
local function needs_text(recipe)
    local parts = {}
    for item_id, count in pairs(recipe.needs) do
        local item = run_function("-items", "get_item", { item_id })
        local owned = my_inv[item_id] or 0
        table.insert(parts, owned .. "/" .. count .. " " .. item.name)
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

-- Gray: owns none of the ingredients. Orange: owns some. Green: craftable.
local function recipe_color(recipe)
    local have_any, have_all = false, true
    for item_id, count in pairs(recipe.needs) do
        local owned = my_inv[item_id] or 0
        if owned > 0 then have_any = true end
        if owned < count then have_all = false end
    end
    if have_all then return COLOR_READY end
    if have_any then return COLOR_SOME end
    return COLOR_NONE
end

-- Inventory rows are a 2-column grid: item cell (equip) + a drop cell right
-- next to it. Rows with nothing to drop (Fists, the empty-bag message) still
-- need BOTH cells filled in - set_table lays cells out by insertion order, so
-- a row missing its column-1 cell would shift every following row sideways.
local function inv_row(table_data, row, color, icon, text, item_id, droppable)
    table_data[vector2_to_string(Vector2(0, row))] = { text = text, color = color,
        icon_path = icon or "", size = ITEM_CELL_SIZE, role = "equip", item_id = item_id or "" }
    if droppable then
        table_data[vector2_to_string(Vector2(1, row))] = { text = "Drop", color = COLOR_DROP,
            size = DROP_CELL_SIZE, role = "drop", item_id = item_id }
    else
        table_data[vector2_to_string(Vector2(1, row))] = { text = "", color = COLOR_HEADER,
            size = DROP_CELL_SIZE, role = "" }
    end
end

-- offset_ratio: 0,0 = top-left of screen, 1,1 = centre, 2,2 = bottom-right.
-- 0.5/1.5 centres each panel within its own half of the screen.
-- The panel itself is only ever created once; every later call (item pickup,
-- drop, craft, equip...) just refreshes the table in place via set_table, so
-- the player's window position/size and scroll offset are never reset.
function rebuild_inventory_panel()
    if not is_panel_exists(INV_PANEL) then
        create_panel({ name = INV_PANEL, title = "Inventory",
            text = "Click an item to equip it (or read what it does).",
            minimum_size = Vector2(430, 560), is_scrollable = true, resizable = true,
            close = true, set_time = false, offset_ratio = Vector2(0.5, 1),
            color = Color(24 / 255, 20 / 255, 37 / 255, 0.95) })
    end

    local table_data = {}
    inv_row(table_data, 0, my_held == "" and COLOR_HELD or COLOR_ITEM, "",
        "Fists (always ready)", "", false)
    local ids = sorted_items()
    if #ids == 0 then
        inv_row(table_data, 1, COLOR_ITEM, "",
            "(empty - chop trees, mine rock, grab what drops)", "", false)
    else
        for row, item_id in ipairs(ids) do
            local item = run_function("-items", "get_item", { item_id })
            local text = item.name .. "  x" .. math.floor(my_inv[item_id])
            local color = (my_held == item_id) and COLOR_HELD or COLOR_ITEM
            inv_row(table_data, row, color, item.image, text, item_id, true)
        end
    end
    set_table(INV_PANEL, { name = INV_TABLE, table_data = table_data,
        entity_name = name, function_name = "on_inv_cell_click" })
end

-- Ready-first ordering for the crafting list: fully craftable recipes float
-- to the top, then partial, then none - stable within each group so tiers
-- stay in the same relative order RECIPES was written in (items.lua).
local function recipe_rank(recipe)
    local have_any, have_all = false, true
    for item_id, count in pairs(recipe.needs) do
        local owned = my_inv[item_id] or 0
        if owned > 0 then have_any = true end
        if owned < count then have_all = false end
    end
    if have_all then return 0 end
    if have_any then return 1 end
    return 2
end

function rebuild_crafting_panel()
    if not is_panel_exists(CRAFT_LIST_PANEL) then
        create_panel({ name = CRAFT_LIST_PANEL, title = "Crafting",
            text = "Click a recipe to craft it.",
            minimum_size = Vector2(430, 560), is_scrollable = true, resizable = true,
            close = true, set_time = false, offset_ratio = Vector2(1.5, 1),
            color = Color(24 / 255, 20 / 255, 37 / 255, 0.95) })
    end

    local recipes = run_function("-items", "get_recipes")
    local indices = {}
    for index in ipairs(recipes) do table.insert(indices, index) end
    table.sort(indices, function(a, b)
        local ra, rb = recipe_rank(recipes[a]), recipe_rank(recipes[b])
        if ra ~= rb then return ra < rb end
        return a < b -- stable: keep RECIPES' own order within the same rank
    end)

    local table_data = {}
    for row, index in ipairs(indices) do
        local recipe = recipes[index]
        local item = run_function("-items", "get_item", { recipe.id })
        local text = item.name
        if recipe.count > 1 then text = text .. " x" .. recipe.count end
        text = text .. "   [" .. needs_text(recipe) .. "]"
        table_data[vector2_to_string(Vector2(0, row - 1))] = { text = text,
            color = recipe_color(recipe), icon_path = item.image,
            size = CRAFT_CELL_SIZE, index = index }
    end
    set_table(CRAFT_LIST_PANEL, { name = CRAFT_TABLE, table_data = table_data,
        entity_name = name, function_name = "on_craft_cell_click" })
end

function on_inv_cell_click(data)
    local cell = data.cell_data
    local item_id = cell.item_id
    if cell.role == "equip" then
        if item_id == "" then
            update_panel_settings(INV_PANEL, { text = "Fists: " ..
                run_function("-items", "get_fists").desc })
            run_network_function(name, "equip_HOST", { "" })
            return
        end
        local item = run_function("-items", "get_item", { item_id })
        update_panel_settings(INV_PANEL, { text = item.name .. ": " .. item.desc })
        if run_function("-items", "is_equippable", { item_id }) then
            run_network_function(name, "equip_HOST", { item_id })
        end
    elseif cell.role == "drop" then
        run_network_function(name, "drop_HOST", { item_id, 1 })
    end
end

-- How many times the client can currently afford this recipe (a display
-- estimate for the "Max" button - the host re-derives the real number from
-- its own authoritative counts before crafting anything).
local function max_craftable(recipe)
    local max_times = nil
    for item_id, count in pairs(recipe.needs) do
        local owned = my_inv[item_id] or 0
        local times = owned // count
        if max_times == nil or times < max_times then max_times = times end
    end
    return max_times or 0
end

function on_craft_cell_click(data)
    -- index round-tripped through set_table's GDScript table_data - floats now.
    on_craft_click(math.floor(data.cell_data.index))
end

-- Clicking a recipe opens a small "how many?" panel instead of crafting
-- immediately, so 1/10/100/max are all one click away.
function on_craft_click(index)
    local recipe = run_function("-items", "get_recipe", { index })
    local item = run_function("-items", "get_item", { recipe.id })
    if is_panel_exists(CRAFT_PANEL) then close_panel(CRAFT_PANEL) end
    local max_times = max_craftable(recipe)
    create_panel({ name = CRAFT_PANEL, title = "Craft " .. item.name,
        text = item.name .. ": " .. item.desc .. "\nNeeds: " .. needs_text(recipe) ..
            "\nMax craftable now: " .. max_times,
        resizable = false, close = true, set_time = false })
    local qty_color = Color(58 / 255, 111 / 255, 66 / 255, 1)
    for _, qty in ipairs({ 1, 10, 100 }) do
        add_button_to_panel(CRAFT_PANEL, { text = "x" .. qty, is_vertical = false,
            color = qty_color, entity_name = name, function_name = "on_craft_qty_click",
            extra_args = { index = index, count = qty } })
    end
    add_button_to_panel(CRAFT_PANEL, { text = "Max", is_vertical = false,
        color = COLOR_READY, entity_name = name, function_name = "on_craft_qty_click",
        extra_args = { index = index, count = math.max(max_times, 1) } })
end

function on_craft_qty_click(data)
    local index = data.extra_args.index
    local count = data.extra_args.count
    if is_panel_exists(CRAFT_PANEL) then close_panel(CRAFT_PANEL) end
    run_network_function(name, "craft_HOST", { index, count })
end

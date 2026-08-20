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
-- Clicking any entry shows its description; clicking a tool/food/seed/block
-- equips it into your hand, shown on the aim dot. A worn accessory is a
-- separate slot with its own Equip/Unequip button (see items.lua's
-- "wearable" field) and is drawn at a fixed spot on the body instead.
-- =============================================================================

local COLOR_HEADER = Color(38 / 255, 43 / 255, 68 / 255, 1)     -- Shade
local COLOR_ITEM = Color(58 / 255, 68 / 255, 102 / 255, 1)      -- Steel
local COLOR_HELD = Color(24 / 255, 60 / 255, 62 / 255, 1)       -- Mold (equipped)
local COLOR_NONE = Color(90 / 255, 105 / 255, 136 / 255, 0.6)   -- Iron, dimmed
local COLOR_SOME = Color(247 / 255, 118 / 255, 34 / 255, 1)     -- Amber
local COLOR_READY = Color(99 / 255, 199 / 255, 77 / 255, 1)     -- Glade
local COLOR_DROP = Color(110 / 255, 32 / 255, 32 / 255, 1)      -- Muted red
local COLOR_EQUIP = Color(58 / 255, 111 / 255, 66 / 255, 1)     -- Moss (put it on)
local COLOR_UNEQUIP = Color(90 / 255, 105 / 255, 136 / 255, 1)  -- Iron (take it off)
-- Inventory and crafting are two separate side-by-side panels (left / right)
-- that always open and close together on E - see toggle_panel().
local INV_PANEL = "_mbl_inventory"
local CRAFT_LIST_PANEL = "_mbl_crafting"
local CRAFT_PANEL = "_mbl_craft_qty" -- the "how many?" popup opened from a recipe row
local INV_TABLE = "mbl_inv_table"
local CRAFT_TABLE = "mbl_craft_table"
-- One row is three cells wide, and the three widths add up to the same 420 the
-- old two-cell row did, so the panel keeps its size.
local ITEM_CELL_SIZE = Vector2(260, 40)  -- item cell (grid column 0)
local EQUIP_CELL_SIZE = Vector2(90, 40)  -- Equip / Unequip (column 1)
local DROP_CELL_SIZE = Vector2(70, 40)   -- Drop (column 2)
-- Craft rows are two separate buttons (icon-only + text-only) so a long
-- recipe name can never steal space from the icon and shrink it.
local CRAFT_ICON_CELL_SIZE = Vector2(56, 56)
local CRAFT_TEXT_CELL_SIZE = Vector2(364, 56) -- 2 text lines tall

-- Host state.
inv = {}   -- steam_id -> { item_id -> count }
held = {}  -- steam_id -> item_id ("" = fists)
worn = {}  -- steam_id -> item_id ("" = nothing worn); wearable accessories only,
           -- a slot of its own so equipping a hat never bumps a tool out of hand
-- Per-player progression that is NOT an item and must outlive a disconnect:
-- max HP bought with Heart Containers, the cosmetic pet, the current mount.
-- Kept here (rather than on the user entity) because the user entity is
-- destroyed on leave, while this table is saved with the world by -gm.
progress = {} -- steam_id -> { max_hp = n, pet = "", mount = "" }

-- Local (per-peer) state.
my_inv = {}
my_held = ""
my_worn = ""

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
        if worn[steam_id] == item_id then
            set_worn(steam_id, "")
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
    set_label({ name = "_mbl_arrows", text ="{arrows}" .. math.floor(my_inv.arrow or 0) })
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
            .. "{opened_a_chest}" .. table.concat(got, ", ") })
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
    set_worn(steam_id, "")
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
        if worn[sender_id] == item_id then set_worn(sender_id, "") end
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

-- The equip click, heard by whoever is standing close enough - the held_ALL /
-- worn_ALL broadcast that changes the sprite already reaches every peer, so
-- there is nothing extra to send.
--
-- 'quiet' is what host_sync_all_to passes: a joining peer is told what every
-- player in the lobby is holding and wearing in one burst, and that is a state
-- restore, not a lobby full of people equipping things at the same instant.
-- Taking something OFF ("") is silent too - only picking something up clicks.
local EQUIP_DISTANCE = 300

function equip_sound(steam_id, item_id, quiet)
    if quiet or item_id == "" then return end
    local pos = get_value("", steam_id, "position")
    if not pos then return end
    set_audio({ stream_path = "item_equiped", is_2d = true, position = pos,
        max_distance = EQUIP_DISTANCE, volume = -4, random_pitch = 0.08 })
end

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

function held_ALL(sender_id, steam_id, item_id, quiet)
    if steam_id == LOCAL_STEAM_ID then
        my_held = item_id
        if is_panel_exists(INV_PANEL) then rebuild_inventory_panel() end
    end
    if get_value("", steam_id, "name") ~= nil then -- entity may not exist yet on a joining peer
        run_function(steam_id, "set_held_visual", { item_id })
        equip_sound(steam_id, item_id, quiet)
    end
end

function get_held(steam_id)
    return held[steam_id] or ""
end

-- =============================================================================
-- Worn accessory (its own slot: a hat/boots never bumps a tool out of hand).
-- Host validates, every peer renders it fixed on the body (see user.lua's
-- set_worn_visual) and the wearer's own copy also gates local passive effects.
-- =============================================================================

function set_worn(steam_id, item_id)
    worn[steam_id] = item_id
    run_network_function(name, "worn_ALL", { steam_id, item_id })
end

function wear_HOST(sender_id, item_id)
    if item_id ~= "" then
        if host_count(sender_id, item_id) <= 0 then return end
        if not run_function("-items", "is_wearable", { item_id }) then return end
    end
    set_worn(sender_id, item_id)
end

function worn_ALL(sender_id, steam_id, item_id, quiet)
    if steam_id == LOCAL_STEAM_ID then
        my_worn = item_id
        if is_panel_exists(INV_PANEL) then rebuild_inventory_panel() end
    end
    if get_value("", steam_id, "name") ~= nil then -- entity may not exist yet on a joining peer
        run_function(steam_id, "set_worn_visual", { item_id })
        equip_sound(steam_id, item_id, quiet)
    end
end

function get_worn(steam_id)
    return worn[steam_id] or ""
end

-- =============================================================================
-- Per-player progression (host only). Read/written by user.lua; saved by -gm.
-- =============================================================================

function host_get_progress(steam_id, key)
    local entry = progress[steam_id]
    return entry and entry[key] or nil
end

function host_set_progress(args)
    if not IS_HOST then return end
    if not progress[args.steam_id] then progress[args.steam_id] = {} end
    progress[args.steam_id][args.key] = args.value
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
    return { inv = inv, held = held, worn = worn, progress = progress }
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
    worn = data.worn or {}
    -- Same float round-trip: max_hp must come back as a whole number or the HP
    -- bar and every "max_hp - hp" comparison drift by fractions.
    progress = {}
    for steam_id, entry in pairs(data.progress or {}) do
        progress[steam_id] = {
            max_hp = entry.max_hp and math.floor(entry.max_hp) or nil,
            pet = entry.pet,
            mount = entry.mount,
        }
    end
end

function host_sync_all_to(steam_id)
    host_sync(steam_id)
    -- Late joiner also needs to see what everyone currently holds and wears.
    -- Sent quiet (see equip_sound): this is a state restore, so it must not
    -- sound like the whole lobby re-equipping at once the moment you walk in.
    for other_id, item_id in pairs(held) do
        run_network_function(name, "held_ALL", { other_id, item_id, true }, steam_id)
    end
    for other_id, item_id in pairs(worn) do
        run_network_function(name, "worn_ALL", { other_id, item_id, true }, steam_id)
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

-- Inventory rows are a 3-column grid: the item cell, an Equip/Unequip button
-- and a Drop button. Clicking the item cell equips a tool/food/seed/block into
-- your HAND same as always (and always shows the description) - that slot has
-- no dedicated button, since R already cycles it and Fists is one click away.
-- The labelled Equip/Unequip button is reserved for WORN accessories: a
-- separate slot (see items.lua's "wearable" field) with no Fists-equivalent
-- to fall back to, so it needs its own explicit way to take it back off.
--
-- Rows with nothing to equip or drop (Fists, the empty-bag message) still need
-- ALL THREE cells filled in: set_table walks the grid and silently skips any
-- cell you did not provide, and a GridContainer packs its children in sequence,
-- so one missing cell would shift every following row sideways.
--
-- equip_state: "equip" | "unequip" | "none".
local function inv_row(table_data, row, color, icon, text, item_id, equip_state, droppable)
    table_data[vector2_to_string(Vector2(0, row))] = { text = text, color = color,
        icon_path = icon or "", size = ITEM_CELL_SIZE, role = "equip", item_id = item_id or "" }
    if equip_state == "equip" then
        table_data[vector2_to_string(Vector2(1, row))] = { text ="{equip}", color = COLOR_EQUIP,
            size = EQUIP_CELL_SIZE, role = "equip_btn", item_id = item_id or "" }
    elseif equip_state == "unequip" then
        table_data[vector2_to_string(Vector2(1, row))] = { text ="{unequip}", color = COLOR_UNEQUIP,
            size = EQUIP_CELL_SIZE, role = "unequip_btn", item_id = item_id or "" }
    else
        table_data[vector2_to_string(Vector2(1, row))] = { text = "", color = COLOR_HEADER,
            size = EQUIP_CELL_SIZE, role = "" }
    end
    if droppable then
        table_data[vector2_to_string(Vector2(2, row))] = { text ="{drop}", color = COLOR_DROP,
            size = DROP_CELL_SIZE, role = "drop", item_id = item_id }
    else
        table_data[vector2_to_string(Vector2(2, row))] = { text = "", color = COLOR_HEADER,
            size = DROP_CELL_SIZE, role = "" }
    end
end

-- offset_ratio: 0,0 = top-left of screen, 1,1 = centre, 2,2 = bottom-right.
-- Shifted left of the 0.5/1.5 half-screen split so the crafting panel (the
-- right one) does not clip off the right edge on narrower windows.
-- The panel itself is only ever created once; every later call (item pickup,
-- drop, craft, equip...) just refreshes the table in place via set_table, so
-- the player's window position/size and scroll offset are never reset.
function rebuild_inventory_panel()
    if not is_panel_exists(INV_PANEL) then
        create_panel({ name = INV_PANEL, title ="{inventory}",
            text ="{click_a_tool_food_seed_block_to_hold_it}",
            minimum_size = Vector2(430, 560), is_scrollable = true, resizable = true,
            close = true, set_time = false, offset_ratio = Vector2(0.3, 1),
            color = Color(24 / 255, 20 / 255, 37 / 255, 0.95) })
    end

    local table_data = {}
    -- Fists are the "nothing equipped" state, so their button IS the unequip:
    -- it only appears while you are actually holding something else.
    inv_row(table_data, 0, my_held == "" and COLOR_HELD or COLOR_ITEM, "",
        "{fists_always_ready}", "", my_held == "" and "none" or "equip", false)
    local ids = sorted_items()
    if #ids == 0 then
        inv_row(table_data, 1, COLOR_ITEM, "",
            "{inventory_empty_hint}", "", "none", false)
    else
        for row, item_id in ipairs(ids) do
            local item = run_function("-items", "get_item", { item_id })
            local text = item.name .. "  x" .. math.floor(my_inv[item_id])
            local color = (my_held == item_id or my_worn == item_id) and COLOR_HELD or COLOR_ITEM
            -- Only worn accessories get the labelled button - a tool/food/seed
            -- is still equipped by clicking the row itself, same as always.
            local equip_state = "none"
            if run_function("-items", "is_wearable", { item_id }) then
                equip_state = (my_worn == item_id) and "unequip" or "equip"
            end
            inv_row(table_data, row, color, item.image, text, item_id, equip_state, true)
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
        create_panel({ name = CRAFT_LIST_PANEL, title ="{crafting}",
            text ="{click_a_recipe_to_craft_it}",
            minimum_size = Vector2(430, 560), is_scrollable = true, resizable = true,
            close = true, set_time = false, offset_ratio = Vector2(1.3, 1),
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
        text = text .. "\n[" .. needs_text(recipe) .. "]"
        local color = recipe_color(recipe)
        -- Icon and text are two separate buttons on the same row (both call
        -- on_craft_cell_click with the same index) so the icon always renders
        -- at full size instead of getting squeezed by a long recipe name.
        table_data[vector2_to_string(Vector2(0, row - 1))] = { text = "",
            color = color, icon_path = item.image, size = CRAFT_ICON_CELL_SIZE, index = index }
        table_data[vector2_to_string(Vector2(1, row - 1))] = { text = text,
            color = color, size = CRAFT_TEXT_CELL_SIZE, index = index }
    end
    set_table(CRAFT_LIST_PANEL, { name = CRAFT_TABLE, table_data = table_data,
        entity_name = name, function_name = "on_craft_cell_click" })
end

function on_inv_cell_click(data)
    local cell = data.cell_data
    local item_id = cell.item_id
    if cell.role == "equip" then
        if item_id == "" then
            update_panel_settings(INV_PANEL, { text ="{fists}" ..
                run_function("-items", "get_fists").desc })
            run_network_function(name, "equip_HOST", { "" })
            return
        end
        local item = run_function("-items", "get_item", { item_id })
        update_panel_settings(INV_PANEL, { text = item.name .. ": " .. item.desc })
        if run_function("-items", "is_wearable", { item_id }) then
            run_network_function(name, "wear_HOST", { item_id })
        elseif run_function("-items", "is_equippable", { item_id }) then
            run_network_function(name, "equip_HOST", { item_id })
        end
    elseif cell.role == "equip_btn" then
        if item_id == "" then
            -- The Fists row's own button: equipping nothing IS taking the held tool off.
            run_network_function(name, "equip_HOST", { "" })
        else
            run_network_function(name, "wear_HOST", { item_id })
        end
    elseif cell.role == "unequip_btn" then
        run_network_function(name, "wear_HOST", { "" })
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
    create_panel({ name = CRAFT_PANEL, title ="{craft}" .. item.name,
        text = item.name .. ": " .. item.desc .. "{needs}" .. needs_text(recipe) ..
            "{max_craftable_now}" .. max_times,
        resizable = false, close = true, set_time = false })
    local qty_color = Color(58 / 255, 111 / 255, 66 / 255, 1)
    for _, qty in ipairs({ 1, 10, 100 }) do
        add_button_to_panel(CRAFT_PANEL, { text = "x" .. qty, is_vertical = false,
            color = qty_color, entity_name = name, function_name = "on_craft_qty_click",
            extra_args = { index = index, count = qty } })
    end
    add_button_to_panel(CRAFT_PANEL, { text ="{max}", is_vertical = false,
        color = COLOR_READY, entity_name = name, function_name = "on_craft_qty_click",
        extra_args = { index = index, count = math.max(max_times, 1) } })
end

function on_craft_qty_click(data)
    local index = data.extra_args.index
    local count = data.extra_args.count
    if is_panel_exists(CRAFT_PANEL) then close_panel(CRAFT_PANEL) end
    run_network_function(name, "craft_HOST", { index, count })
end

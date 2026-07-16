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
local PANEL = "_mbl_inventory"
local BUTTON_SIZE = Vector2(430, 40)

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
    if is_panel_exists(PANEL) then
        rebuild_panel()
    end
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
        if is_panel_exists(PANEL) then rebuild_panel() end
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

function craft_HOST(sender_id, recipe_index)
    local recipe = run_function("-items", "get_recipe", { math.floor(recipe_index) })
    if not recipe then return end
    for item_id, needed in pairs(recipe.needs) do
        if host_count(sender_id, item_id) < needed then return end
    end
    local bag = host_get(sender_id)
    for item_id, needed in pairs(recipe.needs) do
        bag[item_id] = bag[item_id] - needed
        if bag[item_id] <= 0 then bag[item_id] = nil end
    end
    host_add(sender_id, recipe.id, recipe.count)
    run_function("-gm", "add_stat", { sender_id, "crafts", 1 })
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

function toggle_panel()
    if is_panel_exists(PANEL) then
        close_panel(PANEL)
        return
    end
    rebuild_panel()
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

local function needs_text(recipe)
    local parts = {}
    for item_id, count in pairs(recipe.needs) do
        local item = run_function("-items", "get_item", { item_id })
        table.insert(parts, count .. " " .. item.name)
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

local function add_row(color, icon, text, fn, extra)
    local path = add_custom_button_to_panel(PANEL, { size = BUTTON_SIZE, color = color,
        entity_name = name, function_name = fn or "", extra_args = extra or {} })
    if icon and icon ~= "" then
        add_image_to_custom_button(path, { image_path = icon, size = Vector2(28, 28),
            offset_ratio = Vector2(0, 1) })
    end
    add_label_to_custom_button(path, { text = text, font_size = 14,
        offset_ratio = Vector2(1, 1), horizontal_alignment = 1 })
    return path
end

function rebuild_panel()
    if is_panel_exists(PANEL) then close_panel(PANEL) end
    create_panel({ name = PANEL, title = "Inventory & Crafting",
        text = "Click an item to equip it (or read what it does).",
        minimum_size = Vector2(520, 560), is_scrollable = true, resizable = true,
        close = true, set_time = false, offset_ratio = Vector2(1, 1),
        color = Color(24 / 255, 20 / 255, 37 / 255, 0.95) })

    add_row(COLOR_HEADER, "", "-  BACKPACK  -")
    add_row(my_held == "" and COLOR_HELD or COLOR_ITEM, "", "Fists (always ready)",
        "on_item_click", { item_id = "" })
    local ids = sorted_items()
    if #ids == 0 then
        add_row(COLOR_ITEM, "", "(empty - chop trees, mine rock, grab what drops)")
    end
    for _, item_id in ipairs(ids) do
        local item = run_function("-items", "get_item", { item_id })
        local text = item.name .. "  x" .. math.floor(my_inv[item_id])
        local color = (my_held == item_id) and COLOR_HELD or COLOR_ITEM
        add_row(color, item.image, text, "on_item_click", { item_id = item_id })
    end

    add_row(COLOR_HEADER, "", "-  CRAFTING  -")
    local recipes = run_function("-items", "get_recipes")
    for index, recipe in ipairs(recipes) do
        local item = run_function("-items", "get_item", { recipe.id })
        local text = item.name
        if recipe.count > 1 then text = text .. " x" .. recipe.count end
        text = text .. "   [" .. needs_text(recipe) .. "]"
        add_row(recipe_color(recipe), item.image, text, "on_craft_click", { index = index })
    end
end

function on_item_click(data)
    local item_id = data.extra_args.item_id
    if item_id == "" then
        update_panel_settings(PANEL, { text = "Fists: " ..
            run_function("-items", "get_fists").desc })
        run_network_function(name, "equip_HOST", { "" })
        return
    end
    local item = run_function("-items", "get_item", { item_id })
    update_panel_settings(PANEL, { text = item.name .. ": " .. item.desc })
    if run_function("-items", "is_equippable", { item_id }) then
        run_network_function(name, "equip_HOST", { item_id })
    end
end

function on_craft_click(data)
    local index = data.extra_args.index
    local recipe = run_function("-items", "get_recipe", { index })
    local item = run_function("-items", "get_item", { recipe.id })
    local missing = {}
    for item_id, count in pairs(recipe.needs) do
        local owned = my_inv[item_id] or 0
        if owned < count then
            local need_item = run_function("-items", "get_item", { item_id })
            table.insert(missing, (count - owned) .. " " .. need_item.name)
        end
    end
    if #missing > 0 then
        update_panel_settings(PANEL, { text = item.name .. ": " .. item.desc ..
            "  |  Missing: " .. table.concat(missing, ", ") })
        return
    end
    update_panel_settings(PANEL, { text = "Crafted " .. item.name .. "! " .. item.desc })
    run_network_function(name, "craft_HOST", { index })
end

lock_rotation = true
linear_damp = 4

-- =============================================================================
-- MineBlockLand - player entity (runs on every peer for every player).
--
-- 16x16 avatar body that ROTATES toward the mouse (entity rotation rides the
-- engine's normal dynamic sync, so this costs no extra traffic); a small dot
-- shows the facing and the held item is drawn on top of the body for everyone.
--
-- Client sends intents only (use tool / shoot / interact); the HOST copy of
-- this same script validates cooldown + stamina and applies the result. The
-- local copy runs the same stamina rules as prediction for the HUD.
-- =============================================================================

add_tag(name, "user")
add_tag(name, "alive")

-- Tile kind ids (each entity has its own Lua env; must match worldgen.lua).
local K_SEA = 7

local BODY_PX = 16
local BODY_RADIUS = 7
local BASE_SPEED = 18
local SEA_SPEED = 8            -- wading through shallow water is slow
local MAX_HP = 100
local MAX_STAMINA = 100
local STAMINA_REGEN = 14       -- per second, after a short delay
local STAMINA_REGEN_DELAY = 1.2
local STAMINA_TOLERANCE = 3    -- host forgiveness for prediction drift
local REACH = 44               -- how far you can chop/mine/farm (pixels)
local MELEE_WINDUP = 0.25
local RESPAWN_SECONDS = 2.0
local CAMERA_ZOOM = 2.6
local DEAD_TINT = Color(0.4, 0.4, 0.5, 0.5)

-- State (the HOST copy of each player is the authority; the IS_LOCAL copy
-- predicts stamina so the HUD feels instant).
hp = MAX_HP
stamina = MAX_STAMINA
held_item = ""
is_dead = false
local held_def = nil           -- cached use-definition of the held item
local clock = 0                -- monotonic sub-second clock (sums _process delta)
local last_use = -10
local last_spend = -10
local prev_inputs = { use = false, interact = false, inv = false, cycle = false }
local current_speed = BASE_SPEED
local shown_stamina = -1

-- --- visuals (identical on every peer) ---------------------------------------

set_collision({ parent_name = name, name = "col", shape = "circle", size = BODY_RADIUS,
    collision_layer = { 2 }, collision_mask = { 1 } }) -- tiles only: players never push each other

-- Default icon until Steam delivers the avatar (see _on_loaded_avatar).
body_image = set_image({ parent_name = name, name = "body", z_index = 2 })
set_image_pixel(name, "body", Vector2(BODY_PX, BODY_PX))

-- Facing dot in front of the body (rotates with the entity).
set_image({ parent_name = name, name = "dot", image_path = "white",
    position = Vector2(11, 0), scale = Vector2(3, 3), z_index = 4,
    modulate = Color(1, 1, 1, 0.9) })

nick_label = set_label({ parent_name = name, name = "nick", text = nickname,
    position = Vector2(-64, -20), size = Vector2(128, 10), font_size = 6,
    outline_size = 2, outline_color = Color(0, 0, 0, 1), z_index = 10 })

function _on_loaded_avatar(steam_id)
    if steam_id ~= name then return end
    set_image({ parent_name = name, name = "body", image_path = name, z_index = 2 })
    set_image_pixel(name, "body", Vector2(BODY_PX, BODY_PX))
end

if IS_LOCAL then
    set_camera_target(name)
    set_camera_zoom(Vector2(CAMERA_ZOOM, CAMERA_ZOOM))
    set_value("", name, "speed", BASE_SPEED)
end

-- Held item drawn on top of the body; -inv broadcasts every change.
function set_held_visual(item_id)
    held_item = item_id
    held_def = run_function("-items", "get_use_def", { item_id })
    if item_id == "" then
        set_image({ parent_name = name, name = "helditem", visible = false,
            image_path = "white" })
    else
        local item = run_function("-items", "get_item", { item_id })
        set_image({ parent_name = name, name = "helditem", image_path = item.image,
            position = Vector2(2, -4), scale = Vector2(10, 10), z_index = 3, visible = true })
    end
    if IS_LOCAL then
        local held_name = (item_id == "") and "Fists"
            or run_function("-items", "get_item", { item_id }).name
        set_label({ name = "_mbl_held", text = "Holding: " .. held_name })
    end
end

set_held_visual("")

-- =============================================================================
-- Shared stamina simulation (host = authority, local = prediction).
-- =============================================================================

local function regen_stamina(delta)
    if clock - last_spend >= STAMINA_REGEN_DELAY and stamina < MAX_STAMINA then
        stamina = math.min(stamina + STAMINA_REGEN * delta, MAX_STAMINA)
    end
end

local function spend_stamina(cost)
    stamina = stamina - cost
    last_spend = clock
end

local function can_use(def)
    return not is_dead and clock - last_use >= def.cooldown
        and stamina + STAMINA_TOLERANCE >= def.stamina
end

-- =============================================================================
-- Per-frame: facing, input edges, HUD.
-- =============================================================================

function _process(delta, inputs)
    clock = clock + delta
    if IS_HOST or IS_LOCAL then
        regen_stamina(delta)
    end

    -- Nicknames stay upright while the body rotates (local visual only).
    local my_rotation = get_value("", name, "rotation") or 0
    set_label({ parent_name = name, name = "nick", rotation = -my_rotation })

    if not IS_LOCAL then return nil end

    local live_pos = get_value("", name, "position")
    if live_pos and not is_dead then
        local aim = inputs.stick_2
        set_value("", name, "rotation", math.atan(aim.y - live_pos.y, aim.x - live_pos.x))
    end

    -- Edge-detected actions (LMB repeats itself via the cooldown gate).
    if inputs.key_12 and not is_dead and held_def and can_use(held_def) then
        -- Prediction only on clients: for the host player the _HOST handler
        -- below runs SYNCHRONOUSLY and is the one to set last_use / spend
        -- stamina (setting them here first would deny its own validation).
        if not IS_HOST then
            last_use = clock
            spend_stamina(held_def.stamina)
        end
        if held_def.tool == "bow" then
            run_network_function(name, "use_bow_HOST", { inputs.stick_2.x, inputs.stick_2.y })
        else
            run_network_function(name, "use_HOST", { inputs.stick_2.x, inputs.stick_2.y })
        end
    end
    if inputs.key_9 and not prev_inputs.interact and not is_dead then
        run_network_function(name, "interact_HOST", { inputs.stick_2.x, inputs.stick_2.y })
    end
    if inputs.key_6 and not prev_inputs.inv then
        run_function("-inv", "toggle_panel")
    end
    if inputs.key_5 and not prev_inputs.cycle then
        cycle_held()
    end
    prev_inputs.interact = inputs.key_9
    prev_inputs.inv = inputs.key_6
    prev_inputs.cycle = inputs.key_5

    if math.floor(stamina) ~= shown_stamina then
        shown_stamina = math.floor(stamina)
        set_progress_bar({ name = "_mbl_stamina", value = shown_stamina })
    end
    return nil
end

-- R cycles through everything equippable you own.
function cycle_held()
    local bag = get_value("", "-inv", "my_inv") or {}
    local options = { "" } -- fists first
    local ids = {}
    for item_id in pairs(bag) do table.insert(ids, item_id) end
    table.sort(ids)
    for _, item_id in ipairs(ids) do
        if run_function("-items", "is_equippable", { item_id }) then
            table.insert(options, item_id)
        end
    end
    if #options < 2 then return end -- nothing equippable yet
    local current = 1
    for index, item_id in ipairs(options) do
        if item_id == held_item then current = index end
    end
    local next_item = options[(current % #options) + 1]
    if next_item ~= held_item then
        run_network_function("-inv", "equip_HOST", { next_item })
    end
end

-- Shallow sea slows you down (checked a few times a second, not per frame).
function speed_check()
    if not IS_LOCAL then return end
    local live_pos = get_value("", name, "position")
    if not live_pos then return end
    local tile = local_to_map(live_pos)
    local kind = run_function("-gen", "kind_at", { math.floor(tile.x), math.floor(tile.y) })
    local wanted = (kind == K_SEA) and SEA_SPEED or BASE_SPEED -- K_SEA: local mirror above
    if wanted ~= current_speed then
        current_speed = wanted
        set_value("", name, "speed", wanted)
    end
end

start_timer({ timer_id = "speed" .. name, entity_name = name,
    function_name = "speed_check", wait_time = 0.25 })

-- =============================================================================
-- HOST: intent handlers (anti-cheat: sender must be this entity's owner).
-- =============================================================================

local function host_deny_stamina()
    run_network_function(name, "stam_sync_ALL", { stamina }, name)
end

-- LMB: chop / mine when aiming at a tree or rock in reach, melee swing otherwise.
function use_HOST(sender_id, aim_x, aim_y)
    if not IS_HOST or sender_id ~= name then return end
    local def = held_def or run_function("-items", "get_fists")
    if not can_use(def) then
        host_deny_stamina()
        return
    end
    local live_pos = get_value("", name, "position")
    if not live_pos then return end

    local tile = local_to_map(Vector2(aim_x, aim_y))
    local tile_x, tile_y = math.floor(tile.x), math.floor(tile.y)
    local tile_center = map_to_local(Vector2(tile_x, tile_y))
    local gathered = false
    if distance_to(live_pos, tile_center) <= REACH then
        gathered = run_function("-gm", "host_gather_hit", { {
            steam_id = name, x = tile_x, y = tile_y,
            tool = def.tool, power = def.power or 1 } })
    end
    if not gathered then
        -- Melee swing: telegraphed zone in front of the player, toward the aim.
        -- Tools without a melee shape (the bow) swing like bare fists.
        local angle = math.atan(aim_y - live_pos.y, aim_x - live_pos.x)
        local shape = def.shape or run_function("-items", "get_fists").shape
        local ahead = shape.ahead or 12
        local cfg = { x = live_pos.x + math.cos(angle) * ahead,
            y = live_pos.y + math.sin(angle) * ahead,
            shape = shape.kind, r = shape.r, w = shape.w, h = shape.h,
            angle = angle, windup = MELEE_WINDUP, dmg = def.damage,
            targets = "all", attacker = name, kb = 40 }
        run_function("-combat", "start_telegraph", { cfg })
    end
    last_use = clock
    spend_stamina(def.stamina)
end

function use_bow_HOST(sender_id, aim_x, aim_y)
    if not IS_HOST or sender_id ~= name then return end
    local def = held_def
    if not def or def.tool ~= "bow" then return end
    if not can_use(def) then
        host_deny_stamina()
        return
    end
    if not run_function("-inv", "host_consume",
            { { steam_id = name, item_id = "arrow", count = 1 } }) then
        run_network_function(name, "toast_ALL", { "No arrows! Craft some (1 wood + 1 stone)." }, name)
        return
    end
    last_use = clock
    spend_stamina(def.stamina)
    run_function("-combat", "host_arrow", { name, aim_x, aim_y, def.damage })
end

-- RMB: plant seeds, harvest grown crops, or eat the held food.
function interact_HOST(sender_id, aim_x, aim_y)
    if not IS_HOST or sender_id ~= name then return end
    local live_pos = get_value("", name, "position")
    if not live_pos then return end
    local tile = local_to_map(Vector2(aim_x, aim_y))
    local tile_x, tile_y = math.floor(tile.x), math.floor(tile.y)
    local in_reach = distance_to(live_pos, map_to_local(Vector2(tile_x, tile_y))) <= REACH

    if held_item == "seed" and in_reach then
        if run_function("-gm", "host_plant", { { steam_id = name, x = tile_x, y = tile_y } }) then
            return
        end
    end
    if in_reach and run_function("-gm", "host_harvest", { { x = tile_x, y = tile_y } }) then
        return
    end
    local item = run_function("-items", "get_item", { held_item })
    if item and item.heal then
        if run_function("-inv", "host_consume",
                { { steam_id = name, item_id = held_item, count = 1 } }) then
            local healed = math.min(item.heal, MAX_HP - hp)
            hp = hp + healed
            run_network_function(name, "hp_ALL", { hp }, name)
            if healed > 0 then
                run_function("-combat", "show_damage", { live_pos.x, live_pos.y, healed, "heal" })
            end
        end
    end
end

-- =============================================================================
-- HOST: damage / death / respawn.
-- =============================================================================

function host_take_damage(dmg, attacker)
    if not IS_HOST or is_dead then return end
    hp = hp - dmg
    run_function("-gm", "add_stat", { name, "dmg_taken", dmg })
    if attacker and has_tag(attacker, "user") then
        run_function("-gm", "add_stat", { attacker, "dmg_dealt", dmg })
    end
    local live_pos = get_value("", name, "position")
    if live_pos then
        run_function("-combat", "show_damage", { live_pos.x, live_pos.y, dmg, "player" })
    end
    run_network_function(name, "hp_ALL", { hp }, name)
    if hp <= 0 then
        is_dead = true
        remove_tag(name, "alive")
        freeze_entity(name)
        run_function("-gm", "on_player_died", { { steam_id = name } })
        run_network_function(name, "died_ALL", {})
        local spawn = map_to_local(Vector2(0, 0))
        run_function(name, "host_respawn_at", { spawn.x, spawn.y }, RESPAWN_SECONDS)
    end
end

function host_respawn_at(x, y)
    if not IS_HOST then return end
    unfreeze_entity(name)
    change_instantly({ entity_name = name, position = Vector2(x, y),
        linear_velocity = Vector2(0, 0) })
    hp = MAX_HP
    stamina = MAX_STAMINA
    is_dead = false
    add_tag(name, "alive")
    run_network_function(name, "hp_ALL", { hp }, name)
    run_network_function(name, "revived_ALL", {})
end

-- =============================================================================
-- Broadcast handlers (visual/HUD mirrors).
-- =============================================================================

function hp_ALL(sender_id, new_hp)
    if not IS_LOCAL then return end
    hp = new_hp
    set_progress_bar({ name = "_mbl_hp", value = math.max(hp, 0) })
end

function stam_sync_ALL(sender_id, new_stamina)
    if not IS_LOCAL then return end
    stamina = new_stamina
end

function toast_ALL(sender_id, text)
    if not IS_LOCAL then return end
    run_function("-gm", "announce_local", { text })
end

function died_ALL(sender_id)
    is_dead = true
    set_image({ parent_name = name, name = "body", modulate = DEAD_TINT })
    if IS_LOCAL then
        run_function("-gm", "announce_local", { "You died! Respawning at the camp..." })
    end
end

function revived_ALL(sender_id)
    is_dead = false
    set_image({ parent_name = name, name = "body", modulate = Color(1, 1, 1, 1) })
end

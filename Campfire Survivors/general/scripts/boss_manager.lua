singleton_name = "bm"
network_mode = 0

-- =============================================================================
-- Campfire Survivors - boss director + shared telegraph service.
--
-- Thirty minutes into a run the Guardian wakes up, the arena doubles in size
-- and the fight is on. Kill it and you get confetti, a congratulations panel
-- and the arena back at its normal size; wipe instead and wave_manager's
-- game_over path resets everything the same way.
--
-- TELEGRAPHS are the "red zone fills up, then the hit lands" warning used by
-- the boss slam and its meteors. The host sends ONE message when an attack
-- starts, every peer animates the fill locally each frame (zero further
-- traffic) and the host hurts whoever is still standing inside when the
-- windup ends - so you can always walk out of it.
-- =============================================================================

BOSS_TIME = 1800                -- seconds of survival before the Guardian shows up (30 min)
local BOSS_HP_PER_PLAYER = 2500 -- multiplied by the party size AND the wave level index
local BOSS_MAP_SCALE = 2        -- arena is this much bigger while the boss is alive

local ZONE_COLOR = Color(0.62, 0.16, 0.21, 0.42)
local FILL_COLOR = Color(0.89, 0.23, 0.27, 0.6)
local PLAYER_RADIUS = 16        -- users' body radius, see user.lua's collision

boss_active = false
boss_defeated = false
boss_entity = ""
local nav_icon_name = ""
local tg_counter = 0
local active_tg = {}            -- id -> {w, h, windup, elapsed, zone_name, fill_name}

-- =============================================================================
-- Telegraph API - call start_telegraph on the HOST only.
-- cfg = {
--   x, y     centre of the zone
--   shape    "circle" (r = radius) or "rect" (w, h, angle in radians)
--   windup   seconds until the hit lands
--   dmg      damage applied to every player still inside at the end
--   attacker entity name excluded from the victims
-- }
-- =============================================================================

function start_telegraph(cfg)
    if not IS_HOST then return end
    tg_counter = tg_counter + 1
    -- String id: Lua->GDScript numbers come back as floats, so a numeric id
    -- would turn "tgf3" into "tgf3.0" ('.' is invalid in a node name).
    local id = tostring(tg_counter)
    local w, h
    if cfg.shape == "circle" then
        w, h = cfg.r * 2, cfg.r * 2
    else
        w, h = cfg.w, cfg.h
    end
    run_network_function(name, "tg_show_ALL", {
        { id = id, x = cfg.x, y = cfg.y, shape = cfg.shape, w = w, h = h,
            angle = cfg.angle or 0, windup = cfg.windup },
    })
    start_timer({ timer_id = "tg_resolve" .. id, entity_name = name,
        function_name = "tg_resolve", wait_time = cfg.windup, duration = cfg.windup,
        extra_args = { id = id, x = cfg.x, y = cfg.y, shape = cfg.shape,
            r = cfg.r, w = cfg.w, h = cfg.h, angle = cfg.angle or 0,
            dmg = cfg.dmg, attacker = cfg.attacker } })
end

-- Every peer: build the zone + fill visuals and animate them locally.
function tg_show_ALL(sender_id, cfg)
    local zone_name = "tgz" .. cfg.id
    local fill_name = "tgf" .. cfg.id
    local base = { parent_name = name, image_path = "white",
        position = Vector2(cfg.x, cfg.y), rotation = cfg.angle }
    -- z 0/1 keeps the decal above the tiles but below the player bodies.
    base.name = zone_name
    base.scale = Vector2(cfg.w, cfg.h)
    base.modulate = ZONE_COLOR
    base.z_index = 0
    set_image(base)
    base.name = fill_name
    base.scale = Vector2(1, 1)
    base.modulate = FILL_COLOR
    base.z_index = 1
    set_image(base)
    local shader = (cfg.shape == "circle") and "circle" or "rect_telegraph"
    set_shader({ parent_name = name, image_name = zone_name, shader_name = shader })
    set_shader({ parent_name = name, image_name = fill_name, shader_name = shader })
    active_tg[cfg.id] = { w = cfg.w, h = cfg.h, windup = cfg.windup, elapsed = 0,
        zone_name = zone_name, fill_name = fill_name }
end

-- Local per-frame fill animation (no network traffic).
function _process(delta, inputs)
    for id, tg in pairs(active_tg) do
        tg.elapsed = tg.elapsed + delta
        local p = math.min(tg.elapsed / tg.windup, 1.0)
        set_image({ parent_name = name, name = tg.fill_name,
            scale = Vector2(math.max(tg.w * p, 1), math.max(tg.h * p, 1)) })
        if tg.elapsed > tg.windup + 0.5 then -- safety cleanup if the hit msg dropped
            remove_tg(id)
        end
    end
end

function remove_tg(id)
    local tg = active_tg[id]
    if not tg then return end
    destroy(name, tg.zone_name)
    destroy(name, tg.fill_name)
    active_tg[id] = nil
end

function tg_done_ALL(sender_id, id)
    remove_tg(id)
end

-- Shape-vs-circle test (a rect is centred on x,y and rotated by 'angle').
-- 'radius' is the victim's own body radius - without it only their exact
-- centre pixel would count and a clipped edge would read as a miss.
local function inside(cfg, px, py, radius)
    local dx, dy = px - cfg.x, py - cfg.y
    if cfg.shape == "circle" then
        local rr = cfg.r + radius
        return dx * dx + dy * dy <= rr * rr
    end
    local c, s = math.cos(-cfg.angle), math.sin(-cfg.angle)
    local rx = dx * c - dy * s
    local ry = dx * s + dy * c
    local hw, hh = cfg.w / 2, cfg.h / 2
    local cx = math.max(-hw, math.min(hw, rx))
    local cy = math.max(-hh, math.min(hh, ry))
    local ddx, ddy = rx - cx, ry - cy
    return ddx * ddx + ddy * ddy <= radius * radius
end

-- HOST: the windup ended - hurt every living player still inside.
-- (Timer callbacks receive their payload nested under .extra_args.)
function tg_resolve(args)
    local cfg = args.extra_args
    if not IS_HOST or not cfg then return end
    run_network_function(name, "tg_done_ALL", { cfg.id })
    for _, victim in ipairs(get_entity_names_by_tag("alive")) do
        if victim ~= cfg.attacker then
            local pos = get_value("", victim, "position")
            if pos and inside(cfg, pos.x, pos.y, PLAYER_RADIUS) then
                run_function(victim, "take_damage", { cfg.dmg })
            end
        end
    end
end

-- =============================================================================
-- Boss lifecycle (host drives it, everything visible is broadcast).
-- =============================================================================

-- Called by the campfire's per-second clock on the host.
function check_boss_time(current_time)
    if not IS_HOST or boss_active or boss_defeated then return end
    if current_time < BOSS_TIME then return end
    spawn_boss()
end

function spawn_boss()
    if not IS_HOST or boss_active then return end
    boss_active = true

    -- Grow the arena first so the boss has room to fight in, then drop it in
    -- at the centre. Both the tiles and the spawn rectangle come from "-mg".
    run_network_function("-mg", "set_map_scale_ALL", { BOSS_MAP_SCALE })

    -- HP scales with the party size AND how far the run got, so a group that
    -- reached minute 30 with fully upgraded weapons still has a fight on its
    -- hands. Its damage is scaled by the wave level inside boss.lua.
    local players = math.max(#get_entity_names_by_tag("user"), 1)
    local level_data = run_function("-mg", "get_level_data", { get_value("", "-wm", "current_wave") or 1 })
    local level_index = level_data and level_data.level_index or 1
    local hp = math.floor(BOSS_HP_PER_PLAYER * players * level_index)

    local center = run_function("-mg", "get_map_center")
    boss_entity = spawn_entity_host({ t = "boss", p = center, h = hp, wl = level_index })
    run_network_function(name, "boss_arrived_ALL", { boss_entity })
end

-- Every peer: nav icon, warning banner and a growl.
function boss_arrived_ALL(sender_id, boss_name)
    boss_active = true
    -- A targeted _ALL also fires on the host, so a late joiner would replay the
    -- announcement for everyone already in the fight. The nav icon is the flag
    -- for "this peer has already been told".
    if nav_icon_name ~= "" then return end
    nav_icon_name = set_navigation_icon({ target_name = boss_name, name = "nav_cs_boss",
        text = "{boss}", color = Color(0.89, 0.23, 0.27, 1), is_show_distance = true })
    add_to_chat("[color=#e43b44]" .. translate("{the_guardian_has_awakened}") .. "[/color]", false)
    set_label({ name = "_center_information", text = "{the_guardian_has_awakened}",
        font_color = Color(0.89, 0.23, 0.27, 1) })
    start_timer({ entity_name = name, timer_id = "boss_banner", wait_time = 4.0,
        duration = 4.0, function_name = "clear_boss_banner" })
    set_audio({ stream_path = "monster-growl", volume = -4 })
end

function clear_boss_banner()
    set_label({ name = "_center_information", text = "", font_color = Color(1, 1, 1, 1) })
end

-- HOST: the boss died (boss.lua calls this just before it destroys itself).
function on_boss_defeated(killer_id)
    if not IS_HOST or not boss_active then return end
    boss_active = false
    boss_defeated = true
    boss_entity = ""
    restore_arena()
    run_network_function(name, "victory_ALL", { killer_id or "" })
end

function victory_ALL(sender_id, killer_id)
    boss_active = false
    clear_nav_icon()

    add_to_chat("[color=#63c74d]" .. translate("{the_guardian_has_fallen}") .. "[/color]", false)

    -- Confetti around the local player.
    create_particle({ particle_id = "cs_confetti", texture_path = "white",
        lifetime = 1.8, amount = 160, explosiveness = 1.0, one_shot = true,
        spread = 180, initial_velocity_min = 90, initial_velocity_max = 260,
        gravity = { x = 0, y = 160 }, scale_amount_min = 0.15, scale_amount_max = 0.3,
        color_random = true })
    local pos = get_value("", LOCAL_STEAM_ID, "position") or Vector2(0, 0)
    start_particle({ particle_id = "cs_confetti", position = Vector2(pos.x, pos.y - 40) })

    create_panel({ name = "boss_victory_panel", title = "{congratulations}",
        text = "{you_defeated_the_guardian}", close = true, resizable = false,
        set_time = false, minimum_size = Vector2(460, 220) })

    set_label({ name = "_center_information", text = "{congratulations}",
        font_color = Color(0.39, 0.78, 0.30, 1) })
    start_timer({ entity_name = name, timer_id = "boss_banner", wait_time = 5.0,
        duration = 5.0, function_name = "clear_boss_banner" })
end

-- HOST: shrink the arena back and pull everyone to the middle, so nobody is
-- left standing on a tile that no longer exists.
function restore_arena()
    if not IS_HOST then return end
    run_network_function("-mg", "set_map_scale_ALL", { 1 })
    local center = run_function("-mg", "get_map_center")
    run_network_function_by_tag("user", "teleport_ALL", { center.x, center.y })
end

function clear_nav_icon()
    if nav_icon_name ~= "" then
        destroy("", nav_icon_name)
        nav_icon_name = ""
    end
end

-- HOST: the run ended (everyone died). Wipe the boss and give the arena back.
-- wave_manager's game_over already destroyed every "monster"-tagged entity.
function reset_boss_state()
    if not IS_HOST then return end
    local was_active = boss_active
    boss_active = false
    boss_defeated = false
    boss_entity = ""
    run_network_function(name, "clear_boss_ui_ALL", {})
    if was_active then restore_arena() end
end

function clear_boss_ui_ALL(sender_id)
    boss_active = false
    clear_nav_icon()
    for id, _ in pairs(active_tg) do
        remove_tg(id)
    end
    if is_panel_exists("boss_victory_panel") then
        close_panel("boss_victory_panel")
    end
end

-- A client that joins mid-fight needs the nav icon and the enlarged arena.
function _on_user_initialized(steam_id, nickname)
    if IS_HOST and boss_active and boss_entity ~= "" and steam_id ~= LOCAL_STEAM_ID then
        run_network_function("-mg", "set_map_scale_ALL", { BOSS_MAP_SCALE }, steam_id)
        run_network_function(name, "boss_arrived_ALL", { boss_entity }, steam_id)
    end
end

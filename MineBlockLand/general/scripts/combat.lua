singleton_name = "combat"
network_mode = 0

-- =============================================================================
-- MineBlockLand - shared combat services (one singleton, used by everyone).
--
-- TELEGRAPHS: the classic "red zone fills with white, then the hit lands"
-- warning. Fully generic: any shape (rectangle or circle, any size/angle), any
-- windup, any attacker (player, zombie or boss) against any side. The host
-- sends ONE network message when an attack starts; every peer animates the
-- fill locally each frame (zero further traffic) and the host resolves damage
-- against whoever is still inside when the windup ends - so you can dodge.
--
-- Also home to: damage number labels everyone sees, arrow hitscan (raycast
-- from the shooter toward their aim) with a tracer line, and hit puffs.
-- =============================================================================

local ZONE_COLOR = Color(158 / 255, 40 / 255, 53 / 255, 0.42)  -- Blood
local FILL_COLOR = Color(228 / 255, 59 / 255, 68 / 255, 0.6)   -- Fabric
local DAMAGE_COLORS = {
    player = Color(228 / 255, 59 / 255, 68 / 255, 1),          -- damage TO players
    npc = Color(254 / 255, 231 / 255, 97 / 255, 1),            -- damage TO enemies (Light)
    heal = Color(99 / 255, 199 / 255, 77 / 255, 1),            -- healing (Glade)
}
local DAMAGE_LABEL_SECONDS = 2.0
local TRACER_SECONDS = 0.12
local TRACER_COLOR = Color(234 / 255, 212 / 255, 170 / 255, 0.9) -- Birch
local ARROW_RANGE = 320

local tg_counter = 0
local active_tg = {}   -- id -> {x, y, w, h, angle, windup, elapsed, fill_name, zone_name}
local dmg_counter = 0

-- =============================================================================
-- Telegraph API (call start_telegraph on the HOST only).
-- cfg = {
--   x, y          centre of the zone (caller already applied any forward offset)
--   shape         "circle" (r = radius) or "rect" (w, h, angle in radians)
--   windup        seconds until the hit lands
--   dmg           damage applied to everyone still inside at the end
--   targets       "players" | "npcs" | "all"
--   attacker      entity name excluded from the victims (and credited stats)
--   kb            optional knockback applied to npc victims
-- }
-- =============================================================================

function start_telegraph(cfg)
    if not IS_HOST then return end
    tg_counter = tg_counter + 1
    local id = tg_counter
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
            dmg = cfg.dmg, targets = cfg.targets, attacker = cfg.attacker,
            kb = cfg.kb or 0 } })
end

-- Every peer: build the zone + fill visuals and animate locally in _process.
function tg_show_ALL(sender_id, cfg)
    local zone_name = "tgz" .. cfg.id
    local fill_name = "tgf" .. cfg.id
    local base = { parent_name = name, image_path = "white",
        position = Vector2(cfg.x, cfg.y), rotation = cfg.angle }
    -- z 0/1 keeps the decal above the tilemap but below player bodies (z 2).
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
    if cfg.shape == "circle" then
        set_shader({ parent_name = name, image_name = zone_name, shader_name = "circle" })
        set_shader({ parent_name = name, image_name = fill_name, shader_name = "circle" })
    end
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

-- Point-in-shape test (rect is centred and rotated by 'angle').
local function inside(cfg, px, py)
    local dx, dy = px - cfg.x, py - cfg.y
    if cfg.shape == "circle" then
        return dx * dx + dy * dy <= cfg.r * cfg.r
    end
    local c, s = math.cos(-cfg.angle), math.sin(-cfg.angle)
    local rx = dx * c - dy * s
    local ry = dx * s + dy * c
    return math.abs(rx) <= cfg.w / 2 and math.abs(ry) <= cfg.h / 2
end

local function each_victim(cfg, tag, handler)
    for _, victim in ipairs(get_entity_names_by_tag(tag)) do
        if victim ~= cfg.attacker then
            local pos = get_value("", victim, "position")
            if pos and inside(cfg, pos.x, pos.y) then
                handler(victim, pos)
            end
        end
    end
end

-- HOST: the windup ended - hurt whoever is still inside.
-- (Timer callbacks receive their payload nested under .extra_args.)
function tg_resolve(args)
    local cfg = args.extra_args
    if not IS_HOST or not cfg then return end
    run_network_function(name, "tg_done_ALL", { cfg.id })
    local ff = get_value("", "-gm", "friendly_fire") or false
    local attacker_is_player = has_tag(cfg.attacker or "", "user")
    if cfg.targets == "players" or cfg.targets == "all" then
        each_victim(cfg, "alive", function(victim, pos)
            if attacker_is_player and not ff then return end
            run_function(victim, "host_take_damage", { cfg.dmg, cfg.attacker })
        end)
    end
    if cfg.targets == "npcs" or cfg.targets == "all" then
        each_victim(cfg, "npc", function(victim, pos)
            local angle = math.atan(pos.y - cfg.y, pos.x - cfg.x)
            run_function(victim, "npc_take_damage", { cfg.dmg, cfg.attacker, cfg.kb, angle })
        end)
    end
end

-- =============================================================================
-- Damage numbers - everyone sees them, they fade out after 2 seconds.
-- =============================================================================

-- HOST helper: broadcast a floating number at a world position.
-- kind: "player" | "npc" | "heal" (picks the colour).
function show_damage(x, y, amount, kind)
    if not IS_HOST then return end
    run_network_function(name, "damage_fx_ALL", { x, y, amount, kind })
end

function damage_fx_ALL(sender_id, x, y, amount, kind)
    dmg_counter = dmg_counter + 1
    local label_name = "dmg" .. LOCAL_STEAM_ID .. "_" .. dmg_counter
    local prefix = (kind == "heal") and "+" or "-"
    set_label({ parent_name = name, name = label_name,
        text = prefix .. tostring(math.floor(amount)),
        position = Vector2(x, y - 14), size = Vector2(64, 12),
        font_size = 8, outline_size = 2, outline_color = Color(0, 0, 0, 1),
        font_color = DAMAGE_COLORS[kind] or DAMAGE_COLORS.npc, z_index = 60 })
    start_timer({ timer_id = label_name, entity_name = name,
        function_name = "clear_damage_label", wait_time = DAMAGE_LABEL_SECONDS,
        duration = DAMAGE_LABEL_SECONDS, extra_args = { label_name = label_name } })
end

function clear_damage_label(args)
    destroy(name, args.extra_args.label_name)
end

-- =============================================================================
-- Arrows: server-authoritative hitscan + a tracer line for everyone.
-- =============================================================================

-- HOST: fire an arrow from 'shooter' toward world position (aim_x, aim_y).
function host_arrow(shooter, aim_x, aim_y, dmg)
    if not IS_HOST then return end
    local from = get_value("", shooter, "position")
    if not from then return end
    local dir = Vector2(aim_x - from.x, aim_y - from.y)
    if dir.x == 0 and dir.y == 0 then dir = Vector2(1, 0) end
    local ff = get_value("", "-gm", "friendly_fire") or false
    local mask = ff and { 1, 2, 3 } or { 1, 3 }
    local hit = raycast({ from = from, direction = dir, length = ARROW_RANGE,
        collision_mask = mask, exclude = { shooter } })
    run_network_function(name, "tracer_ALL", { from.x, from.y, hit.position.x, hit.position.y })
    if not hit.hit then return end
    if has_tag(hit.collider, "npc") then
        local angle = math.atan(dir.y, dir.x)
        run_function(hit.collider, "npc_take_damage", { dmg, shooter, 60, angle })
    elseif ff and has_tag(hit.collider, "alive") then
        run_function(hit.collider, "host_take_damage", { dmg, shooter })
    end
end

local tracer_counter = 0

function tracer_ALL(sender_id, x1, y1, x2, y2)
    tracer_counter = tracer_counter + 1
    local line_name = "trc" .. LOCAL_STEAM_ID .. "_" .. tracer_counter
    set_line({ name = line_name, start_position = Vector2(x1, y1),
        end_position = Vector2(x2, y2), color = TRACER_COLOR, width = 2, z_index = 50 })
    run_function(name, "clear_tracer", { line_name }, TRACER_SECONDS)
end

function clear_tracer(line_name)
    if line_exists(line_name) then destroy_line(line_name) end
end

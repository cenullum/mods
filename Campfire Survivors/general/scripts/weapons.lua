singleton_name = "wpn"
network_mode = 0

-- =============================================================================
-- Campfire Survivors - the ARSENAL: weapons a player can carry besides the gun.
--
--   1 Lightning        strikes random enemies near you, hurting a small area
--   2 Ember Ring       burns every enemy that comes close to you
--   3 Spinning Hatchets   hatchets circle around you
--   4 Molotov          a bottle at a random enemy; the flames burn for a while
--
-- They are picked up and levelled through the ordinary upgrade panel (see
-- stat_manager.lua: every panel holds one "arsenal" card). Each has
-- MAX_LEVEL levels and a player carries at most ARSENAL_SLOTS of them.
--
-- NETWORK. Nothing here is an entity: no bolt, hatchet, bottle or puddle is
-- ever spawned (a spawn is a script load + a Lua VM + a message per object).
--   * The HOST runs the whole simulation in SIM_STEP steps against ONE snapshot
--     of the monster positions, applies the damage itself and then sends at
--     most ONE message per step for everything that happened in it - every
--     strike, throw and hit of every player (fx_ALL). So the whole arsenal of
--     a full lobby costs at most 1 / SIM_STEP messages a second, however many
--     monsters it hits.
--   * A level change is one small message (state_ALL). The ring and the
--     hatchets are drawn by every peer from that state alone: they follow the
--     player locally and spin on the local clock, so they cost no traffic.
--   * Every peer draws the bolts, flights, puddles, numbers and sounds itself
--     from the fx_ALL payload. Hits carry their position, because the killing
--     blow's destroy reaches the clients before the batch does.
-- =============================================================================

local SIM_STEP = 0.1
MAX_LEVEL = 5
ARSENAL_SLOTS = 2          -- weapons a player can carry besides the gun
WEAPON_COUNT = 4

local KIND_LIGHTNING = 1
local KIND_AURA = 2
local KIND_ORBIT = 3
local KIND_MOLOTOV = 4

-- Every level's FULL stats (not deltas), so the tuning reads as one table per
-- weapon. Damage is multiplied by the player's Damage upgrade (see damage_mult).
local LIGHTNING = {
    { bolts = 1, damage = 24, radius = 18, cooldown = 5.0 },
    { bolts = 2, damage = 24, radius = 18, cooldown = 5.0 },
    { bolts = 2, damage = 28, radius = 21, cooldown = 5.0 },
    { bolts = 2, damage = 28, radius = 21, cooldown = 4.4 },
    { bolts = 2, damage = 34, radius = 24, cooldown = 4.4 },
}
local LIGHTNING_RANGE = 230         -- targets are picked among monsters this close

local AURA = {
    { radius = 44, damage = 12, interval = 1.0, knockback = 20 },
    { radius = 52, damage = 14, interval = 1.0, knockback = 20 },
    { radius = 52, damage = 20, interval = 0.9, knockback = 25 },
    { radius = 60, damage = 24, interval = 0.9, knockback = 25 },
    { radius = 60, damage = 30, interval = 0.8, knockback = 30 },
}

local ORBIT = {
    { count = 2, damage = 12, radius = 46, speed = 2.6 },
    { count = 3, damage = 12, radius = 46, speed = 2.6 },
    { count = 3, damage = 15, radius = 54, speed = 3.0 },
    { count = 4, damage = 15, radius = 54, speed = 3.0 },
    { count = 4, damage = 17, radius = 60, speed = 3.4 },
}
local ORBIT_HIT_COOLDOWN = 1.0      -- one player's hatchets hit a monster at most this often
local ORBIT_KNOCKBACK = 50
local BLADE_RADIUS = 9
local BLADE_SIZE = 18

local MOLOTOV = {
    { bottles = 1, damage = 4, radius = 24, duration = 2.5, cooldown = 4.0 },
    { bottles = 1, damage = 5, radius = 26, duration = 3.0, cooldown = 4.0 },
    { bottles = 2, damage = 5, radius = 26, duration = 3.0, cooldown = 4.0 },
    { bottles = 2, damage = 5, radius = 28, duration = 3.5, cooldown = 3.5 },
    { bottles = 3, damage = 5, radius = 28, duration = 3.5, cooldown = 3.5 },
}
local MOLOTOV_RANGE = 200
local MOLOTOV_FLIGHT = 0.45         -- seconds in the air; the flames start when it lands
local POOL_TICK = 0.5

local WEAPONS = {
    { key = "lightning", stats = LIGHTNING },
    { key = "aura",      stats = AURA },
    { key = "orbit",     stats = ORBIT },
    { key = "molotov",   stats = MOLOTOV },
}

-- Damage number colour per weapon (the gun's own numbers are red).
local KIND_COLOR = {
    Color(1.0, 0.95, 0.35, 1),   -- lightning: yellow
    Color(1.0, 0.55, 0.15, 1),   -- ember ring: orange
    Color(0.85, 0.9, 1.0, 1),    -- hatchets: steel
    Color(1.0, 0.4, 0.1, 1),     -- molotov: fire
}

local GUN_BASE_DAMAGE = 30           -- user.lua's default_player_stats.damage

-- =============================================================================
-- State. players[steam_id] exists on EVERY peer for every player who owns at
-- least one weapon; the host additionally keeps cooldowns and hit timers in it.
-- =============================================================================

local players = {}
local clock = 0
local sim_acc = 0

-- Local effects (every peer): bolts, flashes, bottles, puddles, numbers.
local fx = {}
local fx_counter = 0

-- Host only.
local pools = {}                     -- burning puddles: {x, y, r, dmg, owner, start, stop, next_tick}
local mons = {}                      -- this step's monster snapshot
local mon_info = {}                  -- name -> {r, boss, still}  (looked up once per monster)
local dead_now = {}                  -- monsters killed during this step
local out_events = {}                -- flat, EVENT_STRIDE values per event
local out_hits = {}                  -- flat, HIT_STRIDE values per hit
local EVENT_STRIDE = 7
local HIT_STRIDE = 6

-- Children of this singleton are placed in its LOCAL space. It is auto-created
-- at the origin, but if a map ever places it elsewhere every effect would be
-- drawn that far off (boss_manager.lua hit exactly this), so rebase.
local self_origin = nil
local function to_local(x, y)
    if not self_origin then
        self_origin = get_value("", name, "position") or Vector2(0, 0)
    end
    return Vector2(x - self_origin.x, y - self_origin.y)
end

local function new_player()
    return { lv = { 0, 0, 0, 0 }, dead = false, angle = 0, built_blades = 0, built_aura_r = 0,
        aura_pulse = 0, aura_t = 0, vis_dirty = true,
        cd = { 0, 0, 0, 0 }, hit_t = {} }
end

local function ensure(sid)
    local p = players[sid]
    if p == nil then
        p = new_player()
        players[sid] = p
    end
    return p
end

local function owned_count(p)
    local n = 0
    for i = 1, WEAPON_COUNT do
        if p.lv[i] > 0 then n = n + 1 end
    end
    return n
end

-- =============================================================================
-- Queries for the upgrade panel (stat_manager.lua). Static data, so clients
-- answer them locally too.
-- =============================================================================

function get_levels(sid)
    local p = players[sid]
    if p == nil then return { 0, 0, 0, 0 } end
    return { p.lv[1], p.lv[2], p.lv[3], p.lv[4] }
end

function card_info(weapon_id, level)
    local w = WEAPONS[math.floor(weapon_id or 0)]
    if w == nil then return nil end
    local lv = math.max(1, math.min(MAX_LEVEL, math.floor(level or 1)))
    return { name = "{wpn_" .. w.key .. "}", desc = "{wpn_" .. w.key .. "_lv" .. lv .. "}",
        icon = "icons/wpn_" .. w.key }
end

-- =============================================================================
-- Levels (host decides, everyone draws).
-- =============================================================================

local function broadcast_state(sid, target)
    local p = players[sid]
    if p == nil then return end
    local args = { sid, p.lv[1], p.lv[2], p.lv[3], p.lv[4], p.angle }
    if target then
        run_network_function(name, "state_ALL", args, target)
    else
        run_network_function(name, "state_ALL", args)
    end
end

-- HOST: one level of one weapon for one player. Validates the slot and level
-- limits itself, so a stale or forged pick can never exceed them.
function level_up(sid, weapon_id)
    if not IS_HOST then return false end
    local wid = math.floor(weapon_id or 0)
    if WEAPONS[wid] == nil then return false end
    local p = ensure(sid)
    local lv = p.lv[wid]
    if lv >= MAX_LEVEL then return false end
    if lv == 0 and owned_count(p) >= ARSENAL_SLOTS then return false end
    p.lv[wid] = lv + 1
    -- the first strike/throw comes soon after the pick, not a whole cooldown later
    p.cd[wid] = math.min(p.cd[wid], 0.6)
    broadcast_state(sid)
    run_function("-stats", "track_arsenal_level", { sid, wid, lv + 1 })
    return true
end

-- Every peer: the levels of one player (and, for the hatchets, the host's
-- angle so everyone's hatchets start where the host's are).
function state_ALL(sender_id, sid, l1, l2, l3, l4, angle)
    local p = ensure(sid)
    p.lv = { math.floor(l1 or 0), math.floor(l2 or 0), math.floor(l3 or 0), math.floor(l4 or 0) }
    if not IS_HOST then
        p.angle = angle or 0
    end
    p.vis_dirty = true
end

-- user.lua tells us when a player goes down or gets back up (on every peer,
-- from update_player_state_ALL), so the ring and the hatchets disappear with
-- them and the host stops simulating their weapons.
function set_player_dead(sid, is_dead)
    local p = players[sid]
    if p == nil then return end
    local d = is_dead == true
    if p.dead ~= d then
        p.dead = d
        p.vis_dirty = true
    end
end

-- HOST: the run is over (game over / restart) - everybody back to just the gun.
function reset_all()
    if not IS_HOST then return end
    pools = {}
    run_network_function(name, "reset_ALL", {})
end

local function remove_player_visuals(sid, p)
    if not entity_exists(sid) then return end
    for i = 1, p.built_blades do
        if entity_exists("wpn_blade" .. i, sid) then destroy(sid, "wpn_blade" .. i) end
    end
    if entity_exists("wpn_aura", sid) then destroy(sid, "wpn_aura") end
    p.built_blades = 0
    p.built_aura_r = 0
end

local function clear_fx()
    for _, f in ipairs(fx) do
        for _, n in ipairs(f.nodes) do
            if entity_exists(n, name) then destroy(name, n) end
        end
    end
    fx = {}
end

function reset_ALL(sender_id)
    for sid, p in pairs(players) do
        remove_player_visuals(sid, p)
    end
    players = {}
    clear_fx()
end

function _on_user_initialized(steam_id, nickname)
    if not IS_HOST or steam_id == LOCAL_STEAM_ID then return end
    for sid, _ in pairs(players) do
        broadcast_state(sid, steam_id)
    end
end

function _on_user_disconnected(steam_id, nickname)
    players[steam_id] = nil       -- its images were children of the player entity
end

-- =============================================================================
-- Host simulation.
-- =============================================================================

local function snapshot()
    mons = {}
    dead_now = {}
    local seen = {}
    for _, n in ipairs(get_entity_names_by_tag("monster")) do
        local info = mon_info[n]
        if info == nil then
            -- read once per monster: its body radius, whether it is the boss,
            -- whether it stands still (bandits never re-aim, so a shove would
            -- drift them forever - they are not knocked back)
            if has_tag(n, "boss") then
                info = { r = 32, boss = true, still = true }
            else
                local sz = tonumber(get_value("", n, "size")) or 36
                local sp = tonumber(get_value("", n, "speed")) or 1
                info = { r = sz / 2, boss = false, still = sp <= 0 }
            end
            mon_info[n] = info
        end
        seen[n] = true
        local pos = get_value("", n, "position")
        if pos then
            mons[#mons + 1] = { n = n, x = pos.x, y = pos.y, r = info.r, boss = info.boss, still = info.still }
        end
    end
    for n, _ in pairs(mon_info) do
        if not seen[n] then mon_info[n] = nil end
    end
end

local function push_event(kind, a, b, c, d, e, f)
    local o = out_events
    o[#o + 1] = kind
    o[#o + 1] = a or 0
    o[#o + 1] = b or 0
    o[#o + 1] = c or 0
    o[#o + 1] = d or 0
    o[#o + 1] = e or 0
    o[#o + 1] = f or 0
end

-- Apply one hit. Monsters skip their own per-hit broadcast (take_weapon_damage)
-- and land in this step's batch instead; the boss keeps its own path (bar sync,
-- phases) - it is one entity, so that stays cheap.
local function hit(sid, m, amount, knockback, angle, kind)
    if dead_now[m.n] then return end
    if not entity_exists(m.n) then
        dead_now[m.n] = true
        return
    end
    if m.boss then
        run_function(m.n, "take_damage", { amount, 0, angle, sid })
        return
    end
    local res = run_function(m.n, "take_weapon_damage", { amount, m.still and 0 or knockback, angle, sid })
    if type(res) ~= "table" then return end
    local died = res.k == true
    if died then dead_now[m.n] = true end
    local o = out_hits
    o[#o + 1] = m.n
    o[#o + 1] = math.floor(res.d or 0)
    o[#o + 1] = died and 1 or 0
    o[#o + 1] = math.floor(m.x)
    o[#o + 1] = math.floor(m.y)
    o[#o + 1] = kind
end

local function damage_mult(sid)
    local d = tonumber(get_value("", sid, "damage")) or GUN_BASE_DAMAGE
    return d / GUN_BASE_DAMAGE
end

local function in_range(m, x, y, r)
    local dx, dy = m.x - x, m.y - y
    return dx * dx + dy * dy <= r * r
end

-- Up to `count` different monsters within `range` of (x, y), at random.
local function random_targets(x, y, range, count)
    local cand = {}
    for _, m in ipairs(mons) do
        if not dead_now[m.n] and in_range(m, x, y, range) then
            cand[#cand + 1] = m
        end
    end
    local out = {}
    for i = 1, count do
        if #cand == 0 then break end
        local k = math.random(1, #cand)
        out[#out + 1] = cand[k]
        -- distinct targets while there are enough; after that, double up
        if #cand > 1 then table.remove(cand, k) end
    end
    return out
end

local function sim_lightning(sid, p, px, py, mult)
    local st = LIGHTNING[p.lv[KIND_LIGHTNING]]
    local targets = random_targets(px, py, LIGHTNING_RANGE, st.bolts)
    if #targets == 0 then return false end
    for _, t in ipairs(targets) do
        local x, y = t.x, t.y
        push_event(KIND_LIGHTNING, x, y, st.radius)
        for _, m in ipairs(mons) do
            if in_range(m, x, y, st.radius + m.r * 0.5) then
                hit(sid, m, st.damage * mult, 0, math.atan(m.y - y, m.x - x), KIND_LIGHTNING)
            end
        end
    end
    return true
end

local function sim_molotov(sid, p, px, py, mult)
    local st = MOLOTOV[p.lv[KIND_MOLOTOV]]
    local targets = random_targets(px, py, MOLOTOV_RANGE, st.bottles)
    if #targets == 0 then return false end
    for i, t in ipairs(targets) do
        -- a little scatter, so three bottles at one monster do not stack exactly
        local x = t.x + (i > 1 and math.random(-14, 14) or 0)
        local y = t.y + (i > 1 and math.random(-14, 14) or 0)
        push_event(KIND_MOLOTOV, px, py, x, y, st.radius, st.duration)
        local start = clock + MOLOTOV_FLIGHT
        pools[#pools + 1] = { x = x, y = y, r = st.radius, dmg = st.damage * mult, owner = sid,
            start = start, stop = start + st.duration, next_tick = start }
    end
    return true
end

local function sim_aura(sid, p, px, py, mult)
    local st = AURA[p.lv[KIND_AURA]]
    for _, m in ipairs(mons) do
        if in_range(m, px, py, st.radius + m.r) then
            hit(sid, m, st.damage * mult, st.knockback, math.atan(m.y - py, m.x - px), KIND_AURA)
        end
    end
end

local function sim_orbit(sid, p, px, py, mult)
    local st = ORBIT[p.lv[KIND_ORBIT]]
    local reach = st.radius + BLADE_RADIUS + 40
    for _, m in ipairs(mons) do
        if not dead_now[m.n] and in_range(m, px, py, reach) and clock >= (p.hit_t[m.n] or 0) then
            for i = 1, st.count do
                local a = p.angle + (i - 1) * (2 * math.pi / st.count)
                local bx, by = px + math.cos(a) * st.radius, py + math.sin(a) * st.radius
                if in_range(m, bx, by, BLADE_RADIUS + m.r) then
                    p.hit_t[m.n] = clock + ORBIT_HIT_COOLDOWN
                    hit(sid, m, st.damage * mult, ORBIT_KNOCKBACK, math.atan(m.y - py, m.x - px), KIND_ORBIT)
                    break
                end
            end
        end
    end
end

local function sim_pools()
    local keep = {}
    for _, pool in ipairs(pools) do
        if clock < pool.stop then
            keep[#keep + 1] = pool
            if clock >= pool.next_tick then
                pool.next_tick = pool.next_tick + POOL_TICK
                for _, m in ipairs(mons) do
                    if in_range(m, pool.x, pool.y, pool.r + m.r * 0.5) then
                        hit(pool.owner, m, pool.dmg, 0, math.atan(m.y - pool.y, m.x - pool.x), KIND_MOLOTOV)
                    end
                end
            end
        end
    end
    pools = keep
end

local function sim_step(dt)
    -- anything to do at all? (the common case before anyone picks a weapon)
    local any = #pools > 0
    if not any then
        for _, p in pairs(players) do
            if not p.dead and owned_count(p) > 0 then any = true break end
        end
    end
    if not any then return end

    snapshot()
    sim_pools()
    for sid, p in pairs(players) do
        for i = 1, WEAPON_COUNT do
            if p.cd[i] > 0 then p.cd[i] = p.cd[i] - dt end
        end
        if not p.dead and owned_count(p) > 0 and #mons > 0 and entity_exists(sid) then
            local pos = get_value("", sid, "position")
            if pos then
                local mult = damage_mult(sid)
                if p.lv[KIND_LIGHTNING] > 0 and p.cd[KIND_LIGHTNING] <= 0 then
                    p.cd[KIND_LIGHTNING] = sim_lightning(sid, p, pos.x, pos.y, mult)
                        and LIGHTNING[p.lv[KIND_LIGHTNING]].cooldown or 0.3
                end
                if p.lv[KIND_MOLOTOV] > 0 and p.cd[KIND_MOLOTOV] <= 0 then
                    p.cd[KIND_MOLOTOV] = sim_molotov(sid, p, pos.x, pos.y, mult)
                        and MOLOTOV[p.lv[KIND_MOLOTOV]].cooldown or 0.3
                end
                if p.lv[KIND_AURA] > 0 and p.cd[KIND_AURA] <= 0 then
                    p.cd[KIND_AURA] = AURA[p.lv[KIND_AURA]].interval
                    sim_aura(sid, p, pos.x, pos.y, mult)
                end
                if p.lv[KIND_ORBIT] > 0 then
                    sim_orbit(sid, p, pos.x, pos.y, mult)
                end
            end
        end
        -- forget hit timers of monsters that are gone
        for n, _ in pairs(p.hit_t) do
            if mon_info[n] == nil then p.hit_t[n] = nil end
        end
    end

    if #out_events > 0 or #out_hits > 0 then
        run_network_function(name, "fx_ALL", { out_events, out_hits })
        out_events = {}
        out_hits = {}
    end
end

-- =============================================================================
-- Effects (every peer, local only).
-- =============================================================================

local FX_LABEL_SECONDS = 0.6
-- The green hit puff every monster hit shows (monster_generation.lua) is made for
-- one bullet at a time; burns tick on every monster in the ring or the flames, so
-- only the blows (bolts, hatchets) get it, and only a few per batch.
local MAX_PARTICLES_PER_BATCH = 4
local sparks_ready = false

local function add_fx(f)
    fx[#fx + 1] = f
    return f
end

local function fx_name(prefix)
    fx_counter = fx_counter + 1
    return prefix .. fx_counter
end

local function ensure_sparks()
    if sparks_ready then return end
    sparks_ready = true
    create_particle({ particle_id = "cs_zap_sparks", texture_path = "white", lifetime = 0.35,
        amount = 10, explosiveness = 1.0, one_shot = true, spread = 180,
        initial_velocity_min = 40, initial_velocity_max = 110,
        scale_amount_min = 0.25, scale_amount_max = 0.5, alpha_curve = { 1.0, 0.0 },
        color = Color(1.0, 0.95, 0.5, 1), z_index = 6 })
    create_particle({ particle_id = "cs_fire_burst", texture_path = "white", lifetime = 0.5,
        amount = 12, explosiveness = 0.9, one_shot = true, spread = 180,
        initial_velocity_min = 25, initial_velocity_max = 80, gravity = { x = 0, y = -60 },
        scale_amount_min = 0.3, scale_amount_max = 0.6, alpha_curve = { 1.0, 0.0 },
        color = Color(1.0, 0.55, 0.15, 1), z_index = 6 })
end

local function show_lightning(x, y, radius)
    ensure_sparks()
    -- the bolt's bottom tip sits on the strike point; three drawings, picked at random
    local bolt = set_image({ parent_name = name, name = fx_name("wbolt"),
        image_path = "lightning" .. math.random(1, 3),
        position = to_local(x, y - 50), scale = Vector2(36, 104), z_index = 5 })
    local flash = set_image({ parent_name = name, name = fx_name("wzap"), image_path = "zap_ring",
        position = to_local(x, y), scale = Vector2(radius * 2 + 8, radius * 2 + 8), z_index = 1,
        modulate = Color(1, 1, 1, 0.9) })
    add_fx({ kind = "bolt", nodes = { bolt, flash }, t = 0, dur = 0.32 })
    start_particle({ particle_id = "cs_zap_sparks", position = Vector2(x, y) })
    set_audio({ no_multiple_tag = "wzap" .. (fx_counter % 3), stream_path = "thunder",
        position = Vector2(x, y), is_2d = true, max_distance = 520, volume = -7, random_pitch = 0.12 })
end

local function show_molotov(fx_, fy, tx, ty, radius, duration)
    local bottle = set_image({ parent_name = name, name = fx_name("wbtl"), image_path = "molotov_bottle",
        position = to_local(fx_, fy), scale = Vector2(12, 12), z_index = 5 })
    add_fx({ kind = "bottle", nodes = { bottle }, t = 0, dur = MOLOTOV_FLIGHT,
        fx_ = fx_, fy = fy, tx = tx, ty = ty, radius = radius, duration = duration })
end

local function start_pool(x, y, radius, duration)
    ensure_sparks()
    local size = radius * 2 + 6
    local img = set_image({ parent_name = name, name = fx_name("wpool"), image_path = "fire_pool1",
        position = to_local(x, y), scale = Vector2(size, size), z_index = 0 })
    add_fx({ kind = "pool", nodes = { img }, t = 0, dur = duration, frame = 1, frame_t = 0 })
    start_particle({ particle_id = "cs_fire_burst", position = Vector2(x, y) })
    set_audio({ no_multiple_tag = "wfire" .. (fx_counter % 3), stream_path = "molotov",
        position = Vector2(x, y), is_2d = true, max_distance = 460, volume = -8, random_pitch = 0.1 })
end

local function show_number(x, y, amount, kind)
    local lbl = set_label({ parent_name = name, name = fx_name("wnum"),
        text = "-" .. tostring(amount), font_color = KIND_COLOR[kind] or Color(1, 1, 1, 1),
        outline_color = Color(0, 0, 0, 1), outline_size = 2, font_size = 10,
        position = to_local(x - 32, y - 22), size = Vector2(64, 16), z_index = 10 })
    add_fx({ kind = "label", nodes = { lbl }, t = 0, dur = FX_LABEL_SECONDS })
end

function fx_ALL(sender_id, events, hits)
    if type(events) == "table" then
        local i = 1
        while i + EVENT_STRIDE - 1 <= #events do
            local kind = math.floor(events[i])
            if kind == KIND_LIGHTNING then
                show_lightning(events[i + 1], events[i + 2], events[i + 3])
            elseif kind == KIND_MOLOTOV then
                show_molotov(events[i + 1], events[i + 2], events[i + 3], events[i + 4],
                    events[i + 5], events[i + 6])
            end
            i = i + EVENT_STRIDE
        end
    end
    if type(hits) ~= "table" then return end
    local i = 1
    local particles = 0
    local first_hit, first_death = nil, nil
    while i + HIT_STRIDE - 1 <= #hits do
        local mname = hits[i]
        local amount = math.floor(hits[i + 1])
        local died = hits[i + 2] == 1
        local x, y = hits[i + 3], hits[i + 4]
        local kind = math.floor(hits[i + 5])
        -- the flash/wobble every monster gets - for the blows only (bolts, hatchets): burns tick on every
        -- monster in the ring or the flames, and a white flash on each tick turns the crowd into white blobs
        if not died and (kind == KIND_LIGHTNING or kind == KIND_ORBIT) and entity_exists(mname) then
            local img = get_value("", mname, "image_name")
            if img then
                run_function("-hfx", "play_hit", { mname, img, "circle", (math.random() < 0.5) and -1 or 1 })
            end
        end
        if amount > 0 then show_number(x, y, amount, kind) end
        if (kind == KIND_LIGHTNING or kind == KIND_ORBIT) and particles < MAX_PARTICLES_PER_BATCH then
            particles = particles + 1
            run_function("-mg", "spawn_damage_particle", { Vector2(x, y) })
        end
        first_hit = first_hit or Vector2(x, y)
        if died then first_death = first_death or Vector2(x, y) end
        i = i + HIT_STRIDE
    end
    -- ONE impact (and at most one death) sound per batch: an area weapon hitting
    -- twenty monsters must not stack twenty voices
    if first_hit then
        set_audio({ no_multiple_tag = "wimp", stream_path = "bullet_impact", position = first_hit,
            is_2d = true, max_distance = 420, volume = -11, random_pitch = 0.15 })
    end
    if first_death then
        set_audio({ no_multiple_tag = "wdie", stream_path = "npc_died", position = first_death,
            is_2d = true, max_distance = 420, volume = -9, random_pitch = 0.12 })
    end
end

local function update_fx(delta)
    if #fx == 0 then return end
    local keep = {}
    for _, f in ipairs(fx) do
        f.t = f.t + delta
        local alive = f.t < f.dur
        if f.kind == "bolt" then
            if alive then
                -- hold, then fade; the ground flash grows a little as it fades
                local a = f.t < 0.1 and 1 or math.max(0, 1 - (f.t - 0.1) / (f.dur - 0.1))
                if entity_exists(f.nodes[1], name) then
                    set_image({ parent_name = name, name = f.nodes[1], modulate = Color(1, 1, 1, a) })
                end
                if entity_exists(f.nodes[2], name) then
                    set_image({ parent_name = name, name = f.nodes[2], modulate = Color(1, 1, 1, a * 0.9) })
                end
            end
        elseif f.kind == "bottle" then
            local u = math.min(f.t / f.dur, 1)
            local x = f.fx_ + (f.tx - f.fx_) * u
            local y = f.fy + (f.ty - f.fy) * u - 36 * 4 * u * (1 - u)   -- a lob, not a laser
            if entity_exists(f.nodes[1], name) then
                set_image({ parent_name = name, name = f.nodes[1], position = to_local(x, y), rotation = f.t * 14 })
            end
            if not alive then
                start_pool(f.tx, f.ty, f.radius, f.duration)
            end
        elseif f.kind == "pool" then
            if alive then
                f.frame_t = f.frame_t + delta
                local cfg = nil
                if f.frame_t >= 0.12 then
                    f.frame_t = 0
                    f.frame = (f.frame % 3) + 1
                    cfg = { parent_name = name, name = f.nodes[1], image_path = "fire_pool" .. f.frame }
                end
                local left = f.dur - f.t
                if left < 0.4 then
                    cfg = cfg or { parent_name = name, name = f.nodes[1] }
                    cfg.modulate = Color(1, 1, 1, left / 0.4)
                end
                if cfg and entity_exists(f.nodes[1], name) then set_image(cfg) end
            end
        end
        if alive then
            keep[#keep + 1] = f
        else
            for _, n in ipairs(f.nodes) do
                if entity_exists(n, name) then destroy(name, n) end
            end
        end
    end
    fx = keep
end

-- The ring and the hatchets: children of the player entity, so they follow it
-- for free; only the spin and the ring's pulse are touched per frame.
local function build_visuals(sid, p)
    p.vis_dirty = false
    if not entity_exists(sid) then
        p.vis_dirty = true          -- the player entity is not here yet; try again later
        return
    end
    local show = not p.dead
    -- hatchets
    local want = (show and p.lv[KIND_ORBIT] > 0) and ORBIT[p.lv[KIND_ORBIT]].count or 0
    for i = 1, math.max(want, p.built_blades) do
        local bname = "wpn_blade" .. i
        if i <= want then
            set_image({ parent_name = sid, name = bname, image_path = "hatchet",
                scale = Vector2(BLADE_SIZE, BLADE_SIZE), z_index = 3 })
        elseif entity_exists(bname, sid) then
            destroy(sid, bname)
        end
    end
    p.built_blades = want
    -- ember ring
    local r = (show and p.lv[KIND_AURA] > 0) and AURA[p.lv[KIND_AURA]].radius or 0
    if r > 0 then
        set_image({ parent_name = sid, name = "wpn_aura", image_path = "aura_ring",
            scale = Vector2(r * 2 + 8, r * 2 + 8), z_index = 0, modulate = Color(1, 1, 1, 0.55) })
    elseif entity_exists("wpn_aura", sid) then
        destroy(sid, "wpn_aura")
    end
    p.built_aura_r = r
end

local function update_player_visuals(sid, p, delta)
    if p.vis_dirty then build_visuals(sid, p) end
    if p.lv[KIND_ORBIT] > 0 then
        local st = ORBIT[p.lv[KIND_ORBIT]]
        p.angle = (p.angle + st.speed * delta) % (2 * math.pi)
        for i = 1, p.built_blades do
            local a = p.angle + (i - 1) * (2 * math.pi / st.count)
            set_image({ parent_name = sid, name = "wpn_blade" .. i,
                position = Vector2(math.cos(a) * st.radius, math.sin(a) * st.radius),
                rotation = clock * 13 + i })
        end
    end
    if p.built_aura_r > 0 then
        -- a slow turn, and a glow on every burn tick (local clock, same interval)
        local st = AURA[p.lv[KIND_AURA]]
        p.aura_t = p.aura_t + delta
        if p.aura_t >= st.interval then
            p.aura_t = p.aura_t - st.interval
            p.aura_pulse = 1
        end
        p.aura_pulse = math.max(0, p.aura_pulse - delta * 4)
        set_image({ parent_name = sid, name = "wpn_aura", rotation = clock * 0.6,
            modulate = Color(1, 1, 1, 0.45 + 0.4 * p.aura_pulse) })
    end
end

function _process(delta, inputs)
    clock = clock + delta
    for sid, p in pairs(players) do
        update_player_visuals(sid, p, delta)
    end
    update_fx(delta)
    if IS_HOST then
        sim_acc = sim_acc + delta
        local steps = 0
        while sim_acc >= SIM_STEP and steps < 3 do
            sim_acc = sim_acc - SIM_STEP
            steps = steps + 1
            sim_step(SIM_STEP)
        end
        if sim_acc > SIM_STEP then sim_acc = 0 end   -- a long hitch: skip, do not spiral
    end
end

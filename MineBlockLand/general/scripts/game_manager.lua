singleton_name = "gm"
network_mode = 1

-- =============================================================================
-- MineBlockLand - game manager (time, enemies, boss, save, commands).
--
-- HOST is the single authority: it owns the clock, decides day/night, spawns
-- enemies, applies terrain mutations and persists everything. Peers mirror the
-- clock locally between the (rare) sync messages - the only time traffic is
-- one message at dusk and one at dawn, so there is no per-frame time sync.
-- =============================================================================

-- Tile kind ids (each entity has its own Lua env; must match worldgen.lua).
local K_GRASS, K_SAND, K_TREE, K_FARM, K_FARM_SEEDED, K_FARM_GROWN, K_STONE = 1, 2, 3, 4, 5, 6, 9

-- Day/night: 5 real minutes of day + 2.5 of night; clock shows 06:00 -> 06:00.
local DAY_SECONDS = 300
local CYCLE_SECONDS = 450
local DAWN_HOUR = 6
local BOSS_DAY = 7

local SAVE_PATH = "server/world_save.json"
local DEFAULT_SEED = 784242144
local SEED_PANEL = "_mbl_seed_setup"
local AUTOSAVE_SECONDS = 60
local GROW_SECONDS = 150          -- seeded farmland -> harvestable crop
local ZOMBIE_WAVE_SECONDS = 25
local ZOMBIE_SPAWN_DIST_MIN = 260 -- just outside the player's view
local ZOMBIE_SPAWN_DIST_MAX = 340
local SUN_START_ANGLE = 100       -- shadow angle sweep across the day
local SUN_END_ANGLE = 260

local NIGHT_BG = Color(24 / 255, 20 / 255, 37 / 255, 1)      -- Ink
local DAY_BG = Color(0.3, 0.3, 0.3, 1)
-- Vignette right at dusk (fade target) vs. at the darkest point of the night
-- (just before dawn) - the night keeps creeping in instead of sitting flat at
-- one look for its whole ~2.5 minutes.
local NIGHT_VIGNETTE = { visible = true, strength = 1.3, radius = 0.6,
    smoothness = 0.5, color = Color(0, 0, 0, 1) }
local NIGHT_VIGNETTE_PEAK_STRENGTH = 1.7
local NIGHT_VIGNETTE_PEAK_RADIUS = 0.4
local PHASE_FADE_SECONDS = 3.0   -- dusk/dawn creep in - vignette AND shadows, never a hard cut
local PHASE_FADE_STEP = 0.05

local phase_fade_elapsed = -1       -- < 0 = not fading
local shadow_rgb = nil              -- captured once from the map's own shadow_color (rgb only)
local shadow_alpha_full = 1.0       -- ...and its full alpha, faded to/from 0

-- Enemy archetypes (night zombies scale with the day; dungeon guards are
-- fixed-strength elites so the dungeon is dangerous from day one).
local ENEMY_TYPES = {
    zombie = { image = "items/15x15_zombie", size = 16, hp = 30, dmg = 10, speed = 12,
        windup = 0.55, cooldown = 1.4, reach = 26, tint = Color(1, 1, 1, 1) },
    brute = { image = "items/15x15_zombie", size = 24, hp = 110, dmg = 24, speed = 9,
        windup = 0.8, cooldown = 2.0, reach = 30, tint = Color(0.55, 0.9, 0.55, 1) },
    witch = { image = "items/10x10_witch", size = 18, hp = 70, dmg = 16, speed = 8,
        windup = 0.6, cooldown = 1.6, reach = 24, ranged = true, shoot_cd = 2.8,
        tint = Color(1, 1, 1, 1) },
}
local HP_SCALE_PER_DAY = 0.25
local DMG_SCALE_PER_DAY = 0.15
local ZOMBIES_PER_PLAYER_BASE = 2
local ZOMBIES_PER_PLAYER_MAX = 8
local BOSS_HP_BASE = 1500
local BOSS_HP_PER_EXTRA_PLAYER = 0.5

-- Synced game state (also snapshotted to late joiners via network_mode = 1).
seed_value = 0
day = 1
t = 0
is_night = false
friendly_fire = false
boss_defeated = false
boss_active = false

-- Host-only state.
local stats = {}          -- steam_id -> {trees, stones, kills, dmg_dealt, dmg_taken, deaths, crafts}
local pending_growth = {} -- "x,y" -> absolute game second when the crop matures
local breaks = {}         -- "x,y" -> remaining hit points of the tree/rock
local dungeon_done = {}   -- poi id -> true (chest looted / guard slain)
local saved_positions = {}
local boss_entity = ""
local typed_seed = tostring(DEFAULT_SEED) -- host-only seed-setup panel state

-- Local (every peer).
local nav_icon_name = ""
local synced = IS_HOST

local STAT_KEYS = { "trees", "stones", "kills", "dmg_dealt", "dmg_taken", "deaths", "crafts" }

local function game_time()
    return (day - 1) * CYCLE_SECONDS + t
end

-- Numbers that crossed the Lua<->GDScript boundary come back as floats;
-- floor them so "3,5" and "3.0,5.0" never coexist as different keys.
local function key_of(x, y)
    return math.floor(x) .. "," .. math.floor(y)
end

-- 0 right at dawn, 1 at the last second before dusk.
local function day_progress()
    return math.min(math.max(t / DAY_SECONDS, 0), 1)
end

-- 0 right at dusk, 1 at the last second before dawn.
local function night_progress()
    return math.min(math.max((t - DAY_SECONDS) / (CYCLE_SECONDS - DAY_SECONDS), 0), 1)
end

-- Reads the map's own configured shadow colour once, so the fade respects
-- whatever the editor set instead of hardcoding the engine default.
local function capture_shadow_base()
    if shadow_rgb then return end
    local c = get_shadow_settings().shadow_color
    shadow_rgb = Color(c.r, c.g, c.b, 1)
    shadow_alpha_full = c.a
end

-- The night's vignette config for right now: strength/radius interpolated
-- from NIGHT_VIGNETTE (dusk) toward the *_PEAK values (just before dawn).
function night_vignette_now()
    local p = night_progress()
    local cfg = {}
    for key, value in pairs(NIGHT_VIGNETTE) do cfg[key] = value end
    cfg.strength = NIGHT_VIGNETTE.strength + (NIGHT_VIGNETTE_PEAK_STRENGTH - NIGHT_VIGNETTE.strength) * p
    cfg.radius = NIGHT_VIGNETTE.radius + (NIGHT_VIGNETTE_PEAK_RADIUS - NIGHT_VIGNETTE.radius) * p
    return cfg
end

-- =============================================================================
-- Boot / persistence.
-- =============================================================================

function host_boot()
    if not IS_HOST then return end
    set_minimap(true) -- allow every peer to render its own island map (G key)
    local data = load_json(SAVE_PATH)
    if data and data.seed then
        seed_value = math.floor(data.seed)
        day = data.day or 1
        t = data.t or 0
        is_night = data.is_night or false
        friendly_fire = data.friendly_fire or false
        boss_defeated = data.boss_defeated or false
        pending_growth = data.growth or {}
        stats = data.stats or {}
        dungeon_done = data.dungeon_done or {}
        saved_positions = data.positions or {}
        run_function("-gen", "set_seed", { seed_value })
        run_function("-gen", "set_all_muts", { data.muts or {} })
        run_function("-inv", "load_save_data", { data.inv or {} })
        announce("World restored - day " .. day .. ". Welcome back!")
        finish_boot()
    else
        -- No save yet: let the host pick the seed (default/random/typed)
        -- before the island is generated - see show_seed_setup() below.
        show_seed_setup()
    end
end

-- Finishes booting once a seed is known (either restored from disk or just
-- chosen by the host in the seed-setup panel).
function finish_boot()
    spawn_dungeon_population()
    apply_phase_visuals()
    refresh_clock()
    -- Anyone already in (normally just the host player): restore their spot
    -- and push them their saved inventory.
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        local pos = saved_positions[user_name]
        local target = pos and Vector2(pos.x, pos.y) or map_to_local(Vector2(0, 0))
        run_function(user_name, "host_respawn_at", { target.x, target.y })
        run_function("-inv", "host_sync_all_to", { user_name })
    end
    save_world()
end

-- =============================================================================
-- First-boot seed setup (host only, local panel - shown only when there is no
-- save yet; a restored world never asks). No close button: the host must
-- actually pick a seed before the island generates and anyone can play.
-- =============================================================================

local function begin_world(new_seed)
    if is_panel_exists(SEED_PANEL) then close_panel(SEED_PANEL) end
    seed_value = math.floor(new_seed)
    run_function("-gen", "set_seed", { seed_value })
    announce("A fresh world awakens (seed " .. seed_value
        .. "). Chop, mine, survive the nights - the 7th night brings a monster.")
    finish_boot()
end

function on_seed_input(args)
    -- The input's value is delivered keyed by its label ("Seed").
    typed_seed = tostring(args["Seed"] or "")
end

function on_use_seed(args)
    local s = tonumber(typed_seed)
    if not s or math.floor(s) == 0 then s = DEFAULT_SEED end
    begin_world(s)
end

function on_random_seed(args)
    begin_world(get_os_time_unix() % 1000000007)
end

function show_seed_setup()
    if is_panel_exists(SEED_PANEL) then return end
    create_panel({ name = SEED_PANEL, title = "MineBlockLand - Host",
        text = "Pick the world seed (same seed always builds the same island).\nDefault: "
            .. DEFAULT_SEED,
        set_time = false, close = false, resizable = false, minimum_size = Vector2(400, 220) })
    add_input_to_panel(SEED_PANEL, { entity_name = name, function_name = "on_seed_input",
        text = "Seed", default_value = typed_seed })
    add_button_to_panel(SEED_PANEL, { entity_name = name, function_name = "on_use_seed",
        text = "Use This Seed", color = Color(0.3, 0.55, 0.35) })
    add_button_to_panel(SEED_PANEL, { entity_name = name, function_name = "on_random_seed",
        text = "Random Seed", color = Color(0.35, 0.45, 0.6) })
end

function save_world()
    if not IS_HOST then return end
    saved_positions = saved_positions or {}
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        local pos = get_value("", user_name, "position")
        if pos then saved_positions[user_name] = { x = pos.x, y = pos.y } end
    end
    save_json(SAVE_PATH, {
        seed = seed_value, day = day, t = t, is_night = is_night,
        friendly_fire = friendly_fire, boss_defeated = boss_defeated,
        muts = run_function("-gen", "get_all_muts"),
        growth = pending_growth, stats = stats, dungeon_done = dungeon_done,
        inv = run_function("-inv", "get_save_data"),
        positions = saved_positions,
    })
end

-- The engine spawns singletons in an unspecified order, so -gm waits a beat
-- before touching -gen / -inv.
start_timer({ timer_id = "gm_boot", entity_name = name, function_name = "host_boot",
    wait_time = 0.5, duration = 0.5 })
start_timer({ timer_id = "gm_tick", entity_name = name, function_name = "tick", wait_time = 1.0 })

-- Spawn always shows on the minimap (a fixed spot, not an entity - every peer
-- sets this up locally, same as the player dots in user.lua).
set_minimap_target({ name = "spawn", world_position = map_to_local(Vector2(0, 0)),
    text = "Spawn", icon_size = Vector2(8, 8), color = Color(1, 1, 1, 1) })

if IS_HOST then
    start_timer({ timer_id = "gm_autosave", entity_name = name, function_name = "save_world",
        wait_time = AUTOSAVE_SECONDS })
end

-- =============================================================================
-- Late joiners get the whole world in a handful of messages.
-- =============================================================================

function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end
    if seed_value == 0 then return end -- host boot pending; host_boot syncs itself
    run_network_function(name, "state_ALL",
        { seed_value, day, t, is_night, friendly_fire, boss_defeated }, steam_id)
    run_network_function(name, "muts_ALL",
        { run_function("-gen", "get_all_muts") }, steam_id)
    run_function("-inv", "host_sync_all_to", { steam_id })
    if boss_active and boss_entity ~= "" then
        run_network_function(name, "boss_nav_ALL", { boss_entity }, steam_id)
    end
    -- Returning players continue where they logged off; new ones start at spawn.
    local pos = saved_positions[steam_id]
    local target = pos and Vector2(pos.x, pos.y) or map_to_local(Vector2(0, 0))
    run_function(steam_id, "host_respawn_at", { target.x, target.y }, 0.3)
end

function state_ALL(sender_id, new_seed, new_day, new_t, night, ff, bossed)
    seed_value = new_seed
    day = new_day
    t = new_t
    is_night = night
    friendly_fire = ff
    boss_defeated = bossed
    run_function("-gen", "set_seed", { seed_value })
    synced = true
    apply_phase_visuals()
    refresh_clock()
end

function muts_ALL(sender_id, muts)
    run_function("-gen", "set_all_muts", { muts })
end

function _on_user_disconnected(steam_id, nickname)
    if IS_HOST then save_world() end
end

-- =============================================================================
-- Clock: every peer ticks locally; the host corrects everyone at dusk/dawn.
-- =============================================================================

function tick()
    if not synced then return end
    t = t + 1
    if IS_HOST then
        if not is_night and t >= DAY_SECONDS then
            begin_night()
        elseif t >= CYCLE_SECONDS then
            begin_day()
        end
        check_growth()
        if is_night and t % ZOMBIE_WAVE_SECONDS == 0 then
            spawn_zombie_wave()
        end
    else
        t = math.min(t, CYCLE_SECONDS) -- never self-transition; wait for the host
    end
    refresh_clock()
    -- The sun crawls across the sky: nudge the shadow angle a little each tick.
    if not is_night and t % 3 == 0 then
        set_shadow({ shadow_angle = SUN_START_ANGLE + (SUN_END_ANGLE - SUN_START_ANGLE) * day_progress() })
    end
    -- The vignette keeps creeping in through the night instead of sitting at
    -- one flat look for its whole length (skipped while the dusk fade-in
    -- itself is still running - phase_fade_step already owns the vignette then).
    if is_night and phase_fade_elapsed < 0 and t % 3 == 0 then
        set_vignette(night_vignette_now())
    end
end

function refresh_clock()
    local hour_f = (DAWN_HOUR + t * (24.0 / CYCLE_SECONDS)) % 24
    local hour = math.floor(hour_f)
    local minute = math.floor((hour_f - hour) * 60)
    local suffix = is_night and "  NIGHT" or ""
    set_label({ name = "_mbl_clock",
        text = string.format("Day %d   %02d:%02d%s", day, hour, minute, suffix) })
end

function begin_night()
    is_night = true
    t = DAY_SECONDS
    run_network_function(name, "phase_ALL", { day, t, true })
    if day >= BOSS_DAY and not boss_defeated and not boss_active then
        spawn_boss()
    end
    save_world()
end

function begin_day()
    is_night = false
    t = 0
    day = day + 1
    run_network_function(name, "phase_ALL", { day, t, false })
    -- Sunrise burns the horde away (dungeon guards live underground rules).
    run_function_by_tag("night_npc", "host_burn")
    save_world()
end

function phase_ALL(sender_id, new_day, new_t, night)
    day = new_day
    t = new_t
    is_night = night
    -- phase_ALL only ever fires for a LIVE dusk/dawn transition (both
    -- directions), so it always fades - "true", not "night" (a state restore
    -- - host_boot/state_ALL - is the only case that snaps straight to look).
    apply_phase_visuals(true)
    refresh_clock()
    if night then
        announce_local("Night falls... the dead are walking.")
    else
        announce_local("Day " .. day .. " - the sun is up.")
    end
end

function apply_phase_visuals(fade)
    capture_shadow_base()
    set_background_color(is_night and NIGHT_BG or DAY_BG)
    if fade then
        -- Both effects fade over PHASE_FADE_SECONDS instead of popping in/out.
        phase_fade_elapsed = 0
        if is_night then
            local cfg = {}
            for key, value in pairs(NIGHT_VIGNETTE) do cfg[key] = value end
            cfg.color = Color(0, 0, 0, 0)
            set_vignette(cfg)
            set_shadow({ visible = true }) -- stays visible while its alpha ramps down to 0
        else
            set_vignette({ visible = true }) -- stays visible while its alpha ramps down to 0
            set_shadow({ visible = true, shadow_angle = SUN_START_ANGLE,
                shadow_color = Color(shadow_rgb.r, shadow_rgb.g, shadow_rgb.b, 0) })
        end
        start_timer({ timer_id = "phase_fade", entity_name = name,
            function_name = "phase_fade_step", wait_time = PHASE_FADE_STEP })
    else
        -- State restore (join / new world): snap straight to the correct look
        -- for however far into the day/night we actually are right now.
        phase_fade_elapsed = -1
        stop_timer("phase_fade")
        if is_night then
            set_vignette(night_vignette_now())
            set_shadow({ visible = false })
        else
            set_vignette({ visible = false })
            set_shadow({ visible = true,
                shadow_angle = SUN_START_ANGLE + (SUN_END_ANGLE - SUN_START_ANGLE) * day_progress(),
                shadow_color = Color(shadow_rgb.r, shadow_rgb.g, shadow_rgb.b, shadow_alpha_full) })
        end
    end
end

-- Ramps the vignette and shadow alpha over PHASE_FADE_SECONDS (local only):
-- dusk fades the vignette in and the shadow out; dawn is the mirror image.
function phase_fade_step()
    if phase_fade_elapsed < 0 then
        stop_timer("phase_fade")
        return
    end
    phase_fade_elapsed = phase_fade_elapsed + PHASE_FADE_STEP
    local progress = math.min(phase_fade_elapsed / PHASE_FADE_SECONDS, 1.0)
    if is_night then
        set_vignette({ color = Color(0, 0, 0, NIGHT_VIGNETTE.color.a * progress) })
        set_shadow({ shadow_color = Color(shadow_rgb.r, shadow_rgb.g, shadow_rgb.b,
            shadow_alpha_full * (1 - progress)) })
    else
        set_vignette({ color = Color(0, 0, 0, NIGHT_VIGNETTE.color.a * (1 - progress)) })
        set_shadow({ shadow_color = Color(shadow_rgb.r, shadow_rgb.g, shadow_rgb.b,
            shadow_alpha_full * progress) })
    end
    if progress >= 1.0 then
        phase_fade_elapsed = -1
        stop_timer("phase_fade")
        if is_night then
            set_shadow({ visible = false })
        else
            set_vignette({ visible = false })
        end
    end
end

-- =============================================================================
-- Announcements: chat line + a short banner label everyone sees.
-- =============================================================================

function announce(text)
    if not IS_HOST then return end
    run_network_function(name, "announce_ALL", { text })
end

function announce_ALL(sender_id, text)
    announce_local(text)
end

function announce_local(text)
    add_to_chat(text, false)
    banner_local(text)
end

-- Same on-screen banner as announce_local, but WITHOUT the chat line - for
-- transient toasts (e.g. "No arrows!") that are already visible on screen and
-- would just spam the chat log otherwise.
function banner_local(text)
    set_label({ name = "_mbl_banner", text = text })
    start_timer({ timer_id = "mbl_banner", entity_name = name,
        function_name = "clear_banner", wait_time = 5.0, duration = 5.0 })
end

function clear_banner()
    set_label({ name = "_mbl_banner", text = "" })
end

-- =============================================================================
-- Stats.
-- =============================================================================

local function stat_entry(steam_id)
    if not stats[steam_id] then
        local entry = {}
        for _, stat_key in ipairs(STAT_KEYS) do entry[stat_key] = 0 end
        stats[steam_id] = entry
    end
    return stats[steam_id]
end

function add_stat(steam_id, stat_key, amount)
    if not IS_HOST then return end
    local entry = stat_entry(steam_id)
    entry[stat_key] = (entry[stat_key] or 0) + amount
end

-- =============================================================================
-- Terrain interaction (host side; called by user.lua's intent handlers).
-- All changes flow through ONE broadcast so every peer's ledger matches.
-- =============================================================================

function host_mutate(x, y, kind)
    run_network_function(name, "tile_mut_ALL", { x, y, kind })
end

function tile_mut_ALL(sender_id, x, y, kind)
    run_function("-gen", "apply_mut", { x, y, kind })
end

local function roll_drops(drop_table, power, x, y)
    local world = map_to_local(Vector2(x, y))
    for _, drop in ipairs(drop_table) do
        local chance = drop.chance + (drop.per_power or 0) * (power or 0)
        if math.random() < chance then
            local count = math.random(drop.min, drop.max)
            if count > 0 then
                local angle = math.random() * 2 * math.pi
                spawn_entity_host({ t = "ground_item",
                    p = Vector2(world.x + math.cos(angle) * 8, world.y + math.sin(angle) * 8),
                    item_id = drop.id, count = count })
            end
        end
    end
end

-- One swing against a tree, rock or (with a shovel) the ground. Returns true
-- when the swing was a gather action (the caller melee-swings otherwise). Every
-- hit on a tree/rock shows a floating damage number - a 0 tells the player their
-- tool cannot hurt this (e.g. punching a rock).
function host_gather_hit(args)
    local steam_id = args.steam_id
    local x, y = math.floor(args.x), math.floor(args.y)
    local tool, power = args.tool, args.power or 1
    local kind = run_function("-gen", "kind_at", { x, y })

    -- Shovel on grass tills it into farmland (farm plots are made, not generated).
    if tool == "shovel" and kind == K_GRASS then
        host_mutate(x, y, K_FARM)
        run_network_function(name, "gather_fx_ALL", { x, y, kind })
        return true
    end

    local hit_damage, break_hp, drops, stat_key
    if kind == K_TREE then
        -- Pickaxes chop at full power; anything else nibbles 1 per hit.
        hit_damage = (tool == "pickaxe") and power or 1
        break_hp = run_function("-items", "get_tree_hp")
        drops = run_function("-items", "get_tree_drops")
        stat_key = "trees"
    elseif kind == K_STONE then
        hit_damage = (tool == "pickaxe") and power or 0 -- wrong tool: shows a 0
        break_hp = run_function("-items", "get_stone_hp")
        drops = run_function("-items", "get_stone_drops")
        stat_key = "stones"
    else
        return false
    end
    hit_damage = math.floor(hit_damage)
    local world = map_to_local(Vector2(x, y))
    run_function("-combat", "show_damage", { world.x, world.y, hit_damage, "npc" })
    if hit_damage <= 0 then
        return true -- wrong tool: no real hit landed, so no chip particle either
    end
    run_network_function(name, "gather_fx_ALL", { x, y, kind })
    local break_key = key_of(x, y)
    local hp = (breaks[break_key] or break_hp) - hit_damage
    if hp > 0 then
        breaks[break_key] = hp
        return true
    end
    breaks[break_key] = nil
    host_mutate(x, y, run_function("-gen", "ground_kind", { x, y }))
    roll_drops(drops, power, x, y)
    add_stat(steam_id, stat_key, 1)
    return true
end

-- Small local chip/leaf puff so hits feel real (one message per swing).
function gather_fx_ALL(sender_id, x, y, kind)
    local world = map_to_local(Vector2(x, y))
    local color = (kind == K_TREE) and Color(99 / 255, 199 / 255, 77 / 255, 1)
        or Color(139 / 255, 155 / 255, 180 / 255, 1)
    create_particle({ particle_id = "mbl_chip", texture_path = "white",
        lifetime = 0.4, amount = 6, explosiveness = 1.0, one_shot = true,
        spread = 180, initial_velocity_min = 30, initial_velocity_max = 70,
        scale_amount_min = 0.1, scale_amount_max = 0.2, color = color })
    start_particle({ particle_id = "mbl_chip", position = world })
end

-- Interact intents: plant / harvest. Seeds only take on tilled farmland
-- (make a plot by hitting grass with a shovel first).
function host_plant(args)
    local steam_id = args.steam_id
    local x, y = math.floor(args.x), math.floor(args.y)
    local kind = run_function("-gen", "kind_at", { x, y })
    if kind ~= K_FARM then return false end
    if not run_function("-inv", "host_consume",
            { { steam_id = steam_id, item_id = "seed", count = 1 } }) then
        return false
    end
    host_mutate(x, y, K_FARM_SEEDED)
    pending_growth[key_of(x, y)] = game_time() + GROW_SECONDS
    return true
end

function host_harvest(args)
    local x, y = math.floor(args.x), math.floor(args.y)
    local kind = run_function("-gen", "kind_at", { x, y })
    if kind ~= K_FARM_GROWN then return false end
    host_mutate(x, y, K_FARM)
    roll_drops(run_function("-items", "get_harvest_drops"), 0, x, y)
    return true
end

-- True if any user or npc (zombie/boss) currently stands on tile (x, y) -
-- placing a block under someone's feet (including the placer's own) is
-- rejected.
local function tile_occupied(x, y)
    for _, tag in ipairs({ "user", "npc" }) do
        for _, entity_name in ipairs(get_entity_names_by_tag(tag)) do
            local pos = get_value("", entity_name, "position")
            if pos then
                local tile = local_to_map(pos)
                if math.floor(tile.x) == x and math.floor(tile.y) == y then
                    return true
                end
            end
        end
    end
    return false
end

-- Place a held material back down as a world block (wood -> a choppable tree,
-- stone -> a mineable rock; the same gather loop reclaims it later). Only
-- bare, walkable ground can receive one, never a tile someone is standing on.
function host_place_block(args)
    local steam_id, item_id = args.steam_id, args.item_id
    local x, y = math.floor(args.x), math.floor(args.y)
    local place_kind = run_function("-items", "get_place_kind", { item_id })
    if not place_kind then return false end
    local kind = run_function("-gen", "kind_at", { x, y })
    if kind ~= K_GRASS and kind ~= K_SAND then return false end
    if tile_occupied(x, y) then return false end
    if not run_function("-inv", "host_consume",
            { { steam_id = steam_id, item_id = item_id, count = 1 } }) then
        return false
    end
    host_mutate(x, y, place_kind)
    return true
end

function check_growth()
    local now = game_time()
    for grow_key, when in pairs(pending_growth) do
        if now >= when then
            pending_growth[grow_key] = nil
            -- Tolerate float-form keys ("3.0,5.0") left behind by older saves.
            local x, y = string.match(grow_key, "^(-?[%d%.]+),(-?[%d%.]+)$")
            x, y = tonumber(x), tonumber(y)
            if x and y and run_function("-gen", "kind_at", { x, y }) == K_FARM_SEEDED then
                host_mutate(x, y, K_FARM_GROWN)
            end
        end
    end
end

-- =============================================================================
-- Enemies.
-- =============================================================================

local function scaled(base, per_day)
    return math.floor(base * math.min(1 + per_day * (day - 1), 3.0))
end

function spawn_enemy(etype, pos, opts)
    local def = ENEMY_TYPES[etype]
    opts = opts or {}
    local hp = opts.fixed and math.floor(def.hp * 1.5) or scaled(def.hp, HP_SCALE_PER_DAY)
    local dmg = opts.fixed and math.floor(def.dmg * 1.2) or scaled(def.dmg, DMG_SCALE_PER_DAY)
    spawn_entity_host({ t = "enemy", p = pos,
        image = def.image, size = def.size, hp = hp, dmg = dmg, speed = def.speed,
        windup = def.windup, cooldown = def.cooldown, reach = def.reach,
        ranged = def.ranged or false, shoot_cd = def.shoot_cd or 0,
        tint = def.tint, is_night_npc = not opts.fixed, dungeon_id = opts.dungeon_id or "" })
end

function spawn_zombie_wave()
    local users = get_entity_names_by_tag("alive")
    if #users == 0 then return end
    local cap = math.min(ZOMBIES_PER_PLAYER_BASE + day, ZOMBIES_PER_PLAYER_MAX) * #users
    local current = #get_entity_names_by_tag("night_npc")
    for _, user_name in ipairs(users) do
        if current >= cap then break end
        local pos = get_value("", user_name, "position")
        if pos then
            for _ = 1, 2 do
                local spot = find_walkable_near(pos)
                if spot and current < cap then
                    spawn_enemy("zombie", spot)
                    current = current + 1
                end
            end
        end
    end
end

function find_walkable_near(pos)
    for _ = 1, 8 do
        local angle = math.random() * 2 * math.pi
        local dist = math.random(ZOMBIE_SPAWN_DIST_MIN, ZOMBIE_SPAWN_DIST_MAX)
        local spot = Vector2(pos.x + math.cos(angle) * dist, pos.y + math.sin(angle) * dist)
        local tile = local_to_map(spot)
        if run_function("-gen", "is_walkable", { math.floor(tile.x), math.floor(tile.y) }) then
            return spot
        end
    end
    return nil
end

function spawn_dungeon_population()
    if not IS_HOST then return end
    local pois = run_function("-gen", "get_dungeon_pois")
    for _, poi in ipairs(pois) do
        if not dungeon_done[poi.id] then
            local world = map_to_local(Vector2(poi.x, poi.y))
            if poi.type == "chest" then
                spawn_entity_host({ t = "ground_item", p = world,
                    item_id = "chest", count = 1, dungeon_id = poi.id })
            else
                spawn_enemy(poi.type, world, { fixed = true, dungeon_id = poi.id })
            end
        end
    end
end

function mark_dungeon_done(poi_id)
    if poi_id ~= "" then dungeon_done[poi_id] = true end
end

-- Called by enemy.lua when something dies.
function on_enemy_killed(args)
    local killer, dungeon_id = args.killer, args.dungeon_id
    if killer and has_tag(killer, "user") then
        add_stat(killer, "kills", 1)
    end
    mark_dungeon_done(dungeon_id)
end

-- =============================================================================
-- Boss: shows up at nightfall of day 7, dies to confetti and statistics.
-- =============================================================================

function spawn_boss()
    boss_active = true
    local arena_x = get_value("", "-gen", "BOSS_ARENA_X") or 0
    local arena_y = get_value("", "-gen", "BOSS_ARENA_Y") or -26
    local players = math.max(#get_entity_names_by_tag("user"), 1)
    local hp = math.floor(BOSS_HP_BASE * (1 + BOSS_HP_PER_EXTRA_PLAYER * (players - 1)))
    local world = map_to_local(Vector2(arena_x, arena_y))
    boss_entity = spawn_entity_host({ t = "boss", p = world, hp = hp })
    announce({ "The GUARDIAN OF THE ISLE has risen! Slay it or survive it." })
    run_network_function(name, "boss_nav_ALL", { boss_entity })
end

function boss_nav_ALL(sender_id, boss_name)
    nav_icon_name = set_navigation_icon({ target_name = boss_name, name = "nav_mbl_boss",
        text = "BOSS", color = Color(228 / 255, 59 / 255, 68 / 255, 1),
        is_show_distance = true })
end

function on_boss_defeated(args)
    if not IS_HOST then return end
    boss_active = false
    boss_defeated = true
    local payload = { players = {} }
    for steam_id, entry in pairs(stats) do
        payload.players[steam_id] = { nickname = get_value("", steam_id, "nickname") or steam_id,
            stats = entry }
    end
    run_network_function(name, "victory_ALL", { payload })
    save_world()
end

function victory_ALL(sender_id, payload)
    if nav_icon_name ~= "" then
        destroy("", nav_icon_name)
        nav_icon_name = ""
    end
    -- Confetti around the local player.
    local pos = get_value("", LOCAL_STEAM_ID, "position") or Vector2(0, 0)
    create_particle({ particle_id = "mbl_confetti", texture_path = "white",
        lifetime = 1.8, amount = 160, explosiveness = 1.0, one_shot = true,
        spread = 180, initial_velocity_min = 90, initial_velocity_max = 260,
        gravity = { x = 0, y = 160 }, scale_amount_min = 0.15, scale_amount_max = 0.3,
        color_random = true })
    start_particle({ particle_id = "mbl_confetti", position = Vector2(pos.x, pos.y - 40) })
    show_stats_panel(payload, true)
end

function show_stats_panel(payload, victory)
    local title = victory and "VICTORY - The Guardian has fallen!" or "Statistics"
    local body = victory
        and "Congratulations! You survived seven days and slew the Guardian.\nThe island is yours now - keep playing as long as you like."
        or "The story so far:"
    local panel_name = create_panel({ name = "_mbl_stats", title = title, text = body,
        minimum_size = Vector2(640, 420), is_scrollable = true, resizable = true,
        close = true, set_time = false })
    local header_color = Color(38 / 255, 92 / 255, 66 / 255, 0.95)  -- Moss
    local cell_color = Color(58 / 255, 68 / 255, 102 / 255, 0.9)    -- Steel
    local table_data = {}
    local columns = { "Player", "Trees", "Rocks", "Kills", "Damage Dealt",
        "Damage Taken", "Deaths", "Crafts" }
    for col, caption in ipairs(columns) do
        table_data[vector2_to_string(Vector2(col - 1, 0))] = { text = caption, color = header_color }
    end
    local row = 1
    for _, player in pairs(payload.players) do
        local entry = player.stats
        local cells = { player.nickname, entry.trees, entry.stones, entry.kills,
            math.floor(entry.dmg_dealt), math.floor(entry.dmg_taken), entry.deaths, entry.crafts }
        for col, value in ipairs(cells) do
            table_data[vector2_to_string(Vector2(col - 1, row))] =
                { text = tostring(value), color = cell_color }
        end
        row = row + 1
    end
    set_table(panel_name, { table_data = table_data })
end

function stats_HOST(sender_id)
    local payload = { players = {} }
    for steam_id, entry in pairs(stats) do
        payload.players[steam_id] = { nickname = get_value("", steam_id, "nickname") or steam_id,
            stats = entry }
    end
    run_network_function(name, "stats_panel_ALL", { payload }, sender_id)
end

function stats_panel_ALL(sender_id, payload)
    show_stats_panel(payload, false)
end

-- =============================================================================
-- Player death bookkeeping (user.lua calls this on the host).
-- =============================================================================

function on_player_died(args)
    if not IS_HOST then return end
    local steam_id = args.steam_id
    add_stat(steam_id, "deaths", 1)
    run_function("-inv", "host_scatter", { steam_id })
    announce((get_value("", steam_id, "nickname") or "Someone")
        .. " died! Their pack scattered where they fell.")
end

-- =============================================================================
-- Chat commands.
-- =============================================================================

function cmd_friendlyfire()
    if not IS_HOST then
        add_to_chat("Only the host can toggle friendly fire.", false)
        return
    end
    friendly_fire = not friendly_fire
    run_network_function(name, "ff_ALL", { friendly_fire })
end

function ff_ALL(sender_id, on)
    friendly_fire = on
    announce_local(on and "Friendly fire is now ON - mind your swings!"
        or "Friendly fire is now OFF.")
end

function cmd_seed()
    add_to_chat("World seed: " .. tostring(seed_value), false)
end

function cmd_stats()
    run_network_function(name, "stats_HOST")
end

function cmd_newworld()
    if not IS_HOST then
        add_to_chat("Only the host can start a new world.", false)
        return
    end
    local new_seed = get_os_time_unix() % 1000000007
    destroy_entities_by_tag("npc")
    destroy_entities_by_tag("ground_item")
    stats = {}
    pending_growth = {}
    breaks = {}
    dungeon_done = {}
    saved_positions = {}
    run_network_function(name, "newworld_ALL", { new_seed })
    spawn_dungeon_population()
    run_function("-inv", "load_save_data", { { inv = {}, held = {} } })
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        run_function("-inv", "host_sync_all_to", { user_name })
        local spawn = map_to_local(Vector2(0, 0))
        run_function(user_name, "host_respawn_at", { spawn.x, spawn.y })
    end
    save_world()
end

function newworld_ALL(sender_id, new_seed)
    seed_value = new_seed
    day = 1
    t = 0
    is_night = false
    boss_defeated = false
    boss_active = false
    run_function("-gen", "set_seed", { new_seed })
    apply_phase_visuals()
    refresh_clock()
    announce_local("A brand new world! Everything starts over - good luck.")
end

add_command(name, "cmd_friendlyfire", "friendlyfire",
    "Host only: toggle player-vs-player damage (default off).", true)
add_command(name, "cmd_newworld", "newworld",
    "Host only: abandon this world and generate a fresh one.", true)
add_command(name, "cmd_seed", "seed", "Show the current world seed.", true)
add_command(name, "cmd_stats", "stats", "Show the scoreboard so far.", true)

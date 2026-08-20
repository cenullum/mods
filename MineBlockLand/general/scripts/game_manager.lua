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
local K_SAPLING = 11
local K_CACTUS, K_PALM, K_FLOWER = 12, 13, 14
local K_WOOD_BLOCK = 15

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
local TREE_GROW_SECONDS = 300     -- planted sapling -> full tree
local TILL_SEED_CHANCE = 0.75     -- shovel-tilling grass has this chance to turn up a wheat seed
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
local PHASE_FADE_SECONDS = 3.0   -- dusk/dawn creep in - vignette, shadows AND ambience, never a hard cut
local PHASE_FADE_STEP = 0.05

-- Ambient day/night bed. See update_ambient()/start_ambient() further down for
-- how the crossfade rides the SAME phase_fade_step timer as the vignette/shadow.
local AMBIENT_TRACKS = { amb_day = "ambient/morning_nature", amb_night = "ambient/night" }
local AMBIENT_VOLUME = -12  -- audible target: a quiet bed under sfx sitting at -3..-7
local AMBIENT_SILENT = -60  -- effectively inaudible; the fade-in/out starts/ends here
local ambient_playing = ""     -- "" | "amb_day" | "amb_night" - currently audible (or fading in)
local ambient_fading_out = ""  -- the previous track, ramping to AMBIENT_SILENT before it is freed

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
    -- The witch keeps her distance and throws bolts. Her bolt is tinted violet
    -- (bolt_color) so a witch shot reads differently from a boss shot mid-fight.
    witch = { image = "items/10x10_witch", size = 18, hp = 70, dmg = 16, speed = 8,
        windup = 0.6, cooldown = 1.6, reach = 24, ranged = true, shoot_cd = 2.2,
        bolt_color = Color(178 / 255, 92 / 255, 232 / 255, 1),
        tint = Color(1, 1, 1, 1) },
    -- The ghost ignores every collision layer (see 'phasing' in enemy.lua), so
    -- walls, trees and the rock you hid behind mean nothing to it. It still
    -- deals and takes damage exactly like any other enemy.
    ghost = { image = "items/10x10_ghost", size = 18, hp = 45, dmg = 14, speed = 13,
        windup = 0.5, cooldown = 1.5, reach = 24, phasing = true,
        tint = Color(1, 1, 1, 0.6) },
}

-- Who shows up in a night wave, and from which day on. One entry is picked per
-- spawn slot, weighted - so the horde stays mostly zombies while the rarer,
-- nastier things trickle in as the days pile up.
--
-- 'weight_per_day' is added once per day survived past min_day, so a type does
-- not just unlock and then sit at a fixed rarity - it keeps growing until the
-- ramp freezes (see DIFFICULTY_MAX_DAY). The witch used to be weight 10 from
-- day 4, i.e. under 1 spawn in 10 and never before day 4, which is why she was
-- effectively never seen; she now opens on day 3 and climbs to roughly a
-- quarter of the horde by the boss day.
local NIGHT_SPAWN_TABLE = {
    { etype = "zombie", weight = 70, weight_per_day = 0, min_day = 1 },
    { etype = "ghost", weight = 20, weight_per_day = 2, min_day = 2 },
    { etype = "witch", weight = 20, weight_per_day = 4, min_day = 3 },
    { etype = "brute", weight = 4, weight_per_day = 5, min_day = 6 },
}
local HP_SCALE_PER_DAY = 0.25
local DMG_SCALE_PER_DAY = 0.15
local ZOMBIES_PER_PLAYER_BASE = 2
local ZOMBIES_PER_PLAYER_MAX = 9

-- Difficulty ramp. Every night is a little worse than the last - more enemies
-- alive at once, waves closer together, tougher bodies - but ONLY up to
-- DIFFICULTY_MAX_DAY. That is the boss day: once the run reaches its endgame
-- the pressure stops climbing and holds flat, so a long-lived world never turns
-- into an unplayable spawn storm.
local DIFFICULTY_MAX_DAY = BOSS_DAY
local WAVE_SECONDS_BASE = 25      -- seconds between night waves on day 1
local WAVE_SECONDS_MIN = 16       -- ...and at DIFFICULTY_MAX_DAY onwards
local WAVE_SECONDS_PER_DAY = 1.5
local SPAWNS_PER_WAVE = 2         -- attempts per player per wave...
local SPAWNS_PER_WAVE_LATE = 3    -- ...raised from this day on (the cap still rules)
local SPAWNS_PER_WAVE_LATE_DAY = 5
local BOSS_HP_BASE = 1500
local BOSS_MAX_LIVES = 3 -- per-player spawn rights during the boss fight, see boss_lives below
local RESET_PANEL = "_mbl_boss_reset"
-- Terrain audio. Every one of these is 2D and purely local: the broadcasts that
-- carry them (gather_fx_ALL / tile_mut_ALL / boom_fx_ALL) already reach every
-- peer, so the sound costs no traffic of its own.
local TILE_SFX_DISTANCE = 420
local TILE_HIT_VARIANTS = 5 -- general/sounds/tile_hit1..5.ogg
local TEST_ITEM_COUNT = 99 -- how many of each item /testitems hands out

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
-- steam_id -> spawn rights left in the current boss fight (outside of a boss
-- fight, dying is free - unlimited respawns - so this only exists while
-- boss_active is true and is wiped clean between fights).
local boss_lives = {}

-- Portals. Up to PORTALS_PER_PLAYER each, placed where the owner stands, named
-- by them and travelled between by walking into any of them. The host owns the
-- ledger and persists it; the full list is small (a handful per player), so any
-- change is simply rebroadcast whole instead of diffed.
--
-- Keyed by PORTAL ID, not by steam id: "<steam_id>_<slot>", where slot is the
-- lowest free number 1..PORTALS_PER_PLAYER. Taking a portal back frees its slot
-- again, so the ids stay bounded and stable instead of climbing forever. The id
-- is a STRING on purpose - a numeric one would come back from GDScript as a
-- float and stop matching its own key.
local PORTALS_PER_PLAYER = 5
local portals = {}          -- HOST: pid -> { owner, x, y, label } (x/y are TILE coords)
local portal_entities = {}  -- HOST: pid -> spawned entity name
-- Forward-declared: finish_boot() (further up the file) restores portals, but
-- the implementations live down in the portal section with the rest of them.
local sync_portals, spawn_portal, despawn_portal
local PORTAL_ARRIVE_OFFSET = 22 -- land just outside the destination's trigger ring
local PORTAL_NAME_PANEL = "_mbl_portal_name"
local PORTAL_ITEM = "portal_stone" -- spent on placing, handed back on removal

-- Worlds saved before the five-portal change keyed the ledger by steam id with
-- no 'owner' field; those entries become that player's slot 1.
local function migrate_portals(saved)
    local out = {}
    for key, entry in pairs(saved or {}) do
        local owner = entry.owner or key
        local pid = entry.owner and key or (key .. "_1")
        out[pid] = { owner = owner, x = math.floor(entry.x), y = math.floor(entry.y),
            label = entry.label or "Portal" }
    end
    return out
end

local function portal_count(steam_id)
    local count = 0
    for _, entry in pairs(portals) do
        if entry.owner == steam_id then count = count + 1 end
    end
    return count
end

-- The lowest unused slot for this player as (pid, slot), or ("", 0) when all
-- PORTALS_PER_PLAYER of them are already standing.
local function free_portal_id(steam_id)
    for slot = 1, PORTALS_PER_PLAYER do
        local pid = steam_id .. "_" .. slot
        if not portals[pid] then return pid, slot end
    end
    return "", 0
end

-- Local (every peer).
local nav_icon_name = ""
local synced = IS_HOST
local dungeon_marked = false -- the G map already shows the dungeon (see check_dungeon_marker)
local typed_portal_name = ""  -- owner-side state of the "name your portal" panel
local typed_portal_pid = ""   -- ...and WHICH of the owner's portals it is naming
portal_list = {}            -- every peer: pid -> { owner, x, y, label }; read by portal.lua

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

-- The day the difficulty ramp should be read at: the real day until the
-- endgame, then frozen. Every ramped number (wave size, wave interval, enemy
-- hp/damage, spawn weights) goes through this ONE function, so the whole curve
-- is retuned from the constants above and can never diverge between systems.
local function ramp_day()
    return math.min(day, DIFFICULTY_MAX_DAY)
end

-- Seconds between night waves, shrinking as the days pile up. Kept a whole
-- number because tick() matches it with 't % wave_seconds() == 0'.
local function wave_seconds()
    local seconds = WAVE_SECONDS_BASE - WAVE_SECONDS_PER_DAY * (ramp_day() - 1)
    return math.max(WAVE_SECONDS_MIN, math.floor(seconds))
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
        portals = migrate_portals(data.portals)
        run_function("-gen", "set_seed", { seed_value })
        run_function("-gen", "set_all_muts", { data.muts or {} })
        run_function("-inv", "load_save_data", { data.inv or {} })
        announce("{world_restored_day}" .. day .. "{welcome_back}")
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
    -- Everyone ALREADY in the lobby needs the world state now, not just future
    -- joiners: a peer that connected while the host was still sitting on the
    -- seed panel was skipped by _on_user_initialized (seed_value was still 0),
    -- so without this it never learned the seed - no island ever generated for
    -- it - and its 'synced' flag stayed false, which also froze its clock at
    -- day 1 / 06:00 forever. Late joiners were fine because they get the very
    -- same pair of messages from _on_user_initialized.
    run_network_function(name, "state_ALL",
        { seed_value, day, t, is_night, friendly_fire, boss_defeated })
    run_network_function(name, "muts_ALL", { run_function("-gen", "get_all_muts") })
    spawn_dungeon_population()
    apply_phase_visuals()
    refresh_clock()
    -- Portals restored from the save become real entities again, and every peer
    -- gets the ledger so the map markers and travel panels line up.
    for pid in pairs(portals) do spawn_portal(pid) end
    sync_portals()
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
    announce("{a_fresh_world_awakens_seed}" .. seed_value .. "{chop_mine_and_craft_by_day}"
        .. "{every_night_monsters_come_for_you_and_on}" .. BOSS_DAY
        .. "{the_guardian_of_the_isle_rises_kill_it_t}")
    finish_boot()
end

function on_seed_input(args)
    -- The input's value is delivered keyed by its RAW label, i.e. the token.
    typed_seed = tostring(args["{seed}"] or "")
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
    create_panel({ name = SEED_PANEL, title ="{mineblockland_host}",
        text ="{pick_the_world_seed_same_seed_always_bui}"
            .. DEFAULT_SEED,
        set_time = false, close = false, resizable = false, minimum_size = Vector2(400, 250) })
    add_input_to_panel(SEED_PANEL, { entity_name = name, function_name = "on_seed_input",
        text ="{seed}", default_value = typed_seed })
    add_button_to_panel(SEED_PANEL, { entity_name = name, function_name = "on_use_seed",
        text ="{use_this_seed}", color = Color(0.3, 0.55, 0.35) })
    add_button_to_panel(SEED_PANEL, { entity_name = name, function_name = "on_random_seed",
        text ="{random_seed}", color = Color(0.35, 0.45, 0.6) })
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
        portals = portals,
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
    text ="{spawn}", icon_size = Vector2(8, 8), color = Color(1, 1, 1, 1) })

-- The dungeon marks itself on the G map the moment THIS peer has generated the
-- chunk its door sits in - i.e. the moment you have been close enough to see
-- it. Purely local (like every other marker): finding it is each player's own
-- discovery, and nothing about it needs to travel over the network. Checked
-- once a second from tick() and then never again, so it costs one table lookup
-- per second until it fires.
local DUNGEON_MARKER = "dungeon"

local function check_dungeon_marker()
    local entrance = run_function("-gen", "get_dungeon_entrance")
    if not entrance then return end
    -- Crossed the Lua<->GDScript boundary: tile coords are floats now.
    local tx, ty = math.floor(entrance.x), math.floor(entrance.y)
    if not run_function("-gen", "is_tile_generated", { tx, ty }) then return end
    dungeon_marked = true
    set_minimap_target({ name = DUNGEON_MARKER,
        world_position = map_to_local(Vector2(tx, ty)),
        text ="{dungeon}", icon_size = Vector2(8, 8),
        color = Color(0.85, 0.35, 0.35, 1) })
end

if IS_HOST then
    start_timer({ timer_id = "gm_autosave", entity_name = name, function_name = "save_world",
        wait_time = AUTOSAVE_SECONDS })
end

-- =============================================================================
-- Late joiners get the whole world in a handful of messages.
-- =============================================================================

function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end
    -- Voice chat: one island, one channel. Nothing here splits players into
    -- teams or rooms, so everybody goes straight into "general" with no
    -- proximity falloff - you can always hear each other, wherever you are.
    -- Done here rather than in user.lua because a peer only becomes a valid
    -- RPC target once it is initialized, which is exactly this moment (and
    -- this fires for the host's own player too).
    set_voice_channel({ steam_id = steam_id, channel_name = "general",
        parent_name = steam_id, icon_offset = Vector2(0, -26) })
    if seed_value == 0 then return end -- host boot pending; finish_boot syncs everyone
    run_network_function(name, "state_ALL",
        { seed_value, day, t, is_night, friendly_fire, boss_defeated }, steam_id)
    run_network_function(name, "muts_ALL",
        { run_function("-gen", "get_all_muts") }, steam_id)
    run_function("-inv", "host_sync_all_to", { steam_id })
    -- The portal ENTITIES arrive on their own (network_mode = 1 syncs them on
    -- join); this is the ledger behind them, needed for the map markers and the
    -- travel list.
    run_network_function(name, "portals_ALL", { portals }, steam_id)
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
    if not dungeon_marked then check_dungeon_marker() end
    if IS_HOST then
        if not is_night and t >= DAY_SECONDS then
            begin_night()
        elseif t >= CYCLE_SECONDS then
            begin_day()
        end
        check_growth()
        if is_night and t % wave_seconds() == 0 then
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
    local suffix = is_night and "{night_suffix}" or ""
    set_label({ name = "_mbl_clock",
        text = string.format(translate("{clock_label}"), math.floor(day),
            string.format("%02d", hour), string.format("%02d", minute), suffix) })
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
    -- ...and lets fresh wildlife wander into the chunks nobody is watching.
    run_function("-wild", "host_restock")
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
        announce_local("{night_falls}")
    else
        announce_local("{day}" .. day .. "{the_sun_is_up}")
    end
end

-- =============================================================================
-- Ambient day/night loop.
--
-- Runs on EVERY peer with zero traffic of its own: apply_phase_visuals is only
-- ever reached through phase_ALL (dusk/dawn) or state_ALL (join/restore), both
-- broadcasts the day/night system already sends for the vignette and shadow.
-- The crossfade itself piggybacks on that SAME phase_fade_step timer instead of
-- starting a second one - one 0.05s timer covers vignette, shadow AND ambience.
--
-- Tracks are parented to THIS entity (-gm) rather than left unparented: an
-- unparented audio player lives under SoundManager, which set_audio_volume and
-- destroy cannot look up by name (see set_audio_volume's stub comment) - so a
-- track created here can later be ramped and freed by its plain name.
-- =============================================================================

local function ambient_target()
    return is_night and "amb_night" or "amb_day"
end

local function start_ambient(track_name, start_volume)
    set_audio({ name = track_name, parent_name = name,
        stream_path = AMBIENT_TRACKS[track_name],
        is_loop = true, is_2d = false, bus = "Ambient", volume = start_volume })
end

local function update_ambient(fade)
    local want = ambient_target()
    if want == ambient_playing then return end
    if fade then
        if ambient_playing ~= "" then
            -- A fade already mid-flight when a new one starts (only reachable
            -- through rapid host commands, e.g. /testboss racing a real dusk -
            -- never a normal transition) would otherwise orphan the earlier
            -- track at whatever volume it had reached, looping forever with
            -- nothing left to finish silencing it.
            if ambient_fading_out ~= "" then destroy(name, ambient_fading_out) end
            ambient_fading_out = ambient_playing
        end
        start_ambient(want, AMBIENT_SILENT)
    else
        -- State restore / world reset: nothing to ride a fade on, so whatever
        -- was playing is cut immediately and the right track snaps in at full
        -- volume - the same treatment this function gives the vignette/shadow
        -- in the branch below.
        if ambient_playing ~= "" then destroy(name, ambient_playing) end
        if ambient_fading_out ~= "" then destroy(name, ambient_fading_out) end
        ambient_fading_out = ""
        start_ambient(want, AMBIENT_VOLUME)
    end
    ambient_playing = want
end

function apply_phase_visuals(fade)
    capture_shadow_base()
    set_background_color(is_night and NIGHT_BG or DAY_BG)
    update_ambient(fade)
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
-- dusk fades the vignette in and the shadow out; dawn is the mirror image. The
-- ambient crossfade (update_ambient/start_ambient above) rides the exact same
-- progress value - the incoming track climbs from AMBIENT_SILENT to
-- AMBIENT_VOLUME while the outgoing one falls back the other way, and is freed
-- the moment the window closes.
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
    if ambient_playing ~= "" then
        set_audio_volume(name, ambient_playing,
            AMBIENT_SILENT + (AMBIENT_VOLUME - AMBIENT_SILENT) * progress)
    end
    if ambient_fading_out ~= "" then
        set_audio_volume(name, ambient_fading_out,
            AMBIENT_VOLUME + (AMBIENT_SILENT - AMBIENT_VOLUME) * progress)
    end
    if progress >= 1.0 then
        phase_fade_elapsed = -1
        stop_timer("phase_fade")
        if is_night then
            set_shadow({ visible = false })
        else
            set_vignette({ visible = false })
        end
        if ambient_fading_out ~= "" then
            destroy(name, ambient_fading_out)
            ambient_fading_out = ""
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

-- 'sfx' is "break" | "place" | nil, and rides along on the mutation broadcast
-- that every terrain change already sends - a tile changing kind IS the event,
-- so there is nothing to gain from a second message just to carry a sound.
-- nil is silent on purpose: a crop quietly maturing (check_growth) is not
-- something anyone should hear from across the island.
function host_mutate(x, y, kind, sfx)
    run_network_function(name, "tile_mut_ALL", { x, y, kind, sfx or "" })
end

function tile_mut_ALL(sender_id, x, y, kind, sfx)
    run_function("-gen", "apply_mut", { x, y, kind })
    if sfx == nil or sfx == "" then return end
    local world = map_to_local(Vector2(math.floor(x), math.floor(y)))
    set_audio({ stream_path = (sfx == "place") and "tile_place" or "tile_break",
        is_2d = true, position = world, max_distance = TILE_SFX_DISTANCE,
        volume = -3, random_pitch = 0.1 })
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
    -- A good chance of turning up a wheat seed while at it. A flower is just
    -- decorated grass, so it tills the same way.
    if tool == "shovel" and (kind == K_GRASS or kind == K_FLOWER) then
        host_mutate(x, y, K_FARM)
        run_network_function(name, "gather_fx_ALL", { x, y, kind })
        if math.random() < TILL_SEED_CHANCE then
            roll_drops({ { id = "wheat_seed", min = 1, max = 1, chance = 1.0 } }, 0, x, y)
        end
        return true
    end

    local hit_damage, break_hp, drops, stat_key
    if kind == K_TREE then
        -- Pickaxes chop at full power; anything else nibbles 1 per hit.
        hit_damage = (tool == "pickaxe") and power or 1
        break_hp = run_function("-items", "get_tree_hp")
        drops = run_function("-items", "get_tree_drops")
        stat_key = "trees"
    elseif kind == K_CACTUS or kind == K_PALM then
        -- Desert flora chops on the same rules as a tree (and counts as one).
        hit_damage = (tool == "pickaxe") and power or 1
        if kind == K_CACTUS then
            break_hp = run_function("-items", "get_cactus_hp")
            drops = run_function("-items", "get_cactus_drops")
        else
            break_hp = run_function("-items", "get_palm_hp")
            drops = run_function("-items", "get_palm_drops")
        end
        stat_key = "trees"
    elseif kind == K_STONE then
        hit_damage = (tool == "pickaxe") and power or 0 -- wrong tool: shows a 0
        break_hp = run_function("-items", "get_stone_hp")
        drops = run_function("-items", "get_stone_drops")
        stat_key = "stones"
    elseif kind == K_WOOD_BLOCK then
        -- Player-placed wood block: chops like a tree, any tool works.
        hit_damage = (tool == "pickaxe") and power or 1
        break_hp = run_function("-items", "get_wood_block_hp")
        drops = run_function("-items", "get_wood_block_drops")
        stat_key = "trees"
    elseif kind == K_SAPLING then
        -- Fragile: any tool (even fists) hurts it, and breaking one drops nothing.
        hit_damage = power
        break_hp = run_function("-items", "get_sapling_hp")
        drops = {}
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
    -- A broken sapling reverts to the tilled farmland it was planted on (so the
    -- player doesn't lose the plot); trees/rock revert to bare pure-terrain ground.
    local revert_kind = (kind == K_SAPLING) and K_FARM or run_function("-gen", "ground_kind", { x, y })
    host_mutate(x, y, revert_kind, "break")
    roll_drops(drops, power, x, y)
    if stat_key then add_stat(steam_id, stat_key, 1) end
    return true
end

-- Flat-damage tile hit (no tool/steam_id involved) - used by hostile
-- projectiles that smack into a tree or a placed wood/stone "wall" in
-- flight. Mirrors host_gather_hit's break logic minus the tool gating and
-- player stat credit (nobody chopped this, a bullet did).
-- 'args.quiet' is set by whoever is chewing through MANY cells at once (the
-- bomb), so the crater is carved without a thud per cell.
function host_damage_tile(args)
    if not IS_HOST then return end
    local x, y = math.floor(args.x), math.floor(args.y)
    local dmg = args.dmg or 1
    local quiet = args.quiet == true
    local kind = run_function("-gen", "kind_at", { x, y })
    local break_hp, drops
    if kind == K_TREE then
        break_hp = run_function("-items", "get_tree_hp")
        drops = run_function("-items", "get_tree_drops")
    elseif kind == K_CACTUS then
        break_hp = run_function("-items", "get_cactus_hp")
        drops = run_function("-items", "get_cactus_drops")
    elseif kind == K_PALM then
        break_hp = run_function("-items", "get_palm_hp")
        drops = run_function("-items", "get_palm_drops")
    elseif kind == K_STONE then
        break_hp = run_function("-items", "get_stone_hp")
        drops = run_function("-items", "get_stone_drops")
    elseif kind == K_WOOD_BLOCK then
        break_hp = run_function("-items", "get_wood_block_hp")
        drops = run_function("-items", "get_wood_block_drops")
    else
        return
    end
    -- Same floating number a player swing gets, so a boss bolt chewing through a
    -- tree/rock reads the same as anything else that takes damage.
    local world = map_to_local(Vector2(x, y))
    run_function("-combat", "show_damage", { world.x, world.y, dmg, "npc" })
    run_network_function(name, "gather_fx_ALL", { x, y, kind, quiet })
    local break_key = key_of(x, y)
    local hp = (breaks[break_key] or break_hp) - dmg
    if hp > 0 then
        breaks[break_key] = hp
        return
    end
    breaks[break_key] = nil
    host_mutate(x, y, run_function("-gen", "ground_kind", { x, y }), quiet and "" or "break")
    roll_drops(drops, 1, x, y)
end

-- Small local chip/leaf puff so hits feel real (one message per swing).
-- The two puffs (leaf green / stone grey) are built once and then only
-- re-emitted; create_particle rebuilds the cached node every call, so calling
-- it per swing would churn a GPUParticles2D on every hit.
local chip_fx_ready = false

local function ensure_chip_fx()
    if chip_fx_ready then return end
    chip_fx_ready = true
    local base = { texture_path = "white", lifetime = 0.4, amount = 6,
        explosiveness = 1.0, one_shot = true, spread = 180,
        initial_velocity_min = 30, initial_velocity_max = 70,
        scale_amount_min = 0.1, scale_amount_max = 0.2 }
    for id, color in pairs({
        mbl_chip_leaf = Color(99 / 255, 199 / 255, 77 / 255, 1),
        mbl_chip_stone = Color(139 / 255, 155 / 255, 180 / 255, 1),
    }) do
        local cfg = { particle_id = id, color = color }
        for k, v in pairs(base) do cfg[k] = v end
        create_particle(cfg)
    end
    -- Bomb blast: same one-shot puff, just bigger, faster and orange.
    create_particle({ particle_id = "mbl_boom", texture_path = "white",
        lifetime = 0.5, amount = 26, explosiveness = 1.0, one_shot = true,
        spread = 180, initial_velocity_min = 60, initial_velocity_max = 190,
        scale_amount_min = 0.15, scale_amount_max = 0.4,
        color = Color(247 / 255, 118 / 255, 34 / 255, 1) })
end

-- 'silent' suppresses only the SOUND, never the puff: a bomb chews through
-- dozens of cells in one frame (see bomb.lua's break_tiles), and thirty
-- overlapping chips is a visual flourish while thirty overlapping thuds is a
-- wall of noise. The blast plays one sound of its own instead - see boom_fx_ALL.
function gather_fx_ALL(sender_id, x, y, kind, silent)
    ensure_chip_fx()
    local world = map_to_local(Vector2(x, y))
    local leafy = kind == K_TREE or kind == K_SAPLING or kind == K_CACTUS or kind == K_PALM
    local id = leafy and "mbl_chip_leaf" or "mbl_chip_stone"
    start_particle({ particle_id = id, position = world })
    if silent then return end
    -- One of five thuds per swing, so a long chop never repeats the same sample
    -- twice in a row the way a single file would.
    set_audio({ stream_path = "tile_hit" .. math.random(TILE_HIT_VARIANTS),
        is_2d = true, position = world, max_distance = TILE_SFX_DISTANCE,
        volume = -5, random_pitch = 0.12 })
end

-- Bomb blast felt by every peer: the puff always plays, the shake fades out
-- with distance so a bomb across the island is a thump, not a head-rattle.
local BOOM_SHAKE_RANGE = 260
local BOOM_SHAKE_SECONDS = 0.35
local BOOM_SHAKE_MAX = 14

function boom_fx_ALL(sender_id, x, y)
    ensure_chip_fx()
    local at = Vector2(x, y)
    start_particle({ particle_id = "mbl_boom", position = at })
    set_audio({ stream_path = "bomb", is_2d = true, position = at,
        max_distance = BOOM_SHAKE_RANGE * 2, volume = 1, random_pitch = 0.06 })
    local me = get_value("", LOCAL_STEAM_ID, "position")
    if not me then return end
    local dist = distance_to(me, at)
    if dist >= BOOM_SHAKE_RANGE then return end
    screenshake(BOOM_SHAKE_SECONDS, BOOM_SHAKE_MAX * (1 - dist / BOOM_SHAKE_RANGE))
end

-- Interact intents: plant / harvest. Seeds only take on tilled farmland
-- (make a plot by hitting grass with a shovel first). A wheat seed becomes a
-- growing crop; a tree seed becomes a sapling straight away (no "seeded"
-- in-between step) which then grows into a full tree the same way.
function host_plant(args)
    local steam_id, item_id = args.steam_id, args.item_id
    local x, y = math.floor(args.x), math.floor(args.y)
    local kind = run_function("-gen", "kind_at", { x, y })
    if kind ~= K_FARM then return false end
    if not run_function("-inv", "host_consume",
            { { steam_id = steam_id, item_id = item_id, count = 1 } }) then
        return false
    end
    if item_id == "tree_seed" then
        host_mutate(x, y, K_SAPLING, "place")
        pending_growth[key_of(x, y)] = { when = game_time() + TREE_GROW_SECONDS, into = K_TREE }
    else
        host_mutate(x, y, K_FARM_SEEDED, "place")
        pending_growth[key_of(x, y)] = { when = game_time() + GROW_SECONDS, into = K_FARM_GROWN }
    end
    return true
end

function host_harvest(args)
    local x, y = math.floor(args.x), math.floor(args.y)
    local kind = run_function("-gen", "kind_at", { x, y })
    if kind ~= K_FARM_GROWN then return false end
    host_mutate(x, y, K_FARM, "break")
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
    -- Flowers are decoration on otherwise bare grass; a block simply covers one.
    if kind ~= K_GRASS and kind ~= K_SAND and kind ~= K_FLOWER then return false end
    if tile_occupied(x, y) then return false end
    if not run_function("-inv", "host_consume",
            { { steam_id = steam_id, item_id = item_id, count = 1 } }) then
        return false
    end
    host_mutate(x, y, place_kind, "place")
    return true
end

function check_growth()
    local now = game_time()
    for grow_key, entry in pairs(pending_growth) do
        -- Older saves stored a bare timestamp for the one growth path that
        -- used to exist (seeded farmland -> grown crop); tolerate that shape.
        local when = (type(entry) == "table") and entry.when or entry
        local into = (type(entry) == "table") and entry.into or K_FARM_GROWN
        if now >= when then
            pending_growth[grow_key] = nil
            -- Tolerate float-form keys ("3.0,5.0") left behind by older saves.
            local x, y = string.match(grow_key, "^(-?[%d%.]+),(-?[%d%.]+)$")
            x, y = tonumber(x), tonumber(y)
            local from = (into == K_TREE) and K_SAPLING or K_FARM_SEEDED
            if x and y and run_function("-gen", "kind_at", { x, y }) == from then
                host_mutate(x, y, into)
            end
        end
    end
end

-- =============================================================================
-- Portals: up to five per player, named, persisted, shown on everyone's G map.
-- =============================================================================

-- Every peer keeps its own copy of the (tiny) portal ledger so portal.lua can
-- build its travel panel without a round trip, and so the map markers are drawn
-- locally. Called on any change - there are at most PORTALS_PER_PLAYER entries
-- per player.
sync_portals = function()
    if not IS_HOST then return end
    run_network_function(name, "portals_ALL", { portals })
end

function portals_ALL(sender_id, list)
    -- Drop markers for portals that are gone before drawing the current set.
    for pid in pairs(portal_list) do
        delete_minimap_target("portal_" .. pid)
    end
    portal_list = {}
    for pid, entry in pairs(list or {}) do
        -- Tile coords crossed the Lua<->GDScript boundary as floats.
        local tx, ty = math.floor(entry.x), math.floor(entry.y)
        portal_list[pid] = { owner = entry.owner, x = tx, y = ty,
            label = entry.label or "Portal" }
        set_minimap_target({ name = "portal_" .. pid,
            world_position = map_to_local(Vector2(tx, ty)),
            text = portal_list[pid].label, icon_size = Vector2(7, 7),
            color = Color(0.55, 0.4, 0.95, 1) })
    end
end

function get_portal_list()
    return portal_list
end

spawn_portal = function(pid)
    local entry = portals[pid]
    if not entry then return end
    local world = map_to_local(Vector2(math.floor(entry.x), math.floor(entry.y)))
    portal_entities[pid] = spawn_entity_host({ t = "portal", p = world,
        owner = entry.owner, pid = pid, label = entry.label })
end

despawn_portal = function(pid)
    local entity = portal_entities[pid]
    if entity and entity ~= "" then destroy("", entity) end
    portal_entities[pid] = nil
end

-- HOST: called from user.lua when someone Interacts with a portal stone. This
-- owns the whole transaction - validation AND spending the stone - so there is
-- exactly one place where "has a slot free" and "still holds the stone" agree.
function host_place_portal(args)
    if not IS_HOST then return end
    local steam_id = args.steam_id
    local pid, slot = free_portal_id(steam_id)
    if pid == "" then
        run_network_function(steam_id, "toast_ALL",
            { "{all}" .. PORTALS_PER_PLAYER .. "{of_your_portals_are_standing}"
                .. "{walk_into_one_and_take_it_back_first}" }, steam_id)
        return
    end
    local x, y = math.floor(args.x), math.floor(args.y)
    if not run_function("-gen", "is_walkable", { x, y }) then return end
    if not run_function("-inv", "host_consume",
            { { steam_id = steam_id, item_id = PORTAL_ITEM, count = 1 } }) then
        return
    end
    -- Numbered by slot: five portals all called "Nick's Camp" would be five
    -- identical rows in everyone's travel panel and five identical map markers.
    local nickname = get_value("", steam_id, "nickname") or "Someone"
    portals[pid] = { owner = steam_id, x = x, y = y,
        label = nickname .. "{s_camp}" .. slot }
    spawn_portal(pid)
    sync_portals()
    save_world()
    local left = PORTALS_PER_PLAYER - portal_count(steam_id)
    run_network_function(steam_id, "toast_ALL",
        { "{portal_planted}" .. left .. "{placement}" .. (left == 1 and "" or "s")
            .. "{left}" }, steam_id)
    -- Let the owner name it right away (their peer only).
    run_network_function(name, "portal_name_prompt_ALL",
        { pid, portals[pid].label }, steam_id)
end

-- Owner's peer: a small panel to name the portal just planted.
function portal_name_prompt_ALL(sender_id, pid, default_label)
    if is_panel_exists(PORTAL_NAME_PANEL) then close_panel(PORTAL_NAME_PANEL) end
    typed_portal_pid = pid
    typed_portal_name = default_label
    create_panel({ name = PORTAL_NAME_PANEL, title ="{name_your_portal}",
        text ="{everyone_can_see_this_name_on_the_map_an}",
        set_time = false, close = true, resizable = false,
        minimum_size = Vector2(400, 220) })
    add_input_to_panel(PORTAL_NAME_PANEL, { entity_name = name,
        function_name = "on_portal_name_input", text ="{name}", default_value = default_label })
    add_button_to_panel(PORTAL_NAME_PANEL, { entity_name = name,
        function_name = "on_portal_name_confirm", text ="{save_name}",
        color = Color(0.3, 0.55, 0.35) })
end

function on_portal_name_input(args)
    typed_portal_name = tostring(args["{name}"] or "")
end

function on_portal_name_confirm(args)
    close_panel(PORTAL_NAME_PANEL)
    run_network_function(name, "portal_rename_HOST", { typed_portal_pid, typed_portal_name })
end

-- Client intent: rename ONE OF MY portals. The host is the one that checks the
-- portal is really the sender's, then trims and applies.
function portal_rename_HOST(sender_id, pid, label)
    if not IS_HOST then return end
    local entry = portals[tostring(pid or "")]
    if not entry or entry.owner ~= sender_id then return end
    label = tostring(label or ""):sub(1, 24)
    if label:match("^%s*$") then return end
    entry.label = label
    local entity = portal_entities[tostring(pid)]
    if entity and entity ~= "" then
        run_network_function(entity, "portal_label_ALL", { label })
    end
    sync_portals()
    save_world()
end

-- Client intent: take ONE OF MY portals back (the stone is returned, and the
-- slot it held is free for the next one).
function portal_remove_HOST(sender_id, pid)
    if not IS_HOST then return end
    pid = tostring(pid or "")
    local entry = portals[pid]
    if not entry or entry.owner ~= sender_id then return end
    despawn_portal(pid)
    portals[pid] = nil
    run_function("-inv", "host_add", { sender_id, PORTAL_ITEM, 1 })
    run_function("-inv", "host_sync", { sender_id })
    sync_portals()
    save_world()
end

-- Client intent: travel from wherever I am to some portal. The host owns the
-- destination table, so a client can only ever ask for a portal that really
-- exists - it cannot name its own coordinates.
function portal_travel_HOST(sender_id, target_pid)
    if not IS_HOST then return end
    local entry = portals[tostring(target_pid or "")]
    if not entry then return end
    if get_value("", sender_id, "is_dead") then return end
    local from = get_value("", sender_id, "position")
    local world = map_to_local(Vector2(math.floor(entry.x), math.floor(entry.y)))
    local to = Vector2(world.x, world.y + PORTAL_ARRIVE_OFFSET)
    change_instantly({ entity_name = sender_id, position = to, linear_velocity = Vector2(0, 0) })
    run_network_function(sender_id, "toast_ALL", { "{arrived_at}" .. entry.label .. "." }, sender_id)
    -- Departure AND arrival, so a friend standing at either end of the trip
    -- hears it too, not just the traveller. No existing broadcast covers this
    -- (toast_ALL above only reaches sender_id), hence the one new message.
    if from then
        run_network_function(name, "teleport_fx_ALL", { from.x, from.y, to.x, to.y })
    end
end

local TELEPORT_SFX_DISTANCE = 360

function teleport_fx_ALL(sender_id, x1, y1, x2, y2)
    set_audio({ stream_path = "teleport", is_2d = true, position = Vector2(x1, y1),
        max_distance = TELEPORT_SFX_DISTANCE, volume = -3, random_pitch = 0.08 })
    set_audio({ stream_path = "teleport", is_2d = true, position = Vector2(x2, y2),
        max_distance = TELEPORT_SFX_DISTANCE, volume = -3, random_pitch = 0.08 })
end

-- A player left for good / the world was wiped: their portals go with them.
local function clear_all_portals()
    for pid in pairs(portals) do despawn_portal(pid) end
    portals = {}
    sync_portals()
end

-- =============================================================================
-- Enemies.
-- =============================================================================

-- Enemy hp/damage grow with the day and then hold, exactly like every other
-- ramped number (the old hard 3.0 ceiling is gone: ramp_day() already freezes
-- the curve, and it froze at the boss day instead of two days after it).
local function scaled(base, per_day)
    return math.floor(base * (1 + per_day * (ramp_day() - 1)))
end

function spawn_enemy(etype, pos, opts)
    local def = ENEMY_TYPES[etype]
    opts = opts or {}
    local hp = opts.fixed and math.floor(def.hp * 1.5) or scaled(def.hp, HP_SCALE_PER_DAY)
    local dmg = opts.fixed and math.floor(def.dmg * 1.2) or scaled(def.dmg, DMG_SCALE_PER_DAY)
    spawn_entity_host({ t = "enemy", p = pos, etype = etype,
        image = def.image, size = def.size, hp = hp, dmg = dmg, speed = def.speed,
        windup = def.windup, cooldown = def.cooldown, reach = def.reach,
        ranged = def.ranged or false, shoot_cd = def.shoot_cd or 0,
        bolt_color = def.bolt_color or Color(0, 0, 0, 0), -- transparent = "use the default"
        phasing = def.phasing or false,
        tint = def.tint, is_night_npc = not opts.fixed, dungeon_id = opts.dungeon_id or "" })
end

-- Today's weight for one spawn-table entry: its base plus one 'weight_per_day'
-- for every day survived since it unlocked, frozen once the ramp freezes.
local function spawn_weight(entry)
    if day < entry.min_day then return 0 end
    local days_unlocked = math.max(ramp_day() - entry.min_day, 0)
    return entry.weight + (entry.weight_per_day or 0) * days_unlocked
end

-- Weighted pick out of NIGHT_SPAWN_TABLE, restricted to what the current day
-- has unlocked.
local function roll_night_enemy()
    local total = 0
    for _, entry in ipairs(NIGHT_SPAWN_TABLE) do
        total = total + spawn_weight(entry)
    end
    if total <= 0 then return "zombie" end
    local pick = math.random() * total
    for _, entry in ipairs(NIGHT_SPAWN_TABLE) do
        pick = pick - spawn_weight(entry)
        if pick <= 0 then return entry.etype end
    end
    return "zombie"
end

function spawn_zombie_wave()
    local users = get_entity_names_by_tag("alive")
    if #users == 0 then return end
    local cap = math.min(ZOMBIES_PER_PLAYER_BASE + ramp_day(), ZOMBIES_PER_PLAYER_MAX) * #users
    local current = #get_entity_names_by_tag("night_npc")
    -- Later days also try harder per wave, so the cap is actually reached
    -- instead of only being approached two enemies at a time.
    local attempts = (day >= SPAWNS_PER_WAVE_LATE_DAY) and SPAWNS_PER_WAVE_LATE or SPAWNS_PER_WAVE
    for _, user_name in ipairs(users) do
        if current >= cap then break end
        local pos = get_value("", user_name, "position")
        if pos then
            for _ = 1, attempts do
                local spot = find_walkable_near(pos)
                if spot and current < cap then
                    spawn_enemy(roll_night_enemy(), spot)
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
            elseif poi.type == "jug" then
                spawn_entity_host({ t = "breakable", p = world,
                    image = "items/10x10_jug", size = 12, dungeon_id = poi.id })
            else
                spawn_enemy(poi.type, world, { fixed = true, dungeon_id = poi.id })
            end
        end
    end
end

function mark_dungeon_done(poi_id)
    if poi_id ~= "" then dungeon_done[poi_id] = true end
end

local NPC_DEATH_SFX_DISTANCE = 360

-- Every peer's own thud: the entity destruction itself already replicates
-- (enemy.lua/critter.lua are DYNAMIC), but that is an engine-level RPC with no
-- Lua callback on the receiving end - nothing else here reaches every peer, so
-- this is the one broadcast that does.
function npc_death_fx_ALL(sender_id, x, y)
    set_audio({ stream_path = "dead", is_2d = true, position = Vector2(x, y),
        max_distance = NPC_DEATH_SFX_DISTANCE, volume = -5, random_pitch = 0.1 })
end

-- Called by enemy.lua and critter.lua when something dies. 'x'/'y' are nil for
-- a death whose position could not be read (already gone) - silent then, same
-- as any other fx call that skips a message it has nothing to place.
function on_enemy_killed(args)
    local killer, dungeon_id = args.killer, args.dungeon_id
    if killer and killer ~= "" and has_tag(killer, "user") then
        add_stat(killer, "kills", 1)
    end
    mark_dungeon_done(dungeon_id)
    if args.x and args.y then
        run_network_function(name, "npc_death_fx_ALL", { args.x, args.y })
    end
end

-- =============================================================================
-- Boss: shows up at nightfall of day 7, dies to confetti and statistics.
-- =============================================================================

function spawn_boss()
    boss_active = true
    boss_lives = {}
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        boss_lives[user_name] = BOSS_MAX_LIVES
    end
    local arena_x = get_value("", "-gen", "BOSS_ARENA_X") or 0
    local arena_y = get_value("", "-gen", "BOSS_ARENA_Y") or -26
    -- HP scales directly with the party size (2 players = 2x, 3 = 3x, ...) so
    -- the fight stays proportionally as tough; boss damage never scales.
    local players = math.max(#get_entity_names_by_tag("user"), 1)
    local hp = math.floor(BOSS_HP_BASE * players)
    local world = map_to_local(Vector2(arena_x, arena_y))
    boss_entity = spawn_entity_host({ t = "boss", p = world, hp = hp })
    announce("{guardian_has_risen}"
        .. BOSS_MAX_LIVES .. "{spawn_rights_each_before_the_fight_is_lo}")
    run_network_function(name, "boss_nav_ALL", { boss_entity })
end

function boss_nav_ALL(sender_id, boss_name)
    nav_icon_name = set_navigation_icon({ target_name = boss_name, name = "nav_mbl_boss",
        text ="{boss}", color = Color(228 / 255, 59 / 255, 68 / 255, 1),
        is_show_distance = true })
end

function on_boss_defeated(args)
    if not IS_HOST then return end
    boss_active = false
    boss_defeated = true
    local payload = { players = {}, x = args.x, y = args.y }
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
    -- Same "dead" sound every other npc gets, just from the guardian itself -
    -- the confetti below is a separate, purely celebratory local effect.
    if payload.x and payload.y then
        set_audio({ stream_path = "dead", is_2d = true, position = Vector2(payload.x, payload.y),
            max_distance = NPC_DEATH_SFX_DISTANCE, volume = -2, random_pitch = 0.06 })
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
    local title = victory and "{victory_guardian_fallen}" or "Statistics"
    local body = victory
        and "{congratulations_survived}"
        or "{the_story_so_far}"
    local panel_name = create_panel({ name = "_mbl_stats", title = title, text = body,
        minimum_size = Vector2(640, 420), is_scrollable = true, resizable = true,
        close = true, set_time = false })
    local header_color = Color(38 / 255, 92 / 255, 66 / 255, 0.95)  -- Moss
    local cell_color = Color(58 / 255, 68 / 255, 102 / 255, 0.9)    -- Steel
    local table_data = {}
    local columns = { "Player", "Trees", "Rocks", "Kills", "{damage_dealt}",
        "{damage_taken}", "Deaths", "Crafts" }
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

-- The fight is only lost once EVERY player still in the party has burned
-- through all of their own BOSS_MAX_LIVES spawn rights - each player's lives
-- are tracked separately in boss_lives, so one person running out first must
-- not end the run for teammates who still have rights left.
local function all_boss_lives_spent()
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        if (boss_lives[user_name] or BOSS_MAX_LIVES) > 0 then return false end
    end
    return true
end

-- Returns { boss_death, lives_left } so the dying player's own client can
-- append "spawn rights left" to the death message it already shows (user.lua
-- died_ALL). A death outside the boss fight never touches boss_lives - only
-- the fight itself is limited, ordinary respawns stay unlimited.
function on_player_died(args)
    if not IS_HOST then return end
    local steam_id = args.steam_id
    add_stat(steam_id, "deaths", 1)
    run_function("-inv", "host_scatter", { steam_id })
    announce((get_value("", steam_id, "nickname") or "Someone")
        .. "{died_their_pack_scattered_where_they_fel}")

    local boss_death = boss_active
    local lives_left = -1
    if boss_death then
        local remaining = (boss_lives[steam_id] or BOSS_MAX_LIVES) - 1
        remaining = math.max(remaining, 0)
        boss_lives[steam_id] = remaining
        lives_left = remaining
        if remaining <= 0 and all_boss_lives_spent() then
            -- Give the "last spawn right" death message a moment on screen
            -- before the reset panel takes over.
            start_timer({ timer_id = "boss_wipe", entity_name = name,
                function_name = "trigger_boss_wipe", wait_time = 1.5, duration = 1.5 })
        end
    end
    return { boss_death = boss_death, lives_left = lives_left }
end

-- A player burned through all their boss-fight spawn rights: the whole run
-- is over. Wipe the map/NPCs/inventory/save back to a blank slate and let
-- the host pick a new seed, same as a brand-new install.
function trigger_boss_wipe()
    if not IS_HOST then return end
    boss_active = false
    boss_defeated = false
    boss_entity = ""
    boss_lives = {}
    destroy_entities_by_tag("npc")
    destroy_entities_by_tag("ground_item")
    run_function("-wild", "host_reset") -- the entities are gone; drop the ledger too
    stats = {}
    pending_growth = {}
    breaks = {}
    dungeon_done = {}
    saved_positions = {}
    clear_all_portals()
    day = 1
    t = 0
    is_night = false
    seed_value = 0 -- host_boot's "no world yet" sentinel; also gates late-joiner sync
    save_json(SAVE_PATH, {})
    run_function("-inv", "load_save_data", { { inv = {}, held = {} } })
    for _, user_name in ipairs(get_entity_names_by_tag("user")) do
        run_function("-inv", "host_sync_all_to", { user_name })
        local spawn = map_to_local(Vector2(0, 0))
        run_function(user_name, "host_respawn_at", { spawn.x, spawn.y })
    end
    run_network_function(name, "boss_wipe_ALL", {})
end

-- Every peer sees the "you lost the run" panel; only the host then gets the
-- seed-setup panel on top of it once they dismiss this one.
function boss_wipe_ALL(sender_id)
    -- Force the world to actually regenerate even if the host ends up
    -- re-picking the same seed - see force_wipe()'s comment in worldgen.lua.
    run_function("-gen", "force_wipe")
    if nav_icon_name ~= "" then
        destroy("", nav_icon_name)
        nav_icon_name = ""
    end
    if is_panel_exists(RESET_PANEL) then return end
    create_panel({ name = RESET_PANEL, title ="{the_guardian_was_too_strong}",
        text ="{every_one_of_your_spawn_rights_against_t}"
            .. "{the_world_resets_a_new_journey_begins}",
        set_time = false, close = false, resizable = false, minimum_size = Vector2(420, 200) })
    add_button_to_panel(RESET_PANEL, { entity_name = name, function_name = "on_wipe_ack",
        text ="{continue}", color = Color(0.6, 0.3, 0.3) })
end

function on_wipe_ack(args)
    close_panel(RESET_PANEL)
    if IS_HOST then show_seed_setup() end
end

-- =============================================================================
-- Chat commands.
-- =============================================================================

function cmd_friendlyfire()
    if not IS_HOST then
        add_to_chat("{only_the_host_can_toggle_friendly_fire}", false)
        return
    end
    friendly_fire = not friendly_fire
    run_network_function(name, "ff_ALL", { friendly_fire })
end

function ff_ALL(sender_id, on)
    friendly_fire = on
    announce_local(on and "{friendly_fire_on}"
        or "{friendly_fire_off}")
end

function cmd_seed()
    add_to_chat("{world_seed}" .. tostring(seed_value), false)
end

function cmd_stats()
    run_network_function(name, "stats_HOST")
end

function cmd_newworld()
    if not IS_HOST then
        add_to_chat("{only_the_host_can_start_a_new_world}", false)
        return
    end
    local new_seed = get_os_time_unix() % 1000000007
    destroy_entities_by_tag("npc")
    destroy_entities_by_tag("ground_item")
    run_function("-wild", "host_reset") -- the entities are gone; drop the ledger too
    stats = {}
    pending_growth = {}
    breaks = {}
    dungeon_done = {}
    saved_positions = {}
    boss_lives = {} -- next fight's spawn_boss() rebuilds this fresh, per player
    clear_all_portals()
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
    -- A new seed moves the dungeon's door and wipes every generated chunk, so
    -- the old marker is both stale and un-earned: drop it and start looking again.
    dungeon_marked = false
    delete_minimap_target(DUNGEON_MARKER)
    apply_phase_visuals()
    refresh_clock()
    announce_local("{brand_new_world}")
end

-- Testing shortcut: skip straight to day 7 nightfall (reuses begin_night(),
-- so the sync/visuals/spawn path is identical to the real thing).
function cmd_testboss()
    if not IS_HOST then
        add_to_chat("{only_the_host_can_trigger_the_boss_test}", false)
        return
    end
    if boss_active then
        add_to_chat("{the_boss_is_already_active}", false)
        return
    end
    day = BOSS_DAY
    boss_defeated = false
    begin_night()
    -- Gear everyone up for the fight (user entities are named by steam_id).
    for _, steam_id in ipairs(get_entity_names_by_tag("user")) do
        run_function("-inv", "host_add", { steam_id, "bow", 1 })
        run_function("-inv", "host_add", { steam_id, "arrow", 2000 })
        run_function("-inv", "host_sync", { steam_id })
    end
end

-- Testing shortcut: a full set of everything in the registry, for whoever is
-- playing. Host only and host-applied, like every other inventory change - the
-- point is to skip the grind while testing recipes and gadgets, not to open a
-- way for a client to ask the host for free items.
function cmd_testitems()
    if not IS_HOST then
        add_to_chat("{only_the_host_can_hand_out_the_test_item}", false)
        return
    end
    local item_ids = run_function("-items", "get_all_item_ids")
    for _, steam_id in ipairs(get_entity_names_by_tag("user")) do
        for _, item_id in ipairs(item_ids) do
            run_function("-inv", "host_add", { steam_id, item_id, TEST_ITEM_COUNT })
        end
        run_function("-inv", "host_sync", { steam_id })
    end
    announce("{test_items_handed_out}" .. #item_ids .. "{kinds_x}" .. TEST_ITEM_COUNT .. "{each}")
end

-- Every peer reveals its OWN map: the island is a pure function of the seed, so
-- each machine can paint the tiles itself and nothing has to be sent anywhere.
-- The tiles ARE the map (the engine builds the minimap image straight off this
-- peer's TileMapLayer), so revealing means painting them - just in the
-- background, behind whatever land players are actually walking into.
function cmd_openallmap()
    if not run_function("-gen", "is_seed_ready") then
        add_to_chat("{the_island_has_not_been_generated_yet}", false)
        return
    end
    if run_function("-gen", "is_revealing") then
        add_to_chat("{already_drawing_the_rest_of_the_island_g}", false)
        return
    end
    local pending = run_function("-gen", "reveal_all")
    if pending == 0 then
        add_to_chat("{your_map_already_covers_the_whole_island}", false)
        return
    end
    add_to_chat("{charting_the_island}" .. math.floor(pending)
        .. "{chunks_to_go_open_the_map_g_and_watch_it}", false)
end

add_command(name, "cmd_friendlyfire", "friendlyfire",
    "{cmd_friendly_fire_desc}", true)
add_command(name, "cmd_newworld", "newworld",
    "{cmd_new_world_desc}", true)
add_command(name, "cmd_seed", "seed", "{show_the_current_world_seed}", true)
add_command(name, "cmd_stats", "stats", "{show_the_scoreboard_so_far}", true)
add_command(name, "cmd_testboss", "testboss",
    "{cmd_boss_desc}", true)
add_command(name, "cmd_testitems", "testitems",
    "{cmd_giveall_desc}", true)
add_command(name, "cmd_openallmap", "openallmap",
    "{cmd_reveal_desc}", true)

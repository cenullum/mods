lock_rotation = true
linear_damp = 4
friction = 0 -- slide along walls instead of sticking

-- =============================================================================
-- MineBlockLand - player entity (runs on every peer for every player).
--
-- The body NEVER rotates (lock_rotation; writing the physics rotation every
-- frame fought the sync and made movement stutter + the nickname wobble). The
-- local player's facing dot is moved around the body instead - pure local
-- visuals - and the held item is drawn on top of the body for everyone.
--
-- Client sends intents only (use tool / shoot / interact); the HOST copy of
-- this same script validates cooldown + stamina and applies the result. The
-- local copy runs the same stamina rules as prediction for the HUD.
-- =============================================================================

add_tag(name, "user")
add_tag(name, "alive")

-- Tile kind ids (each entity has its own Lua env; must match worldgen.lua).
local K_GRASS = 1
local K_SAND = 2
local K_TREE = 3
local K_FARM = 4
local K_FARM_SEEDED = 5
local K_FARM_GROWN = 6
local K_SEA = 7
local K_DEEP = 8
local K_STONE = 9
local K_SAPLING = 11
local K_CACTUS, K_PALM, K_FLOWER = 12, 13, 14
local K_WOOD_BLOCK = 15

-- Local-only "tile under the mouse" highlight (each peer sees its own).
local HL_NAME = "mbl_tilehl"
local hl_tile_x, hl_tile_y = 99999, 99999
local hl_actionable = false
local hl_shown = false

local BODY_PX = 16
local BODY_RADIUS = 7
local DOT_ORBIT = 11           -- how far the aim dot / held item sits from the body
local BASE_SPEED = 18
local SEA_SPEED = 8            -- wading through shallow water is slow
local RIPPLE_STEP = 12         -- world px of wading between splash rings
local RIPPLE_FOOT_Y = 6        -- the ring sits at the feet, not the chest
local BASE_MAX_HP = 100
local HEART_CONTAINER_HP = 20  -- permanent max-HP gain per Heart Container used
local MAX_STAMINA = 100
local STAMINA_REGEN = 14       -- per second, after a short delay
local STAMINA_REGEN_DELAY = 1.2
local STAMINA_TOLERANCE = 3    -- host forgiveness for prediction drift
local REACH = 44               -- how far you can chop/mine/farm (pixels)
local MELEE_WINDUP = 0.25
local MELEE_HURTBOX_SCALE = 1.5 -- close-range swings hit a bigger zone than the item's base shape
local RESPAWN_SECONDS = 2.0
local BOMB_THROW_SPEED = 90    -- lobbed just past arm's length, then it skids
local CAMERA_ZOOM = 2.6

-- Grapple hook. The body has linear_damp = 4 (see the top of this file), and a
-- damped body coasts v0/damp pixels, so aiming for a given distance is just
-- dist * damp - no tuning by feel, and the pull lands you a body's width short
-- of the wall you hooked instead of inside it.
local GRAPPLE_RANGE = 160
local GRAPPLE_STOP_SHORT = 10
local GRAPPLE_MAX_SPEED = 900
local GRAPPLE_LINE_SECONDS = 0.25
local GRAPPLE_LINE_COLOR = Color(234 / 255, 212 / 255, 170 / 255, 0.9) -- Birch, same as the arrow tracer
local BOOTS_SPEED_MULT = 1.2
local last_grapple = -10

-- Mount & pet. Both are pure images hung off the player body - no extra entity,
-- no physics, no AI. A mount also changes how fast you move, a pet is cosmetic
-- only.
--
-- Both sit ABOVE the body (z 2) and therefore above loose critters and enemies,
-- which are z 2 as well: at z 1 the mount used to disappear behind any animal
-- that happened to walk over the same spot, so the thing you were riding was
-- hidden by the thing you were not.
local SADDLE_REACH = 34
local MOUNT_SIZE = 20
local MOUNT_Z = 3
local PET_Z = 4
local MOUNT_OFFSET = Vector2(0, 4)
local MOUNT_SPEED_MIN, MOUNT_SPEED_MAX = 0.7, 1.5
local PET_SIZE = 9
local PET_OFFSET = Vector2(12, 2)
-- Declared up here with the rest of the state: speed_check() reads it well
-- before the mount section further down would have introduced it.
local mount_speed_mult = 1.0

-- Worn accessory: one more image hung off the body, same idea as mount/pet,
-- but its slot lives in -inv (see worn_ALL) instead of here - a hat/boots
-- has to survive this entity being destroyed and recreated on relog, and the
-- inventory already owns that lifetime for held items too.
local WORN_SIZE = 13
local WORN_Z = 5 -- above mount/pet, below the nickname/buff badges
-- Each wearable sits where it actually reads as worn: a hat on the head, boots
-- and the trophy sock down at the feet. Only one can ever be worn at once, so
-- there is never a clash to resolve here.
local WORN_OFFSETS = {
    witch_hat = Vector2(0, -10),
    swift_boots = Vector2(0, 7),
    sock = Vector2(0, 7),
}

-- Fishing. Cast at water, wait an unpredictable moment, then Interact again
-- inside a short window. The host owns the whole state machine; every peer just
-- draws the line. Casts are tagged with a STRING id so a stale timer from an
-- abandoned cast can never resolve a newer one (ids crossing the
-- Lua<->GDScript boundary come back as floats, hence tostring).
local FISH_WAIT_MIN, FISH_WAIT_MAX = 2.0, 6.0
local FISH_WINDOW = 1.5
local FISH_LINE_IDLE = Color(234 / 255, 212 / 255, 170 / 255, 0.8) -- Birch
local FISH_LINE_BITE = Color(254 / 255, 231 / 255, 97 / 255, 1)    -- Light
local fish_cast = ""        -- host: id of the cast in flight ("" = not fishing)
local fish_bite_until = -1  -- host: clock time the catch window closes
local fish_counter = 0
local DEAD_TINT = Color(0.4, 0.4, 0.5, 0.5)

-- Local "you got hit" feedback: quick shake + a red flash that fades back out
-- on its own. flash_vignette is a SEPARATE overlay from -gm's set_vignette
-- calls (the day/night darkness), so this never disturbs it.
local DAMAGE_FEEDBACK_SECONDS = 0.25
local DAMAGE_SHAKE_MIN = 3
local DAMAGE_SHAKE_PER_HP = 0.6
local DAMAGE_SHAKE_MAX = 14
local DAMAGE_FLASH_COLOR = Color(0.75, 0.05, 0.05, 0.85)

-- Panels that should swallow the attack input while open (E's inventory/craft
-- pair, and the G minimap) so clicking through them doesn't also swing.
local BLOCKING_PANELS = { "_mbl_inventory", "_mbl_crafting", "_mbl_craft_qty", "_mbl_map_panel" }

local function is_action_blocked()
    for _, panel_name in ipairs(BLOCKING_PANELS) do
        if is_panel_exists(panel_name) then return true end
    end
    return false
end

-- State (the HOST copy of each player is the authority; the IS_LOCAL copy
-- predicts stamina so the HUD feels instant).
hp = BASE_MAX_HP
max_hp = BASE_MAX_HP  -- raised for good by Heart Containers; persisted by -inv
mount = ""            -- species key of what you are riding ("" = on foot)
pet = ""              -- species key of the charm's companion ("" = none)
stamina = MAX_STAMINA
held_item = ""
is_dead = false
local held_def = nil           -- cached use-definition of the held item
local clock = 0                -- monotonic sub-second clock (sums _process delta)
local last_use = -10
local last_spend = -10
local prev_inputs = { use = false, interact = false, inv = false, cycle = false, map = false, drop = false }
local current_speed = BASE_SPEED
local shown_stamina = -1
local last_dot_angle = 999

-- Potion buffs. The host decides when one starts and broadcasts the DURATION;
-- every peer then counts it down against its own 'clock', so the icon above
-- your head and the effect itself expire together without any further traffic.
-- Gameplay is still host-authoritative: strength is applied in use_HOST and
-- regen ticks host-side. Speed is the one exception - speed_check is a local
-- visual/movement concern already, so it reads the local copy.
local BUFF_SECONDS = 20
local BUFF_SPEED_MULT = 1.5
local BUFF_STRENGTH_MULT = 1.5
local BUFF_REGEN_PER_TICK = 3
local BUFF_TICK_SECONDS = 0.5
local BUFF_ICONS = {
    speed = "items/15x15_speed_potion",
    strength = "items/15x15_strength_potion",
    regen = "items/15x15_regen_potion",
}
local BUFF_ORDER = { "speed", "strength", "regen" }
local buff_until = { speed = -1, strength = -1, regen = -1 }
local buff_shown = { speed = false, strength = false, regen = false }
local last_regen_tick = 0

local ripple_from = nil        -- last position a splash ring was left at
local ripple_ready = false     -- particle template built on the first ring

-- --- visuals (identical on every peer) ---------------------------------------

set_collision({ parent_name = name, name = "col", shape = "circle", size = BODY_RADIUS,
    collision_layer = { 2 }, collision_mask = { 1 } }) -- tiles only: players never push each other
set_value("", name, "hit_radius", BODY_RADIUS) -- read by -combat's melee hit test (friendly fire)

-- Default icon until Steam delivers the avatar (see _on_loaded_avatar).
body_image = set_image({ parent_name = name, name = "body", z_index = 2 })
set_image_pixel(name, "body", Vector2(BODY_PX, BODY_PX))

-- Facing dot orbiting the body. It exists on EVERY peer, because it doubles as
-- the held-item sprite (see set_held_visual): your own copy is aimed per frame
-- from your own mouse, everyone else's is aimed by the host's aim_ALL relay.
-- Shown for everybody (fists count as "held item" too), not just the local
-- player - otherwise an empty hand silently vanished on other peers' screens.
set_image({ parent_name = name, name = "dot", image_path = "hand",
    position = Vector2(DOT_ORBIT, 0), scale = Vector2(16, 16), z_index = 4,
    modulate = Color(1, 1, 1, 0.9), visible = true })

-- Crisp world-space nickname: big font_size drawn small via scale
-- (48 * 0.125 = old size 6, but sharp) - set once, no per-frame work.
nick_label = set_label({ parent_name = name, name = "nick", text = nickname,
    position = Vector2(-64, -22), size = Vector2(1024, 96),
    scale = Vector2(0.125, 0.125), horizontal_alignment = 1, font_size = 48,
    outline_size = 16, outline_color = Color(0, 0, 0, 1), z_index = 10 })

-- Every player shows up on the ready-made minimap panel (the engine tracks the
-- position and redraws the marker; targets are local, so the host's map
-- permission is all that gates it). Your own dot is blue (not green, so it
-- doesn't blend into the grassland tiles the minimap also renders).
set_minimap_target({ name = "mm_" .. name, entity_name = name,
    text = nickname, icon_size = Vector2(7, 7),
    color = IS_LOCAL and Color(0.25, 0.55, 0.95, 1) or Color(0.9, 0.9, 0.95, 1) })

-- Buff badges float above the nickname, hidden until a potion is drunk. Built
-- once on EVERY peer (not just the local one) so you can see at a glance which
-- of your friends just chugged something.
for index, kind in ipairs(BUFF_ORDER) do
    set_image({ parent_name = name, name = "buff_" .. kind, image_path = BUFF_ICONS[kind],
        position = Vector2((index - 2) * 9, -30), scale = Vector2(8, 8),
        visible = false, z_index = 6 })
end

local function has_buff(kind)
    return clock < buff_until[kind]
end

-- =============================================================================

function _on_loaded_avatar(steam_id)
    if steam_id ~= name then return end
    set_image({ parent_name = name, name = "body", image_path = name, z_index = 2 })
    set_image_pixel(name, "body", Vector2(BODY_PX, BODY_PX))
end

-- Movement speed is NOT a local-only concern: the host simulates every player's
-- body and the network corrects each client toward that simulation, so a speed
-- only the owner knew about left the host's copy on the engine default (15) and
-- dragged every client back below BASE_SPEED - which is why the host used to run
-- visibly faster than everyone else. Set on every peer, kept in step by
-- speed_check() below.
set_value("", name, "speed", BASE_SPEED)

if IS_LOCAL then
    set_camera_target(name)
    set_camera_zoom(Vector2(CAMERA_ZOOM, CAMERA_ZOOM))
    -- Standalone world-space highlight (16x16, matches a tile). Hidden until the
    -- mouse is over a tile we can act on and it is in reach. z 1 = above tiles,
    -- below player bodies (z 2). Not networked: only this machine ever sees it.
    set_image({ name = HL_NAME, image_path = "choosed_tile", z_index = 1,
        modulate = Color(1, 1, 1, 0.7), visible = false })
end

-- Held item shown on the aim dot (orbits the body toward the mouse); -inv
-- broadcasts every change to every peer, so this runs for EVERY player and you
-- can see what your friends are carrying. Which way it points comes from
-- aim_ALL for other players and from your own mouse for yourself.
function set_held_visual(item_id)
    held_item = item_id
    held_def = run_function("-items", "get_use_def", { item_id })
    if item_id == "" then
        -- Fists: the aim dot goes back to being a plain hand marker. Shown for
        -- everybody, same as a held item - an empty hand is still a visible
        -- state, not just your own aiming aid.
        set_image({ parent_name = name, name = "dot", image_path = "hand",
            scale = Vector2(16, 16), modulate = Color(1, 1, 1, 0.9),
            visible = true })
    else
        local item = run_function("-items", "get_item", { item_id })
        -- Holding something: the aim dot shows the held item instead of
        -- the dot, so it looks like the item itself points at the mouse.
        -- No scale override: shows at the item's own native texture size,
        -- same as everywhere else items are drawn.
        set_image({ parent_name = name, name = "dot", image_path = item.image,
            modulate = Color(1, 1, 1, 1), visible = true })
    end
    if IS_LOCAL then
        local held_name = (item_id == "") and "Fists"
            or run_function("-items", "get_item", { item_id }).name
        set_label({ name = "_mbl_held", text ="{holding}" .. held_name })
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

-- Snaps the highlight to the tile under the mouse; shown only when that tile is
-- something we can act on (tree/rock/grass/farmland/sapling) AND it is within
-- reach. kind_at is only queried when the hovered tile actually changes.
function update_tile_highlight(aim, live_pos)
    local tile = local_to_map(aim)
    local tx, ty = math.floor(tile.x), math.floor(tile.y)
    local center = map_to_local(Vector2(tx, ty))
    if tx ~= hl_tile_x or ty ~= hl_tile_y then
        hl_tile_x, hl_tile_y = tx, ty
        local kind = run_function("-gen", "kind_at", { tx, ty })
        hl_actionable = kind == K_TREE or kind == K_STONE or kind == K_GRASS or kind == K_SAND
            or kind == K_FARM or kind == K_FARM_SEEDED or kind == K_FARM_GROWN or kind == K_SAPLING
            or kind == K_CACTUS or kind == K_PALM or kind == K_FLOWER or kind == K_WOOD_BLOCK
        set_image({ name = HL_NAME, position = center })
    end
    local show = hl_actionable and distance_to(live_pos, center) <= REACH
    if show ~= hl_shown then
        hl_shown = show
        set_image({ name = HL_NAME, visible = show })
    end
end

-- =============================================================================
-- Aim relay: everybody sees which way everybody else is pointing.
--
-- Same pattern as Hook Up / Operation Detonate / Crazy Eights: only the HOST is
-- ever handed another player's raw inputs (a client running _process for
-- somebody else's entity gets its OWN inputs, not theirs), so the host relays
-- the RAW stick_2 world position - not a pre-computed angle. Each receiving
-- peer then works out the orbit angle itself from ITS OWN copy of the target's
-- position, exactly like the local player already does a few lines below - so
-- the maths never depends on the host's position sample staying in lockstep
-- with what a given peer's own synced copy shows. Throttled by squared
-- distance, same threshold Operation Detonate/Crazy Eights use.
-- =============================================================================

local last_sent_aim = Vector2(-999999, -999999)

local function relay_aim(inputs)
    local aim = inputs.stick_2
    if not aim then return end
    local dx = aim.x - last_sent_aim.x
    local dy = aim.y - last_sent_aim.y
    if dx * dx + dy * dy <= 4 then return end
    last_sent_aim = aim
    run_network_function(name, "aim_ALL", { aim })
end

function aim_ALL(sender_id, aim)
    if IS_LOCAL then return end -- our own dot is placed every frame, with no latency
    local live_pos = get_value("", name, "position")
    if not live_pos then return end
    local angle = math.atan(aim.y - live_pos.y, aim.x - live_pos.x)
    set_image({ parent_name = name, name = "dot",
        position = Vector2(math.cos(angle) * DOT_ORBIT, math.sin(angle) * DOT_ORBIT) })
end

-- =============================================================================
-- Per-frame: facing, input edges, HUD.
-- =============================================================================

function _process(delta, inputs)
    clock = clock + delta
    if IS_HOST or IS_LOCAL then
        regen_stamina(delta)
    end
    water_ripple() -- every peer, every player: purely local, see the function
    if IS_HOST and not is_dead then relay_aim(inputs) end

    if not IS_LOCAL then return nil end

    -- Facing dot follows the aim (local visual only - never touch the physics
    -- rotation, that fights the network sync and stutters the movement).
    local live_pos = get_value("", name, "position")
    if live_pos and not is_dead then
        local aim = inputs.stick_2
        local aim_angle = math.atan(aim.y - live_pos.y, aim.x - live_pos.x)
        if math.abs(aim_angle - last_dot_angle) > 0.03 then
            last_dot_angle = aim_angle
            set_image({ parent_name = name, name = "dot",
                position = Vector2(math.cos(aim_angle) * DOT_ORBIT,
                    math.sin(aim_angle) * DOT_ORBIT) })
        end
        update_tile_highlight(Vector2(aim.x, aim.y), live_pos)
    elseif hl_shown then
        hl_shown = false
        set_image({ name = HL_NAME, visible = false })
    end

    -- A panel (inventory/craft/map) eats LMB entirely - clicking a button
    -- behind it must never also swing, as if the key was never pressed.
    if is_action_blocked() then
        inputs.key_12 = false
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
    if inputs.key_11 and not prev_inputs.map then
        toggle_map()
    end
    if inputs.key_7 and not prev_inputs.drop and not is_dead and held_item ~= "" then
        run_network_function("-inv", "drop_HOST", { held_item, 1 })
    end
    prev_inputs.interact = inputs.key_9
    prev_inputs.inv = inputs.key_6
    prev_inputs.cycle = inputs.key_5
    prev_inputs.map = inputs.key_11
    prev_inputs.drop = inputs.key_7

    if math.floor(stamina) ~= shown_stamina then
        shown_stamina = math.floor(stamina)
        set_progress_bar({ name = "_mbl_stamina", value = shown_stamina })
    end
    return nil
end

local MAP_PANEL = "_mbl_map_panel"

-- G toggles the ready-made minimap panel (each peer renders its own explored
-- tiles; the engine only allows it once the host called set_minimap(true)).
function toggle_map()
    if is_panel_exists(MAP_PANEL) then
        close_panel(MAP_PANEL)
        return
    end
    if get_minimap() == "" then
        run_function("-gm", "announce_local", { "{map_not_available}" })
        return
    end
    create_minimap_panel({ panel_name = MAP_PANEL, title ="{island_map}",
        lock_target = "mm_" .. name })
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
--
-- Runs on the HOST copy of every player as well as on your own. The host is the
-- authority the network drags everyone toward, so if only the owner applied the
-- water/boots/buff/mount modifiers the host would keep simulating that body at
-- BASE_SPEED and fight the owner's own slowdown or speed-up every packet.
function speed_check()
    if not IS_HOST and not IS_LOCAL then return end
    local live_pos = get_value("", name, "position")
    if not live_pos then return end
    local tile = local_to_map(live_pos)
    local kind = run_function("-gen", "kind_at", { math.floor(tile.x), math.floor(tile.y) })
    local wanted = (kind == K_SEA) and SEA_SPEED or BASE_SPEED -- K_SEA: local mirror above
    -- Swift Boots only help while actually worn (see -inv's worn slot). The host
    -- reads the authoritative table; the wearer's own peer only has its local
    -- mirror, which is the same trust level as my_inv and good enough there.
    local my_worn
    if IS_HOST then
        my_worn = run_function("-inv", "get_worn", { name }) or ""
    else
        my_worn = get_value("", "-inv", "my_worn") or ""
    end
    if my_worn == "swift_boots" then wanted = wanted * BOOTS_SPEED_MULT end
    if has_buff("speed") then wanted = wanted * BUFF_SPEED_MULT end
    wanted = wanted * mount_speed_mult
    if wanted ~= current_speed then
        current_speed = wanted
        set_value("", name, "speed", wanted)
    end
end

start_timer({ timer_id = "speed" .. name, entity_name = name,
    function_name = "speed_check", wait_time = 0.25 })

-- Leaves a spreading ring behind anyone wading through shallow water. Unlike the
-- other effects this one costs nothing to share: every peer runs it for EVERY user
-- entity off the already DYNAMIC-synced position, so you see everybody's wake
-- without a single packet. Distance-gated, so standing still leaves no rings and
-- kind_at runs once per RIPPLE_STEP walked rather than once per frame.
function water_ripple()
    if is_dead then return end
    local live_pos = get_value("", name, "position")
    if not live_pos then return end
    if not ripple_from then
        ripple_from = live_pos
        return
    end
    if distance_to(live_pos, ripple_from) < RIPPLE_STEP then return end
    ripple_from = live_pos

    local tile = local_to_map(live_pos)
    local kind = run_function("-gen", "kind_at", { math.floor(tile.x), math.floor(tile.y) })
    if kind ~= K_SEA then return end

    if not ripple_ready then
        ripple_ready = true
        -- scale_amount_min/max is the PEAK size, randomized per ripple (1.0..1.2).
        -- scale_curve pops it to full size in the first half of the lifetime and
        -- holds; alpha_curve stays opaque through that same first half then fades
        -- in the second - grow-then-fade as two separate phases, not simultaneous
        -- ramps (which read as "just vanishes" instead of a visible fade).
        create_particle({
            particle_id = "mbl_water_ring",
            texture_path = "splash",
            lifetime = 0.45,
            amount = 1,
            one_shot = true,
            explosiveness = 1.0,
            spread = 0,
            initial_velocity_min = 0,
            initial_velocity_max = 0,
            gravity = { x = 0, y = 0 }, -- a water ring sits still, it doesn't fall
            scale_amount_min = 1.0,
            scale_amount_max = 1.2,
            scale_curve = { 0.0, 1.0, 1.0 },
            alpha_curve = { 1.0, 1.0, 0.0 },
            color = Color(1, 1, 1, 0.8),
            z_index = 1, -- under the body sprite (z 2), still over the tiles
        })
    end
    -- Parented to the body so z_index is relative to it, but local_coords stays
    -- false, so the ring is left behind in the water instead of following you.
    start_particle({ particle_id = "mbl_water_ring", parent_name = name,
        position = Vector2(0, RIPPLE_FOOT_Y) })
end

-- =============================================================================
-- Potion buffs (every peer ticks its own copy; the host owns the healing).
-- =============================================================================

-- HOST: start (or refresh) a buff and tell everyone, so the badge shows up on
-- every screen and each peer counts the same duration down locally.
function host_grant_buff(kind)
    if not IS_HOST then return end
    run_network_function(name, "buff_ALL", { kind, BUFF_SECONDS })
end

function buff_ALL(sender_id, kind, seconds)
    if buff_until[kind] == nil then return end
    buff_until[kind] = clock + seconds
    if not buff_shown[kind] then
        buff_shown[kind] = true
        set_image({ parent_name = name, name = "buff_" .. kind, visible = true })
    end
    if kind == "regen" then last_regen_tick = clock end
end

-- Runs on every peer: drops expired badges. On the host it also applies the
-- regeneration ticks, because hp is host-authoritative.
function buff_check()
    for _, kind in ipairs(BUFF_ORDER) do
        if buff_shown[kind] and not has_buff(kind) then
            buff_shown[kind] = false
            set_image({ parent_name = name, name = "buff_" .. kind, visible = false })
        end
    end
    if not IS_HOST or is_dead then return end
    if has_buff("regen") and clock - last_regen_tick >= 1.0 then
        last_regen_tick = clock
        local healed = math.min(BUFF_REGEN_PER_TICK, max_hp - hp)
        if healed > 0 then
            hp = hp + healed
            run_network_function(name, "hp_ALL", { hp }, name)
            local live_pos = get_value("", name, "position")
            if live_pos then
                run_function("-combat", "show_damage", { live_pos.x, live_pos.y, healed, "heal" })
            end
        end
    end
end

start_timer({ timer_id = "buff" .. name, entity_name = name,
    function_name = "buff_check", wait_time = BUFF_TICK_SECONDS })

-- =============================================================================
-- Mount & pet: two images hung off the body, nothing more.
-- =============================================================================

-- Both slots exist from the start (hidden, on a texture that always resolves)
-- so toggling them later is a plain visibility flip and never has to create an
-- image with no path.
set_image({ parent_name = name, name = "mount", image_path = "white",
    position = MOUNT_OFFSET, visible = false, z_index = MOUNT_Z })
set_image({ parent_name = name, name = "pet", image_path = "white",
    position = PET_OFFSET, visible = false, z_index = PET_Z })
set_image({ parent_name = name, name = "worn", image_path = "white",
    visible = false, z_index = WORN_Z })

-- Driven by -inv's worn_ALL (every peer, for every player) - a worn accessory
-- is its own slot, fixed on the body at that item's own offset, never the
-- orbiting aim dot the held tool uses.
function set_worn_visual(item_id)
    if not item_id or item_id == "" then
        set_image({ parent_name = name, name = "worn", visible = false })
        return
    end
    local item = run_function("-items", "get_item", { item_id })
    if not item then
        set_image({ parent_name = name, name = "worn", visible = false })
        return
    end
    set_image({ parent_name = name, name = "worn", image_path = item.image,
        position = WORN_OFFSETS[item_id] or Vector2(0, 0),
        scale = Vector2(WORN_SIZE, WORN_SIZE), visible = true })
end

local function species_def(species_key)
    if not species_key or species_key == "" then return nil end
    return run_function("-wild", "get_species", { species_key })
end

function mount_ALL(sender_id, species_key)
    mount = species_key or ""
    local def = species_def(mount)
    if def then
        -- A quick animal carries you faster, a turtle is its own punishment.
        mount_speed_mult = math.min(math.max(1.0 + (def.speed - 10) / 30,
            MOUNT_SPEED_MIN), MOUNT_SPEED_MAX)
        set_image({ parent_name = name, name = "mount", image_path = def.image,
            scale = Vector2(MOUNT_SIZE, MOUNT_SIZE), visible = true })
    else
        mount_speed_mult = 1.0
        set_image({ parent_name = name, name = "mount", visible = false })
    end
end

function pet_ALL(sender_id, species_key)
    pet = species_key or ""
    local def = species_def(pet)
    if def then
        set_image({ parent_name = name, name = "pet", image_path = def.image,
            scale = Vector2(PET_SIZE, PET_SIZE), visible = true })
    else
        set_image({ parent_name = name, name = "pet", visible = false })
    end
end

-- =============================================================================
-- Fishing (host-owned state machine; the line itself is drawn by every peer).
-- =============================================================================

local FISH_LINE_SECONDS = 30 -- safety net: the line never outlives a lost cast

function fish_line_ALL(sender_id, x, y, biting)
    local line_name = "fish" .. name
    local live_pos = get_value("", name, "position")
    if not live_pos then return end
    set_line({ name = line_name, start_position = live_pos,
        end_position = Vector2(x, y),
        color = biting and FISH_LINE_BITE or FISH_LINE_IDLE,
        width = 1, z_index = 40 })
    run_function(name, "clear_fish_line", { line_name }, FISH_LINE_SECONDS)
end

function fish_line_off_ALL(sender_id)
    clear_fish_line("fish" .. name)
end

function clear_fish_line(line_name)
    if line_exists(line_name) then destroy_line(line_name) end
end

-- HOST: end the current cast, whatever state it was in.
local function stop_fishing()
    fish_cast = ""
    fish_bite_until = -1
    run_network_function(name, "fish_line_off_ALL", {})
end

-- HOST: the fish is on the hook - the player now has FISH_WINDOW to react.
function host_fish_bite(cast_id, x, y)
    if not IS_HOST or cast_id ~= fish_cast then return end
    fish_bite_until = clock + FISH_WINDOW
    run_network_function(name, "fish_line_ALL", { x, y, true })
    run_network_function(name, "toast_ALL", { "{something_is_biting}" }, name)
    run_function(name, "host_fish_escape", { cast_id }, FISH_WINDOW)
end

-- HOST: the window closed without a reaction.
function host_fish_escape(cast_id)
    if not IS_HOST or cast_id ~= fish_cast then return end
    stop_fishing()
    run_network_function(name, "toast_ALL", { "{it_got_away}" }, name)
end

-- HOST: change what someone rides / is followed by. Tells every peer (so your
-- friends see it too) and parks it in -inv's progress table so it survives a
-- relog, exactly like the Heart Container's max HP does.
function set_mount(species_key)
    if not IS_HOST then return end
    run_network_function(name, "mount_ALL", { species_key })
    run_function("-inv", "host_set_progress",
        { { steam_id = name, key = "mount", value = species_key } })
end

function set_pet(species_key)
    if not IS_HOST then return end
    run_network_function(name, "pet_ALL", { species_key })
    run_function("-inv", "host_set_progress",
        { { steam_id = name, key = "pet", value = species_key } })
end

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
        local damage = def.damage
        if has_buff("strength") then damage = math.floor(damage * BUFF_STRENGTH_MULT) end
        local cfg = { x = live_pos.x + math.cos(angle) * ahead,
            y = live_pos.y + math.sin(angle) * ahead,
            shape = shape.kind,
            r = shape.r and shape.r * MELEE_HURTBOX_SCALE or nil,
            w = shape.w and shape.w * MELEE_HURTBOX_SCALE or nil,
            h = shape.h and shape.h * MELEE_HURTBOX_SCALE or nil,
            angle = angle, windup = MELEE_WINDUP, dmg = damage,
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
        run_network_function(name, "toast_ALL", { "{no_arrows_craft_some}" }, name)
        return
    end
    last_use = clock
    spend_stamina(def.stamina)
    local damage = def.damage
    if has_buff("strength") then damage = math.floor(damage * BUFF_STRENGTH_MULT) end
    run_function("-combat", "host_arrow", { name, aim_x, aim_y, damage })
end

-- A gadget (bomb, potion, heart container, ...) always wins over the ordinary
-- plant/harvest/place/eat chain, because nothing carries both a use_kind and a
-- seed/food/block role. Returns true when the item was handled here.
-- Every branch consumes the item ONLY once its action actually succeeded.
local function use_gadget(use_kind, aim_x, aim_y, live_pos)
    local function take_one()
        return run_function("-inv", "host_consume",
            { { steam_id = name, item_id = held_item, count = 1 } })
    end

    if use_kind == "bomb" then
        local item = run_function("-items", "get_item", { held_item })
        if not take_one() then return true end
        local angle = math.atan(aim_y - live_pos.y, aim_x - live_pos.x)
        spawn_entity_host({ t = "bomb",
            p = Vector2(live_pos.x + math.cos(angle) * 10,
                live_pos.y + math.sin(angle) * 10),
            v = Vector2(math.cos(angle) * BOMB_THROW_SPEED,
                math.sin(angle) * BOMB_THROW_SPEED),
            dmg = item.blast_damage, radius = item.blast_radius, thrower = name })
        return true
    end

    if use_kind == "potion" then
        local item = run_function("-items", "get_item", { held_item })
        if not take_one() then return true end
        host_grant_buff(item.potion)
        return true
    end

    if use_kind == "rod" then
        -- A cast already in the water: this Interact is either the catch or an
        -- early reel-in, never a second cast.
        if fish_cast ~= "" then
            if clock <= fish_bite_until then
                local catch = run_function("-items", "roll_fish")
                stop_fishing()
                -- Routed through the normal pickup path so a fished-up chest
                -- opens itself exactly like one found in the rocks.
                run_function("-inv", "host_pickup",
                    { { picker = name, item_id = catch.id, count = math.floor(catch.count) } })
                if catch.id ~= "chest" then
                    local item = run_function("-items", "get_item", { catch.id })
                    run_network_function(name, "toast_ALL",
                        { "{you_caught}" .. math.floor(catch.count) .. "x " .. item.name .. "!" }, name)
                end
            else
                stop_fishing()
                run_network_function(name, "toast_ALL", { "{you_reel_the_line_back_in}" }, name)
            end
            return true
        end
        local tile = local_to_map(Vector2(aim_x, aim_y))
        local tx, ty = math.floor(tile.x), math.floor(tile.y)
        local center = map_to_local(Vector2(tx, ty))
        if distance_to(live_pos, center) > REACH then
            run_network_function(name, "toast_ALL", { "{that_water_is_too_far_away}" }, name)
            return true
        end
        local kind = run_function("-gen", "kind_at", { tx, ty })
        if kind ~= K_SEA and kind ~= K_DEEP then
            run_network_function(name, "toast_ALL", { "{you_can_only_fish_in_water}" }, name)
            return true
        end
        fish_counter = fish_counter + 1
        fish_cast = tostring(fish_counter)
        fish_bite_until = -1
        local wait = FISH_WAIT_MIN + math.random() * (FISH_WAIT_MAX - FISH_WAIT_MIN)
        run_network_function(name, "fish_line_ALL", { center.x, center.y, false })
        run_function(name, "host_fish_bite", { fish_cast, center.x, center.y }, wait)
        return true
    end

    -- The saddle is a reusable tool, never consumed: near an animal it mounts
    -- that animal. A tamed animal leaves the world for good - see host_tame in
    -- critter.lua - so a saddle thrown over a SECOND animal would quietly delete
    -- the one you are already on. It cannot happen: interact_HOST dismounts you
    -- before any gadget runs, so this branch is only ever reached on foot and
    -- the second animal is never touched.
    if use_kind == "saddle" then
        local nearest = get_nearest_entity_by_tag(name, "critter")
        if nearest and nearest.name and nearest.name ~= ""
                and nearest.distance <= SADDLE_REACH then
            local species_key = run_function(nearest.name, "host_tame", {})
            if species_key and species_key ~= "" then
                set_mount(species_key)
                local def = run_function("-wild", "get_species", { species_key })
                run_network_function(name, "toast_ALL",
                    { "{you_are_riding_a}" .. ((def and def.label) or species_key) .. "!" }, name)
            end
            return true
        end
        run_network_function(name, "toast_ALL", { "{no_animal_close_enough}" }, name)
        return true
    end

    -- The charm is kept, not spent: each Interact summons the next little
    -- creature in the list, and one past the end sends it home again.
    if use_kind == "pet" then
        local options = run_function("-wild", "get_pet_species") or {}
        local index = 0
        for i, species_key in ipairs(options) do
            if species_key == pet then index = i end
        end
        set_pet((index >= #options) and "" or options[index + 1])
        return true
    end

    if use_kind == "portal" then
        -- Planted where you stand, not where you aim: no reach check to get
        -- wrong, and the tile under your feet is walkable by definition.
        -- -gm owns the whole transaction (validate + spend the stone), so
        -- there is no take_one() here.
        local tile = local_to_map(live_pos)
        run_function("-gm", "host_place_portal",
            { { steam_id = name, x = math.floor(tile.x), y = math.floor(tile.y) } })
        return true
    end

    if use_kind == "grapple" then
        local item = run_function("-items", "get_item", { held_item })
        if clock - last_grapple < item.cooldown then return true end
        local angle = math.atan(aim_y - live_pos.y, aim_x - live_pos.x)
        local dir = Vector2(math.cos(angle), math.sin(angle))
        -- Mask {1} is the tilemap: rock, trees and placed blocks are the only
        -- things solid enough to take a hook. Open grass and shallow sea are
        -- not, which is exactly why this is a traversal tool and not a dash.
        local hit = raycast({ from = live_pos, direction = dir,
            length = GRAPPLE_RANGE, collision_mask = { 1 }, exclude = { name } })
        if not hit.hit then
            run_network_function(name, "toast_ALL", { "{nothing_solid_to_hook_onto}" }, name)
            return true
        end
        if stamina + STAMINA_TOLERANCE < item.stamina then
            host_deny_stamina()
            return true
        end
        last_grapple = clock
        spend_stamina(item.stamina)
        -- Interact has no local stamina prediction (unlike the LMB path), so
        -- the owner needs one message to keep their bar honest.
        run_network_function(name, "stam_sync_ALL", { stamina }, name)
        local reach = math.max(distance_to(live_pos, hit.position) - GRAPPLE_STOP_SHORT, 0)
        -- linear_damp is the script-top entity setting at the top of this file;
        -- reading it back means the two can never drift apart.
        local pull = math.min(reach * linear_damp, GRAPPLE_MAX_SPEED)
        add_linear_velocity(name, Vector2(dir.x * pull, dir.y * pull))
        run_network_function(name, "grapple_fx_ALL",
            { live_pos.x, live_pos.y, hit.position.x, hit.position.y })
        return true
    end

    if use_kind == "upgrade" then
        if not take_one() then return true end
        max_hp = max_hp + HEART_CONTAINER_HP
        hp = hp + HEART_CONTAINER_HP
        -- Parked in -inv's progress table so it survives logging off, not just
        -- this life: -gm writes that table into the world save.
        run_function("-inv", "host_set_progress",
            { { steam_id = name, key = "max_hp", value = max_hp } })
        run_network_function(name, "max_hp_ALL", { max_hp, hp }, name)
        run_function("-combat", "show_damage",
            { live_pos.x, live_pos.y, HEART_CONTAINER_HP, "heal" })
        run_network_function(name, "toast_ALL",
            { "{maximum_health_is_now}" .. math.floor(max_hp) .. "!" }, name)
        return true
    end

    return false
end

-- RMB: climb down when riding, otherwise use the held gadget, plant seeds,
-- harvest grown crops, or eat the food.
function interact_HOST(sender_id, aim_x, aim_y)
    if not IS_HOST or sender_id ~= name then return end
    local live_pos = get_value("", name, "position")
    if not live_pos then return end

    -- Riding OVERRIDES the held item: the first Interact climbs down and the
    -- item is not used at all. Dismounting used to need the saddle equipped,
    -- which meant swapping tools just to get off an animal - and it also made
    -- "saddle a second animal" reachable while already mounted.
    if mount ~= "" then
        -- set_mount("") fires mount_ALL synchronously (the host is one of the
        -- "ALL" targets), which clears the local `mount` variable - so the
        -- species has to be read out before that call, not after.
        local released_species = mount
        set_mount("")
        run_function("-wild", "release_mount", { released_species, live_pos.x, live_pos.y })
        run_network_function(name, "toast_ALL", { "{your_mount_wanders_off}" }, name)
        return
    end

    local use_kind = run_function("-items", "get_use_kind", { held_item })
    if use_kind and use_gadget(use_kind, aim_x, aim_y, live_pos) then return end

    local tile = local_to_map(Vector2(aim_x, aim_y))
    local tile_x, tile_y = math.floor(tile.x), math.floor(tile.y)
    local in_reach = distance_to(live_pos, map_to_local(Vector2(tile_x, tile_y))) <= REACH

    if (held_item == "wheat_seed" or held_item == "tree_seed") and in_reach then
        if run_function("-gm", "host_plant",
                { { steam_id = name, item_id = held_item, x = tile_x, y = tile_y } }) then
            return
        end
    end
    if in_reach and run_function("-gm", "host_harvest", { { x = tile_x, y = tile_y } }) then
        return
    end
    -- Placeable materials (wood/stone): put the held block down on bare
    -- ground. host_place_block itself re-checks that held_item is actually
    -- placeable, so this mirrors host_harvest's "just try it" shape.
    if held_item ~= "" and in_reach and run_function("-gm", "host_place_block",
            { { steam_id = name, item_id = held_item, x = tile_x, y = tile_y } }) then
        return
    end
    local item = run_function("-items", "get_item", { held_item })
    if item and item.heal then
        if run_function("-inv", "host_consume",
                { { steam_id = name, item_id = held_item, count = 1 } }) then
            local healed = math.min(item.heal, max_hp - hp)
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
    if attacker and attacker ~= "" and has_tag(attacker, "user") then
        run_function("-gm", "add_stat", { attacker, "dmg_dealt", dmg })
    end
    local live_pos = get_value("", name, "position")
    if live_pos then
        run_function("-combat", "show_damage", { live_pos.x, live_pos.y, dmg, "player" })
    end
    run_network_function(name, "hp_ALL", { hp }, name)
    if hp <= 0 then
        is_dead = true
        stop_fishing() -- dying mid-cast must not leave a line hanging in the sea
        remove_tag(name, "alive")
        freeze_entity(name)
        local death_info = run_function("-gm", "on_player_died", { { steam_id = name } })
        run_network_function(name, "died_ALL", { death_info })
        local spawn = map_to_local(Vector2(0, 0))
        run_function(name, "host_respawn_at", { spawn.x, spawn.y }, RESPAWN_SECONDS)
    end
end

function host_respawn_at(x, y)
    if not IS_HOST then return end
    unfreeze_entity(name)
    change_instantly({ entity_name = name, position = Vector2(x, y),
        linear_velocity = Vector2(0, 0) })
    -- This is the single restore point for BOTH a death respawn and a fresh
    -- join (-gm calls it from finish_boot and _on_user_initialized), so the
    -- persisted max HP is re-read here rather than in a separate join hook.
    max_hp = run_function("-inv", "host_get_progress", { name, "max_hp" }) or BASE_MAX_HP
    hp = max_hp
    stamina = MAX_STAMINA
    is_dead = false
    add_tag(name, "alive")
    run_network_function(name, "max_hp_ALL", { max_hp, hp }, name)
    run_network_function(name, "revived_ALL", {})
    -- Mount and pet ride along through death and relogs; broadcast so a joining
    -- peer's copy of this player is drawn with them from the first frame.
    run_network_function(name, "mount_ALL",
        { run_function("-inv", "host_get_progress", { name, "mount" }) or "" })
    run_network_function(name, "pet_ALL",
        { run_function("-inv", "host_get_progress", { name, "pet" }) or "" })
end

-- =============================================================================
-- Broadcast handlers (visual/HUD mirrors).
-- =============================================================================

function hp_ALL(sender_id, new_hp)
    if not IS_LOCAL then return end
    if new_hp < hp then
        local lost = hp - new_hp
        local intensity = math.min(DAMAGE_SHAKE_MIN + lost * DAMAGE_SHAKE_PER_HP, DAMAGE_SHAKE_MAX)
        screenshake(DAMAGE_FEEDBACK_SECONDS, intensity)
        flash_vignette({ color = DAMAGE_FLASH_COLOR, duration = DAMAGE_FEEDBACK_SECONDS })
    end
    hp = new_hp
    set_progress_bar({ name = "_mbl_hp", value = math.max(hp, 0) })
end

-- A Heart Container widened the bar for good: stretch the HUD gauge to match,
-- then let the ordinary hp path fill it in.
function max_hp_ALL(sender_id, new_max, new_hp)
    -- Crossed the Lua<->GDScript boundary, so it arrived as a float; floor it
    -- or every later "max_hp - hp" carries fractions around.
    max_hp = math.floor(new_max)
    if not IS_LOCAL then return end
    set_progress_bar({ name = "_mbl_hp", max_value = max_hp })
    hp = math.floor(new_hp)
    set_progress_bar({ name = "_mbl_hp", value = math.max(hp, 0) })
end

function stam_sync_ALL(sender_id, new_stamina)
    if not IS_LOCAL then return end
    stamina = new_stamina
end

-- Everyone sees the rope snap taut for a moment (mirrors -combat's arrow
-- tracer: draw a line, clear it on a short delay).
function grapple_fx_ALL(sender_id, x1, y1, x2, y2)
    local line_name = "grap" .. name
    set_line({ name = line_name, start_position = Vector2(x1, y1),
        end_position = Vector2(x2, y2), color = GRAPPLE_LINE_COLOR,
        width = 2, z_index = 50 })
    run_function(name, "clear_grapple_line", { line_name }, GRAPPLE_LINE_SECONDS)
end

function clear_grapple_line(line_name)
    if line_exists(line_name) then destroy_line(line_name) end
end

function toast_ALL(sender_id, text)
    if not IS_LOCAL then return end
    run_function("-gm", "banner_local", { text }) -- already on screen; no need to spam the chat too
end

function died_ALL(sender_id, death_info)
    is_dead = true
    set_image({ parent_name = name, name = "body", modulate = DEAD_TINT })
    if IS_LOCAL then
        local msg = "{you_died_respawning_at_the_camp}"
        -- death_info is only set for a boss-fight death (see -gm's
        -- on_player_died); ordinary deaths never touch the spawn-rights count.
        if death_info and death_info.boss_death then
            local lives_left = math.floor(death_info.lives_left or 0)
            if lives_left > 0 then
                msg = msg .. " " .. lives_left .. "{spawn_right}"
                    .. (lives_left == 1 and "" or "s") .. "{left_before_the_fight_is_lost}"
            else
                msg = msg .. "{that_was_your_last_spawn_right_the_fight}"
            end
        end
        run_function("-gm", "announce_local", { msg })
    end
end

function revived_ALL(sender_id)
    is_dead = false
    set_image({ parent_name = name, name = "body", modulate = Color(1, 1, 1, 1) })
end

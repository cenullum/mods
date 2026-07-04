lock_rotation = true
linear_damp = 2

-- =============================================================================
-- Hide and Seek - player entity (runs on every peer for every player).
--
-- Movement is the engine's built-in TOP_DOWN controller (stick_1), tuned like the
-- Football mod. Hiders walk 1.25x faster than seekers. Every player's body is a
-- paintable 32x32 square: hiders start white (to blend in), seekers start as their
-- Steam avatar (so they're recognisable) - either can repaint it in Paint Mode.
-- The seeker also shoots a short server-authoritative ray on left mouse.
-- =============================================================================

add_tag(name, "user")

local MANAGER = "-hs_manager"
local UI = "-hs_ui"
-- NOTE on zoom direction: set_camera_zoom's value is a magnification factor
-- (confirmed by Draw The Word's zoom_in/zoom_out buttons: zoom_in INCREASES the
-- number). So a SMALLER/narrower view (more zoomed in) means a HIGHER number.
local BASE_ZOOM = 2.6           -- movement mode: tighter view than the old 2.0
local PAINT_ZOOM = 4.0
local LOCK_ZOOM = 4.0          -- seekers zoom right in while locked (can't see the cave)
local COOLDOWN = 2.0            -- client-side spam guard; host is authoritative too
local SEEKER_SPEED = 15.0
local HIDER_SPEED = 18.75       -- 1.25x the seeker

-- Hider-only zoom in/out perk (Zoom In/Zoom Out buttons, hidden from seekers -
-- their view is always fixed at BASE_ZOOM/LOCK_ZOOM). Works in both Movement and
-- Paint Mode: an offset on top of whichever base zoom the current mode uses.
local HIDER_ZOOM_STEP = 0.3
local HIDER_ZOOM_MIN_OFFSET = -1.0
local HIDER_ZOOM_MAX_OFFSET = 10.0

-- State
my_role = 0                     -- 0 none/spectator, 1 seeker, 2 hider
alive = true
paint_mode = false
paint_panel = ""
shoot_held = false
last_shoot = 0
cur_body = ""                   -- current body image node name (per-round, unique)
seeker_locked = false           -- a seeker pulled back into the sealed room (last 10s)
phase_hidden = false            -- true during roam/hide: cross-team bodies are invisible
hider_zoom_offset = 0.0         -- hider-only zoom perk, reset on every role change

-- The zoom to use in movement mode (locked seekers stay zoomed in).
local function move_zoom()
    if my_role == 1 and seeker_locked then return LOCK_ZOOM end
    return BASE_ZOOM
end

-- Zoom actually applied to the camera right now, including the hider's own
-- zoom in/out perk on top of whichever base the current mode/state uses.
-- Seekers never get an offset, so their view stays fixed as required.
local function effective_zoom()
    local base = paint_mode and PAINT_ZOOM or move_zoom()
    if my_role == 2 then
        return base + hider_zoom_offset
    end
    return base
end

-- Hider-only camera perk (buttons are hidden from seekers in hs_ui.lua). Usable
-- in both Movement and Paint Mode.
function zoom_in()
    if my_role ~= 2 or not alive then return end
    hider_zoom_offset = math.min(hider_zoom_offset + HIDER_ZOOM_STEP, HIDER_ZOOM_MAX_OFFSET)
    if IS_LOCAL then
        local z = effective_zoom()
        set_camera_zoom(Vector2(z, z))
    end
end

function zoom_out()
    if my_role ~= 2 or not alive then return end
    hider_zoom_offset = math.max(hider_zoom_offset - HIDER_ZOOM_STEP, HIDER_ZOOM_MIN_OFFSET)
    if IS_LOCAL then
        local z = effective_zoom()
        set_camera_zoom(Vector2(z, z))
    end
end

local function now_secs()
    return get_os_time_unix() -- unix seconds
end

-- Tear down the current body + collision (used on role changes / spectating).
local function clear_body()
    if cur_body ~= "" then
        if is_paintable(cur_body, name) then remove_paintable(cur_body, name) end
        destroy(name, cur_body)
        cur_body = ""
    end
    destroy(name, "col")
end

-- Per-viewer visibility: during the roam/hide phase, each peer independently
-- hides bodies of the OPPOSING role (own-role teammates and spectators still see
-- everyone). This is a purely local rendering decision on each machine - it does
-- not touch the synced paint canvas, so disguises are correct the instant they
-- are revealed. LOCAL_STEAM_ID/get_value let this entity's script (running on
-- every peer) ask "what is THIS peer's own role" to decide what to show.
function refresh_visibility()
    if cur_body == "" then return end
    local viewer_role = get_value("", LOCAL_STEAM_ID, "my_role") or 0
    local show = true
    if phase_hidden and viewer_role ~= 0 and my_role ~= 0 and viewer_role ~= my_role then
        show = false
    end
    set_image({ parent_name = name, name = cur_body, visible = show })
end

-- Broadcast from the manager when entering/leaving the invisible roam/hide phase.
function on_phase_hidden(hidden)
    phase_hidden = hidden
    refresh_visibility()
end

-- =============================================================================
-- Role visuals (called on every peer via the manager's set_roles_ALL).
-- =============================================================================
function apply_role(args)
    local new_role = args.role
    -- Idempotent: a re-broadcast of the same role (e.g. someone joins mid-round)
    -- must NOT rebuild the body, or it would wipe a painted disguise.
    if new_role == my_role and (new_role == 0 or cur_body ~= "") then
        return
    end
    -- Real role change (e.g. a fresh round swaps who is seeker/hider): wipe any
    -- leftover hider zoom perk so a former hider's custom zoom never bleeds into
    -- their next life as a seeker (whose view must stay fixed).
    hider_zoom_offset = 0.0
    clear_body()
    my_role = new_role
    if my_role == 0 then
        return
    end
    alive = true

    -- Body + collision. Layer 2 lets shots target players (raycast masks 1+2);
    -- mask 1 keeps them colliding with walls but NOT with each other.
    set_collision({ parent_name = name, name = "col", shape = "circle", size = 12,
        collision_layer = { 2 }, collision_mask = { 1 } })
    set_value("", name, "speed", (my_role == 1) and SEEKER_SPEED or HIDER_SPEED)

    -- Fresh, uniquely named body each round. IMPORTANT: %d, never tostring(round),
    -- because a float "1.0" becomes a node name with a dot that Godot strips.
    cur_body = string.format("body%d", math.floor(tonumber(args.round) or 0))
    -- Seekers show their Steam avatar (image_path = steam id); hiders a white
    -- square. set_paintable then captures that as the canvas everyone can repaint.
    local base_image = (my_role == 1) and name or "body"
    set_image({ parent_name = name, name = cur_body, image_path = base_image, z_index = 2 })
    set_image_pixel(name, cur_body, Vector2(32, 32))
    -- HOST ONLY: per the API contract ("Call it on the HOST to define permissions
    -- for everyone"), set_paintable/set_painter replicate to every client via the
    -- engine's own _recv_settings RPC. Calling set_paintable on every peer
    -- independently (as this used to) meant each client built its own, separate
    -- canvas object instead of the host's authoritative one reaching them - the
    -- likely cause of paint strokes only ever being visible to the host.
    if IS_HOST then
        set_paintable({ name = cur_body, parent_name = name, editable = true,
            sync_mode = "live", brush_size = 8, max_undo = 12 })
        -- Only this body's owner may paint it (anti-cheat: nobody can paint
        -- anyone else's disguise).
        set_painter(cur_body, name, name)
    end

    -- Seekers now start free to roam (the door opens immediately); they only get
    -- pulled back and locked in the final PRE_LOCK_WARN seconds before the hunt.
    seeker_locked = false
    refresh_visibility()
    -- Unconditional: resets the paint_mode FLAG on every peer (including the
    -- host's own authoritative copy, used to gate movement - see _process).
    -- exit_paint_mode() internally gates the camera/panel side effects to
    -- IS_LOCAL, so this is still a no-visible-op for everyone but the owner.
    exit_paint_mode()
end

-- Late avatar load: refresh a seeker's body to their avatar. Rebuild the canvas
-- (remove + recreate) so the avatar becomes the paint base, unless they already
-- opened Paint Mode (then keep whatever they've drawn).
function _on_loaded_avatar(steam_id)
    if steam_id ~= name or my_role ~= 1 or cur_body == "" or paint_mode then return end
    set_image({ parent_name = name, name = cur_body, image_path = name, z_index = 2 })
    set_image_pixel(name, cur_body, Vector2(32, 32))
    -- HOST ONLY (see apply_role's comment): re-captures the freshly-loaded
    -- avatar as the canvas base and replicates it to every client.
    if IS_HOST then
        if is_paintable(cur_body, name) then remove_paintable(cur_body, name) end
        set_paintable({ name = cur_body, parent_name = name, editable = true,
            sync_mode = "live", brush_size = 8, max_undo = 12 })
        set_painter(cur_body, name, name)
    end
    refresh_visibility() -- set_image defaults to visible=true; re-apply the current hide state
end

-- =============================================================================
-- Per-frame input. Return nil to leave movement inputs untouched (the engine's
-- TOP_DOWN controller handles walking); only return a table when overriding.
-- =============================================================================
function _process(delta, inputs)
    if paint_mode then
        inputs.stick_1 = Vector2(0, 0) -- frozen: stay put so the body is paintable
        return inputs
    end
    if IS_LOCAL and my_role == 1 and alive then
        local pressed = inputs.key_12 -- LEFT MOUSE
        if pressed and not shoot_held then
            try_shoot(inputs.stick_2)
        end
        shoot_held = pressed
    end
    return nil
end

-- Send a shot intent toward the world cursor. The host re-casts from our real
-- position, enforces the 2s cooldown and decides any catch (anti-cheat).
function try_shoot(aim)
    local t = now_secs()
    if t - last_shoot < COOLDOWN then return end
    last_shoot = t
    run_network_function(MANAGER, "shoot_HOST", { aim.x, aim.y })
end

-- =============================================================================
-- Paint Mode <-> Movement Mode (toggled by the view button, available to all).
-- Entering is server-authoritative: the HOST snaps the position to the centre
-- of the tile currently stood on (pixel-perfect, and always clear of the
-- tilemap's collider since the current tile must already be walkable), then
-- the resulting position + paint_mode flag are synced to every peer normally.
-- =============================================================================
function toggle_paint_mode()
    if (my_role ~= 1 and my_role ~= 2) or not alive then return end
    run_network_function(name, "request_paint_mode_HOST", { not paint_mode })
end

-- HOST: validate the request, snap-on-entry, then fan the flag out to everyone.
function request_paint_mode_HOST(sender_id, want_paint)
    if not IS_HOST or sender_id ~= name then return end
    if want_paint and ((my_role ~= 1 and my_role ~= 2) or not alive) then return end
    if want_paint then
        local tile = local_to_map(position)
        local snapped = map_to_local(tile)
        change_instantly({ entity_name = name, position = snapped, linear_velocity = Vector2(0, 0) })
    end
    run_network_function(name, "set_paint_mode_ALL", { want_paint })
end

-- ALL peers: apply the synced flag on every copy of this entity (this is what
-- makes the movement freeze in _process authoritative on the host's side too).
-- The camera/panel/UI side effects only run for the entity's own owner.
function set_paint_mode_ALL(sender_id, want_paint)
    if want_paint then enter_paint_mode() else exit_paint_mode() end
end

function enter_paint_mode()
    if cur_body == "" then return end
    paint_mode = true
    if not IS_LOCAL then return end
    set_camera_target(name)
    local z = effective_zoom()
    set_camera_zoom(Vector2(z, z))
    -- Panel to the left so the zoomed body stays centred/clear. Brush 1-32, and
    -- the eyedropper also samples world colours to blend in.
    paint_panel = create_painting_panel({
        name = cur_body, parent_name = name, title = "Your Disguise",
        brush_min = 1, brush_max = 32, world_pick = true,
        offset_ratio = Vector2(0.3, 1.0),
    })
    run_function(UI, "on_paint_mode", { true })
end

function exit_paint_mode()
    paint_mode = false
    if not IS_LOCAL then return end
    if paint_panel ~= "" and is_panel_exists(paint_panel) then
        close_panel(paint_panel)
    end
    paint_panel = ""
    local z = effective_zoom() -- locked seekers stay zoomed in; hiders keep their zoom perk
    set_camera_zoom(Vector2(z, z))
    set_camera_target(name)
    run_function(UI, "on_paint_mode", { false })
end

-- Camera hopping between hiders (the Previous/Next/Yourself buttons).
function move_camera_to(target_id)
    set_camera_target(target_id)
end

-- Seekers zoom hard onto themselves while sealed in the start room so they cannot
-- see the cave (2D has no wall occlusion), then zoom back out when released.
function on_lock_view()
    if my_role == 1 and IS_LOCAL then
        seeker_locked = true
        set_camera_target(name)
        if not paint_mode then set_camera_zoom(Vector2(LOCK_ZOOM, LOCK_ZOOM)) end
    end
end

function on_release_view()
    if my_role == 1 and IS_LOCAL then
        seeker_locked = false
        if not paint_mode then set_camera_zoom(Vector2(BASE_ZOOM, BASE_ZOOM)) end
    end
end

-- =============================================================================
-- Getting caught (fan-out from the host).
-- =============================================================================
function on_caught()
    alive = false
    if cur_body ~= "" then
        set_image({ parent_name = name, name = cur_body, modulate = Color(0.4, 0.4, 0.4, 0.7) })
        if IS_HOST and is_paintable(cur_body, name) then set_painter(cur_body, 0, name) end
    end
    -- Unconditional: resets paint_mode everywhere (see apply_role's comment);
    -- re-centres the owner's own camera on themself internally when IS_LOCAL.
    exit_paint_mode()
end



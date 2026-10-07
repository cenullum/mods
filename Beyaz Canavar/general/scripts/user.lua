lock_rotation = true
linear_damp = 4
friction = 0

-- =============================================================================
-- Beyaz Canavar - player entity (runs on every peer for every player).
--
-- Humans are their Steam avatar; a caught player becomes a monster (the avatar
-- is hidden and monster_anim.lua draws the creature on the same body).
--
-- Input-driven logic only runs where the inputs are real: on the HOST (it gets
-- every player's inputs) and on the player's OWN machine. Everywhere else a
-- player's _process receives the LOCAL player's inputs, so it must not act on
-- them - and must never return them, or it would overwrite our own.
--
-- Holding E on a task object: both the owner (progress bar) and the host
-- (authority) time the hold; only the host's completion counts.
-- =============================================================================

local HUMAN_SPEED = 12       -- ~78 px/s with linear_damp 4
local MONSTER_SPEED = 10     -- ~85% of a human
local AVATAR_PX = 26
local CAMERA_ZOOM = 2.5
local SIGHT_TILES = 7
local POLL_SECONDS = 0.12
local ROOM_POLL = 0.25
local STEP_STRIDE = 30         -- px walked per footstep (~2.6 steps/s at full speed)
local STEP_RANGE = 10 * 32     -- footsteps fade out to nothing at this distance
local STEP_SOUNDS = 10         -- sounds/wood_footsteps/wood_footsteps-01..10
local STEP_TELEPORT = 48       -- a jump this big in one frame is a teleport, not a step
local SEARCH_RANGE = 10 * 32   -- the rummaging is heard (by monsters too) this far away
local SEARCH_KINDS = { locker = true, bin = true, shelf = true, sink = true }

add_tag(name, "user")
add_tag(name, "fog_hide")
set_collision({ parent_name = name, name = "col", shape = "circle", size = 8,
    collision_layer = { 2 }, collision_mask = { 1 } }) -- walls only: nobody pushes anybody

my_role = "human"
game_phase = tostring(get_value("", "-gm", "phase") or "lobby")
local clock = 0
local stunned_until = 0
local busy_until = 0
local eaten = false
local avatar_loaded = false
local prev = { key_4 = false, key_8 = false, key_11 = false }
local poll_t = 0
local room_t = 0
local last_room = ""
local target = nil
local hold_id = nil
local hold_t = 0
local shown_prompt = ""
local shown_progress = false
local step_last = nil
local step_walked = 0
local searching = false   -- this player is searching right now (as seen by whoever times the hold)
local search_audio = ""   -- name of the looping sound on this peer, "" = silent
local search_serial = 0

local function draw_body()
    if avatar_loaded then
        set_image({ parent_name = name, name = "body", image_path = name, z_index = 0 })
    else
        set_image({ parent_name = name, name = "body", z_index = 0 })
    end
    set_image_pixel(name, "body", Vector2(AVATAR_PX, AVATAR_PX))
    set_shader({ parent_name = name, image_name = "body", shader_name = "circle",
        outline_color = Color(0.9, 0.9, 0.95, 1) })
end

draw_body()
set_label({ parent_name = name, name = "nick", text = nickname,
    position = Vector2(-64, -26), size = Vector2(1024, 96), scale = Vector2(0.125, 0.125),
    horizontal_alignment = 1, font_size = 48, outline_size = 16, outline_color = Color(0, 0, 0, 1), z_index = 10 })

-- Movement speed must be known to the host too (it simulates every body).
set_value("", name, "speed", HUMAN_SPEED)

if IS_LOCAL then
    set_camera_target(name)
    set_camera_zoom(Vector2(CAMERA_ZOOM, CAMERA_ZOOM))
    set_fog_of_war(true, name, { radius = SIGHT_TILES, hide_tag = "fog_hide", reset = true })
end

function _on_loaded_avatar(steam_id)
    if steam_id ~= name then return end
    avatar_loaded = true
    if my_role ~= "monster" and not eaten then draw_body() end
end

local function set_marker(on)
    if on then
        set_minimap_target({ name = "mm_" .. name, entity_name = name, text = nickname,
            icon_size = Vector2(6, 6),
            color = IS_LOCAL and Color(0.3, 0.6, 1.0, 1) or Color(0.95, 0.95, 0.95, 1) })
    else
        delete_minimap_target("mm_" .. name)
    end
end
set_marker(true)

-- =============================================================================
-- Role / state changes (called on every peer by game_manager)
-- =============================================================================

function apply_role(role)
    my_role = role
    eaten = false
    if role == "monster" then
        set_value(name, "body", "visible", false)
        set_value(name, "nick", "visible", false)
        set_value("", name, "speed", MONSTER_SPEED)
        run_function("-anim", "setup", { name })
        run_function("-anim", "walk", { name })
        set_marker(false)
    else
        run_function("-anim", "hide", { name })
        set_value(name, "body", "visible", true)
        set_value(name, "nick", "visible", true)
        set_value("", name, "speed", HUMAN_SPEED)
        set_marker(role == "human")
    end
    if IS_LOCAL then
        run_function("-hud", "set_role", { role })
        if role ~= "human" then
            if is_panel_exists("bc_map") then close_panel("bc_map") end
            run_function("-hud", "prompt", { "" })
            run_function("-hud", "progress", { -1 })
            shown_prompt = ""
            shown_progress = false
        end
    end
end

function set_phase(p)
    game_phase = p
    if IS_LOCAL then
        if p == "playing" or p == "lobby" then
            set_fog_of_war(true, name, { radius = SIGHT_TILES, hide_tag = "fog_hide", reset = true })
        end
    end
end

-- Caught: the body is gone (the corpse entity takes its place) until respawn.
function set_eaten()
    eaten = true
    set_value(name, "body", "visible", false)
    set_value(name, "nick", "visible", false)
    set_marker(false)
end

function set_busy(seconds)
    busy_until = math.max(busy_until, clock + seconds)
end

function set_stunned(seconds)
    stunned_until = math.max(stunned_until, clock + seconds)
end

-- =============================================================================
-- Per frame
-- =============================================================================

local function pressed(inputs, key)
    local now_down = inputs[key] == true
    local was = prev[key]
    prev[key] = now_down
    return now_down and not was
end

local function set_prompt(text)
    if text ~= shown_prompt then
        shown_prompt = text
        run_function("-hud", "prompt", { text })
    end
end

local function set_progress(v)
    if v < 0 then
        if shown_progress then
            shown_progress = false
            run_function("-hud", "progress", { -1 })
        end
    else
        shown_progress = true
        run_function("-hud", "progress", { v })
    end
end

-- Footsteps: every peer plays every human's steps from the synced position
-- (nothing is sent), as positional audio on the body, so they fade with
-- distance. Monsters are silent here - monster_anim.lua stomps for them.
local function footsteps()
    local pos = get_value("", name, "position")
    if not pos then return end
    local last = step_last
    step_last = pos
    if not last or my_role == "monster" or eaten then
        step_walked = 0
        return
    end
    local moved = math.sqrt((pos.x - last.x) ^ 2 + (pos.y - last.y) ^ 2)
    if moved > STEP_TELEPORT then
        step_walked = 0
        return
    end
    step_walked = step_walked + moved
    if step_walked >= STEP_STRIDE then
        step_walked = step_walked - STEP_STRIDE
        set_audio({ stream_path = string.format("wood_footsteps/wood_footsteps-%02d", math.random(1, STEP_SOUNDS)),
            parent_name = name, is_2d = true, max_distance = STEP_RANGE })
    end
end

-- Searching a locker / bin / shelf (or turning off a sink) loops sounds/searching for exactly as long
-- as the hold lasts, as positional audio on the body: everyone near hears it,
-- monsters included. Only the owner and the host know the hold (inputs), so
-- the owner plays its own at once and the host tells everybody else.
local function search_sound(on)
    if search_audio ~= "" then
        destroy(name, search_audio, false)
        search_audio = ""
    end
    if on then
        -- A fresh name each time: a destroyed player lingers until the frame
        -- ends, and set_audio would reuse it by name.
        search_serial = search_serial + 1
        search_audio = "bc_search_" .. search_serial
        set_audio({ stream_path = "searching", name = search_audio, parent_name = name,
            is_2d = true, is_loop = true, max_distance = SEARCH_RANGE })
    end
end

local function set_searching(on)
    if on == searching then return end
    searching = on
    if IS_LOCAL then search_sound(on) end
    if IS_HOST then run_network_function(name, "searching_ALL", { on }) end
end

function searching_ALL(sender_id, on)
    if name == LOCAL_STEAM_ID then return end -- the owner already plays its own
    search_sound(on == true)
end

function _process(delta, inputs)
    clock = clock + delta
    footsteps()
    if not IS_LOCAL and not IS_HOST then return nil end
    local frozen = eaten or clock < stunned_until or clock < busy_until
    local changed = false
    if frozen then
        inputs.stick_1 = Vector2(0, 0)
        changed = true
    end
    local playing = game_phase == "playing" or game_phase == "escape"
    local now_searching = false

    if IS_LOCAL then
        if pressed(inputs, "key_4") and my_role == "human" and playing then
            run_function("-tasks", "toggle_panel", {})
        end
        if pressed(inputs, "key_11") and my_role == "human" then
            if is_panel_exists("bc_map") then
                close_panel("bc_map")
            elseif get_minimap() ~= "" then
                create_minimap_panel({ panel_name = "bc_map", title = "{school_map}",
                    lock_target = "mm_" .. name, minimum_size = Vector2(520, 420) })
            end
        end
        if pressed(inputs, "key_8") and my_role == "monster" and playing and not frozen then
            run_network_function("-gm", "scream_HOST", {})
        end
        room_t = room_t - delta
        if room_t <= 0 then
            room_t = ROOM_POLL
            local pos = get_value("", name, "position")
            if pos then
                local token = run_function("-gen", "room_at", { pos.x, pos.y }) or ""
                if token ~= "" and token ~= last_room then
                    last_room = token
                    run_function("-hud", "set_room", { token })
                end
            end
        end
    end

    -- Hold E on the object in front of you.
    if my_role == "human" and playing and not frozen then
        poll_t = poll_t - delta
        if poll_t <= 0 then
            poll_t = POLL_SECONDS
            local pos = get_value("", name, "position")
            target = pos and run_function("-tasks", "pick_target", { pos.x, pos.y, name }) or nil
            if target and target.id ~= hold_id then
                hold_id = nil
                hold_t = 0
            end
        end
        local hold = target and tonumber(target.hold) or 0
        if target and hold > 0 and inputs.key_6 == true then
            now_searching = SEARCH_KINDS[target.kind] == true
            if hold_id ~= target.id then
                hold_id = target.id
                hold_t = 0
            end
            hold_t = hold_t + delta
            if IS_LOCAL then set_progress(math.min(1, hold_t / hold)) end
            if hold_t >= hold then
                if IS_HOST then run_function("-tasks", "host_complete", { name, target.id }) end
                hold_t = 0
                if not target.again then
                    hold_id = nil
                    target = nil
                    poll_t = 0
                end
            end
        else
            hold_id = nil
            hold_t = 0
            if IS_LOCAL then set_progress(-1) end
        end
        if IS_LOCAL then set_prompt(target and tostring(target.prompt or "") or "") end
    elseif IS_LOCAL then
        target = nil
        hold_id = nil
        set_prompt("")
        set_progress(-1)
    end
    set_searching(now_searching)

    if changed then return inputs end
    return nil
end

function _on_gamepad_connection_changed(has_gamepad)
    if IS_LOCAL then run_function("-hud", "set_role", { my_role }) end
end

-- A player who joins mid-round may have missed role_ALL (it can arrive before
-- this entity exists): take the role the game manager already knows.
apply_role(tostring(run_function("-gm", "get_role", { name }) or "human"))

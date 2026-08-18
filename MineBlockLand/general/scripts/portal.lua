network_mode = 1
freeze = true
lock_rotation = true

-- =============================================================================
-- MineBlockLand - a placed portal.
-- Spawn config: owner (steam id string), pid (portal id string), label.
--
-- Walk into one and its travel panel opens, listing every OTHER portal in the
-- world; pick one and you are there. Standing on your own also offers to take
-- it back (the stone is refunded).
--
-- Everything is keyed by PID rather than by owner, because a player may have
-- several portals standing at once: filtering the destination list by owner
-- would hide a player's own other camps from them.
--
-- The trigger is resolved LOCALLY: the entity exists on every peer (STATIC), so
-- each machine notices its own player stepping in and opens its own panel. That
-- keeps a pure-UI event off the network entirely - the only thing that ever
-- goes to the host is the travel/remove intent itself, and -gm validates that
-- against its own ledger (a client can never name its own destination).
-- =============================================================================

add_tag(name, "portal")

local PANEL = "_mbl_portal"
local RING_SIZE = 20
local ARM_SECONDS = 1.5 -- do not fire the instant it is planted under your feet
local IDLE_COLOR = Color(0.55, 0.4, 0.95, 0.85)

local armed = false

set_image({ parent_name = name, name = "ring", image_path = "items/15x15_portal_stone",
    scale = Vector2(RING_SIZE, RING_SIZE), modulate = IDLE_COLOR, z_index = 1 })

-- Crisp world-space name: big font_size drawn small via scale, same trick the
-- player nickname uses.
set_label({ parent_name = name, name = "tag", text = label,
    position = Vector2(-64, -26), size = Vector2(1024, 96),
    scale = Vector2(0.125, 0.125), horizontal_alignment = 1, font_size = 48,
    outline_size = 16, outline_color = Color(0, 0, 0, 1), z_index = 10 })

set_area({ parent_name = name, name = "area", shape = "circle", size = 12,
    collision_mask = { 2 } }) -- player bodies only

run_function(name, "arm", {}, ARM_SECONDS)

function arm()
    armed = true
end

-- Renamed by its owner: every peer just redraws the label.
function portal_label_ALL(sender_id, new_label)
    label = new_label
    set_label({ parent_name = name, name = "tag", text = new_label })
end

function on_area_body_entered(body_name)
    if not armed or body_name ~= LOCAL_STEAM_ID then return end
    if is_panel_exists(PANEL) then return end
    open_travel_panel()
end

function open_travel_panel()
    local list = run_function("-gm", "get_portal_list") or {}
    create_panel({ name = PANEL, title ="{portal}" .. tostring(label),
        text ="{step_through_to_another_camp}", set_time = false, close = true,
        resizable = false, minimum_size = Vector2(420, 280), is_scrollable = true })

    local destinations = {}
    for portal_id, entry in pairs(list) do
        if portal_id ~= pid then
            table.insert(destinations, { id = portal_id, label = entry.label })
        end
    end
    -- pairs() has no defined order; sort so the list does not reshuffle itself
    -- every time the panel is opened. Labels are renameable and need not be
    -- unique, so the id breaks the tie - otherwise two portals sharing a name
    -- could still swap places between openings.
    table.sort(destinations, function(a, b)
        if a.label ~= b.label then return a.label < b.label end
        return a.id < b.id
    end)

    for _, dest in ipairs(destinations) do
        add_button_to_panel(PANEL, { entity_name = name,
            function_name = "on_travel", text ="{travel_to}" .. dest.label,
            extra_args = { target = dest.id }, color = Color(0.35, 0.3, 0.6) })
    end
    if #destinations == 0 then
        update_panel_settings(PANEL,
            { text ="{this_is_the_only_portal_in_the_world_so}" })
    end
    if owner == LOCAL_STEAM_ID then
        add_button_to_panel(PANEL, { entity_name = name,
            function_name = "on_remove", text ="{take_this_portal_back}",
            color = Color(0.6, 0.3, 0.3) })
    end
end

function on_travel(data)
    close_panel(PANEL)
    run_network_function("-gm", "portal_travel_HOST", { data.extra_args.target })
end

function on_remove(data)
    close_panel(PANEL)
    run_network_function("-gm", "portal_remove_HOST", { pid })
end

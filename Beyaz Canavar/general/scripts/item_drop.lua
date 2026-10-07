network_mode = 1
freeze = true

-- =============================================================================
-- Beyaz Canavar - a task item lying on the floor (the master key, plan pieces
-- or the logbook), dropped where its carrier was caught. Spawned by the host
-- with { item, count }; STATIC so late joiners get it. Only humans see it -
-- monsters know nothing about the tasks - so its label checks the local role.
-- Picking it up goes through task_manager (hold E next to it).
-- =============================================================================

local TOKENS = { key = "{item_key}", book = "{item_book}", pages = "{item_pages}" }

set_label({ parent_name = name, name = "tag", text = TOKENS[tostring(item)] or "?",
    position = Vector2(-64, -12), size = Vector2(1024, 96), scale = Vector2(0.125, 0.125),
    horizontal_alignment = 1, font_size = 48, outline_size = 16, outline_color = Color(0, 0, 0, 1),
    font_color = Color(1, 0.9, 0.4, 1), z_index = 5, visible = false })
set_circle({ name = "ring_" .. name, parent_name = name, radius = 7, width = 2,
    color = Color(1, 0.9, 0.4, 1), fill_color = Color(1, 0.9, 0.4, 0.35), visible = false })

local shown = false
local function refresh()
    local human = run_function("-gm", "get_role", { LOCAL_STEAM_ID }) == "human"
    if human ~= shown then
        shown = human
        set_label({ parent_name = name, name = "tag", visible = human })
        set_circle({ name = "ring_" .. name, visible = human })
    end
end
refresh()

function poll(args)
    if not entity_exists(name) then return end
    refresh()
end

start_timer({ timer_id = "bc_drop_" .. name, entity_name = name, function_name = "poll", wait_time = 1.0 })

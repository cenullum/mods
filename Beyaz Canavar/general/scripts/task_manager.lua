singleton_name = "tasks"
network_mode = 1

-- =============================================================================
-- Beyaz Canavar - the five team tasks.
--
--   key       search corridor lockers for the master key, unlock the principal's door
--   plan      dig through bins for 3 torn pieces of the evacuation plan, pin them up
--             on the staff room's notice board
--   book      search the library shelves for the caretaker's logbook, leave it on
--             the staff room desk
--   sinks     turn off every overflowing sink in the toilets
--   computer  (behind the principal's door) keep the security computer running
--             until it unlocks the building
-- All five done -> game_manager opens the five exits.
--
-- The HOST owns the truth. Which locker holds the key, which bins hold pages
-- and which shelf hides the book are local host tables that never leave it.
-- Task progress is sent only to HUMAN peers (targeted _CLIENT), so a monster
-- client cannot learn it even from the packets; opened lockers / emptied
-- shelves / the opened door are ordinary tile changes everybody sees.
--
-- Holding E is timed by user.lua on the host (with the player's real inputs);
-- host_complete() re-checks role, distance and state before applying anything.
-- =============================================================================

local REACH = 54
local HOLD = { locker = 4, bin = 3, shelf = 4, pdoor = 5, board = 4, desk = 3, sink = 3,
    computer = 1, drop = 1, vent = 0.5 }
local COMPUTER_SECONDS = 60
local PAGES_NEEDED = 3
local VENT_COOLDOWN = 2
local VENT_RANGE = 12 * 32
local TASK_ORDER = { "key", "plan", "book", "sinks", "computer" }
local TASK_TITLE = { key = "{task_key}", plan = "{task_plan}", book = "{task_book}",
    sinks = "{task_sinks}", computer = "{task_computer}" }
local TASK_COLOR = { key = Color(1.0, 0.85, 0.3, 1), plan = Color(0.6, 0.85, 1.0, 1),
    book = Color(0.85, 0.6, 1.0, 1), sinks = Color(0.4, 0.9, 1.0, 1), computer = Color(0.5, 1.0, 0.6, 1) }
local ITEM_TOKEN = { key = "{item_key}", pages = "{item_pages}", book = "{item_book}" }
local FOUND_BY = { key = "{player_found_key}", plan = "{player_found_page}", book = "{player_found_book}" }
local BUCKET = 256

-- School objects (every peer; rebuilt whenever the school is painted).
local objects = {}   -- id -> object from school_gen + wx, wy (world centre)
local by_kind = {}   -- kind -> { ids }
local buckets = {}   -- "bx,by" -> { ids }

local function fresh_state()
    return { key_found = false, key_done = false, pages_found = 0, pages_done = 0,
        book_found = false, book_done = false, sinks_off = 0, sinks_total = 0,
        comp = 0, comp_done = false, all_done = false,
        searched = {}, sink_off = {}, carry = {}, drops = {} }
end

-- Mirrored state (host truth, human peers' copy).
st = fresh_state()

-- Host only.
local secret = { key = 0, pages = {}, book = 0 }
local tiles = {}          -- tile ledger for late joiners: { {x, y, name, old}, ... }
local vent_cd = {}
local last_pos = {}
local clock = 0
local seeded = false

-- Local UI.
local panel = ""
local panel_count = 0
local tracked = {}       -- task -> { sprite = name, icon = name, x, y }
local track_serial = 0
local track_t = 0
local pending_tiles = {}

local function dist(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- =============================================================================
-- Objects
-- =============================================================================

local function rebuild_objects()
    objects, by_kind, buckets = {}, {}, {}
    for _, o in ipairs(run_function("-gen", "get_objects") or {}) do
        local id = math.floor(o.id)
        local obj = { id = id, kind = o.kind, x = math.floor(o.x), y = math.floor(o.y),
            tile = o.tile, opened = o.opened, pair = o.pair and math.floor(o.pair) or nil,
            dy = o.dy and math.floor(o.dy) or 0, rk = o.rk }
        local c = map_to_local(Vector2(obj.x, obj.y))
        obj.wx, obj.wy = c.x, c.y
        objects[id] = obj
        by_kind[obj.kind] = by_kind[obj.kind] or {}
        table.insert(by_kind[obj.kind], id)
        local bk = math.floor(obj.wx / BUCKET) .. "," .. math.floor(obj.wy / BUCKET)
        buckets[bk] = buckets[bk] or {}
        table.insert(buckets[bk], id)
    end
end

-- Where a player stands to use an object: in front of a wall object, beside furniture.
local function stand_pos(obj)
    if obj.kind == "vent" or obj.kind == "board" or obj.kind == "locker" or obj.kind == "sink" then
        local c = map_to_local(Vector2(obj.x, obj.y + 1))
        return c.x, c.y
    end
    return obj.wx, obj.wy
end

function get_exit_points()
    local out = {}
    for _, id in ipairs(by_kind.exit or {}) do
        local o = objects[id]
        out[#out + 1] = map_to_local(Vector2(o.x, o.y + o.dy))
    end
    return out
end

-- =============================================================================
-- State transport (sets travel as arrays: keys would not survive the bridge)
-- =============================================================================

local function pack()
    local p = { key_found = st.key_found, key_done = st.key_done, pages_found = st.pages_found,
        pages_done = st.pages_done, book_found = st.book_found, book_done = st.book_done,
        sinks_off = st.sinks_off, sinks_total = st.sinks_total, comp = st.comp,
        comp_done = st.comp_done, all_done = st.all_done,
        searched = {}, sink_off = {}, carry = {}, drops = {} }
    for id in pairs(st.searched) do p.searched[#p.searched + 1] = id end
    for id in pairs(st.sink_off) do p.sink_off[#p.sink_off + 1] = id end
    for sid, c in pairs(st.carry) do
        p.carry[#p.carry + 1] = { id = sid, key = c.key == true, pages = c.pages or 0, book = c.book == true }
    end
    for n, d in pairs(st.drops) do
        p.drops[#p.drops + 1] = { name = n, item = d.item, count = d.count, x = d.x, y = d.y }
    end
    return p
end

local function unpack_state(p)
    local s = fresh_state()
    for _, k in ipairs({ "key_found", "key_done", "book_found", "book_done", "comp_done", "all_done" }) do
        s[k] = p[k] == true
    end
    for _, k in ipairs({ "pages_found", "pages_done", "sinks_off", "sinks_total", "comp" }) do
        s[k] = math.floor(tonumber(p[k]) or 0)
    end
    for _, id in ipairs(p.searched or {}) do s.searched[math.floor(id)] = true end
    for _, id in ipairs(p.sink_off or {}) do s.sink_off[math.floor(id)] = true end
    for _, c in ipairs(p.carry or {}) do
        s.carry[tostring(c.id)] = { key = c.key == true, pages = math.floor(tonumber(c.pages) or 0), book = c.book == true }
    end
    for _, d in ipairs(p.drops or {}) do
        s.drops[tostring(d.name)] = { item = d.item, count = math.floor(tonumber(d.count) or 1),
            x = tonumber(d.x) or 0, y = tonumber(d.y) or 0 }
    end
    return s
end

local function carry_of(id)
    st.carry[id] = st.carry[id] or { key = false, pages = 0, book = false }
    return st.carry[id]
end

local function task_done(t)
    if t == "key" then return st.key_done end
    if t == "plan" then return st.pages_done >= PAGES_NEEDED end
    if t == "book" then return st.book_done end
    if t == "sinks" then return st.sinks_total > 0 and st.sinks_off >= st.sinks_total end
    return st.comp_done
end

local function done_count()
    local n = 0
    for _, t in ipairs(TASK_ORDER) do
        if task_done(t) then n = n + 1 end
    end
    return n
end

-- =============================================================================
-- What can this player use right here? (host for authority, owner for the UI)
-- =============================================================================

local function option(obj, id)
    local k = obj.kind
    local c = st.carry[id] or {}
    if k == "locker" or k == "bin" or k == "shelf" then
        if st.searched[obj.id] then return nil end
        return { hold = HOLD[k], prompt = "{search_" .. k .. "}" }
    elseif k == "pdoor" then
        if st.key_done then return nil end
        if c.key then return { hold = HOLD.pdoor, prompt = "{unlock_door}" } end
        return { hold = 0, prompt = "{door_locked}" }
    elseif k == "board" then
        if task_done("plan") then return nil end
        if (c.pages or 0) > 0 then return { hold = HOLD.board, prompt = "{pin_pages}" } end
        return { hold = 0, prompt = "{board_hint}" }
    elseif k == "desk" then
        if st.book_done then return nil end
        if c.book then return { hold = HOLD.desk, prompt = "{leave_book}" } end
        return { hold = 0, prompt = "{desk_hint}" }
    elseif k == "sink" then
        if st.sink_off[obj.id] then return nil end
        return { hold = HOLD.sink, prompt = "{turn_off_sink}" }
    elseif k == "computer" then
        if st.comp_done or not st.key_done then return nil end
        local pct = math.floor(100 * st.comp / COMPUTER_SECONDS)
        return { hold = HOLD.computer, prompt = string.format(translate("{use_computer}"), pct), again = true }
    elseif k == "vent" then
        return { hold = HOLD.vent, prompt = "{use_vent}" }
    end
    return nil
end

function pick_target(px, py, id)
    if not IS_HOST and id ~= LOCAL_STEAM_ID then return nil end
    if IS_HOST then last_pos[id] = Vector2(px, py) end
    local best, best_d = nil, REACH
    local bx, by = math.floor(px / BUCKET), math.floor(py / BUCKET)
    for dy = -1, 1 do
        for dx = -1, 1 do
            for _, oid in ipairs(buckets[(bx + dx) .. "," .. (by + dy)] or {}) do
                local obj = objects[oid]
                local sx, sy = stand_pos(obj)
                local d = math.min(dist(px, py, obj.wx, obj.wy), dist(px, py, sx, sy))
                if d < best_d then
                    local opt = option(obj, id)
                    if opt then
                        opt.id = oid
                        opt.kind = obj.kind
                        best, best_d = opt, d
                    end
                end
            end
        end
    end
    for n, d in pairs(st.drops) do
        local dd = dist(px, py, d.x, d.y)
        if dd < best_d then
            best = { id = n, kind = "drop", hold = HOLD.drop, prompt = "{pick_up}" }
            best_d = dd
        end
    end
    return best
end

-- =============================================================================
-- Host: completing an interaction
-- =============================================================================

-- Humans get the state; everybody else only hears that something was found
-- (which item, by whom and the progress stay with the humans).
local function broadcast(event)
    local packed = pack()
    local found = event and event.step == "found"
    for _, uid in ipairs(get_entity_names_by_tag("user")) do
        if uid ~= HOST_STEAM_ID then
            if run_function("-gm", "get_role", { uid }) == "human" then
                run_network_function(name, "state_CLIENT", { packed, event or {} }, uid)
            elseif found then
                run_network_function(name, "found_sound_CLIENT", {}, uid)
            end
        end
    end
    on_state(event or {})
end

local function play_found()
    set_audio({ stream_path = "found" })
end

function found_sound_CLIENT(sender_id)
    play_found()
end

local function tell(steam_id, token)
    if steam_id == HOST_STEAM_ID then
        run_function("-hud", "banner", { token, 3 })
    else
        run_network_function(name, "tell_CLIENT", { token }, steam_id)
    end
end

function tell_CLIENT(sender_id, token)
    run_function("-hud", "banner", { token, 3 })
end

local function change_tile(x, y, tile_name, old)
    tiles[#tiles + 1] = { x = x, y = y, name = tile_name, old = old or "" }
    run_network_function(name, "tile_ALL", { x, y, tile_name, old or "" })
end

function tile_ALL(sender_id, x, y, tile_name, old)
    if run_function("-gen", "is_ready") then
        run_function("-gen", "set_deco", { x, y, tile_name, old })
    else
        pending_tiles[#pending_tiles + 1] = { x = x, y = y, name = tile_name, old = old }
    end
end

local function check_all_done()
    if st.all_done then return end
    if done_count() == #TASK_ORDER then
        st.all_done = true
        run_function("-gm", "host_all_tasks_done", {})
    end
end

function host_complete(steam_id, target_id)
    if not IS_HOST then return end
    if run_function("-gm", "get_role", { steam_id }) ~= "human" then return end
    local phase = get_value("", "-gm", "phase")
    if phase ~= "playing" and phase ~= "escape" then return end
    local pos = get_value("", steam_id, "position")
    if not pos then return end
    local c = carry_of(steam_id)
    local nick = get_value("", steam_id, "nickname")
    local event = { by = steam_id, nick = nick and tostring(nick) or "?" }

    -- Picking up a dropped item.
    if type(target_id) == "string" and st.drops[target_id] then
        local d = st.drops[target_id]
        if dist(pos.x, pos.y, d.x, d.y) > REACH + 10 then return end
        if d.item == "key" then c.key = true
        elseif d.item == "book" then c.book = true
        else c.pages = (c.pages or 0) + d.count end
        st.drops[target_id] = nil
        destroy("", target_id)
        tell(steam_id, ITEM_TOKEN[d.item] or "{pick_up}")
        broadcast(event)
        return
    end

    local obj = objects[math.floor(tonumber(target_id) or 0)]
    if not obj then return end
    local sx, sy = stand_pos(obj)
    if math.min(dist(pos.x, pos.y, obj.wx, obj.wy), dist(pos.x, pos.y, sx, sy)) > REACH + 10 then return end
    local opt = option(obj, steam_id)
    if not opt or opt.hold <= 0 then return end
    local k = obj.kind

    if k == "locker" or k == "bin" or k == "shelf" then
        st.searched[obj.id] = true
        if obj.opened then change_tile(obj.x, obj.y, obj.opened, obj.tile) end
        if k == "locker" and obj.id == secret.key and not st.key_found then
            st.key_found = true
            c.key = true
            event.task, event.step = "key", "found"
            tell(steam_id, "{found_key}")
        elseif k == "bin" and secret.pages[obj.id] then
            secret.pages[obj.id] = nil
            st.pages_found = st.pages_found + 1
            c.pages = (c.pages or 0) + 1
            event.task, event.step = "plan", "found"
            tell(steam_id, "{found_page}")
        elseif k == "shelf" and obj.id == secret.book and not st.book_found then
            st.book_found = true
            c.book = true
            event.task, event.step = "book", "found"
            tell(steam_id, "{found_book}")
        else
            tell(steam_id, "{nothing_here}")
        end
    elseif k == "pdoor" then
        c.key = false
        st.key_done = true
        change_tile(obj.x, obj.y, "", obj.tile)
        event.task, event.step = "key", "done"
        tell(steam_id, "{door_unlocked}")
    elseif k == "board" then
        st.pages_done = math.min(PAGES_NEEDED, st.pages_done + (c.pages or 0))
        c.pages = 0
        event.task, event.step = "plan", task_done("plan") and "done" or "progress"
    elseif k == "desk" then
        c.book = false
        st.book_done = true
        event.task, event.step = "book", "done"
    elseif k == "sink" then
        st.sink_off[obj.id] = true
        st.sinks_off = st.sinks_off + 1
        event.task, event.step = "sinks", task_done("sinks") and "done" or "progress"
    elseif k == "computer" then
        st.comp = math.min(COMPUTER_SECONDS, st.comp + HOLD.computer)
        if st.comp >= COMPUTER_SECONDS then
            st.comp_done = true
            event.task, event.step = "computer", "done"
        else
            event.task, event.step = "computer", "progress"
        end
    elseif k == "vent" then
        if (vent_cd[steam_id] or 0) > clock then return end
        local other = obj.pair and objects[obj.pair]
        if not other then return end
        vent_cd[steam_id] = clock + VENT_COOLDOWN
        local tx, ty = stand_pos(other)
        change_instantly({ entity_name = steam_id, position = Vector2(tx, ty), linear_velocity = Vector2(0, 0) })
        run_network_function(name, "vent_ALL", { obj.id, other.id })
        return
    end
    broadcast(event)
    check_all_done()
end

function vent_ALL(sender_id, a, b)
    -- The clank at BOTH ends, for everybody (monsters too: they can come and
    -- look), plus a short shake for whoever is close to either.
    local me = get_value("", LOCAL_STEAM_ID, "position")
    for _, id in ipairs({ a, b }) do
        local o = objects[math.floor(id)]
        if o then
            set_audio({ stream_path = "vent", is_2d = true, position = Vector2(o.wx, o.wy), max_distance = VENT_RANGE })
            if me and dist(me.x, me.y, o.wx, o.wy) < 160 then screenshake(0.3, 2) end
        end
    end
end

-- Carried items fall where their carrier was caught / escaped / left.
function host_drop_items(steam_id, x, y)
    if not IS_HOST then return end
    local c = st.carry[steam_id]
    if not c then return end
    local items = {}
    if c.key then items[#items + 1] = { "key", 1 } end
    if c.book then items[#items + 1] = { "book", 1 } end
    if (c.pages or 0) > 0 then items[#items + 1] = { "pages", c.pages } end
    st.carry[steam_id] = nil
    for i, it in ipairs(items) do
        local p = Vector2(x + (i - 1) * 10, y + 6)
        local n = spawn_entity_host({ t = "item_drop", p = p, item = it[1], count = it[2] })
        if n then st.drops[n] = { item = it[1], count = it[2], x = p.x, y = p.y } end
    end
    if #items > 0 then broadcast({ by = steam_id }) end
end

function host_player_left(steam_id)
    if not IS_HOST then return end
    local p = last_pos[steam_id]
    if p then
        host_drop_items(steam_id, p.x, p.y)
    elseif st.carry[steam_id] then
        -- Nowhere to drop it: the items go back where they were found.
        local c = st.carry[steam_id]
        if c.key then st.key_found = false st.searched[secret.key] = nil end
        if c.book then st.book_found = false st.searched[secret.book] = nil end
        st.carry[steam_id] = nil
        broadcast({})
    end
    last_pos[steam_id] = nil
end

-- =============================================================================
-- Rounds
-- =============================================================================

function host_new_round()
    if not IS_HOST then return end
    if not seeded then
        math.randomseed(math.floor(get_os_time_unix()))
        seeded = true
    end
    rebuild_objects()
    for n in pairs(st.drops) do destroy("", n) end
    st = fresh_state()
    tiles = {}
    vent_cd = {}
    last_pos = {}
    local lockers = by_kind.locker or {}
    secret.key = #lockers > 0 and lockers[math.random(1, #lockers)] or 0
    -- Pages hide in bins outside the locked office (no task waits on another).
    local bins = {}
    for _, id in ipairs(by_kind.bin or {}) do
        if objects[id].rk ~= "principal" then bins[#bins + 1] = id end
    end
    secret.pages = {}
    for _ = 1, PAGES_NEEDED do
        if #bins == 0 then break end
        local i = math.random(1, #bins)
        secret.pages[bins[i]] = true
        table.remove(bins, i)
    end
    local shelves = by_kind.shelf or {}
    secret.book = #shelves > 0 and shelves[math.random(1, #shelves)] or 0
    st.sinks_total = #(by_kind.sink or {})
    broadcast({ step = "reset" })
end

function host_end_round()
    if not IS_HOST then return end
    for n in pairs(st.drops) do destroy("", n) end
    st = fresh_state()
    tiles = {}
    run_network_function(name, "reset_ALL", {})
end

function reset_ALL(sender_id)
    st = fresh_state()
    pending_tiles = {}
    clear_local()
    refresh_hud()
end

-- Late joiner: the tile ledger (and the task state if it is a human).
function host_sync_to(steam_id)
    if not IS_HOST then return end
    if #tiles > 0 then run_network_function(name, "tiles_CLIENT", { tiles }, steam_id) end
    if run_function("-gm", "get_role", { steam_id }) == "human" then
        run_network_function(name, "state_CLIENT", { pack(), {} }, steam_id)
    end
end

function tiles_CLIENT(sender_id, list)
    for _, t in ipairs(list or {}) do
        tile_ALL(sender_id, t.x, t.y, t.name, t.old)
    end
end

-- school_gen finished painting on this peer.
function on_school_ready()
    rebuild_objects()
    for _, t in ipairs(pending_tiles) do
        run_function("-gen", "set_deco", { t.x, t.y, t.name, t.old })
    end
    pending_tiles = {}
    update_tracking()
end

-- =============================================================================
-- Local: state updates, HUD line, panel, tracking
-- =============================================================================

function state_CLIENT(sender_id, packed, event)
    st = unpack_state(packed)
    on_state(event or {})
end

function refresh_hud()
    if run_function("-gm", "get_role", { LOCAL_STEAM_ID }) ~= "human" then return end
    local line = string.format(translate("{tasks_progress}"), done_count(), #TASK_ORDER)
    local c = st.carry[LOCAL_STEAM_ID]
    if c then
        local items = {}
        if c.key then items[#items + 1] = "{item_key}" end
        if c.book then items[#items + 1] = "{item_book}" end
        if (c.pages or 0) > 0 then items[#items + 1] = string.format(translate("{item_pages_n}"), c.pages) end
        if #items > 0 then line = line .. "\n{carrying} " .. table.concat(items, ", ") end
    end
    line = line .. "\n@key_4@ {open_tasks}"
    run_function("-hud", "set_tasks_line", { line })
end

function on_state(event)
    if event.step == "found" then
        play_found()
        if event.by ~= LOCAL_STEAM_ID and FOUND_BY[event.task]
            and run_function("-gm", "get_role", { LOCAL_STEAM_ID }) == "human" then
            run_function("-hud", "banner", { string.format(translate(FOUND_BY[event.task]), tostring(event.nick or "?")), 4 })
        end
    end
    if event.task and event.step == "done" and tracked[event.task] then
        if event.by ~= LOCAL_STEAM_ID then
            run_function("-hud", "banner", { "{task_done_by_other}", 4 })
        end
        untrack(event.task)
    elseif event.task and event.step == "done" and event.by ~= LOCAL_STEAM_ID then
        run_function("-hud", "banner", { TASK_TITLE[event.task] .. " - {task_completed}", 3 })
    end
    -- A new round starts with every task tracked; the panel can switch them off.
    if event.step == "reset" and run_function("-gm", "get_role", { LOCAL_STEAM_ID }) == "human" then
        for _, t in ipairs(TASK_ORDER) do
            if not tracked[t] then tracked[t] = true end
        end
    end
    refresh_hud()
    if panel ~= "" and is_panel_exists(panel) then open_panel() end
    update_tracking()
end

local function status_of(t)
    if task_done(t) then return "{task_completed}" end
    if t == "key" then return st.key_found and "{key_status_carry}" or "{key_status_search}" end
    if t == "plan" then return string.format(translate("{plan_status}"), st.pages_done, PAGES_NEEDED, st.pages_found) end
    if t == "book" then return st.book_found and "{book_status_carry}" or "{book_status_search}" end
    if t == "sinks" then return string.format(translate("{sinks_status}"), st.sinks_off, st.sinks_total) end
    if not st.key_done then return "{computer_status_locked}" end
    return string.format(translate("{computer_status}"), math.floor(100 * st.comp / COMPUTER_SECONDS))
end

function toggle_panel()
    if panel ~= "" and is_panel_exists(panel) then
        close_panel(panel)
        panel = ""
    else
        open_panel()
    end
end

function open_panel()
    if run_function("-gm", "get_role", { LOCAL_STEAM_ID }) ~= "human" then return end
    if panel ~= "" and is_panel_exists(panel) then close_panel(panel) end
    panel_count = panel_count + 1
    panel = "_bc_tasks_" .. panel_count
    create_panel({ name = panel, title = "{tasks_title}", text = "{tasks_panel_text}", set_time = false,
        close = true, resizable = true, minimum_size = Vector2(480, 620) })
    for _, t in ipairs(TASK_ORDER) do
        local text = TASK_TITLE[t] .. "\n" .. status_of(t)
        if tracked[t] then text = text .. "   {tracking}" end
        local color = Color(0.3, 0.33, 0.38)
        if task_done(t) then color = Color(0.22, 0.45, 0.25)
        elseif tracked[t] then color = Color(0.25, 0.35, 0.6) end
        add_button_to_panel(panel, { entity_name = name, function_name = "on_task_button", text = text,
            extra_args = { task = t }, color = color })
    end
end

function on_task_button(args)
    local t = args.extra_args and args.extra_args.task
    if not t or not TASK_TITLE[t] then return end
    if tracked[t] then
        untrack(t)
    elseif not task_done(t) then
        tracked[t] = true
        update_tracking()
    end
    open_panel()
end

local function nearest(kind_name, px, py, skip)
    local best, best_d = nil, math.huge
    for _, id in ipairs(by_kind[kind_name] or {}) do
        local o = objects[id]
        if not skip or not skip(o) then
            local d = dist(px, py, o.wx, o.wy)
            if d < best_d then best, best_d = o, d end
        end
    end
    return best
end

local function first_of(kind_name)
    local ids = by_kind[kind_name] or {}
    return ids[1] and objects[ids[1]] or nil
end

local function drop_of(item)
    for _, d in pairs(st.drops) do
        if d.item == item then return d end
    end
    return nil
end

-- Where the arrow of task t points for this player right now (nil = nowhere).
local function target_of(t, px, py)
    local c = st.carry[LOCAL_STEAM_ID] or {}
    local function unsearched(o) return st.searched[o.id] end
    local o = nil
    if t == "key" then
        if st.key_done then return nil end
        if c.key or not st.key_found then
            if c.key then o = first_of("pdoor") else o = nearest("locker", px, py, unsearched) end
        else
            local d = drop_of("key")
            if d then return d.x, d.y end
            o = first_of("pdoor")
        end
    elseif t == "plan" then
        if task_done("plan") then return nil end
        if (c.pages or 0) > 0 or st.pages_found >= PAGES_NEEDED then
            local d = ((c.pages or 0) == 0) and drop_of("pages") or nil
            if d then return d.x, d.y end
            o = first_of("board")
        else
            o = nearest("bin", px, py, unsearched)
        end
    elseif t == "book" then
        if st.book_done then return nil end
        if c.book then
            o = first_of("desk")
        elseif st.book_found then
            local d = drop_of("book")
            if d then return d.x, d.y end
            o = first_of("desk")
        else
            o = nearest("shelf", px, py, unsearched)
        end
    elseif t == "sinks" then
        if task_done("sinks") then return nil end
        o = nearest("sink", px, py, function(s) return st.sink_off[s.id] end)
    elseif t == "computer" then
        if st.comp_done then return nil end
        o = st.key_done and first_of("computer") or first_of("pdoor")
    end
    if not o then return nil end
    return o.wx, o.wy
end

function untrack(t)
    local tr = tracked[t]
    tracked[t] = nil
    if type(tr) == "table" then
        if tr.icon and tr.icon ~= "" then destroy("", tr.icon) end
        if tr.sprite then destroy("", tr.sprite, false) end
    end
end

-- The arrow's target is an invisible world sprite. It is MOVED with set_image
-- (set_value "position" only moves physics bodies), and a destroyed sprite or
-- icon lingers until the frame ends - so every new one gets a fresh name.
function update_tracking()
    -- Before this peer's school is painted there is nothing to point at yet;
    -- keep the tracked tasks (on_school_ready runs this again).
    if next(objects) == nil then return end
    local me = get_value("", LOCAL_STEAM_ID, "position")
    if not me then return end
    for _, t in ipairs(TASK_ORDER) do
        if tracked[t] then
            local tx, ty = target_of(t, me.x, me.y)
            if not tx then
                untrack(t)
            else
                local tr = tracked[t]
                if type(tr) ~= "table" then
                    track_serial = track_serial + 1
                    tr = { sprite = "bc_track_" .. t .. "_" .. track_serial }
                    set_image({ name = tr.sprite, image_path = "tiles/clock", position = Vector2(tx, ty), visible = false })
                    tr.icon = set_navigation_icon({ name = "nav_bc_task_" .. t .. "_" .. track_serial,
                        target_name = tr.sprite, text = TASK_TITLE[t], color = TASK_COLOR[t], is_show_distance = true,
                        show_on_screen = true,
                        outline_color = Color(0, 0, 0, 1), outline_size = 8 })
                    tracked[t] = tr
                elseif tr.x ~= tx or tr.y ~= ty then
                    set_image({ name = tr.sprite, position = Vector2(tx, ty) })
                end
                tr.x, tr.y = tx, ty
            end
        end
    end
end

function clear_local()
    for _, t in ipairs(TASK_ORDER) do
        if tracked[t] then untrack(t) end
    end
    if panel ~= "" and is_panel_exists(panel) then close_panel(panel) end
    panel = ""
    run_function("-hud", "set_tasks_line", { "" })
end

function _process(delta, inputs)
    clock = clock + delta
    track_t = track_t - delta
    if track_t <= 0 then
        track_t = 0.5
        if next(tracked) then update_tracking() end
    end
    return nil
end

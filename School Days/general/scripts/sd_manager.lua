network_mode = 1
singleton_name = "sd_manager"

-- =============================================================================
-- School Days - host-authoritative story flow + all client HUD.
--
-- The engine's Visual Novel runtime (vn_*) holds the story graph and evaluates
-- conditions/variables; THIS script turns it into a co-op, vote-driven game:
--
--   * Every peer loads the same story and advances its OWN copy. The engine
--     never networks story state, so we keep everyone in lockstep the standard
--     host-authoritative way: the HOST decides what happens next and broadcasts
--     it with an "_ALL" call, and every peer runs the SAME vn_choose/vn_advance
--     locally. Variables and the current node therefore stay identical for all.
--
--   * On a choice node the host opens a VOTE. Clients tap a choice
--     (vote_HOST); the host tallies live and, when everyone has voted or the
--     60s timer runs out, broadcasts the winner (apply_choice_ALL). Ties and
--     empty votes are broken randomly ON THE HOST only (then broadcast), so the
--     result is still identical everywhere. Nodes tagged "notimer" have no clock.
--
--   * Narration nodes just flow: anyone can press Continue (continue_HOST) and
--     there is an auto-advance fallback so the story never stalls.
--
--   * Late joiners are re-synced: the host sends them the shared variables + the
--     current node id, and they seek to it (vn_goto with apply_enter_ops=false,
--     which jumps WITHOUT re-running the node's variable ops) and render.
--
-- Nothing here is VN-specific engine magic: choice ids + tags come back from
-- vn_choices, so a mod could attach any effect to a choice. This one keeps it to
-- a clean classic-VN presentation as a reference example.
-- =============================================================================

local STORY_PATH = "story/school_days.json"
local VOTE_TIME = 60      -- seconds to vote on a timed choice
local READ_TIME = 30      -- auto-advance fallback for narration nodes
local NOTIMER_TAG = "notimer"
local MAX_CHOICES = 6     -- must match the _choice1.._choice6 buttons in hud.json

local CHAPTERS = {
    chapter1 = "Chapter 1  ·  First Day",
    chapter2 = "Chapter 2  ·  The Project",
    chapter3 = "Chapter 3  ·  The Scandal",
    chapter4 = "Chapter 4  ·  The Festival",
}

-- Loaded once on every peer; vn callbacks come back to THIS entity.
story = vn_load(STORY_PATH)
vn_set_listener(name)

-- ---------- shared phase (mirrored on every peer for rendering) ----------
cl_choices = {}      -- this peer's snapshot of the current node's choices
cl_counts = {}       -- choice_id -> vote count (from the host)
cl_phase = "idle"    -- idle | narration | vote | ended
cl_secs = -1         -- seconds left (-1 = no clock)
cl_voted = 0
cl_total = 0
cl_myvote = ""       -- id this peer voted for (local highlight only)
cl_chapter = ""

-- ---------- HOST-only state ----------
started = false
phase = "idle"
voters = {}          -- steam_id -> true (everyone who may vote)
votes = {}           -- steam_id -> choice_id
deadline = 0         -- unix time the current window ends (0 = no clock)
enabled_ids = {}     -- choice_id -> true for the currently open node

-- =============================================================================
-- Helpers
-- =============================================================================
local function list_contains(list, value)
    if type(list) ~= "table" then return false end
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function count_keys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local function chapter_for(tags)
    for _, tag in ipairs(tags or {}) do
        if CHAPTERS[tag] then return CHAPTERS[tag] end
        if tag == "ending" then return "Ending" end
    end
    return cl_chapter -- unchanged if this node carries no chapter tag
end

-- =============================================================================
-- RENDERING (runs on every peer)
-- =============================================================================
function render_node(node)
    if type(node) ~= "table" or not node.id then return end
    set_image({ name = "_bg", image_path = (node.bg ~= "" and node.bg) or "bg_class" })
    if node.char ~= "" and node.image ~= "" then
        set_image({ name = "_char", image_path = node.image, visible = true })
    else
        set_image({ name = "_char", visible = false })
    end
    set_label({ name = "_speaker", text = node.char_name or "",
        font_color = (node.char_color ~= "" and node.char_color) or "(1,1,1,1)" })
    set_label({ name = "_dialog", text = node.text or "" })
    cl_chapter = chapter_for(node.tags)
    set_label({ name = "_hint", text = cl_chapter })
    if node.sound and node.sound ~= "" then
        set_audio({ stream_path = node.sound })
    end
    cl_choices = vn_choices(story)
    cl_myvote = ""
    -- Hide all buttons during the brief gap before the host's status_ALL arrives
    -- (which sets the real phase); avoids a flash of the wrong buttons.
    cl_phase = "wait"
    render_buttons()
end

-- Show/hide the choice buttons + Continue/Restart for the current phase.
function render_buttons()
    for i = 1, MAX_CHOICES do
        local c = cl_choices[i]
        if cl_phase == "vote" and c then
            local label = c.text
            local n = cl_counts[c.id]
            if n and n > 0 then label = label .. "   (" .. n .. ")" end
            local tint = "(1,1,1,1)"
            if not c.enabled then
                label = "🔒 " .. label
                tint = "(0.5,0.52,0.58,1)"
            elseif c.id == cl_myvote then
                tint = "(0.55,0.95,0.6,1)" -- your current pick
            end
            set_button({ name = "_choice" .. i, text = label, visible = true, modulate = tint })
        else
            set_button({ name = "_choice" .. i, visible = false })
        end
    end
    set_button({ name = "_continue", visible = (cl_phase == "narration") })
    set_button({ name = "_restart", visible = (cl_phase == "ended" and IS_HOST) })
    set_button({ name = "_start", visible = (cl_phase == "idle" and IS_HOST) })
end

function render_status()
    local text = ""
    if cl_phase == "vote" then
        text = "Vote  " .. cl_voted .. "/" .. cl_total
        if cl_secs >= 0 then text = text .. "   ·   " .. cl_secs .. "s" end
    elseif cl_phase == "narration" then
        text = "Continue when ready"
    elseif cl_phase == "ended" then
        text = "The End"
    end
    set_label({ name = "_status", text = text })
end

-- Host pushes the live vote tally + clock + phase to everyone (incl. itself).
function status_ALL(sender_id, data)
    cl_phase = data.phase
    cl_counts = data.counts or {}
    cl_secs = data.secs
    cl_voted = data.voted or 0
    cl_total = data.total or 0
    render_status()
    render_buttons()
end

-- =============================================================================
-- VN CALLBACKS (fire on every peer inside vn_start/advance/choose)
-- =============================================================================
function _on_vn_node(story_id, node)
    if story_id ~= story then return end
    render_node(node)
    if IS_HOST then host_setup_node(node) end
end

function _on_vn_end(story_id, node_id)
    if story_id ~= story or not IS_HOST then return end
    phase = "ended"
    deadline = 0
    broadcast_status()
end

-- =============================================================================
-- HOST: set up the window that follows each node
-- =============================================================================
function host_setup_node(node)
    votes = {}
    enabled_ids = {}
    if node.is_end then
        phase = "ended"
        deadline = 0
        broadcast_status()
        return
    end
    if node.has_choices then
        phase = "vote"
        local choices = vn_choices(story)
        for _, c in ipairs(choices) do
            if c.enabled then enabled_ids[c.id] = true end
        end
        local timed = not list_contains(node.tags, NOTIMER_TAG)
        deadline = timed and (get_os_time_unix() + VOTE_TIME) or 0
    else
        phase = "narration"
        deadline = get_os_time_unix() + READ_TIME
    end
    broadcast_status()
end

function secs_left()
    if deadline == 0 then return -1 end
    return math.max(0, deadline - get_os_time_unix())
end

function broadcast_status()
    if not IS_HOST then return end
    run_network_function(name, "status_ALL", { {
        phase = phase,
        counts = tally(),
        secs = secs_left(),
        voted = count_keys(votes),
        total = count_keys(voters),
    } })
end

function tally()
    local counts = {}
    for _, id in pairs(votes) do
        counts[id] = (counts[id] or 0) + 1
    end
    return counts
end

-- =============================================================================
-- HOST: per-second tick drives both the vote clock and narration auto-advance
-- =============================================================================
function tick(args)
    if not IS_HOST or not started then return end
    if phase == "vote" then
        if deadline > 0 and get_os_time_unix() >= deadline then
            resolve_vote()
        else
            broadcast_status()
        end
    elseif phase == "narration" then
        if deadline > 0 and get_os_time_unix() >= deadline then
            do_advance()
        else
            broadcast_status()
        end
    end
end

-- =============================================================================
-- HOST: begin / resolve / advance
-- =============================================================================
function begin_story()
    if not IS_HOST or started then return end
    if story == "" then return end
    started = true
    voters[LOCAL_STEAM_ID] = true -- the host votes too
    run_network_function(name, "apply_start_ALL", { {} })
    stop_timer("sd_tick")
    start_timer({ timer_id = "sd_tick", entity_name = name,
        function_name = "tick", wait_time = 1 })
end

function resolve_vote()
    if not IS_HOST or phase ~= "vote" then return end
    -- Tally only votes cast for currently-enabled choices.
    local counts = {}
    for _, id in pairs(votes) do
        if enabled_ids[id] then counts[id] = (counts[id] or 0) + 1 end
    end
    -- Winner = most votes; ties broken randomly. No votes = random enabled.
    local best = -1
    local leaders = {}
    for id, n in pairs(counts) do
        if n > best then best = n; leaders = { id }
        elseif n == best then table.insert(leaders, id) end
    end
    if #leaders == 0 then
        for id in pairs(enabled_ids) do table.insert(leaders, id) end
    end
    if #leaders == 0 then return end -- nothing selectable (shouldn't happen)
    local winner = leaders[math.random(1, #leaders)]
    phase = "resolving"
    deadline = 0
    run_network_function(name, "apply_choice_ALL", { { id = winner } })
end

function do_advance()
    if not IS_HOST or phase ~= "narration" then return end
    phase = "resolving"
    deadline = 0
    run_network_function(name, "apply_advance_ALL", { {} })
end

-- =============================================================================
-- NETWORK: authoritative broadcasts every peer applies identically
-- =============================================================================
function apply_start_ALL(sender_id, data)
    vn_start(story) -- resets vars, enters the start node, fires _on_vn_node
end

function apply_advance_ALL(sender_id, data)
    vn_advance(story)
end

function apply_choice_ALL(sender_id, data)
    vn_choose(story, data.id)
end

-- =============================================================================
-- NETWORK: client -> host intents (host validates)
-- =============================================================================
function vote_HOST(sender_id, data)
    if not IS_HOST or phase ~= "vote" then return end
    if not voters[sender_id] then return end
    if not enabled_ids[data.id] then return end -- ignore locked / unknown choices
    votes[sender_id] = data.id
    broadcast_status()
    -- Resolve early once every current voter has picked.
    if count_keys(votes) >= count_keys(voters) then
        resolve_vote()
    end
end

function continue_HOST(sender_id, data)
    if not IS_HOST or phase ~= "narration" then return end
    do_advance()
end

-- =============================================================================
-- HUD button handlers (called via run_function on the presser's peer)
-- =============================================================================
function start_click(args)
    run_network_function(name, "start_HOST", { {} })
end

function start_HOST(sender_id, data)
    -- Only the host may start; guard even though only the host sees the button.
    if not IS_HOST then return end
    if sender_id ~= HOST_STEAM_ID and tostring(sender_id) ~= HOST_STEAM_ID then return end
    begin_story()
end

function choice_click(slot)
    local c = cl_choices[slot]
    if cl_phase ~= "vote" or not c or not c.enabled then return end
    cl_myvote = c.id
    render_buttons() -- instant local feedback; real tally comes from the host
    run_network_function(name, "vote_HOST", { { id = c.id } })
end

function continue_click(args)
    if cl_phase ~= "narration" then return end
    run_network_function(name, "continue_HOST", { {} })
end

function restart_click(args)
    if not IS_HOST then return end
    started = false
    begin_story()
end

-- =============================================================================
-- LATE JOINERS: host catches them up to the current node + variables
-- =============================================================================
function _on_user_initialized(steam_id, nickname)
    if not IS_HOST then return end
    voters[steam_id] = true
    if not started then
        broadcast_status()
        return
    end
    -- Send this one peer the shared variables + current node so they can seek to
    -- it (without re-running the node's ops) and render. Targeted _ALL: the host
    -- also receives it locally but ignores it (guard below).
    local node = vn_current(story)
    run_network_function(name, "sync_state_ALL", { {
        node = node.id or "",
        vars = vn_get_vars(story),
        phase = phase,
        counts = tally(),
        secs = secs_left(),
        voted = count_keys(votes),
        total = count_keys(voters),
    } }, tostring(steam_id))
    broadcast_status() -- refresh everyone's voted/total
end

function _on_user_disconnected(steam_id, nickname)
    if not IS_HOST then return end
    voters[steam_id] = nil
    votes[steam_id] = nil
    if phase == "vote" then
        broadcast_status()
        if count_keys(voters) > 0 and count_keys(votes) >= count_keys(voters) then
            resolve_vote()
        end
    end
end

function sync_state_ALL(sender_id, data)
    if IS_HOST then return end -- the host is already at this state
    for var_name, value in pairs(data.vars or {}) do
        vn_set_var(story, var_name, value)
    end
    -- Pure seek: jump to the host's node WITHOUT re-applying its variable ops.
    vn_goto(story, data.node, false)
    render_node(vn_current(story))
    cl_phase = data.phase
    cl_counts = data.counts or {}
    cl_secs = data.secs
    cl_voted = data.voted or 0
    cl_total = data.total or 0
    render_status()
    render_buttons()
end

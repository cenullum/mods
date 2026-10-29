singleton_name = "team_balancer"
-- =============================================================================
-- Football - who plays on which team.
--
-- Decided on the host, and only when something happens: a player arrives or
-- leaves, someone asks to switch, a bot is added or removed. Nothing here runs
-- per frame.
--
--   * A player who arrives goes to the smaller team (bots count: they hold a
--     slot like anyone else).
--   * Anyone can switch team from their own row in the score table. A switch
--     that would leave the teams more than MAX_DIFF apart is refused, and the
--     player stays where they were. They may instead wait as a spectator; the
--     queue is served first come, first served whenever a slot opens.
--   * When a leave makes the teams lopsided and nobody in the queue fits, the
--     player who joined the bigger team most recently is moved across, with a
--     chat notice.
--   * An admin (the host, or a dedicated server's owner) can still put anyone
--     anywhere from the score table; those moves skip the rules.
--
-- The same rules apply on a listen host and on a dedicated server.
-- =============================================================================

MAX_DIFF = 1

queue = {}       -- host: { { id = steam_id, team = 1|2 }, ... } in arrival order
team_since = {}  -- host: steam_id -> sequence number of their latest team change
sequence = 0

local function users()
    return run_function("-ui_manager", "get_users_table") or {}
end

local function team_of(data)
    return math.floor(tonumber(data.team) or 0)
end

local function team_sizes(skip_id)
    local sizes = { [1] = 0, [2] = 0 }
    for id, data in pairs(users()) do
        local t = team_of(data)
        if id ~= skip_id and (t == 1 or t == 2) then
            sizes[t] = sizes[t] + 1
        end
    end
    return sizes
end

local function other_team(team)
    return team == 1 and 2 or 1
end

-- Would `team` still be fair with one more player on it?
local function fits(team, sizes)
    return (sizes[team] + 1) - sizes[other_team(team)] <= MAX_DIFF
end

local function smaller_team(sizes)
    if sizes[1] == sizes[2] then
        return math.random(1, 2)
    end
    return sizes[1] < sizes[2] and 1 or 2
end

local function remove_from_queue(steam_id)
    for i = #queue, 1, -1 do
        if queue[i].id == steam_id then
            table.remove(queue, i)
        end
    end
end

-- A private message to one player, in their own language.
local function tell(steam_id, token)
    run_network_function(name, "tell_CLIENT", { token }, steam_id)
end

function tell_CLIENT(sender_id, token)
    add_to_chat(token)
end

-- The single place a human player changes team: the scoreboard, the body on
-- every peer (change_team_ALL also moves the voice channel on the host), and
-- the auto-start check, which depends on who is on a team.
local function set_team(steam_id, team)
    run_function("-ui_manager", "move_team", { steam_id, team })
    run_network_function(steam_id, "change_team_ALL", { team })
    sequence = sequence + 1
    team_since[steam_id] = sequence
    run_function("-ui_manager", "check_auto_start")
end

-- Hand out free slots to the queue, oldest request first.
function serve_queue()
    if not IS_HOST then return end
    local i = 1
    while i <= #queue do
        local entry = queue[i]
        local data = users()[entry.id]
        if data == nil then
            table.remove(queue, i)
        elseif fits(entry.team, team_sizes(entry.id)) then
            table.remove(queue, i)
            set_team(entry.id, entry.team)
            tell(entry.id, "{queue_your_turn}")
        else
            i = i + 1
        end
    end
end

-- Serve the queue, then even the teams out if a leave tipped them over.
function rebalance()
    if not IS_HOST then return end
    serve_queue()
    local sizes = team_sizes(nil)
    if math.abs(sizes[1] - sizes[2]) <= MAX_DIFF then return end
    local big = sizes[1] > sizes[2] and 1 or 2
    local pick, pick_seq = nil, -1
    for id, data in pairs(users()) do
        if not data.is_bot and team_of(data) == big and (team_since[id] or 0) > pick_seq then
            pick, pick_seq = id, team_since[id] or 0
        end
    end
    if pick ~= nil then
        local nickname = users()[pick].nickname or ""
        set_team(pick, other_team(big))
        add_to_chat(nickname .. "{auto_balanced}", true)
    end
end

function on_player_joined(steam_id)
    if not IS_HOST then return end
    local data = users()[steam_id]
    if data == nil or data.is_bot then return end
    set_team(steam_id, smaller_team(team_sizes(steam_id)))
end

function on_player_left(steam_id)
    if not IS_HOST then return end
    remove_from_queue(steam_id)
    team_since[steam_id] = nil
    rebalance()
end

-- From a player's own row in the score table. wait: when the move is unfair,
-- queue as a spectator instead of staying put.
function request_team_HOST(sender_id, team, wait)
    if not IS_HOST then return end
    team = math.floor(tonumber(team) or -1)
    if team ~= 0 and team ~= 1 and team ~= 2 then return end
    local data = users()[sender_id]
    if data == nil or data.is_bot then return end
    remove_from_queue(sender_id)
    if team == team_of(data) then return end
    if team == 0 then
        set_team(sender_id, 0)
        rebalance()
        return
    end
    if fits(team, team_sizes(sender_id)) then
        set_team(sender_id, team)
        rebalance()
        return
    end
    if wait == true then
        if team_of(data) ~= 0 then
            set_team(sender_id, 0)
        end
        table.insert(queue, { id = sender_id, team = team })
        tell(sender_id, "{queue_waiting}")
        rebalance()
    else
        run_network_function(name, "switch_refused_CLIENT", { team }, sender_id)
    end
end

-- The switch would have been unfair: the player stayed where they were. Offer
-- to wait for the team as a spectator instead.
function switch_refused_CLIENT(sender_id, team)
    local panel = create_panel({
        title = "{team_switch_refused_title}",
        text = "{team_switch_refused}",
        name = "football_team_refused_id",
        no_multiple_tag = "football_team_refused",
        resizable = false,
    })
    add_button_to_panel(panel, {
        text = "{wait_as_spectator}",
        is_vertical = true,
        color = Color(1, 1, 1),
        entity_name = name,
        function_name = "wait_for_team",
        extra_args = { team = team },
    })
    add_button_to_panel(panel, {
        text = "{stay_in_my_team}",
        is_vertical = true,
        color = Color(0.4, 0.8, 0.4),
        entity_name = name,
        function_name = "close_refused_panel",
    })
end

function wait_for_team(args)
    run_network_function(name, "request_team_HOST", { args.extra_args.team, true })
    close_panel(args.panel_name)
end

function close_refused_panel(args)
    close_panel(args.panel_name)
end

-- Admin moves skip the fairness rules (the admin decides), but still serve
-- whoever was waiting for the slot that was freed.
function admin_set_team_HOST(sender_id, target_id, team)
    if not IS_HOST or not is_admin(sender_id) then return end
    team = math.floor(tonumber(team) or -1)
    if team ~= 0 and team ~= 1 and team ~= 2 then return end
    local data = users()[target_id]
    if data == nil or data.is_bot then return end
    remove_from_queue(target_id)
    set_team(target_id, team)
    serve_queue()
end

math.randomseed(math.floor(get_os_time_unix()))

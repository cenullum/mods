singleton_name = "cmd"
network_mode = 0

-- =============================================================================
-- Beyaz Canavar - chat commands. A command runs only on the machine of whoever
-- typed it, so everything that changes the game is forwarded to the host.
--   /start  host: start now; others: start a vote (if the host allows votes)
--   /seed   show the seed of the current school
--   /testboss  host only, for testing: play as the monster (starts a round from
--              the lobby); the round does not end on its own while testing -
--              type /testboss again to stop and go back to the lobby
-- =============================================================================

add_command("-cmd", "cmd_start", "start", "{cmd_start_desc}", true)
add_command("-cmd", "cmd_seed", "seed", "{cmd_seed_desc}", true)
add_command("-cmd", "cmd_testboss", "testboss", "{cmd_testboss_desc}", true)

function cmd_start(sender_id)
    run_network_function("-gm", "request_start_HOST", {})
end

function cmd_seed(sender_id)
    local s = math.floor(tonumber(get_value("", "-gm", "seed_value")) or 0)
    if s > 0 then
        add_to_chat(string.format(translate("{current_seed}"), s))
    else
        add_to_chat("{no_seed_yet}")
    end
end

function cmd_testboss(sender_id)
    run_network_function("-gm", "request_testboss_HOST", {})
end

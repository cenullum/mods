singleton_name = "cmd"

-- Register commands to the centralized system
add_command("-cmd", "show_fishing_help", "fishing", "Shows fishing game controls and tips", true)
add_command("-cmd", "teleport_to_spawn_point", "spawn_point", "Teleport to spawn point and reset position/velocity",
    true)
add_command("-cmd", "change_spawn_point", "change_spawn_point",
    "[x:number] [y:number] (Host only) Change spawn point position ", true)



-- Function to show fishing game help
function show_fishing_help()
    local fishing_text = "FISHING GAME CONTROLS:\n\n"

    fishing_text = fishing_text .. "HOOK CONTROLS:\n"
    fishing_text = fishing_text .. "• Hold @key_7@ to charge hook power\n"
    fishing_text = fishing_text .. "• Release @key_7@ to fire hook\n"
    fishing_text = fishing_text .. "• Press @key_7@ while hooked to launch yourself\n"
    fishing_text = fishing_text .. "• Press @key_7@ during firing to cancel\n\n"

    fishing_text = fishing_text .. "FISHING MECHANICS:\n"
    fishing_text = fishing_text .. "• Hook onto fish to start fishing minigame\n"
    fishing_text = fishing_text .. "• Follow the traffic light signals\n"
    fishing_text = fishing_text .. "• Green = Reel in, Red = Stop\n"
    fishing_text = fishing_text .. "• Manage your health vs fish health\n\n"

    fishing_text = fishing_text .. "TIPS:\n"
    fishing_text = fishing_text .. "• Different fish have different difficulties\n"
    fishing_text = fishing_text .. "• Watch your hook power - higher power = further range\n"
    fishing_text = fishing_text .. "• Use platforms to get better fishing positions\n"
    fishing_text = fishing_text .. "• Some areas have better fish than others\n"

    local message_config = {
        title = "Fishing Game Help",
        text = fishing_text,
        resizable = true,

    }
    create_panel(message_config)
end



-- Command Wrapper functions
-- These are called locally by add_command and they trigger network functions

function teleport_to_spawn_point()
    run_network_function("-cmd", "teleport_to_spawn_point_HOST", {})
end

function change_spawn_point(x, y)
    run_network_function("-cmd", "change_spawn_point_ALL", { x, y })
end



-- HOST function: Handle teleport to spawn point request
function teleport_to_spawn_point_HOST(sender_id)
    local spawn_position = get_value("", "-spawn_point", "position")

    change_instantly({
        entity_name = sender_id,
        angular_velocity = 0.0,
        position = spawn_position,
        linear_velocity = Vector2(0, 0),
        rotation = 0.0
    })
end

function change_spawn_point_ALL(sender_id, x, y)
    -- Validate parameters
    if not x or not y then
        add_to_chat("[color=#ff8066][b]Error: Missing parameters! Usage: /change_spawn_point x y[/b][/color]", false)
        return
    end

    -- Convert to numbers and validate
    local pos_x = tonumber(x)
    local pos_y = tonumber(y)

    if not pos_x or not pos_y then
        add_to_chat("[color=#ff8066][b]Error: Invalid parameters! x and y must be numbers[/b][/color]", false)
        return
    end

    -- Check for reasonable bounds (optional safety check)
    if pos_x < -10000 or pos_x > 10000 or pos_y < -10000 or pos_y > 10000 then
        add_to_chat(
            "[color=#ff8066][b]Error: Position values too extreme! Use values between -10000 and 10000[/b][/color]",
            false)
        return
    end

    -- Update spawn point position
    local new_position = Vector2(pos_x, pos_y)
    set_value("", "-spawn_point", "position", new_position)

    -- Confirm the change
    add_to_chat("[color=#66FF99][b]Spawn point updated to position (" .. pos_x .. ", " .. pos_y .. ")[/b][/color]", true)
end

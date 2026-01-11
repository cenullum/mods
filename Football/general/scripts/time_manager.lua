singleton_name = "time_manager"

is_match_active = false




function start_time_ALL(sender_id,new_time_limit) -- new_time_limit is in minutes if it is not infinite
    is_match_active = true
    -- Convert minutes to seconds for duration
    if new_time_limit~="∞" then-- if not infinite
        duration = new_time_limit * 60
    end

    -- Show initial time
    if new_time_limit~="∞" then
        set_label({
        name = "_time_label",
        text = format_time(duration)
        })
    else
        set_label({
        name = "_time_label",
        text = "00:00"
        })
    end

    -- Clear game over text
    set_label({
    name = "_center_label",
    text = ""
    })

    if new_time_limit~="∞" then
        start_timer({
        timer_id="match_time",
        entity_name = name,
        function_name = "update_timer",
        wait_time = 1.0,
        duration = duration
        })
    else
        start_timer({
        timer_id="match_time",
        entity_name = name,
        function_name = "update_timer",
        wait_time = 1.0,
        })
    end
end

function update_timer(args)
    if args.duration==nil then
        set_label({
        name = "_time_label",
        text = format_time(args.iteration_count)
        })
        return
    end
    if args.is_last_iteration then
        match_is_over()
        return
    end
    -- Since wait_time is 1 second, we can directly use iteration_count as elapsed seconds.
    -- If wait_time was different (e.g. 2 seconds), we would need to:
    -- 1. Calculate elapsed time as: wait_time * iteration_count
    -- 2. Calculate remaining time as: duration - (wait_time * iteration_count)
    remaining_time=args.duration-args.iteration_count
    set_label({
    name = "_time_label",
    text = format_time(remaining_time)
    })
end

function match_is_over()
    is_match_active = false
    set_label({
    name = "_time_label",
    text = "00:00"
    })

    if IS_HOST then
        run_function("-ui_manager", "determine_winner")
    end
end


-- Function to format time as MM:SS
function format_time(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining_seconds = seconds % 60
    return string.format("%02d:%02d", minutes, remaining_seconds)
end





network_mode = 1
singleton_name = "golden_flag"
freeze=true
--lock_rotation = true
--linear_damp = 0
--ravity_scale = 0

-- Configuration
image_name = set_image({parent_name=name, image_path="golden_flag",z_index = 10})

area_config = {
    parent_name = name,
    shape = "circle",
    size = 32,
    collision_layer = {2},
    collision_mask = {2}
}   
area_name = set_area(area_config)
-- State
local winner_name = nil

local reset_timer_duration = 20.0
local reset_timer_id = "golden_flag_reset_timer"

-- Create confetti particle
confetti_particle_id = create_particle({
    particle_id = "golden_flag_confetti",
    texture_path = "white_8",
    lifetime = 8.0,
    amount = 100,
    explosiveness = 0.5,
    randomness = 0.5,
    one_shot = true,
    local_coords = false,
    spread = 360.0,
    initial_velocity_min = 50.0,
    initial_velocity_max = 200.0,
    angular_velocity_min = -180.0,
    angular_velocity_max = 180.0,
    gravity = {x = 0, y = 98},
    scale_amount_min = 0.3,
    scale_amount_max = 1.0,
    --color_random = true,
    hue_variation_min = 0.0,
    hue_variation_max = 1.0
})

function is_table_empty(t)
    return next(t) == nil
end

-- Called when a body enters the flag area
function on_area_body_entered(body_name)

    if not IS_HOST then return end
    if not has_tag(body_name, "user") then return end

    timer_data=get_timer_data(reset_timer_id)
    if is_table_empty(timer_data) == false then 
        return 
    end-- if it is not empty, then the timer is running
    winner_name = get_value("", body_name, "nickname") or body_name
    run_network_function(name, "show_golden_flag_win_ALL", {winner_name})
    start_reset_timer()
    handle_minigame_interrupts()
end



function start_reset_timer()
    -- Teleport all users to (0,0)
    -- Start 20s timer
    start_timer({
        timer_id = reset_timer_id,
        entity_name = name,
        function_name = "on_reset_timer_finished",
        wait_time = reset_timer_duration,
        duration = reset_timer_duration
    })
    -- Block minigames (fishing, liar, etc.)
    run_function("-fishing_game", "block_minigames", {true})
    run_function("-finding_liar_manager", "block_minigames", {true})
end

function on_reset_timer_finished(args)
    -- Unblock minigames
    run_function("-fishing_game", "block_minigames", {false})
    run_function("-finding_liar_manager", "block_minigames", {false})

    local users = get_entity_names_by_tag("user")
	local spawn_position=get_value("","-spawn_point","position")
	
	
	
    for _, user in ipairs(users) do
        change_instantly({
            entity_name = user,
            angular_velocity = 0.0,
            position = spawn_position,
            linear_velocity = Vector2(0, 0),
            rotation = 0.0
        })
    end

    
    -- Optionally respawn flag or reset state
end

function handle_minigame_interrupts()
    -- Interrupt fishing for all players
    run_function("-fishing_game", "force_escape_all", {})
    -- Interrupt finding liar if needed (implement in manager)
    run_function("-finding_liar_manager", "interrupt_game", {})
end

-- Client-side: Show win message
function show_golden_flag_win_ALL(sender_id, winner)
    -- Trigger confetti effect at flag position

    
    -- Create multiple confetti bursts for extra celebration
    for i = 1, 10 do
        local offset_x = (math.random() - 0.5) * 200 -- Random offset within 100 pixels
        local offset_y = (math.random() - 0.5) * 100  -- Random offset within 50 pixels
        
        start_particle({
            particle_id = "golden_flag_confetti",
            position = Vector2( position.x + offset_x,position.y + offset_y - 100),
            instance_name = "confetti_burst_" .. i
        })
    end
    
    -- Use PopupManager.create_panel via Lua to show a center message
    create_panel({
        title = "🏆 Golden Flag Victory 🏆",
        text = "[center]🎉 [color=gold][b]" .. winner .. "[/b][/color] 🎉\n\n[color=yellow]✨ Touched the [shake freq=5.0 level=10][color=gold]Golden Flag[/color][/shake] and achieved [rainbow freq=0.5 sat=1 val=1]VICTORY[/rainbow]! ✨[/color]\n\n[color=orange]⏰ Game will reset in [b]20 seconds[/b] ⏰[/color][/center]",
        resizable = false,
        countdown = 20,
        color=Color(0.5, 0.47, 0.15, 1),
        no_multiple_tag = "golden_flag_win",
        offset_ratio = Vector2(0.5, 0.5), -- Center of screen
        font_size = 24,
        
        font_color = Color(1, 0.95, 0.3, 1) -- Brighter golden color
    })
end




singleton_name = "campfire"

image_name=set_image({parent_name=name,image_path="campfire0"})

area_config={
parent_name=name,
shape="circle",
size=32,
collision_layer = {2},
collision_mask = {2}
}
set_area(area_config)

wave_state="inactive"
current_time = 0

if IS_HOST then
    set_label({
        parent_name = "",
        name = "_center_information",
        text ="{go_to_campfire_to_start_wave}",
        font_color = Color(1, 1, 1, 1)
    })
end



-- Function to add underwater effect to music during cooldown
function add_underwater_effect()
    add_audio_effect({
        bus_name = "Music",
        effect_type = "lowpass",
        effect_config = {
            cutoff_hz = 800.0,
            resonance = 0.8
        }
    })
end



function set_wave_state_ALL(sender_id,state,_current_time)
    wave_state = state

    if state == "active" then
        clear_bus_effects({bus_name = "Music"})

        if is_panel_exists("upgrade_panel") then
            close_panel("upgrade_panel")
        end
        
        -- Start time counter with current time if provided
        timer_data = get_timer_data("time_counter")

        
        if next(timer_data) == nil then
            start_timer({
                entity_name = name,
                timer_id = "time_counter",
                wait_time = 1.0,
                function_name = "update_time_display",
                iteration_count = _current_time or 0
            })
        end

    elseif state == "inactive" then
        clear_bus_effects({bus_name = "Music"})
        
        current_time = 0
        stop_timer("time_counter")
    elseif state == "cooldown" then
        -- Add underwater effect to music during cooldown
        add_underwater_effect()
    end

end

function animation(args)
    if wave_state~="active" then
        image_name= set_image({parent_name=name,name=image_name,image_path="campfire0"})
        return
    end

    -- Use iteration_count to determine which frame to show
    if args.iteration_count % 2 == 0 then
        image_name= set_image({parent_name=name,name=image_name,image_path="campfire1"})
    else
        image_name= set_image({parent_name=name,name=image_name,image_path="campfire2"})
    end
end

start_timer({
timer_id="animation",
entity_name = name,
function_name = "animation",
wait_time = 0.25,
})

navigation_name=set_navigation_icon({
target_name=name,
is_rotate= true,
text="{campfire}",
outline_color=Color(0,0,0,1),
outline_size=8,
is_show_distance=true,
})

is_interact_campfire_input_last = false
interaction_value = 0
is_campfire_interactable = false

function _process(delta, inputs)
    local is_interact_campfire_input_new = inputs["key_6"]

    -- Only host can interact with campfire and fill the progress bar
    if IS_HOST and is_interact_campfire_input_new and is_campfire_interactable and wave_state~="active" then
        interaction_value = math.min(interaction_value + 100 * delta, 100)

        set_progress_bar({parent_name=name, name="interaction_progress_bar", value=interaction_value, position=Vector2(-32, 32), size=Vector2(64, 8),visible=true})

        if interaction_value == 100 then
            start_game()
        end
    end

    -- Check if button was released after being pressed
    if IS_HOST and is_interact_campfire_input_last == true and is_interact_campfire_input_new == false then
        set_progress_bar({parent_name=name, name="interaction_progress_bar",visible=false})
        interaction_value = 0
    end

    is_interact_campfire_input_last = is_interact_campfire_input_new

    return inputs
end

function start_game()
    run_function("-wm","wave_trigger")

    -- Tell everyone what they are actually training for: the Guardian shows up
    -- BOSS_TIME seconds in, whether or not they are ready for it.
    if IS_HOST then
        local boss_minutes = math.floor((get_value("", "-bm", "BOSS_TIME") or 1800) / 60)
        add_to_chat("[color=#ddcc77]"
            .. string.format(translate("{boss_arrives_in_minutes_get_stronger}"), boss_minutes)
            .. "[/color]", true)
    end

    set_progress_bar({
    parent_name=name,
    name="interaction_progress_bar",
    visible=false})

    if IS_HOST then
        set_label({
        parent_name = "",
        name = "_center_information",
        text = "",
        font_color = Color(1, 1, 1, 1)
        })
    end
end

function set_campfire_interactable(state)
    _text="{go_to_campfire_to_start_wave}"
    is_campfire_interactable=state

    if is_campfire_interactable then
        _text="{hold_key_6_to_start_wave}"
    end

    if wave_state=="active" then
        _text=""
        is_campfire_interactable=false
    end

    if IS_HOST then
        set_label({
        parent_name = "",
        name = "_center_information",
        text = _text,
        font_color = Color(1, 1, 1, 1)
        })
    end
end

function on_area_body_entered(area_name)
    if area_name == LOCAL_STEAM_ID then
        set_campfire_interactable(true)
    end
end

function on_area_body_exited(area_name)
    if area_name == LOCAL_STEAM_ID then
        set_campfire_interactable(false)
        set_progress_bar({parent_name=name, name="interaction_progress_bar",visible=false})
    end
end

function _on_user_initialized(steam_id,nickname)
    -- This will be called when a client has fully downloaded and initialized
    -- Safe to call network functions now for this client

    if IS_HOST then
        -- To sync to players who just joined game
        run_network_function(name, "set_wave_state_ALL", {wave_state, current_time})
    end
end

function reset_campfire_state()
    if IS_HOST then
        interaction_value = 0
        is_campfire_interactable = false
        is_interact_campfire_input_last = false

        image_name = set_image({parent_name=name, name=image_name, image_path="campfire0"})

        set_progress_bar({
            parent_name = name,
            name = "interaction_progress_bar",
            visible = false
        })

        set_label({
            parent_name = "",
            name = "_center_information",
            text ="{go_to_campfire_to_start_wave}",
            font_color = Color(1, 1, 1, 1)
        })
    end
end

function update_time_display(args)
    -- Update current_time with iteration count
    current_time = args.iteration_count
    local minutes = math.floor(current_time / 60)
    local seconds = current_time % 60
    set_label({
        name = "_time_label",
        text = string.format(translate("{time_label}"),
            string.format("%02d", math.floor(minutes)), string.format("%02d", math.floor(seconds)))
    })

    -- This clock is the run's survival time, so the host uses it as the single
    -- source of truth for when the boss is due.
    if IS_HOST then
        run_function("-bm", "check_boss_time", { current_time })
    end
end






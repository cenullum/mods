network_mode = 1
singleton_name = "fishing_game_ui"



function start_fishing_CLIENT(sender_id)
    print("start_fishing_CLIENT")
  

    set_label({name = "_fishing_score", visible = true})
    set_label({name = "_fish_name_label", visible = true})
    set_image({name = "_fish_image", visible = true})
    set_label({name = "_player_health_label", visible = true})
    set_progress_bar({name = "_player_health_bar", visible = true})
    set_label({name = "_fish_health_label", visible = true})
    set_progress_bar({name = "_fish_health_bar", visible = true})
    set_image({name = "_traffic_light", visible = true})
    set_label({name = "_timer_label", visible = true})
    set_image({name = "_background", visible = true})
    print("All fishing UI elements set to visible")
end

function disable_fishing_ui()

    set_label({name = "_fishing_score", visible = false})
    set_label({name = "_fish_name_label", visible = false})
    set_image({name = "_fish_image", visible = false})
    set_label({name = "_player_health_label", visible = false})
    set_progress_bar({name = "_player_health_bar", visible = false})
    set_label({name = "_fish_health_label", visible = false})
    set_progress_bar({name = "_fish_health_bar", visible = false})
    set_image({name = "_traffic_light", visible = false})
    set_label({name = "_timer_label", visible = false})
    set_image({name = "_background", visible = false})

end

function start_fishing_game_CLIENT(sender_id, fish_name, fish_weight, fish_health, max_fish_health, fish_image, fish_rarity, fish_water_source)
    print("start_fishing_game_CLIENT")
    -- Update fish info
    local fish_weight_pounds = math.floor(fish_weight * 2.20462 * 100) / 100  -- Convert kg to pounds with 2 decimal places
    set_label({
        name = "_fish_name_label",
        text = fish_name .. " " .. fish_weight .. " kg (" .. fish_weight_pounds .. " lbs)\nRarity: " .. fish_rarity .. "\nSource: " .. fish_water_source,
        visible=true
    })
    

    
    set_image({
        name = "_fish_image",
        image_path = fish_image,
        visible=true
    })
    
    -- Update health bars
    set_progress_bar({
        name = "_player_health_bar",
        value = 100,
        visible=true
    })
    
    
    set_progress_bar({
        name = "_fish_health_bar",
        value = fish_health,
        max_value = max_fish_health,
        visible=true
    })
    
end

function update_fishing_phase_CLIENT(sender_id, light_color, status_text, duration)
    print("Updating fishing phase: " .. light_color .. " - " .. status_text .. " - " .. duration .. "s")
    
    -- Change traffic light image based on phase
    local light_images = {
        red = "red",
        yellow = "yellow", 
        green = "green"
    }
    
    if light_images[light_color] then
        set_image({
            name = "_traffic_light",
            image_path = light_images[light_color],
            visible = true
        })
        print("Set traffic light to: " .. light_images[light_color])
    end
    
    
    -- Timer updates now come directly from fishing_game via update_timer_CLIENT
    -- No need to start timer on user entity
end

function update_fishing_health_CLIENT(sender_id, player_health, fish_health, max_fish_health)

    -- Update player health
    set_progress_bar({
        name = "_player_health_bar",
        value = player_health
    })
    
    
    -- Update fish health
    set_progress_bar({
        name = "_fish_health_bar",
        value = fish_health
    })
    
end

function fishing_player_damage_CLIENT(sender_id, player_health, fish_health, max_fish_health)
    update_fishing_health_CLIENT(sender_id, player_health, fish_health, max_fish_health)
    if IS_LOCAL then
        screenshake(1, 1)
    end
end






-- New function for receiving timer updates from host
function update_timer_CLIENT(sender_id, remaining_time)
    set_label({
        name = "_timer_label",
        text = string.format("%.1fs", remaining_time),
        visible = true
    })
end 
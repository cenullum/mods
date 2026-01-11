network_mode = 1
gravity_scale = 0
linear_damp = 2.0

-- Bubble effect variables
--image_path 
--text
--target_player 
--fish_weight
lifetime = 10.0
current_time = 0.0
float_speed = 30.0

-- Visual elements
bubble_image_name = ""
bubble_text_name = ""

function create_bubble_effect()
    -- Calculate size based on fish weight (linear scale between min and max)
    local bubble_size = 0.2
    if fish_weight then
        -- Linear scale: 0.2 for lightest fish (0.01kg), 3.0 for heaviest fish (100kg)
        local min_fish_weight = 0.01  -- Minimum weight (seahorse)
        local max_fish_weight = 100.0 -- Maximum weight (large shark)
        local min_bubble_size = 0.2
        local max_bubble_size = 3.0
        
        -- Linear interpolation between min and max sizes
        local weight_ratio = (fish_weight - min_fish_weight) / (max_fish_weight - min_fish_weight)
        weight_ratio = math.max(0, math.min(1, weight_ratio)) -- Clamp between 0 and 1
        bubble_size = min_bubble_size + (max_bubble_size - min_bubble_size) * weight_ratio
    end

    -- Create image if provided
    if image_path and image_path ~= "" then
        bubble_image_name = set_image({
            parent_name = name,
            image_path = image_path,
            modulate = Color(1, 1, 1, 0.8),
            size = Vector2(bubble_size, bubble_size),
            z_index = 10
        })
    end
    
    -- Create text if provided
    if text and text ~= "" then
        local text_position = Vector2(-250, 0) -- Center position
        if bubble_image_name ~= "" then
            text_position = Vector2(-250, 64) -- Below image if image exists
        end
        
        bubble_text_name = set_label({
            parent_name = name,
            name = "bubble_label",
            text = text,
            font_size = 30,
            position = text_position,
            size = Vector2(500, 40),
            horizontal_alignment = 1, -- Center alignment
            vertical_alignment = 1,
            modulate = text_color or Color(1,1,1,0.8),
            outline_color = Color(0, 0, 0, 0.8),
            outline_size = 8,
            z_index = 10
        })
    end
    
    -- Add floating movement
    set_value("", name, "linear_velocity", Vector2(0, -float_speed))
end

-- Initialize bubble when created
create_bubble_effect()

function _process(delta, inputs)
    current_time = current_time + delta
    
    -- Fade out over time
    local alpha = 1.0 - (current_time / lifetime)
    if alpha <= 0 then
        -- Destroy bubble
        destroy("",name)
        print("destroy bubble")
        return inputs
    end
    
    -- Update alpha for image if it exists
    if bubble_image_name ~= "" then
        set_image({
            parent_name = name,
            name = bubble_image_name,
            modulate = Color(1, 1, 1, alpha * 0.8)
        })
    end
    
    -- Update alpha for text if it exists
    if bubble_text_name ~= "" then
        set_label({
            parent_name = name,
            name = bubble_text_name,
            modulate = Color(1, 1, 1, alpha * 0.8)
        })
    end
    
    return inputs
end 
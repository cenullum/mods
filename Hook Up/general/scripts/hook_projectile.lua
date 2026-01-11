linear_damp = 0
gravity_scale = 0.5
lock_rotation = true
network_mode = 2
z_index = 5


-- Hook data
-- owner_name = name of the user that owns the hook (set by user.lua)

-- Visual and collision
image_name = "hook_image"
collision_name = "hook_collision"


-- Add hook tag for identification
add_tag(name, "hook")


-- Helper function to get owner's hook state
function get_owner_hook_state()
    if owner_name and owner_name ~= "" then
        return get_value("", owner_name, "hook_state")
    end
    return "READY"
end


function create_hook_components()
    -- Create hook visual (initially positioned off-screen but visible)
    set_image({
        parent_name = name,
        name = image_name,
        image_path="hook",
        modulate = modulate or Color(0.7, 0.7, 0.9, 1), -- Use entity modulate or default
        visible = false
    })
    
    -- Create collision for hook (initially disabled)
    collision_config = {
        parent_name = name,
        name = collision_name,
        shape = "circle",
        position=Vector2(0,-6),
        size = 10,
        collision_layer = {3}, -- Hook layer
        collision_mask = {1,4}, -- Collides with walls(1), water(4)
        disabled = false -- Start disabled
    }
    set_collision(collision_config)
end

-- Initialize hook components when entity is created
create_hook_components()

function activate_hook()
    set_image({
        parent_name = name,
        name = image_name,
        visible = true,
    })
    
    -- Enable collision
    set_collision({
        parent_name = name,
        name = collision_name,
        disabled = false
    })
end

function deactivate_hook()
    set_value("", name, "linear_velocity", Vector2(0, 0))
    
    -- Keep image visible but move it off-screen
    set_image({
        parent_name = name,
        name = image_name,
        visible = false
    })
    
    -- Disable collision
    set_collision({
        parent_name = name,
        name = collision_name,
        disabled = true
    })
end



-- Collision handler - this is called by entity.gd when hook collides with something
function on_body_body_entered(collision_info)
    if IS_HOST == false then
        return
    end
    
    local state = get_owner_hook_state()
    if state ~= "FIRING" then
        return
    end


    
    local other_entity_name = collision_info.body_name
    -- Don't attach to other players (check if entity has user tag)
    if has_tag(other_entity_name, "user") then
        return
    end
    
    if has_tag(other_entity_name, "hook") then
        return
    end

    if has_tag(other_entity_name, "rotating_cross") then
        return
    end
    
    if has_tag(other_entity_name, "rotating_line") then
        return
    end

    -- Freeze the hook when it attaches (broadcast to all by default)
    freeze_entity(name,true)
    
    -- Notify owner that hook is attached
    if owner_name and owner_name ~= "" then
        run_network_function(owner_name, "set_hook_state_ALL", {"ATTACHED"})
    end
end

-- Area collision handler - this is called when hook (body) enters an area
function on_body_area_entered(area_name)
    if IS_HOST == false then
        return
    end
    
    local state = get_owner_hook_state()

    
    -- Check if hook hit any water area - start searching phase
    if has_tag(area_name, "sea") or has_tag(area_name, "cave_water") or has_tag(area_name, "swamp_water") or has_tag(area_name, "lake") then
        if owner_name and owner_name ~= "" then
            -- Only start searching if currently firing
            if state == "FIRING" then
                -- Set searching state first
                run_network_function(owner_name, "set_hook_state_ALL", {"SEARCHING"})
                
                -- Determine water source type
                local water_source = ""
                if has_tag(area_name, "sea") then
                    water_source = "sea"
                elseif has_tag(area_name, "cave_water") then
                    water_source = "cave_water"
                elseif has_tag(area_name, "swamp_water") then
                    water_source = "swamp_water"
                elseif has_tag(area_name, "lake") then
                    water_source = "lake"
                end
                
                print("DEBUG: Hook hit area " .. area_name .. " - determined water_source: " .. tostring(water_source))
                
                -- Start searching timer in fishing game with water source
                run_function("-fishing_game", "start_searching_for_player", {owner_name, water_source})
            end
        end
        -- Don't attach to water, just start searching
        return
    end
end










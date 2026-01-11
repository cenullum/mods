singleton_name = "mg"

-- Global variables for the spawning system
local rectangle_x = -8          -- X coordinate of spawn rectangle
local rectangle_y = -12          -- Y coordinate of spawn rectangle
local rectangle_width = 24       -- Width of spawn rectangle
local rectangle_height = 16    -- Height of spawn rectangle
local min_monsters = 2           -- Minimum monsters to spawn each wave
local max_monsters = 5           -- Maximum monsters to spawn each wave
local min_interval = 1          -- Minimum seconds between spawns
local max_interval = 3         -- Maximum seconds between spawns
spawning_enabled = true    -- Master switch to enable/disable spawning
local warning_duration = 3.0    -- Duration for warning icon to be visible
current_wave = 0              -- Track current wave number

-- Wave level definitions - now with dynamic multipliers
local WAVE_LEVELS = {
    {name = "Normal", color = Color(0.85, 0, 0.60, 1)}, -- Pink
    {name = "Enhanced", color = Color(0, 0.8, 0, 1)}, -- Green
    {name = "Superior", color = Color(0, 0.3, 0.8, 1)}, -- Blue
    {name = "Elite", color = Color(0.4, 0, 0.9, 1)}, -- Purple
    {name = "Legendary", color = Color(0.9, 0.4, 0, 1)}, -- Orange
    {name = "Mythic", color = Color(0.25, 0.25, 0.5, 1)}, -- dark purple
    {name = "Unstoppable", color = Color(1, 0, 0, 1)} -- Red
}

-- Get level data for a specific wave
function get_level_data(wave_number)
    -- Calculate which level we're on (every 7 waves)
    local level_index = math.floor((wave_number - 1) / 7) + 1
    
    -- If we're past the defined levels, use the last level with increasing multipliers
    if level_index > #WAVE_LEVELS then
        local last_level = WAVE_LEVELS[#WAVE_LEVELS]
        local extra_levels = level_index - #WAVE_LEVELS
        
        -- Get the color index for cycling (0-based index)
        local color_index = (extra_levels - 1) % (#WAVE_LEVELS - 1)
        local color = WAVE_LEVELS[color_index + 1].color
        
        return {
            name = last_level.name .. " " .. extra_levels,
            level_index = level_index,
            color = color
        }
    end
    
    return {
        name = WAVE_LEVELS[level_index].name,
        level_index = level_index,
        color = WAVE_LEVELS[level_index].color
    }
end

-- Centralized monster definitions - Fixed indexing to start from 1
local monster_definitions = {
    [1] = { type = "ghost", health = 30, damage = 1.5, speed = 50, size = 32 },
    [2] = { type = "wolf", health = 45, damage = 2.5, speed = 70, size = 36 },
    [3] = { type = "bandit", health = 60, damage = 0.5, speed = 0, size = 40 },
    [4] = { type = "zombie", health = 75, damage = 3.0, speed = 30, size = 44 },
    [5] = { type = "cactus", health = 90, damage = 4.5, speed = 25, size = 48 },
    [6] = { type = "snake", health = 35, damage = 2.0, speed = 60, size = 34 }
}

-- Function to get monster data by ID
function get_monster_data(monster_id)
    -- Ensure valid ID by wrapping around if out of bounds (1-based indexing)
    local valid_id = ((monster_id - 1) % #monster_definitions) + 1
    return monster_definitions[valid_id]
end

-- Function to get a random position inside the interior of a rectangle
-- Only considers the tiles with Vector2(1,1) (interior tiles)
-- x, y: top-left position of the rectangle
-- width, height: dimensions of the rectangle
-- Returns: a world position (not tile position)
function get_random_interior_position(x, y, width, height)
    -- Ensure we have a valid interior (must be at least 1x1)
    if width < 3 or height < 3 then
        print("Error: Width and height must be at least 3 to have an interior")
        return nil
    end

    -- Calculate interior bounds (exclude the outer edge tiles)
    local interior_x_min = x + 1
    local interior_y_min = y + 1
    local interior_x_max = x + width - 2
    local interior_y_max = y + height - 2

    -- Generate random tile position within interior
    local random_tile_x = math.random(interior_x_min, interior_x_max)
    local random_tile_y = math.random(interior_y_min, interior_y_max)

    -- Convert tile position to world position
    local world_pos = map_to_local(Vector2(random_tile_x, random_tile_y))

    return world_pos
end

-- Function to display warning icon before spawning monsters
function show_spawn_warning_ALL(sender_id, spawn_position, monster_id)
    -- Create X warning icon at spawn position
    local warning_icon_name = set_image({
        parent_name = nil,
        image_path = "x", -- X icon image
        position = spawn_position,
    })
    
    -- Schedule deletion of warning icon and spawn monster after the warning duration

    run_function(name,"spawn_after_warning",{warning_icon_name,spawn_position,monster_id},warning_duration)

end

-- Function to spawn monster after warning disappears
function spawn_after_warning(warning_icon_name, spawn_position, monster_id)
    -- Destroy warning icon
    destroy("", warning_icon_name)
    
    -- Check if spawning is still enabled
    if spawning_enabled and IS_HOST then
        -- Spawn the monster with level enhancements
        spawn_monster_with_level(monster_id, spawn_position, current_wave)
    end
end

-- Function to spawn a monster with wave level enhancements
function spawn_monster_with_level(monster_id, position, wave_number)
    local monster_data = get_monster_data(monster_id)
    local level_data = get_level_data(wave_number)
    
    -- Apply level index to health and damage
    local enhanced_health = monster_data.health * level_data.level_index
    local enhanced_damage = monster_data.damage * level_data.level_index
    
    -- Create the monster entity
    local entity_data = {
        t = "monster",
        p = position,
        id = monster_id,
        h = enhanced_health,
        d = enhanced_damage,
        s = monster_data.speed,
        i = monster_data.size,
        oc = level_data.color,
        wl = level_data.level_index  -- Pass wave level for bullet damage scaling
    }
    
    return spawn_entity_host(entity_data)
end

-- Function to spawn a monster at a random position inside the rectangle
function spawn_monster(x, y, width, height, monster_id)
    -- Get a random interior position
    local spawn_pos = get_random_interior_position(x, y, width, height)

    if spawn_pos == nil then
        print("Failed to find valid spawn position")

    end

    -- Show warning icon to all clients before spawning

    run_network_function(name, "show_spawn_warning_ALL", {spawn_pos, monster_id})

end

-- Function to spawn a random number of monsters
function spawn_monster_group()
    if spawning_enabled == false then
        schedule_next_spawn()
        return
    end

    -- Determine how many monsters to spawn this wave
    local monster_count = math.random(min_monsters, max_monsters)

    -- Start spawn warnings for monsters
    for i = 1, monster_count do
        -- Choose a random monster type from the definitions (1-based indexing)
        local monster_id = math.random(1, #monster_definitions)
        
        spawn_monster(
            rectangle_x,
            rectangle_y,
            rectangle_width,
            rectangle_height,
            monster_id
        )
    end

    set_audio({
        stream_path = "bubble",
        position = get_value("", name, "position"),
        volume = -10,
        random_pitch = 0.15
    })

    -- Schedule the next spawn
    schedule_next_spawn()
end

-- Schedule the next monster spawn with a random interval
function schedule_next_spawn()
    -- Generate a random interval within the configured range
    local next_interval = min_interval + math.random() * (max_interval - min_interval)

    start_timer({
        entity_name = name,
        timer_id = "monster_spawn",
        function_name = "spawn_monster_group",
        wait_time = next_interval,
    })
end

monster_count = 0
function monster_count_reset()
    monster_count = 0
    set_value("", "_monster_count", "text", "Monsters: 0")
    
    -- If host, notify all clients about the monster count reset
    if IS_HOST then
        run_network_function(name, "update_monster_count_CLIENT", {0})
    end
end

function monster_count_change(addition)
    monster_count = monster_count + addition
    set_value("", "_monster_count", "text", "Monsters: "..monster_count)
    
    -- If host, notify all clients about the monster count change
    if IS_HOST then
        run_network_function(name, "update_monster_count_CLIENT", {monster_count})
    end
end

-- Network function to update monster count on clients
function update_monster_count_CLIENT(sender_id, count)
    monster_count = count
    set_value("", "_monster_count", "text", "Monsters: "..monster_count)
end

function get_info()
    info = {
        rectangle_x = rectangle_x,
        rectangle_y = rectangle_y,
        rectangle_width = rectangle_width,
        rectangle_height = rectangle_height,
    }
    return info
end


--This function is not on monster lua because monster can be destroyed so timer can not run this function
function destroy_damage_label(args)
destroy("",args.extra_args.label_name)
end



































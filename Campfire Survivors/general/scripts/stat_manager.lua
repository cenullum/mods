singleton_name = "sm"

-- upgrade_system.lua - Handles the character/weapon upgrade system with network optimization

-- Character attributes that can be upgraded (static data known by all clients)
local character_upgrades = {
{id = 1, name = "Movement Speed", description = "Increases your movement speed by 15%", value = 0.15},
{id = 2, name = "Health/HP", description = "Increases your max health by 20%", value = 0.20},
{id = 3, name = "Armor/Defense", description = "Reduces damage taken by 10%", value = 0.10},
{id = 4, name = "Pickup Range", description = "Increases XP pickup range by 25%", value = 0.25},
{id = 5, name = "Experience Gain", description = "Increases XP gain by 15%", value = 0.15},
{id = 6, name = "Regeneration", description = "Restores 1% of max HP per second", value = 0.01},
{id = 7, name = "Dodge Chance", description = "Adds 5% chance to avoid damage", value = 0.05}
}

-- Weapon attributes that can be upgraded (static data known by all clients)
local weapon_upgrades = {
{id = 1, name = "Attack Speed", description = "Decreases time between shots by 10%", value = 0.10},
{id = 2, name = "Projectile Size", description = "Increases bullet size by 20%", value = 0.20},
{id = 3, name = "Projectile Count", description = "Adds an additional projectile", value = 1},
{id = 4, name = "Projectile Speed", description = "Increases bullet speed by 15%", value = 0.15},
{id = 5, name = "Projectile Penetration", description = "Bullets penetrate through one enemy", value = 1},
{id = 6, name = "Lifesteal", description = "Recover 1% of damage as health", value = 0.01},
{id = 7, name = "Knockback Power", description = "Increases enemy pushback by 20%", value = 0.20},
{id = 8, name = "Damage", description = "Increases bullet damage by 15%", value = 0.15}
}

-- Create lookup tables for faster access by ID
local character_upgrades_by_id = {}
local weapon_upgrades_by_id = {}

-- Initialize lookup tables
function initialize_lookup_tables()
    for _, upgrade in ipairs(character_upgrades) do
        character_upgrades_by_id[upgrade.id] = upgrade
    end

    for _, upgrade in ipairs(weapon_upgrades) do
        weapon_upgrades_by_id[upgrade.id] = upgrade
    end
end

-- Call initialization on script load
initialize_lookup_tables()

-- State variables
local upgrade_panel_name = "upgrade_panel"
local selected_upgrade_ids = {} -- Only IDs are stored/transmitted now, now will be a table keyed by steam_id
local players_upgrade_rights = {} -- {steam_id = number_of_rights}
local players_reroll_rights = {} -- {steam_id = has_reroll_right}
local players_next_upgrade_level = {} -- {steam_id = next_level} - Which level the next right will be used for
local local_reroll_right = false -- Client-side tracking of reroll right
local local_remaining_rights = 0 -- Client-side tracking of remaining rights
local local_next_upgrade_level = 0 -- Client-side tracking of next upgrade level
local local_selected_upgrade_ids={}
-- Generate a set of random upgrade IDs (network optimized)
function generate_random_upgrade_ids()
    local options = {}

    -- Pick 2 random character upgrades
    local char_indices = {}
    while #char_indices < 2 do
        local index = math.random(1, #character_upgrades)
        if not table_contains(char_indices, index) then
            table.insert(char_indices, index)
        end
    end

    -- Pick 2 random weapon upgrades
    local weapon_indices = {}
    while #weapon_indices < 2 do
        local index = math.random(1, #weapon_upgrades)
        if not table_contains(weapon_indices, index) then
            table.insert(weapon_indices, index)
        end
    end

    -- Store only the type (0 for character, 1 for weapon) and ID of each upgrade
    for _, idx in ipairs(char_indices) do
        table.insert(options, {
        type = 0, -- 0 = character
        id = character_upgrades[idx].id
        })
    end

    for _, idx in ipairs(weapon_indices) do
        table.insert(options, {
        type = 1, -- 1 = weapon
        id = weapon_upgrades[idx].id
        })
    end

    return options
end

-- Helper function to check if table contains value
function table_contains(table, value)
    for _, v in ipairs(table) do
        if v == value then
            return true
        end
    end
    return false
end

-- Get full upgrade data from an upgrade ID reference
function get_upgrade_from_id(upgrade_id_ref)
    local upgrade_data = nil
    local upgrade_type = "character"

    if upgrade_id_ref.type == 0 then
        upgrade_data = character_upgrades_by_id[upgrade_id_ref.id]
    else
        upgrade_data = weapon_upgrades_by_id[upgrade_id_ref.id]
        upgrade_type = "weapon"
    end

    return {
    type = upgrade_type,
    data = upgrade_data
    }
end

-- Apply the chosen upgrade
function apply_upgrade(steam_id, upgrade_number, upgrade_id, is_weapon_upgrade)
    if not IS_HOST then return end
    
    -- Validate inputs
    if not steam_id or not upgrade_id then
        print("Invalid inputs to apply_upgrade")
        return false
    end
    
    -- Get player entity name (same as steam_id)
    local target_entity = steam_id
    
    -- Get the upgrade details
    local upgrade = nil
    local value = 0
    
    if is_weapon_upgrade then
        upgrade = weapon_upgrades_by_id[upgrade_id]
        if not upgrade then
            print("Invalid weapon upgrade ID: " .. tostring(upgrade_id))
            return false
        end
        value = upgrade.value
    else
        upgrade = character_upgrades_by_id[upgrade_id]
        if not upgrade then
            print("Invalid character upgrade ID: " .. tostring(upgrade_id))
            return false
        end
        value = upgrade.value
    end
    
    -- Actually apply the upgrade
    if is_weapon_upgrade then
        -- Weapon upgrade
        if upgrade_id == 1 then -- Attack Speed
            run_function(target_entity, "update_attack_speed", {value})
        elseif upgrade_id == 2 then -- Projectile Size
            run_function(target_entity, "update_projectile_size", {value})
        elseif upgrade_id == 3 then -- Projectile Count
            run_function(target_entity, "update_projectile_count", {value})
        elseif upgrade_id == 4 then -- Projectile Speed
            run_function(target_entity, "update_projectile_speed", {value})
        elseif upgrade_id == 5 then -- Projectile Penetration
            run_function(target_entity, "update_projectile_penetration", {value})
        elseif upgrade_id == 6 then -- Lifesteal
            run_function(target_entity, "update_lifesteal", {value})
        elseif upgrade_id == 7 then -- Knockback Power
            run_function(target_entity, "update_knockback", {value})
        elseif upgrade_id == 8 then -- Damage
            run_function(target_entity, "update_damage", {value})
        end
    else
        -- Character upgrade
        if upgrade_id == 1 then -- Movement Speed
            run_function(target_entity, "update_movement_speed", {value})
        elseif upgrade_id == 2 then -- Health
            run_function(target_entity, "update_max_health", {value})
        elseif upgrade_id == 3 then -- Armor
            run_function(target_entity, "update_armor", {value})
        elseif upgrade_id == 4 then -- Pickup Range
            run_function(target_entity, "update_pickup_range", {value})
        elseif upgrade_id == 5 then -- Experience Gain
            run_function(target_entity, "update_experience_gain", {value})
        elseif upgrade_id == 6 then -- Regeneration
            run_function(target_entity, "update_regeneration", {value})
        elseif upgrade_id == 7 then -- Dodge Chance
            run_function(target_entity, "update_dodge_chance", {value})
        end
    end
    
    -- Track the upgrade level in stats
    run_function("-stats", "track_upgrade_level", {steam_id, upgrade_id, is_weapon_upgrade})
    
    return true
end

-- Check if player has upgrade rights
function has_upgrade_rights(steam_id)
    return players_upgrade_rights[steam_id] and players_upgrade_rights[steam_id] > 0
end

-- Check if player has reroll rights
function has_reroll_right(steam_id)
    return players_reroll_rights[steam_id] == true
end

-- Add upgrade rights to a player based on level difference
function add_right(steam_id, how_many)
    if not players_upgrade_rights[steam_id] then
        players_upgrade_rights[steam_id] = 0
    end

    players_upgrade_rights[steam_id] = players_upgrade_rights[steam_id] + how_many

    -- Initialize next_upgrade_level if not already set
    if not players_next_upgrade_level[steam_id] or players_next_upgrade_level[steam_id] == 0 then
        -- Set initial level (starts at 1 if not previously set)
        players_next_upgrade_level[steam_id] = 1
    end

    -- When adding upgrade rights, also grant one reroll right per upgrade session
    players_reroll_rights[steam_id] = true
end

-- Consume one upgrade right from a player
function consume_right(steam_id)
    if players_upgrade_rights[steam_id] and players_upgrade_rights[steam_id] > 0 then
        players_upgrade_rights[steam_id] = players_upgrade_rights[steam_id] - 1
        -- Increase the next upgrade level by 1 (player progresses to next level)
        if players_next_upgrade_level[steam_id] then
            players_next_upgrade_level[steam_id] = players_next_upgrade_level[steam_id] + 1
        else
            players_next_upgrade_level[steam_id] = 1
        end

        return true
    end
    return false
end

-- Consume reroll right from a player
function consume_reroll_right(steam_id)
    if players_reroll_rights[steam_id] then
        players_reroll_rights[steam_id] = false
        return true
    end
    return false
end

-- Send upgrade options to a specific player (network optimized)
function send_upgrade_options_to_player(steam_id)
    if not IS_HOST then return end
    
    local wave_state = get_value("", "-wm", "wave_state")
    
    -- Don't send upgrades during active waves
    if wave_state == "active" then
        return
    end
    
    -- Reset reroll right for each new upgrade session
    players_reroll_rights[steam_id] = true

    -- Generate upgrade options
    local upgrade_ids = generate_random_upgrade_ids()

    -- Store these options for validation later
    if not selected_upgrade_ids[steam_id] then
        selected_upgrade_ids[steam_id] = {}
    end
    selected_upgrade_ids[steam_id] = upgrade_ids

    -- Get level info
    local next_upgrade_level = players_next_upgrade_level[steam_id] or 0
    -- Get remaining rights info
    local remaining_rights = players_upgrade_rights[steam_id] or 0

    -- Send the options along with reroll right status, level info and remaining rights
    run_network_function("-sm", "client_show_upgrades_CLIENT", {
        upgrade_ids,
        true,
        remaining_rights,
        next_upgrade_level
    }, steam_id)

    return upgrade_ids
end

-- Host function to process all players with upgrade rights
function send_upgrade_panels()
    if not IS_HOST then return end
        local players_with_rights = 0

        -- Get all players with upgrade rights and send panels to each one
        for steam_id, rights in pairs(players_upgrade_rights) do
            if rights > 0 then
                players_with_rights = players_with_rights + 1
                -- Send upgrade options to this player
                send_upgrade_options_to_player(steam_id)
            end
        end
    end

-- Show the upgrade panel to the client (receives only IDs, looks up full data locally)
function client_show_upgrades_CLIENT(sender_id, upgrade_ids, has_reroll, remaining_rights, next_upgrade_level)
    local_selected_upgrade_ids = upgrade_ids
    local_reroll_right = has_reroll
    local_remaining_rights = remaining_rights or 0
    local_next_upgrade_level = next_upgrade_level or 0

    show_upgrade_panel()
end

-- Create and display the upgrade selection panel
function show_upgrade_panel()
    if is_panel_exists(upgrade_panel_name) then
        close_panel(upgrade_panel_name)
    end

    -- Create level progression text
    local level_text = "Upgrade right of level " .. (local_next_upgrade_level - 1) .. " → " .. local_next_upgrade_level

    -- Create remaining rights text
    local rights_text = local_remaining_rights - 1 .. " remaining right"

    -- Full header text
    local header_text = "Select one upgrade to enhance your character:\n"

    header_text = header_text .. rights_text
    header_text = header_text .. "\n\nFor each level up you get one upgrade right."
    -- Create panel with close button disabled to prevent escape
    local panel_config = {
        name = "upgrade_panel",
        title = level_text,
        text = header_text,
        resizable = false,
        is_scrollable = true,
        minimum_size = Vector2(400, 520), -- Slightly larger to accommodate the header
        close = false -- This disables the exit button
    }


    upgrade_panel_name = create_panel(panel_config)


    -- Add upgrade option buttons (using local data lookup)
    for i, upgrade_id_ref in ipairs(local_selected_upgrade_ids) do
        local upgrade = get_upgrade_from_id(upgrade_id_ref)
        local type_label = ""
        local button_color = Color(0, 0, 0, 0)

        if upgrade.type == "character" then
            type_label = "Character: "
            button_color = Color(0.2, 0.5, 0.8)
        else
            type_label = "Weapon: "
            button_color = Color(0.8, 0.2, 0.2)
        end

        -- Get the appropriate icon for this upgrade
        local is_weapon_upgrade = (upgrade_id_ref.type == 1)
        local icon_path = get_upgrade_icon_path(upgrade_id_ref.id, is_weapon_upgrade)

        -- Create a custom button for the upgrade
        local button_config = {
        text = type_label .. upgrade.data.name,
        color = button_color,
        entity_name = "-sm",
        function_name = "select_upgrade",
        extra_args = {index = i},
        is_vertical = true,
        size = Vector2(380, 80), -- Set an appropriate size for the button
        icon_path = icon_path -- Add the icon to the button
        }

        local button_path = add_custom_button_to_panel(upgrade_panel_name, button_config)

        -- Add description label to the custom button
        local label_config = {
        text = upgrade.data.description,
        font_size = 14,
        offset_ratio = Vector2(1.0, 1.0), -- Position below the main text with increased spacing
        vertical_alignment = 2, -- BOTTOM, must be bottom or there will be a gap between the button and the label
        horizontal_alignment = 1 -- CENTER
        }

        add_label_to_custom_button(button_path, label_config)
    end

    -- Add reroll button at the bottom - only if they have a reroll right
    local reroll_text = "Reroll Options"
    if not local_reroll_right then
        reroll_text = "Reroll Used (Select an Upgrade)"
    end

    local reroll_config = {
    text = reroll_text,
    color = local_reroll_right and Color(0.3, 0.7, 0.3) or Color(0.5, 0.5, 0.5),
    entity_name = "-sm",
    function_name = local_reroll_right and "reroll_upgrades" or "show_no_reroll_message",
    is_vertical = true
    }
    add_button_to_panel(upgrade_panel_name, reroll_config)
end

-- Show a message when trying to reroll without rights
function show_no_reroll_message()
    -- Create a temporary message panel
    local message_config = {
    title = "No Rerolls Left",
    text = "You've already used your reroll for this upgrade. Please select one of the available upgrades.",
    resizable = false,
    countdown = 3
    }
    create_panel(message_config)
end

-- Handle selection of an upgrade
function select_upgrade(args)
    local index = args.extra_args.index
    local selected = local_selected_upgrade_ids[index]

    -- Close the panel
    close_panel(upgrade_panel_name)

    -- Send only the ID reference to the host for validation (network optimized)
    run_network_function("-sm", "host_validate_upgrade_HOST", {selected})
end

-- Host validates the client's selection (anti-cheat)
function host_validate_upgrade_HOST(sender_id, selected_id_ref)
    local wave_state = get_value("", "-wm", "wave_state")
    
    -- Don't process upgrades during active waves
    if wave_state == "active" then
        return
    end
    
    -- Check if the player has upgrade rights
    if not has_upgrade_rights(sender_id) then
        return
    end

    -- Check if the selected upgrade ID is legitimate
    local valid = false
    if selected_upgrade_ids[sender_id] then
        for i, upgrade_id_ref in ipairs(selected_upgrade_ids[sender_id]) do
            if upgrade_id_ref.id == selected_id_ref.id and upgrade_id_ref.type == selected_id_ref.type then
                valid = true
                break
            end
        end
    end

    if valid then
        consume_right(sender_id)
        local next_upgrade_level = players_next_upgrade_level[sender_id] or 0
        local remaining_rights = players_upgrade_rights[sender_id] or 0
        
        
        --The "_ALL" postfix is present, and the user's steam_id (last parameter) has been identified, so client_apply_upgrade_ALL will run on both the host and the client.
        run_network_function("-sm", "client_apply_upgrade_ALL", {
            selected_id_ref,
            sender_id,
            remaining_rights,
            next_upgrade_level
        }, sender_id)

        -- Check if player has more upgrade rights
        if has_upgrade_rights(sender_id) then
            -- Send another upgrade panel after a short delay
            run_function("-sm", "delayed_send_options", {sender_id}, 0.5)
        end
    end
end

-- Helper function to delay sending options
function delayed_send_options(steam_id)
    send_upgrade_options_to_player(steam_id)
end

-- Client applies the validated upgrade
function client_apply_upgrade_ALL(sender_id, selected_id_ref, target_entity, remaining_rights, next_upgrade_level)
    -- Apply the upgrade locally 
    -- Apply the upgrade based on type
    if selected_id_ref.type == 0 then -- Character upgrade
        apply_upgrade(target_entity, selected_id_ref.position, selected_id_ref.id, false)
    else -- Weapon upgrade
        apply_upgrade(target_entity, selected_id_ref.position, selected_id_ref.id, true)
    end

    -- Update local tracking
    local_remaining_rights = remaining_rights
    local_next_upgrade_level = next_upgrade_level
end

-- Handle reroll button
function reroll_upgrades()
    -- Set local reroll right to false immediately to prevent double clicks
    local_reroll_right = false

    -- Close the existing panel
    close_panel(upgrade_panel_name)

    -- Request new options from host
    run_network_function("-sm", "host_reroll_upgrades_HOST")
end

-- Host handles reroll request from client
function host_reroll_upgrades_HOST(sender_id)
    -- Check if the player has upgrade rights
    if not has_upgrade_rights(sender_id) then
        return
    end

    -- Check if the player has a reroll right
    if not has_reroll_right(sender_id) then
        return
    end

    -- Consume the reroll right
    consume_reroll_right(sender_id)

    -- Generate new upgrades for this player (network optimized)
    local new_upgrade_ids = generate_random_upgrade_ids()

    -- Store the new upgrades for validation
    if not selected_upgrade_ids[sender_id] then
        selected_upgrade_ids[sender_id] = {}
    end
    selected_upgrade_ids[sender_id] = new_upgrade_ids


    local next_upgrade_level = players_next_upgrade_level[sender_id] or 0
    local remaining_rights = players_upgrade_rights[sender_id] or 0

    -- Send back to the requesting client
    run_network_function("-sm", "client_receive_reroll_CLIENT", {
    new_upgrade_ids,
    false,
    remaining_rights,
    next_upgrade_level
    }, sender_id)
end

-- Client receives rerolled options
function client_receive_reroll_CLIENT(sender_id, new_upgrade_ids, has_reroll, remaining_rights, next_upgrade_level)
    local_selected_upgrade_ids = new_upgrade_ids
    local_reroll_right = has_reroll or false -- Default to false if not provided

    if remaining_rights then
        local_remaining_rights = remaining_rights
    end

    if next_upgrade_level then
        local_next_upgrade_level = next_upgrade_level
    end

    show_upgrade_panel()
end

-- Clean up when a user disconnects
function _on_user_disconnected(steam_id, nickname)
    if IS_HOST then
        if players_upgrade_rights[steam_id] then
            players_upgrade_rights[steam_id] = nil
        end
        if players_reroll_rights[steam_id] then
            players_reroll_rights[steam_id] = nil
        end

        if players_next_upgrade_level[steam_id] then
            players_next_upgrade_level[steam_id] = nil
        end
        if selected_upgrade_ids[steam_id] then
            selected_upgrade_ids[steam_id] = nil
        end
    end
end

-- Initialize the upgrade system when a player joins
function _on_user_initialized(steam_id, nickname)
    -- This will be called when a client has fully downloaded and initialized
    -- Safe to call network functions now for this client
    if IS_HOST then
        if not players_upgrade_rights[steam_id] then
            players_upgrade_rights[steam_id] = 0
        end
        players_reroll_rights[steam_id] = false



        if not players_next_upgrade_level[steam_id] then
            players_next_upgrade_level[steam_id] = 0
        end

        if not selected_upgrade_ids[steam_id] then
            selected_upgrade_ids[steam_id] = {}
        end
    end
end



-- Helper to count table entries for debugging
function count_table_entries(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Debug helper function
function dump(o)
    if type(o) == 'table' then
        local s = '{\n'
        for k,v in pairs(o) do
            local key = k
            if type(k) == 'userdata' and k.x and k.y then
                key = string.format("(%d,%d)", k.x, k.y)
            elseif type(k) ~= 'number' then
                key = '"'..tostring(k)..'"'
            end

            local value = v
            if type(v) == 'userdata' and v.x and v.y then
                value = string.format("(%d,%d)", v.x, v.y)
            else
                value = dump(v)
            end

            s = s .. '  ['..key..'] = ' .. value .. ',\n'
        end
        return s .. '}'
    else
        return tostring(o)
    end
end

-- Reset player upgrade rights when they die
function reset_player_upgrade_rights(steam_id)
    if not IS_HOST then return end
    
    -- If steam_id is provided, reset only that player
    if steam_id then
        -- Reset all upgrade-related variables for this player
        players_upgrade_rights[steam_id] = 0
        players_reroll_rights[steam_id] = false
        players_next_upgrade_level[steam_id] = 0
        selected_upgrade_ids[steam_id] = {}
        
    else
        -- Reset all players
        players_upgrade_rights = {}
        players_reroll_rights = {}
        players_next_upgrade_level = {}
        selected_upgrade_ids = {}
        
    end
end

-- Function to get icon path for upgrade
function get_upgrade_icon_path(upgrade_id, is_weapon_upgrade)
    local base_path = "icons/"
    
    if is_weapon_upgrade then
        -- Weapon upgrade icon mapping
        if upgrade_id == 1 then -- Attack Speed
            return base_path .. "attack_speed"
        elseif upgrade_id == 2 then -- Projectile Size
            return base_path .. "projectile_size"
        elseif upgrade_id == 3 then -- Projectile Count
            return base_path .. "projectile_count"
        elseif upgrade_id == 4 then -- Projectile Speed
            return base_path .. "projectile_speed"
        elseif upgrade_id == 5 then -- Projectile Penetration
            return base_path .. "projectile_penetration"
        elseif upgrade_id == 6 then -- Lifesteal
            return base_path .. "lifesteal"
        elseif upgrade_id == 7 then -- Knockback Power
            return base_path .. "knockback"
        elseif upgrade_id == 8 then -- Damage
            return base_path .. "damage"
        end
    else
        -- Character upgrade icon mapping
        if upgrade_id == 1 then -- Movement Speed
            return base_path .. "speed"
        elseif upgrade_id == 2 then -- Health/HP
            return base_path .. "health"
        elseif upgrade_id == 3 then -- Armor/Defense
            return base_path .. "armor"
        elseif upgrade_id == 4 then -- Pickup Range
            return base_path .. "pickup"
        elseif upgrade_id == 5 then -- Experience Gain
            return base_path .. "xp_rate"
        elseif upgrade_id == 6 then -- Regeneration
            return base_path .. "regeneration"
        elseif upgrade_id == 7 then -- Dodge Chance
            return base_path .. "dodge"
        end
    end
    
    -- Default fallback (shouldn't happen)
    return base_path .. "damage"
end















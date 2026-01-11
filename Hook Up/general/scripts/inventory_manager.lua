network_mode = 1
singleton_name = "inventory_manager"

-- Constants
MAX_INVENTORY_SIZE = 100
WARNING_THRESHOLD = 95

-- Cooldown (seconds) for replaying catch animation
REPLAY_CATCH_COOLDOWN = 10

-- Player inventories (server-side)
player_inventories = {} -- {steam_id = {fish_list = [], json_path = ""}}

-- Host-side tracking of last replay times per user
player_replay_catch_timestamps = {} -- {steam_id = last_timestamp}

-- UI element names
inventory_panel_name = "_inventory_panel"
inventory_grid_name = "_inventory_grid"
inventory_warning_name = "_inventory_warning"

-- Rarity colors
rarity_colors = {
    common = Color(0.7, 0.7, 0.7, 1),      -- Gray
    rare = Color(0.2, 0.6, 1.0, 1),        -- Blue
    epic = Color(0.8, 0.2, 0.8, 1),        -- Purple
    legendary = Color(1.0, 0.8, 0.0, 1),   -- Gold
    garbage = Color(0.5, 0.5, 0.5, 1)      -- Dark Gray
}

-- Client-side cache to hold last received inventory
client_fish_list = {}

-- Client-side last replay timestamp
last_replay_catch_client_time = 0

-- Variable to store fish index for removal confirmation
fish_index_to_remove = nil

detail_panel_name = "fish_detail_panel"

-- Utility: safely convert weight to number
function to_number(value, default)
    default = default or 0
    local num = tonumber(value)
    if num == nil then return default end
    return num
end

-- Helper function to format timestamp
function format_timestamp(timestamp)
    -- Fallback numeric formatter that does not rely on os.date (which may be unavailable)
    local SECONDS_PER_MINUTE = 60
    local SECONDS_PER_HOUR   = 3600
    local SECONDS_PER_DAY    = 86400

    -- Days calculation helpers
    local function is_leap(year)
        return (year % 4 == 0) and ((year % 100 ~= 0) or (year % 400 == 0))
    end

    local DAYS_PER_MONTH = {31,28,31,30,31,30,31,31,30,31,30,31}

    local days = math.floor(timestamp / SECONDS_PER_DAY)
    local seconds_today = timestamp % SECONDS_PER_DAY

    -- Calculate hour/min/sec
    local hour = math.floor(seconds_today / SECONDS_PER_HOUR)
    local minute = math.floor((seconds_today % SECONDS_PER_HOUR) / SECONDS_PER_MINUTE)
    local second = seconds_today % SECONDS_PER_MINUTE

    -- Calculate year
    local year = 1970
    while true do
        local days_in_year = is_leap(year) and 366 or 365
        if days >= days_in_year then
            days = days - days_in_year
            year = year + 1
        else
            break
        end
    end

    -- Adjust February days for leap year
    DAYS_PER_MONTH[2] = is_leap(year) and 29 or 28

    -- Calculate month
    local month = 1
    for i = 1, 12 do
        if days < DAYS_PER_MONTH[i] then
            month = i
            break
        end
        days = days - DAYS_PER_MONTH[i]
    end

    -- Remaining days index start at 0 so add 1
    local day = days + 1

    -- Return formatted string YYYY-MM-DD HH:MM:SS
    return string.format("%04d-%02d-%02d %02d:%02d:%02d", year, month, day, hour, minute, second)
end

-- Helper function to get player's inventory data
function get_player_inventory(steam_id)
    if not player_inventories[steam_id] then
        -- Initialize new inventory
        player_inventories[steam_id] = {
            fish_list = {},
            json_path = "server/inventory/" .. steam_id .. ".json"
        }
        
        -- Try to load existing inventory
        if IS_HOST then
            local loaded_data = load_json(player_inventories[steam_id].json_path)
            if loaded_data and loaded_data.fish_list then
                player_inventories[steam_id].fish_list = loaded_data.fish_list
            end
        end
    end
    return player_inventories[steam_id]
end

-- HOST function to add fish to inventory
function add_fish_to_inventory( steam_id, fish)

    
    local inventory = get_player_inventory(steam_id)
    
    -- Check inventory limit
    if #inventory.fish_list >= MAX_INVENTORY_SIZE then
        run_network_function(name, "show_inventory_full_CLIENT", {}, steam_id)
        return false
    end
    
    -- Add catch timestamp and location
    -- Capture player's current position and store it as primitive values to ensure
    -- the data survives JSON serialization/network transfer.
    local pos = get_value("", steam_id, "position") or Vector2.ZERO
    local fish_data = {
        name = fish.name,
        weight = fish.weight,
        image = fish.image,
        rarity = fish.rarity,
        water_source = fish.water_source,
        catch_time = get_os_time(),
        -- Store x/y separately so we always end up with a basic Lua table rather than
        -- a Vector2 userdata (userdata would be lost or converted when sent over the
        -- network, leading to (0,0) on the client side).
        catch_location = { x = pos.x, y = pos.y }
    }
    
    -- Add to inventory
    table.insert(inventory.fish_list, fish_data)
    
    -- Save to JSON
    save_json(inventory.json_path, {fish_list = inventory.fish_list})
    
    -- Show warning if near limit
    if #inventory.fish_list >= WARNING_THRESHOLD then
        run_network_function(name, "show_inventory_warning_CLIENT", {
            #inventory.fish_list, MAX_INVENTORY_SIZE},steam_id)
    end

    -- If the player currently has inventory panel open, refresh it by sending data again
    run_network_function("-inventory_manager", "send_inventory_data_CLIENT", {inventory.fish_list}, steam_id)
    
    return true
end

-- HOST function to remove fish from inventory
function remove_fish_from_inventory_HOST(sender_id, index)
    local inventory = get_player_inventory(sender_id)
    if not inventory.fish_list[index] then return end
    
    -- Remove fish
    table.remove(inventory.fish_list, index)
    
    -- Save to JSON
    save_json(inventory.json_path, {fish_list = inventory.fish_list})
    
    -- Refresh UI
    run_network_function("-inventory_manager", "send_inventory_data_CLIENT", {inventory.fish_list}, sender_id)
end

-- Host-side entry point: client requests its inventory data
function request_inventory_data_HOST(sender_id)
    local inventory = get_player_inventory(sender_id)
    run_network_function("-inventory_manager", "send_inventory_data_CLIENT", {inventory.fish_list}, sender_id)
end






function create_loading_panel()
    if is_panel_exists(inventory_panel_name) then
        return
    end
    
    local panel_config = {
        title = "Fish Inventory",
        text = "Loading...",
        resizable = true,
        is_scrollable = true,
        minimum_size = Vector2(420, 540),
        
    }
    inventory_panel_name=create_panel(panel_config)
end

-- CLIENT function: receive inventory data and build UI
-- fish_list is an array of fish dictionaries sent from host
function send_inventory_data_CLIENT(sender_id, fish_list)
    -- Cache for later detail view & remove requests
    client_fish_list = fish_list or {}
    
    -- If inventory panel is not open, just store data and exit
    if not is_panel_exists(inventory_panel_name) then
        return
    end

    -- Refresh panel: close and rebuild
    close_panel(inventory_panel_name)

    local panel_config = {
        title = "Fish Inventory (" .. #client_fish_list .. "/" .. MAX_INVENTORY_SIZE .. ")",
        text = "Click on a fish to see details",
        resizable = true,
        is_scrollable = true,
        minimum_size = Vector2(420, 540),
    }

    inventory_panel_name=create_panel(panel_config)

    -- Add fish entries
    for i, fish in ipairs(client_fish_list) do
        local button_color = rarity_colors[fish.rarity]
        local button_config = {
            text = fish.name .. " (" .. fish.weight .. " kg)",
            color = button_color,
            entity_name = "-inventory_manager",
            function_name = "show_fish_details",
            extra_args = {index = i},
            is_vertical = true,
            size = Vector2(380, 80),
            icon_path = fish.image
        }
        local button_path = add_custom_button_to_panel(inventory_panel_name, button_config)

    end
end

-- Detail panel when fish button clicked
function show_fish_details(args)
	local index = args.extra_args and args.extra_args.index or args.index or 1
	local fish = client_fish_list[index]
	if not fish then return end
	
	-- Close existing detail panel if present
	if is_panel_exists(detail_panel_name) then
		close_panel(detail_panel_name)
	end
	
	local rarity_hex = {
		common = "#b3b3b3",
		rare = "#3399ff",
		epic = "#cc33cc",
		legendary = "#ffcc00",
		garbage = "#808080"
	}
	local color_hex = rarity_hex[fish.rarity] or "#ffffff"
	local weight_kg = to_number(fish.weight, 0)
	local fish_weight_pounds = math.floor(weight_kg * 2.20462 * 100) / 100
	local pos_x, pos_y = 0, 0
    -- Support both table and Vector2 storage formats for backwards-compatibility
    if fish.catch_location then
        -- New format: plain Lua table {x=…, y=…}
        if type(fish.catch_location) == "table" then
            pos_x = to_number(fish.catch_location.x, 0)
            pos_y = to_number(fish.catch_location.y, 0)
        -- Legacy format: Godot Vector2 userdata
        elseif fish.catch_location.x and fish.catch_location.y then
            pos_x = to_number(fish.catch_location.x, 0)
            pos_y = to_number(fish.catch_location.y, 0)
        end
    end

    local detail_text = "[color=" .. color_hex .. "]" .. fish.name .. "[/color]\nWeight: " .. weight_kg .. " kg (" .. fish_weight_pounds .. " lbs)\nRarity: " .. fish.rarity .. "\nSource: " .. fish.water_source .. "\nCaught: " .. format_timestamp(fish.catch_time) .. "\nLocation: (" .. math.floor(pos_x) .. ", " .. math.floor(pos_y) .. ")"
	
	local panel_config = {
		title = "Fish Details",
		text = detail_text,
		resizable = false
	}
	detail_panel_name = create_panel(panel_config)
	
	-- Image
	add_image_to_panel(detail_panel_name, fish.image)
	
	-- Remove button
	add_button_to_panel(detail_panel_name, {
		text = "Remove",
		entity_name = "-inventory_manager",
		function_name = "request_remove_fish",
		extra_args = {index = index}
	})
	-- Replay catch button
	add_button_to_panel(detail_panel_name, {
		text = "Replay Catch",
		entity_name = "-inventory_manager",
		function_name = "replay_catch_animation",
		extra_args = {index = index}
	})
end

-- CLIENT function to show inventory full message
function show_inventory_full_CLIENT(sender_id)
    create_panel({
        title = "Inventory Full",
        text = "Your inventory is full, the fish could not be added to your inventory!",
        resizable = false,
        countdown = 3
    })
end

-- CLIENT function to show inventory warning
function show_inventory_warning_CLIENT(sender_id, current_count, max_count)
    create_panel({
        title = "Inventory Warning",
        text = string.format("⚠️ Inventory almost full!\nRemove some fish or you will not be able to be added to inventory anymore(%d/%d)", current_count, max_count),
        resizable = false,
        countdown = 10,
        no_multiple_tag = "inventory_warning"
    })
end



are_you_sure_panel_name=nil
-- Helper function to create confirmation panel for fish removal
function create_remove_fish_confirmation(message, fish_index)
    local settings = {
        text = message,
        title = "Are you sure?",
        resizable = false,
        no_multiple_tag = "remove_fish_confirmation"
    }

    -- Store index for later use
    fish_index_to_remove = fish_index

    -- Create main panel
    are_you_sure_panel_name = create_panel(settings)

    -- Add Yes button
    add_button_to_panel(are_you_sure_panel_name, {
        text = "Yes",
        is_vertical = false,
        color = "#FF0000",
        entity_name = "-inventory_manager",
        function_name = "confirm_remove_fish"
    })

    -- Add Cancel button
    add_button_to_panel(are_you_sure_panel_name, {
        text = "Cancel",
        is_vertical = false,
        color = "#808080",
        entity_name = "-inventory_manager",
        function_name = "cancel_remove_fish"
    })

    return are_you_sure_panel_name
end

-- Function called when user confirms fish removal
function confirm_remove_fish()
    if fish_index_to_remove and client_fish_list[fish_index_to_remove] then
        -- Close detail panel
        if is_panel_exists(detail_panel_name) then
            close_panel(detail_panel_name)
        end

        if is_panel_exists(are_you_sure_panel_name) then
            close_panel(are_you_sure_panel_name)
        end
        
        -- Send removal request to host
        run_network_function("-inventory_manager", "remove_fish_from_inventory_HOST", {fish_index_to_remove})
    end
    
    -- Clear stored index
    fish_index_to_remove = nil
end

-- Function called when user cancels fish removal
function cancel_remove_fish()
    -- Just clear the stored index
    fish_index_to_remove = nil
    -- Close detail panel
    if is_panel_exists(are_you_sure_panel_name) then
        close_panel(are_you_sure_panel_name)
    end
            
end

function request_remove_fish(args)
	local idx = args.extra_args and args.extra_args.index or args.index
    if not idx then return end
    if not client_fish_list[idx] then return end
    
    local fish = client_fish_list[idx]
    local message = "Do you want to remove this fish from your inventory?\n\n" .. fish.name .. " (" .. fish.weight .. " kg)"
    
    create_remove_fish_confirmation(message, idx)
end

-- CLIENT function to replay catch animation
function replay_catch_animation(args)
    local idx = (args.extra_args and args.extra_args.index) or args.index
    if not idx then return end

    local now = get_os_time()
    local remaining = (last_replay_catch_client_time + REPLAY_CATCH_COOLDOWN) - now
    if remaining > 0 then
        -- Show cooldown panel
        create_panel({
            title = "Cooldown",
            text = "Try again in " .. math.ceil(remaining) .. " seconds",
            resizable = false,
            countdown = math.ceil(remaining),
            no_multiple_tag = "replay_catch_cooldown"
        })
        return
    end

    last_replay_catch_client_time = now

    -- Send request to host; host will validate and broadcast
    run_network_function("-inventory_manager", "replay_catch_animation_HOST", {idx})
end

-- HOST function to validate replay request and broadcast animation to everyone
function replay_catch_animation_HOST(sender_id, index)
    local now = get_os_time()
    local last_time = player_replay_catch_timestamps[sender_id] or 0
    if now - last_time < REPLAY_CATCH_COOLDOWN then
        return -- rate limited
    end
    player_replay_catch_timestamps[sender_id] = now

    local inventory = get_player_inventory(sender_id)
    if not inventory or not inventory.fish_list[index] then return end

    local fish = inventory.fish_list[index]

    local weight_kg = to_number(fish.weight, 0)
    local fish_weight_pounds = math.floor(weight_kg * 2.20462 * 100) / 100
    local fish_text = fish.name .. "\n" .. weight_kg .. " kg / " .. fish_weight_pounds .. " lbs\nRarity: " .. fish.rarity

    -- Show bubble effect above the owner player; spawning on host replicates to all
    run_function("-fishing_game", "show_world_space_result", {
        sender_id, fish.image, fish_text, fish.weight, rarity_colors[fish.rarity]
    })
end


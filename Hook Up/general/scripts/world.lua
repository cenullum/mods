singleton_name = "w"

-- Side-scroller setup
set_controller_type(0) -- side-scroller
set_gravity_direction(Vector2(0, 1))
set_camera_zoom(Vector2(2.0, 2.0))


-- Input display names
set_input_display_name("stick_1", "Move")
set_input_display_name("stick_2", "Aim")
set_input_display_name("key_6", "Inventory")
set_input_display_name("key_7", "Hook")
set_input_display_name("key_12", "Hook")

function refresh_status_label(state, charging, cooldown)
    local header = "@key_6@ Inventory\n@stick_1@ Move\n\n"
    local status = ""

    if charging then
        if state == "READY" then
            status = "(RELEASE) to Fire Hook!"
        elseif state == "ATTACHED" then
            status = "(RELEASE) to Launch!"
        end
    else
        if state == "READY" then
            if cooldown and cooldown > 0 then
                status = string.format("Cooldown: %.1fs", cooldown) .. "\n"
            end
            status = status .. "@key_7@/@key_12@ Hook"
        elseif state == "ATTACHED" then
            status = "@key_7@/@key_12@ Launch self"
        elseif state == "SEARCHING" then
            status = "Searching for fish...\n@key_7@/@key_12@ Cancel"
        elseif state == "WARNING" then
            status = "🐟 FISH FOUND! 🐟\n@key_7@/@key_12@ CATCH!"
        elseif state == "FISHING" then
            status = "FISHING!\n@key_7@/@key_12@ Pull!"
        elseif state == "FIRING" then
            status = "Hook Firing...\n@key_7@/@key_12@ Cancel"
        end
    end
    print("refresh_status_label", header .. status)
    set_value("", "_hook_status_label", "text", header .. status)
end

function update_inputs_label()
    refresh_status_label("READY", false, 0)
end

function _on_gamepad_connection_changed(has_gamepad)
    update_inputs_label()
end

-- Hook power settings
hook_power_min = 50
hook_power_max = 500
hook_power_default = 200

-- Background music system
local music_files = {
    "Drift Away",
    "Drift Away 2",
    "Jazz Lo",
    "Moonlit Wanderer",
    "Whispers in the Night"
}

function shuffle_array(array)
    local n = #array
    for i = n, 2, -1 do
        local j = math.random(1, i)
        array[i], array[j] = array[j], array[i]
    end
    return array
end

music_files = shuffle_array(music_files)
local current_music_index = 1

function play_next_music()
    if #music_files > 0 then
        local current_music_name = music_files[current_music_index]

        local result = set_audio({
            stream_path = "music/" .. current_music_name,
            volume = -12.0,
            bus = "Music",
            name = "background_music_" .. current_music_index,
            no_multiple_tag = "background_music",
            entity_name = "-w",
            function_name = "on_music_finished"
        })

        print("Now playing: " .. current_music_name)
    end
end

function on_music_finished(config)
    current_music_index = current_music_index + 1
    if current_music_index > #music_files then
        current_music_index = 1
    end
    play_next_music()
end

-- Start first music
play_next_music()

-- Change to gameplay view
change_view("gameplay")

-- Set initial inputs label
update_inputs_label()

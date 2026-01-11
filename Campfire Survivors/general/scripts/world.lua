singleton_name = "w"

set_controller_type(1) --topdown
set_gravity_direction(Vector2(0,0))
set_camera_zoom(Vector2(2.5,2.5))
set_background_color(Color(0.2,0.1,0.1,1.0))

set_input_display_name("stick_1","Movement")
set_input_display_name("key_6","Interact")

-- Background music system
local music_files = {
    "Adrenaline Rush",
    "Endless Horde Mayhem", 
    "Neon Nights",
    "Pixelated Dreams",
    "Pixel Dreams",
    "Rush rush rush",
    "Upbeat",
    "Upgrade Frenzy",
    -- Add your music files here (without extension)
}


function shuffle_array(array)
    local n = #array
    for i = n, 2, -1 do
        local j = math.random(1, i)
        array[i], array[j] = array[j], array[i]
    end
    return array
end

-- Shuffle music files once at startup
music_files = shuffle_array(music_files)
print("Music playlist shuffled! Order:")
for i, music_name in ipairs(music_files) do
    print("  " .. i .. ": " .. music_name)
end

local current_music_index = 1

-- Function to play next music
function play_next_music()
    local current_music_name = music_files[current_music_index]
    
    -- Play music with callback system - no timers needed!

    local result = set_audio({
        stream_path = "music/" .. current_music_name,  -- from music folder
        volume = -10.0,  -- -10 dB (approximately 30% volume)
        bus = "Music",
        name = "background_music_" .. current_music_index,
        no_multiple_tag = "background_music",  -- prevents multiple background music
        entity_name = "-w",  -- this singleton
        function_name = "on_music_finished"  -- function to call when finished
    })
    
    print("Now playing: " .. current_music_name .. " (index: " .. current_music_index .. ")")
end

-- Function called when music finishes - receives full config data
function on_music_finished(config)
    -- Move to next music
    current_music_index = current_music_index + 1
    if current_music_index > #music_files then
        current_music_index = 1 -- Loop back to first
    end
    
    play_next_music()
end

-- Function to skip to next music (called by !next command)
function skip_to_next_music()
    print("Music skipped by user command")
    
    -- Move to next music
    current_music_index = current_music_index + 1
    if current_music_index > #music_files then
        current_music_index = 1 -- Loop back to first
    end
    
    -- Play next music immediately (no_multiple_tag will stop current music)
    play_next_music()
end

-- Start first music
play_next_music()

-- ================ AUDIO EFFECTS EXAMPLES ================
-- Uncomment any of these examples to test audio effects

-- Example 1: Add reverb to Music bus
-- add_audio_effect({
--     bus_name = "Music",
--     effect_type = "reverb",
--     effect_config = {
--         room_size = 0.8,
--         damping = 0.5,
--         wet = 0.3,
--         dry = 1.0
--     }
-- })

-- Example 2: Add delay to Effect bus
-- add_audio_effect({
--     bus_name = "Effect",
--     effect_type = "delay",
--     effect_config = {
--         tap1_delay_ms = 200.0,
--         tap1_level_db = -8.0,
--         feedback_active = true,
--         feedback_delay_ms = 300.0,
--         feedback_level_db = -12.0
--     }
-- })

-- Example 3: Add low-pass filter to Music bus (makes it sound muffled)
-- add_audio_effect({
--     bus_name = "Music",
--     effect_type = "lowpass",
--     effect_config = {
--         cutoff_hz = 1000.0,
--         resonance = 0.7
--     }
-- })

-- Example 4: Add distortion to Effect bus
-- add_audio_effect({
--     bus_name = "Effect",
--     effect_type = "distortion",
--     effect_config = {
--         drive = 0.5,
--         pre_gain = 6.0,
--         post_gain = -3.0
--     }
-- })

-- Example functions for runtime effect control:

-- Function to add music reverb effect
function add_music_reverb()
    add_audio_effect({
        bus_name = "Music",
        effect_type = "reverb",
        effect_config = {
            room_size = 0.9,
            damping = 0.3,
            wet = 0.4,
            dry = 0.8
        }
    })
    print("Added reverb to Music bus")
end

-- Function to remove all effects from Music bus
function clear_music_effects()
    clear_bus_effects({bus_name = "Music"})
    print("Cleared all effects from Music bus")
end

-- Function to add dramatic low-pass filter (underwater effect)
function add_underwater_effect()
    add_audio_effect({
        bus_name = "Music",
        effect_type = "lowpass",
        effect_config = {
            cutoff_hz = 500.0,
            resonance = 0.8
        }
    })
    print("Added underwater effect to Music bus")
end

change_view("gameplay")

set_vignette({
    visible = true,

    color = Color(0, 0, 0, 1.0)

})





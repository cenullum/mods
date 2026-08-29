singleton_name = "w"

-- =============================================================================
-- School Days - world setup.
--
-- This is a classic visual novel driven by the engine's Visual Novel runtime
-- (vn_* functions). The STORY itself (characters, dialog, branches, variables,
-- multiple endings) lives in general/school_days.json - the exact format the
-- Online Asset Editor's Visual Novel tab exports. All the presentation you see
-- (background, character sprite, name box, dialog, choice buttons) is ordinary
-- HUD built here + in sd_manager.lua; the engine only tracks the story graph.
--
-- Everything on screen is the "hud" view (general/views/hud.json), a pure
-- screen-space canvas, so there are no world avatars or camera work to do -
-- players only ever vote through the HUD. sd_manager.lua owns the game loop.
-- =============================================================================

set_background_color(Color(0.06, 0.06, 0.09, 1))
change_view("hud")

-- Background music system (same jazz playlist as Hook Up), shuffled and
-- looped forever on the Music bus.
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

        set_audio({
            stream_path = "music/" .. current_music_name,
            volume = -12.0,
            bus = "Music",
            name = "background_music_" .. current_music_index,
            no_multiple_tag = "background_music",
            entity_name = "-w",
            function_name = "on_music_finished"
        })
    end
end

function on_music_finished(config)
    current_music_index = current_music_index + 1
    if current_music_index > #music_files then
        current_music_index = 1
    end
    play_next_music()
end

play_next_music()

-- Idle screen shown until the host starts. sd_manager takes over from there.
set_label({ name = "_hint", text ="{school_days}" })
set_label({ name = "_speaker", text = "" })
-- Flat, transparent black backdrop behind the dialog text so it stays readable
-- over any background art/character sprite (same trick as Hook Up's fishing
-- "_background": a plain white_32.png tinted via modulate, never touched again).
set_image({ name = "_dialog_bg", visible = true })
set_label({ name = "_dialog", text ="{a_branching_school_story_you_play_togeth}" ..
    "{intro_line1}" ..
    "{intro_line2}" ..
    "{intro_line3}" ..
    "{intro_line4}" })
set_image({ name = "_char", visible = false })

if IS_HOST then
    set_button({ name = "_start", visible = true })
    set_label({ name = "_status", text ="{you_are_the_host}" })
else
    set_label({ name = "_status", text ="{waiting_for_the_host}" })
end

singleton_name = "hud"
network_mode = 0

-- =============================================================================
-- Beyaz Canavar - local HUD (general/views/hud.json): bottom-right key hints
-- that follow the player's role, the current room's name, a centre banner,
-- the "hold E" prompt + progress bar and a status line (tasks for humans,
-- the scream cooldown for monsters). Everything here is local to this peer.
-- Key hints use @key_N@ placeholders, so they always show the player's own
-- bindings (keyboard or gamepad).
-- =============================================================================

local HINTS = "_bc_hints"
local ROOM = "_bc_room"
local STATUS = "_bc_status"
local BANNER = "_bc_banner"
local PROMPT = "_bc_prompt"
local PROGRESS = "_bc_progress"

local role = "human"
local phase = "lobby"
-- Screen effects: humans see a faint CRT that gets stronger as a monster gets
-- closer; monsters see noise. Strength follows the distance smoothly.
local CRT_BASE = 0.4
local CRT_MAX = 1.0
local NOISE_BASE = 0.06
local NOISE_MAX = 0.32
local DANGER_RANGE = 10 * 32
local SCANLINE = 3.6 -- base-resolution px: ~12 px per line pair on a 1080p screen (twice the old 6)
local GRAIN = 2
local crt_now = CRT_BASE
local danger_now = 0
local danger_t = 0
local tasks_line = ""
local scream_ready_at = 0
local clock = 0
local status_t = 0
local shown_status = ""

local function hints_text()
    if phase == "lobby" or phase == "cutscene" or phase == "ended" then
        return "@stick_1@ {move}\n{lobby_hint}"
    end
    if role == "monster" then
        return "@stick_1@ {move}\n@key_8@ {scream}"
    end
    if role == "escaped" then
        return "@stick_1@ {move}"
    end
    return "@stick_1@ {move}\n@key_6@ {interact_hold}\n@key_4@ {tasks}\n@key_11@ {map}"
end

local function refresh_hints()
    set_label({ name = HINTS, text = hints_text() })
end

local function status_text()
    if phase ~= "playing" and phase ~= "escape" then return "" end
    if role == "monster" then
        local left = math.ceil(scream_ready_at - clock)
        if left <= 0 then return "{you_are_the_monster}\n{scream_ready}" end
        return "{you_are_the_monster}\n" .. string.format(translate("{scream_in}"), left)
    end
    if role == "escaped" then return "{you_escaped}" end
    return tasks_line
end

local function refresh_status()
    local text = status_text()
    if text ~= shown_status then
        shown_status = text
        set_label({ name = STATUS, text = text })
    end
end

change_view("hud")
refresh_hints()

local function apply_effects()
    if role == "monster" then
        set_crt({ visible = true, intensity = 0.3, scanline_size = SCANLINE, scanline_strength = 0.4, aberration = 3, flicker = 0.08 })
        set_screen_noise({ visible = true, intensity = 0.25, grain_size = GRAIN, speed = 20, color = Color(0.85, 0.9, 1, 1) })
    else
        local k = danger_now
        set_crt({ visible = true, intensity = CRT_BASE + (CRT_MAX - CRT_BASE) * k, scanline_size = SCANLINE,
            scanline_strength = 0.55,
            aberration = 2 + 4 * k, flicker = 0.06 + 0.14 * k })
        set_screen_noise({ visible = true, intensity = NOISE_BASE + (NOISE_MAX - NOISE_BASE) * k, grain_size = GRAIN,
            speed = 24, color = Color(1, 1, 1, 1) })
    end
end

function set_role(new_role)
    role = new_role
    if role == "monster" and scream_ready_at < clock then scream_ready_at = clock + 15 end
    danger_now = 0
    apply_effects()
    refresh_hints()
    refresh_status()
end

-- Distance from this player to the closest monster (NPC or player).
local function nearest_monster()
    local me = get_value("", LOCAL_STEAM_ID, "position")
    if not me then return math.huge end
    local best = math.huge
    local function consider(id)
        local p = get_value("", id, "position")
        if p then
            local d = math.sqrt((p.x - me.x) ^ 2 + (p.y - me.y) ^ 2)
            if d < best then best = d end
        end
    end
    for _, id in ipairs(get_entity_names_by_tag("monster")) do consider(id) end
    for _, id in ipairs(get_entity_names_by_tag("user")) do
        if id ~= LOCAL_STEAM_ID and run_function("-gm", "get_role", { id }) == "monster" then consider(id) end
    end
    return best
end

function set_phase(new_phase)
    phase = new_phase
    refresh_hints()
    refresh_status()
    if phase == "lobby" then
        set_label({ name = ROOM, text = "{room_detention}" })
    end
end

function set_room(token)
    set_label({ name = ROOM, text = token })
end

function set_tasks_line(text)
    tasks_line = text
    refresh_status()
end

function scream_used(cooldown)
    scream_ready_at = clock + cooldown
    refresh_status()
end

function banner(text, seconds)
    set_label({ name = BANNER, text = text, visible = true })
    local t = math.max(0.5, tonumber(seconds) or 3)
    start_timer({ timer_id = "bc_banner", entity_name = name, function_name = "hide_banner",
        wait_time = t, duration = t })
end

function hide_banner(args)
    set_label({ name = BANNER, visible = false })
end

function prompt(text)
    set_label({ name = PROMPT, text = text or "" })
end

-- v in 0..1; negative hides the bar.
function progress(v)
    if v < 0 then
        set_progress_bar({ name = PROGRESS, visible = false })
    else
        set_progress_bar({ name = PROGRESS, value = v * 100, visible = true })
    end
end

function _process(delta, inputs)
    clock = clock + delta
    danger_t = danger_t - delta
    if danger_t <= 0 then
        danger_t = 0.2
        if role ~= "monster" then
            -- Danger 0..1 from the closest monster; CRT and noise both follow it.
            local want = 0
            if phase == "playing" or phase == "escape" then
                local d = nearest_monster()
                local k = math.max(0, math.min(1, 1 - d / DANGER_RANGE))
                want = k * k
            end
            -- Ease toward the target so it never jumps.
            local next_value = danger_now + (want - danger_now) * 0.35
            if math.abs(next_value - danger_now) > 0.005 then
                danger_now = next_value
                apply_effects()
            end
        end
    end
    status_t = status_t - delta
    if status_t <= 0 then
        status_t = 0.5
        refresh_status()
    end
    return nil
end

function _on_gamepad_connection_changed(has_gamepad)
    refresh_hints()
end

apply_effects()

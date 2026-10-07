singleton_name = "anim"
network_mode = 0

-- =============================================================================
-- Beyaz Canavar - monster frame animation (LOCAL, every peer drives its own).
--
-- Used for the NPC monster and for every player who became a monster. All
-- frames of all four animations are created ONCE per entity as hidden images
-- (set_image reads the PNG from disk every time it changes a path, so swapping
-- textures per frame would hit the disk 12 times a second); after that a frame
-- change is two `visible` flips.
--
--   setup(entity)              build the sprites (idempotent)
--   play(entity, anim, loops)  one-shot: wake_up / scream / eating, then walk
--   hold(entity, anim, frame)  freeze on one frame (the sleeping lobby monster)
--   walk(entity)               back to walking (chasing frames while moving)
--   hide(entity)               hide everything (player turned back to human)
--
-- Walking needs no network: each peer watches the entity's own position and
-- loops the chasing frames while it moves, standing still on frame 1. The art
-- faces right, so it is flipped while moving left.
--
-- Footsteps: whenever a walking monster's foot lands (chasing frames 1 and 6)
-- everyone near it feels a screenshake - humans, other monsters, and the
-- monster player itself (its own steps: distance 0, full strength) - always
-- below the scream's. Whoever can SEE the monster (line of sight, inside the fog radius) gets the full
-- strength whatever the distance; behind walls it fades with distance. Purely
-- local, so nothing is sent. The stomp SOUND lands on the same frame as the
-- shake: positional audio on the monster's body (fades out at STEP_RANGE), a
-- little quieter when a wall is in between, and it plays even while a bigger
-- shake suppresses the step's own shake.
--
-- The numbers look big because the camera has position smoothing on: the
-- engine adds the shake to the camera's TARGET position on 30 Hz physics
-- ticks, and the smoothing averages that jitter down to roughly 1/3 on screen.
-- =============================================================================

local FPS = 8.4           -- 12 * 0.7: every animation 30% slower (game_manager/monster use the same)
local SIZE = 128          -- frames are drawn 1:1 (pixel perfect)
local OFFSET = Vector2(0, -56) -- feet (bottom of the frame) at the body
local Z = 1
local MOVE_EPSILON = 0.6  -- px per frame that counts as moving
local STEP_FRAMES = { [1] = true, [6] = true }
local STEP_SEE = 7 * 32   -- user.lua's fog radius: inside it with line of sight = "sees it"
local STEP_RANGE = 14 * 32 -- heard (through walls) within this distance
local STEP_MIN, STEP_MAX = 3, 11 -- shake intensity at the edge of hearing / seen (scream stun is 30)
local STEP_SECONDS = 0.3
local STEP_SOUNDS = 8      -- sounds/monster_step/monster_step-01..08
local STEP_WALL_DB = -6   -- the stomp through a wall
-- Frame that plays sounds/scream, once per one-shot animation: the scream
-- (frame 4, where game_manager's stun lands too) and the wake-up (the
-- round-start cutscene and every player turned monster).
local SCREAM_FRAMES = { scream = 4, wake_up = 12 }
local SCREAM_RANGE = 24 * 32

local ANIMS = {
    wake_up = { folder = "wake_up/wakeup", count = 23 },
    chasing = { folder = "chasing/chasing", count = 9 },
    scream = { folder = "scream/scream", count = 14 },
    eating = { folder = "eating/eating", count = 17 },
}
local ORDER = { "wake_up", "chasing", "scream", "eating" }

-- A strong shake (stun, scream, caught) must not be cut short by a footstep:
-- screenshake() replaces whatever shake is running.
local clock = 0
local big_shake_until = 0

function shake(duration, intensity)
    big_shake_until = clock + duration
    screenshake(duration, intensity)
end

local function footstep(entity)
    local me = get_value("", LOCAL_STEAM_ID, "position")
    local mp = get_value("", entity, "position")
    if not me or not mp then return end
    local d = math.sqrt((me.x - mp.x) ^ 2 + (me.y - mp.y) ^ 2)
    if d > STEP_RANGE then return end
    local seen = d <= STEP_SEE and has_line_of_sight(mp, me)
    set_audio({ stream_path = string.format("monster_step/monster_step-%02d", math.random(1, STEP_SOUNDS)),
        parent_name = entity, is_2d = true, max_distance = STEP_RANGE, volume = seen and 0 or STEP_WALL_DB })
    if clock < big_shake_until then return end
    local strength = STEP_MAX
    if not seen then
        local near = 1 - d / STEP_RANGE
        strength = STEP_MIN + (STEP_MAX * 0.8 - STEP_MIN) * near
    end
    screenshake(STEP_SECONDS, strength)
end

-- entity name -> { shown = sprite name, flip = bool, mode, anim, frame, t, loops, last = Vector2 }
local actors = {}

local function sprite_name(anim, i)
    return "mon_" .. anim .. "_" .. i
end

local function show(entity, a, anim, frame)
    local new_name = sprite_name(anim, frame)
    if a.shown ~= new_name then
        if a.shown ~= "" then set_value(entity, a.shown, "visible", false) end
        set_value(entity, new_name, "visible", true)
        a.shown = new_name
        a.flips[new_name] = a.flips[new_name] or false
    end
    if a.flips[new_name] ~= a.flip then
        set_value(entity, new_name, "flip_h", a.flip)
        a.flips[new_name] = a.flip
    end
end

function setup(entity)
    if actors[entity] then return end
    if not entity_exists(entity) then return end
    -- Sprites survive hide(); only an entity that never had them builds them.
    if not entity_exists(sprite_name("chasing", 1), entity) then
        build(entity)
    end
    local pos = get_value("", entity, "position") or Vector2(0, 0)
    actors[entity] = { shown = "", flip = false, flips = {}, mode = "walk", anim = "chasing",
        frame = 1, t = 0, loops = 0, last = pos, moving_t = 0 }
    show(entity, actors[entity], "chasing", 1)
end

function build(entity)
    for _, anim in ipairs(ORDER) do
        local def = ANIMS[anim]
        for i = 1, def.count do
            set_image({ parent_name = entity, name = sprite_name(anim, i),
                image_path = def.folder .. i, scale = Vector2(SIZE, SIZE),
                position = OFFSET, visible = false, z_index = Z })
        end
    end
end

function play(entity, anim, loops)
    setup(entity)
    local a = actors[entity]
    if not a or not ANIMS[anim] then return end
    a.mode = "once"
    a.anim = anim
    a.frame = 1
    a.t = 0
    a.loops = math.max(1, math.floor(loops or 1))
    show(entity, a, anim, 1)
end

function hold(entity, anim, frame)
    setup(entity)
    local a = actors[entity]
    if not a or not ANIMS[anim] then return end
    a.mode = "hold"
    a.anim = anim
    a.frame = math.max(1, math.min(ANIMS[anim].count, math.floor(frame or 1)))
    show(entity, a, anim, a.frame)
end

function walk(entity)
    local a = actors[entity]
    if not a then return end
    a.mode = "walk"
    a.anim = "chasing"
    a.frame = 1
    a.t = 0
    show(entity, a, "chasing", 1)
end

function hide(entity)
    local a = actors[entity]
    if not a then return end
    if a.shown ~= "" and entity_exists(a.shown, entity) then set_value(entity, a.shown, "visible", false) end
    actors[entity] = nil
end

-- Seconds a one-shot animation takes (the host uses it to time freezes).
function duration(anim, loops)
    local def = ANIMS[anim]
    if not def then return 0 end
    return def.count * math.max(1, math.floor(loops or 1)) / FPS
end

function _process(delta, inputs)
    clock = clock + delta
    for entity, a in pairs(actors) do
        if not entity_exists(entity) then
            actors[entity] = nil
        else
            local pos = get_value("", entity, "position") or a.last
            local dx = pos.x - a.last.x
            local moving = math.abs(dx) + math.abs(pos.y - a.last.y) > MOVE_EPSILON
            a.last = pos
            if math.abs(dx) > MOVE_EPSILON * 0.5 then a.flip = dx < 0 end
            if a.mode == "once" then
                a.t = a.t + delta
                local frame_time = 1 / FPS
                while a.t >= frame_time do
                    a.t = a.t - frame_time
                    a.frame = a.frame + 1
                    -- Every peer plays the scream itself, on the frame it sees.
                    if SCREAM_FRAMES[a.anim] == a.frame then
                        set_audio({ stream_path = "scream", parent_name = entity, is_2d = true,
                            max_distance = SCREAM_RANGE })
                    end
                    if a.frame > ANIMS[a.anim].count then
                        a.loops = a.loops - 1
                        if a.loops > 0 then
                            a.frame = 1
                        else
                            a.mode = "walk"
                            a.anim = "chasing"
                            a.frame = 1
                            break
                        end
                    end
                end
                show(entity, a, a.anim, a.frame)
            elseif a.mode == "walk" then
                if moving then
                    a.moving_t = 0.15
                else
                    a.moving_t = a.moving_t - delta
                end
                if a.moving_t > 0 then
                    a.t = a.t + delta
                    local frame_time = 1 / FPS
                    while a.t >= frame_time do
                        a.t = a.t - frame_time
                        a.frame = a.frame % ANIMS.chasing.count + 1
                        if STEP_FRAMES[a.frame] then footstep(entity) end
                    end
                else
                    a.frame = 1
                    a.t = 0
                end
                show(entity, a, "chasing", a.frame)
            else
                show(entity, a, a.anim, a.frame)
            end
        end
    end
    return nil
end

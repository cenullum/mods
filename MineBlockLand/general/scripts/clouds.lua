singleton_name = "clouds"
network_mode = 0

-- =============================================================================
-- Drifting clouds (local entity on every peer, auto-created from singleton_name).
--
-- The HOST decides every cloud (image, spawn point, speed, size) and broadcasts
-- it once; after that each peer moves the cloud on its own from
--   position = start + (-speed * age, 0)
-- so no per-frame traffic exists. Late joiners get the live clouds replayed with
-- their current age. A cloud fades in, drifts left, fades out, then is destroyed.
--
-- Clouds appear at the right edge of a random player's view, above or below
-- them, and drift left.
-- =============================================================================

local IMAGES = { "cloud1", "cloud2", "cloud3" }
local MAX_ALPHA = 0.25          -- resting opacity of a cloud
local LIFETIME = 15.0           -- seconds from spawn to gone
local FADE_IN = 4.0
local FADE_OUT = 4.0
local SPEED_MIN, SPEED_MAX = 18, 34
local SCALE_MIN, SCALE_MAX = 0.8, 1.6
local SPAWN_EVERY = 2.5         -- host tries to make one cloud this often
local MAX_PER_PLAYER = 4
local MAX_TOTAL = 14
local Z_INDEX = 10
local SHADOW_HEIGHT = 170       -- set_shadow_of_image y_offset: the cloud floats high above its shadow

local SPAWN_DX_MIN, SPAWN_DX_MAX = 300, 480   -- right of the player (just past the screen edge)
local SPAWN_DY_MIN, SPAWN_DY_MAX = 60, 190      -- above OR below the player

local clock = 0.0               -- local seconds since this entity started
local spawn_timer = 0.0
local next_id = 0
local clouds = {}               -- id -> { img, x, y, speed, birth }

local function smooth(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end

local function alpha_at(age)
    return MAX_ALPHA * smooth(age / FADE_IN) * smooth((LIFETIME - age) / FADE_OUT)
end

local function image_name(id)
    return "cloud_" .. id
end

local function remove_cloud(id)
    local img = image_name(id)
    set_shadow_of_image(name, img, false)
    destroy(name, img)
    clouds[id] = nil
end

-- Runs on every peer (host included): create the cloud locally.
function add_cloud_ALL(sender_id, data)
    local id = tostring(data.id)
    if clouds[id] then return end
    local img = image_name(id)
    local age = data.age or 0.0
    local x = data.x - data.speed * age
    set_image({
        parent_name = name,
        name = img,
        image_path = data.img,
        position = Vector2(x, data.y),
        size = Vector2(data.scale, data.scale),
        flip_h = data.flip == true,
        modulate = Color(1, 1, 1, 0),
        z_index = Z_INDEX,
    })
    set_shadow_of_image(name, img, true, SHADOW_HEIGHT)
    clouds[id] = { img = data.img, x = data.x, y = data.y, speed = data.speed,
                   scale = data.scale, flip = data.flip == true, birth = clock - age }
end

-- Host -> clients (and a single late joiner): same as add_cloud_ALL on the receiving peer.
function add_cloud_CLIENT(sender_id, data)
    add_cloud_ALL(sender_id, data)
end

function _on_user_initialized(steam_id, nickname)
    if not IS_HOST or steam_id == HOST_STEAM_ID then return end
    for id, c in pairs(clouds) do
        run_network_function(name, "add_cloud_CLIENT", {
            id = id, img = c.img, x = c.x, y = c.y, speed = c.speed,
            scale = c.scale, flip = c.flip, age = clock - c.birth,
        }, steam_id)
    end
end

local function eligible_players()
    local list = {}
    for _, user in ipairs(get_entity_names_by_tag("user")) do
        local pos = get_value("", user, "position")
        if pos then list[#list + 1] = pos end
    end
    return list
end

local function count_clouds()
    local n = 0
    for _ in pairs(clouds) do n = n + 1 end
    return n
end

local function host_spawn_cloud()
    local players = eligible_players()
    if #players == 0 then return end
    if count_clouds() >= math.min(MAX_TOTAL, MAX_PER_PLAYER * #players) then return end

    local pos = players[math.random(1, #players)]
    next_id = next_id + 1
    local s = SCALE_MIN + math.random() * (SCALE_MAX - SCALE_MIN)
    local data = {
        id = "h" .. next_id,
        img = IMAGES[math.random(1, #IMAGES)],
        x = pos.x + SPAWN_DX_MIN + math.random() * (SPAWN_DX_MAX - SPAWN_DX_MIN),
        y = pos.y + (math.random() < 0.5 and -1 or 1)
            * (SPAWN_DY_MIN + math.random() * (SPAWN_DY_MAX - SPAWN_DY_MIN)),
        speed = SPEED_MIN + math.random() * (SPEED_MAX - SPEED_MIN),
        scale = s,
        flip = math.random() < 0.5,
        age = 0.0,
    }
    -- Apply on the host directly (run_network_function does nothing outside a
    -- lobby, e.g. in the editor's test run), then tell everyone else.
    add_cloud_ALL(name, data)
    run_network_function(name, "add_cloud_CLIENT", data)
end

function _process(delta, inputs)
    clock = clock + delta

    if IS_HOST then
        spawn_timer = spawn_timer + delta
        if spawn_timer >= SPAWN_EVERY then
            spawn_timer = 0.0
            host_spawn_cloud()
        end
    end

    for id, c in pairs(clouds) do
        local age = clock - c.birth
        if age >= LIFETIME then
            remove_cloud(id)
        else
            set_image({
                parent_name = name,
                name = image_name(id),
                position = Vector2(c.x - c.speed * age, c.y),
                modulate = Color(1, 1, 1, alpha_at(age)),
            })
        end
    end
end

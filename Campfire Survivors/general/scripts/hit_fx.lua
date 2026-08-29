singleton_name = "hfx"
network_mode = 0

-- =============================================================================
-- Hit feedback - the white flash + squash & stretch + elastic wobble that makes
-- a hit FEEL like a hit. Entirely visual and entirely local: nothing here ever
-- touches health, and nothing here is ever sent over the network.
--
-- HOW TO USE IT: on the frame a victim is hurt, on EVERY peer, call
--     run_function("-hfx", "play_hit", { victim, image_name, base_shader, dir })
-- Piggy-back that on the damage broadcast the mod already sends (the _ALL that
-- draws the damage number), so the effect costs no message of its own.
--   victim       entity that was hit
--   image_name   its sprite, the one set_image created
--   base_shader  "" for a plain sprite, or the shader it already wears (a
--                sprite has only ONE material, which is why the flash uniforms
--                also live inside circle.gdshader - pass "circle" for anything
--                already outlined and the outline flashes along with the body)
--   dir          which way it tips; pass cos(angle of the blow), or 1
--   strength     optional multiplier on the squash and the spin. 1 (or nil) is
--                the default look; go lower for something huge, which reads as
--                jelly at full strength, and higher for something flimsy.
--
-- WHY THIS IS A SINGLETON. The animation needs a per-frame tick, and a
-- _process in monster.lua would mean one Lua call per monster per frame just to
-- discover there is nothing to do - with a late wave on screen that is most of
-- a hundred wasted calls every frame. One ticker walks only the handful of
-- sprites that are actually flashing right now, and the table is empty (and the
-- whole _process a single boolean test) the rest of the time.
--
-- The shader does all the maths on the GPU from ONE uniform, so a frame of
-- animation is a single float per flashing sprite - no set_image, no reload.
-- =============================================================================

local FX_SECONDS = 0.26
local SQUASH = 0.35    -- matches the shader defaults; see hit_flash.gdshader
local SPIN = 0.3

local active = {}      -- entity_name -> { img, shader, plain, dir, t }
local any_active = false

local function apply(entity_name, fx, amount)
    set_shader({
        parent_name = entity_name,
        image_name = fx.img,
        shader_name = fx.shader,
        hit = amount,
        hit_dir = fx.dir
    })
end

-- Guarded because the killing blow destroys its victim while the flash is still
-- playing. entity_exists is the silent check - get_value and set_shader would
-- both log an error for every one of those frames.
local function still_there(entity_name, fx)
    return entity_exists(fx.img, entity_name)
end

function play_hit(entity_name, image_name, base_shader, dir, strength)
    if entity_name == nil or image_name == nil then
        return
    end

    local fx = active[entity_name]
    if fx == nil then
        fx = {}
        active[entity_name] = fx
    end

    fx.img = image_name
    fx.plain = (base_shader == nil or base_shader == "")
    fx.shader = fx.plain and "hit_flash" or base_shader
    -- Numbers cross the Lua<->GDScript boundary as floats, so compare, do not
    -- test for equality with 1 or -1.
    fx.dir = (dir ~= nil and dir < 0) and -1.0 or 1.0
    fx.t = FX_SECONDS
    any_active = true

    -- Show the first frame now: a hit that lands and kills in the same frame
    -- still gets its flash. The amplitudes only travel on THIS call - shader
    -- uniforms stay on the material, so every following frame is one float.
    if still_there(entity_name, fx) then
        local amount = (strength ~= nil and strength > 0) and strength or 1.0
        set_shader({
            parent_name = entity_name,
            image_name = fx.img,
            shader_name = fx.shader,
            hit = 1.0,
            hit_dir = fx.dir,
            hit_squash = SQUASH * amount,
            hit_spin = SPIN * amount
        })
    end
end

-- Put the sprite back exactly as it was. A plain sprite loses the material
-- again; an outlined one keeps its shader (and its outline_color, which stays
-- on the material) and is only told the hit is over.
local function finish(entity_name, fx)
    if not still_there(entity_name, fx) then
        return
    end
    if fx.plain then
        set_shader({ parent_name = entity_name, image_name = fx.img, shader_name = "" })
    else
        apply(entity_name, fx, 0.0)
    end
end

function _process(delta, inputs)
    if not any_active then
        return
    end

    local still_running = false
    for entity_name, fx in pairs(active) do
        fx.t = fx.t - delta
        if fx.t <= 0 then
            finish(entity_name, fx)
            active[entity_name] = nil
        elseif still_there(entity_name, fx) then
            apply(entity_name, fx, fx.t / FX_SECONDS)
            still_running = true
        else
            active[entity_name] = nil -- destroyed mid-flash
        end
    end
    any_active = still_running
end

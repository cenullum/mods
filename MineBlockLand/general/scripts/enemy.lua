lock_rotation = true
linear_damp = 0

-- =============================================================================
-- MineBlockLand - one data-driven enemy script for every hostile NPC.
-- The spawner (-gm) passes everything as spawn config: image, size, hp, dmg,
-- speed, windup, cooldown, reach, ranged, shoot_cd, tint, is_night_npc,
-- dungeon_id. Night zombies burn at dawn; dungeon guards hold their room.
--
-- NPCs collide with TILES ONLY (mask {1}); they walk straight through players
-- and each other. All damage flows through -combat's telegraphed zones.
-- =============================================================================

add_tag(name, "npc")
if is_night_npc then
    add_tag(name, "night_npc")
end

local RETARGET_SECONDS = 2.5
local ATTACK_CHECK_SECONDS = 0.3
local GUARD_AGGRO_RANGE = 200   -- dungeon guards only wake up close-by
local RANGED_MAX_RANGE = 240
local BULLET_SPEED = 70
local BULLET_LIFE = 4.0

local attack_ready = true
local target = ""

set_value("", name, "speed", speed)

set_image({ parent_name = name, name = "body", image_path = image,
    scale = Vector2(size, size), modulate = tint, z_index = 2 })
set_collision({ parent_name = name, name = "col", shape = "circle", size = size / 2,
    collision_layer = { 3 }, collision_mask = { 1 } })
-- Read by -combat's melee hit test: without this, a swing that visually
-- clipped the zombie's body but missed its exact centre point counted as a
-- miss (the check only knew the victim's position, not how big it is).
set_value("", name, "hit_radius", size / 2)

-- =============================================================================
-- Host AI.
-- =============================================================================

function retarget()
    if not IS_HOST then return end
    local nearest = get_nearest_entity_by_tag(name, "alive")
    if nearest and nearest.name then
        if dungeon_id ~= "" and nearest.distance > GUARD_AGGRO_RANGE then
            target = ""
        else
            target = nearest.name
        end
    else
        target = ""
    end
    go_to_target(name, target, false)
end

function check_attack()
    if not IS_HOST or not attack_ready or target == "" then return end
    local my_pos = get_value("", name, "position")
    local target_pos = get_value("", target, "position")
    if not my_pos or not target_pos then return end
    local dist = distance_to(my_pos, target_pos)

    if dist <= reach then
        attack_ready = false
        local angle = math.atan(target_pos.y - my_pos.y, target_pos.x - my_pos.x)
        run_function("-combat", "start_telegraph", { {
            x = my_pos.x + math.cos(angle) * (reach * 0.6),
            y = my_pos.y + math.sin(angle) * (reach * 0.6),
            shape = "circle", r = 10 + size / 2, windup = windup,
            dmg = dmg, targets = "players", attacker = name } })
        start_timer({ timer_id = "cd" .. name, entity_name = name,
            function_name = "reset_attack", wait_time = cooldown, duration = cooldown })
    elseif ranged and dist <= RANGED_MAX_RANGE then
        attack_ready = false
        local angle = math.atan(target_pos.y - my_pos.y, target_pos.x - my_pos.x)
        spawn_entity_host({ t = "bullet", p = my_pos, r = angle,
            dmg = dmg, speed = BULLET_SPEED, life = BULLET_LIFE })
        start_timer({ timer_id = "cd" .. name, entity_name = name,
            function_name = "reset_attack", wait_time = shoot_cd, duration = shoot_cd })
    end
end

function reset_attack()
    attack_ready = true
end

if IS_HOST then
    retarget()
    start_timer({ timer_id = "rt" .. name, entity_name = name,
        function_name = "retarget", wait_time = RETARGET_SECONDS })
    start_timer({ timer_id = "atk" .. name, entity_name = name,
        function_name = "check_attack", wait_time = ATTACK_CHECK_SECONDS })
end

-- =============================================================================
-- Damage / death (host authority; -combat and arrows call this).
-- =============================================================================

function npc_take_damage(dmg_in, attacker, kb, angle)
    if not IS_HOST then return end
    hp = hp - dmg_in
    local my_pos = get_value("", name, "position")
    if my_pos then
        run_function("-combat", "show_damage", { my_pos.x, my_pos.y, dmg_in, "npc" })
    end
    if attacker and has_tag(attacker, "user") then
        run_function("-gm", "add_stat", { attacker, "dmg_dealt", dmg_in })
    end
    if kb and kb > 0 and angle then
        add_linear_velocity(name, Vector2(math.cos(angle) * kb, math.sin(angle) * kb))
    end
    if hp <= 0 then
        if my_pos then
            for _, drop in ipairs(run_function("-items", "get_zombie_drops")) do
                if math.random() < drop.chance then
                    spawn_entity_host({ t = "ground_item", p = my_pos,
                        item_id = drop.id, count = math.random(drop.min, drop.max) })
                end
            end
        end
        run_function("-gm", "on_enemy_killed", { { killer = attacker, dungeon_id = dungeon_id } })
        destroy("", name)
    end
end

-- Dawn: the sun destroys every night spawn (dungeon guards are exempt).
function host_burn()
    if not IS_HOST then return end
    if is_night_npc then
        destroy("", name)
    end
end

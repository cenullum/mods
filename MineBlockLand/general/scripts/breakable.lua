network_mode = 1
lock_rotation = true

-- =============================================================================
-- MineBlockLand - a smashable prop (the clay jugs in the dungeon corners).
-- Spawn config: image, size, dungeon_id.
--
-- It is tagged "npc" purely so it goes through the SAME damage path as
-- everything else: melee telegraphs with targets = "all"/"npcs" and arrow
-- hitscans both find it through npc_take_damage, and a world reset wipes it
-- with destroy_entities_by_tag("npc"). It is never tagged "alive", so no enemy
-- ever picks a jug as its target.
--
-- Its collision sits on layer 3 with an EMPTY mask: raycast arrows still hit
-- it, but it collides with nothing itself, so nobody can shove it around.
-- =============================================================================

add_tag(name, "npc")
add_tag(name, "breakable")

local K_STONE = 9 -- chip particle flavour reused from -gm's gather effect

local jug = run_function("-items", "get_jug_loot")
hp = jug.hp
local broken = false

set_image({ parent_name = name, name = "body", image_path = image,
    scale = Vector2(size, size), z_index = 2 })
set_collision({ parent_name = name, name = "col", shape = "circle", size = size / 2,
    collision_layer = { 3 }, collision_mask = {} })
set_value("", name, "hit_radius", size / 2)

-- One weighted pick out of the loot table, or nothing at all.
local function roll_loot()
    if math.random() < jug.empty_chance then return nil end
    local total = 0
    for _, entry in ipairs(jug.loot) do total = total + entry.weight end
    if total <= 0 then return nil end
    local pick = math.random() * total
    for _, entry in ipairs(jug.loot) do
        pick = pick - entry.weight
        if pick <= 0 then
            return { id = entry.id, count = math.random(entry.min, entry.max) }
        end
    end
    return nil
end

-- Same signature every damageable NPC in the mod exposes.
function npc_take_damage(dmg_in, attacker, kb, angle)
    if not IS_HOST or broken then return end
    hp = hp - dmg_in
    local my_pos = get_value("", name, "position")
    if my_pos then
        run_function("-combat", "show_damage", { my_pos.x, my_pos.y, dmg_in, "npc" })
    end
    if hp > 0 then return end
    broken = true
    if my_pos then
        local tile = local_to_map(my_pos)
        run_network_function("-gm", "gather_fx_ALL",
            { math.floor(tile.x), math.floor(tile.y), K_STONE })
        local loot = roll_loot()
        if loot then
            spawn_entity_host({ t = "ground_item", p = my_pos,
                item_id = loot.id, count = loot.count })
        end
    end
    -- A smashed jug never comes back, even if the player leaves and returns.
    run_function("-gm", "mark_dungeon_done", { dungeon_id })
    destroy("", name)
end

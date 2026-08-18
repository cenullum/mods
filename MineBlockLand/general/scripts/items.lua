singleton_name = "items"
network_mode = 0

-- =============================================================================
-- MineBlockLand - single data-driven item registry.
-- EVERY item, recipe and loot table lives here; gameplay code never hardcodes
-- item names (it only reads these tables through the accessors below).
--
-- Item fields:
--   name         display name
--   desc         short in-game description of what it actually does
--   image        icon path under general/images (no .png)
--   heal         eating restores this much HP (food only)
--   tool         "pickaxe" | "shovel" | "sword" | "bow" (equippable tools only)
--   power        gather strength: higher chops/mines faster and finds rarer ore
--   damage       melee/arrow damage
--   stamina      stamina cost per use (worse tools cost MORE, per design)
--   cooldown     seconds between uses
--   shape        melee telegraph shape: {kind="rect",w,h,ahead} or {kind="circle",r,ahead}
--   place_kind   holding this + Interact places it as a world tile of this kind
--                (see worldgen.lua's K_* constants; host-validated in game_manager.lua)
--   use_kind     holding this + Interact runs a special action instead of the
--                plant/harvest/place/eat chain: "potion" | "bomb" | "portal" |
--                "rod" | "saddle" | "pet" | "grapple" | "upgrade".
--                user.lua's interact_HOST branches on this ONE field, so a new
--                gadget is a table entry here plus one handler there.
--   wearable     worn on the body from the inventory panel's own Equip/Unequip
--                button (separate slot from the held tool, so a hat never
--                bumps a pickaxe out of your hand). user.lua's set_worn_visual
--                draws it at that item's fixed body offset; any gameplay
--                effect must check get_worn(), never "do I merely own one".
-- =============================================================================

ITEMS = {
    -- materials -------------------------------------------------------------
    wood = { name = "{item_wood}", image = "items/15x15_wood", place_kind = 15, -- K_WOOD_BLOCK
        desc = "{item_wood_desc}" },
    stone = { name = "{item_stone}", image = "items/15x15_stone", place_kind = 9, -- K_STONE
        desc = "{item_stone_desc}" },
    coal = { name = "{item_coal}", image = "items/15x15_coal",
        desc = "{item_coal_desc}" },
    iron = { name = "{item_iron}", image = "items/15x15_iron",
        desc = "{item_iron_desc}" },
    crystal = { name = "{item_crystal}", image = "items/15x15_cristal",
        desc = "{item_crystal_desc}" },
    diamond = { name = "{item_diamond}", image = "items/15x15_diamond",
        desc = "{item_diamond_desc}" },
    wheat_seed = { name = "{item_wheat_seed}", image = "items/15x15_wheat_seed",
        desc = "{item_wheat_seed_desc}" },
    tree_seed = { name = "{item_tree_seed}", image = "items/15x15_tree_seed",
        desc = "{item_tree_seed_desc}" },
    arrow = { name = "{item_arrow}", image = "items/15x15_arrow",
        desc = "{item_arrow_desc}" },
    -- Not a backpack item: walking over a chest opens it on the spot.
    chest = { name = "{item_chest}", image = "items/10x10_giftbox",
        desc = "{item_chest_desc}" },

    -- monster & animal parts ---------------------------------------------------
    -- Each night creature now leaves its OWN material behind (see ENEMY_DROPS),
    -- so which enemy you choose to fight decides what you can craft next.
    rotten_flesh = { name = "{item_rotten_flesh}", image = "items/15x15_rotten_flesh",
        desc = "{item_rotten_flesh_desc}" },
    ectoplasm = { name = "{item_ectoplasm}", image = "items/15x15_ectoplasm",
        desc = "{item_ectoplasm_desc}" },
    witch_essence = { name = "{item_witch_essence}", image = "items/15x15_witch_essence",
        desc = "{item_witch_essence_desc}" },
    thick_hide = { name = "{item_thick_hide}", image = "items/15x15_thick_hide",
        desc = "{item_thick_hide_desc}" },
    leather_strap = { name = "{item_leather_strap}", image = "items/15x15_leather_strap",
        desc = "{item_leather_strap_desc}" },
    heart_shard = { name = "{item_heart_shard}", image = "items/15x15_heart_shard",
        desc = "{item_heart_shard_desc}" },
    mushroom = { name = "{item_mushroom}", image = "items/10x10_mushroom", heal = 10,
        desc = "{item_mushroom_desc}" },
    -- Pure trophy: no recipe uses it, nothing consumes it. It exists so that
    -- one witch in fifty leaves behind a story instead of a resource.
    witch_hat = { name = "{item_witch_hat}", image = "items/15x15_witch_hat", wearable = true,
        desc = "{item_witch_hat_desc}" },
    -- The other trophy: every fishing game needs one thing that is not a fish.
    sock = { name = "{item_sock}", image = "items/15x15_sock", wearable = true,
        desc = "{item_sock_desc}" },
    pet_charm = { name = "{item_pet_charm}", image = "items/15x15_pet_charm", use_kind = "pet",
        desc = "{item_pet_charm_desc}" },

    -- food (equip, then Interact to eat) --------------------------------------
    apple = { name = "{item_apple}", image = "items/15x15_apple", heal = 25,
        desc = "{item_apple_desc}" },
    potato = { name = "{item_potato}", image = "items/10x10_potato", heal = 20,
        desc = "{item_potato_desc}" },
    watermelon = { name = "{item_watermelon}", image = "items/15x15_watermelon", heal = 50,
        desc = "{item_watermelon_desc}" },
    hamburger = { name = "{item_hamburger}", image = "items/15x15_hamburger", heal = 999,
        desc = "{item_hamburger_desc}" },
    pizza = { name = "{item_pizza}", image = "items/5x5_pizza", heal = 60,
        desc = "{item_pizza_desc}" },
    fish = { name = "{item_fish}", image = "items/15x15_fish", heal = 35,
        desc = "{item_fish_desc}" },
    octopus = { name = "{item_octopus}", image = "items/15x15_octopus", heal = 55,
        desc = "{item_octopus_desc}" },

    -- tools & weapons ---------------------------------------------------------
    -- Three tool families, four material tiers each. PICKAXES gather (they chop
    -- trees AND mine rock at their power); SHOVELS till grass into farmland;
    -- SWORDS are pure weapons. Tool textures live at the images root (no
    -- "items/" prefix).

    -- Pickaxes (gather trees + rock; better tiers find rarer ore) ------------
    wooden_pickaxe = { name = "{item_wooden_pickaxe}", image = "wooden_pickaxe",
        tool = "pickaxe", power = 1, damage = 6, stamina = 12, cooldown = 0.75,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "{item_wooden_pickaxe_desc}" },
    stone_pickaxe = { name = "{item_stone_pickaxe}", image = "stone_pickaxe",
        tool = "pickaxe", power = 2, damage = 8, stamina = 10, cooldown = 0.65,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "{item_stone_pickaxe_desc}" },
    iron_pickaxe = { name = "{item_iron_pickaxe}", image = "iron_pickaxe",
        tool = "pickaxe", power = 4, damage = 12, stamina = 8, cooldown = 0.5,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "{item_iron_pickaxe_desc}" },
    diamond_pickaxe = { name = "{item_diamond_pickaxe}", image = "diamond_pickaxe",
        tool = "pickaxe", power = 6, damage = 16, stamina = 6, cooldown = 0.45,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "{item_diamond_pickaxe_desc}" },

    -- Shovels (strike grass to till it into farmland) -----------------------
    wooden_shovel = { name = "{item_wooden_shovel}", image = "wooden_shovel",
        tool = "shovel", power = 1, damage = 6, stamina = 6, cooldown = 0.5,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "{item_wooden_shovel_desc}" },
    stone_shovel = { name = "{item_stone_shovel}", image = "stone_shovel",
        tool = "shovel", power = 1, damage = 8, stamina = 6, cooldown = 0.5,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "{item_stone_shovel_desc}" },
    iron_shovel = { name = "{item_iron_shovel}", image = "iron_shovel",
        tool = "shovel", power = 1, damage = 11, stamina = 5, cooldown = 0.45,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "{item_iron_shovel_desc}" },
    diamond_shovel = { name = "{item_diamond_shovel}", image = "diamond_shovel",
        tool = "shovel", power = 1, damage = 14, stamina = 5, cooldown = 0.4,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "{item_diamond_shovel_desc}" },

    -- Swords (pure combat) --------------------------------------------------
    wooden_sword = { name = "{item_wooden_sword}", image = "wooden_sword",
        tool = "sword", damage = 12, stamina = 8, cooldown = 0.5,
        shape = { kind = "rect", w = 26, h = 18, ahead = 16 },
        desc = "{item_wooden_sword_desc}" },
    stone_sword = { name = "{item_stone_sword}", image = "stone_sword",
        tool = "sword", damage = 18, stamina = 12, cooldown = 0.6,
        shape = { kind = "rect", w = 28, h = 20, ahead = 16 },
        desc = "{item_stone_sword_desc}" },
    iron_sword = { name = "{item_iron_sword}", image = "iron_sword",
        tool = "sword", damage = 26, stamina = 8, cooldown = 0.45,
        shape = { kind = "rect", w = 30, h = 20, ahead = 17 },
        desc = "{item_iron_sword_desc}" },
    diamond_sword = { name = "{item_diamond_sword}", image = "diamond_sword",
        tool = "sword", damage = 34, stamina = 6, cooldown = 0.4,
        shape = { kind = "rect", w = 34, h = 22, ahead = 18 },
        desc = "{item_diamond_sword_desc}" },

    -- Special --------------------------------------------------------------
    bow = { name = "{item_bow}", image = "items/15x15_bow",
        tool = "bow", damage = 22, stamina = 12, cooldown = 0.8,
        desc = "{item_bow_desc}" },

    -- gadgets (equip, then Interact to use - see use_kind above) ---------------
    bomb = { name = "{item_bomb}", image = "items/10x10_bomb", use_kind = "bomb",
        blast_damage = 45, blast_radius = 34,
        desc = "{item_bomb_desc}" },
    speed_potion = { name = "{item_speed_potion}", image = "items/15x15_speed_potion",
        use_kind = "potion", potion = "speed",
        desc = "{item_speed_potion_desc}" },
    strength_potion = { name = "{item_strength_potion}", image = "items/15x15_strength_potion",
        use_kind = "potion", potion = "strength",
        desc = "{item_strength_potion_desc}" },
    regen_potion = { name = "{item_regen_potion}", image = "items/15x15_regen_potion",
        use_kind = "potion", potion = "regen",
        desc = "{item_regen_potion_desc}" },
    -- The only permanent upgrade in the mod, and the reason to hunt brutes.
    heart_container = { name = "{item_heart_container}", image = "items/15x15_heart",
        use_kind = "upgrade",
        desc = "{item_heart_container_desc}" },
    grapple_hook = { name = "{item_grapple_hook}", image = "items/15x15_grapple_hook",
        use_kind = "grapple", stamina = 15, cooldown = 1.2,
        desc = "{item_grapple_hook_desc}" },
    swift_boots = { name = "{item_swift_boots}", image = "items/15x15_swift_boots", wearable = true,
        desc = "{item_swift_boots_desc}" },
    portal_stone = { name = "{item_portal_stone}", image = "items/15x15_portal_stone",
        use_kind = "portal",
        desc = "{item_portal_stone_desc}" },
    -- Never consumed: a saddle is a tool you keep and re-use on the next animal.
    saddle = { name = "{item_saddle}", image = "items/15x15_saddle", use_kind = "saddle",
        desc = "{item_saddle_desc}" },
    fishing_rod = { name = "{item_fishing_rod}", image = "items/15x15_fishing_rod",
        use_kind = "rod",
        desc = "{item_fishing_rod_desc}" },
}

-- Bare hands: used whenever nothing is equipped. Same fields as a tool item.
FISTS = {
    name = "{item_fists}", tool = "sword", power = 1, damage = 5, stamina = 4, cooldown = 0.5,
    shape = { kind = "circle", r = 11, ahead = 9 },
    desc = "{item_fists_desc}",
}

-- Ordered craft list (Terraria style: everything is always listed; the button
-- colour tells you how close you are to affording it).
RECIPES = {
    -- Wooden tier (wood only).
    { id = "wooden_pickaxe",  count = 1, needs = { wood = 4 } },
    { id = "wooden_shovel",   count = 1, needs = { wood = 3 } },
    { id = "wooden_sword",    count = 1, needs = { wood = 6 } },
    -- Stone tier.
    { id = "stone_pickaxe",   count = 1, needs = { wood = 3, stone = 4 } },
    { id = "stone_shovel",    count = 1, needs = { wood = 2, stone = 3 } },
    { id = "stone_sword",     count = 1, needs = { wood = 2, stone = 5 } },
    -- Iron tier.
    { id = "iron_pickaxe",    count = 1, needs = { wood = 2, iron = 3 } },
    { id = "iron_shovel",     count = 1, needs = { wood = 2, iron = 2 } },
    { id = "iron_sword",      count = 1, needs = { wood = 2, iron = 4 } },
    -- Ranged.
    { id = "bow",             count = 1, needs = { wood = 7 } },
    { id = "arrow",           count = 4, needs = { wood = 1, stone = 1 } },
    -- Top tier.
    { id = "diamond_pickaxe", count = 1, needs = { wood = 2, coal = 2, diamond = 2 } },
    { id = "diamond_shovel",  count = 1, needs = { wood = 2, coal = 1, diamond = 2 } },
    { id = "diamond_sword",   count = 1, needs = { wood = 2, coal = 2, diamond = 3 } },
    { id = "hamburger",       count = 1, needs = { potato = 2, apple = 1, watermelon = 1 } },
    -- Monster-part tier: unlocked by what you kill at night, not by what you mine.
    { id = "bomb",            count = 2, needs = { coal = 2, stone = 3, rotten_flesh = 1 } },
    { id = "speed_potion",    count = 1, needs = { witch_essence = 1, ectoplasm = 1, mushroom = 1 } },
    { id = "strength_potion", count = 1, needs = { witch_essence = 1, coal = 2 } },
    { id = "regen_potion",    count = 1, needs = { witch_essence = 1, watermelon = 1, mushroom = 1 } },
    { id = "heart_container", count = 1, needs = { heart_shard = 4, diamond = 1 } },
    { id = "grapple_hook",    count = 1, needs = { wood = 3, stone = 4, ectoplasm = 2 } },
    { id = "swift_boots",     count = 1, needs = { thick_hide = 3, ectoplasm = 1 } },
    { id = "portal_stone",    count = 1, needs = { crystal = 2, stone = 4, ectoplasm = 1 } },
    -- A guaranteed route to straps: hunting one is luck, cutting one is not.
    { id = "leather_strap",   count = 2, needs = { thick_hide = 1 } },
    { id = "saddle",          count = 1, needs = { thick_hide = 4, leather_strap = 2, wood = 2 } },
    { id = "fishing_rod",     count = 1, needs = { wood = 5, leather_strap = 1 } },
}

-- Gather rules ---------------------------------------------------------------
TREE_HP = 4    -- chop damage: axes deal their power, anything else deals 1
STONE_HP = 6   -- mine damage: pickaxes deal their power, anything else 0
SAPLING_HP = 2 -- any tool/fists deal their power; breaking one drops nothing
CACTUS_HP = 3  -- desert flora chops exactly like a tree, just softer
PALM_HP = 4
WOOD_BLOCK_HP = 3 -- player-placed wood block: chops like a tree, just softer

TREE_DROPS = {
    { id = "wood", min = 2, max = 3, chance = 1.0 },
    { id = "apple", min = 1, max = 1, chance = 0.40 },
    { id = "tree_seed", min = 1, max = 2, chance = 0.35 },
}

-- A cactus is mostly water, so it pays in food rather than timber.
CACTUS_DROPS = {
    { id = "wood", min = 1, max = 1, chance = 0.60 },
    { id = "watermelon", min = 1, max = 1, chance = 0.25 },
    { id = "wheat_seed", min = 1, max = 1, chance = 0.20 },
}

PALM_DROPS = {
    { id = "wood", min = 2, max = 3, chance = 1.0 },
    { id = "apple", min = 1, max = 1, chance = 0.25 },
    { id = "tree_seed", min = 1, max = 1, chance = 0.30 },
}

-- A placed wood block simply gives its wood back when broken.
WOOD_BLOCK_DROPS = {
    { id = "wood", min = 1, max = 1, chance = 1.0 },
}

-- Stone drops: 'per_power' chances scale with the pickaxe's power, so better
-- picks genuinely find rarer minerals more often.
STONE_DROPS = {
    { id = "stone", min = 1, max = 2, chance = 1.0 },
    { id = "coal", min = 1, max = 2, chance = 0.30 },
    { id = "iron", min = 1, max = 2, chance = 0.16, per_power = 0.02 },
    { id = "crystal", min = 1, max = 1, chance = 0.02, per_power = 0.015 },
    { id = "diamond", min = 1, max = 1, chance = 0.005, per_power = 0.008 },
    { id = "chest", min = 1, max = 1, chance = 0.04 },
}

-- Harvesting a grown crop.
HARVEST_DROPS = {
    { id = "watermelon", min = 1, max = 1, chance = 1.0 },
    { id = "wheat_seed", min = 0, max = 2, chance = 1.0 },
}

-- What tumbles out of a chest (weighted picks; a chest rolls 2-3 of these).
CHEST_LOOT = {
    { id = "potato", min = 1, max = 3, weight = 30 },
    { id = "apple", min = 1, max = 2, weight = 20 },
    { id = "arrow", min = 3, max = 8, weight = 15 },
    { id = "coal", min = 1, max = 3, weight = 12 },
    { id = "iron", min = 1, max = 3, weight = 11 },
    { id = "hamburger", min = 1, max = 1, weight = 8 },
    { id = "pizza", min = 1, max = 1, weight = 12 },
    { id = "crystal", min = 1, max = 2, weight = 10 },
    { id = "diamond", min = 1, max = 1, weight = 5 },
}
CHEST_ROLLS_MIN = 2
CHEST_ROLLS_MAX = 3

-- Dungeon jugs: cheap, plentiful and often empty. JUG_EMPTY_CHANCE is rolled
-- first; only the rest of the time is a single weighted item picked.
JUG_HP = 3
JUG_EMPTY_CHANCE = 0.45
JUG_LOOT = {
    { id = "potato", min = 1, max = 2, weight = 26 },
    { id = "apple", min = 1, max = 1, weight = 20 },
    { id = "arrow", min = 2, max = 5, weight = 18 },
    { id = "coal", min = 1, max = 2, weight = 14 },
    { id = "iron", min = 1, max = 2, weight = 13 },
    { id = "stone", min = 1, max = 3, weight = 12 },
    { id = "pizza", min = 1, max = 1, weight = 6 },
    { id = "crystal", min = 1, max = 1, weight = 3 },
    { id = "diamond", min = 1, max = 1, weight = 1 },
}

-- What a slain animal leaves behind (see wildlife.lua for who drops what).
-- Kept here so every loot table in the mod still lives in one file.
--
-- EVERY size class drops leather_strap: it used to come off "large" animals
-- only (rhino/elephant/unicorn, 12%), which are rare, dangerous and mostly
-- inland - so the saddle and the fishing rod both hung off a material nobody
-- could tell where to look for. Now any hunt pays into it, with the chance
-- scaling by how much animal there is to cut up.
WILDLIFE_DROPS = {
    small = { { id = "apple", min = 1, max = 1, chance = 0.18 },
        { id = "leather_strap", min = 1, max = 1, chance = 0.10 },
        { id = "pet_charm", min = 1, max = 1, chance = 0.015 } },
    medium = { { id = "potato", min = 1, max = 2, chance = 0.30 },
        { id = "apple", min = 1, max = 1, chance = 0.20 },
        { id = "thick_hide", min = 1, max = 1, chance = 0.25 },
        { id = "leather_strap", min = 1, max = 1, chance = 0.22 } },
    large = { { id = "potato", min = 1, max = 3, chance = 0.55 },
        { id = "watermelon", min = 1, max = 1, chance = 0.25 },
        { id = "thick_hide", min = 1, max = 2, chance = 0.45 },
        { id = "leather_strap", min = 1, max = 2, chance = 0.40 },
        { id = "hamburger", min = 1, max = 1, chance = 0.05 } },
}

-- What the sea gives up. Weighted like the chest, but a single pick per catch,
-- and one entry is deliberately worthless - a fishing game with no junk in it
-- is just a slower inventory button.
FISH_LOOT = {
    { id = "fish", min = 1, max = 2, weight = 40 },
    { id = "octopus", min = 1, max = 1, weight = 14 },
    { id = "sock", min = 1, max = 1, weight = 12 },
    { id = "crystal", min = 1, max = 1, weight = 8 },
    { id = "pizza", min = 1, max = 1, weight = 6 },
    { id = "chest", min = 1, max = 1, weight = 4 },
}

-- One weighted pick out of FISH_LOOT: { id = ..., count = ... }.
function roll_fish()
    local total = 0
    for _, entry in ipairs(FISH_LOOT) do total = total + entry.weight end
    local pick = math.random() * total
    for _, entry in ipairs(FISH_LOOT) do
        pick = pick - entry.weight
        if pick <= 0 then
            return { id = entry.id, count = math.random(entry.min, entry.max) }
        end
    end
    return { id = FISH_LOOT[1].id, count = 1 }
end

-- Zombies occasionally carry a snack. Kept as-is for anything still asking for
-- the zombie table by name; ENEMY_DROPS below is what the spawner actually uses.
ZOMBIE_DROPS = {
    { id = "apple", min = 1, max = 1, chance = 0.15 },
    { id = "potato", min = 1, max = 1, chance = 0.10 },
}

-- What each night creature leaves behind. Every hostile used to roll the zombie
-- table regardless of what it actually was, so killing a witch paid exactly the
-- same as killing a zombie and the rare spawns had no reward attached. Now the
-- rarer the enemy, the more interesting the material - which is the whole point
-- of the witch showing up more often.
ENEMY_DROPS = {
    zombie = {
        { id = "rotten_flesh", min = 1, max = 2, chance = 0.55 },
        { id = "apple", min = 1, max = 1, chance = 0.15 },
        { id = "potato", min = 1, max = 1, chance = 0.10 },
    },
    ghost = {
        { id = "ectoplasm", min = 1, max = 1, chance = 0.60 },
        { id = "crystal", min = 1, max = 1, chance = 0.08 },
    },
    witch = {
        { id = "witch_essence", min = 1, max = 2, chance = 0.70 },
        { id = "mushroom", min = 1, max = 2, chance = 0.35 },
        { id = "witch_hat", min = 1, max = 1, chance = 0.02 },
    },
    brute = {
        { id = "thick_hide", min = 1, max = 2, chance = 0.75 },
        { id = "rotten_flesh", min = 2, max = 3, chance = 0.50 },
        { id = "heart_shard", min = 1, max = 1, chance = 0.10 },
    },
}

-- =============================================================================
-- Accessors (other entities call these with run_function("-items", ...)).
-- =============================================================================

function get_item(item_id)
    return ITEMS[item_id]
end

-- Every item id there is, sorted (pairs() has no order and this feeds the
-- /testitems cheat, which must hand out the same bag every time).
function get_all_item_ids()
    local ids = {}
    for item_id in pairs(ITEMS) do table.insert(ids, item_id) end
    table.sort(ids)
    return ids
end

function get_fists()
    return FISTS
end

-- The definition used when swinging/using: the held item's, or bare fists.
function get_use_def(item_id)
    local item = ITEMS[item_id]
    if item and item.tool then
        return item
    end
    return FISTS
end

function get_recipes()
    return RECIPES
end

function get_recipe(recipe_index)
    return RECIPES[recipe_index]
end

function is_equippable(item_id)
    local item = ITEMS[item_id]
    if not item then return false end
    return (item.tool ~= nil) or (item.heal ~= nil) or (item.use_kind ~= nil)
        or (item_id == "wheat_seed") or (item_id == "tree_seed") or (item.place_kind ~= nil)
end

-- A worn accessory (see the "wearable" field note above ITEMS): its own slot
-- and its own inventory-panel button, never the held-in-hand slot above.
function is_wearable(item_id)
    local item = ITEMS[item_id]
    return item ~= nil and item.wearable == true
end

-- What Interact should do with the held item, or nil for "nothing special".
function get_use_kind(item_id)
    local item = ITEMS[item_id]
    return item and item.use_kind or nil
end

-- Tile kind this item becomes when placed with Interact, or nil if it can't be.
function get_place_kind(item_id)
    local item = ITEMS[item_id]
    return item and item.place_kind or nil
end

function get_tree_drops() return TREE_DROPS end
function get_stone_drops() return STONE_DROPS end
function get_wood_block_drops() return WOOD_BLOCK_DROPS end
function get_harvest_drops() return HARVEST_DROPS end
function get_zombie_drops() return ZOMBIE_DROPS end

-- Loot for one hostile archetype. Anything spawned without an etype (older
-- saves, dungeon guards) falls back to the zombie table.
function get_enemy_drops(etype)
    return ENEMY_DROPS[etype] or ENEMY_DROPS.zombie
end
function get_cactus_drops() return CACTUS_DROPS end
function get_palm_drops() return PALM_DROPS end

function get_wildlife_drops(size_class)
    return WILDLIFE_DROPS[size_class] or {}
end

function get_chest_loot()
    return { loot = CHEST_LOOT, rolls_min = CHEST_ROLLS_MIN, rolls_max = CHEST_ROLLS_MAX }
end

function get_jug_loot()
    return { loot = JUG_LOOT, empty_chance = JUG_EMPTY_CHANCE, hp = JUG_HP }
end

function get_tree_hp() return TREE_HP end
function get_stone_hp() return STONE_HP end
function get_wood_block_hp() return WOOD_BLOCK_HP end
function get_sapling_hp() return SAPLING_HP end
function get_cactus_hp() return CACTUS_HP end
function get_palm_hp() return PALM_HP end

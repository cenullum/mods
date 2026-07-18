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
-- =============================================================================

ITEMS = {
    -- materials -------------------------------------------------------------
    wood = { name = "Wood", image = "items/15x15_wood", place_kind = 3, -- K_TREE
        desc = "Sturdy timber from trees. The base of most recipes. Right-click on bare ground to place it as a block." },
    stone = { name = "Stone", image = "items/15x15_stone", place_kind = 9, -- K_STONE
        desc = "Chipped rock from boulders. Combine with wood to craft tools. Right-click on bare ground to place it as a block." },
    coal = { name = "Coal", image = "items/15x15_coal",
        desc = "Black mineral fuel. Needed to forge crystal and diamond gear." },
    crystal = { name = "Crystal", image = "items/15x15_cristal",
        desc = "A glowing shard from deep rock. Crafts a fast, light blade." },
    diamond = { name = "Diamond", image = "items/15x15_diamond",
        desc = "The hardest gem there is. Crafts the finest tools." },
    seed = { name = "Seed", image = "items/15x15_seed",
        desc = "Interact with tilled farmland to plant (make a plot with a shovel). Grows into a melon crop." },
    arrow = { name = "Arrow", image = "items/15x15_arrow",
        desc = "Ammunition for the bow. Crafted from wood and stone." },
    -- Not a backpack item: walking over a chest opens it on the spot.
    chest = { name = "Chest", image = "items/10x10_giftbox",
        desc = "Sometimes hides inside broken rock. Walk over it to open." },

    -- food (equip, then Interact to eat) --------------------------------------
    apple = { name = "Apple", image = "items/15x15_apple", heal = 25,
        desc = "Crisp fruit that falls from chopped trees. Eat: +25 HP." },
    potato = { name = "Potato", image = "items/10x10_potato", heal = 20,
        desc = "Humble but filling chest loot. Eat: +20 HP." },
    watermelon = { name = "Watermelon", image = "items/15x15_watermelon", heal = 50,
        desc = "Juicy crop harvested from grown farmland. Eat: +50 HP." },
    hamburger = { name = "Hamburger", image = "items/15x15_hamburger", heal = 999,
        desc = "A feast in your hands. Eat: fully restores HP." },

    -- tools & weapons ---------------------------------------------------------
    -- Three tool families, four material tiers each. PICKAXES gather (they chop
    -- trees AND mine rock at their power); SHOVELS till grass into farmland;
    -- SWORDS are pure weapons. Tool textures live at the images root (no
    -- "items/" prefix). Iron is "smelted" in recipes from stone + coal, so no
    -- separate iron-ore item/icon is needed.

    -- Pickaxes (gather trees + rock; better tiers find rarer ore) ------------
    wooden_pickaxe = { name = "Wooden Pickaxe", image = "wooden_pickaxe",
        tool = "pickaxe", power = 1, damage = 6, stamina = 12, cooldown = 0.75,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "Chops trees and cracks rock, slowly. Your first real tool." },
    stone_pickaxe = { name = "Stone Pickaxe", image = "stone_pickaxe",
        tool = "pickaxe", power = 2, damage = 8, stamina = 10, cooldown = 0.65,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "Faster on wood and stone than a wooden pick." },
    iron_pickaxe = { name = "Iron Pickaxe", image = "iron_pickaxe",
        tool = "pickaxe", power = 4, damage = 12, stamina = 8, cooldown = 0.5,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "Bites through trees and rock, and finds gems more often." },
    diamond_pickaxe = { name = "Diamond Pickaxe", image = "diamond_pickaxe",
        tool = "pickaxe", power = 6, damage = 16, stamina = 6, cooldown = 0.45,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "Shatters rock in one blow, barely tiring you. Finds rare gems far more often." },

    -- Shovels (strike grass to till it into farmland) -----------------------
    wooden_shovel = { name = "Wooden Shovel", image = "wooden_shovel",
        tool = "shovel", power = 1, damage = 6, stamina = 6, cooldown = 0.5,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "Strike grass to till it into farmland, then plant seeds on it." },
    stone_shovel = { name = "Stone Shovel", image = "stone_shovel",
        tool = "shovel", power = 1, damage = 8, stamina = 6, cooldown = 0.5,
        shape = { kind = "rect", w = 22, h = 16, ahead = 14 },
        desc = "Tills farmland and doubles as a passable club." },
    iron_shovel = { name = "Iron Shovel", image = "iron_shovel",
        tool = "shovel", power = 1, damage = 11, stamina = 5, cooldown = 0.45,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "Tills quickly and hits harder than lesser shovels." },
    diamond_shovel = { name = "Diamond Shovel", image = "diamond_shovel",
        tool = "shovel", power = 1, damage = 14, stamina = 5, cooldown = 0.4,
        shape = { kind = "rect", w = 24, h = 18, ahead = 14 },
        desc = "Effortless tilling and a nasty edge when cornered." },

    -- Swords (pure combat) --------------------------------------------------
    wooden_sword = { name = "Wooden Sword", image = "wooden_sword",
        tool = "sword", damage = 12, stamina = 8, cooldown = 0.5,
        shape = { kind = "rect", w = 26, h = 18, ahead = 16 },
        desc = "A trusty plank with a point. Better than fists against the night." },
    stone_sword = { name = "Stone Sword", image = "stone_sword",
        tool = "sword", damage = 18, stamina = 12, cooldown = 0.6,
        shape = { kind = "rect", w = 28, h = 20, ahead = 16 },
        desc = "Heavy edge that hits hard but drains stamina fast." },
    iron_sword = { name = "Iron Sword", image = "iron_sword",
        tool = "sword", damage = 26, stamina = 8, cooldown = 0.45,
        shape = { kind = "rect", w = 30, h = 20, ahead = 17 },
        desc = "A soldier's blade: fast, sharp and reliable." },
    diamond_sword = { name = "Diamond Sword", image = "diamond_sword",
        tool = "sword", damage = 34, stamina = 6, cooldown = 0.4,
        shape = { kind = "rect", w = 34, h = 22, ahead = 18 },
        desc = "The last blade you will ever craft. Devastating and effortless." },

    -- Special --------------------------------------------------------------
    crystal_sword = { name = "Crystal Sword", image = "items/15x15_crystal_sword",
        tool = "sword", damage = 26, stamina = 8, cooldown = 0.35,
        shape = { kind = "circle", r = 17, ahead = 14 },
        desc = "Feather-light shard blade. Fast, wide slashes for little stamina." },
    bow = { name = "Bow", image = "items/15x15_bow",
        tool = "bow", damage = 22, stamina = 12, cooldown = 0.8,
        desc = "Fires arrows exactly where you aim. Each shot uses one arrow." },
}

-- Bare hands: used whenever nothing is equipped. Same fields as a tool item.
FISTS = {
    name = "Fists", tool = "sword", power = 1, damage = 5, stamina = 4, cooldown = 0.5,
    shape = { kind = "circle", r = 11, ahead = 9 },
    desc = "Your own two hands. They can even fell a tree... eventually.",
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
    -- Iron tier (smelted: stone + coal).
    { id = "iron_pickaxe",    count = 1, needs = { wood = 2, stone = 3, coal = 2 } },
    { id = "iron_shovel",     count = 1, needs = { wood = 2, stone = 2, coal = 2 } },
    { id = "iron_sword",      count = 1, needs = { wood = 2, stone = 4, coal = 2 } },
    -- Ranged.
    { id = "bow",             count = 1, needs = { wood = 7 } },
    { id = "arrow",           count = 4, needs = { wood = 1, stone = 1 } },
    -- Top tier.
    { id = "crystal_sword",   count = 1, needs = { wood = 2, coal = 1, crystal = 3 } },
    { id = "diamond_pickaxe", count = 1, needs = { wood = 2, coal = 2, diamond = 2 } },
    { id = "diamond_shovel",  count = 1, needs = { wood = 2, coal = 1, diamond = 2 } },
    { id = "diamond_sword",   count = 1, needs = { wood = 2, coal = 2, diamond = 3 } },
    { id = "hamburger",       count = 1, needs = { potato = 2, apple = 1, watermelon = 1 } },
}

-- Gather rules ---------------------------------------------------------------
TREE_HP = 4    -- chop damage: axes deal their power, anything else deals 1
STONE_HP = 6   -- mine damage: pickaxes deal their power, anything else 0

TREE_DROPS = {
    { id = "wood", min = 2, max = 3, chance = 1.0 },
    { id = "apple", min = 1, max = 1, chance = 0.40 },
    { id = "seed", min = 1, max = 2, chance = 0.35 },
}

-- Stone drops: 'per_power' chances scale with the pickaxe's power, so better
-- picks genuinely find rarer minerals more often.
STONE_DROPS = {
    { id = "stone", min = 1, max = 2, chance = 1.0 },
    { id = "coal", min = 1, max = 2, chance = 0.30 },
    { id = "crystal", min = 1, max = 1, chance = 0.02, per_power = 0.015 },
    { id = "diamond", min = 1, max = 1, chance = 0.005, per_power = 0.008 },
    { id = "chest", min = 1, max = 1, chance = 0.04 },
}

-- Harvesting a grown crop.
HARVEST_DROPS = {
    { id = "watermelon", min = 1, max = 1, chance = 1.0 },
    { id = "seed", min = 0, max = 2, chance = 1.0 },
}

-- What tumbles out of a chest (weighted picks; a chest rolls 2-3 of these).
CHEST_LOOT = {
    { id = "potato", min = 1, max = 3, weight = 30 },
    { id = "apple", min = 1, max = 2, weight = 20 },
    { id = "arrow", min = 3, max = 8, weight = 15 },
    { id = "coal", min = 1, max = 3, weight = 12 },
    { id = "hamburger", min = 1, max = 1, weight = 8 },
    { id = "crystal", min = 1, max = 2, weight = 10 },
    { id = "diamond", min = 1, max = 1, weight = 5 },
}
CHEST_ROLLS_MIN = 2
CHEST_ROLLS_MAX = 3

-- Zombies occasionally carry a snack.
ZOMBIE_DROPS = {
    { id = "apple", min = 1, max = 1, chance = 0.15 },
    { id = "potato", min = 1, max = 1, chance = 0.10 },
}

-- =============================================================================
-- Accessors (other entities call these with run_function("-items", ...)).
-- =============================================================================

function get_item(item_id)
    return ITEMS[item_id]
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
    return (item.tool ~= nil) or (item.heal ~= nil) or (item_id == "seed") or (item.place_kind ~= nil)
end

-- Tile kind this item becomes when placed with Interact, or nil if it can't be.
function get_place_kind(item_id)
    local item = ITEMS[item_id]
    return item and item.place_kind or nil
end

function get_tree_drops() return TREE_DROPS end
function get_stone_drops() return STONE_DROPS end
function get_harvest_drops() return HARVEST_DROPS end
function get_zombie_drops() return ZOMBIE_DROPS end

function get_chest_loot()
    return { loot = CHEST_LOOT, rolls_min = CHEST_ROLLS_MIN, rolls_max = CHEST_ROLLS_MAX }
end

function get_tree_hp() return TREE_HP end
function get_stone_hp() return STONE_HP end

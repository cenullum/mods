singleton_name = "w"

-- =============================================================================
-- Operation: Detonate - world setup + card definitions.
--
-- Theme: a covert ops team pulls equipment cards while trying to dodge the
-- TIME BOMBS hidden in the deck. Card art is a placeholder flat PNG per card
-- (general/images/<id>.png) - repaint them any time, the layout stays.
--
-- Every card is defined here with load_cards_from_data using the same "cards"
-- JSON structure the online card editor exports. Card TEXT is not here: each
-- title/description is a `{keyword}` resolved against this mod's own
-- general/language/operation_detonate_<code>.json, exactly like every label and
-- chat line the mod shows. Nothing user-facing is written in this script.
-- =============================================================================

-- REQUIRED for user.lua's cursor sync: the engine only gathers "stick_2"
-- (world mouse position) into _process()'s inputs table for inputs that have
-- a registered display name (see input_manager.gd::gather_local_inputs -
-- "if not input_name in display_names: continue"). Without this call every
-- peer's stick_2 is nil forever and no one's cursor ever shows up (same
-- requirement Hook Up's world.lua has for its own cursor).
set_input_display_name("stick_2","{mouse}")

set_background_color(Color(0.07, 0.08, 0.11, 1))
-- Straight-down fallback for before we're seated/rotated; once seated,
-- od_manager's sync_ALL recomputes this pulled toward our actual seat angle
-- (see CAMERA_SEAT_PULL there - a fixed world offset would only read as
-- "down" for one particular seat once the camera starts rotating per-seat).
set_camera_position(Vector2(0, 150))
-- Start fully zoomed OUT so the whole table is visible; players zoom in from
-- here (Zoom In). Keep this in sync with od_manager's cl_zoom init / zoom floor.
set_camera_zoom(Vector2(0.6, 0.6))

-- Persistent on-screen controls (Sit at table / Stand up / Zoom In / Zoom Out).
change_view("table")

set_image({
    name = "od_table",
    image_path = "table",
    position = Vector2(0, 0),
    scale = Vector2(780, 780),
    modulate = Color(0.55, 0.6, 0.7, 1), -- cold "briefing room" tint
    z_index = -10,
})

-- -----------------------------------------------------------------------------
-- Card catalogue: id -> {icon, bg, type}; the words live in the language JSONs
-- -----------------------------------------------------------------------------
local ICONS = {
    bomb = "bomb_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    disarm = "construction_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    attack = "swords_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    skip = "directions_run_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    favor = "handshake_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    shuffle = "shuffle_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    future = "radar_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    nope = "wifi_off_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
    weapon = "target_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg",
}

local CATALOG = {
    { id = "time_bomb", type = "bomb", icon = ICONS.bomb, bg = "(0.32, 0.06, 0.06, 1)" },
    { id = "disarm_kit", type = "disarm", icon = ICONS.disarm, bg = "(0.05, 0.35, 0.32, 1)" },
    { id = "ambush", type = "attack", icon = ICONS.attack, bg = "(0.45, 0.16, 0.05, 1)" },
    { id = "retreat", type = "skip", icon = ICONS.skip, bg = "(0.12, 0.25, 0.42, 1)" },
    { id = "supply_request", type = "favor", icon = ICONS.favor, bg = "(0.42, 0.32, 0.14, 1)" },
    { id = "mission_shuffle", type = "shuffle", icon = ICONS.shuffle, bg = "(0.28, 0.16, 0.4, 1)" },
    { id = "recon_drone", type = "future", icon = ICONS.future, bg = "(0.5, 0.42, 0.06, 1)" },
    { id = "signal_jammer", type = "nope", icon = ICONS.nope, bg = "(0.2, 0.23, 0.3, 1)" },
    { id = "pistol_9mm", type = "weapon", icon = ICONS.weapon, bg = "(0.2, 0.2, 0.22, 1)" },
    { id = "heavy_revolver", type = "weapon", icon = ICONS.weapon, bg = "(0.24, 0.19, 0.15, 1)" },
    { id = "machine_pistol", type = "weapon", icon = ICONS.weapon, bg = "(0.25, 0.25, 0.28, 1)" },
    { id = "compact_smg", type = "weapon", icon = ICONS.weapon, bg = "(0.2, 0.23, 0.3, 1)" },
    { id = "tactical_handgun", type = "weapon", icon = ICONS.weapon, bg = "(0.2, 0.26, 0.2, 1)" },
}

local cards = {}
for _, entry in ipairs(CATALOG) do
    -- Titles/descriptions are mod KEYWORDS, never literal text: the strings
    -- themselves live in general/language/operation_detonate_<code>.json like
    -- every other string this mod shows, and CardRenderer resolves a cell's
    -- loc_key against those files (see localized_text). So a card face is
    -- translated by the same JSON the chat lines and panels use, in every
    -- language the mod ships, and adding a language means adding a file - not
    -- editing this script.
    local title_key = "{od_" .. entry.id .. "_title}"
    local desc_key = "{od_" .. entry.id .. "_desc}"
    table.insert(cards, {
        id = entry.id,
        -- A keyword, not a name: od_manager puts this straight into panels and
        -- chat lines, which auto-translate tokens per peer.
        name = title_key,
        keywords = { type = entry.type },
        bg = { type = "color", color = entry.bg },
        corner = {
            text = "", icon = entry.icon, spots = { "tl", "br" }, flip_opposite = true,
            size = 0.11, color = "(1, 1, 1, 0.9)", outline_size = 0,
            outline_color = "(0, 0, 0, 1)",
        },
        layout = { type = "vbox", children = {
            { type = "text", weight = 0.17, pad = 0.015, text = title_key,
              loc_key = "od_" .. entry.id .. "_title", keyword = "title",
              font_size = 0, align = "center", valign = "center",
              color = "(1, 1, 1, 1)", outline_size = 0.14, outline_color = "(0, 0, 0, 1)" },
            { type = "image", weight = 0.5, pad = 0.02, fit = "contain",
              source = "file:" .. entry.id .. ".png", keyword = "art" },
            { type = "text", weight = 0.33, pad = 0.03, text = desc_key,
              loc_key = "od_" .. entry.id .. "_desc", keyword = "description",
              font_size = 0, align = "center", valign = "begin",
              color = "(0.95, 0.95, 0.95, 1)", outline_size = 0.08,
              outline_color = "(0, 0, 0, 1)", bg_color = "(0, 0, 0, 0.4)" },
        } },
    })
end

load_cards_from_data({
    kind = "cards",
    set_id = "od",
    name = "Operation Detonate",
    card_w = 750,
    card_h = 1050,
    corner_radius = 0.07,
    safe_margin = 0.05,
    bg = { type = "color", color = "(0.72, 0.11, 0.11, 1)" },
    back = { type = "color", color = "(0.1, 0.12, 0.16, 1)" },
    -- Subtle steel rim around every card so they read against the dark table.
    outline = { enabled = true, color = "(0.85, 0.88, 0.95, 0.85)", width = 0.018 },
    -- No "languages"/"localization" here on purpose: this set carries no
    -- translation table of its own, it uses the mod's language JSON files.
    cards = cards,
}, "od")

card_set_listener("-od_manager")
card_set_hand_ui({ height = 165, separation = -38 })

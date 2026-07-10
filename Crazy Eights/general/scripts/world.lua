singleton_name = "w"

-- =============================================================================
-- Crazy Eights - world setup + card definitions.
--
-- Everyone looks at one round table. Seats are arranged on a circle around the
-- table center and each seated player's CAMERA IS ROTATED so their own seat is
-- at the bottom of their screen (the table works like a real tabletop).
--
-- The whole deck is defined procedurally right here with load_cards_from_data:
-- bold cards with a big center value + corner indices, four colors (purple /
-- teal / orange / green). Eights are the wild cards. This script runs once on
-- every peer, so every peer has the same definitions; the deck ORDER only
-- ever exists on the host.
-- =============================================================================

local TABLE_IMAGE = "ce_table"

-- REQUIRED for user.lua's cursor sync: the engine only gathers "stick_2"
-- (world mouse position) into _process()'s inputs table for inputs that have
-- a registered display name (see input_manager.gd::gather_local_inputs -
-- "if not input_name in display_names: continue"). Without this call every
-- peer's stick_2 is nil forever and no one's cursor ever shows up (same
-- requirement Hook Up's world.lua has for its own cursor).
set_input_display_name("stick_2", "Mouse")

set_background_color(Color(0.09, 0.10, 0.14, 1))
set_camera_position(Vector2(0, 0))
-- Start fully zoomed OUT so the whole table is visible; players zoom in from
-- here (Zoom In). Keep this in sync with ce_manager's cl_zoom init / zoom floor.
set_camera_zoom(Vector2(0.6, 0.6))

-- Persistent on-screen controls (Sit at table / Stand up / Zoom In / Zoom Out).
change_view("table")

-- The felt table everyone plays on (a plain world-space image).
set_image({
    name = TABLE_IMAGE,
    image_path = "table",
    position = Vector2(0, 0),
    scale = Vector2(760, 760),
    z_index = -10,
})

-- -----------------------------------------------------------------------------
-- Card definitions (four colors, values 0-9 + skip + reverse + draw2)
-- -----------------------------------------------------------------------------
local COLOR_DEFS = {
    { key = "purple", label = "Purple", body = "(0.45, 0.16, 0.72, 1)", dark = "(0.27, 0.08, 0.45, 1)" },
    { key = "teal",   label = "Teal",   body = "(0.05, 0.62, 0.60, 1)", dark = "(0.02, 0.38, 0.37, 1)" },
    { key = "orange", label = "Orange", body = "(0.92, 0.50, 0.08, 1)", dark = "(0.60, 0.30, 0.02, 1)" },
    { key = "green",  label = "Green",  body = "(0.30, 0.68, 0.20, 1)", dark = "(0.16, 0.42, 0.10, 1)" },
}

local WHITE = "(1, 1, 1, 1)"

local function corner_def(text, icon)
    return {
        text = text, icon = icon or "", spots = { "tl", "br" }, flip_opposite = true,
        size = 0.16, color = WHITE, outline_size = 0.22, outline_color = "(0, 0, 0, 1)",
    }
end

local function center_text_cell(text, dark)
    return {
        type = "text", weight = 1.0, text = text, font_size = 0, pad = 0.1,
        align = "center", valign = "center", color = WHITE,
        outline_size = 0.16, outline_color = dark,
    }
end

local function icon_cell(icon_file, weight)
    return {
        type = "icon", weight = weight or 1.0, pad = 0.12, color = WHITE,
        icon = icon_file,
    }
end

-- Builds one card definition in the editor's "cards" JSON structure.
local function build_card(color, value)
    local id = "ce_" .. color.key .. "_" .. value
    local card = {
        id = id,
        name = color.label .. " " .. value,
        keywords = { color = color.key, value = value },
        bg = { type = "color", color = color.body },
        corner = nil,
        layout = nil,
    }

    if value == "skip" then
        card.corner = corner_def("", "block_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg")
        card.layout = { type = "vbox", children = {
            icon_cell("block_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg"),
        } }
    elseif value == "reverse" then
        card.corner = corner_def("", "swap_horiz_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg")
        card.layout = { type = "vbox", children = {
            icon_cell("swap_horiz_32dp_FFFFFF_FILL0_wght400_GRAD0_opsz40.svg"),
        } }
    elseif value == "draw2" then
        card.corner = corner_def("+2")
        card.layout = { type = "vbox", children = {
            center_text_cell("+2", color.dark),
        } }
        card.keywords.power = 2
    elseif value == "8" then
        -- The wild card: the face is split into four equal color quadrants (one
        -- per playable color) so it reads instantly as "play me as any color".
        -- Each quadrant keeps a big "8" so it still reads as an eight.
        card.corner = corner_def("8")
        card.keywords.wild = true
        card.keywords.power = 8
        local function quad(cdef)
            return {
                type = "text", weight = 1, text = "8", font_size = 0, pad = 0.0,
                align = "center", valign = "center", color = WHITE,
                outline_size = 0.16, outline_color = cdef.dark, bg_color = cdef.body,
            }
        end
        card.layout = { type = "vbox", children = {
            { type = "hbox", weight = 1, children = { quad(COLOR_DEFS[1]), quad(COLOR_DEFS[2]) } },
            { type = "hbox", weight = 1, children = { quad(COLOR_DEFS[3]), quad(COLOR_DEFS[4]) } },
        } }
    else
        card.corner = corner_def(value)
        card.layout = { type = "vbox", children = {
            center_text_cell(value, color.dark),
        } }
        card.keywords.power = tonumber(value)
    end
    return card
end

local cards = {}
for _, color in ipairs(COLOR_DEFS) do
    for n = 0, 9 do
        table.insert(cards, build_card(color, tostring(n)))
    end
    table.insert(cards, build_card(color, "skip"))
    table.insert(cards, build_card(color, "reverse"))
    table.insert(cards, build_card(color, "draw2"))
end

load_cards_from_data({
    kind = "cards",
    set_id = "ce",
    name = "Crazy Eights",
    card_w = 750,
    card_h = 1050,
    corner_radius = 0.08,
    safe_margin = 0.055,
    bg = { type = "color", color = "(0.2, 0.2, 0.2, 1)" },
    back = { type = "color", color = "(0.13, 0.13, 0.18, 1)" },
    -- Crisp white rim around every card so they pop against the felt + each other.
    outline = { enabled = true, color = "(1, 1, 1, 0.9)", width = 0.02 },
    cards = cards,
}, "ce")

-- All card events (clicks, draws, plays...) go to the manager singleton.
card_set_listener("-ce_manager")
card_set_hand_ui({ height = 150, separation = -34 })

singleton_name = "w"

-- =============================================================================
-- Draw The Word - world setup.
--
-- There are no moving avatars: every player looks at ONE shared drawing board
-- centred on screen. The board is a paintable world-space Sprite2D, created on
-- every peer so paint strokes sync locally. Only the current drawer is allowed
-- to paint it - that permission is server-authoritative (set_painter), decided
-- by dtw_manager, and is independent of who has the painting toolbox open.
--
-- This script runs once on every peer when the world loads.
-- =============================================================================

local BOARD = "dtw_board"          -- the paintable canvas (matches dtw_manager)
local BOARD_BG = "dtw_board_bg"    -- opaque white backing behind the canvas
local BOARD_SIZE = Vector2(480, 360)  -- on-screen size in world units

-- Dark backdrop so the white board stands out.
set_background_color(Color(0.12, 0.13, 0.18, 1))

-- Fixed camera framing the board; shift up slightly so the board feels centred
-- with the bottom UI buttons visible below it without clipping the canvas.
set_camera_position(Vector2(0, -50))
set_camera_zoom(Vector2(1, 1))

-- A known, clean view context (HUD/score/etc. are separate Lua panels).
-- Buttons and labels in the view are defined in views/drawing.json.
change_view("drawing")

-- Opaque white sheet so a freshly cleared (transparent) canvas still reads as a
-- clean white board. Not paintable; sits just behind the canvas.
set_image({
    name = BOARD_BG,
    image_path = "1x_white",
    position = Vector2(0, 0),
    scale = BOARD_SIZE,
    z_index = 0,
})

-- The shared paintable canvas. dtw_canvas.png is a 384x288 transparent texture,
-- so drawings show on the white backing and "clear" returns to a clean sheet.
set_image({
    name = BOARD,
    image_path = "dtw_canvas",
    position = Vector2(0, 0),
    scale = BOARD_SIZE,
    z_index = 1,
    paintable = true,
    indexed = false,        -- free colour picker + the panel's 32-swatch palette
    sync_mode = "live",     -- everyone sees strokes as they happen
    max_undo = 30,
})

-- Start locked: nobody may draw until dtw_manager begins a round.
set_painter(BOARD, 0)

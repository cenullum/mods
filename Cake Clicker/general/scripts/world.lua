singleton_name = "w"

-- =============================================================================
-- Cake Clicker - world setup.
--
-- Everything the game shows is drawn by cc.lua in world space; this script only
-- sets the stage every peer shares: the fixed camera (the whole table, the
-- market and both side panels fit in the 1152x648 base view), the shop's
-- background and awning, and the inputs.
--
-- Inputs (registered = gathered and sent; the label is the on-screen hint):
--   stick_1  left / right: eat the slice in front of you, or turn the plate
--            when there is none (A / D, the arrow keys, a gamepad stick)
--   key_12 + stick_2  click the market cards, your pocket, the settings board
-- =============================================================================

set_input_display_name("stick_1", "{input_eat_turn}")
set_input_display_name("key_12", "{input_select}")
set_input_display_name("stick_2", "{input_pointer}")

-- Everyone sees everyone else's mouse cursor; cc.lua tints each one with its
-- owner's seat colour once the roster is known. Bots draw their own (cc.lua).
set_cursor(true)

set_background_color(Color(0.929, 0.953, 0.910, 1))
set_camera_position(Vector2(0, 0))
set_camera_zoom(Vector2(1, 1))

-- A striped shop awning along the top edge. is_repeat keeps the texture at 1:1
-- and tiles it across the requested size, so it covers wide screens too.
set_image({
    name = "cc_awning",
    image_path = "ui/awning",
    position = Vector2(0, -310),
    scale = Vector2(4004, 29),
    is_repeat = true,
    z_index = -50,
})

-- Steam achievement: counts this mod once for the local player.
add_unique_achievement_progress("gen_mods", "cake_clicker")

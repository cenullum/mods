singleton_name = "w"

-- =============================================================================
-- Hide and Seek - one-time world setup. Runs once on every peer at map load.
-- Top-down cave (movement matches the Football mod: stick_1 walks the avatar).
-- =============================================================================

set_controller_type(1)                 -- 1 = TOP_DOWN (stick_1 moves the avatar)
set_gravity_direction(Vector2(0, 0))   -- top-down: no gravity pull (like Football)
set_background_color(Color(0.12, 0.12, 0.14, 1))
set_background_texture("floor")  -- repeating ground under the walkable areas
set_camera_zoom(Vector2(2.6, 2.6))
change_view("gameplay")

set_input_display_name("stick_1", "Move")
set_input_display_name("key_12", "Shoot")

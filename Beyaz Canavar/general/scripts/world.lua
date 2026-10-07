singleton_name = "w"
network_mode = 0

-- =============================================================================
-- Beyaz Canavar - world setup (local, every peer): top-down physics, a dark
-- vignette over everything, and the inputs this mod uses. Inputs only exist
-- (and are only sent over the network) once registered here; their labels are
-- what the bottom-right hints (hud.lua) show next to each key.
-- =============================================================================

set_controller_type(1) -- TOP_DOWN
set_gravity_direction(Vector2(0, 0))
set_background_color(Color(0, 0, 0, 1))
set_vignette({ visible = true, color = Color(0, 0, 0, 1), strength = 1.2, radius = 0.5, smoothness = 0.45 })

set_input_display_name("stick_1", "{move}")
set_input_display_name("key_6", "{interact_hold}")
set_input_display_name("key_4", "{tasks}")
set_input_display_name("key_11", "{map}")
set_input_display_name("key_8", "{scream}")

-- The ambience loops forever on the Ambient bus, on every peer. (The horror
-- sting is the host's call - game_manager.lua - so everybody hears it at once.)
set_audio({ stream_path = "ambiance", name = "bc_ambiance", bus = "Ambient", is_loop = true })

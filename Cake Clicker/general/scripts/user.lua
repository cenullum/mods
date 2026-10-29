network_mode = 1
gravity_scale = 0.0
lock_rotation = true
freeze = true
speed = 0

-- =============================================================================
-- Cake Clicker - player entity.
--
-- Nobody walks around: everyone sits at the one round table that cc.lua draws.
-- stick_1 is registered (left/right eats or turns the plate), so the body is
-- frozen and has no speed; the only per-player world presence is the mouse
-- cursor, which the engine draws for every other player (set_cursor in
-- world.lua, colours from cc.lua's roster).
-- =============================================================================

add_tag(name, "user")

network_mode = 1
gravity_scale = 0.0
lock_rotation = true
freeze = true

-- =============================================================================
-- Crazy Eights - player entity.
--
-- There are no walking avatars: everyone sits around one table (the camera is
-- rotated per seat by ce_manager). The only per-player world presence is the
-- mouse cursor, which the engine draws for every other player (set_cursor in
-- world.lua; colours from ce_manager.sync_ALL).
-- =============================================================================

add_tag(name, "user")

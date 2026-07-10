network_mode = 1
gravity_scale = 0.0
lock_rotation = true
freeze = true

-- =============================================================================
-- School Days - player entity.
--
-- A visual novel has no walking avatar: each player only reads the story and
-- votes through the shared HUD (see sd_manager.lua). So the user entity carries
-- no visuals and does nothing per frame - it exists only so the lobby has a
-- proper per-player entity like every other mod.
-- =============================================================================

add_tag(name, "user")

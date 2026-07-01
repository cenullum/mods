network_mode = 1
gravity_scale = 0.0
lock_rotation = true

-- =============================================================================
-- Draw The Word - player entity.
--
-- This game has no moving avatars: everyone just watches the shared board. The
-- player body stays invisible and inert (no image, no collision, no gravity).
-- All per-player game state (turn order, score, who guessed) is tracked by
-- dtw_manager, keyed on steam_id, driven by _on_user_initialized /
-- _on_user_disconnected there.
-- =============================================================================

add_tag(name, "user")

-- The arena tiles themselves are drawn by "-mg" (monster_generation.lua), which
-- owns the rectangle bounds and can repaint them at a different size when the
-- boss shows up. This entity just kicks off the first build on every peer.

run_function("-mg", "build_map")

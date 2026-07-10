singleton_name = "w"

-- =============================================================================
-- School Days - world setup.
--
-- This is a classic visual novel driven by the engine's Visual Novel runtime
-- (vn_* functions). The STORY itself (characters, dialog, branches, variables,
-- multiple endings) lives in story/school_days.json - the exact format the
-- Online Asset Editor's Visual Novel tab exports. All the presentation you see
-- (background, character sprite, name box, dialog, choice buttons) is ordinary
-- HUD built here + in sd_manager.lua; the engine only tracks the story graph.
--
-- Everything on screen is the "hud" view (general/views/hud.json), a pure
-- screen-space canvas, so there are no world avatars or camera work to do -
-- players only ever vote through the HUD. sd_manager.lua owns the game loop.
-- =============================================================================

set_background_color(Color(0.06, 0.06, 0.09, 1))
change_view("hud")

-- Idle screen shown until the host starts. sd_manager takes over from there.
set_label({ name = "_hint", text = "School Days" })
set_label({ name = "_speaker", text = "" })
set_label({ name = "_dialog", text =
    "A branching school story you play together.\n\n" ..
    "One year, told from one point of view - but every choice is decided by a " ..
    "vote of everyone in the lobby. Love, rivalry, a cheating scandal and six " ..
    "different endings are on the table.\n\n" ..
    "When everyone has arrived, the host starts the story." })
set_image({ name = "_char", visible = false })

if IS_HOST then
    set_button({ name = "_start", visible = true })
    set_label({ name = "_status", text = "You are the host" })
else
    set_label({ name = "_status", text = "Waiting for the host..." })
end

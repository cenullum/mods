-- File: cenkers_mod_stub.lua
-- IMPORTANT: This is a META/STUB file for the Lua Language Server (LuaLS) only.
-- It provides type definitions and documentation for global functions and variables
-- exposed from Godot's GDScript layer to Lua scripts in cenker's mod.
-- This file contains no executable logic.

-- This script is licensed under CC0 1.0 Universal (CC0 1.0)
-- Public Domain Dedication
-- Information About The License: https://creativecommons.org/share-your-work/public-domain/cc0/

---@meta

---------------------------------------------------
-- IMPORTANT RULES AND LIMITATIONS
---------------------------------------------------

-- 0. ENTITY GLOBALS: Each entity has its own separate global Lua environment. Variables declared
--    without 'local' are global to that entity only. There is NO shared _G table between entities.
-- 1. VELOCITY CAP: Entity velocity is capped at 600. Values above this are unnecessary.
-- 2. Z-INDEX RANGE: All z_index values must be between -999 and 999.
-- 3. TABLE KEYS: Vector2 and Color types CANNOT be used as table keys - you will get errors.
--    Use strings or numbers as keys instead.
-- 4. LOCAL VARIABLES: Variables declared with 'local' keyword cannot be accessed with
--    get_value() or set_value(). Only global entity variables can be accessed.
-- 5. RETURN VALUES: run_function() and get_value() cannot return multiple values.
--    To return multiple values, wrap them in a table.
-- 6. TOP VARIABLES: Variables at the top of the script (before any function, comment, or blank line)
--    must be primitive types (numbers, strings, booleans). These special configuration variables
--    are parsed before script execution.
-- 7. NETWORK FUNCTIONS: Must end with _HOST, _ALL, or _CLIENT and first parameter MUST be sender_id.
-- 8. SINGLETONS: If created via spawn_entity_host/local, they will NOT become singletons.
--    Singletons must be spawned from map or world initialization.
-- 9. NETWORK SYNC: ALL variables in STATIC (1) and DYNAMIC (2) entities are sent to clients when
--    they join. Be careful with sensitive data.
-- 10. PERFORMANCE: _process runs every frame. Avoid calling set_label, set_image, etc. unless
--     values actually change.

---------------------------------------------------
-- GODOT TYPE DEFINITIONS
---------------------------------------------------

--- Godot's 2D vector structure.
---@class Vector2
---@field x number The X component (float).
---@field y number The Y component (float).
--- Godot's 2D vector structure.
---@type fun(x?: number, y?: number): Vector2
Vector2 = nil

--- Godot's Color structure (RGBA).
---@class Color
---@field r number Red component (0.0 to 1.0).
---@field g number Green component (0.0 to 1.0).
---@field b number Blue component (0.0 to 1.0).
---@field a number Alpha component (0.0 to 1.0).

---@type fun(r?: number, g?: number, b?: number, a?: number): Color
Color = nil

--- Dictionary structure for key-value pairs.
---@class Dictionary: table
local Dictionary = {}

---------------------------------------------------
-- GLOBAL VARIABLES EXPOSED TO ALL LUA SCRIPTS
-- These are automatically set by the engine for each entity.
---------------------------------------------------

--- The unique name of this entity instance.
---@type string
name = ""

--- The script filename this entity was created from (without .lua extension).
---@type string
script_name = ""

--- Current global position of this entity in the world.
---@type Vector2
position = Vector2()

--- Current rotation of this entity in radians.
---@type number
rotation = 0.0

--- Current linear velocity (movement speed and direction).
--- NOTE: Velocity magnitude is capped at 600 by the engine.
---@type Vector2
linear_velocity = Vector2()

--- Whether this entity belongs to the local player (for user entities, compares name with local Steam ID).
---@type boolean
IS_LOCAL = false

--- Whether the local machine is the host/server in multiplayer.
---@type boolean
IS_HOST = false

--- Absolute path to the current mod directory.
---@type string
MOD_PATH = ""

--- Local player's Steam ID as a string.
---@type string
LOCAL_STEAM_ID = ""

--- Host/server's Steam ID as a string.
---@type string
HOST_STEAM_ID = ""

---------------------------------------------------
-- SPECIAL CALLBACK FUNCTIONS
-- Define these functions in your entity script to receive events.
---------------------------------------------------

--- Called every frame on entities that define this function.
--- Return the modified inputs dictionary to update player input state.
--- WARNING: This runs EVERY FRAME and consumes significant processing power.
--- Avoid calling set_label, set_image, set_progress_bar, etc. unless values actually change!
---@param delta number Time elapsed since last frame in seconds.
---@param inputs table Input state dictionary with keys: key_1 to key_15 (boolean), stick_1 (Vector2), stick_2 (Vector2).
---@return table|nil Modified inputs dictionary (or nil to leave unchanged).
function _process(delta, inputs) end

--- Called when a chat message is received (only on entities that define this).
---
--- **Command Processing Note:**
--- The system now checks for registered mod commands BEFORE calling this function.
--- If a command (e.g., `/rules`) is detected, this handler will NOT be called for that message.
--- Use `add_command` to register centralized commands instead of manually parsing chat here.
---
--- **Behavior:**
--- - return nil: show standard format automatically.
--- - return "": suppress output (show nothing).
--- - return non-empty string: show it as-is (supports limited BBCode).
---
--- **Standard format (when returning nil):**
--- - Local user: [color=#66FF99]<nickname>[/color]: <message>
--- - Other users: [color=#6699FF]<nickname>[/color]: <message>
---
--- Allowed BBCode tags when returning a custom string: color, b, i, u, s, center, right, url
---@param sender_id string Steam ID of the sender as a string.
---@param nickname string Display name of the sender.
---@param message string The chat message text.
---@return string|nil Custom formatted message ("" to hide), or nil for standard.
function _on_chat_message_received(sender_id, nickname, message) end

--- Called when gamepad connection status changes or when gamepad display style is changed in settings.
---
--- This function is triggered in two scenarios:
---
--- - When a gamepad is physically connected or disconnected from the system
--- - When the user changes the gamepad display style preference in the settings menu (Auto, Xbox, PlayStation, or Nintendo button styles)
---
--- Use this callback to update UI elements that display gamepad button prompts, ensuring they show the correct button names/symbols based on the current controller type or user preference.
---
--- Common use case: Re-setting label text with @input_name@ placeholders to refresh button displays.
---
--- Example usage:
--- ```lua
--- function _on_gamepad_connection_changed(has_gamepad)
---     -- Update UI labels to refresh button prompts
---     set_value("", "tutorial_label", "text", "Press @key_7@ to interact\n@stick_1@ to move")
--- end
--- ```
---@param has_gamepad boolean True if a gamepad is currently connected, false otherwise.
function _on_gamepad_connection_changed(has_gamepad) end

--- Called when a new user joins and finishes initialization.
--- Useful for sending current game state to late joiners.
---@param initialized_steam_id string Steam ID of the newly initialized user.
---@param nickname string Display name of the newly initialized user.
function _on_user_initialized(initialized_steam_id, nickname) end

--- Called when a user connects to the lobby (before initialization finishes).
--- Do not send run_network_function this steam_id yet in _on_user_connected
---@param steam_id string Steam ID of the connected user.
---@param nickname string Display name of the connected user.
function _on_user_connected(steam_id, nickname) end

--- Called when a user disconnects or leaves the lobby.
---@param steam_id string Steam ID of the disconnected user.
---@param nickname string Display name of the disconnected user (last known).
function _on_user_disconnected(steam_id, nickname) end

--- Called when a Steam avatar is loaded.
---@param steam_id string Steam ID of the user whose avatar was loaded.
function _on_loaded_avatar(steam_id) end

--- Called when a user is kicked from the lobby by the host.
---@param steam_id string Steam ID of the kicked user.
---@param nickname string Display name of the kicked user.
function _on_user_kicked(steam_id, nickname) end

--- Called when a user is banned from the lobby by the host.
---@param steam_id string Steam ID of the banned user.
---@param nickname string Display name of the banned user.
---@param reason string Ban reason text (may be empty).
function _on_user_banned(steam_id, nickname, reason) end

---------------------------------------------------
-- CORE FUNCTION EXECUTION
---------------------------------------------------

--- Execute a local function on a specific entity by name.
--- NOTE: Cannot return multiple values. To return multiple values, wrap them in a table.
---@param entity_name string Target entity name (e.g., "player_1", "-ui_manager").
---@param function_name string Name of the Lua function to call.
---@param parameters? any|table|nil Function parameters (single value, array, dictionary, or nil). Default: [].
---@param delay? number Optional delay in seconds before execution. Default: 0.0.
---@return any|nil Return value from the called function, or nil if delayed/error.
function run_function(entity_name, function_name, parameters, delay) end

--- Execute a local function on all entities with a specific tag.
---@param tag string Target tag name (e.g., "enemy", "player").
---@param function_name string Name of the Lua function to call.
---@param parameters? any|table|nil Function parameters (single value, array, dictionary, or nil). Default: [].
---@param delay? number Optional delay in seconds before execution. Default: 0.0.
function run_function_by_tag(tag, function_name, parameters, delay) end

--- Execute a network-synchronized function on a specific entity.
--- CRITICAL: Function name MUST end with _HOST, _ALL, or _CLIENT.
--- CRITICAL: First parameter of the Lua function MUST be "sender_id" (string).
---@param entity_name string Target entity name. Use "user" to run once on each user entity per client.
---@param function_name string Network function name with suffix (_HOST, _ALL, _CLIENT).
---@param parameters? any|table|nil Function parameters (will be prepended with sender_id automatically). Default: [].
---@param steam_id? string Optional specific Steam ID for targeted execution. Default: "".
function run_network_function(entity_name, function_name, parameters, steam_id) end

--- Execute a network-synchronized function on all entities with a specific tag.
--- Function name must end with _HOST, _ALL, or _CLIENT.
--- First parameter of the Lua function MUST be "sender_id" (string).
---@param tag string Target tag name.
---@param function_name string Network function name with suffix (_HOST, _ALL, _CLIENT).
---@param parameters? any|table|nil Function parameters (will be prepended with sender_id automatically). Default: [].
---@param steam_id? string Optional specific Steam ID for targeted execution. Default: "".
function run_network_function_by_tag(tag, function_name, parameters, steam_id) end

---------------------------------------------------
-- VALUE MANAGEMENT (GET/SET ENTITY PROPERTIES)
---------------------------------------------------

--- Get a variable value from an entity.
--- Can access entity variables, position, rotation, velocity, UI properties, etc.
--- NOTE: Cannot access 'local' variables. Only global entity variables can be accessed.
--- NOTE: Cannot return multiple values. To return multiple values, wrap them in a table.
---@param parent_name string Parent entity name (use "" for world-level entities).
---@param entity_name string Target entity name.
---@param variable_name string Name of the variable to get.
---@return any|nil The variable value, or nil if not found.
function get_value(parent_name, entity_name, variable_name) end

--- Set a variable value on an entity.
--- Can set entity variables, position, rotation, velocity, UI properties, etc.
--- NOTE: Cannot modify 'local' variables. Only global entity variables can be modified.
---@param parent_name string Parent entity name (use "" for world-level entities).
---@param entity_name string Target entity name.
---@param variable_name string Name of the variable to set.
---@param value any The new value to assign.
function set_value(parent_name, entity_name, variable_name, value) end

---------------------------------------------------
-- TIMER MANAGEMENT
---------------------------------------------------

--- Start or create a timer with a callback function.
--- Timers call a Lua function repeatedly based on wait_time intervals.
--- If duration is set, timer stops after that duration.
--- Config parameters:
---   - timer_id (string, optional): Unique identifier for this timer. Default: auto-generated.
---   - entity_name (string, required): Entity that owns this timer and has the callback function.
---   - function_name (string, required): Lua function name to call on each timeout.
---   - wait_time (number, required): Interval in seconds between each callback trigger.
---   - duration (number, optional): Total duration in seconds before timer stops. If not set, timer runs indefinitely. Default: none.
---   - extra_args (table, optional): Additional data to pass to the callback function. Default: {}.
---   - iteration_count (number, optional): Starting iteration count. Default: 0.
---@param config table Timer configuration dictionary.
---@return string Timer identifier (timer_id).
function start_timer(config) end

--- Get information about a running timer.
---@param timer_id string Timer identifier.
---@return table Dictionary with keys: "time_left" (number), "is_running" (boolean), "iteration_count" (number), "duration" (number or nil).
function get_timer_data(timer_id) end

--- Stop and remove a specific timer.
---@param timer_id string Timer identifier.
function stop_timer(timer_id) end

--- Stop and remove all timers (global reset).
function stop_all_timers() end

---------------------------------------------------
-- ENTITY MANAGEMENT
---------------------------------------------------

--- Spawn a new entity locally (client-side only, not synchronized).
--- Config parameters:
---   - t (string, required): Script name (e.g., "enemy", "projectile").
---   - p (Vector2, optional): Position in world space. Default: Vector2(0, 0).
---   - r (number, optional): Rotation in radians. Default: 0.0.
---   - v (Vector2, optional): Linear velocity. Default: Vector2(0, 0).
---   - a (number, optional): Angular velocity in radians/sec. Default: 0.0.
---   - Any custom key-value pairs: You can add your own keys to the config table.
---     These will be stored in the entity and accessible via entity[key] in the entity's Lua code.
---     Example: {t = "enemy", hp = 100, level = 5} creates entity with entity.hp = 100 and entity.level = 5
---@param config table Configuration dictionary.
---@return string|nil The spawned entity name, or nil on error.
function spawn_entity_local(config) end

--- Spawn a new network-synchronized entity (Host only).
--- Automatically generates unique name based on timestamp.
--- Config parameters:
---   - t (string, required): Script name (e.g., "enemy", "projectile").
---   - p (Vector2, optional): Position in world space. Default: Vector2(0, 0).
---   - r (number, optional): Rotation in radians. Default: 0.0.
---   - v (Vector2, optional): Linear velocity. Default: Vector2(0, 0).
---   - a (number, optional): Angular velocity in radians/sec. Default: 0.0.
---   - Any custom key-value pairs: You can add your own keys to the config table.
---     These will be stored in the entity and accessible via entity[key] in the entity's Lua code.
---     Example: {t = "enemy", hp = 100, level = 5} creates entity with entity.hp = 100 and entity.level = 5
---@param config table Configuration dictionary.
---@return string|nil The spawned entity name, or nil on error.
function spawn_entity_host(config) end

--- Change an entity's position, rotation, linear velocity, and angular velocity instantly.
--- This function will override snapshot lerping.
--- Config parameters:
---   - entity_name (string, required): Entity to modify.
---   - position (Vector2, optional): New position.
---   - rotation (number, optional): New rotation in radians.
---   - linear_velocity (Vector2, optional): New linear velocity.
---   - angular_velocity (number, optional): New angular velocity in radians/sec.
---@param data table Configuration dictionary.
function change_instantly(data) end

--- Destroy an entity and its children.
---@param parent_name string Parent entity name (use "" for world-level entities).
---@param entity_name string Entity to destroy.
---@param notify_network? boolean Whether to notify other clients in multiplayer (Host only). Default: true.
function destroy(parent_name, entity_name, notify_network) end

--- Destroy all entities with a specific tag.
---@param tag string Tag identifier.
function destroy_entities_by_tag(tag) end

--- Freeze an entity (stops physics simulation).
--- Freezes the entity's RigidBody2D, disables collisions, and sets gravity_scale to 0.
--- Previous collision and gravity states are cached for restoration on unfreeze.
--- If 'all' is true and called on host, automatically syncs to all clients.
---@param entity_name string Entity to freeze.
---@param all? boolean Also freeze on all clients (Host only). Default: true.
function freeze_entity(entity_name, all) end

--- Unfreeze an entity (resumes physics simulation).
--- Restores the entity's cached collision states and gravity_scale, then unfreezes the RigidBody2D.
--- If 'all' is true and called on host, automatically syncs to all clients.
---@param entity_name string Entity to unfreeze.
---@param all? boolean Also unfreeze on all clients (Host only). Default: true.
function unfreeze_entity(entity_name, all) end

---------------------------------------------------
-- ENTITY TAGS
---------------------------------------------------

--- Add a tag to an entity for grouping/searching.
---@param entity_name string Target entity name.
---@param tag string Tag identifier to add.
function add_tag(entity_name, tag) end

--- Remove a tag from an entity.
---@param entity_name string Target entity name.
---@param tag string Tag identifier to remove.
function remove_tag(entity_name, tag) end

--- Check if an entity has a specific tag.
---@param entity_name string Target entity name.
---@param tag string Tag identifier to check.
---@return boolean True if entity has the tag.
function has_tag(entity_name, tag) end

--- Get all entity names with a specific tag.
---@param tag string Tag identifier.
---@return table Array of entity names as strings.
function get_entity_names_by_tag(tag) end

--- Find the nearest entity with a specific tag to a reference entity.
---@param entity_name string Reference entity name (to measure distance from).
---@param tag string Tag identifier to search for.
---@param excluded_entities? table Array of entity names to exclude from search. Default: [].
---@return table Dictionary with keys: "name" (string), "distance" (number), "angle" (number in radians). Returns empty table {} if none found.
function get_nearest_entity_by_tag(entity_name, tag, excluded_entities) end

---------------------------------------------------
-- ENTITY VISUALS (IMAGES, LABELS, PROGRESS BARS)
---------------------------------------------------

--- Set or create an image (sprite) on an entity.
--- Config parameters:
---   - parent_name (string, required): Parent entity name.
---   - name (string, optional): Image node name. Default: auto-generated.
---   - image_path (string, optional): Path to image in mod/general/images/ (without .png extension). If empty and creating new sprite, uses default icon. Default: "".
---   - position (Vector2, optional): Position offset from parent. Default: Vector2(0, 0).
---   - scale (Vector2, optional): Scale the image to this pixel size (based on texture size). Cannot use with 'size'. Default: none.
---   - size (Vector2, optional): Direct scale multiplier. Cannot use with 'scale'. Default: none.
---   - flip_h (boolean, optional): Flip horizontally. Default: false.
---   - flip_v (boolean, optional): Flip vertically. Default: false.
---   - visible (boolean, optional): Visibility. Default: true.
---   - modulate (Color|string, optional): Color tint. Default: Color(1, 1, 1, 1).
---   - z_index (integer, optional): Rendering order (-999 to 999). Default: 0.
---   - is_repeat (boolean, optional): Enable texture repeat/tiling. Default: false.
---   - rotation (number, optional): LOCAL-ONLY visual rotation in radians, around
---     the image's own centre. Never synced automatically — set it per peer
---     (e.g. to counter-rotate a seat avatar under a rotated per-seat camera).
---
---@param config table Image configuration dictionary.
---@return string The created/updated image node name.
function set_image(config) end

---------------------------------------------------
-- PAINTABLE CANVASES (DRAW ON IMAGES)
---------------------------------------------------
-- Turn a sprite created by set_image into an editable 2D canvas. Painting is
-- SERVER-AUTHORITATIVE: the host owns the pixels and the undo/redo history,
-- validates who may edit each image (by steam_id) and blocks unauthorized edits.
-- Clients send paint intents; the host applies and rebroadcasts. New joiners get
-- the current canvas automatically. The same settings can be configured from the
-- in-editor image panel; set_paintable lets the host (re)configure them at runtime.
-- World positions are world-space (e.g. inputs.stick_2, the in-game mouse).

--- Make an image (created via set_image) into a paintable canvas, or update an
--- existing canvas's settings. Call on the HOST to define permissions for everyone.
--- Config parameters:
---   - name (string, required): Image node name (same as set_image's name).
---   - parent_name (string, optional): Parent entity name. Default: "".
---   - editable (boolean, optional): Master on/off switch for editing. Default: true.
---   - editor_ids (table, optional): Array of steam_id strings allowed to edit.
---       Empty = everyone may edit. Default: {} (everyone).
---   - sync_mode (string, optional): "live" (echo strokes to all as drawn),
---       "manual" (apply on host, hidden until push_canvas reveals), or "none"
---       (purely local, never networked). Default: "live".
---   - brush_size (integer, optional): Brush diameter in pixels. Default: 8.
---   - alpha_blend (boolean, optional): true = blend over (source-over), false =
---       overwrite RGBA. Default: true.
---   - indexed (boolean, optional): Snap painted colours to the palette. Default: false.
---   - palette (table, optional): Array of Color for indexed mode. Default: {}.
---   - tolerance (number, optional): Flood-fill colour tolerance (0..1). Default: 0.
---   - predict (boolean, optional): Clients draw their own stroke immediately for
---       zero-latency feedback. Default: true.
---   - max_undo (integer, optional): Max undo steps kept on the host. Default: 32.
---@param config table Paintable configuration dictionary.
---@return boolean true on success.
function set_paintable(config) end

--- Server-authoritative drawing permission for one canvas, independent of any UI.
--- The host validates every incoming stroke against this, so unauthorized peers
--- are rejected at the network layer (anti-cheat) — this does NOT open or close
--- the painting panel, it only decides who is allowed to paint.
---
--- - steam_id == -1: everyone may draw (clears the allow-list).
--- - steam_id == 0: nobody may draw (locks the canvas).
--- - steam_id > 0 (e.g. "76561198..."): only that steam_id may draw.
---
--- Call it from host logic when assigning the active drawer; only the tiny
--- permission payload is replicated, so it is cheap to flip every turn.
---@param image_name string Image node name (same as set_paintable's name).
---@param steam_id string|integer Steam ID allowed to draw, or -1 (everyone) / 0 (nobody).
---@param parent_name? string Parent entity name. Default: "".
---@return boolean true on success (false if the image is not paintable).
function set_painter(image_name, steam_id, parent_name) end

--- Stop treating an image as paintable and free its canvas resources.
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
---@return boolean true if a canvas was removed.
function remove_paintable(image_name, parent_name) end

--- Whether an image currently has a paintable canvas on this peer.
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
---@return boolean
function is_paintable(image_name, parent_name) end

--- Set the local player's active paint tool.
--- Config parameters:
---   - tool (string, optional): "brush", "eraser" or "bucket". Default: "brush".
---   - brush_size (integer, optional): Brush diameter in pixels. Default: 8.
---   - color (Color|string, optional): Paint colour. Default: Color(0, 0, 0, 1).
---   - active (boolean, optional): When false, paint_* calls are ignored (gate
---       painting behind your own UI/state). Default: true.
---@param config table Tool configuration dictionary.
function set_paint_tool(config) end

--- Begin a brush/eraser stroke at a world position (uses the local tool). If the
--- tool is "bucket" this performs a flood fill instead.
---@param image_name string Image node name.
---@param world_pos Vector2 World-space position (e.g. inputs.stick_2).
---@param parent_name? string Parent entity name. Default: "".
function paint_begin(image_name, world_pos, parent_name) end

--- Continue the active stroke to a new world position (call while dragging).
---@param image_name string Image node name.
---@param world_pos Vector2 World-space position.
---@param parent_name? string Parent entity name. Default: "".
function paint_to(image_name, world_pos, parent_name) end

--- Finish the active stroke (commits one undo step on the host).
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
function paint_end(image_name, parent_name) end

--- Bucket / flood fill from a world position using the local tool colour.
---@param image_name string Image node name.
---@param world_pos Vector2 World-space position.
---@param parent_name? string Parent entity name. Default: "".
function flood_fill(image_name, world_pos, parent_name) end

--- Undo the most recent operation on a canvas (host-authoritative, image-global).
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
function paint_undo(image_name, parent_name) end

--- Redo the most recently undone operation on a canvas.
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
function paint_redo(image_name, parent_name) end

--- Clear a canvas to fully transparent (host-authoritative, undoable).
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
function clear_canvas(image_name, parent_name) end

--- HOST ONLY: push the current pixels of a canvas (or all canvases when name is
--- empty) to every client. This is how "manual" sync canvases are revealed.
---@param image_name? string Image node name, or "" for all canvases. Default: "".
---@param parent_name? string Parent entity name. Default: "".
function push_canvas(image_name, parent_name) end

--- Read a single pixel colour from the local copy of a canvas.
---@param image_name string Image node name.
---@param world_pos Vector2 World-space position.
---@param parent_name? string Parent entity name. Default: "".
---@return Color The pixel colour, or Color(0,0,0,0) when out of bounds.
function get_paint_color(image_name, world_pos, parent_name) end

--- Test whether a world position lands on a paintable canvas's pixel area.
---@param image_name string Image node name.
---@param world_pos Vector2 World-space position.
---@param parent_name? string Parent entity name. Default: "".
---@return boolean True if the point is inside the canvas.
function is_point_on_canvas(image_name, world_pos, parent_name) end

--- Read a canvas's current settings (useful for building adaptive paint UIs).
--- Returns an empty table when the image is not a registered canvas.
---@param image_name string Image node name.
---@param parent_name? string Parent entity name. Default: "".
---@return table info { exists, editable, sync_mode, indexed, palette, tolerance,
---  alpha_blend, predict, max_undo, brush_size, size }.
function get_paint_info(image_name, parent_name) end

--- Read the on-screen colour of the rendered world at a world-space position by
--- sampling the last drawn viewport frame. Unlike get_paint_color (which reads a
--- specific canvas) this samples whatever is actually visible there — tiles,
--- sprites, background — so a painter can eyedrop colours off nearby props to
--- blend in. The painting panel uses this for its off-canvas eyedropper.
---@param world_pos Vector2 World-space position (e.g. inputs.stick_2).
---@return Color The composited on-screen colour, or Color(0,0,0,0) if off-screen.
function get_world_color(world_pos) end

--- Open the READY-MADE painting panel for a paintable image inside a normal
--- popup. No draw code or buttons needed on your side: opening it is enough for
--- synced painting plus brush/eraser/eyedropper/bucket/line/circle/square,
--- undo/redo/reset, a 32-colour palette and brush-size/opacity sliders. The
--- panel adapts to the image's paint settings (e.g. undo disabled when there is
--- no undo allowance, free colour picker disabled on indexed canvases). If the
--- image is not paintable a warning panel is shown and nothing opens.
---@param config table {
---  name = string,            -- REQUIRED image node name to paint
---  parent_name? = string,    -- owning entity name. Default: ""
---  title? = string,          -- popup title. Default: "Paint"
---  close? = boolean,         -- show popup close button. Default: true
---  offset_ratio? = Vector2,  -- screen placement (1,1 = centre). Default: (1,1)
---  resizable? = boolean,     -- allow popup resize. Default: false
---  minimum_size? = Vector2,  -- popup minimum size. Default: (360,230)
---  color? = Color,           -- popup background colour
---  panel_name? = string,     -- explicit popup node name
---  brush_min? = integer,     -- min brush-size slider value in px. Default: 1
---  brush_max? = integer,     -- max brush-size slider value in px. Default: 64
---  world_pick? = boolean,    -- eyedropper also samples world colours off the
---                            --   canvas (see get_world_color). Default: true
--- }
---@return string panel_name The popup name, or "" if the image is not paintable.
function create_painting_panel(config) end

--- Resize an image to a specific pixel size.
--- This scales the image sprite to match the desired pixel dimensions.
---@param parent_name string Parent entity name.
---@param image_name string Image node name to resize.
---@param pixel_size? Vector2 Desired size in pixels. Default: Vector2(32, 32).
function set_image_pixel(parent_name, image_name, pixel_size) end

--- Set or create a text label on an entity.
--- Config parameters:
---   - parent_name (string, required): Parent entity name.
---   - name (string, optional): Label node name. Default: auto-generated.
---   - text (string, optional): Text content (use @key_6@ for input hints). Default: "".
---   - position (Vector2, optional): Position offset from parent. Default: Vector2(0, 0).
---   - size (Vector2, optional): Label size in pixels. Default: Vector2(128, 16).
---   - font_size (integer, optional): Font size in pixels. Default: 16.
---   - font_color (Color|string, optional): Text color. Default: Color(1, 1, 1, 1).
---   - outline_size (integer, optional): Outline thickness. Default: 0.
---   - outline_color (Color|string, optional): Outline color. Default: Color(0, 0, 0, 1).
---   - horizontal_alignment (integer, optional): 0=left, 1=center, 2=right. Default: 1.
---   - vertical_alignment (integer, optional): 0=top, 1=center, 2=bottom. Default: 1.
---   - modulate (Color|string, optional): Label color tint. Default: Color(1, 1, 1, 1).
---   - visible (boolean, optional): Visibility. Default: true.
---   - z_index (integer, optional): Rendering order (-999 to 999). Default: 0.
---   - anchor_left (number, optional): For UI labels, left anchor (0.0 to 1.0).
---   - anchor_right (number, optional): For UI labels, right anchor (0.0 to 1.0).
---   - anchor_top (number, optional): For UI labels, top anchor (0.0 to 1.0).
---   - anchor_bottom (number, optional): For UI labels, bottom anchor (0.0 to 1.0).
---   - rotation (number, optional): LOCAL-ONLY visual rotation in radians, around
---     the label's own centre. Never synced automatically — set it per peer.
---@param config table Label configuration dictionary.
---@return string The created/updated label node name.
function set_label(config) end

--- Set or create a progress bar on an entity.
--- Config parameters:
---   - parent_name (string, required): Parent entity name.
---   - name (string, optional): Progress bar node name. Default: auto-generated.
---   - position (Vector2, optional): Position offset from parent. Default: Vector2(0, 0).
---   - size (Vector2, optional): Bar size in pixels. Default: Vector2(128, 16).
---   - min_value (number, optional): Minimum value. Default: 0.0.
---   - max_value (number, optional): Maximum value. Default: 100.0.
---   - value (number, optional): Current value. Default: 0.0.
---   - step (number, optional): Step increment. Default: 1.0.
---   - fill_mode (integer, optional): 0=left to right, 1=right to left, 2=top to bottom, 3=bottom to top. Default: 0.
---   - show_percentage (boolean, optional): Show percentage text. Default: true.
---   - allow_greater (boolean, optional): Allow value to exceed max_value. Default: false.
---   - allow_lesser (boolean, optional): Allow value to go below min_value. Default: false.
---   - modulate (Color|string, optional): Bar color tint. Default: Color(1, 1, 1, 1).
---   - visible (boolean, optional): Visibility. Default: true.
---   - z_index (integer, optional): Rendering order (-999 to 999). Default: 0.
---   - anchor_left (number, optional): For UI progress bars, left anchor (0.0 to 1.0).
---   - anchor_right (number, optional): For UI progress bars, right anchor (0.0 to 1.0).
---   - anchor_top (number, optional): For UI progress bars, top anchor (0.0 to 1.0).
---   - anchor_bottom (number, optional): For UI progress bars, bottom anchor (0.0 to 1.0).
---@param config table Progress bar configuration dictionary.
---@return string The created/updated progress bar node name.
function set_progress_bar(config) end

--- Set or create a clickable button entity. When the button is pressed at runtime
--- it calls run_function(entity_name, function_name, parameters).
--- Config parameters:
---   - parent_name (string, optional): Parent entity name for placement. Default: world root.
---   - name (string, optional): Button node name. Default: auto-generated.
---   - text (string, optional): Button label text. Default: "".
---   - position (Vector2, optional): Position offset from parent. Default: Vector2(0, 0).
---   - size (Vector2, optional): Button size in pixels. Default: Vector2(128, 32).
---   - font_size (integer, optional): Font size in pixels. Default: theme default.
---   - modulate (Color|string, optional): Button color tint. Default: Color(1, 1, 1, 1).
---   - visible (boolean, optional): Visibility. Default: true.
---   - z_index (integer, optional): Rendering order (-999 to 999). Default: 0.
---   - entity_name (string, optional): Entity name passed to run_function when pressed.
---   - function_name (string, optional): Lua function name called via run_function when pressed.
---   - parameters (table, optional): Array of values passed to run_function when pressed. Default: {}.
---   - icon_path (string, optional): Relative path to a PNG inside the mod's general/images/ folder used as the button icon. Default: "".
---   - anchor_left (number, optional): For UI buttons, left anchor (0.0 to 1.0).
---   - anchor_right (number, optional): For UI buttons, right anchor (0.0 to 1.0).
---   - anchor_top (number, optional): For UI buttons, top anchor (0.0 to 1.0).
---   - anchor_bottom (number, optional): For UI buttons, bottom anchor (0.0 to 1.0).
---@param config table Button configuration dictionary.
---@return string The created/updated button node name.
function set_button(config) end

--- Apply a shader effect to an entity's image.
--- Additional shader parameters can be added to config and will be passed to the shader.
--- Config parameters:
---   - image_name (string, required): Target image/sprite node name.
---   - parent_name (string, required): Parent entity name.
---   - shader_name (string, optional): Shader file name (without .gdshader extension) from res://shaders/. If empty or omitted, removes the shader. Default: "".
---   - Additional shader-specific parameters can be added and will be passed to the shader as uniforms.
---@param config table Shader configuration dictionary.
function set_shader(config) end

---------------------------------------------------
-- ENTITY PHYSICS
---------------------------------------------------

--- Set collision shape for an entity.
--- Config parameters:
---   - parent_name (string, required): Parent entity name.
---   - name (string, optional): Collision node name. Default: auto-generated.
---   - shape (string, optional): Shape type: "circle" or "rectangle". Default: "circle".
---   - size (number|Vector2, optional): For circle: radius (number). For rectangle: size (Vector2). Default: 1.0 for circle, Vector2(1, 1) for rectangle.
---   - position (Vector2, optional): Position offset from parent. Default: Vector2(0, 0).
---   - disabled (boolean, optional): Whether collision is disabled. Default: false.
---   - collision_layer (integer|table, optional): Collision layer bitmask or array of layer numbers (1-32). Empty array means no collisions. Default: unchanged.
---   - collision_mask (integer|table, optional): Collision mask bitmask or array of layer numbers (1-32). Empty array means no collisions. Default: unchanged.
---@param config table Collision configuration dictionary.
---@return string The created/updated collision node name.
function set_collision(config) end

--- Set area shape for an entity (trigger zone).
--- Config parameters:
---   - parent_name (string, required): Parent entity name.
---   - name (string, optional): Area node name. Default: auto-generated.
---   - shape (string, optional): Shape type: "circle" or "rectangle". Default: "circle".
---   - size (number|Vector2, optional): For circle: radius (number). For rectangle: size (Vector2). Default: 1.0 for circle, Vector2(1, 1) for rectangle.
---   - position (Vector2, optional): Position offset from parent. Default: Vector2(0, 0).
---   - disabled (boolean, optional): Whether area is disabled. Default: false.
---   - collision_layer (integer|table, optional): Collision layer bitmask or array of layer numbers (1-32). Empty array means no collisions. Default: unchanged.
---   - collision_mask (integer|table, optional): Collision mask bitmask or array of layer numbers (1-32). Empty array means no collisions. Default: unchanged.
---@param config table Area configuration dictionary.
---@return string The created/updated area node name.
function set_area(config) end

--- Create a unique physics material for an entity (allows independent bounce/friction).
---@param entity_name string Target entity name.
---@param state? boolean True to create unique material, false to revert material. Default: true.
function set_unique_physics_material(entity_name, state) end

--- Add instant velocity to an entity.
---@param entity_name string Target entity name.
---@param velocity Vector2 Velocity to add.
function add_linear_velocity(entity_name, velocity) end

--- Get all entities currently overlapping with an entity's area.
---@param entity_name string Entity with area shape.
---@return table Array of overlapping entity names.
function get_overlapping_entities(entity_name) end

--- Move entity towards a target entity using simple following.
---@param entity_name string Entity to move.
---@param target_name? string Target entity name to follow. Default: "" (stop following).
---@param is_rotate? boolean Whether entity should rotate to face target. Default: true.
function go_to_target(entity_name, target_name, is_rotate) end

---------------------------------------------------
-- WORLD/PHYSICS SETTINGS
---------------------------------------------------

--- Set global gravity strength.
---@param gravity number Gravity value. Default: 980.
function set_gravity(gravity) end

--- Set global gravity direction.
---@param direction Vector2 Normalized direction vector. Default: Vector2(0, 1) for down.
function set_gravity_direction(direction) end

--- Set whether Area of Interest (network visibility culling) is enabled.
---@param enabled boolean True to enable AOI.
function set_aoi_enabled(enabled) end

--- Check if Area of Interest is currently enabled.
---@return boolean True if AOI is enabled.
function is_aoi_enabled() end

--- Set controller input type for display hints.
---@param controller_type number Controller type enum value.
function set_controller_type(controller_type) end

---------------------------------------------------
-- VISUAL EFFECTS
---------------------------------------------------

--- Set background color of the game world.
---@param color Color|table|string The background color. Can be Color, table [r,g,b,a], or String.
function set_background_color(color) end

--- Get current background color.
---@return Color The background color.
function get_background_color() end

--- Set a repeating "ground" texture drawn behind everything in world space (it
--- pans and zooms with the camera and tiles crisply at any zoom). Great for
--- making the walkable floor look like ground instead of a flat colour, without
--- placing tiles everywhere. Pass "" to clear it. This can also be set per-map in
--- the in-game editor's Tile Maps / map settings ("Background Texture").
---@param relative_path string Image path relative to the mod's general/images/ (no .png needed). "" clears it.
function set_background_texture(relative_path) end

--- Get the current background texture path (relative to general/images/), or "".
---@return string
function get_background_texture() end

--- Set vignette visual effect settings.
--- Config parameters:
---   - visible (boolean, optional): Enable/disable vignette effect. Default: false.
---   - smoothness (number, optional): Edge smoothness (0.0 to 1.0). Default: 0.3.
---   - strength (number, optional): Vignette strength/intensity. Default: 1.0.
---   - color (Color|table|string, optional): Vignette color. Can be Color, table [r,g,b,a], or String. Default: Color(0, 0, 0, 1).
---   - radius (number, optional): Vignette radius (0.0 to 1.0). Default: 0.5.
---@param config table Vignette configuration dictionary.
function set_vignette(config) end

--- Get current vignette settings.
---@return table Dictionary with keys: visible, smoothness, strength, color, radius.
function get_vignette_settings() end

--- Set the global tile-shadow effect (the same settings as the map editor's
--- "Shadow Effect Settings"). Great for day/night cycles: animate shadow_angle
--- to move the sun and shadow_color/visible for dusk and dawn.
--- Config parameters:
---   - visible (boolean, optional): Enable/disable the shadow effect.
---   - shadow_color (Color|table|string, optional): Shadow color (alpha = darkness).
---   - shadow_angle (number, optional): Light angle in degrees (0-360).
---   - shadow_length (number, optional): Shadow length in pixels.
---   - shadow_blur (number, optional): Shadow blur strength (0-10).
---@param config table Shadow configuration dictionary.
function set_shadow(config) end

--- Get current shadow effect settings.
---@return table Dictionary with keys: visible, shadow_color, shadow_angle, shadow_length, shadow_blur.
function get_shadow_settings() end

---------------------------------------------------
-- PARTICLES
---------------------------------------------------

--- Create a particle  (GPUParticles2D).
--- This creates a reusable particle  that can be instanced multiple times with start_particle().
--- Config parameters:
---   - particle_id (string, required): Unique identifier for this particle .
---   - texture_path (string, optional): Path to particle texture in mod/general/images/ (without .png extension). Default: "".
---   - lifetime (number, optional): Particle lifetime in seconds. Default: 1.0.
---   - amount (integer, optional): Number of particles to emit. Default: 50.
---   - explosiveness (number, optional): Emission explosiveness (0.0 to 1.0). Default: 0.0.
---   - randomness (number, optional): Emission randomness (0.0 to 1.0). Default: 0.0.
---   - one_shot (boolean, optional): Emit once or continuously. Default: true.
---   - local_coords (boolean, optional): Use local coordinates. Default: false.
---   - fixed_fps (integer, optional): Fixed FPS for particle simulation. Default: 30.
---   - fract_delta (boolean, optional): Use fractional delta. Default: true.
---   - direction (table, optional): Emission direction {x=number, y=number}. Default: none.
---   - spread (number, optional): Emission spread angle in degrees. Default: 0.0.
---   - initial_velocity_min (number, optional): Minimum initial velocity. Default: 0.0.
---   - initial_velocity_max (number, optional): Maximum initial velocity. Default: 1.0.
---   - angular_velocity_min (number, optional): Minimum angular velocity. Default: 0.0.
---   - angular_velocity_max (number, optional): Maximum angular velocity. Default: 0.0.
---   - gravity (table, optional): Gravity vector {x=number, y=number}. Default: none.
---   - scale_amount_min (number, optional): Minimum particle scale. Default: 1.0.
---   - scale_amount_max (number, optional): Maximum particle scale. Default: 1.0.
---   - angle_min (number, optional): Minimum particle angle. Default: 0.0.
---   - angle_max (number, optional): Maximum particle angle. Default: 0.0.
---   - color (Color, optional): Particle color. Default: Color.WHITE.
---   - color_random (boolean, optional): Use rainbow gradient colors. Default: false.
---   - hue_variation_min (number, optional): Minimum hue variation. Default: 0.0.
---   - hue_variation_max (number, optional): Maximum hue variation. Default: 0.0.
---   - particle_flag_align_y (boolean, optional): Align particles to Y axis. Default: false.
---
--- Note: All parameters are cached in the  and will be used for every instance created with start_particle().
---@param config table Particle configuration dictionary.
---@return string Particle  identifier (particle_id).
function create_particle(config) end

--- Start a particle instance.
--- Config parameters:
---   - particle_id (string, required): identifier created with create_particle().
---   - parent_name (string, optional): Entity to attach particle to. Default: "" (ParticleManager).
---   - position (Vector2, optional): Particle position. Default: Vector2(0, 0).
---   - rotation (number, optional): Particle rotation in radians. Default: 0.0.
---   - instance_name (string, optional): Unique name for this instance. Default: auto-generated.
---@param config table Start particle configuration dictionary.
---@return string Instance name, or "" on error.
function start_particle(config) end

--- Stop a particle instance.
---@param instance_name string Particle instance name returned by start_particle().
---@return boolean True if stopped successfully.
function stop_particle(instance_name) end

--- Get particle instance data/state.
---@param instance_name string Particle instance name.
---@return table|nil Dictionary with keys: particle_id, start_time, emitting, lifetime, amount, position_x, position_y, rotation. Returns nil if not found.
function get_particle_data(instance_name) end

--- Clean up all particle instances attached to an entity.
---@param entity_name string Entity that owns particles.
function cleanup_entity_particles(entity_name) end

--- Get count of active particle instances.
---@return number Active particle instance count.
function get_active_particle_count() end

--- Get count of cached particle .
---@return number Cached count.
function get_cached_particle_count() end

---------------------------------------------------
-- DRAWING SHAPES (LINES)
---------------------------------------------------

--- Draw or update a line shape (Line2D).
--- Config parameters:
---   - name (string, required): Line identifier.
---   - points (table, optional): Array of Vector2 positions defining the line path. If not provided, can use start_position and end_position.
---   - start_position (Vector2, optional): Starting point (for simple 2-point lines). Used with end_position.
---   - end_position (Vector2, optional): Ending point (for simple 2-point lines). Used with start_position.
---   - color (Color, optional): Line color. Default: Color.WHITE.
---   - width (number, optional): Line width in pixels. Default: 2.0.
---   - z_index (integer, optional): Rendering order (-999 to 999). Default: 100.
---@param config table Line configuration dictionary.
---@return string Line identifier (name).
function set_line(config) end

--- Remove a line shape.
---@param line_name string Line identifier.
---@return boolean True if line was destroyed.
function destroy_line(line_name) end

--- Remove all line shapes.
function destroy_all_lines() end

--- Check if a line exists.
---@param line_name string Line identifier.
---@return boolean True if line exists.
function line_exists(line_name) end

--- Update the points of an existing line (simple 2-point version).
---@param line_name string Line identifier.
---@param start_pos Vector2 Starting position.
---@param end_pos Vector2 Ending position.
---@return boolean True if updated successfully.
function update_line_points(line_name, start_pos, end_pos) end

---------------------------------------------------
-- CAMERA CONTROL
---------------------------------------------------

--- Set camera to follow a specific entity.
---@param entity_name string Entity for camera to track.
function set_camera_target(entity_name) end

--- Set camera zoom level.
---@param zoom Vector2 Zoom factor (e.g., Vector2(2, 2) for 2x zoom).
function set_camera_zoom(zoom) end

--- Set camera position directly.
---@param position Vector2 Camera world position.
function set_camera_position(position) end

--- Rotate the camera view (radians). Useful for tabletop mods: rotate each
--- player's camera toward their seat so the table center stays "up" for them.
--- Screen-space UI (hand bar, panels) is not affected.
---@param radians number Camera rotation in radians.
function set_camera_rotation(radians) end

--- Get the current camera rotation in radians.
---@return number Camera rotation in radians.
function get_camera_rotation() end

--- Create screen shake effect.
---@param intensity number Shake strength.
---@param duration number Shake duration in seconds.
function screenshake(intensity, duration) end

---------------------------------------------------
-- CARD SYSTEM (tabletop decks, hands, table cards)
---------------------------------------------------
-- Definitions (what cards look like) are loaded on EVERY peer from your mod's
-- own files/data. Shared state (deck order, hands, table) is HOST-authoritative:
-- deck order exists only on the host, and a card's identity is only sent to the
-- peers allowed to know it (per-deck "visibility" policy), so clients cannot
-- cheat by sniffing packets. Clients never mutate state directly - send an
-- intent with run_network_function("..._HOST"), validate on the host, then call
-- the card_* functions there.
--
-- Listener callbacks (define on the entity you pass to card_set_listener; all
-- optional, all run on every peer unless noted):
--   _on_cards_loaded(set_id)                      -- definitions ready (textures rendered)
--   _on_deck_clicked(deck_name)                   -- LOCAL click on a deck
--   _on_hand_card_clicked(uid, card_id)           -- LOCAL tap on your hand bar
--   _on_hand_card_dropped(uid, card_id)           -- LOCAL drag of a hand card onto the drop zone
--   _on_table_card_clicked(uid, card_id)          -- LOCAL click on a table card ("" if hidden)
--   _on_card_drawn(owner_steam_id, deck_name, uid)
--   _on_card_played(owner_steam_id, uid, card_id) -- card_id "" if hidden from you
--   _on_card_flipped(uid, face_up, card_id)
--   _on_card_transferred(from_steam_id, to_steam_id, uid)
--   _on_card_returned(uid, deck_name)
--   _on_card_removed(uid)
--   _on_deck_shuffled(deck_name, count)
--   _on_card_peek(deck_name, ids)                 -- only on the peeking peer
--   _on_player_left_cards(steam_id, uids)         -- HOST only, before cleanup

--- Load a card set JSON exported by the online image editor's Card tool.
--- The path is relative to your mod folder and sandboxed (no "..").
---@param relative_path string e.g. "cards/my_set.cards.json"
---@return string Set id ("" on failure).
function load_cards_from_json(relative_path) end

--- Load a card set from a JSON string (e.g. assembled at runtime).
---@param json_string string The card set JSON text.
---@param set_id string|nil Optional set id override.
---@return string Set id ("" on failure).
function load_cards_from_json_data(json_string, set_id) end

--- Load a card set from a Lua table using the same structure as the JSON
--- format (kind="cards", card_w, card_h, cards={...} etc.). The easiest way
--- to generate decks procedurally.
---@param data table Card set table.
---@param set_id string|nil Optional set id override.
---@return string Set id ("" on failure).
function load_cards_from_data(data, set_id) end

--- Build a card set from a pre-rendered PNG sprite sheet in your mod. Unlike
--- load_cards_from_json/from_data (which render live, so the shadow gets
--- baked in at load and the text can react to language changes), a PNG sheet
--- is a flat image prepared ahead of time — export it from the online image
--- editor's Card tool with the shadow you want already in the pixels.
---
--- Localization for PNG sheets works by FILE NAME (same convention as the
--- image_localizer tool): given front_sheet = "cards.png", this also looks for
--- a sibling "cards_<lang>.png" matching the engine's current locale (e.g.
--- "cards_tr.png" for Turkish, "cards_en.png" for English) and uses it when
--- present; with no matching file it silently falls back to "cards.png".
--- back_image is looked up the same way.
--- Config parameters:
---   - set_id (string, required): Unique set id.
---   - front_sheet (string, required): Sheet path under general/images/ (e.g. "cards.png").
---   - cols, rows (integer, required): Grid layout of the sheet.
---   - count (integer, optional): How many cells are real cards. Default: cols*rows.
---   - back_image (string, optional): Back face image path. Default: flat red.
---   - ids (table, optional): Array of card ids, one per cell. Default: "<set>_1"...
---   - keywords (table, optional): {card_id = {key = value}} keyword map.
---@param config table Sheet configuration.
---@return string Set id ("" on failure).
function load_cards_from_png(config) end

--- Read a keyword value of a card. Checks the card's explicit keywords first,
--- then layout cells whose "keyword" field matches (their text/icon/source is
--- returned). E.g. get_card_keyword("red_7", "power") -> 7.
---@param card_id string Card id.
---@param key string Keyword name.
---@return any Value, or nil when the card/keyword does not exist.
function get_card_keyword(card_id, key) end

--- Get basic info about a card definition.
---@param card_id string Card id.
---@return table {id, name, set_id, keywords} (empty table when unknown).
function get_card_info(card_id) end

--- List loaded card ids (of one set, or all sets).
---@param set_id string|nil Optional set filter.
---@return table Sorted array of card ids.
function get_card_ids(set_id) end

--- Check whether a card id is loaded.
---@param card_id string Card id.
---@return boolean True when the card definition exists.
function is_card(card_id) end

--- HOST ONLY: create a deck of cards at a world position.
--- Config parameters:
---   - name (string, required): Deck identifier.
---   - position (Vector2, required): World position of the deck.
---   - cards (table, required): Array of card ids (duplicates allowed; index 1 = top).
---   - size (Vector2, optional): On-table card size in world units. Default: Vector2(90, 126).
---   - visibility (string, optional): Who learns a drawn card's identity:
---       "owner" (only the drawer - default), "all" (everyone), "none" (nobody).
---   - show_count (boolean, optional): Show the remaining-card counter. Default: true.
---@param config table Deck configuration.
---@return boolean True on success.
function card_create_deck(config) end

--- HOST ONLY: remove a deck (cards already drawn stay in play).
---@param deck_name string Deck identifier.
function card_destroy_deck(deck_name) end

--- HOST ONLY: shuffle a deck. Pass a seed for a reproducible order; omit (or 0)
--- for a random shuffle.
---@param deck_name string Deck identifier.
---@param seed integer|nil Optional RNG seed.
function card_shuffle(deck_name, seed) end

--- Number of cards left in a deck (works on every peer).
---@param deck_name string Deck identifier.
---@return integer Remaining cards.
function card_deck_count(deck_name) end

--- Whether a deck exists (works on every peer).
---@param deck_name string Deck identifier.
---@return boolean
function card_deck_exists(deck_name) end

--- HOST ONLY: deal the top card of a deck to a player's hand. Everyone sees a
--- card-back fly from the deck to that player; only the allowed peers learn
--- which card it is.
---@param deck_name string Deck identifier.
---@param target_steam_id string Receiving player's Steam id string.
---@return string The card's uid ("" when the deck is empty).
function card_draw(deck_name, target_steam_id) end

--- HOST ONLY: privately show the top N card ids of a deck to one player
--- (See-the-Future style). Fires _on_card_peek(deck_name, ids) on that peer.
---@param deck_name string Deck identifier.
---@param count integer How many cards from the top.
---@param target_steam_id string Peeking player's Steam id string.
function card_peek(deck_name, count, target_steam_id) end

--- HOST ONLY: put a card (from a hand or the table) back into a deck.
---@param uid string Card uid.
---@param deck_name string Deck identifier.
---@param index integer|nil 0 = top (default), big = bottom, negative = random spot.
---@return boolean True on success.
function card_return_to_deck(uid, deck_name, index) end

--- HOST ONLY: play a card from a hand onto the table. face_up=true reveals the
--- card to EVERYONE (that is what playing openly means); face_down keeps it
--- hidden. The card animates from the owner's anchor to the position.
---@param uid string Card uid.
---@param position Vector2 World position on the table.
---@param face_up boolean|nil Default: true.
---@return boolean True on success.
function card_play(uid, position, face_up) end

--- HOST ONLY: slide a table card to a new position.
---@param uid string Card uid.
---@param position Vector2 Target world position.
---@param duration number|nil Tween seconds. Default: 0.3.
function card_move(uid, position, duration) end

--- HOST ONLY: flip a table card. Turning it face up reveals it to everyone.
---@param uid string Card uid.
---@param face_up boolean New facing.
function card_flip(uid, face_up) end

--- HOST ONLY: move a card between hands ("" uid = random card of the giver -
--- blind steal). The receiver always learns what they got; others only see the
--- movement.
---@param uid string Card uid or "" for random.
---@param from_steam_id string Giving player.
---@param to_steam_id string Receiving player.
---@return string The moved uid ("" on failure).
function card_transfer(uid, from_steam_id, to_steam_id) end

--- HOST ONLY: remove a card from the game (from a hand or the table).
---@param uid string Card uid.
function card_discard(uid) end

--- HOST ONLY: clear all decks, hands and table cards (e.g. between rounds).
function card_destroy_all() end

--- Get a player's hand. Your own (or revealed) cards include card_id; other
--- players' cards come back with card_id = "". On the host, card_id is always
--- filled - use that to validate the rules server-side.
---@param steam_id string Player's Steam id string.
---@return table Array of {uid = string, card_id = string}.
function card_get_hand(steam_id) end

--- Number of cards in a player's hand (works on every peer).
---@param steam_id string Player's Steam id string.
---@return integer
function card_hand_count(steam_id) end

--- Hand sizes of every player: {steam_id_string = count}.
---@return table
function card_hand_counts() end

--- Uids of every card currently on the table (sorted).
---@return table Array of uid strings.
function card_table_cards() end

--- Info about one card instance.
---@param uid string Card uid.
---@return table {uid, card_id ("" if hidden from you), owner, on_table, face_up, position} or {}.
function card_uid_info(uid) end

--- Choose which entity's Lua script receives the _on_card_* callbacks on this
--- peer (usually your world singleton). Call it on every peer.
---@param entity_name string Listener entity name (e.g. "-w").
function card_set_listener(entity_name) end

--- Set where a player's cards animate from/to in world space (their seat).
--- Call on every peer for every seated player.
---@param steam_id string Player's Steam id string.
---@param world_pos Vector2 Anchor position.
function card_set_player_anchor(steam_id, world_pos) end

--- Configure the local bottom-of-screen hand bar. The hand stays centred at the
--- bottom, may spill to the right and wrap into extra rows above, but never
--- crosses into the left chat strip. Every card is always shown.
--- Config parameters (all optional):
---   - visible (boolean): Show/hide the hand bar. Default: true.
---   - height (number): Card height in screen pixels (40-400). Default: 150.
---   - bottom (number): Distance from the bottom edge. Default: 14.
---   - separation (integer): Pixel gap between cards (negative = overlap). Default: -34.
---   - left_clear (number): Fraction of the screen kept clear on the left (chat). Default: 0.30.
---   - right_clear (number): Fraction kept clear on the right. Default: 0.01.
---@param config table Hand bar configuration.
function card_set_hand_ui(config) end

--- LOCAL ONLY: counter-rotate every card/deck/hand-fan node so they stay
--- upright for THIS peer while the camera itself sits rotated (per-seat
--- tabletop view). Pass the SAME angle you give set_camera_rotation — position
--- is the only thing that ever travels the network; rotation is always local.
---@param radians number Local counter-rotation in radians (usually = your camera's rotation).
function card_set_world_rotation(radians) end

--- Define where a DRAGGED hand card counts as "played". Drop a dragged card
--- within `radius` world units of `world_pos` and the engine fires
--- _on_hand_card_dropped(uid, card_id); drop it anywhere else and it snaps back
--- to the hand. Pass radius <= 0 to accept a drop anywhere. Tapping a card still
--- fires _on_hand_card_clicked regardless.
---@param world_pos Vector2 Centre of the play/drop area in world space.
---@param radius number Accept radius in world units (<= 0 = anywhere).
function card_set_drop_zone(world_pos, radius) end

---------------------------------------------------
-- VISUAL NOVEL / BRANCHING STORY (VNStory format)
---------------------------------------------------
-- Runtime for stories authored in the Online Asset Editor's Visual Novel tab
-- (or built by hand as a table). The engine is DETERMINISTIC AND LOCAL: each
-- peer loads the same story file and advances its OWN copy with explicit
-- calls. It never networks story state for you — a multiplayer mod stays
-- host-authoritative the usual way (clients send an intent with
-- run_network_function("..._HOST"), the host validates + broadcasts the
-- winning choice id with "..._ALL", every peer runs the SAME vn_choose()).
--
-- Presentation is entirely up to the mod. Node/choice `bg`, `sound` and a
-- character mood `image` are opaque path strings for you to feed to
-- set_image / set_audio; choices carry their id + tags so you can attach any
-- effect in Lua. Conditions/variables are evaluated by the engine exactly the
-- way the editor's Preview does.
--
-- A NODE table (returned by vn_start / vn_current / vn_advance / vn_choose /
-- vn_goto / vn_node_info) has:
--   id (string), char (string, "" = narrator), char_name (string),
--   char_color (string "(r,g,b,a)"), mood (string), image (string mood image
--   path), text (string), bg (string), sound (string), tags (string[]),
--   next (string), has_choices (bool), is_end (bool).
-- A CHOICE table (from vn_choices / _on_vn_choice) has:
--   index (int, 1-based), id (string), text (string), tags (string[]),
--   next (string), enabled (bool), hidden (bool).

--- Load a story JSON exported by the Visual Novel editor from the mod folder
--- (path relative to the mod root, no ".."). Call once, e.g. in world.lua.
---@param relative_path string Path to the story .json inside the mod folder.
---@return string Story id (the file's base name), or "" on failure.
function vn_load(relative_path) end

--- Load a story straight from a Lua table (same shape as the exported JSON).
---@param data table Story table (kind="vn", start, vars, chars, nodes).
---@param story_id? string Optional id to register it under. Default: auto.
---@return string Story id, or "" on failure.
function vn_load_data(data, story_id) end

--- Choose which entity's Lua script receives the story callbacks on this peer:
---   _on_vn_node(story_id, node)              -- a node was entered
---   _on_vn_choice(story_id, node_id, choice) -- a choice was accepted
---   _on_vn_end(story_id, node_id)            -- the story reached an end
---@param entity_name string Entity whose script defines the _on_vn_* callbacks.
function vn_set_listener(entity_name) end

--- (Re)start a story: variables reset to their defaults and the entry node is
--- entered (its on-enter variable operations apply, callbacks fire).
---@param story_id string Story id from vn_load.
---@param node_id? string Optional start node override. Default: story start.
---@return table The entered node table (see above), or {} on failure.
function vn_start(story_id, node_id) end

--- Get the current node table without changing anything.
---@param story_id string Story id.
---@return table Current node table, or {} if none is active.
function vn_current(story_id) end

--- Current node's choices with conditions evaluated against the story
--- variables. Disabled choices come back enabled=false; SECRET failing choices
--- (hidden=true) are omitted. Empty = linear node (use vn_advance) or an end.
---@param story_id string Story id.
---@return table Array of choice tables (see above).
function vn_choices(story_id) end

--- Follow the current node's linear "next" link.
---@param story_id string Story id.
---@return table The entered node table, or {} if the node has choices / ended.
function vn_advance(story_id) end

--- Pick a choice of the current node BY ID. Rejected (returns {}) if that
--- choice's conditions currently fail. On success the choice's variable
--- operations apply, _on_vn_choice fires, and the target node is entered.
---@param story_id string Story id.
---@param choice_id string The choice's id (from vn_choices).
---@return table The entered node table, or {} if the choice was not allowed.
function vn_choose(story_id, choice_id) end

--- Jump to any node. With apply_enter_ops=true (default) it enters normally:
--- the node's on-enter variable operations apply and _on_vn_node fires (chapter
--- select / debug). With apply_enter_ops=false it is a PURE SEEK (set the
--- current node without applying ops or firing the callback) — use it for
--- late-joiner sync: vn_set_var the shared variables first, then seek + render.
---@param story_id string Story id.
---@param node_id string Target node id.
---@param apply_enter_ops? boolean Apply the node's on-enter ops + fire callback. Default: true.
---@return table The node table, or {} on failure.
function vn_goto(story_id, node_id, apply_enter_ops) end

--- True when the story has ended (no current node, or the node has neither
--- choices nor a next link).
---@param story_id string Story id.
---@return boolean
function vn_is_end(story_id) end

--- Read a story variable's current value (number, boolean or string).
---@param story_id string Story id.
---@param var_name string Variable name.
---@return any The value, or nil if the story/variable is unknown.
function vn_get_var(story_id, var_name) end

--- Set a story variable directly (bypasses node/choice operations). In
--- multiplayer you must call this identically on every peer.
---@param story_id string Story id.
---@param var_name string Variable name.
---@param value any New value (number, boolean or string).
function vn_set_var(story_id, var_name, value) end

--- Get a copy of ALL current story variables as a table.
---@param story_id string Story id.
---@return table {var_name = value, ...}.
function vn_get_vars(story_id) end

--- Inspect ANY node without entering it. Includes its raw `choices` array (with
--- their conditions) for building custom visualizations in Lua.
---@param story_id string Story id.
---@param node_id string Node id.
---@return table Node table plus a `choices` array, or {} if unknown.
function vn_node_info(story_id, node_id) end

--- All node ids of a loaded story, sorted (deterministic across peers).
---@param story_id string Story id.
---@return table Array of node id strings.
function vn_node_ids(story_id) end

--- Callback: a story node was entered (via vn_start/advance/choose/goto).
---@param story_id string Story id.
---@param node table The entered node table.
function _on_vn_node(story_id, node) end

--- Callback: a choice was accepted, fired BEFORE its target node is entered.
---@param story_id string Story id.
---@param node_id string The node the choice belonged to.
---@param choice table The chosen choice table.
function _on_vn_choice(story_id, node_id, choice) end

--- Callback: the story reached an end (an end node, or an empty "next").
---@param story_id string Story id.
---@param node_id string The last node id ("" if it ran off a dangling link).
function _on_vn_end(story_id, node_id) end

--- Set a navigation icon marker on an entity.
--- This creates an off-screen indicator that points to the target entity when it's outside the viewport.
--- Config parameters:
---   - target_name (string, required): Target entity name to track.
---   - name (string, optional): Indicator identifier. Default: auto-generated.
---   - image_path (string, optional): Path to icon image in mod/general/images/ (without .png extension). If empty, uses default arrow. Default: "".
---   - text (string, optional): Label text to display next to the icon. Default: "".
---   - color (Color, optional): Icon color tint. Default: Color.WHITE.
---   - is_rotate (boolean, optional): Whether icon rotates to point at target. Default: true.
---   - is_show_distance (boolean, optional): Show distance to target in label. Default: false.
---   - font_size (integer, optional): Label font size. Default: system default.
---   - font_color (Color|string, optional): Label text color. Default: system default.
---   - outline_color (Color|string, optional): Label outline color. Default: system default.
---   - outline_size (integer, optional): Label outline thickness. Default: system default.
---@param config table Navigation icon configuration dictionary.
---@return string Indicator identifier (name).
function set_navigation_icon(config) end

---------------------------------------------------
-- UI PANELS & POPUPS
---------------------------------------------------

--- Create a custom UI panel (CustomPanel/Window).
--- Config parameters:
---   - name (string, optional): Panel identifier. Default: auto-generated.
---   - title (string, optional): Panel title text. Default: "Alert!".
---   - text (string, optional): Panel body text (supports BBCode). Default: "".
---   - resizable (boolean, optional): Allow resizing. Default: true.
---   - close (boolean, optional): Show close button. Default: true.
---   - set_time (boolean, optional): Add timestamp to title. Default: true.
---   - offset_ratio (Vector2, optional): Position offset ratio for centering. Default: Vector2(1, 1).
---   - fade (number, optional): Fade animation duration. Default: 0.0.
---   - countdown (number, optional): Auto-close countdown in seconds. Shows countdown in title. Default: 0.0.
---   - selection_enabled (boolean, optional): Allow text selection in body. Default: true.
---   - no_multiple_tag (string, optional): Tag to prevent multiple panels with same tag from existing simultaneously. Default: "".
---   - dont_show_again_tag (string, optional): Tag for "don't show again" checkbox. Persists to user config file. Default: "".
---   - is_scrollable (boolean, optional): Enable scrolling for content. Wraps content in ScrollContainer. Default: false.
---   - minimum_size (Vector2, optional): Minimum panel size in pixels. Default: Vector2(300, 150).
---   - color (Color, optional): Panel background color with transparency. Default: Color(0.2, 0.2, 0.2, 0.9).
---
---
---@param config table|string Panel configuration dictionary, or string for simple message.
---@return string Panel identifier (name), or "dontshowagain" if blocked.
function create_panel(config) end

--- Add a button to a panel.
--- The callback function receives a dictionary with all button data.
--- Config parameters:
---   - entity_name (string, required): Entity that has the callback function.
---   - function_name (string, required): Function name to call when clicked.
---   - text (string, optional): Button label text. Default: "".
---   - extra_args (table, optional): Additional data to pass to callback. Default: {}.
---   - is_vertical (boolean, optional): Add button to vertical layout instead of horizontal row. Default: true.
---   - color (Color, optional): Button background color. Also affects hover, pressed, disabled, and focus states automatically. Default: Color(0.439, 0.502, 0.565).
---   - icon_path (string, optional): Path to button icon image (without extension). Default: "".
---   - icon_alignment (integer, optional): Icon position relative to text. 0=LEFT, 1=CENTER, 2=RIGHT. Default: 0 (LEFT).
---   - expand_icon (boolean, optional): Whether icon should expand to fit button size. Default: true.
---
---@param panel_name string Target panel name.
---@param config table Button configuration dictionary.
function add_button_to_panel(panel_name, config) end

--- Add a text input field to a panel.
--- The callback function receives a dictionary with input value and all config data.
--- The callback is triggered on every text change (each keystroke).
--- Config parameters:
---   - entity_name (string, required): Entity that has the callback function.
---   - function_name (string, required): Function name to call on text change.
---   - text (string, optional): Label text and placeholder text for the input field. Default: "".
---   - default_value (string, optional): Initial text value in the input field. Default: "".
---   - extra_args (table, optional): Additional data to pass to callback. Default: {}.
---@param panel_name string Target panel name.
---@param config table Input configuration dictionary.
function add_input_to_panel(panel_name, config) end

--- Add a checkbox to a panel.
--- The callback function receives a dictionary with checked state and all config data.
--- Config parameters:
---   - entity_name (string, required): Entity that has the callback function.
---   - function_name (string, required): Function name to call when checkbox is toggled.
---   - text (string, optional): Checkbox label text. Default: "".
---   - default_value (boolean, optional): Initial checked state. Default: false.
---   - extra_args (table, optional): Additional data to pass to callback. Default: {}.
---@param panel_name string Target panel name.
---@param config table Checkbox configuration dictionary.
function add_checkbox_to_panel(panel_name, config) end

--- Add a dropdown/option box to a panel.
--- The callback function receives a dictionary with selected option and all config data.
--- Config parameters:
---   - entity_name (string, required): Entity that has the callback function.
---   - function_name (string, required): Function name to call when an option is selected.
---   - text (string, optional): Label text next to the dropdown. Default: "".
---   - options (table, required): Array of option strings to display in the dropdown.
---   - extra_args (table, optional): Additional data to pass to callback. Default: {}.
---@param panel_name string Target panel name.
---@param config table Optionbox configuration dictionary.
function add_optionbox_to_panel(panel_name, config) end

--- Add a custom styled button to a panel.
--- Creates a customizable button container that can have labels and images added to it.
--- Config parameters:
---   - text (string, optional): Button text. Default: "".
---   - entity_name (string, optional): Entity with callback function. Used with function_name.
---   - function_name (string, optional): Function to call when clicked. Used with entity_name.
---   - extra_args (table, optional): Additional data to pass to callback. Default: {}.
---   - is_vertical (boolean, optional): Add button to vertical layout instead of horizontal row. Default: true.
---   - size (Vector2, optional): Custom minimum button size in pixels. Default: depends on content.
---   - color (Color, optional): Button background color. Also affects hover, pressed, disabled, and focus states automatically. Default: Color(0.439, 0.502, 0.565).
---   - icon_path (string, optional): Path to button icon image. Can be "res://" path or mod relative path (auto-adds .png). Default: "".
---   - drag_data (table, optional): Data to attach for drag operations. Makes button draggable. Default: nil (not draggable).
---   - on_drop_function (string, optional): Lua function name to call when another button is dropped on this button. Makes button droppable. Default: "" (not droppable).
---     The drop callback receives a dictionary with: position, data, target_button_name, dragged_button_name, panel_name, extra_args.
---
---@param panel_name string Target panel name.
---@param config table Custom button configuration dictionary.
---@return string Custom button path/identifier.
function add_custom_button_to_panel(panel_name, config) end

--- Add a label to a custom button.
--- Config parameters:
---   - text (string, required): Label text content.
---   - font_size (integer, optional): Font size in pixels. Default: system default.
---   - font_color (Color|string, optional): Text color. Default: system default.
---   - outline_color (Color|string, optional): Text outline color. Default: system default.
---   - outline_size (integer, optional): Text outline thickness in pixels. Default: 0.
---   - horizontal_alignment (integer, optional): Text horizontal alignment. 0=left, 1=center, 2=right. Default: 1 (center), auto-adjusted based on offset_ratio.
---   - vertical_alignment (integer, optional): Text vertical alignment. 0=top, 1=center, 2=bottom. Default: 1 (center), auto-adjusted based on offset_ratio.
---   - offset_ratio (Vector2, optional): Position within button as ratio (0-2 range, 1=center). Default: Vector2(1, 1) (centered).
---     Examples: Vector2(0, 0)=top-left, Vector2(1, 1)=center, Vector2(2, 2)=bottom-right, Vector2(0, 2)=bottom-left, Vector2(2, 0)=top-right.
---   - size (Vector2, optional): Custom minimum size for label in pixels. Default: fills button (SIZE_FILL flags set).
---   - modulate (Color|string, optional): Label color tint/transparency multiplier. Default: Color(1, 1, 1, 1) (no tint, fully opaque).
---   - visible (boolean, optional): Label visibility state. Default: true.
---   - label_name (string, optional): Custom name for the label node. Default: auto-generated.
---
---
---@param custom_button_path string Path/identifier of the custom button returned by add_custom_button_to_panel().
---@param settings table Label configuration dictionary.
---@return string Label identifier.
function add_label_to_custom_button(custom_button_path, settings) end

--- Add an image to a custom button.
--- Config parameters:
---   - image_path (string, required): Path to image in mod/general/images/ (without .png extension).
---   - size (Vector2, optional): Image size in pixels. Default: texture's original size, or Vector2(32, 32) if no texture.
---   - offset_ratio (Vector2, optional): Position within button as ratio (0-2 range, 1=center). Default: Vector2(1, 1) (centered).
---     Examples: Vector2(0, 0)=top-left, Vector2(1, 1)=center, Vector2(2, 2)=bottom-right, Vector2(0, 2)=bottom-left, Vector2(2, 0)=top-right.
---   - stretch_mode (integer, optional): Texture stretch mode. 0=SCALE, 1=TILE, 2=KEEP, 3=KEEP_CENTERED, 4=KEEP_ASPECT, 5=KEEP_ASPECT_CENTERED, 6=KEEP_ASPECT_COVERED. Default: 0 (SCALE).
---   - flip_h (boolean, optional): Flip image horizontally. Default: false.
---   - flip_v (boolean, optional): Flip image vertically. Default: false.
---   - modulate (Color|string, optional): Image color tint/transparency multiplier. Default: Color(1, 1, 1, 1) (no tint, fully opaque).
---   - visible (boolean, optional): Image visibility state. Default: true.
---   - image_name (string, optional): Custom name for the image node. Default: auto-generated.
---
---
---@param custom_button_path string Path/identifier of the custom button returned by add_custom_button_to_panel().
---@param settings table Image configuration dictionary.
---@return string Image identifier.
function add_image_to_custom_button(custom_button_path, settings) end

--- Swap positions of two custom buttons in a panel.
--- Buttons can be in the same or different panels.
---@param button_path_1 string First button path/identifier (full path from add_custom_button_to_panel).
---@param button_path_2 string Second button path/identifier (full path from add_custom_button_to_panel).
---@return table Dictionary with keys: "dragged_name", "target_name", "new_dragged_name", "new_target_name". Returns empty table {} on error.
function swap_custom_buttons(button_path_1, button_path_2) end

--- Close a specific panel.
---@param panel_name string Panel identifier to close.
function close_panel(panel_name) end

--- Close all open panels.
function close_all_panels() end

--- Check if a panel exists and is open.
---@param panel_name string Panel identifier.
---@return boolean True if panel exists.
function is_panel_exists(panel_name) end

--- Update panel settings after creation.
--- Can update various panel properties like title, position, size, scrollable state, etc.
--- Settings parameters:
---   - text (string, optional): Update panel body text.
---   - title (string, optional): Update panel title text.
---   - offset_ratio (Vector2, optional): Update panel position offset ratio.
---   - resizable (boolean, optional): Update panel resizable state.
---   - minimum_size (Vector2, optional): Update minimum panel size.
---   - time (boolean, optional): If true, appends current time to title (requires 'title' key or uses existing title).
---   - is_scrollable (boolean, optional): Convert between scrollable and non-scrollable layout.
---     WARNING: Changing is_scrollable reconstructs the panel's internal structure while preserving all content nodes.
---
---@param panel_name string Panel identifier.
---@param settings table Dictionary of settings to update (same keys as create_panel config).
function update_panel_settings(panel_name, settings) end

--- Display a table/grid in a panel.
--- Creates a GridContainer with clickable cells as buttons.
--- Config parameters:
---   - name (string, optional): Table identifier. If specified and table exists, replaces it. Default: auto-generated (16 character random string).
---   - table_data (table, required): Dictionary mapping position strings to cell data. Keys are "(x,y)" strings, values are cell config dictionaries.
---     Cell config can include:
---       - text (string, optional): Cell button text content. Default: "".
---       - color (Color|string, required): Cell button background color (also affects hover/pressed states).
---       - Any other metadata: Custom key-value pairs will be stored in the button's metadata (accessible via get_meta()).
---   - entity_name (string, optional): Entity with callback function for cell clicks. Required if using function_name.
---   - function_name (string, optional): Function to call when a cell is clicked. Required if using entity_name.
---     Callback receives: {string_cell_position, cell_position, cell_data, extra_args, table_data, panel_name (if available)}.
---   - extra_args (table, optional): Additional data to pass to callback. Default: {}.
---
---@param panel_name string Target panel name.
---@param config table Table configuration dictionary.
---@return string Table identifier (name).
function set_table(panel_name, config) end

---------------------------------------------------
-- VIEW SYSTEM (PREDEFINED UI LAYOUTS)
---------------------------------------------------

--- Add a UI panel to the view system.
---@param config table Panel configuration for view.
function add_panel(config) end

--- Add text element to a view panel.
---@param config table Text configuration with panel_name, text, position, etc.
function add_text_to_panel(config) end

--- Add image element to a view panel.
---@param config table Image configuration with panel_name, image_path, position, size, etc.
function add_image_to_panel(config) end

--- Switch to a different predefined view.
---@param view_name string Name of the view to activate.
function change_view(view_name) end

--- Get list of available views.
---@return table Array of view names.
function get_view_list() end

---------------------------------------------------
-- CHAT & SOCIAL
---------------------------------------------------

--- Send a message to the in-game chat.
---@param message string Message text (supports BBCode formatting).
---@param send_to_server? boolean Whether to broadcast to all players. Default: false.
function add_to_chat(message, send_to_server) end

--- Register a centralized command for chat and debug console.
--- Commands registered here are automatically handled by the system.
---
--- **WARNING:** `add_command` cannot execute network functions directly via `run_network_function`.
--- If you need to trigger network logic from a command, use a local intermediate (wrapper)
--- function as the callback, and call `run_network_function` from within that wrapper.
---
--- ```lua
--- add_command("-my_entity", "my_callback", "greet", "Greets the server", true)
--- -- Players can type "/greet HELLOOO" in chat or greet in console.
---
--- function my_callback(arg1)
---     print(arg1.." World") -- Prints "HELLOOO World"
--- end
--- ```
---
---@param lua_entity_name string The name of the entity containing the callback function (e.g., "-my_entity").
---@param lua_function_name string The name of the function to be called when the command is executed.
---@param command_name string The command trigger name WITHOUT the '/' prefix (e.g., "rules").
---@param description string Description shown in the /help list.
---@param chat_executable boolean If true, the command can be used in chat with '/' prefix. Always works in console.
function add_command(lua_entity_name, lua_function_name, command_name, description, chat_executable) end

--- Open Steam profile overlay for a user.
---@param steam_id string Target user's Steam ID.
function open_profile(steam_id) end

---------------------------------------------------
-- AUDIO & SOUND
---------------------------------------------------

--- Play or configure audio (AudioStreamPlayer or AudioStreamPlayer2D).
--- Config parameters:
---   - stream_path (string, optional): Path to audio file in mod/general/sounds/ (without .ogg extension). Required if 'stream' is not provided.
---   - stream (AudioStream, optional): Direct AudioStream object. Default: none.
---   - name (string, optional): Audio player identifier. Default: auto-generated.
---   - parent_name (string, optional): Entity to attach audio player to. Default: "" (SoundManager).
---   - volume (number, optional): Volume in decibels. Default: 0.0 dB.
---   - pitch_scale (number, optional): Pitch multiplier. Default: 1.0.
---   - random_pitch (number, optional): Random pitch variation range. Default: 0.0.
---   - is_loop (boolean, optional): Loop playback. Default: false.
---   - is_2d (boolean, optional): Use AudioStreamPlayer2D (positional audio). Default: false.
---   - position (Vector2, optional): Position for 2D audio. Default: Vector2(0, 0).
---   - max_distance (number, optional): Max hearing distance for 2D audio. Default: 640.0.
---   - bus (string, optional): Audio bus name (auto-formatted: "effect" -> "Effect"). Default: "Effect".
---   - no_multiple_tag (string, optional): Tag to prevent multiple instances. Reuses existing player with same tag. Default: "".
---   - entity_name (string, optional): Entity to call when audio finishes. Used with function_name.
---   - function_name (string, optional): Function to call when audio finishes. Used with entity_name.
---@param config table Audio configuration dictionary.
---@return string Audio player identifier (name), or "" on error.
function set_audio(config) end

--- Add an audio effect to a bus.
--- Config parameters:
---   - bus_name (string, optional): Audio bus name (auto-formatted). Default: "Effect".
---   - effect_type (string, required): Effect type name. Supported types: "reverb", "delay", "chorus", "compressor", "eq", "filter", "highpass", "lowpass", "distortion", "limiter".
---   - effect_config (table, optional): Effect-specific configuration parameters. Default: {}.
---
--- Effect-specific parameters (effect_config):
---   reverb: room_size (0.8), damping (0.5), spread (1.0), hipass (0.0), dry (1.0), wet (0.5)
---   delay: dry (1.0), tap1_active (true), tap1_delay_ms (250.0), tap1_level_db (-6.0), tap2_active (false), tap2_delay_ms (500.0), tap2_level_db (-12.0), feedback_active (false), feedback_delay_ms (340.0), feedback_level_db (-6.0)
---   chorus: voice_count (2), dry (1.0), wet (0.5), voice_1_delay_ms (15.0), voice_1_rate_hz (0.8), voice_1_depth_ms (2.0), voice_1_level_db (0.0), voice_2_delay_ms (20.0), voice_2_rate_hz (1.2), voice_2_depth_ms (3.0), voice_2_level_db (0.0)
---   distortion: mode (AudioEffectDistortion.MODE_CLIP), pre_gain (0.0), keep_hf_hz (16000.0), drive (0.0), post_gain (0.0)
---   filter: cutoff_hz (2000.0), resonance (0.5), gain (1.0), db (AudioEffectFilter.FILTER_12DB)
---   highpass: cutoff_hz (80.0), resonance (0.5), db (AudioEffectFilter.FILTER_12DB)
---   lowpass: cutoff_hz (2000.0), resonance (0.5), db (AudioEffectFilter.FILTER_12DB)
---   compressor: threshold (0.0), ratio (4.0), gain (0.0), attack_us (20.0), release_ms (250.0), mix (1.0), sidechain ("")
---   limiter: ceiling_db (-0.1), threshold_db (0.0), soft_clip_db (2.0), soft_clip_ratio (10.0)
---   eq: band_0_gain_db (0.0), band_1_gain_db (0.0), band_2_gain_db (0.0), band_3_gain_db (0.0), band_4_gain_db (0.0), band_5_gain_db (0.0)
---@param config table Effect configuration dictionary.
---@return boolean True if effect was added successfully.
function add_audio_effect(config) end

--- Remove an audio effect from a bus by index.
--- Config parameters:
---   - bus_name (string, optional): Audio bus name (auto-formatted). Default: "Effect".
---   - effect_index (integer, required): Index of the effect to remove (0-based).
---@param config table Configuration dictionary.
---@return boolean True if effect was removed successfully.
function remove_audio_effect(config) end

--- Clear all effects from a bus.
--- Config parameters:
---   - bus_name (string, optional): Audio bus name (auto-formatted). Default: "Effect".
---@param config table Configuration dictionary.
---@return boolean True if effects were cleared successfully.
function clear_bus_effects(config) end

--- Set a parameter on an audio effect.
--- Config parameters:
---   - bus_name (string, optional): Audio bus name (auto-formatted). Default: "Effect".
---   - effect_index (integer, required): Index of the effect (0-based).
---   - parameter_name (string, required): Name of the parameter to set.
---   - value (any, required): Value to set for the parameter.
---@param config table Configuration dictionary.
---@return boolean True if parameter was set successfully.
function set_effect_parameter(config) end

---------------------------------------------------
-- VOICE CHAT (HOST ONLY)
---------------------------------------------------

--- Assign a player to a voice chat channel (Host only).
--- Automatically synchronized across all clients via RPC.
--- Config parameters:
---   - steam_id (string, required): Player's Steam ID as string.
---   - channel_name (string, required): Voice channel identifier/name.
---   - mute (boolean, optional): Whether player's microphone is muted. Default: false.
---   - deaf (boolean, optional): Whether player can hear others in the channel. Default: false.
---   - parent_name (string, optional): Entity to attach voice activity icon and spatial audio to. Default: "".
---   - icon_active (boolean, optional): Show voice activity icon above entity. Default: true.
---   - proximity_length (number, optional): Max distance for spatial audio. If 0, audio is global. Default: 0.
---@param config table Voice channel configuration dictionary.
function set_voice_channel(config) end

--- Remove a player from their voice chat channel (Host only).
--- Automatically synchronized across all clients via RPC.
---@param steam_id_str string Player's Steam ID as string.
function remove_voice_channel(steam_id_str) end

---------------------------------------------------
-- FILE SYSTEM (JSON SAVE/LOAD)
---------------------------------------------------

--- Save data to a JSON file in the mod's directory.
--- Automatically creates directory structure if it doesn't exist.
--- Path is relative to current mod folder and cannot contain ".." for security.
--- Example: save_json("inventory/player_data.json", {gold = 100, level = 5})
---@param relative_path string Relative path within mod folder (e.g., "inventory/player_data.json"). Cannot contain "..".
---@param data table|any Data to save (will be serialized to JSON). Can be table, number, string, boolean, etc.
function save_json(relative_path, data) end

--- Load data from a JSON file in the mod's directory.
--- Path is relative to current mod folder and cannot contain ".." for security.
--- Example: local data = load_json("inventory/player_data.json")
---@param relative_path string Relative path within mod folder (e.g., "inventory/player_data.json"). Cannot contain "..".
---@return table Loaded data as a dictionary, or empty table {} on error or if file doesn't exist.
function load_json(relative_path) end

--- List the file names inside a folder of the current mod (sandboxed: the path is
--- resolved under the mod folder and cannot contain ".."). Returns bare file names
--- (NOT absolute paths) sorted alphabetically, so the result is identical on every
--- peer — safe to index deterministically from a shared seed. Pass an extension
--- (e.g. "png") to filter. Great for picking a random image from a folder you may
--- add more files to later without touching code.
--- Example: local names = get_file_names("general/images/items", "png")
---@param relative_folder string Folder relative to the mod root. Cannot contain "..".
---@param extension? string Extension filter without the dot (e.g. "png"). Default: "" (all files).
---@return table Array of file name strings (sorted), or empty table {} if missing.
function get_file_names(relative_folder, extension) end

---------------------------------------------------
-- MAP/TILEMAP
---------------------------------------------------

--- Change to a different map.
---@param map_name string Name of the map to load.
function change_map(map_name) end

--- Get list of available maps in current mod.
---@return table Array of map names.
function get_map_list() end

--- Get the atlas coordinates of the tile at a map coordinate.
---@param x number Tile X coordinate (not world position).
---@param y number Tile Y coordinate.
---@return Vector2 Atlas coordinates of the tile, or (-1, -1) if empty.
function get_tile(x, y) end

--- Set a tile at a map coordinate.
--- `tileset_id` selects which tileset source (default 0 = first tileset). If that
--- tileset has autotile enabled (via the editor's Tile Maps panel), `atlas_coords`
--- is ignored and the correct 47-blob tile is chosen automatically from neighbours
--- (and neighbouring tiles are re-fitted too).
--- Pass `atlas_coords = Vector2(-1, -1)` to ERASE the cell (autotile neighbours are
--- re-fitted around the hole — handy for carving a doorway/opening at runtime).
---@param x number Tile X coordinate.
---@param y number Tile Y coordinate.
---@param atlas_coords Vector2 Atlas coordinates of the tile, or (-1,-1) to erase.
---@param tileset_id? number Tileset source id (default 0).
---@return boolean True on success, false if no tileset is loaded.
function set_tile(x, y, atlas_coords, tileset_id) end

--- Cast a 2D ray through the physics world (walls, entity bodies, areas) and
--- return the first thing it hits. Server-authoritative games should raycast on
--- the HOST from an entity's real position (clients only send aim intents).
--- Config parameters:
---   - from (Vector2, required): ray start in world space.
---   - to (Vector2, optional): ray end. If omitted, uses direction + length.
---   - direction (Vector2, optional): aim direction (used with length).
---   - length (number, optional): ray length in px when using direction. Default: 128.
---   - collision_mask (integer|table, optional): bitmask or array of layer numbers
---       (1-32) to hit. Default: all layers.
---   - exclude (table, optional): array of entity names whose bodies are ignored
---       (e.g. the shooter, so the ray does not hit itself).
---   - parent_name (string, optional): parent used to resolve 'exclude' names. Default: "".
---   - collide_with_bodies (boolean, optional): Default: true.
---   - collide_with_areas (boolean, optional): Default: false.
---@param config table Raycast configuration dictionary.
---@return table { hit (boolean), position (Vector2), normal (Vector2),
---  collider (string entity/node name, "" on miss) }. On a miss, position is the
---  ray end so you can still draw a full-length tracer.
function raycast(config) end

--- Convert map coordinates to world position.
---@param tile_position Vector2 Tile coordinates.
---@return Vector2 World position.
function map_to_local(tile_position) end

--- Convert world position to map coordinates.
---@param world_position Vector2 World position.
---@return Vector2 Tile coordinates.
function local_to_map(world_position) end

---------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------

--- Calculate distance between two positions.
---@param a Vector2 First position.
---@param b Vector2 Second position.
---@return number Distance in pixels.
function distance_to(a, b) end

--- Calculate squared distance (faster, no sqrt).
---@param a Vector2 First position.
---@param b Vector2 Second position.
---@return number Squared distance.
function distance_squared_to(a, b) end

--- Get a random position inside a polygon area.
---@param polygon_entity_name string Name of entity with polygon collision/area.
---@return Vector2 Random position within polygon.
function get_random_position_in_polygon(polygon_entity_name) end

--- Get the current OS time as a Unix timestamp (seconds since the epoch).
--- NOTE: this returns an integer (NOT a date table). It always has.
---@return integer Unix time in seconds (e.g. for timers, cooldowns, elapsed time).
function get_os_time() end

--- Explicit alias for get_os_time(): the current Unix time in seconds. Same value,
--- clearer name. Use whichever reads better at the call site.
---@return integer Unix time in seconds.
function get_os_time_unix() end

--- Convert string to Vector2.
---@param str string String representation like "100,200".
---@return Vector2 Parsed vector.
function string_to_vector2(str) end

--- Convert Vector2 to string.
---@param vec Vector2 Vector to convert.
---@return string String representation like "100,200".
function vector2_to_string(vec) end

---------------------------------------------------
-- INPUT SYSTEM
---------------------------------------------------

--- Set a custom display name for an input (for UI hints).
--- Available input names: key_1 to key_15, stick_1, stick_2.
---@param input_name string Input key name (e.g., "key_6", "stick_1").
---@param display_name string Display name to show in UI (e.g., "Jump", "Move").
function set_input_display_name(input_name, display_name) end

---------------------------------------------------
-- MODERATION (HOST ONLY)
---------------------------------------------------

--- Kick a user from the lobby.
---@param steam_id string Target user's Steam ID.
function kick_user(steam_id) end

--- Ban a user from the room for a specified duration.
---@param steam_id string Steam ID of the user to ban.
---@param duration integer Duration in seconds.
---@param reason? string Reason for the ban. Default: "".
function ban_user(steam_id, duration, reason) end

--- Unban a user.
---@param steam_id string Target user's Steam ID.
function unban_user(steam_id) end

--- Check if a user is banned.
---@param steam_id string Target user's Steam ID.
---@return boolean True if banned.
function is_user_banned(steam_id) end

--- Get ban information for a user.
---@param steam_id string Target user's Steam ID.
---@return table|nil Dictionary with ban details, or nil if not banned.
function get_ban_info(steam_id) end

--- Get a list of all currently banned users.
---@return table Array of dictionaries containing ban information for all active bans.
--- Each entry contains: steam_id, nickname, reason, ban_until, remaining_seconds.
function get_banned_users_list() end

--- Get moderation history for a specific user.
---@param steam_id string Target user's Steam ID.
---@return table Array of dictionaries containing all moderation actions for the user.
--- Each entry contains: timestamp, action (KICK/BAN/UNBAN), steam_id, nickname, reason, duration, executed_by.
--- Returns empty array if no history found. Results sorted newest first.
function get_user_history(steam_id) end

--- Format a Unix timestamp to a human-readable date/time string.
---@param unix_time number Unix timestamp (seconds since epoch).
---@return string Formatted date/time string in format "YYYY-MM-DD HH:MM:SS".
function format_timestamp(unix_time) end

---------------------------------------------------
-- TESTING/DEBUG (HOST ONLY)
---------------------------------------------------

--- Add a test bot user to the game.
---@param nickname string Bot display name.
---@return string Bot's generated Steam ID.
function add_test_user(nickname) end

--- Remove all test bot users.
function remove_all_test_users() end

---------------------------------------------------
-- COMMON ENTITY VARIABLES
-- These can be set at the top of your Lua file or accessed via get_value/set_value.
---------------------------------------------------

-- Configuration variables (set at top of lua script, before any code):

--- Area detection radius for this entity (sets circular area automatically if > 0).
--- Default: 0
---@type number
area_radius = 0

--- Network synchronization mode:
--- 0 = NONE (local only, not synchronized),
--- 1 = STATIC (synchronized only on player join, movement is NOT synced),
--- 2 = DYNAMIC (continuously synchronized, position/rotation/velocity synced automatically).
--- WARNING: ALL variables in STATIC and DYNAMIC entities are sent to clients on join!
--- Default: 0
---@type integer
network_mode = 0

--- If set, this entity becomes a singleton with this name (e.g., "-ui_manager").
--- Singleton names should start with "-" and be short for network efficiency.
--- WARNING: Singletons created via spawn_entity_host/local will NOT work!
--- Default: ""
---@type string
singleton_name = ""

--- Whether this entity can be dragged by the user.
--- If true, on_drag function will be called when dragged.
--- Default: false
---@type boolean
is_draggable = false

--- Whether this entity can receive dropped items.
--- If true, on_drop function will be called when another draggable is dropped on it.
--- Default: false
---@type boolean
is_droppable = false

--- Whether this entity responds to touch/click events.
--- If true, on_touch function will be called when clicked.
--- Default: false
---@type boolean
is_touchable = false

--- Whether this entity can be collected as an inventory item.
--- Default: false
---@type boolean
is_item = false

--- Whether users can ride this entity.
--- Use ride(entity_name) function in user code to mount.
--- Default: false
---@type boolean
is_rideable = false

-- Common entity properties (accessible via get_value/set_value):

--- Entity visibility (can be toggled on/off).
--- Default: true
---@type boolean
visible = true

--- Entity scale (Vector2 for Node2D).
--- Default: Vector2(1, 1)
---@type Vector2
scale = Vector2()

--- Color tint applied to entity visuals.
--- Default: Color(1, 1, 1, 1)
---@type Color
modulate = Color()

--- Z-order for rendering (higher values render on top).
--- MUST be between -999 and 999 (values outside this range will cause errors).
--- Default: 0
---@type integer
z_index = 0

-- Physics properties (for RigidBody2D entities):

speed = 15

--- Jump impulse force (side-scroller only).
--- Default: 500
---@type number
jump_force = 500.0

--- Total number of jumps allowed (0 = disabled, 1 = single jump, 2 = double jump, negative = infinite).
--- Default: 2
---@type integer
max_jump_count = 2

--- Enable wall jumping (jumping away from walls).
--- Default: true
---@type boolean
wall_jump_enabled = true

--- Linear damping (movement friction). Controls how quickly linear velocity decreases.
--- Default: 1.0
---@type number
linear_damp = 1.0

--- Angular damping (rotation friction). Controls how quickly angular velocity decreases.
--- Default: -1 (disabled)
---@type number
angular_damp = -1

--- Current angular velocity (rotation speed) in radians per second.
--- Default: 0.0
---@type number
angular_velocity = 0.0

--- Lock rotation to prevent entity from spinning.
--- Default: false
---@type boolean
lock_rotation = false

--- Gravity scale multiplier (1.0 = normal gravity, 0.0 = no gravity).
--- Default: 0.0
---@type number
gravity_scale = 0.0

--- Controls the speed at which the entity's rotation interpolates toward the target rotation received from the server. A value of 0 means no rotation change and 1 means instant rotation change will occur. Higher values result in faster interpolation.
--- Default: 0.5
---@type number
rotation_lerp_time = 0.5

--- Entity mass (affects physics interactions and resistance to acceleration).
--- Default: 1
---@type number
mass = 1

--- Freeze entity physics (true = no movement/physics).
--- Default: false
---@type boolean
freeze = false

--- Physics material: Defines how much kinetic energy the entity absorbs during collisions. Higher values result in softer collisions, as the entity absorbs more of the impact
--- Default: false
---@type boolean
absorbent = false

--- Physics material: bounciness (0.0 = no bounce, 1.0 = perfect bounce).
--- Default: 0
---@type number
bounce = 0

--- Physics material: friction coefficient (affects sliding resistance).
--- Default: 1
---@type number
friction = 1

--- Physics material: surface roughness (affects friction interaction).
--- Default: 0
---@type number
rough = 0

-- Label properties (for Label entities):

--- Text content displayed by label (use @key_6@ for input hints).
--- Default: ""
---@type string
text = ""

--- Vertical alignment (0 = top, 1 = center, 2 = bottom).
--- Default: 1
---@type integer
vertical_alignment = 1

--- Horizontal alignment (0 = left, 1 = center, 2 = right).
--- Default: 1
---@type integer
horizontal_alignment = 1

--- Label font color.
--- Default: Color(1, 1, 1, 1)
---@type Color
font_color = Color()

--- Label outline color.
--- Default: Color(0, 0, 0, 1)
---@type Color
outline_color = Color()

--- Label outline thickness in pixels.
--- Default: 0
---@type integer
outline_size = 0

--- Label font size in pixels.
--- Default: 16
---@type integer
font_size = 16

-- Image/Sprite properties (for TextureRect/Sprite2D entities):

--- Flip image horizontally.
--- Default: false
---@type boolean
flip_h = false

--- Flip image vertically.
--- Default: false
---@type boolean
flip_v = false

--- Path to image file (relative to mod/general/images/), .png extension added automatically.
--- Default: ""
---@type string
image_path = ""

-- ProgressBar properties:

--- Minimum value of progress bar.
--- Default: 0.0
---@type number
min_value = 0.0

--- Maximum value of progress bar.
--- Default: 100.0
---@type number
max_value = 100.0

--- Current value of progress bar.
--- Default: 0.0
---@type number
value = 0.0

--- Step increment for progress bar.
--- Default: 1.0
---@type number
step = 1.0

--- Allow value to exceed max_value.
--- Default: false
---@type boolean
allow_greater = false

--- Allow value to go below min_value.
--- Default: false
---@type boolean
allow_lesser = false

--- Fill direction (0 = left to right, 1 = right to left, 2 = top to bottom, 3 = bottom to top).
--- Default: 0
---@type integer
fill_mode = 0

--- Show percentage text on progress bar.
--- Default: true
---@type boolean
show_percentage = true

-- Area2D properties (for area/trigger entities or PolygonEditor):

--- Gravity override mode for area (0 = disabled, 1 = combine, 2 = replace).
--- Default: 0
---@type integer
gravity_space_override = 0

--- Whether gravity points to a specific point (true) or uses direction (false).
--- Default: false
---@type boolean
gravity_point = false

--- Gravity direction vector for area (when gravity_point is false).
--- Default: Vector2(0, 1)
---@type Vector2
gravity_direction = Vector2()

--- Linear damping override mode (0 = disabled, 1 = combine, 2 = replace).
--- Default: 0
---@type integer
linear_damp_space_override = 0

--- Angular damping override mode (0 = disabled, 1 = combine, 2 = replace).
--- Default: 0
---@type integer
angular_damp_space_override = 0

--- Angular damping value for area (only applies if angular_damp_space_override > 0).
--- Default: 0.0
---@type number
angular_damp = 0.0

-- User-specific variables (only for user script):


--- Steam nickname of user (automatically set, read-only).
--- Default: false (auto-set)
---@type string
nickname = ""

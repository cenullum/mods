-- File: cenkers_mod_stub.lua
-- IMPORTANT: This is a META/STUB file for the Lua Language Server (LuaLS) only.
-- It provides type definitions and documentation for global functions and variables
-- exposed from Godot's GDScript layer to Lua scripts in Cenker's Mod.
-- This file contains no executable logic.

-- This script is licensed under CC0 1.0 Universal (CC0 1.0)
-- Public Domain Dedication
-- Information About The License: https://creativecommons.org/share-your-work/public-domain/cc0/

---@meta

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
---@param delta number Time elapsed since last frame in seconds.
---@param inputs table Input state dictionary with keys: key_1 to key_15 (boolean), stick_1 (Vector2), stick_2 (Vector2).
---@return table|nil Modified inputs dictionary (or nil to leave unchanged).
function _process(delta, inputs) end

--- Called when a chat message is received (only on entities that define this).
--- Behavior:
--- - return nil: show standard format automatically.
--- - return "": suppress output (show nothing).
--- - return non-empty string: show it as-is (supports limited BBCode).
---
--- Standard format (when returning nil):
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
--- Function name must end with _HOST, _ALL, or _CLIENT.
--- First parameter of the Lua function MUST be "sender_id" (string).
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
---@param parent_name string Parent entity name (use "" for world-level entities).
---@param entity_name string Target entity name.
---@param variable_name string Name of the variable to get.
---@return any|nil The variable value, or nil if not found.
function get_value(parent_name, entity_name, variable_name) end

--- Set a variable value on an entity.
--- Can set entity variables, position, rotation, velocity, UI properties, etc.
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
---
---@param config table Image configuration dictionary.
---@return string The created/updated image node name.
function set_image(config) end

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

--- Create screen shake effect.
---@param intensity number Shake strength.
---@param duration number Shake duration in seconds.
function screenshake(intensity, duration) end

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
---   - parent_name (string, optional): Entity to attach voice activity icon to. Default: "".
---   - icon_active (boolean, optional): Show voice activity icon above entity. Default: true.
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

---------------------------------------------------
-- MAP/TILEMAP
---------------------------------------------------

--- Change to a different map.
---@param map_name string Name of the map to load.
function change_map(map_name) end

--- Get list of available maps in current mod.
---@return table Array of map names.
function get_map_list() end

--- Get tile ID at a map coordinate.
---@param tile_position Vector2 Tile coordinates (not world position).
---@return number Tile ID, or -1 if empty.
function get_tile(tile_position) end

--- Set tile at a map coordinate.
---@param tile_position Vector2 Tile coordinates.
---@param tile_id number Tile ID to place, or -1 to clear.
function set_tile(tile_position, tile_id) end

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

--- Get current OS timestamp.
---@return table Dictionary with: year, month, day, hour, minute, second.
function get_os_time() end

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
function kick_user(steam_id, reason) end

--- Ban a user from the lobby.
---@param steam_id string Target user's Steam ID.
---@param reason? string Ban reason (optional). Default: "".
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
--- 1 = STATIC (synchronized only on player join),
--- 2 = DYNAMIC (continuously synchronized).
--- Default: 0
---@type integer
network_mode = 0

--- If set, this entity becomes a singleton with this name (e.g., "-ui_manager").
--- Singleton names should start with "-" and be short for network efficiency.
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

--- Z-order for rendering (higher values render on top), clamped between -999 and 999.
--- Default: 0
---@type integer
z_index = 0

-- Physics properties (for RigidBody2D entities):

--- Movement speed multiplier for entity.
--- Default: 15
---@type number
speed = 15

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

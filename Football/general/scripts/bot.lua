network_mode = 2
lock_rotation = true
bounce = 0.8
friction = 0.1
linear_damp = 1.0
-- =============================================================================
-- Football - a single bot player.  Spawned by -bot_manager (host only), but the
-- script itself runs on every peer because the body is a DYNAMIC entity: the
-- visuals below are built everywhere, the AI below that is host only.
--
-- This file does not think.  -bot_manager sends it one command per half second
-- (set_command) and everything here is the per-frame execution of it:
--
--   * walk to a point with a proper arrival slow-down (turned off when the point
--     is the ball: you arrive at a ball, you do not park on it),
--   * KEEP THE TOUCH IT IS ALREADY CARRYING - if the way the body is travelling
--     would send the ball roughly where the coach wants it, run the ball on with
--     the body at full speed and do not line anything up at all,
--   * ORBIT the ball to get the body on the right side of it before hitting -
--     the hit direction is bot->ball, exactly like a player's, so the only way
--     to aim is to stand in the right place - but only when the run we have is
--     no use, because braking to walk round the ball loses it,
--   * hold the hit "button" (hit_value climbs 100/s, same as user.lua) and let
--     go the moment the body, the ball and the target line up,
--   * dribble by shoving the ball with the body at a controlled speed.
--
-- Spawn config from the manager: team, btype, label.
-- =============================================================================

add_tag(name, "bot")

-- Visual + engine constants that must match user.lua so a bot is exactly as
-- capable as a human player - no more, no less.
local BODY_R    = 16.0
local HIT_MULT  = 3.0    -- user.lua: velocity = dir * 3 * hit_value
local HIT_MAX   = 100.0

-- MOVEMENT: a bot presses a virtual thumbstick, it does NOT teleport its
-- velocity around.  user.gd::process_movement -> Entity.apply_direct_movement
-- adds `speed` (15) to the velocity in the held direction once per physics
-- frame and clamps each axis to MAX_VELOCITY; let go and linear_damp glides you
-- to a stop.  Doing the same read-add-write here would give a bot exactly a
-- player's acceleration, top speed, turning arc and glide - except for TWO
-- differences between where the two run, both of which press() has to undo:
--
--  1. RATE.  _process is a RENDERED frame (InputManager._process); the player's
--     push is a physics frame (user.gd::_integrate_forces, 30 Hz).  And the
--     shoves stack rather than overwrite, because set_value writes straight into
--     the entity's variable cache that get_value reads back.  Ungated, a 144 fps
--     host gave its bots 4.8x a player's acceleration and parked them on the
--     600/axis MAX_VELOCITY clamp instead of a player's 435.
--  2. LAG.  The player edits the physics state in place.  We can only queue a
--     value (set_value -> Entity.last_state) that the NEXT _integrate_forces
--     ASSIGNS - one physics frame later, and it wipes out the damping and the
--     contact response of the frame it lands on.  So a shove computed from the
--     velocity we can see lands two frames after that velocity was true, and the
--     body's motion splits into two independent chains that only meet again
--     after ~0.5 s: every bump fed one chain and not the other, and the bot
--     visibly juddered at 15 Hz instead of gliding.
--
-- The cure for (2) is to write where the body WILL be, not where it was: carry
-- our own commanded velocity forward through one frame of the engine's damping
-- and put the shove on top of that (sent_vx/sent_vy below).  That makes the
-- commanded velocity follow the player's recurrence one frame at a time -
-- v = v * DAMP_STEP + 15 - so it is smooth, and it still settles at the same
-- 435 px/s a player tops out at.  The engine's own value is re-adopted whenever
-- it disagrees with that model by more than RESYNC_TOL, which is exactly when
-- something physical happened to us (a bounce off a wall, a body or the ball).
local PHYS_HZ   = 30.0   -- project.godot: physics/common/physics_ticks_per_second
local PUSH_STEP = 15.0   -- Entity.speed, the per-physics-frame shove
local MAX_AXIS  = 600.0  -- Entity.MAX_VELOCITY, clamped per axis
local ACCEL     = PUSH_STEP * PHYS_HZ -- px/s^2 equivalent at 30 Hz physics
local DAMP_STEP = 1.0 - 1.0 / PHYS_HZ -- one physics frame of linear_damp = 1.0
local RESYNC_TOL = 25.0  -- px/s of "the engine knows something we do not"
local DEADZONE  = 30.0   -- steering smaller than this: let go, do not twitch

local ORBIT_R   = 36.0   -- circling distance: outside body+ball contact (24)
-- Braking distance from top speed with a full counter-press, so the bot starts
-- easing off in time instead of sailing past its slot.
local ARRIVE_R  = 150.0
local ALIGN_TOL = 0.30   -- rad: shooting - the hit goes bot->ball, so be exact
-- Dribbling is a SHOVE WITH THE BODY, and a body is 32 px wide: the ball rolls
-- roughly where you lean on it, no line-up needed.  Demanding shot-grade
-- alignment to dribble was why a bot pirouetted around the ball with an opponent
-- standing on it - which is exactly when the ball gets taken off you.
local DRIBBLE_TOL = 1.15 -- rad: good enough to just push the thing
local ANG_ARRIVE = 0.90  -- rad: start easing off the circling inside this
local FIRE_TOL  = 0.13   -- rad: close enough to actually let the shot go
local DRIBBLE_SPEED = 0.70 -- fraction of top speed while pushing the ball
local PUSH_AHEAD = 70.0  -- aim this far through the ball when dribbling

-- MOMENTUM.  Both the charged hit and a plain shove with the body travel
-- bot->ball, so the direction a body is ALREADY running when it reaches the ball
-- is the direction the ball is going to go.  A bot that brakes out of a good run
-- to walk round to a textbook angle throws away a touch it had for free and then
-- spends a second pirouetting next to the ball, which is exactly when an
-- opponent takes it.  So: if the speed we are carrying already sends the ball
-- roughly where the coach wants it, we keep every bit of it and run the ball on
-- with the body.  The coach knows this too (bot_manager's line_up_time) and
-- stops asking for hits we would have to brake for - this is the same rule at
-- frame rate, because our speed changes far faster than the coach ticks.
local CARRY_MIN = 130.0  -- px/s: below this there is no momentum worth keeping
local CARRY_TOL = 0.80   -- rad: how far off our run may be and still be useful

-- state ----------------------------------------------------------------------
image_name = ""
label_name = ""
collision_name = ""
hit_progress_bar_name = ""
-- DEBUG ONLY: shows what the bot is currently trying to do, under its
-- nickname.  Host-only, same reasoning as hit_progress_bar_name below (the
-- coach's decision is host-only state).  Delete this whole block (here, in
-- build_visuals, set_command and _process) once bot behaviour is trusted.
debug_label_name = ""
cmd_reason = ""
last_debug_text = nil
is_ball_interactable = false
hit_value = 0.0
press_time = 0.0 -- seconds spent holding the stick, read by the coach

-- The velocity we last commanded and the one before it (see press): together
-- they are our model of what the engine is doing with the body right now.
sent_vx = 0.0
sent_vy = 0.0
prev_vx = 0.0
prev_vy = 0.0
has_sent_v = false -- false = we are coasting, trust the engine's own value

-- current order from the coach (see -bot_manager)
-- act: 0 walk, 1 shoot, 2 pass, 3 clear, 4 dribble
cmd_act = 0
cmd_tx = 0.0
cmd_ty = 0.0
cmd_ax = 0.0
cmd_ay = 0.0
cmd_power = 0.0
cmd_speed = 300.0
-- act 0 only: the target is the ball rather than a spot to take up, so arrive
-- carrying speed instead of easing to a halt on it (see seek's run_through).
cmd_chase = false
has_cmd = false

-- after a hit the bot peels away instead of standing in the ball's way (a
-- clearance into a wall bounces straight back at 100% - this is what stops it
-- dying against the shooter's own body)
retreat_t = 0.0
retreat_x = 0.0
retreat_y = 0.0

if team == nil then team = 0 end
if label == nil then label = "Bot" end
if btype == nil then btype = 0 end

function team_color()
	if team == 1 then return Color(1, 0, 0, 1) end
	if team == 2 then return Color(0, 0, 1, 1) end
	return Color(1, 1, 1, 1)
end

-- Same look a player without a Steam avatar gets, plus the bot's name tag.
function build_visuals()
	collision_name = set_collision({ parent_name = name, name = collision_name, shape = "circle", size = BODY_R })
	image_name = set_image({ parent_name = name, name = image_name })
	set_image_pixel(name, image_name, Vector2(32, 32))
	set_shader({ parent_name = name, image_name = image_name, shader_name = "circle", outline_color = team_color() })
	label_name = set_label({
		parent_name = name, name = label_name, text = label,
		position = Vector2(-256, 16), size = Vector2(4096, 128),
		font_size = 64, scale = Vector2(0.125, 0.125),
		horizontal_alignment = 1, vertical_alignment = 1,
	})
	-- Debug-only: hit_value (charge for the next shot) is host-only state, so
	-- only the host can draw a meaningful bar for it - clients never see this.
	if IS_HOST then
		hit_progress_bar_name = set_progress_bar({
			parent_name = name, name = hit_progress_bar_name, position = Vector2(-64, 48),
			modulate = Color(1, 1, 0, 1), size = Vector2(128, 16),
		})
		-- DEBUG ONLY, see the note by debug_label_name above.
		debug_label_name = set_label({
			parent_name = name, name = debug_label_name, text = "",
			position = Vector2(-256, 68), size = Vector2(4096, 128),
			font_size = 64, scale = Vector2(0.1, 0.1),
			horizontal_alignment = 1, vertical_alignment = 1,
			modulate = Color(1, 1, 0.3, 1),
		})
	end
end

build_visuals()

-- Team changes come from the host so every peer recolours the same bot.
function set_team_ALL(sender_id, new_team)
	team = math.floor(new_team)
	set_shader({ parent_name = name, image_name = image_name, shader_name = "circle", outline_color = team_color() })
end

-- ball.lua drives this exactly like it does for a user: we may only hit the
-- ball while we are inside its area.
function set_ball_interactable(state)
	is_ball_interactable = state
end

-- Kickoff and after every goal (-ui_manager walks the scoreboard and calls this
-- on bots and players alike).
function reset_position()
	if not IS_HOST then return end
	local slot = run_function("-bot_manager", "get_kickoff_position", { name })
	if slot == nil then return end
	has_cmd = false
	hit_value = 0.0
	retreat_t = 0.0
	has_sent_v = false -- teleported: our idea of the body's velocity is void
	change_instantly({
		entity_name = name,
		position = slot,
		linear_velocity = Vector2(0, 0),
		angular_velocity = 0.0,
		rotation = 0.0,
	})
end

-- How full the bar has to be for a hit of `power`.  A release spends the WHOLE
-- bar (user.lua: velocity = dir * 3 * hit_value, then hit_value = 0), so the bot
-- cannot dial a shot in - it has to stop charging at the strength it wants,
-- exactly like letting go of the key at the right moment.
local function charge_for(power)
	local n = power / HIT_MULT
	if n > HIT_MAX then n = HIT_MAX end
	return n
end

function set_command(c)
	cmd_act = math.floor(c.act or 0)
	cmd_tx = c.tx or 0.0
	cmd_ty = c.ty or 0.0
	cmd_ax = c.ax or cmd_tx
	cmd_ay = c.ay or cmd_ty
	cmd_power = c.power or 0.0
	cmd_speed = c.speed or 300.0
	cmd_chase = c.chase and true or false
	has_cmd = true
	retreat_t = 0.0
	cmd_reason = c.reason or "" -- DEBUG ONLY, see debug_label_name above
	-- The bar survives a new order and just keeps climbing towards HIT_MAX (see
	-- _process) - it is never trimmed back down when the coach re-decides with a
	-- slightly different power, which used to make the bar visibly snap backwards
	-- every ACTION_COOLDOWN.  How much of it a shot spends is decided at the
	-- moment of firing instead (work_ball's `spend`).
end

-- ============================================================  host AI loop --

local function vlen(x, y)
	return math.sqrt(x * x + y * y)
end

-- Hold the stick in this direction for one frame (see PUSH_STEP above).  Not
-- calling this is how a bot "lets go": the engine's damping does the braking,
-- exactly like a player taking their hand off the keys.
-- THE PHYSICS FRAME BOUNDARY, as seen from a rendered frame.  get_value reads the
-- variable cache that set_value writes into directly and that _integrate_forces
-- refreshes with the engine's own velocity exactly once per physics frame - so
-- "the cache is no longer what I wrote" is precisely "a physics frame has run".
-- A render-time counter cannot stand in for this: it drifts against the tick, and
-- because set_value REPLACES the queued velocity rather than adding to it, two
-- writes inside one frame silently drop a shove and the bot moves in jerks.
-- (The margin is for the float32 a Vector2 stores; the engine's value differs by
-- whole px/s.)
local function frame_advanced(vx, vy)
	if not has_sent_v then return true end
	return math.abs(vx - sent_vx) > 0.01 or math.abs(vy - sent_vy) > 0.01
end

local function press(dx, dy, delta)
	local l = vlen(dx, dy)
	if l < 0.001 then return end
	-- The coach watches this to tell "walking" apart from "leaning on a wall":
	-- a blocked bot now barely moves AND barely has any velocity, because the
	-- solver eats the push every frame.  It counts real seconds of holding the
	-- stick, so it is charged on every frame - not just the paying ones.
	press_time = press_time + delta

	local v = get_value("", name, "linear_velocity")
	if v == nil then return end

	-- One shove per PHYSICS frame, exactly like the player whose stick is sampled
	-- at 30 Hz.
	if not frame_advanced(v.x, v.y) then return end

	-- What the body will be doing when this write lands, one frame from now.
	-- Coasting: the engine's value, damped by the frame in between.  Steering:
	-- our own last command, because the engine got it a frame ago and our write
	-- is about to overwrite whatever it made of it.
	local bx, by = v.x, v.y
	if has_sent_v then
		-- Undisturbed, the engine turns the command before last into exactly
		-- prev * DAMP_STEP.  Anything else is a contact we did not predict, and
		-- our write would erase it: take the engine's word instead.
		local ex, ey = prev_vx * DAMP_STEP, prev_vy * DAMP_STEP
		if vlen(v.x - ex, v.y - ey) <= RESYNC_TOL then
			bx, by = sent_vx, sent_vy
		end
	end

	-- Below 30 fps a player really does get more than one stick sample per
	-- rendered frame; above it, one.  Never more than two, so a hitch cannot be
	-- spent as a single lunge.
	local ticks = math.floor(delta * PHYS_HZ)
	if ticks < 1 then ticks = 1 elseif ticks > 2 then ticks = 2 end

	local ux, uy = dx / l * PUSH_STEP, dy / l * PUSH_STEP
	local nx, ny = bx, by
	for _ = 1, ticks do
		nx = nx * DAMP_STEP + ux
		ny = ny * DAMP_STEP + uy
	end
	if nx > MAX_AXIS then nx = MAX_AXIS elseif nx < -MAX_AXIS then nx = -MAX_AXIS end
	if ny > MAX_AXIS then ny = MAX_AXIS elseif ny < -MAX_AXIS then ny = -MAX_AXIS end

	-- bx/by is what we believe the body is carrying right now, so it is also what
	-- the next frame's engine value will be checked against.
	prev_vx, prev_vy = bx, by
	sent_vx, sent_vy = nx, ny
	has_sent_v = true
	set_value("", name, "linear_velocity", Vector2(nx, ny))
end

-- Which way to hold the stick to end up moving at `want` towards a point: the
-- difference between the speed we want and the speed we have.  That is what
-- makes a bot counter-steer to brake or to change direction instead of
-- snapping, and it falls into the deadzone once it is already cruising right.
-- `run_through` turns the arrival slow-down off, for a target that is not a spot
-- to stand on but something to arrive at carrying speed - the ball.  Easing to a
-- halt on top of a loose ball and then starting again from nothing is precisely
-- the "sprints over, stops next to it, fiddles about" a bot must never do.
local function seek(vx, vy, mx, my, tx, ty, speed, run_through)
	local dx, dy = tx - mx, ty - my
	local d = vlen(dx, dy)
	local want = speed
	if d < ARRIVE_R and not run_through then want = speed * (d / ARRIVE_R) end
	if d < 1.0 then
		if run_through then return 0.0, 0.0 end
		return -vx, -vy
	end
	return dx / d * want - vx, dy / d * want - vy
end

-- Turn "the velocity I want" into "the way I hold the stick", never letting the
-- wish exceed a player's top speed.
local function steer_to(dvx, dvy, vx, vy, cap)
	local l = vlen(dvx, dvy)
	if l > cap and l > 0.001 then
		dvx, dvy = dvx / l * cap, dvy / l * cap
	end
	return dvx - vx, dvy - vy
end

-- The whole point of the bot: the hit always travels bot->ball, so to send the
-- ball at `aim` the body has to be on the opposite side of it first.  Walking
-- straight there would shove the ball away, so we circle it at ORBIT_R instead.
local function work_ball(vx, vy, mx, my, bx, by, bvx, bvy, ax, ay, speed, power, do_hit)
	local wx, wy = ax - bx, ay - by            -- where the ball must go
	local wl = vlen(wx, wy)
	if wl < 1.0 then
		-- degenerate order: just push it away from us, that spot is reachable
		wx, wy = bx - mx, by - my
		wl = vlen(wx, wy)
		if wl < 1.0 then wx, wy, wl = 1.0, 0.0, 1.0 end
	end
	wx, wy = wx / wl, wy / wl

	local rx, ry = mx - bx, my - by            -- where we are around the ball
	local rd = vlen(rx, ry)
	if rd < 1.0 then rx, ry, rd = -wx, -wy, 1.0 end
	local ux, uy = rx / rd, ry / rd

	-- angle between "where we stand" and "behind the ball"
	local err = math.atan(ux * -wy - uy * -wx, ux * -wx + uy * -wy)
	local aerr = math.abs(err)

	if do_hit then
		-- The bar is filled in _process, so the bot walks up already loaded rather
		-- than loitering next to the ball winding up.  Releasing spends all of it.
		local need = charge_for(power)

		if aerr < FIRE_TOL and is_ball_interactable and hit_value >= need then
			-- fire: identical maths to user.lua's hit_ball(), but capped at what this
			-- shot actually needs - the bar itself always charges to a full HIT_MAX
			-- (see _process), so a soft pass does not go out at full power just
			-- because the bar kept climbing while we waited to line the shot up.
			local spend = math.min(hit_value, need)
			local hx, hy = bx - mx, by - my
			local hl = vlen(hx, hy)
			if hl > 0.001 then
				run_function("*ball", "set_last_touching_steam_id", { name })
				add_linear_velocity("*ball", Vector2(hx / hl * HIT_MULT * spend, hy / hl * HIT_MULT * spend))
				retreat_x, retreat_y = mx - hx / hl * 130.0, my - hy / hl * 130.0
				retreat_t = 0.4
			end
			hit_value = 0.0
			has_cmd = false -- wait for the coach's next order
			-- peel away from this frame on: a clearance into a nearby wall is
			-- back on top of us in a moment, and a bot standing still would
			-- simply absorb it again
			return seek(vx, vy, mx, my, retreat_x, retreat_y, speed * 0.8)
		end
	end

	-- ---- the touch we are already carrying (see CARRY_MIN) -------------------
	-- Note this is checked BEFORE any of the lining-up below, and for a shot
	-- order just as much as for a dribble: a body doing 300 px/s at the ball has
	-- a shot on RIGHT NOW, and the alternative on offer is to brake, walk round
	-- and take a tidier one in a second's time with somebody else's foot on it.
	local sp = vlen(vx, vy)
	if sp > CARRY_MIN then
		-- Where our run would send the ball, and whether we are actually closing
		-- on it - momentum going past the ball is no use to anyone.
		local cerr = math.abs(math.atan(vx * wy - vy * wx, vx * wx + vy * wy))
		local cx, cy = bx - mx, by - my
		local cl = vlen(cx, cy)
		if cerr < CARRY_TOL and cl > 0.001 and (vx * cx + vy * cy) / cl > CARRY_MIN * 0.5 then
			-- Run THROUGH it, not at it.  Aiming past the ball keeps the body
			-- behind it as it rolls away, so the next touch goes the same way as
			-- this one and the ball is carried up the pitch a stride at a time.
			-- Full speed, deliberately: the arrival slow-down is what used to turn
			-- a break away into a jog.
			local tx, ty = bx + wx * PUSH_AHEAD, by + wy * PUSH_AHEAD
			local dx, dy = tx - mx, ty - my
			local d = vlen(dx, dy)
			if d < 1.0 then dx, dy, d = wx, wy, 1.0 end
			return steer_to(dx / d * speed, dy / d * speed, vx, vy, speed)
		end
	end

	-- How straight we have to be behind the ball before we commit.  A shot is
	-- fussy; a shove with the body is not.
	local align_tol = do_hit and ALIGN_TOL or DRIBBLE_TOL

	if rd > ORBIT_R * 2.2 and (do_hit or aerr > align_tol) then
		-- Still out here: spiral in towards the right side of the ball.  Walking
		-- straight at the spot behind it would plough through the ball on the way
		-- and knock it away before we got there.  A dribbler already on a usable
		-- side skips this and simply runs the ball down - it is not trying to
		-- arrive anywhere exact, it is going to lean on the thing.
		local turn = math.min(aerr, 1.15) * ((err > 0.0) and 1.0 or -1.0)
		local c, s = math.cos(turn), math.sin(turn)
		local sx, sy = ux * c - uy * s, ux * s + uy * c
		local reach = math.max(ORBIT_R, rd * 0.72)
		return seek(vx, vy, mx, my, bx + sx * reach, by + sy * reach, speed)
	end

	-- Everything from here happens IN THE BALL'S FRAME: the wanted velocity is
	-- the ball's plus our manoeuvre.  Without that the bot politely jogged at
	-- close-control speed while a rolling ball left it behind.
	-- Turning in a circle of radius r needs v^2/r of sideways acceleration and
	-- all we have is ACCEL, so a body cannot whip around the ball at sprint
	-- speed either: close control means slowing down, for a bot as for you.
	local close_speed = math.min(speed, math.sqrt(ACCEL * ORBIT_R))

	if aerr > align_tol then
		-- Circle the ball, easing off as the angle closes so we SETTLE behind it
		-- rather than sweeping past and having to come round again.  Same arrive
		-- behaviour as walking, just expressed around a circle: tangential travel
		-- that fades out with the angle, plus a pull back onto ORBIT_R.
		local side = (err > 0.0) and 1.0 or -1.0
		local tang = close_speed * math.min(1.0, aerr / ANG_ARRIVE)
		local pull = close_speed * math.max(-1.0, math.min(1.0, (rd - ORBIT_R) / 45.0))
		return steer_to(bvx + (-uy * side) * tang - ux * pull,
			bvy + (ux * side) * tang - uy * pull, vx, vy, speed)
	end

	if do_hit then
		-- Lined up and charging: hold station just outside the ball and travel
		-- with it, so a moving ball can still be struck.
		local tx, ty = bx - wx * (ORBIT_R * 0.8), by - wy * (ORBIT_R * 0.8)
		local dx, dy = tx - mx, ty - my
		local d = vlen(dx, dy)
		if d < 1.0 then return steer_to(bvx, bvy, vx, vy, speed) end
		local want = math.min(close_speed, d * 3.0)
		return steer_to(bvx + dx / d * want, bvy + dy / d * want, vx, vy, speed)
	end

	-- Dribbling: lean on the ball and walk it where the coach wants it, keeping
	-- enough on top of its own speed to stay in contact instead of trailing it.
	local tx, ty = bx + wx * PUSH_AHEAD, by + wy * PUSH_AHEAD
	local dx, dy = tx - mx, ty - my
	local d = vlen(dx, dy)
	if d < 1.0 then return steer_to(bvx, bvy, vx, vy, speed) end
	-- Sprint while there is still ground between us and it, then ease into close
	-- control as we arrive: chasing a loose ball at dribbling pace loses the race.
	local far = math.min(1.0, rd / (ORBIT_R * 3.0))
	local pace = DRIBBLE_SPEED + (1.0 - DRIBBLE_SPEED) * far
	local push = math.min(speed, speed * pace + vlen(bvx, bvy))
	return steer_to(dx / d * push, dy / d * push, vx, vy, speed)
end

function _process(delta, inputs)
	-- Clients only draw this bot; never return a value here, the engine would
	-- take it as the local player's input state.
	if not IS_HOST then return end
	if team == 0 then return end

	-- Holding the hit "button" down the whole time, the way a player runs at the
	-- ball with the key already pressed, so the bar is loaded on arrival instead
	-- of the bot standing over the ball waiting for it.  It always charges all
	-- the way to HIT_MAX, exactly like a player who keeps the key held - it never
	-- stalls parked at some fractional level while lining the shot up (that used
	-- to look like the bar freezing at 80% or snapping back and forth as the
	-- coach's re-decisions nudged the order's power up and down).  How much of a
	-- full bar an order actually needs is decided once, at the moment of firing
	-- (see work_ball's `spend`), not by capping how high the bar is allowed to go.
	hit_value = math.min(hit_value + HIT_MAX * delta, HIT_MAX)
	set_progress_bar({ parent_name = name, name = hit_progress_bar_name, value = hit_value })

	-- DEBUG ONLY: refresh the "what am I doing" label under the nickname.  Only
	-- writes when the text actually changed (see rule 10 in the stub header).
	local debug_text = cmd_reason
	if retreat_t > 0.0 then debug_text = "retreating after hit" end
	if not has_cmd and retreat_t <= 0.0 then debug_text = "idle: no order" end
	if debug_text ~= last_debug_text then
		last_debug_text = debug_text
		set_label({ parent_name = name, name = debug_label_name, text = debug_text })
	end

	if not has_cmd and retreat_t <= 0.0 then
		has_sent_v = false
		return
	end

	local me = get_value("", name, "position")
	if me == nil then return end
	local v = get_value("", name, "linear_velocity")
	local vx, vy = v and v.x or 0.0, v and v.y or 0.0

	-- Everything below returns "which way to hold the stick", never a velocity.
	local sx, sy = 0.0, 0.0
	if retreat_t > 0.0 then
		retreat_t = retreat_t - delta
		sx, sy = seek(vx, vy, me.x, me.y, retreat_x, retreat_y, cmd_speed * 0.8)
	elseif cmd_act == 0 then
		sx, sy = seek(vx, vy, me.x, me.y, cmd_tx, cmd_ty, cmd_speed, cmd_chase)
	else
		local ball = get_value("", "*ball", "position")
		if ball ~= nil then
			local bv = get_value("", "*ball", "linear_velocity")
			sx, sy = work_ball(vx, vy, me.x, me.y, ball.x, ball.y,
				bv and bv.x or 0.0, bv and bv.y or 0.0,
				cmd_ax, cmd_ay, cmd_speed, cmd_power, cmd_act ~= 4)
		end
	end

	-- Small correction? Let go and coast, the way you would.  Hands off the stick
	-- also means hands off the velocity: from here the engine owns it, so the
	-- next shove has to start from the engine's value again, not from our model.
	-- Only once a physics frame has really gone by without a shove, though - the
	-- rendered frames right after one still read our own value back.
	if vlen(sx, sy) >= DEADZONE then
		press(sx, sy, delta)
	elseif frame_advanced(vx, vy) then
		has_sent_v = false
	end
end

-- Physics callbacks (ball.lua looks at script_name, so touches by a bot count
-- for goals and assists just like a player's).
function on_body_body_entered(data)
end

function on_body_body_exited(body_name)
end

function on_area_area_entered(area_name)
end

function on_area_area_exited(area_name)
end

function on_area_body_entered(body_name)
end

function on_area_body_exited(body_name)
end

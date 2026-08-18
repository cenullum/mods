singleton_name = "bot_manager"
-- =============================================================================
-- Football - THE COACH.  One shared brain for every bot on the pitch.
--
-- bot.lua is a dumb executor (steer / orbit the ball / charge / release, per
-- frame).  Everything that needs to know about the OTHER 21 things on the pitch
-- lives here and runs on a timer, not in _process:
--
--   * who on the team is actually the best man for the ball (humans included) -
--     everyone else keeps their shape instead of swarming it,
--   * where every role stands (the whole block slides with the ball, so a
--     forward walks back when the team is defending),
--   * what the man on the ball should do with it: shoot / pass / dribble /
--     clear, with the goal side the keeper is NOT covering, wall bounces
--     included when the direct lane is blocked.
--
-- HOST ONLY.  Bots are DYNAMIC entities, so clients just receive their motion.
--
-- Nothing about the pitch is hardcoded: the field rectangle is measured with
-- raycasts, the goals come from the map's own red_goalpost / blue_goalpost
-- polygons, and the shot maths is derived from the ball's real linear_damp.
-- Drop the same scripts on a bigger map and the bots re-measure it.
-- =============================================================================

-- ------------------------------------------------------------------ tuning --
local COACH_TICK        = 0.25 -- cheap pass: interceptions, roles, positions
local ACTION_COOLDOWN   = 0.25 -- expensive pass (raycasts): shot/pass search
local MAX_BOTS_PER_TEAM = 10
-- Both passes used to run at half the rate above (0.5 / 1.0).  A second is a
-- long time on a pitch: the man on the ball would keep dribbling into a defender
-- who arrived after the decision was taken, and a sight of goal that opened up
-- mid-run was not looked at until it had closed again.  Everything below that
-- was calibrated in TICKS rather than seconds is expressed in seconds now, so
-- these two numbers can move without changing what anything else means.

-- Engine facts the planner has to know.  (project.godot: physics 30 Hz,
-- entity.tscn: linear_damp 1, Entity.speed 15, user.lua: hit = dir*3*charge.)
local PHYSICS_DT  = 1.0 / 30.0
local USER_ACCEL  = 15.0
local USER_DAMP   = 1.0
local HIT_MULT    = 3.0   -- user.lua hit_ball(): velocity = dir * 3 * hit_value
local HIT_CHARGE  = 100.0 -- hit_value climbs 100/s while the key is held
local BALL_R      = 8.0   -- ball.lua collision radius
local BODY_R      = 16.0  -- user.lua collision radius

-- A player accelerates by USER_ACCEL every physics frame and loses USER_DAMP
-- per second, so it settles at this speed.  Bots move at the same top speed
-- (times the difficulty factor) - they are not allowed to be faster than you.
local PLAYER_SPEED = USER_ACCEL * (1.0 - USER_DAMP * PHYSICS_DT) / (USER_DAMP * PHYSICS_DT)
local ACCEL = USER_ACCEL / PHYSICS_DT -- px/s^2 while the stick is held

local MAX_SHOT_SPEED = HIT_MULT * HIT_CHARGE -- 300: a fully charged hit

-- How close a player must be to count as "on the ball" (ball.lua's area is 48,
-- our body is 16, so contact happens well before this).
local CONTROL_R  = 42.0
local PRESSURE_T = 0.55  -- an opponent arriving sooner than this = under pressure
-- The most time worth spending on getting the body round to the far side of the
-- ball before a hit (see line_up_time).  Anything dearer than this is dropped
-- and the ball is run on with the body instead: a bot braking out of a good run
-- to pirouette next to the ball is a bot about to have the ball taken off it,
-- and it was doing it constantly because "walk round to it" used to be free.
local LINEUP_BUDGET  = 0.45 -- seconds; ~90 deg of walking from a standing start
local LINEUP_PRESSED = 0.28 -- with an opponent on us there is far less of it
local LINEUP_COST    = 90.0 -- score points a second of lining up is worth
-- A second of holding the stick and going nowhere is a bot wedged on a corner,
-- expressed in seconds so the coach's rate can change under it.
local STUCK_TIME  = 1.0
local STUCK_TICKS = math.max(2, math.floor(STUCK_TIME / COACH_TICK + 0.5))
-- Re-deciding four times a second, two ideas a couple of points apart would swap
-- every tick and the body would spend the whole possession turning between them
-- instead of committing to either.  Whatever we picked last time defends its
-- place by this much.
local STICKY_BONUS = 30.0
-- An opponent this far from the ball is not stopping us running with it.  This
-- is SPACE, deliberately separate from PRESSURE_T above, which is TIME: a man
-- sprinting in from 200 px is pressure, a man standing still at 200 px is not.
local CLEAR_R = 210.0
-- Inside this an opponent is close enough that we stop dribbling towards goal and
-- start dribbling away from HIM - which puts our body between him and the ball.
local SHIELD_R   = 105.0

-- Arrival speed we want the ball to still have when it gets there.
local ARRIVE_SHOT = 120.0
local ARRIVE_PASS = 55.0

-- Team shape.  depth 0 = own goal line, 1 = opponent goal line.
local ROLE_DEPTH = {
	GK   = { base = 0.030, shift = 0.02 },
	GK2  = { base = 0.090, shift = 0.05 },
	DEF  = { base = 0.200, shift = 0.34 },
	MID  = { base = 0.430, shift = 0.46 },
	FWD  = { base = 0.680, shift = 0.42 },
}
local LANE_FOLLOW  = 0.45 -- how hard the block slides towards the ball's lane
local SPREAD_MIN   = 90.0 -- two team-mates never aim at the same spot
local KEEP_OFF_R   = 110.0 -- nobody but the chaser walks into the ball

local DIFFICULTY = {
	[1] = { speed = 0.78, react = 0.40, aim_err = 0.17, shoot_bias = -25.0 },
	[2] = { speed = 0.92, react = 0.22, aim_err = 0.08, shoot_bias = 0.0 },
	[3] = { speed = 1.00, react = 0.10, aim_err = 0.03, shoot_bias = 20.0 },
}
-- Also used to tag a bot's nickname (e.g. "Bot 1 (Hard)") so the token
-- translates on-screen along with everything else.
local DIFF_TOKENS = { "{bot_diff_easy}", "{bot_diff_normal}", "{bot_diff_hard}" }

-- DEBUG ONLY: human-readable label for what the man on the ball decided to do,
-- shown under a bot's nickname (see bot.lua's debug_label).  act: 1 shoot,
-- 2 pass, 3 clear, 4 dribble.  Delete along with the debug label when done.
local ON_BALL_REASON = {
	[1] = "shooting",
	[2] = "passing",
	[3] = "clearing",
	[4] = "dribbling",
}

-- Bot brains offered in the panel.
local TYPE_BOTH  = 0 -- can be given any role, keeper included
local TYPE_GK    = 1 -- keeper only, never leaves its box
local TYPE_FIELD = 2 -- outfield only, never plays in goal

-- ------------------------------------------------------------------- state --
bots        = {} -- [entity_name] = { team, btype, label, role, lane, stuck, ... }
bot_order   = {} -- insertion order, so role assignment does not flip around
bot_seq     = 0
difficulty  = 2
geo         = nil -- measured pitch: bounds + both goals
ball_damp   = 0.5
coach_on    = false
team_state  = { [1] = {}, [2] = {} } -- per-team memory (chaser, last decision)
BOT_PANEL   = "football_bot_panel_id"

-- ==============================================================  small maths --

local function vlen(x, y)
	return math.sqrt(x * x + y * y)
end

local function clampf(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function dist(ax, ay, bx, by)
	return vlen(bx - ax, by - ay)
end

-- Signed shortest angle between two directions (radians, -pi..pi).
local function angle_between(ax, ay, bx, by)
	return math.atan(ax * by - ay * bx, ax * bx + ay * by)
end

-- How far round the ball a body has to walk before it could hit it towards
-- (ax, ay): the angle between where it stands now and the far side of the ball.
-- 0 = already lined up, pi = on completely the wrong side.
local function turn_cost(mex, mey, bx, by, ax, ay)
	local rx, ry = mex - bx, mey - by
	local rl = vlen(rx, ry)
	local wx, wy = ax - bx, ay - by
	local wl = vlen(wx, wy)
	if rl < 1.0 or wl < 1.0 then return 0.0 end
	return math.abs(angle_between(rx / rl, ry / rl, -wx / wl, -wy / wl))
end

local function rotate(x, y, a)
	local c, s = math.cos(a), math.sin(a)
	return x * c - y * s, x * s + y * c
end

-- Seconds of faffing about before this body could hit the ball towards (ax, ay).
-- A hit travels bot->ball, so an idea aimed anywhere except where we are ALREADY
-- running costs two separate things: the walk round to the far side of the ball,
-- and the speed we have to kill before we can make that walk.  A body already
-- travelling the way the ball has to go is a shot that is lined up for free.
-- This is what decides between striking the ball and simply running it on, and
-- it is the reason a bot arriving at pace no longer brakes to pirouette.
local ORBIT_R = 36.0 -- bot.lua's ORBIT_R: the radius a body circles the ball at
local function line_up_time(p, bx, by, ax, ay)
	-- Circling is slow whoever does it: turning in a circle of radius r needs
	-- v^2/r of sideways acceleration and ACCEL is all anybody has.
	local orbit_speed = math.sqrt(ACCEL * ORBIT_R)
	local t = turn_cost(p.x, p.y, bx, by, ax, ay) * ORBIT_R / orbit_speed

	local wx, wy = ax - bx, ay - by
	local wl = vlen(wx, wy)
	local sp = vlen(p.vx, p.vy)
	if wl > 1.0 and sp > 1.0 then
		local along = (p.vx * wx + p.vy * wy) / wl -- speed already going that way
		local side = math.sqrt(math.max(sp * sp - along * along, 0.0))
		-- Sideways speed has to be shed; speed pointing the wrong way has to be
		-- shed AND paid for again in the other direction, hence twice over.
		t = t + (side + math.max(-along, 0.0) * 2.0) / ACCEL
	end
	return t
end

-- ======================================================  ball physics model --
-- The ball only loses speed to linear_damp, so its motion has a closed form:
--   v(t) = v0 * e^(-d*t)      travelled(t) = v0 * (1 - e^(-d*t)) / d
-- Two consequences the bots plan with:
--   * a hit can never carry further than v0/d  (600 px at full charge),
--   * arriving speed is exactly v0 - d * distance.

-- Speed to give the ball so that it still moves at `arrive` after `d` pixels.
local function speed_for(d, arrive)
	return arrive + ball_damp * d
end

-- Seconds for a ball hit at v0 to cover d pixels (nil = it never gets there).
local function flight_time(d, v0)
	local k = 1.0 - ball_damp * d / v0
	if k <= 0.001 then return nil end
	return -math.log(k) / ball_damp
end

-- Where the ball will be in t seconds, with one bounce off the walls folded in
-- (walls are perfectly elastic here, so mirroring is a good enough guess).
local function ball_at(px, py, vx, vy, t)
	local k = (1.0 - math.exp(-ball_damp * t)) / ball_damp
	local x, y = px + vx * k, py + vy * k
	if geo then
		if x < geo.x0 then x = 2 * geo.x0 - x elseif x > geo.x1 then x = 2 * geo.x1 - x end
		if y < geo.y0 then y = 2 * geo.y0 - y elseif y > geo.y1 then y = 2 * geo.y1 - y end
		x = clampf(x, geo.x0, geo.x1)
		y = clampf(y, geo.y0, geo.y1)
	end
	return x, y
end

-- ==========================================================  pitch geometry --

local function probe(fx, fy, dx, dy, ignore)
	local hit = raycast({
		from = Vector2(fx, fy),
		direction = Vector2(dx, dy),
		length = 6000,
		collision_mask = { 1 },
		exclude = ignore,
	})
	if hit == nil or not hit.hit then return nil end
	return dist(fx, fy, hit.position.x, hit.position.y)
end

-- Everything that is not a wall, so a player standing in the way cannot be
-- mistaken for the touchline.
local function moving_bodies()
	local list = { "*ball" }
	local users = get_entity_names_by_tag("user")
	for i = 1, #users do list[#list + 1] = users[i] end
	for i = 1, #bot_order do list[#list + 1] = bot_order[i] end
	return list
end

-- The goal polygons are the only thing the map has to name (ball.lua already
-- relies on them).  Sampling them gives their rectangle without any hardcoding.
local function polygon_bounds(pname, samples)
	local x0, y0, x1, y1
	for _ = 1, samples do
		local p = get_random_position_in_polygon(pname)
		if p == nil then return nil end
		if x0 == nil then
			x0, y0, x1, y1 = p.x, p.y, p.x, p.y
		else
			if p.x < x0 then x0 = p.x end
			if p.y < y0 then y0 = p.y end
			if p.x > x1 then x1 = p.x end
			if p.y > y1 then y1 = p.y end
		end
	end
	if x0 == nil then return nil end
	if x0 == 0 and x1 == 0 and y0 == 0 and y1 == 0 then return nil end -- missing polygon
	-- Random samples never quite touch the edges; grow the box back a little.
	local ex, ey = (x1 - x0) * 0.05 + 1.0, (y1 - y0) * 0.05 + 1.0
	return { x0 = x0 - ex, y0 = y0 - ey, x1 = x1 + ex, y1 = y1 + ey,
		cx = (x0 + x1) * 0.5, cy = (y0 + y1) * 0.5 }
end

-- Measures the pitch once (and again if the map changes under us).
function build_geometry()
	local centre = get_value("", "*ball", "init_pos")
	if centre == nil then centre = get_value("", "*ball", "position") end
	if centre == nil then return false end

	local red = polygon_bounds("red_goalpost", 24)
	local blue = polygon_bounds("blue_goalpost", 24)
	if red == nil or blue == nil then return false end

	local ignore = moving_bodies()
	local up = probe(centre.x, centre.y, 0, -1, ignore)
	local down = probe(centre.x, centre.y, 0, 1, ignore)
	if up == nil or down == nil then return false end
	local y0, y1 = centre.y - up, centre.y + down

	-- Horizontal walls: several rows, nearest hit wins.  The rows that slip
	-- through a goal mouth land deeper inside the net and are ignored by the
	-- min(), which is exactly what makes this work on any map.
	local left, right
	for i = 1, 7 do
		local y = y0 + (y1 - y0) * (i / 8.0)
		local l = probe(centre.x, y, -1, 0, ignore)
		local r = probe(centre.x, y, 1, 0, ignore)
		if l ~= nil and (left == nil or l < left) then left = l end
		if r ~= nil and (right == nil or r < right) then right = r end
	end
	if left == nil or right == nil then return false end

	local x0, x1 = centre.x - left, centre.x + right
	if x1 - x0 < 200 or y1 - y0 < 200 then return false end

	geo = {
		x0 = x0, y0 = y0, x1 = x1, y1 = y1,
		w = x1 - x0, h = y1 - y0,
		cx = (x0 + x1) * 0.5, cy = (y0 + y1) * 0.5,
		kick_x = centre.x, kick_y = centre.y,
		goals = {},
	}
	-- red_goalpost is the goal RED defends (ball.lua scores it for blue).
	for team, box in pairs({ [1] = red, [2] = blue }) do
		local on_left = box.cx < geo.cx
		geo.goals[team] = {
			cx = box.cx, cy = box.cy,
			ymin = box.y0, ymax = box.y1,
			line = on_left and geo.x0 or geo.x1, -- own goal line, inside the pitch
			dir = on_left and 1.0 or -1.0,       -- attacking direction for this team
		}
	end
	geo.box_depth = math.max(geo.w * 0.14, 150.0)             -- "penalty area"
	geo.box_half = math.max((red.y1 - red.y0) * 1.6, geo.h * 0.20)
	ball_damp = get_value("", "*ball", "linear_damp") or 0.5
	if ball_damp <= 0.01 then ball_damp = 0.5 end
	return true
end

local function ensure_geometry()
	if geo ~= nil then return true end
	return build_geometry()
end

-- depth: 0 at own goal line, 1 at the opponent's.  lane: 0 top, 1 bottom.
local function depth_of(team, x)
	local g = geo.goals[team]
	if g.dir > 0 then return clampf((x - geo.x0) / geo.w, 0, 1) end
	return clampf((geo.x1 - x) / geo.w, 0, 1)
end

local function lane_of(y)
	return clampf((y - geo.y0) / geo.h, 0, 1)
end

local function slot_xy(team, d, l)
	local g = geo.goals[team]
	local x
	if g.dir > 0 then x = geo.x0 + d * geo.w else x = geo.x1 - d * geo.w end
	return clampf(x, geo.x0 + 24, geo.x1 - 24), clampf(geo.y0 + l * geo.h, geo.y0 + 24, geo.y1 - 24)
end

local function in_own_box(team, x, y)
	local g = geo.goals[team]
	return math.abs(x - g.line) < geo.box_depth and math.abs(y - g.cy) < geo.box_half
end

-- ============================================================  world sample --

local function gather_players()
	local list = {}
	local users = get_entity_names_by_tag("user")
	for i = 1, #users do
		local id = users[i]
		local t = get_value("", id, "team")
		if t ~= nil and t ~= 0 then
			local p = get_value("", id, "position")
			if p ~= nil then
				local v = get_value("", id, "linear_velocity")
				list[#list + 1] = {
					n = id, team = math.floor(t), bot = false,
					x = p.x, y = p.y,
					vx = v and v.x or 0.0, vy = v and v.y or 0.0,
					speed = PLAYER_SPEED, react = 0.0,
				}
			end
		end
	end

	local dead = nil
	for i = 1, #bot_order do
		local bn = bot_order[i]
		local b = bots[bn]
		if b ~= nil then
			local p = get_value("", bn, "position")
			if p == nil then
				-- Spawning is queued engine side, so a brand new bot can miss a
				-- tick or two; only give up on it after a few of them.
				b.missing = (b.missing or 0) + 1
				if b.missing >= 3 then
					dead = dead or {}
					dead[#dead + 1] = bn
				end
			else
				b.missing = 0
				local v = get_value("", bn, "linear_velocity")
				local d = DIFFICULTY[difficulty]
				list[#list + 1] = {
					n = bn, team = b.team, bot = true, ref = b,
					x = p.x, y = p.y,
					vx = v and v.x or 0.0, vy = v and v.y or 0.0,
					speed = PLAYER_SPEED * d.speed, react = d.react,
				}
			end
		end
	end
	if dead ~= nil then
		for i = 1, #dead do forget_bot(dead[i]) end
	end
	return list
end

-- How long this body really needs to cover `d` px towards (dx, dy): nobody here
-- teleports up to speed, they accelerate at ACCEL and top out at p.speed, so a
-- standing start costs about half a second that a plain d/speed would miss.
local function travel_time(p, d, dirx, diry)
	if d <= 0 then return 0.0 end
	local v0 = p.vx * dirx + p.vy * diry -- speed already going that way
	if v0 < 0 then v0 = 0 elseif v0 > p.speed then v0 = p.speed end
	local ramp = (p.speed * p.speed - v0 * v0) / (2 * ACCEL) -- distance spent accelerating
	if d <= ramp then
		return (math.sqrt(v0 * v0 + 2 * ACCEL * d) - v0) / ACCEL
	end
	return (p.speed - v0) / ACCEL + (d - ramp) / p.speed
end

-- When can this player get to the ball, and where.  This is what stops the
-- whole team running at the ball: only the best time gets to go.
local function intercept(p, bx, by, bvx, bvy)
	for step = 0, 16 do
		local t = step * 0.15
		local px, py = ball_at(bx, by, bvx, bvy, t)
		local dx, dy = px - p.x, py - p.y
		local d = vlen(dx, dy)
		if d < 1.0 then return t, px, py end
		local reach = d - CONTROL_R
		if reach <= 0 then return t, px, py end
		if travel_time(p, reach, dx / d, dy / d) + p.react <= t then return t, px, py end
	end
	local px, py = ball_at(bx, by, bvx, bvy, 2.4)
	local dx, dy = px - p.x, py - p.y
	local d = math.max(vlen(dx, dy), 1.0)
	return travel_time(p, d - CONTROL_R, dx / d, dy / d) + p.react, px, py
end

-- =========================================================  lane of fire ----

-- Two parallel rays a ball-radius apart: a single centre ray happily "passes
-- through" a defender it would really clip.
local function lane_clear(fx, fy, tx, ty, ignore)
	local dx, dy = tx - fx, ty - fy
	local d = vlen(dx, dy)
	if d < 1.0 then return true end
	local nx, ny = -dy / d * BALL_R, dx / d * BALL_R
	for s = -1, 1, 2 do
		local hit = raycast({
			from = Vector2(fx + nx * s, fy + ny * s),
			to = Vector2(tx + nx * s, ty + ny * s),
			collision_mask = { 1 },
			exclude = ignore,
		})
		if hit ~= nil and hit.hit then
			if dist(fx, fy, hit.position.x, hit.position.y) < d - 6.0 then return false end
		end
	end
	return true
end

-- The map is a box with elastic walls, so a blocked lane can still be played by
-- mirroring the target through the top or bottom wall and hitting the wall.
-- Returns the aim point on the wall plus the full path length.
local function bank_shot(fx, fy, tx, ty, ignore)
	for _, wall in ipairs({ geo.y0 + BALL_R, geo.y1 - BALL_R }) do
		local my = 2 * wall - ty -- mirrored target
		local dy = my - fy
		if math.abs(dy) > 1.0 then
			local k = (wall - fy) / dy
			if k > 0.05 and k < 0.95 then
				local wx = fx + (tx - fx) * k
				if wx > geo.x0 + BALL_R and wx < geo.x1 - BALL_R then
					if lane_clear(fx, fy, wx, wall, ignore) and lane_clear(wx, wall, tx, ty, ignore) then
						local total = dist(fx, fy, wx, wall) + dist(wx, wall, tx, ty)
						return wx, wall, total
					end
				end
			end
		end
	end
	return nil
end

-- Can a bot physically get behind the ball to play it that way?  The hit always
-- travels bot->ball, so the spot bot.lua has to reach is ball - dir * ORBIT_R;
-- against a touchline or in a corner half of those spots are inside the wall.
local STAND_R = 38.0 -- bot.lua ORBIT_R plus a little slack

-- Push the ideal standing spot back inside the pitch and see how far off the
-- wanted direction that leaves us.  Sliding along a touchline only costs a
-- couple of degrees; a ball in the corner cannot be played out at all.
local function aim_error(bx, by, ax, ay)
	local dx, dy = ax - bx, ay - by
	local d = vlen(dx, dy)
	if d < 1.0 then return nil end
	dx, dy = dx / d, dy / d
	local sx = clampf(bx - dx * STAND_R, geo.x0 + BODY_R, geo.x1 - BODY_R)
	local sy = clampf(by - dy * STAND_R, geo.y0 + BODY_R, geo.y1 - BODY_R)
	local rx, ry = bx - sx, by - sy
	local rl = vlen(rx, ry)
	if rl < 10.0 then return nil end -- squashed onto the ball: no angle at all
	return math.abs(angle_between(rx / rl, ry / rl, dx, dy))
end

local function stand_ok(bx, by, ax, ay, tol)
	local err = aim_error(bx, by, ax, ay)
	return err ~= nil and err < (tol or 0.12)
end

-- Nearest direction to (ax, ay) that the bot can both line up on AND that
-- keeps the ball on the pitch.  Third return is false when the ball is wedged
-- so tightly that no legal angle exists at all (a corner).
local function playable(bx, by, tx, ty)
	return stand_ok(bx, by, tx, ty, 0.40) -- a shove has more slack than a shot
		and tx > geo.x0 + 30 and tx < geo.x1 - 30
		and ty > geo.y0 + 30 and ty < geo.y1 - 30
end

local function reachable_aim(bx, by, ax, ay, reach)
	if playable(bx, by, ax, ay) then return ax, ay, true end
	local dx, dy = ax - bx, ay - by
	local d = vlen(dx, dy)
	if d < 1.0 then dx, dy, d = geo.cx - bx, geo.cy - by, math.max(vlen(geo.cx - bx, geo.cy - by), 1.0) end
	dx, dy = dx / d, dy / d
	for step = 1, 9 do
		for _, s in ipairs({ 1.0, -1.0 }) do
			local rx, ry = rotate(dx, dy, s * step * 0.35)
			local tx, ty = bx + rx * reach, by + ry * reach
			if playable(bx, by, tx, ty) then return tx, ty, true end
		end
	end
	return bx, by, false
end

-- Wedged in a corner: every spot behind the ball is inside a wall, so NOTHING -
-- bot or player - can push or shoot it straight out of there.  The way out is
-- the rebound: play it into the wall and let bounce = 1 send it back.  Pick the
-- angle whose REFLECTION points back into the pitch rather than mirroring
-- straight back down the line we shot along.  Power was measured, not guessed:
-- freed corners out of 19 drops went 10 / 14 / 17 / 16 at 110 / 180 / 240 / 300,
-- because a soft one dies on the shooter's own body (equal masses: the ball
-- just hands its velocity over) while a firm one keeps ricocheting until it
-- finds a way out.
local JAM_POWER = 240.0

function jam_escape(bx, by)
	local ox, oy = geo.cx - bx, geo.cy - by
	local ol = vlen(ox, oy)
	if ol < 1.0 then ox, oy, ol = 1.0, 0.0, 1.0 end
	ox, oy = ox / ol, oy / ol
	-- which walls is it trapped against?
	local wall_x = (bx - geo.x0 < 45.0) and -1.0 or ((geo.x1 - bx < 45.0) and 1.0 or 0.0)
	local wall_y = (by - geo.y0 < 45.0) and -1.0 or ((geo.y1 - by < 45.0) and 1.0 or 0.0)

	local best_x, best_y, best = -ox, -oy, -1e9
	for k = 0, 15 do
		local a = k * math.pi / 8.0
		local dx, dy = math.cos(a), math.sin(a)
		local err = aim_error(bx, by, bx + dx * 100.0, by + dy * 100.0)
		if err ~= nil and err < 0.45 then
			local rx, ry = dx, dy -- direction after bouncing off the wall(s)
			if wall_x ~= 0.0 and dx * wall_x > 0.0 then rx = -dx end
			if wall_y ~= 0.0 and dy * wall_y > 0.0 then ry = -dy end
			local score = rx * ox + ry * oy - err * 0.3
			if score > best then best_x, best_y, best = dx, dy, score end
		end
	end
	return { act = 3, ax = bx + best_x * 120.0, ay = by + best_y * 120.0, power = JAM_POWER }
end

-- The ball has not moved in seconds and we are standing over it.  Two players
-- squeezing it against a touchline from either side will do that, and neither
-- can walk around the other to play it properly.  No planning here: hit it
-- straight away from where the body already is (the one direction that needs
-- no repositioning, so it goes off the instant the wind-up ends), nudged a
-- little towards whichever side has nobody standing in it.
function panic_hit(px, py, bx, by)
	local dx, dy = bx - px, by - py
	local d = vlen(dx, dy)
	if d < 1.0 then dx, dy, d = 1.0, 0.0, 1.0 end
	dx, dy = dx / d, dy / d
	local best_x, best_y, best_room = dx, dy, -1.0
	for _, ang in ipairs({ 0.0, 0.4, -0.4 }) do
		local cx, cy = rotate(dx, dy, ang)
		local hit = raycast({
			from = Vector2(bx, by), direction = Vector2(cx, cy), length = 170,
			collision_mask = { 1 }, exclude = { "*ball" },
		})
		local room = (hit ~= nil and hit.hit) and dist(bx, by, hit.position.x, hit.position.y) or 170.0
		if room > best_room + 20.0 then best_x, best_y, best_room = cx, cy, room end
	end
	return { act = 3, ax = bx + best_x * 140.0, ay = by + best_y * 140.0, power = JAM_POWER }
end

-- Somebody is on us, there is no shot on and nobody to give it to.  Hit it
-- anyway.  This is the tackle AND the clearance, which are the same stroke in
-- this game: the only way to take a ball off a man is to knock it away from
-- him, and the only way out of a 50/50 is to be the one who plays it first.
--
-- Without this the planner had no move here at all - a contested shot and a
-- contested pass both get thrown out for needing too much turning (see
-- too_far_round), the wing clearance below only covers our own third, so
-- everything fell through to DRIBBLE.  Two bots dribbling into the same ball
-- lean on it from either side and neither ever plays it: they circle it looking
-- for an angle that the other one is standing in, for as long as you let them.
--
-- So angles are scored here, not hunted for.  line_up_time is in the score with
-- the same weight as everywhere else, which means the winner is nearly always a
-- direction the body ALREADY has - the stroke goes off now, while the ball is
-- still ours to hit, instead of after a half-circle walk.  No raycasts: the
-- touchline comes out of the pitch rectangle and opponents are checked with a
-- dot product, because this fires in a scramble and has to be cheap.
local CONTEST_REACH = 220.0 -- how far ahead we are aiming; the ball runs on past it
local CONTEST_LANE  = 46.0  -- an opponent this close to the line is standing in it
function contest_hit(me, players, bx, by, team, opp)
	local og, mg = geo.goals[opp], geo.goals[team]
	local fx, fy = og.cx - bx, og.cy - by
	local fl = vlen(fx, fy)
	if fl < 1.0 then fx, fy, fl = mg.dir, 0.0, 1.0 end
	fx, fy = fx / fl, fy / fl

	local best_x, best_y, best = fx, fy, -1e9
	for k = 0, 15 do
		local a = k * math.pi / 8.0
		local dx, dy = math.cos(a), math.sin(a)
		local fwd = dx * fx + dy * fy -- -1 straight at our own goal, +1 at theirs
		-- Never strike it back towards our own goal.  A clearance that goes the
		-- wrong way is worse than the tackle we did not make.
		if fwd > -0.15 then
			local tx, ty = bx + dx * CONTEST_REACH, by + dy * CONTEST_REACH
			local err = aim_error(bx, by, tx, ty)
			if err ~= nil and err < 0.5 then
				-- Room before the touchline, straight out of the pitch rectangle.
				local room = 1e9
				if dx > 0.01 then room = math.min(room, (geo.x1 - BALL_R - bx) / dx)
				elseif dx < -0.01 then room = math.min(room, (bx - geo.x0 - BALL_R) / -dx) end
				if dy > 0.01 then room = math.min(room, (geo.y1 - BALL_R - by) / dy)
				elseif dy < -0.01 then room = math.min(room, (by - geo.y0 - BALL_R) / -dy) end
				room = clampf(room, 0.0, 400.0)

				-- ...and who is standing in it.  Only opponents: knocking it off a
				-- team-mate is how the move continues, not how it ends.
				local blocked = 0.0
				for i = 1, #players do
					local o = players[i]
					if o.team ~= team then
						local ox, oy = o.x - bx, o.y - by
						local along = ox * dx + oy * dy
						if along > 0.0 and along < 260.0 then
							if math.abs(ox * dy - oy * dx) < CONTEST_LANE then
								blocked = blocked + (1.0 - along / 260.0) * 120.0
							end
						end
					end
				end

				local s = fwd * 110.0 + room * 0.25 - blocked - err * 40.0
					- line_up_time(me, bx, by, tx, ty) * LINEUP_COST
				if s > best then best, best_x, best_y = s, dx, dy end
			end
		end
	end
	-- Firm, for the reason measured on the corner drops (see JAM_POWER): equal
	-- masses, so a soft one just hands the ball to whoever we are leaning on.
	return { act = 3, ax = bx + best_x * CONTEST_REACH, ay = by + best_y * CONTEST_REACH, power = JAM_POWER }
end

-- ==============================================================  role plan ---

local FORMATIONS = {
	[0] = {},
	[1] = { "MID" },
	[2] = { "DEF", "FWD" },
	[3] = { "DEF", "MID", "FWD" },
	[4] = { "DEF", "DEF", "MID", "FWD" },
	[5] = { "DEF", "DEF", "MID", "MID", "FWD" },
	[6] = { "DEF", "DEF", "MID", "MID", "FWD", "FWD" },
	[7] = { "DEF", "DEF", "DEF", "MID", "MID", "FWD", "FWD" },
}

-- Roles only change when the squad changes, so a bot does not swap job every
-- half second.  Keeper first, then the outfield line-up for whatever is left.
function assign_roles(team)
	local squad = {}
	for i = 1, #bot_order do
		local b = bots[bot_order[i]]
		if b ~= nil and b.team == team then squad[#squad + 1] = b end
	end

	local keeper = nil
	for i = 1, #squad do
		if squad[i].btype == TYPE_GK then keeper = squad[i] break end
	end
	-- A "keeper / player" bot only goes in goal once there is somebody else to
	-- play outfield: a lone bot standing on its line all match is no fun.
	if keeper == nil and #squad >= 2 then
		for i = 1, #squad do
			if squad[i].btype == TYPE_BOTH then keeper = squad[i] break end
		end
	end

	local outfield = {}
	for i = 1, #squad do
		local b = squad[i]
		if b == keeper then
			b.role = "GK"
		elseif b.btype == TYPE_GK then
			b.role = "GK2" -- extra keeper-only bots guard the box
		else
			outfield[#outfield + 1] = b
		end
	end

	local shape = FORMATIONS[#outfield]
	if shape == nil then
		shape = {}
		for i = 1, #outfield do
			if i <= 3 then shape[i] = "DEF" elseif i <= #outfield - 2 then shape[i] = "MID" else shape[i] = "FWD" end
		end
	end
	for i = 1, #outfield do outfield[i].role = shape[i] or "MID" end

	-- Spread same-role bots across the pitch, and keeper-only extras across
	-- the goal mouth.
	local counters = {}
	for i = 1, #squad do
		local b = squad[i]
		counters[b.role] = (counters[b.role] or 0) + 1
		b.lane_index = counters[b.role]
	end
	for i = 1, #squad do
		local b = squad[i]
		b.lane = (b.lane_index - 0.5) / counters[b.role]
	end
	team_state[team].dirty = false
end

-- ======================================================  what to do on ball --

local function goal_aim_points(g)
	local pts = {}
	local span = g.ymax - g.ymin
	local inset = math.min(span * 0.22, 28.0)
	local lo, hi = g.ymin + inset, g.ymax - inset
	for i = 0, 4 do
		pts[#pts + 1] = { x = g.cx, y = lo + (hi - lo) * (i / 4.0) }
	end
	return pts
end

-- The opponent closest to their own goal is treated as their keeper, whether
-- that is a bot in goal or a human standing on the line.
local function find_keeper(players, opp_team)
	local best, best_d = nil, 1e18
	local g = geo.goals[opp_team]
	for i = 1, #players do
		local p = players[i]
		if p.team == opp_team then
			local d = dist(p.x, p.y, g.cx, g.cy)
			if d < best_d then best, best_d = p, d end
		end
	end
	return best, best_d
end

-- Full shoot / pass / dribble / clear search for the man on the ball.  This is
-- the only part that raycasts, and it is rate limited to ACTION_COOLDOWN.
function decide_action(me, players, bx, by, opp_time, team, prev)
	local opp = (team == 1) and 2 or 1
	local og = geo.goals[opp]
	local mg = geo.goals[team]
	local diff = DIFFICULTY[difficulty]
	local ignore = { "*ball", me.n }
	local my_depth = depth_of(team, bx)
	local pressed = opp_time < PRESSURE_T
	-- How much room we are actually standing in, as opposed to how soon someone
	-- could get here.  Nothing below raycasts for this, so it is free.
	local nearest_opp = 1e9
	for i = 1, #players do
		local o = players[i]
		if o.team ~= team then
			local od = dist(o.x, o.y, bx, by)
			if od < nearest_opp then nearest_opp = od end
		end
	end
	local in_the_clear = (not pressed) and nearest_opp > CLEAR_R
	local keeper, _ = find_keeper(players, opp)
	-- A keeper never tries to dribble out of its own box.
	local role = me.ref and me.ref.role or "MID"
	local is_keeper = (role == "GK" or role == "GK2")

	-- ---- shot ------------------------------------------------------------
	local best_shot, shot_score = nil, -1e9
	for _, aim in ipairs(goal_aim_points(og)) do
		local d = dist(bx, by, aim.x, aim.y)
		local need = speed_for(d, ARRIVE_SHOT)
		local arrive = ARRIVE_SHOT
		if need > MAX_SHOT_SPEED then -- too far for a firm shot: roll it in
			need = MAX_SHOT_SPEED
			arrive = MAX_SHOT_SPEED - ball_damp * d
		end
		if arrive > 25.0 then
			local blocked = not lane_clear(bx, by, aim.x, aim.y, ignore)
			local ax, ay, path = aim.x, aim.y, d
			if blocked then
				local wx, wy, total = bank_shot(bx, by, aim.x, aim.y, ignore)
				if wx ~= nil and total < 600.0 then
					blocked = false
					ax, ay, path = wx, wy, total
					need = math.min(speed_for(total, ARRIVE_SHOT * 0.7), MAX_SHOT_SPEED)
					arrive = need - ball_damp * total
				end
			end
			if not blocked and arrive > 25.0 and stand_ok(bx, by, ax, ay) then
				local keeper_gap = keeper and dist(keeper.x, keeper.y, aim.x, aim.y) or 400.0
				local s = 60.0 + math.min(keeper_gap, 260.0) * 0.45 + arrive * 0.22 - path * 0.09 + diff.shoot_bias
				-- The corner of the goal that is cheapest to line up wins ties: our
				-- own run is part of picking WHERE to shoot, not just whether to.
				s = s - line_up_time(me, bx, by, ax, ay) * LINEUP_COST
				if path > d + 1.0 then s = s - 45.0 end -- bank shots are a last resort
				if s > shot_score then
					shot_score = s
					best_shot = { ax = ax, ay = ay, power = need }
				end
			end
		end
	end

	-- ---- pass ------------------------------------------------------------
	local best_pass, pass_score = nil, -1e9
	for i = 1, #players do
		local mate = players[i]
		if mate.team == team and mate.n ~= me.n then
			-- lead the pass onto the run
			local lx, ly = mate.x, mate.y
			for _ = 1, 2 do
				local d = dist(bx, by, lx, ly)
				local v0 = math.min(speed_for(d, ARRIVE_PASS), MAX_SHOT_SPEED)
				local t = flight_time(d, v0)
				if t == nil then break end
				lx, ly = mate.x + mate.vx * t * 0.6, mate.y + mate.vy * t * 0.6
			end
			lx = clampf(lx, geo.x0 + 30, geo.x1 - 30)
			ly = clampf(ly, geo.y0 + 30, geo.y1 - 30)

			local d = dist(bx, by, lx, ly)
			local need = speed_for(d, ARRIVE_PASS)
			if d > 70.0 and need <= MAX_SHOT_SPEED then
				-- how tightly is he marked, and is the pass going forwards?
				local marked = 1e9
				for j = 1, #players do
					local o = players[j]
					if o.team ~= team then
						local md = dist(o.x, o.y, lx, ly)
						if md < marked then marked = md end
					end
				end
				local gain = depth_of(team, lx) - my_depth
				if marked > 55.0 and (gain > -0.06 or pressed) then
					local mate_ignore = { "*ball", me.n, mate.n }
					local path, ax, ay = d, lx, ly
					local ok = lane_clear(bx, by, lx, ly, mate_ignore)
					if not ok then
						local wx, wy, total = bank_shot(bx, by, lx, ly, mate_ignore)
						if wx ~= nil and speed_for(total, ARRIVE_PASS) <= MAX_SHOT_SPEED then
							ok, ax, ay, path = true, wx, wy, total
						end
					end
					if ok and not stand_ok(bx, by, ax, ay) then ok = false end
					if ok then
						local s = gain * 190.0 + math.min(marked, 240.0) * 0.25 - path * 0.05
						s = s - line_up_time(me, bx, by, ax, ay) * LINEUP_COST
						if pressed then s = s + 55.0 end
						if mate.bot and mate.ref and mate.ref.role == "FWD" then s = s + 25.0 end
						if path > d + 1.0 then s = s - 40.0 end
						if s > pass_score then
							pass_score = s
							best_pass = { ax = ax, ay = ay, power = math.min(speed_for(path, ARRIVE_PASS), MAX_SHOT_SPEED) }
						end
					end
				end
			end
		end
	end

	-- ---- pick one --------------------------------------------------------
	-- A hit travels bot->ball, so before striking anywhere the body has to get
	-- round to the far side of the ball first, braking out of whatever run it is
	-- on to do it (bot.lua orbits it).  An idea we cannot line up in the time we
	-- have is not an idea, it is a pirouette next to the ball - so we drop it and
	-- carry the ball instead, which costs nothing and goes the same way.
	-- This used to apply only under pressure, so an unpressed bot would happily
	-- brake to a stop and walk a full half-circle round the ball for a shot it
	-- could just as well have run into.  It applies always now, and how far round
	-- "too far" is depends on the speed the body is already carrying.
	local budget = pressed and LINEUP_PRESSED or LINEUP_BUDGET
	local function too_far_round(cand)
		return line_up_time(me, bx, by, cand.ax, cand.ay) > budget
	end

	-- Stick to the last idea unless the new one is clearly better (see
	-- STICKY_BONUS).  Applied here rather than inside the search loops, so it
	-- decides between shooting and passing without changing WHERE we would shoot.
	if prev ~= nil then
		if prev.act == 1 then shot_score = shot_score + STICKY_BONUS end
		if prev.act == 2 then pass_score = pass_score + STICKY_BONUS end
	end

	-- How far out we are willing to shoot.  The physics has already thrown away
	-- anything that cannot arrive with pace (a hit dies after v0/damp px and
	-- `arrive` is checked against 25 above), so this is only about not giving
	-- possession away with hopeful pot-shots.  At 0.42 of the pitch a bot with a
	-- clean sight of goal from the edge of the area would turn round and dribble
	-- instead, which is not what anyone does.  A genuinely good look - keeper off
	-- his line, clear lane, and a hit we are already running into - buys its own
	-- range, because that is a chance worth taking from anywhere it carries.
	local shoot_range = dist(bx, by, og.cx, og.cy) < geo.w * 0.60 or shot_score >= 150.0
	if best_shot ~= nil and too_far_round(best_shot) then best_shot = nil end
	if best_pass ~= nil and too_far_round(best_pass) then best_pass = nil end

	if best_shot ~= nil and shoot_range and shot_score >= 95.0 then
		return { act = 1, ax = best_shot.ax, ay = best_shot.ay, power = best_shot.power }
	end
	-- Only give it away for a real gain (or when someone is on top of us);
	-- otherwise carry it, which is what actually beats a packed defence here.
	-- With nobody within CLEAR_R the bar goes up: passing is how you beat a man
	-- you cannot go past, and with no man to beat a pass is just a loose ball for
	-- the other side to read.  A player in space runs at the defence.
	if best_pass ~= nil and (pressed or pass_score > (in_the_clear and 165.0 or 110.0)) then
		return { act = 2, ax = best_pass.ax, ay = best_pass.ay, power = best_pass.power }
	end
	-- A mediocre sight of goal (score below the "take it" bar above) is only
	-- worth stopping to line up for when there is no time to do better - under
	-- pressure, or already deep enough in the attacking third that dribbling
	-- closer risks losing it for nothing.  Otherwise let it fall through to
	-- dribble: advancing the ball with the body is free, orbiting to line up a
	-- so-so shot is not, and it was winning that fight almost every tick.
	if best_shot ~= nil and shoot_range and (pressed or my_depth > 0.78) then
		return { act = 1, ax = best_shot.ax, ay = best_shot.ay, power = best_shot.power }
	end

	-- Own third, pressed and nobody to give it to: get rid of it up the wing.
	if (my_depth < 0.28 and pressed) or (is_keeper and my_depth < 0.30) then
		local sy = (by < geo.cy) and (geo.y0 + geo.h * 0.15) or (geo.y1 - geo.h * 0.15)
		local sx = bx + mg.dir * math.min(geo.w * 0.45, 520.0)
		local ax, ay, found = reachable_aim(bx, by, clampf(sx, geo.x0 + 40, geo.x1 - 40), sy, 400.0)
		if found then
			return { act = 3, ax = ax, ay = ay, power = MAX_SHOT_SPEED }
		end
		return jam_escape(bx, by)
	end

	-- Anywhere else on the pitch with a man on us and nothing on: play it.  This
	-- has to sit BELOW both shot gates and the pass (a contested chance is still
	-- a chance, and a pass out of trouble is better than a clearance) and ABOVE
	-- dribble, because dribbling with an opponent leaning on us is exactly the
	-- stalemate this exists to break.
	if pressed then
		return contest_hit(me, players, bx, by, team, opp)
	end

	-- ---- dribble ---------------------------------------------------------
	local dx, dy = og.cx - bx, og.cy - by
	local dl = vlen(dx, dy)
	if dl < 1.0 then dx, dy, dl = mg.dir, 0.0, 1.0 end
	dx, dy = dx / dl, dy / dl

	-- The nearest opponent to the ball, and separately the nearest one actually
	-- standing in our way: one of them we shield the ball from, the other we go
	-- round.  They are usually but not always the same man.
	local threat, threat_d = nil, 1e9
	local near, near_d = nil, 1e9
	for i = 1, #players do
		local o = players[i]
		if o.team ~= team then
			local od = dist(o.x, o.y, bx, by)
			if od < 240.0 then
				if od < near_d then near, near_d = o, od end
				local ox, oy = (o.x - bx) / od, (o.y - by) / od
				if ox * dx + oy * dy > 0.35 and od < threat_d then threat, threat_d = o, od end
			end
		end
	end
	-- swerve around the man in front
	if threat ~= nil then
		local side = angle_between(dx, dy, threat.x - bx, threat.y - by) > 0 and -1.0 or 1.0
		dx, dy = rotate(dx, dy, side * (0.55 + 0.35 * (1.0 - threat_d / 240.0)))
	end
	-- SHIELD.  Pushing the ball directly away from an opponent means standing on
	-- the side he is on, so our own body ends up between him and the ball - the
	-- ball is behind us and he has to come through us to reach it.  Blend it in
	-- by how close he is: a shoulder to lean on at 100 px, all of it at nought.
	if near ~= nil and near_d < SHIELD_R then
		local sx, sy = (bx - near.x) / near_d, (by - near.y) / near_d
		local w = 1.0 - near_d / SHIELD_R
		dx, dy = dx * (1.0 - w) + sx * w, dy * (1.0 - w) + sy * w
		local nl = vlen(dx, dy)
		if nl < 0.001 then dx, dy = sx, sy else dx, dy = dx / nl, dy / nl end
	end
	-- ...and never pick a direction we would have to stand inside a wall to use
	local tx, ty, found = reachable_aim(bx, by,
		clampf(bx + dx * 260.0, geo.x0 + 30, geo.x1 - 30),
		clampf(by + dy * 260.0, geo.y0 + 30, geo.y1 - 30), 260.0)
	if found then
		return { act = 4, ax = tx, ay = ty, power = 0.0 }
	end
	return jam_escape(bx, by)
end

-- ==================================================================  coach ---

local function gk_target(team, b, bx, by, ball_dist)
	local g = geo.goals[team]
	-- Stand on the line the shot would come down, never outside the posts.
	local dx, dy = bx - g.cx, by - g.cy
	local dl = vlen(dx, dy)
	if dl < 1.0 then dl = 1.0 end
	-- come off the line as the ball gets closer (max ~1/4 of the box)
	local off = clampf(1.0 - ball_dist / (geo.box_depth * 3.0), 0.0, 1.0) * geo.box_depth * 0.55
	if b.role == "GK2" then off = off * 0.4 end
	local x = g.line + g.dir * (24.0 + off)
	local y = clampf(g.cy + dy / dl * (g.ymax - g.ymin) * 0.55, g.ymin + 10.0, g.ymax - 10.0)
	if b.role == "GK2" then
		y = clampf(y + ((b.lane or 0.5) - 0.5) * (g.ymax - g.ymin) * 1.6, geo.y0 + 30, geo.y1 - 30)
	end
	return x, y
end

local function plan_team(team, players, bx, by, now)
	local st = team_state[team]
	if st.dirty then assign_roles(team) end

	local squad = {}
	for i = 1, #players do
		if players[i].team == team and players[i].bot then squad[#squad + 1] = players[i] end
	end
	if #squad == 0 then return end

	local opp = (team == 1) and 2 or 1
	local mg, og = geo.goals[team], geo.goals[opp]
	local ball_depth = depth_of(team, bx)
	local ball_lane = lane_of(by)

	-- Best man for the ball on each side (humans count: a bot never barges a
	-- team-mate off the ball just because it is a bot).
	local mine, mine_t = nil, 1e9
	local theirs_t = 1e9
	local human_t = 1e9
	for i = 1, #players do
		local p = players[i]
		if p.team == team then
			if p.bot then
				-- keepers are not candidates out on the pitch (see below)
				local r = p.ref.role
				if r ~= "GK" and r ~= "GK2" and p.t_int < mine_t then mine, mine_t = p, p.t_int end
			elseif p.t_int < human_t then
				human_t = p.t_int
			end
		elseif p.t_int < theirs_t then
			theirs_t = p.t_int
		end
	end

	-- A keeper inside its own box owns the ball there, whoever else is near.
	local ball_in_box = in_own_box(team, bx, by)
	for i = 1, #squad do
		local p = squad[i]
		local r = p.ref.role
		if (r == "GK" or r == "GK2") and ball_in_box and p.t_int < mine_t + 0.45 then
			mine, mine_t = p, p.t_int
		end
	end

	-- Defer to a human team-mate who is genuinely closer, but take over if the
	-- ball has just been sitting there (someone is idle at the keyboard).
	local defer = (human_t + 0.2 < mine_t) and not st.ball_idle
	local chaser = (mine ~= nil and not defer) and mine or nil

	-- Hysteresis: keep the current chaser unless someone is clearly better.
	if chaser ~= nil and st.chaser ~= nil and st.chaser ~= chaser.n then
		for i = 1, #squad do
			local p = squad[i]
			local r = p.ref.role
			local keeps = (r ~= "GK" and r ~= "GK2") or ball_in_box
			if p.n == st.chaser and keeps and p.t_int < mine_t + 0.30 then chaser = p break end
		end
	end
	st.chaser = chaser and chaser.n or nil

	-- Second man: supports in front when we have it, covers when we do not.
	local second, second_t = nil, 1e9
	for i = 1, #squad do
		local p = squad[i]
		if (chaser == nil or p.n ~= chaser.n) and p.ref.role ~= "GK" and p.ref.role ~= "GK2" then
			if p.t_int < second_t then second, second_t = p, p.t_int end
		end
	end
	local we_have_it = math.min(mine_t, human_t) <= theirs_t + 0.15

	-- The most advanced opponent gets picked up by the deepest free defender.
	local danger, danger_d = nil, 1e9
	for i = 1, #players do
		local p = players[i]
		if p.team == opp then
			local d = dist(p.x, p.y, mg.cx, mg.cy)
			if d < geo.w * 0.55 and d < danger_d then danger, danger_d = p, d end
		end
	end
	local marker = nil
	if danger ~= nil and not we_have_it then
		local best_d = 1e9
		for i = 1, #squad do
			local p = squad[i]
			local r = p.ref.role
			if r == "DEF" and (chaser == nil or p.n ~= chaser.n) then
				local d = dist(p.x, p.y, danger.x, danger.y)
				if d < best_d then marker, best_d = p, d end
			end
		end
	end

	-- ---- turn all of that into one target per bot ------------------------
	local cmds = {}
	for i = 1, #squad do
		local p = squad[i]
		local b = p.ref
		local role = b.role or "MID"
		local cmd

		if b.stuck_until > now then
			if dist(p.x, p.y, bx, by) < 64.0 then
				-- the ball is right there and we are going nowhere: belt it
				cmd = panic_hit(p.x, p.y, bx, by)
				cmd.tx, cmd.ty, cmd.speed = bx, by, p.speed
				cmd.reason = "STUCK: panic hit"
			else
				cmd = { act = 0, tx = b.escape_x, ty = b.escape_y, speed = p.speed }
				cmd.reason = "STUCK: escaping"
			end
		elseif chaser ~= nil and p.n == chaser.n then
			-- Hysteresis around "am I on the ball yet".  Bots now carry momentum
			-- like players, so one orbiting the ball drifts in and out of a tight
			-- radius; without this it kept flipping back to "run at the ball",
			-- which throws away the shot it was winding up.
			local on_ball = (st.action ~= nil and st.action_for == p.n)
			-- Hand the last stretch of the approach over to bot.lua early: it is
			-- the only one that sees the body's speed every frame, and running the
			-- ball on with the momentum we arrive with is the whole idea.  Walking
			-- to within a body's length first meant braking to a stop next to the
			-- ball and starting again from nothing.
			local hold_r = on_ball and CONTROL_R * 3.0 or CONTROL_R * 2.4
			local away = dist(p.x, p.y, bx, by) > hold_r
			if away or (not on_ball and p.t_int > 0.30) then
				-- Not there yet: run to where the ball WILL be, not where it is,
				-- and come at it from the side we want to play it towards, so the
				-- body's own momentum sends it up the pitch on contact instead of
				-- back at our goal.  The more time there is before we get there,
				-- the wider we can afford to swing behind it.
				local ix, iy = p.i_x, p.i_y
				local ax, ay = og.cx - ix, og.cy - iy
				local al = vlen(ax, ay)
				if al > 1.0 then
					local back = clampf((p.t_int - 0.25) * 90.0, 0.0, 62.0)
					-- ...but only while the ball is actually ours to walk around.
					-- If they get there as soon as we do it is a race, and the man
					-- who swings out wide to line his shot up loses a race he was
					-- winning.  Go straight at it and settle it on contact.
					if theirs_t < p.t_int + 0.25 then back = 0.0 end
					ix = ix - ax / al * back
					iy = iy - ay / al * back
				end
				-- chase: this target is the ball, not a spot to park on - bot.lua
				-- must run THROUGH it rather than easing to a halt on top of it.
				cmd = { act = 0, tx = ix, ty = iy, speed = p.speed, chase = true, reason = "chasing the ball" }
				st.action = nil -- the ball is loose again: re-decide on arrival
			elseif st.ball_jam and dist(p.x, p.y, bx, by) < 70.0 then
				-- Nothing has moved the ball in seconds and we are on it: stop
				-- planning and belt it (see panic_hit).  This is the backstop for
				-- every "nobody can physically play this ball" position - two
				-- players pinning it against a wall, or a corner.
				local decided = panic_hit(p.x, p.y, bx, by)
				st.action, st.action_at, st.action_for = decided, now, p.n
				cmd = { act = decided.act, tx = bx, ty = by, ax = decided.ax, ay = decided.ay,
					power = decided.power, speed = p.speed, reason = "jam: forcing it free" }
			else
				local decided = st.action
				if decided == nil or now - (st.action_at or -99) >= ACTION_COOLDOWN or st.action_for ~= p.n then
					local prev = (st.action_for == p.n) and st.action or nil
					decided = decide_action(p, players, bx, by, theirs_t, team, prev)
					-- difficulty: bots do not aim like a machine
					local d = DIFFICULTY[difficulty]
					if d.aim_err > 0.001 and decided.act ~= 4 then
						local ex, ey = decided.ax - bx, decided.ay - by
						local el = vlen(ex, ey)
						if el > 1.0 then
							-- Roll the wobble once per IDEA, not once per tick.  The
							-- planner runs four times a second now, and a fresh error
							-- each time is not a worse aim, it is a moving target: the
							-- body would walk round the ball chasing its own noise and
							-- never finish the wind-up.  Kept as a unit offset so a
							-- difficulty change takes effect without re-rolling.
							if b.aim_noise == nil or prev == nil or prev.act ~= decided.act then
								b.aim_noise = math.random() * 2.0 - 1.0
							end
							ex, ey = rotate(ex / el, ey / el, b.aim_noise * d.aim_err)
							decided.ax, decided.ay = bx + ex * el, by + ey * el
						end
					end
					st.action, st.action_at, st.action_for = decided, now, p.n
				end
				cmd = { act = decided.act, tx = bx, ty = by, ax = decided.ax, ay = decided.ay,
					power = decided.power, speed = p.speed, reason = ON_BALL_REASON[decided.act] or "on the ball" }
			end
		elseif role == "GK" or role == "GK2" then
			local gx, gy = gk_target(team, b, bx, by, dist(bx, by, mg.cx, mg.cy))
			cmd = { act = 0, tx = gx, ty = gy, speed = p.speed, reason = "keeper: holding line" }
		elseif marker ~= nil and p.n == marker.n then
			local dx, dy = mg.cx - danger.x, mg.cy - danger.y
			local dl = vlen(dx, dy)
			if dl < 1.0 then dl = 1.0 end
			cmd = { act = 0, tx = danger.x + dx / dl * 62.0, ty = danger.y + dy / dl * 62.0, speed = p.speed, reason = "marking the danger man" }
		elseif second ~= nil and p.n == second.n then
			local d, l
			local reason
			if we_have_it then
				d = clampf(ball_depth + 0.14, 0.12, 0.90)
				l = clampf(ball_lane + ((by > geo.cy) and -0.20 or 0.20), 0.08, 0.92)
				reason = "supporting the ball"
			else
				d = clampf(ball_depth - 0.13, 0.05, 0.85)
				l = clampf(ball_lane * 0.6 + 0.2, 0.08, 0.92)
				reason = "covering behind the ball"
			end
			local tx, ty = slot_xy(team, d, l)
			cmd = { act = 0, tx = tx, ty = ty, speed = p.speed, reason = reason }
		else
			local rd = ROLE_DEPTH[role] or ROLE_DEPTH.MID
			local d = clampf(rd.base + (ball_depth - 0.5) * rd.shift, 0.06, 0.93)
			local l = clampf((b.lane or 0.5) + (ball_lane - 0.5) * LANE_FOLLOW, 0.07, 0.93)
			local tx, ty = slot_xy(team, d, l)
			cmd = { act = 0, tx = tx, ty = ty, speed = p.speed, reason = "holding " .. role .. " shape" }
		end

		-- Nobody except the chaser crowds the ball.
		if cmd.act == 0 and (chaser == nil or p.n ~= chaser.n) then
			local dx, dy = cmd.tx - bx, cmd.ty - by
			local dl = vlen(dx, dy)
			if dl < KEEP_OFF_R then
				if dl < 1.0 then dx, dy, dl = mg.dir, 0.0, 1.0 end
				cmd.tx = bx + dx / dl * KEEP_OFF_R
				cmd.ty = by + dy / dl * KEEP_OFF_R
			end
			cmd.tx = clampf(cmd.tx, geo.x0 + 24, geo.x1 - 24)
			cmd.ty = clampf(cmd.ty, geo.y0 + 24, geo.y1 - 24)
		end

		-- A keeper never wanders out of its own box, not even chasing (last, so
		-- the spacing rules above cannot drag it off its line).
		if role == "GK" or role == "GK2" then
			local g = geo.goals[team]
			local edge = g.line + g.dir * geo.box_depth * 1.35
			cmd.tx = clampf(cmd.tx, math.min(g.line, edge), math.max(g.line, edge))
			cmd.ty = clampf(cmd.ty, g.cy - geo.box_half * 1.15, g.cy + geo.box_half * 1.15)
			-- ...and a target that has just been clamped back to the box is a spot
			-- to stop on again, not a ball to run through.
			cmd.chase = nil
		end
		cmds[#cmds + 1] = { p = p, cmd = cmd }
	end

	-- Two bots never stand on the same blade of grass.
	for i = 1, #cmds do
		for j = i + 1, #cmds do
			local a, c = cmds[i].cmd, cmds[j].cmd
			if a.act == 0 and c.act == 0 then
				local dx, dy = c.tx - a.tx, c.ty - a.ty
				local d = vlen(dx, dy)
				if d < SPREAD_MIN then
					if d < 1.0 then dx, dy, d = 0.0, 1.0, 1.0 end
					local push = (SPREAD_MIN - d) * 0.5
					a.tx, a.ty = a.tx - dx / d * push, a.ty - dy / d * push
					c.tx, c.ty = c.tx + dx / d * push, c.ty + dy / d * push
				end
			end
		end
	end

	for i = 1, #cmds do
		local entry = cmds[i]
		entry.cmd.tx = clampf(entry.cmd.tx, geo.x0 + 20, geo.x1 - 20)
		entry.cmd.ty = clampf(entry.cmd.ty, geo.y0 + 20, geo.y1 - 20)
		run_function(entry.p.n, "set_command", { entry.cmd })
	end
end

-- Walls have corners and bots have no pathfinding.  Now that bots shove
-- themselves along like players, a blocked one has almost no velocity either
-- (the solver eats every push), so the tell is "it held the stick down and
-- still went nowhere" - press_time comes from bot.lua.
local function check_stuck(p, now)
	local b = p.ref
	if b.stuck_until > now then return end
	local moved = dist(p.x, p.y, b.last_x or p.x, b.last_y or p.y)
	local pressed_total = get_value("", p.n, "press_time") or 0.0
	local pressed = pressed_total - (b.last_press or pressed_total)
	b.last_press = pressed_total
	b.last_x, b.last_y = p.x, p.y
	-- Both halves of this test are per-tick quantities, so they are written as
	-- rates: "held the stick for most of the tick" and "moved slower than about
	-- 44 px/s while doing it".  Left as flat numbers they would mean something
	-- different at every coach rate - at 0.25 s a flat 22 px would have called
	-- anything under 88 px/s stuck, which is a bot jostling for the ball.
	if pressed > COACH_TICK * 0.6 and moved < COACH_TICK * 44.0 then
		b.stuck = b.stuck + 1
		if b.stuck >= STUCK_TICKS then
			b.stuck = 0
			b.stuck_until = now + 1.1
			-- eight probes, walk towards the most open direction
			local ignore = moving_bodies()
			local best, best_len = 0.0, -1.0
			for k = 0, 7 do
				local a = k * math.pi / 4.0
				local dx, dy = math.cos(a), math.sin(a)
				local free = probe(p.x, p.y, dx, dy, ignore) or 400.0
				-- prefer open space that also points back towards the pitch
				local towards = ((geo.cx - p.x) * dx + (geo.cy - p.y) * dy) / math.max(dist(p.x, p.y, geo.cx, geo.cy), 1.0)
				local score = math.min(free, 400.0) + towards * 120.0
				if score > best_len then best, best_len = a, score end
			end
			b.escape_x = clampf(p.x + math.cos(best) * 150.0, geo.x0 + 30, geo.x1 - 30)
			b.escape_y = clampf(p.y + math.sin(best) * 150.0, geo.y0 + 30, geo.y1 - 30)
		end
	else
		b.stuck = 0
	end
end

function coach_tick()
	if not IS_HOST then return end
	if #bot_order == 0 then return end
	if not ensure_geometry() then return end

	local bp = get_value("", "*ball", "position")
	if bp == nil then return end
	local bv = get_value("", "*ball", "linear_velocity")
	local bx, by = bp.x, bp.y
	local bvx, bvy = bv and bv.x or 0.0, bv and bv.y or 0.0

	tick_clock = tick_clock + COACH_TICK
	local now = tick_clock

	-- Is the ball just sitting there untouched?  Used to take over from an
	-- idle human team-mate instead of standing next to him forever.
	local drift = dist(bx, by, last_ball_x or bx, last_ball_y or by)
	local bspeed = vlen(bvx, bvy)
	-- Two different questions, two thresholds.  "Nobody has touched it" wants a
	-- dead ball; "nobody CAN play it" has to also catch a ball being jostled on
	-- the spot between two bodies, which never fully stops.
	-- drift is the distance covered since the last tick, so like check_stuck it is
	-- written as a rate: flat pixels would quietly mean a different speed at every
	-- coach rate (at 0.25 s the old 22 px would have called 88 px/s "stalled").
	if bspeed < 12.0 and drift < COACH_TICK * 16.0 then ball_still = ball_still + COACH_TICK else ball_still = 0.0 end
	if bspeed < 40.0 and drift < COACH_TICK * 44.0 then ball_stalled = ball_stalled + COACH_TICK else ball_stalled = 0.0 end
	last_ball_x, last_ball_y = bx, by
	for t = 1, 2 do
		team_state[t].ball_idle = ball_still > 2.5   -- take over from an idle human
		team_state[t].ball_jam = ball_stalled > 3.5  -- nobody can play it: force it free
	end

	local players = gather_players()
	if #players == 0 then return end
	for i = 1, #players do
		local p = players[i]
		p.t_int, p.i_x, p.i_y = intercept(p, bx, by, bvx, bvy)
		if p.bot then check_stuck(p, now) end
	end

	for team = 1, 2 do
		plan_team(team, players, bx, by, now)
	end
end

-- ================================================================  roster ----

local function team_bot_count(team)
	local n = 0
	for i = 1, #bot_order do
		local b = bots[bot_order[i]]
		if b ~= nil and b.team == team then n = n + 1 end
	end
	return n
end

-- Kickoff / after a goal: bots spawn like players, at a random point in their
-- team's spawn area (same polygon user.lua's reset_position uses).
function get_kickoff_position(bot_name)
	local b = bots[bot_name]
	if b == nil then return nil end
	return get_random_position_in_polygon(b.team == 1 and "red_spawn_area" or "blue_spawn_area")
end

function add_bot(team, btype)
	if not IS_HOST then return end
	team = math.floor(team)
	btype = math.floor(btype)
	if team ~= 1 and team ~= 2 then return end
	if team_bot_count(team) >= MAX_BOTS_PER_TEAM then
		create_panel({ text = "{bot_limit_reached}", title = "{bot_management}" })
		return
	end
	if not ensure_geometry() then
		create_panel({ text = "{bot_no_pitch}", title = "{bot_management}" })
		return
	end

	bot_seq = bot_seq + 1
	local label = "Bot " .. tostring(bot_seq) .. " (" .. (DIFF_TOKENS[difficulty] or DIFF_TOKENS[2]) .. ")"
	local spawn_pos = get_random_position_in_polygon(team == 1 and "red_spawn_area" or "blue_spawn_area")
	local bot_name = spawn_entity_host({
		t = "bot",
		p = spawn_pos,
		team = team,
		btype = btype,
		label = label,
	})
	if bot_name == nil or bot_name == "" then return end

	bots[bot_name] = {
		name = bot_name, team = team, btype = btype, label = label,
		role = nil, lane = 0.5, lane_index = 1,
		stuck = 0, stuck_until = -1.0,
		escape_x = x, escape_y = y, last_x = x, last_y = y, want_x = x, want_y = y,
	}
	bot_order[#bot_order + 1] = bot_name
	team_state[team].dirty = true
	assign_roles(team)

	-- The scoreboard is keyed by entity name, so a bot can score, assist and be
	-- clicked exactly like a player.
	run_function("-ui_manager", "add_bot_to_scoreboard", { bot_name, label, team })
	start_coach()
	refresh_bot_panel()
end

-- Drops the roster entry only (the entity is already gone or about to be).
function forget_bot(bot_name)
	local b = bots[bot_name]
	if b == nil then return end
	bots[bot_name] = nil
	for i = 1, #bot_order do
		if bot_order[i] == bot_name then table.remove(bot_order, i) break end
	end
	for t = 1, 2 do
		if team_state[t].chaser == bot_name then team_state[t].chaser = nil end
		if team_state[t].action_for == bot_name then team_state[t].action = nil end
	end
	team_state[b.team].dirty = true
	assign_roles(b.team)
	run_function("-ui_manager", "remove_user_from_scoreboard", { bot_name })
end

function remove_bot(bot_name)
	if not IS_HOST then return end
	if bots[bot_name] == nil then return end
	forget_bot(bot_name)
	destroy("", bot_name)
	if #bot_order == 0 then stop_coach() end
	refresh_bot_panel()
end

function remove_last_bot(team)
	if not IS_HOST then return end
	team = math.floor(team)
	for i = #bot_order, 1, -1 do
		local b = bots[bot_order[i]]
		if b ~= nil and b.team == team then
			remove_bot(bot_order[i])
			return
		end
	end
end

function remove_all_bots()
	if not IS_HOST then return end
	for i = #bot_order, 1, -1 do
		remove_bot(bot_order[i])
	end
end

function set_bot_team(bot_name, team)
	if not IS_HOST then return end
	local b = bots[bot_name]
	if b == nil then return end
	team = math.floor(team)
	if team ~= 1 and team ~= 2 then return end
	local old = b.team
	b.team = team
	team_state[old].dirty = true
	team_state[team].dirty = true
	assign_roles(old)
	assign_roles(team)
	run_network_function(bot_name, "set_team_ALL", { team })
	run_function("-ui_manager", "move_team", { bot_name, team })
	refresh_bot_panel()
end

function set_bot_type(bot_name, btype)
	if not IS_HOST then return end
	local b = bots[bot_name]
	if b == nil then return end
	b.btype = math.floor(btype)
	team_state[b.team].dirty = true
	assign_roles(b.team)
	refresh_bot_panel()
end

function start_coach()
	if coach_on or not IS_HOST then return end
	coach_on = true
	start_timer({
		timer_id = "football_bot_coach",
		entity_name = name,
		function_name = "coach_tick",
		wait_time = COACH_TICK,
	})
end

function stop_coach()
	if not coach_on then return end
	coach_on = false
	stop_timer("football_bot_coach")
end

-- ==================================================================  panel ---

local TYPE_TOKENS = { [TYPE_BOTH] = "{bot_type_both}", [TYPE_GK] = "{bot_type_gk}", [TYPE_FIELD] = "{bot_type_field}" }
local TYPE_FROM_TOKEN = { ["{bot_type_both}"] = TYPE_BOTH, ["{bot_type_gk}"] = TYPE_GK, ["{bot_type_field}"] = TYPE_FIELD }
local TEAM_FROM_TOKEN = { ["{bot_team_red}"] = 1, ["{bot_team_blue}"] = 2 }
local DIFF_FROM_TOKEN = { ["{bot_diff_easy}"] = 1, ["{bot_diff_normal}"] = 2, ["{bot_diff_hard}"] = 3 }

local function roster_text()
	local red, blue = {}, {}
	for i = 1, #bot_order do
		local b = bots[bot_order[i]]
		if b ~= nil then
			local line = b.label .. " (" .. (TYPE_TOKENS[b.btype] or "?") .. ")"
			if b.team == 1 then red[#red + 1] = line else blue[#blue + 1] = line end
		end
	end
	local text = "{bot_team_red}: " .. tostring(#red) .. "\n"
	for i = 1, #red do text = text .. "  - " .. red[i] .. "\n" end
	text = text .. "{bot_team_blue}: " .. tostring(#blue) .. "\n"
	for i = 1, #blue do text = text .. "  - " .. blue[i] .. "\n" end
	return text
end

function refresh_bot_panel()
	if is_panel_exists(BOT_PANEL) then
		update_panel_settings(BOT_PANEL, { text = roster_text() })
	end
end

function show_bot_panel()
	if not IS_HOST then return end
	BOT_PANEL = create_panel({
		title = "{bot_management}",
		text = roster_text(),
		name = BOT_PANEL,
		no_multiple_tag = "football_bot_panel",
		resizable = true,
		is_scrollable = true,
		minimum_size = Vector2(340, 400),
	})

	add_optionbox_to_panel(BOT_PANEL, {
		text = "{team}",
		options = { "{bot_team_red}", "{bot_team_blue}" },
		entity_name = name,
		function_name = "panel_noop",
	})
	add_optionbox_to_panel(BOT_PANEL, {
		text = "{bot_type}",
		options = { "{bot_type_both}", "{bot_type_gk}", "{bot_type_field}" },
		entity_name = name,
		function_name = "panel_noop",
	})
	add_optionbox_to_panel(BOT_PANEL, {
		text = "{bot_difficulty}",
		options = DIFF_TOKENS,
		default_value = DIFF_TOKENS[difficulty],
		entity_name = name,
		function_name = "panel_difficulty",
	})
	add_button_to_panel(BOT_PANEL, {
		text = "{add_bot}", is_vertical = true, color = Color(0, 0.7, 0.2),
		entity_name = name, function_name = "panel_add",
	})
	add_button_to_panel(BOT_PANEL, {
		text = "{remove_bot}", is_vertical = true, color = Color(0.8, 0.4, 0),
		entity_name = name, function_name = "panel_remove",
	})
	add_button_to_panel(BOT_PANEL, {
		text = "{remove_all_bots}", is_vertical = true, color = Color(0.8, 0.1, 0.1),
		entity_name = name, function_name = "panel_remove_all",
	})
end

-- Panel widget values arrive keyed by the widget's RAW text - the token itself.
function panel_noop()
end

function panel_difficulty(args)
	difficulty = DIFF_FROM_TOKEN[args["{bot_difficulty}"]] or 2
end

function panel_add(args)
	difficulty = DIFF_FROM_TOKEN[args["{bot_difficulty}"]] or difficulty
	add_bot(TEAM_FROM_TOKEN[args["{team}"]] or 1, TYPE_FROM_TOKEN[args["{bot_type}"]] or TYPE_BOTH)
end

function panel_remove(args)
	remove_last_bot(TEAM_FROM_TOKEN[args["{team}"]] or 1)
end

function panel_remove_all()
	remove_all_bots()
end

-- ===================================================================  init ---

tick_clock = 0.0
ball_still = 0.0
ball_stalled = 0.0
last_ball_x = nil
last_ball_y = nil
math.randomseed(math.floor(get_os_time_unix()))

-- A freshly hosted pitch starts with one bot a side, so whoever walks in first
-- has someone to play against instead of an empty field.  Startup only: the host
-- can remove them from the bot panel and they are never put back - not after a
-- goal, a new match or a player joining.
--
-- On a timer because add_bot needs the pitch, and the pitch is measured with
-- raycasts against a map that is still loading while this runs; each tick just
-- retries until build_geometry finally succeeds.
auto_bots_done = false

function spawn_starting_bots(args)
	if not IS_HOST or auto_bots_done then return end
	if not ensure_geometry() then
		-- Out of retries: leave the pitch empty rather than nag the host.
		if args ~= nil and args.is_last_iteration then auto_bots_done = true end
		return
	end
	auto_bots_done = true
	add_bot(1, TYPE_BOTH)
	add_bot(2, TYPE_BOTH)
end

if IS_HOST then
	start_timer({
		timer_id = "football_starting_bots",
		entity_name = name,
		function_name = "spawn_starting_bots",
		wait_time = 0.5,
		duration = 5.0,
	})
end

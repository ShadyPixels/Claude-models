--!nonstrict
--[[
	PullUpMotion

	The choreography. Given a session (when it started, the tempo, when the
	player let go ...) and a time, returns the pose parameters PullUpRig:solve
	needs. Everything is a pure function of server time, so every client draws
	the same frame for the same moment and the motion stays in sync without
	streaming poses over the network.

	One session:
		mount     crouch, reach up, jump and catch the bar, settle      (MOUNT_TIME)
		reps      pull up -> squeeze at the top -> lower -> settle      (tempo per rep)
		dismount  let go, drop, absorb the landing, stand up            (DISMOUNT_TIME)
]]

local Motion = {}

Motion.MOUNT_TIME = 0.8
Motion.DISMOUNT_TIME = 0.75

local FALL = 0.3 -- drop until the feet touch
local ABSORB = 0.16 -- knees soak up the landing

-- Rep timing as fractions of one rep.
local UP_END = 0.36 -- chin reaches the bar
local HOLD_END = 0.48 -- squeeze at the top
local DOWN_END = 0.86 -- arms straight again; the rest is a small settle
Motion.TOP = (UP_END + HOLD_END) / 2 -- the moment a rep counts

local rad = math.rad
local sin = math.sin
local PI = math.pi

local function clamp01(x)
	return math.clamp(x, 0, 1)
end

-- zero velocity and acceleration at both ends: the core of the "fluid" feel
local function smoother(x)
	x = clamp01(x)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

local function easeOutCubic(x)
	x = clamp01(x)
	local i = 1 - x
	return 1 - i * i * i
end

local function easeInQuad(x)
	x = clamp01(x)
	return x * x
end

local function lerp(a, b, t)
	return a + (b - a) * t
end

-- Body height through one rep: 0 = dead hang, 1 = chin over the bar.
function Motion.rise(p)
	if p < UP_END then
		return smoother(p / UP_END)
	elseif p < HOLD_END then
		local x = (p - UP_END) / (HOLD_END - UP_END)
		return 1 + 0.035 * sin(PI * x) ^ 2
	elseif p < DOWN_END then
		return 1 - smoother((p - HOLD_END) / (DOWN_END - HOLD_END))
	else
		local x = (p - DOWN_END) / (1 - DOWN_END)
		return -0.06 * sin(PI * x) ^ 2
	end
end

local function riseVelocity(p)
	local e = 1e-3
	return (Motion.rise(math.min(p + e, 0.9999)) - Motion.rise(math.max(p - e, 0))) / (2 * e)
end

---------------------------------------------------------------------------
-- parameter tables
---------------------------------------------------------------------------

local NUM_KEYS = {
	"pitch", "roll", "waist", "head", "grip", "plant", "splay",
	"hipL", "hipR", "kneeL", "kneeR", "ankleL", "ankleR",
}

local function blend(a, b, t)
	local out = {
		shoulder = a.shoulder:Lerp(b.shoulder, t),
		footOffset = a.footOffset:Lerp(b.footOffset, t),
	}
	for _, k in NUM_KEYS do
		out[k] = lerp(a[k], b[k], t)
	end
	return out
end
Motion.blend = blend

local function copy(a)
	return blend(a, a, 0)
end

---------------------------------------------------------------------------
-- context: everything that depends on the avatar + bar, computed once
---------------------------------------------------------------------------

function Motion.context(rig, standCF, grips, floor)
	local ctx = { rig = rig, standCF = standCF, grips = grips, floor = floor }
	local up = standCF.UpVector
	ctx.up = up
	ctx.look = standCF.LookVector
	ctx.gripMid = (grips.Left + grips.Right) / 2

	local armL, armR = rig.arms.Left, rig.arms.Right
	local reach = ((armL.l1 + armL.l2 + armL.l3) + (armR.l1 + armR.l2 + armR.l3)) / 2
	local gripHalf = (grips.Left - grips.Right).Magnitude / 2
	local dx = gripHalf - rig.shoulderHalfWidth

	-- how far the torso sits behind the bar (towards the camera), bottom and top.
	-- At the top the head and chest must clear the bar.
	ctx.backBottom = 0.35
	ctx.backTop = math.max(0.85, rig.headHalfDepth + 0.35, rig.torsoHalfDepth + 0.4)

	-- dead hang: arms almost straight
	local r = reach * 0.94 -- leaves room for the settle dip below dead hang
	local gripY = (ctx.gripMid - floor):Dot(up)
	local standShoulderH = (rig:standShoulder(standCF) - floor):Dot(up)
	-- keep the feet off the floor for very tall avatars
	local lowest = standShoulderH * 0.97 + 0.2 - gripY
	local function bottomFor(back)
		local vertical = math.sqrt(math.max(0.04, r * r - dx * dx - back * back))
		return math.max(-vertical, lowest)
	end
	ctx.dyBottom = bottomFor(ctx.backBottom)
	-- Short arms leave the head near the bar even at the bottom: hang further
	-- behind the bar so the head never touches it.
	local headTop = ctx.dyBottom + rig.neckAboveShoulder + rig.headHeight
	if headTop > -0.45 then
		ctx.backBottom = math.max(ctx.backBottom, rig.headHalfDepth + 0.38)
		ctx.dyBottom = bottomFor(ctx.backBottom)
	end
	-- top: the chin (neck joint) clears the bar
	ctx.dyTop = math.max(0.36 - rig.neckAboveShoulder, ctx.dyBottom + 0.6)

	ctx.standShoulder = rig:standShoulder(standCF)
	ctx.stand = {
		shoulder = ctx.standShoulder,
		footOffset = Vector3.new(),
		pitch = 0, roll = 0, waist = 0, head = 0, grip = 0, plant = 0, splay = 0,
		hipL = 0, hipR = 0, kneeL = 0, kneeR = 0, ankleL = 0, ankleR = 0,
	}
	ctx.crouch = copy(ctx.stand)
	ctx.crouch.shoulder = ctx.standShoulder - up * 0.45 + ctx.look * 0.12
	ctx.crouch.pitch = rad(-8)
	ctx.crouch.head = rad(14)
	ctx.crouch.plant = 1
	return ctx
end

---------------------------------------------------------------------------
-- hanging pose for a rise value
---------------------------------------------------------------------------

local function hang(ctx, r, v, t)
	local rc = clamp01(r)
	local kick = math.clamp(v / 5, -1, 1) -- + while pulling up, - while lowering
	local kickUp = math.max(kick, 0)
	local kickDown = math.max(-kick, 0)
	local sway = sin(t * 2 * PI / 2.8)

	local dy = lerp(ctx.dyBottom, ctx.dyTop, r)
	local back = lerp(ctx.backBottom, ctx.backTop, 1 - (1 - rc) ^ 2.6)
	return {
		shoulder = ctx.gripMid + ctx.up * dy - ctx.look * back,
		footOffset = Vector3.new(),
		pitch = rad(lerp(3, 13, rc) + 1.4 * sway - 3 * kickDown),
		roll = rad(0.8 * sin(t * 2 * PI / 3.7)),
		waist = rad(lerp(2, 7, rc)),
		-- look up at the bar on the way up, chin over at the top
		head = rad(lerp(12, 3, rc) + 14 * sin(PI * rc) * (1 - rc * 0.4)),
		grip = 1,
		plant = 0,
		splay = rad(3 + 2 * kickUp),
		-- knees bent, ankles crossed-ish, legs kick a little as you pull
		hipL = rad(14 + 12 * kickUp - 8 * kickDown + 3 * sway),
		hipR = rad(9 + 12 * kickUp - 8 * kickDown + 3 * sway),
		kneeL = rad(42 + 16 * kickUp - 6 * kickDown),
		kneeR = rad(30 + 16 * kickUp - 6 * kickDown),
		ankleL = rad(24),
		ankleR = rad(18),
	}
end

-- Rise and rise velocity at time `now` (no mount / dismount)
local function repState(s, now)
	if s.mode == "Tap" then
		if not s.repStart then
			return 0, 0
		end
		local p = (now - s.repStart) / s.tempo
		if p < 0 or p >= 1 then
			return 0, 0
		end
		return Motion.rise(p), riseVelocity(p)
	end
	local p = ((now - s.startTime) / s.tempo) % 1
	return Motion.rise(p), riseVelocity(p)
end

-- Mount + reps (everything except letting go)
local function sampleOnBar(ctx, s, now)
	local tau = now - s.mountStart
	local P
	if tau >= Motion.MOUNT_TIME then
		local r, v = repState(s, now)
		P = hang(ctx, r, v, now)
	else
		local hang0 = hang(ctx, 0, 0, s.mountStart + Motion.MOUNT_TIME)
		if tau < 0.26 then
			-- crouch and reach for the bar
			P = blend(ctx.stand, ctx.crouch, smoother(tau / 0.26))
		elseif tau < 0.66 then
			-- jump and catch
			local x = (tau - 0.26) / 0.4
			P = blend(ctx.crouch, hang0, 1 - (1 - x) ^ 2)
			P.shoulder += ctx.up * (0.06 * sin(PI * x))
			local tuck = rad(28) * sin(PI * x)
			P.kneeL += tuck
			P.kneeR += tuck
			P.hipL += tuck * 0.6
			P.hipR += tuck * 0.6
			P.plant = 1 - smoother(x / 0.65)
		else
			-- the catch: body swings and settles under the bar
			local x = (tau - 0.66) / (Motion.MOUNT_TIME - 0.66)
			P = hang(ctx, -0.07 * sin(PI * x) ^ 2, 0, now)
			P = blend(hang0, P, smoother(x * 3))
		end
		P.grip = smoother(tau / 0.48)
		-- slide in from wherever the player stood when they started
		if s.entry then
			local k = 1 - smoother(tau / 0.4)
			P.shoulder += s.entry * k
			P.footOffset += s.entry * k
		end
	end
	return P
end

function Motion.sample(ctx, s, now)
	if not s.dismountStart or now < s.dismountStart then
		return sampleOnBar(ctx, s, now)
	end
	local tau = now - s.dismountStart
	if tau >= Motion.DISMOUNT_TIME then
		return copy(ctx.stand)
	end
	local from = sampleOnBar(ctx, s, s.dismountStart)
	local up, look = ctx.up, ctx.look
	local touch = copy(ctx.stand)
	touch.shoulder = ctx.standShoulder - up * 0.05
	touch.pitch = rad(-4)
	touch.head = rad(6)
	touch.plant = 1
	local land = copy(ctx.crouch)
	land.shoulder = ctx.standShoulder - up * 0.55 + look * 0.05
	land.pitch = rad(-10)
	local release = from.grip * (1 - smoother(tau / 0.42))
	local P
	if tau < FALL then
		-- let go and drop; legs reach for the floor
		local x = tau / FALL
		local e = easeInQuad(x)
		-- drop first; lean and drift under the bar only once the head is below it
		P = blend(from, touch, x ^ 6)
		local delta = touch.shoulder - from.shoulder
		local vertical = up * delta:Dot(up)
		P.shoulder = from.shoulder + vertical * e + (delta - vertical) * (x ^ 6)
		P.plant = smoother((x - 0.15) / 0.85)
	elseif tau < FALL + ABSORB then
		-- knees soak up the landing
		local x = (tau - FALL) / ABSORB
		P = blend(touch, land, easeOutCubic(x))
	else
		-- stand back up
		local x = (tau - FALL - ABSORB) / (Motion.DISMOUNT_TIME - FALL - ABSORB)
		P = blend(land, ctx.stand, smoother(x))
		P.plant = 1 - smoother((x - 0.6) / 0.4)
	end
	P.grip = release
	return P
end

-- Whole seconds of motion for a session that is still running
function Motion.isDone(s, now)
	return s.dismountStart ~= nil and now >= s.dismountStart + Motion.DISMOUNT_TIME
end

return Motion

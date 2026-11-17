--!nonstrict
--[[
	ThrowPoses: the throw choreography as editable keyframes.

	This is the file to revise. Change a number, press Play, and the throw,
	the cinematic camera and the VFX all follow it, because they read the same
	timeline. (Or bake it with Tools/BakeThrowAnimation and revise it in the
	Animation Editor instead; see the README.)

	Times are in seconds at Config.Speed = 1. Angles are in degrees, distances
	in studs. A channel left out of a key counts as 0 (the standing pose).
	Keys are joined with smooth Catmull-Rom curves, so motion never snaps.

	Thrower channels
		drop        lower the hips (negative = crouch)
		pitch       whole-body lean (+ back, - forward). Feet stay planted.
		roll        whole-body side lean (+ right)
		waistPitch  bend at the waist (+ arch back)
		waistYaw    twist the upper body (+ left, the spin direction)
		neckPitch   head (+ look up)
		neckYaw     head turn (+ left)
		shoulderFwd raise both arms forward (90 = straight ahead, 180 = overhead)
		shoulderIn  bring the hands together (+) or apart (-)
		armLead     right arm higher than the left (+)
		elbow       elbow bend
		wrist       wrist bend
		stance      extra foot width (studs)
		footFwd     feet ahead of the hips (studs), for leaning back against the spin
]]

return {
	-- Timeline (seconds)
	Timing = {
		Yank = 0.22, -- the ragdoll slides to the thrower's feet
		Grab = 0.3, -- hands close on its ankles
		SpinStart = 0.5, -- lifted; the spin begins
		Release = 2.45, -- let go
		End = 3.45, -- back to standing
	},

	-- Spin: the thrower turns SpinTurns times (Config) before letting go, speeding
	-- up along this curve (higher = slower start, faster finish), then spins one
	-- more decelerating turn in the follow-through and ends facing the throw.
	SpinCurve = 2.2,

	-- How the held ragdoll flies outwards: lower gravity = it lifts level sooner.
	HeldGravity = 30,

	Keys = {
		{ t = 0.0 },
		{ t = 0.14, drop = -0.15, pitch = -6, waistPitch = -6, neckPitch = -14, shoulderFwd = 22, elbow = 12 },
		{ t = 0.3, drop = -1.15, pitch = -26, waistPitch = -20, neckPitch = -10, shoulderFwd = 70,
			shoulderIn = 14, elbow = 10, wrist = -10, stance = 0.25, footFwd = -0.1 },
		{ t = 0.5, drop = -0.5, pitch = 12, waistPitch = 4, neckPitch = -8, shoulderFwd = 82, shoulderIn = 16,
			elbow = 8, stance = 0.35, footFwd = 0.35 },
		{ t = 1.4, drop = -0.62, pitch = 19, roll = -4, waistPitch = 6, waistYaw = 10, neckPitch = -4,
			shoulderFwd = 80, shoulderIn = 14, elbow = 4, stance = 0.45, footFwd = 0.6 },
		{ t = 2.2, drop = -0.78, pitch = 26, roll = -8, waistPitch = 8, waistYaw = 20, neckPitch = 0,
			shoulderFwd = 78, shoulderIn = 12, elbow = 2, stance = 0.5, footFwd = 0.8 },
		-- the whip: upper body snaps through, arms fling up and over
		{ t = 2.45, drop = -0.32, pitch = 4, roll = 5, waistPitch = -4, waistYaw = -32, neckPitch = 16,
			shoulderFwd = 132, shoulderIn = -12, armLead = 18, elbow = 10, stance = 0.5, footFwd = 0.3 },
		{ t = 2.72, drop = -0.7, pitch = -14, roll = 3, waistPitch = -14, waistYaw = -18, neckPitch = 6,
			shoulderFwd = 45, shoulderIn = -26, armLead = -10, elbow = 32, stance = 0.42, footFwd = -0.1 },
		{ t = 3.1, drop = -0.18, pitch = -3, waistPitch = -3, shoulderFwd = 12, elbow = 12, stance = 0.12 },
		{ t = 3.45 },
	},

	-- The ragdoll while it is held (it flails with these amplitudes)
	Victim = {
		ArmFling = 160, -- arms thrown back over the head by the spin
		ArmFlail = 22,
		HeadLoll = 18,
		BodyWobble = 8,
	},
}

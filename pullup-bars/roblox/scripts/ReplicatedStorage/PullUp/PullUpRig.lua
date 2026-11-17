--!nonstrict
--[[
	PullUpRig

	Measures an R15 character and turns high-level pose parameters (where the
	shoulders are, how far the torso leans, how bent the knees are ...) into
	Motor6D.Transform values.

	The arms are solved with two-bone IK every frame, so the hands stay locked
	on the grip bar for any avatar size or body proportions. The legs use IK
	only while the feet are planted (crouch / landing) and simple FK while
	hanging.

	Nothing here touches the network or RunService; it is pure math, so the
	same code drives the live animation (PullUpClient) and the bake tool.
]]

local PullUpRig = {}
PullUpRig.__index = PullUpRig

local IDENTITY = CFrame.new()
local UP = Vector3.new(0, 1, 0)
local X_AXIS = Vector3.new(1, 0, 0)

-- Motor6D name -> the part it lives in (its Part1)
PullUpRig.MOTORS = {
	{ part = "LowerTorso", name = "Root" },
	{ part = "UpperTorso", name = "Waist" },
	{ part = "Head", name = "Neck" },
	{ part = "LeftUpperArm", name = "LeftShoulder" },
	{ part = "LeftLowerArm", name = "LeftElbow" },
	{ part = "LeftHand", name = "LeftWrist" },
	{ part = "RightUpperArm", name = "RightShoulder" },
	{ part = "RightLowerArm", name = "RightElbow" },
	{ part = "RightHand", name = "RightWrist" },
	{ part = "LeftUpperLeg", name = "LeftHip" },
	{ part = "LeftLowerLeg", name = "LeftKnee" },
	{ part = "LeftFoot", name = "LeftAnkle" },
	{ part = "RightUpperLeg", name = "RightHip" },
	{ part = "RightLowerLeg", name = "RightKnee" },
	{ part = "RightFoot", name = "RightAnkle" },
}

local ARMS = {
	Left = { "LeftShoulder", "LeftElbow", "LeftWrist", sign = -1 },
	Right = { "RightShoulder", "RightElbow", "RightWrist", sign = 1 },
}
local LEGS = {
	Left = { "LeftHip", "LeftKnee", "LeftAnkle", sign = -1 },
	Right = { "RightHip", "RightKnee", "RightAnkle", sign = 1 },
}

---------------------------------------------------------------------------
-- math helpers
---------------------------------------------------------------------------

-- Rotation whose Y axis points along `dir` and whose X axis is as close to
-- `hinge` as possible. Bones are matched by mapping a local basis onto a
-- world basis built the same way.
local function basis(hinge, dir)
	local b = dir.Unit
	local x = hinge - b * hinge:Dot(b)
	if x.Magnitude < 1e-5 then
		x = UP:Cross(b)
		if x.Magnitude < 1e-5 then
			x = X_AXIS
		end
	end
	x = x.Unit
	return CFrame.fromMatrix(Vector3.new(), x, b, x:Cross(b))
end

-- Two-bone IK. a = root joint, c = desired end joint, pole = which way the
-- middle joint should point. Returns middle joint, reachable end joint and
-- the hinge axis of the chain.
local function solveChain(a, c, l1, l2, pole)
	local ac = c - a
	local d = ac.Magnitude
	local dir = d > 1e-4 and ac / d or -UP
	-- Soft IK: ease into full extension instead of snapping straight, which
	-- removes the classic knee/elbow "pop" when a limb is nearly straight.
	local maxD = l1 + l2 - 1e-3
	local soft = 0.05 * (l1 + l2)
	if d > maxD - soft then
		d = maxD - soft + soft * (1 - math.exp(-(d - (maxD - soft)) / soft))
	end
	d = math.max(d, math.abs(l1 - l2) + 1e-3)
	c = a + dir * d
	local along = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, l1 * l1 - along * along))
	local toPole = pole - a
	local perp = toPole - dir * toPole:Dot(dir)
	if perp.Magnitude < 1e-5 then
		perp = dir:Cross(X_AXIS)
		if perp.Magnitude < 1e-5 then
			perp = dir:Cross(UP)
		end
	end
	perp = perp.Unit
	local b = a + dir * along + perp * h
	local n = (b - a):Cross(c - b)
	if n.Magnitude < 1e-6 then
		n = -(c - a):Cross(toPole)
	end
	if n.Magnitude < 1e-6 then
		n = X_AXIS
	end
	return b, c, n.Unit
end

-- World CFrame of a bone whose joint (jointLocal, in the part's space) sits at
-- `joint`, pointing along `dir`, with its hinge on `hinge`.
local function placeBone(joint, dir, hinge, localBasis, jointLocal)
	local r = basis(hinge, dir) * localBasis:Inverse()
	return CFrame.new(joint) * r * CFrame.new(-jointLocal)
end

local function unitOr(v, fallback)
	if v.Magnitude < 1e-5 then
		return fallback
	end
	return v.Unit
end

---------------------------------------------------------------------------
-- construction
---------------------------------------------------------------------------

-- Returns a rig, or nil plus a reason when the character can't do pull-ups.
function PullUpRig.new(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil, "no Humanoid"
	end
	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return nil, "R15 character required"
	end
	local hrp = character:FindFirstChild("HumanoidRootPart")
	local head = character:FindFirstChild("Head")
	local upperTorso = character:FindFirstChild("UpperTorso")
	if not (hrp and head and upperTorso) then
		return nil, "character not loaded"
	end

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		hrp = hrp,
		motors = {},
		c0 = {},
		c1 = {},
	}, PullUpRig)

	for _, j in PullUpRig.MOTORS do
		local part = character:FindFirstChild(j.part)
		local motor = part and part:FindFirstChild(j.name)
		if not (motor and motor:IsA("Motor6D")) then
			return nil, "missing joint " .. j.name
		end
		self.motors[j.name] = motor
		self.c0[j.name] = motor.C0
		self.c1[j.name] = motor.C1
	end

	local c0, c1 = self.c0, self.c1

	-- standing pose relative to the HumanoidRootPart
	self.restLowerTorso = c0.Root * c1.Root:Inverse()
	self.restUpperTorso = self.restLowerTorso * c0.Waist * c1.Waist:Inverse()
	self.restTorsoRot = self.restUpperTorso.Rotation
	self.shoulderMid = (c0.LeftShoulder.Position + c0.RightShoulder.Position) / 2
	self.shoulderHalfWidth = math.abs(c0.LeftShoulder.Position.X - c0.RightShoulder.Position.X) / 2
	self.neckAboveShoulder = c0.Neck.Position.Y - self.shoulderMid.Y
	self.headHalfDepth = head.Size.Z / 2
	self.headHeight = head.Size.Y
	self.torsoHalfDepth = upperTorso.Size.Z / 2
	self.hrpHalfHeight = hrp.Size.Y / 2

	self.arms = {}
	for side, names in ARMS do
		local sh, el, wr = names[1], names[2], names[3]
		local u1 = c0[el].Position - c1[sh].Position
		local u2 = c0[wr].Position - c1[el].Position
		local u3 = -c1[wr].Position
		self.arms[side] = {
			l1 = u1.Magnitude,
			l2 = u2.Magnitude,
			l3 = u3.Magnitude,
			basis1 = basis(X_AXIS, unitOr(u1, -UP)),
			basis2 = basis(X_AXIS, unitOr(u2, -UP)),
			basis3 = basis(X_AXIS, unitOr(u3, -UP)),
		}
	end

	self.legs = {}
	for side, names in LEGS do
		local hip, knee, ankle = names[1], names[2], names[3]
		local u1 = c0[knee].Position - c1[hip].Position
		local u2 = c0[ankle].Position - c1[knee].Position
		local ankleFrame = self.restLowerTorso * c0[hip] * c1[hip]:Inverse() * c0[knee] * c1[knee]:Inverse()
			* c0[ankle]
		self.legs[side] = {
			l1 = u1.Magnitude,
			l2 = u2.Magnitude,
			-- legs bend the other way, so their hinge is -X
			basis1 = basis(-X_AXIS, unitOr(u1, -UP)),
			basis2 = basis(-X_AXIS, unitOr(u2, -UP)),
			restAnkle = ankleFrame.Position, -- relative to the HumanoidRootPart
			restFootRot = (ankleFrame * c1[ankle]:Inverse()).Rotation,
		}
	end

	return self
end

-- Height of the HumanoidRootPart centre above the floor while standing.
function PullUpRig:standHeight()
	return self.humanoid.HipHeight + self.hrpHalfHeight
end

-- World position of the point between the shoulders when standing at standCF.
function PullUpRig:standShoulder(standCF)
	return standCF * (self.restUpperTorso * self.shoulderMid)
end

---------------------------------------------------------------------------
-- bars
---------------------------------------------------------------------------

-- Reads a pull-up bar model. Returns the stand CFrame for this rig (where the
-- HumanoidRootPart is anchored, facing the bar) and the grip points for the
-- character's left and right hands.
function PullUpRig:barFrames(bar)
	local base = bar.PrimaryPart or bar:FindFirstChild("Base", true)
	local gripBar = bar:FindFirstChild("GripBar", true)
	if not (base and gripBar) then
		return nil
	end
	local stand = base:FindFirstChild("StandPoint")
	local ga = gripBar:FindFirstChild("GripLeft")
	local gb = gripBar:FindFirstChild("GripRight")
	if not (stand and ga and gb) then
		return nil
	end
	local baseCF = base.CFrame
	local up = baseCF.UpVector
	local facing = -baseCF.LookVector -- players face into the station
	local floor = (baseCF * stand.CFrame).Position
	local root = floor + up * self:standHeight()
	local standCF = CFrame.lookAt(root, root + facing, up)

	local pa = (gripBar.CFrame * ga.CFrame).Position
	local pb = (gripBar.CFrame * gb.CFrame).Position
	local right = standCF.RightVector
	local grips
	if (pa - pb):Dot(right) > 0 then
		grips = { Right = pa, Left = pb }
	else
		grips = { Right = pb, Left = pa }
	end
	return standCF, grips, floor
end

---------------------------------------------------------------------------
-- solving
---------------------------------------------------------------------------

--[[
	params:
		shoulder    Vector3  world point between the shoulders
		pitch       number   torso lean, + leans back (radians)
		roll        number   torso roll (radians)
		waist       number   upper torso bend over the hips, + arches back
		head        number   head pitch, + looks up
		grip        0..1     how much the hands follow the grips (0 = arms at rest)
		plant       0..1     how much the feet stay planted on the floor (IK)
		footOffset  Vector3  extra offset for planted feet
		hipL/hipR, kneeL/kneeR, ankleL/ankleR, splay   leg FK angles (radians)
]]
function PullUpRig:solve(standCF, grips, p)
	local c0, c1 = self.c0, self.c1
	local T = {}

	-- torso
	local torsoRot = standCF.Rotation * self.restTorsoRot * CFrame.Angles(p.pitch, 0, p.roll or 0)
	local UT = CFrame.new(p.shoulder) * torsoRot * CFrame.new(-self.shoulderMid)
	local waist = CFrame.Angles(p.waist, 0, 0)
	local LT = UT * c1.Waist * waist:Inverse() * c0.Waist:Inverse()
	T.Waist = waist
	T.Root = c0.Root:Inverse() * standCF:Inverse() * LT * c1.Root
	T.Neck = CFrame.Angles(p.head, 0, 0)

	-- arms: IK onto the grips
	local back = -standCF.LookVector
	local down = -standCF.UpVector
	for side, names in ARMS do
		local sh, el, wr = names[1], names[2], names[3]
		local info = self.arms[side]
		local S = (UT * c0[sh]).Position
		local G = grips[side]
		local W = G + unitOr(S - G, down) * info.l3
		local pole = S + standCF.RightVector * (names.sign * 1.4) + back * 0.5 + down * 0.6
		local E, W2, n = solveChain(S, W, info.l1, info.l2, pole)
		local UA = placeBone(S, E - S, n, info.basis1, c1[sh].Position)
		local LA = placeBone(E, W2 - E, n, info.basis2, c1[el].Position)
		local HA = placeBone(W2, unitOr(G - W2, W2 - E), n, info.basis3, c1[wr].Position)
		local w = p.grip
		T[sh] = IDENTITY:Lerp(c0[sh]:Inverse() * UT:Inverse() * UA * c1[sh], w)
		T[el] = IDENTITY:Lerp(c0[el]:Inverse() * UA:Inverse() * LA * c1[el], w)
		T[wr] = IDENTITY:Lerp(c0[wr]:Inverse() * LA:Inverse() * HA * c1[wr], w)
	end

	-- legs: FK while hanging, IK while the feet are planted
	for side, names in LEGS do
		local hip, knee, ankle = names[1], names[2], names[3]
		local isLeft = side == "Left"
		local fkHip = CFrame.Angles(isLeft and p.hipL or p.hipR, 0, names.sign * (p.splay or 0))
		local fkKnee = CFrame.Angles(-(isLeft and p.kneeL or p.kneeR), 0, 0)
		local fkAnkle = CFrame.Angles(-(isLeft and p.ankleL or p.ankleR), 0, 0)
		if p.plant > 1e-3 then
			local info = self.legs[side]
			local H = (LT * c0[hip]).Position
			local A = (standCF * info.restAnkle) + (p.footOffset or Vector3.new())
			local pole = H + standCF.LookVector * 2 + down * 0.5
			local K, A2, n = solveChain(H, A, info.l1, info.l2, pole)
			local UL = placeBone(H, K - H, n, info.basis1, c1[hip].Position)
			local LL = placeBone(K, A2 - K, n, info.basis2, c1[knee].Position)
			local FT = CFrame.new(A2) * standCF.Rotation * info.restFootRot * CFrame.new(-c1[ankle].Position)
			local w = p.plant
			T[hip] = fkHip:Lerp(c0[hip]:Inverse() * LT:Inverse() * UL * c1[hip], w)
			T[knee] = fkKnee:Lerp(c0[knee]:Inverse() * UL:Inverse() * LL * c1[knee], w)
			T[ankle] = fkAnkle:Lerp(c0[ankle]:Inverse() * LL:Inverse() * FT * c1[ankle], w)
		else
			T[hip] = fkHip
			T[knee] = fkKnee
			T[ankle] = fkAnkle
		end
	end

	return T
end

function PullUpRig:apply(T)
	for name, motor in self.motors do
		local t = T[name]
		if t then
			motor.Transform = t
		end
	end
end

-- Shared IK helpers (used by the throw animation too)
PullUpRig.basis = basis
PullUpRig.solveChain = solveChain
PullUpRig.placeBone = placeBone
PullUpRig.unitOr = unitOr

-- World CFrame of every body part for a set of transforms, with the
-- HumanoidRootPart at hrpCF.
function PullUpRig:fk(hrpCF, T)
	local world = { HumanoidRootPart = hrpCF }
	for _, j in PullUpRig.MOTORS do
		local motor = self.motors[j.name]
		local parent = world[motor.Part0.Name]
		world[j.part] = parent * self.c0[j.name] * (T[j.name] or IDENTITY) * self.c1[j.name]:Inverse()
	end
	return world
end

function PullUpRig:reset()
	for _, motor in self.motors do
		motor.Transform = IDENTITY
	end
end

return PullUpRig

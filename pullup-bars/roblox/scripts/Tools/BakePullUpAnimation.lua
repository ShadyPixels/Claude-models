--!nonstrict
--[[
	BakePullUpAnimation  (paste into the Studio command bar)

	Bakes the procedural pull-up into regular KeyframeSequences, in case you
	also want normal Animation assets (thumbnails, cutscenes, NPCs, or your own
	animation pipeline).

	1. Install the PullUp folder in ReplicatedStorage first.
	2. Select an R15 rig in Workspace (Avatar tab > Rig Builder > Block Rig works).
	3. Paste this into the command bar and press Enter.

	It creates ServerStorage.PullUpAnimations with:
		PullUp_Mount     jump up and grab the bar
		PullUp_Loop      one rep, set to loop
		PullUp_Dismount  let go and land
	To publish one: right-click it > Save to Roblox. To edit one: open the
	Animation Editor on the rig and import it.

	The baked keyframes fit the selected rig's proportions. The live system
	(PullUpClient) solves the hands every frame instead, so it fits every avatar.
	The baked root motion assumes the HumanoidRootPart stays still under the bar,
	as the live system does by anchoring it.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Selection = game:GetService("Selection")

local folder = ReplicatedStorage:FindFirstChild("PullUp")
assert(folder, "Put the PullUp folder in ReplicatedStorage first")
local PullUpRig = require(folder.PullUpRig)
local Motion = require(folder.PullUpMotion)
local Config = require(folder.Config)

local FPS = 30
local BAR_HEIGHT = 8.6 -- grip bar height above the mat on the pull-up bar models
local GRIP_HALF = 2.0

local rig = Selection:Get()[1]
assert(rig and rig:IsA("Model"), "Select an R15 rig model first")
local r, why = PullUpRig.new(rig)
assert(r, "Can't bake for this rig: " .. tostring(why))

-- A virtual bar right above the rig, matching the real models
local hrp = rig.HumanoidRootPart
local standCF = CFrame.lookAt(hrp.CFrame.Position, hrp.CFrame.Position + hrp.CFrame.LookVector)
local floor = standCF.Position - standCF.UpVector * r:standHeight()
local gripCenter = floor + standCF.UpVector * BAR_HEIGHT
local grips = {
	Left = gripCenter - standCF.RightVector * GRIP_HALF,
	Right = gripCenter + standCF.RightVector * GRIP_HALF,
}
local ctx = Motion.context(r, standCF, grips, floor)

-- Part1 -> Part0 tree for nesting the poses
local parentOf, motorOf = {}, {}
for _, j in PullUpRig.MOTORS do
	local motor = r.motors[j.name]
	parentOf[j.part] = motor.Part0.Name
	motorOf[j.part] = j.name
end

local function keyframe(time, T)
	local kf = Instance.new("Keyframe")
	kf.Time = time
	local poses = { HumanoidRootPart = Instance.new("Pose") }
	poses.HumanoidRootPart.Name = "HumanoidRootPart"
	poses.HumanoidRootPart.Weight = 0
	poses.HumanoidRootPart.Parent = kf
	local function poseFor(partName)
		if poses[partName] then
			return poses[partName]
		end
		local pose = Instance.new("Pose")
		pose.Name = partName
		pose.CFrame = T[motorOf[partName]] or CFrame.new()
		pose.EasingStyle = Enum.PoseEasingStyle.Linear
		pose.Parent = poseFor(parentOf[partName])
		poses[partName] = pose
		return pose
	end
	for _, j in PullUpRig.MOTORS do
		poseFor(j.part)
	end
	return kf
end

local function bake(name, t0, duration, s, loop)
	local seq = Instance.new("KeyframeSequence")
	seq.Name = name
	seq.Loop = loop
	seq.Priority = Enum.AnimationPriority.Action
	local frames = math.max(2, math.round(duration * FPS))
	for i = 0, frames do
		local time = duration * i / frames
		local params = Motion.sample(ctx, s, t0 + time)
		keyframe(time, r:solve(standCF, grips, params)).Parent = seq
	end
	return seq
end

local out = ServerStorage:FindFirstChild("PullUpAnimations") or Instance.new("Folder")
out.Name = "PullUpAnimations"
out.Parent = ServerStorage
for _, child in out:GetChildren() do
	child:Destroy()
end

local tempo = Config.Tempo
local s = { mode = "Auto", tempo = tempo, mountStart = 0, startTime = Motion.MOUNT_TIME }
local mount = bake("PullUp_Mount", 0, Motion.MOUNT_TIME, s, false)
local loop = bake("PullUp_Loop", Motion.MOUNT_TIME, tempo, s, true)
-- let go from a dead hang (a whole number of reps before t = 0)
local d = { mode = "Auto", tempo = tempo, startTime = -4 * tempo, mountStart = -4 * tempo - Motion.MOUNT_TIME, dismountStart = 0 }
local dismount = bake("PullUp_Dismount", 0, Motion.DISMOUNT_TIME, d, false)
mount.Parent, loop.Parent, dismount.Parent = out, out, out

Selection:Set({ mount, loop, dismount })
print(("[PullUp] Baked 3 animations for %s into ServerStorage.PullUpAnimations"):format(rig.Name))

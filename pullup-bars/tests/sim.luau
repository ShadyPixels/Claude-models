-- Simulates a whole session (mount, reps, dismount) for a synthetic R15 avatar and checks
-- hand lock, bar clearance, floor clearance, smoothness and the final pose.
-- usage (from pullup-bars/): lune run tests/sim.luau [scale] [export.json|""] [mid]
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local K = require("./rigkit")
local V, CF = roblox.Vector3.new, roblox.CFrame.new
local PullUpRig = K.load("PullUpRig")
local Motion = K.load("PullUpMotion")
local scale = tonumber(process.args[1] or "1")
local outPath = process.args[2]; if outPath == "" then outPath = nil end

local bar = K.loadBar("roblox/models/PullUpBar_T1_Basic.rbxmx")
local model, parts = K.makeRig(CF(0, 3.3 * scale + 0.72, -4.2), scale)
local rig = assert(PullUpRig.new(model))
local standCF, grips, floor = rig:barFrames(bar)
print("standCF", standCF.Position, "look", standCF.LookVector, "floor", floor, "gripL", grips.Left, "gripR", grips.Right)
local ctx = Motion.context(rig, standCF, grips, floor)
print(("dyBottom %.3f dyTop %.3f backTop %.3f"):format(ctx.dyBottom, ctx.dyTop, ctx.backTop))

local tempo = 1.8
local reps = 3
local s = { mode = "Auto", tempo = tempo, mountStart = 0, startTime = Motion.MOUNT_TIME,
	entry = parts.HumanoidRootPart.CFrame.Position - standCF.Position }
local dismountAt = Motion.MOUNT_TIME + reps * tempo
if process.args[3] == "mid" then dismountAt += 0.55 end
s.dismountStart = dismountAt
local endT = dismountAt + Motion.DISMOUNT_TIME + 0.8

local barA = (bar:FindFirstChild("GripBar", true)).CFrame
local function boxDist(cf, size, p)
	local l = cf:PointToObjectSpace(p)
	local h = size / 2
	local q = V(math.clamp(l.X, -h.X, h.X), math.clamp(l.Y, -h.Y, h.Y), math.clamp(l.Z, -h.Z, h.Z))
	return (l - q).Magnitude
end
local function barClear(cf, size)
	local m = math.huge
	for i = -40, 40 do
		local p = barA * V(i * 0.11, 0, 0)
		m = math.min(m, boxDist(cf, size, p))
	end
	return m - 0.21
end

local dt = 1 / 60
local prev
local worst = { hand = 0, jump = 0, jumpT = 0, rot = 0, rotT = 0, footMin = math.huge, headClr = math.huge, torsoClr = math.huge, armClr = math.huge }
local frames = {}
local t = 0
local lastT
local nan = false
while t <= endT + 1e-6 do
	local p = Motion.sample(ctx, s, t)
	local T = rig:solve(standCF, grips, p)
	local w = K.fk(rig, PullUpRig.MOTORS, standCF, T)
	for name, cf in w do
		local x, y, z = cf.X, cf.Y, cf.Z
		if x ~= x or y ~= y or z ~= z then nan = true end
	end
	local onBar = t >= Motion.MOUNT_TIME and t < dismountAt
	if onBar and p.grip > 0.999 then
		for _, side in { "Left", "Right" } do
			local e = (w[side .. "Hand"].Position - grips[side]).Magnitude
			if e > worst.hand then worst.hand = e end
		end
		if p.plant < 1e-3 then
			for _, side in { "Left", "Right" } do
				local f = w[side .. "Foot"]
				local bottom = math.huge
				for _, c in { V(-0.5, -0.15, -0.5), V(0.5, -0.15, 0.5), V(-0.5, -0.15, 0.5), V(0.5, -0.15, -0.5) } do
					bottom = math.min(bottom, (f * (c * scale)).Y)
				end
				worst.footMin = math.min(worst.footMin, bottom - floor.Y)
			end
		end
	end
	worst.headClr = math.min(worst.headClr, barClear(w.Head, parts.Head.Size))
	worst.torsoClr = math.min(worst.torsoClr, barClear(w.UpperTorso, parts.UpperTorso.Size))
	if prev then
		for name, cf in w do
			local d = (cf.Position - prev[name].Position).Magnitude
			if d > worst.jump then worst.jump = d; worst.jumpT = t; worst.jumpPart = name end
			local _, ang = (prev[name]:Inverse() * cf):ToAxisAngle()
			if math.abs(ang) > worst.rot then worst.rot = math.abs(ang); worst.rotT = t; worst.rotPart = name end
		end
	end
	prev = w
	if outPath and (not lastT or t - lastT >= 1 / 30 - 1e-6) then
		lastT = t
		local f = {}
		for _, j in { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
			"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
			"RightUpperLeg", "RightLowerLeg", "RightFoot" } do
			local c = { w[j]:GetComponents() }
			for i = 1, 12 do table.insert(f, math.round(c[i] * 1000) / 1000) end
		end
		table.insert(frames, f)
	end
	t += dt
end
-- final transforms vs identity (the player ends exactly in the rest pose)
local Tend = rig:solve(standCF, grips, Motion.sample(ctx, s, endT))
local endDev = 0
for name, tr in Tend do
	local _, a = tr:ToAxisAngle()
	endDev = math.max(endDev, tr.Position.Magnitude + math.abs(a))
end
print(("scale %.2f  NaN=%s  handErr=%.4f  maxStep=%.3f studs @%.2fs (%s)  maxRot=%.1f deg @%.2fs (%s)"):format(
	scale, tostring(nan), worst.hand, worst.jump, worst.jumpT, tostring(worst.jumpPart), math.deg(worst.rot), worst.rotT, tostring(worst.rotPart)))
print(("feet above floor while hanging: %.3f   head-bar clearance: %.3f   torso-bar clearance: %.3f   end pose deviation: %.5f"):format(
	worst.footMin, worst.headClr, worst.torsoClr, endDev))
local fail = nan or worst.hand > 0.08 or worst.headClr < 0 or worst.torsoClr < 0 or worst.footMin < 0 or endDev > 1e-3
print(fail and "FAIL" or "PASS")
if outPath then
	local names = {}
	local sizes = {}
	for _, j in { "HumanoidRootPart", "LowerTorso", "UpperTorso", "Head", "LeftUpperArm", "LeftLowerArm", "LeftHand",
		"RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
		"RightUpperLeg", "RightLowerLeg", "RightFoot" } do
		table.insert(names, j)
		local sz = parts[j].Size
		table.insert(sizes, { sz.X, sz.Y, sz.Z })
	end
	local serde = require("@lune/serde")
	fs.writeFile(outPath, serde.encode("json", { fps = 30, names = names, sizes = sizes, frames = frames,
		mount = Motion.MOUNT_TIME, tempo = tempo, reps = reps, dismount = dismountAt }))
	print("wrote", #frames, "frames")
end
if fail then
	process.exit(1)
end

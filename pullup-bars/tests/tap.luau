local roblox = require("@lune/roblox")
local K = require("./rigkit")
local CF = roblox.CFrame.new
local PullUpRig = K.load("PullUpRig")
local Motion = K.load("PullUpMotion")
local bar = K.loadBar("roblox/models/PullUpBar_T7_Arcane.rbxmx")
local model = K.makeRig(CF(0, 4.02, -4.2), 1)
local rig = PullUpRig.new(model)
local standCF, grips, floor = rig:barFrames(bar)
local ctx = Motion.context(rig, standCF, grips, floor)
local s = { mode = "Tap", tempo = 1.8, mountStart = 0, startTime = Motion.MOUNT_TIME }
local prev, worst, worstT = nil, 0, 0
for i = 0, 8 * 120 do
	local t = i / 120
	if t >= 1.5 and not s.repStart then s.repStart = 1.5 end
	if t >= 4.2 and s.repStart == 1.5 then s.repStart = 4.2 end
	local w = K.fk(rig, PullUpRig.MOTORS, standCF, rig:solve(standCF, grips, Motion.sample(ctx, s, t)))
	if prev then
		for n, cf in w do
			local d = (cf.Position - prev[n].Position).Magnitude
			if d > worst then worst, worstT = d, t end
		end
	end
	prev = w
end
print(("Tap mode on the Arcane bar: max step %.3f studs per 1/120 s at t=%.2f"):format(worst, worstT))

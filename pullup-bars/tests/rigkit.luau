-- shared helpers for the pull-up tests: roblox env, module loader, synthetic R15 rig
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local task = require("@lune/task")
local K = {}
local SRC = "roblox/scripts/ReplicatedStorage/PullUp/"
K.env = {
	Instance = roblox.Instance, Vector3 = roblox.Vector3, Vector2 = roblox.Vector2, CFrame = roblox.CFrame,
	Color3 = roblox.Color3, Enum = roblox.Enum, UDim2 = roblox.UDim2, UDim = roblox.UDim,
	ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint, NumberRange = roblox.NumberRange,
	task = task, tonumber = tonumber, os = os, next = next, math = math, table = table, string = string,
	setmetatable = setmetatable, ipairs = ipairs, pairs = pairs, type = type, typeof = typeof,
	tostring = tostring, print = print, warn = print, error = error, pcall = pcall, assert = assert,
}
function K.load(name, path, extraEnv)
	local env = K.env
	if extraEnv then
		env = table.clone(K.env)
		for k, v in extraEnv do env[k] = v end
	end
	return luau.load(fs.readFile(path or (SRC .. name .. ".lua")), { debugName = name, environment = env })()
end
local V, CF = roblox.Vector3.new, roblox.CFrame.new
-- synthetic R15 (block-like proportions, scale `sc`), HRP at `at`
function K.makeRig(at, sc)
	sc = sc or 1
	local model = roblox.Instance.new("Model")
	model.Name = "Rig"
	local hum = roblox.Instance.new("Humanoid")
	hum.RigType = roblox.Enum.HumanoidRigType.R15
	hum.HipHeight = 2.3 * sc
	hum.Parent = model
	local parts = {}
	local function part(name, size, rel)
		local p = roblox.Instance.new("Part")
		p.Name = name
		p.Size = size * sc
		p.CFrame = at * CF(rel * sc)
		p.Parent = model
		parts[name] = p
		return p
	end
	local hrpY = 3.3
	part("HumanoidRootPart", V(2, 2, 1), V(0, 0, 0))
	part("LowerTorso", V(2, 0.4, 1), V(0, 2.9 - hrpY, 0))
	part("UpperTorso", V(2, 1.6, 1), V(0, 3.9 - hrpY, 0))
	part("Head", V(1.2, 1.2, 1.2), V(0, 5.3 - hrpY, 0))
	for _, s in { -1, 1 } do
		local side = s < 0 and "Left" or "Right"
		part(side .. "UpperArm", V(1, 1.2, 1), V(s * 1.5, 4.1 - hrpY, 0))
		part(side .. "LowerArm", V(1, 1.0, 1), V(s * 1.5, 3.0 - hrpY, 0))
		part(side .. "Hand", V(1, 0.4, 1), V(s * 1.5, 2.3 - hrpY, 0))
		part(side .. "UpperLeg", V(1, 1.2, 1), V(s * 0.5, 2.1 - hrpY, 0))
		part(side .. "LowerLeg", V(1, 1.2, 1), V(s * 0.5, 0.9 - hrpY, 0))
		part(side .. "Foot", V(1, 0.3, 1), V(s * 0.5, 0.15 - hrpY, 0))
	end
	local function motor(name, p0, p1, c0, c1)
		local m = roblox.Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parts[p0]
		m.Part1 = parts[p1]
		m.C0 = CF(c0 * sc)
		m.C1 = CF(c1 * sc)
		m.Parent = parts[p1]
	end
	motor("Root", "HumanoidRootPart", "LowerTorso", V(0, -0.4, 0), V(0, 0, 0))
	motor("Waist", "LowerTorso", "UpperTorso", V(0, 0.2, 0), V(0, -0.8, 0))
	motor("Neck", "UpperTorso", "Head", V(0, 0.8, 0), V(0, -0.6, 0))
	for _, s in { -1, 1 } do
		local side = s < 0 and "Left" or "Right"
		motor(side .. "Shoulder", "UpperTorso", side .. "UpperArm", V(s * 1.0, 0.55, 0), V(-s * 0.5, 0.35, 0))
		motor(side .. "Elbow", side .. "UpperArm", side .. "LowerArm", V(0, -0.6, 0), V(0, 0.5, 0))
		motor(side .. "Wrist", side .. "LowerArm", side .. "Hand", V(0, -0.5, 0), V(0, 0.2, 0))
		motor(side .. "Hip", "LowerTorso", side .. "UpperLeg", V(s * 0.5, -0.2, 0), V(0, 0.6, 0))
		motor(side .. "Knee", side .. "UpperLeg", side .. "LowerLeg", V(0, -0.6, 0), V(0, 0.6, 0))
		motor(side .. "Ankle", side .. "LowerLeg", side .. "Foot", V(0, -0.6, 0), V(0, 0.15, 0))
	end
	return model, parts
end
-- world CFrames of every part for a set of transforms, HRP at hrpCF
function K.fk(rig, MOTORS, hrpCF, T)
	local w = { HumanoidRootPart = hrpCF }
	for _, j in MOTORS do
		local m = rig.motors[j.name]
		w[j.part] = w[m.Part0.Name] * m.C0 * (T[j.name] or CF()) * m.C1:Inverse()
	end
	return w
end
function K.loadBar(path)
	return roblox.deserializeModel(fs.readFile(path))[1]
end
return K

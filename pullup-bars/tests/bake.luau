local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local luau = require("@lune/luau")
local K = require("./rigkit")
local CF = roblox.CFrame.new
local game = roblox.Instance.new("DataModel")
local rs = game:GetService("ReplicatedStorage")
local folder = roblox.Instance.new("Folder"); folder.Name = "PullUp"; folder.Parent = rs
local mods = {}
for _, n in { "PullUpRig", "PullUpMotion", "Config" } do
	local m = roblox.Instance.new("ModuleScript"); m.Name = n; m.Parent = folder
	mods[m] = K.load(n)
end
local model = K.makeRig(CF(0, 3.3, 0), 1)
model.Parent = game:GetService("Workspace")
local selected = { model }
local Selection = { Get = function() return selected end, Set = function(_, t) selected = t end }
local env = table.clone(K.env)
env.game = { GetService = function(_, name) if name == "Selection" then return Selection end return game:GetService(name) end }
env.require = function(m) return mods[m] end
env.print = print
local fn = luau.load(fs.readFile("roblox/scripts/Tools/BakePullUpAnimation.lua"), { debugName = "bake", environment = env })
fn()
local out = game:GetService("ServerStorage"):FindFirstChild("PullUpAnimations")
for _, seq in out:GetChildren() do
	local kfs = seq:GetChildren()
	local poses = #kfs[1]:GetDescendants()
	print(seq.Name, "keyframes", #kfs, "poses/keyframe", poses, "loop", seq.Loop, "last time", kfs[#kfs].Time)
end
local hrpPose = out.PullUp_Loop:GetChildren()[1]:FindFirstChild("HumanoidRootPart")
print("pose tree:", hrpPose.Name, ">", hrpPose:GetChildren()[1].Name, ">", hrpPose:GetChildren()[1]:GetChildren()[1].Name)

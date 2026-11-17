--!nonstrict
--[[
	PullUpClient

	Animates every character that has a "PullUpSession" (created by
	PullUpServer). Motor6D.Transform changes made on a client are only seen by
	that client, so every client animates every hanging player itself. The
	motion is a pure function of server time, so they all match.

	For the local player it also handles letting go (jump), tap-to-rep (when
	Config.Mode is "Tap"), the camera following the body, and a small HUD.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local folder = ReplicatedStorage:WaitForChild("PullUp")
local Config = require(folder:WaitForChild("Config"))
local PullUpRig = require(folder:WaitForChild("PullUpRig"))
local Motion = require(folder:WaitForChild("PullUpMotion"))
local remote = folder:WaitForChild("PullUpRemote")

local player = Players.LocalPlayer
local SESSION_TAG = "PullUpSession"

local tracked = {} -- [session ObjectValue] = entry

local function readSession(obj, entry)
	local s = entry.s
	s.mode = obj:GetAttribute("Mode") or "Auto"
	s.tempo = obj:GetAttribute("Tempo") or 1.8
	s.mountStart = obj:GetAttribute("MountStart") or 0
	s.startTime = obj:GetAttribute("StartTime") or s.mountStart + Motion.MOUNT_TIME
	s.repStart = obj:GetAttribute("RepStart")
	s.dismountStart = obj:GetAttribute("DismountStart")
	s.entry = obj:GetAttribute("Entry")
end

-- Builds the rig + context once the character and bar have streamed in.
local function prepare(obj, entry)
	local character = obj.Parent
	local bar = obj.Value
	if not (character and bar) then
		return false
	end
	local rig = PullUpRig.new(character)
	if not rig then
		return false
	end
	local standCF, grips, floor = rig:barFrames(bar)
	if not standCF then
		return false
	end
	entry.rig = rig
	entry.standCF = standCF
	entry.grips = grips
	entry.ctx = Motion.context(rig, standCF, grips, floor)
	entry.isLocal = Players:GetPlayerFromCharacter(character) == player
	return true
end

---------------------------------------------------------------------------
-- local player HUD
---------------------------------------------------------------------------

local hud
local function showHud(visible, reps)
	if not Config.ShowHud then
		return
	end
	if not hud then
		local gui = Instance.new("ScreenGui")
		gui.Name = "PullUpHud"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = false
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -110)
		label.Size = UDim2.fromOffset(320, 54)
		label.BackgroundColor3 = Color3.fromRGB(12, 15, 24)
		label.BackgroundTransparency = 0.25
		label.TextColor3 = Color3.fromRGB(238, 242, 250)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 20
		label.RichText = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = label
		label.Parent = gui
		gui.Parent = player:WaitForChild("PlayerGui")
		hud = label
	end
	hud.Visible = visible
	if visible then
		local how = Config.Mode == "Tap" and "Click / tap to pull · Jump to let go" or "Jump to let go"
		hud.Text = ("%d reps<br/><font size=\"13\" color=\"#9aa4b8\">%s</font>"):format(reps or 0, how)
	end
end

---------------------------------------------------------------------------
-- shop: toasts and other players' prompts
---------------------------------------------------------------------------

local toastGui
local function toast(kind, text)
	if not toastGui then
		toastGui = Instance.new("ScreenGui")
		toastGui.Name = "PullUpToasts"
		toastGui.ResetOnSpawn = false
		local list = Instance.new("Frame")
		list.Name = "List"
		list.BackgroundTransparency = 1
		list.AnchorPoint = Vector2.new(0.5, 0)
		list.Position = UDim2.new(0.5, 0, 0, 70)
		list.Size = UDim2.fromOffset(360, 200)
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 6)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.Parent = list
		list.Parent = toastGui
		toastGui.Parent = player:WaitForChild("PlayerGui")
	end
	local colors = {
		success = Color3.fromRGB(80, 220, 140),
		error = Color3.fromRGB(255, 110, 110),
		info = Color3.fromRGB(120, 200, 255),
	}
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(360, 44)
	label.BackgroundColor3 = Color3.fromRGB(12, 15, 24)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = colors[kind] or colors.info
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.Text = text
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = toastGui.List
	task.delay(2.6, function()
		label:Destroy()
	end)
end

task.spawn(function()
	local noticeRemote = folder:WaitForChild("PullUpNotice", 30)
	if noticeRemote then
		noticeRemote.OnClientEvent:Connect(toast)
	end
end)

-- Hide the prompts on bars that belong to someone else.
local function guardPrompt(prompt, bar)
	if not (Config.Shop and Config.Shop.OwnerOnly) then
		return
	end
	local function check()
		local owner = bar:GetAttribute("OwnerUserId")
		if owner and owner ~= player.UserId and prompt.Enabled then
			prompt.Enabled = false
		end
	end
	prompt:GetPropertyChangedSignal("Enabled"):Connect(check)
	check()
end

local function watchBar(bar)
	for _, d in bar:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			guardPrompt(d, bar)
		end
	end
	bar.DescendantAdded:Connect(function(d)
		if d:IsA("ProximityPrompt") then
			guardPrompt(d, bar)
		end
	end)
end
CollectionService:GetInstanceAddedSignal("PullUpBar"):Connect(watchBar)
for _, bar in CollectionService:GetTagged("PullUpBar") do
	watchBar(bar)
end

---------------------------------------------------------------------------
-- tracking
---------------------------------------------------------------------------

local function untrack(obj)
	local entry = tracked[obj]
	if not entry then
		return
	end
	tracked[obj] = nil
	if entry.rig then
		entry.rig:reset()
		if entry.isLocal then
			entry.rig.humanoid.CameraOffset = Vector3.zero
			showHud(false)
		end
	end
end

local function track(obj)
	if tracked[obj] or not obj:IsA("ObjectValue") then
		return
	end
	tracked[obj] = { s = {} }
	obj.AncestryChanged:Connect(function(_, parent)
		if not parent then
			untrack(obj)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(SESSION_TAG):Connect(track)
CollectionService:GetInstanceRemovedSignal(SESSION_TAG):Connect(untrack)
for _, obj in CollectionService:GetTagged(SESSION_TAG) do
	track(obj)
end

-- Motor6D.Transform must be written after animations run and before physics.
RunService.PreSimulation:Connect(function()
	local t = workspace:GetServerTimeNow()
	for obj, entry in tracked do
		if not entry.rig and not prepare(obj, entry) then
			continue
		end
		if not entry.rig.character.Parent then
			untrack(obj)
			continue
		end
		readSession(obj, entry)
		local ok, err = pcall(function()
			local params = Motion.sample(entry.ctx, entry.s, t)
			entry.rig:apply(entry.rig:solve(entry.standCF, entry.grips, params))
			if entry.isLocal then
				-- let the camera rise with the body
				local lift = entry.standCF:VectorToObjectSpace(params.shoulder - entry.ctx.standShoulder)
				entry.rig.humanoid.CameraOffset = Vector3.new(0, lift.Y * 0.7, 0)
				showHud(not entry.s.dismountStart, obj:GetAttribute("RepCount"))
			end
		end)
		if not ok then
			warn("[PullUp] animation error:", err)
			untrack(obj)
		end
	end
end)

---------------------------------------------------------------------------
-- local input
---------------------------------------------------------------------------

local function mySession()
	for obj, entry in tracked do
		if entry.isLocal and not entry.s.dismountStart then
			return obj
		end
	end
	return nil
end

UserInputService.JumpRequest:Connect(function()
	if mySession() then
		remote:FireServer("Leave")
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or Config.Mode ~= "Tap" or not mySession() then
		return
	end
	local kind = input.UserInputType
	if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch
		or input.KeyCode == Enum.KeyCode.ButtonR2 then
		remote:FireServer("Rep")
	end
end)

--!nonstrict
--[[
	PullUpServer

	Puts a ProximityPrompt on every model tagged "PullUpBar" in Workspace.
	When a player triggers it, the server anchors their HumanoidRootPart at the
	bar's StandPoint and creates a "PullUpSession" ObjectValue inside the
	character. Every client (PullUpClient) sees that session and animates the
	character from it, so everyone sees the same pull-ups.

	The server also counts reps and fires ServerStorage.PullUpRep:
		PullUpRep.Event:Connect(function(player, tier, repCount) ... end)
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local folder = ReplicatedStorage:WaitForChild("PullUp")
local Config = require(folder:WaitForChild("Config"))
local PullUpRig = require(folder:WaitForChild("PullUpRig"))
local Motion = require(folder:WaitForChild("PullUpMotion"))

local remote = folder:FindFirstChild("PullUpRemote") or Instance.new("RemoteEvent")
remote.Name = "PullUpRemote"
remote.Parent = folder

local repEvent = ServerStorage:FindFirstChild("PullUpRep") or Instance.new("BindableEvent")
repEvent.Name = "PullUpRep"
repEvent.Parent = ServerStorage

local BAR_TAG = "PullUpBar"
local SESSION_TAG = "PullUpSession"

local sessions = {} -- [player] = state
local occupant = {} -- [bar] = player
local prompts = {} -- [bar] = ProximityPrompt

local function now()
	return workspace:GetServerTimeNow()
end

local function tierOf(bar)
	return bar:GetAttribute("Tier") or 1
end

local function tempoFor(bar)
	return Config.TempoByTier[tierOf(bar)] or Config.Tempo
end

local function setPromptEnabled(bar, enabled)
	local prompt = prompts[bar]
	if prompt then
		prompt.Enabled = enabled
	end
end

---------------------------------------------------------------------------
-- rewards
---------------------------------------------------------------------------

local function award(player, state)
	state.reps += 1
	if state.session.Parent then
		state.session:SetAttribute("RepCount", state.reps)
	end
	local tier = tierOf(state.bar)
	if Config.Leaderstat then
		local stats = player:FindFirstChild("leaderstats")
		local stat = stats and stats:FindFirstChild(Config.Leaderstat)
		if stat and (stat:IsA("IntValue") or stat:IsA("NumberValue")) then
			stat.Value += Config.RewardByTier[tier] or 1
		end
	end
	repEvent:Fire(player, tier, state.reps)
end

---------------------------------------------------------------------------
-- sessions
---------------------------------------------------------------------------

local function cleanup(player)
	local state = sessions[player]
	if not state then
		return
	end
	sessions[player] = nil
	for _, c in state.connections do
		c:Disconnect()
	end
	if state.session then
		state.session:Destroy()
	end
	local hrp, humanoid = state.hrp, state.humanoid
	if hrp and hrp.Parent then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
		hrp.Anchored = state.wasAnchored
	end
	if humanoid and humanoid.Parent then
		humanoid.AutoRotate = state.autoRotate
	end
	if occupant[state.bar] == player then
		occupant[state.bar] = nil
		setPromptEnabled(state.bar, true)
	end
end

local function stop(player)
	local state = sessions[player]
	if not state or state.dismountStart then
		return
	end
	local t = now()
	state.dismountStart = t
	state.session:SetAttribute("DismountStart", t)
	task.delay(Motion.DISMOUNT_TIME, function()
		if sessions[player] == state then
			cleanup(player)
		end
	end)
end

local function start(player, bar)
	if sessions[player] or occupant[bar] then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and hrp) or humanoid.Health <= 0 then
		return
	end
	local rig, why = PullUpRig.new(character)
	if not rig then
		warn(("[PullUp] %s can't use the bar: %s"):format(player.Name, why))
		return
	end
	-- a ragdolled character has disabled joints
	for _, motor in rig.motors do
		if not motor.Enabled then
			return
		end
	end
	local standCF = rig:barFrames(bar)
	if not standCF then
		warn("[PullUp] bar is missing Base.StandPoint or GripBar grips:", bar:GetFullName())
		return
	end

	local t = now()
	local entry = hrp.Position - standCF.Position
	if entry.Magnitude > 12 then
		entry = Vector3.zero
	end

	local session = Instance.new("ObjectValue")
	session.Name = "PullUpSession"
	session.Value = bar
	session:SetAttribute("Mode", Config.Mode)
	session:SetAttribute("Tempo", tempoFor(bar))
	session:SetAttribute("MountStart", t)
	session:SetAttribute("StartTime", t + Motion.MOUNT_TIME)
	session:SetAttribute("Entry", entry)
	session:SetAttribute("RepCount", 0)
	session:SetAttribute("Player", player.UserId)
	session:AddTag(SESSION_TAG)

	local state = {
		bar = bar,
		session = session,
		hrp = hrp,
		humanoid = humanoid,
		wasAnchored = hrp.Anchored,
		autoRotate = humanoid.AutoRotate,
		tempo = tempoFor(bar),
		startTime = t + Motion.MOUNT_TIME,
		reps = 0,
		nextTop = nil, -- Tap mode: when the queued rep reaches the top
		repStart = nil,
		connections = {},
	}
	sessions[player] = state
	occupant[bar] = player
	setPromptEnabled(bar, false)

	humanoid.AutoRotate = false
	hrp.AssemblyLinearVelocity = Vector3.zero
	hrp.Anchored = true
	hrp.CFrame = standCF
	session.Parent = character

	table.insert(state.connections, humanoid.Died:Connect(function()
		cleanup(player)
	end))
	table.insert(state.connections, character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanup(player)
		end
	end))
	table.insert(state.connections, bar.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanup(player)
		end
	end))
end

local function tapRep(player)
	local state = sessions[player]
	if not state or state.dismountStart or Config.Mode ~= "Tap" then
		return
	end
	local t = now()
	if t < state.startTime then
		return
	end
	-- one rep at a time; allow the next tap during the settle at the bottom
	if state.repStart and t < state.repStart + state.tempo * 0.9 then
		return
	end
	local startAt = t + 0.08 -- small lead so remote clients receive it before it starts
	state.repStart = startAt
	state.nextTop = startAt + state.tempo * Motion.TOP
	state.session:SetAttribute("RepStart", startAt)
end

remote.OnServerEvent:Connect(function(player, action)
	if action == "Leave" then
		stop(player)
	elseif action == "Rep" then
		tapRep(player)
	end
end)

-- rep counting
RunService.Heartbeat:Connect(function()
	local t = now()
	for player, state in sessions do
		if state.dismountStart then
			continue
		end
		if Config.Mode == "Tap" then
			if state.nextTop and t >= state.nextTop then
				state.nextTop = nil
				award(player, state)
			end
		else
			local done = math.floor((t - state.startTime) / state.tempo - Motion.TOP) + 1
			while state.reps < done do
				award(player, state)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(cleanup)

---------------------------------------------------------------------------
-- bars
---------------------------------------------------------------------------

local function setupBar(bar)
	if prompts[bar] or not bar:IsDescendantOf(workspace) then
		return
	end
	local base = bar.PrimaryPart or bar:FindFirstChild("Base", true)
	local stand = base and base:FindFirstChild("StandPoint")
	if not stand then
		warn("[PullUp] bar has no Base.StandPoint:", bar:GetFullName())
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PullUpPrompt"
	prompt.ActionText = "Pull-ups"
	prompt.ObjectText = bar:GetAttribute("TierName") or "Pull-up bar"
	prompt.KeyboardKeyCode = Config.PromptKey
	prompt.GamepadKeyCode = Config.PromptGamepadKey
	prompt.MaxActivationDistance = Config.PromptDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.UIOffset = Vector2.new(0, 40)
	prompt.Parent = stand
	prompts[bar] = prompt
	prompt.Triggered:Connect(function(player)
		start(player, bar)
	end)
end

local function removeBar(bar)
	local prompt = prompts[bar]
	prompts[bar] = nil
	if prompt then
		prompt:Destroy()
	end
	local player = occupant[bar]
	if player then
		cleanup(player)
	end
end

CollectionService:GetInstanceAddedSignal(BAR_TAG):Connect(setupBar)
CollectionService:GetInstanceRemovedSignal(BAR_TAG):Connect(removeBar)
for _, bar in CollectionService:GetTagged(BAR_TAG) do
	setupBar(bar)
end

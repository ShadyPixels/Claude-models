--!nonstrict
--[[
	PullUpBarShop

	Every player gets their own pull-up bar on a spot in the gym. It starts as
	the lowest tier, and each purchase replaces it with the next tier up, in
	order: Basic -> Inferno -> Celestial -> Void -> Frostbite -> Stormcastle
	-> Arcane -> Blood Moon -> Toxic. Tiers can't be skipped.

	Players buy from the "Upgrade" prompt on their bar, or from your own shop UI
	through ReplicatedStorage.PullUp.BuyNextPullUpBar (a RemoteFunction that
	returns ok, message).

	Your scripts can use this module:
		local Shop = require(game.ServerScriptService.PullUpServer.PullUpBarShop)
		Shop.GetTier(player)          -> 1..9
		Shop.SetTier(player, tier)    -- e.g. from your own save data or an admin command
		Shop.BuyNext(player)          -> ok, message
		Shop.Charge = function(player, price) ... return ok, message end  -- custom currency
		ServerStorage.PullUpBarTierChanged.Event:Connect(function(player, tier) end)

	The bar models come from ServerStorage.PullUpBars, ordered by their Tier
	attribute, so adding or reordering models there changes the progression.
]]

local Shop = {}

local Players, DataStoreService, CollectionService, Workspace, ServerStorage, ReplicatedStorage
local Config, Motion, service
local TESTING = false

local SPOT_TAG = "PullUpBarSpot"

local templates = {} -- [index] = Model, lowest tier first
local accents = {} -- [index] = Color3 of the bar's main neon
local owners = {} -- [player] = { tier, loaded, loadFailed, busy, spot, bar }
local spots = {} -- ordered spot parts
local spotOwner = {} -- [spot] = player
local store, tierChanged, notice, barsFolder

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local function on(inst, event, fn)
	if TESTING then
		return
	end
	return inst[event]:Connect(fn)
end

function Shop.Abbreviate(n)
	n = math.floor(n)
	for _, u in { { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } } do
		if n >= u[1] then
			local v = n / u[1]
			local s = v >= 100 and tostring(math.floor(v)) or (string.format("%.1f", v):gsub("%.0$", ""))
			return s .. u[2]
		end
	end
	return tostring(n)
end

local function shopConfig()
	return Config.Shop or {}
end

local function priceOf(index)
	return shopConfig().Prices and shopConfig().Prices[index] or 0
end

local function nameOf(index)
	local t = templates[index]
	return t and (t:GetAttribute("TierName") or t.Name) or "?"
end

local function clampTier(t)
	t = tonumber(t) or 1
	return math.clamp(math.floor(t), 1, math.max(#templates, 1))
end

local function say(player, kind, text)
	if notice then
		notice:FireClient(player, kind, text)
	end
end

-- Moves a model built around the origin onto `cf`.
local function placeModel(model, cf)
	local ok = pcall(function()
		model:PivotTo(cf)
	end)
	if not ok then
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.CFrame = cf * d.CFrame
			end
		end
	end
end

---------------------------------------------------------------------------
-- bar templates
---------------------------------------------------------------------------

local function loadTemplates()
	table.clear(templates)
	local folder = ServerStorage:FindFirstChild("PullUpBars")
	if not folder then
		warn("[PullUp] ServerStorage.PullUpBars is missing, so there are no bars to hand out")
		return
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Tier") then
			table.insert(templates, m)
		end
	end
	table.sort(templates, function(a, b)
		return a:GetAttribute("Tier") < b:GetAttribute("Tier")
	end)
	for i, m in templates do
		-- the colour used most by the bar's neon is its accent
		local counts, best, bestN = {}, Color3.new(1, 1, 1), 0
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Material == Enum.Material.Neon then
				local c = d.Color
				local key = string.format("%d,%d,%d", c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5)
				counts[key] = (counts[key] or 0) + 1
				if counts[key] > bestN then
					bestN, best = counts[key], d.Color
				end
			end
		end
		accents[i] = best
	end
end

---------------------------------------------------------------------------
-- spots
---------------------------------------------------------------------------

local function spotCFrame(spot)
	return spot.CFrame * CFrame.new(0, spot.Size.Y / 2, 0)
end

local function sortSpots()
	table.sort(spots, function(a, b)
		local oa, ob = a:GetAttribute("Order") or math.huge, b:GetAttribute("Order") or math.huge
		if oa ~= ob then
			return oa < ob
		end
		return a:GetFullName() < b:GetFullName()
	end)
end

local function addSpot(spot)
	if not (spot:IsA("BasePart") and spot:IsDescendantOf(Workspace)) or table.find(spots, spot) then
		return false
	end
	table.insert(spots, spot)
	sortSpots()
	return true
end

local function createAutoSpots(count, spacing)
	local folder = Instance.new("Folder")
	folder.Name = "PullUpGym"
	local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local origin = spawn and spawn.CFrame or CFrame.new()
	local look = origin.LookVector * Vector3.new(1, 0, 1)
	look = look.Magnitude > 1e-3 and look.Unit or Vector3.new(0, 0, -1)
	local right = look:Cross(Vector3.new(0, 1, 0))
	local groundY = spawn and (origin.Position.Y - spawn.Size.Y / 2) or 0
	local center = origin.Position + look * 40
	for i = 1, count do
		local pos = center + right * ((i - (count + 1) / 2) * spacing)
		local y = groundY
		pcall(function()
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { folder }
			local hit = Workspace:Raycast(Vector3.new(pos.X, groundY + 60, pos.Z), Vector3.new(0, -200, 0), params)
			if hit then
				y = hit.Position.Y
			end
		end)
		pos = Vector3.new(pos.X, y + 0.2, pos.Z)
		local pad = Instance.new("Part")
		pad.Name = "PullUpBarSpot"
		pad.Anchored = true
		pad.Size = Vector3.new(12, 0.4, 9)
		pad.Color = Color3.fromRGB(70, 74, 82)
		pad.Material = Enum.Material.SmoothPlastic
		pad.TopSurface = Enum.SurfaceType.Smooth
		-- the bar's open side faces the spawn
		pad.CFrame = CFrame.lookAt(pos, pos - look)
		pad:SetAttribute("Order", i)
		pad:AddTag(SPOT_TAG)
		pad.Parent = folder
	end
	folder.Parent = Workspace
	for _, pad in folder:GetChildren() do
		addSpot(pad)
	end
end

local function takeSpot(player)
	for _, spot in spots do
		if not spotOwner[spot] and spot.Parent then
			spotOwner[spot] = player
			return spot
		end
	end
	return nil
end

---------------------------------------------------------------------------
-- bar decoration: sign, upgrade prompt, upgrade burst
---------------------------------------------------------------------------

local function signText(player, index)
	local nextIndex = index + 1
	local nextLine
	if nextIndex > #templates then
		nextLine = "Max tier"
	else
		nextLine = ("Next: %s · %s %s"):format(nameOf(nextIndex), Shop.Abbreviate(priceOf(nextIndex)),
			shopConfig().Currency or "")
	end
	return ("%s's Pull-up Bar"):format(player.DisplayName), ("Tier %d · %s"):format(index, nameOf(index)), nextLine
end

local function decorate(bar, player, data)
	local base = bar.PrimaryPart or bar:FindFirstChild("Base", true)
	if not base then
		return
	end
	local index = data.tier

	-- sign above the bar
	local top = 12
	pcall(function()
		local cf, size = bar:GetBoundingBox()
		top = (cf.Position.Y + size.Y / 2) - base.CFrame.Position.Y
	end)
	local anchor = Instance.new("Attachment")
	anchor.Name = "SignPoint"
	anchor.CFrame = CFrame.new(0, top + 1.6, 0)
	anchor.Parent = base

	local gui = Instance.new("BillboardGui")
	gui.Name = "PullUpSign"
	gui.Size = UDim2.fromOffset(260, 78)
	gui.LightInfluence = 0
	gui.MaxDistance = 90
	gui.Parent = anchor
	local l1, l2, l3 = signText(player, index)
	local accent = accents[index] or Color3.new(1, 1, 1)
	for i, info in { { l1, 16, Color3.fromRGB(238, 242, 250) }, { l2, 22, accent }, { l3, 14, Color3.fromRGB(190, 198, 214) } } do
		local label = Instance.new("TextLabel")
		label.Name = "Line" .. i
		label.BackgroundTransparency = 1
		label.Size = UDim2.new(1, 0, 0, i == 2 and 30 or 22)
		label.Position = UDim2.fromOffset(0, i == 1 and 0 or i == 2 and 22 or 54)
		label.Font = i == 2 and Enum.Font.GothamBlack or Enum.Font.GothamBold
		label.Text = info[1]
		label.TextSize = info[2]
		label.TextColor3 = info[3]
		label.TextStrokeTransparency = 0.35
		label.Parent = gui
	end

	-- upgrade prompt (only while there is a next tier)
	local nextIndex = index + 1
	local enter = base:FindFirstChild("EnterPoint")
	if nextIndex <= #templates and enter then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "UpgradePrompt"
		prompt.ActionText = ("Upgrade · %s %s"):format(Shop.Abbreviate(priceOf(nextIndex)), shopConfig().Currency or "")
		prompt.ObjectText = "Next: " .. nameOf(nextIndex)
		prompt.KeyboardKeyCode = shopConfig().UpgradeKey or Enum.KeyCode.F
		prompt.GamepadKeyCode = shopConfig().UpgradeGamepadKey or Enum.KeyCode.ButtonY
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = enter
		on(prompt, "Triggered", function(who)
			if who == player then
				Shop.BuyNext(player)
			else
				say(who, "error", ("This is %s's bar"):format(player.DisplayName))
			end
		end)
	end
end

local function burst(bar, index)
	pcall(function()
		local cf, size = bar:GetBoundingBox()
		local part = Instance.new("Part")
		part.Name = "UpgradeBurst"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Transparency = 1
		part.Size = Vector3.new(size.X * 0.8, size.Y * 0.8, size.Z * 0.8)
		part.CFrame = cf
		local color = accents[index] or Color3.new(1, 1, 1)
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
		pe.Transparency = NumberSequence.new(0, 1)
		pe.Lifetime = NumberRange.new(0.6, 1.3)
		pe.Speed = NumberRange.new(8, 22)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.LightEmission = 1
		pe.Rate = 0
		pe.Parent = part
		local light = Instance.new("PointLight")
		light.Color = color
		light.Range = 28
		light.Brightness = 6
		light.Parent = part
		part.Parent = Workspace
		pe:Emit(120)
		game:GetService("TweenService"):Create(light, TweenInfo.new(0.9), { Brightness = 0 }):Play()
		game:GetService("Debris"):AddItem(part, 2)
	end)
end

---------------------------------------------------------------------------
-- placing bars
---------------------------------------------------------------------------

-- Puts the player's current tier on their spot, replacing the old bar.
local function placeBar(player, data, celebrate)
	local old = data.bar
	data.bar = nil
	if old then
		old:SetAttribute("Locked", true)
		service.ClearBar(old) -- let whoever is on it drop off first
		old:Destroy()
	end
	if owners[player] ~= data or not data.spot then
		return
	end
	local template = templates[data.tier]
	if not template then
		return
	end
	local bar = template:Clone()
	bar.Name = ("PullUpBar_%s"):format(player.Name)
	bar:SetAttribute("OwnerUserId", player.UserId)
	bar:SetAttribute("OwnerName", player.DisplayName)
	placeModel(bar, spotCFrame(data.spot))
	decorate(bar, player, data)
	bar.Parent = barsFolder
	data.bar = bar
	if celebrate then
		burst(bar, data.tier)
	end
end

---------------------------------------------------------------------------
-- saving
---------------------------------------------------------------------------

local function key(player)
	return "u" .. player.UserId
end

local function loadTier(player)
	local start = clampTier(shopConfig().StartTier or 1)
	if not store then
		return start, true
	end
	for attempt = 1, 3 do
		local ok, value = pcall(function()
			return store:GetAsync(key(player))
		end)
		if ok then
			return clampTier(value or start), true
		end
		task.wait(attempt)
	end
	warn(("[PullUp] couldn't load %s's pull-up bar tier; it won't be saved this session"):format(player.Name))
	return start, false
end

local function saveTier(player, data)
	if not store or data.loadFailed or not data.loaded then
		return
	end
	local tier = data.tier
	local ok, err = pcall(function()
		store:UpdateAsync(key(player), function()
			return tier
		end)
	end)
	if not ok then
		warn("[PullUp] couldn't save pull-up bar tier:", err)
	end
end

---------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------

function Shop.GetTier(player)
	local data = owners[player]
	return data and data.tier or 1
end

function Shop.GetTemplates()
	return templates
end

-- Default payment: take `price` from leaderstats[Config.Shop.Currency].
-- Replace this function to use your own currency system.
function Shop.Charge(player, price)
	if price <= 0 then
		return true
	end
	local currency = shopConfig().Currency or "Cash"
	local stats = player:FindFirstChild("leaderstats")
	local stat = stats and stats:FindFirstChild(currency)
	if not stat then
		warn(("[PullUp] %s has no leaderstats.%s to pay with (see Config.Shop.Currency)"):format(player.Name, currency))
		return false, ("Upgrades cost %s, but you don't have any"):format(currency)
	end
	if stat.Value < price then
		return false, ("You need %s more %s"):format(Shop.Abbreviate(price - stat.Value), currency)
	end
	stat.Value -= price
	return true
end

local function setTier(player, data, tier, celebrate)
	data.tier = clampTier(tier)
	player:SetAttribute("PullUpBarTier", data.tier)
	task.spawn(saveTier, player, data)
	placeBar(player, data, celebrate)
	if tierChanged then
		tierChanged:Fire(player, data.tier)
	end
end

-- Sets a player's tier directly (your save data, admin commands, gamepasses ...).
function Shop.SetTier(player, tier)
	local data = owners[player]
	if not data then
		return
	end
	data.loaded = true
	setTier(player, data, tier, false)
end

-- Buys the next tier in order. Returns ok, message.
function Shop.BuyNext(player)
	local data = owners[player]
	if not data or not data.loaded then
		return false, "Still loading your data"
	end
	if data.busy then
		return false, "Upgrade in progress"
	end
	local nextIndex = data.tier + 1
	if nextIndex > #templates then
		say(player, "info", "You already have the best pull-up bar!")
		return false, "Max tier"
	end
	data.busy = true
	local ok, message = Shop.Charge(player, priceOf(nextIndex))
	if not ok then
		data.busy = false
		say(player, "error", message or "Can't afford that yet")
		return false, message
	end
	setTier(player, data, nextIndex, true)
	data.busy = false
	local done = ("Upgraded to %s!"):format(nameOf(nextIndex))
	say(player, "success", done)
	return true, done
end

---------------------------------------------------------------------------
-- players
---------------------------------------------------------------------------

local function onPlayerAdded(player)
	if owners[player] then
		return
	end
	local data = { tier = 1, loaded = false }
	owners[player] = data
	local tier, ok = loadTier(player)
	if owners[player] ~= data then
		return -- left while loading
	end
	data.loadFailed = not ok
	data.loaded = true
	data.spot = takeSpot(player)
	if not data.spot then
		warn(("[PullUp] no free PullUpBarSpot for %s"):format(player.Name))
	end
	data.tier = clampTier(tier)
	player:SetAttribute("PullUpBarTier", data.tier)
	placeBar(player, data, false)
	if tierChanged then
		tierChanged:Fire(player, data.tier)
	end
end

local function onPlayerRemoving(player)
	local data = owners[player]
	if not data then
		return
	end
	saveTier(player, data)
	owners[player] = nil
	if data.spot then
		spotOwner[data.spot] = nil
	end
	if data.bar then
		data.bar:Destroy()
	end
end

---------------------------------------------------------------------------
-- init
---------------------------------------------------------------------------

-- deps lets the tests swap in fake services; leave it nil in the game.
function Shop.Init(pullUpService, deps)
	deps = deps or {}
	TESTING = deps.testing == true
	service = pullUpService
	Players = deps.Players or game:GetService("Players")
	CollectionService = deps.CollectionService or game:GetService("CollectionService")
	Workspace = deps.Workspace or workspace
	ServerStorage = deps.ServerStorage or game:GetService("ServerStorage")
	ReplicatedStorage = deps.ReplicatedStorage or game:GetService("ReplicatedStorage")
	local folder = ReplicatedStorage:FindFirstChild("PullUp") or ReplicatedStorage:WaitForChild("PullUp")
	Config = deps.Config or require(folder:WaitForChild("Config"))
	Motion = deps.Motion or require(folder:WaitForChild("PullUpMotion"))
	if shopConfig().Enabled == false then
		return
	end

	loadTemplates()
	if #templates == 0 then
		return
	end

	if not TESTING then
		tierChanged = ServerStorage:FindFirstChild("PullUpBarTierChanged") or Instance.new("BindableEvent")
		tierChanged.Name = "PullUpBarTierChanged"
		tierChanged.Parent = ServerStorage
		notice = folder:FindFirstChild("PullUpNotice") or Instance.new("RemoteEvent")
		notice.Name = "PullUpNotice"
		notice.Parent = folder
		local buy = folder:FindFirstChild("BuyNextPullUpBar") or Instance.new("RemoteFunction")
		buy.Name = "BuyNextPullUpBar"
		buy.Parent = folder
		buy.OnServerInvoke = function(player)
			return Shop.BuyNext(player)
		end
	end

	if shopConfig().DataStoreName then
		local ok, result = pcall(function()
			return (deps.DataStoreService or game:GetService("DataStoreService")):GetDataStore(shopConfig().DataStoreName)
		end)
		if ok then
			store = result
		else
			warn("[PullUp] DataStores unavailable, pull-up bar tiers won't save this session:", result)
		end
	end

	barsFolder = Workspace:FindFirstChild("PullUpPlayerBars") or Instance.new("Folder")
	barsFolder.Name = "PullUpPlayerBars"
	barsFolder.Parent = Workspace

	for _, spot in CollectionService:GetTagged(SPOT_TAG) do
		addSpot(spot)
	end
	if #spots == 0 and (shopConfig().AutoSpots or 0) > 0 then
		createAutoSpots(shopConfig().AutoSpots, shopConfig().SpotSpacing or 16)
	end
	if not TESTING then
		CollectionService:GetInstanceAddedSignal(SPOT_TAG):Connect(function(spot)
			if addSpot(spot) then
				-- hand new spots to anyone who didn't get one
				for player, data in owners do
					if data.loaded and not data.spot then
						data.spot = takeSpot(player)
						if data.spot then
							task.spawn(placeBar, player, data, false)
						end
					end
				end
			end
		end)
		Players.PlayerAdded:Connect(onPlayerAdded)
		Players.PlayerRemoving:Connect(onPlayerRemoving)
		game:BindToClose(function()
			for player, data in owners do
				task.spawn(saveTier, player, data)
			end
			task.wait(2)
		end)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- test hooks
Shop._onPlayerAdded = onPlayerAdded
Shop._onPlayerRemoving = onPlayerRemoving
Shop._owners = owners

return Shop

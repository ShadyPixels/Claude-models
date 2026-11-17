-- Tests PullUpBarShop with fake players, a fake DataStore and three spots:
-- bars are handed out, upgrades go strictly in tier order, prices are charged,
-- old bars are cleared and removed, tiers save and load, spots are reused.
-- usage (from pullup-bars/): lune run tests/shop.luau
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local K = require("./rigkit")
local V, CF = roblox.Vector3.new, roblox.CFrame.new

local failures = 0
local function check(cond, msg)
	print((cond and "  ok   " or "  FAIL ") .. msg)
	if not cond then failures += 1 end
end

-- a place with the system's ServerStorage + ReplicatedStorage contents
local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local bundle = roblox.deserializeModel(fs.readFile("roblox/PullUpSystem.rbxmx"))[1]
bundle.ServerStorage.PullUpBars.Parent = ServerStorage
bundle.ReplicatedStorage.PullUp.Parent = ReplicatedStorage
check(#ServerStorage.PullUpBars:GetChildren() == 9, "bundle has 9 bar templates")
check(bundle.ServerScriptService.PullUpServer.Disabled == true, "bundled server script stays disabled until installed")

-- three spots, deliberately out of order and rotated
local spotDefs = { { 3, V(40, 0, 0), 90 }, { 1, V(0, 0, 0), 0 }, { 2, V(20, 5, 10), 180 } }
for _, d in spotDefs do
	local p = roblox.Instance.new("Part")
	p.Name = "Spot" .. d[1]
	p.Size = V(12, 0.4, 9)
	p.CFrame = CF(d[2]) * roblox.CFrame.Angles(0, math.rad(d[3]), 0)
	p:SetAttribute("Order", d[1])
	p:AddTag("PullUpBarSpot")
	p.Parent = workspace
end

local fakeCollection = {
	GetTagged = function(_, tag)
		local out = {}
		for _, d in workspace:GetDescendants() do
			if d:HasTag(tag) then table.insert(out, d) end
		end
		return out
	end,
}
local fakePlayers = { GetPlayers = function() return {} end }
local saved = {}
local fakeDataStores = {
	GetDataStore = function(_, name)
		return {
			GetAsync = function(_, key) return saved[key] end,
			UpdateAsync = function(_, key, fn) saved[key] = fn(saved[key]) end,
		}
	end,
}
local cleared = {}
local fakeService = { ClearBar = function(bar) table.insert(cleared, bar) end }

local function makePlayer(id, name, cash)
	local holder = roblox.Instance.new("Folder")
	local stats = roblox.Instance.new("Folder")
	stats.Name = "leaderstats"
	local c = roblox.Instance.new("IntValue")
	c.Name = "Cash"
	c.Value = cash
	c.Parent = stats
	stats.Parent = holder
	return setmetatable({ UserId = id, Name = name, DisplayName = name, cash = c }, { __index = {
		FindFirstChild = function(_, n) return holder:FindFirstChild(n) end,
		SetAttribute = function(_, k, v) holder:SetAttribute(k, v) end,
		GetAttribute = function(_, k) return holder:GetAttribute(k) end,
	} })
end

local Config = K.load("Config")
local Shop = K.load("PullUpBarShop", "roblox/scripts/ServerScriptService/PullUpServer/PullUpBarShop.lua", { game = game, workspace = workspace })
Shop.Init(fakeService, {
	testing = true, Players = fakePlayers, CollectionService = fakeCollection, Workspace = workspace,
	ServerStorage = ServerStorage, ReplicatedStorage = ReplicatedStorage, Config = Config,
	Motion = K.load("PullUpMotion"), DataStoreService = fakeDataStores,
})

local order = {}
for i, t in Shop.GetTemplates() do order[i] = t:GetAttribute("TierName") end
print("progression: " .. table.concat(order, " -> "))
check(table.concat(order, ",") == "Basic,Inferno,Celestial,Void,Frostbite,Stormcastle,Arcane,Blood Moon,Toxic",
	"templates are ordered lowest tier to highest")

local function barOf(player)
	return Shop._owners[player] and Shop._owners[player].bar
end
local function spotTop(name)
	local s = workspace:FindFirstChild(name)
	return s.CFrame * CF(0, s.Size.Y / 2, 0)
end

print("player joins")
local alice = makePlayer(101, "Alice", 0)
Shop._onPlayerAdded(alice)
local bar = barOf(alice)
check(bar ~= nil and bar.Parent == workspace.PullUpPlayerBars, "Alice gets a bar in Workspace.PullUpPlayerBars")
check(bar:GetAttribute("Tier") == 1 and Shop.GetTier(alice) == 1, "it starts at tier 1 (Basic)")
check(bar:GetAttribute("OwnerUserId") == 101, "the bar is marked as Alice's")
local base = bar:FindFirstChild("Base", true)
local expect = spotTop("Spot1") * CF(0, 0.3, 0)
check((base.CFrame.Position - expect.Position).Magnitude < 1e-3, "it sits on the first spot (Order = 1)")
check(base:FindFirstChild("EnterPoint"):FindFirstChild("UpgradePrompt") ~= nil, "it has an Upgrade prompt")
check(base.SignPoint.PullUpSign.Line2.Text == "Tier 1 · Basic", "its sign shows the tier")
check(base.SignPoint.PullUpSign.Line3.Text == "Next: Inferno · 500 Cash", "its sign shows the next tier and price")

print("can't afford")
local ok, msg = Shop.BuyNext(alice)
check(not ok and msg == "You need 500 more Cash", "with 0 Cash the purchase is refused: " .. tostring(msg))
check(Shop.GetTier(alice) == 1 and barOf(alice) == bar, "tier and bar are unchanged")

print("upgrades in order")
alice.cash.Value = 20000000
local spent = 0
local seen = {}
for expected = 2, 9 do
	local before = barOf(alice)
	local cashBefore = alice.cash.Value
	ok, msg = Shop.BuyNext(alice)
	local now = barOf(alice)
	table.insert(seen, now:GetAttribute("TierName"))
	spent += cashBefore - alice.cash.Value
	check(ok and Shop.GetTier(alice) == expected and now:GetAttribute("Tier") == expected
		and before.Parent == nil and cleared[#cleared] == before
		and cashBefore - alice.cash.Value == Config.Shop.Prices[expected],
		("buy #%d -> tier %d %s for %d (old bar cleared and removed)"):format(expected - 1, expected,
			now:GetAttribute("TierName"), cashBefore - alice.cash.Value))
end
local total = 0
for i = 2, 9 do total += Config.Shop.Prices[i] end
check(spent == total, ("total spent %d matches the price list"):format(spent))
ok, msg = Shop.BuyNext(alice)
check(not ok and msg == "Max tier", "at Toxic there is nothing higher to buy")
local top = barOf(alice):FindFirstChild("Base", true)
check(top.EnterPoint:FindFirstChild("UpgradePrompt") == nil, "the Toxic bar has no Upgrade prompt")
check(top.SignPoint.PullUpSign.Line3.Text == "Max tier", "its sign says Max tier")
check(#workspace.PullUpPlayerBars:GetChildren() == 1, "only one bar exists for Alice")
check(saved.u101 == 9, "tier 9 was saved")

print("other players and spots")
saved.u202 = 4
local bob = makePlayer(202, "Bob", 0)
Shop._onPlayerAdded(bob)
check(Shop.GetTier(bob) == 4 and barOf(bob):GetAttribute("TierName") == "Void", "Bob loads his saved tier 4 (Void)")
local bobBase = barOf(bob):FindFirstChild("Base", true)
check((bobBase.CFrame.Position - (spotTop("Spot2") * CF(0, 0.3, 0)).Position).Magnitude < 1e-3, "Bob gets spot 2")
Shop._onPlayerRemoving(alice)
check(#workspace.PullUpPlayerBars:GetChildren() == 1, "Alice's bar is removed when she leaves")
local cara = makePlayer(303, "Cara", 0)
Shop._onPlayerAdded(cara)
local caraBase = barOf(cara):FindFirstChild("Base", true)
check((caraBase.CFrame.Position - (spotTop("Spot1") * CF(0, 0.3, 0)).Position).Magnitude < 1e-3, "Cara gets Alice's freed spot 1")
local alice2 = makePlayer(101, "Alice", 0)
Shop._onPlayerAdded(alice2)
check(Shop.GetTier(alice2) == 9 and barOf(alice2):GetAttribute("TierName") == "Toxic", "Alice rejoins with Toxic")
check((barOf(alice2):FindFirstChild("Base", true).CFrame.Position - (spotTop("Spot3") * CF(0, 0.3, 0)).Position).Magnitude < 1e-3,
	"and gets the last free spot (3), rotated with it")
Shop.SetTier(bob, 1)
check(Shop.GetTier(bob) == 1 and barOf(bob):GetAttribute("TierName") == "Basic" and saved.u202 == 1, "SetTier works for your own data system")

print(failures == 0 and "PASS" or ("FAIL (" .. failures .. ")"))
if failures > 0 then process.exit(1) end

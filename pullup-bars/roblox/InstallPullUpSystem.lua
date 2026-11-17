--[[
	InstallPullUpSystem  (paste into the Studio command bar)

	1. Drag roblox/PullUpSystem.rbxmx into Studio (it lands in Workspace as "PullUpSystem").
	2. Paste this whole file into the command bar and press Enter.

	It moves each part of the system into its service, replacing older copies
	with the same names (PullUp, PullUpServer, PullUpClient, PullUpBars), then
	removes the PullUpSystem folder. Run it again after dragging in a newer
	PullUpSystem.rbxmx to update.
]]

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local root = workspace:FindFirstChild("PullUpSystem") or game:GetService("Selection"):Get()[1]
assert(root and root.Name == "PullUpSystem", "Drag PullUpSystem.rbxmx into Studio first")

local targets = {
	ReplicatedStorage = game:GetService("ReplicatedStorage"),
	ServerScriptService = game:GetService("ServerScriptService"),
	StarterPlayerScripts = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"),
	ServerStorage = game:GetService("ServerStorage"),
}

local recording = ChangeHistoryService:TryBeginRecording("Install pull-up system")
for _, group in root:GetChildren() do
	local target = targets[group.Name]
	if target then
		for _, item in group:GetChildren() do
			local old = target:FindFirstChild(item.Name)
			if old then
				old:Destroy()
				print(("[PullUp] replaced %s.%s"):format(target.Name, item.Name))
			end
			item.Parent = target
			if item:IsA("Script") then
				item.Enabled = true
			end
			print(("[PullUp] installed %s.%s"):format(target.Name, item.Name))
		end
	end
end
root:Destroy()
if recording then
	ChangeHistoryService:FinishRecording(recording, Enum.FinishRecordingOperation.Commit)
end
print("[PullUp] Done. Set Config.Shop.Currency to your game's money leaderstat, then press Play.")

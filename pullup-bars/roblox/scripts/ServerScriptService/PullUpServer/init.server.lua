--!nonstrict
--[[
	PullUpServer

	Starts the pull-up system:
		PullUpService   prompts on every bar, sessions, rep counting
		PullUpBarShop   each player's own bar, upgraded tier by tier in order

	Settings live in ReplicatedStorage.PullUp.Config.
]]

local PullUpService = require(script:WaitForChild("PullUpService"))
local PullUpBarShop = require(script:WaitForChild("PullUpBarShop"))

PullUpService.Init()
PullUpBarShop.Init(PullUpService)

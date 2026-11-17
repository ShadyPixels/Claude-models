--!nonstrict
-- Settings for the pull-up bars. Server and clients both read this.
return {
	-- "Auto": reps keep going until the player lets go.
	-- "Tap":  each click / tap / R2 press does one rep.
	Mode = "Auto",

	-- Seconds per rep. Lower is faster.
	Tempo = 1.8,
	-- Optional per-tier tempo, e.g. { [8] = 1.5, [9] = 1.4 }
	TempoByTier = {},

	-- If the player has leaderstats with this value, each rep adds RewardByTier[tier].
	-- Set Leaderstat to nil to only use the PullUpRep event (see the README).
	Leaderstat = "Strength",
	RewardByTier = { 1, 2, 4, 7, 12, 20, 35, 60, 100 },

	-- Proximity prompt
	PromptKey = Enum.KeyCode.E,
	PromptGamepadKey = Enum.KeyCode.ButtonX,
	PromptDistance = 9,

	-- Show a small "reps / let go" label for the player on the bar
	ShowHud = true,

	-- Personal pull-up bars that upgrade in order: Basic -> Inferno -> Celestial -> Void
	-- -> Frostbite -> Stormcastle -> Arcane -> Blood Moon -> Toxic.
	Shop = {
		Enabled = true,

		-- leaderstats value used to pay for upgrades
		Currency = "Cash",
		-- Price to unlock each tier, in order. Tier 1 is the free starter bar.
		Prices = { 0, 500, 2500, 10000, 40000, 150000, 500000, 2000000, 10000000 },

		-- Saves each player's tier. Set to nil if your own data system saves it and
		-- calls PullUpBarShop.SetTier(player, tier) when the player joins.
		DataStoreName = "PullUpBarTier_v1",

		-- Only the owner can use (and upgrade) their bar.
		OwnerOnly = true,

		-- Upgrade prompt on each player's bar
		UpgradeKey = Enum.KeyCode.F,
		UpgradeGamepadKey = Enum.KeyCode.ButtonY,

		-- Where personal bars go: any parts tagged "PullUpBarSpot". If the place has
		-- none, this many spots are created in a row in front of the SpawnLocation.
		AutoSpots = 8,
		SpotSpacing = 16,
	},
}

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
}

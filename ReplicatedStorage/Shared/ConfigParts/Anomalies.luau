--!strict
-- Anomalies: per-anomaly settings, intro cutscenes, repairs.
-- Merged into Shared/Config (read it as Config.<Name>).

local Config = {}

-- Anomalies --------------------------------------------------------------------
-- Duration is the countdown shown to players. For Overheat/Mimic it is a safety
-- timeout: those end early once players deal with them.
Config.AnomalyInterval = 180
Config.Anomalies = {
	GravityDistortion = {
		DisplayName = "GRAVITY DISTORTION",
		Description = "Gravity has dropped to 10%!",
		Weight = 1,
		Duration = 45,
		GravityScale = 0.1,
	},
	OverheatCrisis = {
		DisplayName = "OVERHEAT CRISIS",
		Description = "Ovens are overheating! Use your Fire Extinguisher before they EXPLODE!",
		Weight = 1,
		Duration = 60,
		ExtinguisherRange = 12,
	},
	MimicCustomer = {
		DisplayName = "MIMIC CUSTOMER",
		Description = "A glowing mimic is after your cakes! Click or touch it to stop it.",
		Weight = 1,
		Duration = 60,
		StopReward = 50,
	},
	Brute = {
		DisplayName = "BRUTE BREAK-IN",
		Description = "A Brute is smashing into your bakery! Whack it with the Frying Pan before it wrecks your machines.",
		Weight = 1,
		Duration = 90,
		HP = 12,
		SmashInterval = 8, -- seconds between machine smashes
		MaxBreaks = 3, -- machines it can break per plot
		RewardCash = 300,
		RewardGems = 5,
	},
	RatSwarm = {
		DisplayName = "RAT SWARM",
		Description = "Rats are raiding your pantry and nibbling cakes! Stomp or whack them!",
		Weight = 1,
		Duration = 60,
		Count = 7,
		Steal = 2, -- bag ingredients a rat steals from the pantry
		Speed = 9, -- studs per second
		RewardCash = 20, -- per rat
		ClearGems = 2, -- squash every rat
	},
	Gremlin = {
		DisplayName = "GREMLIN SABOTAGE",
		Description = "A Gremlin is sabotaging your production lines! Catch it 3 times!",
		Weight = 1,
		Duration = 75,
		Catches = 3,
		ActionInterval = 6, -- seconds between sabotage moves
		VisibleTime = 4, -- seconds it sits still (catchable) after a move
		JamSeconds = 15,
		RewardGems = 4,
	},
	Phantom = {
		DisplayName = "PHANTOM HAUNTING",
		Description = "A Phantom is scaring customers away and spooking cakes! Click it when it appears!",
		Weight = 1,
		Duration = 75,
		Banishes = 4,
		AppearEvery = 6, -- seconds between appearances
		VisibleTime = 3,
		RewardGems = 4,
	},
}

-- Anomaly intro cutscenes (client: UI/Cutscene). Creatures wait this long
-- before they act. Style picks the camera move; Tint colours the screen.
Config.Cutscene = {
	Length = 4,
	Shots = {
		GravityDistortion = { Style = "tilt", Tint = Color3.fromRGB(150, 180, 255) },
		OverheatCrisis = { Style = "push", Tint = Color3.fromRGB(255, 140, 80) },
		MimicCustomer = { Style = "glitch", Tint = Color3.fromRGB(190, 120, 255) },
		Brute = { Style = "low", Tint = Color3.fromRGB(255, 90, 90) },
		RatSwarm = { Style = "ground", Tint = Color3.fromRGB(200, 170, 120) },
		Gremlin = { Style = "whip", Tint = Color3.fromRGB(120, 255, 140) },
		Phantom = { Style = "blackout", Tint = Color3.fromRGB(170, 200, 255) },
	},
}

-- Repairs: broken machines can't be used until repaired for a share of their price.
Config.Repair = {
	ExplodeFraction = 0.5, -- ovens that explode after an unchecked Overheat
	DamageFraction = 0.25, -- machines smashed by anomalies
	HoldTime = 2, -- seconds to hold the Repair prompt
	OverheatWarning = 10, -- last seconds of an Overheat where ovens flash
}

return Config

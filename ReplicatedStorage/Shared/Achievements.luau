--!strict
-- Achievement definitions. Each one unlocks when PlayerData.Stats[Stat] reaches
-- Goal (Services/Achievements watches every stat change) and pays Gems.
-- BadgeId: optional Roblox badge awarded too (0 = none; create badges on the
-- Creator Dashboard and paste their IDs here).

export type Achievement = {
	Id: string,
	Icon: string,
	Name: string,
	Description: string,
	Stat: string,
	Goal: number,
	Gems: number,
	BadgeId: number,
}

local Achievements = {}

local function a(id: string, icon: string, name: string, description: string, stat: string, goal: number, gems: number): Achievement
	return { Id = id, Icon = icon, Name = name, Description = description, Stat = stat, Goal = goal, Gems = gems, BadgeId = 0 }
end

Achievements.List = {
	-- Selling
	a("FirstSale", "🍰", "First Sale", "Sell your first cake", "CakesSold", 1, 2),
	a("BakersDozen", "🧁", "Baker's Dozen", "Sell 13 cakes", "CakesSold", 13, 5),
	a("CakeTycoon", "🏪", "Cake Tycoon", "Sell 1,000 cakes", "CakesSold", 1000, 50),
	a("Thousandaire", "💵", "Thousandaire", "Earn $10,000 from sales", "TotalEarned", 10000, 5),
	a("Millionaire", "💰", "Millionaire", "Earn $1,000,000 from sales", "TotalEarned", 1000000, 40),
	-- Rolling
	a("Lucky", "🍀", "Lucky Roll", "Roll a Legendary ingredient", "BestRoll", 5, 10),
	a("Mythical", "💖", "Mythical", "Roll a Mythic ingredient", "BestRoll", 6, 25),
	a("BeyondMyth", "😇", "Beyond Myth", "Roll a Divine ingredient", "BestRoll", 7, 60),
	a("Anomalous", "🌀", "Anomalous!", "Roll an Anomalous ingredient", "BestRoll", 8, 150),
	a("IntoTheVoid", "🕳️", "Into the Void", "Roll a Void ingredient", "BestRoll", 9, 400),
	a("Celestial", "✨", "Celestial!", "Roll a Celestial ingredient", "BestRoll", 10, 1000),
	a("Hoarder", "🎲", "Hoarder", "Roll 500 ingredients", "IngredientsRolled", 500, 15),
	-- Baking
	a("Perfectionist", "🎯", "Perfectionist", "Make 10 Perfect mixes", "PerfectMixes", 10, 10),
	a("MutantBaker", "🧬", "Mutant Baker", "Bake a mutated cake", "Mutations", 1, 5),
	a("MadScientist", "🧪", "Mad Scientist", "Bake 50 mutated cakes", "Mutations", 50, 40),
	a("GalaxyBrain", "🌌", "Galaxy Brain", "Bake a Galaxy cake", "MutationGalaxy", 1, 15),
	a("TasteTheRainbow", "🌈", "Taste the Rainbow", "Bake a Rainbow cake", "MutationRainbow", 1, 20),
	a("IntoTheVoid", "🕳️", "Into the Void", "Bake a Void cake (only during anomalies)", "MutationVoid", 1, 40),
	-- Anomalies
	a("Firefighter", "🧯", "Firefighter", "Save 10 overheating ovens", "OvensSaved", 10, 10),
	a("Kaboom", "💥", "Kaboom", "Let an oven explode", "Explosions", 1, 2),
	a("Handyman", "🔧", "Handyman", "Repair 10 machines", "Repairs", 10, 10),
	a("MimicHunter", "👁️", "Mimic Hunter", "Stop 5 Mimics", "MimicsStopped", 5, 10),
	a("BruteForce", "💪", "Brute Force", "Knock out a Brute", "BrutesDefeated", 1, 10),
	a("PestControl", "🐀", "Pest Control", "Squash 50 rats", "RatsSquashed", 50, 15),
	a("GremlinCatcher", "👺", "Gremlin Catcher", "Catch a Gremlin for good", "GremlinsCaught", 1, 10),
	a("Ghostbuster", "👻", "Ghostbuster", "Banish a Phantom", "PhantomsBanished", 1, 10),
	a("AnomalyExpert", "🛡️", "Anomaly Expert", "Stop 25 anomaly creatures", "AnomaliesStopped", 25, 30),
	-- Progress
	a("FullyAutomated", "🏭", "Fully Automated", "Own 3 Auto-Bakers", "AutoBakersOwned", 3, 25),
	a("Reborn", "♻️", "Reborn", "Rebirth once", "Rebirths", 1, 25),
	a("Reborn5", "🔱", "Born Again (x5)", "Rebirth 5 times", "Rebirths", 5, 100),
}

function Achievements.Find(id: string): Achievement?
	for _, def in Achievements.List do
		if def.Id == id then
			return def
		end
	end
	return nil
end

return Achievements

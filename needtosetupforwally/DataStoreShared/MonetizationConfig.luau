local MonetizationConfig = {}
MonetizationConfig.DataKey = "MonetizationStore001"
MonetizationConfig.useMock = nil
MonetizationConfig.template = {
	PurchaseHistory = {},
	OwnedGamepasses = {},
	GroupRewardClaimedAt = nil,
	WasEverInGroup = false,
	WasInGroupOnLastJoin = false,
	IsCurrentlyInGroup = false,
	HasClaimedGroupReward = false,
}

MonetizationConfig.Gamepasses = {
	--[[
	-- Template
	[0] = {
		Name = "",
		StringId = "Monetization:Gamepasses:StringId",
		Description = nil,
		NormalPrice = nil
	}
	]]
	[1267827692] = {
		Name = "TripleXP",
		StringId = "Monetization:Gamepasses:TripleXP",
		Description = nil,
		NormalPrice = nil,
	},
	[1267309728] = {
		Name = "TripleCoins",
		StringId = "Monetization:Gamepasses:TripleCoins",
		Description = nil,
		NormalPrice = nil,
	},
	[1267509620] = {
		Name = "Magnet",
		StringId = "Monetization:Gamepasses:Magnet",
		Description = nil,
		NormalPrice = nil,
	},
	[1268829591] = {
		Name = "TripleDamage",
		StringId = "Monetization:Gamepasses:TripleDamage",
		Description = nil,
		NormalPrice = nil,
	},
	[1268751743] = {
		Name = "Void Beam",
		StringId = "Monetization:Gamepasses:Void Beam",
		Description = nil,
		NormalPrice = nil,
	},
}
MonetizationConfig.DevProducts = {
	--[[
	-- Template
	[0] = {
		Name = "",
		StringId = "Monetization:DevProducts:StringId",
		Description = nil,
		NormalPrice = nil
	}
	]]
	[3313069146] = {
		Name = "1kCoins",
		StringId = "Monetization:DevProducts:1kCoins",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069265] = {
		Name = "3kCoins",
		StringId = "Monetization:DevProducts:3kCoins",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069364] = {
		Name = "10kCoins",
		StringId = "Monetization:DevProducts:10kCoins",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069535] = {
		Name = "50kCoins",
		StringId = "Monetization:DevProducts:50kCoins",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069992] = {
		Name = "3UpgradeSlots",
		StringId = "Monetization:DevProducts:3UpgradeSlots",
		Description = nil,
		NormalPrice = nil,
	},
	[3313070073] = {
		Name = "4UpgradeSlots",
		StringId = "Monetization:DevProducts:4UpgradeSlots",
		Description = nil,
		NormalPrice = nil,
	},
	[3313070153] = {
		Name = "5UpgradeSlots",
		StringId = "Monetization:DevProducts:5UpgradeSlots",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069652] = {
		Name = "UnlockBrick",
		StringId = "Monetization:DevProducts:UnlockBrick",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069877] = {
		Name = "UnlockCrackedLava",
		StringId = "Monetization:DevProducts:UnlockCrackedLava",
		Description = nil,
		NormalPrice = nil,
	},
	[3313069768] = {
		Name = "UnlockSteal",
		StringId = "Monetization:DevProducts:UnlockSteal",
		Description = nil,
		NormalPrice = nil,
	},
}

return MonetizationConfig

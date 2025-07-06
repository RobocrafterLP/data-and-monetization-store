local DataConfig = {}
DataConfig.DataKey = "PlayerStore002"
DataConfig.useMock = nil
DataConfig.leaderstats = {
	{
		path = "Stats.Coins",
		name = "Coins",
		class = "NumberValue",
	},
	{
		path = "Stats.Level",
		name = "Level",
		class = "NumberValue",
	},
}

DataConfig.template = {
	GotVIPRewards = false,
	Gamepass = {},
	Inventory = {},
	UpgradeSlots = {
		Slot1 = true,
		Slot2 = true,
		Slot3 = false,
		Slot4 = false,
		Slot5 = false,
	},
	UnlockBlocks = {
		Lava = false,
		Metal = false,
		Brick = false,
	},
	Equipped = {
		Weapon = "Blaster",
		Slot1 = "",
		Slot2 = "",
		Slot3 = "",
		Slot4 = "",
		Slot5 = "",
	},
	Stats = {
		Coins = 0,
		XP = 0,
		Level = 1,
	},
	Monetization = {},
	Badges = {},
}

return DataConfig

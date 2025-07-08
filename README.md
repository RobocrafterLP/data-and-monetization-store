# Data and Monetization Store Handler

Data and monetization handler and replication

# Server

```luau
local DataAndMonetizationStore = require(path.to.service)
local DataStore = DataAndMonetizationStore.data.server
local MonetizationStore = DataAndMonetizationStore.monetization.server

DataStore:init({
	DataKey = "PlayerStore001",
    useMock = nil,
    leaderstats = {
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
    },
    template = {
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
    }
})

MonetizationStore:Init({
    DataKey = "MonetizationStore001",
    useMock = nil,
    template = {
        PurchaseHistory = {},
        OwnedGamepasses = {},
        GroupRewardClaimedAt = nil,
        WasEverInGroup = false,
        WasInGroupOnLastJoin = false,
        IsCurrentlyInGroup = false,
        HasClaimedGroupReward = false,
    },
    Gamepasses = {
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
    },
    DevProducts = {
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
    }
})

```

# Client

```luau
local DataAndMonetizationStore = require(path.to.service)
local DataStore = DataAndMonetizationStore.data.server
local MonetizationStore = DataAndMonetizationStore.monetization.server


```

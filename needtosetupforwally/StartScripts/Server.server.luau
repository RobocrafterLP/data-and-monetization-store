local DataStore = require(game.ServerScriptService.ServerDataStore)
local DataConfig = require(game.ReplicatedStorage.DataStoreShared.DataConfig)

local MonetizationStore = require(game.ServerScriptService.ServerMonetizationStore)
local MonetizationConfig = require(game.ReplicatedStorage.DataStoreShared.MonetizationConfig)

MonetizationStore:init(MonetizationConfig)
DataStore:init(DataConfig)

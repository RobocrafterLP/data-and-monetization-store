if game:GetService("RunService"):IsServer() then
	return {}
end

local Players = game:GetService("Players")
local DataStoreClientFolder = script.Parent.DataStoreClient

local LocalPlayer = Players.LocalPlayer
local ProfileClient = require(script.Parent.DataStoreClient.ProfileClient)
local ReplicaClient = require(DataStoreClientFolder.ReplicaClient)

local DataStoreClient = {
	_profiles = {} :: { [Player]: Profile },
}

function CreateProfile(replica)
	local player: Player? = replica.Tags.Player
	if not player then
		return
	end

	local Profile = ProfileClient.new(replica, player)

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(Players) then
			DataStoreClient._profiles[player] = nil
		end
	end)

	DataStoreClient._profiles[player] = Profile
end

function DataStoreClient.HasProfile(self: DataStoreClient, player: Player?): boolean
	return self._profiles[player or LocalPlayer] ~= nil
end

function DataStoreClient.GetProfile(self: DataStoreClient, player: Player?): Profile?
	return self._profiles[player or LocalPlayer]
end

function DataStoreClient.GetPlayerProfileAsync(self: DataStoreClient, player: Player?): Profile
	local Profile = self:GetProfile(player)
	repeat
		task.wait()
		Profile = self:GetProfile(player)
	until Profile
	return Profile
end

function DataStoreClient.init(self: DataStoreClient, DataOptions: DataOptions)
	self.DataOptions = DataOptions
	ReplicaClient.FromData(table.clone(DataOptions.template), "DataStore", 2)
end

export type DataOptions = {
	template: any,
	DataKey: string,
	useMock: boolean?,
	leaderstats: {
		{
			path: string,
			name: string,
			class: string,
		}
	}?,
}

export type Profile = ProfileClient.Profile

export type DataStoreClient = typeof(DataStoreClient)

ReplicaClient.OnNew("DataStore", CreateProfile)

ReplicaClient.RequestData()
return DataStoreClient

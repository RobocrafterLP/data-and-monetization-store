if game:GetService("RunService"):IsServer() then
	return {}
end

local Players = game:GetService("Players")
local DataStoreShared = script.Parent.DataStoreShared
local DataStoreClient = script.Parent.DataStoreClient

local LocalPlayer = Players.LocalPlayer
local Replica = require(DataStoreClient.ReplicaClient)
local Connection = require(DataStoreShared.Connection)

local Profile = {}
Profile.__index = Profile

local DataStore = {
	_profiles = {} :: { [Player]: Profile },
}

function StringPathToArray(path)
	local path_array = {}
	if path ~= "" then
		for s in string.gmatch(path, "[^%.]+") do
			table.insert(path_array, s)
		end
	end
	return path_array
end

function CreateProfile(replica)
	local player: Player? = replica.Tags.Player
	if not player then
		return
	end

	local playerreplica = setmetatable({
		Replica = replica,
		_player = player,
		Connections = {},
		Listeners = {
			Change = {},
			NewKey = {},
			RemoveKey = {},
			ArrayInsert = {},
			ArrayRemove = {},
			Leaderstats = {},
		},
	}, Profile)

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(Players) then
			DataStore._profiles[player] = nil
		end
	end)

	playerreplica.Replica:OnChange(function(action, path, new, old)
		local path_key = table.concat(path, ".")
		if action == "Set" and old ~= nil and new ~= nil then
			local listeners = playerreplica.Listeners.Change[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
				end
			end
		elseif action == "Set" and old and new == nil then
			local key = table.remove(path, #path)
			local path_key = table.concat(path, ".")
			local listeners = playerreplica.Listeners.RemoveKey[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(key, new, old)
				end
			end
		elseif action == "Set" and old == nil and new then
			local key = table.remove(path, #path)
			local path_key = table.concat(path, ".")
			local listeners = playerreplica.Listeners.NewKey[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(key, new, old)
				end
			end
		elseif action == "TableInsert" then
			local listeners = playerreplica.Listeners.ArrayInsert[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
				end
			end
		elseif action == "TableRemove" then
			local listeners = playerreplica.Listeners.ArrayRemove[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
				end
			end
		end
	end)

	DataStore._profiles[player] = playerreplica
end

function Profile.IsActive(self: Profile)
	return self.Replica:IsActive()
end

function Profile.GetValue(self: Profile, path: string | { any })
	if self:IsActive() == false then
		return
	end

	if typeof(path) == "string" then
		return self.Replica:Get(StringPathToArray(path))
	end

	return self.Replica:Get(path)
end

function Profile.SubscribeToChange(
	self: Profile,
	path: string | { any },
	listener: (new: any, old: any) -> ()
): Connection
	local path_key = typeof(path) == "string" and path or typeof(path) == "table" and table.concat(path, ".")

	local listeners = self.Listeners.Change[path_key]
	if listeners == nil then
		listeners = {}
		self.Listeners.Change[path_key] = listeners
	end

	return Connection.new(listeners, listener)
end

function Profile.SubscribeToNewKey(
	self: Profile,
	path: string | { any },
	listener: (key: any, new: any, old: any) -> ()
): Connection
	local path_key = typeof(path) == "string" and path or typeof(path) == "table" and table.concat(path, ".")

	local listeners = self.Listeners.NewKey[path_key]
	if listeners == nil then
		listeners = {}
		self.Listeners.NewKey[path_key] = listeners
	end

	return Connection.new(listeners, listener)
end

function Profile.SubscribeToRemoveKey(
	self: Profile,
	path: string | { any },
	listener: (key: any, new: any, old: any) -> ()
): Connection
	local path_key = typeof(path) == "string" and path or typeof(path) == "table" and table.concat(path, ".")

	local listeners = self.Listeners.RemoveKey[path_key]
	if listeners == nil then
		listeners = {}
		self.Listeners.RemoveKey[path_key] = listeners
	end

	return Connection.new(listeners, listener)
end

function Profile.SubscribeToArrayInsert(
	self: Profile,
	path: string | { any },
	listener: (new: any, old: any) -> ()
): Connection
	local path_key = typeof(path) == "string" and path or typeof(path) == "table" and table.concat(path, ".")

	local listeners = self.Listeners.ArrayInsert[path_key]
	if listeners == nil then
		listeners = {}
		self.Listeners.ArrayInsert[path_key] = listeners
	end

	return Connection.new(listeners, listener)
end

function Profile.SubscribeToArrayRemove(
	self: Profile,
	path: string | { any },
	listener: (new: any, old: any) -> ()
): Connection
	local path_key = typeof(path) == "string" and path or typeof(path) == "table" and table.concat(path, ".")

	local listeners = self.Listeners.ArrayRemove[path_key]
	if listeners == nil then
		listeners = {}
		self.Listeners.ArrayRemove[path_key] = listeners
	end

	return Connection.new(listeners, listener)
end

function DataStore.HasProfile(self: DataStore, player: Player?): boolean
	return self._profiles[player or LocalPlayer] ~= nil
end

function DataStore.GetProfile(self: DataStore, player: Player?): Profile?
	return self._profiles[player or LocalPlayer]
end

function DataStore.GetPlayerProfileAsync(self: DataStore, player: Player?): Profile
	local Profile = self:GetProfile(player)
	repeat
		task.wait()
		Profile = self:GetProfile(player)
	until Profile
	return Profile
end

function DataStore.init(self: DataStore, DataOptions: DataOptions)
	self.DataOptions = DataOptions
	Replica.FromData(table.clone(DataOptions.template), DataOptions.DataKey, 2)
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

export type Connections = { [string | { string }]: typeof(Connection.new()) }

export type Connection = typeof(Connection.new())

export type DataStore = typeof(DataStore)

export type Profile = typeof(Profile) & {
	Replica: Replica.Replica,
	_player: Player,
	Listeners: {
		Change: Connections,
		NewKey: Connections,
		RemoveKey: Connections,
		ArrayInsert: Connections,
		ArrayRemove: Connections,
	},
}

Replica.OnNew("DataStore", CreateProfile)

Replica.RequestData()
return DataStore

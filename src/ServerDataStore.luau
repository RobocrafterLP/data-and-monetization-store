if game:GetService("RunService"):IsClient() then
	return {}
end

local Players = game:GetService("Players")

local DataStoreShared = script.Parent.DataStoreShared
local DataStoreServer = script.Parent.DataStoreServer

local Replica = require(DataStoreServer.ReplicaServer)
local ProfileStore = require(DataStoreServer.ProfileStore)
local Connection = require(DataStoreShared.Connection)

local Profile = {}
Profile.__index = Profile

local DataStoreServer = {
	_profiles = {} :: { [Player]: Profile },
	options = {},
	profileStore = {} :: ProfileStore.ProfileStore<any>,
	token = {} :: Replica.Token,
	_init = false,
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

function Profile.IsActive(self: Profile): boolean
	return self.Profile:IsActive()
end

function Profile.EndSession(self: Profile): ()
	self.Profile:EndSession()
end

function Profile.GetValue(self: Profile, path: string | { any }): any
	if self:IsActive() == false then
		return
	end

	if typeof(path) == "string" then
		return self.Replica:Get(StringPathToArray(path))
	end

	return self.Replica:Get(path)
end

function Profile.SetValue(self: Profile, path: string | { any }, value: any): ()
	if self:IsActive() == false then
		return
	end
	if typeof(path) == "string" then
		self.Replica:Set(StringPathToArray(path), value)
	else
		self.Replica:Set(path, value)
	end

	self:VisualizeData()
end

function Profile.SetValues(self: Profile, path: string | { any }, value: any): ()
	if self:IsActive() == false then
		return
	end
	if typeof(path) == "string" then
		self.Replica:SetValues(StringPathToArray(path), value)
	else
		self.Replica:SetValues(path, value)
	end

	self:VisualizeData()
end

function Profile.AddValue(self: Profile, path: string | { any }, value: any): number
	local oldvalue = self:GetValue(path) or 0
	local newValue = oldvalue + value
	self:SetValue(path, newValue)
	return newValue
end

function Profile.RemoveValue(self: Profile, path: string | { any }, value: any): number
	local oldvalue = self:GetValue(path) or 0
	local newValue = oldvalue - value
	self:SetValue(path, newValue)
	return newValue
end

function Profile.TableInsert(self: Profile, path: string | { any }, value: any, index: number?): number?
	if self:IsActive() == false then
		return
	end
	local Data

	if typeof(path) == "string" then
		Data = self.Replica:TableInsert(StringPathToArray(path), value, index)
	else
		Data = self.Replica:TableInsert(path, value, index)
	end

	self:VisualizeData()
	return Data
end

function Profile.TableRemove(self: Profile, path: string | { any }, index: number): number?
	if self:IsActive() == false then
		return
	end
	local Data

	if typeof(path) == "string" then
		Data = self.Replica:TableRemove(StringPathToArray(path), index)
	else
		Data = self.Replica:TableRemove(path, index)
	end

	self:VisualizeData()
	return Data
end

function Profile.AddLeaderstat(self: Profile, path: string | { any }, Name: string, Type: string): ()
	if not self.leaderstats then
		local leader = Instance.new("Folder", self._player)
		leader.Name = "leaderstats"
		self.leaderstats = leader
	end

	local NewValue = Instance.new(Type, self.leaderstats)
	NewValue.Name = Name
	spawn(function()
		local value = nil
		repeat
			value = self:GetValue(path)
			task.wait()
		until value ~= nil

		if typeof(NewValue.Value) == typeof(value) then
			NewValue.Value = value
		end
	end)

	self.Connections[path] = self:SubscribeToChange(path, function(value)
		NewValue.Value = value
	end)
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
	listener: (new: any, old: any) -> ()
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
	listener: (new: any, old: any) -> ()
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

function Profile.Save(self: Profile): ()
	self.Profile:Save()
end

function Profile.WipeData(self: Profile): ()
	self:SetValue({}, {})
	self.Profile:Reconcile()
	self:Save()
end

function Profile.VisualizeData(self: Profile): ()
	if not game:GetService("RunService"):IsStudio() then
		return
	end
	local FolderName = "Data"

	local visual = self._player:FindFirstChild(FolderName)

	-- fix later to remove instaces that aren't stored in the profile anymore
	if not visual then
		visual = Instance.new("Folder", self._player)
		visual.Name = FolderName
	end

	local function processnum(Par, Nam, Val)
		local num = Par:FindFirstChild(Nam) or Instance.new("NumberValue", Par)
		num.Name = Nam
		num.Value = Val
	end

	local function processstring(Par, Nam, Val)
		local str = Par:FindFirstChild(Nam) or Instance.new("StringValue", Par)
		str.Name = Nam
		str.Value = Val
	end

	local function processbool(Par, Nam, Val)
		local bool = Par:FindFirstChild(Nam) or Instance.new("BoolValue", Par)
		bool.Name = Nam
		bool.Value = Val
	end

	local function ProcessTable(Table, Parent)
		for key, value in pairs(Table) do
			if typeof(value) == "string" then
				processstring(Parent, key, Table[key])
			end

			if typeof(value) == "number" then
				processnum(Parent, key, Table[key])
			end

			if typeof(value) == "boolean" then
				processbool(Parent, key, Table[key])
			end

			if type(value) == "table" then
				local newpar = Parent:FindFirstChild(key) or Instance.new("Folder", Parent)
				newpar.Name = key
				ProcessTable(Table[key], newpar)
			end
		end
	end

	ProcessTable(self.Profile.Data, visual)
end

function DataStoreServer.init(self: DataStoreServer, options: DataOptions): ()
	local PlayerStore = ProfileStore.New(options.DataKey, options.template)
	self.options = options
	self.profileStore = options.useMock and PlayerStore.Mock or PlayerStore
	self.token = Replica.Token("DataStoreServer")

	for _, player: Player in Players:GetPlayers() do
		task.spawn(function()
			self:_playerAdded(player)
		end)
	end

	Players.PlayerAdded:Connect(function(player: Player)
		self:_playerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_playerRemoving(player)
	end)
	self._init = true
end

function DataStoreServer._playerAdded(self: DataStoreServer, player: Player): ()
	local userId = player.UserId

	local playerprofile: ProfileStore.Profile<typeof(self.options.template)> =
		self.profileStore:StartSessionAsync(`{userId}`, {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})

	if not playerprofile then
		player:Kick(`Profile load fail - Please rejoin`)
		return
	end

	playerprofile:AddUserId(userId)
	playerprofile:Reconcile()

	playerprofile.OnSessionEnd:Connect(function()
		local profile = self._profiles[player]
		for index, Connection in profile.Connections do
			Connection:Disconnect()
			profile.Connections[index] = nil
		end
		self._profiles[player] = nil
		player:Kick(`Profile session end - Please rejoin`)
	end)

	if not player:IsDescendantOf(Players) then
		playerprofile:EndSession()
		return
	end

	local playerreplica = setmetatable({
		Profile = playerprofile,
		Replica = Replica.New({
			Token = self.token,
			Tags = { Player = player },
			Data = playerprofile.Data,
			Replication = "All",
		}),
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

	if self.options.leaderstats then
		for _, data in self.options.leaderstats do
			playerreplica:AddLeaderstat(data.path, data.name, data.class)
		end
	end

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
					connection:Fire(new, old)
				end
			end
		elseif action == "Set" and old == nil and new then
			local key = table.remove(path, #path)
			local path_key = table.concat(path, ".")
			local listeners = playerreplica.Listeners.NewKey[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
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

	playerreplica:VisualizeData()
	playerreplica.Replica:Replicate()

	self._profiles[player] = playerreplica
	self:OnPlayerAdded(player, playerreplica)
end

function DataStoreServer._playerRemoving(self: DataStoreServer, player: Player): ()
	local profile = self:GetProfile(player)

	if not profile then
		return
	end

	self:OnPlayerRemoving(player, profile)

	profile:EndSession()
	self._profiles[player].Replica:Destroy()
	self._profiles[player] = nil
end

function DataStoreServer.OnPlayerAdded(self: DataStoreServer, _player: Player, _profile: Profile) end
function DataStoreServer.OnPlayerRemoving(self: DataStoreServer, _player: Player, _profile: Profile) end

function DataStoreServer._isinit(self: DataStoreServer): ()
	assert(self._init, "Init first to use Datastore")
end

function DataStoreServer.GetProfile(self: DataStoreServer, player: Player): Profile?
	self:_isinit()
	return self._profiles[player] :: Profile?
end

function DataStoreServer.HasProfile(self: DataStoreServer, player: Player): boolean
	self:_isinit()
	return self._profiles[player] ~= nil
end

function DataStoreServer.GetPlayerProfileAsync(self: DataStoreServer, player: Player): Profile
	self:_isinit()
	local Profile = self:GetProfile(player)
	repeat
		task.wait()
		Profile = self:GetProfile(player)
	until Profile
	return Profile
end

export type DataStoreServer = typeof(DataStoreServer)

export type Connections = { [string | { string }]: typeof(Connection.new()) }

export type Connection = typeof(Connection.new())

export type Profile = typeof(Profile) & {
	Profile: ProfileStore.Profile<any>,
	Replica: Replica.Replica,
	_player: Player,
	Connections: Connections,
	Listeners: {
		Change: Connections,
		NewKey: Connections,
		RemoveKey: Connections,
		ArrayInsert: Connections,
		ArrayRemove: Connections,
	},
	leaderstats: Folder?,
}

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

return DataStoreServer

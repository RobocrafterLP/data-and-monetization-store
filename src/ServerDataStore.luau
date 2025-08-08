if game:GetService("RunService"):IsClient() then
	return {}
end

local Players = game:GetService("Players")

local DataStoreServerFolder = script.Parent.DataStoreServer

local Replica = require(DataStoreServerFolder.ReplicaServer)
local ProfileStore = require(DataStoreServerFolder.ProfileStore)
local ProfileServer = require(DataStoreServerFolder.ProfileServer)

local DataStoreServer = {
	_profiles = {} :: { [Player]: Profile },
	options = {},
	profileStore = {} :: ProfileStore.ProfileStore<any>,
	token = {} :: Replica.Token,
	_init = false,
}

function DataStoreServer.init(self: DataStoreServer, options: DataOptions): ()
	local PlayerStore = ProfileStore.New(options.DataKey, options.template)
	self.options = options
	self.profileStore = options.useMock and PlayerStore.Mock or PlayerStore
	self.token = Replica.Token("DataStore")

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

	local Profile = ProfileServer.new(self.token, playerprofile, player)

	Profile.OnSessionEnd:Connect(function()
		self._profiles[player] = nil
		player:Kick(`Profile session end - Please rejoin`)
	end)

	if not player:IsDescendantOf(Players) then
		Profile:EndSession()
		return
	end

	if self.options.leaderstats then
		for _, data in self.options.leaderstats do
			Profile:AddLeaderstat(data.path, data.name, data.class)
		end
	end

	self._profiles[player] = Profile
	self:OnPlayerAdded(player, Profile)
end

function DataStoreServer._playerRemoving(self: DataStoreServer, player: Player): ()
	local profile = self:GetProfile(player)

	if not profile then
		return
	end

	self:OnPlayerRemoving(player, profile)

	profile:EndSession()
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

export type Profile = ProfileServer.Profile

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

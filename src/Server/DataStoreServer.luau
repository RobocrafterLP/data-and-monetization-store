local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

if RunService:IsClient() then
	return {} :: any
end

local ProfileServer = require(script.Parent.ProfileServer)
local Utils = require(script.Parent.Parent.Shared.Utils)
local ProfileStore = if RunService:IsServer() then require(script.Parent.Parent.Parent.ProfileStore) else nil :: any
local Networker = require(script.Parent.Parent.Parent.Networker)
local Signal = require(script.Parent.Parent.Parent.Signal)
local Value = require(script.Parent.Parent.Shared.Value)

local DEFAULT_PROFILE_STORE_INDEX = "Default_DataStore"
local storeCancel = Utils.storeCancel

local DataStoreServer = {
	_profiles = {} :: {[Player]: Profile<any>},
	_waitSignals = {} :: { [Player]: Signal.Signal<any> },
	_removalFunctions = {} :: { (player: Player, data: any) -> () },
	_loadingPlayers = {} :: { [Player]: boolean },
	_globalCallbacks = {} :: { [string]: (player: Player, { any }) -> boolean? },
	_globalCallbackAdded = Signal.new() :: Signal.Signal<string>,
	data = {} :: { [Player]: Value.Value<any> },
}

export type Profile<T> = ProfileServer.Profile<T>
export type DataOptions<T> = Utils.DataOptions<T>
export type DataStoreServer<T> = typeof(DataStoreServer) & {
	networker: Networker.Server,
	data: { [Player]: Value.Value<T> },
	options: DataOptions<T>,
	playerStore: any,
}
export type MessageData = {
	key: string,
	data: { any },
}

function DataStoreServer._configure<T>(self: DataStoreServer<T>, options: DataOptions<T>): DataStoreServer<T>
	assert(RunService:IsServer(), "DataStoreServer can only be used on the server.")
	assert(not self.options, "DataStoreServer has already been configured.")
	Value.shouldRecordPath = true
	self.options = options
	
	return self
end

function DataStoreServer.init<T>(self: DataStoreServer<T>): ()
	assert(RunService:IsServer(), "DataStoreServer can only be used on the server.")
	assert(self.options, "DataStoreServer has not been configured.")
	assert(not self.playerStore, "DataStoreServer has already been initialized.")
	self.networker = Networker.server.new("DataStore", self, {
		self.requestData,
	})
	self.playerStore = ProfileStore.New(self.options.dataKey or DEFAULT_PROFILE_STORE_INDEX, self.options.template)

	Players.PlayerAdded:Connect(function(player: Player)
		self:_playerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		self:_playerRemoving(player)
	end)

	for _, player: Player in Players:GetPlayers() do
		task.spawn(function()
			self:_playerAdded(player)
		end)
	end
end

function DataStoreServer.resetData<T>(self: DataStoreServer<T>, player: Player): ()
	local index = self:_getProfileKey(player.UserId)
	self:_playerRemoving(player)
	self.playerStore:RemoveAsync(index)
	player:Kick("Your data has been reset. Please rejoin.")
end

function DataStoreServer.requestData<T>(self: DataStoreServer<T>, player: Player): ()
	local Profile = self:GetProfile(player)
	if Profile == nil then
		return
	end

	if self.options.dataReplica == "All" then
		self.networker:fireAll("load", player, Profile.Data())

		task.delay(0.05, function()
			for profileplayer, profile in self._profiles do
				if profileplayer == player then
					continue
				end

				self.networker:fire(player, "load", profileplayer, profile.Data())
			end
		end)
	else
		self.networker:fire(player, "load", player, Profile.Data())
	end
end

function DataStoreServer._playerAdded<T>(self: DataStoreServer<T>, player: Player): ()
	if self._loadingPlayers[player] or self._profiles[player] then
		return
	end
	self._loadingPlayers[player] = true

	local userId = self.options.overridenUserId or self.options.viewedUserId or player.UserId
	local index = self:_getProfileKey(userId)

	if self.options.resetData and not self.options.viewedUserId then
		self.playerStore:RemoveAsync(index)
	end

	local playerprofile = if self.options.useMock
		then self.playerStore.Mock:StartSessionAsync(index, storeCancel(player))
		elseif self.options.viewedUserId or self.options.dontSave then self.playerStore:GetAsync(index)
		else self.playerStore:StartSessionAsync(index, storeCancel(player))

	local Profile = ProfileServer.new(playerprofile, player, function(replicateType: string, path: { string }, ...)
		if self.options.dataReplica == "All" then
			self.networker:fireAll(replicateType, player, path, ...)
		else
			self.networker:fire(player, replicateType, player, path, ...)
		end
	end, "Data")
	self._loadingPlayers[player] = nil

	if not Profile then
		if player:IsDescendantOf(Players) then
			player:Kick(`Profile load fail - Please rejoin`)
		end
		return
	end

	Profile:AddUserId(player.UserId)
	Profile:Reconcile()
	Profile.OnSessionEnd:Connect(function()
		self._profiles[player] = nil
		player:Kick(`Profile session end - Please rejoin`)
	end)

	if not player:IsDescendantOf(Players) then
		Profile:EndSession()
		return
	end

	self._profiles[player] = Profile
	self:_initPlayer(player, Profile)

	if not player:IsDescendantOf(Players) then
		player:Kick(`Profile load fail - Please rejoin`)
		return
	end

	Profile:MessageHandler(function(messageData: MessageData, processed: () -> ())
		local cb = self._globalCallbacks[messageData.key]
		if cb then
			if cb(player, messageData.data) ~= false then
				processed()
			end
			return
		end

		local waitConnection
		waitConnection = self._globalCallbackAdded:Connect(function(key: string)
			if key ~= messageData.key then
				return
			end
			if self._globalCallbacks[messageData.key](player, messageData.data) ~= false then
				processed()
			end
			waitConnection:Disconnect()
		end)
	end)
end

function DataStoreServer._playerRemoving<T>(self: DataStoreServer<T>, player: Player): ()
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	for _, fn in self._removalFunctions do
		local success, err: any? = pcall(fn, player, profile)
		if not success then
			warn(err or "Error in removal function for " .. player.Name)
		end
	end

	profile:EndSession()
	self._profiles[player] = nil

	local waitSignal = self._waitSignals[player]
	if waitSignal then
		waitSignal:Destroy()
		self._waitSignals[player] = nil
	end

	self.data[player] = nil

	if self.options.dataReplica == "All" then
		self.networker:fireAll("destroy", player)
	else
		self.networker:fire(player, "destroy", player)
	end
end

function DataStoreServer.OnPlayerAdded<T>(_self: DataStoreServer<T>, _player: Player, _profile: Profile<T>) end

function DataStoreServer._initPlayer<T>(self: DataStoreServer<T>, player: Player, profile: Profile<T>)
	self:OnPlayerAdded(player, profile)
	if not self:HasProfile(player) then
		return
	end

	if self.options.dataReplica == "All" then
		self.networker:fireAll("load", player, profile.Data())

		task.delay(0.05, function()
			for profileplayer, profiledata in self._profiles do
				if profileplayer == player then
					continue
				end

				self.networker:fire(player, "load", profileplayer, profiledata.Data())
			end
		end)
	else
		self.networker:fire(player, "load", player, profile.Data())
	end

	if self.options.leaderstats then
		for _, data in self.options.leaderstats do
			profile:AddLeaderstat(data.path, data.name, data.class)
		end
	end

	self:_resolveWaiters(player)
end

function DataStoreServer._resolveWaiters<T>(self: DataStoreServer<T>, player: Player): ()
	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		return
	end

	self._waitSignals[player] = nil
	waitSignal:Fire()
	waitSignal:Destroy()
end

function DataStoreServer.GetProfile<T>(self: DataStoreServer<T>, player: Player): Profile<T>?
	return self._profiles[player] :: Profile<T>?
end

function DataStoreServer.HasProfile<T>(self: DataStoreServer<T>, player: Player): boolean
	return self._profiles[player] ~= nil
end

function DataStoreServer.GetPlayerProfileAsync<T>(self: DataStoreServer<T>, player: Player): Profile<T>
	local Profile = self:GetProfile(player)
	if Profile or not player:IsDescendantOf(Players) then
		return Profile :: Profile<T>
	end

	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		waitSignal = Signal.new()
		self._waitSignals[player] = waitSignal

		local leftConnection: RBXScriptConnection
		leftConnection = player.AncestryChanged:Connect(function()
			if not player:IsDescendantOf(Players) then
				leftConnection:Disconnect()
				self:_resolveWaiters(player)
			end
		end)
	end

	waitSignal:Wait()
	return self:GetProfile(player) :: Profile<T>
end

function DataStoreServer.addPlayerRemovingCallback(
	self: DataStoreServer<any>,
	fn: (player: Player, profile: Profile<any>) -> ()
): () -> ()
	table.insert(self._removalFunctions, fn)
	return function()
		local index = table.find(self._removalFunctions, fn)
		if index then
			table.remove(self._removalFunctions, index)
		end
	end
end

function DataStoreServer._getProfileKey(self: DataStoreServer<any>, userId: number | string): string
	return self:_getDataPrefix() .. tostring(userId)
end

function DataStoreServer._getDataPrefix(self: DataStoreServer<any>): string
	return self.options.dataPrefix or ""
end

return DataStoreServer
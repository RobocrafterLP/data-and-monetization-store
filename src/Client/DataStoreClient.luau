local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProfileClient = require(script.Parent.ProfileClient)
local Utils = require(script.Parent.Parent.Shared.Utils)
local Networker = require(script.Parent.Parent.Parent.Networker)
local Signal = require(script.Parent.Parent.Parent.Signal)
local Value = require(script.Parent.Parent.Shared.Value)

local LocalPlayer = Players.LocalPlayer

local DataStoreClient = {
	_profiles = {} :: any,
	_waitSignals = {} :: { [Player]: Signal.Signal<any> },

	data = {} :: { [Player]: Value.Value<any> },
	
	ProfileAdded = Signal.new() :: Signal.Signal<Profile<any>, Player>,
	ProfileRemoved = Signal.new() :: Signal.Signal<Profile<any>, Player>
}

export type Profile<T> = ProfileClient.Profile<T>
export type DataOptions<T> = Utils.DataOptions<T>
export type DataStoreClient<T> = typeof(DataStoreClient) & {
	networker: Networker.Server,
	data: { [Player]: Value.Value<any> },
	options: DataOptions<T>,
	playerStore: any,
}

function DataStoreClient.init<T>(self: DataStoreClient<T>, options: DataOptions<T>?)
	if not RunService:IsRunning() then
		self:load(LocalPlayer, options.template)
		return self
	end

	self.networker = Networker.client.new("DataStore", self)
	self.networker:fire("requestData")
	self:GetPlayerProfileAsync()
	return self
end

function DataStoreClient.GetProfile<T>(self: DataStoreClient<T>, player: Player?): Profile<T>?
	return self._profiles[player or LocalPlayer]
end

function DataStoreClient.HasProfile<T>(self: DataStoreClient<T>, player: Player?): boolean
	return self._profiles[player or LocalPlayer] ~= nil
end

function DataStoreClient.GetPlayerProfileAsync<T>(self: DataStoreClient<T>, player: Player?): Profile<T>
	player = player or LocalPlayer
	local Profile = self:GetProfile(player)
	if Profile then
		return Profile
	end

	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		waitSignal = Signal.new()
		self._waitSignals[player] = waitSignal
	end

	waitSignal:Wait()
	return self:GetProfile(player)
end

function DataStoreClient.load<T>(self: DataStoreClient<T>, player: Player, data: T)
	if not player or not data then
		return
	end

	local profile = ProfileClient.new(data, player)
	self._profiles[player] = profile

	local waitSignal = self._waitSignals[player]
	if waitSignal then
		waitSignal:Fire()
		waitSignal:Destroy()
		self._waitSignals[player] = nil
	end

	self.ProfileAdded:Fire(profile, player)
end

function DataStoreClient.get<T>(self: DataStoreClient<T>, player: Player, path: { string }): Value.Value<any>
	local profile = self:GetPlayerProfileAsync(player)

	local current = profile.Data
	for i = #path, 2, -1 do
		local key = path[i]
		current = (current :: any)[key]
	end

	return current[path[1]]
end

function DataStoreClient.set<T>(self: DataStoreClient<T>, player: Player, path: { string }, value: any?)
	self:get(player, path)(value)
end

function DataStoreClient.insert<T>(self: DataStoreClient<T>, player: Player, path: { string }, item: any, pos: number?)
	self:get(player, path).Insert(item, pos)
end

function DataStoreClient.remove<T>(self: DataStoreClient<T>, player: Player, path: { string }, pos: number?)
	self:get(player, path).Remove(pos)
end

function DataStoreClient.destroy<T>(self: DataStoreClient<T>, player: Player)
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	self._profiles[player] = nil

	local waitSignal = self._waitSignals[player]
	if waitSignal then
		waitSignal:Destroy()
		self._waitSignals[player] = nil
	end

	self.ProfileRemoved:Fire(profile, player)
end

return DataStoreClient

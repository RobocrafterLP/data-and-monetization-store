local Value = require(script.Parent.Parent.Shared.Value)
local Utils = require(script.Parent.Parent.Shared.Utils)

local Profile = {}
Profile.__index = Profile

type Disconnect = Utils.Disconnect
export type OnArrayRemove<T> = (T, number?) -> ()
export type OnArrayInsert<T> = (T, number?) -> ()
export type Changed<T> = (T, T, string?) -> ()
export type Value<T> = Value.Value<T>
export type Path = string | { string }
export type Profile<T> = typeof(setmetatable(
	{} :: {
		Active: boolean,
		Data: Value<T>,
		_player: Player,
		Listeners: { Disconnect },
	},
	Profile
))

local Get = Utils.Get
local DisconnectCallback = Utils.DisconnectCallback

function Profile.IsActive<T>(self: Profile<T>)
	return self.Active
end

function Profile.GetValue<T>(self: Profile<T>, path: Path)
	if self:IsActive() == false then
		return
	end

	return Get(self.Data, path)()
end

function Profile.SetValue<T>(self: Profile<T>, path: Path, value: T)
	if self:IsActive() == false then
		return
	end

	Get(self.Data, path)(value)
end

function Profile.AddValue<T>(self: Profile<T>, path: Path, value: any): number
	assert(typeof(value) == "number", `expected number got {typeof(value)}`)
	local oldvalue = self:GetValue(path) or 0
	local newValue = oldvalue + value
	self:SetValue(path, newValue)
	return newValue
end

function Profile.RemoveValue<T>(self: Profile<T>, path: Path, value: any): number
	assert(typeof(value) == "number", `expected number got {typeof(value)}`)
	local oldvalue = self:GetValue(path) or 0
	local newValue = oldvalue - value
	self:SetValue(path, newValue)
	return newValue
end

function Profile.TableInsert<T>(self: Profile<T>, path: Path, value: any, index: number?)
	Get(self.Data, path).Insert(value, index)
	self:VisualizeData()
end

function Profile.TableRemove<T>(self: Profile<T>, path: Path, index: number)
	Get(self.Data, path).Remove(index)
	self:VisualizeData()
end

function Profile.SubscribeToChange<T>(self: Profile<T>, path: Path, listener: Changed<T>): Disconnect?
	if self:IsActive() == false then
		return
	end

	local dc = Get(self.Data, path).OnChanged(listener)
	return DisconnectCallback(self.Listeners, dc)
end

function Profile.SubscribeToArrayInsert<T>(self: Profile<T>, path: Path, listener: OnArrayInsert<T>): Disconnect?
	if self:IsActive() == false then
		return
	end

	local dc = Get(self.Data, path).OnInsert(listener)
	return DisconnectCallback(self.Listeners, dc)
end

function Profile.SubscribeToArrayRemove<T>(self: Profile<T>, path: Path, listener: OnArrayRemove<T>): Disconnect?
	if self:IsActive() == false then
		return
	end

	local dc = Get(self.Data, path).OnRemove(listener)
	return DisconnectCallback(self.Listeners, dc)
end

function Profile.Destroy<T>(self: Profile<T>)
	self.Active = false

	for _index, dc in self.Listeners do
		dc()
	end

	table.freeze(self)
end

function Profile.new<T>(data: any, player: Player): Profile<T>
	local self = setmetatable({
		Active = true,
		_player = player,
		Listeners = {},
		Data = Value.new(data)
	}, Profile)

	return self
end

return Profile
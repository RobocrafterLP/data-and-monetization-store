local DataStoreSharedFolder = script.Parent.Parent.DataStoreShared
local DataStoreClientFolder = script.Parent.Parent.DataStoreClient

local Sift = require(script.Parent.Parent.Parent.Sift)
local ReplicaClient = require(DataStoreClientFolder.ReplicaClient)
local Signal = require(DataStoreSharedFolder.GoodSignal)

local Profile = {}
Profile.__index = Profile

export type Path = string | { string }

function StringPathToArray(path)
	local path_array = {}
	if path ~= "" then
		for s in string.gmatch(path, "[^%.]+") do
			table.insert(path_array, s)
		end
	end
	return path_array
end

local function pathToString(path: Path): string
	if type(path) == "string" then
		return path
	end

	local pathString = ""
	local maxIndex = #path - 1
	for i, key in ipairs(path) do
		if type(key) == "number" then
			pathString ..= "#"
		end

		pathString ..= key
		if i < maxIndex then
			pathString ..= "."
		end
	end

	return pathString
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
	return self:_getSignal(path, "Change"):Connect(listener)
end

function Profile.SubscribeToNewKey(
	self: Profile,
	path: string | { any },
	listener: (key: any, new: any, old: any) -> ()
): Connection
	return self:_getSignal(path, "NewKey"):Connect(listener)
end

function Profile.SubscribeToRemoveKey(
	self: Profile,
	path: string | { any },
	listener: (key: any, new: any, old: any) -> ()
): Connection
	return self:_getSignal(path, "RemoveKey"):Connect(listener)
end

function Profile.SubscribeToArrayInsert(
	self: Profile,
	path: string | { any },
	listener: (new: any, old: any) -> ()
): Connection
	return self:_getSignal(path, "ArrayInsert"):Connect(listener)
end

function Profile.SubscribeToArrayRemove(
	self: Profile,
	path: string | { any },
	listener: (new: any, old: any) -> ()
): Connection
	return self:_getSignal(path, "ArrayRemove"):Connect(listener)
end

--Made by leifstout. Modified by RobocrafterLP
function Profile._getSignal<T>(
	self: Profile,
	path: Path,
	signalType: "Change" | "NewKey" | "RemoveKey" | "ArrayInsert" | "ArrayRemove"
): Signal<any>
	local pathString = pathToString(path)
	if not self.Listeners[signalType][pathString] then
		self.Listeners[signalType][pathString] = Signal.new()
	end

	return self.Listeners[signalType][pathString]
end

function Profile._fireSignal<T>(
	self: Profile,
	path: Path,
	signalType: "Change" | "NewKey" | "RemoveKey" | "ArrayInsert" | "ArrayRemove",
	arg1: any?,
	arg2: any?,
	arg3: any?
)
	local pathString = pathToString(path)
	local signal = self.Listeners[signalType][pathString]
	if signal then
		signal:Fire(arg1, arg2, arg3)
	end
end

function Profile.new(replica, player)
	local self = setmetatable({
		Replica = replica,
		_player = player,
		Connections = {},
		Listeners = {
			Change = {},
			NewKey = {},
			RemoveKey = {},
			ArrayInsert = {},
			ArrayRemove = {},
		},
	}, Profile)

	self.Replica:OnChange(function(action, path, new, old)
		if action == "Set" and old ~= nil and new ~= nil then
			self:_fireSignal(path, "Change", new, old)
		elseif action == "Set" and old ~= nil and new == nil then
			self:_fireSignal(path, "RemoveKey", path[#path], new, old)
		elseif action == "Set" and old == nil and new ~= nil then
			self:_fireSignal(path, "NewKey", path[#path], new, old)
		elseif action == "TableInsert" then
			self:_fireSignal(path, "ArrayInsert", new, old)
		elseif action == "TableRemove" then
			self:_fireSignal(path, "ArrayRemove", new, old)
		elseif action == "SetValues" and not Sift.Dictionary.equals(new, old) then
			local keys = Sift.Array.join(
				Sift.Dictionary.keys(new),
				Sift.Dictionary.keys(old)
			)

			self:_fireSignal(path, "Change", new, old)
			for _, key in keys do
				local newValue = new[key]
				local oldValue = old[key]
				local newPath = table.clone(path)
				table.insert(newPath, key)
				if oldValue ~= nil and newValue ~= nil then
					self:_fireSignal(newPath, "Change", newValue, oldValue)
				elseif oldValue ~= nil and newValue == nil then
					self:_fireSignal(path, "RemoveKey", key, newValue, oldValue)
				elseif oldValue == nil and newValue ~= nil then
					self:_fireSignal(path, "NewKey", key, newValue, oldValue)
				end
			end
		end
	end)

	return self
end

type Signal<T> = Signal.Signal<T>
export type Signals = { [string]: Signal<any> }
export type Connection = Signal.Connection

export type Profile = typeof(setmetatable(
	{} :: {
		Replica: ReplicaClient.Replica,
		_player: Player,
		Listeners: {
			Change: Signals,
			NewKey: Signals,
			RemoveKey: Signals,
			ArrayInsert: Signals,
			ArrayRemove: Signals,
		},
	},
	Profile
))

return Profile

local DataStoreSharedFolder = script.Parent.Parent.DataStoreShared
local DataStoreServerFolder = script.Parent.Parent.DataStoreServer

local Sift = require(script.Parent.Parent.Parent.Sift)
local ReplicaServer = require(DataStoreServerFolder.ReplicaServer)
local ProfileStore = require(DataStoreServerFolder.ProfileStore)
local Signal = require(DataStoreSharedFolder.GoodSignal)

local Profile = {}
Profile.__index = Profile

export type Path = string | { string }
type Signal<T> = Signal.Signal<T>

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
	if typeof(path) == "string" then
		return self.Replica:Get(StringPathToArray(path))
	end

	return self.Replica:Get(path)
end

function Profile.SetValue(self: Profile, path: string | { any }, value: any): ()
	if typeof(path) == "string" then
		self.Replica:Set(StringPathToArray(path), value)
	else
		self.Replica:Set(path, value)
	end

	self:VisualizeData()
end

function Profile.SetValues(self: Profile, path: string | { any }, value: any): ()
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
		local leader = Instance.new("Folder")
		leader.Parent = self._player
		leader.Name = "leaderstats"
		self.leaderstats = leader
	end

	local NewValue = Instance.new(Type)
	NewValue.Parent = self.leaderstats
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

	self:SubscribeToChange(path, function(value)
		NewValue.Value = value
	end)
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
		visual = Instance.new("Folder")
		visual.Parent = self._player
		visual.Name = FolderName
	end

	local function processnum(Par, Nam, Val)
		local num = Par:FindFirstChild(Nam) or Instance.new("NumberValue")
		num.Parent = Par
		num.Name = Nam
		num.Value = Val
	end

	local function processstring(Par, Nam, Val)
		local str = Par:FindFirstChild(Nam) or Instance.new("StringValue")
		str.Parent = Par
		str.Name = Nam
		str.Value = Val
	end

	local function processbool(Par, Nam, Val)
		local bool = Par:FindFirstChild(Nam) or Instance.new("BoolValue")
		bool.Parent = Par
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
				local newpar = Parent:FindFirstChild(key) or Instance.new("Folder")
				newpar.Parent = Parent
				newpar.Name = key
				ProcessTable(Table[key], newpar)
			end
		end
	end

	ProcessTable(self.Profile.Data, visual)
end

function Profile.new(token: ReplicaServer.Token, profile: ProfileStore.Profile<any>, player: Player)
	local self = setmetatable({
		Profile = profile,
		Replica = ReplicaServer.New({
			Token = token,
			Tags = { Player = player },
			Data = profile.Data,
		}),
		_player = player,
		Listeners = {
			Change = {},
			NewKey = {},
			RemoveKey = {},
			ArrayInsert = {},
			ArrayRemove = {},
			Leaderstats = {},
		},
		OnSessionEnd = profile.OnSessionEnd,
		OnAfterSave = profile.OnAfterSave,
		OnLastSave = profile.OnLastSave,
		OnSave = profile.OnSave,
	}, Profile) :: Profile

	self.OnSessionEnd:Connect(function()
		for index, listeners in self.Listeners do
			for _, singal in listeners do
				singal:Destroy()
			end
		end
	end)

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
			local keys = Sift.Array.join(Sift.Dictionary.keys(new), Sift.Dictionary.keys(old))

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

	self.Profile:AddUserId(player.UserId)
	self.Profile:Reconcile()
	self.Replica:Replicate()
	self:VisualizeData()

	return self
end

export type Profile = typeof(setmetatable(
	{} :: {
		Profile: ProfileStore.Profile<any>,
		Replica: ReplicaServer.Replica,
		_player: Player,
		Listeners: {
			Change: Signals,
			NewKey: Signals,
			RemoveKey: Signals,
			ArrayInsert: Signals,
			ArrayRemove: Signals,
		},
		leaderstats: Folder?,
		OnSessionEnd: any,
		OnAfterSave: any,
		OnLastSave: any,
		OnSave: any,
	},
	Profile
))

export type Signals = { [string]: Signal<any>? }
export type Connection = Signal.Connection

return Profile

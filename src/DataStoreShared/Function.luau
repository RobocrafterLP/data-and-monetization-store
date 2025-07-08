--[[
MAD STUDIO

-[Remote]---------------------------------------
	Remote function setup utility; Prevents duplicate RemoteFunction names server-side

	Functions:
			
		Remote.New(name [string]) --> [RemoteFunction]
			-- Calling this with the same name server-side twice will throw an error
	
--]]

----- Private -----

local CONTAINER_NAME = "RemoteFunctions"
local REMOTE_MISSING_TIME = 20

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IsStudio = RunService:IsStudio()
local IsServer = RunService:IsServer()
local DefinedRemotes = {} -- [name] = true, ...

local Container, OnContainerReady
do
	if IsServer == true then
		Container = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)

		if Container ~= nil then
			if IsStudio == true then
				warn(`[{script.Name}]: ReplicatedStorage "{CONTAINER_NAME}" container was already defined`)
			end
		else
			Container = Instance.new("Folder")
			Container.Name = CONTAINER_NAME
			Container.Parent = ReplicatedStorage
		end
	else
		Container = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)

		if Container == nil then
			OnContainerReady = Instance.new("BindableEvent")

			task.spawn(function()
				while task.wait() do
					Container = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)
					if Container ~= nil then
						OnContainerReady:Fire()
						break
					end
				end
			end)
		end
	end
end

----- Public -----

local Connection = {}
Connection.__index = Connection

function Connection.New(fn)
	return setmetatable({
		fn = fn,
		is_disconnected = false,
	}, Connection)
end

function Connection:Disconnect()
	self.is_disconnected = true
end

local Remote = {}
Remote.__index = Remote

function Remote.New(name: string): RemoteFunction
	if type(name) ~= "string" then
		error(`[{script.Name}]: name must be a string`)
	end

	if IsServer == true then
		if DefinedRemotes[name] ~= nil then
			error(`[{script.Name}]: RemoteFunction {name} was already defined`)
		end

		DefinedRemotes[name] = true

		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = Container

		return remote
	else
		local remote: RemoteFunction = Container and Container:FindFirstChild(name)

		if remote ~= nil then
			return remote
		end

		local connections = {}

		local self = setmetatable({
			OnServerInvoke = {
				Connect = function()
					error(`[{script.Name}]: Can't connect to "OnServerInvoke" client-side`)
				end,
			},
			OnClientInvoke = {
				Connect = function(_, fn)
					if remote ~= nil then
						remote.OnClientInvoke = fn
						return Connection.New(fn)
					else
						local connection = Connection.New(fn)
						table.insert(connections, connection)
						return connection
					end
				end,
			},
			RemoteFunction = nil,
		}, Remote)

		local function on_container_ready()
			local missing_start = os.clock()

			while true do
				remote = Container:FindFirstChild(name)
				if remote == nil then
					if missing_start ~= nil and os.clock() - missing_start > REMOTE_MISSING_TIME then
						missing_start = nil
						warn(`[{script.Name}]: RemoteFunction "{name}" hasn't been defined server-side`)
					end
					task.wait()
				else
					break
				end
			end

			for _, connection in ipairs(connections) do
				if connection.is_disconnected == false then
					remote.OnClientInvoke = connection.fn
				end
			end

			self.RemoteFunction = remote
			connections = {}
		end

		if Container ~= nil then
			task.spawn(on_container_ready)
		else
			local wait_connection
			wait_connection = OnContainerReady.Event:Connect(function()
				wait_connection:Disconnect()
				on_container_ready()
			end)
		end

		return self
	end
end

function Remote:InvokeServer(...)
	if self.RemoteFunction ~= nil then
		return self.RemoteFunction:InvokeServer(...)
	end

    return nil
end

function Remote:InvokeClient()
	error(`[{script.Name}]: Can't use "InvokeClient" client-side`)
end

function Remote:SetCallback(fn)
	if self.RemoteFunction ~= nil then
		self.RemoteFunction.OnClientInvoke = fn
	end
end

return Remote

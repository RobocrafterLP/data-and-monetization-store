local Connection = {}
Connection.__index = Connection

local FreeRunnerThread

local function AcquireRunnerThreadAndCallEventHandler(fn, ...)
	local acquired_runner_thread = FreeRunnerThread
	FreeRunnerThread = nil
	fn(...)
	-- The handler finished running, this runner thread is free again.
	FreeRunnerThread = acquired_runner_thread
end

local function RunEventHandlerInFreeThread(...)
	AcquireRunnerThreadAndCallEventHandler(...)
	while true do
		AcquireRunnerThreadAndCallEventHandler(coroutine.yield())
	end
end

function Connection.new(t, fn)
	local self = setmetatable({
		t = t,
		fn = fn,
	}, Connection)

	t[self] = true

	return self
end

function Connection:Fire(...)
	if not FreeRunnerThread then
		FreeRunnerThread = coroutine.create(RunEventHandlerInFreeThread)
	end
	task.spawn(FreeRunnerThread, self.fn, ...)
end

function Connection:Disconnect()
	self.t[self] = nil
end

return Connection

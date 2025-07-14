if game:GetService("RunService"):IsClient() then
	return {}
end

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local GroupService = game:GetService("GroupService")

local DataStoreShared = script.Parent.DataStoreShared
local DataStoreServer = script.Parent.DataStoreServer

local Replica = require(DataStoreServer.ReplicaServer)
local ProfileStore = require(DataStoreServer.ProfileStore)
local Connection = require(DataStoreShared.Connection)
local Signal = require(DataStoreShared.GoodSignal)
local Remote = require(DataStoreShared.Remote)
local Function = require(DataStoreShared.Function)

local Monetization_GetMonetizationConfig = Function.New("Monetization_GetMonetizationConfig")
local Monetization_OnGroupRewardClaimAttempted = Remote.New("Monetization_OnGroupRewardClaimAttempted")
local Monetization_AttemptToClaimGroupReward = Function.New("Monetization_AttemptToClaimGroupReward")
local Monetization_SendPromptPurchase = Remote.New("Monetization_SendPromptPurchase")
local Monetization_DevProductPurchased = Remote.New("Monetization_DevProductPurchased")
local Monetization_GamepassPurchased = Remote.New("Monetization_GamepassPurchased")

local Profile = {}
Profile.__index = Profile

local MonetizationStoreServer = {
	_profiles = {} :: { [Player]: Profile },
	options = {},
	profileStore = {} :: ProfileStore.ProfileStore<any>,
	token = {} :: Replica.Token,
	_init = false,
	_productInfosLoaded = 0,
	_productInfosToLoad = 0,
	_productInfosLoadedSignal = Signal.new() :: Signal.Signal<nil>,
	OnDevProductPurchased = Signal.new() :: Signal.Signal<Player, ProductInfo, ReceiptInfo>,
	OnGamepassPurchased = Signal.new() :: Signal.Signal<Player, GamepassInfo>,
	OnProductPurchased = Signal.new() :: Signal.Signal<Player, ProductInfo, ReceiptInfo?>,
	OnGroupRewardClaimAttempted = Signal.new() :: Signal.Signal<Player, boolean>,
	Handlers = {
		Gamepasses = {} :: PurchaseHandlers,
		DevProducts = {} :: PurchaseHandlers,
	},
	ProductTypes = table.freeze({
		Gamepass = "Monetization:ProductTypes:Gamepass",
		DevProduct = "Monetization:ProductTypes:DevProduct",
		DeveloperProduct = "Monetization:ProductTypes:DevProduct",
	}),
}

function generateUUID()
	local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
	return string.gsub(template, "[xy]", function(c)
		local v = (c == "x") and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format("%x", v)
	end)
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
	local FolderName = "MonetizationData"

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

function MonetizationStoreServer.init(self: MonetizationStoreServer, options: DataOptions): ()
	local PlayerStore = ProfileStore.New(options.DataKey, options.template)
	self.options = options
	self.profileStore = options.useMock and PlayerStore.Mock or PlayerStore
	self.token = Replica.Token("MonetizationStore")

	for gamepassId, gamepassInfo in options.Gamepasses do
		gamepassInfo.ProductId = gamepassId
		gamepassInfo.GamepassId = gamepassId
		gamepassInfo.ProductType = self.ProductTypes.Gamepass

		self._productInfosToLoad += 1
	end

	for devProductId, devProductInfo in options.DevProducts do
		devProductInfo.ProductId = devProductId
		devProductInfo.DevProductId = devProductId
		devProductInfo.ProductType = self.ProductTypes.DevProduct

		self._productInfosToLoad += 1
	end

	for gamepassId, gamepassInfo in options.Gamepasses do
		task.spawn(function()
			gamepassInfo.ProductInfo = { Status = "Loading" }

			local productInfo
			repeat
				productInfo = MarketplaceService:GetProductInfo(gamepassId, Enum.InfoType.GamePass)
				task.wait()
			until productInfo
			gamepassInfo.ProductInfo = productInfo

			gamepassInfo.NormalPrice = gamepassInfo.NormalPrice or gamepassInfo.ProductInfo.PriceInRobux
			gamepassInfo.Description = gamepassInfo.Description
				or gamepassInfo.ProductInfo.DisplayDescription
				or gamepassInfo.ProductInfo.Description

			self._productInfosLoaded += 1
			if self._productInfosLoaded == self._productInfosToLoad then
				self._productInfosLoadedSignal:Fire()
			end
		end)
	end

	for devProductId, devProductInfo in options.DevProducts do
		task.spawn(function()
			devProductInfo.ProductInfo = { Status = "Loading" }

			local productInfo
			repeat
				productInfo = MarketplaceService:GetProductInfo(devProductId, Enum.InfoType.Product)
				task.wait()
			until productInfo
			devProductInfo.ProductInfo = productInfo

			devProductInfo.NormalPrice = devProductInfo.NormalPrice or devProductInfo.ProductInfo.PriceInRobux
			devProductInfo.Description = devProductInfo.Description
				or devProductInfo.ProductInfo.DisplayDescription
				or devProductInfo.ProductInfo.Description

			self._productInfosLoaded += 1
			if self._productInfosLoaded == self._productInfosToLoad then
				self._productInfosLoadedSignal:Fire()
			end
		end)
	end

	Monetization_GetMonetizationConfig.OnServerInvoke = function(player)
		self:WaitForAllProductInfosToBeLoaded()
		return self.options
	end

	Monetization_AttemptToClaimGroupReward.OnServerInvoke = function(player)
		return self:AttemptToClaimGroupReward(player)
	end

	Monetization_SendPromptPurchase.OnServerEvent:Connect(function(player: Player, product: product)
		self:PromptPurchase(player, product)
	end)

	MarketplaceService.ProcessReceipt = function(receiptInfo: ReceiptInfo)
		local success, result = pcall(function()
			local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
			if not player then
				return error(`Player with UserId "{receiptInfo.PlayerId}" not found`)
			end

			local productInfo = self:GetDevProductInfo(receiptInfo.ProductId)
			if not productInfo then
				return error(`Product info not found for ProductId "{receiptInfo.ProductId}"`)
			end

			local Profile = self:GetProfile(player)
			if not Profile then
				return error(`No Profile found for "{player}"`)
			end

			local handlerFunctions = self.Handlers.DevProducts[productInfo.DevProductId]
			if not handlerFunctions then
				print("Handlers:", self.Handlers)
				return error(`No handler functions bound for DevProductId "{productInfo.DevProductId}"`)
			end

			for _, handler in handlerFunctions do
				local result = handler(player, productInfo, receiptInfo)
				if
					result == Enum.ProductPurchaseDecision.NotProcessedYet
					or result == Enum.ProductPurchaseDecision.PurchaseGranted
				then
					return result
				end
			end

			local purchaseHistory = Profile:GetValue("PurchaseHistory")
			if not purchaseHistory then
				warn(`Unable to locate purchase history table in {player}'s monetization data`)
				-- Grant the purchase even though we weren't able to record it since the handlers have already been called.
				return Enum.ProductPurchaseDecision.PurchaseGranted
			end

			local now = DateTime.now()

			local purchaseStatement = {
				ProductId = receiptInfo.ProductId,
				StringId = productInfo.StringId,
				PurchaseTimestamp = now.UnixTimestamp,
				PurchaseTimestampMillis = now.UnixTimestampMillis,
				NormalPrice = productInfo.NormalPrice,
				PurchasePrice = productInfo.ProductInfo.PriceInRobux,
				TransactionUUID = generateUUID(),
				ProductType = self.ProductTypes.DevProduct,
				GrantedHistory = {
					{
						GrantedTimestamp = now.UnixTimestamp,
						GrantedTimestampMillis = now.UnixTimestampMillis,
					},
				},
			}

			Profile:SetValue(`PurchaseHistory.{now.UnixTimestampMillis}`, purchaseStatement)

			self.OnDevProductPurchased:Fire(player, productInfo, receiptInfo)
			self.OnProductPurchased:Fire(player, productInfo, receiptInfo)

			Monetization_DevProductPurchased:FireClient(player, productInfo, receiptInfo)

			return Enum.ProductPurchaseDecision.PurchaseGranted
		end)

		if not success or result ~= Enum.ProductPurchaseDecision.PurchaseGranted then
			warn(
				`[ProcessReceipt] Error or no return value — deferring receipt for retry: {receiptInfo.ProductId},`,
				result
			)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamepassId: number, wasPurchased: boolean)
			if not wasPurchased then
				return
			end

			local productInfo = self:GetGamepassInfo(gamepassId)
			if not productInfo then
				return
			end

			local Profile = self:GetProfile(player)
			if not Profile then
				return error(`No Profile found for "{player}"`)
			end

			Profile:SetValue(`OwnedGamepasses.{productInfo.GamepassId}`, true)

			local handlerFunctions = self.Handlers.Gamepasses[productInfo.GamepassId]
			if not handlerFunctions then
				print("Handlers:", self.Handlers)
				return error(`No handler functions bound for DevProductId "{productInfo.DevProductId}"`)
			end

			for _, handler in handlerFunctions do
				handler(player, productInfo)
			end

			local purchaseHistory = Profile:GetValue("PurchaseHistory")
			if not purchaseHistory then
				warn(`Unable to locate purchase history table in {player}'s monetization data`)
				return
			end

			local now = DateTime.now()

			local purchaseStatement = {
				ProductId = productInfo.GamepassId,
				StringId = productInfo.StringId,
				PurchaseTimestamp = now.UnixTimestamp,
				PurchaseTimestampMillis = now.UnixTimestampMillis,
				NormalPrice = productInfo.NormalPrice,
				PurchasePrice = productInfo.ProductInfo.PriceInRobux,
				TransactionUUID = generateUUID(),
				ProductType = self.ProductTypes.Gamepass,
				GrantedHistory = {
					{
						GrantedTimestamp = now.UnixTimestamp,
						GrantedTimestampMillis = now.UnixTimestampMillis,
					},
				},
			}

			Profile:SetValue(`PurchaseHistory.{now.UnixTimestampMillis}`, purchaseStatement)

			self.OnGamepassPurchased:Fire(player, productInfo)
			self.OnProductPurchased:Fire(player, productInfo)

			Monetization_GamepassPurchased:FireClient(player, productInfo)
		end
	)

	if self._productInfosLoaded ~= self._productInfosToLoad then
		self._productInfosLoadedSignal:Wait()
	end

	self._init = true

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
end

function MonetizationStoreServer._playerAdded(self: MonetizationStoreServer, player: Player): ()
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
			Replication = player,
			Listeners = {
				Change = {},
				NewKey = {},
				RemoveKey = {},
				ArrayInsert = {},
				ArrayRemove = {},
				Leaderstats = {},
			},
		}),
		_player = player,
	}, Profile)

	playerreplica:VisualizeData()
	playerreplica.Replica:Replicate()
	self._profiles[player] = playerreplica

	self:UpdatePlayerGroupStatus(player)
	self:UpdatePlayerOwnedGamepasses(player)
	self:OnPlayerAdded(player, playerreplica)
end

function MonetizationStoreServer._playerRemoving(self: MonetizationStoreServer, player: Player): ()
	local profile = self:GetProfile(player)

	if not profile then
		return
	end

	self:OnPlayerRemoving(player, profile)

	if profile:GetValue("WasEverInGroup") and not profile:GetValue("WasInGroupOnLastJoin") then
		profile:SetValue("WasInGroupOnLastJoin", true)
	end

	profile:EndSession()
	self._profiles[player] = nil
end

function MonetizationStoreServer.OnPlayerAdded(self: MonetizationStoreServer, _player: Player, _profile: Profile) end
function MonetizationStoreServer.OnPlayerRemoving(self: MonetizationStoreServer, _player: Player, _profile: Profile) end

function MonetizationStoreServer.SearchTableForProduct(
	self: MonetizationStoreServer,
	products,
	product: product
): DevProduct | Gamepass?
	if products[product] then
		return products[product]
	end

	for _, productInfo in products :: {} do
		if productInfo.Name == product or productInfo.StringId == product or productInfo.ProductId == product then
			return productInfo
		end
	end

	return nil
end

function MonetizationStoreServer.GetGamepassInfo(self: MonetizationStoreServer, product: product): Gamepass?
	return self:SearchTableForProduct(self.options.Gamepasses, product) :: Gamepass?
end

function MonetizationStoreServer.GetDevProductInfo(self: MonetizationStoreServer, product: product): DevProduct?
	return self:SearchTableForProduct(self.options.DevProducts, product) :: DevProduct?
end

function MonetizationStoreServer.GetProductInfo(self: MonetizationStoreServer, product: product): DevProduct | Gamepass?
	return self:GetDevProductInfo(product) or self:GetGamepassInfo(product)
end

function MonetizationStoreServer.BindGamepassPurchaseHandler(
	self: MonetizationStoreServer,
	product: product,
	purchaseHandler: PurchaseHandler,
	player: Player?
): string?
	local productInfo = self:GetGamepassInfo(product)
	if not productInfo then
		return warn(`Unable to find product info for gamepass {product}, and thus could not properly bind a handler.`)
	end

	local gamepassHandlers = self.Handlers.Gamepasses[productInfo.GamepassId] or {}
	self.Handlers.Gamepasses[productInfo.GamepassId] = gamepassHandlers

	for _, _ in gamepassHandlers do
		warn(
			`Binding another handler to GamepassId "{productInfo.GamepassId}" ({product}). It is not recommended to bind more than one handler server-sided per product.`
		)
		break
	end

	local uuid = generateUUID()

	if player then
		gamepassHandlers[uuid] = function(purchasedPlayer: Player, ...)
			if purchasedPlayer ~= player then
				return
			end
			purchaseHandler(purchasedPlayer, ...)
		end
	else
		gamepassHandlers[uuid] = purchaseHandler
	end

	return uuid
end

function MonetizationStoreServer.BindDevProductPurchaseHandler(
	self: MonetizationStoreServer,
	product: product,
	purchaseHandler: PurchaseHandler,
	player: Player?
): string?
	local productInfo = self:GetDevProductInfo(product)
	if not productInfo then
		return warn(
			`Unable to find product info for dev product {product}, and thus could not properly bind a handler.`
		)
	end

	local devProductHandlers = self.Handlers.DevProducts[productInfo.DevProductId] or {}
	self.Handlers.DevProducts[productInfo.DevProductId] = devProductHandlers

	for _, _ in devProductHandlers do
		warn(
			`Binding another handler to DevProductId "{productInfo.DevProductId}" ({product}). It is not recommended to bind more than one server-sided handler per product.`
		)
		break
	end

	local uuid = generateUUID()

	if player then
		devProductHandlers[uuid] = function(purchasedPlayer: Player, ...)
			if purchasedPlayer ~= player then
				return
			end
			purchaseHandler(purchasedPlayer, ...)
		end
	else
		devProductHandlers[uuid] = purchaseHandler
	end

	return uuid
end

function MonetizationStoreServer.PromptPurchase(self: MonetizationStoreServer, player: Player, productId: product): ()
	local productInfo = self:GetProductInfo(productId)
	if not productInfo then
		return
	end

	if productInfo.ProductType == self.ProductTypes.Gamepass then
		MarketplaceService:PromptGamePassPurchase(player, productInfo.ProductId)
	elseif productInfo.ProductType == self.ProductTypes.DevProduct then
		MarketplaceService:PromptProductPurchase(player, productInfo.ProductId)
	end
end

function MonetizationStoreServer.WaitForAllProductInfosToBeLoaded(self: MonetizationStoreServer): ()
	if self._productInfosLoaded == self._productInfosToLoad then
		return
	end
	self._productInfosLoadedSignal:Wait()
end

function MonetizationStoreServer.UpdatePlayerOwnedGamepasses(
	self: MonetizationStoreServer,
	player: Player
): { [number]: boolean }
	local ownedGamepasses = {}
	local Profile = self:GetProfile(player)

	for gamepassId, gamepassInfo in self.options.Gamepasses :: Gamepasses do
		if Profile:GetValue(`OwnedGamepasses.{gamepassInfo.GamepassId}`) then
			continue
		end

		local success, isOwned = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamepassInfo.GamepassId)
		end)

		if success ~= true then
			ownedGamepasses[gamepassInfo.GamepassId] = false
			isOwned = false
		else
			ownedGamepasses[gamepassInfo.GamepassId] = isOwned
		end

		Profile:SetValue(`OwnedGamepasses.{gamepassInfo.GamepassId}`, isOwned)
	end

	return ownedGamepasses
end

function MonetizationStoreServer.PlayerOwnsGamepass(
	self: MonetizationStoreServer,
	player: Player,
	productId: product
): boolean
	local productInfo = self:GetGamepassInfo(productId)
	if not productInfo then
		return false
	end
	local Profile = self:GetProfile(player)
	if not Profile then
		return false
	end

	return Profile:GetValue(`OwnedGamepasses.{productInfo.GamepassId}`)
end

function MonetizationStoreServer.IsIdAGroupId(self: MonetizationStoreServer, potentialGroupId: number)
	local success, _ = pcall(GroupService.GetGroupInfoAsync, GroupService, game.CreatorId)
	return success
end

function MonetizationStoreServer.IsPlayerInGroup(
	self: MonetizationStoreServer,
	player: Player | number,
	groupId: number?
): boolean
	if groupId == nil then
		if not self:IsIdAGroupId(game.CreatorId) then
			warn(`game.CreatorId ({game.CreatorId}) is not a valid GroupId`)
			return false
		end
		groupId = game.CreatorId
	end

	local groups
	if typeof(player) == "number" then
		groups = GroupService:GetGroupsAsync(player)
	elseif typeof(player) == "Instance" and player:IsA("Player") then
		groups = GroupService:GetGroupsAsync(player.UserId)
	else
		error(`Player must be a Player instance or number, but got {typeof(player)} instead.`)
	end

	for _, group in groups do
		if group.Id == groupId then
			return true
		end
	end

	return false
end

function MonetizationStoreServer.UpdatePlayerGroupStatus(self: MonetizationStoreServer, player: Player): ()
	local isInGroup = self:IsPlayerInGroup(player)
	local Profile = self:GetProfile(player)

	if Profile:GetValue("WasEverInGroup") == false then
		if isInGroup then
			Profile:SetValue("WasEverInGroup", true)
		end
	end

	if Profile:GetValue("IsCurrentlyInGroup") ~= isInGroup then
		Profile:SetValue("IsCurrentlyInGroup", isInGroup)
	end
end

function MonetizationStoreServer.AttemptToClaimGroupReward(
	self: MonetizationStoreServer,
	player: Player,
	callback: (claimSuccess: boolean) -> ()?,
	onlyCallbackOnClaimSuccess: boolean?
): boolean
	local Profile = self:GetProfile(player)
	if Profile:GetValue("HasClaimedGroupReward") or not self:IsPlayerInGroup(player) then
		if not onlyCallbackOnClaimSuccess and callback then
			callback(false)
		end
		self.OnGroupRewardClaimAttempted:Fire(player, false)
		Monetization_OnGroupRewardClaimAttempted:FireClient(player, false)
		return false
	end

	if callback then
		callback(true)
	end
	Profile:SetValue("GroupRewardClaimedAt", DateTime.now().UnixTimestampMillis)
	Profile:SetValue("HasClaimedGroupReward", true)
	self.OnGroupRewardClaimAttempted:Fire(player, true)
	Monetization_OnGroupRewardClaimAttempted:FireClient(player, true)
	return true
end

function MonetizationStoreServer._isinit(self: MonetizationStoreServer): ()
	assert(self._init, "Init first to use Datastore")
end

function MonetizationStoreServer.GetProfile(self: MonetizationStoreServer, player: Player): Profile?
	self:_isinit()
	return self._profiles[player] :: Profile?
end

function MonetizationStoreServer.HasProfile(self: MonetizationStoreServer, player: Player): boolean
	self:_isinit()
	return self._profiles[player] ~= nil
end

function MonetizationStoreServer.GetPlayerProfileAsync(self: MonetizationStoreServer, player: Player): Profile
	self:_isinit()
	local Profile = self:GetProfile(player)
	repeat
		task.wait()
		Profile = self:GetProfile(player)
	until Profile
	return Profile
end

export type PurchaseHandler = (
	player: Player,
	productInfo: GamepassInfo | ProductInfo,
	receiptInfo: ReceiptInfo?
) -> Enum.ProductPurchaseDecision?

export type PurchaseHandlers = { [product]: PurchaseHandlers }

export type MonetizationStoreServer = typeof(MonetizationStoreServer)

export type Connections = { [string | { string }]: typeof(Connection.new()) }

export type Connection = typeof(Connection.new())

export type Profile = typeof(Profile) & {
	Profile: ProfileStore.Profile<any>,
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

export type ProductInfo = {
	AssetId: number,
	AssetTypeId: number,
	Created: string,
	Creator: {
		CreatorTargetId: number,
		Id: number,
	},
	Description: string,
	DisplayDescription: string,
	DisplayIconImageAssetId: number,
	DisplayName: string,
	IconImageAssetId: number,
	IsForSale: boolean,
	IsLimited: boolean,
	IsLimitedUnique: boolean,
	IsNew: boolean,
	IsPublicDomain: boolean,
	MinimumMembershipLevel: number,
	Name: string,
	PriceInRobux: number,
	ProductId: number,
	ProductType: string,
	TargetId: number,
	UniverseId: number,
	Updated: string,
}

export type GamepassInfo = {
	AssetId: number,
	AssetTypeId: number,
	Created: string,
	Creator: {
		CreatorTargetId: number,
		CreatorType: string,
		Id: number,
		Name: string,
	},
	Description: string,
	IconImageAssetId: number,
	IsForSale: boolean,
	IsLimited: boolean,
	IsLimitedUnique: boolean,
	IsNew: boolean,
	IsPublicDomain: boolean,
	MinimumMembershipLevel: number,
	Name: string,
	PriceInRobux: number,
	ProductId: number,
	ProductType: string,
	Sales: number,
	TargetId: number,
	Updated: string,
}

export type ReceiptInfo = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
	PlaceIdWherePurchased: number,
	CurrencySpent: number,
	CurrencyType: Enum.CurrencyType,
	ProductPurchaseChannel: Enum.ProductPurchaseChannel,
}

export type product = number | string

export type Gamepass = {
	Name: string,
	StringId: string,
	Description: string?,
	NormalPrice: number?,
	ProductInfo: GamepassInfo?,
	GamepassId: number?,
	ProductId: number?,
}

export type Gamepasses = {
	[product]: Gamepass?,
}

export type DevProduct = {
	Name: string,
	StringId: string,
	Description: string?,
	NormalPrice: number?,
	ProductInfo: ProductInfo?,
	DevProductId: number?,
	ProductId: number?,
}

export type DevProducts = {
	[product]: DevProduct?,
}

export type DataOptions = {
	template: any,
	DataKey: string,
	useMock: boolean?,
	Gamepasses: Gamepasses,
	DevProducts: DevProducts,
}

return MonetizationStoreServer

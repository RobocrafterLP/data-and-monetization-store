local GroupService = game:GetService("GroupService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
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

local GAMEPASS_DATA_KEY = "__gamepasses"
local ROBUX_SPENT_DATA_KEY = "__robux_spent"
local ONE_TIME_PURCHASES_DATA_KEY = "__oneTimePurchases"
local PURCHASE_COOLDOWNS_KEY = "__purchaseCooldowns"
local PURSHASE_HISTORY_DATA_KEY = "__purchaseHistory"
local GIFT_RECEIVER_DATA_KEY = "__giftReceiver"
local GIFTING_TO_DATA_KEY = "__giftingTo"
local GIFT_GLOBAL_CALLBACK_KEY = "gift"
local RETRY_DELAY = 5
local MAX_RETRIES = 5
local DEFAULT_PROFILE_STORE_INDEX = "Default_MonetizationStore"
local storeCancel = Utils.storeCancel

local MonetizationStoreServer = {
	_profiles = {} :: any,
	_waitSignals = {} :: { [Player]: Signal.Signal<any> },
	_removalFunctions = {} :: { (player: Player, data: any) -> () },
	_loadingPlayers = {} :: { [Player]: boolean },
	_globalCallbacks = {} :: { [string]: (player: Player, { any }) -> boolean? },
	_globalCallbackAdded = Signal.new() :: Signal.Signal<string>,
	data = {} :: { [Player]: Value.Value<any> },
	costRequest = {} :: { [Player]: string },
	gamePassAwarded = Signal.new() :: Signal.Signal<Player, Utils.MonetizationProduct>,
	productProcessed = Signal.new() :: Signal.Signal<Player, Utils.MonetizationProduct, Utils.ReceiptInfo>,
}

local LOADING_PRODUCT_INFO = {
	Name = "Loading",
	Description = "Loading",
	PriceInRobux = 0,
	CostText = "Loading",
	Image = "Loading",
}

local UNKNOWN_PRODUCT_INFO = {
	Name = "Unknown",
	Description = "Unknown",
	PriceInRobux = -1,
	CostText = "Unknown",
	Image = "Unknown",
}

export type Profile<T> = ProfileServer.Profile<T>
export type MonetizationOptions<T> = Utils.MonetizationOptions<T>
export type MonetizationStoreServer<T> = typeof(MonetizationStoreServer) & {
	networker: Networker.Server,
	data: { [Player]: Value.Value<T> },
	costRequest: { [Player]: string },
	options: MonetizationOptions<T>,
	playerStore: any,
}
export type MessageData = {
	key: string,
	data: { any },
}

MonetizationStoreServer.RobuxSpentKey = ROBUX_SPENT_DATA_KEY

function GetProductInfo(product: Utils.MonetizationProduct, retryCount: number?): Utils.ProductInfo
	if not RunService:IsRunning() then
		return table.clone(UNKNOWN_PRODUCT_INFO)
	end

	local infoType = if product.isPass then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, result = pcall(MarketplaceService.GetProductInfoAsync, MarketplaceService, product.id, infoType)
	if not ok then
		if not retryCount or retryCount < MAX_RETRIES then
			task.wait(RETRY_DELAY)
			retryCount = (retryCount or 0) + 1
			warn("Failed to get product info for product", product.key, "retrying...", result, "attempt", retryCount)
			return GetProductInfo(product, retryCount)
		end
		warn("Failed to get product info for product", product.key, "giving up:", result)
		return table.clone(UNKNOWN_PRODUCT_INFO)
	end

	return result
end

function MonetizationStoreServer._configure<T>(self: MonetizationStoreServer<T>, options: MonetizationOptions<T>): MonetizationStoreServer<T>
	assert(RunService:IsServer(), "MonetizationStoreServer can only be used on the server.")
	assert(not self.options, "MonetizationStoreServer has already been configured.")
	Value.shouldRecordPath = true
	self.options = options

	return self
end

function MonetizationStoreServer.init<T>(self: MonetizationStoreServer<T>, options: MonetizationOptions<T>): ()
	assert(RunService:IsServer(), "MonetizationStoreServer can only be used on the server.")
	assert(self.options, "MonetizationStoreServer has not been configured.")
	assert(not self.playerStore, "MonetizationStoreServer has already been initialized.")

	local template = {
		[GAMEPASS_DATA_KEY] = {},
		[PURCHASE_COOLDOWNS_KEY] = {},
		[ONE_TIME_PURCHASES_DATA_KEY] = {},
		[PURSHASE_HISTORY_DATA_KEY] = {},
		[GIFT_RECEIVER_DATA_KEY] = nil,
		[ROBUX_SPENT_DATA_KEY] = 0,
	}

	self.networker = Networker.server.new("MonetizationStore", self, {
		self.PromptGift,
		self.requestData,
		self.requestCost,
	})
	self.playerStore = ProfileStore.New(self.options.dataKey or DEFAULT_PROFILE_STORE_INDEX, template)

	self:_initProducts(self.options.products)

	self:AddGlobalCallback(GIFT_GLOBAL_CALLBACK_KEY, function(player: Player, data: Utils.GiftData): boolean?
		return self:ReceiveGift(player, data)
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, gamepassId: number, wasPurchased: boolean)
			if
				not wasPurchased
				or self.options.canAwardGamepasses == false
				or self:OwnsGamepass(player, gamepassId)
			then
				return
			end

			local product = self:GetProductFromId(gamepassId)
			if not product then
				return
			end

			local Profile = self:GetPlayerProfileAsync(player)
			local PurchaseId = HttpService:GenerateGUID(false):gsub("-", "")
			local now = DateTime.now()
			if not Profile:GetValue(`{PURSHASE_HISTORY_DATA_KEY}.{PurchaseId}`) then
				Profile:SetValue(`{PURSHASE_HISTORY_DATA_KEY}.{PurchaseId}`, {
					PurchaseId = PurchaseId,
					ProductId = gamepassId,
					PurchaseTimestamp = now.UnixTimestamp,
					PurchaseTimestampMillis = now.UnixTimestampMillis,
					GrantedTimestamp = now.UnixTimestamp,
					GrantedTimestampMillis = now.UnixTimestampMillis,
					TransactionUUID = HttpService:GenerateGUID(false),
					Type = "Gamepass",
				})
				self:CurrencySpent(player, product)
			end

			self:AwardGamepass(player, gamepassId)
		end
	)

	MarketplaceService.ProcessReceipt = function(receiptInfo: Utils.ReceiptInfo)
		local result = self:_processDeveloperProduct(receiptInfo)
		local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if player then
			self:GetPlayerProfileAsync(player):SetValue(GIFTING_TO_DATA_KEY, nil)
		end
		return result
	end

	MarketplaceService.PromptProductPurchaseFinished:Connect(
		function(userId: number, _productId: number, _wasPurchased: boolean)
			local player = Players:GetPlayerByUserId(userId)
			if player then
				self:GetPlayerProfileAsync(player):SetValue(GIFTING_TO_DATA_KEY, nil)
			end
		end
	)

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

function MonetizationStoreServer.requestData<T>(self: MonetizationStoreServer<T>, player: Player): ()
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
--Monetization
function MonetizationStoreServer._playerAdded<T>(self: MonetizationStoreServer<T>, player: Player): ()
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
	end, "Monetization")
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

	Profile:SetValue(GIFT_RECEIVER_DATA_KEY, nil)

	if self.options.canAwardGamepasses == false then
		return
	end

	local qualifiesForFreePasses = self:hasGroupRole(player, self.options.freePassesGroupRank)
	for _, product in self.options.products do
		if product.disabled or not product.isPass then
			continue
		end

		local gamepassId = product.id
		local alreadyOwns = self:PlayerOwnsGamepass(player, gamepassId)
		if alreadyOwns then
			continue
		end

		local owns = qualifiesForFreePasses or self:PlayerOwnsGamepassAsync(player.UserId, gamepassId)
		if owns then
			self:AwardGamepass(player, gamepassId)
		end

		if owns and not qualifiesForFreePasses then
			self:CurrencySpent(player, product)
		end
	end
end

function MonetizationStoreServer._playerRemoving<T>(self: MonetizationStoreServer<T>, player: Player): ()
	local profile = self:GetProfile(player)
	if not profile then
		return
	end

	for _, fn in self._removalFunctions do
		local success, err: any? = pcall(fn, player, profile.Data)
		if not success then
			warn(err or "Error in removal function for " .. player.Name)
		end
	end

	profile:EndSession()
	self._profiles[player] = nil

	self:_resolveWaiters(player)

	self.data[player] = nil

	if self.options.dataReplica == "All" then
		self.networker:fireAll("destroy", player)
	else
		self.networker:fire(player, "destroy", player)
	end
end

function MonetizationStoreServer._initProduct<T>(
	_self: MonetizationStoreServer<T>,
	key: string,
	product: Utils.MonetizationProduct | Utils.MonetizationLoadedProduct
): ()
	product.key = key
	product._productInfo = table.clone(LOADING_PRODUCT_INFO)
	product._productInfo = GetProductInfo(product)
end

function MonetizationStoreServer._initProducts<T>(
	self: MonetizationStoreServer<T>,
	products: Utils.MonetizationProducts
): ()
	for key, product in products do
		product.key = key
		task.spawn(function()
			self:_initProduct(key, product)
		end)
	end
end

function MonetizationStoreServer.OnPlayerAdded<T>(
	_self: MonetizationStoreServer<T>,
	_player: Player,
	_profile: Profile<T>
)
end

function MonetizationStoreServer._initPlayer<T>(self: MonetizationStoreServer<T>, player: Player, profile: Profile<T>)
	self:OnPlayerAdded(player, profile.Data())
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

function MonetizationStoreServer._resolveWaiters<T>(self: MonetizationStoreServer<T>, player: Player): ()
	local waitSignal = self._waitSignals[player]
	if not waitSignal then
		return
	end

	self._waitSignals[player] = nil
	waitSignal:Fire()
	waitSignal:Destroy()
end

function MonetizationStoreServer.GetProfile<T>(self: MonetizationStoreServer<T>, player: Player): Profile<T>?
	return self._profiles[player] :: Profile<T>?
end

function MonetizationStoreServer.HasProfile<T>(self: MonetizationStoreServer<T>, player: Player): boolean
	return self._profiles[player] ~= nil
end

function MonetizationStoreServer.GetPlayerProfileAsync<T>(self: MonetizationStoreServer<T>, player: Player): Profile<T>
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
	return self:GetProfile(player) :: Profile<T>?
end

function MonetizationStoreServer.hasGroupRole(
	self: MonetizationStoreServer<any>,
	player: Player,
	checkRole: string
): boolean
	if not checkRole then
		return false
	end

	if self.options.groupId and self.options.groupId > 0 then
		local groupData = GroupService:GetGroupInfoAsync(self.options.groupId)
		local rolePower = 0

		for _, role in groupData.Roles do
			if checkRole == role.Name then
				rolePower = role.Rank
				break
			end
		end

		local result: Utils.RolesInGroupData = GroupService:GetRolesInGroupAsync(player.UserId, self.options.groupId)
		if not result.IsMember then
			return false
		end

		for _, role in result.Roles do
			if checkRole == role.Name or rolePower <= role.Rank then
				return true
			end
		end
	end

	return false
end

function MonetizationStoreServer.addPlayerRemovingCallback(
	self: MonetizationStoreServer<any>,
	fn: (player: Player, data: any) -> ()
): () -> ()
	table.insert(self._removalFunctions, fn)
	return function()
		local index = table.find(self._removalFunctions, fn)
		if index then
			table.remove(self._removalFunctions, index)
		end
	end
end

function MonetizationStoreServer._getProfileKey(self: MonetizationStoreServer<any>, userId: number | string): string
	return self:_getDataPrefix() .. tostring(userId)
end

function MonetizationStoreServer._getDataPrefix(self: MonetizationStoreServer<any>): string
	return self.options.dataPrefix or ""
end

--Monetization
function MonetizationStoreServer.GetProductFromId<T>(
	self: MonetizationStoreServer<T>,
	productId: number
): Utils.MonetizationProduct?
	for _, product in self.options.products do
		if product.id == productId or product.giftId == productId then
			return product
		end
	end
	return nil
end

function MonetizationStoreServer.GetPlayerRobuxSpent<T>(self: MonetizationStoreServer<T>, player: Player)
	local Profile = self:GetProfile(player)
	if not Profile then
		warn("No Profile for player", player)
		return 0
	end

	return Profile:GetValue(`{ROBUX_SPENT_DATA_KEY}`)
end

function MonetizationStoreServer.AwardGamepass<T>(self: MonetizationStoreServer<T>, player: Player, gamepassId: number): ()
	local product = self:GetProductFromId(gamepassId)
	if not product then
		warn("No product for gamepass id", gamepassId)
		return
	end

	assert(product.isPass, "Product is not a gamepass: " .. product.key)
	local Profile = self:GetProfile(player)
	if not Profile then
		warn("No Profile for player", player)
		return
	end

	self:GetPlayerGamepasses(player) -- ensure table exists
	Profile:SetValue(`{GAMEPASS_DATA_KEY}.{gamepassId}`, true)

	local callback = product.callback

	if callback then
		local success, result = pcall(callback, player)
		if not success then
			warn("Failed to process gamepass callback for product", product.key, result)
			return
		end
	end

	self.gamePassAwarded:Fire(player, product)
end

function MonetizationStoreServer.IsProductIdGift<T>(self: MonetizationStoreServer<T>, productId: number): boolean
	local product = self:GetProductFromId(productId)
	if not product then
		return false
	end
	return product.giftId == productId
end

function MonetizationStoreServer.GetPlayerGamepasses<T>(
	self: MonetizationStoreServer<T>,
	player: Player
): { [string]: boolean? }
	local Profile = self:GetProfile(player)
	if not Profile then
		warn("No Profile for player", player)
		return {}
	end

	local gamepasses: { [string]: boolean? } = Profile:GetValue(GAMEPASS_DATA_KEY)
	if not gamepasses then
		gamepasses = {}
		Profile:SetValue(GAMEPASS_DATA_KEY, gamepasses)
	end
	return gamepasses
end

function MonetizationStoreServer.ReceiveGift<T>(self: MonetizationStoreServer<T>, player: Player, data: Utils.GiftData): ()
	self.networker:fire(player, "_receivedGift", data)
	local product = self.options.products[data.productKey]
	assert(product, "No product for product key " .. data.productKey)

	if product.isPass then
		self:AwardGamepass(player, product.id)
		return true
	end

	local callback = product.callback
	if callback then
		local success, result = pcall(callback, player)
		if not success then
			warn("Failed to process gift callback for product", product.key, result)
			return nil
		end
		return result
	end

	return nil
end

function MonetizationStoreServer._attemptLocalGift<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	product: Utils.MonetizationProduct
): boolean
	local Profile = self:GetProfile(player)
	if not Profile then
		warn("No Profile for player", player)
	end

	local userId = Profile:GetValue(GIFTING_TO_DATA_KEY)
	if not userId or player.UserId == userId then
		return false
	end

	local receiver = Players:GetPlayerByUserId(userId)
	if not receiver or not self:HasProfile(receiver) then
		return false
	end

	self:ReceiveGift(receiver, {
		fromUserId = player.UserId,
		productKey = product.key,
		date = os.time(),
	})

	return true
end

function MonetizationStoreServer.PromptGift<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	userId: number,
	productId: number
): (boolean, string?)
	local Profile = self:GetProfile(player)
	local isGifting = Profile:GetValue(GIFTING_TO_DATA_KEY) ~= nil
	if isGifting then
		return false, "Already gifting to someone, please wait."
	end

	local product = self:GetProductFromId(productId)
	assert(product, "No product for product id " .. productId)
	if not product.giftId then
		return false, "Product has no gift"
	end

	local receiver = Players:GetPlayerByUserId(userId)
	if receiver and self:OwnsGamepass(receiver, product.id) then
		return false, "Receiver already owns gamepass"
	end

	Profile:SetValue(GIFTING_TO_DATA_KEY, userId)
	MarketplaceService:PromptProductPurchase(player, product.giftId)
	return true
end

function MonetizationStoreServer._attemptGift<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	product: Utils.MonetizationProduct
): boolean
	local giftReceiverUserId: number? = (self:GetProfile(player) :: any):GetValue(GIFTING_TO_DATA_KEY)
	assert(giftReceiverUserId, "No gift receiver for player")
	assert(player.UserId ~= giftReceiverUserId, "Cannot gift to yourself")

	local alreadyOwns = self:OwnsGamepassAsync(giftReceiverUserId, product.id)
	if alreadyOwns then
		return false
	end

	return self:SendGlobalMessage(GIFT_GLOBAL_CALLBACK_KEY, giftReceiverUserId, {
		fromUserId = player.UserId,
		productKey = product.key,
		date = os.time(),
	})
end

function MonetizationStoreServer._processDeveloperProduct<T>(
	self: MonetizationStoreServer<T>,
	receiptInfo: Utils.ReceiptInfo
): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local Profile = self:GetPlayerProfileAsync(player)
	if not Profile then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not Profile:IsActive() then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local local_purchase_ids = Profile:GetValue(PURSHASE_HISTORY_DATA_KEY)
	if local_purchase_ids == nil then
		local_purchase_ids = {}
		Profile:SetValue(PURSHASE_HISTORY_DATA_KEY, local_purchase_ids)
	end

	local id = receiptInfo.ProductId
	local product = self:GetProductFromId(id)
	if not product then
		warn("No product for productId", id)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local oneTimePurchase = product.oneTimePurchase
	if oneTimePurchase then
		local oneTimePurchases = Profile:GetValue(ONE_TIME_PURCHASES_DATA_KEY) :: { [string]: boolean }?
		if oneTimePurchases and oneTimePurchases[tostring(product.id)] then
			warn("Player has already purchased one-time product", product.id)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	local hasCooldown = product.purchaseCooldown and product.purchaseCooldown > 0
	if hasCooldown then
		local cooldowns = Profile:GetValue(PURCHASE_COOLDOWNS_KEY) :: { [string]: number }?
		if cooldowns and cooldowns[tostring(product.id)] then
			local purchaseTime = cooldowns[tostring(product.id)]
			local timeSincePurchase = os.time() - purchaseTime
			if timeSincePurchase < product.purchaseCooldown then
				warn("Player has already purchased time-limited product", product.id)
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
		end
	end

	if product.disabled then
		warn("Product is disabled", id)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local callback
	if self:IsProductIdGift(id) then
		callback = function()
			if not self:_attemptLocalGift(player, product) then
				return self:_attemptGift(player, product)
			end
			return true
		end
	else
		callback = product.callback
		if not callback then
			warn("No callback for developer product", product.key)
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	local success, result = pcall(callback, player)
	if not success then
		warn("Failed to process developer product", result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	--true or nil is fine
	if result == false then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if oneTimePurchase then
		if not Profile:GetValue(ONE_TIME_PURCHASES_DATA_KEY) then
			Profile:SetValue(ONE_TIME_PURCHASES_DATA_KEY, {})
		end
		Profile:SetValue(`{ONE_TIME_PURCHASES_DATA_KEY}.{product.id}`, true)
	end

	if hasCooldown then
		if not Profile:GetValue(PURCHASE_COOLDOWNS_KEY) then
			Profile:SetValue(PURCHASE_COOLDOWNS_KEY, {})
		end
		Profile:SetValue(`{PURCHASE_COOLDOWNS_KEY}.{product.id}`, os.time())
	end

	local now = DateTime.now()
	if not Profile:GetValue(`{PURSHASE_HISTORY_DATA_KEY}.{receiptInfo.PurchaseId}`) then
		Profile:SetValue(`{PURSHASE_HISTORY_DATA_KEY}.{receiptInfo.PurchaseId}`, {
			PurchaseId = receiptInfo.PurchaseId,
			ProductId = receiptInfo.ProductId,
			PurchaseTimestamp = now.UnixTimestamp,
			PurchaseTimestampMillis = now.UnixTimestampMillis,
			GrantedTimestamp = now.UnixTimestamp,
			GrantedTimestampMillis = now.UnixTimestampMillis,
			TransactionUUID = HttpService:GenerateGUID(false),
			Type = "Product",
		})
		self:CurrencySpent(player, product)
	end

	self.productProcessed:Fire(player, product, receiptInfo)

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function MonetizationStoreServer.CurrencySpent<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	product: Utils.MonetizationProduct
)
	if self.options.regionalPrice == true then
		local valid = HttpService:GenerateGUID(false)
		self.costRequest[player] = valid
		self.networker:fire(player, "requestCost", product.key, valid)
	else
		local Profile = self:GetPlayerProfileAsync(player)
		if Profile == nil then
			return
		end

		local currencySpent = product._productInfo and product._productInfo.PriceInRobux or 0
		if currencySpent <= 0 then
			return
		end

		Profile:AddValue(`{ROBUX_SPENT_DATA_KEY}`, currencySpent)
	end
end

function MonetizationStoreServer.requestCost<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	key: string,
	currencySpent: number
)
	if not self.costRequest[player] or self.costRequest[player] ~= key then
		return
	end

	local Profile = self:GetPlayerProfileAsync(player)
	if Profile == nil then
		return
	end

	self.costRequest[player] = nil
	Profile:AddValue(`{ROBUX_SPENT_DATA_KEY}`, currencySpent)
end

function MonetizationStoreServer.PlayerOwnsGamepassAsync<T>(
	_self: MonetizationStoreServer<T>,
	userId: number,
	gamepassIdOrProduct: number | Utils.MonetizationProduct
): boolean
	local id = if typeof(gamepassIdOrProduct) == "number"
		then gamepassIdOrProduct
		else (gamepassIdOrProduct :: Utils.MonetizationProduct).id
	local success, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, id)
	end)
	if not success then
		warn("Failed to check if user owns gamepass", result)
		return false
	end
	return result
end

function MonetizationStoreServer.PlayerOwnsOneTimePurchase<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	product: Utils.MonetizationProduct
): boolean
	if not product.oneTimePurchase then
		warn("Product is not a one-time purchase:", product.key)
		return false
	end

	local Profile = self:GetProfile(player)
	if not Profile then
		warn("No Profile for player", player)
		return false
	end

	local oneTimePurchases = Profile:GetValue(ONE_TIME_PURCHASES_DATA_KEY)
	return oneTimePurchases ~= nil and oneTimePurchases[tostring(product.id)]
end

function MonetizationStoreServer.PromptProduct<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	product: Utils.MonetizationProduct
): ()
	self.networker:fire(player, "PromptProduct", product)
end

function MonetizationStoreServer.GetPlayerGamepassOwnerShipChanged<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	product: Utils.MonetizationProduct
): Signal.Signal<boolean?>
	local Profile = self:GetPlayerProfileAsync(player)
	return Profile:SubscribeToChange(`{GAMEPASS_DATA_KEY}.{product.id}`)
end

function MonetizationStoreServer.PlayerOwnsGamepass<T>(
	self: MonetizationStoreServer<T>,
	player: Player,
	gamepassIdOrProduct: number | Utils.MonetizationProduct
): boolean
	local profile = self:GetProfile(player)
	if not profile then
		return false
	end

	local product = if typeof(gamepassIdOrProduct) == "number"
		then self:GetProductFromId(gamepassIdOrProduct)
		else gamepassIdOrProduct

	local gamepasses = profile:GetValue(GAMEPASS_DATA_KEY)
	return gamepasses ~= nil and gamepasses[tostring(product.id)]
end

function MonetizationStoreServer.SendGlobalMessage<T>(
	self: MonetizationStoreServer<T>,
	key: string,
	userId: number | string,
	data: { any }
): boolean
	local messageData: MessageData = { key = key, data = data }
	return self.profileStore:MessageAsync(`{userId}`, messageData)
end

function MonetizationStoreServer.AddGlobalCallback<T>(
	self: MonetizationStoreServer<T>,
	key: string,
	cb: (player: Player, { [any]: any }) -> boolean?
): ()
	assert(self._globalCallbacks[key] == nil, "Global callback already exists for key: " .. key)
	self._globalCallbacks[key] = cb
	self._globalCallbackAdded:Fire(key)
end

return MonetizationStoreServer

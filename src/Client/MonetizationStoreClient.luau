local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")

local ProfileClient = require(script.Parent.ProfileClient)
local Utils = require(script.Parent.Parent.Shared.Utils)
local Networker = require(script.Parent.Parent.Parent.Networker)
local Signal = require(script.Parent.Parent.Parent.Signal)
local Value = require(script.Parent.Parent.Shared.Value)

local LocalPlayer = Players.LocalPlayer

local MonetizationStoreClient = {
	_profiles = {} :: any,
	_waitSignals = {} :: { [Player]: Signal.Signal<any> },
	_playerPolicyInfo = {} :: { [Player]: Utils.PolicyInfo },
	data = {} :: { [Player]: Value.Value<any> },
	policyInfoChanged = Signal.new(),
	ProfileAdded = Signal.new() :: Signal.Signal<Profile<any>, Player>,
	ProfileRemoved = Signal.new() :: Signal.Signal<Profile<any>, Player>
}

export type Profile<T> = ProfileClient.Profile<T>
export type MonetizationStoreClient<T> = typeof(MonetizationStoreClient) & {
	networker: Networker.Server,
	data: { [Player]: Value.Value<any> },
	products: Utils.MonetizationProducts,
	playerStore: any,
}

local GAMEPASS_DATA_KEY = "__gamepasses"
local ROBUX_SPENT_DATA_KEY = "__robux_spent"
local ONE_TIME_PURCHASES_DATA_KEY = "__oneTimePurchases"
local PURCHASE_COOLDOWNS_KEY = "__purchaseCooldowns"
local PURSHASE_HISTORY_DATA_KEY = "__purchaseHistory"
local GIFT_RECEIVER_DATA_KEY = "__giftReceiver"
local RETRY_DELAY = 5
local MAX_RETRIES = 5

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

MonetizationStoreClient.RobuxSpentKey = ROBUX_SPENT_DATA_KEY

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

	result.Image = result.IconImageAssetId ~= 0 and `rbxassetId://{result.IconImageAssetId}` or ""
	return result
end

function MonetizationStoreClient.init<T>(self: MonetizationStoreClient<T>, products: Utils.MonetizationProducts)
	self.products = products
	self:_initProducts(products)

	if not RunService:IsRunning() then
		local template = {
			[GAMEPASS_DATA_KEY] = {},
			[PURCHASE_COOLDOWNS_KEY] = {},
			[ONE_TIME_PURCHASES_DATA_KEY] = {},
			[PURSHASE_HISTORY_DATA_KEY] = {},
			[GIFT_RECEIVER_DATA_KEY] = nil,
			[ROBUX_SPENT_DATA_KEY] = 0,
		}

		self:load(LocalPlayer, template)
		return self
	end

	self.networker = Networker.client.new("MonetizationStore", self)
	self.networker:fire("requestData")
	self:GetPlayerProfileAsync()
	return self
end

function MonetizationStoreClient.requestCost<T>(self: MonetizationStoreClient<T>, productKey: string, key: string)
	local info = self:GetProductInfo(productKey)
	if not info then
		return	
	end

	self.networker:fire("requestCost", key, info.PriceInRobux)
end

function MonetizationStoreClient.GetProfile<T>(self: MonetizationStoreClient<T>, player: Player?): Profile<T>?
	return self._profiles[player or LocalPlayer]
end

function MonetizationStoreClient.HasProfile<T>(self: MonetizationStoreClient<T>, player: Player?): boolean
	return self._profiles[player or LocalPlayer] ~= nil
end

function MonetizationStoreClient.GetPlayerProfileAsync<T>(self: MonetizationStoreClient<T>, player: Player?): Profile<T>
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

function MonetizationStoreClient.load<T>(self: MonetizationStoreClient<T>, player: Player, data: T)
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

function MonetizationStoreClient.get<T>(
	self: MonetizationStoreClient<T>,
	player: Player,
	path: { string }
): Value.Value<any>
	local profile = self:GetPlayerProfileAsync(player)

	local current = profile.Data
	for i = #path, 2, -1 do
		local key = path[i]
		current = (current :: any)[key]
	end

	return current[path[1]]
end

function MonetizationStoreClient.set<T>(self: MonetizationStoreClient<T>, player: Player, path: { string }, value: any?)
	self:get(player, path)(value)
end

function MonetizationStoreClient.insert<T>(
	self: MonetizationStoreClient<T>,
	player: Player,
	path: { string },
	item: any,
	pos: number?
)
	self:get(player, path).Insert(item, pos)
end

function MonetizationStoreClient.remove<T>(
	self: MonetizationStoreClient<T>,
	player: Player,
	path: { string },
	pos: number?
)
	self:get(player, path).Remove(pos)
end

function MonetizationStoreClient.destroy<T>(self: MonetizationStoreClient<T>, player: Player)
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

function MonetizationStoreClient._initProduct<T>(
	self: MonetizationStoreClient<T>,
	key: string,
	product: Utils.MonetizationProduct | Utils.MonetizationLoadedProduct
): ()
	product.key = key
	product._infoUpdated = Signal.new()
	product._productInfo = table.clone(LOADING_PRODUCT_INFO)
	product._productInfo = GetProductInfo(product)

	local function update()
		if
			(product.isPass and self:OwnsGamepass(product))
			or (product.oneTimePurchase and self:OwnsOneTimePurchase(product))
		then
			product._productInfo.CostText = "Owned"
		elseif product.purchaseCooldown and self:IsProductOnCooldown(product) then
			local timeRemaining = self:GetProductCooldownRemaining(product)
			product._productInfo.CostText = "Sec: " .. timeRemaining
		elseif product.disabled then
			product._productInfo.CostText = "Disabled"
		elseif product.random and self:GetPolicyInfoForPlayer().ArePaidRandomItemsRestricted then
			product._productInfo.CostText = "Locked"
		else
			product._productInfo.CostText = "\u{E002}" .. tostring(product._productInfo.PriceInRobux)
		end
		product._infoUpdated:Fire()
	end

	update()
	self.policyInfoChanged:Connect(update)

	local Profile = self:GetPlayerProfileAsync()
	if product.isPass then
		Profile:SubscribeToChange(`{GAMEPASS_DATA_KEY}.{product.id}`, update)
	end

	Profile:SubscribeToChange(ONE_TIME_PURCHASES_DATA_KEY, update)
	Profile:SubscribeToChange(PURCHASE_COOLDOWNS_KEY, update)

	if product.purchaseCooldown and product.purchaseCooldown > 0 then
		task.spawn(function()
			while true do
				update()
				task.wait(1)
			end
		end)
	end
end

function MonetizationStoreClient._initProducts<T>(
	self: MonetizationStoreClient<T>,
	products: Utils.MonetizationProducts
): ()
	for key, product in products do
		task.spawn(function()
			self:_initProduct(key, product)
		end)
	end
end

function MonetizationStoreClient._receivedGift<T>(self: MonetizationStoreClient<T>, giftData: Utils.GiftData): ()
	local product = self.products[giftData.productKey]
	self.giftReceived:Fire(product, giftData)
end

function MonetizationStoreClient.GetProductInfoChangedSignal<T>(
	_self: MonetizationStoreClient<T>,
	product: Utils.MonetizationLoadedProduct
): Signal.Signal<>
	return product._infoUpdated
end

function MonetizationStoreClient.GetProductInfo<T>(
	self: MonetizationStoreClient<T>,
	productOrId: Utils.MonetizationLoadedProduct | number
): Utils.ProductInfo
	local product: Utils.MonetizationLoadedProduct = if typeof(productOrId) == "number"
		then self:GetProductFromId(productOrId :: any)
		elseif typeof(productOrId) == "string" then self.products[productOrId]
		else productOrId
	if not product then
		return nil
	end

	return product._productInfo
end

function MonetizationStoreClient.GetProductCostString<T>(
	_self: MonetizationStoreClient<T>,
	product: Utils.MonetizationLoadedProduct
): string
	return product._productInfo.CostText
end

function MonetizationStoreClient.GetProductFromId<T>(
	self: MonetizationStoreClient<T>,
	productId: number
): Utils.MonetizationProduct
	for _, product in self.products do
		if product.id == productId or product.giftId == productId then
			return product
		end
	end
	error("No product for product id " .. productId)
end

function MonetizationStoreClient.GetRobuxSpent<T>(self: MonetizationStoreClient<T>)
	local Profile = self:GetPlayerProfileAsync()
	return Profile:GetValue(`{ROBUX_SPENT_DATA_KEY}`)
end

function MonetizationStoreClient.GetPlayerRobuxSpent<T>(self: MonetizationStoreClient<T>, player: Player)
	local Profile = self:GetPlayerProfileAsync(player)
	return Profile:GetValue(`{ROBUX_SPENT_DATA_KEY}`)
end

function MonetizationStoreClient.GetRobuxSpentChanged<T>(self: MonetizationStoreClient<T>, listener)
	local Profile = self:GetPlayerProfileAsync()
	return Profile:SubscribeToChange(`{ROBUX_SPENT_DATA_KEY}`, listener)
end

function MonetizationStoreClient.GetPlayerRobuxSpentChanged<T>(self: MonetizationStoreClient<T>, player: Player, listener)
	local Profile = self:GetPlayerProfileAsync(player)
	return Profile:SubscribeToChange(`{ROBUX_SPENT_DATA_KEY}`, listener)
end

function MonetizationStoreClient.GetGamepassOwnerShipChanged<T>(
	self: MonetizationStoreClient<T>,
	product: Utils.MonetizationProduct,
	listener
): Signal.Signal<boolean?>
	local Profile = self:GetPlayerProfileAsync()
	return Profile:SubscribeToChange(`{GAMEPASS_DATA_KEY}.{product.id}`, listener)
end

function MonetizationStoreClient.GetPlayerGamepassOwnerShipChanged<T>(
	self: MonetizationStoreClient<T>,
	player: Player,
	product: Utils.MonetizationProduct
): Signal.Signal<boolean?>
	local Profile = self:GetPlayerProfileAsync(player)
	return Profile:SubscribeToChange(`{GAMEPASS_DATA_KEY}.{product.id}`)
end

function MonetizationStoreClient.GetProductCooldownRemaining<T>(
	self: MonetizationStoreClient<T>,
	product: Utils.MonetizationProduct
): number
	if not product.purchaseCooldown then
		warn("Product does not have a cooldown:", product.key)
		return 0
	end

	local purchaseCooldowns = (self:GetProfile() :: any):GetValue(PURCHASE_COOLDOWNS_KEY)
	if not purchaseCooldowns then
		return 0
	end

	local purchaseTime = purchaseCooldowns[tostring(product.id)]
	if not purchaseTime then
		return 0
	end

	local timeSincePurchase = workspace:GetServerTimeNow() - purchaseTime
	local remaining = product.purchaseCooldown - timeSincePurchase
	return math.max(0, remaining)
end

function MonetizationStoreClient.OwnsOneTimePurchase<T>(
	self: MonetizationStoreClient<T>,
	product: Utils.MonetizationProduct
): boolean
	if not product.oneTimePurchase then
		warn("Product is not a one-time purchase:", product.key)
		return false
	end

	local Profile = self:GetPlayerProfileAsync()
	local oneTimePurchases = Profile:GetValue(ONE_TIME_PURCHASES_DATA_KEY)
	return oneTimePurchases ~= nil and oneTimePurchases[tostring(product.id)]
end

function MonetizationStoreClient.PlayerOwnsOneTimePurchase<T>(
	self: MonetizationStoreClient<T>,
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

function MonetizationStoreClient.IsProductOnCooldown<T>(
	self: MonetizationStoreClient<T>,
	product: Utils.MonetizationProduct
): boolean
	return self:GetProductCooldownRemaining(product) > 0
end

function MonetizationStoreClient.OwnsGamepass<T>(
	self: MonetizationStoreClient<T>,
	gamepassIdOrProduct: number | Utils.MonetizationProduct
): boolean
	local profile = self:GetProfile()
	if not profile then
		return false
	end

	local product = if typeof(gamepassIdOrProduct) == "number"
		then self:GetProductFromId(gamepassIdOrProduct)
		elseif typeof(gamepassIdOrProduct) == "string" then self.products[gamepassIdOrProduct]
		else gamepassIdOrProduct

	local gamepasses = self:GetPlayerProfileAsync():GetValue(GAMEPASS_DATA_KEY)
	return gamepasses ~= nil and gamepasses[tostring(product.id)]
end

function MonetizationStoreClient.PlayerOwnsGamepass<T>(
	self: MonetizationStoreClient<T>,
	player: Player,
	gamepassIdOrProduct: number | Utils.MonetizationProduct
): boolean
	local profile = self:GetProfile(player)
	if not profile then
		return false
	end

	local product = if typeof(gamepassIdOrProduct) == "number"
		then self:GetProductFromId(gamepassIdOrProduct)
		elseif typeof(gamepassIdOrProduct) == "string" then self.products[gamepassIdOrProduct]
		else gamepassIdOrProduct

	local gamepasses = profile:GetValue(GAMEPASS_DATA_KEY)
	return gamepasses ~= nil and gamepasses[tostring(product.id)]
end

function MonetizationStoreClient.PromptProduct<T>(self: MonetizationStoreClient<T>, product: Utils.MonetizationProduct): ()
	if product.disabled then
		warn("Product is disabled:", product.key)
		return
	end

	if product.random and self:GetPolicyInfoForPlayer().ArePaidRandomItemsRestricted then
		warn("Cannot purchase random items due to policy restrictions")
		return
	end

	if product.oneTimePurchase and self:OwnsOneTimePurchase(product) then
		warn("oneTimePurchase")
		return
	end

	if product.purchaseCooldown and self:IsProductOnCooldown(product) then
		warn("purchaseCooldown")
		return
	end

	if product.isPass then
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, product.id)
	else
		MarketplaceService:PromptProductPurchase(LocalPlayer, product.id)
	end
end

function MonetizationStoreClient.PromptGift<T>(
	self: MonetizationStoreClient<T>,
	userId: number,
	product: Utils.MonetizationProduct
): (boolean, string?)
	return self.networker:fetch("PromptGift", userId, product.giftId) :: any
end

function MonetizationStoreClient.GetPolicyInfoForPlayer<T>(
	self: MonetizationStoreClient<T>,
	player: Player?,
	update: boolean?
): Utils.PolicyInfo
	if not player then
		player = LocalPlayer
	end

	local success, result
	if not self._playerPolicyInfo[player] or update then
		success, result = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)

		if not success then
			task.wait(1)
			return self:GetPolicyInfoForPlayer(player, update)
		end

		result._lastUpdate = os.time()
		self._playerPolicyInfo[player] = result
	else
		result = self._playerPolicyInfo[player]
	end

	if result._lastUpdate + 60 * 5 < os.time() then
		local New = self:GetPolicyInfoForPlayer(player, true)

		if New then
			self.policyInfoChanged:Fire(New)
		end

		return New
	end

	return result
end

return MonetizationStoreClient

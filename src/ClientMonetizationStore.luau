if game:GetService("RunService"):IsServer() then
	return {}
end

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local DataStoreSharedFolder = script.Parent.DataStoreShared
local DataStoreClientFolder = script.Parent.DataStoreClient

local LocalPlayer = Players.LocalPlayer
local ProfileClient = require(DataStoreClientFolder.ProfileClient)
local Replica = require(DataStoreClientFolder.ReplicaClient)
local Signal = require(DataStoreSharedFolder.GoodSignal)
local Remote = require(DataStoreSharedFolder.Remote)
local Function = require(DataStoreSharedFolder.Function)
local MonetizationConfig: { [any]: any }

local Monetization_GetMonetizationConfig = Function.New("Monetization_GetMonetizationConfig")
local Monetization_OnGroupRewardClaimAttempted = Remote.New("Monetization_OnGroupRewardClaimAttempted")
local Monetization_AttemptToClaimGroupReward = Function.New("Monetization_AttemptToClaimGroupReward")
local Monetization_SendPromptPurchase = Remote.New("Monetization_SendPromptPurchase")
local Monetization_DevProductPurchased = Remote.New("Monetization_DevProductPurchased")
local Monetization_GamepassPurchased = Remote.New("Monetization_GamepassPurchased")

local MonetizationStoreClient = {
	Intialized = false,
	_profiles = {} :: { [Player]: Profile },
	OnDevProductPurchased = Signal.new() :: Signal.Signal<DevProduct, ReceiptInfo>,
	OnGamepassPurchased = Signal.new() :: Signal.Signal<Gamepass>,
	OnProductPurchased = Signal.new() :: Signal.Signal<any, ReceiptInfo?>,
	OnGroupRewardClaimAttempted = Signal.new() :: Signal.Signal<boolean>,
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

function CreateProfile(replica)
	local player: Player? = replica.Tags.Player
	if not player then
		return
	end

	local Profile = ProfileClient.new(replica, player)

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(Players) then
			MonetizationStoreClient._profiles[player] = nil
		end
	end)

	MonetizationStoreClient._profiles[player] = Profile
end

function MonetizationStoreClient.SearchTableForProduct(
	self: MonetizationStoreClient,
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

function MonetizationStoreClient.GetGamepassInfo(self: MonetizationStoreClient, product: product): Gamepass?
	return self:SearchTableForProduct(MonetizationConfig.Gamepasses, product) :: Gamepass?
end

function MonetizationStoreClient.GetDevProductInfo(self: MonetizationStoreClient, product: product): DevProduct?
	return self:SearchTableForProduct(MonetizationConfig.DevProducts, product) :: DevProduct?
end

function MonetizationStoreClient.GetProductInfo(self: MonetizationStoreClient, product: product): DevProduct | Gamepass?
	return self:GetDevProductInfo(product) or self:GetGamepassInfo(product)
end

function MonetizationStoreClient.PromptPurchase(self: MonetizationStoreClient, product: product)
	local productInfo = self:GetProductInfo(product)
	if not productInfo then
		return
	end

	if productInfo.ProductType == self.ProductTypes.Gamepass then
		MarketplaceService:PromptGamePassPurchase(LocalPlayer, productInfo.ProductId)
	elseif productInfo.ProductType == self.ProductTypes.DevProduct then
		MarketplaceService:PromptProductPurchase(LocalPlayer, productInfo.ProductId)
	end
end

function MonetizationStoreClient.SendPromptPurchaseSignal(self: MonetizationStoreClient, product: product)
	local productInfo = self:GetProductInfo(product)
	if not productInfo then
		return
	end

	Monetization_SendPromptPurchase:FireServer(productInfo.ProductId)
end

function MonetizationStoreClient.BindGamepassPurchaseHandler(
	self: MonetizationStoreClient,
	product: product,
	purchaseHandler: PurchaseHandler
): string?
	local productInfo = self:GetGamepassInfo(product)
	if not productInfo then
		return warn(`Unable to find product info for gamepass {product}, and thus could not properly bind a handler.`)
	end

	local gamepassHandlers = self.Handlers.Gamepasses[productInfo.GamepassId] or {}
	self.Handlers.Gamepasses[productInfo.GamepassId] = gamepassHandlers

	local uuid = generateUUID()
	gamepassHandlers[uuid] = purchaseHandler

	return uuid
end

function MonetizationStoreClient.BindDevProductPurchaseHandler(
	self: MonetizationStoreClient,
	product: product,
	purchaseHandler: PurchaseHandler
): string?
	local productInfo = self:GetDevProductInfo(product)
	if not productInfo then
		return warn(
			`Unable to find product info for dev product {product}, and thus could not properly bind a handler.`
		)
	end

	local devProductHandlers = self.Handlers.DevProducts[productInfo.DevProducts] or {}
	self.Handlers.DevProducts[productInfo.DevProducts] = devProductHandlers

	local uuid = generateUUID()
	devProductHandlers[uuid] = purchaseHandler

	return uuid
end

function MonetizationStoreClient.AttemptToClaimGroupReward(
	self: MonetizationStoreClient,
	callback: (claimSuccess: boolean) -> ()?,
	onlyCallbackOnClaimSuccess: boolean?
): boolean
	local claimSuccess = Monetization_AttemptToClaimGroupReward:InvokeServer()

	if callback and not onlyCallbackOnClaimSuccess then
		callback(claimSuccess)
		return claimSuccess
	elseif callback and onlyCallbackOnClaimSuccess then
		if claimSuccess then
			callback(true)
		end
		return claimSuccess
	end

	return claimSuccess
end

function MonetizationStoreClient.PlayerOwnsGamepass(self: MonetizationStoreClient, productId: product, player: Player?): boolean
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

function MonetizationStoreClient.HasProfile(self: MonetizationStoreClient, player: Player?): boolean
	return self._profiles[player or LocalPlayer] ~= nil
end

function MonetizationStoreClient.GetProfile(self: MonetizationStoreClient, player: Player?): Profile?
	return self._profiles[player or LocalPlayer]
end

function MonetizationStoreClient.GetPlayerProfileAsync(self: MonetizationStoreClient, player: Player?): Profile
	local Profile = self:GetProfile(player)
	repeat
		task.wait()
		Profile = self:GetProfile(player)
	until Profile
	return Profile
end

function MonetizationStoreClient.Intialize(self: MonetizationStoreClient)
	if self.Intialized then
		return
	end
	self.Intialized = true

	MonetizationConfig = Monetization_GetMonetizationConfig:InvokeServer()

	Monetization_DevProductPurchased.OnClientEvent:Connect(function(receiptInfo: ReceiptInfo, productInfo: DevProduct)
		local handlerFunctions = self.Handlers.DevProducts[productInfo.DevProductId] or {}
		if not handlerFunctions then
			print("Handlers:", self.Handlers)
			return error(`No handler functions bound for DevProductId "{productInfo.DevProductId}"`)
		end

		for _, handler in handlerFunctions do
			handler(receiptInfo, productInfo)
		end

		self.OnDevProductPurchased:Fire(productInfo, receiptInfo)
		self.OnProductPurchased:Fire(productInfo, receiptInfo)
	end)

	Monetization_OnGroupRewardClaimAttempted.OnClientEvent:Connect(function(success: boolean)
		self.OnGroupRewardClaimAttempted:Fire(success)
	end)

	Monetization_GamepassPurchased.OnClientEvent:Connect(function(productInfo: Gamepass)
		local handlerFunctions = self.Handlers.Gamepasses[productInfo.GamepassId] or {}
		if not handlerFunctions then
			print("Handlers:", self.Handlers)
			return error(`No handler functions bound for GamepassId "{productInfo.GamepassId}"`)
		end

		for _, handler in handlerFunctions do
			handler(productInfo)
		end

		self.OnGamepassPurchased:Fire(productInfo)
		self.OnProductPurchased:Fire(productInfo)
	end)
end

function MonetizationStoreClient.init(self: MonetizationStoreClient, DataOptions: DataOptions)
	self.DataOptions = DataOptions
	Replica.FromData(table.clone(DataOptions.template), "MonetizationStore", 1)
end

export type PurchaseHandler = (
	player: Player,
	productInfo: GamepassInfo | ProductInfo,
	receiptInfo: ReceiptInfo?
) -> Enum.ProductPurchaseDecision?

export type PurchaseHandlers = { [product]: PurchaseHandlers }

export type MonetizationStoreClient = typeof(MonetizationStoreClient)

export type Profile = ProfileClient.Profile

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

Replica.OnNew("MonetizationStore", CreateProfile)

Replica.RequestData()
MonetizationStoreClient:Intialize()
return MonetizationStoreClient

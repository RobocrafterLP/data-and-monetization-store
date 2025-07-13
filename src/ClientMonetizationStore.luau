if game:GetService("RunService"):IsServer() then
	return {}
end

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local DataStoreShared = script.Parent.DataStoreShared
local DataStoreClient = script.Parent.DataStoreClient

local LocalPlayer = Players.LocalPlayer
local Replica = require(DataStoreClient.ReplicaClient)
local Connection = require(DataStoreShared.Connection)
local Signal = require(DataStoreShared.GoodSignal)
local Remote = require(DataStoreShared.Remote)
local Function = require(DataStoreShared.Function)
local MonetizationConfig: { [any]: any }

local Monetization_GetMonetizationConfig = Function.New("Monetization_GetMonetizationConfig")
local Monetization_OnGroupRewardClaimAttempted = Remote.New("Monetization_OnGroupRewardClaimAttempted")
local Monetization_AttemptToClaimGroupReward = Function.New("Monetization_AttemptToClaimGroupReward")
local Monetization_SendPromptPurchase = Remote.New("Monetization_SendPromptPurchase")
local Monetization_DevProductPurchased = Remote.New("Monetization_DevProductPurchased")
local Monetization_GamepassPurchased = Remote.New("Monetization_GamepassPurchased")

local Profile = {}
Profile.__index = Profile

local MonetizationStore = {
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

function StringPathToArray(path)
	local path_array = {}
	if path ~= "" then
		for s in string.gmatch(path, "[^%.]+") do
			table.insert(path_array, s)
		end
	end
	return path_array
end

function CreateProfile(replica)
	local player: Player? = replica.Tags.Player
	if not player then
		return
	end

	local playerreplica = setmetatable({
		Replica = replica,
		_player = player,
		Connections = {},
		Listeners = {
			Change = {},
			NewKey = {},
			RemoveKey = {},
			ArrayInsert = {},
			ArrayRemove = {},
			Leaderstats = {},
		},
	}, Profile)

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(Players) then
			MonetizationStore._profiles[player] = nil
		end
	end)

	playerreplica.Replica:OnChange(function(action, path, new, old)
		local path_key = table.concat(path, ".")
		if action == "Set" and old ~= nil and new ~= nil then
			local listeners = playerreplica.Listeners.Change[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
				end
			end
		elseif action == "Set" and old and new == nil then
			local key = table.remove(path, #path)
			local path_key = table.concat(path, ".")
			local listeners = playerreplica.Listeners.RemoveKey[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(key, new, old)
				end
			end
		elseif action == "Set" and old == nil and new then
			local key = table.remove(path, #path)
			local path_key = table.concat(path, ".")
			local listeners = playerreplica.Listeners.NewKey[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(key, new, old)
				end
			end
		elseif action == "TableInsert" then
			local listeners = playerreplica.Listeners.ArrayInsert[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
				end
			end
		elseif action == "TableRemove" then
			local listeners = playerreplica.Listeners.ArrayRemove[path_key]
			if listeners ~= nil then
				for connection in pairs(listeners) do
					connection:Fire(new, old)
				end
			end
		end
	end)

	MonetizationStore._profiles[player] = playerreplica
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
	listener: (key: any, new: any, old: any) -> ()
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
	listener: (key: any, new: any, old: any) -> ()
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

function MonetizationStore.SearchTableForProduct(
	self: MonetizationStore,
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

function MonetizationStore.GetGamepassInfo(self: MonetizationStore, product: product): Gamepass?
	return self:SearchTableForProduct(MonetizationConfig.Gamepasses, product) :: Gamepass?
end

function MonetizationStore.GetDevProductInfo(self: MonetizationStore, product: product): DevProduct?
	return self:SearchTableForProduct(MonetizationConfig.DevProducts, product) :: DevProduct?
end

function MonetizationStore.GetProductInfo(self: MonetizationStore, product: product): DevProduct | Gamepass?
	return self:GetDevProductInfo(product) or self:GetGamepassInfo(product)
end

function MonetizationStore.PromptPurchase(self: MonetizationStore, product: product)
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

function MonetizationStore.SendPromptPurchaseSignal(self: MonetizationStore, product: product)
	local productInfo = self:GetProductInfo(product)
	if not productInfo then
		return
	end

	Monetization_SendPromptPurchase:FireServer(productInfo.ProductId)
end

function MonetizationStore.BindGamepassPurchaseHandler(
	self: MonetizationStore,
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

function MonetizationStore.BindDevProductPurchaseHandler(
	self: MonetizationStore,
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

function MonetizationStore.AttemptToClaimGroupReward(
	self: MonetizationStore,
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

function MonetizationStore.PlayerOwnsGamepass(self: MonetizationStore, productId: product, player: Player?): boolean
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

function MonetizationStore.HasProfile(self: MonetizationStore, player: Player?): boolean
	return self._profiles[player or LocalPlayer] ~= nil
end

function MonetizationStore.GetProfile(self: MonetizationStore, player: Player?): Profile?
	return self._profiles[player or LocalPlayer]
end

function MonetizationStore.GetPlayerProfileAsync(self: MonetizationStore, player: Player?): Profile
	local Profile = self:GetProfile(player)
	repeat
		task.wait()
		Profile = self:GetProfile(player)
	until Profile
	return Profile
end

function MonetizationStore.Intialize(self: MonetizationStore)
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

function MonetizationStore.init(self: MonetizationStore, DataOptions: DataOptions)
	self.DataOptions = DataOptions
	Replica.FromData(table.clone(DataOptions.template), DataOptions.DataKey, 1)
end

export type PurchaseHandler = (
	player: Player,
	productInfo: GamepassInfo | ProductInfo,
	receiptInfo: ReceiptInfo?
) -> Enum.ProductPurchaseDecision?

export type PurchaseHandlers = { [product]: PurchaseHandlers }

export type Connections = { [string | { string }]: typeof(Connection.new()) }

export type Connection = typeof(Connection.new())

export type MonetizationStore = typeof(MonetizationStore)

export type Profile = typeof(Profile) & {
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

Replica.OnNew("MonetizationStore", CreateProfile)

Replica.RequestData()
MonetizationStore:Intialize()
return MonetizationStore

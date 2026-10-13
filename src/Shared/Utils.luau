local Players = game:GetService("Players")
local Value = require(script.Parent.Value)
local Signal = require(script.Parent.Parent.Parent.Signal)

export type RoleData = {
	Id: number,
	Name: string,
	Rank: number,
}
export type RolesInGroupData = {
	IsMember: boolean,
	Roles: { RoleData },
}

export type Disconnect = () -> ()
export type Value<T> = Value.Value<T>
export type DataOptions<T> = {
	template: T,
	useMock: boolean?,
	viewedUserId: number?,
	overridenUserId: number?,
	dontSave: boolean?,
	resetData: boolean?,
	dataKey: string,
	dataPrefix: string?,
	dataReplica: "All" | "Player",
	leaderstats: {
		{
			path: string,
			name: string,
			class: string,
		}
	}?,
}

export type MonetizationOptions<T> = {
	products: MonetizationProducts,
	groupId: number?,
	freePassesGroupRank: string?,
	canAwardGamepasses: boolean?,
	dataKey: string,
	dataPrefix: string?,
	dataReplica: "All" | "Player",
	regionalPrice: boolean?
}

export type GiftData = {
	fromUserId: number,
	productKey: string,
	date: number,
}

export type MonetizationProducts = MonetizationProductsValue<{ [string]: MonetizationProduct }>
export type MonetizationProduct = {
	id: number,
	key: string?,
	giftId: number?,
	isPass: boolean?,
	oneTimePurchase: boolean?,
	purchaseCooldown: number?,
	random: boolean?,
	disabled: boolean?,
	callback: ((Player) -> ())?,
}

-- selene: allow(undefined_variable)
type function MonetizationProductsValue(T)
	if not T:is("table") then
		error("MonetizationProductsValue expects a table type")
	end

	local indexer = T:indexer()
	if not indexer then
		error("MonetizationProductsValue expects a dictionary type like { [string]: MonetizationProduct }")
	end

	local product = indexer.readresult

	if not product:is("table") then
		error("MonetizationProductsValue expects the dictionary values to be table types")
	end

	local newProduct = types.newtable()

	for key, prop in product:properties() do
		newProduct:setproperty(key, prop.read)
	end

	local products = types.newtable()
	products:setindexer(indexer.index, newProduct)

	return products
end

export type MonetizationLoadedProduct = MonetizationProduct & {
	_infoUpdated: Signal.Signal<>,
	_productInfo: {
		Name: string,
		Description: string,
		PriceInRobux: number,
		Image: string,
		CostText: string,
	},
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

export type PolicyInfo = {
	AreAdsAllowed: boolean,
	ArePaidRandomItemsRestricted: boolean,
	AllowedExternalLinkReferences: { string },
	IsContentSharingAllowed: boolean,
	IsEligibleToPurchaseCommerceProduct: boolean,
	IsEligibleToPurchaseSubscription: boolean,
	IsPaidItemTradingAllowed: boolean,
	IsPhotoToAvatarAllowed: boolean,
	IsSubjectToChinaPolicies: boolean,
}

export type ProductInfo = {
	Name: string,
	Description: string,
	PriceInRobux: number,
	CostText: string,
	Image: string,
}

local Utils = {}

local function StringPathToArray(path)
	local path_array = {}
	if path ~= "" then
		for s in string.gmatch(path, "[^%.]+") do
			table.insert(path_array, tonumber(s) or s)
		end
	end
	return path_array
end

function Utils.storeCancel(player: Player)
	return {
		Cancel = function()
			return player.Parent ~= Players
		end,
	}
end

function Utils.Get<T>(data, path: Path)
	if typeof(path) == "string" then
		path = StringPathToArray(path)
	end
	local pointer = data :: Value<T>

	if #path == 0 then
		return pointer
	end

	local e = pointer

	for i = 1, #path do
		pointer = pointer[path[i]]
	end

	return pointer
end

function Utils.DisconnectCallback(listeners: { Disconnect }, dc: Disconnect)
	return function()
		dc()
		local pos = table.find(listeners, dc)
		if not pos then
			return
		end

		table.remove(listeners, pos)
	end
end

return Utils

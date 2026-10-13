local RunService = game:GetService("RunService")

local DataStoreClient = require(script.Client.DataStoreClient)
local DataStoreServer = require(script.Server.DataStoreServer)

local MonetizationStoreClient = require(script.Client.MonetizationStoreClient)
local MonetizationStoreServer = require(script.Server.MonetizationStoreServer)

local ProfileServer = require(script.Server.ProfileServer)
local ProfileClient = require(script.Client.ProfileClient)

local Utils = require(script.Shared.Utils)

export type DataOptions<T> = Utils.DataOptions<T>
export type MonetizationOptions<T> = Utils.MonetizationOptions<T>
export type ProfileClient<T> = ProfileClient.Profile<T>
export type ProfileServer<T> = ProfileServer.Profile<T>
export type MonetizationProduct = Utils.MonetizationProduct

return {
	Data = function<T>(options: DataOptions<T>)
		return {
			client = (
					if RunService:IsClient() then DataStoreClient:init(options) else {}
				) :: DataStoreClient.DataStoreClient<T>,
			server = (
					if RunService:IsServer() then DataStoreServer:_configure(options) else {}
				) :: DataStoreServer.DataStoreServer<T>,
		}
	end,
	Monetization = function<T>(options: MonetizationOptions<T>)
		return {
			client = (
					if RunService:IsClient() then MonetizationStoreClient:init(options.products) else {}
				) :: MonetizationStoreClient.MonetizationStoreClient<T>,
			server = (
					if RunService:IsServer() then MonetizationStoreServer:_configure(options) else {}
				) :: MonetizationStoreServer.MonetizationStoreServer<T>,
		}
	end,
}

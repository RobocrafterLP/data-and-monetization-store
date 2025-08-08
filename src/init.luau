local ClientDataStore = require(script.ClientDataStore)
local ClientMonetizationStore = require(script.ClientMonetizationStore)
local ServerDataStore = require(script.ServerDataStore)
local ServerMonetizationStore = require(script.ServerMonetizationStore)

export type ServerDataStore = ServerDataStore.DataStoreServer
export type ClientDataStore = ClientDataStore.DataStoreClient

export type ServerMonetizationStore = ServerMonetizationStore.MonetizationStoreServer
export type ClientMonetizationStore = ClientMonetizationStore.MonetizationStoreClient

return {
    data = {
        server = ServerDataStore,
        client = ClientDataStore,
    },
    monetization = {
        server = ServerMonetizationStore,
        client = ClientMonetizationStore,
    }
} :: {
    data: {
        server: ServerDataStore,
        client: ClientDataStore,
    },
    monetization: {
        server: ServerMonetizationStore,
        client: ClientMonetizationStore,
    }
}

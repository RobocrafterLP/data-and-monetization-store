local ClientDataStore = require(script.ClientDataStore)
local ClientMonetizationStore = require(script.ClientMonetizationStore)
local ServerDataStore = require(script.ServerDataStore)
local ServerMonetizationStore = require(script.ServerMonetizationStore)

export type ServerDataStore = ServerDataStore.DataStore
export type ClientDataStore = ClientDataStore.DataStore

export type ServerMonetizationStore = ServerMonetizationStore.MonetizationStore
export type ClientMonetizationStore = ClientMonetizationStore.MonetizationStore

return {
    data = {
        server = ServerDataStore,
        client = ClientDataStore,
    },
    monetization = {
        server = ServerMonetizationStore,
        client = ClientMonetizationStore,
    }
}

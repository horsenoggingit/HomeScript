//
//  ScriptingViewModel.swift
//  HomeScript
//
//  Created by James Infusino on 9/21/25.
//


struct ScriptClient : Identifiable, Equatable {
    let id: String
    let isConnected: Bool
    
    init(id: String, isConnected: Bool) {
        self.id = id
        self.isConnected = isConnected
    }
}

@MainActor
class ScriptingViewModel : ObservableObject {
    @Published var clients: [ScriptClient] = []
    var shadowClients: [ScriptClient] = []
    
    init () {
        var cont : AsyncStream<Void>.Continuation?
        let stream = AsyncStream<Void> { continuation in
            cont = continuation
        }
        guard let cont else {
            fatalError("continuation is nil")
        }
        
        Task { [weak self] in
            for await _ in stream {
                let allClients = AccessoryTrackedGetterScripter.taskStore.keys.sorted()
                self?.clients = allClients.map { id in
                    ScriptClient(id: id, isConnected: AccessoryTrackedGetterScripter.isConnectedStore.contains(id))
                }
            }
        }
        AccessoryTrackedGetterScripter.addUpdateContinuation(cont)
    }
}

//
//  HSKHomeManager.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import Foundation
import HomeKit


enum HSKHomeManagerEventEnum : Equatable {
    case targetHomesUpdated([HMHome])
}

actor HSKHomeManager {
    let hm = HMHomeManager()
    let hmHomeDelegate : HSKHMHomeManagerDelegate
    let stream : AsyncStream<HSKHMHomeManagerDelegateEnum>
    let streamContinuation : AsyncStream<HSKHMHomeManagerDelegateEnum>.Continuation
    var targetHomeNames = Set<String>()
    var eventContinuations = [AsyncStream<HSKHomeManagerEventEnum>.Continuation]()
    
    init () {
        var cont : AsyncStream<HSKHMHomeManagerDelegateEnum>.Continuation?
        stream = AsyncStream<HSKHMHomeManagerDelegateEnum> { continuation in
            cont = continuation
        }
        guard let cont else {
            fatalError("unexpected")
        }
        self.streamContinuation = cont
        hmHomeDelegate = HSKHMHomeManagerDelegate(cont)
        hm.delegate = hmHomeDelegate
        print("\(hm.authorizationStatus)")
        Task { [weak self, stream] in
            print("start await")
            for await aResult in stream {
                switch aResult {
                    
                case .didUpdateHomes(let hm):
                    for home in hm.homes {
                        await self?.addHome(home)
                    }
                    break
                case .didAddHome(_, didAdd: let home):
                    await self?.addHome(home)
                case .didRemoveHome(_, didRemove: let home):
                    await self?.removeHome(home)
                    break
                case .didUpdatePrimaryHome(_):
                    break
                case .didUpdateAuthorizationStatus(_, didUpdate: _):
                    break
                case .didStartSearchingForHomes(_):
                    break
                }
            }
            print("finished")
        }
    }
    
    deinit {
        print("deinit HSKHomeManager")
        self.eventContinuations.forEach({ cont in
            cont.finish()
        })
        self.streamContinuation.finish()
    }
    
    func addHome(_ home: HMHome) {
        print("Adding Home: \(home.name)")

        if self.targetHomeNames.contains(home.name) {
            setTargetHome(home)
        }
    }
    
    func removeHome(_ home: HMHome) {
        print("Removing Home: \(home.name)")
        if targetHomeNames.contains(home.name) {
            setTargetHome(nil)
        }
    }
    
    func addNewTargetHomeName(_ name : String, cont: AsyncStream<HSKHomeManagerEventEnum>.Continuation) {
        self.targetHomeNames.insert(name)
        self.eventContinuations.append(cont)
        cont.yield(.targetHomesUpdated(self.hm.homes))
    }
    
    func setTargetHome(_ home: HMHome?) {
        print("New Target Home: \( home?.name ?? "undefined")")
        var indexes = [Int]()
        
        for (index, cont) in self.eventContinuations.enumerated() {
            switch cont.yield(.targetHomesUpdated(hm.homes)) {
            case .terminated:
                indexes.insert(index, at: 0)
            default:
                break
            }
        }
        
       for index in indexes {
            self.eventContinuations.remove(at: index)
        }
    }

}



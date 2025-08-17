//
//  HSKHMHomeManagerDelegate.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import HomeKit

enum HSKHMHomeManagerDelegateEnum {
    case didUpdateHomes(_ hmgr: HMHomeManager)
    case didAddHome(_ hmgr:HMHomeManager, didAdd: HMHome)
    case didRemoveHome(_ hmgr:HMHomeManager, didRemove: HMHome)
    case didUpdatePrimaryHome(_ hmgr:HMHomeManager)
    case didUpdateAuthorizationStatus(_ hmgr: HMHomeManager, didUpdate: HMHomeManagerAuthorizationStatus)
    case didStartSearchingForHomes(_ hmgr: HMHomeManager)
}

class HSKHMHomeManagerDelegate : NSObject, HMHomeManagerDelegate {
    let cont : AsyncStream<HSKHMHomeManagerDelegateEnum>.Continuation
    init(_ continuation: AsyncStream<HSKHMHomeManagerDelegateEnum>.Continuation) {
        cont = continuation
        super.init()
    }
    
    deinit {
       cont.finish()
    }
    
    func homeManagerDidUpdateHomes(_ hmgr: HMHomeManager) {
        cont.yield(.didUpdateHomes(hmgr))
    }
    
    func homeManagerDidStartSearchingForHomes(_ hmgr: HMHomeManager) {
        cont.yield(.didStartSearchingForHomes(hmgr))
    }
    
    func homeManager(_ hmgr: HMHomeManager, didAdd:  HMHome) {
        cont.yield(.didAddHome(hmgr, didAdd: didAdd))
    }
    
    func homeManager(_ hmgr: HMHomeManager, didRemove: HMHome) {
        cont.yield(.didRemoveHome(hmgr, didRemove: didRemove))
    }
    
    func homeManagerDidUpdatePrimaryHome(_ hmgr: HMHomeManager) {
        cont.yield(.didUpdatePrimaryHome(hmgr))
    }
    
    func homeManager(_ hmgr: HMHomeManager, didUpdate: HMHomeManagerAuthorizationStatus) {
        cont.yield(.didUpdateAuthorizationStatus(hmgr, didUpdate: didUpdate))
    }
}

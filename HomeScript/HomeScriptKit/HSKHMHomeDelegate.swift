//
//  HSKHMHomeDelegate.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//

import HomeKit

enum HSKHMHomeDelegateEnum {
    case homeDidUpdateName(_ hm: HMHome)
    case didAddAccessory(_ hm: HMHome, didAddAccessory: HMAccessory)
    case didUpdateRoom(_ hm: HMHome, didUpdateRoom: HMRoom, forAccessory: HMAccessory)
    case didRemoveAccessory(_ hm: HMHome, didRemoveAccessory: HMAccessory)
    case didAddRoom(_ hm: HMHome, didAddRoom: HMRoom)
    case didUpdateNameForRoom(_ hm: HMHome, didUpdateNameForRoom: HMRoom)
    case didAddRoomToZone(_ hm: HMHome, didAddRoom: HMRoom, toZone: HMZone)
    case didRemoveRoomFromZone(_ hm: HMHome, didRemoveRoom: HMRoom, fromZone: HMZone)
    case didRemoveRoom(_ hm: HMHome, didRemoveRoom: HMRoom)
    case didAddZone(_ hm: HMHome, didAddZone: HMZone)
    case didUpdateNameForZone(_ hm: HMHome, didUpdateNameForZone: HMZone)
    case didRemoveZone(_ hm: HMHome, didRemoveZone: HMZone)
    case didAddUser(_ hm: HMHome, didAddUser: HMUser)
    case didRemoveUser(_ hm: HMHome, didRemoveUser: HMUser)
    case homeDidUpdateAccessControl(forCurrentUser: HMHome)
    case didUpdateHomeHubState(_ hm: HMHome, didUpdateHomeHubState: HMHomeHubState)
    case homeDidUpdateSupportedFeatures(_ hm: HMHome)
    case didAddServiceGroup(_ hm: HMHome, didAddServiceGroup: HMServiceGroup)
    case didUpdateNameForServiceGroup(_ hm: HMHome, didUpdateNameForServiceGroup: HMServiceGroup)
    case didAddService(_ hm: HMHome, didAddService: HMService, toServiceGroup: HMServiceGroup)
    case didRemoveService(_ hm: HMHome, didRemoveService: HMService, fromServiceGroup: HMServiceGroup)
    case didRemoveServiceGroup(_ hm: HMHome, didRemoveServiceGroup: HMServiceGroup)
    case didAddActionSet(_ hm: HMHome, didAddActionSet: HMActionSet)
    case didUpdateNameForActionSet(_ hm: HMHome, didUpdateNameForActionSet: HMActionSet)
    case didUpdateActionsForActionSet(_ hm: HMHome, didUpdateActionsForActionSet: HMActionSet)
    case didRemoveActionSet(_ hm: HMHome, didRemoveActionSet: HMActionSet)
    case didAddTrigger(_ hm: HMHome, didAddTrigger: HMTrigger)
    case didUpdateNameForTrigger(_ hm: HMHome, didUpdateNameForTrigger: HMTrigger)
    case didUpdateTrigger(_ hm: HMHome, didUpdateTrigger: HMTrigger)
    case didRemoveTrigger(_ hm: HMHome, didRemoveTrigger: HMTrigger)
    case didEncounterError(_ hm: HMHome, didEncounterError: any Error, forAccessory: HMAccessory)
    case didUnblockAccessory(_ hm: HMHome, didUnblockAccessory: HMAccessory)
    
}

class HSKHMHomeDelegate : NSObject, HMHomeDelegate {
    let cont : AsyncStream<HSKHMHomeDelegateEnum>.Continuation
    init(_ continuation: AsyncStream<HSKHMHomeDelegateEnum>.Continuation) {
        cont = continuation
    }
    
    deinit {
       cont.finish()
    }
    
    func homeDidUpdateName(_ hm: HMHome) {
        cont.yield(.homeDidUpdateName(hm))
    }
    
    func home(_ hm: HMHome, didAdd: HMAccessory) {
        cont.yield(.didAddAccessory(hm, didAddAccessory: didAdd))
    }
    
    func home(_ hm: HMHome, didUpdate: HMRoom, for `accessory`: HMAccessory) {
        cont.yield(.didUpdateRoom(hm, didUpdateRoom: didUpdate, forAccessory: accessory))
    }
    
    func home(_ hm: HMHome, didRemove: HMAccessory) {
        cont.yield(.didRemoveAccessory(hm, didRemoveAccessory: didRemove))
    }
    
    func home(_ hm: HMHome, didAdd: HMRoom) {
        cont.yield(.didAddRoom(hm, didAddRoom: didAdd))
    }
    
    func home(_ hm: HMHome, didUpdateNameFor: HMRoom) {
        cont.yield(.didUpdateNameForRoom(hm, didUpdateNameForRoom: didUpdateNameFor))
    }
    
    func home(_ hm: HMHome, didAdd: HMRoom, to: HMZone) {
        cont.yield(.didAddRoomToZone(hm, didAddRoom: didAdd, toZone: to))
    }
    
    func home(_ hm: HMHome, didRemove: HMRoom, from: HMZone) {
        cont.yield(.didRemoveRoomFromZone(hm, didRemoveRoom: didRemove, fromZone: from))
    }
    
    func home(_ hm: HMHome, didRemove: HMRoom) {
        cont.yield(.didRemoveRoom(hm, didRemoveRoom: didRemove))
    }
    
    func home(_ hm: HMHome, didAdd: HMZone) {
        cont.yield(.didAddZone(hm, didAddZone: didAdd))
    }
    
    func home(_ hm: HMHome, didUpdateNameFor: HMZone) {
        cont.yield(.didUpdateNameForZone(hm, didUpdateNameForZone: didUpdateNameFor))
    }
    
    func home(_ hm: HMHome, didRemove: HMZone) {
        cont.yield(.didRemoveZone(hm, didRemoveZone: didRemove))
    }
    
    func home(_ hm: HMHome, didAdd: HMUser) {
        cont.yield(.didAddUser(hm, didAddUser: didAdd))
    }
    
    func home(_ hm: HMHome, didRemove: HMUser) {
        cont.yield(.didRemoveUser(hm, didRemoveUser: didRemove))
    }
    
    func homeDidUpdateAccessControl(forCurrentUser: HMHome) {
        cont.yield(.homeDidUpdateAccessControl(forCurrentUser: forCurrentUser))
    }
    
    func home(_ hm: HMHome, didUpdate: HMHomeHubState) {
        cont.yield(.didUpdateHomeHubState(hm, didUpdateHomeHubState: didUpdate))
    }
    
    func homeDidUpdateSupportedFeatures(_ hm: HMHome) {
        cont.yield(.homeDidUpdateSupportedFeatures(hm))
    }
    
    func home(_ hm: HMHome, didAdd: HMServiceGroup) {
        cont.yield(.didAddServiceGroup(hm, didAddServiceGroup: didAdd))
    }
    
    func home(_ hm: HMHome, didUpdateNameFor: HMServiceGroup) {
        cont.yield(.didUpdateNameForServiceGroup(hm, didUpdateNameForServiceGroup: didUpdateNameFor))
    }
    
    func home(_ hm: HMHome, didAdd: HMService, to: HMServiceGroup) {
        cont.yield(.didAddService(hm, didAddService: didAdd, toServiceGroup: to))
    }
    
    func home(_ hm: HMHome, didRemove: HMService, from: HMServiceGroup) {
        cont.yield(.didRemoveService(hm, didRemoveService: didRemove, fromServiceGroup: from))
    }
    
    func home(_ hm: HMHome, didRemove: HMServiceGroup) {
        cont.yield(.didRemoveServiceGroup(hm, didRemoveServiceGroup: didRemove))
    }
    
    func home(_ hm: HMHome, didAdd: HMActionSet) {
        cont.yield(.didAddActionSet(hm, didAddActionSet: didAdd))
    }
    
    func home(_ hm: HMHome, didUpdateNameFor: HMActionSet) {
        cont.yield(.didUpdateNameForActionSet(hm, didUpdateNameForActionSet: didUpdateNameFor))
    }
    
    func home(_ hm: HMHome, didUpdateActionsFor: HMActionSet) {
        cont.yield(.didUpdateActionsForActionSet(hm, didUpdateActionsForActionSet: didUpdateActionsFor))
    }
    
    func home(_ hm: HMHome, didRemove: HMActionSet) {
        cont.yield(.didRemoveActionSet(hm, didRemoveActionSet: didRemove))
    }
    
    func home(_ hm: HMHome, didAdd: HMTrigger) {
        cont.yield(.didAddTrigger(hm, didAddTrigger: didAdd))
    }
    
    func home(_ hm: HMHome, didUpdateNameFor: HMTrigger) {
        cont.yield(.didUpdateNameForTrigger(hm, didUpdateNameForTrigger: didUpdateNameFor))
    }
    
    func home(_ hm: HMHome, didUpdate: HMTrigger) {
        cont.yield(.didUpdateTrigger(hm, didUpdateTrigger: didUpdate))
    }
    
    func home(_ hm: HMHome, didRemove: HMTrigger) {
        cont.yield(.didRemoveTrigger(hm, didRemoveTrigger: didRemove))
    }
    
    func home(_ hm: HMHome, didEncounterError: any Error, for `accessory`: HMAccessory) {
        cont.yield(.didEncounterError(hm, didEncounterError: didEncounterError, forAccessory: accessory))
    }
    func home(_ hm: HMHome, didUnblockAccessory: HMAccessory) {
        cont.yield(.didUnblockAccessory(hm, didUnblockAccessory: didUnblockAccessory))
    }
    
}

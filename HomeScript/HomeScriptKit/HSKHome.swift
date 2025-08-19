//
//  HSKHome.swift
//  HomeScript
//
//  Created by James Infusino on 8/16/25.
//

import Foundation
import HomeKit
import os

enum HSKHomeEventEnum {
    case targetAccessoryUpdated(HMAccessory)
}

struct AccessoryNameAndRoom: Hashable {
    init(name: String, room: String?) {
        self.name = name
        self.room = room
    }
    init (accessory: HMAccessory) {
        self.name = accessory.name
        self.room = accessory.room?.name
    }
    let name: String
    let room: String?
}

actor HSKHome {
    let home: HMHome
    let homeDelegate : HSKHMHomeDelegate
    let stream : AsyncStream<HSKHMHomeDelegateEnum>
    let streamContinuation : AsyncStream<HSKHMHomeDelegateEnum>.Continuation
    var targetAccessoryNames = Set<AccessoryNameAndRoom>()
    var targetAccessories = Set<HMAccessory>()
    var eventContinuation : AsyncStream<HSKHomeEventEnum>.Continuation?
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HSKHome", category: "HSKHome")
    
    init(home: HMHome, eventContinuation: AsyncStream<HSKHomeEventEnum>.Continuation?) async {
        self.home = home
        self.eventContinuation = eventContinuation
        var cont : AsyncStream<HSKHMHomeDelegateEnum>.Continuation?
        stream = AsyncStream<HSKHMHomeDelegateEnum> { continuation in
            cont = continuation
        }
        guard let cont else {
            fatalError("unexpected")
        }
        self.streamContinuation = cont
        homeDelegate = HSKHMHomeDelegate(cont)
        home.delegate = homeDelegate
        Task { [weak self, stream] in
            for await aResult in stream {
                switch aResult {
                    
                case .homeDidUpdateName(_):
                    break
                case .didAddAccessory(_, didAddAccessory: let didAddAccessory):
                    await self?.addAccessory(didAddAccessory)
                case .didUpdateRoom(_, didUpdateRoom: _, forAccessory: _):
                    break
                case .didRemoveAccessory(_, didRemoveAccessory: let didRemoveAccessory):
                    await self?.removeAccessory(didRemoveAccessory)
                case .didAddRoom(_, didAddRoom: _):
                    break
                case .didUpdateNameForRoom(_, didUpdateNameForRoom: _):
                    break
                case .didAddRoomToZone(_, didAddRoom: _, toZone: _):
                    break
                case .didRemoveRoomFromZone(_, didRemoveRoom: _, fromZone: _):
                    break
                case .didRemoveRoom(_, didRemoveRoom: _):
                    break
                case .didAddZone(_, didAddZone: _):
                    break
                case .didUpdateNameForZone(_, didUpdateNameForZone: _):
                    break
                case .didRemoveZone(_, didRemoveZone: _):
                    break
                case .didAddUser(_, didAddUser: _):
                    break
                case .didRemoveUser(_, didRemoveUser: _):
                    break
                case .homeDidUpdateAccessControl(forCurrentUser: _):
                    break
                case .didUpdateHomeHubState(_, didUpdateHomeHubState: _):
                    break
                case .homeDidUpdateSupportedFeatures(_):
                    break
                case .didAddServiceGroup(_, didAddServiceGroup: _):
                    break
                case .didUpdateNameForServiceGroup(_, didUpdateNameForServiceGroup: _):
                    break
                case .didAddService(_, didAddService: _, toServiceGroup: _):
                    break
                case .didRemoveService(_, didRemoveService: _, fromServiceGroup: _):
                    break
                case .didRemoveServiceGroup(_, didRemoveServiceGroup: _):
                    break
                case .didAddActionSet(_, didAddActionSet: _):
                    break
                case .didUpdateNameForActionSet(_, didUpdateNameForActionSet: _):
                    break
                case .didUpdateActionsForActionSet(_, didUpdateActionsForActionSet: _):
                    break
                case .didRemoveActionSet(_, didRemoveActionSet: _):
                    break
                case .didAddTrigger(_, didAddTrigger: _):
                    break
                case .didUpdateNameForTrigger(_, didUpdateNameForTrigger: _):
                    break
                case .didUpdateTrigger(_, didUpdateTrigger: _):
                    break
                case .didRemoveTrigger(_, didRemoveTrigger: _):
                    break
                case .didEncounterError(_, didEncounterError: _, forAccessory: _):
                    break
                case .didUnblockAccessory(_, didUnblockAccessory: _):
                    break
                }
            }
        }
    }
    
    deinit {
        print("HSKHome deinitialized")
        self.eventContinuation?.finish()
        self.streamContinuation.finish()
    }
    
    func addAccessory(_ accessory: HMAccessory) {
        logger.info("Adding Accessory: \(accessory.name)")
        let newAccessoryNameAndRoom: AccessoryNameAndRoom = AccessoryNameAndRoom(name: accessory.name, room: accessory.room?.name)
        // already have this one
        guard (self.targetAccessories.contains { accessory in
            if AccessoryNameAndRoom(accessory: accessory).name == newAccessoryNameAndRoom.name {
                return true
            }
            return false
        }) == false else {
            return
        }
        if targetAccessoryNames.contains(AccessoryNameAndRoom(name: accessory.name, room: accessory.room?.name)) {
            self.addTargetAccessory(accessory)
        }
    }
    
    func removeAccessory(_ accessory: HMAccessory) {
        logger.info("Removing Accessory: \(accessory.name)")
        self.targetAccessories.remove(accessory)

    }
    
    func addTargetAccessory(_ accessory: HMAccessory) {
        self.targetAccessories.insert(accessory)
        logger.info("New Target Accessory: \(accessory.name)")
        self.eventContinuation?.yield(.targetAccessoryUpdated(accessory))
    }
    
    func addTargetAccessoryName(_ name: String, inRoom room: String) {
        let newAccessoryNameAndRoom: AccessoryNameAndRoom = AccessoryNameAndRoom(name: name, room: room)
        guard (self.targetAccessoryNames.contains { accessoryNameAndRoom in
            if accessoryNameAndRoom == newAccessoryNameAndRoom {
                return true
            }
            return false
        }) == false else {
            return
        }
        self.targetAccessoryNames.insert(newAccessoryNameAndRoom)
        logger.info("New Target Accessory Name: \(name)")
        for accessory in home.accessories {
            let accessoryNameAndRoom: AccessoryNameAndRoom = AccessoryNameAndRoom(name: accessory.name, room: accessory.room?.name)
            
            if accessoryNameAndRoom == newAccessoryNameAndRoom {
                self.addTargetAccessory(accessory)
                return
            }
        }
    }
}

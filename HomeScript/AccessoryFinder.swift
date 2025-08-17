//
//  AccessoryFinder.swift
//  HomeScript
//
//  Created by James Infusino on 8/16/25.
//

import Foundation
import HomeKit

struct AFAccessoryNameContainer : Hashable {
    init(name: String, home: String, room: String?) {
        self.name = name
        self.home = home
        self.room = room
    }
    
    let name : String
    let home : String
    let room : String?
}

@MainActor
class AccessoryFinder {
    static let shared = AccessoryFinder()
    
    let homeManager = HSKHomeManager()
    var trackedAccessories = [AFAccessoryNameContainer : HMAccessory]()
    var dataStore = [AFAccessoryNameContainer : [String: Any?]]()
    var lastWriteError : Error?
    var failedWriteValues = [AFAccessoryNameContainer : [String: Any?]]()

/*    init() {
        Task {
            await self.trackCharacteristicsInAccessoryNamed("Bobby", inRoomNamed: "Ginza", inHomeNamed: "Tokyo Palace")
        }
        Task {
            await self.trackCharacteristicsInAccessoryNamed("Reading", inRoomNamed: "Ginza", inHomeNamed: "Tokyo Palace")
        }
        Task {
            await self.trackCharacteristicsInAccessoryNamed("Main", inRoomNamed: "Kitchen", inHomeNamed: "AJ Home In Mammoth")

        }
        Task {
            self.setTrackedAccessryCharacteristic(value: 1, name: "Power State", accessoryName: "Reading", inRoomNamed: "Ginza", inHomeNamed: "Tokyo Palace")
        }
    }
*/

    func readStoredCharacteristicNamed(name : String, accessoryName: String, inRoomNamed: String, inHomeNamed: String) -> Any? {
        
        guard let innerOptiona = dataStore[AFAccessoryNameContainer(name: accessoryName, home: inHomeNamed, room: inRoomNamed)]?[name] else {
            return nil
        }
        return innerOptiona
    }
    
    func trackCharacteristicNamed(name : String, accessoryName: String, inRoomNamed: String, inHomeNamed: String) -> Any? {
        let value = dataStore[AFAccessoryNameContainer(name: accessoryName, home: inHomeNamed, room: inRoomNamed)]?[name]
        if value == nil {
            print("Characteristing not found. Starting tracking... (\(name) \(accessoryName) \(inRoomNamed) \(inHomeNamed))")
            Task {
                await trackCharacteristicsInAccessoryNamed(accessoryName, inRoomNamed: inRoomNamed, inHomeNamed: inHomeNamed)
            }
            return nil
        }
        return value as Any?
    }
    
    func setTrackedAccessryCharacteristic(value: Any?, name: String, accessoryName: String, inRoomNamed: String?, inHomeNamed: String) -> Bool {
        let keyName = AFAccessoryNameContainer(name: accessoryName, home: inHomeNamed, room: inRoomNamed)

        guard let accessory = trackedAccessories[keyName] else {
            if let kv = self.failedWriteValues[keyName] {
                self.failedWriteValues[keyName] = kv.merging([name: value]) { (_, new) in
                    new
                }
            } else {
                self.failedWriteValues[keyName] = [name: value]
            }
            
            return false
        }
        
        for service in accessory.services {
            let char = service.characteristics.first { char in
                if char.localizedDescription == name {
                    return true
                }
                return false
            }
            guard let char else {
                continue
            }
            char.writeValue(value) { err in
                if err != nil {
                    if let kv = self.failedWriteValues[keyName] {
                        self.failedWriteValues[keyName] = kv.merging([name: value]) { (_, new) in
                            new
                        }
                    } else {
                        self.failedWriteValues[keyName] = [name: value]
                    }
                    self.lastWriteError = err
                    return
                }
                self.lastWriteError = nil
                // need to write the updated value into the data source
                if let kv = self.dataStore[keyName] {
                    self.dataStore[keyName] = kv.merging([name: value]) { (_, new) in
                        new
                    }
                } else {
                    self.dataStore[keyName] = [name: value]
                }
                print("SET characteristic \(name) value \(String(describing:value)) for accessory \(accessoryName) in room \(String(describing: inRoomNamed)) in home \(inHomeNamed)")
            }
            return true
        }
        return false
    }

    private func getTargetHome(_ inHomeNamed: String) async -> HMHome? {
        var contuation : AsyncStream<HSKHomeManagerEventEnum>.Continuation?
        let stream = AsyncStream<HSKHomeManagerEventEnum> { cont in
            contuation = cont
        }
        guard let contuation else {
            fatalError("contuation nil")
        }
        await self.homeManager.addNewTargetHomeName(inHomeNamed, cont: contuation)
        
        print("Looking for home \(inHomeNamed)")
        var targetHome : HMHome?
        for await event in stream {
            switch event {
            case .targetHomesUpdated(let homes):
                targetHome = homes.first(where: { $0.name == inHomeNamed })
            }
            if targetHome != nil {
                print("Found home \(inHomeNamed)")
                break
            }
        }
        return targetHome
    }
    
    private func getTargetAccessorNamed(_ name: String, inRoomNamed: String, inHome: HMHome) async -> HMAccessory? {
        var homeContuation : AsyncStream<HSKHomeEventEnum>.Continuation?
        let homeStream = AsyncStream<HSKHomeEventEnum> { cont in
            homeContuation = cont
        }
        guard let homeContuation else {
            fatalError("contuation nil")
        }
        print("Looking for accessory \(name) in room \(inRoomNamed) in home \(inHome.name)")

        var targetAccessory : HMAccessory?
        let home = await HSKHome(home: inHome, eventContinuation: homeContuation)
        await home.addTargetAccessoryName(name, inRoom: inRoomNamed)
        for await event in homeStream {
            switch event {
            case .targetAccessoryUpdated(let hkaccessory):
                print("Found for accessory \(name) in room \(inRoomNamed) in home \(inHome.name)")
                targetAccessory = hkaccessory
            }
            if targetAccessory != nil {
                break
            }
        }
        return targetAccessory
    }
    
    func trackCharacteristicsInAccessoryNamed(_ name: String, inRoomNamed: String, inHomeNamed: String) async {
        let keyName = AFAccessoryNameContainer(name: name, home: inHomeNamed, room: inRoomNamed)
        print("Starting track of \(keyName)")
        
        guard trackedAccessories[keyName] == nil else {
            print("Accessory already tracked of \(keyName)")
            return
        }
        
        guard let targetHome = await getTargetHome(inHomeNamed) else {
            return
        }
        
        guard let targetAccessory = await getTargetAccessorNamed(name, inRoomNamed: inRoomNamed, inHome: targetHome) else {
            return
        }
        
        if let tracked = trackedAccessories[keyName], tracked == targetAccessory {
            print("Already tracking accessory \(name) in room \(inRoomNamed) in home \(inHomeNamed)")
            return
        }
        
        var accessoryContuation : AsyncStream<HSKAccessoryEventEnum>.Continuation?
        let accessoryStream = AsyncStream<HSKAccessoryEventEnum> { cont in
            accessoryContuation = cont
        }
        guard let accessoryContuation else {
            fatalError("contuation nil")
        }
        
        let accessory = await HSKAccessory(accessory: targetAccessory, eventContinuation: accessoryContuation)
        
        trackedAccessories[keyName] = targetAccessory
        print("Tracking tracking accessory \(name) in room \(inRoomNamed) in home \(inHomeNamed)")

        if let v = failedWriteValues[keyName] {
            failedWriteValues.removeValue(forKey: keyName)
            for (characteristic, value) in v {
                _ = self.setTrackedAccessryCharacteristic(value: value, name: characteristic, accessoryName: keyName.name, inRoomNamed: keyName.room, inHomeNamed: keyName.home)
            }
           
        }
        
        for await event in accessoryStream {
            switch event {
            case .characteristicValueUpdated(let characteristic, let value):
                print("Received characteristic \(characteristic.localizedDescription) value \(String(describing:value)) for accessory \(name) in room \(inRoomNamed) in home \(inHomeNamed)")
                if let stored = self.dataStore[keyName] {
                    self.dataStore[keyName] = stored.merging([characteristic.localizedDescription : value], uniquingKeysWith: { _, new in
                        new
                    })
                } else {
                    self.dataStore[keyName] = [characteristic.localizedDescription : value]
                }
                
            }
        }
        print("Accessory tracking complete for \(name) in room \(inRoomNamed) in home \(inHomeNamed)")
    }
    
}

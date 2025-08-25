//
//  AccessoryFinder.swift
//  HomeScript
//
//  Created by James Infusino on 8/16/25.
//

import Foundation
import HomeKit
import os

// these are what the user would know
// the is the minimum object to track
// the system will automatically track all Services and Characteristics
struct AFAccessoryNameContainer : Hashable, CustomStringConvertible {
    
    init(name: String, home: String, room: String) {
        self.name = name
        self.home = home
        self.room = room
    }
    
    init(_ array: [String]) throws {
        
        if array.count < 3 {
            throw NSError(domain: "InvalidFormatError", code: 1, userInfo: nil)
        }
        
        self.name = array[0]
        self.room = array[1]
        self.home = array[2]
    }
    
    let name : String
    let home : String
    let room : String
    
    var description: String {
        "accessory:'\(self.name)' room:'\(self.room)' home:'\(self.home)'"
    }
    
    func array() -> [String] {
        return [self.name, self.room, self.home]
    }
}

@MainActor
class AccessoryFinder {
    static let shared = AccessoryFinder()
    
    let homeManager = HSKHomeManager()
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AccessoryFinder")

    var trackedHomes = [String: HSKHome]()
    
    // fast aaccess to the tracked accessories
    var trackedAccessories = [AFAccessoryNameContainer : HMAccessory]()
    // Keep track of the relationships between objects
    // Key(Home:Room:Accessory) : [Service : [ Characteristic : Last read value] ] ]
    var dataStore = [AFAccessoryNameContainer : [String : [String: Any?]]]()
    
    var dataStoreContinuations = [AsyncStream<[AFAccessoryNameContainer : [String : [String : Any? ]]]>.Continuation]()
    
    // write error history
    var writeErrors = [Error]()

    func clearWriteErrors() {
        self.writeErrors.removeAll()
    }
    
    func serviceToServiceName(_ service: HMService) -> String {
        service.localizedDescription + " " + service.uniqueIdentifier.uuidString.suffix(5)
    }
    
    // update an entry in the datastore
    func updateDataStore(key: AFAccessoryNameContainer, serviceName: String, characteristicName : String, value: Any?) {
        if var stored = self.dataStore[key] {
            if var inner = stored[serviceName] {
                inner[characteristicName] = value
                stored[serviceName] = inner
            } else {
                stored[serviceName] = [characteristicName : value]
            }
            self.dataStore[key] = stored
        } else {
            self.dataStore[key] = [serviceName : [characteristicName: value]]
        }
        
        // distribute the update
        var indexes = [Int]()
        
        for (index, cont) in self.dataStoreContinuations.enumerated() {
            switch cont.yield([key: [serviceName : [characteristicName: value]]]) {
            case .terminated:
                indexes.insert(index, at: 0)
            default:
                break
            }
        }
        
        for index in indexes.reversed() {
            self.dataStoreContinuations.remove(at: index)
       }
    }
    
    // read the latest value of a stored characteristic from the datastore
    func readStoredCharacteristicNamed(name : String, serviceName: String, accessory: AFAccessoryNameContainer) -> Any? {
        
        guard let innerOptiona = dataStore[accessory]?[serviceName]?[name] else {
            return nil
        }
        return innerOptiona
    }
    
    // read the services in a stored accessory from the datastore
    func readStoredServicesForAccessory(_ accessory: AFAccessoryNameContainer, startingWith: String? = nil, characterissticStartingWith: String? = nil, value: Any? = nil) -> [String]? {
        let servicesValues = dataStore[accessory]
        guard let servicesValues else {
            // means there is no information available
            return nil
        }
        return servicesValues.keys.filter({ serviceKey in
            guard let startingWith else {
                return true
            }
            return serviceKey.starts(with: startingWith)
        })
        .filter({ serviceKey in
            guard let characterissticStartingWith else {
                return true
            }
            
            guard let cv = dataStore[accessory]?[serviceKey] else {
                return false
            }
            for (k, v) in cv {
                if value == nil {
                    if k.starts(with: characterissticStartingWith) {
                        return true
                    }
                } else {
                    if k.starts(with: characterissticStartingWith) {
                        if let vv = v as? String, vv == value as? String {
                            return true
                        }
                        if let vv = v as? Int, vv == value as? Int {
                            return true
                        }
                        if let vv = v as? Bool, vv == value as? Bool {
                            return true
                        }
                    }
                }
                
            }
            return false
        })
        
        
        .sorted()
    }
    
    // read the all the values for all the characteristics of a service of a stored accessory
    // sorted in alpha order of the characteristics
    func readStoredValuesForCharacteristicsForService(_ serviceName: String, accesory: AFAccessoryNameContainer) -> [Any?]? {
        let characteristicsValues = dataStore[accesory]?[serviceName]
        guard let characteristicsValues else {
            // means there is no information available
            return nil
        }
        
        let sortedKeys = characteristicsValues.keys.sorted()
        
        let sortedValues = sortedKeys.reduce(into: [Any?]()) { partialResult, nextKey in
            partialResult.append(characteristicsValues[nextKey] as Any?)
        }
        return sortedValues
    }
 
    // read the all the haracteristics of a service of a stored accessory in alpha order
    func readStoredCharacteristicsForService(_ serviceName: String, accessory: AFAccessoryNameContainer) -> [String]? {
        let characteristicsValues = dataStore[accessory]?[serviceName]
        guard let characteristicsValues else {
            // means there is no information available
            return nil
        }
        return characteristicsValues.keys.sorted()
    }
    
    // a list of all the tracked accessories, their rooms and homes
    func readTrackedAccessories() -> [[String]] {
        let x = dataStore.keys.map { keyContainer in
            [keyContainer.name, keyContainer.room, keyContainer.home]
        }
        return x
    }
    
    // set the value of a characteristic
    // a write failure will append an error to the write error array
    // if the write is successful the local datastore is updated
    func setTrackedAccessryCharacteristic(value: Any?, characteristicName: String, serviceName: String, accessory keyName: AFAccessoryNameContainer) -> Bool {

        guard let accessory = trackedAccessories[keyName] else {
            return false
        }
        
        let service = accessory.services.first { service in
            self.serviceToServiceName(service) == serviceName
        }
        
        guard let service else {
            logger.error("No service named \(serviceName) in accessory \(keyName.description)")
            return false
        }
        
        let char = service.characteristics.first { char in
            char.localizedDescription == characteristicName
        }

        guard let char else {
            logger.error("No characteristic named \(characteristicName) in service named \(serviceName) in accessory \(keyName.description)")
            return false
        }

        char.writeValue(value) { err in
            if let err {
                self.logger.error("Failed to write value \(String(describing:value)) to characteristic \(characteristicName) for accessory \(keyName.description): \(err.localizedDescription)")
                let myError = NSError(domain: "AccessoryFinder", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to write value \(String(describing:value)) to characteristic \(characteristicName) for accessory \(keyName.description): \(err.localizedDescription)",
                    NSUnderlyingErrorKey: err])
                
                self.writeErrors.append(myError)
                return
            }

            // need to write the updated value into the data source
            self.updateDataStore(key: keyName, serviceName: self.serviceToServiceName(service), characteristicName: characteristicName, value: value)

            self.logger.info("SET characteristic \(characteristicName) value \(String(describing:value)) in service \(self.serviceToServiceName(service)) in accessory \(keyName.description)")
        }
        return true
    }

    // find a home - dynamically updates
    private func getTargetHome(_ inHomeNamed: String) async -> HMHome? {
        var contuation : AsyncStream<HSKHomeManagerEventEnum>.Continuation?
        let stream = AsyncStream<HSKHomeManagerEventEnum> { cont in
            contuation = cont
        }
        guard let contuation else {
            fatalError("contuation nil")
        }
        await self.homeManager.addNewTargetHomeName(inHomeNamed, cont: contuation)
        
        logger.info("Looking for home \(inHomeNamed)")
        var targetHome : HMHome?
        for await event in stream {
            switch event {
            case .targetHomesUpdated(let homes):
                targetHome = homes.first(where: { $0.name == inHomeNamed })
            }
            if targetHome != nil {
                logger.info("Found home \(inHomeNamed)")
                break
            }
        }
        
        return targetHome
    }
    
    
    private func getTargetAccessorNamed(_ accessoryName: String, inRoomNamed: String, inHome: HSKHome) async throws -> HMAccessory? {
        var homeContuation : AsyncStream<HSKHomeEventEnum>.Continuation?
        let homeStream = AsyncStream<HSKHomeEventEnum> { cont in
            homeContuation = cont
        }
        guard let homeContuation else {
            fatalError("contuation nil")
        }
        
        if let storedHome = self.trackedHomes[inHome.home.name] {
            if storedHome.home.uniqueIdentifier != inHome.home.uniqueIdentifier {
                logger.error("Different IDs for homes with name \(inHome.home.name)")
                throw NSError(domain: "AccessoryFinder", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Different IDs for homes with name \(inHome.home.name)"])
            }
        } else {
            self.trackedHomes[inHome.home.name] = inHome
        }
        
        await inHome.addTargetAccessoryName(accessoryName, inRoom: inRoomNamed, cont: homeContuation)
        var targetAccessory : HMAccessory?

        for await event in homeStream {
            switch event {
            case .targetAccessoryUpdated(let hkaccessory):
                if hkaccessory.name == accessoryName {
                    logger.info("Found accessory \(accessoryName) in room \(inRoomNamed) in home \(inHome.home.name)")
                    targetAccessory = hkaccessory
                }
            }
            if targetAccessory != nil {
                break
            }
        }

        return targetAccessory
    }
    
    // dymaically track accessory value changes and update the datastore
    func trackAccessoryNamed(_ accessoryName: String, inRoomNamed: String, inHomeNamed: String, resultWrittenCallback: ((AFAccessoryNameContainer?) -> Void)? = nil, statusCallback: ((String) -> Void)? = nil) async throws -> AFAccessoryNameContainer? {
        var resultWritten = false
        let keyName = AFAccessoryNameContainer(name: accessoryName, home: inHomeNamed, room: inRoomNamed)
        logger.info("Starting track of \(keyName)")
        statusCallback?("Starting track of \(keyName)")
        guard trackedAccessories[keyName] == nil else {
            logger.info("Accessory already tracked of \(keyName)")
            resultWrittenCallback?(keyName)
            statusCallback?("Tracking already started for \(keyName)")
            return keyName
        }
        
        let targetHome: HSKHome
    
        statusCallback?("Looking for home: \(inHomeNamed)")
        if let storedHome = trackedHomes[inHomeNamed] {
            logger.info("Reusing home \(inHomeNamed)")
            targetHome = storedHome
        } else {
            guard let newHome = await getTargetHome(inHomeNamed) else {
                logger.info("Get getTargetHome loop aborted")
                return nil
            }
            
            logger.info("Tracking new home \(inHomeNamed)")
            
            targetHome = await HSKHome(home: newHome)
        }
       
        statusCallback?("Looking for accessory \(accessoryName) in room \(inRoomNamed)")
        guard let targetAccessory = try await getTargetAccessorNamed(accessoryName, inRoomNamed: inRoomNamed, inHome: targetHome) else {
            logger.info("Get getTargetAccessorNamed loop aborted")
            return nil
        }
        
        if let tracked = trackedAccessories[keyName], tracked == targetAccessory {
            logger.info("Already tracking accessory \(accessoryName) in room \(inRoomNamed) in home \(inHomeNamed)")
            resultWrittenCallback?(keyName)
            return keyName
        }
        
        var accessoryContuation : AsyncStream<HSKAccessoryEventEnum>.Continuation?
        let accessoryStream = AsyncStream<HSKAccessoryEventEnum> { cont in
            accessoryContuation = cont
        }
        guard let accessoryContuation else {
            fatalError("contuation nil")
        }
        
        let accessory = await HSKAccessory(accessory: targetAccessory, eventContinuation: accessoryContuation)
        
        var accessoryServices = accessory.accessory.services
        
        trackedAccessories[keyName] = targetAccessory
        logger.info("Tracking accessory \(keyName.description)")
        statusCallback?("Tracking accessory \(keyName.description)")
        for await event in accessoryStream {
            switch event {
            case .characteristicValueUpdated(let service, let characteristic, let value):
                
                let serviceName = self.serviceToServiceName(service)
                
                logger.info("Received characteristic \(characteristic.localizedDescription) value \(String(describing:value)) in service \(serviceName) of accessory \(keyName.description)")
                
                self.updateDataStore(key: keyName, serviceName: serviceName, characteristicName: characteristic.localizedDescription, value: value)
                
                accessoryServices.removeAll { ss in
                    ss == service
                }
                // call the calback to inform that all the expected values have been writted
                if accessoryServices.isEmpty, !resultWritten, let resultWrittenCallback {
                    resultWrittenCallback(keyName)
                    resultWritten = true
                }
            }
        }
        logger.info("Accessory tracking complete for \(keyName.description)")
        statusCallback?("Accessory tracking complete for \(keyName.description)")
        // tracking is complete. The datasotre will no longer update
        self.trackedAccessories.removeValue(forKey: keyName)
        // retunring nill becasue the accessory is no longer tracked
        return nil
    }
    
    
}

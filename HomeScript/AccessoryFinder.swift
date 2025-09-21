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
struct AFAccessoryNameContainer : Hashable, CustomStringConvertible, Comparable {
    static func < (lhs: AFAccessoryNameContainer, rhs: AFAccessoryNameContainer) -> Bool {
        if lhs.home != rhs.home {
            return lhs.home < rhs.home
        }
        if lhs.room != rhs.room {
            return lhs.room < rhs.room
        }
        return lhs.name < rhs.name
    }
    
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

    nonisolated
    static let characteristicValueDateSuffix = ".dateUpdated"

    private let homeManager = HSKHomeManager()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AccessoryFinder")

    private var trackedHomes = [String: HSKHome]()
    
    // fast aaccess to the tracked accessories
    private var trackedAccessories = [AFAccessoryNameContainer : HMAccessory]()
    
    // Keep track of the relationships between objects
    // Key(Home:Room:Accessory) : [Service : [ Characteristic : Last read value] ] ]
    private var dataStore = [AFAccessoryNameContainer : [String : [String: Any?]]]()
    
    private var dataStoreContinuations = [AsyncStream<[AFAccessoryNameContainer : [String : [String : Any? ]]]>.Continuation]()
    
    // the process of tracking an accessory take time, this dict helps to avoid
    // running into issues when when multiple trakcing requests are made while tracking
    // is in progress
    private var accessoriesTrackingInProgress : [AFAccessoryNameContainer: [(resultWrittenCallback: ((AFAccessoryNameContainer?) -> Void)?, continuation: CheckedContinuation<AFAccessoryNameContainer?, Error>)]] = [:]
    
    func addDataStoreContinuation(_ continuation: AsyncStream<[AFAccessoryNameContainer : [String : [String : Any? ]]]>.Continuation) {
        self.dataStoreContinuations.append(continuation)
    }
    
    // write error history
    private var writeErrors = [Error]()

    func clearWriteErrors() {
        self.writeErrors.removeAll()
    }
    
    func serviceToServiceName(_ service: HMService) -> String {
        service.localizedDescription + " " + service.uniqueIdentifier.uuidString.suffix(5)
    }
    
    // update an entry in the datastore
    func updateDataStore(key: AFAccessoryNameContainer, serviceName: String, characteristicName : String, value: Any?) {
        // keep track of the time the event occured. This way we can tell when every characteristic was updated
        let valueDict = [characteristicName: value, characteristicName + AccessoryFinder.characteristicValueDateSuffix: Date()]
        
        // add or merge the vaule dictionary into the data store
        if var stored = self.dataStore[key] {
            if var inner = stored[serviceName] {
                inner.merge(valueDict) { _, newValue in
                    newValue
                }
                inner[characteristicName] = value
                stored[serviceName] = inner
            } else {
                stored[serviceName] = valueDict
            }
            self.dataStore[key] = stored
        } else {
            self.dataStore[key] = [serviceName : valueDict]
        }
        
        // distribute the update to individual async stream, removing any stream that has ended.
        var indexes = [Int]()
        
        for (index, cont) in self.dataStoreContinuations.enumerated() {
            switch cont.yield([key: [serviceName : valueDict]]) {
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
    // filter for service starting with a pattern (e.g. "Light"
    // filter for services with certain characteristics
    // filter for specific values associated with those characteristics
    // this way you can filter for "Light" with "Power State" that is 1
    func readStoredServicesForAccessory(_ accessory: AFAccessoryNameContainer, startingWith: String? = nil, characterissticStartingWith: String? = nil, value: Any? = nil) -> [String]? {
        let servicesValues = dataStore[accessory]
        guard let servicesValues else {
            // means there is no information available
            return nil
        }
        return servicesValues.keys.filter({ serviceKey in
            // if there is no pattern for service just pass them all through
            guard let startingWith else {
                return true
            }
            return serviceKey.starts(with: startingWith)
        })
        .filter({ serviceKey in
            // if there is no pattern for characteristic just pass them all through
            guard let characterissticStartingWith else {
                return true
            }
            
            guard let cv = dataStore[accessory]?[serviceKey] else {
                return false
            }
            // go through the characteristics and values
            for (characteristic, cValue) in cv {
                if value == nil {
                    // if no value specified the base decision on the characteristic name
                    if characteristic.starts(with: characterissticStartingWith) {
                        return true
                    }
                } else {
                    // match both characteristic and value
                    if characteristic.starts(with: characterissticStartingWith) {
                        if let vv = cValue as? String, vv == value as? String {
                            return true
                        }
                        if let vv = cValue as? Int, vv == value as? Int {
                            return true
                        }
                        if let vv = cValue as? Bool, vv == value as? Bool {
                            return true
                        }
                    }
                }
                
            }
            return false
        })
        
        
        .sorted()
    }
    
    // All information about an accessorie
    func readStoredServicesCharacteristicsAndValuesForAccessory(_ accessory: AFAccessoryNameContainer) -> [String:  [String: Any?]]? {
        dataStore[accessory]
    }
    
    // All information about a service
    func readStoredCharacteristicsAndValuesForService(_ serviceName: String, accessory: AFAccessoryNameContainer) -> [String: Any?]? {
        dataStore[accessory]?[serviceName]
    }
    
    // read the all the values for all the characteristics of a service of a stored accessory
    // sorted in alpha order of the characteristics
    func readStoredValuesForCharacteristicsForService(_ serviceName: String, accessory: AFAccessoryNameContainer) -> [Any?]? {
        let characteristicsValues = dataStore[accessory]?[serviceName]
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
 
    // read the all the characteristics of a service of a stored accessory in alpha order
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
        let x = dataStore.keys.map {
            $0.array()
        }
        return x
    }
    
    // set the value of a characteristic
    // a write failure will append an error to the write error array
    // if the write is successful the local datastore is updated
    func setTrackedAccessryCharacteristic(value: Any?, characteristicName: String, serviceName: String, accessory keyName: AFAccessoryNameContainer) async -> Bool {

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

        do {
            try await char.writeValue(value)
        } catch {
            self.logger.error("Failed to write value \(String(describing:value)) to characteristic \(characteristicName) for accessory \(keyName.description): \(error.localizedDescription)")
            let myError = NSError(domain: "AccessoryFinder", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to write value \(String(describing:value)) to characteristic \(characteristicName) for accessory \(keyName.description): \(error.localizedDescription)",
                NSUnderlyingErrorKey: error])
            
            self.writeErrors.append(myError)
            return false
        }
 
        // need to write the updated value into the data source
        self.updateDataStore(key: keyName, serviceName: self.serviceToServiceName(service), characteristicName: characteristicName, value: value)

        self.logger.info("SET characteristic \(characteristicName) value \(String(describing:value)) in service \(self.serviceToServiceName(service)) in accessory \(keyName.description)")

        return true
    }

    // find a home - dynamically updates
    // if the home isn't there the function will wait for it to be reported
    // the caller is responsible for managing timeout
    // this function will return nil if the continuation or enclosing task is cancelled
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
    
    // find an accessory in a room in a home
    // if the accessory isn't there the function will wait for it to be reported
    // the caller is responsible for managing timeout
    // this function will return nil if the continuation or enclosing task is cancelled
    private func getTargetAccessoryNamed(_ accessoryName: String, inRoomNamed: String, inHome: HSKHome) async throws -> HMAccessory? {
        var homeContuation : AsyncStream<HSKHomeEventEnum>.Continuation?
        let homeStream = AsyncStream<HSKHomeEventEnum> { cont in
            homeContuation = cont
        }
        guard let homeContuation else {
            fatalError("contuation nil")
        }
        
        // cache the home now that we're looking for an accessory, make sure that any home with the same name has the same ID
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
    
    // track accessory value changes and update the datastore
    // tracking will listen to all characteristic changes
    // calls resultWrittenCallback the first time an update is received from the accessory which signals it has been found
    // since this is a multi-phase function statusCallback will be called with progress updates
    // the caller is responsible for managing timeout
    // this function will return nil if the continuation or enclosing task is cancelled

    func trackAccessoryNamed(_ accessoryName: String, inRoomNamed: String, inHomeNamed: String, resultWrittenCallback: ((AFAccessoryNameContainer?) -> Void)? = nil, statusCallback: ((String) -> Void)? = nil) async throws -> AFAccessoryNameContainer? {
        var resultWritten = false
        let keyName = AFAccessoryNameContainer(name: accessoryName, home: inHomeNamed, room: inRoomNamed)
        logger.info("Starting track of \(keyName)")
        statusCallback?("Starting track of \(keyName)")
        
        // check to see if the accessory is already tracked
        guard trackedAccessories[keyName] == nil else {
            logger.info("Accessory already tracked \(keyName)")
            resultWrittenCallback?(keyName)
            statusCallback?("Tracking already started for \(keyName)")
            return keyName
        }
        
        // check if we are currently trying to track this accessory
        if let trackArray = accessoriesTrackingInProgress[keyName] {
            logger.info("Accessory in progress of being tracked \(keyName)")
            statusCallback?("Accessory in progress of being tracked \(keyName)")
            var result : AFAccessoryNameContainer? = nil
            do {
                result = try await withCheckedThrowingContinuation { continuation in
                    var tkArray = trackArray
                    tkArray.append((resultWrittenCallback, continuation))
                    accessoriesTrackingInProgress[keyName] = tkArray
                }
            } catch {
                throw error
            }
            return result
        }
        accessoriesTrackingInProgress[keyName] = []
        
        let targetHome: HSKHome
        // check if we already allocated this home and get if from the cache
        statusCallback?("Looking for home: \(inHomeNamed)")
        if let storedHome = trackedHomes[inHomeNamed] {
            logger.info("Reusing home \(inHomeNamed)")
            targetHome = storedHome
        } else {
            // get a new home from the manager
            guard let newHome = await getTargetHome(inHomeNamed) else {
                logger.info("Get getTargetHome loop aborted")
                return nil
            }
            
            logger.info("Tracking new home \(inHomeNamed)")
            
            targetHome = await HSKHome(home: newHome)
        }
        
        // find the accessory in the home
        statusCallback?("Looking for accessory \(accessoryName) in room \(inRoomNamed)")
        guard let targetAccessory = try await getTargetAccessoryNamed(accessoryName, inRoomNamed: inRoomNamed, inHome: targetHome) else {
            logger.info("Get getTargetAccessorNamed loop aborted")
            // task was cancelled
            accessoriesTrackingInProgress[keyName]?.forEach { arg in
                arg.1.resume(throwing: NSError(domain: "AccessoryFinder", code: 0, userInfo: [NSLocalizedDescriptionKey: "Get getTargetAccessorNamed loop aborted"]))
            }
            accessoriesTrackingInProgress.removeValue(forKey: keyName)
            throw NSError(domain: "AccessoryFinder", code: 0, userInfo: [NSLocalizedDescriptionKey: "Get getTargetAccessorNamed loop aborted"])
        }
        
        // check if the accessory is already tracked
        if let tracked = trackedAccessories[keyName], tracked == targetAccessory {
            logger.info("Already tracking accessory \(accessoryName) in room \(inRoomNamed) in home \(inHomeNamed)")
            resultWrittenCallback?(keyName)
            accessoriesTrackingInProgress[keyName]?.forEach { arg in
                arg.0?(keyName)
                arg.1.resume(returning: keyName)
            }
            accessoriesTrackingInProgress.removeValue(forKey: keyName)
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
        
        // add new characteristic changes to the data store
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
                    accessoriesTrackingInProgress[keyName]?.forEach { arg in
                        arg.0?(keyName)
                        arg.1.resume(returning: keyName)
                    }
                    accessoriesTrackingInProgress.removeValue(forKey: keyName)
                    trackedAccessories[keyName] = targetAccessory
                    logger.info("Tracking accessory \(keyName.description)")
                    statusCallback?("Tracking accessory \(keyName.description)")

                    resultWritten = true
                }
            }
        }
        accessoriesTrackingInProgress[keyName]?.forEach { arg in
            arg.0?(keyName)
            arg.1.resume(returning: nil)
        }
        accessoriesTrackingInProgress.removeValue(forKey: keyName)

        logger.info("Accessory tracking complete for \(keyName.description)")
        statusCallback?("Accessory tracking complete for \(keyName.description)")
        // tracking is complete. The datasotre will no longer update
        self.trackedAccessories.removeValue(forKey: keyName)
        // retunring nill becasue the accessory is no longer tracked
        return nil
    }
    
    
}

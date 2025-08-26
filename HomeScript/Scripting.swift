//
//  Scripting.swift
//  CatalystAppleScript
//
//  Created by Steven Troughton-Smith on 05/06/2021.
//

#if targetEnvironment(macCatalyst)

import Foundation
import os

class Scripting: NSObject {
	
	class func enableScripting() {
		
		/*
		Catalyst doesn't have access to the regular NSApplication or AppKit application delegate.
		This is just one method to swizzle NSApplication and process scripting events as they happen
		*/
		
		do {
			let m1 = class_getInstanceMethod(NSClassFromString("NSApplication"), NSSelectorFromString("valueForKey:"))
			let m2 = class_getInstanceMethod(NSClassFromString("NSApplication"), NSSelectorFromString("MyAppScriptingValueForKey:"))
			
			if let m1 = m1, let m2 = m2 {
				method_exchangeImplementations(m1, m2)
			}
		}
		
		do {
			let m1 = class_getInstanceMethod(NSClassFromString("NSApplication"), NSSelectorFromString("setValue:forKey:"))
			let m2 = class_getInstanceMethod(NSClassFromString("NSApplication"), NSSelectorFromString("MyAppScriptingSetValue:forKey:"))
			
			if let m1 = m1, let m2 = m2 {
				method_exchangeImplementations(m1, m2)
			}
		}
	}
}

@MainActor
@objc
class AccessoryFinderScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments()
        var task : Task<Void, Never>?
        task = Task { [weak self] in
            var trackingStatus : String = "Not Started"
            var timeout = 60.0
            
            if let argTimeout = arguments["timeout"], let timeoutNumber = argTimeout as? NSNumber {
                timeout = Double(timeoutNumber.doubleValue)
            }
            
            let timerTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                if Task.isCancelled { return }
                task?.cancel()
                self?.scriptErrorNumber = -42
                self?.scriptErrorString = "Timeout trying to find accessory: \(arguments["accessory"] as! String), \(arguments["room"] as! String), \(arguments["home"] as! String) whle tracking status was: \(trackingStatus)"
                self?.resumeExecution(withResult: {})
            }
            
            do {
                _ = try await AccessoryFinder.shared.trackAccessoryNamed(arguments["accessory"] as! String,
                                                                  inRoomNamed: arguments["room"] as! String,
                                                                           inHomeNamed: arguments["home"] as! String, resultWrittenCallback: { r in
                    let result = r?.array().reduce(into: NSMutableArray()) { partialResult, str in
                            partialResult.add(NSString(string: str))
                    }
                    timerTask.cancel()
                    self?.resumeExecution(withResult: result)
                }, statusCallback: { status in
                    trackingStatus = status
                })
                   
            } catch {
                let nsError = error as NSError
                self?.scriptErrorNumber = -42 - nsError.code
                self?.scriptErrorString = error.localizedDescription
                self?.resumeExecution(withResult: {})
            }
              
            timerTask.cancel()
        }

        suspendExecution()
        return nil
    }
}

@MainActor
@objc
class AccessoryTrackedGetterScripter: NSScriptCommand {
    
    static var historyStore = [String: [[AFAccessoryNameContainer : [String : [String: Any?]]]]]()
    static var continuationStore = [String: AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]>.Continuation]()
    static var isConnectedStore = Set<String>()
    static var taskStore = [String: Task<Void, Never>]()
    static var timerTaskStore = [String: Task<Void, Never>]()
    static let logger = Logger()
    static var resumerStore = [String: (NSAppleEventDescriptor?) -> Void]()
    
    func fourCharCode(from string: String) -> FourCharCode {
        assert(string.count == 4, "String length must be 4")
        var result: FourCharCode = 0
        for char in string.utf16 { // Using UTF-16 for character representation
            result = (result << 8) + FourCharCode(char)
        }
        return result
    }
    
    func dictToRecord(_ dict: [String: Any?]) -> NSAppleEventDescriptor {
        let recDesc = NSAppleEventDescriptor(recordDescriptor: ())
        let userProperties = NSAppleEventDescriptor(listDescriptor: ())
        
        for key in dict.keys {
            let keyDesc = NSAppleEventDescriptor(string: key)
            userProperties.insert(keyDesc, at: 0)
            
            let value = dict[key]
            
            let ad : NSAppleEventDescriptor
            if value == nil {
                ad = NSAppleEventDescriptor(listDescriptor: ())
            } else if let y = value as? String {
                ad = NSAppleEventDescriptor(string: y)
            } else if let y = value as? Int {
                ad = NSAppleEventDescriptor(int32: sint32(y))
            } else if let y = value as? Bool {
                ad = NSAppleEventDescriptor(boolean: y)
            }  else if let y = value as? [[AFAccessoryNameContainer : [String : [String: Any?]]]] {
                ad = eventArrayToRecord(y)
            } else if let y = value as? [String : Any?] {
                ad = dictToRecord(y)
            } else if let y = value as? [String] {
               ad = y.reduce(into: NSAppleEventDescriptor(listDescriptor: ())) { partialResult, aString in
                   partialResult.insert(NSAppleEventDescriptor(string: aString), at: 0)
                }
            }
            else  {
                ad =  NSAppleEventDescriptor(listDescriptor: ())
            }
            userProperties.insert(ad, at: 0)
        }
        let kw = fourCharCode(from: "usrf") // keyASUserRecordFields from Cocoa
        recDesc.setDescriptor(userProperties, forKeyword: kw)
        return recDesc
    }
    
    func eventDictToDict(_ event: [AFAccessoryNameContainer : [String : [String: Any?]]]) -> [String : Any?] {
        var eventDict = [String : Any]()
        let accessory = event.keys.first
        guard let accessory else {
            return eventDict
        }
        eventDict["accessory"] = accessory.array()
        let service = event[accessory]?.keys.first
        guard let service else {
            return eventDict
        }
        eventDict["service"] = service
        guard let characteristic = event[accessory]?[service]?.keys.first(where: { characterisitc in
            !characterisitc.hasSuffix(AccessoryFinder.characteristicValueDateSuffix)
        }) else {
            return eventDict
        }
        eventDict["characteristic"] = characteristic
        guard let value = event[accessory]?[service]?[characteristic] else {
            return eventDict
        }
        eventDict["value"] = value
        guard let dateUpdated = event[accessory]?[service]?[characteristic + AccessoryFinder.characteristicValueDateSuffix] as? Date else {
            return eventDict
        }
        var format = Date.ISO8601FormatStyle()
        format.timeZone = .current
        
        eventDict["updated"] = dateUpdated.ISO8601Format(format)

        return eventDict
    }
    
    func eventArrayToRecord(_ events: [[AFAccessoryNameContainer : [String : [String: Any?]]]]) -> NSAppleEventDescriptor {
        return events.reduce(into: NSAppleEventDescriptor(listDescriptor: ())) { partialResult, event in
            partialResult.insert(dictToRecord(eventDictToDict(event)) , at: 0)
        }
    }
    
    func finishClientConnection(_ client: String, clientHistory:  [[AFAccessoryNameContainer : [String : [String: Any?]]]]) {
        AccessoryTrackedGetterScripter.isConnectedStore.remove(client)
        AccessoryTrackedGetterScripter.timerTaskStore[client]?.cancel()
        AccessoryTrackedGetterScripter.timerTaskStore[client] = nil
        AccessoryTrackedGetterScripter.historyStore[client] = []
        AccessoryTrackedGetterScripter.resumerStore[client]?(dictToRecord(["client" : client, "eventHistory" : clientHistory]))
        AccessoryTrackedGetterScripter.resumerStore[client] = nil
    }
    
    @objc public override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments()
        let client = arguments["id"] as? String ?? UUID().uuidString
        let clientHistory = AccessoryTrackedGetterScripter.historyStore[client] ?? []
        
    
        guard !AccessoryTrackedGetterScripter.isConnectedStore.contains(client) else {
            
            // messed up situation
            finishClientConnection(client, clientHistory: clientHistory)
            return dictToRecord(["client" : client, "events" : clientHistory])
        }
        
        AccessoryTrackedGetterScripter.isConnectedStore.insert(client)
        if arguments["id"] as? String == nil {
            var cont : AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]>.Continuation?
            let stream = AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]> { continuation in
                AccessoryTrackedGetterScripter.continuationStore[client] = continuation
                cont = continuation
            }
            guard let cont else {
                fatalError("continuation is nil")
            }
            // needs a setter
            AccessoryFinder.shared.dataStoreContinuations.append(cont)
            AccessoryTrackedGetterScripter.logger.info("Starting streaming for client \(client)")
            AccessoryTrackedGetterScripter.taskStore[client] = Task {
                for await entry in stream {
                    // add time to entry
                    var clientHistory = AccessoryTrackedGetterScripter.historyStore[client] ?? []
                    clientHistory.append(entry)

                    if AccessoryTrackedGetterScripter.isConnectedStore.contains(client) {
                        finishClientConnection(client, clientHistory: clientHistory)
                    } else {
                        AccessoryTrackedGetterScripter.historyStore[client] = clientHistory
                    }
                }
                AccessoryTrackedGetterScripter.logger.info("Stopped streaming for client \(client)")
            }
        }

        var timeout = 60.0
        
        if let argTimeout = arguments["timeout"], let timeoutNumber = argTimeout as? NSNumber {
            timeout = Double(timeoutNumber.doubleValue)
        }
        
        AccessoryTrackedGetterScripter.timerTaskStore[client] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            if Task.isCancelled { return }
            if AccessoryTrackedGetterScripter.isConnectedStore.contains(client) {
                let clientHistory = AccessoryTrackedGetterScripter.historyStore[client] ?? []
                self?.finishClientConnection(client, clientHistory: clientHistory)
            }
        }
        AccessoryTrackedGetterScripter.resumerStore[client] = { [weak self]  result in
            self?.resumeExecution(withResult: result)
        }
        suspendExecution()
        return nil
    }
}

@MainActor
@objc
class AccessoryGetterScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let accessory: AFAccessoryNameContainer
        do {
            accessory = try AFAccessoryNameContainer(arguments["accessory"] as! [String])
        } catch {
            fatalError("Could not parse accessory name")
        }
        
        let x = AccessoryFinder.shared.readStoredCharacteristicNamed(name: arguments["characteristic"] as! String,
                                                                     serviceName: arguments["service"] as! String,
                                                                     accessory: accessory)
   
        guard let x else { return nil }
        
        if let y = x as? String {
            return NSString(string: y)
        }
        
        if let y = x as? Int {
            return NSNumber(value: y)
        }
        
        if let y = x as? Bool {
            return NSNumber(value: y)
        }
        
        if let y = x as? Double {
            return NSNumber(value: y)
        }
        
        return nil
    }
}

@MainActor
@objc
class AccessorySetterScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let accessory: AFAccessoryNameContainer
        do {
            accessory = try AFAccessoryNameContainer(arguments["accessory"] as! [String])
        } catch {
            fatalError("Could not parse accessory name")
        }

        _ = AccessoryFinder.shared.setTrackedAccessryCharacteristic(value: arguments[""],
                                                                    characteristicName: arguments["toCharacteristic"] as! String,
                                                                    serviceName: arguments["service"] as! String,
                                                                    accessory: accessory)
        return nil
    }
}



@MainActor
@objc
class AccessoryServicesForAccessoryScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let accessory: AFAccessoryNameContainer
        do {
            accessory = try AFAccessoryNameContainer(arguments["accessory"] as! [String])
        } catch {
            fatalError("Could not parse accessory name")
        }
        return AccessoryFinder.shared.readStoredServicesForAccessory(accessory, startingWith: arguments["starting"] as? String,
                                                                     characterissticStartingWith: arguments["characteristicStarting"] as? String,
                                                                     value: arguments["value"])
       
    }
}


@MainActor
@objc
class AccessoryTrackedAccessoriesScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        //let arguments = evaluatedArguments()
       
        let x = AccessoryFinder.shared.readTrackedAccessories()
        
        let y = x.map { strArr in
            return NSString(string:"\(strArr.joined(separator: ","))")
            
        }
        return y
    }
}

@MainActor
@objc
class AccessoryTrackedCharacteristicsForServiceScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let accessory: AFAccessoryNameContainer
        do {
            accessory = try AFAccessoryNameContainer(arguments["accessory"] as! [String])
        } catch {
            fatalError("Could not parse accessory name")
        }
        return AccessoryFinder.shared.readStoredCharacteristicsForService(arguments["service"] as! String, accessory: accessory)
    }
}

@MainActor
@objc
class AccessoryValueForCharacteristicsForServiceScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let accessory: AFAccessoryNameContainer
        do {
            accessory = try AFAccessoryNameContainer(arguments["accessory"] as! [String])
        } catch {
            fatalError("Could not parse accessory name")
        }

        let list =  AccessoryFinder.shared.readStoredValuesForCharacteristicsForService(arguments["service"] as! String, accesory: accessory)
        
        guard let list else {
            return nil
        }
        let appleList = NSAppleEventDescriptor(listDescriptor: ())
 
        for x in list {
            let ad: NSAppleEventDescriptor
            if x == nil {
                ad = NSAppleEventDescriptor(listDescriptor: ())
            } else if let y = x as? String {
                ad = NSAppleEventDescriptor(string: y)
            } else if let y = x as? Int {
                ad = NSAppleEventDescriptor(int32: sint32(y))
            } else if let y = x as? Bool {
                ad = NSAppleEventDescriptor(boolean: y)
            } else  {
                ad =  NSAppleEventDescriptor(listDescriptor: ())
            }
            
            appleList.insert(ad, at: 0)
        }
        
        return appleList
    }
}


extension NSObject {
	@objc public func MyAppScriptingValueForKey(_ key:String) -> Any? {
		
		NSLog("[APPLESCRIPT] Querying value for \(key)")
			
		return self.MyAppScriptingValueForKey(key)
	}
	
	@objc public func MyAppScriptingSetValue(_ value:Any, forKey:String) {
		NSLog("[APPLESCRIPT] Setting value for \(forKey): \(String(describing:value))")
		
		return self.MyAppScriptingSetValue(value, forKey: forKey)
	}
	
	@objc func evaluatedArguments() -> NSDictionary {
		return NSDictionary()
	}
}

#endif

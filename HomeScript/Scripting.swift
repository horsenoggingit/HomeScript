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
    
    func eventToRecord(_ event :[String: [[AFAccessoryNameContainer : [String : [String: Any?]]]]]) -> NSAppleEventDescriptor? {
        let record = NSAppleEventDescriptor(listDescriptor: ())
        
        let client = event.keys.first
        guard let client else {
            return nil
        }
        
        let clientEvents = event[client] ?? []
        
        let eventList = NSAppleEventDescriptor(listDescriptor: ())
        
        
        clientEvents.forEach { event in
            let theRecord = NSAppleEventDescriptor(listDescriptor: ())
            let accessory = event.keys.first
            guard let accessory else {
                eventList.insert(theRecord, at: 0)
                return
            }
            let listRecord = NSAppleEventDescriptor(listDescriptor: ())
            accessory.array().forEach { item in
                listRecord.insert(NSAppleEventDescriptor(string: item), at: 0)
            }
            theRecord.insert(listRecord, at: 0)
            let service = event[accessory]?.keys.first
            guard let service else {
                eventList.insert(theRecord, at: 0)
                return
            }
            theRecord.insert(NSAppleEventDescriptor(string: service), at: 0)
            
            guard let characteristic = event[accessory]?[service]?.keys.first else {
                eventList.insert(theRecord, at: 0)
                return
            }
            theRecord.insert(NSAppleEventDescriptor(string:characteristic), at: 0)

            let value = event[accessory]?[service]?[characteristic]
            let ad : NSAppleEventDescriptor
            if value == nil {
                ad = NSAppleEventDescriptor(listDescriptor: ())
            } else if let y = value as? String {
                ad = NSAppleEventDescriptor(string: y)
            } else if let y = value as? Bool {
                ad = NSAppleEventDescriptor(boolean: y)
            } else if let y = value as? Int {
  
                ad = NSAppleEventDescriptor(int32: sint32(y))
            } else  {
                ad =  NSAppleEventDescriptor(listDescriptor: ())
            }
            theRecord.insert(ad, at: 0)
            eventList.insert(theRecord, at: 0)
            return
        }

        record.insert(NSAppleEventDescriptor(string:client), at: 0)
        record.insert(eventList, at: 0)
        
        return record
    }
    
    @objc public override func performDefaultImplementation() -> Any? {
        let arguments = evaluatedArguments()
        let client = arguments["id"] as? String ?? UUID().uuidString
        let clientHistory = AccessoryTrackedGetterScripter.historyStore[client] ?? []
        
    
        guard !AccessoryTrackedGetterScripter.isConnectedStore.contains(client) else {
            
            // messed up situation
            AccessoryTrackedGetterScripter.historyStore[client] = []
            AccessoryTrackedGetterScripter.isConnectedStore.remove(client)

            AccessoryTrackedGetterScripter.resumerStore[client]?(eventToRecord([client : clientHistory]))
            AccessoryTrackedGetterScripter.resumerStore[client] = nil

            return eventToRecord([client : clientHistory])
        }
        
        AccessoryTrackedGetterScripter.isConnectedStore.insert(client)
        if arguments["id"] as? String == nil {
            var cont : AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]>.Continuation?
            let stream = AsyncStream<[AFAccessoryNameContainer : [String : [String: Any?]]]> { continuation in
                AccessoryTrackedGetterScripter.continuationStore[client] = continuation
                cont = continuation
            }
            guard let cont else {
                fatalError("continuation is nill")
            }
            // needs a setter
            AccessoryFinder.shared.dataStoreContinuations.append(cont)
            AccessoryTrackedGetterScripter.logger.info("Starting streaming for client \(client)")
            AccessoryTrackedGetterScripter.taskStore[client] = Task {
                for await entry in stream {
                    var clientHistory = AccessoryTrackedGetterScripter.historyStore[client] ?? []
                    clientHistory.append(entry)

                    if AccessoryTrackedGetterScripter.isConnectedStore.contains(client) {
                        AccessoryTrackedGetterScripter.timerTaskStore[client]?.cancel()
                        AccessoryTrackedGetterScripter.timerTaskStore[client] = nil
                        AccessoryTrackedGetterScripter.historyStore[client] = []
                        AccessoryTrackedGetterScripter.isConnectedStore.remove(client)
                        AccessoryTrackedGetterScripter.resumerStore[client]?(eventToRecord([client : clientHistory]))
                        AccessoryTrackedGetterScripter.resumerStore[client] = nil

                    } else {
                        AccessoryTrackedGetterScripter.historyStore[client] = clientHistory
                    }
                }
                AccessoryTrackedGetterScripter.logger.info("Stopped streaming for client \(client)")
            }
        }

        // TODO: timeout to flush and return what we have
        var timeout = 60.0
        
        if let argTimeout = arguments["timeout"], let timeoutNumber = argTimeout as? NSNumber {
            timeout = Double(timeoutNumber.doubleValue)
        }
        
        AccessoryTrackedGetterScripter.timerTaskStore[client] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            if Task.isCancelled { return }
            if AccessoryTrackedGetterScripter.isConnectedStore.contains(client) {
                let clientHistory = AccessoryTrackedGetterScripter.historyStore[client] ?? []
                AccessoryTrackedGetterScripter.historyStore[client] = []
                AccessoryTrackedGetterScripter.isConnectedStore.remove(client)
                AccessoryTrackedGetterScripter.resumerStore[client]?(self?.eventToRecord([client : clientHistory]))
                AccessoryTrackedGetterScripter.resumerStore[client] = nil
                AccessoryTrackedGetterScripter.timerTaskStore[client] = nil
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

        if let y = x as? Bool {
            return NSNumber(value: y)
        }
        
        if let y = x as? Int {
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
            } else if let y = x as? Bool {
                ad = NSAppleEventDescriptor(boolean: y)
            } else if let y = x as? Int {
  
                ad = NSAppleEventDescriptor(int32: sint32(y))
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

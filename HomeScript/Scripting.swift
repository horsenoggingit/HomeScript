//
//  Scripting.swift
//  CatalystAppleScript
//
//  Created by Steven Troughton-Smith on 05/06/2021.
//

#if targetEnvironment(macCatalyst)

import Foundation

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
        Task {
            _ = await AccessoryFinder.shared.trackAccessoryNamed(arguments["accessory"] as! String,
                                                                 inRoomNamed: arguments["room"] as! String,
                                                                 inHomeNamed: arguments["home"] as! String)
            
        }
        return nil
    }
}

@MainActor
@objc
class AccessoryGetterScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let x = AccessoryFinder.shared.readStoredCharacteristicNamed(name: arguments["characteristic"] as! String,
                                                                     serviceName: arguments["service"] as! String,
                                                                     accessoryName: arguments["accessory"] as! String,
                                                                     inRoomNamed: arguments["room"] as! String,
                                                                     inHomeNamed: arguments["home"] as! String)
   
        guard let x else { return nil }
        
        if let s = x as? String {
            return NSString(string: s)
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
        _ = AccessoryFinder.shared.setTrackedAccessryCharacteristic(value: arguments[""],
                                                                    characteristicName: arguments["toCharacteristic"] as! String,
                                                                    serviceName: arguments["service"] as! String,
                                                                    accessoryName: arguments["accessory"] as! String,
                                                                    inRoomNamed: (arguments["room"] as! String),
                                                                    inHomeNamed: arguments["home"] as! String)
       
        return nil
    }
}



@MainActor
@objc
class AccessoryServicesForAccessoryScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()

        return AccessoryFinder.shared.readStoredServicesForAccessory(arguments["accessory"] as! String,
                                                                          inRoomNamed: (arguments["room"] as! String),
                                                                          inHomeNamed: arguments["home"] as! String)
       
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
       
        return AccessoryFinder.shared.readStoredCharacteristicsForService(arguments["service"] as! String, inAccesoryNamed: arguments["accessory"] as! String, inRoomNamed: (arguments["room"] as! String), inHomeNamed: arguments["home"] as! String)
    }
}

@MainActor
@objc
class AccessoryValueForCharacteristicsForServiceScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
  
        let list =  AccessoryFinder.shared.readStoredValuesForCharacteristicsForService(arguments["service"] as! String, inAccesoryNamed: arguments["accessory"] as! String, inRoomNamed: (arguments["room"] as! String), inHomeNamed: arguments["home"] as! String)
        
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

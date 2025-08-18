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
        _ = AccessoryFinder.shared.trackCharacteristicNamed(name: arguments["characteristic"] as! String,
                                                        accessoryName: arguments["accessory"] as! String,
                                                        inRoomNamed: arguments["room"] as! String,
                                                        inHomeNamed: arguments["home"] as! String)
        return nil
    }
}

@MainActor
@objc
class AccessoryGetterScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        let x = AccessoryFinder.shared.readStoredCharacteristicNamed(name: arguments["characteristic"] as! String,
                                                                        accessoryName: arguments["accessory"] as! String,
                                                                        inRoomNamed: arguments["room"] as! String,
                                                                        inHomeNamed: arguments["home"] as! String)
        return x
    }
}

@MainActor
@objc
class AccessorySetterScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
        _ = AccessoryFinder.shared.setTrackedAccessryCharacteristic(value: arguments[""],
                                                                name: arguments["toCharacteristic"] as! String,
                                                                accessoryName: arguments["accessory"] as! String,
                                                                    inRoomNamed: (arguments["room"] as! String),
                                                                inHomeNamed: arguments["home"] as! String)
       
        return nil
    }
}

@MainActor
@objc
class AccessoryCharacteristicsForAccesoryScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
       
        return AccessoryFinder.shared.readStoredCharacteristicsForAccessory(arguments["accessory"] as! String, inRoomNamed: (arguments["room"] as! String), inHomeNamed: arguments["home"] as! String)
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
class AccessoryTrackedCharacteristicsForAccessoryScripter: NSScriptCommand {
    @objc public override func performDefaultImplementation() -> Any? {
        
        let arguments = evaluatedArguments()
       
        return AccessoryFinder.shared.readStoredCharacteristicsForAccessory(arguments["accessory"] as! String, inRoomNamed: (arguments["room"] as! String), inHomeNamed: arguments["home"] as! String)
    }
}

extension NSObject {
	@objc public func MyAppScriptingValueForKey(_ key:String) -> Any? {
		
		NSLog("[APPLESCRIPT] Querying value for \(key)")
		
		if key == "savedString" {
			return "aaa" //DataModel.shared.testString
		}
		
		if key == "savedNumber" {
			return 3 //DataModel.shared.testNumber
		}
		
		if key == "savedList" {
			return ["One", "Two", "Three"] //[DataModel.shared.testList
		}
		
		if key == "savedBool" {
			return true //DataModel.shared.testBool
		}
		
		return self.MyAppScriptingValueForKey(key)
	}
	
	@objc public func MyAppScriptingSetValue(_ value:Any, forKey:String) {
		NSLog("[APPLESCRIPT] Setting value for \(forKey): \(String(describing:value))")
		
		if forKey == "savedString" {
//			DataModel.shared.testString = String(describing:value)
			return
		}
		
		if forKey == "savedNumber" {
//			DataModel.shared.testNumber = value as? Int ?? -1
			return
		}
		
		return self.MyAppScriptingSetValue(value, forKey: forKey)
	}
	
	@objc func evaluatedArguments() -> NSDictionary {
		return NSDictionary()
	}
}

#endif

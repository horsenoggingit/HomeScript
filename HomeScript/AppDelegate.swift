//
//  AppDelegate.swift
//  HomeScript
//
//  Created by James Infusino on 8/16/25.
//

import UIKit
import Foundation

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Perform setup tasks when the app finishes launching
        
#if targetEnvironment(macCatalyst)
        Scripting.enableScripting()
#endif

        print("AppDelegate: App has finished launching")
        return true
    }
}

//
//  HSKHMAccessoryDelegate.swift
//  HomeScript
//
//  Created by James Infusino on 8/15/25.
//
import HomeKit

enum HSKHMAccessoryDelegateEnum {
    case didUpdateName(_ hma:HMAccessory)
    case didUpdateReachability(_ hma:HMAccessory)
    case didUpdateServices(_ hma:HMAccessory)
    case didUpdateNameForService(_ hma:HMAccessory, didUpdateNameFor: HMService)
    case didUpdateValueForCharacteristic(_ hma:HMAccessory, service: HMService, didUpdateValueFor: HMCharacteristic)
    case didUpdateAssociatedServiceTypeFor(_ hma:HMAccessory, didUpdateAssociatedServiceTypeFor: HMService)
    case didAddAccessoryProfile(_ hma:HMAccessory, didAdd: HMAccessoryProfile)
    case didRemoveAccessoryProfile(_ hma:HMAccessory, didRemove: HMAccessoryProfile)
    case didUpdateFirmwareVersion(_ hma:HMAccessory, didUpdateFirmwareVersion: String)
}


class HSKHMAccessoryDelegate : NSObject, HMAccessoryDelegate {
    let cont : AsyncStream<HSKHMAccessoryDelegateEnum>.Continuation
    init(_ continuation: AsyncStream<HSKHMAccessoryDelegateEnum>.Continuation) {
        cont = continuation
    }
    
    deinit {
       cont.finish()
    }
    
    func accessoryDidUpdateName(_ hma:HMAccessory) {
        cont.yield(.didUpdateName(hma))
    }
    
    func accessoryDidUpdateReachability(_ hma:HMAccessory) {
        cont.yield(.didUpdateReachability(hma))
    }
    
    func accessoryDidUpdateServices(_ hma:HMAccessory) {
        cont.yield(.didUpdateServices(hma))
    }
    
    func accessory(_ hma:HMAccessory, didUpdateNameFor: HMService) {
        cont.yield(.didUpdateNameForService(hma, didUpdateNameFor:didUpdateNameFor))
    }
    
    func accessory(_ hma:HMAccessory, service: HMService, didUpdateValueFor: HMCharacteristic) {
        cont.yield(.didUpdateValueForCharacteristic(hma, service:service, didUpdateValueFor:didUpdateValueFor))
    }
    
    func accessory(_ hma:HMAccessory, didUpdateAssociatedServiceTypeFor: HMService) {
        cont.yield(.didUpdateAssociatedServiceTypeFor(hma, didUpdateAssociatedServiceTypeFor:didUpdateAssociatedServiceTypeFor))
    }
    
    func accessory(_ hma:HMAccessory, didAdd: HMAccessoryProfile) {
        cont.yield(.didAddAccessoryProfile(hma, didAdd: didAdd))
    }
    
    func accessory(_ hma:HMAccessory, didRemove: HMAccessoryProfile) {
        cont.yield(.didRemoveAccessoryProfile(hma, didRemove: didRemove))
    }
    
    func accessory(_ hma:HMAccessory, didUpdateFirmwareVersion: String) {
        cont.yield(.didUpdateFirmwareVersion(hma, didUpdateFirmwareVersion:didUpdateFirmwareVersion))
    }
}


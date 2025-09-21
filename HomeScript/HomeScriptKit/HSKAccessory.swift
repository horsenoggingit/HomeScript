//
//  HSKAccessory.swift
//  HomeScript
//
//  Created by James Infusino on 8/16/25.
//

import Foundation
import HomeKit

enum HSKAccessoryEventEnum {
    case characteristicValueUpdated(HMService, HMCharacteristic, Any?)
}

actor HSKAccessory {
    let accessory: HMAccessory
    let accessoryDelegate: HSKHMAccessoryDelegate
    let stream: AsyncStream<HSKHMAccessoryDelegateEnum>
    let streamContinuation: AsyncStream<HSKHMAccessoryDelegateEnum>.Continuation
    let eventContinuation: AsyncStream<HSKAccessoryEventEnum>.Continuation
    
    init(accessory: HMAccessory, eventContinuation: AsyncStream<HSKAccessoryEventEnum>.Continuation) async {
        self.accessory = accessory
        self.eventContinuation = eventContinuation
        
        var cont : AsyncStream<HSKHMAccessoryDelegateEnum>.Continuation?
        let stream = AsyncStream<HSKHMAccessoryDelegateEnum> { continuation in
            cont = continuation
        }
        guard let cont else {
            fatalError("unexpected")
        }
        self.streamContinuation = cont
        self.stream = stream
        
        self.accessoryDelegate = HSKHMAccessoryDelegate(cont)
        accessory.delegate = accessoryDelegate
        
        Task { [weak self, stream] in
            for await event in stream {
                switch event {
                
                case .didUpdateName(_):
                    break
                case .didUpdateReachability(_):
                    break
                case .didUpdateServices(_):
                    break
                case .didUpdateNameForService(_, didUpdateNameFor: _):
                    break
                case .didUpdateValueForCharacteristic(_, service: let service, didUpdateValueFor: let didUpdateValueFor):
                    await self?.updatedValueForCharacteristic(didUpdateValueFor, service: service)
                    break
                case .didUpdateAssociatedServiceTypeFor(_, didUpdateAssociatedServiceTypeFor: _):
                    break
                case .didAddAccessoryProfile(_, didAdd: _):
                    break
                case .didRemoveAccessoryProfile(_, didRemove: _):
                    break
                case .didUpdateFirmwareVersion(_, didUpdateFirmwareVersion: _):
                    break
                }
            }
        }
        
        for service in accessory.services {
            if Task.isCancelled {
                break
            }
            for characteristic in service.characteristics {
                if Task.isCancelled {
                    break
                }
                if characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) {
                    try? await characteristic.enableNotification(true)
                }
               
                if characteristic.properties.contains(HMCharacteristicPropertyReadable) {
                    do {
                        try await characteristic.readValue()
                    } catch {
                        print ("Error reading characteristic \(characteristic.localizedDescription) value: \(error)")
                    }
                }
                self.updatedValueForCharacteristic(characteristic, service: service)
            }
        }

    }
    
    func updatedValueForCharacteristic(_ characteristic: HMCharacteristic, service: HMService) {
        guard characteristic.properties.contains(HMCharacteristicPropertyReadable) else {
            self.eventContinuation.yield(.characteristicValueUpdated(service, characteristic, nil))
            return 
        }
        self.eventContinuation.yield(.characteristicValueUpdated(service, characteristic, characteristic.value))
    }
    
    deinit {
        eventContinuation.finish()
        streamContinuation.finish()
        print("HSKAccessory deinit")
    }
}

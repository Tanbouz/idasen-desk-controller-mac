//
//  DeskPeripheral.swift
//  Desk Controller
//
//  Created by David Williames on 10/1/21.
//

import Cocoa
import CoreBluetooth

class DeskPeripheral: NSObject {

    public static let deskPositionServiceUUID = CBUUID.init(string: "99FA0020-338A-1024-8A49-009C0215F78A")
    public static let deskPositionCharacteristicUUID = CBUUID.init(string: "99FA0021-338A-1024-8A49-009C0215F78A")
    
    public static let deskControlServiceUUID = CBUUID.init(string: "99FA0001-338A-1024-8A49-009C0215F78A")
    public static let deskControlCharacteristicUUID = CBUUID.init(string: "99FA0002-338A-1024-8A49-009C0215F78A")
    
    static let heightPositionOffset: Float = 61.5 // min
    
    
    let peripheral: CBPeripheral
    
    var positionService: CBService?
    var positionCharacteristic: CBCharacteristic?
        
    var controlService: CBService?
    var controlCharacteristic: CBCharacteristic?
    
    
    var speed: Float = 0
    
    var hasLoadedPositionCharacteristicValues = false

    private var pollTimer: Timer?

    var onPositionChange: (Float) -> Void = { _ in }
    var position: Float? {
        didSet {
//            print("\(position)cm")
            
            if let position = position, hasLoadedPositionCharacteristicValues {
                onPositionChange(position)
            }
            
        }
    }
    
    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral

        super.init()

        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    deinit {
        pollTimer?.invalidate()
    }

    // Belt-and-suspenders against notify subscriptions that silently fail or
    // get dropped (observed with ad-hoc-signed builds), which would otherwise
    // leave `position` frozen at whatever the initial `readValue` returned.
    private func startPollingFallback() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let characteristic = self.positionCharacteristic else { return }
            self.peripheral.readValue(for: characteristic)
        }
    }
}

extension DeskPeripheral: CBPeripheralDelegate {
    
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        
        guard peripheral == self.peripheral, let services = peripheral.services else {
            return
        }
        
        services.forEach { service in
            if service.uuid == DeskPeripheral.deskPositionServiceUUID {
                positionService = service
                // print("Discovered position service: \(service)")
            } else if service.uuid == DeskPeripheral.deskControlServiceUUID {
                controlService = service
                // print("Discovered control service: \(service)")
            } else {
                return
            }
            
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        
        guard peripheral == self.peripheral, let characteristics = service.characteristics else {
            return
        }
        
        characteristics.forEach { characteristic in
            if characteristic.uuid == DeskPeripheral.deskPositionCharacteristicUUID {
                // print("Discovered position characteristic: \(characteristic)")
                positionCharacteristic = characteristic
                
                peripheral.readValue(for: characteristic)
                // Start monitoring the position / speed
                peripheral.setNotifyValue(true, for: characteristic)
                startPollingFallback()
            } else if characteristic.uuid == DeskPeripheral.deskControlCharacteristicUUID {
                // print("Discovered control characteristic: \(characteristic)")
                controlCharacteristic = characteristic
            } else {
                return
            }
            
            print(characteristic.properties)
        }
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Failed to subscribe to notifications for \(characteristic.uuid): \(error)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if characteristic == positionCharacteristic, let value = characteristic.value {
            
            hasLoadedPositionCharacteristicValues = true
            
            // Position = 16 Little Endian – Unsigned
            // Speed = 16 Little Endian – Signed
            
            let positionValue = [value[0], value[1]].withUnsafeBytes {
                $0.load(as: UInt16.self)
            }
            
            let speedValue = [value[2], value[3]].withUnsafeBytes {
                $0.load(as: Int16.self)
            }
            
            speed = Float(speedValue)
            position = Float(positionValue) / 100 + DeskPeripheral.heightPositionOffset

        }
        
    }

}

//
//  BTTool.swift
//  AirBattery
//
//  Created by apple on 2024/10/17.
//

import Foundation
import IOBluetooth

class BTTool {
    static func disconnect(mac: String) -> Bool {
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
           let device = devices.first(where: { $0.addressString == mac.replacingOccurrences(of: ":", with: "-").lowercased() && $0.isConnected() }){
            var attempts = 0
            while (attempts < 10 && device.isConnected()) {
                device.closeConnection()
                usleep(500000)
                attempts += 1
            }
            if !device.isConnected() {
                DebugLog.info(.bluetooth, "Device disconnected: \(device: device.name ?? "")")
                let selector = NSSelectorFromString("remove")
                
                if device.responds(to: selector) {
                    device.perform(selector)
                    DebugLog.info(.bluetooth, "Unpair attempt successful")
                    return true
                } else {
                    DebugLog.warning(.bluetooth, "Unpair method unavailable")
                    return false
                }
            }
        }
        return false
    }
    
    static func connect(mac: String) -> Bool {
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
           let device = devices.first(where: { $0.addressString == mac.replacingOccurrences(of: ":", with: "-").lowercased() }){
            device.openConnection()
            var attempts = 0
            while (attempts < 10 && !device.isConnected()) {
                usleep(500000)
                attempts += 1
            }
            return device.isConnected()
        }
        return false
    }
}

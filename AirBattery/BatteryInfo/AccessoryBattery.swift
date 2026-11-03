//
//  AccessoryBattery.swift
//  AirBattery
//

import SwiftUI
import Foundation
import IOKit.ps

// The public IOPSCopyPowerSourcesInfo only lists internal batteries; type 4 selects Bluetooth accessories.
@_silgen_name("IOPSCopyPowerSourcesByType")
private func IOPSCopyPowerSourcesByType(_ type: Int32) -> Unmanaged<CFTypeRef>?

private let appleVendorID = 76

class AccessoryBattery {
    static let shared = AccessoryBattery()
    @AppStorage("readBTDevice") var readBTDevice = true
    private let work = DispatchQueue(label: "com.kerdofficial.AirBattery.accessory", qos: .utility)

    func startScan() {
        print("ℹ️ Start scanning accessory power sources...")
        refresh()
    }

    func refresh() {
        guard readBTDevice else { return }
        work.async { AccessoryBattery.read().forEach { AirBatteryModel.updateDevice($0) } }
    }

    static func read() -> [Device] {
        guard let info = IOPSCopyPowerSourcesByType(4)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return [] }
        let types = bluetoothTypesByName()
        let parent = ud.string(forKey: "deviceName") ?? "Mac"
        var devices = [Device]()
        for source in sources {
            guard let ps = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let name = ps[kIOPSNameKey] as? String, !name.isEmpty,
                  let current = ps[kIOPSCurrentCapacityKey] as? Int,
                  let max = ps[kIOPSMaxCapacityKey] as? Int, max > 0,
                  (ps["Vendor ID"] as? Int) != appleVendorID,
                  !AirBatteryModel.checkIfBlocked(name: name) else { continue }
            let id = ps["Accessory Identifier"] as? String ?? name
            let type = types[name] ?? deviceType(forCategory: ps["Accessory Category"] as? String)
            devices.append(Device(deviceID: id, deviceType: type, deviceName: name, batteryLevel: Swift.min(100, Swift.max(0, current * 100 / max)), isCharging: (ps[kIOPSIsChargingKey] as? Bool) == true ? 1 : 0, isCharged: (ps[kIOPSIsChargedKey] as? Bool) == true, parentName: parent, lastUpdate: Date().timeIntervalSince1970))
        }
        return devices
    }

    private static func deviceType(forCategory category: String?) -> String {
        switch category {
        case "Keyboard": return "Keyboard"
        case "Mouse": return "Mouse"
        case "Headset", "Headphones": return "Headphones"
        case "Gamepad", "Game Controller": return "Gamepad"
        case "Trackpad": return "Trackpad"
        default: return "general_bt"
        }
    }

    private static func bluetoothTypesByName() -> [String: String] {
        guard let json = try? JSONSerialization.jsonObject(with: Data(SPBluetoothDataModel.shared.data.utf8)) as? [String: Any],
              let sections = json["SPBluetoothDataType"] as? [[String: Any]],
              let connected = sections.first?["device_connected"] as? [[String: Any]] else { return [:] }
        var types = [String: String]()
        for entry in connected {
            for (name, value) in entry {
                if let info = value as? [String: Any], let type = info["device_minorType"] as? String { types[name] = type }
            }
        }
        return types
    }
}

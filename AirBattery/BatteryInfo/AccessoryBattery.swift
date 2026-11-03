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
        work.async {
            let reading = AccessoryBattery.read()
            reading.devices.forEach { AirBatteryModel.updateDevice($0) }
            reading.airPods.forEach { $0.apply() }
        }
    }

    static func read() -> (devices: [Device], airPods: [AirPodsPublication]) {
        guard let info = IOPSCopyPowerSourcesByType(4)?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return ([], []) }
        let descriptions = sources.compactMap { IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] }
        return (readOthers(descriptions), airPods(from: descriptions))
    }

    static func airPods(from descriptions: [[String: Any]]) -> [AirPodsPublication] {
        let audio = descriptions.filter { ($0["Vendor ID"] as? Int) == appleVendorID }
        let cases = Dictionary(audio.filter { $0["Accessory Category"] as? String == "Audio Battery Case" }.compactMap { ps in (ps["Group Identifier"] as? String).map { ($0, ps) } }, uniquingKeysWith: { first, _ in first })
        let now = Date().timeIntervalSince1970
        return audio.compactMap { ps in
            guard ["Headset", "Headphones"].contains(ps["Accessory Category"] as? String),
                  let name = ps[kIOPSNameKey] as? String, !name.isEmpty,
                  !AirBatteryModel.checkIfBlocked(name: name),
                  let whole = part(ps) else { return nil }
            let productID = (ps["Product ID"] as? Int).map { String(format: "%04x", $0) } ?? ""
            var reading = AirPodsReading(name: name, deviceID: ps["Accessory Identifier"] as? String ?? name, model: getHeadphoneModel(productID))
            if let parts = ps["Combined Parts"] as? [[String: Any]] {
                for combined in parts {
                    let partName = combined["Part Name"] as? String ?? ""
                    if partName.contains("🅛") || partName.contains("🄻") { reading.left = part(combined) }
                    if partName.contains("🅡") || partName.contains("🅁") { reading.right = part(combined) }
                }
                if let group = ps["Group Identifier"] as? String, let caseSource = cases[group] { reading.casePart = part(caseSource) }
            } else {
                reading.whole = whole
            }
            return reading.publication(now: now)
        }
    }

    private static func part(_ ps: [String: Any]) -> AirPodsPart? {
        guard let current = ps[kIOPSCurrentCapacityKey] as? Int, let max = ps[kIOPSMaxCapacityKey] as? Int, max > 0 else { return nil }
        return AirPodsPart(level: Swift.min(100, Swift.max(0, current * 100 / max)), charging: (ps[kIOPSIsChargingKey] as? Bool) == true ? 1 : 0, charged: (ps[kIOPSIsChargedKey] as? Bool) == true)
    }

    private static func readOthers(_ descriptions: [[String: Any]]) -> [Device] {
        let types = bluetoothTypesByName()
        let parent = ud.string(forKey: "deviceName") ?? "Mac"
        var devices = [Device]()
        for ps in descriptions {
            guard let name = ps[kIOPSNameKey] as? String, !name.isEmpty,
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

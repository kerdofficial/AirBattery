//
//  LogitechBattery.swift
//  AirBattery
//
//  Portions adapted from LinearMouse (https://github.com/linearmouse/linearmouse),
//  Copyright (c) 2021-2024 LinearMouse, MIT License
//  (see the full permission notice in HIDPP.swift)
//
import SwiftUI
import Foundation
import IOKit.hid

class LogitechBattery {
    static let shared = LogitechBattery()

    @AppStorage("readLogitech") var readLogitech = true

    private struct BatteryReading {
        var level: Int
        var isCharging: Bool
        var isFull: Bool
    }

    private struct SlotInfo {
        var name: String
        var type: String
        var batteryFeature: (id: HIDPPFeatureID, index: UInt8)?
    }

    private static let vendorID = 0x046D
    private static let headsetProductID = 0x0AF7
    private static let receiverProductIDs: Set<Int> = [
        0xC52B, 0xC532, // Unifying
        0xC539, 0xC53A, 0xC53D, 0xC53F, 0xC541, 0xC543, 0xC545, 0xC547, 0xC54D, // Lightspeed
        0xC548 // Bolt
    ]
    private static let headsetBatteryRequest: [UInt8] = {
        var frame = [UInt8](repeating: 0, count: 64)
        frame[0] = 0x51; frame[1] = 0x08; frame[3] = 0x03; frame[4] = 0x1a
        frame[6] = 0x03; frame[8] = 0x04; frame[9] = 0x0a
        return frame
    }()

    let work = DispatchQueue(label: "com.lihaoyun6.AirBattery.logitech")
    private let hidQueue = DispatchQueue(label: "com.lihaoyun6.AirBattery.logitech.hid")
    private var manager: IOHIDManager?
    private var channels: [IOHIDDevice: HIDChannel] = [:]
    private var slots: [String: SlotInfo] = [:]
    private var refreshScheduled = false

    func startScan() {
        refresh()
    }

    func refresh() {
        guard readLogitech else { return }
        work.async {
            self.startManagerIfNeeded()
            self.scan().forEach { AirBatteryModel.updateDevice($0) }
        }
    }

    func startManagerIfNeeded() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [[String: Int]] = [0xFF00, 0xFFA0].map {
            [kIOHIDVendorIDKey: Self.vendorID, kIOHIDDeviceUsagePageKey: $0, kIOHIDDeviceUsageKey: 1]
        }
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<LogitechBattery>.fromOpaque(context).takeUnretainedValue().scheduleRefresh()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<LogitechBattery>.fromOpaque(context).takeUnretainedValue().deviceRemoved(device)
        }, context)
        IOHIDManagerSetDispatchQueue(manager, hidQueue)
        IOHIDManagerActivate(manager)
        self.manager = manager
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        work.async {
            self.channels.removeValue(forKey: device)?.close()
            self.slots = [:]
        }
    }

    private func scheduleRefresh() {
        work.async {
            guard !self.refreshScheduled else { return }
            self.refreshScheduled = true
            self.work.asyncAfter(deadline: .now() + 1) {
                self.refreshScheduled = false
                self.refresh()
            }
        }
    }

    func scan() -> [Device] {
        guard let devices = manager.flatMap({ IOHIDManagerCopyDevices($0) as? Set<IOHIDDevice> }) else { return [] }
        var result: [Device] = []
        for device in devices {
            let productID = intProperty(device, kIOHIDProductIDKey) ?? 0
            let locationID = String(intProperty(device, kIOHIDLocationIDKey) ?? 0, radix: 16)
            let usagePage = intProperty(device, kIOHIDPrimaryUsagePageKey)
            if productID == Self.headsetProductID {
                if let device = readHeadset(device, id: "logitech:\(locationID):headset") { result.append(device) }
            } else if Self.receiverProductIDs.contains(productID), usagePage == 0xFF00,
                      (intProperty(device, kIOHIDMaxOutputReportSizeKey) ?? 0) >= 7 {
                result += readReceiver(device, locationID: locationID)
            }
        }
        return result
    }

    private func intProperty(_ device: IOHIDDevice, _ key: String) -> Int? {
        IOHIDDeviceGetProperty(device, key as CFString) as? Int
    }

    private func channel(for device: IOHIDDevice) -> HIDChannel? {
        if let channel = channels[device] { return channel }
        guard let channel = HIDChannel(managedDevice: device) else { return nil }
        channels[device] = channel
        return channel
    }

    private func readReceiver(_ device: IOHIDDevice, locationID: String) -> [Device] {
        guard let channel = channel(for: device) else { return [] }
        var result: [Device] = []
        for slot in UInt8(1) ... 6 {
            guard let transport = HIDPPTransport(channel: channel, deviceIndex: slot) else { continue }
            let key = "\(locationID):\(slot)"
            guard let info = slotInfo(for: key, transport: transport),
                  let feature = info.batteryFeature,
                  let battery = readBattery(feature, transport: transport) else {
                slots.removeValue(forKey: key)
                continue
            }
            result.append(makeDevice(id: "logitech:\(key)", type: info.type, name: info.name, battery: battery))
        }
        return result
    }

    private func slotInfo(for key: String, transport: HIDPPTransport) -> SlotInfo? {
        if let info = slots[key] { return info }
        guard let type = readDeviceType(transport),
              let name = readName(transport, feature: .deviceFriendlyName, skipFirstByte: true)
                  ?? readName(transport, feature: .deviceName, skipFirstByte: false),
              let batteryFeature = findBatteryFeature(transport) else { return nil }
        let info = SlotInfo(name: name, type: type, batteryFeature: batteryFeature)
        slots[key] = info
        return info
    }

    private func readDeviceType(_ transport: HIDPPTransport) -> String? {
        guard let index = transport.featureIndex(for: .deviceName),
              let type = transport.request(featureIndex: index, function: 2)?.first else { return nil }
        switch type {
        case 0, 2: return "Keyboard"
        case 3, 5, 6: return "Mouse"
        case 4: return "Trackpad"
        case 8: return "Headphones"
        case 10, 11, 12: return "Gamepad"
        case 14: return "Speaker"
        default: return "general_bt"
        }
    }

    private func readName(_ transport: HIDPPTransport, feature: HIDPPFeatureID, skipFirstByte: Bool) -> String? {
        guard let index = transport.featureIndex(for: feature),
              let length = transport.request(featureIndex: index, function: 0)?.first, length > 0 else { return nil }
        var bytes: [UInt8] = []
        while bytes.count < Int(length) {
            guard let payload = transport.request(featureIndex: index, function: 1, parameters: [UInt8(bytes.count)]) else { return nil }
            let fragment = skipFirstByte ? Array(payload.dropFirst()) : payload
            if fragment.isEmpty { break }
            bytes += fragment
        }
        return String(bytes: bytes.prefix(Int(length)).prefix { $0 != 0 }, encoding: .utf8)
    }

    private func findBatteryFeature(_ transport: HIDPPTransport) -> (id: HIDPPFeatureID, index: UInt8)? {
        for id in [HIDPPFeatureID.unifiedBattery, .batteryStatus, .batteryVoltage, .adcMeasurement] {
            if let index = transport.featureIndex(for: id) { return (id, index) }
        }
        return nil
    }

    private func readBattery(_ feature: (id: HIDPPFeatureID, index: UInt8), transport: HIDPPTransport) -> BatteryReading? {
        switch feature.id {
        case .unifiedBattery:
            guard let capabilities = transport.request(featureIndex: feature.index, function: 0), capabilities.count >= 2,
                  let status = transport.request(featureIndex: feature.index, function: 1), status.count >= 3 else { return nil }
            let levels: [UInt8: Int] = [1: 5, 2: 20, 4: 50, 8: 100]
            let level: Int
            if capabilities[1] & 0x02 != 0, (1 ... 100).contains(status[0]) {
                level = Int(status[0])
            } else if let approximate = levels[status[1]] {
                level = approximate
            } else {
                return nil
            }
            return BatteryReading(level: level, isCharging: [1, 2, 4].contains(status[2]), isFull: status[2] == 3)
        case .batteryStatus:
            guard let status = transport.request(featureIndex: feature.index, function: 0), status.count >= 3,
                  (1 ... 100).contains(status[0]) else { return nil }
            return BatteryReading(level: Int(status[0]), isCharging: [1, 2, 4].contains(status[2]), isFull: status[2] == 3)
        case .batteryVoltage, .adcMeasurement:
            guard let status = transport.request(featureIndex: feature.index, function: 0), status.count >= 3 else { return nil }
            let flags = status[2]
            let millivolts = Int(status[0]) << 8 | Int(status[1])
            let level = Int((Double(max(3500, min(4200, millivolts)) - 3500) / 700 * 100).rounded())
            if feature.id == .adcMeasurement {
                guard flags & 0x01 != 0 else { return nil }
                return BatteryReading(level: level, isCharging: flags & 0x02 != 0, isFull: false)
            }
            return BatteryReading(level: level, isCharging: flags & 0x80 != 0 && flags & 0x03 != 3, isFull: flags & 0x83 == 0x83)
        default:
            return nil
        }
    }

    private func readHeadset(_ device: IOHIDDevice, id: String) -> Device? {
        guard let channel = channel(for: device),
              let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String else { return nil }
        let isPoweredOff: (Data) -> Bool = { $0.count > 6 && $0[1] == 0x05 && $0[6] == 0x00 }
        let isBattery: (Data) -> Bool = { $0.count >= 13 && $0[1] == 0x0b && $0[8] == 0x04 }
        guard let reply = channel.request(Data(Self.headsetBatteryRequest), timeout: 2, accept: {
            $0.first == 0x51 && (isPoweredOff($0) || isBattery($0))
        }), isBattery(reply) else { return nil }
        let state = reply[12]
        let battery = BatteryReading(level: min(Int(reply[10]), 100), isCharging: state == 0x01 || state == 0x02, isFull: state == 0x03)
        return makeDevice(id: id, type: "Headphones", name: name, battery: battery)
    }

    private func makeDevice(id: String, type: String, name: String, battery: BatteryReading) -> Device {
        Device(deviceID: id, deviceType: type, deviceName: name, batteryLevel: battery.level,
               isCharging: battery.isCharging ? 1 : 0, isCharged: battery.isFull,
               lastUpdate: Date().timeIntervalSince1970)
    }
}

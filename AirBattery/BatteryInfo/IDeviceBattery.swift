//
//  AirBatteryModel.swift
//  AirBattery
//
//  Created by apple on 2024/2/6.
//
import SwiftUI
import Foundation

class IDeviceBattery {
    static var shared: IDeviceBattery = IDeviceBattery()
    
    private let scanQueue = DispatchQueue(label: "com.kerdofficial.AirBattery.idevice-scan", qos: .utility)
    private let lock = NSLock()
    private var isRunning = false
    @AppStorage("readPencil") var readPencil = false
    @AppStorage("readIDevice") var readIDevice = true
    @AppStorage("updateInterval") var updateInterval = 1
    
    func startScan() {
        DebugLog.info(.idevice, "Source started")
        scanDevices()
    }
    
    func scanDevices() {
        guard readIDevice else { DebugLog.verbose(.idevice, "Source disabled"); return }
        lock.lock()
        if isRunning { lock.unlock(); return }
        isRunning = true
        lock.unlock()

        scanQueue.async {
            let started = debugScanStart(.idevice)
            self.getIDeviceBattery()
            DebugLog.verbose(.idevice, "Scan duration \(Int((started.map { Date().timeIntervalSince($0) } ?? 0) * 1000)) ms")
            self.lock.lock()
            self.isRunning = false
            self.lock.unlock()
        }
    }
    
    func getPencil(d: Device, type: String = "") {
        guard d.deviceType == "iPad", readPencil else { return }
        var readSucceeded = false
        defer { if !readSucceeded { DebugLog.warning(.idevice, "Pencil read failed: \(device: d.deviceName)") } }
        if let result = process(path: "/bin/bash", arguments: ["\(Bundle.main.resourcePath!)/logReader.sh", "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevicesyslog", type, d.deviceID], timeout: 11 * updateInterval) {
            if let json = try? JSONSerialization.jsonObject(with: Data(result.utf8), options: []) as? [String: Any] {
                if let level = json["level"] as? Int, let model = json["model"] as? String, let vendor = json["vendor"] as? String {
                    let status = (json["status"] as? Int) ?? 0
                    readSucceeded = true
                    DebugLog.verbose(.idevice, "Pencil level \(level) charging \(status)")
                    AirBatteryModel.updateDevice(Device(deviceID: "Pencil_"+d.deviceID, deviceType: vendor == "Apple" ? "ApplePencil" : "Pencil", deviceName: vendor == "Apple" ? "Apple Pencil".local : "Pencil".local, deviceModel: model, batteryLevel: level, isCharging: status, parentName: d.deviceName, lastUpdate: Date().timeIntervalSince1970))
                }
            }
        }
    }
    
    func getIDeviceBattery() {
        if let result = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevice_id", arguments: ["-n"]) {
            DebugLog.verbose(.idevice, "Enumeration devices \(result.split(whereSeparator: { $0.isNewline }).count)")
            for id in result.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                if let d = AirBatteryModel.getByID(id) {
                    if (Double(Date().timeIntervalSince1970) - d.lastUpdate) > Double(60 * updateInterval) { writeBatteryInfo(id, "-n") }
                    getPencil(d: d, type: "-n")
                } else {
                    writeBatteryInfo(id, "-n")
                }
            }
        }
        if let result = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/idevice_id", arguments: ["-l"]) {
            DebugLog.verbose(.idevice, "Enumeration devices \(result.split(whereSeparator: { $0.isNewline }).count)")
            for id in result.components(separatedBy: .newlines).filter({ !$0.isEmpty }) {
                if let d = AirBatteryModel.getByID(id) {
                    if (Double(Date().timeIntervalSince1970) - d.lastUpdate) > Double(60 * updateInterval) { writeBatteryInfo(id, "") }
                    getPencil(d: d)
                } else {
                    writeBatteryInfo(id, "")
                }
            }
        }
    }
    
    func writeBatteryInfo(_ id: String, _ connectType: String) {
        var readSucceeded = false
        defer { if !readSucceeded { DebugLog.warning(.idevice, "Device battery read failed: \(id: id)") } }
        let lastUpdate = Date().timeIntervalSince1970
        if connectType == "" { _ = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/wificonnection", arguments: ["-u", id, "true"]) }
        if let deviceInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id]){
            let i = deviceInfo.components(separatedBy: .newlines)
            if let deviceName = i.filter({ $0.contains("DeviceName") }).first?.components(separatedBy: ": ").last,
               let model = i.filter({ $0.contains("ProductType") }).first?.components(separatedBy: ": ").last,
               let type = i.filter({ $0.contains("DeviceClass") }).first?.components(separatedBy: ": ").last {
                if let batteryInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id, "-q", "com.apple.mobile.battery"]) {
                    let b = batteryInfo.components(separatedBy: .newlines)
                    if let level = b.filter({ $0.contains("BatteryCurrentCapacity") }).first?.components(separatedBy: ": ").last,
                       let levelValue = Int(level),
                       let charging = b.filter({ $0.contains("BatteryIsCharging") }).first?.components(separatedBy: ": ").last,
                       let isCharging = Bool(charging) {
                        readSucceeded = true
                        AirBatteryModel.updateDevice(Device(deviceID: id, deviceType: type, deviceName: deviceName, deviceModel: model, batteryLevel: levelValue, isCharging: isCharging ? 1 : 0, lastUpdate: lastUpdate, iconSymbol: DeviceSymbols.symbol(modelCode: model)))
                        if let watchInfo = process(path: "\(Bundle.main.resourcePath!)/libimobiledevice/bin/comptest", arguments: [id], timeout: 15) {
                            let w = watchInfo.components(separatedBy: .newlines)
                            if let watchID = w.filter({ $0.contains("Checking watch") }).first?.components(separatedBy: " ").last,
                               let watchName = w.filter({ $0.contains("DeviceName") }).first?.components(separatedBy: ": ").last,
                               let watchModel = w.filter({ $0.contains("ProductType") }).first?.components(separatedBy: ": ").last,
                               let watchLevel = w.filter({ $0.contains("BatteryCurrentCapacity") }).first?.components(separatedBy: ": ").last,
                               let watchLevelValue = Int(watchLevel),
                               let watchCharging = w.filter({ $0.contains("BatteryIsCharging") }).first?.components(separatedBy: ": ").last,
                               let watchIsCharging = Bool(watchCharging) {
                                AirBatteryModel.updateDevice(Device(deviceID: watchID, deviceType: "Watch", deviceName: watchName, deviceModel: watchModel, batteryLevel: watchLevelValue, isCharging: watchIsCharging ? 1 : 0, parentName: deviceName, lastUpdate: lastUpdate, iconSymbol: DeviceSymbols.symbol(modelCode: watchModel)))
                            }
                        }
                    }
                }
            }
        }
    }
}

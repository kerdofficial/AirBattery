//
//  AirBatteryModel.swift
//  AirBattery
//
//  Created by apple on 2024/2/9.
//

import Foundation
import os

let dataLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.kerdofficial.AirBattery", category: "data")

struct btdDevice: Codable, Equatable {
    let time: Date
    let vid: String
    let pid: String
    let type: String
    let mac: String
    let name: String
    let level: Int
}

struct Device: Hashable, Codable {
    var hasBattery: Bool = true
    var deviceID: String
    var deviceType: String
    var deviceName: String
    var deviceModel: String?
    var batteryLevel: Int
    var isCharging: Int
    var isCharged: Bool = false
    var isPaused: Bool = false
    var acPowered: Bool = false
    var isHidden: Bool = false
    var lowPower: Bool = false
    var parentName: String = ""
    var lastUpdate: Double
    var realUpdate: Double = 0.0
    var iconSymbol: String?
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(hasBattery)
        hasher.combine(deviceID)
        hasher.combine(deviceType)
        hasher.combine(deviceName)
        hasher.combine(deviceModel)
        hasher.combine(batteryLevel)
        hasher.combine(isCharging)
        hasher.combine(isCharged)
        hasher.combine(isPaused)
        hasher.combine(acPowered)
        hasher.combine(isHidden)
        hasher.combine(lowPower)
        hasher.combine(lastUpdate)
        hasher.combine(realUpdate)
        hasher.combine(parentName)
        hasher.combine(iconSymbol)
    }
}

class AirBatteryModel {
    private static let devicesLock = NSLock()
    private static var _devices: [Device] = []
    static var Devices: [Device] {
        get { devicesLock.lock(); defer { devicesLock.unlock() }; return _devices }
        set { devicesLock.lock(); defer { devicesLock.unlock() }; _devices = newValue }
    }
    static let machineType = ud.string(forKey: "machineType") ?? "Mac"
    static let key = "com.kerdofficial.AirBattery.widget"
    
    static func updateDevice(_ device: Device) {
        //let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        //if blockedItems.contains(device.deviceName) { return }
        devicesLock.lock(); defer { devicesLock.unlock() }
        //self.Devices.removeAll(where: {blockedItems.contains($0.deviceName)})
        if let index = _devices.firstIndex(where: { $0.deviceName == device.deviceName }) {
            _devices[index] = device
        } else {
            _devices.append(device)
        }
    }
    
    static func hideDevice(_ name: String) {
        devicesLock.lock(); defer { devicesLock.unlock() }
        for index in _devices.indices {
            if _devices[index].deviceName == name {
                _devices[index].isHidden = true
            }
        }
    }
    
    static func removeDevice(_ name: String) {
        devicesLock.lock(); defer { devicesLock.unlock() }
        _devices.removeAll { $0.deviceName == name }
    }
    
    static func unhideDevice(_ name: String) {
        devicesLock.lock(); defer { devicesLock.unlock() }
        for index in _devices.indices {
            if _devices[index].deviceName == name {
                _devices[index].isHidden = false
            }
        }
    }
    
    static func getBlackList() -> [Device] {
        let blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
        let devices = getAll(noFilter: true)
        return devices.filter({ blackList.contains($0.deviceName) })
    }
    
    static func getAll(reverse: Bool = false, noFilter: Bool = false) -> [Device] {
        let thisMac = ud.string(forKey: "deviceName")
        let disappearTime = (ud.object(forKey: "disappearTime") ?? 20) as! Int
        let blackList = (ud.object(forKey: "blackList") ?? []) as! [String]
        let now = Double(Date().timeIntervalSince1970)
        let neverMergeTws = ud.bool(forKey: "neverMergeTws")
        let snapshot = Devices
        var list = (reverse ? Array(snapshot.reversed()) : snapshot).filter { (disappearTime == -1 || now - $0.lastUpdate < Double(disappearTime * 60)) && !(neverMergeTws && $0.deviceType == "ap_pod_all") }
        if !noFilter { list = list.filter { !blackList.contains($0.deviceName) && !$0.isHidden } }
        var newList: [Device] = list.filter({ $0.parentName == thisMac })
        for d in list {
            if d.parentName == "" && d.parentName != thisMac {
                newList.append(d)
                for sd in list.filter({ $0.parentName == d.deviceName }) {
                    newList.append(sd)
                }
            }
        }
        for dd in list.filter({ !newList.contains($0) }) { newList.append(dd) }
        let visible = newList.filter({ !checkIfBlocked(name: $0.deviceName) })
        return sortGroups(visible, order: ud.string(forKey: "deviceSortOrder") ?? "default", thisMac: thisMac, reverse: reverse)
    }
    
    static func sortGroups(_ list: [Device], order: String, thisMac: String?, reverse: Bool = false) -> [Device] {
        guard order != "default" else { return list }
        let (roots, members) = groupByRoot(list, thisMac: thisMac)
        let manualIndex = Dictionary(manualOrder.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        let indexed = roots.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            switch order {
            case "levelAsc", "levelDesc":
                if x.hasBattery != y.hasBattery { return x.hasBattery }
                if x.batteryLevel != y.batteryLevel { return order == "levelAsc" ? x.batteryLevel < y.batteryLevel : x.batteryLevel > y.batteryLevel }
            case "manual":
                let (i, j) = (manualIndex[x.deviceName] ?? Int.max, manualIndex[y.deviceName] ?? Int.max)
                if i != j { return i < j }
            default:
                let result = x.deviceName.localizedCaseInsensitiveCompare(y.deviceName)
                if result != .orderedSame { return result == .orderedAscending }
            }
            return a.offset < b.offset
        }
        var sortedRoots = indexed.map { $0.element }
        if reverse { sortedRoots.reverse() }
        let rootNames = Set(sortedRoots.map { $0.deviceName })
        let orphans = members.filter { !rootNames.contains($0.key) }.values.flatMap { $0 }
        return sortedRoots.flatMap { [$0] + (members[$0.deviceName] ?? []) } + orphans
    }
    
    private static func groupByRoot(_ list: [Device], thisMac: String?) -> (roots: [Device], members: [String: [Device]]) {
        let byName = Dictionary(list.map { ($0.deviceName, $0) }, uniquingKeysWith: { first, _ in first })
        func rootName(_ device: Device) -> String {
            var current = device
            var seen: Set<String> = [device.deviceName]
            while current.parentName != "", current.parentName != thisMac, let parent = byName[current.parentName], seen.insert(parent.deviceName).inserted {
                current = parent
            }
            return current.deviceName
        }
        var roots: [Device] = []
        var members: [String: [Device]] = [:]
        for device in list {
            let root = rootName(device)
            if root == device.deviceName { roots.append(device) } else { members[root, default: []].append(device) }
        }
        return (roots, members)
    }
    
    static var manualOrder: [String] { ud.stringArray(forKey: "manualDeviceOrder") ?? [] }
    
    static func rootDevices(order: String? = nil) -> [Device] {
        let thisMac = ud.string(forKey: "deviceName")
        var list = getAll()
        if let order { list = sortGroups(list, order: order, thisMac: thisMac) }
        return groupByRoot(list, thisMac: thisMac).roots
    }
    
    static func saveManualOrder(_ visible: [String]) {
        ud.set(visible + manualOrder.filter { !visible.contains($0) }, forKey: "manualDeviceOrder")
    }
    
    static func getByName(_ name: String) -> Device? {
        for d in getAll(noFilter: true) { if d.deviceName == name { return d } }
        return nil
    }
    
    static func getByID(_ id: String) -> Device? {
        for d in getAll(noFilter: true) { if d.deviceID == id { return d } }
        return nil
    }
    
    static func singleDeviceName() -> String {
        var url: URL
        let bundleIdentifier = Bundle.main.bundleIdentifier
        if bundleIdentifier == key {
            url = fd.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("singleDeviceName")
            let devicename = try? String(contentsOf: url, encoding: .utf8)
            return devicename ?? ""
        } else {
            url = fd.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Containers/\(key)/Data/Documents/singleDeviceName")
            do {
                try ud.string(forKey: "deviceOnWidget")?.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                dataLog.error("Write singleDeviceName failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        return ""
    }
    
    static func getJsonURL() -> URL {
        var url: URL
        let bundleIdentifier = Bundle.main.bundleIdentifier
        if bundleIdentifier == key {
            url = fd.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("data.json")
        } else {
            url = fd.urls(for: .libraryDirectory, in: .userDomainMask).first!.appendingPathComponent("Containers/\(key)/Data/Documents/data.json")
        }
        return url
    }
    
    @discardableResult
    static func writeData() -> [Device] {
        //let showMac = ud.object(forKey: "showMacOnWidget") as? Bool ?? true
        let revList = ud.object(forKey: "revListOnWidget") as? Bool ?? false
        
        var devices = getAll(reverse: revList)
        let ibStatus = InternalBattery.status
        if ibStatus.hasBattery { devices.insert(ib2ab(ibStatus), at: 0) }
        do {
            let jsonData = try JSONEncoder().encode(devices)
            try jsonData.write(to: getJsonURL())
        } catch {
            dataLog.error("Write data.json failed: \(error.localizedDescription, privacy: .public)")
        }
        return devices
    }
    
    static func readData(url: URL = getJsonURL()) -> [Device]{
        do {
            let jsonData = try Data(contentsOf: url)
            let list = try JSONDecoder().decode([Device].self, from: jsonData)
            return list
        } catch {
            dataLog.error("Read \(url.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        return []
    }
    
    static func ncGetAll(url: URL, fromWidget: Bool = false) -> [Device] {
        let disappearTime = (ud.object(forKey: "disappearTime") ?? 20) as! Int
        let devices = readData(url: url)
        let now = Double(Date().timeIntervalSince1970)
        var localDevices = getAll().map({ $0.deviceName })
        if fromWidget { localDevices = readData().map({ $0.deviceName }) }
        var list = devices.filter{ disappearTime == -1 || now - $0.lastUpdate < Double(disappearTime * 60) }.filter({!localDevices.contains($0.deviceName)})
        if let first = devices.first { if !list.contains(first) && list.count != 0 { list.insert(first, at: 0) }}
        if let first = list.first { if list.count == 1 && !first.hasBattery { return [] }}
        return list
    }
    
    static func baseDeviceName(_ name: String) -> String {
        for suffix in [" (Case)".local, " (Case)", " 🄻🅁", " 🄻", " 🅁"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        return name
    }
    
    static func checkIfBlocked(name: String) -> Bool {
        let whitelistMode = ud.bool(forKey: "whitelistMode")
        let blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]()
        let listed = blockedItems.contains(name) || blockedItems.contains(baseDeviceName(name))
        return listed != whitelistMode
    }
}

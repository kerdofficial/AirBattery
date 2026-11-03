//
//  DebugLog.swift
//  AirBattery
//

import Foundation
import CryptoKit
import os
import Darwin
import SystemConfiguration

enum LogCategory: String {
    case app, settings, model, widget, ble, bluetooth, magic, hid, accessory, idevice, power, logReader, process, nearcast, alerts, updates, crash
}

struct LogMessage: ExpressibleByStringInterpolation {
    struct StringInterpolation: StringInterpolationProtocol {
        var text = ""

        init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity)
        }

        mutating func appendLiteral(_ literal: String) {
            text += literal
        }

        mutating func appendInterpolation<T: BinaryInteger>(_ value: T) {
            text += String(value)
        }

        mutating func appendInterpolation<T: BinaryFloatingPoint>(_ value: T) {
            text += String(describing: Double(value))
        }

        mutating func appendInterpolation(_ value: Bool) {
            text += value ? "true" : "false"
        }

        mutating func appendInterpolation<T: RawRepresentable>(_ value: T) where T.RawValue == String {
            text += value.rawValue
        }

        mutating func appendInterpolation(_ value: String) {
            text += "<redacted>"
        }

        mutating func appendInterpolation(public value: String) {
            text += value
        }

        mutating func appendInterpolation(device name: String) {
            text += DebugLog.pseudonym(device: name)
        }

        mutating func appendInterpolation(id value: String) {
            text += DebugLog.pseudonym(id: value)
        }

        mutating func appendInterpolation(error: Error) {
            let nsError = error as NSError
            text += "\(nsError.domain) \(nsError.code): \(DebugLog.scrub(nsError.localizedDescription))"
        }
    }

    let text: String

    init(stringLiteral value: String) {
        text = value
    }

    init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }
}

enum DebugLog {
    private static let enabled = Bundle.main.bundleIdentifier == "com.kerdofficial.AirBattery"
    private static let queue = DispatchQueue(label: "com.kerdofficial.AirBattery.debugLog", qos: .utility)
    private static let queueKey = DispatchSpecificKey<Bool>()
    private static let configureQueue: Void = queue.setSpecific(key: queueKey, value: true)
    private static let identityLock = NSRecursiveLock()
    private static var salt: SymmetricKey?
    private static var codes: [String: String] = [:]
    private static let clearLock = NSLock()
    private static var pendingClears = 0
    private static var buffer = Data()
    private static var repeats: [String: (windowStart: Date, suppressed: Int)] = [:]
    private static var timer: DispatchSourceTimer?
    private static var observer: NSObjectProtocol?
    private static var pendingSettings: DispatchWorkItem?
    private static var snapshot: [String: String] = [:]
    private static var sections: [(String, () -> [LogMessage])] = []
    private static var sessionStart: Date?
    private static var loggers: [String: Logger] = [:]
    private static let limit = 5 * 1024 * 1024
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    static func info(_ category: LogCategory, _ message: @autoclosure () -> LogMessage) {
        guard enabled else { return }
        enqueue("INFO", category, message())
    }

    static func warning(_ category: LogCategory, _ message: @autoclosure () -> LogMessage) {
        guard enabled else { return }
        enqueue("WARN", category, message())
    }

    static func error(_ category: LogCategory, _ message: @autoclosure () -> LogMessage) {
        guard enabled else { return }
        enqueue("ERROR", category, message())
    }

    static func verbose(_ category: LogCategory, _ message: @autoclosure () -> LogMessage) {
        guard isVerbose else { return }
        enqueue("DEBUG", category, message())
    }

    static var isVerbose: Bool {
        get { enabled && UserDefaults.standard.bool(forKey: "verboseLogging") }
        set {
            guard enabled else { return }
            UserDefaults.standard.set(newValue, forKey: "verboseLogging")
        }
    }

    // Lifecycle and export callers must not hold the device model lock while waiting here.
    private static func sync<T>(_ work: () throws -> T) rethrows -> T {
        _ = configureQueue
        if DispatchQueue.getSpecific(key: queueKey) == true { return try work() }
        return try queue.sync(execute: work)
    }

    private static func code(_ value: String) -> String {
        identityLock.lock()
        defer { identityLock.unlock() }
        if let cached = codes[value] { return cached }
        if salt == nil {
            let defaults = UserDefaults.standard
            if let data = defaults.data(forKey: "debugLogSalt"), data.count == 32 {
                salt = SymmetricKey(data: data)
            } else {
                let key = SymmetricKey(size: .bits256)
                defaults.set(key.withUnsafeBytes { Data($0) }, forKey: "debugLogSalt")
                salt = key
            }
        }
        guard let key = salt else { return "redacted" }
        let digest = HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: key)
        let result = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        codes[value] = result
        return result
    }

    static func pseudonym(device name: String) -> String {
        guard enabled else { return "Device-redacted" }
        let rawType = AirBatteryModel.Devices.first { $0.deviceName == name }?.deviceType ?? "Device"
        return pseudonym(device: name, type: rawType)
    }

    private static func pseudonym(device name: String, type: String) -> String {
        "\(deviceType(type))-\(code(name))"
    }

    private static func deviceType(_ raw: String) -> String {
        switch raw {
        case "ap_case": return "AirPodsCase"
        case "ap_pod_left", "ap_pod_right", "ap_pod_all": return "AirPods"
        case "MMouse": return "Mouse"
        case "ApplePencil": return "Pencil"
        case "Headset": return "Headphones"
        case "MacBook", "MacBookAir", "MacBookPro", "iMac", "Macmini", "MacPro", "MacStudio",
             "mac", "applevirtualmachine1", "macbook", "macbookair", "macbookpro", "macbookneo",
             "macmini", "macstudio", "macpro", "imac", "imacpro": return "Mac"
        default:
            let clean = raw.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            return clean.isEmpty ? "Device" : clean
        }
    }

    static func pseudonym(id value: String) -> String {
        guard enabled else { return "id-redacted" }
        return "id-\(code(value))"
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static let protected = regex(#"<(?:redacted|email|ip|user|this-mac|id)>|\b[A-Za-z][A-Za-z0-9]*-[0-9a-f]{6}\b"#)
    private static let identifiers = regex(#"(?i)(?<![a-z0-9])(?:[0-9a-f]{2}(?::[0-9a-f]{2}){5}|[0-9a-f]{2}(?:-[0-9a-f]{2}){5}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[0-9a-f]{8}-[0-9a-f]{16,17}|(?:0x)?[0-9a-f]{16,})(?![a-z0-9])"#)
    private static let email = regex(#"[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+"#)
    private static let ipv4 = regex(#"(?<![\w.])(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![\w.])"#)
    private static let ipv6 = regex(#"(?i)(?<![a-z0-9:])[0-9a-f:.]*:[0-9a-f:.]*:[0-9a-f:.]*(?:%[a-z0-9_.-]+)?"#)
    private static let localUserNames = [NSUserName(), NSFullUserName()].filter { !$0.isEmpty }
    private static let computerName = SCDynamicStoreCopyComputerName(nil, nil) as String?
    private static let literalLock = NSLock()
    private static var lastLiterals: [String: String] = [:]
    private static var literalRegex: NSRegularExpression?
    private static var literalExpiry = Date.distantPast
    private static let homePath = regex(#"/Users/[^/\s]+"#)

    // Placeholders keep replacement text and existing pseudonyms out of later passes.
    static func scrub(_ input: String) -> String {
        guard enabled else { return "<redacted>" }
        var result = input
        var replacements: [String] = []
        func protect(_ value: String) -> String {
            replacements.append(value)
            return "\u{E000}\(replacements.count - 1)\u{E001}"
        }
        func replace(_ expression: NSRegularExpression?, _ transform: (String) -> String?) {
            guard let expression = expression else { return }
            let original = result
            for match in expression.matches(in: original, range: NSRange(original.startIndex..., in: original)).reversed() {
                guard let range = Range(match.range, in: original), let value = transform(String(original[range])),
                      let currentRange = Range(match.range, in: result) else { continue }
                result.replaceSubrange(currentRange, with: protect(value))
            }
        }
        replace(protected) { value in
            if value.hasPrefix("<") { return value }
            identityLock.lock()
            defer { identityLock.unlock() }
            return codes.values.contains(String(value.suffix(6))) ? value : nil
        }
        replace(homePath) { _ in "~" }
        replace(email) { _ in "<email>" }
        literalLock.lock()
        if Date() >= literalExpiry {
            var literals: [String: String] = [:]
            let defaults = UserDefaults.standard
            for name in localUserNames { literals[name] = "<user>" }
            for name in [computerName, defaults.string(forKey: "deviceName")].compactMap({ $0 }) where !name.isEmpty {
                literals[name] = "<this-mac>"
            }
            if let group = defaults.string(forKey: "ncGroupID"), !group.isEmpty {
                literals[group] = "<redacted>"
                literals[String(group.prefix(15))] = "<redacted>"
            }
            let devices = AirBatteryModel.Devices
            for device in devices where !device.deviceName.isEmpty {
                literals[device.deviceName] = pseudonym(device: device.deviceName, type: device.deviceType)
            }
            let names = literals.keys.sorted { $0.count > $1.count }
            let pattern = names.map { name -> String in
                let escaped = NSRegularExpression.escapedPattern(for: name)
                return localUserNames.contains(name) ? "(?<![\\p{L}\\p{N}_])" + escaped + "(?![\\p{L}\\p{N}_])" : escaped
            }.joined(separator: "|")
            literalRegex = pattern.isEmpty ? nil : regex(pattern)
            lastLiterals = literals
            literalExpiry = Date().addingTimeInterval(5)
        }
        let literals = lastLiterals
        let expression = literalRegex
        literalLock.unlock()
        replace(expression) { literals[$0] }
        replace(ipv6) { value in
            let address = String(value.split(separator: "%", maxSplits: 1)[0])
            var bytes = in6_addr()
            return address.withCString { inet_pton(AF_INET6, $0, &bytes) } == 1 ? "<ip>" : nil
        }
        replace(identifiers) { pseudonym(id: $0) }
        replace(ipv4) { _ in "<ip>" }
        for (index, value) in replacements.enumerated() {
            result = result.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: value)
        }
        return result
    }

    private static func enqueue(_ level: String, _ category: LogCategory, _ message: LogMessage) {
        let date = Date()
        queue.async { append(level, category, message.text, at: date, suppressRepeats: level != "DEBUG" && category != .crash) }
    }

    private static func append(_ level: String, _ category: LogCategory, _ text: String, at date: Date = Date(), suppressRepeats: Bool = false, suffix: String = "") {
        let scrubbed = scrub(text).replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
        // Bound a single entry so even oversized process output cannot exceed a rotation file.
        var safe = scrubbed.count > 16000 ? String(scrubbed.prefix(16000)) + " [truncated]" : scrubbed
        if suppressRepeats {
            let key = "\(level)\n\(category.rawValue)\n\(scrubbed)"
            if let previous = repeats[key] {
                if date.timeIntervalSince(previous.windowStart) < 600 {
                    repeats[key]?.suppressed += 1
                    return
                }
                if previous.suppressed > 0 {
                    safe += " (repeated \(previous.suppressed) more times in the previous 10 min)"
                }
            }
            repeats[key] = (date, 0)
            if repeats.count > 512 {
                repeats = repeats.filter { date.timeIntervalSince($0.value.windowStart) <= 600 }
                if repeats.count > 512, let oldest = repeats.min(by: { $0.value.windowStart < $1.value.windowStart })?.key {
                    repeats.removeValue(forKey: oldest)
                }
            }
        }
        let line = "\(formatter.string(from: date)) \(level.padding(toLength: 5, withPad: " ", startingAt: 0)) [\(category.rawValue)] \(safe)\(suffix)"
        let logger = loggers[category.rawValue] ?? Logger(subsystem: "com.kerdofficial.AirBattery", category: category.rawValue)
        loggers[category.rawValue] = logger
        switch level {
        case "ERROR": logger.error("\(line, privacy: .public)")
        case "WARN": logger.warning("\(line, privacy: .public)")
        case "DEBUG": logger.debug("\(line, privacy: .public)")
        default: logger.info("\(line, privacy: .public)")
        }
        buffer.append(contentsOf: (line + "\n").utf8)
        if buffer.count > 64 * 1024 { flush() }
        if !buffer.isEmpty && timer == nil {
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 2)
            source.setEventHandler { flush() }
            timer = source
            source.resume()
        }
    }

    private static func file(_ index: Int) -> URL {
        logDirectory.appendingPathComponent(index == 0 ? "AirBattery.log" : "AirBattery.\(index).log")
    }

    private static func flush(durable: Bool = false) {
        timer?.cancel()
        timer = nil
        guard !buffer.isEmpty || durable else { return }
        defer { buffer.removeAll(keepingCapacity: true) }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            var size = (try? file(0).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            var offset = buffer.startIndex
            while offset < buffer.endIndex {
                let available = max(0, limit - size)
                let end: Data.Index
                if buffer.endIndex - offset <= available {
                    end = buffer.endIndex
                } else if available > 0,
                          let newline = buffer[offset..<offset + available].lastIndex(of: 10) {
                    end = newline + 1
                } else if size == 0 {
                    end = buffer[offset...].firstIndex(of: 10).map { $0 + 1 } ?? buffer.endIndex
                } else {
                    end = offset
                }
                if end > offset {
                    if !fm.fileExists(atPath: file(0).path) { try Data().write(to: file(0)) }
                    let handle = try FileHandle(forWritingTo: file(0))
                    do {
                        try handle.seekToEnd()
                        try handle.write(contentsOf: buffer[offset..<end])
                        if durable { try handle.synchronize() }
                        try handle.close()
                    } catch {
                        try? handle.close()
                        throw error
                    }
                    size += end - offset
                    offset = end
                }
                if offset < buffer.endIndex {
                    if fm.fileExists(atPath: file(4).path) { try fm.removeItem(at: file(4)) }
                    for index in stride(from: 3, through: 0, by: -1) where fm.fileExists(atPath: file(index).path) {
                        try fm.moveItem(at: file(index), to: file(index + 1))
                    }
                    size = 0
                }
            }
            if durable && buffer.isEmpty && fm.fileExists(atPath: file(0).path) {
                let handle = try FileHandle(forWritingTo: file(0))
                defer { try? handle.close() }
                try handle.synchronize()
            }
        } catch {
            // A full or unwritable disk must not cause unbounded memory growth.
        }
    }

    private static let valueKeys = "showOn machineType nearCast launchAtLogin intBattOnStatusBar batteryPercent readBTHID hideLevel disappearTime whitelistMode iosBatteryStyle updateInterval widgetInterval carouselMode revListOnWidget deviceSortOrder ideviceOverBLE readBTDevice readBLEDevice readPencil readIDevice readLogitech twsMerge neverMergeTws appearance showThisMac colorfulBattery showDebug verboseLogging test_debug SUEnableAutomaticChecks SUAutomaticallyUpdate".split(separator: " ").map(String.init)
    private static let privateKeys = "deviceName ncGroupID deviceOnWidget blackList blockedDevices pinnedList alertList manualDeviceOrder neverRemindMe logReaderLastTS".split(separator: " ").map(String.init)

    private static func settings() -> [String: String] {
        let defaults = UserDefaults.standard
        var values: [String: String] = [:]
        for key in valueKeys {
            let value = defaults.object(forKey: key)
            if let number = value as? NSNumber { values[key] = number.stringValue }
            else if let text = value as? String { values[key] = text }
            else { values[key] = value == nil ? "unset" : "set" }
        }
        for key in privateKeys {
            let value = defaults.object(forKey: key)
            if let array = value as? [Any] { values[key] = "\(array.count) items" }
            else if let data = value as? Data, let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
                values[key] = "\(array.count) items"
            } else if let text = value as? String { values[key] = text.isEmpty ? "unset" : "set" }
            else { values[key] = value == nil ? "unset" : "set" }
        }
        return values
    }

    private static func settingsLines(_ values: [String: String]) -> [String] {
        values.keys.sorted().map { "\($0): \(values[$0] ?? "unset")" }
    }

    private static func header() -> [String] {
        let bundle = Bundle.main
        var size = 0
        var model = "unknown"
        if sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 {
            var bytes = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &bytes, &size, nil, 0) == 0 { model = String(cString: bytes) }
        }
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return ["AirBattery \(bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown") (\(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"))",
                "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)", "Hardware: \(model)",
                "Architecture: \(architecture)", "Locale: \(Locale.current.identifier)", "Verbose: \(isVerbose)"]
    }

    private struct Marker: Codable { let start: Date; let clean: Bool }
    private static var markerURL: URL { logDirectory.appendingPathComponent("session.json") }

    private static func writeMarker(clean: Bool) {
        guard let start = sessionStart, let data = try? JSONEncoder().encode(Marker(start: start, clean: clean)) else { return }
        try? data.write(to: markerURL, options: .atomic)
    }

    static func startSession() {
        guard enabled else { return }
        queue.async {
            guard sessionStart == nil else { return }
            try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let previous = (try? Data(contentsOf: markerURL)).flatMap { try? JSONDecoder().decode(Marker.self, from: $0) }
            sessionStart = Date()
            writeMarker(clean: false)
            NSSetUncaughtExceptionHandler { exception in
                DebugLog.sync {
                    DebugLog.append("ERROR", .crash, "Uncaught exception: \(exception.name.rawValue): \(exception.reason ?? "unknown")")
                    for symbol in exception.callStackSymbols { DebugLog.append("ERROR", .crash, symbol) }
                    DebugLog.flush(durable: true)
                }
            }
            header().forEach { append("INFO", .app, $0) }
            snapshot = settings()
            settingsLines(snapshot).forEach { append("INFO", .settings, $0) }
            if let previous = previous, !previous.clean {
                append("WARN", .crash, "Previous session ended unexpectedly")
                importCrash(after: previous.start)
            }
            observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
                queue.async {
                    pendingSettings?.cancel()
                    let item = DispatchWorkItem {
                        let current = settings()
                        for key in current.keys.sorted() where current[key] != snapshot[key] {
                            append("INFO", .settings, "\(key): \(snapshot[key] ?? "unset") -> \(current[key] ?? "unset")")
                        }
                        snapshot = current
                    }
                    pendingSettings = item
                    queue.asyncAfter(deadline: .now() + 1, execute: item)
                }
            }
        }
    }

    private static func importCrash(after start: Date) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let newest = urls.filter { $0.lastPathComponent.hasPrefix("AirBattery-") && $0.pathExtension == "ips" }
            .compactMap { url -> (URL, Date)? in
                guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, date > start else { return nil }
                return (url, date)
            }.max { $0.1 < $1.1 }?.0
        guard let url = newest, let data = try? Data(contentsOf: url), let newline = data.firstIndex(of: 10) else { return }
        let header = (try? JSONSerialization.jsonObject(with: Data(data[..<newline]))) as? [String: Any]
        guard let body = (try? JSONSerialization.jsonObject(with: Data(data[data.index(after: newline)...]))) as? [String: Any] else { return }
        func scalar(_ value: Any?) -> String? {
            if let text = value as? String { return text }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        if let version = scalar(header?["app_version"]) { append("ERROR", .crash, "App version: \(version)") }
        for (section, keys) in [("exception", ["type", "signal", "codes"]), ("termination", ["reason", "indicator"])] {
            guard let values = body[section] as? [String: Any] else { continue }
            for key in keys {
                if let value = scalar(values[key]) { append("ERROR", .crash, "\(section).\(key): \(value)") }
            }
        }
        guard let threads = body["threads"] as? [[String: Any]], let index = body["faultingThread"] as? Int,
              threads.indices.contains(index), let frames = threads[index]["frames"] as? [[String: Any]] else { return }
        let images = body["usedImages"] as? [[String: Any]] ?? []
        for frame in frames.prefix(30) {
            let imageIndex = frame["imageIndex"] as? Int ?? -1
            let image = images.indices.contains(imageIndex) ? scalar(images[imageIndex]["name"]) ?? "unknown" : "unknown"
            append("ERROR", .crash, "\(image) \(scalar(frame["symbol"]) ?? "unknown") + \(scalar(frame["symbolLocation"]) ?? "unknown")")
        }
    }

    static func endSession() {
        guard enabled else { return }
        sync {
            pendingSettings?.cancel()
            pendingSettings = nil
            if let token = observer { NotificationCenter.default.removeObserver(token) }
            observer = nil
            for (key, entry) in repeats where entry.suppressed > 0 {
                let parts = key.split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
                if parts.count == 3, let category = LogCategory(rawValue: String(parts[1])) {
                    append(String(parts[0]), category, String(parts[2]), suffix: " (repeated \(entry.suppressed) more times in the previous 10 min)")
                }
            }
            repeats.removeAll()
            append("INFO", .app, "Session ended")
            writeMarker(clean: true)
            flush(durable: true)
            sessionStart = nil
            NSSetUncaughtExceptionHandler(nil)
        }
    }

    static func registerExportSection(_ title: String, _ lines: @escaping () -> [LogMessage]) {
        guard enabled else { return }
        queue.async { sections.append((title, lines)) }
    }

    static func exportDiagnostics(to url: URL) throws {
        guard enabled else { return }
        try sync {
            flush()
            var lines = ["AirBattery Diagnostics", "Exported: \(formatter.string(from: Date()))"] + header() + ["", "Settings"] + settingsLines(settings()) + ["", "Devices"]
            let now = Date().timeIntervalSince1970
            for device in AirBatteryModel.Devices {
                let parent = device.parentName.isEmpty ? "none" : pseudonym(device: device.parentName)
                lines.append("\(pseudonym(device: device.deviceName)) type=\(device.deviceType) model=\(device.deviceModel ?? "unknown") level=\(device.batteryLevel) charging=\(device.isCharging) charged=\(device.isCharged) paused=\(device.isPaused) acPowered=\(device.acPowered) hasBattery=\(device.hasBattery) ageSeconds=\(Int(max(0, now - device.lastUpdate))) parent=\(parent)")
            }
            for (title, section) in sections { lines += ["", title] + section().map { $0.text } }
            for index in stride(from: 4, through: 0, by: -1) {
                if FileManager.default.fileExists(atPath: file(index).path) {
                    lines += ["", file(index).lastPathComponent, try String(contentsOf: file(index), encoding: .utf8)]
                }
            }
            try (lines.map { scrub($0) }.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func clearLogs() {
        guard enabled else { return }
        clearLock.lock()
        pendingClears += 1
        clearLock.unlock()
        queue.async {
            defer {
                clearLock.lock()
                pendingClears -= 1
                clearLock.unlock()
            }
            buffer.removeAll(keepingCapacity: true)
            repeats.removeAll()
            timer?.cancel()
            timer = nil
            for index in 0...4 where FileManager.default.fileExists(atPath: file(index).path) {
                try? FileManager.default.removeItem(at: file(index))
            }
        }
    }

    static var logDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/AirBattery", isDirectory: true)
    }

    static var totalLogSize: Int {
        guard enabled else { return 0 }
        clearLock.lock()
        let clearing = pendingClears > 0
        clearLock.unlock()
        guard !clearing else { return 0 }
        return (0...4).reduce(0) { $0 + ((try? file($1).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }
}

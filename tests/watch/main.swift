import Foundation

let complete = "Checking watch watch-one\nDeviceName: Test: Watch\nProductType: Watch7,1\nBatteryCurrentCapacity: 42\nBatteryIsCharging: true\n"
func parse(_ text: String) -> [Device] {
    IDeviceBattery.parseWatches(text, parentName: "Test Phone", lastUpdate: Date().timeIntervalSince1970)
}
assert(parse(complete).first?.deviceName == "Test: Watch")
assert(parse(complete).first?.deviceID == "watch-one")
for field in ["DeviceName: Test: Watch\n", "BatteryCurrentCapacity: 42\n", "BatteryIsCharging: true\n"] {
    assert(parse(complete.replacingOccurrences(of: field, with: "")).isEmpty)
}
for level in ["-1", "101", "unknown"] {
    assert(parse(complete.replacingOccurrences(of: "42", with: level)).isEmpty)
}
assert(parse(complete.replacingOccurrences(of: "true", with: "unknown")).isEmpty)
assert(parse(complete.replacingOccurrences(of: "42", with: "0")).first?.batteryLevel == 0)
assert(parse(complete.replacingOccurrences(of: "42", with: "100")).first?.batteryLevel == 100)
let incomplete = "Checking watch missing-fields\nDeviceName: Incomplete\n"
assert(parse(incomplete + complete).count == 1)
assert(parse(complete + complete.replacingOccurrences(of: "watch-one", with: "watch-two")).count == 2)
assert(parse("Waiting for phone...\nConnected!\nRetrieving list of watches...").isEmpty)

if CommandLine.arguments.count > 1 {
    watchOutput = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
} else { watchOutput = complete }
IDeviceBattery.shared.writeBatteryInfo("test-phone", "-n")
let watches = AirBatteryModel.getAll().filter { $0.deviceType == "Watch" }
assert(!watches.isEmpty, "Helper output did not reach the model")
let watch = watches[0]
assert(watch.parentName == "Test Phone" && (0...100).contains(watch.batteryLevel))
let container = AirBatteryModel.getJsonURL().deletingLastPathComponent()
try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
AirBatteryModel.writeData()
let decoded = AirBatteryModel.readData()
assert(decoded.contains(watch), "Watch lost in data.json round trip")
ud.set(1, forKey: "disappearTime")
AirBatteryModel.Devices = [Device(deviceID: "old", deviceType: "Watch", deviceName: "Old", batteryLevel: 42, isCharging: 0, lastUpdate: Date().timeIntervalSince1970 - 120)]
assert(AirBatteryModel.getAll().isEmpty, "Unreachable watch did not age out")
ud.removePersistentDomain(forName: testSuite)
print("PASS: parser, source to model, isolated widget data.json round trip, age-out")

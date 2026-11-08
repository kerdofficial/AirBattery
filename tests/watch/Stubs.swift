import Foundation

let testSuite = "AirBattery.watch-tests.\(UUID().uuidString)"
let ud = UserDefaults(suiteName: testSuite)!
let fd = TestFileManager()
class TestFileManager: FileManager, @unchecked Sendable {
    let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WATCH_TEST_ROOT"]!)
    override func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] { [root] }
}
extension String {
    var local: String { self }
}
extension String.StringInterpolation {
    mutating func appendInterpolation(device value: String) { appendLiteral("<device>") }
    mutating func appendInterpolation(id value: String) { appendLiteral("<id>") }
    mutating func appendInterpolation(error value: Error) { appendLiteral("<error>") }
}
enum Category { case idevice, model, widget }
enum DebugLog {
    static func verbose(_ category: Category, _ message: String) {}
    static func info(_ category: Category, _ message: String) {}
    static func warning(_ category: Category, _ message: String) {}
    static func error(_ category: Category, _ message: String) { fatalError(message) }
}
func debugScanStart(_ category: Category) -> Date? { nil }
enum DeviceSymbols { static func symbol(modelCode: String) -> String? { nil } }
struct BatteryStatus { var hasBattery = false }
enum InternalBattery { static let status = BatteryStatus() }
func ib2ab(_ status: BatteryStatus) -> Device { fatalError("No internal battery in tests") }
var watchOutput = ""
func process(path: String, arguments: [String], timeout: Int = 0) -> String? {
    switch URL(fileURLWithPath: path).lastPathComponent {
    case "ideviceinfo":
        return arguments.contains("-q") ? "BatteryCurrentCapacity: 70\nBatteryIsCharging: false" : "DeviceName: Test Phone\nProductType: iPhone15,2\nDeviceClass: iPhone"
    case "comptest": return watchOutput
    default: fatalError("Unexpected tool")
    }
}

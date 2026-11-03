//
//  SettingsView.swift
//  AirBattery
//
//  Created by apple on 2023/9/7.
//

import SwiftUI
import ServiceManagement
import WidgetKit

private enum SettingsPane: String, CaseIterable {
    case general = "General"
    case display = "Display"
    case nearbility = "Nearbility"
    case nearcast = "Nearcast"
    case widget = "Widget"
    case blocklist = "Blocklist"
    case debug = "Debug"

    var title: LocalizedStringKey {
        switch self {
        case .display: "Menu Bar & Dock"
        default: LocalizedStringKey(rawValue)
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .display: "dock"
        case .nearbility: "nearbility"
        case .nearcast: "nearcast"
        case .widget: "widget"
        case .blocklist: "blacklist"
        case .debug: "debug"
        }
    }
}

struct SettingsView: View {
    @State private var selectedItem: String? = SettingsPane.general.rawValue
    @AppStorage("showDebug") var showDebug: Bool = false

    private var panes: [SettingsPane] {
        SettingsPane.allCases.filter { $0 != .debug || showDebug }
    }

    private var current: SettingsPane {
        selectedItem.flatMap(SettingsPane.init(rawValue:)) ?? .general
    }

    var body: some View {
        NavigationSplitView {
            List(panes, id: \.rawValue, selection: $selectedItem) { pane in
                Label(pane.title, image: pane.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(220)
            .removingSidebarToggle()
        } detail: {
            detail
                .navigationTitle(current.title)
                .toolbar { ToolbarItem { Color.clear.frame(width: 0, height: 0) } }
        }
        .frame(minWidth: 820, idealWidth: 820, minHeight: 620, idealHeight: 620)
        .background(WindowConfigurator { $0.toolbarStyle = .unified })
    }

    @ViewBuilder
    private var detail: some View {
        switch current {
        case .general: GeneralView()
        case .display: DisplayView()
        case .nearbility: NearbilityView()
        case .nearcast: NearcastView()
        case .widget: WidgetView()
        case .blocklist: BlacklistView()
        case .debug: DebugView(selectedItem: $selectedItem)
        }
    }
}

private extension View {
    @ViewBuilder
    func removingSidebarToggle() -> some View {
        if #available(macOS 14, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}

struct GeneralView: View {
    @AppStorage("showOn") var showOn = "sbar"
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("showDebug") var showDebug: Bool = false
    @State private var debugCount: Int = 0
    @State private var cltInstalled: Bool = false
    
    var body: some View {
        SForm {
            SGroupBox(label: "Startup") {
                SToggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        SMLoginItemSetEnabled("com.kerdofficial.AirBatteryHelper" as CFString, newValue)
                    }
                SPicker("Show AirBattery", selection: $showOn) {
                    Text("Dock").tag("dock")
                    Text("Menu Bar").tag("sbar")
                    Text("Both").tag("both")
                    Text("None").tag("none")
                }.onChange(of: showOn) { newValue in
                    switch newValue {
                    case "sbar":
                        statusBarItem.isVisible = true
                        for i in pinnedItems { i.isVisible = true }
                        NSApp.setActivationPolicy(.accessory)
                    case "both":
                        statusBarItem.isVisible = true
                        for i in pinnedItems { i.isVisible = true }
                        NSApp.setActivationPolicy(.regular)
                    case "dock":
                        statusBarItem.isVisible = false
                        for i in pinnedItems { i.isVisible = false }
                        NSApp.setActivationPolicy(.regular)
                    default:
                        statusBarItem.isVisible = false
                        for i in pinnedItems { i.isVisible = false }
                        NSApp.setActivationPolicy(.accessory)
                    }
                    if newValue == "dock" || newValue == "both" {
                        _ = createAlert(title: "AirBattery Tips".local, message: "Displaying AirBattery on the Dock will consume more power, it is better to use Menu Bar mode or Widgets.".local, button1: "OK").runModal()
                    }
                }
            }
            SGroupBox {
                SButton("Command Line Tool", buttonTitle: cltInstalled ? "Uninstall" : "Install",
                        tips: "After installation, you can run \"airbattery\" in your terminal to list all devices.") {
                    if cltInstalled {
                        CommandLineTool.uninstall { updateCTL() }
                    } else {
                        CommandLineTool.install { updateCTL() }
                    }
                }.onAppear { cltInstalled = CommandLineTool.isInstalled() }
            }
            SGroupBox(label: "Update") {
                UpdaterSettingsView(updater: updaterController.updater)
                HStack {
                    CheckForUpdatesView(updater: updaterController.updater)
                    Spacer()
                    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("AirBattery v\(appVersion)")
                            .foregroundStyle(.secondary)
                            .onTapGesture {
                                debugCount += 1
                                if debugCount > 9 {
                                    debugCount = 0
                                    showDebug.toggle()
                                }
                            }
                    }
                }
            }
        }
    }
    func updateCTL() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            cltInstalled = CommandLineTool.isInstalled()
        }
    }
}

struct NearbilityView: View {
    @AppStorage("ideviceOverBLE") var ideviceOverBLE = false
    @AppStorage("readBTDevice") var readBTDevice = true
    @AppStorage("readBLEDevice") var readBLEDevice = false
    @AppStorage("readPencil") var readPencil = false
    @AppStorage("readIDevice") var readIDevice = true
    @AppStorage("readBTHID") var readBTHID = true
    @AppStorage("readLogitech") var readLogitech = true
    @AppStorage("updateInterval") var updateInterval = 1
    @AppStorage("twsMerge") var twsMerge = 5
    
    var body: some View {
        SForm {
            SGroupBox(label: "Scanner", footer: "If a device is missing, try \"Discover more BT devices\" or \"Discover more BLE devices\".") {
                SToggle("Discover iOS devices via Network", isOn: $readIDevice, tips: "iPhone, iPad, Apple Watch and Vision Pro on your local network.")
                SToggle("Discover iOS devices via Bluetooth", isOn: $ideviceOverBLE, tips: "Nearby iPhone and cellular iPad over Bluetooth.")
                SToggle("Discover BT and BLE devices", isOn: $readBTDevice, tips: "Mice, keyboards, headphones and other Bluetooth peripherals.")
                SToggle("Discover Logitech receiver devices", isOn: $readLogitech, tips: "Logitech mice, keyboards and headsets on Lightspeed, Unifying or Bolt receivers.")
                SToggle("Discover more BT devices", isOn: $readBTHID, tips: "More third-party Bluetooth devices. Updates when they reconnect or the Mac wakes.")
                SToggle("Discover more BLE devices", isOn: $readBLEDevice, tips: "Any Bluetooth device AirBattery can find. Beta, may cause unexpected errors.")
                    .foregroundColor(.orange)
                    .onChange(of: readBLEDevice) { newValue in
                        if newValue {
                            _ = createAlert(title: "AirBattery Tips".local, message: "If you see a bluetooth pairing request from any device that isn't yours, add it to your blocklist!".local, button1: "OK").runModal()
                        }
                    }
                SToggle("Apple Pencil from your iPad", isOn: $readPencil, tips: "Through your iPad. First discovery can take 10+ minutes. Beta, may drain your iPad faster.")
                    .foregroundColor(.orange)
            }
            SGroupBox(label: "Others") {
                VStack(alignment: .leading, spacing: 4) {
                    SSteper("Refresh Interval (min)", value: $updateInterval, min: 1, max: 99)
                    if updateDelay != updateInterval {
                        Text("Relaunch AirBattery to apply this change")
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }
                SSteper("Earbud Merging Threshold", value: $twsMerge, min: 1, max: 99, tips: "Show earbuds as one device when their levels differ by less than this.")
            }
        }
    }
}

struct NearcastView: View {
    @AppStorage("nearCast") var nearCast = false
    @AppStorage("ncGroupID") var ncGroupID = ""
    @State var debug: Bool = false
    
    var body: some View {
        SForm {
            Section {
                SToggle("Enable Nearcast", isOn: $nearCast)
                    .onChange(of: nearCast) { newValue in
                        if newValue {
                            if ncGroupID != "" && isGroudIDValid(id: ncGroupID) {
                                netcastService.resume()
                            } else {
                                DispatchQueue.main.async { nearCast = false; ncGroupID = "" }
                                _ = createAlert(
                                    title: "Invalid group ID".local,
                                    message: "Please create or enter a valid Group ID before use!",
                                    button1: "OK".local
                                ).runModal()
                            }
                        } else {
                            netcastService.stop()
                        }
                    }
                LabeledContent("Group ID") {
                    HStack(spacing: 8) {
                        TextField("Group ID", text: $ncGroupID)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .disabled(nearCast)
                        Button(action: {
                            ncGroupID = "nc-" + randomString(length: 20)
                        }, label: {
                            Image(systemName: ncGroupID != "" ? "arrow.clockwise.circle" : "plus.circle")
                        })
                        .buttonStyle(.borderless)
                        .disabled(nearCast)
                        Button(action: {
                            if ncGroupID != "" && isGroudIDValid(id: ncGroupID) {
                                copyToClipboard(ncGroupID)
                                _ = createAlert(title: "Group ID Copied".local,
                                                message: String(format: "Group ID has been copied to the clipboard.".local, ncGroupID),
                                                button1: "OK".local).runModal()
                            } else {
                                DispatchQueue.main.async { ncGroupID = "" }
                                _ = createAlert(
                                    title: "Invalid group ID".local,
                                    message: "Please create or enter a valid Group ID before use!",
                                    button1: "OK".local
                                ).runModal()
                            }
                        }, label: {
                            Image("list.clipboard.fill.circle")
                                .resizable().scaledToFit()
                                .frame(width: 15, height: 15)
                        }).buttonStyle(.borderless)
                    }
                }
            } header: {
                Text("Nearcast")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nearcast will broadcast your battery data within the local network.")
                    Text("Your data has been encrypted using the group id, don't share it with others.")
                }
            }
            SGroupBox(label: "Peer Info") {
                LabeledContent("Local ID") {
                    Text(netcastService.transceiver.localPeerId ?? "")
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct DisplayView: View {
    @AppStorage("appearance") var appearance = "auto"
    @AppStorage("showThisMac") var showThisMac = "icon"
    @AppStorage("carouselMode") var carouselMode = true
    @AppStorage("colorfulBattery") var colorfulBattery = false
    @AppStorage("iosBatteryStyle") var iosBatteryStyle = false
    @AppStorage("intBattOnStatusBar") var intBattOnStatusBar = true
    @AppStorage("batteryPercent") var batteryPercent = "outside"
    @AppStorage("hideLevel") var hideLevel = 90
    @AppStorage("disappearTime") var disappearTime = 20
    @State private var levelList = [95, 90, 80, 70, 60, 50, 40, 30, 20, 10]
    
    var body: some View {
        SForm {
            SGroupBox(label: "Menu Bar") {
                SToggle("Dynamic Battery Icon", isOn: $intBattOnStatusBar)
                SToggle("Colorful Battery Icon", isOn: $colorfulBattery)
                    .disabled(!intBattOnStatusBar)
                SPicker("Battery Icon Style", selection: $iosBatteryStyle) {
                    Text("macOS").tag(false)
                    Text("iOS").tag(true)
                }.disabled(!intBattOnStatusBar)
                SPicker("Show Percentage", selection: $batteryPercent) {
                    Text("Hidden").tag("hide")
                    Text("Inside").tag("inside")
                    Text("Outside").tag("outside")
                }.disabled(!intBattOnStatusBar)
                SPicker("Remove Offline Device", selection: $disappearTime) {
                    Text("Never").tag(-1)
                    Text("after 20min").tag(20)
                    Text("after 40min").tag(40)
                    Text("after 60min").tag(60)
                }
                SPicker("Hide percentage when above", selection: $hideLevel) {
                    Text("Never").tag(100)
                    ForEach(levelList, id: \.self) { number in
                        Text("\(number)%").tag(number)
                    }
                    if !levelList.contains(hideLevel) && hideLevel != 100 {
                        Text("\(hideLevel)%").tag(hideLevel)
                    }
                }.disabled(!intBattOnStatusBar || (batteryPercent == "hide"))
            }
            SGroupBox(label: "Dock") {
                    SPicker("Appearance", selection: $appearance) {
                        Text("Automatic").tag("auto")
                        Text("Light").tag("false")
                        Text("Dark").tag("true")
                    }.pickerStyle(.segmented)
                    SPicker("Built-in Battery Style", selection: $showThisMac, tips: "Show or hide this Mac's built-in battery in the Dock icon") {
                        Text("Hidden").tag("hidden")
                        Text("Device Icon").tag("icon")
                        Text("Percent").tag("percent")
                    }
                    SToggle("Carousel Mode", isOn: $carouselMode, tips: "Cycle through all found devices in the Dock icon")
            }
        }
    }
}

struct WidgetView: View {
    //@AppStorage("showMacOnWidget") var showMacOnWidget = true
    @AppStorage("revListOnWidget") var revListOnWidget = false
    @AppStorage("deviceOnWidget") var deviceOnWidget = ""
    @AppStorage("widgetInterval") var widgetInterval = 0
    @AppStorage("deviceName") var deviceName = "Mac"
    
    @State var ib = getMacDeviceType().lowercased().contains("book")
    @State var devices = [String]()

    var body: some View {
        SForm {
            SGroupBox(label: "Widget") {
                SToggle("Reverse Device List", isOn: $revListOnWidget)
                SPicker("Refresh Interval", selection: $widgetInterval) {
                    Text("System Default").tag(-1)
                    Text("Same as Nearbility").tag(0)
                }
                if #unavailable(macOS 14) {
                    SPicker("Single Device Widget", selection: $deviceOnWidget) {
                        Text("Not Set").tag("")
                        if ib { Text(deviceName).tag(deviceName) }
                        ForEach(devices, id: \.self) { device in
                            Text(device).tag(device)
                        }
                        if !devices.contains(deviceOnWidget) && deviceOnWidget != deviceName && deviceOnWidget != "" {
                            Text(deviceOnWidget).tag(deviceOnWidget)
                        }
                    }.onChange(of: deviceOnWidget) { _ in _ = AirBatteryModel.singleDeviceName() }
                }
                SButton("Reload All Widgets", buttonTitle: "Reload") {
                    AirBatteryModel.writeData()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }
        }
        .onAppear { devices = AirBatteryModel.getAll(noFilter: true).filter({ $0.hasBattery }).map({ $0.deviceName }) }
        .onReceive(dockTimer) { _ in
            if #unavailable(macOS 14) {
                devices = AirBatteryModel.getAll(noFilter: true).filter({ $0.hasBattery }).map({ $0.deviceName })
            }
        }
    }
}

struct BlacklistView: View {
    @AppStorage("whitelistMode") var whitelistMode = false
    @State private var blockedItems = [String]()
    @State private var temp = ""
    @State private var showSheet = false
    
    var body: some View {
        SForm {
            Section {
                SToggle("Allowlist Mode", isOn: $whitelistMode)
            } header: {
                Text("Blocklist")
            } footer: {
                Text(whitelistMode ? "Only the following devices will be showed" : "The following devices will be ignored")
            }
            Section {
                ForEach(blockedItems, id: \.self) { item in
                    HStack {
                        Text(item)
                        Spacer()
                        Button {
                            blockedItems.removeAll { $0 == item }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Remove")
                    }
                }
                Button {
                    showSheet = true
                } label: {
                    Label("Add to List", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
        }
        .sheet(isPresented: $showSheet) {
            VStack {
                TextField("Enter Device Name".local, text: $temp).frame(width: 300)
                HStack(spacing: 20) {
                    Button {
                        if temp == "" { return }
                        if !blockedItems.contains(temp) { blockedItems.append(temp) }
                        temp = ""
                        showSheet = false
                    } label: {
                        Text("Add to List").frame(width: 80)
                    }.keyboardShortcut(.defaultAction)
                    Button {
                        showSheet = false
                    } label: {
                        Text("Cancel").frame(width: 80)
                    }
                }.padding(.top, 10)
            }.padding()
        }
        .onAppear { blockedItems = (ud.object(forKey: "blockedDevices") as? [String]) ?? [String]() }
        .onChange(of: blockedItems) { b in ud.setValue(b, forKey: "blockedDevices") }
    }
}

struct DebugView: View {
    @AppStorage("test_debug") var test_debug = false
    @AppStorage("test_hasib") var test_hasib = false
    @AppStorage("test_acpower") var test_ac = false
    @AppStorage("test_full") var test_full = false
    @AppStorage("test_iblevel") var test_iblevel = 100
    @AppStorage("showDebug") var showDebug: Bool = false
    
    @State private var deviceID: String = ""
    @State private var deviceType: String = ""
    @State private var deviceName: String = ""
    @State private var deviceModel: String = ""
    @State private var parentName: String = ""
    @State private var batteryLevel: Int = 0
    @State private var lowPower: Bool = false
    @State private var isCharging: Bool = false
    @State private var fullCharged: Bool = false
    @State private var isPresented: Bool = false
    
    @Binding var selectedItem: String?
    
    var body: some View {
        SForm {
            SGroupBox {
                SToggle("Debug Mode", isOn: $test_debug)
                SButton("Data Folder", buttonTitle: "Open") {
                    NSWorkspace.shared.open(ncFolder.deletingLastPathComponent())
                }
            }
            SGroupBox(label: "Built-in Battery") {
                SToggle("Built-in Battery", isOn: $test_hasib)
                SToggle("AC Powered", isOn: $test_ac)
                SToggle("Paused", isOn: $test_full)
                SSteper("Level", value: $test_iblevel, min: 1)
            }
            SGroupBox(label: "Remote Battery") {
                LabeledContent("Create Item") {
                    Button(action: {
                        isPresented = true
                    }, label: {
                        Image(systemName: "plus.circle.fill")
                    })
                    .buttonStyle(.borderless)
                    .sheet(isPresented: $isPresented) {
                        VStack(spacing: 0) {
                            SForm {
                              SGroupBox(label: "Remote Battery") {
                                SField("Device ID", text: $deviceID)
                                SField("Device Name", text: $deviceName)
                                SField("Device Type", text: $deviceType)
                                SField("Device Model", text: $deviceModel)
                                HStack {
                                    SField("Parent Name", text: $parentName)
                                    Button(action: {
                                        parentName = getMacDeviceName()
                                    }, label: {
                                        let ib = ib2ab(InternalBattery.status)
                                        Image(getDeviceIcon(ib))
                                            .resizable().scaledToFit()
                                            .frame(width: 16, height: 16)
                                    }).buttonStyle(.borderless)
                                }
                                SSteper("Level", value: $batteryLevel)
                                SToggle("Charging", isOn: $isCharging)
                                SToggle("Paused", isOn: $fullCharged)
                                SToggle("Low Power", isOn: $lowPower)
                              }
                            }
                            HStack {
                                Spacer()
                                Button(action: {
                                    isPresented = false
                                }, label: {
                                    Text("Cancle").frame(width: 50)
                                })
                                Button(action: {
                                    let device = Device(deviceID: deviceID, deviceType: deviceType, deviceName: deviceName, batteryLevel: batteryLevel, isCharging: isCharging ? 1 : (fullCharged ? 5 : 0), lowPower: lowPower, parentName: parentName,lastUpdate: Date().timeIntervalSince1970)
                                    AirBatteryModel.updateDevice(device)
                                    isPresented = false
                                }, label: {
                                    Text("Add").frame(width: 50)
                                }).keyboardShortcut(.defaultAction)
                            }
                        }
                        .frame(width: 420, height: 440)
                        .onAppear {
                            deviceID = randomString(length: 10)
                            deviceType = "virtual"
                            deviceName = "Virtual Device"
                            deviceModel = ""
                            parentName = ""
                            batteryLevel = 100
                            lowPower = false
                            isCharging = false
                            fullCharged = false
                        }
                    }
                }
            }
            Section {
                Button("Hide Debug Menu", action: {
                    test_debug = false
                    showDebug = false
                    selectedItem = "General"
                })
            }
        }
    }
}

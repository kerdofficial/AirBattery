# AirBattery

AirBattery is a macOS app that collects the battery level of the Mac and nearby devices (AirPods and Beats, Bluetooth and BLE peripherals, Logitech receiver devices and headsets, iPhone, iPad, Apple Watch, Apple Pencil, other Macs over Nearcast) and shows them in the menu bar, the Dock, pinned menu bar items, desktop widgets and a command line tool. This repository is the `kerdofficial` fork of `lihaoyun6/AirBattery`; it builds and signs its own app (`com.kerdofficial.AirBattery`) with its own Sparkle feed.

## What we never compromise on

### 1. Honest battery state

A level is shown only when a source actually reported it. Every `Device` carries `lastUpdate`; stale devices are marked and then dropped by `AirBatteryModel.getAll()` instead of being kept alive with old numbers. Levels stay within 0-100, and charging is shown only when the source reports it. A device that is off or unreachable ages out; never fill in a guessed value.

### 2. One data path, every surface

Every battery source writes through `AirBatteryModel.updateDevice(_:)`. The menu bar popover, Dock view and pinned items read `AirBatteryModel.getAll()`; widgets and the `abt` CLI read the JSON that `AirBatteryModel.writeData()` writes into the widget container. A new source or field that skips this path is missing on some surface, which is a bug.

### 3. Bounded background work

Sources run on their own queues and timers and must never block the main thread. HID requests have short timeouts, external tools run through `process(path:arguments:timeout:)`, and widget data is refreshed by one app-level timer in `AppDelegate`. Do not add a second periodic timer for work an existing tick already does, and release HID devices, observers and processes on every exit path.

### 4. Old systems keep working

The minimum is macOS 13.0 for every target. APIs from newer systems (Liquid Glass, widget rendering modes) go behind `#available` with the previous behavior kept for older systems. The project stays in Swift 5 language mode.

## How we work

Prefer ambitious ideas and simple systems. Do not preserve complexity just because it exists, and do not add machinery because it looks impressive. Find the real constraint, then build the smallest model that makes the correct behavior unsurprising. Channel both "measure twice, cut once" and "yagni".

Treat this document as good defaults, not hard rules. The developer's instructions override it. If a rule here fights the task in front of you, say so and get a human sign-off before breaking it.

## A small glossary

- **you** means the agent reading this file and changing AirBattery.
- **maintainers** means the people building this fork.
- **source** means one battery reader in `AirBattery/BatteryInfo/` (for example `MagicBattery`, `BLEBattery`, `LogitechBattery`, `IDeviceBattery`).
- **Nearbility** means the local discovery engine made of all sources; **Nearcast** means sharing device lists with other Macs on the LAN (`AirBattery/Supports/Multipeer.swift`).
- **widget container** means `~/Library/Containers/com.kerdofficial.AirBattery.widget/Data/Documents`, where the app writes `data.json` for the sandboxed widget.

## The three ways to hurt yourself

1. **Killing by pattern.** Never `pkill -f`, `pgrep | kill`, or kill a PID found by matching a name or path. The maintainer's installed AirBattery, your own agent and other processes share those strings. Kill only a PID you captured at spawn, or quit an app you launched by its exact path.
2. **Touching the maintainer's live app and data.** `/Applications/AirBattery.app` is in daily use. Debug builds share its preferences domain (`com.kerdofficial.AirBattery`) and its widget container, so running one changes real settings and widget data. Ask before quitting, replacing or reconfiguring the installed app, and never change settings values while testing unless asked.
3. **Publishing by accident.** `appcast.xml` on `main` is the live Sparkle update feed for installed copies, and `scripts/build-release.sh` submits to Apple notarization. Edit the feed, run notarization, push tags or create releases only when asked. Signing keys and the Sparkle private key live in the maintainer's keychain and key files; never commit, print or copy them. Logitech code only reads battery and identity features; never send HID++ writes to real devices.

## Hit every surface

Before calling a change done, walk this list and say which entries applied:

- **Device model.** `AirBattery/BatteryInfo/AirBatteryModel.swift` (`Device`, `updateDevice`, `getAll`, `writeData`). Fields added here must survive the JSON round trip to the widget and CLI.
- **Sources.** `AirBattery/BatteryInfo/`; start-up in `AirBattery/Supports/AirBatteryApp.swift`, periodic refresh in `AppDelegate.refreshWidgetData()`, and an on/off toggle in `NearbilityView` (`AirBattery/ViewModel/SettingsView.swift`).
- **Device icons.** `getDeviceIcon` in `AirBattery/Supports/Supports.swift` and `AirBattery/Assets.xcassets/Device Icon/`. Use the existing type strings (`Mouse`, `Keyboard`, `Headphones`, ...).
- **Menu bar and Dock.** Popover and Dock window in `AirBattery/ViewModel/ContentView.swift`, battery glyphs in `AirBattery/ViewModel/BatteryView.swift`, pinned items in `AirBattery/Supports/AirBatteryApp.swift`.
- **Widgets.** `widget/*.swift`; shared helpers in `widget/widgetBundle.swift`. Check full color and dimmed (vibrant/accented) rendering.
- **CLI and scripting.** `abt/main.swift` (reads `data.json`), `AirBattery/Supports/AppleScript.swift` and `AirBattery/Supports/Scriptable.sdef`.
- **Settings UI.** Panes in `AirBattery/ViewModel/SettingsView.swift`, row components in `AirBattery/Supports/GroupForm.swift`.
- **Localization.** English text is the key; add every new user-visible string to `AirBattery/zh-Hans.lproj/Localizable.strings` and `AirBattery/zh-Hant.lproj/Localizable.strings` and run `plutil -lint` on both.
- **Reverse states.** A device that appears must also age out; HID connect needs removal handling; pin needs unpin; hide needs unhide; a source toggle turned off must stop its work.
- **Debug log.** New failures and state changes get a `DebugLog` line (see "Debug logging"); verbose detail goes through `DebugLog.verbose`.
- **Docs.** Update `README.md`, `TROUBLESHOOTING.md` and this file when behavior they describe changes.

## Debug logging

`AirBattery/Supports/DebugLog.swift` is the only logging path; do not add `print`, `NSLog` or `os.Logger` calls. It writes anonymized text to `~/Library/Logs/AirBattery/` (5 MB rotation, 4 old files), only in the app; in the widget and `abt` it does nothing. Users export it from the hidden Developer pane (Option-click the Settings button in the popover) and may send it to us, so nothing identifying may reach it:

- `LogMessage` interpolation is private by default: a plain `String` becomes `<redacted>`. Use `\(device:)` for device, computer and peer names, `\(id:)` for MACs, UUIDs, UDIDs and peer IDs, `\(error:)` for errors, and `\(public:)` only for values that cannot identify anyone (model codes, device types, tool names, settings values).
- Never log raw tool output (`ideviceinfo`, `system_profiler`, `log show`), raw BLE payloads, file paths or any part of `ncGroupID`. A scrubber is the safety net, not the rule.
- Basic level is always on: keep it to state changes and failures, and log repeating failures on transition, not on every tick. Anything per scan or per update is `DebugLog.verbose`, which costs one Bool check when off.
- Never call `DebugLog` while holding `AirBatteryModel`'s device lock; pseudonyms read the device list.

## Development

- Xcode 27 or newer; `AirBattery.xcodeproj` has the schemes `AirBattery`, `AirBatteryWidgetExtension`, `AirBatteryHelper` and `abt`. Swift packages (Sparkle, MultipeerKit, swift-argument-parser) are pinned in `AirBattery.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.
- Compile check without touching signing: `xcodebuild -project AirBattery.xcodeproj -scheme AirBattery -configuration Debug -derivedDataPath <temp dir> CODE_SIGNING_ALLOWED=NO build`. Use a temp derived data path; after a package version change, delete its `Build` folder to avoid stale module errors.
- Signed, notarized release build: `scripts/build-release.sh` with `ASC_KEY_PATH`, `ASC_KEY_ID` and `ASC_ISSUER_ID` set; it also checks the team and hardened runtime of every Mach-O file. Output goes to `build/` (ignored). `scripts/publish-release.sh` ships it (see Releasing).
- Ad-hoc signed builds cannot write into the widget container and fail Sparkle library validation from `/Applications`; widget behavior can only be checked with a properly signed build.
- After replacing the installed app, an already running `AirBatteryWidgetExtension` process keeps serving the old code (data still updates, code changes do not). Check `ps` for extension processes started before the install or running from a derived data path, and stop those exact PIDs. Delete `Build/Products` of temporary derived data folders after compile checks so their extensions cannot be picked up.
- `scripts/build-watch-helper.sh` rebuilds the universal `comptest` from its tracked C source using the bundled libraries and external libimobiledevice 1.4.0 / libplist 2.7.0 headers (`IMOBILEDEVICE_SOURCE`, `PLIST_SOURCE`). It does not sign, notarize or install the app.
- `AirBattery/libimobiledevice/` holds prebuilt universal binaries and dylibs copied into the app as resources. Rebuild them from source outside the repo, keep `@executable_path/../lib/` install names and `-mmacosx-version-min` at or below the app minimum. `scripts/build-release.sh` signs them for notarization.
- Never deploy, publish packages, push tags, or create releases unless asked.

## Releasing

- Bump `MARKETING_VERSION` (SemVer) and `CURRENT_PROJECT_VERSION` in the app and widget targets, and in `abt` if it sets them. The build number must increase, because Sparkle compares it, not the marketing version.
- Write `release-notes/<version>.md`: user-facing, English, used for both the GitHub release and the appcast item.
- Run `scripts/build-release.sh`, then `scripts/publish-release.sh <version> --dry-run`, then `scripts/publish-release.sh <version>`. The script signs the zip for Sparkle, adds the item to `appcast.xml` and creates the GitHub release with the zip.
- The appcast goes live only when the commit containing `appcast.xml` reaches `main`, so merge it after the release asset exists.
- Releasing needs the maintainer's go; never run these scripts on your own.

## Verifying

- Apple Watch regression checks: `scripts/test-watch.sh` compiles the production source and model against isolated tool, preference and filesystem adapters. With `IMOBILEDEVICE_SOURCE` (1.4.0) and `PLIST_SOURCE` (2.7.0) set, it also tests the C helper under AddressSanitizer. Smallest compile proof: build every scheme your change touches (`AirBattery` and `AirBatteryWidgetExtension` for shared files such as `AirBatteryModel.swift` and `Supports.swift`), plus `plutil -lint` for changed `.strings` files.
- UI changes: run the app and capture the affected window with `screencapture -l <window id>`; compare against the native macOS look in both light and dark appearance when relevant.
- Source changes: confirm the device reaches `data.json` in the widget container, not only the popover.
- Wait for observable events or persisted state. Do not use arbitrary sleeps; keep bounded timeouts as failure guards.
- Real hardware results (Logitech devices, AirPods, iPhones) are reported separately from build checks. Never claim them without evidence.

## Pull requests

- Never open a PR unless the developer asks. PRs target `main` of `kerdofficial/AirBattery`; `gh pr create` defaults to the upstream parent, so always pass `--repo kerdofficial/AirBattery`.
- Commit titles follow conventional commits with an optional scope, for example `feat(hid): read battery of Logitech receiver devices`.
- Body: the problem in a sentence or two, then how you fixed it.
- One concern per PR. If the description says "also", split it.
- Implementation never authorizes merging, publishing releases, or deploying.

## How it works

`AppDelegate` (`AirBattery/Supports/AirBatteryApp.swift`) starts every enabled source at launch. Sources discover devices through CoreBluetooth, IOBluetooth and the IORegistry, `log show` parsing (`AirBattery/Supports/logReader.sh`), IOHIDManager for Logitech receivers and headsets, and the bundled libimobiledevice tools for iOS devices; each calls `AirBatteryModel.updateDevice`. The model keeps devices in memory, filtered by blocklist, hidden state and age.

One app-level timer refreshes the periodic sources, writes `data.json` into the widget container and asks WidgetKit to reload timelines; widget timelines also refresh on their own every few minutes. The widget extension is sandboxed without an app group, so the unsandboxed app writes into its container directly. Nearcast exchanges device lists with other Macs through MultipeerKit and stores them under the widget container as well.

## Where code lives

- `AirBattery/BatteryInfo` - device model and battery sources.
- `AirBattery/ViewModel` - SwiftUI views: popover, Dock view, settings, alerts.
- `AirBattery/Supports` - app delegate, shared helpers, settings components, Sparkle and AppleScript glue.
- `AirBattery/libimobiledevice` - bundled iOS device tools.
- `widget` - WidgetKit extension.
- `AirBatteryHelper` - legacy login item helper.
- `abt` - `airbattery` command line tool.
- `scripts` - release build script.

## Taste

- Prefer inferred local types and optional binding; do not add new force casts or force unwraps where the existing code is defensive.
- Comments explain non-obvious constraints only. Files with code ported from other projects keep their license notice in the header.
- Add a dependency only for a responsibility that is actually implemented.
- Shared code compiled into the widget (`AirBatteryModel.swift`, `Supports.swift`, `InternalBattery.swift`) must stay free of app-only APIs.

## Interface

- Native SwiftUI and AppKit controls, restrained and spacious, keyboard usable with visible focus. No pure black or white surfaces or primary text of our own; system backgrounds are fine.
- Settings rows use the components in `AirBattery/Supports/GroupForm.swift`: title with a short description below, control on the trailing side.
- macOS 26+ styling (glass, concentric corner radii) goes behind `#available`; older systems keep their previous look.
- Status uses an icon or label, not color alone. Animate only transform and opacity, and avoid continuous decorative animation.
- Copy states only verified behavior and does not name specific products when a general description works.

## Language and documentation

- Write all tracked content in English, including documentation, comments, error messages and commit messages. Chinese text lives only in the zh-Hans and zh-Hant `.lproj` files.
- Do not use emojis, em dashes, or en dashes in code or documentation. Use ordinary hyphens.
- Keep guidance focused on capabilities and commands that exist.

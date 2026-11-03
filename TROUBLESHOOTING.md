# Troubleshooting

## My iPhone or iPad does not show up

Make sure the device trusts this Mac. While AirBattery is running, connect it to the Mac with a cable at least once so the two can pair. After that, the device only needs to be on the same network as the Mac.

Check that **Discover iOS devices via network** is on in **Settings > Nearbility**.

## My iPhone is not on Wi-Fi

Turn on **Discover iOS devices via Bluetooth** in **Settings > Nearbility** and keep Bluetooth on on the device. This works for iPhone and cellular iPad only.

## Does my Apple Watch need to be connected?

No. When AirBattery finds the paired iPhone over the network or USB, it also reads the battery of the Apple Watch paired with it. An iPhone found only over Bluetooth cannot report its watch.

## Why does a device name start with ⚠︎?

The device has not reported a new battery level for more than 10 minutes. It may be off, asleep or out of range. Devices that stay silent are removed after the time set in **Settings > Menu Bar & Dock > Remove offline devices**.

## My Logitech mouse or keyboard disappears

Logitech devices answer only while they are awake. A sleeping device drops out of the list and comes back on its own once you use it again. Check that **Discover Logitech receiver devices** is on in **Settings > Nearbility** and that the receiver is plugged in.

## My AirPods show as one device

AirBattery merges the left and right earbud into one entry when their levels are close. Turn on **Always show earbuds separately** in **Settings > Nearbility**, or adjust **Earbud merging threshold**.

## My widget is not up to date

Widgets refresh every few minutes and whenever a battery level changes, but macOS limits how often a widget may redraw. Open the menu bar popover to see the latest values.

## Why does AirBattery need Bluetooth permission?

AirBattery reads the battery information that Bluetooth devices broadcast, so it needs Bluetooth access to receive those packets.

## Sending diagnostics

AirBattery keeps a local log that helps track down problems.

1. Option-click the Settings button in the menu bar popover.
2. Open **Developer**, the last item in the sidebar.
3. If the problem is hard to catch, turn on **Verbose logging**, reproduce the problem, then turn it off again. Verbose logging can increase CPU usage.
4. Click **Export Diagnostics...** and attach the file to your issue.

The log never leaves your Mac on its own. Device names, hardware and network addresses, identifiers and your user name are replaced with anonymous codes before anything is written, and raw device details such as serial numbers are never logged. **Device Codes** in the same pane shows which code belongs to which of your devices, so you can tell us which device has the problem.
